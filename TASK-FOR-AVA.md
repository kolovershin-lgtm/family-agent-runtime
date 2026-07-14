# TASK-FOR-AVA — достроить family-agent-runtime на VPS Андрея

**Клиент:** Андрей Ахметов, VPS 95.179.243.18 (Vultr Frankfurt, Ubuntu 24.04, 3.8GB RAM).
**Исполнитель:** AVA (агент Андрея).
**Ревьюер:** Boss (Илья). PR → ревью → мерж в `main`.
**Приоритет:** **стабильность важнее скорости**. Время не лимит.
**Общий deadline:** нет. Каждая веха — самостоятельная и обратимая.

---

## Цель

Три задачи одновременно:

1. **Стабильность:** превратить установку Андрея (AVA + Оля + Ева) из ручной и хрупкой
   в самодиагностирующуюся и восстановимую. Ошибки — видимы, действия — обратимы.
2. **Автономность AVA:** снять с Boss'а «последнюю милю» — root-шаги при построении
   нового агента, отладке инфраструктуры, ротации логов, откате изменений.
3. **Андрей как оркестратор:** упростить интерфейс до «AVA сделай X» — а система
   выполняет через `sudo`-whitelist, без пересылок Boss'у через Андрея.

---

## Что уже есть на VPS Андрея (не переделывать)

- Три пользователя-агента: `claudegw` (uid 1001, AVA), `olyagw` (1002, Оля), `mariannagw` (1003, Ева).
- Три БД gbrain: `gbrain`, `gbrain_olya`, `gbrain_marianna` (изолированы токенами + iptables UID).
- 12 сервисов gbrain/gateway — все active.
- iptables 3×3 (6 REJECT-правил) сохранены в `/etc/iptables/rules.v4`.
- Одна утилита мониторинга: `/usr/local/bin/vps_capacity_alarm.sh` (RAM/disk 85%, cron 30мин).
- Один GitHub-репо у AVA: `Android1872/andrei-vault` (workspace + eva-setup).
- Vault Андрея (в gbrain): 4 подкаталога, есть runbook про Hermes-trener, `github-repo-andrei.md`.
- Vault Оли и Марианны — **пустые** (ритуал письма ещё не заведён).

## Чего не хватает (в порядке приоритета — от самого критичного)

### P0 — Пакетный root (снимает возврат к Boss'у по каждой мелочи)

**Задача 0: install.sh + family-runtime-update + sudoers whitelist.**

Ключевая инвестиция. Без неё каждая последующая P0/P1/P4 задача упирается в мой root-заход. С ней — Boss делает root один раз (install.sh), дальше AVA автономна через `sudo family-runtime-update` до подписанных тегов.

- Дописать `install.SKELETON.sh` (см. 8 TODO-блоков в файле).
- Дописать `scripts/family-runtime-update.SKELETON.sh` (см. 6 TODO-блоков в файле).
- Верификация тега — вариант C для старта (сравнение sha с `gh api ... /refs/tags/<tag>`). Позже — на GPG.
- Проверить весь флоу локально в docker/lxc-контейнере: install → создать fake-агента → update до v0.0.2 → rollback.
- **Приёмка:** Boss на VPS Андрея делает `sudo ./install.sh --orchestrator-user claudegw --apply` — после этого AVA может `sudo family-runtime-update --dry-run` и `sudo system-health` без пароля, ни к одной другой sudo-команде доступа нет.
- **Deliverable:** PR + тесты + описание того, что произойдёт при `install.sh` (contract Boss читает и валидирует до запуска).

Только после мержа P0-0 → всё остальное.

### P1 — Тихие сбои становятся громкими

**Задача 1: миграция swarm-канала + миграция ingest_worker.**

Две миграции в одной ветке (`feature/P1-1-schema-catchup`):

**(a) swarm require_ack** — уже готов файл `migrations/2026-06-25-swarm-require-ack.sql`.
- До применения: `\d delivery_outbox` — 11 колонок. После: 13.
- Verify: тест `swarm.notify` от AVA к Boss'у (то что раньше 500'ило) возвращает `ok=true`.

**(b) ingest_worker retry columns** — написать новую миграцию `migrations/2026-07-14-ingest-worker-retry.sql`:
- Добавить в `embedding_jobs` колонки: `attempts int not null default 0`, `max_attempts int not null default 3`, `error_message text`, `next_retry_at timestamptz`.
- Индекс `idx_embedding_jobs_next_retry` on `(next_retry_at)` where `status='pending'`.
- Verify: `\d embedding_jobs` показывает новые колонки.

**Отдельный upstream-issue (не входит в PR миграции):**
Boss обнаружил root cause крэш-лупа `gbrain-ingest-worker`: код делает `INSERT` в `embedding_jobs (doc_id, status)` без `ON CONFLICT`. При попытке пометить job для уже существующего `(doc_id, status)` — `UniqueViolationError` → crash. Правильный фикс — `INSERT ... ON CONFLICT (doc_id, status) DO UPDATE SET updated_at = NOW(), attempts = attempts + 1`. **Открыть issue в upstream `gbrain` (не в family-runtime).** Boss временно починил данные (удалил конфликтующие записи 14.07), но код нужно патчить.

**Deliverable:** PR с двумя миграциями + tests/swarm-notify-smoke.sh + tests/ingest-worker-retry-smoke.sh + запись в audit-log. После merge — Boss применяет обе миграции ко всем БД (`gbrain`, `gbrain_olya`, `gbrain_marianna`) и подтверждает в issue.

**Задача 2: system_health.py адаптирован.**
- Взять `seeds/system_health.py` за основу. Он рассчитан на 5 агентов в `~/.claude-lab/*`.
- Адаптировать проверки для случая Андрея:
  1. `active gateways` — ожидать 3 (`claude-gateway`, `-olya`, `-marianna`).
  2. `active gbrain services` — ожидать 12 (3 набора × 4 сервиса).
  3. `handoff freshness` — читать `/home/{claudegw,olyagw,mariannagw}/claude-lab/*/core/hot/handoff.md`, alert если mtime > 7 дней.
  4. `recent.md size` — alert если > 40KB (правило: `recent.md > 50KB → claude exit 1`; при 40 будим).
  5. `iptables integrity` — 6 REJECT-правил присутствуют.
  6. `delivery_outbox lag` — сколько строк со статусом `failed` за 24ч.
  7. `RAM available` — как у vps_capacity_alarm, но интегрирован в общий health.
- Вывод: `--json` для программного использования AVA + человекочитаемый по умолчанию.
- Cron: каждые 15 минут, лог `/var/log/family-runtime/health.log`.
- **Deliverable:** `scripts/system-health.sh` + `scripts/system-health.py` + timer/service unit.

**Задача 3: recent-md-guard.**
- Взять `seeds/recent-md-guard.sh`. Адаптировать пути под трёх агентов Андрея.
- Cron каждые 15 минут. Если `recent.md > 40KB` — tail последних 200 строк + бэкап полного файла в `~/.claude-lab/backups/recent-md/YYYY-MM-DD-HH-MM.md.gz`.
- **Deliverable:** cron + первая проверка вручную + запись в audit-log.

### P2 — Восстановление

**Задача 4: backup.sh на VPS Андрея.**
- Взять `seeds/backup.sh`, адаптировать пути. Что бэкапится:
  - Workspace каждого агента (git add + commit + push в его репо, если репо есть; иначе tar-архив в `/var/backups/family-runtime/YYYY-MM-DD/`).
  - `/etc/gbrain-*/`, `/etc/systemd/system/{gbrain-*,claude-gateway-*}.service`.
  - Только на VPS, не тянуть секреты в git.
- Cron 03:17 UTC (не 03:00 — во избежание совпадения с чужими).
- Retention: 14 дней локально, git-история — навсегда.
- **Deliverable:** `scripts/backup.sh` + cron + первый успешный запуск.

**Задача 5: git-репозитории для Оли и Евы.**

Решение владельца (Илья, 2026-07-14): оба репо — под аккаунтом Андрея `Android1872` (тот же, что уже используется для `andrei-vault`). Приватные. Одна GitHub-подписка на семью, одна кредитка (её нет, GitHub free), одно место наблюдения.

Шаги:
1. По образцу `andrei-vault` (см. `/opt/gbrain/vault/70-runbooks/github-repo-andrei.md`) создать приватные репо в аккаунте Android1872:
   - `andrei-vault-olya` — workspace Оли
   - `andrei-vault-eva` — workspace Марианны
2. Авторизация: gh device-flow с аккаунта Android1872 из sysuser'а `olyagw`, потом из `mariannagw`. Токены раскладываются в их локальные `~/.config/gh/hosts.yml` (mode 600).
3. `.gitignore` идентичный `andrei-vault`: secrets/, .credentials.json, .claude/{projects,sessions,shell-snapshots,backups}/, media-inbound/, *.log, .venv/, node_modules/.
4. Первый push workspace'а каждой.
5. **Проверка секретов ПЕРЕД push:** `git ls-files | grep -iE "token|secret|credential"` должен вернуть 0 строк. Если нет — abort.

Deliverable: два приватных репо + runbook «git операции» в vault каждой + audit-log.

### P3 — Ротация / гигиена

**Задача 6: memory-rotation набор.**
- Взять `seeds/{trim-hot,rotate-warm,compress-warm,memory-rotate}.sh`.
- Расписание — как у Ильи (смотри его cron): `trim-hot` каждый час, `rotate-warm` еженедельно, `compress-warm` ежемесячно.
- Адаптировать `AGENT_WORKSPACE` под трёх агентов.
- **Deliverable:** три cron-строки + первый прогон + запись в audit-log.

### P4 — Governance

**Задача 7: POLICY.md для семьи Андрея.**
- Взять `templates/POLICY.template.md` за основу. Заполнить под Андрея:
  - Зоны владения (AVA → своё, Оля → своё, Ева → своё).
  - Whitelist для write в чужие workspace (при необходимости).
  - Правила секретов на этом VPS.
  - Audit-log paths и что там писать.
- Положить в `/home/claudegw/family-policy.md` + ссылка в CLAUDE.md AVA.
- **Deliverable:** заполненный POLICY.md + ссылки из всех трёх CLAUDE.md.

**Задача 8: audit-log дисциплина.**
- Каждый ключевой sudo-вызов (provision, deprovision, миграция, rollback) —
  пишет в `/var/log/agent-provisioning.log` строку формата:
  `<ISO-ts> | <agent> | <cmd> | <args> | <exit_code> | <summary>`.
- Дополнительно у каждого агента — `~/audit.log` (mode 600) для его личных
  root-совершений (через sudo).
- **Deliverable:** helper `scripts/audit.sh log <event>` + вызов из всех скриптов.

### P5 — Автономный provisioning (та часть, ради которой всё)

**Задача 9: провижининг нового агента одной командой.**
- Реализовать `scripts/provision-agent-clone.SKELETON.sh` полностью
  (SKELETON уже описывает 9 шагов — просто заполнить их по образцу двух живых
  примеров на VPS: Оля и Ева).
- Реализовать `scripts/deprovision-agent-clone.SKELETON.sh`.
- Реализовать `scripts/provision-agent-status.sh <slug>` (active/inactive, RAM, docs count).
- Sudoers-drop `/etc/sudoers.d/claudegw-provision` — только эти три бинаря.
- **Тест:** dry-run + apply на fake-агенте `testbot` + verify + deprovision. Затем — на реальном (по запросу Ильи/Андрея).
- **Deliverable:** три работающих скрипта + sudoers + tests/provision-e2e.sh + runbook «как построить нового агента» в vault AVA.

### P6 — Ежедневный дайджест

**Задача 10: утренний дайджест Андрею в TG.**
- Cron 08:15 МСК (не 8:00) — AVA собирает и отправляет:
  - Ошибок за сутки: N (из health-логов).
  - RAM/disk/сеть.
  - Активны 3/3 агента.
  - Handoff Оли не обновлялся X дней (напоминание жизни в системе).
  - Что было запущено через sudo (agent-provisioning.log).
- Формат: одно короткое сообщение или файл через present, на усмотрение AVA.
- **Deliverable:** `scripts/morning-digest.sh` + cron + первый успешный запуск.

---

## Формат работы (для AVA)

1. **Одна задача — одна feature/ветка.** Пример: `feature/P0-swarm-migration`, `feature/P1-backup-script`.
2. **Тесты обязательны.** Не «работает у меня» — а скрипт `tests/<task>.sh` который проверяет
   инвариант. Если тест плоский (одна команда) — можно inline в PR-описании.
3. **PR к Boss'у.** Заголовок формата `[Pn] <короткое имя>`. В теле — что сделано, что протестировано, какие риски. Boss читает — либо мержит, либо возвращает с комментариями.
4. **Каждый мерж → тег.** `v0.1.0-p0-swarm`, `v0.1.1-p0-health`, и т.д.
5. **Rollback plan.** В каждом PR — секция «как откатить, если что-то пошло не так».
6. **Не трогать код Оли/Марианны.** Пишешь только в свою зону + в этот shared репо.
   Изменения на VPS Андрея — только через sudo-whitelist или через свой workspace.
7. **Не хардкодить пути в скрипты.** Все пути — через конфиг или переменные окружения.
   Это же даст будущим клиентам (другому VPS) шанс переиспользовать без правки кода.

---

## Приёмки в конце (definition of done для всей работы)

- [ ] Все P0/P1 задачи закрыты и протестированы.
- [ ] На VPS Андрея работает `system-health` — при принудительной поломке любого сервиса алерт приходит Андрею в TG в течение 15 минут.
- [ ] `sudo provision-agent-clone --name testbot --tg-id 999999999 --owner Test --apply` строит нового агента за ≤5 минут; `deprovision testbot --force` полностью откатывает.
- [ ] После случайной перезагрузки VPS все 3 агента поднимаются автоматически (проверка `systemctl reboot` в контролируемом окне).
- [ ] Ежедневный backup работает 7 дней подряд без пропусков.
- [ ] Андрей может из чата AVA спросить «здоровье», «покажи что делает система», «создай агента для X» — и получить осмысленный ответ или действие.

---

## Решения владельца (уже приняты)

1. **install.sh + family-runtime-update + sudoers whitelist** — один пакетный root, чтобы AVA дальше не тыкалась в Boss'а по каждой мелочи. Реализуется в P0-Задаче 0 (новый первый пункт).
2. **Место установки:** `/opt/family-runtime/current/` (git-клон), симлинки в `/usr/local/sbin/`.
3. **Пользователь-оркестратор:** `claudegw` (AVA). Добавляется в группу `family-runtime-admin`.
4. **Update-механизм:** только к подписанным тегам. Произвольные commit'ы применяться не будут (защита от подмены).
5. **Параллельная работа:** AVA может писать root-независимые скрипты (system-health, backup.sh, POLICY.md, morning-digest) параллельно с P0-Задачей 0. Каждый — отдельный PR.
6. **Репо Оли и Евы (P2-Задача 5):** оба приватных, в аккаунте Android1872 (тот же, где `andrei-vault`). Перед первым push — спросить у Оли и Марианны согласие: их рабочие папки поедут в приватный GitHub у папы. `.gitignore` уберёт секреты, но личные заметки — их данные, они решают.
7. **Единая инсталляция (Илья, 2026-07-14):** family-agent-runtime разворачиваем на одном VPS Андрея (95.179.243.18) как общую инфру для трёх агентов. `install.sh` может быть узким под этот VPS (Ubuntu 24.04, Postgres 16, sysuser claudegw), без универсальности. Разнесение на разные VPS — открытый горизонт, не сейчас.
8. **Модель работы через форк (Илья, 2026-07-14):** AVA работает в форке `Android1872/family-agent-runtime`, PR в `kolovershin-lgtm/family-agent-runtime`. Boss ревьюит в GitHub UI, мержит, тегает. AVA — writer в свой форк, reader в main Boss'а. Через `sudo family-runtime-update` подтягивает подписанные теги.
9. **Миграции gbrain (P1-Задача 1):** AVA пишет миграцию + tests. После merge PR Boss применяет её на живую БД сам, отдельного разрешения не нужно (это инфраструктура, не приватка).

## Открытые вопросы (эскалировать Boss'у по мере подхода)

- **Верификация тегов (P0-Задача 0):** старт с вариантом C (GitHub API sha-check), позже — GPG-подпись Boss'а.

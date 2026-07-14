# POLICY.md — Governance семейной AI-инфраструктуры Ахметовых

**Версия:** v0.1 (draft AVA, 2026-07-14)
**Статус:** ⚠ ОЖИДАЕТ SIGNOFF Андрея (владелец) + Ильи (эталон)
**Owner:** Андрей (signoff) + Boss/Илья (maintain стандарта) + каждый агент (применять)
**Канон:** этот файл — источник истины по governance на VPS Андрея. Разворачивается в `/home/claudegw/family-policy.md`, ссылка из CLAUDE.md каждого агента.

---

## 1. Агенты (canonical)

| Канон-slug | Sysuser | Telegram-бот | БД | Зона |
|---|---|---|---|---|
| `ava` (Jarvis) | `claudegw` | бот Андрея | `gbrain` | бизнес Андрея + оркестрация инфры |
| `olya` | `olyagw` | бот Оли | `gbrain_olya` | личный помощник Оли |
| `eva` | `mariannagw` | @Marianna_andreevna_eva_bot | `gbrain_marianna` | помощник Марианны (учёба, медиа) |
| `boss` (Илья) | внешний | @Kolovershin_Bot | — | эталон, ревью PR, root-операции |

**Правило:** в gbrain audit_log и delivery_outbox — только канон-slug. Если в handoff старое имя (`jarvis`, `AVA`) — переводить в канон на лету.

## 2. Owner split (кто что делает)

| Зона | Owner |
|---|---|
| root на хосте (chmod/chown/rm/cron/systemctl/apt) | **Boss/Илья** |
| Миграции БД gbrain (все три) | **Boss/Илья** |
| Код gbrain, gateway | **Boss/Илья** |
| sudoers-whitelist (`/etc/sudoers.d/claudegw-*`) | **Boss/Илья** ставит; **AVA** пользуется |
| Пакет family-runtime (скрипты, PR) | **AVA** пишет → **Boss** ревьюит/мержит |
| Провижининг новых агентов (после P5) | **AVA** через `sudo`-whitelist |
| Персона / handoff / decisions / память | **каждый агент — своё** |
| Общая семейная wiki `/srv/akhmetov-family` | **все три** (append-only, подпись автора) |

**Принцип:** не пересекать чужую зону. Нужен доступ в чужую — только через sudo-whitelist (инфра-скрипты AVA) или через владельца.

## 3. Secrets hygiene

- Секреты — в `~/secrets/` каждого sysuser'а, `chmod 600` (каталог 700). `.bak` тоже 600.
- **Никогда** не выводить токены/ключи/пароли в чат, логи, swarm-payload, git.
- `.gitignore` во всех репо блокирует: `secrets/`, `*-token`, `*.env`, `.credentials.json`.
- Передача секрета между агентами — не через общий каталог в открытом виде; если пришлось (handoff-файл) — минимальные права + удалить сразу после забора (урок 14.07: ключ Perplexity временно лежал в `/srv/akhmetov-family/_handoff`, забран Евой, удалён AVA).
- Один семейный API-ключ (Perplexity) общий у AVA и Евы — расход общий, следить за балансом.

## 4. Handoff ритуал (каждый агент)

- Значимая сессия → запись в `core/hot/handoff.md` (append-only, mtime обновляется).
- Долгосрочное решение → `core/warm/decisions.md` (+ dual-write в gbrain, где доступно).
- `handoff.md` не обновлялся 7+ дней при активной работе → persistence drift, чинить.
- Проверяется автоматически: `system-health.py` (P1-2), алерт в утреннем дайджесте (P6-10).

## 5. Swarm-ack ритуал

- Каждый агент в pre-prompt: `list_my_pending` — входящие задачи.
- На каждую: `ack` или `escalate`. Молчание = failed после N retries.
- Несуществующий получатель / мёртвый slug → сразу `failed` с error_msg.
- Схема `delivery_outbox` синхронизируется миграцией `2026-06-25-swarm-require-ack.sql` (P1-1).

## 6. Данные и приватность семьи

- `/home/<user>/` каждого агента — **приватная зона** (mode 700). Кросс-доступ только root (инфра-скрипты) или явное согласие.
- **Выгрузка рабочей папки агента в GitHub** (даже приватный репо) = данные покидают VPS. Для Оли и Марианны — **только с их личного согласия** (P2-5). До согласия — локальные снапшоты. `.gitignore` убирает секреты, но личные заметки — их решение.
- Общая семейная wiki — только то, что осознанно общее (календарь, контакты, планы). Приватное — в свой workspace.

## 7. Audit-log дисциплина

- Каждый root-вызов через whitelist (provision/deprovision/миграция/rollback) → `/var/log/agent-provisioning.log`:
  `<ISO-ts> | <agent> | <cmd> | <args> | <exit_code> | <summary>`.
- У каждого агента — `~/audit.log` (mode 600) для его личных root-совершений.
- Helper: `scripts/audit.sh log <event>` (P4-8), вызывается из всех инфра-скриптов.

## 8. Здоровье и ритм

- `system-health.py` (P1-2) — каждые 15 мин, лог `/var/log/family-runtime/health.log`.
- Утренний дайджест Андрею 08:15 МСК (P6-10): ошибки за сутки, RAM/disk, 3/3 агента, свежесть handoff'ов, что шло через sudo.
- Бэкапы (P2-4): workspace каждого агента + `/etc/{gbrain-*,systemd}`, cron 03:17 UTC, retention 14 дней.

---

## Changelog

- 2026-07-14: v0.1 draft (AVA) под семью Андрея на базе эталона Ильи. Ожидает signoff Андрея + Ильи. Разворачивание (`/home/claudegw/family-policy.md` + ссылки из трёх CLAUDE.md) — после мержа, через whitelist (правка чужих CLAUDE.md требует root/согласия).

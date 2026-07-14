# POLICY.md — Governance команды агентов JOY

**Версия:** v0.1 (draft Boss, 2026-06-07)
**Статус:** ⚠ ОЖИДАЕТ SIGNOFF Ильи
**Owner:** Илья (signoff) + Boss (maintain) + per-agent (применять)
**Канон:** этот файл — единственный источник истины по governance. Канон-копия для read-only — `~/.claude-lab/shared/POLICY.md` (mode 644).

---

## 1. Команда (canonical names)

| Канон-slug | Telegram бот | Зона |
|---|---|---|
| `conductor-agent` (Boss) | @Kolovershin_Bot | стратегия Ильи, мета-уровень |
| `hermes` (Архи) | @KolovershinBot | архитектура runtime, deploy-инфра |
| `jarvis-agent` (=Joe ист.) | @agent_joy_bot | финансы JOY |
| `mark-agent` | (TG бот) | SMM JOY |
| `pasha-agent` | (TG бот) | карточки МП |
| `victoria-agent` | (TG бот) | Instagram @rajskaja |
| `arma` | @joy_arma_bot | дежурный склад |

**Правило:** в gbrain audit_log и delivery_outbox — только канон-slug. Алиасы (`joe`, `jarvis`, `mark`, `conductor`) — НЕ адресаты. Если в handoff увидели старое имя — переводить в канон-slug на лету.

## 2. Owner split (кто что делает)

| Зона | Owner |
|---|---|
| Telegraph/секрет rotate (внешние API) | **Илья** |
| POLICY.md signoff и редактирование | **Илья** |
| chmod / chown / rm / cron на хосте | **Boss** |
| conductor_kb/ ведение | **Boss** |
| Runtime Hermes (config, sandbox-policy, скиллы) | **Архи** |
| Inter-agent swarm routing | **Архи** |
| Per-agent persona/handoff/decisions | **каждый агент** |

**Принцип:** не пересекать чужую зону. Если risk — пишешь в свой handoff и просишь.

## 3. Secrets hygiene

- Файлы секретов и их `.bak` — `chmod 600`. Всегда.
- Хранение: `~/.claude-lab/shared/secrets/` (mode 700) и `~/data/conductor_kb/_secrets/` (mode 700).
- Никогда не выводить токены в чат, в логи, в swarm-payload.
- При обновлении: `<file>.bak.<UTC-timestamp>` рядом, новый файл туда же, права 600.
- Ротация по типу: финансовые ключи (МС/Ozon/WB/YM/банки) — по протуханию. Контент-ключи (Telegraph/VK/IG) — по утечке.

## 4. Handoff ритуал (каждый агент)

- **Каждая значимая сессия → запись в `core/hot/handoff.md`** (append-only, mtime обновляется).
- **Каждое долгосрочное решение → `core/warm/decisions.md`** + dual-write в `gbrain mcp_create_decision_note`.
- **Если handoff.md не обновлялся 7+ дней при активной работе** — это R-persistence drift, фиксить.
- Conductor: handoff в `~/.claude-lab/conductor/core/hot/handoff.md` (вне `.claude/` из-за sensitive-zone).

## 5. Swarm-ack ритуал

- Каждый агент в pre-prompt вызывает `mcp__gbrain-swarm__list_my_pending` — получает входящие задачи.
- На каждую задачу: либо `ack`, либо `escalate`. Молчание = failed после N retries.
- Если получатель не существует (или slug мёртв) — сразу `failed` с error_msg, не до 5 attempts.

## 6. .bak правило

- `.bak` файлы системных каталогов (CLAUDE.md, USER.md, identity.md, SYSTEM_PROMPT.md, rules.md, settings.local.json) — **mode 600** (identity injection surface).
- `.bak` секретов и токенов — **mode 600**, всегда.
- Старые `.bak` (>30 дней) — переносить в `archive/` или удалять при подтверждении.

## 7. Sensitive-zone (доступ Boss/Conductor)

- `~/.claude/` и `~/.claude-lab/{jarvis,mark,pasha,victoria}/` — по умолчанию **read-only** для Boss.
- Whitelist (write только после явного «да» Ильи): `core/hot/handoff.md`, `core/warm/decisions.md`, `.claude/settings.local.json`.
- Перед записью: путь + diff в ответе.
- Audit-log обязателен: `~/data/conductor_kb/_private/write_journal.log`.

## 8. Weekly audit (ритм)

- **Каждое воскресенье 21:00 МСК** Boss запускает `agents_observer.sh`:
  - handoff mtime по 5 агентам
  - delivery_outbox failed counter
  - secret-файлы перм-чек
  - gbrain DB размер
  - state.db размер
- Отчёт в `~/data/conductor_kb/audits/weekly_<date>.md`.
- Если flags > 0 — handoff в conductor-handoff + dual в gbrain.

---

## Changelog

- 2026-06-07: v0.1 draft (Boss). Ожидает signoff Ильи. Триггер: Архи-аудит (R5: POLICY.md отсутствует) + Boss-аудит (4 false positive Архи, R-persistence drift, naming chaos в delivery_outbox).

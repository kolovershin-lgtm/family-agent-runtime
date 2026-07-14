# family-agent-runtime — architecture

## Что это

Пакет для однотипной семейной инфраструктуры «несколько изолированных AI-агентов на одном VPS».
Собран из проверенного кода эталонной установки Ильи (edgelab, 5 агентов + 3 hermes)
и адаптирован для повторного применения (Андрей: AVA + Оля + Ева).

## Компоненты

- **Naming / изоляция**: каждый агент — свой `Nname>gw` sysuser (uid ≥ 1001, home 700),
  своя БД `gbrain_<name>` в общем Postgres, свой набор из 4 systemd-юнитов gbrain
  (`memory-mcp`, `recall-mcp`, `swarm-mcp`, `ingest-worker`) на портах `{swarm, memory, recall}`,
  свой gateway-юнит `claude-gateway-<name>`.
- **Сетевая изоляция**: iptables `OUTPUT --uid-owner ...` REJECT-правила для cross-user
  портов, потому что `recall-mcp` без auth (см. runbook_gbrain_two_instances_isolation.md).
- **Наблюдаемость**: `system_health.py` (7 проверок), `agent_status.sh`, `vps_capacity_alarm.sh`.
- **Гигиена**: `recent-md-guard.sh` (cron 15м), `memory-rotation/` (trim-hot, rotate-warm,
  compress-warm).
- **Backup**: ежедневный `backup.sh` — git-snapshot workspace + config archive.
- **Provisioning**: `provision-agent-clone` (dry-run по умолчанию, `sudo` whitelist).
- **Governance**: `POLICY.template.md` — правила зон записи, audit, secrets hygiene.
- **Persona**: `CLAUDE.template.md` — базовый скелет системного промпта агента.

## Инвариант, который нельзя нарушать

Никакая часть пакета не должна:

1. Давать агенту root вне whitelist (`/etc/sudoers.d/*-provision`).
2. Позволять агенту читать/писать в чужой `/home/<user>/`.
3. Класть секреты в git-репо (пакет не читает секреты, только знает пути к ним).
4. Автоматически ставить apt-пакеты или менять системные конфиги вне `/etc/gbrain-<name>/`
   и `/etc/systemd/system/{gbrain-<name>-*,claude-gateway-<name>}.service`.

## Модель распространения

- Репо публичный (внутри секретов нет).
- На каждом целевом VPS: `git clone` в `/opt/family-runtime/`, `sudo ./install.sh`.
- Обновления: `cd /opt/family-runtime && git pull && sudo ./upgrade.sh`.
- Идемпотентность: `install.sh` и `upgrade.sh` можно запускать многократно.

## Целевая аудитория

- **Эталон**: Илья, edgelab, `~/.claude-lab/` (5 агентов + 3 hermes).
- **Первый клиент**: Андрей, VPS 95.179.243.18 (AVA + Оля + Ева).
- **На горизонте**: Витя-агент, Марианна на своём хосте, друзья Ильи.

## Совместимость

- Ubuntu 22.04 / 24.04 (тестировано на 24.04).
- Postgres 16 + pgvector.
- Python 3.12.
- FastEmbed models: `intfloat/multilingual-e5-large` (1024d, 1.5GB RAM) или
  `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (384d, 200MB RAM).

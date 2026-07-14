# family-agent-runtime

Пакет для однотипной инфраструктуры «несколько изолированных AI-агентов на одном VPS».
Собран из проверенных компонентов эталонной установки Ильи и адаптирован для
повторного применения (первый клиент — Андрей: AVA + Оля + Ева).

## Устройство

```
family-agent-runtime/
├── README.md                     ← этот файл
├── TASK-FOR-AVA.md               ← ТЗ (что достроить, приёмки, приоритеты)
├── docs/
│   └── architecture.md           ← общая схема и инварианты безопасности
├── seeds/                        ← рабочие эталоны из edgelab (готовы к копированию)
│   ├── system_health.py
│   ├── agent_status.sh
│   ├── recent-md-guard.sh
│   ├── trim-hot.sh
│   ├── rotate-warm.sh
│   ├── compress-warm.sh
│   ├── memory-rotate.sh
│   └── backup.sh
├── scripts/                      ← новые скрипты (SKELETON = каркас, AVA дописывает)
│   ├── provision-agent-clone.SKELETON.sh
│   └── deprovision-agent-clone.SKELETON.sh
├── templates/                    ← шаблоны с {{plchlder}}
│   ├── POLICY.template.md
│   └── CLAUDE.template.md
├── systemd/
│   ├── gbrain-agent.service.template
│   └── claude-gateway.service.template
└── migrations/
    └── 2026-06-25-swarm-require-ack.sql
```

## Идея работы

1. На целевом VPS: `git clone` в `/opt/family-runtime/`.
2. `sudo ./install.sh` — раскладывает seeds в `/usr/local/bin/`, templates в
   `/opt/family-runtime/templates/`, ставит systemd-таймеры.
3. Дальше — команды `provision-agent-clone`, `system-health`, `agent-status`,
   `runtime-rollback` доступны как sudo whitelist агенту-оркестратору (AVA).
4. Обновления: `git pull && sudo ./upgrade.sh` — идемпотентно, применяет новые
   миграции и обновляет скрипты, не трогает существующих агентов.

## Кому что читать

- **Илья (эталон)** — обновляет seeds по мере эволюции своей установки.
- **AVA (первый клиент)** — работает по [TASK-FOR-AVA.md](TASK-FOR-AVA.md):
  дописывает SKELETON'ы, тестирует на VPS, коммитит в feature/ветки, PR на
  ревью Boss'у.
- **Boss (Илья + Conductor)** — держит стандарт, ревьюит PR от AVA, мержит в main.

## Инварианты (нельзя нарушать)

- Никакого секрета внутри репо (в семенных скриптах есть только ссылки на пути).
- Никакого root вне whitelist (`/etc/sudoers.d/*-provision`).
- Никакого доступа агента к чужому `/home/<user>/`.
- `install.sh` и `upgrade.sh` — идемпотентны.

## Обратная связь

- Найден баг / нехватка / улучшение — issue или PR в этот репо.
- Вопросы по эксплуатации на конкретном VPS — в личке владельцу.

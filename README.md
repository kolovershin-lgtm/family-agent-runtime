# family-agent-runtime

Пакет для однотипной инфраструктуры «несколько изолированных AI-агентов на одном VPS».
Собран из проверенных компонентов эталонной установки Ильи и адаптирован для
повторного применения (первый клиент — Андрей: AVA + Оля + Ева).

## Устройство

```
family-agent-runtime/
├── README.md                              ← этот файл
├── TASK-FOR-AVA.md                        ← ТЗ (что достроить, приёмки, приоритеты)
├── install.SKELETON.sh                    ← первичная установка на VPS (один root-заход)
├── docs/
│   └── architecture.md                    ← общая схема и инварианты безопасности
├── seeds/                                 ← рабочие эталоны из edgelab (готовы к копированию)
│   ├── system_health.py                     health, rotation, backup, guard, status
│   ├── agent_status.sh
│   ├── recent-md-guard.sh
│   ├── trim-hot.sh · rotate-warm.sh · compress-warm.sh · memory-rotate.sh
│   └── backup.sh
├── scripts/                               ← новые скрипты (SKELETON = каркас, AVA дописывает)
│   ├── family-runtime-update.SKELETON.sh    apt-подобный update до подписанных тегов
│   ├── provision-agent-clone.SKELETON.sh
│   └── deprovision-agent-clone.SKELETON.sh
├── templates/
│   ├── POLICY.template.md
│   ├── CLAUDE.template.md
│   └── sudoers.template                     whitelist FAMILYRT для group family-runtime-admin
├── systemd/
│   ├── gbrain-agent.service.template
│   └── claude-gateway.service.template
└── migrations/
    └── 2026-06-25-swarm-require-ack.sql
```

## Идея работы

1. На целевом VPS: `git clone` в `/opt/family-runtime/current/`.
2. **Один root-заход:** `sudo ./install.sh --orchestrator-user <user> --apply`
   — создаёт группу `family-runtime-admin`, ставит sudoers-whitelist,
   раскладывает симлинки в `/usr/local/sbin/`, ставит cron-задачи,
   применяет все pending миграции gbrain.
3. Дальше agent-оркестратор (AVA) работает автономно через whitelist:
   `sudo system-health`, `sudo provision-agent-clone`, `sudo family-runtime-update` и т.д.
   Никакого `sudo bash`, `sudo apt`, `sudo systemctl` — блокировано.
4. **Обновления:** оркестратор запускает `sudo family-runtime-update` — скрипт
   делает `git pull`, проверяет что HEAD == **подписанный тег** (не произвольный
   commit), применяет новые миграции, обновляет симлинки. Если тег не проходит
   верификацию — отказ.
5. **Root возвращается только** когда появляется качественно новый примитив,
   не покрытый пакетом (напр., новая семья, новый архитектурный слой).

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

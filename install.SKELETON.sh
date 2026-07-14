#!/usr/bin/env bash
# install.sh — единственный root-заход при развёртывании family-agent-runtime на VPS.
#
# Идея: после этого скрипта AVA (и любой будущий оркестратор из группы
# family-runtime-admin) работает автономно через `sudo family-runtime-update`.
# Root возвращается ТОЛЬКО когда появляется качественно новый примитив,
# не покрытый пакетом.
#
# SKELETON. AVA дописывает по TASK-FOR-AVA.md P0-Задача 0.
#
# Требования:
#   - Ubuntu 22.04 / 24.04
#   - Postgres 16 + pgvector
#   - Уже настроен /opt/gbrain (общая инсталляция) и хотя бы один агент
#
# Использование:
#   sudo ./install.sh --orchestrator-user claudegw [--apply]

set -euo pipefail

readonly RUNTIME_DIR=/opt/family-runtime
readonly BIN_DIR=/usr/local/sbin
readonly SUDOERS=/etc/sudoers.d/family-runtime
readonly CRON_DROP=/etc/cron.d/family-runtime
readonly LOG=/var/log/family-runtime/install.log
readonly ADMIN_GROUP=family-runtime-admin

# ---- 1. Проверки ----------------------------------------------------------
# TODO:
# - id != 0 → отказ (нужен root)
# - --orchestrator-user существует и не root
# - Postgres доступен (sudo -u postgres psql -c '\l' | grep gbrain)
# - Свободное место в /opt > 100M
# - Detect already installed: /etc/sudoers.d/family-runtime существует → предлагать --reinstall

# ---- 2. Группа family-runtime-admin ---------------------------------------
# TODO:
# - groupadd -r family-runtime-admin (если нет)
# - usermod -aG family-runtime-admin <orchestrator-user>

# ---- 3. Раскладка файлов --------------------------------------------------
# TODO:
# - mkdir -p $RUNTIME_DIR, chown root:family-runtime-admin, chmod 2755
# - cp -a . $RUNTIME_DIR/current/ (полный snapshot этого репо)
# - симлинки $BIN_DIR/{system-health,agent-status,provision-agent-clone,
#   deprovision-agent-clone,provision-agent-status,family-runtime-update,
#   backup,recent-md-guard,morning-digest} → $RUNTIME_DIR/current/scripts/*
# - chmod 755 на скрипты

# ---- 4. sudoers whitelist -------------------------------------------------
# TODO:
# - Сгенерировать $SUDOERS.tmp из templates/sudoers.template
# - visudo -c -f $SUDOERS.tmp — валидация. Провал → abort.
# - mv $SUDOERS.tmp $SUDOERS, chmod 440
# Whitelist ровно эти команды (никакого sudo bash, sudo apt):
#   Cmnd_Alias FAMILYRT = /usr/local/sbin/system-health, \
#                         /usr/local/sbin/agent-status, \
#                         /usr/local/sbin/provision-agent-clone, \
#                         /usr/local/sbin/deprovision-agent-clone, \
#                         /usr/local/sbin/provision-agent-status, \
#                         /usr/local/sbin/family-runtime-update, \
#                         /usr/local/sbin/backup, \
#                         /usr/local/sbin/recent-md-guard, \
#                         /usr/local/sbin/morning-digest
#   %family-runtime-admin ALL=(root) NOPASSWD: FAMILYRT
#   Defaults!FAMILYRT log_output, log_input, env_reset

# ---- 5. cron / systemd таймеры --------------------------------------------
# TODO:
# - Скопировать systemd/timers/*.timer + *.service (когда AVA их напишет)
# - Или упростить: положить /etc/cron.d/family-runtime с задачами:
#   */15 * * * * root /usr/local/sbin/system-health --alert
#   */15 * * * * root /usr/local/sbin/recent-md-guard
#   17 3 * * *   root /usr/local/sbin/backup
#   15 5 * * *   root /usr/local/sbin/morning-digest

# ---- 6. Миграции gbrain ---------------------------------------------------
# TODO:
# - Прогнать все migrations/*.sql через все БД gbrain* по алфавиту
# - Использовать таблицу schema_migrations (создать если нет) для трекинга
# - Не применять уже применённые (idempotent)
# - Ошибка на одной БД → rollback и stop

# ---- 7. Первый снапшот backup + первая проверка health --------------------
# TODO:
# - /usr/local/sbin/backup --initial → создаст baseline
# - /usr/local/sbin/system-health --json → сохранить как /var/log/family-runtime/baseline.json
# - Сравнивать при следующих запусках, чтобы видеть drift

# ---- 8. Финальный отчёт ---------------------------------------------------
# TODO:
# - Список: что установлено, куда, sudoers-путь, установленные таймеры, применённые миграции, версия/тег пакета
# - Инструкция orchestrator'у: как проверить (sudo family-runtime-update --dry-run)

echo "install.sh SKELETON — implement TODO blocks per TASK-FOR-AVA.md P0-Task 0"
exit 2

#!/usr/bin/env bash
# family-runtime-update — обновление пакета на VPS до нового подписанного тега.
# Запускается orchestrator'ом через sudo (whitelist из install.sh).
#
# Инвариант: HEAD после `git pull` ДОЛЖЕН совпадать с сигнатурным тегом,
# помеченным Boss'ом после ревью PR. Произвольные коммиты применяться не должны.
# Это ровно то, что делает apt: обновляйся, но только до релиза.
#
# SKELETON. AVA дописывает по TASK-FOR-AVA.md P0-Задача 0.
#
# Использование:
#   sudo family-runtime-update [--dry-run] [--tag <vX.Y.Z>]
#
# --dry-run: показать diff между текущей и предлагаемой версией без применения.
# --tag: apply конкретный тег (по умолчанию — последний семверный тег).

set -euo pipefail

readonly RUNTIME_DIR=/opt/family-runtime
readonly CURRENT=$RUNTIME_DIR/current
readonly LOG=/var/log/family-runtime/update.log
readonly TAG_KEY_FINGERPRINT=""   # TODO: подпись Boss'а (либо GPG, либо signed tag, либо hash-allowlist)

# ---- 1. Проверки безопасности ---------------------------------------------
# TODO:
# - Только root (uid 0) может запускать эффективно
# - Нет открытых uncommitted changes в $CURRENT (git diff-index --quiet HEAD)
# - Working tree чистое → пропускаем; иначе abort с логом diff'а
# - $CURRENT.git/config remote origin — соответствует ожидаемому URL (защита от подмены)

# ---- 2. Fetch + определение целевого тега ---------------------------------
# TODO:
# - cd $CURRENT && git fetch --tags origin
# - Если --tag передан явно: TARGET=$1. Иначе:
#   TARGET=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
# - Если TARGET == текущий HEAD tag → «already up-to-date», exit 0
# - Если TARGET не существует → error

# ---- 3. Верификация тега --------------------------------------------------
# TODO:
# Вариант A (GPG-подпись, если Boss настроил):
#   git tag -v $TARGET 2>&1 | grep -q "Good signature from" || abort
# Вариант B (allowlist tag hashes в /etc/family-runtime/tags.allowlist):
#   git rev-parse $TARGET → sha, проверить что sha в allowlist
# Вариант C (простейший, для старта): проверка что тег создан GitHub-аккаунтом Ильи
#   через `gh api repos/kolovershin-lgtm/family-agent-runtime/git/refs/tags/$TARGET`
#   и sha совпадает с git rev-parse $TARGET^{}
# Без прохождения верификации — hard abort.

# ---- 4. Dry-run отчёт -----------------------------------------------------
# TODO:
# - Показать что изменится: git log --oneline HEAD..$TARGET
# - Показать какие миграции будут применены (diff migrations/)
# - Показать какие сервисы понадобится перезапустить (diff systemd/)
# Если --dry-run → exit 0 без применения.

# ---- 5. Применение --------------------------------------------------------
# TODO:
# a. Snapshot текущего состояния: tar $CURRENT → /var/backups/family-runtime/rt-$(date).tar.gz
# b. git checkout $TARGET
# c. Применить новые миграции (использовать schema_migrations tracking)
# d. Обновить симлинки в /usr/local/sbin/ (перечитать список скриптов)
# e. Обновить /etc/cron.d/family-runtime и /etc/sudoers.d/family-runtime,
#    если файлы в репо изменились. sudoers обязательно через visudo -c.
# f. Перезапустить сервисы, чей unit-файл изменился: systemctl daemon-reload && systemctl restart <changed>
# g. Прогнать system-health после — если алерты → automatic rollback (снапшот из шага a)
# h. audit-log: строка «updated to $TARGET at $ts by $SUDO_USER»

# ---- 6. Финальный отчёт ---------------------------------------------------
# TODO:
# - Печать: from → to, что применено, сколько миграций, какие сервисы перезапущены, health-status
# - stdout — короткий summary; stderr — детали
# - exit 0 если всё ok; > 0 если rollback

echo "family-runtime-update SKELETON — implement TODO blocks per TASK-FOR-AVA.md P0-Task 0"
exit 2

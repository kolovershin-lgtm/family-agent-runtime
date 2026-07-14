#!/bin/bash
#
# edgelab-backup.sh
# Ежедневный бэкап критичных данных Claude-агентов.
# Запускается из user-cron edgelab в 03:17.
#
set -euo pipefail

DATE=$(date +%Y-%m-%d)
BACKUP_ROOT=/home/edgelab/backups
DEST=$BACKUP_ROOT/$DATE
LOG=$BACKUP_ROOT/backup.log

mkdir -p "$DEST"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

log "=== Backup started ($DATE) ==="

# 1. Workspace агентов (Jarvis + Victoria)
tar czf "$DEST/claude-lab.tar.gz" -C /home/edgelab .claude-lab/ 2>>"$LOG" || log "WARN: claude-lab"
log "claude-lab.tar.gz: $(du -h "$DEST/claude-lab.tar.gz" | cut -f1)"

# 2. Глобальный CC + sessions (без cache)
tar czf "$DEST/claude-global.tar.gz" \
    -C /home/edgelab \
    --exclude='.claude/cache' \
    --exclude='.claude/shell-snapshots' \
    .claude/ 2>>"$LOG" || log "WARN: claude-global"
log "claude-global.tar.gz: $(du -h "$DEST/claude-global.tar.gz" | cut -f1)"

# 3. Gateway-конфиг + state (БЕЗ media-inbound и log)
tar czf "$DEST/gateway.tar.gz" \
    -C /home/edgelab \
    --exclude='claude-gateway/media-inbound' \
    --exclude='claude-gateway/gateway.log' \
    claude-gateway/ 2>>"$LOG" || log "WARN: gateway"
log "gateway.tar.gz: $(du -h "$DEST/gateway.tar.gz" | cut -f1)"

# 4. OpenViking — останавливаем контейнер для консистентности, бэкапим, стартуем
log "Stopping openviking..."
docker stop openviking >/dev/null 2>>"$LOG" || log "WARN: docker stop"
tar czf "$DEST/openviking.tar.gz" -C /home/edgelab .openviking/ 2>>"$LOG" || log "WARN: openviking"
docker start openviking >/dev/null 2>>"$LOG" || log "WARN: docker start"
log "openviking.tar.gz: $(du -h "$DEST/openviking.tar.gz" | cut -f1)"

# 5. ~/data/ (наши аналитические данные)
tar czf "$DEST/data.tar.gz" -C /home/edgelab data/ 2>>"$LOG" || log "WARN: data"
log "data.tar.gz: $(du -h "$DEST/data.tar.gz" | cut -f1)"

# 6. Манифест с контрольными суммами
(cd "$DEST" && sha256sum *.tar.gz > MANIFEST.sha256)
log "MANIFEST.sha256 created"

# 7. Ротация — локально храним 3 дня (полная история — в off-site YC Object Storage)
DELETED=$(find "$BACKUP_ROOT/" -mindepth 1 -maxdepth 1 -type d -mtime +3 -print -exec rm -rf {} \; 2>>"$LOG" | wc -l)
log "Pruned $DELETED snapshot(s) older than 3 days (off-site copy retained)"

# 8. Off-site: rclone sync в Yandex Object Storage (с шифрованием)
log "Off-site sync to yc-crypt..."
if rclone sync "$DEST" "yc-crypt:snapshots/$DATE" --transfers 4 --checksum 2>>"$LOG"; then
    log "Off-site OK"
else
    log "WARN: off-site sync failed (см. лог)"
fi

# 9. Итог
TOTAL=$(du -sh "$DEST" | cut -f1)
ALL=$(du -sh "$BACKUP_ROOT" | cut -f1)
log "=== Backup done — today: $TOTAL · total: $ALL ==="

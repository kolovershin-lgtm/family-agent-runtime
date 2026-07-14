#!/usr/bin/env bash
# recent-md-guard — sidecar protector против двух классов exit 1:
#   (a) bloated core/hot/recent.md > 40KB  → tail-trim до 200 строк
#   (b) bloated session jsonl > 40MB       → archive + wipe sid-file для свежей сессии
# Cron: каждые 15 мин.
# Audit-log: ~/data/conductor_kb/_private/audit.log
# Author: Conductor, 2026-05-18 (после двух инцидентов с Пашей и упреждающей ротации Jarvis).

set -euo pipefail

RECENT_THRESHOLD_BYTES=40000
RECENT_KEEP_LINES=200
SESSION_THRESHOLD_BYTES=$((40 * 1024 * 1024))   # 40 MB

LOG=/home/edgelab/data/conductor_kb/_private/audit.log
GATEWAY_STATE=/home/edgelab/claude-gateway/state
GATEWAY_CFG=/home/edgelab/claude-gateway/config.json

AGENTS=(jarvis mark pasha victoria)   # conductor пропускаем — не ротируем себя из своего же скрипта
ts() { date -u +%FT%TZ; }

# (a) recent.md trim
for a in "${AGENTS[@]}" conductor; do
    f=/home/edgelab/.claude-lab/$a/.claude/core/hot/recent.md
    [ -f "$f" ] || continue
    size=$(stat -c %s "$f")
    if [ "$size" -gt "$RECENT_THRESHOLD_BYTES" ]; then
        bak="${f}.bak.guard.$(date +%Y%m%d_%H%M%S)"
        lines_before=$(wc -l < "$f")
        cp "$f" "$bak"
        tail -n "$RECENT_KEEP_LINES" "$f" > "${f}.new" && mv "${f}.new" "$f"
        size_after=$(stat -c %s "$f")
        lines_after=$(wc -l < "$f")
        echo "$(ts) guard recent.md trim agent=$a ${size}→${size_after}B (${lines_before}→${lines_after} lines) backup=$(basename "$bak")" >> "$LOG"
    fi
done

# (b) session jsonl rotate
project_key_from_workspace() {
    echo "$1" | tr '/.' '--'
}

for a in "${AGENTS[@]}"; do
    # Найти sid-файл агента в gateway-state (может быть с разным chat_id-постфиксом)
    for sf in "$GATEWAY_STATE"/sid-${a}-*.txt; do
        [ -f "$sf" ] || continue
        sid=$(cat "$sf")
        [ -z "$sid" ] && continue

        ws=$(python3 -c "import json; print(json.load(open('$GATEWAY_CFG'))['agents']['$a']['workspace'])" 2>/dev/null)
        [ -z "$ws" ] && continue

        pk=$(project_key_from_workspace "$ws")
        jsonl="/home/edgelab/.claude/projects/${pk}/${sid}.jsonl"
        [ -f "$jsonl" ] || continue

        size=$(stat -c %s "$jsonl")
        if [ "$size" -gt "$SESSION_THRESHOLD_BYTES" ]; then
            bak="${jsonl}.bak.guard.$(date +%Y%m%d_%H%M%S)"
            mv "$jsonl" "$bak"
            # ВАЖНО: удаляем И .txt И .first маркеры.
            # .first — gateway смотрит на его наличие чтобы понять «is_first=True/False»:
            #   нет .first → создаёт сессию через --session-id (правильно)
            #   есть .first без .txt → пытается --resume "" → claude exit 1
            #   есть .first и .txt с битым sid → claude exit 1 "No conversation found"
            rm -f "$sf"
            rm -f "${sf%.txt}.first"
            size_mb=$((size / 1024 / 1024))
            echo "$(ts) guard session rotate agent=$a sid=$sid size=${size_mb}MB → archived $(basename "$bak"), sid .txt+.first removed" >> "$LOG"
        fi
    done
done

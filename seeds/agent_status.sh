#!/bin/bash
# agent_status.sh — что в работе у каждого агента команды.
# Читает core/hot/handoff.md + реальные следы активности (gateway.log, recent.md).
# handoff.md может месяцами не обновляться при живом агенте — не судить по нему одному.

set -u
TS=$(date '+%Y-%m-%d %H:%M')
GWLOG=/home/edgelab/claude-gateway/gateway.log

print_agent() {
  local name=$1 slug=$2 path=$3
  local ws
  ws=$(dirname "$(dirname "$(dirname "$path")")")
  echo "==== $name ===="
  if [ -f "$path" ]; then
    grep -E '^\[?(PENDING|BLOCKED|IN-PROGRESS|OPEN)' "$path" 2>/dev/null | head -5
    grep -E '^[0-9]+\.\s*\*\*\[(PENDING|BLOCKED|IN-PROGRESS|OPEN)' "$path" 2>/dev/null | head -5
    local mtime
    mtime=$(stat -c '%y' "$path" 2>/dev/null | cut -d. -f1)
    echo "  (handoff updated: $mtime)"
  else
    echo "  no handoff at $path"
  fi
  # Реальная активность: последний ответ через gateway + свежесть recent.md
  if [ -f "$GWLOG" ]; then
    local last_reply
    last_reply=$(grep -E "\[$slug\] replied" "$GWLOG" 2>/dev/null | tail -1 | cut -d' ' -f1-2 | cut -d, -f1)
    echo "  (last gateway reply: ${last_reply:-none in current log})"
  fi
  local recent="$ws/.claude/core/hot/recent.md"
  if [ -f "$recent" ]; then
    echo "  (recent.md updated: $(stat -c '%y' "$recent" 2>/dev/null | cut -d. -f1))"
  fi
  echo
}

echo "=== AGENT STATUS — $TS ==="
echo
print_agent "Джо (Jarvis)"   "jarvis"   "/home/edgelab/.claude-lab/jarvis/.claude/core/hot/handoff.md"
print_agent "Марк (Mark)"    "mark"     "/home/edgelab/.claude-lab/mark/.claude/core/hot/handoff.md"
print_agent "Паша (Pasha)"   "pasha"    "/home/edgelab/.claude-lab/pasha/.claude/core/hot/handoff.md"
print_agent "Виктория"       "victoria" "/home/edgelab/.claude-lab/victoria/.claude/core/hot/handoff.md"
print_agent "Life (Павел)"   "life"     "/home/edgelab/.claude-lab/life/.claude/core/hot/handoff.md"

#!/usr/bin/env python3
"""system_health.py — Conductor self-audit: соответствует ли система задуманному.

7 проверок (PASS/WARN/FAIL):
  1. Agent handoffs не устарели (≤7 дней)
  2. gbrain MCP up (3 порта отвечают)
  3. gbrain dual-write активен (есть свежие entries в recall)
  4. Cron-задачи отрабатывают (логи свежие)
  5. Memory rotation работает (jarvis pipeline)
  6. CLAUDE_CODE_AUTO_COMPACT_WINDOW выставлен
  7. CLAUDE.md размер у Conductor (≤200 строк core)

Запуск: ~/bin/system_health.py [--json]
Output: human-readable summary или JSON.
"""

import os
import sys
import json
import socket
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

HOME = Path.home()
AGENTS = ["jarvis", "mark", "pasha", "victoria"]
GBRAIN_PORTS = {"memory": 8767, "recall": 8768, "swarm": 8766}
HANDOFF_STALE_DAYS = 7
CRON_LOG_STALE_HOURS = 48
NOW = datetime.now()

# Per-log expected frequency override (для weekly/monthly cron)
CRON_LOG_FREQ_OVERRIDE = {
    "self_compile.log": 192,   # weekly (8d max)
    "ym/cron.log": 768,        # monthly (32d max)
    "insta_token.log": 720,    # ~25d max
    "cron-memory-rotate.log": 999999,  # пустой по дизайну, stderr-only
    "cron-rotate-warm.log": 999999,
    "cron-trim-hot.log": 999999,
    "cron-compress-warm.log": 999999,
}


def fmt_ago(ts: float) -> str:
    delta = NOW - datetime.fromtimestamp(ts)
    if delta.total_seconds() < 3600:
        return f"{int(delta.total_seconds() / 60)}m"
    if delta.total_seconds() < 86400:
        return f"{int(delta.total_seconds() / 3600)}h"
    return f"{delta.days}d"


def check_handoffs() -> dict:
    results = []
    worst = "PASS"
    for a in AGENTS:
        p = HOME / ".claude-lab" / a / ".claude" / "core" / "hot" / "handoff.md"
        if not p.exists():
            results.append({"agent": a, "status": "FAIL", "note": "handoff отсутствует"})
            worst = "FAIL"
            continue
        age_days = (NOW.timestamp() - p.stat().st_mtime) / 86400
        if age_days > HANDOFF_STALE_DAYS:
            status = "WARN"
            if worst == "PASS":
                worst = "WARN"
            note = f"устарел на {int(age_days)}д"
        else:
            status = "PASS"
            note = f"{fmt_ago(p.stat().st_mtime)} назад"
        results.append({"agent": a, "status": status, "note": note})
    return {"name": "Agent handoffs", "status": worst, "items": results}


def check_gbrain_ports() -> dict:
    results = []
    worst = "PASS"
    for name, port in GBRAIN_PORTS.items():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        try:
            s.connect(("127.0.0.1", port))
            results.append({"service": name, "port": port, "status": "PASS"})
        except Exception as e:
            results.append({"service": name, "port": port, "status": "FAIL", "note": str(e)})
            worst = "FAIL"
        finally:
            s.close()
    return {"name": "gbrain MCP up", "status": worst, "items": results}


def check_gbrain_dualwrite() -> dict:
    """Через psql проверяем, что в documents есть свежие записи за 7 дней."""
    try:
        out = subprocess.run(
            [
                "sudo", "-u", "postgres", "psql", "-d", "gbrain", "-tA", "-c",
                "select count(*) from documents where created_at > now() - interval '7 days';"
            ],
            capture_output=True, text=True, timeout=10
        )
        cnt = int(out.stdout.strip() or "0")
        if cnt == 0:
            return {"name": "gbrain dual-write (7d)", "status": "WARN", "items": [{"note": "0 записей за 7 дней"}]}
        return {"name": "gbrain dual-write (7d)", "status": "PASS", "items": [{"count": cnt}]}
    except subprocess.CalledProcessError as e:
        return {"name": "gbrain dual-write (7d)", "status": "FAIL", "items": [{"note": str(e)}]}
    except Exception as e:
        return {"name": "gbrain dual-write (7d)", "status": "WARN", "items": [{"note": f"psql недоступен: {e}"}]}


def check_cron_logs() -> dict:
    """Логи cron-задач не должны быть старше 48ч."""
    log_dirs = [
        HOME / "data",
        HOME / ".claude-lab" / "jarvis" / "logs",
    ]
    results = []
    worst = "PASS"
    for ld in log_dirs:
        if not ld.exists():
            continue
        for f in ld.glob("*.log"):
            if f.stat().st_size == 0:
                continue
            age_h = (NOW.timestamp() - f.stat().st_mtime) / 3600
            threshold = CRON_LOG_FREQ_OVERRIDE.get(f.name, CRON_LOG_STALE_HOURS)
            if age_h > threshold * 7:  # очень старые игнорируем
                continue
            status = "PASS" if age_h <= threshold else "WARN"
            if status == "WARN" and worst == "PASS":
                worst = "WARN"
            results.append({"file": str(f.name), "age_h": round(age_h, 1), "status": status})
    return {"name": "Cron logs (<48h)", "status": worst, "items": sorted(results, key=lambda x: -x["age_h"])[:8]}


def check_memory_rotation() -> dict:
    """jarvis pipeline — смотрим на содержательные логи trim-hot.log / compress-warm.log."""
    base = HOME / ".claude-lab" / "jarvis" / "logs"
    files = ["trim-hot.log", "compress-warm.log"]
    items = []
    worst = "PASS"
    for fname in files:
        p = base / fname
        if not p.exists() or p.stat().st_size == 0:
            items.append({"file": fname, "status": "WARN", "note": "пустой/отсутствует"})
            if worst == "PASS":
                worst = "WARN"
            continue
        age_h = (NOW.timestamp() - p.stat().st_mtime) / 3600
        status = "PASS" if age_h <= 30 else "WARN"
        if status == "WARN" and worst == "PASS":
            worst = "WARN"
        items.append({"file": fname, "age_h": round(age_h, 1), "status": status})
    return {"name": "Memory rotation (jarvis)", "status": worst, "items": items}


def check_compact_window() -> dict:
    """CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000."""
    # ищем в системных env / .profile / .bashrc / settings.json
    sources = [
        HOME / ".bashrc",
        HOME / ".profile",
        HOME / ".claude" / "settings.json",
    ]
    found = []
    for s in sources:
        if not s.exists():
            continue
        try:
            txt = s.read_text()
            if "CLAUDE_CODE_AUTO_COMPACT_WINDOW" in txt:
                found.append(str(s))
        except Exception:
            pass
    if found:
        return {"name": "CLAUDE_CODE_AUTO_COMPACT_WINDOW set", "status": "PASS", "items": [{"sources": found}]}
    return {"name": "CLAUDE_CODE_AUTO_COMPACT_WINDOW set", "status": "WARN", "items": [{"note": "не выставлено — модель работает с 1M (дорого, склонна к 'эволюционированию')"}]}


def check_claude_md_size() -> dict:
    """CLAUDE.md ≤200 строк (эталон AgentOS)."""
    results = []
    worst = "PASS"
    for a in AGENTS + ["conductor"]:
        p = HOME / ".claude-lab" / a / ".claude" / "CLAUDE.md"
        if not p.exists():
            continue
        lines = sum(1 for _ in p.open())
        status = "PASS" if lines <= 200 else "WARN"
        if status == "WARN" and worst == "PASS":
            worst = "WARN"
        results.append({"agent": a, "lines": lines, "status": status})
    return {"name": "CLAUDE.md ≤200 строк", "status": worst, "items": results}


def check_recent_md_size() -> dict:
    """recent.md ≤50KB (WARN), ≤70KB (FAIL). Превышение ведёт к claude exit 1 на тяжёлых сессиях."""
    results = []
    worst = "PASS"
    for a in AGENTS + ["conductor"]:
        p = HOME / ".claude-lab" / a / ".claude" / "core" / "hot" / "recent.md"
        if not p.exists():
            continue
        size = p.stat().st_size
        if size > 70000:
            status = "FAIL"
        elif size > 50000:
            status = "WARN"
        else:
            status = "PASS"
        if status == "FAIL":
            worst = "FAIL"
        elif status == "WARN" and worst == "PASS":
            worst = "WARN"
        results.append({"agent": a, "bytes": size, "status": status})
    return {"name": "recent.md ≤50KB (warn) / ≤70KB (fail)", "status": worst, "items": results}


def check_session_jsonl_size() -> dict:
    """Active session jsonl ≤30MB (WARN), ≤50MB (FAIL). Большой jsonl ломает claude --resume → exit 1."""
    import json as _json
    results = []
    worst = "PASS"
    try:
        cfg = _json.load(open("/home/edgelab/claude-gateway/config.json"))
    except Exception:
        return {"name": "session.jsonl ≤30MB (warn) / ≤50MB (fail)", "status": "WARN", "items": [{"error": "no gateway config"}]}
    state_dir = HOME / "claude-gateway" / "state"
    for a in AGENTS + ["conductor"]:
        ws = cfg.get("agents", {}).get(a, {}).get("workspace", "")
        if not ws:
            continue
        pk = ws.replace("/", "-").replace(".", "-")
        for sf in state_dir.glob(f"sid-{a}-*.txt"):
            sid = sf.read_text().strip()
            if not sid:
                results.append({"agent": a, "size": "fresh", "status": "PASS"})
                continue
            jsonl = HOME / ".claude" / "projects" / pk / f"{sid}.jsonl"
            if not jsonl.exists():
                continue
            size = jsonl.stat().st_size
            if size > 50 * 1024 * 1024:
                status = "FAIL"
            elif size > 30 * 1024 * 1024:
                status = "WARN"
            else:
                status = "PASS"
            if status == "FAIL":
                worst = "FAIL"
            elif status == "WARN" and worst == "PASS":
                worst = "WARN"
            results.append({"agent": a, "bytes": size, "MB": f"{size//1048576}M", "status": status})
    return {"name": "session.jsonl ≤30MB (warn) / ≤50MB (fail)", "status": worst, "items": results}


CHECKS = [
    check_handoffs,
    check_gbrain_ports,
    check_gbrain_dualwrite,
    check_cron_logs,
    check_memory_rotation,
    check_compact_window,
    check_claude_md_size,
    check_recent_md_size,
    check_session_jsonl_size,
]


def main():
    json_out = "--json" in sys.argv
    results = [c() for c in CHECKS]

    if json_out:
        print(json.dumps({"ts": NOW.isoformat(), "checks": results}, ensure_ascii=False, indent=2))
        return

    icon = {"PASS": "✅", "WARN": "⚠️ ", "FAIL": "❌"}
    print(f"=== SYSTEM HEALTH — {NOW.strftime('%Y-%m-%d %H:%M МСК')} ===\n")
    summary = {"PASS": 0, "WARN": 0, "FAIL": 0}
    for r in results:
        summary[r["status"]] += 1
        print(f"{icon[r['status']]} {r['name']}: {r['status']}")
        for item in r.get("items", []):
            line = "    " + ", ".join(f"{k}={v}" for k, v in item.items())
            print(line)
        print()
    print(f"--- Итог: {summary['PASS']} PASS / {summary['WARN']} WARN / {summary['FAIL']} FAIL ---")


if __name__ == "__main__":
    main()

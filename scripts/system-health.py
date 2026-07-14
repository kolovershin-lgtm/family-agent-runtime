#!/usr/bin/env python3
"""system-health.py — самоаудит установки family-agent-runtime (VPS Андрея).

Адаптировано из seeds/system_health.py (эталон Ильи на 5 агентов) под реальную
схему Андрея: 3 системных пользователя-агента, сервисы systemd, 3 БД gbrain,
iptables. Пути и состав агентов вынесены в CONFIG (не хардкод — правило ТЗ №7),
при желании выносится в /etc/family-runtime/agents.json.

Проверки (P1-Задача 2):
  1. active gateways            — ожидаем 3
  2. active gbrain services     — ожидаем 12 (3 набора × 4)
  3. handoff freshness          — alert если mtime > 7 дней
  4. recent.md size             — alert если > 40KB
  5. iptables integrity         — 6 REJECT-правил
  6. delivery_outbox lag        — строк failed за 24ч (нужен доступ к БД)
  7. RAM available              — alert < 15%

Часть проверок (iptables, БД, чужие /home) требуют root — запускать через
`sudo system-health` (whitelist P0-Задачи 0). Без root они деградируют в WARN
с пометкой «нет доступа», а не падают.

Запуск: system-health.py [--json]
"""

import os
import sys
import json
import glob
import shutil
import subprocess
from datetime import datetime, timezone

NOW = datetime.now(timezone.utc).astimezone()

# --- Конфигурация установки (позже -> /etc/family-runtime/agents.json) ---
AGENTS = [
    {"slug": "andrei",   "user": "claudegw",   "gateway": "claude-gateway.service",
     "gbrain_prefix": "gbrain",          "db": "gbrain"},
    {"slug": "olya",     "user": "olyagw",     "gateway": "claude-gateway-olya.service",
     "gbrain_prefix": "gbrain-olya",     "db": "gbrain_olya"},
    {"slug": "marianna", "user": "mariannagw", "gateway": "claude-gateway-marianna.service",
     "gbrain_prefix": "gbrain-marianna", "db": "gbrain_marianna"},
]
GBRAIN_SUFFIXES = ["memory-mcp", "recall-mcp", "swarm-mcp", "ingest-worker"]
HANDOFF_GLOB = "/home/{user}/claude-lab/*/core/hot/handoff.md"
RECENT_GLOB = "/home/{user}/claude-lab/*/core/hot/recent.md"
HANDOFF_STALE_DAYS = 7
RECENT_MD_WARN_BYTES = 40 * 1024
IPTABLES_EXPECTED_REJECT = 6
RAM_WARN_PCT = 15

WORST_ORDER = {"PASS": 0, "WARN": 1, "FAIL": 2}


def worse(a, b):
    return a if WORST_ORDER[a] >= WORST_ORDER[b] else b


def fmt_ago(ts):
    delta = NOW.timestamp() - ts
    if delta < 3600:
        return f"{int(delta/60)}м"
    if delta < 86400:
        return f"{int(delta/3600)}ч"
    return f"{int(delta/86400)}д"


def _sysctl_active(unit):
    try:
        out = subprocess.run(["systemctl", "is-active", unit],
                             capture_output=True, text=True, timeout=8)
        return out.stdout.strip()
    except Exception as e:
        return f"err:{e}"


def check_gateways():
    items, worst = [], "PASS"
    active = 0
    for a in AGENTS:
        st = _sysctl_active(a["gateway"])
        ok = st == "active"
        active += ok
        if not ok:
            worst = "FAIL"
        items.append({"agent": a["slug"], "unit": a["gateway"],
                      "status": "PASS" if ok else "FAIL", "state": st})
    return {"name": f"Gateways активны ({active}/{len(AGENTS)})", "status": worst, "items": items}


def check_gbrain_services():
    items, worst = [], "PASS"
    active = 0
    total = len(AGENTS) * len(GBRAIN_SUFFIXES)
    for a in AGENTS:
        for suf in GBRAIN_SUFFIXES:
            unit = f"{a['gbrain_prefix']}-{suf}.service"
            st = _sysctl_active(unit)
            ok = st == "active"
            active += ok
            if not ok:
                worst = "FAIL"
                items.append({"unit": unit, "status": "FAIL", "state": st})
    if worst == "PASS":
        items.append({"note": f"все {total} активны"})
    return {"name": f"gbrain services ({active}/{total})", "status": worst, "items": items}


def check_handoff_freshness():
    items, worst = [], "PASS"
    for a in AGENTS:
        pattern = HANDOFF_GLOB.format(user=a["user"])
        try:
            matches = glob.glob(pattern)
        except Exception as e:
            matches = []
        if not matches:
            # нет доступа к чужому /home (не root) ИЛИ файла нет
            readable = os.access(f"/home/{a['user']}", os.R_OK)
            note = "нет доступа (нужен root)" if not readable else "handoff не найден"
            st = "WARN"
            items.append({"agent": a["slug"], "status": st, "note": note})
            worst = worse(worst, st)
            continue
        p = max(matches, key=lambda m: os.stat(m).st_mtime)
        age_days = (NOW.timestamp() - os.stat(p).st_mtime) / 86400
        st = "WARN" if age_days > HANDOFF_STALE_DAYS else "PASS"
        worst = worse(worst, st)
        items.append({"agent": a["slug"], "status": st,
                      "note": f"обновлён {fmt_ago(os.stat(p).st_mtime)} назад"})
    return {"name": f"Handoff свежесть (≤{HANDOFF_STALE_DAYS}д)", "status": worst, "items": items}


def check_recent_md_size():
    items, worst = [], "PASS"
    any_seen = False
    for a in AGENTS:
        try:
            matches = glob.glob(RECENT_GLOB.format(user=a["user"]))
        except Exception:
            matches = []
        for p in matches:
            any_seen = True
            size = os.stat(p).st_size
            st = "WARN" if size > RECENT_MD_WARN_BYTES else "PASS"
            worst = worse(worst, st)
            items.append({"agent": a["slug"], "kb": round(size/1024, 1), "status": st})
    if not any_seen:
        items.append({"note": "recent.md не найден (нет доступа или не используется)"})
    return {"name": f"recent.md ≤{RECENT_MD_WARN_BYTES//1024}KB", "status": worst, "items": items}


def check_iptables():
    try:
        out = subprocess.run(["iptables", "-S"], capture_output=True, text=True, timeout=8)
        if out.returncode != 0:
            return {"name": "iptables 6 REJECT", "status": "WARN",
                    "items": [{"note": "нет доступа (нужен root)"}]}
        n = sum(1 for ln in out.stdout.splitlines() if "REJECT" in ln)
        st = "PASS" if n == IPTABLES_EXPECTED_REJECT else "FAIL"
        return {"name": f"iptables REJECT ({n}/{IPTABLES_EXPECTED_REJECT})", "status": st,
                "items": [{"reject_rules": n}]}
    except Exception as e:
        return {"name": "iptables 6 REJECT", "status": "WARN", "items": [{"note": f"недоступно: {e}"}]}


def check_delivery_outbox_lag():
    items, worst = [], "PASS"
    if not shutil.which("psql"):
        return {"name": "delivery_outbox lag (24ч)", "status": "WARN",
                "items": [{"note": "psql недоступен"}]}
    for a in AGENTS:
        try:
            out = subprocess.run(
                ["sudo", "-n", "-u", "postgres", "psql", "-d", a["db"], "-tA", "-c",
                 "select count(*) from delivery_outbox where status='failed' "
                 "and created_at > now() - interval '24 hours';"],
                capture_output=True, text=True, timeout=10)
            if out.returncode != 0:
                items.append({"db": a["db"], "status": "WARN", "note": "нет доступа (нужен root)"})
                worst = worse(worst, "WARN")
                continue
            cnt = int((out.stdout.strip() or "0"))
            st = "PASS" if cnt == 0 else "WARN"
            worst = worse(worst, st)
            items.append({"db": a["db"], "failed_24h": cnt, "status": st})
        except Exception as e:
            items.append({"db": a["db"], "status": "WARN", "note": str(e)[:40]})
            worst = worse(worst, "WARN")
    return {"name": "delivery_outbox failed (24ч)", "status": worst, "items": items}


def check_ram():
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for ln in f:
                k, v = ln.split(":")
                info[k] = int(v.strip().split()[0])  # kB
        total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", 0)
        pct = round(avail / total * 100, 1) if total else 0
        st = "WARN" if pct < RAM_WARN_PCT else "PASS"
        return {"name": f"RAM свободно ({pct}%)", "status": st,
                "items": [{"avail_mb": avail // 1024, "total_mb": total // 1024, "pct": pct}]}
    except Exception as e:
        return {"name": "RAM свободно", "status": "WARN", "items": [{"note": str(e)}]}


CHECKS = [
    check_gateways,
    check_gbrain_services,
    check_handoff_freshness,
    check_recent_md_size,
    check_iptables,
    check_delivery_outbox_lag,
    check_ram,
]


def main():
    json_out = "--json" in sys.argv
    results = [c() for c in CHECKS]
    overall = "PASS"
    for r in results:
        overall = worse(overall, r["status"])

    if json_out:
        print(json.dumps({"ts": NOW.isoformat(), "overall": overall, "checks": results},
                         ensure_ascii=False, indent=2))
        return 0 if overall != "FAIL" else 1

    icon = {"PASS": "[OK]", "WARN": "[!]", "FAIL": "[X]"}
    print(f"=== SYSTEM HEALTH — {NOW.strftime('%Y-%m-%d %H:%M %Z')} ===\n")
    summary = {"PASS": 0, "WARN": 0, "FAIL": 0}
    for r in results:
        summary[r["status"]] += 1
        print(f"{icon[r['status']]} {r['name']}: {r['status']}")
        for item in r.get("items", []):
            print("    " + ", ".join(f"{k}={v}" for k, v in item.items()))
    print(f"\n--- Итог: {summary['PASS']} PASS / {summary['WARN']} WARN / {summary['FAIL']} FAIL "
          f"→ {overall} ---")
    return 0 if overall != "FAIL" else 1


if __name__ == "__main__":
    sys.exit(main())

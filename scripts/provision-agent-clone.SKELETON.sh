#!/usr/bin/env bash
# provision-agent-clone — one-shot provisioner for a new family agent.
# Runs as root via sudo NOPASSWD whitelist (see docs/sudoers-example).
#
# SKELETON. AVA fills in the TODO blocks by mirroring the pattern that Boss
# used to provision Olya (2026-06-19) and Eva (2026-07-10).
# Both live examples are on the VPS:
#   - /etc/gbrain-olya/          /etc/gbrain-marianna/
#   - /opt/claude-gateway-olya/  /opt/claude-gateway-marianna/
#   - /etc/systemd/system/gbrain-{olya,marianna}-*.service
#   - /etc/systemd/system/claude-gateway-{olya,marianna}.service
#
# AVA reference runbook: gbrain vault → 70-runbooks/provisioning-new-agent.md
# (to be written as part of TASK-FOR-AVA.md step 3).
#
# Usage:
#   sudo provision-agent-clone --name <slug> --tg-id <telegram_id> \
#        --owner "<full name>" --tone "<tone one-liner>" \
#        [--allow-extra-id <id> ...] [--apply]
#
# Without --apply the script prints the plan and exits (dry-run default).

set -euo pipefail

# ---- Config (edit at install time) -----------------------------------------
readonly PORT_POOL_START=8871        # search here upward for a free triplet
readonly MAX_AGENTS=5                # hard cap to protect VPS RAM
readonly MIN_AVAIL_RAM_MB=400        # refuse if VPS has less than this free
readonly TEMPLATE_DIR=/opt/family-runtime/templates
readonly SEED_DIR=/opt/family-runtime/seeds
readonly LOG=/var/log/agent-provisioning.log

# ---- Arg parsing (STRICT) --------------------------------------------------
# Enforce name regex ^[a-z][a-z0-9]{2,15}$ before ANY substitution.
# Fail early if bot token file missing at /home/claudegw/secrets/<slug>-bot.
# Fail if slug/uid/ports/db already exist.

# TODO: implement arg parsing here.

# ---- Precondition checks ---------------------------------------------------
# 1. Count active agents (sysusers matching *gw) < MAX_AGENTS
# 2. `free -m` available > MIN_AVAIL_RAM_MB
# 3. Bot token file exists (do NOT read its content)
# 4. Owner-provided CLAUDE.md at $TEMPLATE_DIR/persona-<slug>.md
# 5. Free port triplet in PORT_POOL_START..+3

# TODO: implement checks.

# ---- Plan output (dry-run always shows this) -------------------------------
# Print the ordered list of actions with the resolved values (slug, uid,
# ports, db name). No mutation until --apply is on.

# TODO: implement plan printer.

if [[ "${APPLY:-0}" != "1" ]]; then
    echo "DRY-RUN: pass --apply to execute."
    exit 0
fi

# ---- Execution steps -------------------------------------------------------
# Each step must be idempotent and rollback-friendly. On failure at step N,
# invoke deprovision-agent-clone <slug> to clean up steps 1..N-1.

trap 'echo "ERROR at line $LINENO — rolling back"; /usr/local/sbin/deprovision-agent-clone "${SLUG:-unknown}" --force || true' ERR

# Step 1: useradd + akhmetovfam group + home 700
# Step 2: createdb + clone schema (pg_dump -s | psql) + create agent_tokens row
# Step 3: /etc/gbrain-<slug>/secrets.env + directories + fastembed cache (cp -a from seed)
# Step 4: 4 systemd units (gbrain-<slug>-{memory,recall,swarm,ingest}) + daemon-reload + enable --now
# Step 5: iptables — for every OTHER active agent uid, add REJECT --uid-owner rules in both directions
#         netfilter-persistent save
# Step 6: /opt/claude-gateway-<slug>/ + config.json (from template) + gateway.py symlink + logs/ + state/ + media-inbound/
#         chown to <sysuser>. unit + enable --now.
# Step 7: /home/<sysuser>/claude-lab/<slug>/.claude/{CLAUDE.md,.mcp.json}
#         + copy Claude credentials from seed (Max OAuth token)
# Step 8: verify — 4/4 gbrain active, gateway active, getMe OK,
#         cross-token matrix (foreign token → 401), cross-uid iptables matrix (foreign uid → tcp-reset)
# Step 9: audit line to $LOG

# TODO: implement steps 1-9. Each should print `[STEP N] <what>` before doing it.

echo "OK — agent '${SLUG}' provisioned. Owner writes /start to @${BOT_USERNAME}."

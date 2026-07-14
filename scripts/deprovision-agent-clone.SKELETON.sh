#!/usr/bin/env bash
# deprovision-agent-clone — reverse of provision-agent-clone.
# Removes: gateway unit, gbrain units, iptables rules, DB, sysuser, dirs.
# SKELETON. AVA fills in TODO blocks.
#
# Safety: refuses to touch existing production agents unless --force is given.
# By default asks the caller to type the slug to confirm.

set -euo pipefail

# TODO:
# 1. Parse args: <slug> [--force]
# 2. Refuse if slug is not in a "known family agent" list (read from
#    /var/lib/family-runtime/agents.list, updated by provision on success)
# 3. Ordered teardown (reverse of provisioner):
#    a. systemctl disable --now claude-gateway-<slug>, gbrain-<slug>-*
#    b. remove /etc/systemd/system/{gbrain-<slug>-*,claude-gateway-<slug>}.service
#    c. daemon-reload
#    d. iptables -D lines matching --uid-owner <uid> and --dport <ports>
#       (both directions), netfilter-persistent save
#    e. dropdb gbrain_<slug>  (WARN: destroys their memory — require --force)
#    f. rm -rf /opt/{gbrain-<slug>,claude-gateway-<slug>} /etc/gbrain-<slug> /var/log/gbrain-<slug> /var/lib/gbrain-<slug>
#    g. userdel -r <slug>gw   (WARN: wipes their home — require --force)
#    h. audit line to /var/log/agent-provisioning.log

echo "not implemented yet — see SKELETON comments"
exit 1

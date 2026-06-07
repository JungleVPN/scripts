#!/usr/bin/env bash
# =============================================================================
# na_protect.sh — Node Accelerator: nftables firewall + CrowdSec IPS
#
# Runs protect.sh from https://github.com/jestivald/node-accelerator
# Sets up: nftables na_filter table (coexists with UFW/Docker/CrowdSec),
#          anti-scan, flag-drop, SYN/UDP flood limits, per-IP connlimit,
#          SSH connect-flood ban, portscan autoban.
#          CrowdSec + firewall-bouncer for community blocklists.
#
# ⚠ Does NOT flush existing ruleset — manages only its own inet na_filter table.
#   Safe to run alongside UFW and Docker NAT rules.
#
# ENV overrides (all optional):
#   SSH_PORT, TCP_PORTS, UDP_PORTS, NODE_PORT, WHITELIST
#   ENABLE_CROWDSEC=0  to skip CrowdSec install
#
# Usage (standalone):
#   bash na_protect.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/na_protect.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

NA_REPO="https://raw.githubusercontent.com/jestivald/node-accelerator/main"

clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║        The Jungle — Node Accelerator: Protect          ║
  ║      nftables · autoban · CrowdSec IPS · anti-scan     ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "$SEP"
warn "A safety timer will auto-remove the firewall table after 300s."
warn "You will be asked to confirm SSH still works before it is disarmed."
warn "Coexists with UFW and Docker — does NOT flush existing rules."
echo -e "$SEP"
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Fetching node-accelerator protect..."
mkdir -p "$TMPDIR/scripts/lib"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/lib/common.sh" \
    -o "$TMPDIR/scripts/lib/common.sh"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/protect.sh" \
    -o "$TMPDIR/scripts/protect.sh"
chmod +x "$TMPDIR/scripts/protect.sh"

bash "$TMPDIR/scripts/protect.sh"

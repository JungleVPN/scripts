#!/usr/bin/env bash
# =============================================================================
# na_optimize.sh — Node Accelerator: full VPS optimization
#
# Runs optimize.sh from https://github.com/jestivald/node-accelerator
# Applies: XanMod kernel (BBRv3), sysctl, RPS/RFS/XPS, file limits,
#          NIC tuning, swap, THP off, CPU governor, irqbalance.
#
# ⚠ XanMod kernel install requires a REBOOT to activate BBRv3.
#   Skip with: ENABLE_XANMOD=0 bash na_optimize.sh
#
# Usage (standalone):
#   bash na_optimize.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/na_optimize.sh)
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
  ║        The Jungle — Node Accelerator: Optimize         ║
  ║   XanMod kernel · sysctl · RPS · limits · THP · swap   ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "$SEP"
warn "XanMod kernel will be installed — a REBOOT is required afterwards."
warn "To skip kernel install: ENABLE_XANMOD=0 bash na_optimize.sh"
echo -e "$SEP"
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Fetching node-accelerator optimize..."
mkdir -p "$TMPDIR/scripts/lib"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/lib/common.sh" \
    -o "$TMPDIR/scripts/lib/common.sh"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/optimize.sh" \
    -o "$TMPDIR/scripts/optimize.sh"
chmod +x "$TMPDIR/scripts/optimize.sh"

bash "$TMPDIR/scripts/optimize.sh"

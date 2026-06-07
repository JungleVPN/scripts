#!/usr/bin/env bash
# =============================================================================
# na_diagnose.sh — Node Accelerator: read-only node diagnostics
#
# Runs diagnose.sh from https://github.com/jestivald/node-accelerator
# Checks: kernel/BBR, sysctl, limits, conntrack, NIC/RPS, firewall, CrowdSec
# Prints ✔/▲/✘ summary with recommendations. Makes NO changes.
#
# Usage (standalone):
#   bash na_diagnose.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/na_diagnose.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }

NA_REPO="https://raw.githubusercontent.com/jestivald/node-accelerator/main"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Fetching node-accelerator diagnose..."
mkdir -p "$TMPDIR/scripts/lib"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/lib/common.sh" \
    -o "$TMPDIR/scripts/lib/common.sh"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/diagnose.sh" \
    -o "$TMPDIR/scripts/diagnose.sh"
chmod +x "$TMPDIR/scripts/diagnose.sh"

bash "$TMPDIR/scripts/diagnose.sh"

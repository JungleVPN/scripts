#!/usr/bin/env bash
# =============================================================================
# remnanode.sh — RemnaNode install via DigneZzZ script
#
# Usage (standalone):
#   bash remnanode.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/remnanode.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$*${NC}"; }

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║              The Jungle — RemnaNode                    ║
  ║           Remnawave node installation                  ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN}1.${NC} Run the ${CYAN}RemnaNode${NC} installer (DigneZzZ)"
echo -e "$SEP"
echo ""
warn "The RemnaNode installer has its own interactive prompts."
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Execute ───────────────────────────────────────────────────────────────────

step "Installing RemnaNode"
curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh | bash -s -- @ install

echo ""
echo -e "$SEP"
info "RemnaNode installation complete."
echo -e "$SEP"

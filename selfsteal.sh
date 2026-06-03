#!/usr/bin/env bash
# =============================================================================
# selfsteal.sh — Caddy-based Reality traffic masking (selfsteal)
#
# Usage (standalone):
#   bash selfsteal.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/selfsteal.sh)
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
  ║              The Jungle — selfsteal                    ║
  ║         Caddy-based Reality traffic masking            ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN}1.${NC} Run the ${CYAN}selfsteal${NC} installer (DigneZzZ)"
echo -e "       Caddy reverse proxy masking VLESS Reality traffic"
echo -e "$SEP"
echo ""
warn "The selfsteal installer has its own interactive prompts."
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Execute ───────────────────────────────────────────────────────────────────

step "Installing selfsteal"
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install

echo ""
echo -e "$SEP"
info "selfsteal setup complete."
echo -e "$SEP"

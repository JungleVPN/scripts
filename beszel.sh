#!/usr/bin/env bash
# =============================================================================
# beszel.sh — Beszel monitoring agent + MOTD banner
#
# Usage (standalone):
#   bash beszel.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/beszel.sh)
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
  ║              The Jungle — Beszel + MOTD                ║
  ║         monitoring agent · login banner                ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN}1.${NC} Create ${CYAN}/opt/beszel/compose.yml${NC}"
echo -e "   ${CYAN}2.${NC} Install ${CYAN}MOTD${NC} login banner (distillium)"
echo -e "$SEP"
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Execute ───────────────────────────────────────────────────────────────────

step "Creating Beszel directory"
mkdir -p /opt/beszel
touch /opt/beszel/compose.yml
info "Created /opt/beszel/compose.yml"

step "Installing MOTD banner"
curl -fsSL https://raw.githubusercontent.com/distillium/motd/main/install-motd.sh | bash

echo ""
echo -e "$SEP"
info "Beszel + MOTD setup complete."
echo -e "$SEP"

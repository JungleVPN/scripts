#!/usr/bin/env bash
# =============================================================================
# node_setup.sh — VPS node hardening: apt, SSH
# Firewall is handled by na_protect.sh (nftables).
#
# Usage (standalone):
#   bash node_setup.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/node_setup.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$*${NC}"; }

JUNGLE_ENV="/etc/profile.d/jungle-node.sh"

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║             The Jungle — Node Setup                    ║
  ║              apt update · SSH hardening                ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Load saved vars ───────────────────────────────────────────────────────────
[[ -f "$JUNGLE_ENV" ]] && source "$JUNGLE_ENV"

# ── Collect all inputs upfront ────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  Configuration — defaults shown in brackets${NC}"
echo -e "$SEP"
echo ""

read -rp "  SSH port         [${JUNGLE_SSH_PORT:-1702}]:           " _v; SSH_PORT="${_v:-${JUNGLE_SSH_PORT:-1702}}"
read -rp "  Panel IP         [${JUNGLE_PANEL_IP:-}]:  "              _v; PANEL_IP="${_v:-${JUNGLE_PANEL_IP:-}}"
read -rp "  Beszel port      [${JUNGLE_BESZEL_PORT:-45876}]:          " _v; BESZEL_PORT="${_v:-${JUNGLE_BESZEL_PORT:-45876}}"
read -rp "  Node port        [${JUNGLE_NODE_PORT:-2222}]:           "  _v; NODE_PORT="${_v:-${JUNGLE_NODE_PORT:-2222}}"
read -rp "  XHTTP port       [${JUNGLE_XHTTP_PORT:-8443}]:           " _v; XHTTP_PORT="${_v:-${JUNGLE_XHTTP_PORT:-8443}}"
read -rp "  gRPC port        [${JUNGLE_GRPC_PORT:-9443}]:           "  _v; GRPC_PORT="${_v:-${JUNGLE_GRPC_PORT:-9443}}"

echo ""
echo -e "$SEP"
echo -e "${BOLD}  Summary${NC}"
echo -e "$SEP"
echo -e "  SSH_PORT    = ${CYAN}$SSH_PORT${NC}"
echo -e "  PANEL_IP    = ${CYAN}$PANEL_IP${NC}"
echo -e "  BESZEL_PORT = ${CYAN}$BESZEL_PORT${NC}"
echo -e "  NODE_PORT   = ${CYAN}$NODE_PORT${NC}"
echo -e "  XHTTP_PORT  = ${CYAN}$XHTTP_PORT${NC}"
echo -e "  GRPC_PORT   = ${CYAN}$GRPC_PORT${NC}"
echo -e "$SEP"
echo ""
warn "Firewall is configured separately via Node Accelerator → Protect."
echo ""
read -rp "Start node setup? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

SSHD_CONFIG="/etc/ssh/sshd_config"

# ── Execute ───────────────────────────────────────────────────────────────────

step "Saving config to $JUNGLE_ENV"
mkdir -p /etc/profile.d
sed -i '/# === jungle-init ===/,/# === \/jungle-init ===/d' "$JUNGLE_ENV" 2>/dev/null || true
cat >> "$JUNGLE_ENV" <<EOF
# === jungle-init ===
export JUNGLE_SSH_PORT="${SSH_PORT}"
export JUNGLE_PANEL_IP="${PANEL_IP}"
export JUNGLE_BESZEL_PORT="${BESZEL_PORT}"
export JUNGLE_NODE_PORT="${NODE_PORT}"
export JUNGLE_XHTTP_PORT="${XHTTP_PORT}"
export JUNGLE_GRPC_PORT="${GRPC_PORT}"
# === /jungle-init ===
EOF
info "Saved"

step "Updating system packages"
apt update -y
apt upgrade -y

step "Installing required packages"
apt install -y curl unattended-upgrades

step "Enabling unattended upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades

step "Switching SSH socket → service"
systemctl stop ssh.socket    || true
systemctl disable ssh.socket || true
systemctl enable ssh.service
systemctl restart ssh.service

step "Hardening SSH (port $SSH_PORT, password auth off)"
sed -i "s/#Port 22/Port $SSH_PORT/"    "$SSHD_CONFIG"
sed -i "s/Port 22/Port $SSH_PORT/"     "$SSHD_CONFIG"
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" "$SSHD_CONFIG"
sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/"  "$SSHD_CONFIG"
systemctl restart ssh

echo ""
echo -e "$SEP"
info "Node setup complete. SSH is now on port ${BOLD}$SSH_PORT${NC}."
warn "Run Node Accelerator → Protect (option 7) to configure the firewall."
echo -e "$SEP"

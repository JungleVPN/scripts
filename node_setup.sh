#!/usr/bin/env bash
# =============================================================================
# node_setup.sh — VPS node hardening: apt, SSH, UFW
#
# Usage (standalone):
#   bash node_setup.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/RamazanIttiev/jungle-scripts/main/node_setup.sh)
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
  ║             The Jungle — Node Setup                    ║
  ║       apt update · SSH hardening · UFW firewall        ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Collect all inputs upfront ────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  Configuration — defaults shown in brackets${NC}"
echo -e "$SEP"
echo ""

read -rp "  SSH port         [1702]:           " SSH_PORT;    SSH_PORT="${SSH_PORT:-1702}"
read -rp "  Panel IP         [144.31.196.234]: " PANEL_IP;    PANEL_IP="${PANEL_IP:-144.31.196.234}"
read -rp "  Beszel port      [45876]:          " BESZEL_PORT; BESZEL_PORT="${BESZEL_PORT:-45876}"
read -rp "  Node port        [2222]:           " NODE_PORT;   NODE_PORT="${NODE_PORT:-2222}"
read -rp "  XHTTP port       [8443]:           " XHTTP_PORT;  XHTTP_PORT="${XHTTP_PORT:-8443}"
read -rp "  gRPC port        [9443]:           " GRPC_PORT;   GRPC_PORT="${GRPC_PORT:-9443}"

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
read -rp "Start node setup? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

SSHD_CONFIG="/etc/ssh/sshd_config"

# ── Execute ───────────────────────────────────────────────────────────────────

step "Updating system packages"
apt update -y
apt upgrade -y

step "Installing required packages"
apt install -y ufw curl unattended-upgrades

step "Enabling unattended upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades

step "Switching SSH socket → service"
systemctl stop ssh.socket   || true
systemctl disable ssh.socket || true
systemctl enable ssh.service
systemctl restart ssh.service

step "Hardening SSH (port $SSH_PORT, password auth off)"
sed -i "s/#Port 22/Port $SSH_PORT/"    "$SSHD_CONFIG"
sed -i "s/Port 22/Port $SSH_PORT/"     "$SSHD_CONFIG"
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" "$SSHD_CONFIG"
sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/"  "$SSHD_CONFIG"
systemctl restart ssh

step "Configuring UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"                                         # SSH
ufw allow 80/tcp                                                  # HTTP
ufw allow 443/tcp                                                 # VPN HTTPS
ufw allow 443                                                     # VPN UDP
ufw allow "$BESZEL_PORT/tcp"                                      # Beszel monitoring
ufw allow "$XHTTP_PORT/tcp"                                       # XHTTP
ufw allow "$GRPC_PORT/tcp"                                        # gRPC
ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp     # Panel → node
ufw --force enable

echo ""
echo -e "$SEP"
info "Node setup complete. SSH is now on port ${BOLD}$SSH_PORT${NC}."
echo -e "$SEP"

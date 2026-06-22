#!/usr/bin/env bash
# =============================================================================
# node_setup.sh — VPS node hardening: apt, SSH, UFW firewall
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║             The Jungle — Node Setup                    ║
  ║         apt update · SSH hardening · UFW               ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Load saved vars ───────────────────────────────────────────────────────────
[[ -f "$JUNGLE_ENV" ]] && source "$JUNGLE_ENV"

# ── Collect all inputs upfront ────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/node_config.sh"
collect_node_config
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
apt install -y curl unattended-upgrades ufw

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

step "Configuring UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Core ports
ufw allow "$SSH_PORT/tcp"    comment 'SSH'
ufw allow 80/tcp             comment 'HTTP'
ufw allow 443/tcp            comment 'HTTPS'
ufw allow 443/udp            comment 'HTTPS/UDP'
ufw allow "$XHTTP_PORT/tcp"  comment 'XHTTP'
ufw allow "$GRPC_PORT/tcp"   comment 'gRPC'
ufw allow "$BESZEL_PORT/tcp" comment 'Beszel'

# Node port — restrict to panel IP if provided
if [[ -n "$PANEL_IP" ]]; then
    ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'Node (panel only)'
else
    ufw allow "$NODE_PORT/tcp" comment 'Node'
    warn "No PANEL_IP set — NODE_PORT $NODE_PORT is open to everyone"
fi

ufw --force enable
ufw status verbose

echo ""
echo -e "$SEP"
info "Node setup complete."
info "SSH is now on port ${BOLD}$SSH_PORT${NC}."
info "Firewall is active (UFW)."
echo -e "$SEP"

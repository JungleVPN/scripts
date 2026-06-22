#!/usr/bin/env bash
# =============================================================================
# na_protect.sh — UFW firewall + CrowdSec IPS
#
# Port config is loaded from /etc/profile.d/jungle-node.sh (saved by
# node_setup.sh) — prompts only for values that are missing.
#
# Ports opened:
#   TCP — SSH, 80, 443, XHTTP, gRPC, Beszel
#   UDP — 443
#   NODE_PORT — restricted to PANEL_IP (whitelist)
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
step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$*${NC}"; }

JUNGLE_SCRIPTS_REPO="https://raw.githubusercontent.com/JungleVPN/scripts/main"
JUNGLE_ENV="/etc/profile.d/jungle-node.sh"

[[ $EUID -eq 0 ]] || { echo -e "${RED}[ERROR]${NC} Run as root." >&2; exit 1; }

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║        The Jungle — Node Accelerator: Protect          ║
  ║          UFW firewall · CrowdSec IPS · anti-scan       ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Load saved vars ───────────────────────────────────────────────────────────
[[ -f "$JUNGLE_ENV" ]] && source "$JUNGLE_ENV"

# ── Resolve lib ───────────────────────────────────────────────────────────────
_local_lib="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)/lib/node_config.sh"
if [[ -f "$_local_lib" ]]; then
    source "$_local_lib"
else
    _tmp_lib="$(mktemp)"
    curl -Ls "$JUNGLE_SCRIPTS_REPO/lib/node_config.sh" -o "$_tmp_lib"
    trap "rm -f $_tmp_lib" EXIT
    source "$_tmp_lib"
fi
collect_node_config

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  UFW rules summary${NC}"
echo -e "$SEP"
echo -e "  SSH         = ${CYAN}$SSH_PORT/tcp${NC}"
echo -e "  HTTP/HTTPS  = ${CYAN}80/tcp · 443/tcp · 443/udp${NC}"
echo -e "  XHTTP       = ${CYAN}$XHTTP_PORT/tcp${NC}"
echo -e "  gRPC        = ${CYAN}$GRPC_PORT/tcp${NC}"
echo -e "  Beszel      = ${CYAN}$BESZEL_PORT/tcp${NC}"
echo -e "  NODE_PORT   = ${CYAN}$NODE_PORT/tcp${NC}  (panel-only: $PANEL_IP)"
echo -e "$SEP"
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Repair any interrupted dpkg state ────────────────────────────────────────
info "Checking package manager state..."
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

# ── UFW ───────────────────────────────────────────────────────────────────────
step "Installing UFW"
apt-get install -y ufw

step "Configuring UFW rules"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow "$SSH_PORT/tcp"   comment 'SSH'
ufw allow 80/tcp            comment 'HTTP'
ufw allow 443/tcp           comment 'HTTPS'
ufw allow 443/udp           comment 'HTTPS/UDP'
ufw allow "$XHTTP_PORT/tcp" comment 'XHTTP'
ufw allow "$GRPC_PORT/tcp"  comment 'gRPC'
ufw allow "$BESZEL_PORT/tcp" comment 'Beszel'

if [[ -n "${PANEL_IP:-}" ]]; then
    ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'Node (panel only)'
else
    ufw allow "$NODE_PORT/tcp" comment 'Node'
    warn "No PANEL_IP set — NODE_PORT $NODE_PORT is open to everyone"
fi

ufw --force enable
ufw status verbose

# ── CrowdSec ──────────────────────────────────────────────────────────────────
step "Installing CrowdSec"
curl -Ls https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt-get install -y crowdsec crowdsec-firewall-bouncer-ufw

step "Enrolling CrowdSec collections"
cscli collections install crowdsecurity/linux || true
cscli collections install crowdsecurity/sshd  || true
systemctl enable --now crowdsec
systemctl restart crowdsec-firewall-bouncer || true

echo ""
echo -e "$SEP"
info "Firewall active (UFW) + CrowdSec IPS running."
echo -e "$SEP"

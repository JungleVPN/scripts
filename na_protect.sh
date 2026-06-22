#!/usr/bin/env bash
# =============================================================================
# na_protect.sh — nftables firewall + CrowdSec IPS
#
# Wraps protect.sh from https://github.com/jestivald/node-accelerator
# Port config is loaded from /etc/profile.d/jungle-node.sh (saved by
# node_setup.sh) — prompts only for values that are missing.
#
# Replaces UFW: disables and removes ufw after protect.sh completes.
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

NA_REPO="https://raw.githubusercontent.com/jestivald/node-accelerator/main"
JUNGLE_SCRIPTS_REPO="https://raw.githubusercontent.com/JungleVPN/scripts/main"
JUNGLE_ENV="/etc/profile.d/jungle-node.sh"

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║        The Jungle — Node Accelerator: Protect          ║
  ║      nftables · autoban · CrowdSec IPS · anti-scan     ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Load saved vars ───────────────────────────────────────────────────────────
[[ -f "$JUNGLE_ENV" ]] && source "$JUNGLE_ENV"

# ── Collect all inputs upfront ────────────────────────────────────────────────
_local_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/node_config.sh"
if [[ -f "$_local_lib" ]]; then
    source "$_local_lib"
else
    source <(curl -Ls "$JUNGLE_SCRIPTS_REPO/lib/node_config.sh")
fi
collect_node_config

# Build protect.sh ENV vars
TCP_PORTS="80,443,${XHTTP_PORT},${GRPC_PORT},${BESZEL_PORT}"
UDP_PORTS="443"
WHITELIST="${PANEL_IP}"

echo -e "$SEP"
echo -e "${BOLD}  nftables rules summary${NC}"
echo -e "$SEP"
echo -e "  SSH             = ${CYAN}$SSH_PORT/tcp${NC}"
echo -e "  TCP_PORTS       = ${CYAN}$TCP_PORTS${NC}"
echo -e "  UDP_PORTS       = ${CYAN}$UDP_PORTS${NC}"
echo -e "  NODE_PORT       = ${CYAN}$NODE_PORT/tcp${NC}  (panel-only via whitelist)"
echo -e "  WHITELIST       = ${CYAN}$PANEL_IP${NC}"
echo -e "$SEP"
echo ""
warn "A 300s safety timer will auto-remove the firewall if SSH breaks."
warn "You will be asked to confirm SSH still works before it is disarmed."
warn "Coexists with Docker — does NOT flush existing nftables rules."
echo ""
read -rp "Proceed? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Repair any interrupted dpkg state ────────────────────────────────────────
info "Checking package manager state..."
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

# ── Fetch and run protect.sh with pre-filled ENV ──────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Fetching node-accelerator protect..."
mkdir -p "$TMPDIR/scripts/lib"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/lib/common.sh" \
    -o "$TMPDIR/scripts/lib/common.sh"
curl -Ls -H 'Cache-Control: no-cache' "$NA_REPO/scripts/protect.sh" \
    -o "$TMPDIR/scripts/protect.sh"
chmod +x "$TMPDIR/scripts/protect.sh"

# Export vars — protect.sh will show these as defaults in its prompts
# so the user just presses Enter to confirm each one.
export SSH_PORT TCP_PORTS UDP_PORTS UDP_PORTS NODE_PORT WHITELIST

bash "$TMPDIR/scripts/protect.sh"


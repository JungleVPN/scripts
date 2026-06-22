#!/usr/bin/env bash
# =============================================================================
# nft_ports.sh — Manage UFW firewall rules
#
# Usage (standalone):
#   bash nft_ports.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/nft_ports.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
pause() { echo ""; read -rp "  Press Enter to continue..." _; }

[[ $EUID -eq 0 ]] || die "Run as root."
command -v ufw &>/dev/null || die "UFW not installed. Run na_protect.sh first."

# ── List ──────────────────────────────────────────────────────────────────────
cmd_list() {
    echo ""
    echo -e "$SEP"
    echo -e "${BOLD}  UFW rules (numbered)${NC}"
    echo -e "$SEP"
    ufw status numbered
    echo -e "$SEP"
    echo ""
}

# ── Add plain port ────────────────────────────────────────────────────────────
cmd_add_port() {
    read -rp "  Protocol [tcp/udp, default tcp]: " _proto
    _proto="${_proto:-tcp}"
    [[ "$_proto" == "tcp" || "$_proto" == "udp" ]] || die "Protocol must be tcp or udp."

    read -rp "  Port: " _port
    [[ "$_port" =~ ^[0-9]+$ ]] || die "Invalid port number."

    read -rp "  Comment (optional): " _comment

    if [[ -n "${_comment:-}" ]]; then
        ufw allow "$_port/$_proto" comment "$_comment"
    else
        ufw allow "$_port/$_proto"
    fi
    info "Opened $_proto/$_port"
}

# ── Add port restricted to a source IP ───────────────────────────────────────
cmd_add_port_ip() {
    read -rp "  Protocol [tcp/udp, default tcp]: " _proto
    _proto="${_proto:-tcp}"
    [[ "$_proto" == "tcp" || "$_proto" == "udp" ]] || die "Protocol must be tcp or udp."

    read -rp "  Port: " _port
    [[ "$_port" =~ ^[0-9]+$ ]] || die "Invalid port number."

    read -rp "  Allowed source IP: " _ip
    [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$ ]] || die "Invalid IP address."

    read -rp "  Comment (optional): " _comment

    if [[ -n "${_comment:-}" ]]; then
        ufw allow from "$_ip" to any port "$_port" proto "$_proto" comment "$_comment"
    else
        ufw allow from "$_ip" to any port "$_port" proto "$_proto"
    fi
    info "Opened $_proto/$_port for $_ip only"
}

# ── Remove rule ───────────────────────────────────────────────────────────────
cmd_remove() {
    echo ""
    ufw status numbered
    echo ""
    read -rp "  Rule number to delete: " _num
    [[ "$_num" =~ ^[0-9]+$ ]] || die "Invalid rule number."
    ufw --force delete "$_num"
    info "Rule $_num deleted"
}

# ── Menu ──────────────────────────────────────────────────────────────────────
while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — Firewall Port Manager           ║
  ║                         UFW                            ║
  ╚════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    echo -e "$SEP"
    echo -e "   ${CYAN}1)${NC} List rules"
    echo -e "   ${CYAN}2)${NC} Open port             — allow a port for everyone"
    echo -e "   ${CYAN}3)${NC} Open port for one IP  — restrict port to a specific source IP"
    echo -e "   ${CYAN}4)${NC} Remove rule           — delete by rule number"
    echo -e "$SEP"
    echo -e "   ${CYAN}0)${NC} Exit"
    echo -e "$SEP"
    echo ""
    read -rp "Choice: " _c

    case "$_c" in
        1) cmd_list;         pause ;;
        2) cmd_add_port;     pause ;;
        3) cmd_add_port_ip;  pause ;;
        4) cmd_remove;       pause ;;
        0) exit 0 ;;
        *) warn "Invalid choice." ; pause ;;
    esac
done

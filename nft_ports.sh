#!/usr/bin/env bash
# =============================================================================
# nft_ports.sh — Manage ports in the na_filter nftables table
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

TABLE="inet na_filter"
CHAIN="input"
NFT_CONF="/etc/nftables.conf"

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root."
}

require_table() {
    nft list table $TABLE &>/dev/null || die "Table '$TABLE' not found. Run na_protect.sh first."
}

save_ruleset() {
    nft list ruleset > "$NFT_CONF"
    info "Saved to $NFT_CONF"
}

# ── List ──────────────────────────────────────────────────────────────────────
cmd_list() {
    echo ""
    echo -e "$SEP"
    echo -e "${BOLD}  Open ports in $TABLE ($CHAIN)${NC}"
    echo -e "$SEP"
    nft -a list chain $TABLE $CHAIN 2>/dev/null \
        | grep -E 'dport|saddr' \
        | sed 's/^/  /' \
        | sed "s/accept/${GREEN}accept${NC}/g" \
        | sed "s/drop/${RED}drop${NC}/g"
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

    nft add rule $TABLE $CHAIN $_proto dport $_port accept
    save_ruleset
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

    nft add rule $TABLE $CHAIN ip saddr $_ip $_proto dport $_port accept
    save_ruleset
    info "Opened $_proto/$_port for $_ip only"
}

# ── Remove port ───────────────────────────────────────────────────────────────
cmd_remove() {
    echo ""
    echo -e "${BOLD}  Current rules with handles:${NC}"
    echo ""
    nft -a list chain $TABLE $CHAIN 2>/dev/null | grep -E 'dport|saddr' | sed 's/^/  /'
    echo ""

    read -rp "  Handle number to delete: " _handle
    [[ "$_handle" =~ ^[0-9]+$ ]] || die "Invalid handle."

    nft delete rule $TABLE $CHAIN handle $_handle
    save_ruleset
    info "Rule handle $_handle deleted"
}

# ── Menu ──────────────────────────────────────────────────────────────────────
require_root
require_table

while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — Firewall Port Manager           ║
  ║                    nftables · na_filter                ║
  ╚════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    echo -e "$SEP"
    echo -e "   ${CYAN}1)${NC} List open ports"
    echo -e "   ${CYAN}2)${NC} Open port             — allow a port for everyone"
    echo -e "   ${CYAN}3)${NC} Open port for one IP  — restrict port to a specific source IP"
    echo -e "   ${CYAN}4)${NC} Remove rule           — delete by handle number"
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

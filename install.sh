#!/usr/bin/env bash
# =============================================================================
# install.sh — The Jungle: VPS node management menu
#
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/RamazanIttiev/jungle-scripts/main/install.sh)
# =============================================================================
set -euo pipefail

REPO="https://raw.githubusercontent.com/RamazanIttiev/jungle-scripts/main"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BLUE='\033[0;34m'; GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}▶${NC} ${BOLD}$*${NC}"; }

# ── Header ────────────────────────────────────────────────────────────────────
show_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║              The Jungle — Node Manager                 ║
  ║       VPS hardening · CDN setup · Kernel tuning        ║
  ╚════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# ── Env check ─────────────────────────────────────────────────────────────────
load_env() {
    ENV_FILE="/etc/profile.d/jungle-node.sh"
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        info "Loaded env from $ENV_FILE"
        echo -e "  ORIGIN_DOMAIN     = ${ORIGIN_DOMAIN:-${YELLOW}not set${NC}}"
        echo -e "  CDN_SYSTEM_DOMAIN = ${CDN_SYSTEM_DOMAIN:-${YELLOW}not set${NC}}"
        echo -e "  CDN_CUSTOM_DOMAIN = ${CDN_CUSTOM_DOMAIN:-${YELLOW}not set (optional)${NC}}"
        echo -e "  LOCAL_PORT        = ${LOCAL_PORT:-${YELLOW}not set${NC}}"
        echo -e "  XHTTP_PATH        = ${XHTTP_PATH:-${YELLOW}not set${NC}}"
    else
        warn "No env file found at $ENV_FILE"
        warn "CDN scripts require ORIGIN_DOMAIN, LOCAL_PORT, etc."
        echo ""
        read -rp "Set up env vars now? [y/N] " SET_ENV
        if [[ "${SET_ENV,,}" == "y" ]]; then
            read -rp "  ORIGIN_DOMAIN:     " ORIGIN_DOMAIN
            read -rp "  LOCAL_PORT [4443]:  " LOCAL_PORT;   LOCAL_PORT="${LOCAL_PORT:-4443}"
            read -rp "  NODE_PORT  [2222]:  " NODE_PORT;    NODE_PORT="${NODE_PORT:-2222}"
            read -rp "  XHTTP_PATH [/api/uploadFile/]: " XHTTP_PATH; XHTTP_PATH="${XHTTP_PATH:-/api/uploadFile/}"
            read -rp "  CDN_SYSTEM_DOMAIN:  " CDN_SYSTEM_DOMAIN
            read -rp "  CDN_CUSTOM_DOMAIN (optional, Enter to skip): " CDN_CUSTOM_DOMAIN

            mkdir -p /etc/profile.d
            cat > "$ENV_FILE" <<EOF
export ORIGIN_DOMAIN="${ORIGIN_DOMAIN}"
export LOCAL_PORT="${LOCAL_PORT}"
export NODE_PORT="${NODE_PORT}"
export XHTTP_PATH="${XHTTP_PATH}"
export CDN_SYSTEM_DOMAIN="${CDN_SYSTEM_DOMAIN}"
export CDN_CUSTOM_DOMAIN="${CDN_CUSTOM_DOMAIN}"
EOF
            source "$ENV_FILE"
            info "Saved to $ENV_FILE"
        fi
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────
run_remote() {
    local script="$1"
    info "Fetching $script from $REPO ..."
    bash <(curl -Ls "$REPO/$script")
}

# ── Main menu ─────────────────────────────────────────────────────────────────
show_header
load_env

echo ""
echo -e "$SEP"
echo -e "${BOLD}  What do you want to do?${NC}"
echo -e "$SEP"
echo ""
echo -e "  ${CYAN}CDN / Origin setup${NC}"
echo -e "   ${CYAN}1)${NC} Origin setup      — certbot + nginx + remnanode containers"
echo -e "   ${CYAN}2)${NC} Verify CDN chain  — full chain check + Remnawave Host config"
echo -e "   ${CYAN}3)${NC} Generate profile  — output Remnawave Config Profile JSON"
echo -e "   ${CYAN}4)${NC} Cert renewal hook — certbot deploy hook for nginx reload"
echo -e "   ${CYAN}5)${NC} Edit env vars     — update /etc/profile.d/jungle-node.sh"
echo ""
echo -e "  ${CYAN}VPS hardening${NC}"
echo -e "   ${CYAN}6)${NC} Node setup        — apt update, SSH hardening, UFW firewall"
echo -e "   ${CYAN}7)${NC} Kernel tuning     — sysctl, BBR, Beszel, selfsteal, MOTD, RemnaNode"
echo ""
echo -e "   ${CYAN}0)${NC} Exit"
echo -e "$SEP"
echo ""
read -rp "Choice: " CHOICE

case "$CHOICE" in
    1)
        [[ -z "${ORIGIN_DOMAIN:-}" ]] && die "ORIGIN_DOMAIN is not set. Re-run and set env vars."
        [[ -z "${SECRET_KEY:-}" ]] && read -rsp "  SECRET_KEY (from Remnawave panel): " SECRET_KEY && echo
        export SECRET_KEY
        run_remote "01_origin_setup.sh"
        ;;
    2)
        [[ -z "${ORIGIN_DOMAIN:-}" ]]     && die "ORIGIN_DOMAIN is not set."
        [[ -z "${CDN_SYSTEM_DOMAIN:-}" ]] && die "CDN_SYSTEM_DOMAIN is not set."
        run_remote "02_cdn_verify.sh"
        ;;
    3)
        [[ -z "${REALITY_PRIVATE_KEY:-}" ]] && read -rsp "  REALITY_PRIVATE_KEY: " REALITY_PRIVATE_KEY && echo
        [[ -z "${REALITY_SHORT_ID:-}" ]]    && read -rp  "  REALITY_SHORT_ID:    " REALITY_SHORT_ID
        export REALITY_PRIVATE_KEY REALITY_SHORT_ID
        OUTPUT="xhttp_profile_$(date +%Y%m%d_%H%M%S).json"
        bash <(curl -Ls "$REPO/03_gen_xhttp_profile.sh") > "$OUTPUT"
        info "Profile written to $(pwd)/$OUTPUT"
        info "Upload this file as a Config Profile in Remnawave panel"
        ;;
    4)
        [[ -z "${ORIGIN_DOMAIN:-}" ]] && die "ORIGIN_DOMAIN is not set."
        run_remote "04_cert_renewal.sh"
        ;;
    5)
        "${EDITOR:-nano}" "$ENV_FILE"
        source "$ENV_FILE"
        info "Env reloaded"
        ;;
    6)
        run_remote "node_setup.sh"
        ;;
    7)
        run_remote "kernel_tuning.sh"
        ;;
    0)
        exit 0
        ;;
    *)
        die "Invalid choice: $CHOICE"
        ;;
esac

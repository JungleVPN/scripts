#!/usr/bin/env bash
# =============================================================================
# install.sh — The Jungle: VPS node management menu
#
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/install.sh)
# =============================================================================
set -euo pipefail

REPO="https://raw.githubusercontent.com/JungleVPN/scripts/main"
ENV_FILE="/etc/profile.d/jungle-node.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GRAY='\033[38;5;8m'; BOLD='\033[1m'; NC='\033[0m'

SEP="${GRAY}$(printf '─%.0s' $(seq 1 54))${NC}"

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}▶${NC} ${BOLD}$*${NC}"; }

# ── Install jungle command if not present ─────────────────────────────────────
if [[ ! -f /usr/local/bin/jungle ]]; then
    cat > /usr/local/bin/jungle <<'CMD'
#!/usr/bin/env bash
bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/install.sh)
CMD
    chmod +x /usr/local/bin/jungle
    info "jungle command installed to /usr/local/bin/jungle"
fi

# ── Load saved vars silently ──────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# ── Ensure CDN vars are set, prompt only for missing ones ─────────────────────
ensure_cdn_vars() {
    local changed=0

    [[ -z "${ORIGIN_DOMAIN:-}" ]]     && { read -rp "  ORIGIN_DOMAIN:                              " ORIGIN_DOMAIN;     changed=1; }
    [[ -z "${CDN_SYSTEM_DOMAIN:-}" ]] && { read -rp "  CDN_SYSTEM_DOMAIN:                          " CDN_SYSTEM_DOMAIN; changed=1; }
    [[ -z "${CDN_CUSTOM_DOMAIN:-}" ]] && { read -rp "  CDN_CUSTOM_DOMAIN (optional, Enter to skip): " CDN_CUSTOM_DOMAIN; changed=1; }
    [[ -z "${LOCAL_PORT:-}" ]]        && { read -rp "  LOCAL_PORT        [4443]:                    " LOCAL_PORT;        LOCAL_PORT="${LOCAL_PORT:-4443}";             changed=1; }
    [[ -z "${XHTTP_PATH:-}" ]]        && { read -rp "  XHTTP_PATH        [/api/uploadFile/]:        " XHTTP_PATH;        XHTTP_PATH="${XHTTP_PATH:-/api/uploadFile/}"; changed=1; }

    if [[ $changed -eq 1 ]]; then
        mkdir -p /etc/profile.d
        cat > "$ENV_FILE" <<EOF
export ORIGIN_DOMAIN="${ORIGIN_DOMAIN}"
export CDN_SYSTEM_DOMAIN="${CDN_SYSTEM_DOMAIN}"
export CDN_CUSTOM_DOMAIN="${CDN_CUSTOM_DOMAIN}"
export LOCAL_PORT="${LOCAL_PORT}"
export XHTTP_PATH="${XHTTP_PATH}"
EOF
        info "Saved to $ENV_FILE"
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────
run_remote() {
    local script="$1"
    info "Fetching $script ..."
    bash <(curl -Ls "$REPO/$script")
}

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║              The Jungle — Node Manager                 ║
  ║       VPS hardening · CDN setup · Kernel tuning        ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Menu ──────────────────────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  What do you want to do?${NC}"
echo -e "$SEP"
echo ""
echo -e "  ${CYAN}CDN / Origin setup${NC}"
echo -e "   ${CYAN}1)${NC} Origin setup      — certbot + nginx + remnanode containers"
echo -e "   ${CYAN}2)${NC} Verify CDN chain  — full chain check + Remnawave Host config"
echo -e "   ${CYAN}3)${NC} Cert renewal hook — certbot deploy hook for nginx reload"
echo -e "   ${CYAN}4)${NC} Edit CDN vars     — update $ENV_FILE"
echo ""
echo -e "  ${CYAN}VPS hardening${NC}"
echo -e "   ${CYAN}5)${NC} Node setup        — apt update, SSH hardening, UFW firewall"
echo -e "   ${CYAN}6)${NC} Kernel tuning     — sysctl, BBR, Beszel, selfsteal, MOTD, RemnaNode"
echo ""
echo -e "   ${CYAN}0)${NC} Exit"
echo -e "$SEP"
echo ""
read -rp "Choice: " CHOICE

case "$CHOICE" in
    1)
        ensure_cdn_vars
        [[ -z "${SECRET_KEY:-}" ]] && read -rsp "  SECRET_KEY (from Remnawave panel): " SECRET_KEY && echo
        export SECRET_KEY
        run_remote "01_origin_setup.sh"
        ;;
    2)
        ensure_cdn_vars
        run_remote "02_cdn_verify.sh"
        ;;
    3)
        ensure_cdn_vars
        run_remote "04_cert_renewal.sh"
        ;;
    4)
        "${EDITOR:-nano}" "$ENV_FILE"
        source "$ENV_FILE"
        info "Env reloaded"
        ;;
    5)
        run_remote "node_setup.sh"
        ;;
    6)
        run_remote "kernel_tuning.sh"
        ;;
    0)
        exit 0
        ;;
    *)
        die "Invalid choice: $CHOICE"
        ;;
esac

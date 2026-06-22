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
pause() { echo ""; read -rp "  Press Enter to continue..." _; }

# ── Install jungle command if not present ─────────────────────────────────────
cat > /usr/local/bin/jungle <<'CMD'
#!/usr/bin/env bash
bash <(curl -Ls "https://raw.githubusercontent.com/JungleVPN/scripts/main/install.sh")
CMD
chmod +x /usr/local/bin/jungle

# ── Load saved vars silently ──────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# ── Ensure CDN vars are set, prompt only for missing ones ─────────────────────
ensure_cdn_vars() {
    local changed=0

    [[ -z "${ORIGIN_DOMAIN:-}" ]]     && { read -rp "  ORIGIN_DOMAIN:                               " ORIGIN_DOMAIN;     changed=1; }
    [[ -z "${CDN_SYSTEM_DOMAIN:-}" ]] && { read -rp "  CDN_SYSTEM_DOMAIN:                           " CDN_SYSTEM_DOMAIN; changed=1; }
    [[ -z "${CDN_CUSTOM_DOMAIN:-}" ]] && { read -rp "  CDN_CUSTOM_DOMAIN (optional, Enter to skip):  " CDN_CUSTOM_DOMAIN; changed=1; }
    [[ -z "${LOCAL_PORT:-}" ]]        && { read -rp "  LOCAL_PORT        [4443]:                     " LOCAL_PORT;        LOCAL_PORT="${LOCAL_PORT:-4443}";             changed=1; }
    [[ -z "${XHTTP_PATH:-}" ]]        && { read -rp "  XHTTP_PATH        [/api/uploadFile/]:         " XHTTP_PATH;        XHTTP_PATH="${XHTTP_PATH:-/api/uploadFile/}"; changed=1; }
    [[ -z "${SECRET_KEY:-}" ]]        && { read -rp "  SECRET_KEY        (node secret key):          " SECRET_KEY;        changed=1; }

    if [[ $changed -eq 1 ]]; then
        mkdir -p /etc/profile.d
        cat > "$ENV_FILE" <<EOF
export ORIGIN_DOMAIN="${ORIGIN_DOMAIN}"
export CDN_SYSTEM_DOMAIN="${CDN_SYSTEM_DOMAIN}"
export CDN_CUSTOM_DOMAIN="${CDN_CUSTOM_DOMAIN}"
export LOCAL_PORT="${LOCAL_PORT}"
export XHTTP_PATH="${XHTTP_PATH}"
export SECRET_KEY="${SECRET_KEY}"
EOF
        info "Saved to $ENV_FILE"
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────
run_remote() {
    local script="$1"
    info "Fetching $script ..."
    bash <(curl -Ls "$REPO/$script") || warn "$script exited with errors."
}

ensure_hy2_vars() {
    [[ -z "${HY2_DOMAIN:-}" ]] && read -rp "  HY2_DOMAIN (SNI for this node):  " HY2_DOMAIN
    [[ -z "${HY2_PORT:-}" ]]   && { read -rp "  HY2_PORT   [36712]:              " HY2_PORT; HY2_PORT="${HY2_PORT:-36712}"; }
    export HY2_DOMAIN HY2_PORT
}

# ── Scripts submenus ──────────────────────────────────────────────────────────

menu_speed_benchmarks() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — Speed & Benchmarks              ║
  ╚════════════════════════════════════════════════════════╝
BANNER
        echo -e "${NC}"
        echo -e "$SEP"
        echo -e "   ${CYAN}1)${NC} Speedtest       — Ookla CLI speed test"
        echo -e "   ${CYAN}2)${NC} YABS            — disk, network + GeekBench"
        echo -e "   ${CYAN}3)${NC} bench.sh        — speed to international providers"
        echo -e "   ${CYAN}4)${NC} speed.tlab.pw   — speed to international providers (alt)"
        echo -e "   ${CYAN}5)${NC} bench.gig.ovh   — speed to Russian providers"
        echo -e "   ${CYAN}6)${NC} bench.tlab.pw   — speed to Russian providers (alt)"
        echo -e "$SEP"
        echo -e "   ${CYAN}0)${NC} Back"
        echo -e "$SEP"
        echo ""
        read -rp "Choice: " _c
        case "$_c" in
            1)
                step "Running Speedtest CLI (Ookla)"
                ARCH=$(uname -m)
                case "$ARCH" in
                    aarch64) ARCH_SUFFIX="aarch64" ;;
                    armv7l)  ARCH_SUFFIX="armhf"   ;;
                    *)       ARCH_SUFFIX="x86_64"  ;;
                esac
                SPEEDTEST_URL="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${ARCH_SUFFIX}.tgz"
                curl -Ls "$SPEEDTEST_URL" -o /tmp/speedtest.tgz
                tar -xzf /tmp/speedtest.tgz -C /tmp speedtest
                chmod +x /tmp/speedtest
                /tmp/speedtest
                rm -f /tmp/speedtest /tmp/speedtest.tgz
                pause
                ;;
            2) curl -sL yabs.sh | bash -s -- -4;  pause ;;
            3) wget -qO- bench.sh | bash;           pause ;;
            4) wget -qO- speed.tlab.pw | bash;      pause ;;
            5) wget -qO- bench.gig.ovh | bash;      pause ;;
            6) wget -qO- bench.tlab.pw | bash;      pause ;;
            0) return ;;
            *) warn "Invalid choice." ; pause ;;
        esac
    done
}

menu_cpu_hardware() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — CPU & Hardware                  ║
  ╚════════════════════════════════════════════════════════╝
BANNER
        echo -e "${NC}"
        echo -e "$SEP"
        echo -e "   ${CYAN}1)${NC} sysbench CPU     — CPU benchmark across all threads"
        echo -e "   ${CYAN}2)${NC} TCP congestion   — show active congestion algorithm"
        echo -e "   ${CYAN}3)${NC} CPU frequency    — show frequency info (dedicated servers)"
        echo -e "$SEP"
        echo -e "   ${CYAN}0)${NC} Back"
        echo -e "$SEP"
        echo ""
        read -rp "Choice: " _c
        case "$_c" in
            1)
                step "Installing sysbench"
                apt install -y sysbench
                sysbench cpu run --threads="$(nproc)"
                pause
                ;;
            2)
                sysctl net.ipv4.tcp_congestion_control
                pause
                ;;
            3)
                if ! command -v cpupower &>/dev/null; then
                    step "Installing cpupower"
                    apt install -y linux-tools-common "linux-tools-$(uname -r)" 2>/dev/null \
                        || apt install -y cpufrequtils
                fi
                cpupower frequency-info
                pause
                ;;
            0) return ;;
            *) warn "Invalid choice." ; pause ;;
        esac
    done
}

menu_ip_connectivity() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — IP & Connectivity               ║
  ╚════════════════════════════════════════════════════════╝
BANNER
        echo -e "${NC}"
        echo -e "$SEP"
        echo -e "   ${CYAN}1)${NC} IP Region        — region seen by websites"
        echo -e "   ${CYAN}2)${NC} IP.Check.Place   — check IP blocks by foreign services"
        echo -e "   ${CYAN}3)${NC} Instagram audio  — check Instagram audio block"
        echo -e "   ${CYAN}4)${NC} CensorCheck DPI  — DPI block check (Russian servers)"
        echo -e "$SEP"
        echo -e "   ${CYAN}0)${NC} Back"
        echo -e "$SEP"
        echo ""
        read -rp "Choice: " _c
        case "$_c" in
            1) bash <(wget -qO- https://ipregion.xyz);                                                              pause ;;
            2) bash <(curl -Ls IP.Check.Place) -l en;                                                              pause ;;
            3) bash <(curl -L -s https://bench.openode.xyz/checker_inst.sh);                                       pause ;;
            4) bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode dpi;     pause ;;
            0) return ;;
            *) warn "Invalid choice." ; pause ;;
        esac
    done
}

# ── Main menu (loops until exit) ──────────────────────────────────────────────
while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║              The Jungle — Node Manager                 ║
  ║       VPS hardening · CDN setup · Kernel tuning        ║
  ╚════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    echo -e "$SEP"
    echo -e "${BOLD}  What do you want to do?${NC}"
    echo -e "$SEP"
    echo ""
    echo -e "  ${CYAN}Init${NC}"
    echo -e "   ${CYAN}1)${NC} Node setup        — apt update, SSH hardening"
    echo -e "   ${CYAN}2)${NC} Kernel tuning     — XanMod, sysctl, limits, RPS, NIC, THP, swap"
    echo -e "   ${CYAN}3)${NC} Beszel + MOTD     — monitoring agent + login banner"
    echo -e "   ${CYAN}4)${NC} selfsteal         — Caddy Reality traffic masking"
    echo -e "   ${CYAN}5)${NC} RemnaNode         — Remnawave node install"
    echo ""
    echo -e "  ${CYAN}Node Accelerator${NC}"
    echo -e "   ${CYAN}6)${NC} Diagnose          — read-only: kernel, sysctl, NIC, firewall check"
    echo -e "   ${CYAN}7)${NC} Protect           — nftables firewall + CrowdSec IPS"
    echo -e "   ${CYAN}8)${NC} Firewall ports    — list, open, restrict, or remove nftables ports"
    echo ""
    echo -e "  ${CYAN}CDN${NC}"
    echo -e "   ${CYAN}9)${NC} Origin setup      — certbot + nginx + remnanode containers"
    echo -e "  ${CYAN}10)${NC} Verify CDN chain  — full chain check + Remnawave Host config"
    echo -e "  ${CYAN}11)${NC} Cert renewal hook — certbot deploy hook for nginx reload"
    echo -e "  ${CYAN}12)${NC} Edit CDN vars     — update $ENV_FILE"
    echo ""
    echo -e "  ${CYAN}Scripts${NC}"
    echo -e "  ${CYAN}13)${NC} Speed & Benchmarks  — Speedtest, YABS, bench.sh, tlab, gig.ovh"
    echo -e "  ${CYAN}14)${NC} CPU & Hardware      — sysbench, TCP congestion, CPU frequency"
    echo -e "  ${CYAN}15)${NC} IP & Connectivity   — IP region, block checks, CensorCheck DPI"
    echo -e "  ${CYAN}16)${NC} RU Services check   — connectivity to gov, banks, social, e-commerce"
    echo ""
    echo -e "  ${CYAN}Protocols${NC}"
    echo -e "  ${CYAN}17)${NC} Hysteria2         — install Hysteria2 inbound on RemnaNode"
    echo ""
    echo -e "  ${CYAN}System${NC}"
    echo -e "  ${CYAN}18)${NC} Update jungle     — reinstall jungle command and reload"
    echo ""
    echo -e "   ${CYAN}0)${NC} Exit"
    echo -e "$SEP"
    echo ""
    read -rp "Choice: " CHOICE

    case "$CHOICE" in
        1)  run_remote "node_setup.sh";    pause ;;
        2)  run_remote "kernel_tuning.sh"; pause ;;
        3)  run_remote "beszel.sh";        pause ;;
        4)  run_remote "selfsteal.sh";     pause ;;
        5)  run_remote "remnanode.sh";     pause ;;
        6)  run_remote "na_diagnose.sh";   pause ;;
        7)  run_remote "na_protect.sh";    pause ;;
        8)  run_remote "nft_ports.sh";     pause ;;
        9)
            ensure_cdn_vars
            export SECRET_KEY
            run_remote "origin_setup.sh"
            pause
            ;;
        10) ensure_cdn_vars; run_remote "cdn_verify.sh";    pause ;;
        11) ensure_cdn_vars; run_remote "cert_renewal.sh";  pause ;;
        12)
            "${EDITOR:-nano}" "$ENV_FILE"
            source "$ENV_FILE"
            info "Env reloaded"
            pause
            ;;
        13) menu_speed_benchmarks ;;
        14) menu_cpu_hardware ;;
        15) menu_ip_connectivity ;;
        16) run_remote "ru_check.sh"; pause ;;
        17) ensure_hy2_vars; run_remote "hysteria.sh"; pause ;;
        18)
            cat > /usr/local/bin/jungle <<'CMD'
#!/usr/bin/env bash
bash <(curl -Ls "https://raw.githubusercontent.com/JungleVPN/scripts/main/install.sh")
CMD
            chmod +x /usr/local/bin/jungle
            info "jungle command updated"
            exec jungle
            ;;
        0)  exit 0 ;;
        *)  warn "Invalid choice: $CHOICE"; pause ;;
    esac
done

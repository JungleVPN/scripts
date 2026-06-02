#!/usr/bin/env bash
# =============================================================================
# kernel_tuning.sh — Kernel/network optimizations + tooling install
#
# Applies: sysctl hardening, BBR, Beszel dir, selfsteal, MOTD, vps-audit,
#          RemnaNode.
#
# Usage (standalone):
#   bash kernel_tuning.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/RamazanIttiev/jungle-scripts/main/kernel_tuning.sh)
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
  ║           The Jungle — Kernel & Network Tuning         ║
  ║     sysctl · BBR · Beszel · selfsteal · RemnaNode      ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN}1.${NC} Overwrite ${CYAN}/etc/sysctl.conf${NC} with hardened + performance settings"
echo -e "       IPv6 disabled, BBR congestion control, TCP buffer tuning,"
echo -e "       anti-spoofing, ICMP protection, kernel security flags"
echo -e "   ${CYAN}2.${NC} Run BBR + fq enable script (endomarfan)"
echo -e "   ${CYAN}3.${NC} Create ${CYAN}/opt/beszel/compose.yml${NC}"
echo -e "   ${CYAN}4.${NC} Install ${CYAN}selfsteal${NC} — Caddy-based Reality traffic masking"
echo -e "   ${CYAN}5.${NC} Install ${CYAN}MOTD${NC} banner (distillium)"
echo -e "   ${CYAN}6.${NC} Run ${CYAN}vps-audit${NC} (vernu)"
echo -e "   ${CYAN}7.${NC} Install ${CYAN}RemnaNode${NC} via DigneZzZ script"
echo -e "$SEP"
echo ""
warn "Steps 4 and 7 have their own interactive prompts."
echo ""
read -rp "Start kernel & network tuning? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── Execute ───────────────────────────────────────────────────────────────────

step "Writing /etc/sysctl.conf"
rm -rf /etc/sysctl.conf
touch  /etc/sysctl.conf

cat <<'EOF' > /etc/sysctl.conf

### IPv6 disable
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

net.ipv6.conf.all.forwarding = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

### IPv4 security
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

### ICMP protection
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 88089
net.ipv4.icmp_ignore_bogus_error_responses = 1

### TCP security and optimization
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_fack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_sack = 1

### Keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5

### TCP buffers
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

### Kernel queues
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 50000
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

### BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

### Kernel security
kernel.yama.ptrace_scope = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0

### Filesystem
fs.file-max = 2097152

### Memory
vm.swappiness = 0

EOF

sysctl --system

step "Enabling BBR + fq"
bash <(curl -sSL https://raw.githubusercontent.com/endomarfan/scripts/main/enable-bbr-fq.sh)

step "Creating Beszel directory"
mkdir -p /opt/beszel
touch /opt/beszel/compose.yml

step "Installing selfsteal (Caddy Reality masking)"
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install

step "Installing MOTD banner"
curl -fsSL https://raw.githubusercontent.com/distillium/motd/main/install-motd.sh | bash

step "Running vps-audit"
curl -O https://raw.githubusercontent.com/vernu/vps-audit/main/vps-audit.sh
chmod +x vps-audit.sh
bash vps-audit.sh

step "Installing RemnaNode"
curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh | bash -s -- @ install

echo ""
echo -e "$SEP"
info "Kernel & network tuning complete."
echo -e "$SEP"

#!/usr/bin/env bash
# =============================================================================
# kernel_tuning.sh — Kernel/network tuning: sysctl, limits, RPS, THP, swap
#
# Merged from node-accelerator/optimize.sh recommendations + original config.
# Safe subset only — no kernel replacement, no reboot required.
# For XanMod kernel (BBRv3) use Node Accelerator → Optimize instead.
#
# Usage (standalone):
#   bash kernel_tuning.sh
#   bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/kernel_tuning.sh)
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
  ║     sysctl · limits · RPS · THP · swap · vps-audit     ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN}1.${NC} Write ${CYAN}/etc/sysctl.conf${NC} — merged hardened + performance config"
echo -e "       IPv6 off · rp_filter=2 (loose, VPN-safe) · BBR · large buffers"
echo -e "       conntrack tuning · TCP optimizations · kernel security"
echo -e "   ${CYAN}2.${NC} Set file descriptor limits (limits.conf + systemd)"
echo -e "   ${CYAN}3.${NC} Enable RPS/RFS/XPS — spread packet processing across CPU cores"
echo -e "   ${CYAN}4.${NC} Disable Transparent Huge Pages (THP)"
echo -e "   ${CYAN}5.${NC} Enable irqbalance"
echo -e "   ${CYAN}6.${NC} Create 2G swap (if none exists)"
echo -e "   ${CYAN}7.${NC} Cap journald logs at 300M"
echo -e "   ${CYAN}8.${NC} Run vps-audit"
echo -e "$SEP"
echo ""
warn "No reboot required. For XanMod kernel (BBRv3) use Node Accelerator → Optimize."
echo ""
read -rp "Start kernel tuning? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ── 1. sysctl ─────────────────────────────────────────────────────────────────
step "Loading nf_conntrack module"
modprobe nf_conntrack 2>/dev/null || true

step "Writing /etc/sysctl.conf"
cat > /etc/sysctl.conf <<'EOF'

### ─── IPv6 disable ────────────────────────────────────────────────────────
net.ipv6.conf.all.disable_ipv6      = 1
net.ipv6.conf.default.disable_ipv6  = 1
net.ipv6.conf.lo.disable_ipv6       = 1
net.ipv6.conf.all.forwarding        = 0
net.ipv6.conf.all.accept_ra         = 0
net.ipv6.conf.default.accept_ra     = 0
net.ipv6.conf.all.autoconf          = 0
net.ipv6.conf.default.autoconf      = 0
net.ipv6.conf.all.use_tempaddr      = 2
net.ipv6.conf.default.use_tempaddr  = 2
net.ipv6.conf.all.accept_redirects  = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route  = 0
net.ipv6.conf.default.accept_source_route = 0

### ─── IPv4 security ────────────────────────────────────────────────────────
net.ipv4.ip_forward                     = 1
net.ipv4.conf.all.forwarding            = 1
net.ipv4.conf.all.send_redirects        = 0
net.ipv4.conf.default.send_redirects    = 0
net.ipv4.conf.all.accept_redirects      = 0
net.ipv4.conf.default.accept_redirects  = 0
net.ipv4.conf.all.secure_redirects      = 0
net.ipv4.conf.all.accept_source_route   = 0
net.ipv4.conf.default.accept_source_route = 0
# loose mode: VPN nodes have asymmetric routing — strict (1) drops legit packets
net.ipv4.conf.all.rp_filter             = 2
net.ipv4.conf.default.rp_filter         = 2
net.ipv4.conf.all.log_martians          = 1
net.ipv4.conf.default.log_martians      = 1

### ─── ICMP ─────────────────────────────────────────────────────────────────
net.ipv4.icmp_echo_ignore_broadcasts        = 1
net.ipv4.icmp_ratelimit                     = 100
net.ipv4.icmp_ratemask                      = 88089
net.ipv4.icmp_ignore_bogus_error_responses  = 1

### ─── TCP security & optimisation ─────────────────────────────────────────
net.ipv4.tcp_syncookies           = 1
net.ipv4.tcp_syn_retries          = 2
net.ipv4.tcp_synack_retries       = 2
net.ipv4.tcp_timestamps           = 1
net.ipv4.tcp_rfc1337              = 1
net.ipv4.tcp_fin_timeout          = 15
net.ipv4.tcp_fastopen             = 3
net.ipv4.tcp_tw_reuse             = 1
net.ipv4.tcp_max_syn_backlog      = 65535
net.ipv4.tcp_max_tw_buckets       = 2000000
net.ipv4.tcp_mtu_probing          = 1
net.ipv4.tcp_no_metrics_save      = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack                 = 1
net.ipv4.tcp_fack                 = 1
net.ipv4.tcp_ecn                  = 1
net.ipv4.tcp_window_scaling       = 1
net.ipv4.tcp_notsent_lowat        = 131072
net.ipv4.ip_local_port_range      = 10000 65535

### ─── Keepalive (1200s: keeps mobile/NAT VPN clients alive) ───────────────
net.ipv4.tcp_keepalive_time    = 1200
net.ipv4.tcp_keepalive_intvl   = 30
net.ipv4.tcp_keepalive_probes  = 5

### ─── TCP/UDP buffers ──────────────────────────────────────────────────────
net.ipv4.tcp_rmem       = 4096 87380 67108864
net.ipv4.tcp_wmem       = 4096 65536 67108864
net.ipv4.udp_rmem_min   = 16384
net.ipv4.udp_wmem_min   = 16384

### ─── Kernel queues ────────────────────────────────────────────────────────
net.core.somaxconn              = 65535
net.core.netdev_max_backlog     = 250000
net.core.rmem_default           = 2097152
net.core.wmem_default           = 2097152
net.core.rmem_max               = 67108864
net.core.wmem_max               = 67108864
net.core.optmem_max             = 65536
net.core.rps_sock_flow_entries  = 32768

### ─── BBR ──────────────────────────────────────────────────────────────────
net.core.default_qdisc            = fq
net.ipv4.tcp_congestion_control   = bbr

### ─── Conntrack ────────────────────────────────────────────────────────────
net.netfilter.nf_conntrack_max                      = 2000000
net.netfilter.nf_conntrack_buckets                  = 500000
net.netfilter.nf_conntrack_tcp_timeout_established  = 7440

### ─── Kernel security ──────────────────────────────────────────────────────
kernel.yama.ptrace_scope    = 1
kernel.randomize_va_space   = 2
fs.suid_dumpable            = 0

### ─── Filesystem ───────────────────────────────────────────────────────────
fs.file-max                   = 2097152
fs.nr_open                    = 2097152
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 8192

### ─── Memory ───────────────────────────────────────────────────────────────
vm.swappiness               = 0
vm.dirty_ratio              = 10
vm.dirty_background_ratio   = 5
vm.overcommit_memory        = 1
vm.max_map_count            = 262144

EOF

sysctl --system

# ── 2. File descriptor limits ─────────────────────────────────────────────────
step "Setting file descriptor limits"

sed -i '/# === jungle ===/,/# === \/jungle ===/d' /etc/security/limits.conf
cat >> /etc/security/limits.conf <<'LIMITS'
# === jungle ===
*     soft  nofile  1048576
*     hard  nofile  1048576
*     soft  nproc   1048576
*     hard  nproc   1048576
root  soft  nofile  1048576
root  hard  nofile  1048576
# === /jungle ===
LIMITS

mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d
cat > /etc/systemd/system.conf.d/jungle-limits.conf <<'L'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
L
cp /etc/systemd/system.conf.d/jungle-limits.conf /etc/systemd/user.conf.d/jungle-limits.conf

for pam in common-session common-session-noninteractive; do
    f="/etc/pam.d/$pam"
    [[ -f "$f" ]] && grep -q '^session.*pam_limits.so' "$f" \
        || { [[ -f "$f" ]] && echo "session required pam_limits.so" >> "$f"; }
done

info "nofile/nproc → 1048576 (takes effect after re-login for shell sessions)"

# ── 3. RPS/RFS/XPS ───────────────────────────────────────────────────────────
step "Enabling RPS/RFS/XPS (spread packet processing across CPU cores)"
cat > /usr/local/sbin/jungle-rps-setup <<'RPS'
#!/usr/bin/env bash
# Spread RX/TX softirq across all CPU cores.
# Critical on VPS with virtio-net (single-queue) — without this all RX
# softirq pins to cpu0, capping throughput regardless of CPU count.
set -e
NIC="${1:-$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')}"
[ -z "$NIC" ] && exit 0
ncpu="$(nproc)"
mask="$(awk -v n="$ncpu" 'BEGIN{
    s=""; while(n>0){ b=(n>=32?32:n); n-=32;
        v=(b>=32?4294967295:(2^b)-1);
        s=(s==""?sprintf("%x",v):sprintf("%x,%s",v,s)); } print (s==""?"0":s) }')"
echo 32768 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
for q in /sys/class/net/"$NIC"/queues/rx-*; do
    [ -e "$q/rps_cpus" ]    && echo "$mask" > "$q/rps_cpus"    2>/dev/null || true
    [ -e "$q/rps_flow_cnt" ] && echo 4096   > "$q/rps_flow_cnt" 2>/dev/null || true
done
for q in /sys/class/net/"$NIC"/queues/tx-*; do
    [ -e "$q/xps_cpus" ] && echo "$mask" > "$q/xps_cpus" 2>/dev/null || true
done
echo "jungle-rps: NIC=$NIC mask=$mask cpus=$ncpu"
RPS
chmod +x /usr/local/sbin/jungle-rps-setup

cat > /etc/systemd/system/jungle-rps.service <<'SVC'
[Unit]
Description=The Jungle — RPS/RFS/XPS tuning
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/jungle-rps-setup

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now jungle-rps.service >/dev/null 2>&1 || true
info "RPS/RFS/XPS enabled across $(nproc) cores"

# ── 4. Transparent Huge Pages → never ────────────────────────────────────────
step "Disabling Transparent Huge Pages (THP)"
cat > /etc/systemd/system/jungle-thp-off.service <<'SVC'
[Unit]
Description=The Jungle — disable THP
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true; \
    echo never > /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now jungle-thp-off.service >/dev/null 2>&1 || true
info "THP disabled"

# ── 5. irqbalance ─────────────────────────────────────────────────────────────
step "Enabling irqbalance"
apt-get install -y -qq irqbalance >/dev/null
systemctl enable --now irqbalance >/dev/null 2>&1 || true
info "irqbalance active"

# ── 6. Swap ───────────────────────────────────────────────────────────────────
step "Checking swap"
if [[ ! -f /swapfile ]] && ! swapon --show | grep -q .; then
    info "No swap found — creating 2G /swapfile"
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    info "Swap created: 2G"
else
    info "Swap already present — skipping"
fi

# ── 7. journald cap ───────────────────────────────────────────────────────────
step "Capping journald logs at 300M"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/jungle-size.conf <<'J'
[Journal]
SystemMaxUse=300M
SystemKeepFree=500M
SystemMaxFileSize=50M
Compress=yes
J
systemctl restart systemd-journald
info "journald capped at 300M"

# ── 8. vps-audit ──────────────────────────────────────────────────────────────
step "Running vps-audit"
curl -fsSL https://raw.githubusercontent.com/vernu/vps-audit/main/vps-audit.sh -o /tmp/vps-audit.sh
chmod +x /tmp/vps-audit.sh
bash /tmp/vps-audit.sh
rm -f /tmp/vps-audit.sh

echo ""
echo -e "$SEP"
info "Kernel tuning complete."
warn "File descriptor limits take effect after re-login for shell sessions."
echo -e "$SEP"

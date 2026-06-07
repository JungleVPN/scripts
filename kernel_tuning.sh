#!/usr/bin/env bash
# =============================================================================
# kernel_tuning.sh — Complete VPS kernel & network optimisation
#
# Sections:
#   1. XanMod kernel (BBRv3)  — optional, x86_64 bare-metal/KVM only
#   2. sysctl                 — IPv6 off, BBR, large buffers, conntrack, security
#   3. File limits            — nofile/nproc 1M via limits.conf + systemd
#   4. RPS/RFS/XPS            — spread packet processing across CPU cores
#   5. NIC tuning             — ring buffer, GRO/GSO/TSO, txqueuelen
#   6. THP off                — transparent huge pages disabled
#   7. CPU governor           — performance mode (skipped on VPS without cpufreq)
#   8. irqbalance
#   9. Swap                   — 2G created if none exists
#  10. journald cap           — 300M max
#  11. vps-audit
#
# XanMod requires a REBOOT to activate. Everything else takes effect immediately.
# Skip XanMod: ENABLE_XANMOD=0 bash kernel_tuning.sh
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

ENABLE_XANMOD="${ENABLE_XANMOD:-1}"
XANMOD_FLAVOR="${XANMOD_FLAVOR:-lts}"
REBOOT_NEEDED=0

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat <<'BANNER'
  ╔════════════════════════════════════════════════════════╗
  ║           The Jungle — Kernel & Network Tuning         ║
  ║  XanMod · sysctl · limits · RPS · NIC · THP · swap    ║
  ╚════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── Summary & confirmation ────────────────────────────────────────────────────
echo -e "$SEP"
echo -e "${BOLD}  This script will:${NC}"
echo -e "$SEP"
echo -e "   ${CYAN} 1.${NC} XanMod kernel (BBRv3)  — x86_64 non-container only, skip ENABLE_XANMOD=0"
echo -e "   ${CYAN} 2.${NC} sysctl                 — IPv6 off, BBR, buffers, conntrack, security"
echo -e "   ${CYAN} 3.${NC} File limits            — nofile/nproc → 1M"
echo -e "   ${CYAN} 4.${NC} RPS/RFS/XPS            — packet processing across all CPU cores"
echo -e "   ${CYAN} 5.${NC} NIC tuning             — ring buffer, GRO/GSO/TSO, txqueuelen"
echo -e "   ${CYAN} 6.${NC} THP off                — transparent huge pages disabled"
echo -e "   ${CYAN} 7.${NC} CPU governor           — performance (skipped if no cpufreq)"
echo -e "   ${CYAN} 8.${NC} irqbalance"
echo -e "   ${CYAN} 9.${NC} Swap                   — 2G created if none exists"
echo -e "   ${CYAN}10.${NC} journald cap           — 300M max"
echo -e "   ${CYAN}11.${NC} vps-audit"
echo -e "$SEP"
echo ""
[[ "$ENABLE_XANMOD" == "1" ]] \
    && warn "XanMod kernel install requires a REBOOT to activate BBRv3." \
    || info "ENABLE_XANMOD=0 — kernel install skipped."
echo ""
read -rp "Start? [y/N] " _ans
[[ "${_ans,,}" == "y" ]] || { info "Aborted."; exit 0; }

# ─────────────────────────────────────────────────────────────────────────────
# Helpers for XanMod
# ─────────────────────────────────────────────────────────────────────────────
_detect_virt() {
    command -v systemd-detect-virt >/dev/null 2>&1 \
        && systemd-detect-virt 2>/dev/null || echo "unknown"
}
_is_container() {
    case "$(_detect_virt)" in
        openvz|lxc|lxc-libvirt|docker|podman|systemd-nspawn|wsl|rkt) return 0;;
        *) return 1;;
    esac
}
_can_install_kernel() {
    [[ "$(uname -m)" == "x86_64" ]] || return 1
    _is_container && return 1
    return 0
}
_psabi_level() {
    local flags lvl=1
    flags=" $(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2) "
    _has() { local x; for x in $1; do [[ "$flags" == *" $x "* ]] || return 1; done; }
    _has "cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3"               && lvl=2
    [[ $lvl -eq 2 ]] && _has "avx avx2 bmi1 bmi2 f16c fma abm movbe xsave" && lvl=3
    [[ $lvl -eq 3 ]] && _has "avx512f avx512bw avx512cd avx512dq avx512vl" && lvl=4
    echo "$lvl"
}
_os_codename() {
    local c=""
    [[ -f /etc/os-release ]] && c="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
    [[ -z "$c" ]] && command -v lsb_release >/dev/null 2>&1 && c="$(lsb_release -sc 2>/dev/null)"
    echo "$c"
}

# ── 1. XanMod kernel ─────────────────────────────────────────────────────────
step "XanMod kernel (BBRv3)"
if [[ "$ENABLE_XANMOD" != "1" ]]; then
    info "Skipped (ENABLE_XANMOD=0)"
elif uname -r | grep -qi xanmod; then
    info "XanMod already active ($(uname -r)) — skipping"
elif ! _can_install_kernel; then
    virt="$(_detect_virt)"
    if _is_container; then
        warn "Container ($virt) — shares host kernel, XanMod cannot be installed."
        warn "BBR will use the stock kernel's implementation."
    else
        warn "Architecture $(uname -m) — XanMod is x86_64 only. Skipping."
    fi
else
    keyring=/etc/apt/keyrings/xanmod-archive-keyring.gpg
    list=/etc/apt/sources.list.d/xanmod-release.list
    codename="$(_os_codename)"

    mkdir -p /etc/apt/keyrings
    if ! curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o "$keyring" 2>/dev/null; then
        warn "Could not download XanMod key — skipping kernel install"
    else
        chmod 0644 "$keyring"
        echo "deb [signed-by=$keyring] http://deb.xanmod.org ${codename:-releases} main" > "$list"
        if ! apt-get update -qq 2>/dev/null; then
            warn "Codename '$codename' not in XanMod repo — trying 'releases'"
            echo "deb [signed-by=$keyring] http://deb.xanmod.org releases main" > "$list"
            apt-get update -qq 2>/dev/null || { warn "XanMod repo unavailable — skipping"; }
        fi

        lvl="$(_psabi_level)"
        info "CPU psABI level: x86-64-v${lvl}, flavor: ${XANMOD_FLAVOR}"
        pref=""; [[ "$XANMOD_FLAVOR" == "lts"  ]] && pref="lts-"
                 [[ "$XANMOD_FLAVOR" == "edge" ]] && pref="edge-"
                 [[ "$XANMOD_FLAVOR" == "rt"   ]] && pref="rt-"

        pkg=""
        case "$lvl" in
            4|3) candidates=("linux-xanmod-${pref}x64v3" "linux-xanmod-${pref}x64v2" "linux-xanmod-lts-x64v2");;
            2)   candidates=("linux-xanmod-${pref}x64v2" "linux-xanmod-lts-x64v2");;
            *)   candidates=("linux-xanmod-lts-x64v1");;
        esac
        for p in "${candidates[@]}"; do
            if apt-cache show "$p" >/dev/null 2>&1; then
                info "Installing $p (this takes a while — building initramfs)..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$p" >/dev/null 2>&1 \
                    && { pkg="$p"; break; }
            fi
        done
        if [[ -n "$pkg" ]]; then
            update-grub >/dev/null 2>&1 || true
            info "XanMod installed: $pkg — active after reboot"
            REBOOT_NEEDED=1
        else
            warn "No XanMod package installed — continuing with stock kernel"
        fi
    fi
fi

# ── 2. sysctl ─────────────────────────────────────────────────────────────────
step "Loading nf_conntrack module"
modprobe nf_conntrack 2>/dev/null || true

step "Writing /etc/sysctl.conf"
cat > /etc/sysctl.conf <<'EOF'

### ─── IPv6 disable ────────────────────────────────────────────────────────
net.ipv6.conf.all.disable_ipv6         = 1
net.ipv6.conf.default.disable_ipv6     = 1
net.ipv6.conf.lo.disable_ipv6          = 1
net.ipv6.conf.all.forwarding           = 0
net.ipv6.conf.all.accept_ra            = 0
net.ipv6.conf.default.accept_ra        = 0
net.ipv6.conf.all.autoconf             = 0
net.ipv6.conf.default.autoconf         = 0
net.ipv6.conf.all.use_tempaddr         = 2
net.ipv6.conf.default.use_tempaddr     = 2
net.ipv6.conf.all.accept_redirects     = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route  = 0
net.ipv6.conf.default.accept_source_route = 0

### ─── IPv4 security ────────────────────────────────────────────────────────
net.ipv4.ip_forward                       = 1
net.ipv4.conf.all.forwarding              = 1
net.ipv4.conf.all.send_redirects          = 0
net.ipv4.conf.default.send_redirects      = 0
net.ipv4.conf.all.accept_redirects        = 0
net.ipv4.conf.default.accept_redirects    = 0
net.ipv4.conf.all.secure_redirects        = 0
net.ipv4.conf.all.accept_source_route     = 0
net.ipv4.conf.default.accept_source_route = 0
# loose: VPN nodes have asymmetric routing — strict (1) drops legit packets
net.ipv4.conf.all.rp_filter               = 2
net.ipv4.conf.default.rp_filter           = 2
net.ipv4.conf.all.log_martians            = 1
net.ipv4.conf.default.log_martians        = 1

### ─── ICMP ─────────────────────────────────────────────────────────────────
net.ipv4.icmp_echo_ignore_broadcasts        = 1
net.ipv4.icmp_ratelimit                     = 100
net.ipv4.icmp_ratemask                      = 88089
net.ipv4.icmp_ignore_bogus_error_responses  = 1

### ─── TCP security & optimisation ─────────────────────────────────────────
net.ipv4.tcp_syncookies            = 1
net.ipv4.tcp_syn_retries           = 2
net.ipv4.tcp_synack_retries        = 2
net.ipv4.tcp_timestamps            = 1
net.ipv4.tcp_rfc1337               = 1
net.ipv4.tcp_fin_timeout           = 15
net.ipv4.tcp_fastopen              = 3
net.ipv4.tcp_tw_reuse              = 1
net.ipv4.tcp_max_syn_backlog       = 65535
net.ipv4.tcp_max_tw_buckets        = 2000000
net.ipv4.tcp_mtu_probing           = 1
net.ipv4.tcp_no_metrics_save       = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack                  = 1
net.ipv4.tcp_fack                  = 1
net.ipv4.tcp_ecn                   = 1
net.ipv4.tcp_window_scaling        = 1
net.ipv4.tcp_notsent_lowat         = 131072
net.ipv4.ip_local_port_range       = 10000 65535

### ─── Keepalive (1200s keeps mobile/NAT VPN clients alive) ────────────────
net.ipv4.tcp_keepalive_time    = 1200
net.ipv4.tcp_keepalive_intvl   = 30
net.ipv4.tcp_keepalive_probes  = 5

### ─── TCP/UDP buffers ──────────────────────────────────────────────────────
net.ipv4.tcp_rmem     = 4096 87380 67108864
net.ipv4.tcp_wmem     = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

### ─── Kernel queues ────────────────────────────────────────────────────────
net.core.somaxconn             = 65535
net.core.netdev_max_backlog    = 250000
net.core.rmem_default          = 2097152
net.core.wmem_default          = 2097152
net.core.rmem_max              = 67108864
net.core.wmem_max              = 67108864
net.core.optmem_max            = 65536
net.core.rps_sock_flow_entries = 32768

### ─── BBR ──────────────────────────────────────────────────────────────────
net.core.default_qdisc          = fq
net.ipv4.tcp_congestion_control = bbr

### ─── Conntrack ────────────────────────────────────────────────────────────
net.netfilter.nf_conntrack_max                     = 2000000
net.netfilter.nf_conntrack_buckets                 = 500000
net.netfilter.nf_conntrack_tcp_timeout_established = 7440

### ─── Kernel security ──────────────────────────────────────────────────────
kernel.yama.ptrace_scope  = 1
kernel.randomize_va_space = 2
fs.suid_dumpable          = 0

### ─── Filesystem ───────────────────────────────────────────────────────────
fs.file-max                   = 2097152
fs.nr_open                    = 2097152
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 8192

### ─── Memory ───────────────────────────────────────────────────────────────
vm.swappiness             = 0
vm.dirty_ratio            = 10
vm.dirty_background_ratio = 5
vm.overcommit_memory      = 1
vm.max_map_count          = 262144

EOF

sysctl --system

# ── 3. File limits ────────────────────────────────────────────────────────────
step "Setting file descriptor limits (nofile/nproc → 1M)"
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
    [[ -f "$f" ]] && ! grep -q '^session.*pam_limits.so' "$f" \
        && echo "session required pam_limits.so" >> "$f"
done
info "Limits set — shell sessions pick up after re-login"

# ── 4. RPS/RFS/XPS ───────────────────────────────────────────────────────────
step "Enabling RPS/RFS/XPS (spread softirq across CPU cores)"
cat > /usr/local/sbin/jungle-rps-setup <<'RPS'
#!/usr/bin/env bash
# Without RPS, all RX softirq on single-queue VPS (virtio-net) pins to cpu0.
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
    [ -e "$q/rps_cpus" ]     && echo "$mask" > "$q/rps_cpus"     2>/dev/null || true
    [ -e "$q/rps_flow_cnt" ] && echo 4096    > "$q/rps_flow_cnt" 2>/dev/null || true
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

# ── 5. NIC tuning ────────────────────────────────────────────────────────────
step "NIC tuning (ring buffer, offloads, txqueuelen)"
NIC="$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')" || NIC=""
if [[ -n "${NIC:-}" ]]; then
    apt-get install -y -qq ethtool >/dev/null 2>&1 || true
    cat > /etc/systemd/system/jungle-nic-tune.service <<EOF
[Unit]
Description=The Jungle — NIC tuning ($NIC)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
    ethtool -G $NIC rx 4096 tx 4096 2>/dev/null || true; \
    ethtool -K $NIC gro on gso on tso on 2>/dev/null || true; \
    ip link set $NIC txqueuelen 10000 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now jungle-nic-tune.service >/dev/null 2>&1 || true
    info "NIC=$NIC: ring 4096, GRO/GSO/TSO on, txqueuelen 10000"
else
    warn "Could not detect primary NIC — skipping NIC tuning"
fi

# ── 6. THP off ────────────────────────────────────────────────────────────────
step "Disabling Transparent Huge Pages"
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

# ── 7. CPU governor ───────────────────────────────────────────────────────────
step "CPU governor"
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    cat > /etc/systemd/system/jungle-cpu-perf.service <<'SVC'
[Unit]
Description=The Jungle — CPU governor performance
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$c" 2>/dev/null || true; done'
[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload
    systemctl enable --now jungle-cpu-perf.service >/dev/null 2>&1 || true
    info "CPU governor → performance"
else
    info "No cpufreq interface — typical VPS, skipping"
fi

# ── 8. irqbalance ─────────────────────────────────────────────────────────────
step "irqbalance"
apt-get install -y -qq irqbalance >/dev/null 2>&1
systemctl enable --now irqbalance >/dev/null 2>&1 || true
info "irqbalance active"

# ── 9. Swap ───────────────────────────────────────────────────────────────────
step "Swap"
if [[ ! -f /swapfile ]] && ! swapon --show | grep -q .; then
    info "Creating 2G /swapfile"
    fallocate -l 2G /swapfile 2>/dev/null \
        || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    info "Swap created: 2G"
else
    info "Swap already present — skipping"
fi

# ── 10. journald cap ──────────────────────────────────────────────────────────
step "Capping journald at 300M"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/jungle-size.conf <<'J'
[Journal]
SystemMaxUse=300M
SystemKeepFree=500M
SystemMaxFileSize=50M
Compress=yes
J
systemctl restart systemd-journald
info "journald capped"

# ── 11. vps-audit ─────────────────────────────────────────────────────────────
step "Running vps-audit"
curl -fsSL https://raw.githubusercontent.com/vernu/vps-audit/main/vps-audit.sh \
    -o /tmp/vps-audit.sh
chmod +x /tmp/vps-audit.sh
bash /tmp/vps-audit.sh
rm -f /tmp/vps-audit.sh

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "$SEP"
info "Kernel tuning complete."
[[ "$REBOOT_NEEDED" == "1" ]] \
    && warn "REBOOT REQUIRED — XanMod kernel activates after: reboot" \
    || info "No reboot needed."
warn "File descriptor limits apply to new sessions after re-login."
echo -e "$SEP"

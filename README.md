# The Jungle — VPS Management Scripts

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JungleVPN/scripts/main/install.sh)
```

---

An interactive menu for setting up and managing VPS nodes running Remnawave infrastructure.

## What it does

**VPS Hardening**
- System update, essential package install, unattended upgrades
- SSH hardening — custom port, password auth disabled
- UFW firewall — allowlist-based rules for all relevant ports
- Kernel tuning — sysctl hardening, IPv6 disable, TCP buffer optimization, BBR congestion control

**Remnawave Stack**
- RemnaNode install and configuration
- selfsteal — Caddy-based Reality traffic masking
- Beszel monitoring agent setup
- MOTD login banner

**CDN Setup**
- Origin VPS setup — certbot, nginx, remnanode containers
- CDN chain verification
- Certbot renewal hook for automatic nginx reload

**Diagnostics**
- Speed tests — Speedtest CLI, YABS, bench.sh and regional alternatives
- CPU benchmarks — sysbench, frequency info, TCP congestion algorithm
- IP and connectivity checks — region detection, block lists, DPI inspection

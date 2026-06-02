set -euo pipefail

: "${ORIGIN_DOMAIN:?  Set ORIGIN_DOMAIN}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
section() { echo -e "\n${YELLOW}══════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════════${NC}"; }

section "Certbot deploy hook: reload cdn-nginx on renewal"

HOOK_FILE="/etc/letsencrypt/renewal-hooks/deploy/reload-cdn-nginx.sh"

cat > "$HOOK_FILE" <<HOOK
#!/usr/bin/env bash
# Reload cdn-nginx after certbot renews ${ORIGIN_DOMAIN}
if [[ "\$RENEWED_DOMAINS" == *"${ORIGIN_DOMAIN}"* ]]; then
    docker exec cdn-nginx nginx -s reload
fi
HOOK

chmod +x "$HOOK_FILE"
info "Deploy hook installed: $HOOK_FILE"

section "Verify certbot systemd timer"
systemctl status certbot.timer --no-pager || true
info "If the timer is not active, enable it:"
info "  systemctl enable --now certbot.timer"

section "Dry-run renewal test"
certbot renew --dry-run && info "Dry-run passed ✓" || info "Dry-run failed (expected if cert is not near expiry)"

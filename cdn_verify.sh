set -euo pipefail

: "${ORIGIN_DOMAIN:?  Set ORIGIN_DOMAIN}"
: "${CDN_SYSTEM_DOMAIN:?  Set CDN_SYSTEM_DOMAIN}"
: "${CDN_CUSTOM_DOMAIN:=}"        # optional
: "${XHTTP_PATH:=/api/uploadFile/}"
: "${LOCAL_PORT:=4443}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
section() { echo -e "\n${YELLOW}══════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════════${NC}"; }

check_400() {
    local label="$1" url="$2" insecure="${3:-}"
    local flags="-so /dev/null -w %{http_code} --max-time 15"
    [[ -n "$insecure" ]] && flags="$flags -k"
    local code
    code=$(curl $flags "$url" 2>/dev/null || echo "ERR")
    if [[ "$code" == "400" ]]; then
        ok "$label → $code ✓"
        return 0
    else
        fail "$label → $code  (expected 400)"
        return 1
    fi
}

# ── 1. Origin chain ───────────────────────────────────────────────────────────
section "1. Origin chain"
check_400 "Xray inbound direct      http://127.0.0.1:${LOCAL_PORT}${XHTTP_PATH}" \
    "http://127.0.0.1:${LOCAL_PORT}${XHTTP_PATH}" insecure || true

check_400 "nginx HTTPS proxy        https://${ORIGIN_DOMAIN}${XHTTP_PATH}" \
    "https://${ORIGIN_DOMAIN}${XHTTP_PATH}" insecure || true

HTTP_ROOT=$(curl -sko /dev/null -w "%{http_code}" --max-time 10 "https://${ORIGIN_DOMAIN}/" 2>/dev/null || echo "ERR")
[[ "$HTTP_ROOT" == "200" ]] \
    && ok  "nginx root               https://${ORIGIN_DOMAIN}/ → $HTTP_ROOT ✓" \
    || fail "nginx root               https://${ORIGIN_DOMAIN}/ → $HTTP_ROOT"

# ── 2. CDN system domain ──────────────────────────────────────────────
section "2. CDN — system domain ($CDN_SYSTEM_DOMAIN)"

CDN_RESPONSE=$(curl -sI --max-time 20 "https://${CDN_SYSTEM_DOMAIN}${XHTTP_PATH}" 2>&1 || true)
CDN_CODE=$(echo "$CDN_RESPONSE" | grep -i '^HTTP' | tail -1 | awk '{print $2}' || echo "ERR")
CDN_CACHE=$(echo "$CDN_RESPONSE" | grep -i 'x-cdn-edge-cache' | tr -d '\r' || echo "(header absent)")

if [[ "$CDN_CODE" == "400" ]]; then
    ok "CDN system domain → $CDN_CODE ✓  ($CDN_CACHE)"
else
    fail "CDN system domain → $CDN_CODE  (expected 400)"
    warn "Common causes:"
    warn "  502/504: CDN provider can't reach origin — check source = ${ORIGIN_DOMAIN}:443 with HTTPS"
    warn "  403:     Secure token / access restrictions / CORS — disable all in CDN settings"
    warn "  Other:   nginx not running, port 443 blocked by ufw"
    echo ""
    info "Raw headers:"
    echo "$CDN_RESPONSE" | head -30
fi

# ── 3. Custom CDN domain (optional) ───────────────────────────────────────────
if [[ -n "$CDN_CUSTOM_DOMAIN" ]]; then
    section "3. Custom CDN domain ($CDN_CUSTOM_DOMAIN)"

    # DNS check
    CNAME_TARGET=$(dig +short CNAME "$CDN_CUSTOM_DOMAIN" 2>/dev/null | sed 's/\.$//' || true)
    if [[ "$CNAME_TARGET" == "$CDN_SYSTEM_DOMAIN" ]]; then
        ok "CNAME $CDN_CUSTOM_DOMAIN → $CDN_SYSTEM_DOMAIN ✓"
    else
        warn "CNAME mismatch: $CDN_CUSTOM_DOMAIN → '$CNAME_TARGET' (expected $CDN_SYSTEM_DOMAIN)"
    fi

    # HTTPS without -k (cert must be valid and on CDN_CUSTOM_DOMAIN)
    CUSTOM_RESPONSE=$(curl -sI --max-time 20 "https://${CDN_CUSTOM_DOMAIN}${XHTTP_PATH}" 2>&1 || true)
    CUSTOM_CODE=$(echo "$CUSTOM_RESPONSE" | grep -i '^HTTP' | tail -1 | awk '{print $2}' || echo "ERR")
    CERT_SUBJECT=$(echo | openssl s_client -servername "$CDN_CUSTOM_DOMAIN" -connect "${CDN_CUSTOM_DOMAIN}:443" 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null | grep -o 'CN[^,]*' || echo "(unknown)")

    if [[ "$CUSTOM_CODE" == "400" ]]; then
        ok "Custom domain → $CUSTOM_CODE ✓"
    else
        fail "Custom domain → $CUSTOM_CODE  (expected 400)"
    fi
    info "Certificate subject: $CERT_SUBJECT"
    if echo "$CERT_SUBJECT" | grep -q "$CDN_CUSTOM_DOMAIN"; then
        ok "Certificate CN matches $CDN_CUSTOM_DOMAIN ✓"
    else
        warn "Certificate CN does NOT contain $CDN_CUSTOM_DOMAIN — issue/bind SSL cert in CDN provider panel"
    fi
fi

# ── 4. Generate Remnawave Host config ─────────────────────────────────────────
section "4. Remnawave Host config (copy into panel)"

CDN_ADDRESS="${CDN_CUSTOM_DOMAIN:-$CDN_SYSTEM_DOMAIN}"

cat <<HOST

  ┌─ Remnawave → Hosts → Add Host ──────────────────────────────────┐
  │  Node:          <your node>                                      │
  │  Inbound tag:   Inbound                                    │
  │  Address:       ${CDN_ADDRESS}
  │  Port:          443                                              │
  │  SNI:           ${CDN_ADDRESS}
  │  Host:          ${CDN_ADDRESS}
  │  Path:          ${XHTTP_PATH}
  │  Security:      TLS                                              │
  │  Transport:     XHTTP                                            │
  │  ALPN:          h2,http/1.1                                      │
  │  Fingerprint:   chrome                                           │
  │  Vless Route ID: (empty)                                         │
  └──────────────────────────────────────────────────────────────────┘

  xHTTP extra params (paste as JSON):

HOST

cat <<XHTTPJSON
{
  "path": "${XHTTP_PATH}",
  "xmux": {
    "cMaxLifetimeMs": 300000,
    "cMaxReuseTimes": 100,
    "maxConcurrency": "16-32",
    "maxConnections": 0
  },
  "seqKey": "chunk_id",
  "sessionKey": "X-Upload-Token",
  "xPaddingKey": "hash",
  "seqPlacement": "query",
  "xPaddingHeader": "X-Client-Version",
  "xPaddingMethod": "tokenish",
  "sessionPlacement": "header",
  "uplinkHTTPMethod": "GET",
  "xPaddingObfsMode": true,
  "xPaddingPlacement": "queryInHeader"
}
XHTTPJSON

# ── 5. Summary checklist ──────────────────────────────────────────────────────
section "5. Final checklist"
echo ""
echo "  [?] = not checked automatically   [✓/✗] = checked above"
echo ""

checks=(
    "ORIGIN_DOMAIN A → VPS IP"
    "certbot cert on ORIGIN_DOMAIN"
    "nginx container running"
    "remnanode container running"
    "Xray XHTTP inbound on 127.0.0.1:${LOCAL_PORT}"
    "curl origin XHTTP_PATH → 400"
    "CDN source = ${ORIGIN_DOMAIN}:443, HTTPS enabled"
    "curl CDN_SYSTEM_DOMAIN XHTTP_PATH → 400"
)

if [[ -n "$CDN_CUSTOM_DOMAIN" ]]; then
    checks+=(
        "CNAME ${CDN_CUSTOM_DOMAIN} → ${CDN_SYSTEM_DOMAIN}"
        "SSL cert for ${CDN_CUSTOM_DOMAIN} issued + bound in CDN provider"
        "curl ${CDN_CUSTOM_DOMAIN} XHTTP_PATH → 400 (no -k)"
    )
fi

checks+=(
    "Remnawave Host Address/SNI/Host = ${CDN_ADDRESS}"
    "Path everywhere = ${XHTTP_PATH} (with trailing slash)"
    "Server extra and Host xHTTP extra params match"
    "mode = packet-up"
    "uplinkHTTPMethod = GET"
    "Subscription tested in client app"
)

for c in "${checks[@]}"; do echo "  [ ] $c"; done
echo ""

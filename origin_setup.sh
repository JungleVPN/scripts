set -euo pipefail

# ── Defaults (override via env) ──────────────────────────────────────────────
: "${ORIGIN_DOMAIN:?  Set ORIGIN_DOMAIN}"
: "${LOCAL_PORT:=4443}"
: "${NODE_PORT:=2222}"
: "${XHTTP_PATH:=/api/uploadFile/}"
: "${SECRET_KEY:?  Set SECRET_KEY}"

NGINX_DIR="/opt/cdn-nginx"
REMNANODE_DIR="/opt/remnanode"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${YELLOW}══════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════════${NC}"; }

# ── 0. Preflight ─────────────────────────────────────────────────────────────
section "0. Preflight checks"

info "Verifying DNS: $ORIGIN_DOMAIN"
RESOLVED=$(dig +short "$ORIGIN_DOMAIN" | tail -1)
SERVER_IP=$(curl -s4 ifconfig.me || true)
if [[ -z "$RESOLVED" ]]; then
    die "DNS: $ORIGIN_DOMAIN does not resolve. Create an A record pointing to this server first."
fi
if [[ "$RESOLVED" != "$SERVER_IP" ]]; then
    warn "DNS resolves to $RESOLVED but server IP is $SERVER_IP — make sure this is intentional."
fi
info "DNS OK: $ORIGIN_DOMAIN → $RESOLVED"

# ── 1. Dependencies ───────────────────────────────────────────────────────────
section "1. Installing dependencies"
apt-get update -qq
apt-get install -y -qq certbot docker.io docker-compose-plugin curl nano dnsutils
systemctl enable --now docker
info "Dependencies installed"

# ── 2. TLS certificate ────────────────────────────────────────────────────────
section "2. TLS certificate via certbot"

CERT_PATH="/etc/letsencrypt/live/$ORIGIN_DOMAIN/fullchain.pem"
if [[ -f "$CERT_PATH" ]]; then
    info "Certificate already exists at $CERT_PATH — skipping"
else
    # Port 80 conflict check
    if ss -ltnp | grep -q ':80 '; then
        warn "Something is listening on port 80:"
        ss -ltnp | grep ':80 '
        warn "Attempting to continue anyway — certbot may fail. Stop the conflicting service first."
    fi
    certbot certonly --standalone -d "$ORIGIN_DOMAIN" \
        --non-interactive --agree-tos --register-unsafely-without-email
    info "Certificate issued"
fi

# ── 3. nginx container ────────────────────────────────────────────────────────
section "3. nginx reverse proxy container"

mkdir -p "$NGINX_DIR/html"

# Stub page
cat > "$NGINX_DIR/html/index.html" <<'EOF'
ok
EOF

# nginx.conf
cat > "$NGINX_DIR/nginx.conf" <<NGINXCONF
server {
    listen 80;
    server_name ${ORIGIN_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ${ORIGIN_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${ORIGIN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${ORIGIN_DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        root  /usr/share/nginx/html;
        index index.html;
        add_header Cache-Control "public, max-age=86400" always;
    }

    location ${XHTTP_PATH} {
        proxy_pass              http://127.0.0.1:${LOCAL_PORT};
        proxy_http_version      1.1;
        proxy_set_header        Host              \$host;
        proxy_set_header        X-Real-IP         \$remote_addr;
        proxy_set_header        X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto https;

        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate" always;
        add_header Pragma        "no-cache" always;
        add_header Expires       "0" always;

        proxy_buffering          off;
        proxy_request_buffering  off;
        proxy_cache              off;

        proxy_connect_timeout    60s;
        proxy_read_timeout       3600s;
        proxy_send_timeout       3600s;
        client_max_body_size     0;
    }
}
NGINXCONF

# docker-compose.yml
cat > "$NGINX_DIR/docker-compose.yml" <<'DCNGINX'
services:
  cdn-nginx:
    image: nginx:1.28
    container_name: cdn-nginx
    restart: always
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./html:/usr/share/nginx/html:ro
DCNGINX

# Port 443 conflict check
if ss -ltnp | grep -q ':443 '; then
    warn "Port 443 is already in use — nginx may fail to start:"
    ss -ltnp | grep ':443 '
fi

cd "$NGINX_DIR"
docker compose up -d
sleep 2
docker exec cdn-nginx nginx -t && docker restart cdn-nginx
info "nginx container started"

# ── 4. remnanode container ────────────────────────────────────────────────────
section "4. remnanode container"

mkdir -p "$REMNANODE_DIR"

cat > "$REMNANODE_DIR/docker-compose.yml" <<DCNODE
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - /dev/shm:/dev/shm:rw
DCNODE

cd "$REMNANODE_DIR"
docker compose up -d
info "remnanode container started"

# ── 5. Verification ────────────────────────────────────────────────────────────
section "5. Verification"
sleep 3

info "Listening ports:"
ss -tulpn | grep -E "(${NODE_PORT}|${LOCAL_PORT}|443|80)" || true

info "Testing Xray XHTTP inbound (expect 400):"
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_PORT}${XHTTP_PATH}" || true)
[[ "$HTTP_CODE" == "400" ]] && info "  127.0.0.1:${LOCAL_PORT}${XHTTP_PATH} → $HTTP_CODE ✓" \
    || warn "  127.0.0.1:${LOCAL_PORT}${XHTTP_PATH} → $HTTP_CODE (expected 400 — inbound may not be ready yet)"

info "Testing nginx root (expect 200):"
HTTP_CODE=$(curl -sko /dev/null -w "%{http_code}" "https://${ORIGIN_DOMAIN}/" || true)
[[ "$HTTP_CODE" == "200" ]] && info "  https://${ORIGIN_DOMAIN}/ → $HTTP_CODE ✓" \
    || warn "  https://${ORIGIN_DOMAIN}/ → $HTTP_CODE"

info "Testing nginx XHTTP proxy (expect 400):"
HTTP_CODE=$(curl -sko /dev/null -w "%{http_code}" "https://${ORIGIN_DOMAIN}${XHTTP_PATH}" || true)
[[ "$HTTP_CODE" == "400" ]] && info "  https://${ORIGIN_DOMAIN}${XHTTP_PATH} → $HTTP_CODE ✓" \
    || warn "  https://${ORIGIN_DOMAIN}${XHTTP_PATH} → $HTTP_CODE (not 400 yet — CDN not ready to connect)"

echo ""
info "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Origin setup complete."
info "Next steps:"
info "  1. Verify all three curl checks above show expected codes"
info "  2. In Remnawave panel → Nodes: set Address=$ORIGIN_DOMAIN Port=$NODE_PORT"
info "  3. Apply the Config Profile with XHTTP inbound on port $LOCAL_PORT"
info "  4. Then run 02_cdn_verify.sh after setting up Timeweb CDN"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

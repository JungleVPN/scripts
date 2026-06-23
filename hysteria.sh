set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# hysteria2_setup.sh — Prepare a Remnawave remnanode for a managed Hysteria2 inbound.
#
# What it DOES (idempotent, reversible):
#   1. Swaps the in-container Xray core to a pinned release that fixes the
#      Hysteria2 online/traffic-accounting bug (>= v26.6.1) via a bind-mount.
#   2. Ensures a real TLS cert exists for HY2_DOMAIN (HY2 terminates its own TLS;
#      it does NOT use REALITY and does NOT go through Caddy).
#   3. Mounts /etc/letsencrypt into the container so Xray can read the cert.
#   4. Opens the Hysteria2 UDP port in ufw.
#   5. Prints the exact inbound JSON to paste into the Remnawave panel + verify steps.
#
# What it does NOT do:
#   - Touch the Remnawave panel (inbound is added in the UI — MCP/API is read-only here).
#   - Touch REALITY / XHTTP / Caddy / selfsteal. Core swap is a drop-in binary.
#
# Rollback: remove the custom-xray volume line from the compose file and restart.
#           (Script can do this for you: `ROLLBACK=1 bash hysteria2_setup.sh`)
# ─────────────────────────────────────────────────────────────────────────────

# ── Defaults (override via env) ──────────────────────────────────────────────
: "${HY2_DOMAIN:?  Set HY2_DOMAIN (e.g. lv.thejungle.pro — the published SNI for this node)}"
: "${HY2_PORT:=443}"
: "${XRAY_VERSION:=v26.6.1}"
: "${REMNANODE_DIR:=/opt/remnanode}"
: "${CUSTOM_XRAY_DIR:=/opt/remnanode/custom-xray}"
: "${CERT_EMAIL:=}"            # required for certbot; set to your email (e.g. admin@example.com)
: "${SKIP_CERT:=0}"           # set 1 if a valid cert for HY2_DOMAIN already exists & is mounted
: "${ROLLBACK:=0}"            # set 1 to remove the core override and exit
: "${CERTBOT_DIR:=/opt/certbot}"        # where certbot docker-compose.yml and certs live
: "${CADDY_CONTAINER:=caddy-selfsteal}" # Docker container name holding port 80; stopped briefly during cert issuance. Override: CADDY_CONTAINER=other bash hysteria.sh

COMPOSE_FILE="${REMNANODE_DIR}/docker-compose.yml"
CERTBOT_COMPOSE="${CERTBOT_DIR}/docker-compose.yml"
CERT_LIVE="${CERTBOT_DIR}/certs/live/${HY2_DOMAIN}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${YELLOW}══════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════════${NC}"; }

[[ $EUID -eq 0 ]] || die "Run as root (needs docker, ufw, /etc/letsencrypt, /opt write access)."
[[ -f "$COMPOSE_FILE" ]] || die "No compose file at $COMPOSE_FILE — is this a remnanode host?"

# ── Rollback path ────────────────────────────────────────────────────────────
if [[ "$ROLLBACK" == "1" ]]; then
    section "ROLLBACK: removing custom Xray core override"
    if grep -q "custom-xray/xray:/usr/local/bin/xray" "$COMPOSE_FILE"; then
        cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%s)"
        sed -i "\#custom-xray/xray:/usr/local/bin/xray#d" "$COMPOSE_FILE"
        info "Removed core override line. Restarting node onto the image's bundled core."
        (cd "$REMNANODE_DIR" && docker compose down && docker compose up -d)
        docker exec remnanode xray version | head -1 || true
        info "Rollback complete. The HY2 inbound in the panel will stop working until a fixed core is restored."
    else
        warn "No core override line found in $COMPOSE_FILE — nothing to roll back."
    fi
    exit 0
fi

# ── 0. Preflight ─────────────────────────────────────────────────────────────
section "0. Preflight checks"

command -v docker >/dev/null || die "docker not found"
docker ps --format '{{.Names}}' | grep -qx remnanode || die "remnanode container is not running"
info "remnanode container present"

CORE_NOW=$(docker exec remnanode xray version 2>/dev/null | head -1 || echo "unknown")
info "Current in-container core: $CORE_NOW"

info "Verifying DNS for $HY2_DOMAIN"
RESOLVED=$(dig +short "$HY2_DOMAIN" +time=3 +tries=1 2>/dev/null | tail -1 || true)
SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || true)
[[ -n "$RESOLVED" ]] || die "DNS: $HY2_DOMAIN does not resolve. Create an A record first."
if [[ -z "$SERVER_IP" ]]; then
    warn "Could not detect server IP — skipping DNS match check"
elif [[ "$RESOLVED" == "$SERVER_IP" ]]; then
    info "DNS OK: $HY2_DOMAIN → $RESOLVED (matches server)"
else
    warn "DNS: $HY2_DOMAIN → $RESOLVED but server IP is $SERVER_IP — confirm this is intentional."
fi

# ── 1. Dependencies ──────────────────────────────────────────────────────────
section "1. Dependencies"
apt-get update -qq
apt-get install -y -qq unzip wget curl dnsutils ufw certbot
info "Dependencies installed"

# ── 2. Swap Xray core (pinned, checksum-verified) ────────────────────────────
section "2. Xray core → ${XRAY_VERSION}"

mkdir -p "$CUSTOM_XRAY_DIR"
cd "$CUSTOM_XRAY_DIR"

ZIP="Xray-linux-64.zip"
BASE="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"
info "Downloading ${XRAY_VERSION} ..."
wget -q -O "$ZIP"        "${BASE}/${ZIP}"        || die "Download failed: ${BASE}/${ZIP}"
wget -q -O "${ZIP}.dgst" "${BASE}/${ZIP}.dgst"   || warn "Could not fetch .dgst checksum file — skipping verify"

if [[ -f "${ZIP}.dgst" ]]; then
    LOCAL_SHA=$(sha256sum "$ZIP" | awk '{print $1}')
    # .dgst lists multiple hashes; grab the SHA2-256 line
    EXPECT_SHA=$(grep -iA1 'SHA2-256' "${ZIP}.dgst" | tail -1 | tr -d ' \t\r' || true)
    if [[ -n "$EXPECT_SHA" && "$LOCAL_SHA" == "$EXPECT_SHA" ]]; then
        info "Checksum OK ($LOCAL_SHA)"
    else
        warn "Checksum mismatch or unparsed:"
        warn "  local:    $LOCAL_SHA"
        warn "  expected: ${EXPECT_SHA:-<unparsed>}"
        warn "  Inspect ${CUSTOM_XRAY_DIR}/${ZIP}.dgst manually before trusting this binary."
        read -r -p "Continue anyway? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted at checksum step."
    fi
fi

unzip -o "$ZIP" xray >/dev/null
chmod +x xray
HOST_VER=$(./xray version 2>/dev/null | head -1 || echo "FAILED")
[[ "$HOST_VER" != "FAILED" ]] || die "Downloaded xray binary will not execute on this host."
info "Binary runs on host: $HOST_VER"

# Bind-mount into the container if not already present
if grep -q "custom-xray/xray:/usr/local/bin/xray" "$COMPOSE_FILE"; then
    info "Core override already present in compose — leaving as-is"
else
    cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%s)"
    info "Backed up compose file"
    # Insert under the remnanode service's volumes:. Requires an existing 'volumes:' key.
    if grep -qE '^\s*volumes:' "$COMPOSE_FILE"; then
        sed -i "0,/^\(\s*\)volumes:/s##&\n\1  - '${CUSTOM_XRAY_DIR}/xray:/usr/local/bin/xray:ro'#" "$COMPOSE_FILE"
        info "Added core override to volumes:"
    else
        die "No 'volumes:' key in $COMPOSE_FILE — add this line manually under remnanode:
      - '${CUSTOM_XRAY_DIR}/xray:/usr/local/bin/xray:ro'"
    fi
fi

# ── 3. TLS certificate for HY2_DOMAIN ────────────────────────────────────────
section "3. TLS certificate (standalone HTTP-01 via Docker certbot)"

# Ensure certbot dir and compose file exist
mkdir -p "$CERTBOT_DIR"
if [[ ! -f "$CERTBOT_COMPOSE" ]]; then
    cat > "$CERTBOT_COMPOSE" <<'CERTBOT_COMPOSE_EOF'
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
CERTBOT_COMPOSE_EOF
    info "Created ${CERTBOT_COMPOSE}"
else
    info "certbot compose already exists: ${CERTBOT_COMPOSE}"
fi

if [[ "$SKIP_CERT" == "1" ]]; then
    info "SKIP_CERT=1 — assuming a valid cert for $HY2_DOMAIN is already present & mounted"
elif [[ -f "${CERT_LIVE}/fullchain.pem" ]]; then
    info "Certificate already exists: ${CERT_LIVE}/fullchain.pem — skipping issuance"
else
    [[ -n "$CERT_EMAIL" ]] || die "CERT_EMAIL is required for certbot (e.g. CERT_EMAIL=admin@example.com)"

    CERTBOT_EMAIL_ARG="--email ${CERT_EMAIL}"

    # If port 80 is held by the caddy container, stop it briefly for the HTTP-01 challenge
    PORT80_PID=$(ss -tlnp 'sport = :80' 2>/dev/null | grep -oP '(?<=pid=)\d+' | head -1 || true)
    CADDY_WAS_RUNNING=0
    if [[ -n "$PORT80_PID" ]]; then
        PORT80_PROC=$(ps -p "$PORT80_PID" -o comm= 2>/dev/null || true)
        info "Port 80 held by: ${PORT80_PROC} (pid ${PORT80_PID})"
        if docker inspect --format '{{.State.Running}}' "$CADDY_CONTAINER" 2>/dev/null | grep -q true; then
            info "Stopping ${CADDY_CONTAINER} to free port 80 (~10 s downtime)..."
            docker stop "$CADDY_CONTAINER"
            CADDY_WAS_RUNNING=1
        else
            die "Port 80 is in use by '${PORT80_PROC}' (not ${CADDY_CONTAINER}). Free it manually, then re-run."
        fi
    fi

    info "Issuing cert for $HY2_DOMAIN via standalone HTTP-01..."
    docker run --rm \
        -v "${CERTBOT_DIR}/certs:/etc/letsencrypt" \
        -v "${CERTBOT_DIR}/var-lib:/var/lib/letsencrypt" \
        --network host \
        certbot/certbot certonly --standalone \
        --non-interactive --agree-tos \
        $CERTBOT_EMAIL_ARG \
        -d "$HY2_DOMAIN" \
        < /dev/null \
        || { [[ "$CADDY_WAS_RUNNING" == "1" ]] && docker start "$CADDY_CONTAINER"; die "certbot failed"; }

    [[ "$CADDY_WAS_RUNNING" == "1" ]] && { docker start "$CADDY_CONTAINER"; info "Restarted ${CADDY_CONTAINER}"; }
    info "Certificate issued → ${CERT_LIVE}"
fi

# Mount certbot certs dir into remnanode (maps to /etc/letsencrypt inside container)
CERT_MOUNT="${CERTBOT_DIR}/certs:/etc/letsencrypt"
if grep -qF "$CERT_MOUNT" "$COMPOSE_FILE"; then
    info "certbot certs already mounted into container"
else
    # Remove any old /etc/letsencrypt mount that may exist from a previous approach
    sed -i "\#/etc/letsencrypt:/etc/letsencrypt#d" "$COMPOSE_FILE"
    sed -i "0,/^\(\s*\)volumes:/s##&\n\1  - '${CERT_MOUNT}:ro'#" "$COMPOSE_FILE"
    info "Mounted ${CERTBOT_DIR}/certs → /etc/letsencrypt (ro) into container"
fi

# Print cron renewal instructions
echo
info "Auto-renewal cron (add via 'crontab -e' on this host):"
echo "  0 0 28 * * docker stop ${CADDY_CONTAINER}; cd ${CERTBOT_DIR} && docker compose run --rm certbot renew; docker start ${CADDY_CONTAINER}"

# ── 4. Firewall ──────────────────────────────────────────────────────────────
section "4. Firewall (ufw)"
if ufw status | grep -q "${HY2_PORT}/udp"; then
    info "ufw already allows ${HY2_PORT}/udp"
else
    ufw allow "${HY2_PORT}/udp" comment 'Hysteria2'
    info "Opened ${HY2_PORT}/udp"
fi

# ── 5. Restart node & verify core ────────────────────────────────────────────
section "5. Restart remnanode & verify core"
cd "$REMNANODE_DIR"
docker compose down && docker compose up -d
sleep 4

CORE_AFTER=$(docker exec remnanode xray version 2>/dev/null | head -1 || echo "FAILED")
info "In-container core now: $CORE_AFTER"
echo "$CORE_AFTER" | grep -q "${XRAY_VERSION#v}" \
    && info "Core swap confirmed (${XRAY_VERSION}) ✓" \
    || warn "Core version does not show ${XRAY_VERSION} — check 'docker exec remnanode xray version'"

# ── 6. Inbound JSON to paste into Remnawave ──────────────────────────────────
section "6. Remnawave panel — add this inbound to the node's Config Profile"
HY2_TAG="HY2_${HY2_DOMAIN//./_}"
cat <<JSON

  Panel → Config Profiles → (the profile for this node) → inbounds[] → add:

{
  "tag": "${HY2_TAG}",
  "listen": "0.0.0.0",
  "port": ${HY2_PORT},
  "protocol": "hysteria",
  "settings": {
    "version": 2,
    "clients": []
  },
  "streamSettings": {
    "network": "hysteria",
    "security": "tls",
    "tlsSettings": {
      "serverName": "${HY2_DOMAIN}",
      "alpn": ["h3"],
      "certificates": [
        {
          "usage": "encipherment",
          "certificateFile": "/etc/letsencrypt/live/${HY2_DOMAIN}/fullchain.pem",
          "keyFile": "/etc/letsencrypt/live/${HY2_DOMAIN}/privkey.pem"
        }
      ]
    },
    "hysteriaSettings": {
      "version": 2,
      "udpIdleTimeout": 60,
      "quicParams": {
        "congestion": "brutal",
        "brutalUp": "100 mbps",
        "brutalDown": "100 mbps"
      }
    }
  }
}

  Notes:
   - "clients": [] is intentional — Remnawave injects users (and per-user auth)
     at subscription-generation time, which is what makes online status &
     traffic accounting work. Do NOT hardcode auth here.
   - No finalmask/Salamander obfs yet — prove the bare protocol on RU networks first.
   - "brutal" 100/100 mbps is a starting point; set at/below the real egress of the node.

JSON

# ── 7. Post-apply verification (run after pasting + applying the profile) ─────
section "7. After applying the profile, verify on the node:"
cat <<'VERIFY'

  # UDP listener present?
  ss -ulpn | grep <HY2_PORT> || echo "NOT LISTENING — profile not applied or core too old"

  # Watch handshake/auth while a client connects (on the buggy 26.3.27 you'd see
  # bind succeed then total silence; on 26.6.1 you should see auth/accepted lines):
  docker logs -f remnanode 2>&1 | grep -iE "hysteria|<HY2_PORT>|accepted|auth"

  # The real gate: connect from a RU MTS/Beeline/Rostelecom MOBILE link via Happ, then confirm
  #   (a) it connects, (b) user shows ONLINE in panel, (c) traffic increments.
  # Then test DPI survivability from those operators via t.me/bschekbot / chebur.me.

VERIFY

info "Done. Core prepared + cert + firewall ready. Add the inbound in the panel, then run the Step 7 checks."
info "Rollback any time with:  ROLLBACK=1 HY2_DOMAIN=${HY2_DOMAIN} bash $(basename "$0")"
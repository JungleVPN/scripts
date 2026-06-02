# Timeweb CDN + XHTTP Setup Scripts

Scripts for setting up the Remnawave XHTTP-over-CDN scheme:
**Client → Timeweb CDN:443 → ORIGIN_DOMAIN:443 → nginx → 127.0.0.1:LOCAL_PORT → Xray/remnanode**

---

## Scripts

| Script | What it does | Run where |
|--------|-------------|-----------|
| `origin_setup.sh` | Installs certbot, nginx container, remnanode container | Origin VPS |
| `cdn_verify.sh` | Verifies full chain + prints Remnawave Host config | Origin VPS |
| `cert_renewal.sh` | Installs certbot deploy hook to reload nginx on renewal | Origin VPS |

---

## Workflow

### Step 1 — DNS (manual, before anything)
```
ORIGIN_DOMAIN  A     <VPS_IP>
# After CDN is set up:
CDN_CUSTOM_DOMAIN  CNAME  CDN_SYSTEM_DOMAIN
```

### Step 2 — Set vars
```bash
cat > /etc/profile.d/jungle-node.sh <<'EOF'
export ORIGIN_DOMAIN=""
export CDN_SYSTEM_DOMAIN=""
export XHTTP_PATH=""
export LOCAL_PORT="8443"
export SECRET_KEY=""
EOF
```

Upload `xhttp_profile.json` as a new Config Profile in Remnawave panel.

### Step 3 — Set up origin VPS
```bash
bash origin_setup.sh
```

### Step 4 — Remnawave panel: create/update node
- Nodes → Add/Edit node
- Address: `ORIGIN_DOMAIN`
- Port: `NODE_PORT` (2222)
- Config Profile: the one with XHTTP-TIMEWEB inbound

### Step 5 — Create Timeweb CDN resource (manual)
- CDN → Add resource
- Source type: Domain
- Source domain: `ORIGIN_DOMAIN:443`
- HTTPS to source: **enabled**
- Caching, Always Online, Secure Token, HTTP/3, Gzip: **all disabled**
- Note the system domain: `CDN_SYSTEM_DOMAIN`

### Step 6 — Verify the chain
```bash
bash cdn_verify.sh
```
Script prints the Remnawave Host config block to paste into the panel.

### Step 7 — Custom domain (optional, manual in Timeweb)
1. Timeweb → CDN resource → Domains → Add `CDN_CUSTOM_DOMAIN`
2. Timeweb → SSL certs → Add Let's Encrypt for `CDN_CUSTOM_DOMAIN`
3. Bind cert to CDN resource
4. Add CNAME at your DNS provider

### Step 8 — Cert renewal hook
```bash
bash cert_renewal.sh
```

---

## Key rules (from guide)
- `/api/uploadFile` ≠ `/api/uploadFile/` — trailing slash matters **everywhere**
- `mode: packet-up` + `uplinkHTTPMethod: GET` — never POST (Timeweb returns 405)
- Server `extra` in Config Profile must match client `xHTTP extra params` in Host exactly
- CDN address in Node settings = `ORIGIN_DOMAIN` — never the CDN domain there
- CDN domain only goes in **Hosts**, not in **Nodes**
- Don't connect Timeweb CDN until origin returns 400 on XHTTP path

## Troubleshooting quick reference

| Symptom | Likely cause |
|---------|-------------|
| `127.0.0.1:LOCAL_PORT` not listening | Config Profile not applied to node, or inbound disabled |
| nginx `502`/`504` on CDN | Timeweb source not set to `ORIGIN_DOMAIN:443` or HTTPS disabled |
| CDN returns `403` | Secure token / CORS / access restriction enabled in Timeweb |
| Custom domain N/A in client | SSL cert not issued or not bound to CDN resource in Timeweb |
| `405` on CDN | POST used — switch to `uplinkHTTPMethod: GET` |
| `404` on XHTTP path | Trailing slash mismatch between nginx, profile, and Host |

# nginx_stream_generator

> **Module:** `lib` | **File:** `lib/nginx_stream_generator.sh` | **Version:** `5.34`

Nginx Configuration Generator. Generates `/opt/familytraffic/config/nginx/nginx.conf`, replacing the legacy `lib/haproxy_config_manager.sh`.

---

## Overview

Produces a complete `nginx.conf` with two top-level blocks:

- **`stream` block** — L4 routing (replaces HAProxy `mode tcp`):
  - Port `443`: `ssl_preread` SNI routing — Reality passthrough to `127.0.0.1:8443`, Tier 2 subdomains to `127.0.0.1:8448`
  - Port `1080`: TLS termination → `127.0.0.1:10800` (SOCKS5 plaintext)
  - Port `8118`: TLS termination → `127.0.0.1:18118` (HTTP proxy plaintext)

- **`http` block** — Tier 2 TLS termination and optional MTProxy cloak:
  - Port `8448`: WebSocket / XHTTP / gRPC server blocks (Phase 2 transports)
  - Port `4443`: MTProxy cloak-port — internal only, active probing protection (v5.34)
  - Port `80`: ACME HTTP-01 challenge (certbot webroot renewal)

**Version history:**

| Version | Change |
|---------|--------|
| v5.30 | Initial release; SNI routing, SOCKS5/HTTP TLS termination, WebSocket transport |
| v5.31 | XHTTP/SplitHTTP transport |
| v5.32 | gRPC transport |
| v5.34 | MTProxy cloak-port 4443 (`enable_mtproxy_cloak` parameter) |

---

## Functions

### generate_nginx_config *(v5.34)*

Generate complete `nginx.conf` content to stdout.

**Parameters:**

| # | Name | Required | Description |
|---|------|----------|-------------|
| `$1` | `cert_domain` | Yes | Domain for Let's Encrypt certificate (e.g., `proxy.example.com`) |
| `$2` | `enable_tier2` | No | `"true"` / `"false"` — include Tier 2 server blocks in http section (default: `"false"`) |
| `$3` | `ws_subdomain` | No | WebSocket subdomain (Phase 2 / v5.30, e.g., `ws.example.com`) |
| `$4` | `xhttp_subdomain` | No | XHTTP/SplitHTTP subdomain (Phase 2 / v5.31) |
| `$5` | `grpc_subdomain` | No | gRPC subdomain (Phase 2 / v5.32) |
| `$6` | `enable_mtproxy_cloak` | No | `"true"` / `"false"` — include MTProxy cloak-port 4443 (v5.34, default: `"false"`) |

**Returns:** nginx.conf content on stdout; `0` on success, `1` on failure

**Notes:**
- Port `4443` cloak server is **loopback-only** — do NOT open in UFW
- mtg v2 (`generate_mtg_toml()`) must set `cloak.port = 4443` to match
- The SNI `map` block is populated only for non-empty subdomain arguments
- cert path is derived as `/etc/letsencrypt/live/${cert_domain}/`

**Examples:**

```bash
# Minimal — Reality only (no Tier 2, no MTProxy)
generate_nginx_config "proxy.example.com" \
    > /opt/familytraffic/config/nginx/nginx.conf

# With all Tier 2 transports
generate_nginx_config "proxy.example.com" "true" \
    "ws.example.com" "xhttp.example.com" "grpc.example.com" \
    > /opt/familytraffic/config/nginx/nginx.conf

# With MTProxy cloak-port (no Tier 2 transports)
generate_nginx_config "proxy.example.com" "false" "" "" "" "true" \
    > /opt/familytraffic/config/nginx/nginx.conf

# With both Tier 2 and MTProxy cloak-port
generate_nginx_config "proxy.example.com" "true" \
    "ws.example.com" "" "" "true" \
    > /opt/familytraffic/config/nginx/nginx.conf
```

---

## Generated Configuration Structure

```
nginx.conf
├── stream {
│   ├── map $ssl_preread_server_name $backend_addr
│   │   ├── <ws_subdomain>    → 127.0.0.1:8448  (if set)
│   │   ├── <xhttp_subdomain> → 127.0.0.1:8448  (if set)
│   │   ├── <grpc_subdomain>  → 127.0.0.1:8448  (if set)
│   │   └── default           → 127.0.0.1:8443  (Reality passthrough)
│   ├── server { listen 443; ssl_preread on; ... }
│   ├── server { listen 1080 ssl; → 127.0.0.1:10800 SOCKS5 }
│   └── server { listen 8118 ssl; → 127.0.0.1:18118 HTTP proxy }
└── http {
    ├── server { listen 8448 ssl default_server; return 444; }  ← probing protection
    ├── server { listen 8448 ssl; ws transport }     (if ws_subdomain set)
    ├── server { listen 8448 ssl; xhttp transport }  (if xhttp_subdomain set)
    ├── server { listen 8448 ssl; grpc transport }   (if grpc_subdomain set)
    ├── server { listen 4443 ssl; cloak-port }       (if enable_mtproxy_cloak=true)
    └── server { listen 80; ACME challenge + 301 redirect }
    }
```

---

## MTProxy Cloak-Port (v5.34)

When `enable_mtproxy_cloak="true"`, a server block is added:

```nginx
server {
    listen 4443 ssl;
    server_name proxy.example.com;
    ssl_certificate     /etc/letsencrypt/live/proxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/proxy.example.com/privkey.pem;
    ssl_protocols       TLSv1.3;
    root /var/www/html;
    location / { try_files $uri $uri/ =404; }
}
```

**Purpose:** mtg v2 redirects all invalid / censorship-probe connections to this port. The censor sees valid TLS with a real LE certificate and real HTTP content — not a proxy fingerprint.

**Security:** Port `4443` must NOT be opened in UFW. It is loopback-only (`cloak.port = 4443` in `mtg.toml`).

---

## Usage

```bash
source lib/nginx_stream_generator.sh

# Used in orchestrator.sh (basic install)
generate_nginx_config "${CERT_DOMAIN}" \
    > "${VLESS_DIR}/config/nginx/nginx.conf"

# Used in transport_manager.sh (Phase 2 transports)
generate_nginx_config "${CERT_DOMAIN}" "true" \
    "${WS_SUBDOMAIN}" "${XHTTP_SUBDOMAIN}" "${GRPC_SUBDOMAIN}" \
    > "${VLESS_DIR}/config/nginx/nginx.conf"

# With MTProxy (mtproxy_manager.sh integration)
generate_nginx_config "${CERT_DOMAIN}" "false" "" "" "" "true" \
    > "${VLESS_DIR}/config/nginx/nginx.conf"
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_CONF` | `/opt/familytraffic/config/nginx/nginx.conf` | Target config path |

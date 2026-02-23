#!/usr/bin/env bash
# lib/nginx_stream_generator.sh
# Nginx Configuration Generator (v5.30)
# Replaces lib/haproxy_config_manager.sh — generates /opt/vless/config/nginx/nginx.conf
#
# Architecture (v5.30):
#   stream block — L4 routing (replaces HAProxy mode tcp):
#     - Port 443: ssl_preread SNI routing (Reality passthrough, Tier2 → loopback 8448)
#     - Port 1080: TLS termination → vless_xray:10800 (SOCKS5 plaintext)
#     - Port 8118: TLS termination → vless_xray:18118 (HTTP proxy plaintext)
#   http block — Tier 2 TLS termination (populated by Phase 2 / transport_manager.sh):
#     - Port 8448: loopback target from stream SNI map; ws/xhttp/grpc server blocks
#
# Functions:
#   1. generate_nginx_config()  — writes complete nginx.conf to stdout
#
# Usage (in orchestrator.sh):
#   source "${LIB_DIR}/nginx_stream_generator.sh"
#   generate_nginx_config "$CERT_DOMAIN" > "${VLESS_DIR}/config/nginx/nginx.conf"
#
# Usage (with Tier 2 transports, in transport_manager.sh):
#   generate_nginx_config "$CERT_DOMAIN" "true" "$ws_sub" "$xhttp_sub" "$grpc_sub" \
#       > "${VLESS_DIR}/config/nginx/nginx.conf"

# ============================================================================
# FUNCTION: generate_nginx_config (v5.30)
# ============================================================================
# Description: Generate complete nginx.conf replacing haproxy.cfg
#   stream block: SNI routing (port 443), TLS termination (1080, 8118)
#   http block:   Tier 2 transports (port 8448, populated by Phase 2)
# Arguments:
#   $1 - cert_domain: domain for LE cert (e.g., proxy.example.com)
#   $2 - enable_tier2: "true"/"false" — include Tier 2 server blocks in http section
#   $3 - ws_subdomain: WebSocket subdomain (optional, Phase 2 / v5.30)
#   $4 - xhttp_subdomain: XHTTP subdomain (optional, Phase 2 / v5.31)
#   $5 - grpc_subdomain: gRPC subdomain (optional, Phase 2 / v5.32)
# Returns: nginx.conf content on stdout; 0 on success, 1 on failure
# ============================================================================
NGINX_CONF="${NGINX_CONF:-/opt/vless/config/nginx/nginx.conf}"

# ============================================================================
# FUNCTION: add_reverse_proxy_route
# ============================================================================
# Description: Adds SNI map entry for a reverse proxy subdomain in nginx.conf.
#   Inserts "domain  vless_nginx_reverseproxy:port;" before the 'default'
#   line in the stream map block, then reloads vless_nginx (zero-downtime).
#
# Arguments:
#   $1 - domain: subdomain to route (e.g., claude.example.com)
#   $2 - port:   vless_nginx_reverseproxy backend port (e.g., 9443)
# Returns: 0 on success, 1 on failure
# ============================================================================
add_reverse_proxy_route() {
    local domain="$1"
    local port="$2"
    local conf="${NGINX_CONF}"

    if [[ -z "$domain" || -z "$port" ]]; then
        echo "ERROR: add_reverse_proxy_route requires <domain> <port>" >&2
        return 1
    fi

    if [[ ! -f "$conf" ]]; then
        echo "ERROR: nginx.conf not found: $conf" >&2
        return 1
    fi

    # Escape dots for use in sed/grep patterns (domain is a literal string)
    local domain_esc
    domain_esc=$(printf '%s' "$domain" | sed 's/\./\\./g')

    # Idempotent: skip if entry already exists
    if grep -qP "^\s*${domain_esc}\s" "$conf"; then
        echo "INFO: SNI route already exists: ${domain}" >&2
        return 0
    fi

    cp "$conf" "${conf}.bak"

    # Insert before the 'default' line inside the map block
    sed -i "/default\s\+vless_xray:8443/i\\        ${domain}    vless_nginx_reverseproxy:${port};  # Reverse proxy" \
        "$conf"

    if ! docker exec vless_nginx nginx -t 2>/dev/null; then
        echo "ERROR: nginx -t failed after adding route, rolling back" >&2
        mv "${conf}.bak" "$conf"
        return 1
    fi

    docker exec vless_nginx nginx -s reload
    echo "INFO: SNI route added: ${domain} → vless_nginx_reverseproxy:${port}" >&2
    return 0
}

# ============================================================================
# FUNCTION: remove_reverse_proxy_route
# ============================================================================
# Description: Removes the SNI map entry for a reverse proxy subdomain
#   from nginx.conf, then reloads vless_nginx (zero-downtime).
#
# Arguments:
#   $1 - domain: subdomain to remove (e.g., claude.example.com)
# Returns: 0 on success, 1 on failure
# ============================================================================
remove_reverse_proxy_route() {
    local domain="$1"
    local conf="${NGINX_CONF}"

    if [[ -z "$domain" ]]; then
        echo "ERROR: remove_reverse_proxy_route requires <domain>" >&2
        return 1
    fi

    if [[ ! -f "$conf" ]]; then
        echo "ERROR: nginx.conf not found: $conf" >&2
        return 1
    fi

    # Escape dots for use in sed pattern (domain is a literal string)
    local domain_esc
    domain_esc=$(printf '%s' "$domain" | sed 's/\./\\./g')

    cp "$conf" "${conf}.bak"

    # Remove the SNI map entry for this domain
    sed -i "/^\s*${domain_esc}\s/d" "$conf"

    if ! docker exec vless_nginx nginx -t 2>/dev/null; then
        echo "ERROR: nginx -t failed after removing route, rolling back" >&2
        mv "${conf}.bak" "$conf"
        return 1
    fi

    docker exec vless_nginx nginx -s reload
    echo "INFO: SNI route removed: ${domain}" >&2
    return 0
}

generate_nginx_config() {
    local cert_domain="${1}"
    local enable_tier2="${2:-false}"
    local ws_subdomain="${3:-}"
    local xhttp_subdomain="${4:-}"
    local grpc_subdomain="${5:-}"

    if [[ -z "$cert_domain" ]]; then
        echo "ERROR: generate_nginx_config requires cert_domain as \$1" >&2
        return 1
    fi

    local cert_path="/etc/letsencrypt/live/${cert_domain}"

    cat <<EOF
# nginx.conf — vless_nginx (v5.30, replaces haproxy.cfg)
# Generated by lib/nginx_stream_generator.sh
# DO NOT EDIT MANUALLY — regenerate via orchestrator.sh or transport_manager.sh

user nginx;
worker_processes auto;

events {
    worker_connections 65536;
    use epoll;
    multi_accept on;
}

# =============================================================================
# Stream block: L4 routing (replaces HAProxy mode tcp)
# =============================================================================
stream {
    error_log /var/log/nginx/stream_error.log warn;

    # SNI map: Tier 2 subdomains → loopback http block; Reality → Xray passthrough
    map \$ssl_preread_server_name \$backend_addr {
$(if [[ -n "$ws_subdomain" ]]; then
    echo "        ${ws_subdomain}       127.0.0.1:8448;  # WebSocket Tier 2"
fi)
$(if [[ -n "$xhttp_subdomain" ]]; then
    echo "        ${xhttp_subdomain}    127.0.0.1:8448;  # XHTTP Tier 2"
fi)
$(if [[ -n "$grpc_subdomain" ]]; then
    echo "        ${grpc_subdomain}     127.0.0.1:8448;  # gRPC Tier 2"
fi)
        default             vless_xray:8443;  # Reality passthrough (no TLS termination)
    }

    # -------------------------------------------------------------------------
    # Port 443: SNI routing (NO TLS termination — Reality requires passthrough)
    # ssl_preread reads SNI without decrypting TLS — preserves Reality handshake
    # -------------------------------------------------------------------------
    server {
        listen 443;
        ssl_preread on;
        proxy_pass \$backend_addr;
        proxy_connect_timeout 10s;
        proxy_timeout 300s;
    }

    # -------------------------------------------------------------------------
    # Port 1080: SOCKS5 with TLS termination (replaces HAProxy frontend socks5_tls)
    # TLS terminated here; plaintext forwarded to vless_xray:10800
    # -------------------------------------------------------------------------
    server {
        listen 1080 ssl;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        ssl_ciphers         TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384;
        proxy_pass          vless_xray:10800;
        proxy_connect_timeout 10s;
        proxy_timeout        300s;
    }

    # -------------------------------------------------------------------------
    # Port 8118: HTTP proxy with TLS termination (replaces HAProxy frontend http_tls)
    # TLS terminated here; plaintext forwarded to vless_xray:18118
    # -------------------------------------------------------------------------
    server {
        listen 8118 ssl;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        ssl_ciphers         TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384;
        proxy_pass          vless_xray:18118;
        proxy_connect_timeout 10s;
        proxy_timeout        300s;
    }
}

# =============================================================================
# HTTP block: Tier 2 transports
# Port 8448: loopback target from stream SNI map (Tier 2 subdomains only)
# =============================================================================
http {
    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    # Default server — reject unknown hosts (active probing protection)
    server {
        listen 8448 ssl default_server;
        http2 on;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        server_name         _;
        return 444;
    }
$(if [[ -n "$ws_subdomain" ]]; then
cat <<WS_BLOCK

    # WebSocket Transport (Phase 2 / v5.30)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${ws_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /vless-ws {
            proxy_pass http://vless_xray:8444;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_read_timeout 300s;
        }
    }
WS_BLOCK
fi)
$(if [[ -n "$xhttp_subdomain" ]]; then
cat <<XHTTP_BLOCK

    # XHTTP/SplitHTTP Transport (Phase 2 / v5.31)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${xhttp_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /api/v2 {
            proxy_pass http://vless_xray:8445;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header Connection "";
            proxy_buffering off;
            client_max_body_size 0;
            proxy_read_timeout 300s;
        }
    }
XHTTP_BLOCK
fi)
$(if [[ -n "$grpc_subdomain" ]]; then
cat <<GRPC_BLOCK

    # gRPC Transport (Phase 2 / v5.32)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${grpc_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /GunService/ {
            grpc_pass grpc://vless_xray:8446;
            grpc_read_timeout 300s;
            grpc_send_timeout 300s;
        }
    }
GRPC_BLOCK
fi)
}
EOF
}

export -f generate_nginx_config

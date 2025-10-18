#!/bin/bash
# lib/nginx_config_generator.sh
#
# Nginx Reverse Proxy Configuration Generator for VLESS v4.3
# Generates secure reverse proxy configurations with heredoc templates
#
# Features:
# - TLS 1.3 only (Let's Encrypt certificates)
# - HTTP Basic Auth (bcrypt hashed)
# - Host Header Validation (VULN-001 fix)
# - HSTS header (VULN-002 fix)
# - Rate limiting & DoS protection (VULN-003/004/005 fix)
# - Error logging only (no access log for privacy)
# - v4.3: Localhost-only binding (9443-9452), SNI routing via HAProxy
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-18

set -euo pipefail

# Source common utilities (if available)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration paths
NGINX_CONF_DIR="/opt/vless/config/reverse-proxy"
HTPASSWD_DIR="/opt/vless/config/reverse-proxy"
LETSENCRYPT_DIR="/etc/letsencrypt/live"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [nginx-generator] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [nginx-generator] ERROR: $*" >&2
}

# ============================================================================
# Function: generate_reverseproxy_nginx_config
# Description: Generates Nginx reverse proxy configuration for a domain
#
# Parameters:
#   $1 - domain: Reverse proxy domain (e.g., claude.example.com)
#   $2 - target_site: Target site to proxy (e.g., blocked-site.com)
#   $3 - port: Localhost listening port (e.g., 9443, v4.3 range: 9443-9452)
#   $4 - xray_port: Xray HTTP inbound port (e.g., 10080)
#   $5 - username: HTTP Basic Auth username
#   $6 - password_hash: bcrypt hashed password
#
# Output:
#   Creates: ${NGINX_CONF_DIR}/${domain}.conf
#   Creates: ${HTPASSWD_DIR}/.htpasswd-${domain}
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
generate_reverseproxy_nginx_config() {
    local domain="$1"
    local target_site="$2"
    local port="$3"
    local xray_port="$4"
    local username="$5"
    local password_hash="$6"

    # Validation
    if [[ -z "$domain" || -z "$target_site" || -z "$port" || -z "$xray_port" || -z "$username" || -z "$password_hash" ]]; then
        log_error "Missing required parameters"
        echo "Usage: generate_reverseproxy_nginx_config <domain> <target_site> <port> <xray_port> <username> <password_hash>"
        return 1
    fi

    # Validate domain format
    if ! [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi

    # Validate port range (v4.3: 9443-9952 for localhost-only nginx backends)
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port: $port (must be numeric)"
        return 1
    fi

    if [ "$port" -lt 9443 ] || [ "$port" -gt 9452 ]; then
        log_error "Invalid port: $port (v4.3 requires 9443-9452 range for reverse proxy)"
        log_error "Nginx binds to localhost only, HAProxy routes via SNI on port 443"
        return 1
    fi

    # Check if certificate exists
    local cert_path="${LETSENCRYPT_DIR}/${domain}"
    if [ ! -d "$cert_path" ]; then
        log_error "Let's Encrypt certificate not found: $cert_path"
        log_error "Run certbot to obtain certificate first"
        return 1
    fi

    # Create directories if not exist
    mkdir -p "$NGINX_CONF_DIR" || {
        log_error "Failed to create directory: $NGINX_CONF_DIR"
        return 1
    }

    # Generate .htpasswd file
    local htpasswd_file="${HTPASSWD_DIR}/.htpasswd-${domain}"
    echo "${username}:${password_hash}" > "$htpasswd_file" || {
        log_error "Failed to create htpasswd file: $htpasswd_file"
        return 1
    }
    chmod 600 "$htpasswd_file"

    # Generate Nginx configuration using heredoc
    local nginx_conf="${NGINX_CONF_DIR}/${domain}.conf"

    log "Generating Nginx configuration: $nginx_conf"

    cat > "$nginx_conf" <<EOF
# Nginx Reverse Proxy Configuration
# Domain: ${domain}
# Target: ${target_site}
# Port: ${port} (localhost-only, HAProxy SNI routing)
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Version: v4.3 (HAProxy Unified Architecture)

upstream xray_reverseproxy_${domain//[.-]/_} {
    server vless_xray:${xray_port};
    keepalive 32;
}

# Primary server block (with Host header validation)
server {
    listen 127.0.0.1:${port} ssl http2;  # v4.3: localhost-only (HAProxy routes by SNI)
    server_name ${domain};  # EXACT match required

    # TLS Configuration (TLS 1.3 only)
    ssl_certificate ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256;

    # HTTP Basic Auth
    auth_basic "Restricted Access";
    auth_basic_user_file ${htpasswd_file};

    # VULN-001 FIX: Host Header Validation (CRITICAL)
    # Defense-in-depth: Explicit Host validation
    if (\$host != "${domain}") {
        return 444;  # Close connection without response
    }

    # VULN-002 FIX: HSTS Header (HIGH)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Additional Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # VULN-003/004 FIX: Rate Limiting
    limit_req zone=reverseproxy_${domain//[.-]/_} burst=20 nodelay;
    limit_conn conn_limit_per_ip 5;

    # Logging (error log only, no access log)
    access_log off;  # Privacy: no access logging
    error_log /var/log/nginx/reverse-proxy-${domain}-error.log warn;

    # Proxy to Xray
    location / {
        proxy_pass http://xray_reverseproxy_${domain//[.-]/_};
        proxy_http_version 1.1;

        # VULN-001 FIX: Hardcoded Host header (NOT \$host or \$http_host)
        proxy_set_header Host ${target_site};  # Target site (hardcoded)

        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Upgrade headers (for potential WebSocket support in future)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts (prevent slowloris)
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # Error pages (optional)
    error_page 401 /401.html;
    location = /401.html {
        internal;
        return 401 'Unauthorized: Invalid credentials';
        add_header Content-Type text/plain always;
    }

    error_page 429 /429.html;
    location = /429.html {
        internal;
        return 429 'Too Many Requests: Rate limit exceeded';
        add_header Content-Type text/plain always;
    }
}

# VULN-001 FIX: Default server block (catch invalid Host headers)
server {
    listen 127.0.0.1:${port} ssl http2 default_server;  # v4.3: localhost-only
    server_name _;

    ssl_certificate ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;

    # Reject all requests with invalid Host header
    return 444;  # No response
}
EOF

    # Set permissions
    chmod 600 "$nginx_conf"

    log "✅ Nginx configuration created successfully: $nginx_conf"
    log "✅ htpasswd file created: $htpasswd_file"

    return 0
}

# ============================================================================
# Function: generate_reverseproxy_http_context
# Description: Generates HTTP context configuration for rate limiting zones
#
# Output:
#   Creates: ${NGINX_CONF_DIR}/http_context.conf
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
generate_reverseproxy_http_context() {
    local http_context_conf="${NGINX_CONF_DIR}/http_context.conf"

    log "Generating HTTP context configuration: $http_context_conf"

    cat > "$http_context_conf" <<'EOF'
# HTTP Context Configuration for Reverse Proxy
# Rate limiting zones and global settings
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Version: v4.3 (HAProxy Unified Architecture)

# VULN-003 FIX: Connection limit zone (by IP address)
# 10m zone = ~160,000 IP addresses tracked
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

# VULN-004 FIX: Request rate limit zones (per domain)
# Each reverse proxy domain gets its own rate limit zone
# Rate: 10 requests per second per IP
# Note: Actual limit_req_zone directives are generated per domain

# VULN-005 FIX: Maximum request body size
client_max_body_size 10m;

# Timeouts (prevent slowloris attacks)
client_body_timeout 10s;
client_header_timeout 10s;
send_timeout 10s;
keepalive_timeout 30s;

# Error responses for limit violations
limit_conn_status 429;  # Too Many Requests
limit_req_status 429;

# Hide Nginx version
server_tokens off;

# Include reverse proxy server blocks
include /etc/nginx/conf.d/reverse-proxy/*.conf;
EOF

    chmod 644 "$http_context_conf"

    log "✅ HTTP context configuration created: $http_context_conf"

    return 0
}

# ============================================================================
# Function: add_rate_limit_zone
# Description: Adds rate limit zone for a specific domain
#
# Parameters:
#   $1 - domain: Domain name (e.g., proxy.example.com)
#
# Output:
#   Appends to: ${NGINX_CONF_DIR}/http_context.conf
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
add_rate_limit_zone() {
    local domain="$1"
    local http_context_conf="${NGINX_CONF_DIR}/http_context.conf"

    if [[ -z "$domain" ]]; then
        log_error "Missing domain parameter"
        return 1
    fi

    # Sanitize domain for zone name (replace . and - with _)
    local zone_name="reverseproxy_${domain//[.-]/_}"

    # Check if zone already exists
    if grep -q "zone=${zone_name}" "$http_context_conf" 2>/dev/null; then
        log "Rate limit zone already exists: $zone_name"
        return 0
    fi

    log "Adding rate limit zone: $zone_name"

    # Append rate limit zone
    echo "" >> "$http_context_conf"
    echo "# Rate limit zone for: ${domain}" >> "$http_context_conf"
    echo "limit_req_zone \$binary_remote_addr zone=${zone_name}:10m rate=10r/s;" >> "$http_context_conf"

    log "✅ Rate limit zone added: $zone_name"

    return 0
}

# ============================================================================
# Function: remove_reverseproxy_config
# Description: Removes Nginx reverse proxy configuration for a domain
#
# Parameters:
#   $1 - domain: Domain name to remove
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
remove_reverseproxy_config() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_error "Missing domain parameter"
        return 1
    fi

    local nginx_conf="${NGINX_CONF_DIR}/${domain}.conf"
    local htpasswd_file="${HTPASSWD_DIR}/.htpasswd-${domain}"

    log "Removing Nginx configuration for: $domain"

    # Remove Nginx config
    if [ -f "$nginx_conf" ]; then
        rm -f "$nginx_conf"
        log "✅ Removed Nginx config: $nginx_conf"
    else
        log "Nginx config not found: $nginx_conf"
    fi

    # Remove htpasswd file
    if [ -f "$htpasswd_file" ]; then
        rm -f "$htpasswd_file"
        log "✅ Removed htpasswd file: $htpasswd_file"
    else
        log "htpasswd file not found: $htpasswd_file"
    fi

    # TODO: Remove rate limit zone from http_context.conf (optional)

    return 0
}

# ============================================================================
# Function: validate_nginx_config
# Description: Validates Nginx configuration syntax
#
# Returns:
#   0 if valid, 1 if invalid
# ============================================================================
validate_nginx_config() {
    log "Validating Nginx configuration..."

    if docker exec vless_nginx nginx -t 2>&1; then
        log "✅ Nginx configuration is valid"
        return 0
    else
        log_error "❌ Nginx configuration is invalid"
        return 1
    fi
}

# ============================================================================
# Function: reload_nginx
# Description: Reloads Nginx configuration
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
reload_nginx() {
    log "Reloading Nginx..."

    if docker exec vless_nginx nginx -s reload 2>&1; then
        log "✅ Nginx reloaded successfully"
        return 0
    else
        log_error "❌ Failed to reload Nginx"
        return 1
    fi
}

# ============================================================================
# Main execution (for testing)
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [ $# -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  generate <domain> <target_site> <port> <xray_port> <username> <password_hash>"
        echo "  http-context"
        echo "  add-zone <domain>"
        echo "  remove <domain>"
        echo "  validate"
        echo "  reload"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        generate)
            generate_reverseproxy_nginx_config "$@"
            ;;
        http-context)
            generate_reverseproxy_http_context
            ;;
        add-zone)
            add_rate_limit_zone "$@"
            ;;
        remove)
            remove_reverseproxy_config "$@"
            ;;
        validate)
            validate_nginx_config
            ;;
        reload)
            reload_nginx
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
fi

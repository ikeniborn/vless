#!/bin/bash
# lib/nginx_config_generator.sh
#
# Nginx Reverse Proxy Configuration Generator for VLESS v5.10
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
# - v5.8: Cookie/URL rewriting for complex auth (OAuth, session cookies, etc.)
# - v5.9: Enhanced cookie handling (OAuth2, large cookies >4kb)
# - v5.9: CSRF protection (Referer rewriting)
# - v5.9: WebSocket support (long-lived connections)
# - v5.10: CSP header handling (configurable strip/keep)
# - v5.10: Intelligent sub-filter (protocol-relative URLs, API endpoints)
# - v5.10: Advanced wizard support (OAuth2/WebSocket/CSP options)
#
# Version: 5.10.0
# Author: VLESS Development Team
# Date: 2025-10-20

set -euo pipefail

# Source common utilities (if available)
# Only set SCRIPT_DIR if not already defined (avoid readonly conflicts when sourced)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

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
# Function: resolve_target_ipv4
# Description: Resolves target site to IPv4 address (IPv6-safe)
#
# Parameters:
#   $1 - target_site: Target site hostname
#
# Output:
#   Prints IPv4 address to stdout
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
resolve_target_ipv4() {
    local target_site="$1"

    if [[ -z "$target_site" ]]; then
        log_error "Missing target_site parameter"
        return 1
    fi

    # Try to resolve using dig (preferred)
    if command -v dig &> /dev/null; then
        local ipv4=$(dig +short "$target_site" A @8.8.8.8 | head -1)
        if [[ -n "$ipv4" ]] && [[ "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ipv4"
            return 0
        fi
    fi

    # Fallback to getent (system resolver)
    if command -v getent &> /dev/null; then
        local ipv4=$(getent ahostsv4 "$target_site" | awk '{print $1}' | head -1)
        if [[ -n "$ipv4" ]] && [[ "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ipv4"
            return 0
        fi
    fi

    # Fallback to host command
    if command -v host &> /dev/null; then
        local ipv4=$(host -t A "$target_site" 8.8.8.8 | awk '/has address/ {print $NF}' | head -1)
        if [[ -n "$ipv4" ]] && [[ "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ipv4"
            return 0
        fi
    fi

    log_error "Failed to resolve IPv4 for: $target_site"
    return 1
}

# ============================================================================
# Function: generate_reverseproxy_nginx_config
# Description: Generates Nginx reverse proxy configuration for a domain
#
# Parameters:
#   $1 - domain: Reverse proxy domain (e.g., claude.example.com)
#   $2 - target_site: Target site to proxy (e.g., blocked-site.com)
#   $3 - port: Localhost listening port (e.g., 9443, v4.3 range: 9443-9452)
#   $4 - username: HTTP Basic Auth username
#   $5 - password_hash: bcrypt hashed password
#
# Output:
#   Creates: ${NGINX_CONF_DIR}/${domain}.conf
#   Creates: ${HTPASSWD_DIR}/.htpasswd-${domain}
#
# Returns:
#   0 on success, 1 on failure
#
# v5.2 Changes:
#   - IPv4-only proxy_pass (prevents IPv6 unreachable errors)
#   - Resolves target_site to IPv4 at config generation time
#   - Preserves correct Host header and SNI for target site
#
# v5.8 Changes:
#   - Cookie domain rewriting (proxy_cookie_domain) for session persistence
#   - URL rewriting (sub_filter) for absolute links in HTML/JS/CSS
#   - Origin header rewriting for CORS compatibility
#   - Supports: OAuth, Google Auth, session cookies, form-based auth
#
# v5.9 Changes:
#   - Enhanced cookie handling: multiple Set-Cookie headers (OAuth2)
#   - Large cookie support: increased buffers for OAuth2 state (>4kb)
#   - CSRF protection: Referer header rewriting for target domain
#   - WebSocket support: long-lived connection timeouts (1 hour)
#
# v5.10 Changes:
#   - CSP header handling: strip or keep CSP headers (configurable)
#   - Intelligent sub-filter: protocol-relative URLs, subdomain matching
#   - Advanced options: STRIP_CSP, ENABLE_WEBSOCKET, OAUTH2_SUPPORT (env vars)
# ============================================================================
generate_reverseproxy_nginx_config() {
    local domain="$1"
    local target_site="$2"
    local port="$3"
    local username="$4"
    local password_hash="$5"

    # v5.10: Advanced configuration options (environment variables)
    # Set defaults if not provided
    local strip_csp="${STRIP_CSP:-true}"           # Strip CSP headers by default
    local enable_websocket="${ENABLE_WEBSOCKET:-true}"  # WebSocket enabled by default
    local oauth2_support="${OAUTH2_SUPPORT:-true}"      # OAuth2 support by default

    # Validation
    if [[ -z "$domain" || -z "$target_site" || -z "$port" || -z "$username" || -z "$password_hash" ]]; then
        log_error "Missing required parameters"
        echo "Usage: generate_reverseproxy_nginx_config <domain> <target_site> <port> <username> <password_hash>"
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

    # Resolve target site to IPv4 (CRITICAL: prevents IPv6 unreachable errors)
    log "Resolving target site to IPv4: $target_site"
    local target_ipv4
    if ! target_ipv4=$(resolve_target_ipv4 "$target_site"); then
        log_error "Failed to resolve IPv4 for target: $target_site"
        log_error "Cannot generate configuration without valid IPv4 address"
        return 1
    fi
    log "✅ Resolved $target_site → $target_ipv4"

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
    chmod 644 "$htpasswd_file"  # Make readable by nginx user

    # Generate Nginx configuration using heredoc
    local nginx_conf="${NGINX_CONF_DIR}/${domain}.conf"

    log "Generating Nginx configuration: $nginx_conf"

    cat > "$nginx_conf" <<EOF
# Nginx Reverse Proxy Configuration
# Domain: ${domain}
# Target: ${target_site} → ${target_ipv4}
# Port: ${port} (localhost-only, HAProxy SNI routing)
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Version: v5.9 (OAuth2, CSRF, WebSocket support)
# NOTE: Direct HTTPS proxy to target site IPv4 (prevents IPv6 unreachable errors)

# v5.9: WebSocket support - connection upgrade map
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# Primary server block (with Host header validation)
server {
    listen 0.0.0.0:${port} ssl;  # v4.3: Bridge network (HAProxy routes by SNI)
    http2 on;  # Modern HTTP/2 syntax (Nginx 1.25+)
    server_name ${domain};  # EXACT match required

    # TLS Configuration (TLS 1.3 only)
    ssl_certificate ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;
    # TLS 1.3 cipher suites configured automatically (no ssl_ciphers directive needed)

    # HTTP Basic Auth
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/conf.d/reverse-proxy/.htpasswd-${domain};  # Path inside container

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
    add_header Permissions-Policy "identity-credentials-get=*, geolocation=(), microphone=(), camera=()" always;

    # v5.10: CSP Header Handling (conditional)
EOF

    # CSP handling based on strip_csp flag
    if [[ "$strip_csp" == "true" ]]; then
        cat >> "$nginx_conf" <<'EOF'
    # CSP headers stripped (prevents blocking of proxy domain resources)
    proxy_hide_header Content-Security-Policy;
    proxy_hide_header Content-Security-Policy-Report-Only;
    proxy_hide_header X-Content-Security-Policy;
    proxy_hide_header X-WebKit-CSP;
EOF
    else
        cat >> "$nginx_conf" <<'EOF'
    # CSP headers preserved (may cause issues with inline scripts)
    # Note: Target site CSP may block proxy domain resources
EOF
    fi

    cat >> "$nginx_conf" <<EOF

    # VULN-003/004 FIX: Rate Limiting (increased for modern web apps)
    limit_req zone=reverseproxy_${domain//[.-]/_} burst=200 nodelay;
    limit_conn conn_limit_per_ip 200;  # Allow many parallel connections for webpack chunks (Claude.ai loads 40+ files)

    # Logging (error log only, no access log)
    access_log off;  # Privacy: no access logging
    error_log /var/log/nginx/reverse-proxy-${domain}-error.log warn;

    # Proxy directly to target site (v5.2: IPv4-only, prevents IPv6 unreachable errors)
    location / {
        # IPv4-only proxy_pass (resolved at config generation time)
        # Auto-monitored by vless-monitor-reverse-proxy-ips cron job
        proxy_pass https://${target_ipv4};
        resolver 8.8.8.8 ipv4=on valid=300s;
        resolver_timeout 5s;
        proxy_http_version 1.1;

        # SSL settings for upstream (target site)
        proxy_ssl_server_name on;
        proxy_ssl_name ${target_site};

        # v5.9: Enhanced cookie handling (multiple Set-Cookie headers for OAuth2)
        proxy_pass_header Set-Cookie;
        proxy_set_header Cookie \$http_cookie;

        # VULN-001 FIX: Hardcoded Host header (NOT \$host or \$http_host)
        proxy_set_header Host ${target_site};  # Target site (hardcoded)

        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # v5.9: CSRF Protection Headers
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Original-URL \$scheme://\$http_host\$request_uri;

        # v5.9: WebSocket support (with connection upgrade map)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        # v5.9: Timeouts (increased for WebSocket long-lived connections)
        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;  # 1 hour for WebSocket
        proxy_read_timeout 3600s;   # 1 hour for WebSocket

        # v5.9: Buffering (increased for OAuth2 large cookies >4kb)
        proxy_buffering on;
        proxy_buffer_size 32k;      # Increased from 16k
        proxy_buffers 16 32k;       # Increased from 8 16k
        proxy_busy_buffers_size 64k;  # Increased from 32k

        # v5.8: Cookie domain rewrite (CRITICAL for authorization)
        # Rewrites cookies from target site to proxy domain
        proxy_cookie_domain ${target_site} ${domain};
        proxy_cookie_path / /;
        proxy_cookie_flags ~ secure httponly samesite=lax;

        # v5.10: Intelligent URL rewriting (multiple patterns for better coverage)
        # Pattern 1: HTTPS URLs (most common)
        sub_filter 'https://${target_site}' 'https://${domain}';
        # Pattern 2: HTTP URLs (redirect to HTTPS)
        sub_filter 'http://${target_site}' 'https://${domain}';
        # Pattern 3: Protocol-relative URLs (//domain.com)
        sub_filter '//${target_site}' '//${domain}';
        # Pattern 4: Quoted URLs in JavaScript ("https://domain")
        sub_filter '"https://${target_site}' '"https://${domain}';
        sub_filter "'https://${target_site}" "'https://${domain}";
        # Pattern 5: URL objects in JSON (\"https://domain\")
        sub_filter '\\"https://${target_site}' '\\"https://${domain}';

        # Apply to multiple content types
        sub_filter_once off;
        sub_filter_types text/html text/css text/javascript application/javascript application/json;
        sub_filter_last_modified on;

        # v5.9: Referer rewriting (CRITICAL for CSRF protection)
        # Rewrites Referer from proxy domain to target domain
        set \$new_referer \$http_referer;
        if (\$http_referer ~* "^https?://${domain}(.*)$") {
            set \$new_referer "https://${target_site}\$1";
        }
        proxy_set_header Referer \$new_referer;

        # v5.8: Origin header rewriting (for CORS and anti-hotlinking)
        # Sets Origin to target site for proper CORS handling
        proxy_set_header Origin "https://${target_site}";
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
    listen 0.0.0.0:${port} ssl default_server;  # v4.3: Bridge network
    http2 on;  # Modern HTTP/2 syntax (Nginx 1.25+)
    server_name _;

    ssl_certificate ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;
    ssl_protocols TLSv1.3;

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

    # Create parent directory if it doesn't exist (CRITICAL FIX)
    mkdir -p "$NGINX_CONF_DIR" || {
        log_error "Failed to create directory: $NGINX_CONF_DIR"
        return 1
    }

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
# Rate: 100 requests per second per IP (increased for modern web apps)
# Note: Actual limit_req_zone directives are generated per domain

# VULN-005 FIX: Maximum request body size
client_max_body_size 10m;

# Timeouts (prevent slowloris attacks)
client_body_timeout 10s;
client_header_timeout 10s;
send_timeout 10s;

# Error responses for limit violations
limit_conn_status 429;  # Too Many Requests
limit_req_status 429;

# Hide Nginx version
server_tokens off;

# Include reverse proxy server blocks
# Include only domain configs (exclude http_context.conf)
include /etc/nginx/conf.d/reverse-proxy/*[!t].conf;
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
    echo "limit_req_zone \$binary_remote_addr zone=${zone_name}:10m rate=100r/s;" >> "$http_context_conf"

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

    if docker exec vless_nginx_reverseproxy nginx -t 2>&1; then
        log "✅ Nginx configuration is valid"
        return 0
    else
        log_error "❌ Nginx configuration is invalid"
        return 1
    fi
}

# ============================================================================
# Function: reload_nginx
# Description: Reloads Nginx configuration (graceful reload)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
reload_nginx() {
    log "Reloading Nginx (graceful)..."

    if docker exec vless_nginx_reverseproxy nginx -s reload 2>&1; then
        log "✅ Nginx reloaded successfully (zero downtime)"
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
        echo "  generate <domain> <target_site> <port> <username> <password_hash>"
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

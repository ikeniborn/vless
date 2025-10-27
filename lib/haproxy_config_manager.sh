#!/bin/bash
# lib/haproxy_config_manager.sh
#
# HAProxy Configuration Manager (v4.3 Unified Solution)
# Dynamic HAProxy configuration generation and management
#
# Features:
# - Unified haproxy.cfg generation via heredoc (PRD v4.1 compliant)
# - 3 frontends: 443 (SNI routing), 1080 (SOCKS5 TLS), 8118 (HTTP TLS)
# - Dynamic ACL/backend management for reverse proxies
# - Graceful reload without downtime
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-17

set -euo pipefail

# Configuration
VLESS_DIR="${VLESS_DIR:-/opt/vless}"
HAPROXY_CONFIG="${VLESS_DIR}/config/haproxy.cfg"
HAPROXY_CONTAINER="vless_haproxy"

# Source container management module (v5.22)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/container_management.sh" ]; then
    source "${SCRIPT_DIR}/container_management.sh"
fi

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [haproxy-config] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [haproxy-config] ERROR: $*" >&2
}

# =============================================================================
# Function: generate_haproxy_config
# Description: Generates unified haproxy.cfg via heredoc (v4.3)
#
# Parameters:
#   $1 - vless_domain: Domain for VLESS Reality (e.g., vless.ikeniborn.ru)
#   $2 - main_domain: Main domain for certificates (e.g., ikeniborn.ru)
#   $3 - stats_password: Password for stats page (optional)
#   $4 - enable_public_proxy: Enable public proxy frontends (true/false, default: false)
#
# Returns:
#   0 on success, 1 on failure
#
# Output:
#   Creates /opt/vless/config/haproxy.cfg
#
# Example:
#   generate_haproxy_config "vless.ikeniborn.ru" "ikeniborn.ru" "admin123" "true"
#
# v5.25 Changes:
#   - Added enable_public_proxy parameter for VLESS-only mode support
#   - Public proxy frontends (ports 1080/8118) generated conditionally
# =============================================================================
generate_haproxy_config() {
    local vless_domain="${1:-vless.example.com}"
    local main_domain="${2:-example.com}"
    local stats_password="${3:-$(openssl rand -hex 8)}"
    local enable_public_proxy="${4:-false}"

    log "Generating unified haproxy.cfg (v4.3)"
    log "  VLESS Domain: ${vless_domain}"
    log "  Main Domain: ${main_domain}"
    log "  Public Proxy: ${enable_public_proxy}"

    # Create backup if file exists
    if [ -f "${HAPROXY_CONFIG}" ]; then
        cp "${HAPROXY_CONFIG}" "${HAPROXY_CONFIG}.bak"
        log "  Backup created: ${HAPROXY_CONFIG}.bak"
    fi

    # Create config directory if not exists
    mkdir -p "$(dirname "${HAPROXY_CONFIG}")"

    # Generate public proxy sections conditionally (v5.25)
    local public_proxy_sections=""
    if [[ "${enable_public_proxy}" == "true" ]]; then
        public_proxy_sections=$(cat <<'PROXY_SECTIONS'

# ==============================================================================
# Frontend 2: Port 1080 - SOCKS5 TLS Termination
# Decrypts TLS, forwards plaintext SOCKS5 to Xray
# ==============================================================================
frontend socks5_tls
    bind *:1080 ssl crt /etc/letsencrypt/live/${main_domain}/combined.pem
    mode tcp
    option tcplog

    # Enable request inspection for SNI capture
    tcp-request inspect-delay 5s
    tcp-request content accept if TRUE

    # Log TLS info
    tcp-request content capture req.ssl_sni len 100

    default_backend xray_socks5_plaintext

# Backend for SOCKS5 (plaintext to Xray)
backend xray_socks5_plaintext
    mode tcp
    server xray vless_xray:10800 check inter 10s fall 3 rise 2

# ==============================================================================
# Frontend 3: Port 8118 - HTTP Proxy TLS Termination
# Decrypts TLS, forwards plaintext HTTP proxy to Xray
# ==============================================================================
frontend http_proxy_tls
    bind *:8118 ssl crt /etc/letsencrypt/live/${main_domain}/combined.pem
    mode tcp
    option tcplog

    # Enable request inspection for SNI capture
    tcp-request inspect-delay 5s
    tcp-request content accept if TRUE

    # Log TLS info
    tcp-request content capture req.ssl_sni len 100

    default_backend xray_http_plaintext

# Backend for HTTP Proxy (plaintext to Xray)
backend xray_http_plaintext
    mode tcp
    server xray vless_xray:18118 check inter 10s fall 3 rise 2
PROXY_SECTIONS
)
        # Replace ${main_domain} in the heredoc with actual value
        public_proxy_sections="${public_proxy_sections//\$\{main_domain\}/${main_domain}}"
    else
        public_proxy_sections=$(cat <<'VLESS_ONLY_COMMENT'

# ==============================================================================
# Public Proxy Frontends (DISABLED in VLESS-only mode)
# ==============================================================================
# To enable public proxy (SOCKS5 + HTTP with TLS termination):
#   1. Set ENABLE_PUBLIC_PROXY=true in installation
#   2. Configure domain and obtain Let's Encrypt certificate
#   3. Regenerate HAProxy configuration
#
# Public proxy provides:
#   - SOCKS5 TLS: Port 1080 (socks5s://)
#   - HTTP TLS: Port 8118 (https://)
# ==============================================================================
VLESS_ONLY_COMMENT
)
    fi

    # Generate haproxy.cfg via heredoc
    cat > "${HAPROXY_CONFIG}" <<EOF
# ==============================================================================
# HAProxy Configuration (v4.3 Unified Solution)
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================

# ==============================================================================
# Global Settings
# ==============================================================================
global
    log stdout format raw local0
    maxconn 4096

    # DH parameters for TLS
    tune.ssl.default-dh-param 2048

    # SSL/TLS configuration (TLS 1.3 ONLY per NFR-SEC-001)
    # NOTE: ssl-default-bind-ciphers is for TLS 1.2 and below (NOT used for TLS 1.3)
    # For TLS 1.3 ONLY, use ssl-default-bind-ciphersuites exclusively
    ssl-default-bind-ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.3

    # NOTE: user/group directives removed for bridge network mode (v4.3)
    # HAProxy Alpine image runs as user haproxy (uid=99) with NET_BIND_SERVICE capability
    # This allows binding to privileged ports (443/1080/8118) without running as root

# ==============================================================================
# Default Settings
# ==============================================================================
defaults
    log global
    timeout connect 5s
    timeout client 50s
    timeout server 50s
    option dontlognull

# ==============================================================================
# Frontend 1: Port 443 - SNI-based Routing (NO TLS termination)
# Routes traffic based on Server Name Indication to appropriate backend
# ==============================================================================
frontend https_sni_router
    bind *:443
    mode tcp
    option tcplog

    # Enable SNI inspection (read SNI from TLS ClientHello without decrypting)
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # ========== Dynamic ACLs for Reverse Proxies ==========
    # Populated dynamically via add_reverse_proxy_route()
    # Format:
    #   acl is_<domain_safe> req_ssl_sni -i <domain>
    #   use_backend nginx_<domain_safe> if is_<domain_safe>
    # =======================================================

    # Default: forward to VLESS Reality (handles all non-reverse-proxy traffic)
    # NOTE: VLESS Reality uses SNI of destination site (e.g., www.google.com),
    #       NOT the server domain. Therefore, VLESS must be default backend.
    #       Reverse proxy domains use explicit ACLs above.
    default_backend xray_vless

# Backend for VLESS Reality (TCP passthrough, NO TLS termination)
backend xray_vless
    mode tcp
    server xray vless_xray:8443 check inter 10s fall 3 rise 2
${public_proxy_sections}

# ==============================================================================
# Stats Page (localhost only)
# Access: http://127.0.0.1:9000/stats
# ==============================================================================
listen stats
    bind 127.0.0.1:9000
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats show-legends
    stats show-desc HAProxy v4.3 Unified Solution
    stats auth admin:${stats_password}
EOF

    local exit_code=$?

    # Set permissions to 644 (readable by HAProxy container user)
    if [ $exit_code -eq 0 ]; then
        chmod 644 "${HAPROXY_CONFIG}"
        chown root:root "${HAPROXY_CONFIG}" 2>/dev/null || true
    fi

    if [ $exit_code -eq 0 ]; then
        log "✅ haproxy.cfg generated successfully"
        log "  Location: ${HAPROXY_CONFIG}"
        log "  Stats page: http://127.0.0.1:9000/stats (admin:${stats_password})"
        return 0
    else
        log_error "❌ Failed to generate haproxy.cfg"

        # Restore backup if generation failed
        if [ -f "${HAPROXY_CONFIG}.bak" ]; then
            mv "${HAPROXY_CONFIG}.bak" "${HAPROXY_CONFIG}"
            log "  Backup restored"
        fi

        return 1
    fi
}

# =============================================================================
# Function: add_reverse_proxy_route
# Description: Adds dynamic ACL and backend for reverse proxy domain
#
# Parameters:
#   $1 - domain: Reverse proxy domain (e.g., claude.ikeniborn.ru)
#   $2 - port: Nginx backend port (e.g., 9443)
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   add_reverse_proxy_route "claude.ikeniborn.ru" 9443
# =============================================================================
add_reverse_proxy_route() {
    local domain="$1"
    local port="$2"

    if [ -z "$domain" ] || [ -z "$port" ]; then
        log_error "Usage: add_reverse_proxy_route <domain> <port>"
        return 1
    fi

    log "Adding reverse proxy route: ${domain} → 127.0.0.1:${port}"

    # v5.22: Ensure HAProxy container is running before adding route
    if command -v ensure_container_running &> /dev/null; then
        if ! ensure_container_running "vless_haproxy"; then
            log_error "Cannot add route: HAProxy container not available"
            return 1
        fi
    fi

    # Backup current config
    cp "${HAPROXY_CONFIG}" "${HAPROXY_CONFIG}.bak"

    # Sanitize domain for ACL name (replace . with _)
    local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')

    # Check if route already exists
    if grep -q "acl is_${domain_safe}" "${HAPROXY_CONFIG}"; then
        log "⚠️  Route already exists: ${domain}"
        return 0
    fi

    # Find insertion point for ACL (after "# ========== Dynamic ACLs" section)
    local marker_line=$(grep -n "# ========== Dynamic ACLs for Reverse Proxies ==========" "${HAPROXY_CONFIG}" | cut -d: -f1)

    if [ -z "$marker_line" ]; then
        log_error "Marker not found in haproxy.cfg (dynamic ACLs section)"
        return 1
    fi

    # Calculate insertion line (after marker + 5 lines of comments)
    local insert_line=$((marker_line + 5))

    # Insert ACL and use_backend
    sed -i "${insert_line}a\\    acl is_${domain_safe} req_ssl_sni -i ${domain}" "${HAPROXY_CONFIG}"
    sed -i "$((insert_line+1))a\\    use_backend nginx_${domain_safe} if is_${domain_safe}" "${HAPROXY_CONFIG}"
    sed -i "$((insert_line+2))a\\ " "${HAPROXY_CONFIG}"

    # Add backend at end of file (before stats section)
    local stats_line=$(grep -n "^# ==.*Stats Page" "${HAPROXY_CONFIG}" | cut -d: -f1)

    if [ -z "$stats_line" ]; then
        # No stats section, add at EOF
        cat >> "${HAPROXY_CONFIG}" <<EOF

# Backend for reverse proxy: ${domain}
backend nginx_${domain_safe}
    mode tcp
    server nginx_${port} vless_nginx_reverseproxy:${port} check inter 10s fall 3 rise 2
EOF
    else
        # Insert before stats section
        sed -i "$((stats_line-1))a\\# Backend for reverse proxy: ${domain}" "${HAPROXY_CONFIG}"
        sed -i "$((stats_line))a\\backend nginx_${domain_safe}" "${HAPROXY_CONFIG}"
        sed -i "$((stats_line+1))a\\    mode tcp" "${HAPROXY_CONFIG}"
        sed -i "$((stats_line+2))a\\    server nginx_${port} vless_nginx_reverseproxy:${port} check inter 10s fall 3 rise 2" "${HAPROXY_CONFIG}"
        sed -i "$((stats_line+3))a\\ " "${HAPROXY_CONFIG}"
    fi

    # Validate config
    if ! validate_haproxy_config; then
        log_error "Invalid configuration, rolling back..."
        mv "${HAPROXY_CONFIG}.bak" "${HAPROXY_CONFIG}"
        return 1
    fi

    # Graceful reload (v5.21: silent mode to suppress timeout warnings)
    if ! reload_haproxy --silent; then
        log_error "Failed to reload HAProxy"
        mv "${HAPROXY_CONFIG}.bak" "${HAPROXY_CONFIG}"
        return 1
    fi

    log "✅ Route added successfully: ${domain} → 127.0.0.1:${port}"
    return 0
}

# =============================================================================
# Function: remove_reverse_proxy_route
# Description: Removes dynamic ACL and backend for reverse proxy domain
#
# Parameters:
#   $1 - domain: Reverse proxy domain to remove
#
# Returns:
#   0 on success, 1 on failure
# =============================================================================
remove_reverse_proxy_route() {
    local domain="$1"

    if [ -z "$domain" ]; then
        log_error "Usage: remove_reverse_proxy_route <domain>"
        return 1
    fi

    log "Removing reverse proxy route: ${domain}"

    # v5.22: Ensure HAProxy container is running before removing route
    if command -v ensure_container_running &> /dev/null; then
        if ! ensure_container_running "vless_haproxy"; then
            log_error "Cannot remove route: HAProxy container not available"
            return 1
        fi
    fi

    # Backup
    cp "${HAPROXY_CONFIG}" "${HAPROXY_CONFIG}.bak"

    local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')

    # Remove ACL lines
    sed -i "/acl is_${domain_safe} req_ssl_sni/d" "${HAPROXY_CONFIG}"
    sed -i "/use_backend nginx_${domain_safe} if is_${domain_safe}/d" "${HAPROXY_CONFIG}"

    # Remove backend section
    # Find line with "# Backend for reverse proxy: ${domain}"
    local backend_start=$(grep -n "# Backend for reverse proxy: ${domain}" "${HAPROXY_CONFIG}" | cut -d: -f1)

    if [ -n "$backend_start" ]; then
        # Delete backend section (4 lines: comment + backend + mode + server)
        sed -i "${backend_start},$((backend_start+3))d" "${HAPROXY_CONFIG}"
    fi

    # Validate and reload
    if ! validate_haproxy_config; then
        log_error "Invalid configuration, rolling back..."
        mv "${HAPROXY_CONFIG}.bak" "${HAPROXY_CONFIG}"
        return 1
    fi

    # v5.21: Silent mode to suppress timeout warnings during removal
    if ! reload_haproxy --silent; then
        log_error "Failed to reload HAProxy"
        mv "${HAPROXY_CONFIG}.bak" "${HAPROXY_CONFIG}"
        return 1
    fi

    log "✅ Route removed: ${domain}"
    return 0
}

# =============================================================================
# Function: validate_haproxy_config
# Description: Validates HAProxy configuration
#
# Returns:
#   0 if valid, 1 if invalid
# =============================================================================
validate_haproxy_config() {
    if [ ! -f "${HAPROXY_CONFIG}" ]; then
        log_error "Config file not found: ${HAPROXY_CONFIG}"
        return 1
    fi

    # Check if HAProxy container is running
    if ! docker ps | grep -q "${HAPROXY_CONTAINER}"; then
        log "⚠️  HAProxy container not running, skipping validation"
        return 0
    fi

    # Validate config via docker exec (capture output once to avoid race conditions)
    local validation_output
    local validation_exit_code

    validation_output=$(docker exec "${HAPROXY_CONTAINER}" haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg 2>&1)
    validation_exit_code=$?

    # Check exit code first
    if [ $validation_exit_code -eq 0 ]; then
        log "✅ HAProxy config is valid"
        return 0
    else
        # Only show error if validation actually failed (not just warnings)
        # HAProxy returns 0 for valid config even with warnings
        if echo "$validation_output" | grep -qi "error\|failed\|invalid"; then
            log_error "❌ HAProxy config has errors:"
            echo "$validation_output" >&2
            return 1
        else
            # Exit code non-zero but no errors in output - treat as valid (warnings only)
            log "⚠️  HAProxy config valid with warnings:"
            echo "$validation_output" >&2
            return 0
        fi
    fi
}

# =============================================================================
# Function: reload_haproxy
# Description: Gracefully reloads HAProxy without downtime
#
# Parameters:
#   --silent : Suppress info/warning messages (only show errors)
#
# Returns:
#   0 on success, 1 on failure
# =============================================================================
reload_haproxy() {
    local silent_mode=false

    # Parse parameters
    if [[ "${1:-}" == "--silent" ]]; then
        silent_mode=true
    fi

    if ! docker ps | grep -q "${HAPROXY_CONTAINER}"; then
        log_error "HAProxy container not running"
        return 1
    fi

    if [[ "$silent_mode" == "false" ]]; then
        log "Reloading HAProxy (graceful, no downtime)..."
    fi

    # Get current PID
    local old_pid=$(docker exec "${HAPROXY_CONTAINER}" pidof haproxy 2>/dev/null)

    if [ -z "$old_pid" ]; then
        log_error "Failed to get HAProxy PID"
        return 1
    fi

    # Graceful reload: haproxy -f config.cfg -sf <old_pid>
    # Note: Capture output to check for errors (warnings are OK, only errors should fail)
    # Use timeout to prevent hanging when active connections are present
    local reload_output
    reload_output=$(timeout 10 docker exec "${HAPROXY_CONTAINER}" haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf ${old_pid} 2>&1)
    local exit_code=$?

    # Exit code 124 means timeout occurred (reload is still in progress, but that's OK)
    # The new HAProxy process started successfully and will finish gracefully in background
    if [ $exit_code -eq 124 ]; then
        if [[ "$silent_mode" == "false" ]]; then
            log "ℹ️  HAProxy reload: graceful shutdown in progress (normal with active connections)"
        fi
        exit_code=0  # Consider it success
    fi

    # Check if reload has actual errors (not just warnings)
    if echo "$reload_output" | grep -qi "\[ALERT\]"; then
        log_error "❌ HAProxy reload failed with ALERT:"
        echo "$reload_output" | grep -i "\[ALERT\]" >&2
        echo "" >&2
        log_error "TROUBLESHOOTING:"
        log_error "  1. Check config permissions: sudo ls -la ${HAPROXY_CONFIG}"
        log_error "     (Should be: -rw-r--r-- root root)"
        log_error "  2. Test config: docker exec ${HAPROXY_CONTAINER} haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"
        return 1
    fi

    # Verify container is still running after reload
    sleep 1
    if ! docker ps | grep -q "${HAPROXY_CONTAINER}"; then
        log_error "❌ HAProxy container died after reload"
        return 1
    fi

    # Log warnings if present (but don't fail)
    if [[ "$silent_mode" == "false" ]]; then
        if echo "$reload_output" | grep -qi "\[WARNING\]"; then
            log "⚠️  HAProxy reload completed with warnings (non-critical):"
            echo "$reload_output" | grep -i "\[WARNING\]" >&2
        fi

        log "✅ HAProxy reloaded successfully"
    fi

    return 0
}

# =============================================================================
# Function: check_haproxy_status
# Description: Checks HAProxy container status and backend health
#
# Returns:
#   Prints status information to stdout
#   Returns 0 if healthy, 1 if issues detected
# =============================================================================
check_haproxy_status() {
    echo "HAProxy Status (v4.3 Unified Solution)"
    echo "========================================"
    echo ""

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${HAPROXY_CONTAINER}$"; then
        echo "❌ HAProxy container not found"
        return 1
    fi

    # Check container status
    local container_status=$(docker inspect "${HAPROXY_CONTAINER}" -f '{{.State.Status}}' 2>/dev/null || echo "unknown")
    local container_health=$(docker inspect "${HAPROXY_CONTAINER}" -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")

    echo "Container Status:"
    if [[ "$container_status" == "running" ]]; then
        echo "  ✓ Running"
    else
        echo "  ✗ Status: $container_status"
        return 1
    fi

    if [[ "$container_health" != "no-healthcheck" ]]; then
        if [[ "$container_health" == "healthy" ]]; then
            echo "  ✓ Health: Healthy"
        else
            echo "  ⚠️  Health: $container_health"
        fi
    fi

    # Check HAProxy process
    local haproxy_pid=$(docker exec "${HAPROXY_CONTAINER}" pidof haproxy 2>/dev/null || echo "")
    if [[ -n "$haproxy_pid" ]]; then
        echo "  ✓ Process running (PID: $haproxy_pid)"
    else
        echo "  ✗ HAProxy process not running"
        return 1
    fi

    echo ""

    # Check ports
    echo "Port Bindings:"
    if ss -tuln | grep -q ":443 "; then
        echo "  ✓ Port 443 (HTTPS SNI Router) - LISTENING"
    else
        echo "  ✗ Port 443 - NOT LISTENING"
    fi

    if ss -tuln | grep -q ":1080 "; then
        echo "  ✓ Port 1080 (SOCKS5 TLS) - LISTENING"
    else
        echo "  ℹ️  Port 1080 (SOCKS5 TLS) - Not configured or disabled"
    fi

    if ss -tuln | grep -q ":8118 "; then
        echo "  ✓ Port 8118 (HTTP Proxy TLS) - LISTENING"
    else
        echo "  ℹ️  Port 8118 (HTTP Proxy TLS) - Not configured or disabled"
    fi

    if ss -tuln | grep -q "127.0.0.1:9000 "; then
        echo "  ✓ Port 9000 (Stats Page) - LISTENING (localhost only)"
    else
        echo "  ℹ️  Port 9000 (Stats Page) - Not accessible"
    fi

    echo ""

    # Stats page info
    echo "Stats Page:"
    echo "  URL: http://127.0.0.1:9000/stats"
    echo "  Access: localhost only (use SSH tunnel from remote)"
    echo "  SSH Tunnel: ssh -L 9000:localhost:9000 user@server"

    echo ""

    # Backend check (basic connectivity test)
    echo "Backend Connectivity:"

    # Check Xray VLESS backend
    if nc -z 127.0.0.1 8443 2>/dev/null; then
        echo "  ✓ Xray VLESS (127.0.0.1:8443) - UP"
    else
        echo "  ✗ Xray VLESS (127.0.0.1:8443) - DOWN"
    fi

    # Check Xray SOCKS5 backend
    if nc -z 127.0.0.1 10800 2>/dev/null; then
        echo "  ✓ Xray SOCKS5 (127.0.0.1:10800) - UP"
    else
        echo "  ℹ️  Xray SOCKS5 (127.0.0.1:10800) - Not configured or disabled"
    fi

    # Check Xray HTTP backend
    if nc -z 127.0.0.1 18118 2>/dev/null; then
        echo "  ✓ Xray HTTP (127.0.0.1:18118) - UP"
    else
        echo "  ℹ️  Xray HTTP (127.0.0.1:18118) - Not configured or disabled"
    fi

    echo ""

    # Count configured reverse proxy routes
    local proxy_count=0
    if [ -f "${HAPROXY_CONFIG}" ]; then
        proxy_count=$(grep "acl is_" "${HAPROXY_CONFIG}" | grep -v "is_vless" | wc -l)
    fi

    echo "Configured Routes:"
    echo "  VLESS Reality: 1"
    echo "  Reverse Proxies: ${proxy_count}"
    echo "  Proxy Services: 2 (SOCKS5, HTTP)"

    echo ""
    echo "For detailed stats, access: http://127.0.0.1:9000/stats"

    return 0
}

# =============================================================================
# Function: list_haproxy_routes
# Description: Lists all configured reverse proxy routes
#
# Returns:
#   Prints routes to stdout
# =============================================================================
list_haproxy_routes() {
    if [ ! -f "${HAPROXY_CONFIG}" ]; then
        echo "HAProxy config not found"
        return 1
    fi

    echo "HAProxy Routes:"
    echo "==============="
    echo ""

    # Extract VLESS route
    local vless_domain=$(grep "acl is_vless req_ssl_sni" "${HAPROXY_CONFIG}" | sed -n 's/.*req_ssl_sni -i \(.*\)/\1/p')
    if [ -n "$vless_domain" ]; then
        echo "  VLESS Reality:"
        echo "    - ${vless_domain} → 127.0.0.1:8443"
        echo ""
    fi

    # Extract reverse proxy routes
    echo "  Reverse Proxies:"
    grep "acl is_" "${HAPROXY_CONFIG}" | grep -v "is_vless" | while read -r line; do
        local domain=$(echo "$line" | sed -n 's/.*req_ssl_sni -i \(.*\)/\1/p')
        if [ -n "$domain" ]; then
            # Find corresponding backend port
            local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')
            local port=$(grep -A 2 "^backend nginx_${domain_safe}" "${HAPROXY_CONFIG}" | grep "server" | sed -n 's/.*127\.0\.0\.1:\([0-9]*\).*/\1/p')
            echo "    - ${domain} → 127.0.0.1:${port}"
        fi
    done

    echo ""
    echo "  Proxy Services:"
    echo "    - SOCKS5 TLS: *:1080 → 127.0.0.1:10800"
    echo "    - HTTP TLS: *:8118 → 127.0.0.1:18118"
}

# =============================================================================
# Main execution (for testing)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [ $# -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  generate <vless_domain> <main_domain> [stats_pass]"
        echo "                          - Generate unified haproxy.cfg"
        echo "  add <domain> <port>     - Add reverse proxy route"
        echo "  remove <domain>         - Remove reverse proxy route"
        echo "  validate                - Validate configuration"
        echo "  reload                  - Gracefully reload HAProxy"
        echo "  status                  - Check HAProxy status and health"
        echo "  list                    - List all routes"
        echo ""
        echo "Examples:"
        echo "  $0 generate vless.example.com example.com"
        echo "  $0 add claude.example.com 9443"
        echo "  $0 remove claude.example.com"
        echo "  $0 status"
        echo "  $0 list"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        generate)
            generate_haproxy_config "$@"
            ;;
        add)
            add_reverse_proxy_route "$@"
            ;;
        remove)
            remove_reverse_proxy_route "$@"
            ;;
        validate)
            validate_haproxy_config
            ;;
        reload)
            reload_haproxy
            ;;
        status)
            check_haproxy_status
            ;;
        list)
            list_haproxy_routes
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
fi

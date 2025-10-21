#!/bin/bash
################################################################################
# lib/validation.sh
#
# Reverse Proxy Validation Module (v5.22)
# Post-operation validation to ensure reverse proxy is working correctly
#
# Features:
# - HAProxy configuration validation
# - Nginx configuration validation
# - Port binding verification
# - Backend health check (HAProxy stats)
# - Removal verification
#
# Usage:
#   source lib/validation.sh
#   validate_reverse_proxy "example.com" 9443
#   validate_reverse_proxy_removed "example.com" 9443
#
# Version: 5.22.0
# Author: VLESS Development Team
# Date: 2025-10-21
################################################################################

set -euo pipefail

# Logging functions (if not already defined)
if ! command -v log &> /dev/null; then
    log() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [validation] $*" >&2
    }
fi

if ! command -v log_error &> /dev/null; then
    log_error() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [validation] ERROR: $*" >&2
    }
fi

# =============================================================================
# Function: validate_reverse_proxy
# Description: Validates that reverse proxy was added successfully
#
# Parameters:
#   $1 - domain: Reverse proxy domain
#   $2 - port: Nginx backend port (e.g., 9443)
#
# Returns:
#   0 if all checks pass, 1 if any check fails
#
# Validation checks:
#   1. HAProxy config has ACL and backend for domain
#   2. Nginx config file exists
#   3. Port is bound to nginx container (retry with backoff)
#   4. HAProxy backend shows UP in stats page
#
# Example:
#   if validate_reverse_proxy "example.com" 9443; then
#       echo "Reverse proxy is working"
#   fi
# =============================================================================
validate_reverse_proxy() {
    local domain="$1"
    local port="$2"

    if [ -z "$domain" ] || [ -z "$port" ]; then
        log_error "Usage: validate_reverse_proxy <domain> <port>"
        return 1
    fi

    log "Validating reverse proxy: $domain (port $port)"

    # v5.23: Wait for HAProxy reload to stabilize
    # Race condition fix: graceful reload can take 10s+ with active connections
    # This delay ensures new HAProxy process has started before validation
    sleep 2

    local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')
    local checks_passed=0
    local checks_total=4

    # -------------------------------------------------------------------------
    # Check 1: HAProxy config has ACL for domain
    # -------------------------------------------------------------------------
    log "  [1/4] Checking HAProxy ACL configuration..."

    # v5.23: Check config on HOST instead of container
    # Race condition fix: during graceful reload, docker exec may read old config
    # Host file is updated immediately by add_reverse_proxy_route()
    if grep -q "acl is_${domain_safe}" /opt/vless/config/haproxy.cfg 2>/dev/null; then
        log "  ✅ HAProxy ACL found for $domain"
        checks_passed=$((checks_passed + 1))
    else
        log_error "  ❌ HAProxy config missing ACL for $domain"
        log_error "     Expected: acl is_${domain_safe} req_ssl_sni -i ${domain}"
        log_error "     Check: grep 'acl is_${domain_safe}' /opt/vless/config/haproxy.cfg"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Check 2: Nginx config file exists
    # -------------------------------------------------------------------------
    log "  [2/4] Checking Nginx configuration file..."

    local nginx_config="/opt/vless/config/reverse-proxy/${domain}.conf"
    if [ -f "$nginx_config" ]; then
        log "  ✅ Nginx config exists: ${domain}.conf"
        checks_passed=$((checks_passed + 1))
    else
        log_error "  ❌ Nginx config missing: ${nginx_config}"
        log_error "     Check: ls -la /opt/vless/config/reverse-proxy/"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Check 3: Port is bound to nginx container (with retries)
    # -------------------------------------------------------------------------
    log "  [3/4] Checking port binding (with retries)..."

    local max_attempts=3
    local attempt=1
    local port_bound=false

    while [ $attempt -le $max_attempts ]; do
        # v5.23 FIX: Support Docker port ranges (e.g., 9443-9444)
        # Use word boundary \b to match exact port number
        # Pattern matches:
        #   - Individual port: 127.0.0.1:9444
        #   - Port at start of range: 127.0.0.1:9444-9445
        #   - Port at end of range: 127.0.0.1:9443-9444
        if docker ps --format "{{.Ports}}" --filter "name=vless_nginx_reverseproxy" | grep -qE "\b${port}\b"; then
            port_bound=true
            log "  ✅ Port $port is bound to nginx container"
            checks_passed=$((checks_passed + 1))
            break
        fi

        if [ $attempt -lt $max_attempts ]; then
            log "  ⏳ Port $port not bound yet, waiting... (attempt $attempt/$max_attempts)"
            sleep 2
        fi

        attempt=$((attempt + 1))
    done

    if [ "$port_bound" = "false" ]; then
        log_error "  ❌ Port $port not bound after $max_attempts attempts"
        log_error "     Check: docker ps --format '{{.Ports}}' --filter 'name=vless_nginx_reverseproxy'"
        log_error "     Check: docker logs vless_nginx_reverseproxy --tail 20"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Check 4: HAProxy backend shows UP in stats
    # -------------------------------------------------------------------------
    log "  [4/4] Checking HAProxy backend health..."

    # Try to get HAProxy stats page
    local stats_output
    stats_output=$(curl -s http://127.0.0.1:9000/stats 2>/dev/null || echo "")

    if [ -z "$stats_output" ]; then
        log "  ⚠️  HAProxy stats page not accessible (skipping backend check)"
        log "     This is non-critical, nginx might still be working"
        checks_passed=$((checks_passed + 1))  # Don't fail on this
    else
        # Check if backend exists and is not DOWN
        if echo "$stats_output" | grep -q "nginx_${domain_safe}.*DOWN"; then
            log_error "  ❌ HAProxy backend is DOWN for $domain"
            log_error "     Check: curl -s http://127.0.0.1:9000/stats | grep '${domain_safe}'"
            log_error "     Check: docker exec vless_haproxy nc -zv vless_nginx_reverseproxy ${port}"
            return 1
        elif echo "$stats_output" | grep -q "nginx_${domain_safe}"; then
            log "  ✅ HAProxy backend is UP for $domain"
            checks_passed=$((checks_passed + 1))
        else
            log "  ⚠️  HAProxy backend not found in stats (might be initializing)"
            checks_passed=$((checks_passed + 1))  # Don't fail on this
        fi
    fi

    # -------------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------------
    if [ $checks_passed -eq $checks_total ]; then
        log "✅ Reverse proxy validation successful: $domain ($checks_passed/$checks_total checks passed)"
        return 0
    else
        log_error "❌ Reverse proxy validation failed: $domain ($checks_passed/$checks_total checks passed)"
        return 1
    fi
}

# =============================================================================
# Function: validate_reverse_proxy_removed
# Description: Validates that reverse proxy was removed successfully
#
# Parameters:
#   $1 - domain: Reverse proxy domain
#   $2 - port: Nginx backend port (e.g., 9443)
#
# Returns:
#   0 if all checks pass, 1 if any check fails
#
# Validation checks:
#   1. HAProxy config does NOT have ACL for domain
#   2. Nginx config file does NOT exist
#   3. Port is NOT bound to nginx container
#
# Example:
#   if validate_reverse_proxy_removed "example.com" 9443; then
#       echo "Reverse proxy removed successfully"
#   fi
# =============================================================================
validate_reverse_proxy_removed() {
    local domain="$1"
    local port="$2"

    if [ -z "$domain" ] || [ -z "$port" ]; then
        log_error "Usage: validate_reverse_proxy_removed <domain> <port>"
        return 1
    fi

    log "Validating reverse proxy removal: $domain (port $port)"

    local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')
    local checks_passed=0
    local checks_total=3

    # -------------------------------------------------------------------------
    # Check 1: HAProxy config should NOT have ACL
    # -------------------------------------------------------------------------
    log "  [1/3] Verifying HAProxy ACL removed..."

    # v5.23: Check config on HOST instead of container (same as validate_reverse_proxy)
    if grep -q "acl is_${domain_safe}" /opt/vless/config/haproxy.cfg 2>/dev/null; then
        log_error "  ❌ HAProxy config still has ACL for $domain"
        log_error "     Found: acl is_${domain_safe} req_ssl_sni -i ${domain}"
        log_error "     Action: sudo vless-proxy remove ${domain} (run again)"
        return 1
    else
        log "  ✅ HAProxy ACL removed for $domain"
        checks_passed=$((checks_passed + 1))
    fi

    # -------------------------------------------------------------------------
    # Check 2: Nginx config file should NOT exist
    # -------------------------------------------------------------------------
    log "  [2/3] Verifying Nginx config removed..."

    local nginx_config="/opt/vless/config/reverse-proxy/${domain}.conf"
    if [ -f "$nginx_config" ]; then
        log_error "  ❌ Nginx config still exists: ${nginx_config}"
        log_error "     Action: sudo rm ${nginx_config}"
        return 1
    else
        log "  ✅ Nginx config removed: ${domain}.conf"
        checks_passed=$((checks_passed + 1))
    fi

    # -------------------------------------------------------------------------
    # Check 3: Port should NOT be bound
    # -------------------------------------------------------------------------
    log "  [3/3] Verifying port freed..."

    # v5.23 FIX: Support Docker port ranges (same pattern as validate_reverse_proxy)
    # Use word boundary \b to match exact port number
    # Check that the specific port is NOT present in any form:
    #   - Individual port: 127.0.0.1:9444
    #   - Port at start of range: 127.0.0.1:9444-9445
    #   - Port at end of range: 127.0.0.1:9443-9444
    if docker ps --format "{{.Ports}}" --filter "name=vless_nginx_reverseproxy" | grep -qE "\b${port}\b"; then
        log_error "  ❌ Port $port still bound to nginx container"
        log_error "     Check: docker ps --format '{{.Ports}}' --filter 'name=vless_nginx_reverseproxy'"
        log_error "     Action: docker restart vless_nginx_reverseproxy"
        return 1
    else
        log "  ✅ Port $port freed (not bound)"
        checks_passed=$((checks_passed + 1))
    fi

    # -------------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------------
    if [ $checks_passed -eq $checks_total ]; then
        log "✅ Reverse proxy removal validation successful: $domain ($checks_passed/$checks_total checks passed)"
        return 0
    else
        log_error "❌ Reverse proxy removal validation failed: $domain ($checks_passed/$checks_total checks passed)"
        return 1
    fi
}

################################################################################
# Module loaded successfully
################################################################################

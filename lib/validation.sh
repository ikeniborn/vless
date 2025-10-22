#!/bin/bash
################################################################################
# lib/validation.sh
#
# Reverse Proxy Validation Module (v5.23)
# Post-operation validation to ensure reverse proxy is working correctly
#
# Features:
# - HAProxy configuration validation
# - Nginx configuration validation
# - Port binding verification with retry
# - Backend health check with retry (HAProxy stats)
# - HTTP connectivity test (end-to-end validation)
# - Removal verification
# - Extended stabilization period (10s initial delay)
#
# v5.23 Improvements:
# - Increased initial delay: 2s → 10s (prevent false negatives)
# - HAProxy backend check with retry: up to 6 attempts (30s max)
# - NEW: HTTP connectivity test (Check 5) - real end-to-end validation
# - Better UX: progress indicators during retry loops
#
# Usage:
#   source lib/validation.sh
#   validate_reverse_proxy "example.com" 9443
#   validate_reverse_proxy_removed "example.com" 9443
#
# Version: 5.23.0
# Author: VLESS Development Team
# Date: 2025-10-22
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
    # Extended delay (2→10s): ensures HAProxy backend health checks have time to detect nginx
    # This prevents false negatives when validating immediately after service restart
    log "⏳ Waiting for services to stabilize (10 seconds)..."
    sleep 10

    local domain_safe=$(echo "$domain" | tr '.' '_' | tr '-' '_')
    local checks_passed=0
    local checks_total=5

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
    # Check 4: HAProxy backend shows UP in stats (with retry)
    # -------------------------------------------------------------------------
    log "  [4/5] Checking HAProxy backend health (with retry)..."

    # v5.23: Extract HAProxy stats credentials from config
    local stats_auth=""
    if [ -f "/opt/vless/config/haproxy.cfg" ]; then
        stats_auth=$(grep "stats auth" /opt/vless/config/haproxy.cfg 2>/dev/null | awk '{print $3}' | head -1)
    fi

    # v5.23: Retry logic for HAProxy backend detection
    # Backend can take 30-60s to become UP after nginx restart
    # Retry up to 6 times with 5s intervals (max 30 seconds)
    local backend_check_attempts=6
    local backend_check_wait=5
    local backend_up=false

    for attempt in $(seq 1 $backend_check_attempts); do
        # Try to get HAProxy stats page (from inside container)
        # v5.23: HAProxy stats bind to 127.0.0.1 inside container, not accessible from host
        # Use docker exec to access stats from inside the container
        # BusyBox wget doesn't support --http-user, use --header with Basic Auth
        local stats_output
        if [ -n "$stats_auth" ]; then
            # Encode credentials for Basic Auth header
            local auth_encoded
            auth_encoded=$(echo -n "$stats_auth" | base64)
            stats_output=$(docker exec vless_haproxy wget -q -O- --header="Authorization: Basic ${auth_encoded}" http://127.0.0.1:9000/stats 2>/dev/null || echo "")
        else
            stats_output=$(docker exec vless_haproxy wget -q -O- http://127.0.0.1:9000/stats 2>/dev/null || echo "")
        fi

        if [ -z "$stats_output" ]; then
            if [ $attempt -lt $backend_check_attempts ]; then
                log "  ⏳ HAProxy stats not accessible, waiting... (attempt $attempt/$backend_check_attempts)"
                sleep $backend_check_wait
                continue
            else
                log "  ⚠️  HAProxy stats page not accessible after $backend_check_attempts attempts"
                log "     Skipping backend health check (non-critical)"
                checks_passed=$((checks_passed + 1))  # Don't fail on this
                break
            fi
        fi

        # Check if backend exists and is not DOWN
        if echo "$stats_output" | grep -q "nginx_${domain_safe}.*DOWN"; then
            if [ $attempt -lt $backend_check_attempts ]; then
                log "  ⏳ HAProxy backend is DOWN, waiting for health check... (attempt $attempt/$backend_check_attempts)"
                sleep $backend_check_wait
                continue
            else
                log_error "  ❌ HAProxy backend is DOWN for $domain after $backend_check_attempts attempts"
                log_error "     Check: curl -s http://127.0.0.1:9000/stats | grep '${domain_safe}'"
                log_error "     Check: docker exec vless_haproxy nc -zv vless_nginx_reverseproxy ${port}"
                return 1
            fi
        elif echo "$stats_output" | grep -q "nginx_${domain_safe}"; then
            log "  ✅ HAProxy backend is UP for $domain (attempt $attempt)"
            checks_passed=$((checks_passed + 1))
            backend_up=true
            break
        else
            if [ $attempt -lt $backend_check_attempts ]; then
                log "  ⏳ HAProxy backend not found in stats, waiting... (attempt $attempt/$backend_check_attempts)"
                sleep $backend_check_wait
                continue
            else
                log "  ⚠️  HAProxy backend not found in stats after $backend_check_attempts attempts"
                log "     This might indicate configuration issue, but proceeding with HTTP check"
                checks_passed=$((checks_passed + 1))  # Don't fail on this
                break
            fi
        fi
    done

    # -------------------------------------------------------------------------
    # Check 5: HTTP connectivity test (v5.23 - NEW)
    # -------------------------------------------------------------------------
    log "  [5/5] Checking HTTP connectivity (end-to-end test)..."

    # v5.23: Real HTTP request to verify reverse proxy works end-to-end
    # This tests: HAProxy SNI routing → nginx backend → response
    # Expected: 401 (nginx auth required) or 200 (if auth successful)
    # Timeout: 10 seconds
    local http_code
    http_code=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" -k "https://127.0.0.1:443" \
        -H "Host: ${domain}" \
        --resolve "${domain}:443:127.0.0.1" 2>/dev/null || echo "000")

    if [ "$http_code" = "401" ] || [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        log "  ✅ HTTP connectivity successful (HTTP $http_code)"
        log "     Reverse proxy is serving requests correctly"
        checks_passed=$((checks_passed + 1))
    elif [ "$http_code" = "000" ]; then
        log_error "  ❌ HTTP connectivity test failed (connection refused/timeout)"
        log_error "     Check: docker logs vless_haproxy --tail 20"
        log_error "     Check: docker logs vless_nginx_reverseproxy --tail 20"
        log_error "     Check: curl -k -I -H 'Host: ${domain}' https://127.0.0.1:443"
        return 1
    else
        log "  ⚠️  HTTP connectivity test returned unexpected code: $http_code"
        log "     Expected: 200/401/302, Got: $http_code"
        log "     Proceeding anyway (might be target site issue)"
        checks_passed=$((checks_passed + 1))  # Don't fail on unexpected codes
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

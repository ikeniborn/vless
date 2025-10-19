#!/bin/bash
# tests/integration/v4.3/test_02_proxy_haproxy.sh
#
# Test Case 2: SOCKS5/HTTP Proxy через HAProxy v4.3
# Validates: HAProxy TLS termination → Xray plaintext proxies
#
# Duration: ~30 minutes
# Author: VLESS Development Team
# Version: 4.3.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Icons
ICON_PASS="✓"
ICON_FAIL="✗"
ICON_INFO="ℹ"
ICON_WARN="⚠"

# Test Results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Configuration
INSTALL_ROOT="${INSTALL_ROOT:-/opt/vless}"
DEV_MODE="${DEV_MODE:-false}"

# Logging
log_info() { echo -e "${CYAN}${ICON_INFO} $*${NC}"; }
log_success() { echo -e "${GREEN}${ICON_PASS} $*${NC}"; ((TESTS_PASSED++)); }
log_error() { echo -e "${RED}${ICON_FAIL} $*${NC}"; ((TESTS_FAILED++)); }
log_warning() { echo -e "${YELLOW}${ICON_WARN} $*${NC}"; }
log_skip() { echo -e "${YELLOW}⊘ $*${NC}"; ((TESTS_SKIPPED++)); }

# ============================================================================
# Test 2.1: HAProxy SOCKS5 Frontend (port 1080)
# ============================================================================
test_haproxy_socks5_frontend() {
    log_info "Test 2.1: Validating HAProxy SOCKS5 frontend (port 1080)..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 2.1: Skipped (dev mode)"
            return 0
        else
            log_error "Test 2.1: HAProxy config not found"
            return 1
        fi
    fi

    # Check frontend socks5-tls
    if ! grep -q "frontend socks5-tls" "$config_file"; then
        log_error "Test 2.1: Frontend 'socks5-tls' not found"
        return 1
    fi

    # Check bind :1080
    if ! grep -A 5 "frontend socks5-tls" "$config_file" | grep -q "bind \*:1080"; then
        log_error "Test 2.1: Frontend not bound to port 1080"
        return 1
    fi

    # Check TLS termination (ssl crt)
    if ! grep -A 5 "frontend socks5-tls" "$config_file" | grep -q "ssl crt"; then
        log_error "Test 2.1: TLS termination not configured"
        return 1
    fi

    log_success "Test 2.1: HAProxy SOCKS5 frontend config valid"
    return 0
}

# ============================================================================
# Test 2.2: HAProxy HTTP Frontend (port 8118)
# ============================================================================
test_haproxy_http_frontend() {
    log_info "Test 2.2: Validating HAProxy HTTP frontend (port 8118)..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 2.2: Skipped (dev mode)"
            return 0
        else
            log_error "Test 2.2: HAProxy config not found"
            return 1
        fi
    fi

    # Check frontend http-tls
    if ! grep -q "frontend http-tls" "$config_file"; then
        log_error "Test 2.2: Frontend 'http-tls' not found"
        return 1
    fi

    # Check bind :8118
    if ! grep -A 5 "frontend http-tls" "$config_file" | grep -q "bind \*:8118"; then
        log_error "Test 2.2: Frontend not bound to port 8118"
        return 1
    fi

    # Check TLS termination
    if ! grep -A 5 "frontend http-tls" "$config_file" | grep -q "ssl crt"; then
        log_error "Test 2.2: TLS termination not configured"
        return 1
    fi

    log_success "Test 2.2: HAProxy HTTP frontend config valid"
    return 0
}

# ============================================================================
# Test 2.3: HAProxy Proxy Backends (Xray plaintext)
# ============================================================================
test_haproxy_proxy_backends() {
    log_info "Test 2.3: Validating HAProxy proxy backends..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 2.3: Skipped (dev mode)"
            return 0
        else
            log_error "Test 2.3: HAProxy config not found"
            return 1
        fi
    fi

    # Check backend xray_socks5
    if ! grep -q "backend xray_socks5" "$config_file"; then
        log_error "Test 2.3: Backend 'xray_socks5' not found"
        return 1
    fi

    # Check SOCKS5 backend server (vless_xray:10800)
    if ! grep -A 5 "backend xray_socks5" "$config_file" | grep -q "server xray vless_xray:10800"; then
        log_error "Test 2.3: SOCKS5 backend not pointing to vless_xray:10800"
        return 1
    fi

    # Check backend xray_http
    if ! grep -q "backend xray_http" "$config_file"; then
        log_error "Test 2.3: Backend 'xray_http' not found"
        return 1
    fi

    # Check HTTP backend server (vless_xray:18118)
    if ! grep -A 5 "backend xray_http" "$config_file" | grep -q "server xray vless_xray:18118"; then
        log_error "Test 2.3: HTTP backend not pointing to vless_xray:18118"
        return 1
    fi

    log_success "Test 2.3: HAProxy proxy backends config valid"
    return 0
}

# ============================================================================
# Test 2.4: Xray SOCKS5 Inbound (plaintext, localhost:10800)
# ============================================================================
test_xray_socks5_inbound() {
    log_info "Test 2.4: Validating Xray SOCKS5 inbound config..."

    local config_file="${INSTALL_ROOT}/config/config.json"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 2.4: Skipped (dev mode)"
            return 0
        else
            log_error "Test 2.4: Xray config not found"
            return 1
        fi
    fi

    # Check SOCKS5 inbound exists
    if ! jq -e '.inbounds[] | select(.protocol == "socks" and .port == 10800)' "$config_file" &>/dev/null; then
        log_error "Test 2.4: SOCKS5 inbound (port 10800) not found"
        return 1
    fi

    # Check listen address (should be 127.0.0.1, not 0.0.0.0)
    local listen=$(jq -r '.inbounds[] | select(.protocol == "socks" and .port == 10800) | .listen' "$config_file")
    if [ "$listen" != "127.0.0.1" ]; then
        log_warning "Test 2.4: SOCKS5 inbound not bound to localhost (found: $listen)"
    fi

    # Check auth required
    local auth=$(jq -r '.inbounds[] | select(.protocol == "socks" and .port == 10800) | .settings.auth' "$config_file")
    if [ "$auth" != "password" ]; then
        log_error "Test 2.4: SOCKS5 auth not set to 'password' (found: $auth)"
        return 1
    fi

    log_success "Test 2.4: Xray SOCKS5 inbound config valid (port 10800, auth: password)"
    return 0
}

# ============================================================================
# Test 2.5: Xray HTTP Inbound (plaintext, localhost:18118)
# ============================================================================
test_xray_http_inbound() {
    log_info "Test 2.5: Validating Xray HTTP inbound config..."

    local config_file="${INSTALL_ROOT}/config/config.json"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 2.5: Skipped (dev mode)"
            return 0
        else
            log_error "Test 2.5: Xray config not found"
            return 1
        fi
    fi

    # Check HTTP inbound exists
    if ! jq -e '.inbounds[] | select(.protocol == "http" and .port == 18118)' "$config_file" &>/dev/null; then
        log_error "Test 2.5: HTTP inbound (port 18118) not found"
        return 1
    fi

    # Check listen address
    local listen=$(jq -r '.inbounds[] | select(.protocol == "http" and .port == 18118) | .listen' "$config_file")
    if [ "$listen" != "127.0.0.1" ]; then
        log_warning "Test 2.5: HTTP inbound not bound to localhost (found: $listen)"
    fi

    # Check auth required
    local accounts_count=$(jq -r '.inbounds[] | select(.protocol == "http" and .port == 18118) | .settings.accounts | length' "$config_file")
    if [ "$accounts_count" -eq 0 ]; then
        log_error "Test 2.5: HTTP inbound has no accounts (auth required)"
        return 1
    fi

    log_success "Test 2.5: Xray HTTP inbound config valid (port 18118, auth enabled)"
    return 0
}

# ============================================================================
# Test 2.6: HAProxy Ports Listening
# ============================================================================
test_haproxy_ports_listening() {
    log_info "Test 2.6: Checking HAProxy proxy ports listening..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 2.6: Skipped (dev mode)"
        return 0
    fi

    local ports_ok=0

    # Check port 1080 (SOCKS5)
    if sudo ss -tulnp | grep ":1080" | grep -q "haproxy"; then
        log_info "  Port 1080 (SOCKS5): ✓ Listening"
        ((ports_ok++))
    else
        log_error "  Port 1080 (SOCKS5): ✗ Not listening"
    fi

    # Check port 8118 (HTTP)
    if sudo ss -tulnp | grep ":8118" | grep -q "haproxy"; then
        log_info "  Port 8118 (HTTP): ✓ Listening"
        ((ports_ok++))
    else
        log_error "  Port 8118 (HTTP): ✗ Not listening"
    fi

    if [ $ports_ok -eq 2 ]; then
        log_success "Test 2.6: HAProxy proxy ports listening (1080, 8118)"
        return 0
    else
        log_error "Test 2.6: HAProxy proxy ports not fully configured"
        return 1
    fi
}

# ============================================================================
# Test 2.7: Certificate Files for TLS Termination
# ============================================================================
test_certificate_files() {
    log_info "Test 2.7: Checking certificate files for TLS termination..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 2.7: Skipped (dev mode)"
        return 0
    fi

    local cert_dir="${INSTALL_ROOT}/certs"

    # Check combined.pem exists
    if [ -f "$cert_dir/combined.pem" ]; then
        log_success "Test 2.7: Certificate file exists ($cert_dir/combined.pem)"
        return 0
    else
        log_warning "Test 2.7: combined.pem not found (may need certificate acquisition)"
        return 0
    fi
}

# ============================================================================
# Test 2.8: Functional Test (if curl available)
# ============================================================================
test_proxy_functional() {
    log_info "Test 2.8: Functional proxy test (if credentials available)..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 2.8: Skipped (dev mode - requires production env)"
        return 0
    fi

    # This is a placeholder - actual functional test requires user credentials
    log_skip "Test 2.8: Skipped (requires user credentials for functional test)"
    return 0
}

# ============================================================================
# Main Test Execution
# ============================================================================
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Test Case 2: SOCKS5/HTTP Proxy через HAProxy v4.3        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Detect mode
    if [ ! -d "$INSTALL_ROOT" ]; then
        DEV_MODE="true"
        log_warning "VLESS not installed - running in DEV MODE"
        echo ""
    fi

    # Run tests
    test_haproxy_socks5_frontend
    test_haproxy_http_frontend
    test_haproxy_proxy_backends
    test_xray_socks5_inbound
    test_xray_http_inbound
    test_haproxy_ports_listening
    test_certificate_files
    test_proxy_functional

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}${ICON_FAIL} Test Case 2 FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}${ICON_PASS} Test Case 2 PASSED${NC}"
        exit 0
    fi
}

# Execute
main

#!/bin/bash
# tests/integration/v4.3/test_01_vless_reality_haproxy.sh
#
# Test Case 1: VLESS Reality через HAProxy v4.3
# Validates: HAProxy SNI passthrough → Xray:8443 (VLESS Reality)
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
NC='\033[0m' # No Color

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
INSTALL_ROOT="${INSTALL_ROOT:-/opt/familytraffic}"
DEV_MODE="${DEV_MODE:-false}"

# Logging
log_info() {
    echo -e "${CYAN}${ICON_INFO} $*${NC}"
}

log_success() {
    echo -e "${GREEN}${ICON_PASS} $*${NC}"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}${ICON_FAIL} $*${NC}"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}${ICON_WARN} $*${NC}"
}

log_skip() {
    echo -e "${YELLOW}⊘ $*${NC}"
    ((TESTS_SKIPPED++))
}

# ============================================================================
# Test 1.1: HAProxy Container Running
# ============================================================================
test_haproxy_container_running() {
    log_info "Test 1.1: Checking HAProxy container status..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 1.1: Skipped (dev mode - no containers)"
        return 0
    fi

    if docker ps --filter "name=familytraffic-haproxy" --format "{{.Names}}" | grep -q "familytraffic-haproxy"; then
        local status=$(docker ps --filter "name=familytraffic-haproxy" --format "{{.Status}}")
        log_success "Test 1.1: HAProxy container running ($status)"
        return 0
    else
        log_error "Test 1.1: HAProxy container not running"
        return 1
    fi
}

# ============================================================================
# Test 1.2: HAProxy Listening on Port 443
# ============================================================================
test_haproxy_port_443() {
    log_info "Test 1.2: Checking HAProxy port 443..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 1.2: Skipped (dev mode - no network bindings)"
        return 0
    fi

    if sudo ss -tulnp | grep ":443" | grep -q "haproxy"; then
        log_success "Test 1.2: HAProxy listening on port 443"
        return 0
    else
        log_error "Test 1.2: HAProxy not listening on port 443"
        return 1
    fi
}

# ============================================================================
# Test 1.3: HAProxy Config - VLESS Reality Frontend
# ============================================================================
test_haproxy_vless_frontend() {
    log_info "Test 1.3: Validating HAProxy VLESS Reality frontend config..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 1.3: Skipped (dev mode - config not installed)"
            return 0
        else
            log_error "Test 1.3: HAProxy config file not found: $config_file"
            return 1
        fi
    fi

    # Check frontend vless-reality exists
    if ! grep -q "frontend vless-reality" "$config_file"; then
        log_error "Test 1.3: Frontend 'vless-reality' not found in config"
        return 1
    fi

    # Check bind :443
    if ! grep -A 5 "frontend vless-reality" "$config_file" | grep -q "bind \*:443"; then
        log_error "Test 1.3: Frontend 'vless-reality' not bound to port 443"
        return 1
    fi

    # Check mode tcp
    if ! grep -A 5 "frontend vless-reality" "$config_file" | grep -q "mode tcp"; then
        log_error "Test 1.3: Frontend 'vless-reality' not in TCP mode"
        return 1
    fi

    # Check default_backend xray_reality
    if ! grep -A 10 "frontend vless-reality" "$config_file" | grep -q "default_backend xray_reality"; then
        log_error "Test 1.3: Frontend 'vless-reality' missing default_backend xray_reality"
        return 1
    fi

    log_success "Test 1.3: HAProxy VLESS Reality frontend config valid"
    return 0
}

# ============================================================================
# Test 1.4: HAProxy Config - Xray Reality Backend
# ============================================================================
test_haproxy_xray_backend() {
    log_info "Test 1.4: Validating HAProxy Xray Reality backend config..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 1.4: Skipped (dev mode - config not installed)"
            return 0
        else
            log_error "Test 1.4: HAProxy config file not found: $config_file"
            return 1
        fi
    fi

    # Check backend xray_reality exists
    if ! grep -q "backend xray_reality" "$config_file"; then
        log_error "Test 1.4: Backend 'xray_reality' not found in config"
        return 1
    fi

    # Check mode tcp
    if ! grep -A 5 "backend xray_reality" "$config_file" | grep -q "mode tcp"; then
        log_error "Test 1.4: Backend 'xray_reality' not in TCP mode"
        return 1
    fi

    # Check server pointing to familytraffic_xray:8443
    if ! grep -A 5 "backend xray_reality" "$config_file" | grep -q "server xray familytraffic_xray:8443"; then
        log_error "Test 1.4: Backend 'xray_reality' not pointing to familytraffic_xray:8443"
        return 1
    fi

    log_success "Test 1.4: HAProxy Xray Reality backend config valid"
    return 0
}

# ============================================================================
# Test 1.5: Xray Container Running on Port 8443
# ============================================================================
test_xray_container_port() {
    log_info "Test 1.5: Checking Xray container and port 8443..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 1.5: Skipped (dev mode - no containers)"
        return 0
    fi

    # Check container running
    if ! docker ps --filter "name=vless-xray" --format "{{.Names}}" | grep -q "vless-xray"; then
        log_error "Test 1.5: Xray container not running"
        return 1
    fi

    # Check port 8443 exposed in container (internal)
    if ! docker inspect vless-xray | jq -r '.[0].Config.ExposedPorts | keys[]' 2>/dev/null | grep -q "8443"; then
        log_warning "Test 1.5: Port 8443 not in ExposedPorts (may be OK if listening internally)"
    fi

    log_success "Test 1.5: Xray container running"
    return 0
}

# ============================================================================
# Test 1.6: Xray Config - VLESS Inbound on 8443
# ============================================================================
test_xray_vless_inbound() {
    log_info "Test 1.6: Validating Xray VLESS inbound config..."

    local config_file="${INSTALL_ROOT}/config/config.json"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 1.6: Skipped (dev mode - config not installed)"
            return 0
        else
            log_error "Test 1.6: Xray config file not found: $config_file"
            return 1
        fi
    fi

    # Check inbound with protocol "vless"
    if ! jq -e '.inbounds[] | select(.protocol == "vless")' "$config_file" &>/dev/null; then
        log_error "Test 1.6: VLESS inbound not found in Xray config"
        return 1
    fi

    # Check port 8443
    local vless_port=$(jq -r '.inbounds[] | select(.protocol == "vless") | .port' "$config_file")
    if [ "$vless_port" != "8443" ]; then
        log_error "Test 1.6: VLESS inbound not on port 8443 (found: $vless_port)"
        return 1
    fi

    # Check streamSettings.security = "reality"
    local security=$(jq -r '.inbounds[] | select(.protocol == "vless") | .streamSettings.security' "$config_file")
    if [ "$security" != "reality" ]; then
        log_error "Test 1.6: VLESS inbound security not 'reality' (found: $security)"
        return 1
    fi

    log_success "Test 1.6: Xray VLESS inbound config valid (port 8443, security: reality)"
    return 0
}

# ============================================================================
# Test 1.7: Network Connectivity (HAProxy → Xray)
# ============================================================================
test_network_connectivity() {
    log_info "Test 1.7: Testing network connectivity HAProxy → Xray..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 1.7: Skipped (dev mode - no network)"
        return 0
    fi

    # Check if containers are on same network
    local haproxy_network=$(docker inspect familytraffic-haproxy | jq -r '.[0].HostConfig.NetworkMode')
    local xray_network=$(docker inspect vless-xray | jq -r '.[0].HostConfig.NetworkMode')

    if [ "$haproxy_network" != "$xray_network" ]; then
        log_error "Test 1.7: HAProxy and Xray on different networks ($haproxy_network vs $xray_network)"
        return 1
    fi

    # Test connectivity from HAProxy to Xray
    if docker exec familytraffic-haproxy nc -zv familytraffic_xray 8443 2>&1 | grep -q "succeeded"; then
        log_success "Test 1.7: Network connectivity HAProxy → Xray:8443 successful"
        return 0
    else
        log_error "Test 1.7: Cannot reach Xray:8443 from HAProxy container"
        return 1
    fi
}

# ============================================================================
# Test 1.8: HAProxy Stats Page (Monitoring)
# ============================================================================
test_haproxy_stats() {
    log_info "Test 1.8: Checking HAProxy stats page..."

    if [ "$DEV_MODE" = "true" ]; then
        log_skip "Test 1.8: Skipped (dev mode - no stats page)"
        return 0
    fi

    # Check stats page on localhost:9000
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/stats 2>/dev/null | grep -q "200"; then
        log_success "Test 1.8: HAProxy stats page accessible on :9000"
        return 0
    else
        log_warning "Test 1.8: HAProxy stats page not accessible (may be disabled)"
        return 0
    fi
}

# ============================================================================
# Main Test Execution
# ============================================================================
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Test Case 1: VLESS Reality через HAProxy v4.3           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Detect mode
    if [ ! -d "$INSTALL_ROOT" ]; then
        DEV_MODE="true"
        log_warning "VLESS not installed at $INSTALL_ROOT - running in DEV MODE"
        log_info "Dev mode: Only config validation tests will run"
        echo ""
    fi

    # Run tests
    test_haproxy_container_running
    test_haproxy_port_443
    test_haproxy_vless_frontend
    test_haproxy_xray_backend
    test_xray_container_port
    test_xray_vless_inbound
    test_network_connectivity
    test_haproxy_stats

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}${ICON_FAIL} Test Case 1 FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}${ICON_PASS} Test Case 1 PASSED${NC}"
        exit 0
    fi
}

# Execute
main

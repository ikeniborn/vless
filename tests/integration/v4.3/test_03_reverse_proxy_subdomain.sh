#!/bin/bash
# tests/integration/v4.3/test_03_reverse_proxy_subdomain.sh
#
# Test Case 3: Reverse Proxy без порта (subdomain access)
# Validates: HAProxy SNI routing → Nginx → Xray → Target
#
# Duration: ~1 hour
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

ICON_PASS="✓"
ICON_FAIL="✗"
ICON_INFO="ℹ"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

INSTALL_ROOT="${INSTALL_ROOT:-/opt/vless}"
DEV_MODE="${DEV_MODE:-false}"

log_info() { echo -e "${CYAN}${ICON_INFO} $*${NC}"; }
log_success() { echo -e "${GREEN}${ICON_PASS} $*${NC}"; ((TESTS_PASSED++)); }
log_error() { echo -e "${RED}${ICON_FAIL} $*${NC}"; ((TESTS_FAILED++)); }
log_skip() { echo -e "${YELLOW}⊘ $*${NC}"; ((TESTS_SKIPPED++)); }

# ============================================================================
# Test 3.1: Reverse Proxy Database Schema (v4.3 ports 9443-9452)
# ============================================================================
test_reverse_proxy_db_schema() {
    log_info "Test 3.1: Validating reverse proxy database schema..."

    local db_file="${INSTALL_ROOT}/data/reverse-proxies.json"

    if [ ! -f "$db_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 3.1: Skipped (dev mode - no database)"
            return 0
        else
            log_info "Test 3.1: Database not found (OK if no proxies configured yet)"
            log_skip "Test 3.1: Skipped (no reverse proxies configured)"
            return 0
        fi
    fi

    # Check JSON validity
    if ! jq empty "$db_file" 2>/dev/null; then
        log_error "Test 3.1: Database JSON invalid"
        return 1
    fi

    # Check schema version
    local version=$(jq -r '.version // "unknown"' "$db_file")
    if [ "$version" != "2.0" ]; then
        log_error "Test 3.1: Database schema version mismatch (expected 2.0, found: $version)"
        return 1
    fi

    log_success "Test 3.1: Reverse proxy database schema valid (v2.0)"
    return 0
}

# ============================================================================
# Test 3.2: Port Range 9443-9452 (not 8443-8452)
# ============================================================================
test_port_range() {
    log_info "Test 3.2: Verifying port range 9443-9452..."

    # Check docker-compose generator
    local generator_file="${INSTALL_ROOT}/../lib/docker_compose_manager.sh"
    if [ ! -f "$generator_file" ]; then
        generator_file="lib/docker_compose_manager.sh"
    fi

    if [ ! -f "$generator_file" ]; then
        log_skip "Test 3.2: Skipped (docker_compose_manager.sh not found)"
        return 0
    fi

    # Check for 9443-9452 range
    if grep -q "9443.*9452" "$generator_file"; then
        log_success "Test 3.2: Port range 9443-9452 configured correctly"
        return 0
    else
        log_error "Test 3.2: Port range 9443-9452 not found in docker_compose_manager.sh"
        return 1
    fi
}

# ============================================================================
# Test 3.3: HAProxy Dynamic ACL Section
# ============================================================================
test_haproxy_dynamic_acl() {
    log_info "Test 3.3: Checking HAProxy dynamic ACL section..."

    local config_file="${INSTALL_ROOT}/config/haproxy.cfg"

    if [ ! -f "$config_file" ]; then
        if [ "$DEV_MODE" = "true" ]; then
            log_skip "Test 3.3: Skipped (dev mode)"
            return 0
        else
            log_error "Test 3.3: HAProxy config not found"
            return 1
        fi
    fi

    # Check DYNAMIC_REVERSE_PROXY_ROUTES marker
    if ! grep -q "# === DYNAMIC_REVERSE_PROXY_ROUTES ===" "$config_file"; then
        log_error "Test 3.3: Dynamic ACL section marker not found"
        return 1
    fi

    log_success "Test 3.3: HAProxy dynamic ACL section present"
    return 0
}

# ============================================================================
# Test 3.4: HAProxy Route Management Functions
# ============================================================================
test_haproxy_route_functions() {
    log_info "Test 3.4: Verifying HAProxy route management functions..."

    local manager_file="${INSTALL_ROOT}/../lib/haproxy_config_manager.sh"
    if [ ! -f "$manager_file" ]; then
        manager_file="lib/haproxy_config_manager.sh"
    fi

    if [ ! -f "$manager_file" ]; then
        log_error "Test 3.4: haproxy_config_manager.sh not found"
        return 1
    fi

    # Check required functions exist
    local required_functions=(
        "add_reverse_proxy_route"
        "remove_reverse_proxy_route"
        "list_haproxy_routes"
        "reload_haproxy"
    )

    local functions_ok=0
    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$manager_file" || grep -q "^function ${func}" "$manager_file"; then
            ((functions_ok++))
        else
            log_error "  Function '$func' not found"
        fi
    done

    if [ $functions_ok -eq ${#required_functions[@]} ]; then
        log_success "Test 3.4: All HAProxy route management functions present"
        return 0
    else
        log_error "Test 3.4: Missing HAProxy route functions ($functions_ok/${#required_functions[@]})"
        return 1
    fi
}

# ============================================================================
# Test 3.5: Nginx Config Generator (port 9443-9452)
# ============================================================================
test_nginx_config_generator() {
    log_info "Test 3.5: Checking Nginx config generator..."

    local generator_file="${INSTALL_ROOT}/../lib/nginx_config_generator.sh"
    if [ ! -f "$generator_file" ]; then
        generator_file="lib/nginx_config_generator.sh"
    fi

    if [ ! -f "$generator_file" ]; then
        log_error "Test 3.5: nginx_config_generator.sh not found"
        return 1
    fi

    # Check for 9443-9452 port references
    if grep -q "9443.*9452" "$generator_file"; then
        log_success "Test 3.5: Nginx config generator uses port range 9443-9452"
        return 0
    else
        log_error "Test 3.5: Nginx config generator missing 9443-9452 port range"
        return 1
    fi
}

# ============================================================================
# Test 3.6: CLI Integration (vless-setup-proxy, vless-proxy)
# ============================================================================
test_cli_integration() {
    log_info "Test 3.6: Checking CLI integration..."

    local setup_script="${INSTALL_ROOT}/../scripts/vless-setup-proxy"
    local proxy_cli="${INSTALL_ROOT}/../cli/vless-proxy"

    if [ ! -f "$setup_script" ]; then
        setup_script="scripts/vless-setup-proxy"
    fi
    if [ ! -f "$proxy_cli" ]; then
        proxy_cli="cli/vless-proxy"
    fi

    local cli_ok=0

    # Check vless-setup-proxy
    if [ -f "$setup_script" ]; then
        if grep -q "4.3" "$setup_script"; then
            ((cli_ok++))
        else
            log_error "  vless-setup-proxy not updated to v4.3"
        fi
    else
        log_error "  vless-setup-proxy not found"
    fi

    # Check vless-proxy
    if [ -f "$proxy_cli" ]; then
        if grep -q "4.3" "$proxy_cli"; then
            ((cli_ok++))
        else
            log_error "  vless-proxy not updated to v4.3"
        fi
    else
        log_error "  vless-proxy not found"
    fi

    if [ $cli_ok -eq 2 ]; then
        log_success "Test 3.6: CLI tools updated to v4.3"
        return 0
    else
        log_error "Test 3.6: CLI tools not fully updated ($cli_ok/2)"
        return 1
    fi
}

# ============================================================================
# Test 3.7: Subdomain Access Format (NO port number)
# ============================================================================
test_subdomain_format() {
    log_info "Test 3.7: Verifying subdomain access format (no port)..."

    local proxy_cli="${INSTALL_ROOT}/../cli/vless-proxy"
    if [ ! -f "$proxy_cli" ]; then
        proxy_cli="cli/vless-proxy"
    fi

    if [ ! -f "$proxy_cli" ]; then
        log_skip "Test 3.7: Skipped (vless-proxy not found)"
        return 0
    fi

    # Check that URL format is https://domain (NOT https://domain:port)
    # Look for patterns that explicitly say "no port" or show https://domain format
    if grep -q "https://\${domain}" "$proxy_cli" || grep -q "БЕЗ номера порта" "$proxy_cli"; then
        log_success "Test 3.7: Subdomain access format correct (https://domain, no port)"
        return 0
    else
        log_error "Test 3.7: Subdomain access format unclear (check for port numbers in URLs)"
        return 1
    fi
}

# ============================================================================
# Test 3.8: Certificate Requirement (DNS validation)
# ============================================================================
test_certificate_requirement() {
    log_info "Test 3.8: Verifying certificate requirement and DNS validation..."

    local cert_manager="${INSTALL_ROOT}/../lib/certificate_manager.sh"
    if [ ! -f "$cert_manager" ]; then
        cert_manager="lib/certificate_manager.sh"
    fi

    if [ ! -f "$cert_manager" ]; then
        log_error "Test 3.8: certificate_manager.sh not found"
        return 1
    fi

    # Check for DNS validation function
    if grep -q "validate_dns_for_domain" "$cert_manager"; then
        log_success "Test 3.8: DNS validation integrated in certificate workflow"
        return 0
    else
        log_error "Test 3.8: DNS validation function not found"
        return 1
    fi
}

# ============================================================================
# Main Test Execution
# ============================================================================
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Test Case 3: Reverse Proxy Subdomain Access (v4.3)        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$INSTALL_ROOT" ]; then
        DEV_MODE="true"
        log_info "Running in DEV MODE (VLESS not installed)"
        echo ""
    fi

    # Run tests
    test_reverse_proxy_db_schema
    test_port_range
    test_haproxy_dynamic_acl
    test_haproxy_route_functions
    test_nginx_config_generator
    test_cli_integration
    test_subdomain_format
    test_certificate_requirement

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${NC}"
    echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}${ICON_FAIL} Test Case 3 FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}${ICON_PASS} Test Case 3 PASSED${NC}"
        exit 0
    fi
}

main

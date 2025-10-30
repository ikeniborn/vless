#!/bin/bash
#
# External Proxy Test Suite
# Part of VLESS+Reality VPN Deployment System (v5.23)
#
# Purpose: Test external proxy management functionality
#
# Usage: sudo bash test_external_proxy.sh
#
# Version: 5.23.0
# Date: 2025-10-25

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Test directory (use temp location to avoid affecting production)
readonly TEST_ROOT="/tmp/vless_test_$$"
readonly TEST_CONFIG_DIR="${TEST_ROOT}/config"
readonly TEST_LIB_DIR="${TEST_ROOT}/lib"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# SETUP & TEARDOWN
# =============================================================================

setup_test_environment() {
    echo -e "${CYAN}Setting up test environment...${NC}"

    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_LIB_DIR"

    # Copy required modules
    if [[ -d "/opt/vless/lib" ]]; then
        cp /opt/vless/lib/external_proxy_manager.sh "$TEST_LIB_DIR/" 2>/dev/null || true
        cp /opt/vless/lib/xray_routing_manager.sh "$TEST_LIB_DIR/" 2>/dev/null || true
    elif [[ -d "$(dirname "${BASH_SOURCE[0]}")/../" ]]; then
        # Development mode - copy from project lib/
        local project_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
        cp "$project_lib/external_proxy_manager.sh" "$TEST_LIB_DIR/" 2>/dev/null || true
        cp "$project_lib/xray_routing_manager.sh" "$TEST_LIB_DIR/" 2>/dev/null || true
    fi

    # Override paths for testing
    export EXTERNAL_PROXY_DB="${TEST_CONFIG_DIR}/external_proxy.json"
    export XRAY_CONFIG="${TEST_CONFIG_DIR}/xray_config.json"

    # Source modules if available
    if [[ -f "${TEST_LIB_DIR}/external_proxy_manager.sh" ]]; then
        source "${TEST_LIB_DIR}/external_proxy_manager.sh"
    fi

    if [[ -f "${TEST_LIB_DIR}/xray_routing_manager.sh" ]]; then
        source "${TEST_LIB_DIR}/xray_routing_manager.sh"
    fi

    # Create minimal xray_config.json for testing
    cat > "$XRAY_CONFIG" <<'EOF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"port": 443, "protocol": "vless"}],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF

    echo -e "${GREEN}✓ Test environment ready${NC}"
    echo ""
}

teardown_test_environment() {
    echo ""
    echo -e "${CYAN}Cleaning up test environment...${NC}"
    rm -rf "$TEST_ROOT"
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# =============================================================================
# TEST UTILITIES
# =============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Expected: $expected"
        echo "    Actual: $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"

    ((TESTS_RUN++))

    if [[ -f "$file_path" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    File not found: $file_path"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_json_valid() {
    local file_path="$1"
    local test_name="$2"

    ((TESTS_RUN++))

    if jq empty "$file_path" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Invalid JSON in: $file_path"
        ((TESTS_FAILED++))
        return 1
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

test_01_init_database() {
    echo -e "${BLUE}Test 1: Initialize External Proxy Database${NC}"

    if declare -f init_external_proxy_db >/dev/null 2>&1; then
        init_external_proxy_db >/dev/null 2>&1

        assert_file_exists "$EXTERNAL_PROXY_DB" "Database file created"
        assert_json_valid "$EXTERNAL_PROXY_DB" "Database is valid JSON"

        local enabled=$(jq -r '.enabled' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "")
        assert_equals "false" "$enabled" "Default enabled state is false"

        local proxy_count=$(jq -r '.proxies | length' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "-1")
        assert_equals "0" "$proxy_count" "Initial proxy count is zero"
    else
        echo -e "  ${YELLOW}⊘ Skipped (init_external_proxy_db not available)${NC}"
    fi

    echo ""
}

test_02_validate_config() {
    echo -e "${BLUE}Test 2: Configuration Validation${NC}"

    if declare -f validate_proxy_config >/dev/null 2>&1; then
        # Test valid configuration
        if validate_proxy_config "socks5s" "proxy.example.com" "1080" "user" "pass" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Valid config accepted"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}✗${NC} Valid config rejected"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))

        # Test invalid port
        if ! validate_proxy_config "socks5" "example.com" "99999" "" "" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Invalid port rejected"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}✗${NC} Invalid port accepted"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))

        # Test invalid type
        if ! validate_proxy_config "invalid-type" "example.com" "1080" "" "" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Invalid type rejected"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}✗${NC} Invalid type accepted"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    else
        echo -e "  ${YELLOW}⊘ Skipped (validate_proxy_config not available)${NC}"
    fi

    echo ""
}

test_03_add_proxy() {
    echo -e "${BLUE}Test 3: Add External Proxy${NC}"

    if declare -f add_external_proxy >/dev/null 2>&1; then
        # Add test proxy
        local proxy_id
        proxy_id=$(add_external_proxy "socks5s" "test.proxy.com" "1080" "testuser" "testpass" 2>/dev/null || echo "")

        if [[ -n "$proxy_id" ]]; then
            echo -e "  ${GREEN}✓${NC} Proxy added successfully (ID: $proxy_id)"
            ((TESTS_PASSED++))

            # Verify proxy exists in database
            local exists=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .id' \
                "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "")

            if [[ "$exists" == "$proxy_id" ]]; then
                echo -e "  ${GREEN}✓${NC} Proxy found in database"
                ((TESTS_PASSED++))
            else
                echo -e "  ${RED}✗${NC} Proxy not found in database"
                ((TESTS_FAILED++))
            fi

            # Verify proxy type
            local proxy_type=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .type' \
                "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "")
            assert_equals "socks5s" "$proxy_type" "Proxy type is correct"

            # Verify proxy address
            local proxy_address=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .address' \
                "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "")
            assert_equals "test.proxy.com" "$proxy_address" "Proxy address is correct"

            # Store proxy_id for next tests
            echo "$proxy_id" > "${TEST_ROOT}/test_proxy_id"
        else
            echo -e "  ${RED}✗${NC} Failed to add proxy"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    else
        echo -e "  ${YELLOW}⊘ Skipped (add_external_proxy not available)${NC}"
    fi

    echo ""
}

test_04_set_active_proxy() {
    echo -e "${BLUE}Test 4: Set Active Proxy${NC}"

    if [[ ! -f "${TEST_ROOT}/test_proxy_id" ]]; then
        echo -e "  ${YELLOW}⊘ Skipped (no test proxy available)${NC}"
        echo ""
        return 0
    fi

    local proxy_id
    proxy_id=$(cat "${TEST_ROOT}/test_proxy_id")

    if declare -f set_active_proxy >/dev/null 2>&1; then
        set_active_proxy "$proxy_id" >/dev/null 2>&1

        local is_active=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .active' \
            "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "false")

        assert_equals "true" "$is_active" "Proxy marked as active"
    else
        echo -e "  ${YELLOW}⊘ Skipped (set_active_proxy not available)${NC}"
    fi

    echo ""
}

test_05_generate_xray_outbound() {
    echo -e "${BLUE}Test 5: Generate Xray Outbound JSON${NC}"

    if [[ ! -f "${TEST_ROOT}/test_proxy_id" ]]; then
        echo -e "  ${YELLOW}⊘ Skipped (no test proxy available)${NC}"
        echo ""
        return 0
    fi

    local proxy_id
    proxy_id=$(cat "${TEST_ROOT}/test_proxy_id")

    if declare -f generate_xray_outbound_json >/dev/null 2>&1; then
        local outbound_json
        outbound_json=$(generate_xray_outbound_json "$proxy_id" 2>/dev/null || echo "")

        if [[ -n "$outbound_json" ]]; then
            echo -e "  ${GREEN}✓${NC} Outbound JSON generated"
            ((TESTS_PASSED++))

            # Validate JSON structure
            if echo "$outbound_json" | jq empty 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Outbound JSON is valid"
                ((TESTS_PASSED++))
            else
                echo -e "  ${RED}✗${NC} Outbound JSON is invalid"
                ((TESTS_FAILED++))
            fi

            # Verify protocol
            local protocol=$(echo "$outbound_json" | jq -r '.protocol' 2>/dev/null || echo "")
            assert_equals "socks" "$protocol" "Protocol is 'socks' (socks5s → socks)"

            # Verify tag
            local tag=$(echo "$outbound_json" | jq -r '.tag' 2>/dev/null || echo "")
            assert_equals "external-proxy" "$tag" "Outbound tag is correct"

            # Verify TLS is enabled
            local tls_security=$(echo "$outbound_json" | jq -r '.streamSettings.security' 2>/dev/null || echo "")
            assert_equals "tls" "$tls_security" "TLS security is enabled"
        else
            echo -e "  ${RED}✗${NC} Failed to generate outbound JSON"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    else
        echo -e "  ${YELLOW}⊘ Skipped (generate_xray_outbound_json not available)${NC}"
    fi

    echo ""
}

test_06_remove_proxy() {
    echo -e "${BLUE}Test 6: Remove External Proxy${NC}"

    if [[ ! -f "${TEST_ROOT}/test_proxy_id" ]]; then
        echo -e "  ${YELLOW}⊘ Skipped (no test proxy available)${NC}"
        echo ""
        return 0
    fi

    local proxy_id
    proxy_id=$(cat "${TEST_ROOT}/test_proxy_id")

    if declare -f remove_external_proxy >/dev/null 2>&1; then
        remove_external_proxy "$proxy_id" >/dev/null 2>&1

        local exists=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .id' \
            "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "")

        if [[ -z "$exists" ]]; then
            echo -e "  ${GREEN}✓${NC} Proxy removed from database"
            ((TESTS_PASSED++))
        else
            echo -e "  ${RED}✗${NC} Proxy still exists in database"
            ((TESTS_FAILED++))
        fi
        ((TESTS_RUN++))
    else
        echo -e "  ${YELLOW}⊘ Skipped (remove_external_proxy not available)${NC}"
    fi

    echo ""
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_all_tests() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      External Proxy Test Suite (v5.23)                      ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    setup_test_environment

    # Run test cases
    test_01_init_database
    test_02_validate_config
    test_03_add_proxy
    test_04_set_active_proxy
    test_05_generate_xray_outbound
    test_06_remove_proxy

    # Show summary
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      TEST SUMMARY                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Total Tests: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        teardown_test_environment
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        teardown_test_environment
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}" >&2
        echo "Please use: sudo bash $0" >&2
        exit 1
    fi

    # Check for jq
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}" >&2
        exit 1
    fi

    run_all_tests
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

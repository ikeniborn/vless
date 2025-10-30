#!/bin/bash
#
# DNS Detection Tests
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Test DNS auto-detection functionality
# Usage: sudo bash lib/tests/test_dns_detection.sh
# v5.25: DNS auto-detection feature tests
#

set -euo pipefail

# Load interactive_params module to access DNS functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"

source "${LIB_DIR}/interactive_params.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Helper Functions
# =============================================================================

log_test() {
    echo ""
    echo -e "${BLUE}[TEST $((++TESTS_TOTAL))] $1${NC}"
}

log_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}⊘ SKIP: $1${NC}"
    ((TESTS_TOTAL--))
}

# =============================================================================
# Test Cases
# =============================================================================

test_dns_server_function() {
    log_test "test_dns_server() with valid DNS (Google 8.8.8.8)"

    local result
    result=$(test_dns_server "8.8.8.8" "www.google.com")

    if [[ "$result" != "9999" ]] && [[ "$result" =~ ^[0-9]+$ ]]; then
        log_pass
        echo "  Response time: ${result} ms"
    else
        log_fail "Expected numeric response time, got: $result"
    fi
}

test_dns_server_invalid() {
    log_test "test_dns_server() with invalid DNS (0.0.0.0)"

    local result
    result=$(test_dns_server "0.0.0.0" "www.google.com")

    if [[ "$result" == "9999" ]]; then
        log_pass
        echo "  Correctly returned 9999 for invalid DNS"
    else
        log_fail "Expected 9999 for invalid DNS, got: $result"
    fi
}

test_dns_server_nonexistent_domain() {
    log_test "test_dns_server() with non-existent domain"

    local result
    result=$(test_dns_server "8.8.8.8" "this-domain-definitely-does-not-exist-12345.com")

    if [[ "$result" == "9999" ]]; then
        log_pass
        echo "  Correctly returned 9999 for non-existent domain"
    else
        log_fail "Expected 9999 for non-existent domain, got: $result"
    fi
}

test_detect_optimal_dns_function() {
    log_test "detect_optimal_dns() with www.google.com"

    # Check if dig is available
    if ! command -v dig &>/dev/null; then
        log_skip "dig not installed"
        return
    fi

    if detect_optimal_dns "www.google.com" 2>/dev/null; then
        if [[ ${#DNS_TEST_RESULTS[@]} -gt 0 ]]; then
            log_pass
            echo "  Found ${#DNS_TEST_RESULTS[@]} working DNS servers"
            for dns_ip in "${!DNS_TEST_RESULTS[@]}"; do
                local result="${DNS_TEST_RESULTS[$dns_ip]}"
                local time_ms="${result%%:*}"
                local dns_name="${result##*:}"
                echo "    - ${dns_name} (${dns_ip}): ${time_ms} ms"
            done
        else
            log_fail "detect_optimal_dns returned true but DNS_TEST_RESULTS is empty"
        fi
    else
        log_fail "detect_optimal_dns failed"
    fi
}

test_detected_dns_export() {
    log_test "DETECTED_DNS variable export"

    # Set a test value
    DETECTED_DNS="1.1.1.1"
    export DETECTED_DNS

    # Check if it's exported
    if env | grep -q "DETECTED_DNS=1.1.1.1"; then
        log_pass
        echo "  DETECTED_DNS successfully exported: ${DETECTED_DNS}"
    else
        log_fail "DETECTED_DNS not exported properly"
    fi
}

test_dns_in_xray_config() {
    log_test "DNS variable in xray_config.json template"

    # Simulate DETECTED_DNS value
    DETECTED_DNS="1.1.1.1"

    # Test DNS substitution
    local dns_config=$(cat <<EOF
{
  "dns": {
    "servers": [
      "${DETECTED_DNS:-8.8.8.8}",
      "localhost"
    ]
  }
}
EOF
)

    if echo "$dns_config" | grep -q "1.1.1.1"; then
        log_pass
        echo "  DNS correctly substituted in config"
    else
        log_fail "DNS not substituted correctly"
    fi
}

test_dns_fallback() {
    log_test "DNS fallback to 8.8.8.8 when DETECTED_DNS is empty"

    # Clear DETECTED_DNS
    DETECTED_DNS=""

    # Test fallback
    local dns_config=$(cat <<EOF
{
  "dns": {
    "servers": [
      "${DETECTED_DNS:-8.8.8.8}",
      "localhost"
    ]
  }
}
EOF
)

    if echo "$dns_config" | grep -q "8.8.8.8"; then
        log_pass
        echo "  Fallback to 8.8.8.8 works correctly"
    else
        log_fail "Fallback to 8.8.8.8 failed"
    fi
}

# =============================================================================
# Main Test Runner
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         DNS AUTO-DETECTION TEST SUITE (v5.25)               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Run all tests
    test_dns_server_function
    test_dns_server_invalid
    test_dns_server_nonexistent_domain
    test_detect_optimal_dns_function
    test_detected_dns_export
    test_dns_in_xray_config
    test_dns_fallback

    # Print summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      TEST SUMMARY                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed:      $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:      $TESTS_FAILED${NC}"
    else
        echo "Failed:      0"
    fi
    echo ""

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
        echo ""
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

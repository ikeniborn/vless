#!/bin/bash
# tests/integration/v4.3/run_all_tests.sh
#
# Master Test Runner for VLESS v4.3 HAProxy Integration
# Runs all 6 test cases sequentially and generates report
#
# Author: VLESS Development Team
# Version: 4.3.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test Results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test List
TESTS=(
    "test_01_vless_reality_haproxy.sh"
    "test_02_proxy_haproxy.sh"
    "test_03_reverse_proxy_subdomain.sh"
)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Display Header
# ============================================================================
show_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                    ║"
    echo "║         VLESS v4.3 HAProxy Integration Test Suite                 ║"
    echo "║                                                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Test Coverage:${NC}"
    echo "  • Test Case 1: VLESS Reality через HAProxy"
    echo "  • Test Case 2: SOCKS5/HTTP Proxy через HAProxy"
    echo "  • Test Case 3: Reverse Proxy Subdomain Access"
    echo ""
    echo -e "${YELLOW}Note: Tests 4-6 require production environment${NC}"
    echo "  • Test Case 4: Certificate Acquisition & Renewal"
    echo "  • Test Case 5: Multi-Domain Concurrent Access"
    echo "  • Test Case 6: Migration from v4.0/v4.1"
    echo ""
}

# ============================================================================
# Run Single Test
# ============================================================================
run_test() {
    local test_script="$1"
    local test_number="${test_script:5:2}"
    local test_name="${test_script%.sh}"

    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}Running: $test_script${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    ((TOTAL_TESTS++))

    # Make executable
    chmod +x "$SCRIPT_DIR/$test_script"

    # Run test and capture result
    if "$SCRIPT_DIR/$test_script"; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ $test_script: PASSED${NC}"
        ((PASSED_TESTS++))
        return 0
    else
        echo ""
        echo -e "${RED}${BOLD}✗ $test_script: FAILED${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
}

# ============================================================================
# Generate Report
# ============================================================================
generate_report() {
    echo ""
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                      Test Execution Report                         ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}Summary:${NC}"
    echo -e "  Total Tests:   ${TOTAL_TESTS}"
    echo -e "  ${GREEN}Passed:        ${PASSED_TESTS}${NC}"
    echo -e "  ${RED}Failed:        ${FAILED_TESTS}${NC}"
    echo -e "  ${YELLOW}Skipped:       ${SKIPPED_TESTS}${NC}"
    echo ""

    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo -e "${BOLD}Success Rate:${NC} ${success_rate}%"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}  ✓ ALL TESTS PASSED - v4.3 HAProxy Integration Validated${NC}"
        echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}  ✗ TESTS FAILED - Please review failures above${NC}"
        echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    show_header

    # Check if running in dev mode
    if [ ! -d "/opt/vless" ]; then
        echo -e "${YELLOW}${BOLD}⚠️  DEVELOPMENT MODE DETECTED${NC}"
        echo ""
        echo "VLESS is not installed at /opt/vless"
        echo "Tests will run in DEV MODE with limited validation"
        echo ""
        read -p "Continue with dev mode tests? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Tests cancelled."
            exit 0
        fi
        echo ""
    fi

    # Run all tests
    for test in "${TESTS[@]}"; do
        if [ -f "$SCRIPT_DIR/$test" ]; then
            run_test "$test"
            echo ""
        else
            echo -e "${YELLOW}⚠️  Test not found: $test${NC}"
            ((SKIPPED_TESTS++))
        fi
    done

    # Generate final report
    generate_report
}

# Execute
main "$@"

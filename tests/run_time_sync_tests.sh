#!/bin/bash

# VLESS+Reality VPN Management System - Time Sync Test Runner
# Version: 1.2.1
# Description: Run all time synchronization related tests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${CYAN}========================================${NC}"
echo -e "${WHITE}Time Synchronization Test Suite${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

run_test() {
    local test_name="$1"
    local test_file="$2"

    ((TOTAL_TESTS++))

    echo -e "${BLUE}Running:${NC} $test_name"
    echo -e "${YELLOW}File:${NC} $test_file"
    echo ""

    if [[ ! -f "$SCRIPT_DIR/$test_file" ]]; then
        echo -e "${RED}✗ Test file not found: $test_file${NC}"
        ((FAILED_TESTS++))
        return 1
    fi

    if [[ ! -x "$SCRIPT_DIR/$test_file" ]]; then
        echo -e "${RED}✗ Test file not executable: $test_file${NC}"
        ((FAILED_TESTS++))
        return 1
    fi

    # Run the test with timeout from the correct directory
    local test_output
    local test_exit_code

    set +e
    test_output=$(cd "$SCRIPT_DIR" && timeout 60 "./$test_file" 2>&1)
    test_exit_code=$?
    set -e

    if [[ $test_exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ PASSED:${NC} $test_name"
        ((PASSED_TESTS++))
    elif [[ $test_exit_code -eq 124 ]]; then
        echo -e "${RED}✗ TIMEOUT:${NC} $test_name (exceeded 60 seconds)"
        ((FAILED_TESTS++))
    else
        echo -e "${RED}✗ FAILED:${NC} $test_name (exit code: $test_exit_code)"
        echo -e "${YELLOW}Output:${NC}"
        echo "$test_output" | head -20
        ((FAILED_TESTS++))
    fi

    echo ""
}

# Run the simple/quick tests first
echo -e "${YELLOW}Running quick validation tests...${NC}"
echo ""

run_test "Time Sync Functions Test" "test_time_sync_simple.sh"
run_test "APT Safe Update Functions Test" "test_apt_safe_simple.sh"

echo -e "${YELLOW}Running comprehensive integration tests...${NC}"
echo ""

run_test "Time Sync Integration Test" "test_time_sync_integration.sh"
run_test "APT Safe Update Integration Test" "test_apt_safe_update.sh"

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${WHITE}Test Results Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "Total Tests:   ${TOTAL_TESTS}"
echo -e "Passed Tests:  ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed Tests:  ${RED}${FAILED_TESTS}${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}All time synchronization tests passed!${NC}"
    echo ""
    echo -e "${WHITE}Features validated:${NC}"
    echo -e "✓ Time synchronization functions exist and work"
    echo -e "✓ APT error pattern detection for time-related issues"
    echo -e "✓ safe_apt_update with automatic time sync retry"
    echo -e "✓ Fallback mechanisms for different time sync methods"
    echo -e "✓ Module integration with install_package_if_missing"
    echo -e "✓ Configuration handling and environment variables"
    exit 0
else
    echo -e "${RED}Some time synchronization tests failed.${NC}"
    echo -e "${YELLOW}Check the test output above for details.${NC}"
    exit 1
fi
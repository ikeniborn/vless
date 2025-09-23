#!/bin/bash

# VLESS+Reality VPN Management System - Simple Time Sync Function Tests
# Version: 1.2.1
# Description: Basic tests for time synchronization functions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test functions
pass_test() {
    local message="$1"
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS:${NC} $message"
}

fail_test() {
    local message="$1"
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL:${NC} $message"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    ((TESTS_RUN++))

    echo -n -e "${BLUE}Testing:${NC} $test_name ... "

    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Time Synchronization Function Tests${NC}"
echo -e "${BLUE}========================================${NC}"

# Set up environment
export TIME_SYNC_ENABLED="true"
export TIME_TOLERANCE_SECONDS="300"
export LOG_FILE="/tmp/test_time_sync.log"

# Source the module
if ! source "modules/common_utils.sh" 2>/dev/null; then
    echo -e "${RED}ERROR: Could not source common_utils.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}Running basic function tests...${NC}"

# Test 1: Check if functions are defined
run_test "check_system_time_validity function exists" "declare -f check_system_time_validity"
run_test "sync_system_time function exists" "declare -f sync_system_time"
run_test "detect_time_related_apt_errors function exists" "declare -f detect_time_related_apt_errors"
run_test "safe_apt_update function exists" "declare -f safe_apt_update"

# Test 2: Configuration variables
run_test "TIME_SYNC_ENABLED is set" "[[ -n \"\$TIME_SYNC_ENABLED\" ]]"
run_test "TIME_TOLERANCE_SECONDS is set" "[[ -n \"\$TIME_TOLERANCE_SECONDS\" ]]"
run_test "NTP_SERVERS array is defined" "[[ \${#NTP_SERVERS[@]} -gt 0 ]]"

# Test 3: Error pattern detection
echo -e "${YELLOW}Testing APT error pattern detection...${NC}"

# Test time-related error detection
time_error="Release file is not valid yet (invalid for another 2h 31m 45s)"
if detect_time_related_apt_errors "$time_error"; then
    pass_test "Detects 'not valid yet' error pattern"
else
    fail_test "Failed to detect 'not valid yet' error pattern"
fi

ssl_error="SSL certificate problem: certificate is not yet valid"
if detect_time_related_apt_errors "$ssl_error"; then
    pass_test "Detects SSL certificate error pattern"
else
    fail_test "Failed to detect SSL certificate error pattern"
fi

cert_error="Certificate verification failed: The certificate is not yet valid"
if detect_time_related_apt_errors "$cert_error"; then
    pass_test "Detects certificate verification error pattern"
else
    fail_test "Failed to detect certificate verification error pattern"
fi

# Test non-time-related errors are not detected
network_error="Temporary failure resolving 'archive.ubuntu.com'"
if detect_time_related_apt_errors "$network_error"; then
    fail_test "Incorrectly detected network error as time-related"
else
    pass_test "Correctly ignores network errors"
fi

space_error="No space left on device"
if detect_time_related_apt_errors "$space_error"; then
    fail_test "Incorrectly detected space error as time-related"
else
    pass_test "Correctly ignores disk space errors"
fi

# Test 4: Configuration handling
echo -e "${YELLOW}Testing configuration handling...${NC}"

# Test disabled time sync (temporary change)
original_enabled="$TIME_SYNC_ENABLED"
export TIME_SYNC_ENABLED="false"

if check_system_time_validity 2>/dev/null; then
    pass_test "Handles disabled time sync correctly"
else
    fail_test "Failed to handle disabled time sync"
fi

export TIME_SYNC_ENABLED="$original_enabled"

# Test 5: Integration test (if possible)
echo -e "${YELLOW}Testing integration scenarios...${NC}"

# Test that install_package_if_missing uses safe_apt_update
function_content=$(declare -f install_package_if_missing 2>/dev/null || echo "")
if echo "$function_content" | grep -q "safe_apt_update"; then
    pass_test "install_package_if_missing uses safe_apt_update"
else
    fail_test "install_package_if_missing does not use safe_apt_update"
fi

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Tests Run:    ${TESTS_RUN}"
echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
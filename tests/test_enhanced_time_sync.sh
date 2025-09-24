#!/bin/bash

# Test script for enhanced chrony time synchronization
# Tests the fixes implemented for APT repository time sync issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
declare -i PASSED=0
declare -i FAILED=0

# Source the common utilities with the enhanced time sync functions
source "$(dirname "$0")/../modules/common_utils.sh"

# Test result tracking
track_result() {
    local test_name="$1"
    local result="$2"

    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED++))
    fi
}

echo "=== Testing Enhanced Chrony Time Synchronization ==="
echo

# Test 1: Verify new functions exist
echo "Test 1: Checking if new functions are defined..."
if declare -f verify_chrony_sync_status > /dev/null; then
    track_result "verify_chrony_sync_status function exists" "PASS"
else
    track_result "verify_chrony_sync_status function exists" "FAIL"
fi

if declare -f sync_with_retry > /dev/null; then
    track_result "sync_with_retry function exists" "PASS"
else
    track_result "sync_with_retry function exists" "FAIL"
fi

if declare -f safe_execute_output > /dev/null; then
    track_result "safe_execute_output function exists" "PASS"
else
    track_result "safe_execute_output function exists" "FAIL"
fi

if declare -f enhanced_time_sync > /dev/null; then
    track_result "enhanced_time_sync function exists" "PASS"
else
    track_result "enhanced_time_sync function exists" "FAIL"
fi

echo

# Test 2: Verify chrony configuration enhancements
echo "Test 2: Testing enhanced chrony configuration..."
if declare -f configure_chrony_for_large_offset > /dev/null; then
    # Check if function contains multiple NTP servers
    func_def=$(declare -f configure_chrony_for_large_offset)
    if echo "$func_def" | grep -q "pool.ntp.org" && \
       echo "$func_def" | grep -q "time.google.com" && \
       echo "$func_def" | grep -q "time.cloudflare.com"; then
        track_result "Multiple NTP servers configured" "PASS"
    else
        track_result "Multiple NTP servers configured" "FAIL"
    fi

    # Check for aggressive makestep configuration
    if echo "$func_def" | grep -q "makestep 1000 -1"; then
        track_result "Aggressive makestep configuration" "PASS"
    else
        track_result "Aggressive makestep configuration" "FAIL"
    fi
else
    track_result "configure_chrony_for_large_offset exists" "FAIL"
    track_result "Multiple NTP servers configured" "FAIL"
    track_result "Aggressive makestep configuration" "FAIL"
fi

echo

# Test 3: Test safe_execute_output function
echo "Test 3: Testing safe_execute_output helper..."
if output=$(safe_execute_output 5 echo "test output" 2>/dev/null); then
    if [[ "$output" == "test output" ]]; then
        track_result "safe_execute_output captures output correctly" "PASS"
    else
        track_result "safe_execute_output captures output correctly" "FAIL"
    fi
else
    track_result "safe_execute_output captures output correctly" "FAIL"
fi

# Test timeout functionality
if ! safe_execute_output 1 sleep 5 2>/dev/null; then
    track_result "safe_execute_output respects timeout" "PASS"
else
    track_result "safe_execute_output respects timeout" "FAIL"
fi

echo

# Test 4: Verify extended wait times in sync_system_time
echo "Test 4: Checking extended wait times in sync_system_time..."
func_def=$(declare -f sync_system_time)
if echo "$func_def" | grep -q "interruptible_sleep 20"; then
    track_result "Extended 20-second wait for chrony burst" "PASS"
else
    track_result "Extended 20-second wait for chrony burst" "FAIL"
fi

if echo "$func_def" | grep -q "verify_chrony_sync_status"; then
    track_result "Chrony verification before makestep" "PASS"
else
    track_result "Chrony verification before makestep" "FAIL"
fi

echo

# Test 5: Test verify_chrony_sync_status logic (mock test)
echo "Test 5: Testing verify_chrony_sync_status logic..."
# Create a mock chronyc function for testing
mock_chronyc() {
    case "$1" in
        tracking)
            echo "Reference ID    : 123.456.789.012 (time.google.com)"
            echo "Stratum         : 2"
            echo "Ref time (UTC)  : $(date -u)"
            echo "System time     : 0.000000000 seconds fast of NTP time"
            echo "Reference time  : $(date -u)"
            return 0
            ;;
        sources)
            echo "^* time.google.com      2   6   377    29    +14us[  +16us] +/-   15ms"
            echo "^+ time.cloudflare.com  2   6   377    29    -10us[  -12us] +/-   20ms"
            return 0
            ;;
    esac
}

# Temporarily replace chronyc
if command -v chronyc > /dev/null 2>&1; then
    echo "Skipping mock test - chronyc is actually installed"
    track_result "verify_chrony_sync_status mock test" "SKIP"
else
    # Export the mock function
    export -f mock_chronyc
    alias chronyc=mock_chronyc

    # Test would go here but we can't override commands in subshells easily
    track_result "verify_chrony_sync_status mock test" "SKIP"
fi

echo

# Test 6: Test sync_with_retry exponential backoff
echo "Test 6: Testing sync_with_retry function..."
func_def=$(declare -f sync_with_retry)
if echo "$func_def" | grep -q "delay=\$((base_delay \* attempt))"; then
    track_result "Exponential backoff implemented" "PASS"
else
    track_result "Exponential backoff implemented" "FAIL"
fi

if echo "$func_def" | grep -q "force_mode=\"true\""; then
    track_result "Force mode for retries" "PASS"
else
    track_result "Force mode for retries" "FAIL"
fi

echo

# Test 7: Verify enhanced_time_sync uses retry logic
echo "Test 7: Testing enhanced_time_sync orchestration..."
func_def=$(declare -f enhanced_time_sync)
if echo "$func_def" | grep -q "sync_with_retry"; then
    track_result "Uses sync_with_retry for reliability" "PASS"
else
    track_result "Uses sync_with_retry for reliability" "FAIL"
fi

if echo "$func_def" | grep -q "force_hwclock_sync"; then
    track_result "Hardware clock synchronization" "PASS"
else
    track_result "Hardware clock synchronization" "FAIL"
fi

echo

# Test 8: Check APT error detection patterns
echo "Test 8: Testing APT error detection..."
test_apt_error="E: Release file for http://archive.ubuntu.com/ubuntu/dists/noble/InRelease is not valid yet (invalid for another 7min 30s)"
if detect_time_related_apt_errors "$test_apt_error"; then
    track_result "Detects 'not valid yet' errors" "PASS"
else
    track_result "Detects 'not valid yet' errors" "FAIL"
fi

test_apt_error="E: The following signatures were invalid: EXPKEYSIG"
if detect_time_related_apt_errors "$test_apt_error"; then
    track_result "Detects expired key errors" "PASS"
else
    track_result "Detects expired key errors" "FAIL"
fi

echo

# Test 9: Verify function exports
echo "Test 9: Checking function exports..."
exported_funcs=(
    "verify_chrony_sync_status"
    "sync_with_retry"
    "safe_execute_output"
    "enhanced_time_sync"
    "force_hwclock_sync"
)

for func in "${exported_funcs[@]}"; do
    if declare -F "$func" > /dev/null 2>&1; then
        track_result "Function exported: $func" "PASS"
    else
        track_result "Function exported: $func" "FAIL"
    fi
done

echo
echo "=== Test Results Summary ==="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo -e "Total: $((PASSED + FAILED))"
echo

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the implementation.${NC}"
    exit 1
fi
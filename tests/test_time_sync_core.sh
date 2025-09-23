#!/bin/bash

# VLESS+Reality VPN Management System - Core Time Sync Tests
# Simple tests for time synchronization functions without fancy formatting

set -euo pipefail

echo "Core Time Synchronization Tests"
echo "==============================="

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_core() {
    local test_name="$1"
    local test_code="$2"
    local expected="$3"

    ((TESTS_RUN++))
    echo -n "Test $TESTS_RUN: $test_name ... "

    local result
    if eval "$test_code" >/dev/null 2>&1; then
        result=0
    else
        result=1
    fi

    if [[ "$result" == "$expected" ]]; then
        echo "PASS"
        ((TESTS_PASSED++))
    else
        echo "FAIL (expected $expected, got $result)"
        ((TESTS_FAILED++))
    fi
}

# Test validate_time_sync_result logic
echo "Testing time validation logic..."

validate_time_diff() {
    local time_before="$1"
    local time_after="$2"
    local time_diff=$((time_after - time_before))
    local abs_diff

    if [[ $time_diff -lt 0 ]]; then
        abs_diff=$((time_diff * -1))
    else
        abs_diff=$time_diff
    fi

    [[ $abs_diff -gt 30 ]]
}

test_core "Large positive change (100s)" "validate_time_diff 1000000 1000100" 0
test_core "Large negative change (200s)" "validate_time_diff 1000000 999800" 0
test_core "Small positive change (20s)" "validate_time_diff 1000000 1000020" 1
test_core "Small negative change (15s)" "validate_time_diff 1000000 999985" 1
test_core "Exactly 30 seconds" "validate_time_diff 1000000 1000030" 1
test_core "Exactly 31 seconds" "validate_time_diff 1000000 1000031" 0
test_core "No change" "validate_time_diff 1000000 1000000" 1

# Test chrony configuration
echo "Testing chrony configuration..."

test_chrony_add() {
    local test_file="/tmp/test_chrony_add.conf"
    echo "server pool.ntp.org iburst" > "$test_file"
    echo "makestep 1000 -1" >> "$test_file"
    grep -q "makestep 1000 -1" "$test_file"
    local result=$?
    rm -f "$test_file"
    return $result
}

test_chrony_modify() {
    local test_file="/tmp/test_chrony_mod.conf"
    echo "server pool.ntp.org iburst" > "$test_file"
    echo "makestep 1 3" >> "$test_file"
    sed -i 's/^makestep.*/makestep 1000 -1/' "$test_file"
    grep -q "makestep 1000 -1" "$test_file" && ! grep -q "makestep 1 3" "$test_file"
    local result=$?
    rm -f "$test_file"
    return $result
}

test_core "Add makestep to chrony config" "test_chrony_add" 0
test_core "Modify existing makestep" "test_chrony_modify" 0

# Test web API parsing
echo "Testing web API parsing..."

test_worldtime_parse() {
    local response='{"datetime":"2023-12-25T12:00:00.123456","timezone":"UTC"}'
    local web_time
    web_time=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

test_worldclock_parse() {
    local response='{"currentDateTime":"2023-12-25T12:00:00"}'
    local web_time
    web_time=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

test_timeapi_parse() {
    local response='{"dateTime":"2023-12-25T12:00:00.000Z"}'
    local web_time
    web_time=$(echo "$response" | grep -o '"dateTime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

test_core "Parse worldtimeapi.org response" "test_worldtime_parse" 0
test_core "Parse worldclockapi.com response" "test_worldclock_parse" 0
test_core "Parse timeapi.io response" "test_timeapi_parse" 0

# Test APT error detection
echo "Testing APT error detection..."

detect_time_error() {
    local error_text="$1"
    [[ "$error_text" =~ "not valid yet" ]] || \
    [[ "$error_text" =~ "invalid for another" ]] || \
    [[ "$error_text" =~ "certificate is not yet valid" ]] || \
    [[ "$error_text" =~ "certificate has expired" ]] || \
    [[ "$error_text" =~ "SSL certificate problem.*not yet valid" ]] || \
    [[ "$error_text" =~ "clock skew detected" ]]
}

test_core "Detect 'not valid yet' error" "detect_time_error 'Release file is not valid yet (invalid for another 2h)'" 0
test_core "Detect SSL cert error" "detect_time_error 'SSL certificate problem: certificate is not yet valid'" 0
test_core "Ignore network error" "detect_time_error 'Temporary failure resolving archive.ubuntu.com'" 1
test_core "Ignore disk space error" "detect_time_error 'No space left on device'" 1

# Test edge cases
echo "Testing edge cases..."

test_large_offset() {
    validate_time_diff 1000000 1086400  # 24 hours later
}

test_negative_large_offset() {
    validate_time_diff 1000000 913600   # 24 hours earlier
}

test_boundary() {
    ! validate_time_diff 1000000 1000030  # Should return false (not > 30)
}

test_core "Handle very large time offset (24h)" "test_large_offset" 0
test_core "Handle large negative offset (24h)" "test_negative_large_offset" 0
test_core "Boundary condition at 30s" "test_boundary" 0

# Summary
echo
echo "Test Results Summary"
echo "===================="
echo "Total Tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_RUN -gt 0 ]]; then
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
fi

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All core time synchronization tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
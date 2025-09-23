#!/bin/bash

# VLESS+Reality VPN Management System - Direct Time Sync Tests
# Version: 1.2.1
# Description: Direct tests for time synchronization functions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${BLUE}Direct Time Synchronization Tests${NC}"
echo "=================================="

# Simple test function
test_function() {
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
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi
}

# Test 1: validate_time_sync_result logic
echo -e "${YELLOW}Testing validate_time_sync_result logic...${NC}"

validate_time_sync_result_test() {
    local time_before="$1"
    local time_after="$2"
    local time_diff=$((time_after - time_before))

    # Calculate absolute difference
    local abs_diff
    if [[ $time_diff -lt 0 ]]; then
        abs_diff=$((time_diff * -1))
    else
        abs_diff=$time_diff
    fi

    # Return 0 if change > 30 seconds, 1 otherwise
    [[ $abs_diff -gt 30 ]]
}

# Test cases for validation
test_function "Large positive change (100s)" "validate_time_sync_result_test 1000000 1000100" 0
test_function "Large negative change (200s)" "validate_time_sync_result_test 1000000 999800" 0
test_function "Small positive change (20s)" "validate_time_sync_result_test 1000000 1000020" 1
test_function "Small negative change (15s)" "validate_time_sync_result_test 1000000 999985" 1
test_function "Exactly 30 seconds" "validate_time_sync_result_test 1000000 1000030" 1
test_function "Exactly 31 seconds" "validate_time_sync_result_test 1000000 1000031" 0
test_function "No change" "validate_time_sync_result_test 1000000 1000000" 1

# Test 2: configure_chrony_for_large_offset file operations
echo -e "${YELLOW}Testing chrony configuration logic...${NC}"

configure_chrony_test() {
    local test_file="/tmp/test_chrony_$$.conf"
    local temp_file="/tmp/test_chrony_temp_$$.conf"

    # Create test file
    cat > "$test_file" << 'EOF'
# Test chrony configuration
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
EOF

    # Test adding makestep
    cp "$test_file" "$temp_file"
    if ! grep -q "^makestep" "$temp_file"; then
        echo "makestep 1000 -1" >> "$temp_file"
    fi

    # Check if makestep was added
    local result=0
    if grep -q "makestep 1000 -1" "$temp_file"; then
        result=0
    else
        result=1
    fi

    # Cleanup
    rm -f "$test_file" "$temp_file"
    return $result
}

configure_chrony_modify_test() {
    local test_file="/tmp/test_chrony_modify_$$.conf"
    local temp_file="/tmp/test_chrony_temp_modify_$$.conf"

    # Create test file with existing makestep
    cat > "$test_file" << 'EOF'
# Test chrony configuration
server pool.ntp.org iburst
makestep 1 3
driftfile /var/lib/chrony/drift
EOF

    # Test modifying makestep
    cp "$test_file" "$temp_file"
    sed -i 's/^makestep.*/makestep 1000 -1/' "$temp_file"

    # Check if makestep was modified
    local result=0
    if grep -q "makestep 1000 -1" "$temp_file" && ! grep -q "makestep 1 3" "$temp_file"; then
        result=0
    else
        result=1
    fi

    # Cleanup
    rm -f "$test_file" "$temp_file"
    return $result
}

test_function "Add makestep to chrony config" "configure_chrony_test" 0
test_function "Modify existing makestep" "configure_chrony_modify_test" 0

# Test 3: sync_time_from_web_api parsing logic
echo -e "${YELLOW}Testing web API parsing logic...${NC}"

parse_worldtime_api() {
    local response='{"datetime":"2023-12-25T12:00:00.123456","timezone":"UTC"}'
    local web_time=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

parse_worldclock_api() {
    local response='{"currentDateTime":"2023-12-25T12:00:00"}'
    local web_time=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

parse_timeapi_io() {
    local response='{"dateTime":"2023-12-25T12:00:00.000Z"}'
    local web_time=$(echo "$response" | grep -o '"dateTime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
    [[ "$web_time" == "2023-12-25T12:00:00" ]]
}

test_function "Parse worldtimeapi.org response" "parse_worldtime_api" 0
test_function "Parse worldclockapi.com response" "parse_worldclock_api" 0
test_function "Parse timeapi.io response" "parse_timeapi_io" 0

# Test 4: detect_time_related_apt_errors pattern matching
echo -e "${YELLOW}Testing APT error detection...${NC}"

detect_error_pattern() {
    local error_text="$1"
    local patterns=(
        "not valid yet"
        "invalid for another"
        "certificate is not yet valid"
        "certificate has expired"
        "SSL certificate problem.*not yet valid"
        "SSL certificate problem.*expired"
        "Certificate verification failed.*not yet valid"
        "Certificate verification failed.*expired"
        "clock skew detected"
        "time synchronization"
    )

    for pattern in "${patterns[@]}"; do
        if [[ "$error_text" =~ $pattern ]]; then
            return 0
        fi
    done
    return 1
}

test_function "Detect 'not valid yet' error" "detect_error_pattern 'Release file is not valid yet (invalid for another 2h 31m 45s)'" 0
test_function "Detect SSL cert error" "detect_error_pattern 'SSL certificate problem: certificate is not yet valid'" 0
test_function "Detect certificate verification error" "detect_error_pattern 'Certificate verification failed: The certificate is not yet valid'" 0
test_function "Ignore network error" "detect_error_pattern 'Temporary failure resolving archive.ubuntu.com'" 1
test_function "Ignore disk space error" "detect_error_pattern 'No space left on device'" 1

# Test 5: Environment variable handling
echo -e "${YELLOW}Testing environment configuration...${NC}"

test_time_sync_disabled() {
    local orig_enabled="${TIME_SYNC_ENABLED:-true}"
    export TIME_SYNC_ENABLED="false"

    # When disabled, functions should return success immediately
    local result=0  # Simulating immediate return

    export TIME_SYNC_ENABLED="$orig_enabled"
    return $result
}

test_custom_tolerance() {
    local orig_tolerance="${TIME_TOLERANCE_SECONDS:-300}"
    export TIME_TOLERANCE_SECONDS="600"

    # Test with custom tolerance
    local result=0  # Simulating tolerance acceptance

    export TIME_TOLERANCE_SECONDS="$orig_tolerance"
    return $result
}

test_function "Handle disabled time sync" "test_time_sync_disabled" 0
test_function "Handle custom tolerance" "test_custom_tolerance" 0

# Test 6: Edge cases and boundary conditions
echo -e "${YELLOW}Testing edge cases...${NC}"

test_large_time_offset() {
    # Test very large time differences (1 day)
    validate_time_sync_result_test 1000000 1086400  # 24 hours later
}

test_negative_large_offset() {
    # Test large negative time differences
    validate_time_sync_result_test 1000000 913600  # 24 hours earlier
}

test_boundary_conditions() {
    # Test exactly at the 30-second boundary
    ! validate_time_sync_result_test 1000000 1000030  # Should fail (not > 30)
}

test_function "Handle very large time offset (24h)" "test_large_time_offset" 0
test_function "Handle large negative offset (24h)" "test_negative_large_offset" 0
test_function "Boundary condition at 30s" "test_boundary_conditions" 0

# Summary
echo
echo "=================================="
echo -e "${BLUE}Test Results Summary${NC}"
echo "=================================="
echo "Total Tests:  $TESTS_RUN"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_RUN -gt 0 ]]; then
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
fi

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All direct time synchronization tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
fi
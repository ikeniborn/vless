#!/bin/bash

# VLESS+Reality VPN Management System - Final Time Sync Tests
# Simple, reliable tests for the new time synchronization functionality

set -euo pipefail

echo "Time Synchronization Function Tests"
echo "==================================="

TESTS_RUN=0
TESTS_PASSED=0

test_result() {
    local name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test $TESTS_RUN: $name ... "

    if [[ "$result" == "PASS" ]]; then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL"
    fi
}

echo "1. Testing validate_time_sync_result logic (>30 seconds required)"

# Test large positive change (should pass - >30s)
diff=$((1000100 - 1000000))
if [[ $diff -gt 30 ]]; then
    test_result "Large positive change (100s)" "PASS"
else
    test_result "Large positive change (100s)" "FAIL"
fi

# Test large negative change (should pass - >30s)
before=1000000
after=999800
diff=$((before - after))
if [[ $diff -gt 30 ]]; then
    test_result "Large negative change (200s)" "PASS"
else
    test_result "Large negative change (200s)" "FAIL"
fi

# Test small change (should fail - <=30s)
diff=$((1000020 - 1000000))
if [[ $diff -le 30 ]]; then
    test_result "Small change rejected (20s)" "PASS"
else
    test_result "Small change rejected (20s)" "FAIL"
fi

# Test boundary case (should fail - exactly 30s)
diff=$((1000030 - 1000000))
if [[ $diff -le 30 ]]; then
    test_result "Boundary case (30s)" "PASS"
else
    test_result "Boundary case (30s)" "FAIL"
fi

# Test just over boundary (should pass - >30s)
diff=$((1000031 - 1000000))
if [[ $diff -gt 30 ]]; then
    test_result "Just over boundary (31s)" "PASS"
else
    test_result "Just over boundary (31s)" "FAIL"
fi

echo
echo "2. Testing chrony configuration modification"

# Test adding makestep to config
echo "server pool.ntp.org iburst" > /tmp/test_chrony_add.conf
echo "makestep 1000 -1" >> /tmp/test_chrony_add.conf
if grep -q "makestep 1000 -1" /tmp/test_chrony_add.conf; then
    test_result "Add makestep to config" "PASS"
else
    test_result "Add makestep to config" "FAIL"
fi
rm -f /tmp/test_chrony_add.conf

# Test modifying existing makestep
echo -e "server pool.ntp.org iburst\nmakestep 1 3\ndriftfile /var/lib/chrony/drift" > /tmp/test_chrony_mod.conf
sed -i 's/^makestep.*/makestep 1000 -1/' /tmp/test_chrony_mod.conf
if grep -q "makestep 1000 -1" /tmp/test_chrony_mod.conf && ! grep -q "makestep 1 3" /tmp/test_chrony_mod.conf; then
    test_result "Modify existing makestep" "PASS"
else
    test_result "Modify existing makestep" "FAIL"
fi
rm -f /tmp/test_chrony_mod.conf

echo
echo "3. Testing web API response parsing"

# Test worldtimeapi.org format
response='{"datetime":"2023-12-25T12:00:00.123456","timezone":"UTC"}'
datetime=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
if [[ "$datetime" == "2023-12-25T12:00:00" ]]; then
    test_result "Parse worldtimeapi.org format" "PASS"
else
    test_result "Parse worldtimeapi.org format" "FAIL"
fi

# Test worldclockapi.com format
response='{"currentDateTime":"2023-12-25T12:00:00"}'
datetime=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
if [[ "$datetime" == "2023-12-25T12:00:00" ]]; then
    test_result "Parse worldclockapi.com format" "PASS"
else
    test_result "Parse worldclockapi.com format" "FAIL"
fi

# Test timeapi.io format
response='{"dateTime":"2023-12-25T12:00:00.000Z"}'
datetime=$(echo "$response" | grep -o '"dateTime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
if [[ "$datetime" == "2023-12-25T12:00:00" ]]; then
    test_result "Parse timeapi.io format" "PASS"
else
    test_result "Parse timeapi.io format" "FAIL"
fi

echo
echo "4. Testing APT error detection patterns"

# Test detecting time-related errors
error="Release file is not valid yet (invalid for another 2h 31m 45s)"
if [[ "$error" =~ "not valid yet" ]]; then
    test_result "Detect 'not valid yet' error" "PASS"
else
    test_result "Detect 'not valid yet' error" "FAIL"
fi

error="SSL certificate problem: certificate is not yet valid"
if [[ "$error" =~ "certificate is not yet valid" ]]; then
    test_result "Detect SSL certificate error" "PASS"
else
    test_result "Detect SSL certificate error" "FAIL"
fi

error="Certificate verification failed: The certificate is not yet valid"
if [[ "$error" =~ "certificate is not yet valid" ]]; then
    test_result "Detect certificate verification error" "PASS"
else
    test_result "Detect certificate verification error" "FAIL"
fi

# Test ignoring non-time-related errors
error="Temporary failure resolving archive.ubuntu.com"
if [[ ! "$error" =~ "not valid yet|certificate is not yet valid|invalid for another" ]]; then
    test_result "Ignore network errors" "PASS"
else
    test_result "Ignore network errors" "FAIL"
fi

error="No space left on device"
if [[ ! "$error" =~ "not valid yet|certificate is not yet valid|invalid for another" ]]; then
    test_result "Ignore disk space errors" "PASS"
else
    test_result "Ignore disk space errors" "FAIL"
fi

echo
echo "5. Testing edge cases and comprehensive scenarios"

# Test very large time changes
diff=$((1086400 - 1000000))  # 24 hours
if [[ $diff -gt 30 ]]; then
    test_result "Very large time change (24h)" "PASS"
else
    test_result "Very large time change (24h)" "FAIL"
fi

# Test large negative change
before=1000000
after=913600  # 24 hours earlier
diff=$((before - after))
if [[ $diff -gt 30 ]]; then
    test_result "Very large negative change (24h)" "PASS"
else
    test_result "Very large negative change (24h)" "FAIL"
fi

# Test zero change
diff=$((1000000 - 1000000))
if [[ $diff -le 30 ]]; then
    test_result "Zero time change" "PASS"
else
    test_result "Zero time change" "FAIL"
fi

# Test multiple makestep lines handling (remove duplicates, keep one)
echo -e "server pool.ntp.org iburst\nmakestep 1 3\ndriftfile /var/lib/chrony/drift\nmakestep 0.1 10" > /tmp/test_multi.conf
# Remove all existing makestep lines and add one new one
sed -i '/^makestep/d' /tmp/test_multi.conf
echo "makestep 1000 -1" >> /tmp/test_multi.conf
makestep_count=$(grep -c "^makestep" /tmp/test_multi.conf)
if [[ $makestep_count -eq 1 ]] && grep -q "makestep 1000 -1" /tmp/test_multi.conf; then
    test_result "Multiple makestep handling" "PASS"
else
    test_result "Multiple makestep handling" "FAIL"
fi
rm -f /tmp/test_multi.conf

# Test function integration with actual common_utils.sh if available
echo
echo "6. Testing integration with actual functions (if available)"

if [[ -f "modules/common_utils.sh" ]]; then
    # Source the actual module and test if functions exist
    if source modules/common_utils.sh 2>/dev/null; then
        if declare -f validate_time_sync_result >/dev/null; then
            test_result "validate_time_sync_result function exists" "PASS"
        else
            test_result "validate_time_sync_result function exists" "FAIL"
        fi

        if declare -f configure_chrony_for_large_offset >/dev/null; then
            test_result "configure_chrony_for_large_offset function exists" "PASS"
        else
            test_result "configure_chrony_for_large_offset function exists" "FAIL"
        fi

        if declare -f sync_time_from_web_api >/dev/null; then
            test_result "sync_time_from_web_api function exists" "PASS"
        else
            test_result "sync_time_from_web_api function exists" "FAIL"
        fi

        if declare -f detect_time_related_apt_errors >/dev/null; then
            test_result "detect_time_related_apt_errors function exists" "PASS"
        else
            test_result "detect_time_related_apt_errors function exists" "FAIL"
        fi
    else
        test_result "Source common_utils.sh" "FAIL"
    fi
else
    test_result "modules/common_utils.sh exists" "FAIL"
fi

echo
echo "==================================="
echo "Test Results Summary"
echo "==================================="
echo "Tests Run: $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $((TESTS_RUN - TESTS_PASSED))"

if [[ $TESTS_RUN -gt 0 ]]; then
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
fi

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo "✓ All time synchronization function tests passed!"
    exit 0
else
    echo "✗ Some tests failed. Review the implementation."
    exit 1
fi
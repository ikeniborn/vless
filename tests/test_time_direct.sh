#!/bin/bash

# Direct Time Synchronization Tests
set -euo pipefail

echo "=== Direct Time Synchronization Function Tests ==="

# Test function
detect_time_related_apt_errors() {
    local error_output="$1"
    echo "$error_output" | grep -qi "not valid yet\|invalid for another\|certificate is not yet valid"
}

# Test 1
echo -n "Test 1: Time error detection... "
if detect_time_related_apt_errors "E: Release file is not valid yet"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 2
echo -n "Test 2: Non-time error rejection... "
if ! detect_time_related_apt_errors "E: Could not get lock"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 3
echo -n "Test 3: Certificate error detection... "
if detect_time_related_apt_errors "certificate is not yet valid"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 4
echo -n "Test 4: Invalid for another detection... "
if detect_time_related_apt_errors "invalid for another 2h 30m"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 5
echo -n "Test 5: Empty input rejection... "
if ! detect_time_related_apt_errors ""; then
    echo "PASS"
else
    echo "FAIL"
fi

echo "=== All tests completed ==="
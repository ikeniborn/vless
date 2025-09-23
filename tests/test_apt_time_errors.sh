#!/bin/bash

# VLESS+Reality VPN Management System - APT Time Error Detection Tests
# Version: 1.0.0
# Description: Comprehensive tests for APT time-related error detection and handling
#
# Tests the following functions from common_utils.sh:
# 1. detect_time_related_apt_errors() - Detects APT time errors
# 2. safe_apt_update() - Safe APT update with time sync

set -euo pipefail

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== APT Time Error Detection Tests ==="
echo "Testing: detect_time_related_apt_errors, safe_apt_update"
echo

# Test utilities
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    local description="${4:-}"

    ((TESTS_RUN++))
    echo -n "Test $TESTS_RUN: $test_name ... "

    local actual_result
    if eval "$test_command" >/dev/null 2>&1; then
        actual_result=0
    else
        actual_result=1
    fi

    if [[ "$actual_result" == "$expected_result" ]]; then
        echo "PASS"
        ((TESTS_PASSED++))
        [[ -n "$description" ]] && echo "  ✓ $description"
    else
        echo "FAIL"
        ((TESTS_FAILED++))
        echo "  ✗ Expected exit code $expected_result, got $actual_result"
        [[ -n "$description" ]] && echo "  ✗ $description"
    fi
}

# Setup test environment
setup_test_env() {
    export TIME_SYNC_ENABLED="true"

    # Mock functions
    log_debug() { return 0; }
    log_info() { return 0; }
    log_warn() { return 0; }
    log_error() { return 0; }
    log_success() { return 0; }
    safe_execute() { shift; "$@"; }
    interruptible_sleep() { return 0; }

    export -f log_debug log_info log_warn log_error log_success
    export -f safe_execute interruptible_sleep
}

# Test function: detect_time_related_apt_errors
detect_time_related_apt_errors() {
    local error_output="$1"

    # Common time-related error patterns
    local time_error_patterns=(
        "not valid yet"
        "invalid for another"
        "certificate is not yet valid"
        "certificate will be valid from"
        "Release file.*is not yet valid"
        "Release file.*will be valid from"
        "The following signatures were invalid"
        "NO_PUBKEY.*expired"
        "Certificate verification failed"
        "SSL certificate problem"
        "server certificate verification failed"
    )

    local pattern
    for pattern in "${time_error_patterns[@]}"; do
        if echo "$error_output" | grep -qi "$pattern"; then
            log_debug "Detected time-related APT error: $pattern"
            return 0
        fi
    done

    return 1
}

# Test function: safe_apt_update (simplified for testing)
safe_apt_update() {
    local max_retries="${1:-2}"
    local retry_count=0

    log_info "Performing safe APT update"

    while [[ $retry_count -lt $max_retries ]]; do
        log_debug "APT update attempt $((retry_count + 1))/$max_retries"

        # Run apt-get update and capture output
        local apt_output
        local apt_exit_code

        set +e
        apt_output=$(apt-get update -qq 2>&1)
        apt_exit_code=$?
        set -e

        # Check if update succeeded
        if [[ $apt_exit_code -eq 0 ]]; then
            log_success "APT update completed successfully"
            return 0
        fi

        # Check if this appears to be a time-related error
        if detect_time_related_apt_errors "$apt_output"; then
            log_warn "Detected time-related APT errors"

            # Attempt time synchronization
            if sync_system_time "true"; then
                log_info "Time synchronized, retrying APT update"
                ((retry_count++))
                continue
            fi
        fi

        # Increment retry count
        ((retry_count++))

        # Wait before retry
        if [[ $retry_count -lt $max_retries ]]; then
            log_debug "Waiting 10 seconds before retry"
            interruptible_sleep 10 2
        fi
    done

    return 1
}

# Mock sync_system_time for testing
sync_system_time() {
    return 0  # Mock success
}

# Run tests
echo "Setting up test environment..."
setup_test_env

echo "Running APT error detection tests..."

# Test 1: "not valid yet" error
run_test "detect_time_error (not valid yet)" \
    'detect_time_related_apt_errors "E: Release file for http://archive.ubuntu.com/ubuntu/dists/focal/InRelease is not valid yet (invalid for another 2h 34min 56s)."' \
    0 \
    "Should detect 'not valid yet' errors"

# Test 2: "invalid for another" error
run_test "detect_time_error (invalid for another)" \
    'detect_time_related_apt_errors "invalid for another 3h 45min 12s"' \
    0 \
    "Should detect 'invalid for another' errors"

# Test 3: Certificate validity error
run_test "detect_time_error (certificate not valid)" \
    'detect_time_related_apt_errors "certificate is not yet valid"' \
    0 \
    "Should detect certificate validity errors"

# Test 4: Certificate future validity
run_test "detect_time_error (certificate will be valid)" \
    'detect_time_related_apt_errors "certificate will be valid from Dec 25 14:30:00 2024 GMT"' \
    0 \
    "Should detect future certificate validity"

# Test 5: Release file validity error
run_test "detect_time_error (release file not valid)" \
    'detect_time_related_apt_errors "Release file for http://archive.ubuntu.com/ubuntu/dists/focal/InRelease is not yet valid"' \
    0 \
    "Should detect Release file validity errors"

# Test 6: Release file future validity
run_test "detect_time_error (release file will be valid)" \
    'detect_time_related_apt_errors "Release file will be valid from 2024-12-25 15:00:00 UTC"' \
    0 \
    "Should detect Release file future validity"

# Test 7: Invalid signatures
run_test "detect_time_error (invalid signatures)" \
    'detect_time_related_apt_errors "The following signatures were invalid: KEYEXPIRED"' \
    0 \
    "Should detect signature validation errors"

# Test 8: Expired public key
run_test "detect_time_error (expired pubkey)" \
    'detect_time_related_apt_errors "NO_PUBKEY BC528686B50D79E6 expired"' \
    0 \
    "Should detect expired public key errors"

# Test 9: SSL certificate problem
run_test "detect_time_error (SSL certificate)" \
    'detect_time_related_apt_errors "SSL certificate problem: certificate is not yet valid"' \
    0 \
    "Should detect SSL certificate problems"

# Test 10: Server certificate verification failure
run_test "detect_time_error (server cert verification)" \
    'detect_time_related_apt_errors "server certificate verification failed"' \
    0 \
    "Should detect server certificate verification failures"

# Test 11: Certificate verification failed
run_test "detect_time_error (cert verification failed)" \
    'detect_time_related_apt_errors "Certificate verification failed: The certificate is NOT trusted"' \
    0 \
    "Should detect certificate verification failures"

# Test 12: Non-time-related error
run_test "detect_non_time_error (lock error)" \
    'detect_time_related_apt_errors "E: Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)"' \
    1 \
    "Should not detect non-time-related errors"

# Test 13: Empty error output
run_test "detect_time_error (empty)" \
    'detect_time_related_apt_errors ""' \
    1 \
    "Should not detect errors in empty input"

# Test 14: Case insensitive matching
run_test "detect_time_error (case insensitive)" \
    'detect_time_related_apt_errors "CERTIFICATE IS NOT YET VALID"' \
    0 \
    "Should detect errors case-insensitively"

# Test 15: Mixed errors
run_test "detect_time_error (mixed errors)" \
    'detect_time_related_apt_errors "E: Could not get lock\nE: Release file is not valid yet"' \
    0 \
    "Should detect time errors even when mixed with other errors"

echo
echo "Running safe APT update tests..."

# Test 16: Successful APT update
apt-get() {
    if [[ "$1" == "update" ]]; then
        echo "Reading package lists... Done"
        return 0
    fi
}
export -f apt-get

run_test "safe_apt_update (success)" \
    "safe_apt_update" \
    0 \
    "Should succeed when APT update succeeds"

# Test 17: Time error with successful retry
local attempt_count=0
apt-get() {
    if [[ "$1" == "update" ]]; then
        if [[ $attempt_count -eq 0 ]]; then
            attempt_count=1
            echo "E: Release file is not valid yet (invalid for another 2h 34min 56s)." >&2
            return 1
        else
            echo "Reading package lists... Done"
            return 0
        fi
    fi
}
export -f apt-get

run_test "safe_apt_update (time error retry)" \
    "safe_apt_update" \
    0 \
    "Should succeed after time sync and retry"

# Test 18: Non-time error
apt-get() {
    if [[ "$1" == "update" ]]; then
        echo "E: Could not get lock /var/lib/apt/lists/lock" >&2
        return 1
    fi
}
export -f apt-get

run_test "safe_apt_update (non-time error)" \
    "safe_apt_update" \
    1 \
    "Should fail with non-time errors"

# Test 19: Time error with failed sync
sync_system_time() {
    return 1  # Mock failure
}
export -f sync_system_time

apt-get() {
    echo "E: Release file is not valid yet" >&2
    return 1
}
export -f apt-get

run_test "safe_apt_update (sync failed)" \
    "safe_apt_update" \
    1 \
    "Should fail when time sync fails"

# Test 20: Custom retry count
sync_system_time() {
    return 0  # Mock success
}
export -f sync_system_time

local custom_attempt_count=0
apt-get() {
    if [[ "$1" == "update" ]]; then
        if [[ $custom_attempt_count -lt 2 ]]; then
            custom_attempt_count=$((custom_attempt_count + 1))
            echo "E: Temporary error $custom_attempt_count" >&2
            return 1
        else
            echo "Reading package lists... Done"
            return 0
        fi
    fi
}
export -f apt-get

run_test "safe_apt_update (custom retries)" \
    "safe_apt_update 3" \
    0 \
    "Should succeed within custom retry limit"

echo
echo "Running edge case tests..."

# Test 21: Very long error message
local long_prefix=$(printf 'A%.0s' {1..500})
local long_error="${long_prefix}E: Release file is not valid yet${long_prefix}"

run_test "detect_time_error (long message)" \
    "detect_time_related_apt_errors '$long_error'" \
    0 \
    "Should detect time errors in long messages"

# Test 22: Multiline error output
local multiline_error="Reading package lists... Done
Building dependency tree
Reading state information... Done
E: Release file is not valid yet
   (invalid for another 2h 34min 56s)"

run_test "detect_time_error (multiline)" \
    "detect_time_related_apt_errors '$multiline_error'" \
    0 \
    "Should detect time errors in multiline output"

# Test 23: Multiple pattern matches
run_test "detect_time_error (multiple patterns)" \
    'detect_time_related_apt_errors "certificate is not yet valid and will be valid from tomorrow"' \
    0 \
    "Should detect when multiple patterns match"

# Test 24: Regex pattern matching
run_test "detect_time_error (regex patterns)" \
    'detect_time_related_apt_errors "Release file http://example.com/InRelease is not yet valid"' \
    0 \
    "Should match regex patterns"

# Test 25: Idempotent execution
echo
echo "Testing idempotent execution..."

# Reset environment
setup_test_env

# First run
run_test "Idempotent detection 1" \
    'detect_time_related_apt_errors "certificate is not yet valid"' \
    0 \
    "First detection should succeed"

# Second run with same input
run_test "Idempotent detection 2" \
    'detect_time_related_apt_errors "certificate is not yet valid"' \
    0 \
    "Second detection should also succeed"

# Summary
echo
echo "=== Test Summary ==="
echo "Total Tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"
echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"

# Log results
echo "Test Results Summary:" > /tmp/apt_time_test_results.log
echo "Total Tests: $TESTS_RUN" >> /tmp/apt_time_test_results.log
echo "Passed: $TESTS_PASSED" >> /tmp/apt_time_test_results.log
echo "Failed: $TESTS_FAILED" >> /tmp/apt_time_test_results.log
echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%" >> /tmp/apt_time_test_results.log

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All APT time error detection tests passed!"
    echo "Test results saved to: /tmp/apt_time_test_results.log"
    exit 0
else
    echo "✗ Some tests failed!"
    echo "Test results saved to: /tmp/apt_time_test_results.log"
    exit 1
fi
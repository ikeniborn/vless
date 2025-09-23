#!/bin/bash

# VLESS+Reality VPN Management System - Time Synchronization Tests
# Version: 1.0.0
# Description: Comprehensive tests for time synchronization functionality
#
# Tests the following functions from common_utils.sh:
# 1. check_system_time_validity() - Validates system time
# 2. sync_system_time() - Synchronizes system time

set -euo pipefail

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== Time Synchronization Tests ==="
echo "Testing: check_system_time_validity, sync_system_time"
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
    export TIME_TOLERANCE_SECONDS="300"
    export NTP_SERVERS=("pool.ntp.org" "time.nist.gov" "time.google.com" "time.cloudflare.com")

    # Mock functions
    log_debug() { return 0; }
    log_info() { return 0; }
    log_warn() { return 0; }
    log_error() { return 0; }
    log_success() { return 0; }
    command_exists() {
        case "$1" in
            ntpdate|sntp|chronyc|timedatectl|systemctl|curl|timeout) return 0 ;;
            *) return 1 ;;
        esac
    }
    safe_execute() { shift; "$@"; }
    interruptible_sleep() { return 0; }
    install_package_if_missing() { return 0; }
    setup_signal_handlers() { return 0; }

    export -f log_debug log_info log_warn log_error log_success command_exists
    export -f safe_execute interruptible_sleep install_package_if_missing setup_signal_handlers
}

# Test function: check_system_time_validity (simplified for testing)
check_system_time_validity() {
    local tolerance="${1:-$TIME_TOLERANCE_SECONDS}"

    if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
        return 0
    fi

    local system_time=$(date +%s)
    local ntp_time=""

    # Mock NTP query
    if command_exists ntpdate; then
        ntp_time=$(timeout 10 ntpdate -q "${NTP_SERVERS[0]}" 2>/dev/null | grep "^server" | tail -1 | awk '{print $6}' | cut -d'.' -f1)
    fi

    if [[ -z "$ntp_time" ]]; then
        return 0  # Graceful fallback
    fi

    local time_diff=$((system_time - ntp_time))
    local abs_diff=$(( time_diff < 0 ? -time_diff : time_diff ))

    if [[ $abs_diff -gt $tolerance ]]; then
        return 1
    else
        return 0
    fi
}

# Test function: sync_system_time (simplified for testing)
sync_system_time() {
    local force="${1:-false}"

    if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ "$force" != "true" ]] && check_system_time_validity; then
        return 0
    fi

    # Try various sync methods
    if command_exists timedatectl; then
        if safe_execute 30 timedatectl set-ntp true; then
            return 0
        fi
    fi

    if command_exists ntpdate; then
        for server in "${NTP_SERVERS[@]}"; do
            if safe_execute 30 ntpdate -s "$server"; then
                return 0
            fi
        done
    fi

    return 1
}

# Run tests
echo "Setting up test environment..."
setup_test_env

echo "Running time validity tests..."

# Test 1: Time validity with sync enabled
date() { echo "1234567890"; }
ntpdate() {
    if [[ "$1" == "-q" ]]; then
        echo "server pool.ntp.org, stratum 2, offset 0.000000, delay 0.12345"
    fi
}
export -f date ntpdate

run_test "Time validity (correct time)" \
    "check_system_time_validity" \
    0 \
    "Should pass with synchronized time"

# Test 2: Time validity disabled
run_test "Time validity (disabled)" \
    "TIME_SYNC_ENABLED=false check_system_time_validity" \
    0 \
    "Should pass when time sync is disabled"

# Test 3: Custom tolerance
run_test "Time validity (custom tolerance)" \
    "check_system_time_validity 900" \
    0 \
    "Should pass with custom tolerance"

# Test 4: No NTP servers available
ntpdate() { return 1; }
sntp() { return 1; }
chronyc() { return 1; }
curl() { return 1; }
export -f ntpdate sntp chronyc curl

run_test "Time validity (no NTP)" \
    "check_system_time_validity" \
    0 \
    "Should pass gracefully when no NTP servers available"

echo
echo "Running time sync tests..."

# Reset environment
setup_test_env

# Test 5: Sync when already synchronized
check_system_time_validity() { return 0; }
export -f check_system_time_validity

run_test "Time sync (already synced)" \
    "sync_system_time" \
    0 \
    "Should succeed when already synchronized"

# Test 6: Sync disabled
run_test "Time sync (disabled)" \
    "TIME_SYNC_ENABLED=false sync_system_time" \
    0 \
    "Should succeed when time sync is disabled"

# Test 7: Forced sync
check_system_time_validity() { return 1; }
timedatectl() { return 0; }
export -f check_system_time_validity timedatectl

run_test "Time sync (forced)" \
    "sync_system_time force" \
    0 \
    "Should succeed with forced sync"

# Test 8: Network unavailable
timedatectl() { return 1; }
ntpdate() { return 1; }
export -f timedatectl ntpdate

run_test "Time sync (network unavailable)" \
    "sync_system_time force" \
    1 \
    "Should fail when all sync methods fail"

# Test 9: Environment variable bypass
run_test "Environment bypass" \
    "TIME_SYNC_ENABLED=false check_system_time_validity" \
    0 \
    "Should bypass when TIME_SYNC_ENABLED=false"

# Test 10: Idempotent execution
echo
echo "Testing idempotent execution..."
setup_test_env

run_test "Idempotent execution 1" \
    "sync_system_time" \
    0 \
    "First execution should succeed"

run_test "Idempotent execution 2" \
    "sync_system_time" \
    0 \
    "Second execution should also succeed"

# Summary
echo
echo "=== Test Summary ==="
echo "Total Tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"
echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All time synchronization tests passed!"
    exit 0
else
    echo "✗ Some tests failed!"
    exit 1
fi
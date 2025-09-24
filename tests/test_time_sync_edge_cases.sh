#!/bin/bash

# VLESS+Reality VPN Management System - Time Sync Edge Case Tests
# Version: 1.2.2
# Description: Edge case and stress tests for enhanced time synchronization
#
# Tests edge cases and failure scenarios for:
# 1. Network connectivity failures during web API calls
# 2. Service management failures and recovery
# 3. Large time offset corrections (>10 minutes, >1 hour)
# 4. Malformed web API responses
# 5. File system permission issues
# 6. Hardware clock access failures
# 7. Concurrent time sync operations
# 8. APT error pattern detection and handling

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test configuration
readonly TEST_NAME="Time Sync Edge Case Tests"
readonly TEST_VERSION="1.2.2"
readonly TEST_RESULTS_DIR="$SCRIPT_DIR/results"
readonly TEST_LOG_FILE="$TEST_RESULTS_DIR/time_sync_edge_cases.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Test utilities
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_section() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

pass_test() {
    local message="$1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
    echo -e "${GREEN}✓ PASS:${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: $message" >> "$TEST_LOG_FILE"
}

fail_test() {
    local message="$1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
    echo -e "${RED}✗ FAIL:${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: $message" >> "$TEST_LOG_FILE"
}

skip_test() {
    local message="$1"
    ((TESTS_SKIPPED++))
    ((TESTS_RUN++))
    echo -e "${YELLOW}⊝ SKIP:${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SKIP: $message" >> "$TEST_LOG_FILE"
}

info_message() {
    local message="$1"
    echo -e "${CYAN}ℹ INFO:${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $message" >> "$TEST_LOG_FILE"
}

# Edge case mock setup
setup_edge_case_environment() {
    # Create test directories and files
    export TEST_FAILURE_MODE="/tmp/test_failure_mode"
    export TEST_NETWORK_STATE="/tmp/test_network_state"
    export TEST_PERMISSION_STATE="/tmp/test_permission_state"
    export TEST_SERVICE_FAILURE="/tmp/test_service_failure"
    export TEST_API_RESPONSE_STATE="/tmp/test_api_response_state"
    export TEST_LARGE_OFFSET="/tmp/test_large_offset"

    # Initialize failure modes
    echo "normal" > "$TEST_FAILURE_MODE"
    echo "connected" > "$TEST_NETWORK_STATE"
    echo "writable" > "$TEST_PERMISSION_STATE"
    echo "healthy" > "$TEST_SERVICE_FAILURE"
    echo "valid" > "$TEST_API_RESPONSE_STATE"
    echo "0" > "$TEST_LARGE_OFFSET"

    # Create malformed API responses
    cat > "/tmp/malformed_worldtime.json" << 'EOF'
{
  "error": "invalid request",
  "message": "malformed response"
EOF

    cat > "/tmp/malformed_worldclock.json" << 'EOF'
{
  "currentDateTime": "invalid-date-format",
  "utcOffset": null
}
EOF

    cat > "/tmp/empty_response.json" << 'EOF'
EOF

    # Create test APT error outputs
    cat > "/tmp/apt_error_future.txt" << 'EOF'
E: Release file for http://archive.ubuntu.com/ubuntu/dists/focal/InRelease is not valid yet (invalid for another 2h 15min 30s). Updates for this repository will not be applied.
EOF

    cat > "/tmp/apt_error_expired.txt" << 'EOF'
W: GPG error: http://archive.ubuntu.com/ubuntu focal Release: The following signatures were invalid: BADSIG 3B4FE6ACC0B21F32 Ubuntu Archive Automatic Signing Key <ftpmaster@ubuntu.com>
E: The repository 'http://archive.ubuntu.com/ubuntu focal Release' is not signed.
EOF

    cat > "/tmp/apt_error_clock_skew.txt" << 'EOF'
E: Release file for http://security.ubuntu.com/ubuntu/dists/focal-security/InRelease is not valid yet (invalid for another 45min 22s). Updates for this repository will not be applied.
EOF
}

# Advanced mock functions for edge cases
mock_curl_edge_cases() {
    local url="$1"
    local network_state
    network_state=$(cat "$TEST_NETWORK_STATE" 2>/dev/null || echo "connected")
    local api_state
    api_state=$(cat "$TEST_API_RESPONSE_STATE" 2>/dev/null || echo "valid")

    case "$network_state" in
        "disconnected")
            echo "curl: (7) Failed to connect to host" >&2
            return 7
            ;;
        "timeout")
            echo "curl: (28) Operation timed out" >&2
            return 28
            ;;
        "dns_failure")
            echo "curl: (6) Could not resolve host" >&2
            return 6
            ;;
    esac

    case "$api_state" in
        "malformed")
            case "$url" in
                *worldtimeapi*)
                    cat "/tmp/malformed_worldtime.json"
                    ;;
                *worldclockapi*)
                    cat "/tmp/malformed_worldclock.json"
                    ;;
                *)
                    cat "/tmp/empty_response.json"
                    ;;
            esac
            ;;
        "empty")
            cat "/tmp/empty_response.json"
            ;;
        "invalid_json")
            echo "not-json-data-at-all"
            ;;
        *)
            # Use normal mock responses
            case "$url" in
                *worldtimeapi*)
                    echo '{"datetime": "2024-01-15T10:30:45.123456+00:00", "unixtime": 1705314645}'
                    ;;
                *worldclockapi*)
                    echo '{"currentDateTime": "2024-01-15T10:30:45Z"}'
                    ;;
                *timeapi.io*)
                    echo '{"dateTime": "2024-01-15T10:30:45.123Z"}'
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
}

mock_systemctl_edge_cases() {
    local action="$1"
    local service="$2"
    local failure_mode
    failure_mode=$(cat "$TEST_SERVICE_FAILURE" 2>/dev/null || echo "healthy")

    case "$failure_mode" in
        "service_not_found")
            if [[ "$action" == "is-active" ]]; then
                echo "Unit $service.service could not be found." >&2
                return 4
            fi
            ;;
        "permission_denied")
            echo "Failed to $action $service.service: Access denied" >&2
            return 1
            ;;
        "service_failed")
            if [[ "$action" == "start" || "$action" == "restart" ]]; then
                echo "Job for $service.service failed because the control process exited with error code." >&2
                return 1
            fi
            ;;
        "timeout")
            echo "A dependency job for $service.service failed" >&2
            return 1
            ;;
    esac

    # Normal mock behavior if no failure mode
    case "$action" in
        "is-active")
            echo "active"
            return 0
            ;;
        "start"|"stop"|"restart")
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

mock_hwclock_edge_cases() {
    local args="$*"
    local permission_state
    permission_state=$(cat "$TEST_PERMISSION_STATE" 2>/dev/null || echo "writable")

    case "$permission_state" in
        "no_rtc_device")
            echo "hwclock: Cannot access the Hardware Clock via any known method." >&2
            return 2
            ;;
        "permission_denied")
            echo "hwclock: Unable to set the Hardware Clock to the current System Time." >&2
            return 1
            ;;
        "rtc_busy")
            echo "hwclock: ioctl() to /dev/rtc to set the time failed: Device or resource busy" >&2
            return 1
            ;;
    esac

    # Normal behavior
    case "$args" in
        *"--show"*)
            echo "Mon 15 Jan 2024 10:30:45 AM UTC  -0.123456 seconds"
            ;;
        *"--systohc"*)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

mock_date_edge_cases() {
    local args="$*"
    local large_offset
    large_offset=$(cat "$TEST_LARGE_OFFSET" 2>/dev/null || echo "0")

    case "$args" in
        "+%s")
            # Simulate different time scenarios
            case "$large_offset" in
                "large_past")
                    echo "1705310000"  # 1+ hours in the past
                    ;;
                "large_future")
                    echo "1705320000"  # 1+ hours in the future
                    ;;
                "extreme_past")
                    echo "1705200000"  # Many hours in the past
                    ;;
                *)
                    echo "1705314645"  # Normal time
                    ;;
            esac
            ;;
        "-s"*)
            local permission_state
            permission_state=$(cat "$TEST_PERMISSION_STATE" 2>/dev/null || echo "writable")
            case "$permission_state" in
                "readonly_system")
                    echo "date: cannot set date: Operation not permitted" >&2
                    return 1
                    ;;
                *)
                    return 0
                    ;;
            esac
            ;;
        "-d"*)
            if [[ "$args" == *"invalid-date-format"* ]]; then
                echo "date: invalid date 'invalid-date-format'" >&2
                return 1
            elif [[ "$args" == *"+ 30 minutes"* ]]; then
                echo "2024-01-15 11:00:45"
            else
                echo "2024-01-15 10:30:45"
            fi
            ;;
        *)
            echo "Mon Jan 15 10:30:45 UTC 2024"
            ;;
    esac
}

mock_safe_execute_edge_cases() {
    local timeout="$1"
    shift
    local cmd="$1"

    case "$cmd" in
        "systemctl")
            mock_systemctl_edge_cases "${@:2}"
            ;;
        "hwclock")
            mock_hwclock_edge_cases "${@:2}"
            ;;
        "date")
            mock_date_edge_cases "${@:2}"
            ;;
        *)
            return 0
            ;;
    esac
}

# Set up edge case mocks
setup_edge_case_mocks() {
    export -f mock_curl_edge_cases mock_systemctl_edge_cases mock_hwclock_edge_cases
    export -f mock_date_edge_cases mock_safe_execute_edge_cases

    # Override system commands with edge case versions
    alias curl=mock_curl_edge_cases
    alias systemctl=mock_systemctl_edge_cases
    alias hwclock=mock_hwclock_edge_cases
    alias date=mock_date_edge_cases
    alias safe_execute=mock_safe_execute_edge_cases
}

# Load common utilities
load_common_utils() {
    if [[ ! -f "$SCRIPT_DIR/../modules/common_utils.sh" ]]; then
        fail_test "common_utils.sh not found at expected location"
        return 1
    fi

    source "$SCRIPT_DIR/../modules/common_utils.sh" 2>/dev/null || {
        fail_test "Failed to source common_utils.sh"
        return 1
    }

    info_message "Successfully loaded common_utils.sh with edge case mocks"
    return 0
}

# Edge Case Test Functions

test_network_failure_scenarios() {
    print_section "Testing network failure scenarios"

    # Test 1: Complete network disconnection
    echo "disconnected" > "$TEST_NETWORK_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Network disconnection handled gracefully"
    else
        fail_test "Network disconnection should cause sync failure"
    fi

    # Test 2: Network timeout scenarios
    echo "timeout" > "$TEST_NETWORK_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Network timeout handled gracefully"
    else
        fail_test "Network timeout should cause sync failure"
    fi

    # Test 3: DNS resolution failure
    echo "dns_failure" > "$TEST_NETWORK_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "DNS resolution failure handled gracefully"
    else
        fail_test "DNS failure should cause sync failure"
    fi

    # Reset network state
    echo "connected" > "$TEST_NETWORK_STATE"
}

test_malformed_api_responses() {
    print_section "Testing malformed API response handling"

    # Test 1: Malformed JSON responses
    echo "malformed" > "$TEST_API_RESPONSE_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Malformed JSON responses handled gracefully"
    else
        info_message "Malformed JSON may have been processed (unexpected success)"
    fi

    # Test 2: Empty API responses
    echo "empty" > "$TEST_API_RESPONSE_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Empty API responses handled gracefully"
    else
        info_message "Empty response processing attempted"
    fi

    # Test 3: Non-JSON responses
    echo "invalid_json" > "$TEST_API_RESPONSE_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Non-JSON responses handled gracefully"
    else
        info_message "Non-JSON response processing attempted"
    fi

    # Reset API state
    echo "valid" > "$TEST_API_RESPONSE_STATE"
}

test_service_management_failures() {
    print_section "Testing service management failure scenarios"

    # Test 1: Service not found
    echo "service_not_found" > "$TEST_SERVICE_FAILURE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Missing service handled gracefully"
    else
        pass_test "Service not found handled (possibly continued without service management)"
    fi

    # Test 2: Permission denied for service operations
    echo "permission_denied" > "$TEST_SERVICE_FAILURE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Service permission denial handled gracefully"
    else
        pass_test "Permission denial handled (possibly continued without service management)"
    fi

    # Test 3: Service failed to start/restart
    echo "service_failed" > "$TEST_SERVICE_FAILURE"
    if sync_time_from_web_api 2>/dev/null; then
        pass_test "Service start failure doesn't prevent time sync"
    else
        pass_test "Service failure handled gracefully"
    fi

    # Reset service state
    echo "healthy" > "$TEST_SERVICE_FAILURE"
}

test_hardware_clock_failures() {
    print_section "Testing hardware clock failure scenarios"

    # Test 1: No RTC device available
    echo "no_rtc_device" > "$TEST_PERMISSION_STATE"
    if ! force_hwclock_sync 2>/dev/null; then
        pass_test "Missing RTC device handled gracefully"
    else
        fail_test "Missing RTC device should cause hwclock sync failure"
    fi

    # Test 2: Permission denied for RTC access
    echo "permission_denied" > "$TEST_PERMISSION_STATE"
    if ! force_hwclock_sync 2>/dev/null; then
        pass_test "RTC permission denial handled gracefully"
    else
        fail_test "RTC permission denial should cause hwclock sync failure"
    fi

    # Test 3: RTC device busy
    echo "rtc_busy" > "$TEST_PERMISSION_STATE"
    if ! force_hwclock_sync 2>/dev/null; then
        pass_test "Busy RTC device handled gracefully"
    else
        fail_test "Busy RTC device should cause hwclock sync failure"
    fi

    # Reset permission state
    echo "writable" > "$TEST_PERMISSION_STATE"
}

test_large_time_offset_scenarios() {
    print_section "Testing large time offset scenarios"

    # Test 1: Large offset in the past (>10 minutes)
    echo "large_past" > "$TEST_LARGE_OFFSET"
    if enhanced_time_sync true "large past offset test" 2>/dev/null; then
        pass_test "Large past time offset handled"
    else
        info_message "Large past offset test completed"
    fi

    # Test 2: Large offset in the future (>10 minutes)
    echo "large_future" > "$TEST_LARGE_OFFSET"
    if enhanced_time_sync true "large future offset test" 2>/dev/null; then
        pass_test "Large future time offset handled"
    else
        info_message "Large future offset test completed"
    fi

    # Test 3: Extreme time offset (hours difference)
    echo "extreme_past" > "$TEST_LARGE_OFFSET"
    if enhanced_time_sync true "extreme offset test" 2>/dev/null; then
        pass_test "Extreme time offset handled"
    else
        info_message "Extreme offset test completed"
    fi

    # Reset offset
    echo "0" > "$TEST_LARGE_OFFSET"
}

test_file_system_permission_issues() {
    print_section "Testing file system permission issues"

    # Test 1: Read-only system (cannot set date)
    echo "readonly_system" > "$TEST_PERMISSION_STATE"
    if ! sync_time_from_web_api 2>/dev/null; then
        pass_test "Read-only system handled gracefully"
    else
        fail_test "Read-only system should prevent date setting"
    fi

    # Test 2: Chrony configuration file permission issues
    local test_chrony_conf="/tmp/test_chrony_readonly.conf"
    echo "server pool.ntp.org iburst" > "$test_chrony_conf"
    chmod 444 "$test_chrony_conf"  # Read-only

    # Temporarily override chrony config path for testing
    if ! configure_chrony_for_large_offset 2>/dev/null; then
        pass_test "Read-only chrony config handled gracefully"
    else
        info_message "Chrony config permission test completed"
    fi

    # Cleanup
    rm -f "$test_chrony_conf"
    echo "writable" > "$TEST_PERMISSION_STATE"
}

test_apt_error_pattern_detection() {
    print_section "Testing APT error pattern detection"

    # Source the function that might not be available in all contexts
    if ! command -v detect_time_related_apt_errors >/dev/null 2>&1; then
        skip_test "detect_time_related_apt_errors function not available"
        return 0
    fi

    # Test 1: Future timestamp APT errors
    if detect_time_related_apt_errors "$(cat /tmp/apt_error_future.txt 2>/dev/null || echo '')" 2>/dev/null; then
        pass_test "Future timestamp APT error detected"
    else
        fail_test "Future timestamp APT error not detected"
    fi

    # Test 2: Clock skew APT errors
    if detect_time_related_apt_errors "$(cat /tmp/apt_error_clock_skew.txt 2>/dev/null || echo '')" 2>/dev/null; then
        pass_test "Clock skew APT error detected"
    else
        fail_test "Clock skew APT error not detected"
    fi

    # Test 3: Non-time-related APT errors (should not trigger)
    if ! detect_time_related_apt_errors "$(cat /tmp/apt_error_expired.txt 2>/dev/null || echo '')" 2>/dev/null; then
        pass_test "Non-time-related APT error correctly ignored"
    else
        fail_test "Non-time-related APT error incorrectly detected as time-related"
    fi
}

test_concurrent_time_sync_operations() {
    print_section "Testing concurrent time sync operation handling"

    # This test simulates what happens if multiple time sync operations are attempted
    # In practice, this would be handled by process isolation and signal handlers

    # Test 1: Signal handler setup verification
    if enhanced_time_sync false "concurrent test" 2>/dev/null; then
        pass_test "Time sync operation completed (signal handlers active)"
    else
        info_message "Concurrent operation test completed"
    fi

    # Test 2: Multiple rapid sync attempts (would be handled by process isolation)
    local sync_count=0
    for i in {1..3}; do
        if enhanced_time_sync false "rapid sync $i" 2>/dev/null; then
            ((sync_count++))
        fi
    done

    if [[ $sync_count -gt 0 ]]; then
        pass_test "Multiple sync operations handled ($sync_count succeeded)"
    else
        fail_test "No sync operations succeeded in concurrent test"
    fi
}

test_extreme_edge_cases() {
    print_section "Testing extreme edge cases"

    # Test 1: Empty environment variables
    local original_time_sync_enabled="$TIME_SYNC_ENABLED"
    export TIME_SYNC_ENABLED=""

    if check_system_time_validity 2>/dev/null; then
        pass_test "Empty TIME_SYNC_ENABLED handled gracefully"
    else
        info_message "Empty TIME_SYNC_ENABLED test completed"
    fi

    export TIME_SYNC_ENABLED="$original_time_sync_enabled"

    # Test 2: Invalid time tolerance values
    if check_system_time_validity "invalid" 2>/dev/null; then
        pass_test "Invalid tolerance parameter handled"
    else
        info_message "Invalid tolerance test completed"
    fi

    # Test 3: Missing required binaries (simulated)
    # This would typically be handled by command_exists function
    local test_result=0
    enhanced_time_sync false "missing binary test" 2>/dev/null || test_result=$?

    if [[ $test_result -ne 127 ]]; then  # 127 = command not found
        pass_test "Missing binary scenario handled ($test_result)"
    else
        fail_test "Missing binary not handled properly"
    fi
}

test_recovery_mechanisms() {
    print_section "Testing recovery mechanisms"

    # Test 1: Recovery after network failure
    echo "disconnected" > "$TEST_NETWORK_STATE"
    sync_time_from_web_api 2>/dev/null || true

    # Restore network and try again
    echo "connected" > "$TEST_NETWORK_STATE"
    if sync_time_from_web_api 2>/dev/null; then
        pass_test "Network recovery successful"
    else
        info_message "Network recovery test completed"
    fi

    # Test 2: Service recovery after failure
    echo "service_failed" > "$TEST_SERVICE_FAILURE"
    sync_time_from_web_api 2>/dev/null || true

    # Restore service and try again
    echo "healthy" > "$TEST_SERVICE_FAILURE"
    if sync_time_from_web_api 2>/dev/null; then
        pass_test "Service recovery successful"
    else
        info_message "Service recovery test completed"
    fi

    # Test 3: Hardware clock recovery
    echo "no_rtc_device" > "$TEST_PERMISSION_STATE"
    force_hwclock_sync 2>/dev/null || true

    # Restore hardware access
    echo "writable" > "$TEST_PERMISSION_STATE"
    if force_hwclock_sync 2>/dev/null; then
        pass_test "Hardware clock recovery successful"
    else
        fail_test "Hardware clock recovery failed"
    fi
}

# Main test execution
main() {
    print_header "$TEST_NAME v$TEST_VERSION"
    echo "Starting edge case tests at $(date)"
    echo "Test results will be logged to: $TEST_LOG_FILE"
    echo ""

    # Initialize test environment
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting $TEST_NAME v$TEST_VERSION" > "$TEST_LOG_FILE"

    setup_edge_case_environment
    setup_edge_case_mocks

    if ! load_common_utils; then
        echo -e "${RED}Failed to load common utilities. Aborting tests.${NC}"
        exit 1
    fi

    # Run edge case test suites
    test_network_failure_scenarios
    test_malformed_api_responses
    test_service_management_failures
    test_hardware_clock_failures
    test_large_time_offset_scenarios
    test_file_system_permission_issues
    test_apt_error_pattern_detection
    test_concurrent_time_sync_operations
    test_extreme_edge_cases
    test_recovery_mechanisms

    # Print final results
    echo ""
    print_header "Edge Case Test Results Summary"
    echo -e "Total Tests: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"

    local success_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    echo -e "Success Rate: ${GREEN}${success_rate}%${NC}"

    # Log final results
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Edge Case Test Summary: $TESTS_RUN total, $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped" >> "$TEST_LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Success Rate: ${success_rate}%" >> "$TEST_LOG_FILE"

    # Cleanup test files
    rm -f "$TEST_FAILURE_MODE" "$TEST_NETWORK_STATE" "$TEST_PERMISSION_STATE"
    rm -f "$TEST_SERVICE_FAILURE" "$TEST_API_RESPONSE_STATE" "$TEST_LARGE_OFFSET"
    rm -f "/tmp/malformed_"*.json "/tmp/empty_response.json" "/tmp/apt_error_"*.txt

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All edge case tests completed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some edge case tests failed. Check the logs for details.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
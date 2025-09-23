#!/bin/bash

# VLESS+Reality VPN Management System - Time Synchronization Integration Tests
# Version: 1.2.1
# Description: Comprehensive tests for time synchronization functionality including fallback mechanisms
#
# This test suite validates:
# - Time validity checking functions
# - Multiple time synchronization methods and fallbacks
# - Configuration handling and variable validation
# - Error handling and recovery mechanisms
# - Integration with external time sources

set -euo pipefail

# Import test framework and module to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Import the module to test
MODULE_PATH="${SCRIPT_DIR}/../modules/common_utils.sh"

# Initialize test suite
init_test_framework "Time Synchronization Integration Tests"

# Test configuration - set before sourcing module
export TIME_SYNC_ENABLED="true"
export TIME_TOLERANCE_SECONDS="300"
export LOG_LEVEL=0  # Debug level for detailed testing

# Setup test environment
setup_test_environment() {
    # Create temporary directories for testing
    export TEST_LOG_DIR
    TEST_LOG_DIR=$(create_temp_dir)
    export LOG_FILE="${TEST_LOG_DIR}/test.log"

    # Create mock NTP response files
    export MOCK_NTP_DIR="${TEST_LOG_DIR}/mock_ntp"
    mkdir -p "$MOCK_NTP_DIR"

    # Mock successful NTP response
    echo "server 1.2.3.4, stratum 2, offset 0.000123, delay 0.05432" > "${MOCK_NTP_DIR}/ntpdate_success.txt"
    echo "2024-01-15 10:30:45.123456 (+0000) +0.000123 +/- 0.054321 pool.ntp.org" > "${MOCK_NTP_DIR}/sntp_success.txt"

    # Mock web service time response (Unix timestamp)
    local current_timestamp
    current_timestamp=$(date +%s)
    echo "{\"unixtime\": $current_timestamp}" > "${MOCK_NTP_DIR}/web_time_success.json"

    # Create mock command functions for different scenarios
    setup_mock_commands

    # Source the module after mocking
    source "$MODULE_PATH"
}

# Setup mock commands for different test scenarios
setup_mock_commands() {
    # Mock successful NTP commands
    mock_command "ntpdate" "custom" 'ntpdate() {
        local server="$1"
        if [[ "$server" == "fail.example.com" ]]; then
            echo "no server suitable for synchronization found" >&2
            return 1
        fi
        echo "15 Jan 10:30:45 ntpdate[12345]: adjust time server 1.2.3.4 offset 0.000123 sec"
        cat "${MOCK_NTP_DIR}/ntpdate_success.txt"
        return 0
    }'

    mock_command "sntp" "custom" 'sntp() {
        local server="$2"  # sntp uses -t flag before server
        if [[ "$server" == "fail.example.com" ]]; then
            echo "sntp: no server suitable for synchronization found" >&2
            return 1
        fi
        cat "${MOCK_NTP_DIR}/sntp_success.txt"
        return 0
    }'

    mock_command "chronyc" "custom" 'chronyc() {
        if [[ "$1" == "tracking" ]]; then
            echo "System time     : 0.000000123 seconds fast of NTP time"
            return 0
        elif [[ "$1" == "makestep" ]]; then
            echo "200 OK"
            return 0
        fi
        return 1
    }'

    mock_command "timedatectl" "success" ""
    mock_command "systemctl" "success" ""

    # Mock curl for web time service
    mock_command "curl" "custom" 'curl() {
        local url=""
        while [[ $# -gt 0 ]]; do
            case $1 in
                -s) shift ;;
                http://*) url="$1"; shift ;;
                *) shift ;;
            esac
        done

        if [[ "$url" == *"worldtimeapi.org"* ]]; then
            cat "${MOCK_NTP_DIR}/web_time_success.json"
            return 0
        elif [[ "$url" == *"timeapi.io"* ]]; then
            cat "${MOCK_NTP_DIR}/web_time_success.json"
            return 0
        fi
        return 1
    }'

    # Mock date command to return controlled time
    mock_command "date" "custom" 'date() {
        if [[ "$1" == "+%s" ]]; then
            # Return a fixed timestamp for consistent testing
            echo "1705316445"  # 2024-01-15 10:30:45 UTC
        else
            command date "$@"
        fi
    }'

    # Mock timeout command
    mock_command "timeout" "custom" 'timeout() {
        local duration="$1"
        shift
        "$@"
    }'

    # Mock command_exists function
    mock_command "command_exists" "custom" 'command_exists() {
        local cmd="$1"
        case "$cmd" in
            ntpdate|sntp|chronyc|timedatectl|curl) return 0 ;;
            *) return 1 ;;
        esac
    }'
}

# Cleanup test environment
cleanup_test_environment() {
    cleanup_temp_files
    [[ -n "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
    # Note: Cannot unset readonly variables TIME_SYNC_ENABLED and TIME_TOLERANCE_SECONDS
}

# Test functions

test_time_sync_configuration_validation() {
    # Test that configuration variables are properly set
    assert_equals "true" "$TIME_SYNC_ENABLED" "TIME_SYNC_ENABLED should be true"
    assert_equals "300" "$TIME_TOLERANCE_SECONDS" "TIME_TOLERANCE_SECONDS should be 300"

    # Test NTP servers array is defined and not empty
    assert_true "[[ \${#NTP_SERVERS[@]} -gt 0 ]]" "NTP_SERVERS array should not be empty"

    # Verify at least some common NTP servers are included
    local ntp_servers_string="${NTP_SERVERS[*]}"
    assert_contains "$ntp_servers_string" "pool.ntp.org" "Should include pool.ntp.org"
}

test_check_system_time_validity_success() {
    # Test successful time validity check
    local result
    if result=$(check_system_time_validity 2>&1); then
        pass_test "Time validity check should succeed with proper mocks"
    else
        fail_test "Time validity check failed: $result"
    fi
}

test_check_system_time_validity_with_tolerance() {
    # Test time validity check with custom tolerance
    local result
    if result=$(check_system_time_validity 600 2>&1); then
        pass_test "Time validity check should succeed with larger tolerance"
    else
        fail_test "Time validity check with custom tolerance failed: $result"
    fi
}

test_check_system_time_validity_disabled() {
    # Test behavior when time sync is disabled
    local original_setting="$TIME_SYNC_ENABLED"
    export TIME_SYNC_ENABLED="false"

    local result
    if result=$(check_system_time_validity 2>&1); then
        pass_test "Time validity check should succeed when disabled"
    else
        fail_test "Time validity check should succeed when disabled: $result"
    fi

    export TIME_SYNC_ENABLED="$original_setting"
}

test_sync_system_time_systemd_method() {
    # Test systemd-timesyncd method
    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should succeed with systemd method"
    else
        fail_test "Time sync with systemd method failed: $result"
    fi
}

test_sync_system_time_ntpdate_fallback() {
    # Mock systemd commands to fail, forcing ntpdate fallback
    mock_command "timedatectl" "failure" "Failed to connect to bus"

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should fallback to ntpdate successfully"
    else
        fail_test "Time sync ntpdate fallback failed: $result"
    fi

    # Restore systemd mock
    mock_command "timedatectl" "success" ""
}

test_sync_system_time_sntp_fallback() {
    # Mock both systemd and ntpdate to fail, forcing sntp fallback
    mock_command "timedatectl" "failure" "Failed to connect to bus"
    mock_command "ntpdate" "failure" "Connection refused"

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should fallback to sntp successfully"
    else
        fail_test "Time sync sntp fallback failed: $result"
    fi

    # Restore mocks
    mock_command "timedatectl" "success" ""
    setup_mock_commands
}

test_sync_system_time_chrony_fallback() {
    # Mock systemd, ntpdate, and sntp to fail, forcing chrony fallback
    mock_command "timedatectl" "failure" "Failed to connect to bus"
    mock_command "ntpdate" "failure" "Connection refused"
    mock_command "sntp" "failure" "Connection refused"

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should fallback to chrony successfully"
    else
        fail_test "Time sync chrony fallback failed: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_sync_system_time_disabled() {
    # Test behavior when time sync is disabled
    local original_setting="$TIME_SYNC_ENABLED"
    export TIME_SYNC_ENABLED="false"

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should succeed (do nothing) when disabled"
    else
        fail_test "Time sync should succeed when disabled: $result"
    fi

    export TIME_SYNC_ENABLED="$original_setting"
}

test_sync_system_time_force_option() {
    # Test forced sync bypasses validity check
    local result
    if result=$(sync_system_time "true" 2>&1); then
        pass_test "Forced time sync should always attempt synchronization"
    else
        fail_test "Forced time sync failed: $result"
    fi
}

test_sync_system_time_all_methods_fail() {
    # Mock all time sync methods to fail
    mock_command "timedatectl" "failure" "Failed to connect to bus"
    mock_command "ntpdate" "failure" "Connection refused"
    mock_command "sntp" "failure" "Connection refused"
    mock_command "chronyc" "failure" "Can't connect to daemon"

    # Also mock package installation to fail
    mock_command "apt-get" "failure" "Package not found"

    local result
    set +e
    result=$(sync_system_time 2>&1)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        pass_test "Time sync should fail when all methods are unavailable"
    else
        fail_test "Time sync should have failed when all methods are unavailable: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_web_service_fallback() {
    # Mock NTP commands to fail, test web service fallback in validity check
    mock_command "ntpdate" "failure" "Connection refused"
    mock_command "sntp" "failure" "Connection refused"
    mock_command "chronyc" "failure" "Can't connect to daemon"

    local result
    if result=$(check_system_time_validity 2>&1); then
        pass_test "Time validity check should fallback to web services"
    else
        fail_test "Web service fallback failed: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_ntp_server_iteration() {
    # Test that multiple NTP servers are tried
    local server_count=0

    # Mock ntpdate to fail for first server, succeed for second
    mock_command "ntpdate" "custom" 'ntpdate() {
        local server="$2"
        if [[ "$server" == "${NTP_SERVERS[0]}" ]]; then
            echo "Connection timeout" >&2
            return 1
        else
            echo "15 Jan 10:30:45 ntpdate[12345]: adjust time server $server offset 0.000123 sec"
            return 0
        fi
    }'

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Time sync should try multiple NTP servers on failure"
    else
        fail_test "Multiple NTP server iteration failed: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_time_difference_calculation() {
    # Test time difference calculation in validity check

    # Mock date to return a time that's 100 seconds off
    mock_command "date" "custom" 'date() {
        if [[ "$1" == "+%s" ]]; then
            echo "1705316545"  # 100 seconds ahead of mocked NTP time
        else
            original_date "$@"
        fi
    }'

    local result
    set +e
    result=$(check_system_time_validity 50 2>&1)  # 50 second tolerance
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        pass_test "Time validity check should fail when time difference exceeds tolerance"
    else
        fail_test "Time validity check should have failed with large time difference: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_no_reference_time_handling() {
    # Test behavior when no reference time can be obtained
    mock_command "ntpdate" "failure" "Connection refused"
    mock_command "sntp" "failure" "Connection refused"
    mock_command "chronyc" "failure" "Can't connect to daemon"
    mock_command "curl" "failure" "Connection refused"

    local result
    if result=$(check_system_time_validity 2>&1); then
        pass_test "Time validity check should succeed gracefully when no reference time available"
    else
        fail_test "Should handle missing reference time gracefully: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

test_signal_handling_setup() {
    # Test that signal handlers are properly set up during time sync
    local result
    if result=$(sync_system_time 2>&1); then
        # Check that cleanup functions are registered (this is indirect testing)
        assert_true "[[ \"\$CLEANUP_REGISTERED\" == \"true\" ]]" "Signal handlers should be registered"
        pass_test "Signal handlers should be set up during time sync"
    else
        fail_test "Time sync failed: $result"
    fi
}

test_interruptible_sleep_during_sync() {
    # Test that interruptible sleep is used (can't easily test interruption in unit test)
    # This test validates the function is called correctly

    # Mock interruptible_sleep to track calls
    local sleep_called=false
    mock_command "interruptible_sleep" "custom" 'interruptible_sleep() {
        sleep_called=true
        return 0
    }'

    local result
    if result=$(sync_system_time 2>&1); then
        assert_true "[[ \"\$sleep_called\" == \"true\" ]]" "Interruptible sleep should be used during sync"
        pass_test "Interruptible sleep is properly used"
    else
        fail_test "Time sync failed: $result"
    fi
}

test_logging_levels_during_sync() {
    # Test that appropriate log levels are used
    local log_content

    # Run time sync and capture log output
    sync_system_time >/dev/null 2>&1 || true

    if [[ -f "$LOG_FILE" ]]; then
        log_content=$(cat "$LOG_FILE")
        assert_contains "$log_content" "INFO" "Should contain INFO level logs"
        assert_contains "$log_content" "DEBUG" "Should contain DEBUG level logs"
        pass_test "Appropriate logging levels are used"
    else
        skip_test "Log file not created during test"
    fi
}

test_package_installation_fallback() {
    # Test ntpdate installation when not available
    mock_command "command_exists" "custom" 'command_exists() {
        local cmd="$1"
        case "$cmd" in
            timedatectl|sntp|chronyc) return 1 ;;  # Not available
            ntpdate) return 1 ;;  # Initially not available
            curl) return 0 ;;
            *) return 1 ;;
        esac
    }'

    # Mock package installation
    mock_command "install_package_if_missing" "custom" 'install_package_if_missing() {
        local package="$1"
        if [[ "$package" == "ntpdate" ]]; then
            # After "installation", make ntpdate available
            mock_command "command_exists" "custom" "command_exists() {
                local cmd=\"\$1\"
                case \"\$cmd\" in
                    ntpdate|curl) return 0 ;;
                    *) return 1 ;;
                esac
            }"
            return 0
        fi
        return 1
    }'

    local result
    if result=$(sync_system_time 2>&1); then
        pass_test "Should install ntpdate when other methods fail"
    else
        fail_test "Package installation fallback failed: $result"
    fi

    # Restore mocks
    setup_mock_commands
}

# Main test execution
main() {
    setup_test_environment

    # Run all tests
    run_all_test_functions

    # Cleanup and finalize
    cleanup_test_environment
    finalize_test_suite
}

# Trap cleanup on exit
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
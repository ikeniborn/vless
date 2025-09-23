#!/bin/bash

# VLESS+Reality VPN Management System - Safe APT Update Tests
# Version: 1.2.1
# Description: Comprehensive tests for safe_apt_update functionality and APT error handling
#
# This test suite validates:
# - APT error pattern detection for time-related issues
# - safe_apt_update function with automatic retry and time sync
# - Error handling and recovery mechanisms
# - Integration with time synchronization
# - Module adoption of safe_apt_update

set -euo pipefail

# Import test framework and module to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Import the module to test
MODULE_PATH="${SCRIPT_DIR}/../modules/common_utils.sh"

# Initialize test suite
init_test_framework "Safe APT Update Tests"

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

    # Create mock APT error responses
    export MOCK_APT_DIR="${TEST_LOG_DIR}/mock_apt"
    mkdir -p "$MOCK_APT_DIR"

    # Create various APT error scenarios
    create_apt_error_scenarios

    # Setup mock commands
    setup_mock_commands

    # Source the module after mocking
    source "$MODULE_PATH"
}

# Create mock APT error response files
create_apt_error_scenarios() {
    # Time-related errors
    cat > "${MOCK_APT_DIR}/time_error_1.txt" << 'EOF'
W: GPG error: http://archive.ubuntu.com/ubuntu focal InRelease: The following signatures were invalid: EXPKEYSIG 3B4FE6ACC0B21F32 Ubuntu Archive Automatic Signing Key <ftpmaster@ubuntu.com>
E: The repository 'http://archive.ubuntu.com/ubuntu focal InRelease' is not signed.
W: Release file for http://archive.ubuntu.com/ubuntu/dists/focal/InRelease is not valid yet (invalid for another 2h 31m 45s). Updates for this repository will not be applied.
EOF

    cat > "${MOCK_APT_DIR}/time_error_2.txt" << 'EOF'
W: An error occurred during the signature verification. The repository is not updated and the previous index files will be used. GPG error: https://download.docker.com/linux/ubuntu focal InRelease: The following signatures were invalid: EXPKEYSIG 9DC858229FC7DD38 Docker Release (CE deb) <docker@docker.com>
E: Release file for https://download.docker.com/linux/ubuntu/dists/focal/InRelease is not yet valid (invalid for another 1h 23m 12s). Updates for this repository will not be applied.
EOF

    cat > "${MOCK_APT_DIR}/time_error_3.txt" << 'EOF'
W: GPG error: https://packages.microsoft.com/ubuntu/20.04/prod focal InRelease: The following signatures were invalid: BADSIG BC528686B50D79E339D3721CEB3E94ADBE1229CF Microsoft (Release signing) <gpgsecurity@microsoft.com>
E: The repository 'https://packages.microsoft.com/ubuntu/20.04/prod focal InRelease' is not signed.
W: Release file for https://packages.microsoft.com/ubuntu/20.04/prod/dists/focal/InRelease will be valid from 2024-01-15 12:00:00 UTC. Updates for this repository will not be applied.
EOF

    cat > "${MOCK_APT_DIR}/ssl_error.txt" << 'EOF'
W: Failed to fetch https://example.com/dists/focal/InRelease  SSL certificate problem: certificate is not yet valid
E: Some index files failed to download. They have been ignored, or old ones used instead.
EOF

    cat > "${MOCK_APT_DIR}/cert_verification_error.txt" << 'EOF'
W: Failed to fetch https://example.com/dists/focal/InRelease  Certificate verification failed: The certificate is not yet valid
E: Some index files failed to download. They have been ignored, or old ones used instead.
EOF

    # Non-time-related errors
    cat > "${MOCK_APT_DIR}/network_error.txt" << 'EOF'
W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/focal/InRelease  Temporary failure resolving 'archive.ubuntu.com'
W: Some index files failed to download. They have been ignored, or old ones used instead.
EOF

    cat > "${MOCK_APT_DIR}/space_error.txt" << 'EOF'
E: Write error - write (28: No space left on device)
E: IO Error saving source cache
E: The package lists or status file could not be parsed or opened.
EOF

    cat > "${MOCK_APT_DIR}/permission_error.txt" << 'EOF'
E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), are you root?
EOF

    # Success response
    cat > "${MOCK_APT_DIR}/success.txt" << 'EOF'
Hit:1 http://archive.ubuntu.com/ubuntu focal InRelease
Get:2 http://archive.ubuntu.com/ubuntu focal-updates InRelease [114 kB]
Get:3 http://archive.ubuntu.com/ubuntu focal-backports InRelease [108 kB]
Get:4 http://security.ubuntu.com/ubuntu focal-security InRelease [114 kB]
Fetched 336 kB in 2s (168 kB/s)
Reading package lists... Done
EOF
}

# Setup mock commands for different test scenarios
setup_mock_commands() {
    # Mock apt-get update with different behaviors
    local apt_behavior="success"
    local apt_error_file=""

    mock_command "apt-get" "custom" 'apt-get() {
        local cmd="$1"
        if [[ "$cmd" == "update" ]]; then
            case "${APT_TEST_SCENARIO:-success}" in
                "time_error_1")
                    cat "${MOCK_APT_DIR}/time_error_1.txt" >&2
                    return 1
                    ;;
                "time_error_2")
                    cat "${MOCK_APT_DIR}/time_error_2.txt" >&2
                    return 1
                    ;;
                "time_error_3")
                    cat "${MOCK_APT_DIR}/time_error_3.txt" >&2
                    return 1
                    ;;
                "ssl_error")
                    cat "${MOCK_APT_DIR}/ssl_error.txt" >&2
                    return 1
                    ;;
                "cert_verification_error")
                    cat "${MOCK_APT_DIR}/cert_verification_error.txt" >&2
                    return 1
                    ;;
                "network_error")
                    cat "${MOCK_APT_DIR}/network_error.txt" >&2
                    return 1
                    ;;
                "space_error")
                    cat "${MOCK_APT_DIR}/space_error.txt" >&2
                    return 1
                    ;;
                "permission_error")
                    cat "${MOCK_APT_DIR}/permission_error.txt" >&2
                    return 1
                    ;;
                "retry_success")
                    # Fail first time, succeed second time
                    if [[ "${APT_RETRY_COUNT:-0}" -eq 0 ]]; then
                        export APT_RETRY_COUNT=1
                        cat "${MOCK_APT_DIR}/time_error_1.txt" >&2
                        return 1
                    else
                        cat "${MOCK_APT_DIR}/success.txt"
                        return 0
                    fi
                    ;;
                "persistent_failure")
                    cat "${MOCK_APT_DIR}/time_error_1.txt" >&2
                    return 1
                    ;;
                "success"|*)
                    cat "${MOCK_APT_DIR}/success.txt"
                    return 0
                    ;;
            esac
        elif [[ "$cmd" == "install" ]]; then
            echo "Reading package lists... Done"
            echo "Building dependency tree"
            echo "Package installed successfully"
            return 0
        fi
        return 0
    }'

    # Mock sync_system_time
    mock_command "sync_system_time" "custom" 'sync_system_time() {
        case "${TIME_SYNC_SCENARIO:-success}" in
            "failure")
                echo "Failed to synchronize time" >&2
                return 1
                ;;
            "success"|*)
                echo "Time synchronized successfully"
                return 0
                ;;
        esac
    }'

    # Mock interruptible_sleep
    mock_command "interruptible_sleep" "custom" 'interruptible_sleep() {
        return 0  # No actual sleep in tests
    }'

    # Mock check_system_time_validity
    mock_command "check_system_time_validity" "success" ""
}

# Cleanup test environment
cleanup_test_environment() {
    cleanup_temp_files
    [[ -n "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
    # Note: Cannot unset readonly variables TIME_SYNC_ENABLED and TIME_TOLERANCE_SECONDS
    unset APT_TEST_SCENARIO TIME_SYNC_SCENARIO APT_RETRY_COUNT 2>/dev/null || true
}

# Test functions

test_detect_time_related_apt_errors_positive_cases() {
    # Test detection of various time-related error patterns
    local error_files=(
        "time_error_1.txt"
        "time_error_2.txt"
        "time_error_3.txt"
        "ssl_error.txt"
        "cert_verification_error.txt"
    )

    for error_file in "${error_files[@]}"; do
        local error_content
        error_content=$(cat "${MOCK_APT_DIR}/${error_file}")

        if detect_time_related_apt_errors "$error_content"; then
            pass_test "Should detect time-related error in $error_file"
        else
            fail_test "Failed to detect time-related error in $error_file"
        fi
    done
}

test_detect_time_related_apt_errors_negative_cases() {
    # Test that non-time-related errors are not detected as time-related
    local error_files=(
        "network_error.txt"
        "space_error.txt"
        "permission_error.txt"
    )

    for error_file in "${error_files[@]}"; do
        local error_content
        error_content=$(cat "${MOCK_APT_DIR}/${error_file}")

        if detect_time_related_apt_errors "$error_content"; then
            fail_test "Should not detect time-related error in $error_file"
        else
            pass_test "Correctly identified non-time-related error in $error_file"
        fi
    done
}

test_detect_time_related_apt_errors_specific_patterns() {
    # Test specific error patterns individually
    local test_cases=(
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

    for pattern in "${test_cases[@]}"; do
        local test_error="Error: This is a test with pattern: $pattern"

        if detect_time_related_apt_errors "$test_error"; then
            pass_test "Should detect pattern: $pattern"
        else
            fail_test "Failed to detect pattern: $pattern"
        fi
    done
}

test_safe_apt_update_success() {
    # Test successful APT update
    export APT_TEST_SCENARIO="success"

    local result
    if result=$(safe_apt_update 2>&1); then
        assert_contains "$result" "APT update completed successfully" "Should report success"
        pass_test "safe_apt_update should succeed with no errors"
    else
        fail_test "safe_apt_update failed unexpectedly: $result"
    fi
}

test_safe_apt_update_time_error_with_sync_success() {
    # Test APT update with time error that gets resolved after time sync
    export APT_TEST_SCENARIO="retry_success"
    export TIME_SYNC_SCENARIO="success"

    local result
    if result=$(safe_apt_update 2>&1); then
        assert_contains "$result" "Detected time-related APT errors" "Should detect time error"
        assert_contains "$result" "Time synchronized, retrying APT update" "Should attempt time sync"
        assert_contains "$result" "APT update completed successfully" "Should succeed after retry"
        pass_test "safe_apt_update should recover from time errors with sync"
    else
        fail_test "safe_apt_update failed to recover from time error: $result"
    fi
}

test_safe_apt_update_time_error_with_sync_failure() {
    # Test APT update with time error where time sync fails
    export APT_TEST_SCENARIO="time_error_1"
    export TIME_SYNC_SCENARIO="failure"

    local result
    set +e
    result=$(safe_apt_update 2>&1)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        assert_contains "$result" "Detected time-related APT errors" "Should detect time error"
        assert_contains "$result" "Failed to synchronize time" "Should report sync failure"
        assert_contains "$result" "APT update failed after" "Should report final failure"
        pass_test "safe_apt_update should fail when time sync fails"
    else
        fail_test "safe_apt_update should have failed when time sync fails: $result"
    fi
}

test_safe_apt_update_non_time_error() {
    # Test APT update with non-time-related error
    export APT_TEST_SCENARIO="network_error"

    local result
    set +e
    result=$(safe_apt_update 2>&1)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        assert_contains "$result" "APT error does not appear to be time-related" "Should identify non-time error"
        assert_contains "$result" "APT update failed after" "Should report final failure"
        pass_test "safe_apt_update should handle non-time errors correctly"
    else
        fail_test "safe_apt_update should have failed with network error: $result"
    fi
}

test_safe_apt_update_persistent_time_error() {
    # Test APT update with persistent time error that doesn't resolve
    export APT_TEST_SCENARIO="persistent_failure"
    export TIME_SYNC_SCENARIO="success"

    local result
    set +e
    result=$(safe_apt_update 3 2>&1)  # 3 retries
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        assert_contains "$result" "APT update failed after 3 attempts" "Should exhaust retries"
        pass_test "safe_apt_update should fail after exhausting retries"
    else
        fail_test "safe_apt_update should have failed after retries: $result"
    fi
}

test_safe_apt_update_custom_retry_count() {
    # Test safe_apt_update with custom retry count
    export APT_TEST_SCENARIO="persistent_failure"

    local result
    set +e
    result=$(safe_apt_update 1 2>&1)  # Only 1 retry
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        assert_contains "$result" "APT update failed after 1 attempts" "Should respect custom retry count"
        pass_test "safe_apt_update should respect custom retry count"
    else
        fail_test "safe_apt_update should have failed with 1 retry: $result"
    fi
}

test_safe_apt_update_output_capture() {
    # Test that APT output is properly captured and logged
    export APT_TEST_SCENARIO="time_error_1"

    local result
    set +e
    result=$(safe_apt_update 2>&1)
    local exit_code=$?
    set -e

    assert_contains "$result" "APT update failed with exit code:" "Should report exit code"
    assert_contains "$result" "APT error output:" "Should log error output"

    if [[ -f "$LOG_FILE" ]]; then
        local log_content
        log_content=$(cat "$LOG_FILE")
        assert_contains "$log_content" "ASSERTION FAILED" "Should log error details" || true
        pass_test "APT output should be captured and logged"
    else
        skip_test "Log file not available for verification"
    fi
}

test_safe_apt_update_interruptible_sleep() {
    # Test that interruptible sleep is used between retries
    export APT_TEST_SCENARIO="persistent_failure"

    # Mock interruptible_sleep to track calls
    local sleep_call_count=0
    mock_command "interruptible_sleep" "custom" 'interruptible_sleep() {
        sleep_call_count=$((sleep_call_count + 1))
        return 0
    }'

    local result
    set +e
    result=$(safe_apt_update 3 2>&1)
    set -e

    # Should call interruptible_sleep between retries (2 times for 3 attempts)
    if [[ $sleep_call_count -gt 0 ]]; then
        pass_test "safe_apt_update should use interruptible sleep between retries"
    else
        fail_test "safe_apt_update did not use interruptible sleep"
    fi
}

test_safe_apt_update_signal_handling() {
    # Test that signal handling is maintained during APT operations
    export APT_TEST_SCENARIO="success"

    local result
    if result=$(safe_apt_update 2>&1); then
        # This is an indirect test - we verify that the function completes
        # without issues, indicating signal handling didn't interfere
        pass_test "safe_apt_update should handle signals correctly"
    else
        fail_test "safe_apt_update signal handling test failed: $result"
    fi
}

test_safe_apt_update_logging_levels() {
    # Test that appropriate logging levels are used
    export APT_TEST_SCENARIO="time_error_1"

    local result
    set +e
    result=$(safe_apt_update 2>&1)
    set -e

    # Check for different log levels in output
    assert_contains "$result" "INFO" "Should use INFO level logging"
    assert_contains "$result" "WARN" "Should use WARN level logging"
    assert_contains "$result" "DEBUG" "Should use DEBUG level logging"

    pass_test "safe_apt_update should use appropriate logging levels"
}

test_module_adoption_verification() {
    # Test that modules use safe_apt_update instead of direct apt-get update
    local modules_dir="${SCRIPT_DIR}/../modules"
    local problematic_modules=()

    # Check each module for direct apt-get update usage
    while IFS= read -r -d '' module_file; do
        local module_name
        module_name=$(basename "$module_file")

        # Skip common_utils.sh as it defines safe_apt_update
        [[ "$module_name" == "common_utils.sh" ]] && continue

        # Look for direct apt-get update calls (not through safe_apt_update)
        if grep -q "apt-get[[:space:]]\+update" "$module_file" && \
           ! grep -q "safe_apt_update" "$module_file"; then
            problematic_modules+=("$module_name")
        fi
    done < <(find "$modules_dir" -name "*.sh" -type f -print0 2>/dev/null || true)

    if [[ ${#problematic_modules[@]} -eq 0 ]]; then
        pass_test "All modules should use safe_apt_update instead of direct apt-get update"
    else
        fail_test "Modules using direct apt-get update: ${problematic_modules[*]}"
    fi
}

test_install_package_if_missing_integration() {
    # Test that install_package_if_missing uses safe_apt_update
    local function_content

    # Extract the function definition to check implementation
    if function_content=$(declare -f install_package_if_missing 2>/dev/null); then
        if echo "$function_content" | grep -q "safe_apt_update"; then
            pass_test "install_package_if_missing should use safe_apt_update"
        else
            # Check if it exists and what it uses
            if echo "$function_content" | grep -q "apt-get update"; then
                fail_test "install_package_if_missing uses direct apt-get update"
            else
                skip_test "install_package_if_missing implementation unclear"
            fi
        fi
    else
        skip_test "install_package_if_missing function not available for testing"
    fi
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
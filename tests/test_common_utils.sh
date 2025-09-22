#!/bin/bash

# VLESS+Reality VPN Management System - Common Utils Unit Tests
# Version: 1.0.0
# Description: Unit tests for common_utils.sh module

set -euo pipefail

# Import test framework and module to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Import the module to test (but mock external dependencies)
MODULE_PATH="${SCRIPT_DIR}/../modules/common_utils.sh"

# Initialize test suite
init_test_framework "Common Utils Unit Tests"

# Setup test environment
setup_test_environment() {
    # Create temporary directories for testing
    export TEST_LOG_DIR
    TEST_LOG_DIR=$(create_temp_dir)
    export LOG_FILE="${TEST_LOG_DIR}/test.log"

    # Mock external commands that might not be available
    mock_command "systemctl" "success" ""
    mock_command "docker" "success" "Docker version 20.10.12"
    mock_command "ufw" "success" ""
}

# Cleanup test environment
cleanup_test_environment() {
    cleanup_temp_files
    [[ -n "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
}

# Test functions

test_color_codes_defined() {
    source "$MODULE_PATH"

    # Test that color codes are properly defined
    assert_not_equals "" "$RED" "RED color code should be defined"
    assert_not_equals "" "$GREEN" "GREEN color code should be defined"
    assert_not_equals "" "$YELLOW" "YELLOW color code should be defined"
    assert_not_equals "" "$BLUE" "BLUE color code should be defined"
    assert_not_equals "" "$NC" "NC (No Color) code should be defined"
}

test_log_levels_defined() {
    source "$MODULE_PATH"

    # Test that log levels are properly defined
    assert_equals "0" "$LOG_DEBUG" "LOG_DEBUG should be 0"
    assert_equals "1" "$LOG_INFO" "LOG_INFO should be 1"
    assert_equals "2" "$LOG_WARN" "LOG_WARN should be 2"
    assert_equals "3" "$LOG_ERROR" "LOG_ERROR should be 3"
    assert_equals "4" "$LOG_FATAL" "LOG_FATAL should be 4"
}

test_script_paths_detection() {
    source "$MODULE_PATH"

    # Test that script paths are correctly detected
    assert_file_exists "$SCRIPT_DIR" "SCRIPT_DIR should exist"
    assert_contains "$PROJECT_ROOT" "vless" "PROJECT_ROOT should contain 'vless'"
}

test_validate_not_empty_function() {
    source "$MODULE_PATH"

    # Test validate_not_empty with valid input
    if validate_not_empty "test_value" "test_param"; then
        pass_test "validate_not_empty should pass with non-empty value"
    else
        fail_test "validate_not_empty should pass with non-empty value"
        return
    fi

    # Test validate_not_empty with empty input
    if ! validate_not_empty "" "empty_param" 2>/dev/null; then
        pass_test "validate_not_empty should fail with empty value"
    else
        fail_test "validate_not_empty should fail with empty value"
    fi
}

test_uuid_generation() {
    source "$MODULE_PATH"

    # Test UUID generation
    local uuid1 uuid2
    uuid1=$(generate_uuid)
    uuid2=$(generate_uuid)

    # UUID should be 36 characters long (including hyphens)
    assert_equals "36" "${#uuid1}" "UUID should be 36 characters long"

    # Two generated UUIDs should be different
    assert_not_equals "$uuid1" "$uuid2" "Generated UUIDs should be unique"

    # UUID should match pattern (basic check)
    if [[ $uuid1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        pass_test "UUID should match expected format"
    else
        fail_test "UUID should match expected format: $uuid1"
    fi
}

test_uuid_validation() {
    source "$MODULE_PATH"

    # Test valid UUID
    local valid_uuid="550e8400-e29b-41d4-a716-446655440000"
    if validate_uuid "$valid_uuid"; then
        pass_test "Should validate correct UUID format"
    else
        fail_test "Should validate correct UUID format"
        return
    fi

    # Test invalid UUID formats
    local invalid_uuids=(
        "not-a-uuid"
        "550e8400-e29b-41d4-a716"
        "550e8400-e29b-41d4-a716-446655440000-extra"
        ""
        "550e8400xe29bx41d4xa716x446655440000"
    )

    for invalid_uuid in "${invalid_uuids[@]}"; do
        if ! validate_uuid "$invalid_uuid" 2>/dev/null; then
            pass_test "Should reject invalid UUID: $invalid_uuid"
        else
            fail_test "Should reject invalid UUID: $invalid_uuid"
        fi
    done
}

test_logging_functions() {
    source "$MODULE_PATH"

    # Create a test log file
    local test_log_file
    test_log_file=$(create_temp_file)
    export LOG_FILE="$test_log_file"
    export LOG_LEVEL=$LOG_DEBUG

    # Test different log levels
    log_debug "Debug message"
    log_info "Info message"
    log_warn "Warning message"
    log_error "Error message"

    # Check that messages were written to log file
    if [[ -f "$test_log_file" ]]; then
        local log_content
        log_content=$(cat "$test_log_file")

        assert_contains "$log_content" "Debug message" "Log should contain debug message"
        assert_contains "$log_content" "Info message" "Log should contain info message"
        assert_contains "$log_content" "Warning message" "Log should contain warning message"
        assert_contains "$log_content" "Error message" "Log should contain error message"
    else
        fail_test "Log file should be created"
    fi
}

test_check_root_privileges() {
    source "$MODULE_PATH"

    # This test depends on whether the test is run as root or not
    if [[ $EUID -eq 0 ]]; then
        # Running as root - function should pass
        if check_root_privileges; then
            pass_test "check_root_privileges should pass when running as root"
        else
            fail_test "check_root_privileges should pass when running as root"
        fi
    else
        # Not running as root - function should fail
        if ! check_root_privileges 2>/dev/null; then
            pass_test "check_root_privileges should fail when not running as root"
        else
            fail_test "check_root_privileges should fail when not running as root"
        fi
    fi
}

test_network_connectivity_check() {
    source "$MODULE_PATH"

    # Mock ping command for testing
    mock_command "ping" "success" "PING google.com: 56 data bytes"

    if check_network_connectivity; then
        pass_test "Network connectivity check should pass with mocked ping"
    else
        fail_test "Network connectivity check should pass with mocked ping"
    fi

    # Test with failing ping
    mock_command "ping" "failure" "ping: cannot resolve google.com"

    if ! check_network_connectivity 2>/dev/null; then
        pass_test "Network connectivity check should fail with failing ping"
    else
        fail_test "Network connectivity check should fail with failing ping"
    fi
}

test_system_info_detection() {
    source "$MODULE_PATH"

    # Test OS detection (this will use actual system values)
    local os_info
    os_info=$(detect_os)

    assert_not_equals "" "$os_info" "OS detection should return non-empty result"

    # Test that it returns expected format
    if [[ "$os_info" =~ ^[A-Za-z]+[[:space:]]+[0-9]+\.[0-9]+ ]]; then
        pass_test "OS detection should return expected format: $os_info"
    else
        fail_test "OS detection should return expected format, got: $os_info"
    fi
}

test_error_handling() {
    source "$MODULE_PATH"

    # Test handle_error function
    local error_msg="Test error message"
    local error_code=42

    # Mock exit to capture the behavior
    exit() { echo "exit_code:$1"; }

    local result
    result=$(handle_error "$error_msg" $error_code 2>&1)

    assert_contains "$result" "$error_msg" "Error message should be included in output"
    assert_contains "$result" "exit_code:$error_code" "Should exit with correct code"
}

test_input_validation_functions() {
    source "$MODULE_PATH"

    # Test email validation
    if validate_email "test@example.com"; then
        pass_test "Should validate correct email format"
    else
        fail_test "Should validate correct email format"
    fi

    if ! validate_email "invalid-email" 2>/dev/null; then
        pass_test "Should reject invalid email format"
    else
        fail_test "Should reject invalid email format"
    fi

    # Test port validation
    if validate_port "443"; then
        pass_test "Should validate valid port number"
    else
        fail_test "Should validate valid port number"
    fi

    if ! validate_port "99999" 2>/dev/null; then
        pass_test "Should reject invalid port number"
    else
        fail_test "Should reject invalid port number"
    fi
}

test_process_management() {
    source "$MODULE_PATH"

    # Test process isolation setup
    setup_signal_handlers

    # Verify that cleanup is registered
    assert_equals "true" "$CLEANUP_REGISTERED" "Cleanup should be registered after setup"

    # Test child process tracking (basic functionality)
    local test_pid=12345
    track_child_process $test_pid

    # Check if PID was added to array
    local found=false
    for pid in "${CHILD_PROCESSES[@]}"; do
        if [[ "$pid" == "$test_pid" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" == "true" ]]; then
        pass_test "Child process should be tracked"
    else
        fail_test "Child process should be tracked"
    fi
}

# Main execution
main() {
    setup_test_environment
    trap cleanup_test_environment EXIT

    # Run all test functions
    run_all_test_functions

    # Finalize test suite
    finalize_test_suite
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
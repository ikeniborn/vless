#!/bin/bash

# VLESS+Reality VPN Management System - Test Framework
# Version: 1.0.0
# Description: Common test framework utilities and functions
#
# This framework provides:
# - Test assertion functions
# - Test result tracking
# - Mock functions for external dependencies
# - Test report generation

set -euo pipefail

# Test framework configuration
readonly TEST_FRAMEWORK_VERSION="1.0.0"
readonly TEST_RESULTS_DIR="/home/ikeniborn/Documents/Project/vless/tests/results"
readonly TEST_LOG_FILE="${TEST_RESULTS_DIR}/test_framework.log"

# Test colors
readonly T_RED='\033[0;31m'
readonly T_GREEN='\033[0;32m'
readonly T_YELLOW='\033[1;33m'
readonly T_BLUE='\033[0;34m'
readonly T_PURPLE='\033[0;35m'
readonly T_CYAN='\033[0;36m'
readonly T_WHITE='\033[1;37m'
readonly T_NC='\033[0m' # No Color

# Test counters
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Test state
CURRENT_TEST_SUITE=""
CURRENT_TEST_NAME=""
TEST_START_TIME=""
TEST_SUITE_START_TIME=""

# Initialize test framework
init_test_framework() {
    local test_suite_name="$1"
    CURRENT_TEST_SUITE="$test_suite_name"
    TEST_SUITE_START_TIME=$(date +%s)

    # Ensure results directory exists
    mkdir -p "$TEST_RESULTS_DIR"

    # Initialize test log
    {
        echo "=========================================="
        echo "Test Suite: $test_suite_name"
        echo "Start Time: $(date)"
        echo "Framework Version: $TEST_FRAMEWORK_VERSION"
        echo "=========================================="
    } >> "$TEST_LOG_FILE"

    echo -e "${T_CYAN}Starting test suite: ${T_WHITE}$test_suite_name${T_NC}"
}

# Start individual test
start_test() {
    local test_name="$1"
    CURRENT_TEST_NAME="$test_name"
    TEST_START_TIME=$(date +%s)
    ((TEST_TOTAL++))

    echo -n -e "${T_BLUE}  Running: ${T_WHITE}$test_name${T_NC} ... "
    echo "Starting test: $test_name" >> "$TEST_LOG_FILE"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    Expected: ${T_GREEN}$expected${T_NC}"
        echo -e "    Actual:   ${T_RED}$actual${T_NC}"
        echo "ASSERTION FAILED: $message - Expected: '$expected', Actual: '$actual'" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$not_expected" != "$actual" ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    Not Expected: ${T_RED}$not_expected${T_NC}"
        echo -e "    Actual:       ${T_RED}$actual${T_NC}"
        echo "ASSERTION FAILED: $message - Not Expected: '$not_expected', Actual: '$actual'" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    String: ${T_YELLOW}$haystack${T_NC}"
        echo -e "    Should contain: ${T_GREEN}$needle${T_NC}"
        echo "ASSERTION FAILED: $message - String '$haystack' should contain '$needle'" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    String: ${T_YELLOW}$haystack${T_NC}"
        echo -e "    Should not contain: ${T_RED}$needle${T_NC}"
        echo "ASSERTION FAILED: $message - String '$haystack' should not contain '$needle'" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"

    if [[ -f "$file_path" ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    File: ${T_YELLOW}$file_path${T_NC}"
        echo "ASSERTION FAILED: $message - File '$file_path' does not exist" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_file_not_exists() {
    local file_path="$1"
    local message="${2:-File should not exist}"

    if [[ ! -f "$file_path" ]]; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    File: ${T_YELLOW}$file_path${T_NC}"
        echo "ASSERTION FAILED: $message - File '$file_path' should not exist" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command should succeed}"

    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    Command: ${T_YELLOW}$command${T_NC}"
        echo "ASSERTION FAILED: $message - Command '$command' failed" >> "$TEST_LOG_FILE"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-Command should fail}"

    if ! eval "$command" >/dev/null 2>&1; then
        return 0
    else
        echo -e "\n    ${T_RED}ASSERTION FAILED:${T_NC} $message"
        echo -e "    Command: ${T_YELLOW}$command${T_NC}"
        echo "ASSERTION FAILED: $message - Command '$command' should have failed" >> "$TEST_LOG_FILE"
        return 1
    fi
}

# Test completion functions
pass_test() {
    local message="${1:-}"
    local test_end_time=$(date +%s)
    local duration=$((test_end_time - TEST_START_TIME))

    ((TEST_PASSED++))
    echo -e "${T_GREEN}PASS${T_NC} (${duration}s)"
    [[ -n "$message" ]] && echo -e "    ${T_GREEN}$message${T_NC}"
    echo "Test PASSED: $CURRENT_TEST_NAME (${duration}s) - $message" >> "$TEST_LOG_FILE"
}

fail_test() {
    local message="${1:-Test failed}"
    local test_end_time=$(date +%s)
    local duration=$((test_end_time - TEST_START_TIME))

    ((TEST_FAILED++))
    echo -e "${T_RED}FAIL${T_NC} (${duration}s)"
    echo -e "    ${T_RED}$message${T_NC}"
    echo "Test FAILED: $CURRENT_TEST_NAME (${duration}s) - $message" >> "$TEST_LOG_FILE"
}

skip_test() {
    local reason="${1:-Test skipped}"

    ((TEST_SKIPPED++))
    echo -e "${T_YELLOW}SKIP${T_NC}"
    echo -e "    ${T_YELLOW}$reason${T_NC}"
    echo "Test SKIPPED: $CURRENT_TEST_NAME - $reason" >> "$TEST_LOG_FILE"
}

# Mock functions for external dependencies
mock_command() {
    local command_name="$1"
    local mock_behavior="${2:-success}"
    local mock_output="${3:-}"

    case "$mock_behavior" in
        "success")
            eval "${command_name}() { echo '$mock_output'; return 0; }"
            ;;
        "failure")
            eval "${command_name}() { echo '$mock_output' >&2; return 1; }"
            ;;
        "custom")
            # For custom mock behavior, the mock_output should be a function definition
            eval "$mock_output"
            ;;
    esac
}

# Utility functions for testing
create_temp_file() {
    local content="${1:-}"
    local temp_file
    temp_file=$(mktemp)
    [[ -n "$content" ]] && echo "$content" > "$temp_file"
    echo "$temp_file"
}

create_temp_dir() {
    mktemp -d
}

cleanup_temp_files() {
    # Clean up any temporary files created during testing
    find /tmp -name "tmp.*" -user "$(whoami)" -mtime +1 -delete 2>/dev/null || true
}

# Test suite completion
finalize_test_suite() {
    local suite_end_time=$(date +%s)
    local total_duration=$((suite_end_time - TEST_SUITE_START_TIME))

    echo ""
    echo -e "${T_CYAN}========================================${T_NC}"
    echo -e "${T_CYAN}Test Suite Results: ${T_WHITE}$CURRENT_TEST_SUITE${T_NC}"
    echo -e "${T_CYAN}========================================${T_NC}"
    echo -e "${T_WHITE}Total Tests:${T_NC}   $TEST_TOTAL"
    echo -e "${T_GREEN}Passed:${T_NC}       $TEST_PASSED"
    echo -e "${T_RED}Failed:${T_NC}       $TEST_FAILED"
    echo -e "${T_YELLOW}Skipped:${T_NC}      $TEST_SKIPPED"
    echo -e "${T_WHITE}Duration:${T_NC}     ${total_duration}s"

    # Calculate success rate
    if [[ $TEST_TOTAL -gt 0 ]]; then
        local success_rate=$((TEST_PASSED * 100 / TEST_TOTAL))
        echo -e "${T_WHITE}Success Rate:${T_NC} ${success_rate}%"

        if [[ $TEST_FAILED -eq 0 ]]; then
            echo -e "${T_GREEN}All tests passed!${T_NC}"
        else
            echo -e "${T_RED}Some tests failed.${T_NC}"
        fi
    fi

    # Write summary to log
    {
        echo "=========================================="
        echo "Test Suite Summary: $CURRENT_TEST_SUITE"
        echo "Total: $TEST_TOTAL, Passed: $TEST_PASSED, Failed: $TEST_FAILED, Skipped: $TEST_SKIPPED"
        echo "Duration: ${total_duration}s"
        echo "End Time: $(date)"
        echo "=========================================="
        echo ""
    } >> "$TEST_LOG_FILE"

    # Return appropriate exit code
    [[ $TEST_FAILED -eq 0 ]] && return 0 || return 1
}

# Test discovery and execution helpers
run_test_function() {
    local test_function="$1"

    if declare -f "$test_function" >/dev/null; then
        start_test "$test_function"

        # Run test in subshell to isolate side effects
        if (
            set -euo pipefail
            "$test_function"
        ); then
            pass_test
        else
            fail_test "Test function execution failed"
        fi
    else
        start_test "$test_function"
        fail_test "Test function not found"
    fi
}

# Discover and run all test functions in current scope
run_all_test_functions() {
    local test_functions
    test_functions=$(declare -F | grep -E "^declare -f test_" | cut -d' ' -f3 | sort)

    if [[ -z "$test_functions" ]]; then
        echo -e "${T_YELLOW}No test functions found (functions should start with 'test_')${T_NC}"
        return 0
    fi

    for test_func in $test_functions; do
        run_test_function "$test_func"
    done
}

# Export functions for use in test scripts
export -f init_test_framework start_test pass_test fail_test skip_test
export -f assert_equals assert_not_equals assert_contains assert_not_contains
export -f assert_file_exists assert_file_not_exists assert_command_success assert_command_failure
export -f mock_command create_temp_file create_temp_dir cleanup_temp_files
export -f finalize_test_suite run_test_function run_all_test_functions
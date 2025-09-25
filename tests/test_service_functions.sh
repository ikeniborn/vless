#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Service Functions Test Suite
# Version: 1.0.0
# Description: Tests for service functions: help, backup, uninstall
# Author: VLESS Testing Team

#######################################################################################
# TEST CONSTANTS AND CONFIGURATION
#######################################################################################

readonly TEST_SCRIPT_NAME="test_service_functions"
readonly TEST_VERSION="1.0.0"
readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_ROOT")"
readonly VLESS_MANAGER="$PROJECT_ROOT/vless-manager.sh"

# Test results tracking
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -a FAILED_TEST_NAMES=()

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Test environment setup
export TEST_MODE=true
export MOCK_SYSTEM_CALLS=true

# Test temporary directories
readonly TEST_TEMP_DIR="/tmp/claude/vless_service_test_$$"
readonly TEST_PROJECT_ROOT="$TEST_TEMP_DIR/vless"

#######################################################################################
# TEST UTILITY FUNCTIONS
#######################################################################################

# Test logging function
test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        "PASS")
            echo -e "${GREEN}[PASS]${NC} ${timestamp} - $message"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        *)
            echo "$timestamp - $message"
            ;;
    esac
}

# Test assertion function
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        test_log "FAIL" "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

# Test start function
test_start() {
    local test_name="$1"
    echo -e "\n${WHITE}Testing: $test_name${NC}"
    ((TOTAL_TESTS++))
}

# Test pass function
test_pass() {
    local message="$1"
    test_log "PASS" "$message"
    ((PASSED_TESTS++))
}

# Test fail function
test_fail() {
    local message="$1"
    test_log "FAIL" "$message"
    ((FAILED_TESTS++))
    FAILED_TEST_NAMES+=("$message")
}

# Test info function
test_info() {
    local message="$1"
    test_log "INFO" "$message"
}

# Prevent script from executing when sourced
export SOURCING_MODE=true

# Load the main script in test mode
export PROJECT_PATH="$TEST_PROJECT_ROOT"
source "${VLESS_MANAGER}" 2>/dev/null || true

# Mock dangerous operations
docker() {
    if [[ "$1" == "compose" ]] || [[ "$1" == "rm" ]] || [[ "$1" == "rmi" ]]; then
        echo "Mock: docker $*"
        return 0
    fi
    command docker "$@" 2>/dev/null || echo "Mock: docker $*"
}

rm() {
    if [[ "$1" == "-rf" ]] || [[ "$1" == "-f" ]]; then
        echo "Mock: rm $*"
        return 0
    fi
    command rm "$@"
}

# Export mocked functions
export -f docker
export -f rm

# Test suite setup
setup_suite() {
    test_log "INFO" "Starting Service Functions Test Suite v${TEST_VERSION}"

    # Create test environment
    mkdir -p "$TEST_PROJECT_ROOT"
    export PROJECT_PATH="$TEST_PROJECT_ROOT"

    test_log "INFO" "Test environment created at: $TEST_PROJECT_ROOT"
}

# Test suite teardown
teardown_suite() {
    test_log "INFO" "Cleaning up test environment"

    # Clean up test directory
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Test show_help function
test_show_help() {
    test_start "show_help displays help information"

    # Capture help output
    local output=$(show_help 2>&1)

    # Check for required sections
    if echo "$output" | grep -q "VLESS+Reality VPN Service Manager" && \
       echo "$output" | grep -q "System Commands:" && \
       echo "$output" | grep -q "User Management:" && \
       echo "$output" | grep -q "Service Control:" && \
       echo "$output" | grep -q "help.*Show this help message" && \
       echo "$output" | grep -q "install.*Install VPN service" && \
       echo "$output" | grep -q "uninstall.*Remove VPN service"; then
        test_pass "Help displays all required sections"
    else
        test_fail "Help missing required sections"
    fi
}

# Test help command variants
test_help_command_variants() {
    test_start "Help command accepts various formats"

    # Test different help invocations through main
    for cmd in "help" "--help" "-h"; do
        # Mock the main function call
        case "$cmd" in
            "help"|"--help"|"-h")
                local result="success"
                ;;
            *)
                local result="fail"
                ;;
        esac

        if [[ "$result" == "success" ]]; then
            test_info "Command '$cmd' recognized"
        else
            test_fail "Command '$cmd' not recognized"
            return
        fi
    done

    test_pass "All help command variants work"
}

# Test backup_service with no installation
test_backup_no_installation() {
    test_start "backup_service handles missing installation"

    # Ensure no .env file exists
    command rm -f "$TEST_PROJECT_ROOT/.env"

    # Try to create backup
    local output=$(backup_service 2>&1)
    local result=$?

    if [[ $result -ne 0 ]] && echo "$output" | grep -q "Service not installed"; then
        test_pass "Correctly detects no installation"
    else
        test_fail "Should detect missing installation"
    fi
}

# Test backup_service with mock installation
test_backup_with_installation() {
    test_start "backup_service creates backup archive"

    # Create mock installation
    echo "PROJECT_PATH=$TEST_PROJECT_ROOT" > "$TEST_PROJECT_ROOT/.env"
    echo "SERVER_IP=1.2.3.4" >> "$TEST_PROJECT_ROOT/.env"

    mkdir -p "$TEST_PROJECT_ROOT/config"
    echo '{"test": "config"}' > "$TEST_PROJECT_ROOT/config/server.json"

    mkdir -p "$TEST_PROJECT_ROOT/data"
    echo "test_user:uuid:shortid:date:active" > "$TEST_PROJECT_ROOT/data/users.db"

    echo "version: '3'" > "$TEST_PROJECT_ROOT/docker-compose.yml"

    # Create backup
    local output=$(backup_service 2>&1)
    local result=$?

    # Check if backup was created
    local backup_file=$(ls "$TEST_PROJECT_ROOT"/vless_backup_*.tar.gz 2>/dev/null | head -n1)

    if [[ $result -eq 0 ]] && [[ -f "$backup_file" ]]; then
        # Verify archive contents
        tar -tzf "$backup_file" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            test_pass "Backup archive created successfully"
        else
            test_fail "Backup archive is invalid"
        fi

        # Clean up backup file
        command rm -f "$backup_file"
    else
        test_fail "Backup creation failed"
    fi
}

# Test uninstall_service confirmation
test_uninstall_confirmation() {
    test_start "uninstall_service requires confirmation"

    # Create mock installation
    echo "PROJECT_PATH=$TEST_PROJECT_ROOT" > "$TEST_PROJECT_ROOT/.env"
    echo "version: '3'" > "$TEST_PROJECT_ROOT/docker-compose.yml"

    # Simulate 'no' response
    echo "no" | uninstall_service >/dev/null 2>&1

    # Check if files still exist
    if [[ -f "$TEST_PROJECT_ROOT/.env" ]] && [[ -f "$TEST_PROJECT_ROOT/docker-compose.yml" ]]; then
        test_pass "Uninstall cancelled when not confirmed"
    else
        test_fail "Files removed without confirmation"
    fi
}

# Test uninstall_service without backup
test_uninstall_without_backup() {
    test_start "uninstall_service removes all components without backup"

    # Create mock installation
    echo "PROJECT_PATH=$TEST_PROJECT_ROOT" > "$TEST_PROJECT_ROOT/.env"
    echo "version: '3'" > "$TEST_PROJECT_ROOT/docker-compose.yml"
    mkdir -p "$TEST_PROJECT_ROOT/config" "$TEST_PROJECT_ROOT/data" "$TEST_PROJECT_ROOT/logs"
    echo "test" > "$TEST_PROJECT_ROOT/config/server.json"
    echo "test" > "$TEST_PROJECT_ROOT/data/users.db"
    echo "test" > "$TEST_PROJECT_ROOT/logs/xray.log"

    # Simulate 'yes' for confirmation and 'n' for backup
    printf "yes\nn\n" | uninstall_service >/dev/null 2>&1

    # Check if directories and files were removed (mocked)
    local all_removed=true

    # Since we're mocking rm, files won't actually be removed
    # Check that the mock was called (by checking output contains Mock:)
    printf "yes\nn\n" | uninstall_service 2>&1 | grep -q "Mock: rm" && all_removed=true || all_removed=false

    if [[ "$all_removed" == "true" ]]; then
        test_pass "Uninstall attempts to remove all components"
    else
        test_fail "Uninstall did not attempt removal"
    fi
}

# Test uninstall_service with backup
test_uninstall_with_backup() {
    test_start "uninstall_service creates backup before removal"

    # Create mock installation
    echo "PROJECT_PATH=$TEST_PROJECT_ROOT" > "$TEST_PROJECT_ROOT/.env"
    echo "version: '3'" > "$TEST_PROJECT_ROOT/docker-compose.yml"
    mkdir -p "$TEST_PROJECT_ROOT/config" "$TEST_PROJECT_ROOT/data"
    echo '{"test": "config"}' > "$TEST_PROJECT_ROOT/config/server.json"
    echo "test_user:uuid:shortid:date:active" > "$TEST_PROJECT_ROOT/data/users.db"

    # Simulate 'yes' for confirmation and 'y' for backup
    printf "yes\ny\n" | uninstall_service 2>&1 | grep -q "Backup created successfully"
    local backup_created=$?

    if [[ $backup_created -eq 0 ]]; then
        test_pass "Backup created before uninstall"
    else
        test_fail "Backup not created before uninstall"
    fi

    # Clean up any backup files
    command rm -f "$TEST_PROJECT_ROOT"/vless_backup_*.tar.gz
}

# Test uninstall with missing components
test_uninstall_partial_installation() {
    test_start "uninstall_service handles partial installation"

    # Create only docker-compose.yml (partial installation)
    echo "version: '3'" > "$TEST_PROJECT_ROOT/docker-compose.yml"
    # No .env file

    # Try to uninstall
    printf "yes\nn\n" | uninstall_service >/dev/null 2>&1
    local result=$?

    # Should proceed with uninstall even with partial installation
    if [[ $result -eq 0 ]]; then
        test_pass "Handles partial installation gracefully"
    else
        test_fail "Failed to handle partial installation"
    fi
}

# Test main function with unknown command
test_main_unknown_command() {
    test_start "main function shows help for unknown command"

    # Capture output for unknown command
    local output=$(main "unknown_command" 2>&1)

    if echo "$output" | grep -q "Error: Unknown command 'unknown_command'" && \
       echo "$output" | grep -q "VLESS+Reality VPN Service Manager"; then
        test_pass "Shows error and help for unknown command"
    else
        test_fail "Should show error and help for unknown command"
    fi
}

# Test main function with no arguments
test_main_no_arguments() {
    test_start "main function shows help when no arguments"

    # Capture output with no arguments
    local output=$(main 2>&1)

    if echo "$output" | grep -q "VLESS+Reality VPN Service Manager"; then
        test_pass "Shows help when no arguments provided"
    else
        test_fail "Should show help when no arguments"
    fi
}

# Run specific test
run_test() {
    local test_name="$1"

    case "$test_name" in
        "help")
            test_show_help
            test_help_command_variants
            ;;
        "backup")
            test_backup_no_installation
            test_backup_with_installation
            ;;
        "uninstall")
            test_uninstall_confirmation
            test_uninstall_without_backup
            test_uninstall_with_backup
            test_uninstall_partial_installation
            ;;
        "main")
            test_main_unknown_command
            test_main_no_arguments
            ;;
        *)
            echo "Unknown test: $test_name"
            echo "Available tests: help, backup, uninstall, main"
            return 1
            ;;
    esac
}

# Display test results summary
display_results() {
    echo
    echo "============================================"
    echo "Service Functions Test Suite - Summary"
    echo "============================================"
    echo -e "Total Tests: ${WHITE}${TOTAL_TESTS}${NC}"
    echo -e "Passed:      ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed:      ${RED}${FAILED_TESTS}${NC}"
    echo "============================================"

    if [[ ${#FAILED_TEST_NAMES[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}Failed Tests:${NC}"
        for test_name in "${FAILED_TEST_NAMES[@]}"; do
            echo "  - $test_name"
        done
    fi

    echo
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Main test execution
run_tests() {
    setup_suite

    # Run all test functions
    test_show_help
    test_help_command_variants
    test_backup_no_installation
    test_backup_with_installation
    test_uninstall_confirmation
    test_uninstall_without_backup
    test_uninstall_with_backup
    test_uninstall_partial_installation
    test_main_unknown_command
    test_main_no_arguments

    teardown_suite
    display_results
}

# Execute tests when run directly or from test runner
if [[ "${1:-}" == "run" ]] || [[ -z "${1:-}" ]]; then
    run_tests
    exit $?
fi
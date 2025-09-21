#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Common Utilities Unit Tests
# ======================================================================================
# Unit tests for individual functions in the common_utils.sh module.
# Tests all utility functions, logging functions, and validation functions.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ======================================================================================
# TEST UTILITY FUNCTIONS
# ======================================================================================

# Function: run_test
# Description: Run a single test with error handling
run_test() {
    local test_name="$1"
    local test_function="$2"

    echo -n "Testing $test_name... "
    ((TESTS_RUN++))

    if $test_function; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ======================================================================================
# LOGGING FUNCTION TESTS
# ======================================================================================

# Function: test_log_info
# Description: Test log_info function
test_log_info() {
    # Create temporary log directory
    local temp_log_dir="/tmp/vless_test_$$"
    mkdir -p "$temp_log_dir"
    export LOG_DIR="$temp_log_dir"

    # Test log_info function
    log_info "Test message" &>/dev/null

    # Check if log file was created and contains message
    if [[ -f "$temp_log_dir/vless.log" ]] && grep -q "Test message" "$temp_log_dir/vless.log"; then
        rm -rf "$temp_log_dir"
        return 0
    else
        rm -rf "$temp_log_dir"
        return 1
    fi
}

# Function: test_log_error
# Description: Test log_error function
test_log_error() {
    local temp_log_dir="/tmp/vless_test_$$"
    mkdir -p "$temp_log_dir"
    export LOG_DIR="$temp_log_dir"

    # Test log_error function
    log_error "Test error" &>/dev/null

    # Check if log file was created and contains error
    if [[ -f "$temp_log_dir/vless.log" ]] && grep -q "ERROR.*Test error" "$temp_log_dir/vless.log"; then
        rm -rf "$temp_log_dir"
        return 0
    else
        rm -rf "$temp_log_dir"
        return 1
    fi
}

# Function: test_get_timestamp
# Description: Test timestamp generation
test_get_timestamp() {
    local timestamp
    timestamp=$(get_timestamp)

    # Check timestamp format (YYYY-MM-DD HH:MM:SS)
    if [[ $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        return 0
    else
        return 1
    fi
}

# ======================================================================================
# VALIDATION FUNCTION TESTS
# ======================================================================================

# Function: test_validate_port_valid
# Description: Test port validation with valid port
test_validate_port_valid() {
    # Test with high port that should be available
    if validate_port 54321 &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: test_validate_port_invalid
# Description: Test port validation with invalid port
test_validate_port_invalid() {
    # Test with invalid port number
    if ! validate_port 99999 &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: test_validate_port_string
# Description: Test port validation with string input
test_validate_port_string() {
    # Test with non-numeric input
    if ! validate_port "abc" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: test_validate_ip_valid
# Description: Test IP validation with valid IP
test_validate_ip_valid() {
    if validate_ip "192.168.1.1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: test_validate_ip_invalid
# Description: Test IP validation with invalid IP
test_validate_ip_invalid() {
    if ! validate_ip "256.256.256.256" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ======================================================================================
# UTILITY FUNCTION TESTS
# ======================================================================================

# Function: test_generate_uuid
# Description: Test UUID generation
test_generate_uuid() {
    local uuid1 uuid2
    uuid1=$(generate_uuid)
    uuid2=$(generate_uuid)

    # Check that UUIDs are different and not empty
    if [[ -n "$uuid1" && -n "$uuid2" && "$uuid1" != "$uuid2" ]]; then
        return 0
    else
        return 1
    fi
}

# Function: test_backup_file
# Description: Test file backup functionality
test_backup_file() {
    local temp_file="/tmp/test_backup_$$"
    echo "test content" > "$temp_file"

    # Test backup function
    if backup_file "$temp_file" &>/dev/null; then
        # Check if backup was created
        if ls "${temp_file}.backup."* &>/dev/null; then
            rm -f "$temp_file" "${temp_file}.backup."*
            return 0
        fi
    fi

    rm -f "$temp_file" "${temp_file}.backup."*
    return 1
}

# Function: test_create_directory
# Description: Test directory creation
test_create_directory() {
    local temp_dir="/tmp/test_dir_$$"

    # Test directory creation
    if create_directory "$temp_dir" "755" "$(whoami):$(whoami)" &>/dev/null; then
        if [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir"
            return 0
        fi
    fi

    rm -rf "$temp_dir"
    return 1
}

# Function: test_ensure_file_exists
# Description: Test file creation
test_ensure_file_exists() {
    local temp_file="/tmp/test_file_$$"

    # Test file creation
    if ensure_file_exists "$temp_file" "644" "$(whoami):$(whoami)" &>/dev/null; then
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            return 0
        fi
    fi

    rm -f "$temp_file"
    return 1
}

# ======================================================================================
# PACKAGE MANAGEMENT TESTS
# ======================================================================================

# Function: test_is_package_installed
# Description: Test package installation check
test_is_package_installed() {
    # Test with a package that should be installed (bash)
    if is_package_installed "bash" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ======================================================================================
# MAIN TEST EXECUTION
# ======================================================================================

# Function: run_unit_tests
# Description: Run all unit tests
run_unit_tests() {
    echo -e "${BLUE}VLESS Common Utilities - Unit Tests${NC}"
    echo "===================================="
    echo ""

    # Source the common utilities module
    if ! source "${MODULES_DIR}/common_utils.sh" 2>/dev/null; then
        echo -e "${RED}ERROR: Cannot source common_utils.sh${NC}"
        exit 1
    fi

    # Override some settings for testing
    export VLESS_TEST_MODE=true
    export VLESS_LOG_LEVEL=0

    echo -e "${BLUE}Testing Logging Functions:${NC}"
    run_test "log_info function" test_log_info
    run_test "log_error function" test_log_error
    run_test "timestamp generation" test_get_timestamp

    echo ""
    echo -e "${BLUE}Testing Validation Functions:${NC}"
    run_test "valid port validation" test_validate_port_valid
    run_test "invalid port validation" test_validate_port_invalid
    run_test "string port validation" test_validate_port_string
    run_test "valid IP validation" test_validate_ip_valid
    run_test "invalid IP validation" test_validate_ip_invalid

    echo ""
    echo -e "${BLUE}Testing Utility Functions:${NC}"
    run_test "UUID generation" test_generate_uuid
    run_test "file backup" test_backup_file
    run_test "directory creation" test_create_directory
    run_test "file creation" test_ensure_file_exists

    echo ""
    echo -e "${BLUE}Testing Package Functions:${NC}"
    run_test "package check" test_is_package_installed

    # Show results
    show_results
}

# Function: show_results
# Description: Show test results summary
show_results() {
    echo ""
    echo "=============================================="
    echo -e "${BLUE}UNIT TEST RESULTS${NC}"
    echo "=============================================="
    echo "Tests Run: $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

    local success_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi

    echo "Success Rate: ${success_rate}%"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL UNIT TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${RED}✗ SOME UNIT TESTS FAILED!${NC}"
        return 1
    fi
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Function: main
# Description: Main execution function
main() {
    # Check if help requested
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << 'EOF'
VLESS Common Utilities Unit Test Suite

Usage: ./test_common_utils.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

This script tests individual functions in common_utils.sh including:
- Logging functions (log_info, log_error, etc.)
- Validation functions (validate_port, validate_ip, etc.)
- Utility functions (generate_uuid, backup_file, etc.)
- Package management functions

Run this script to ensure all utility functions work correctly.
EOF
        exit 0
    fi

    # Enable verbose mode if requested
    if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
        set -x
    fi

    # Run unit tests
    run_unit_tests
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
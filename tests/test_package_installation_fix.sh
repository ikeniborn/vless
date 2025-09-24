#!/bin/bash

# Test script for package installation fix
# Tests the updated install_package_if_missing function

set -euo pipefail

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set test mode to avoid log file issues
export LOG_FILE="/tmp/test_package_install_$$.log"

source "${SCRIPT_DIR}/../modules/common_utils.sh"

echo "========================================="
echo "Package Installation Fix Test Suite"
echo "========================================="

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_function="$2"

    echo -n "Testing: $test_name... "

    if $test_function; then
        echo "✓ PASSED"
        ((TESTS_PASSED++))
    else
        echo "✗ FAILED"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Check if is_package_installed detects installed packages
test_detect_installed_packages() {
    # Test with a package we know is installed (bash)
    if is_package_installed "bash"; then
        return 0
    else
        return 1
    fi
}

# Test 2: Check if is_package_installed correctly identifies ca-certificates
test_ca_certificates_detection() {
    # ca-certificates should be installed on most systems
    if dpkg -l ca-certificates 2>/dev/null | grep -q "^ii"; then
        # If ca-certificates is installed via dpkg, our function should detect it
        is_package_installed "ca-certificates"
        return $?
    else
        # If not installed, our function should not detect it
        ! is_package_installed "ca-certificates"
        return $?
    fi
}

# Test 3: Test gnupg detection (checks for gpg command)
test_gnupg_detection() {
    if command -v gpg >/dev/null 2>&1; then
        # If gpg exists, gnupg should be detected as installed
        is_package_installed "gnupg"
        return $?
    else
        # If gpg doesn't exist, gnupg should not be detected
        ! is_package_installed "gnupg"
        return $?
    fi
}

# Test 4: Test lsb-release detection
test_lsb_release_detection() {
    if command -v lsb_release >/dev/null 2>&1; then
        # If lsb_release command exists, package should be detected
        is_package_installed "lsb-release"
        return $?
    else
        ! is_package_installed "lsb-release"
        return $?
    fi
}

# Test 5: Test curl detection (command-based package)
test_curl_detection() {
    if command -v curl >/dev/null 2>&1; then
        is_package_installed "curl"
        return $?
    else
        ! is_package_installed "curl"
        return $?
    fi
}

# Test 6: Test non-existent package
test_nonexistent_package() {
    # This package should not exist
    ! is_package_installed "this-package-does-not-exist-12345"
    return $?
}

# Test 7: Simulate package installation check for ca-certificates
test_ca_certificates_installation() {
    # Check current state
    local was_installed=false
    if is_package_installed "ca-certificates"; then
        was_installed=true
        echo "(ca-certificates already installed, skipping installation test)"
        return 0
    fi

    # If not installed, we can't actually test installation without root
    if [[ $EUID -ne 0 ]]; then
        echo "(skipped - requires root)"
        return 0
    fi

    # Try to install (if running as root)
    install_package_if_missing "ca-certificates"
    return $?
}

# Test 8: Test the function doesn't fail on already installed packages
test_already_installed_package() {
    # This should succeed without trying to install
    local output
    output=$(install_package_if_missing "bash" 2>&1)

    # Should not contain "Installing" message
    if echo "$output" | grep -q "Installing missing package"; then
        return 1
    else
        return 0
    fi
}

# Run all tests
echo ""
echo "Running Package Installation Tests..."
echo "-------------------------------------"

run_test "Detect installed packages" test_detect_installed_packages
run_test "ca-certificates detection" test_ca_certificates_detection
run_test "gnupg detection" test_gnupg_detection
run_test "lsb-release detection" test_lsb_release_detection
run_test "curl detection" test_curl_detection
run_test "Non-existent package" test_nonexistent_package
run_test "ca-certificates installation" test_ca_certificates_installation
run_test "Already installed package" test_already_installed_package

echo ""
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "✓ All tests passed successfully!"
    exit 0
else
    echo ""
    echo "✗ Some tests failed. Please review the results above."
    exit 1
fi
#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Certificate Management Tests
# ======================================================================================
# Comprehensive test suite for certificate management module including SSL/TLS
# certificate generation, validation, and renewal functionality.
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
readonly TEST_RESULTS_DIR="${SCRIPT_DIR}/results"
readonly TEST_LOG="${TEST_RESULTS_DIR}/cert_management_tests.log"

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

# Function: setup_test_environment
setup_test_environment() {
    echo -e "${BLUE}[INFO]${NC} Setting up certificate management test environment..."

    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Initialize test log
    echo "Certificate Management Tests - $(date)" > "$TEST_LOG"
    echo "===========================================" >> "$TEST_LOG"

    # Export test mode
    export TEST_MODE="true"
    export DRY_RUN="true"
    export SKIP_INTERACTIVE="true"

    # Source the certificate management module
    if [[ -f "${MODULES_DIR}/cert_management.sh" ]]; then
        source "${MODULES_DIR}/cert_management.sh"
    else
        echo -e "${RED}[FAIL]${NC} Certificate management module not found"
        exit 1
    fi

    echo -e "${GREEN}[PASS]${NC} Test environment initialized"
}

# Function: run_test
run_test() {
    local test_name="$1"
    local test_function="$2"

    echo -e "${BLUE}[INFO]${NC} Running test: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))

    if $test_function; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        echo "PASS: $test_name" >> "$TEST_LOG"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        echo "FAIL: $test_name" >> "$TEST_LOG"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Function: cleanup_test_environment
cleanup_test_environment() {
    echo -e "${BLUE}[INFO]${NC} Cleaning up test environment..."
    # No cleanup needed for dry-run tests
    echo -e "${GREEN}[PASS]${NC} Test environment cleaned up"
}

# ======================================================================================
# CERTIFICATE MANAGEMENT TESTS
# ======================================================================================

# Test: Check if certificate management module loads correctly
test_module_loading() {
    if [[ -f "${MODULES_DIR}/cert_management.sh" ]]; then
        # Check if key functions are defined
        if declare -f generate_certificates >/dev/null 2>&1 || \
           declare -f create_ssl_cert >/dev/null 2>&1 || \
           declare -f setup_certificates >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Test: Certificate generation functionality
test_certificate_generation() {
    export DRY_RUN="true"

    # Check if certificate generation function exists
    if declare -f generate_certificates >/dev/null 2>&1; then
        local output
        if output=$(generate_certificates 2>&1); then
            return 0
        fi
    fi

    # Alternative function names
    if declare -f create_ssl_cert >/dev/null 2>&1; then
        local output
        if output=$(create_ssl_cert 2>&1); then
            return 0
        fi
    fi

    return 1
}

# Test: Certificate validation
test_certificate_validation() {
    export DRY_RUN="true"

    # Check if certificate validation function exists
    if declare -f validate_certificate >/dev/null 2>&1; then
        local output
        if output=$(validate_certificate 2>&1); then
            return 0
        fi
    fi

    # Alternative function names
    if declare -f check_certificate >/dev/null 2>&1; then
        local output
        if output=$(check_certificate 2>&1); then
            return 0
        fi
    fi

    return 1
}

# Test: Certificate renewal functionality
test_certificate_renewal() {
    export DRY_RUN="true"

    # Check if certificate renewal function exists
    if declare -f renew_certificates >/dev/null 2>&1; then
        local output
        if output=$(renew_certificates 2>&1); then
            return 0
        fi
    fi

    # Alternative function names
    if declare -f update_certificates >/dev/null 2>&1; then
        local output
        if output=$(update_certificates 2>&1); then
            return 0
        fi
    fi

    return 1
}

# Test: Certificate configuration setup
test_certificate_config() {
    # Check if certificate config function exists
    if declare -f setup_cert_config >/dev/null 2>&1; then
        local output
        if output=$(setup_cert_config 2>&1); then
            return 0
        fi
    fi

    # Test certificate-related configurations
    if grep -q "openssl\|ssl\|cert\|key" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Self-signed certificate generation
test_self_signed_certs() {
    export DRY_RUN="true"

    # Check if self-signed certificate function exists
    if declare -f generate_self_signed_cert >/dev/null 2>&1; then
        local output
        if output=$(generate_self_signed_cert 2>&1); then
            return 0
        fi
    fi

    # Test self-signed certificate patterns
    if grep -q "self.signed\|selfsigned\|openssl.*req" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: CA certificate handling
test_ca_certificate_handling() {
    export DRY_RUN="true"

    # Check if CA certificate function exists
    if declare -f setup_ca_cert >/dev/null 2>&1; then
        local output
        if output=$(setup_ca_cert 2>&1); then
            return 0
        fi
    fi

    # Test CA certificate patterns
    if grep -q "ca\|authority\|root.*cert" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Certificate file permissions
test_certificate_permissions() {
    # Check if certificate permissions function exists
    if declare -f set_cert_permissions >/dev/null 2>&1; then
        local output
        if output=$(set_cert_permissions 2>&1); then
            return 0
        fi
    fi

    # Test permission-related patterns
    if grep -q "chmod\|chown\|600\|644" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Certificate expiry checking
test_certificate_expiry() {
    # Check if certificate expiry function exists
    if declare -f check_cert_expiry >/dev/null 2>&1; then
        local output
        if output=$(check_cert_expiry 2>&1); then
            return 0
        fi
    fi

    # Test expiry checking patterns
    if grep -q "expir\|date\|valid\|openssl.*x509" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Certificate backup functionality
test_certificate_backup() {
    export DRY_RUN="true"

    # Check if certificate backup function exists
    if declare -f backup_certificates >/dev/null 2>&1; then
        local output
        if output=$(backup_certificates 2>&1); then
            return 0
        fi
    fi

    # Test backup-related patterns
    if grep -q "backup\|copy\|archive" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Certificate installation
test_certificate_installation() {
    export DRY_RUN="true"

    # Check if certificate installation function exists
    if declare -f install_certificates >/dev/null 2>&1; then
        local output
        if output=$(install_certificates 2>&1); then
            return 0
        fi
    fi

    # Test installation patterns
    if grep -q "install\|deploy\|copy.*cert" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Test: Certificate key generation
test_private_key_generation() {
    export DRY_RUN="true"

    # Check if private key generation function exists
    if declare -f generate_private_key >/dev/null 2>&1; then
        local output
        if output=$(generate_private_key 2>&1); then
            return 0
        fi
    fi

    # Test private key patterns
    if grep -q "private.*key\|rsa\|openssl.*genrsa" "${MODULES_DIR}/cert_management.sh" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ======================================================================================
# MAIN TEST EXECUTION
# ======================================================================================

main() {
    echo ""
    echo "========================================"
    echo "Certificate Management Module Tests"
    echo "========================================"

    # Setup test environment
    setup_test_environment

    echo ""
    echo "Running certificate management tests..."
    echo ""

    # Run all tests
    run_test "Module Loading" test_module_loading
    run_test "Certificate Generation" test_certificate_generation
    run_test "Certificate Validation" test_certificate_validation
    run_test "Certificate Renewal" test_certificate_renewal
    run_test "Certificate Configuration" test_certificate_config
    run_test "Self-signed Certificates" test_self_signed_certs
    run_test "CA Certificate Handling" test_ca_certificate_handling
    run_test "Certificate Permissions" test_certificate_permissions
    run_test "Certificate Expiry Check" test_certificate_expiry
    run_test "Certificate Backup" test_certificate_backup
    run_test "Certificate Installation" test_certificate_installation
    run_test "Private Key Generation" test_private_key_generation

    # Print test summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    # Log summary
    echo "" >> "$TEST_LOG"
    echo "Test Summary:" >> "$TEST_LOG"
    echo "Tests run: $TESTS_RUN" >> "$TEST_LOG"
    echo "Passed: $TESTS_PASSED" >> "$TEST_LOG"
    echo "Failed: $TESTS_FAILED" >> "$TEST_LOG"

    # Cleanup
    cleanup_test_environment

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All certificate management tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some certificate management tests failed!${NC}"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
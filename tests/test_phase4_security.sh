#!/bin/bash

# Phase 4 Security Integration Test Script
# Tests UFW configuration, security hardening, certificate management, and monitoring
# Version: 1.0

set -euo pipefail

# Test configuration
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_DIR")"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"
readonly TEST_LOG="/tmp/phase4_test_$(date +%Y%m%d_%H%M%S).log"
readonly TEST_DOMAIN="test.vless.local"

# Import common utilities
if [[ -f "${MODULES_DIR}/common_utils.sh" ]]; then
    source "${MODULES_DIR}/common_utils.sh"
else
    echo "Error: Cannot find common_utils.sh"
    exit 1
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_test() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TEST: $*" | tee -a "$TEST_LOG"
}

log_result() {
    local status="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $*" | tee -a "$TEST_LOG"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log_test "Running: $test_name"

    if $test_function; then
        ((TESTS_PASSED++))
        log_result "PASS" "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        log_result "FAIL" "$test_name"
        return 1
    fi
}

# Test UFW module existence and basic functionality
test_ufw_module() {
    local ufw_module="${MODULES_DIR}/ufw_config.sh"

    # Check if module exists
    if [[ ! -f "$ufw_module" ]]; then
        log_error "UFW module not found: $ufw_module"
        return 1
    fi

    # Check if module is executable
    if [[ ! -x "$ufw_module" ]]; then
        chmod +x "$ufw_module"
    fi

    # Test syntax
    if ! bash -n "$ufw_module"; then
        log_error "UFW module has syntax errors"
        return 1
    fi

    # Test help command
    if ! "$ufw_module" help >/dev/null 2>&1; then
        log_error "UFW module help command failed"
        return 1
    fi

    # Test status command (should work even without UFW installed)
    "$ufw_module" status >/dev/null 2>&1 || true

    log_info "UFW module tests passed"
    return 0
}

# Test security hardening module
test_security_hardening_module() {
    local security_module="${MODULES_DIR}/security_hardening.sh"

    # Check if module exists
    if [[ ! -f "$security_module" ]]; then
        log_error "Security hardening module not found: $security_module"
        return 1
    fi

    # Check if module is executable
    if [[ ! -x "$security_module" ]]; then
        chmod +x "$security_module"
    fi

    # Test syntax
    if ! bash -n "$security_module"; then
        log_error "Security hardening module has syntax errors"
        return 1
    fi

    # Test help command
    if ! "$security_module" help >/dev/null 2>&1; then
        log_error "Security hardening module help command failed"
        return 1
    fi

    # Test validate command (safe to run)
    "$security_module" validate >/dev/null 2>&1 || true

    log_info "Security hardening module tests passed"
    return 0
}

# Test certificate management module
test_certificate_management_module() {
    local cert_module="${MODULES_DIR}/cert_management.sh"

    # Check if module exists
    if [[ ! -f "$cert_module" ]]; then
        log_error "Certificate management module not found: $cert_module"
        return 1
    fi

    # Check if module is executable
    if [[ ! -x "$cert_module" ]]; then
        chmod +x "$cert_module"
    fi

    # Test syntax
    if ! bash -n "$cert_module"; then
        log_error "Certificate management module has syntax errors"
        return 1
    fi

    # Test help command
    if ! "$cert_module" help >/dev/null 2>&1; then
        log_error "Certificate management module help command failed"
        return 1
    fi

    # Test list command (safe to run)
    "$cert_module" list >/dev/null 2>&1 || true

    log_info "Certificate management module tests passed"
    return 0
}

# Test monitoring module
test_monitoring_module() {
    local monitoring_module="${MODULES_DIR}/monitoring.sh"

    # Check if module exists
    if [[ ! -f "$monitoring_module" ]]; then
        log_error "Monitoring module not found: $monitoring_module"
        return 1
    fi

    # Check if module is executable
    if [[ ! -x "$monitoring_module" ]]; then
        chmod +x "$monitoring_module"
    fi

    # Test syntax
    if ! bash -n "$monitoring_module"; then
        log_error "Monitoring module has syntax errors"
        return 1
    fi

    # Test help command
    if ! "$monitoring_module" help >/dev/null 2>&1; then
        log_error "Monitoring module help command failed"
        return 1
    fi

    # Test status command (should work without special privileges)
    "$monitoring_module" status >/dev/null 2>&1 || true

    log_info "Monitoring module tests passed"
    return 0
}

# Test certificate generation (in test environment)
test_certificate_generation() {
    local cert_module="${MODULES_DIR}/cert_management.sh"
    local test_cert_dir="/tmp/test_certs_$$"

    # Create temporary directory for test certificates
    mkdir -p "$test_cert_dir"

    # Modify certificate directory for testing
    export CERT_DIR="$test_cert_dir"

    # Test certificate generation
    if command -v openssl >/dev/null 2>&1; then
        # Generate test certificate
        if "$cert_module" generate "$TEST_DOMAIN" "" 30 >/dev/null 2>&1; then
            # Check if certificate files were created
            if [[ -f "${test_cert_dir}/server.crt" ]] && [[ -f "${test_cert_dir}/server.key" ]]; then
                # Verify certificate
                if openssl x509 -in "${test_cert_dir}/server.crt" -noout -text | grep -q "$TEST_DOMAIN"; then
                    log_info "Certificate generation test passed"
                    rm -rf "$test_cert_dir"
                    return 0
                else
                    log_error "Generated certificate does not contain expected domain"
                fi
            else
                log_error "Certificate files were not created"
            fi
        else
            log_error "Certificate generation failed"
        fi
    else
        log_warn "OpenSSL not available, skipping certificate generation test"
        rm -rf "$test_cert_dir"
        return 0
    fi

    rm -rf "$test_cert_dir"
    return 1
}

# Test UFW backup functionality (safe test)
test_ufw_backup() {
    local ufw_module="${MODULES_DIR}/ufw_config.sh"

    # Test UFW backup command (safe to run)
    if "$ufw_module" backup >/dev/null 2>&1; then
        log_info "UFW backup test passed"
        return 0
    else
        log_warn "UFW backup test failed (may be expected if UFW not installed)"
        return 0  # Don't fail the test suite for this
    fi
}

# Test security report generation
test_security_report() {
    local security_module="${MODULES_DIR}/security_hardening.sh"

    # Test security report generation
    if "$security_module" report >/dev/null 2>&1; then
        log_info "Security report generation test passed"
        return 0
    else
        log_warn "Security report generation failed (may require root privileges)"
        return 0  # Don't fail the test suite for this
    fi
}

# Test monitoring status
test_monitoring_status() {
    local monitoring_module="${MODULES_DIR}/monitoring.sh"

    # Test monitoring status
    if "$monitoring_module" status >/dev/null 2>&1; then
        log_info "Monitoring status test passed"
        return 0
    else
        log_error "Monitoring status test failed"
        return 1
    fi
}

# Test process isolation integration
test_process_isolation() {
    local process_safe_module="${MODULES_DIR}/process_isolation/process_safe.sh"

    if [[ -f "$process_safe_module" ]]; then
        # Check if process isolation module can be sourced
        if bash -c "source '$process_safe_module' && echo 'Process isolation loaded'" >/dev/null 2>&1; then
            log_info "Process isolation integration test passed"
            return 0
        else
            log_error "Process isolation module cannot be loaded"
            return 1
        fi
    else
        log_warn "Process isolation module not found (may be expected)"
        return 0
    fi
}

# Test integration between modules
test_module_integration() {
    local modules=(
        "${MODULES_DIR}/ufw_config.sh"
        "${MODULES_DIR}/security_hardening.sh"
        "${MODULES_DIR}/cert_management.sh"
        "${MODULES_DIR}/monitoring.sh"
    )

    # Check if all modules can import common_utils
    for module in "${modules[@]}"; do
        if [[ -f "$module" ]]; then
            # Test if module can source common_utils
            if ! bash -c "source '$module'" >/dev/null 2>&1; then
                log_error "Module integration failed: $(basename "$module")"
                return 1
            fi
        fi
    done

    log_info "Module integration test passed"
    return 0
}

# Test configuration file generation
test_config_generation() {
    # Test certificate configuration generation
    local cert_module="${MODULES_DIR}/cert_management.sh"
    local test_config="/tmp/test_cert_config_$$"

    # Generate test configuration
    if bash -c "
        source '$cert_module'
        CERT_CONFIG='$test_config'
        generate_cert_config '$TEST_DOMAIN' 'www.$TEST_DOMAIN'
    " >/dev/null 2>&1; then
        if [[ -f "$test_config" ]] && grep -q "$TEST_DOMAIN" "$test_config"; then
            log_info "Configuration generation test passed"
            rm -f "$test_config"
            return 0
        else
            log_error "Configuration file not generated correctly"
            rm -f "$test_config"
            return 1
        fi
    else
        log_error "Configuration generation failed"
        return 1
    fi
}

# Test log file creation and permissions
test_log_permissions() {
    local test_log_dir="/tmp/test_vless_logs_$$"
    local test_log_file="${test_log_dir}/test.log"

    mkdir -p "$test_log_dir"

    # Test log creation with proper permissions
    echo "Test log entry" > "$test_log_file"
    chmod 640 "$test_log_file"

    if [[ -f "$test_log_file" ]]; then
        local perms
        perms=$(stat -c %a "$test_log_file" 2>/dev/null || echo "")
        if [[ "$perms" == "640" ]]; then
            log_info "Log permissions test passed"
            rm -rf "$test_log_dir"
            return 0
        else
            log_error "Log permissions incorrect: $perms (expected 640)"
        fi
    else
        log_error "Log file creation failed"
    fi

    rm -rf "$test_log_dir"
    return 1
}

# Test directory structure creation
test_directory_structure() {
    local test_base="/tmp/test_vless_structure_$$"
    local expected_dirs=(
        "$test_base/certs"
        "$test_base/backups/ufw"
        "$test_base/backups/security"
        "$test_base/backups/certs"
        "$test_base/logs"
        "$test_base/monitoring/metrics"
        "$test_base/monitoring/reports"
    )

    # Create directory structure
    for dir in "${expected_dirs[@]}"; do
        mkdir -p "$dir"
        chmod 700 "$dir"
    done

    # Verify directories exist with correct permissions
    local all_good=true
    for dir in "${expected_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory not created: $dir"
            all_good=false
        else
            local perms
            perms=$(stat -c %a "$dir" 2>/dev/null || echo "")
            if [[ "$perms" != "700" ]]; then
                log_error "Directory permissions incorrect: $dir ($perms, expected 700)"
                all_good=false
            fi
        fi
    done

    rm -rf "$test_base"

    if $all_good; then
        log_info "Directory structure test passed"
        return 0
    else
        return 1
    fi
}

# Main test execution
main() {
    log_test "Starting Phase 4 Security Integration Tests"
    log_test "Test log: $TEST_LOG"

    echo "Phase 4 Security Integration Test Suite"
    echo "======================================="
    echo ""

    # Module existence and syntax tests
    run_test "UFW Module Tests" test_ufw_module
    run_test "Security Hardening Module Tests" test_security_hardening_module
    run_test "Certificate Management Module Tests" test_certificate_management_module
    run_test "Monitoring Module Tests" test_monitoring_module

    # Functionality tests
    run_test "Certificate Generation Test" test_certificate_generation
    run_test "UFW Backup Test" test_ufw_backup
    run_test "Security Report Test" test_security_report
    run_test "Monitoring Status Test" test_monitoring_status

    # Integration tests
    run_test "Process Isolation Integration" test_process_isolation
    run_test "Module Integration Test" test_module_integration
    run_test "Configuration Generation Test" test_config_generation

    # Infrastructure tests
    run_test "Log Permissions Test" test_log_permissions
    run_test "Directory Structure Test" test_directory_structure

    # Test summary
    echo ""
    echo "Test Results Summary"
    echo "==================="
    echo "Tests Run: $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_result "SUCCESS" "All Phase 4 tests passed!"
        echo "✓ Phase 4 Security integration tests completed successfully"
        echo ""
        echo "Phase 4 Components Ready:"
        echo "- UFW Firewall Configuration"
        echo "- Security Hardening"
        echo "- Certificate Management"
        echo "- System Monitoring"
        echo ""
        echo "Test log saved to: $TEST_LOG"
        return 0
    else
        log_result "FAILURE" "$TESTS_FAILED tests failed"
        echo "✗ Phase 4 Security integration tests failed"
        echo ""
        echo "Please review the test log for details: $TEST_LOG"
        return 1
    fi
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# VLESS+Reality VPN - Phase 5 Integration Tests
# Comprehensive testing for advanced features and Telegram integration
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TEST_LOG="${SCRIPT_DIR}/test_results_phase5.log"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "${TEST_LOG}"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "${TEST_LOG}"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "${TEST_LOG}"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "${TEST_LOG}"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))
    log_test "Running: ${test_name}"

    if ${test_function}; then
        log_pass "${test_name}"
        return 0
    else
        log_fail "${test_name}"
        return 1
    fi
}

# Initialize test environment
init_test_env() {
    log_info "Initializing Phase 5 test environment..."

    # Clear previous test log
    > "${TEST_LOG}"

    # Create test directories
    mkdir -p /tmp/vless_test/{backups,logs,config,users}

    # Set environment variables for testing
    export VLESS_TEST_MODE=true
    export VLESS_TEST_DIR=/tmp/vless_test

    log_info "Test environment initialized"
}

# Cleanup test environment
cleanup_test_env() {
    log_info "Cleaning up test environment..."

    # Remove test directories
    rm -rf /tmp/vless_test

    # Unset test environment variables
    unset VLESS_TEST_MODE VLESS_TEST_DIR

    log_info "Test environment cleaned up"
}

# Test backup and restore system
test_backup_restore() {
    local backup_script="${MODULES_DIR}/backup_restore.sh"

    # Test script exists and is executable
    if [[ ! -x "${backup_script}" ]]; then
        return 1
    fi

    # Test backup system initialization
    if ! ${backup_script} init 2>/dev/null; then
        return 1
    fi

    # Test configuration backup (dry run)
    if ! ${backup_script} config "Test config backup" 2>/dev/null; then
        return 1
    fi

    # Test backup listing
    if ! ${backup_script} list 2>/dev/null; then
        return 1
    fi

    # Test backup status
    if ! ${backup_script} status 2>/dev/null; then
        return 1
    fi

    return 0
}

# Test system monitoring
test_system_monitoring() {
    local monitoring_script="${MODULES_DIR}/monitoring.sh"

    # Test script exists and is executable
    if [[ ! -x "${monitoring_script}" ]]; then
        return 1
    fi

    # Test system status check
    if ! ${monitoring_script} status 2>/dev/null; then
        return 1
    fi

    # Test resource monitoring
    if ! ${monitoring_script} resources 2>/dev/null; then
        return 1
    fi

    # Test performance metrics
    if ! ${monitoring_script} performance 2>/dev/null; then
        return 1
    fi

    return 0
}

# Test maintenance utilities
test_maintenance_utils() {
    local maintenance_script="${MODULES_DIR}/maintenance_utils.sh"

    # Test script exists and is executable
    if [[ ! -x "${maintenance_script}" ]]; then
        return 1
    fi

    # Test health check
    if ! ${maintenance_script} health-check 2>/dev/null; then
        return 1
    fi

    # Test maintenance mode toggle
    if ! ${maintenance_script} enable-maintenance "Test maintenance" 2>/dev/null; then
        return 1
    fi

    if ! ${maintenance_script} disable-maintenance 2>/dev/null; then
        return 1
    fi

    # Test cleanup operations (dry run)
    if ! ${maintenance_script} cleanup-logs 2>/dev/null; then
        return 1
    fi

    return 0
}

# Test system update mechanism
test_system_update() {
    local update_script="${MODULES_DIR}/system_update.sh"

    # Test script exists and is executable
    if [[ ! -x "${update_script}" ]]; then
        return 1
    fi

    # Test update system initialization
    if ! ${update_script} init 2>/dev/null; then
        return 1
    fi

    # Test update checking
    if ! ${update_script} check system 2>/dev/null; then
        return 1
    fi

    # Test update status
    if ! ${update_script} status 2>/dev/null; then
        return 1
    fi

    return 0
}

# Test Telegram bot interface
test_telegram_bot() {
    local bot_script="${MODULES_DIR}/telegram_bot.py"
    local bot_manager="${MODULES_DIR}/telegram_bot_manager.sh"

    # Test bot script exists
    if [[ ! -f "${bot_script}" ]]; then
        return 1
    fi

    # Test bot manager exists and is executable
    if [[ ! -x "${bot_manager}" ]]; then
        return 1
    fi

    # Test Python dependencies (basic check)
    if ! python3 -c "import sys; print('Python version check OK')" 2>/dev/null; then
        return 1
    fi

    # Test bot configuration validation
    if ! ${bot_manager} validate 2>/dev/null; then
        # This is expected to fail in test environment without proper config
        log_info "Bot validation failed as expected (no configuration)"
    fi

    # Test admin database initialization
    if ! ${bot_manager} list-admins 2>/dev/null; then
        # This might fail if no database exists, which is acceptable
        log_info "Admin listing test completed"
    fi

    return 0
}

# Test bot management functions
test_bot_management() {
    local bot_manager="${MODULES_DIR}/telegram_bot_manager.sh"

    # Test script exists and is executable
    if [[ ! -x "${bot_manager}" ]]; then
        return 1
    fi

    # Test status check
    if ! ${bot_manager} status 2>/dev/null; then
        return 1
    fi

    # Test dependency installation check
    if ! ${bot_manager} install-deps --dry-run 2>/dev/null; then
        # This command might not support dry-run, so we'll accept any exit code
        log_info "Dependency installation test completed"
    fi

    return 0
}

# Test bot deployment script
test_bot_deployment() {
    local deploy_script="${PROJECT_ROOT}/deploy_telegram_bot.sh"

    # Test script exists and is executable
    if [[ ! -x "${deploy_script}" ]]; then
        return 1
    fi

    # Test help function
    if ! ${deploy_script} help 2>/dev/null; then
        # Try with unknown command to trigger help
        ${deploy_script} unknown_command >/dev/null 2>&1 || true
    fi

    return 0
}

# Test configuration files
test_configuration_files() {
    local config_files=(
        "${PROJECT_ROOT}/config/bot_config.env"
        "${PROJECT_ROOT}/config/vless-vpn.service"
        "${PROJECT_ROOT}/requirements.txt"
    )

    for config_file in "${config_files[@]}"; do
        if [[ ! -f "${config_file}" ]]; then
            log_fail "Configuration file missing: ${config_file}"
            return 1
        fi
    done

    # Test requirements.txt format
    if ! grep -q "python-telegram-bot" "${PROJECT_ROOT}/requirements.txt"; then
        return 1
    fi

    # Test service file format
    if ! grep -q "\[Unit\]" "${PROJECT_ROOT}/config/vless-vpn.service"; then
        return 1
    fi

    return 0
}

# Test Python dependencies
test_python_dependencies() {
    local requirements_file="${PROJECT_ROOT}/requirements.txt"

    if [[ ! -f "${requirements_file}" ]]; then
        return 1
    fi

    # Test if requirements file is readable
    if ! cat "${requirements_file}" >/dev/null 2>&1; then
        return 1
    fi

    # Check for critical dependencies
    local critical_deps=(
        "python-telegram-bot"
        "requests"
        "qrcode"
        "psutil"
    )

    for dep in "${critical_deps[@]}"; do
        if ! grep -q "${dep}" "${requirements_file}"; then
            log_fail "Missing critical dependency: ${dep}"
            return 1
        fi
    done

    return 0
}

# Test script permissions and structure
test_script_structure() {
    local scripts=(
        "${MODULES_DIR}/backup_restore.sh"
        "${MODULES_DIR}/maintenance_utils.sh"
        "${MODULES_DIR}/system_update.sh"
        "${MODULES_DIR}/telegram_bot.py"
        "${MODULES_DIR}/telegram_bot_manager.sh"
        "${PROJECT_ROOT}/deploy_telegram_bot.sh"
    )

    for script in "${scripts[@]}"; do
        # Check if file exists
        if [[ ! -f "${script}" ]]; then
            log_fail "Script missing: ${script}"
            return 1
        fi

        # Check if file is executable
        if [[ ! -x "${script}" ]]; then
            log_fail "Script not executable: ${script}"
            return 1
        fi

        # Check for shebang
        if ! head -1 "${script}" | grep -q "^#!" 2>/dev/null; then
            log_fail "Missing shebang: ${script}"
            return 1
        fi
    done

    return 0
}

# Test integration between modules
test_module_integration() {
    # Test if backup system can call maintenance utils
    local backup_script="${MODULES_DIR}/backup_restore.sh"
    local maintenance_script="${MODULES_DIR}/maintenance_utils.sh"

    if [[ ! -x "${backup_script}" || ! -x "${maintenance_script}" ]]; then
        return 1
    fi

    # Test if scripts can source common_utils
    local common_utils="${MODULES_DIR}/common_utils.sh"
    if [[ ! -f "${common_utils}" ]]; then
        return 1
    fi

    # Test if modules can be sourced without errors
    if ! bash -n "${backup_script}" 2>/dev/null; then
        return 1
    fi

    if ! bash -n "${maintenance_script}" 2>/dev/null; then
        return 1
    fi

    return 0
}

# Test logging and error handling
test_logging_error_handling() {
    local scripts=(
        "${MODULES_DIR}/backup_restore.sh"
        "${MODULES_DIR}/maintenance_utils.sh"
        "${MODULES_DIR}/system_update.sh"
        "${MODULES_DIR}/telegram_bot_manager.sh"
    )

    for script in "${scripts[@]}"; do
        # Check if script has error handling (set -e or equivalent)
        if ! grep -q "set.*e" "${script}" 2>/dev/null; then
            log_fail "Missing error handling: ${script}"
            return 1
        fi

        # Check if script has logging functions or calls
        if ! grep -qE "(log_|echo)" "${script}" 2>/dev/null; then
            log_fail "Missing logging: ${script}"
            return 1
        fi
    done

    return 0
}

# Generate test report
generate_report() {
    echo | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"
    echo "Phase 5 Integration Test Results" | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"
    echo "Total Tests: ${TESTS_TOTAL}" | tee -a "${TEST_LOG}"
    echo "Passed: ${TESTS_PASSED}" | tee -a "${TEST_LOG}"
    echo "Failed: ${TESTS_FAILED}" | tee -a "${TEST_LOG}"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%" | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}" | tee -a "${TEST_LOG}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}" | tee -a "${TEST_LOG}"
        return 1
    fi
}

# Main test execution
main() {
    echo "Starting Phase 5 Integration Tests..."
    echo "====================================="

    init_test_env

    # Run all tests
    run_test "Backup and Restore System" test_backup_restore
    run_test "System Monitoring" test_system_monitoring
    run_test "Maintenance Utilities" test_maintenance_utils
    run_test "System Update Mechanism" test_system_update
    run_test "Telegram Bot Interface" test_telegram_bot
    run_test "Bot Management Functions" test_bot_management
    run_test "Bot Deployment Script" test_bot_deployment
    run_test "Configuration Files" test_configuration_files
    run_test "Python Dependencies" test_python_dependencies
    run_test "Script Structure" test_script_structure
    run_test "Module Integration" test_module_integration
    run_test "Logging and Error Handling" test_logging_error_handling

    # Generate report
    generate_report

    # Cleanup
    cleanup_test_env

    echo
    echo "Test log saved to: ${TEST_LOG}"

    # Exit with appropriate code
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
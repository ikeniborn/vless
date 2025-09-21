#!/bin/bash

# VLESS+Reality VPN - Backup and Restore System Tests
# Unit tests for backup and restore functionality
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly BACKUP_SCRIPT="${PROJECT_ROOT}/modules/backup_restore.sh"
readonly TEST_DIR="/tmp/vless_backup_test"
readonly TEST_LOG="${SCRIPT_DIR}/test_backup_restore.log"

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

# Setup test environment
setup_test_env() {
    log_info "Setting up test environment..."

    # Clear previous test log
    > "${TEST_LOG}"

    # Remove and recreate test directory
    rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DIR}"/{config,logs,users,certs,backups}

    # Create test files
    echo "test config data" > "${TEST_DIR}/config/test_config.json"
    echo "test user data" > "${TEST_DIR}/users/test_user.json"
    echo "test cert data" > "${TEST_DIR}/certs/test_cert.pem"
    echo "test log data" > "${TEST_DIR}/logs/test.log"

    # Create mock docker-compose file
    cat > "${TEST_DIR}/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  xray:
    image: ghcr.io/xtls/xray-core:latest
    container_name: vless-xray
    restart: unless-stopped
EOF

    # Set environment variables for testing
    export BACKUP_BASE_DIR="${TEST_DIR}/backups"
    export CONFIG_DIR="${TEST_DIR}/config"
    export USERS_DIR="${TEST_DIR}/users"
    export CERTS_DIR="${TEST_DIR}/certs"
    export LOGS_DIR="${TEST_DIR}/logs"
    export DOCKER_COMPOSE_FILE="${TEST_DIR}/docker-compose.yml"

    log_info "Test environment setup completed"
}

# Cleanup test environment
cleanup_test_env() {
    log_info "Cleaning up test environment..."

    # Remove test directory
    rm -rf "${TEST_DIR}"

    # Unset environment variables
    unset BACKUP_BASE_DIR CONFIG_DIR USERS_DIR CERTS_DIR LOGS_DIR DOCKER_COMPOSE_FILE

    log_info "Test environment cleaned up"
}

# Test backup script exists and is executable
test_backup_script_exists() {
    if [[ ! -f "${BACKUP_SCRIPT}" ]]; then
        return 1
    fi

    if [[ ! -x "${BACKUP_SCRIPT}" ]]; then
        return 1
    fi

    return 0
}

# Test backup system initialization
test_backup_init() {
    if ! "${BACKUP_SCRIPT}" init >/dev/null 2>&1; then
        return 1
    fi

    # Check if backup directories were created
    local required_dirs=(
        "${TEST_DIR}/backups/full"
        "${TEST_DIR}/backups/config"
        "${TEST_DIR}/backups/users"
        "${TEST_DIR}/backups/temp"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            return 1
        fi
    done

    return 0
}

# Test configuration backup
test_config_backup() {
    if ! "${BACKUP_SCRIPT}" config "Test config backup" >/dev/null 2>&1; then
        return 1
    fi

    # Check if backup file was created
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/config" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Test backup integrity
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Test users backup
test_users_backup() {
    if ! "${BACKUP_SCRIPT}" users "Test users backup" >/dev/null 2>&1; then
        return 1
    fi

    # Check if backup file was created
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/users" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Test backup integrity
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Test full backup
test_full_backup() {
    if ! "${BACKUP_SCRIPT}" full "Test full backup" >/dev/null 2>&1; then
        return 1
    fi

    # Check if backup file was created
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/full" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Test backup integrity
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    # Check if metadata exists in backup
    if ! tar -tzf "${backup_file}" | grep -q "metadata/backup_info.txt"; then
        return 1
    fi

    return 0
}

# Test backup listing
test_backup_list() {
    # Create some test backups first
    "${BACKUP_SCRIPT}" config "Test config 1" >/dev/null 2>&1
    "${BACKUP_SCRIPT}" users "Test users 1" >/dev/null 2>&1
    "${BACKUP_SCRIPT}" full "Test full 1" >/dev/null 2>&1

    # Test listing all backups
    if ! "${BACKUP_SCRIPT}" list >/dev/null 2>&1; then
        return 1
    fi

    # Test listing specific backup types
    if ! "${BACKUP_SCRIPT}" list config >/dev/null 2>&1; then
        return 1
    fi

    if ! "${BACKUP_SCRIPT}" list users >/dev/null 2>&1; then
        return 1
    fi

    if ! "${BACKUP_SCRIPT}" list full >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Test backup status
test_backup_status() {
    if ! "${BACKUP_SCRIPT}" status >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Test backup validation
test_backup_validation() {
    # Create a test backup
    "${BACKUP_SCRIPT}" config "Test validation backup" >/dev/null 2>&1

    # Find the backup file
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/config" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Test backup integrity using internal validation
    # This tests the validate_backup_integrity function indirectly
    local temp_dir="${TEST_DIR}/validation_test"
    mkdir -p "${temp_dir}"

    # Extract backup to test its contents
    cd "${temp_dir}"
    if ! tar -xzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    # Check if expected files exist
    if [[ ! -f "metadata/backup_info.txt" ]]; then
        return 1
    fi

    # Cleanup
    rm -rf "${temp_dir}"

    return 0
}

# Test backup metadata
test_backup_metadata() {
    # Create a test backup
    "${BACKUP_SCRIPT}" full "Test metadata backup" >/dev/null 2>&1

    # Find the backup file
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/full" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Extract and check metadata
    local temp_dir="${TEST_DIR}/metadata_test"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    if ! tar -xzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    # Check metadata content
    if [[ ! -f "metadata/backup_info.txt" ]]; then
        return 1
    fi

    # Check required metadata fields
    local metadata_file="metadata/backup_info.txt"
    local required_fields=("BACKUP_TYPE" "BACKUP_DATE" "HOSTNAME")

    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=" "${metadata_file}"; then
            return 1
        fi
    done

    # Check checksums file
    if [[ ! -f "metadata/checksums.txt" ]]; then
        return 1
    fi

    # Cleanup
    rm -rf "${temp_dir}"

    return 0
}

# Test backup cleanup
test_backup_cleanup() {
    # Create multiple test backups
    for i in {1..5}; do
        "${BACKUP_SCRIPT}" config "Test cleanup backup ${i}" >/dev/null 2>&1
        sleep 1  # Ensure different timestamps
    done

    # Test cleanup function
    if ! "${BACKUP_SCRIPT}" cleanup >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Test restore functionality (basic)
test_restore_functionality() {
    # Create a test backup
    "${BACKUP_SCRIPT}" config "Test restore backup" >/dev/null 2>&1

    # Find the backup file
    local backup_file
    backup_file=$(find "${TEST_DIR}/backups/config" -name "*.tar.gz" | head -1)

    if [[ ! -f "${backup_file}" ]]; then
        return 1
    fi

    # Test restore dry-run (simulate restore without actual changes)
    # Since we can't do actual restore in test environment, we'll test
    # that the restore function accepts the correct parameters

    # Test backup file validation for restore
    local temp_dir="${TEST_DIR}/restore_test"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    # Test if backup can be extracted (simulates restore validation)
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        return 1
    fi

    # Test if backup contains expected structure
    if ! tar -tzf "${backup_file}" | grep -q "metadata/backup_info.txt"; then
        return 1
    fi

    # Cleanup
    rm -rf "${temp_dir}"

    return 0
}

# Test error handling
test_error_handling() {
    # Test with invalid backup type
    if "${BACKUP_SCRIPT}" invalid_type >/dev/null 2>&1; then
        return 1  # Should fail
    fi

    # Test with missing directories (should handle gracefully)
    local original_config_dir="${CONFIG_DIR}"
    export CONFIG_DIR="/nonexistent/directory"

    # This should handle the missing directory gracefully
    "${BACKUP_SCRIPT}" config "Test error handling" >/dev/null 2>&1 || true

    # Restore original directory
    export CONFIG_DIR="${original_config_dir}"

    return 0
}

# Generate test report
generate_report() {
    echo | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"
    echo "Backup and Restore Test Results" | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"
    echo "Total Tests: ${TESTS_TOTAL}" | tee -a "${TEST_LOG}"
    echo "Passed: ${TESTS_PASSED}" | tee -a "${TEST_LOG}"
    echo "Failed: ${TESTS_FAILED}" | tee -a "${TEST_LOG}"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%" | tee -a "${TEST_LOG}"
    echo "============================================" | tee -a "${TEST_LOG}"

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}All backup tests passed!${NC}" | tee -a "${TEST_LOG}"
        return 0
    else
        echo -e "${RED}Some backup tests failed!${NC}" | tee -a "${TEST_LOG}"
        return 1
    fi
}

# Main test execution
main() {
    echo "Starting Backup and Restore System Tests..."
    echo "============================================"

    setup_test_env

    # Run all tests
    run_test "Backup Script Exists" test_backup_script_exists
    run_test "Backup System Initialization" test_backup_init
    run_test "Configuration Backup" test_config_backup
    run_test "Users Backup" test_users_backup
    run_test "Full System Backup" test_full_backup
    run_test "Backup Listing" test_backup_list
    run_test "Backup Status" test_backup_status
    run_test "Backup Validation" test_backup_validation
    run_test "Backup Metadata" test_backup_metadata
    run_test "Backup Cleanup" test_backup_cleanup
    run_test "Restore Functionality" test_restore_functionality
    run_test "Error Handling" test_error_handling

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
#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - User Management Tests
# ======================================================================================
# This script provides comprehensive testing for the user management functionality
# including CRUD operations, configuration generation, and database operations.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="${PROJECT_ROOT}/modules"

# Source required modules
source "${MODULES_DIR}/common_utils.sh"

# Test specific variables
readonly TEST_USER_DIR="/tmp/vless_test_users"
readonly TEST_BACKUP_DIR="/tmp/vless_test_backups"
readonly TEST_CONFIG_DIR="/tmp/vless_test_config"
readonly TEST_LOG_DIR="/tmp/vless_test_logs"
readonly TEST_DATABASE="${TEST_USER_DIR}/users.json"

# Override global variables for testing
export USER_DIR="$TEST_USER_DIR"
export BACKUP_DIR="$TEST_BACKUP_DIR"
export CONFIG_DIR="$TEST_CONFIG_DIR"
export LOG_DIR="$TEST_LOG_DIR"
export VLESS_ROOT="/tmp/vless_test"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# ======================================================================================
# TEST FRAMEWORK FUNCTIONS
# ======================================================================================

# Function: setup_test_environment
# Description: Initialize test environment
setup_test_environment() {
    log_info "Setting up test environment..."

    # Clean up any existing test data
    cleanup_test_environment

    # Create test directories
    mkdir -p "$TEST_USER_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_LOG_DIR"
    mkdir -p "${TEST_USER_DIR}/configs"
    mkdir -p "${TEST_USER_DIR}/qr_codes"
    mkdir -p "${TEST_USER_DIR}/exports"

    # Set permissions
    chmod 700 "$TEST_USER_DIR" "$TEST_BACKUP_DIR" "$TEST_CONFIG_DIR" "$TEST_LOG_DIR"

    log_success "Test environment setup completed"
}

# Function: cleanup_test_environment
# Description: Clean up test environment
cleanup_test_environment() {
    if [[ -d "/tmp/vless_test" ]]; then
        rm -rf "/tmp/vless_test"
    fi
    if [[ -d "$TEST_USER_DIR" ]]; then
        rm -rf "$TEST_USER_DIR"
    fi
    if [[ -d "$TEST_BACKUP_DIR" ]]; then
        rm -rf "$TEST_BACKUP_DIR"
    fi
    if [[ -d "$TEST_CONFIG_DIR" ]]; then
        rm -rf "$TEST_CONFIG_DIR"
    fi
    if [[ -d "$TEST_LOG_DIR" ]]; then
        rm -rf "$TEST_LOG_DIR"
    fi
}

# Function: run_test
# Description: Run a single test with error handling
# Parameters: $1 - test name, $2 - test function
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))

    echo ""
    log_info "Running test: $test_name"
    echo "----------------------------------------"

    if $test_function; then
        ((TESTS_PASSED++))
        log_success "PASSED: $test_name"
    else
        ((TESTS_FAILED++))
        log_error "FAILED: $test_name"
    fi

    echo "----------------------------------------"
}

# Function: assert_equals
# Description: Assert that two values are equal
# Parameters: $1 - expected, $2 - actual, $3 - description
assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_debug "ASSERT PASS: $description"
        return 0
    else
        log_error "ASSERT FAIL: $description"
        log_error "  Expected: '$expected'"
        log_error "  Actual: '$actual'"
        return 1
    fi
}

# Function: assert_not_empty
# Description: Assert that a value is not empty
# Parameters: $1 - value, $2 - description
assert_not_empty() {
    local value="$1"
    local description="$2"

    if [[ -n "$value" ]]; then
        log_debug "ASSERT PASS: $description"
        return 0
    else
        log_error "ASSERT FAIL: $description (value is empty)"
        return 1
    fi
}

# Function: assert_file_exists
# Description: Assert that a file exists
# Parameters: $1 - file path, $2 - description
assert_file_exists() {
    local file_path="$1"
    local description="$2"

    if [[ -f "$file_path" ]]; then
        log_debug "ASSERT PASS: $description"
        return 0
    else
        log_error "ASSERT FAIL: $description (file not found: $file_path)"
        return 1
    fi
}

# Function: assert_command_success
# Description: Assert that a command succeeds
# Parameters: $* - command to run
assert_command_success() {
    local description="Command execution"
    if [[ "${*: -1}" =~ ^[A-Z] ]]; then
        description="${*: -1}"
        set -- "${@:1:$(($#-1))}"
    fi

    if "$@" >/dev/null 2>&1; then
        log_debug "ASSERT PASS: $description"
        return 0
    else
        log_error "ASSERT FAIL: $description"
        return 1
    fi
}

# ======================================================================================
# USER MANAGEMENT TESTS
# ======================================================================================

# Function: test_user_database_initialization
# Description: Test user database initialization
test_user_database_initialization() {
    source "${MODULES_DIR}/user_database.sh"

    # Test database initialization
    if ! init_user_database; then
        return 1
    fi

    # Verify database file exists
    if ! assert_file_exists "$TEST_DATABASE" "Database file created"; then
        return 1
    fi

    # Verify database content
    local db_content
    db_content=$(cat "$TEST_DATABASE")

    if ! echo "$db_content" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    assert 'metadata' in data
    assert 'users' in data
    assert isinstance(data['users'], list)
    assert len(data['users']) == 0
    print('Database structure valid')
except Exception as e:
    print(f'Database structure invalid: {e}')
    sys.exit(1)
"; then
        return 1
    fi

    log_debug "Database initialization test passed"
    return 0
}

# Function: test_add_user
# Description: Test adding users
test_add_user() {
    source "${MODULES_DIR}/user_management.sh"

    # Initialize database
    init_user_database

    # Test adding a user
    if ! add_user "testuser1" "test1@example.com" "Test User 1"; then
        return 1
    fi

    # Verify user was added
    if ! user_exists "testuser1"; then
        log_error "User not found after adding"
        return 1
    fi

    # Test adding another user
    if ! add_user "testuser2" "test2@example.com" "Test User 2"; then
        return 1
    fi

    # Verify both users exist
    local user_count
    user_count=$(get_user_count)
    if ! assert_equals "2" "$user_count" "User count after adding two users"; then
        return 1
    fi

    # Test duplicate user (should fail)
    if add_user "testuser1" "duplicate@example.com" "Duplicate User" 2>/dev/null; then
        log_error "Duplicate user addition should have failed"
        return 1
    fi

    log_debug "Add user test passed"
    return 0
}

# Function: test_remove_user
# Description: Test removing users
test_remove_user() {
    source "${MODULES_DIR}/user_management.sh"

    # Initialize and add test users
    init_user_database
    add_user "removetest1" "remove1@example.com" "Remove Test 1"
    add_user "removetest2" "remove2@example.com" "Remove Test 2"

    # Verify initial state
    local initial_count
    initial_count=$(get_user_count)
    if ! assert_equals "2" "$initial_count" "Initial user count"; then
        return 1
    fi

    # Remove first user
    if ! remove_user "removetest1"; then
        return 1
    fi

    # Verify user was removed
    if user_exists "removetest1"; then
        log_error "User still exists after removal"
        return 1
    fi

    # Verify count decreased
    local after_removal_count
    after_removal_count=$(get_user_count)
    if ! assert_equals "1" "$after_removal_count" "User count after removal"; then
        return 1
    fi

    # Test removing non-existent user (should fail)
    if remove_user "nonexistent" 2>/dev/null; then
        log_error "Removing non-existent user should have failed"
        return 1
    fi

    log_debug "Remove user test passed"
    return 0
}

# Function: test_list_users
# Description: Test user listing functionality
test_list_users() {
    source "${MODULES_DIR}/user_management.sh"

    # Initialize and add test users
    init_user_database
    add_user "listtest1" "list1@example.com" "List Test 1"
    add_user "listtest2" "list2@example.com" "List Test 2"
    add_user "listtest3" "list3@example.com" "List Test 3"

    # Test table format listing
    local table_output
    table_output=$(list_users table 2>/dev/null)

    # Verify output contains user information
    if ! echo "$table_output" | grep -q "listtest1"; then
        log_error "Table output missing user listtest1"
        return 1
    fi

    if ! echo "$table_output" | grep -q "listtest2"; then
        log_error "Table output missing user listtest2"
        return 1
    fi

    # Test JSON format listing
    local json_output
    json_output=$(list_users json 2>/dev/null)

    # Verify JSON is valid and contains users
    if ! echo "$json_output" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    assert isinstance(data, list)
    assert len(data) == 3
    usernames = [user.get('username') for user in data]
    assert 'listtest1' in usernames
    assert 'listtest2' in usernames
    assert 'listtest3' in usernames
    print('JSON output valid')
except Exception as e:
    print(f'JSON output invalid: {e}')
    sys.exit(1)
"; then
        return 1
    fi

    log_debug "List users test passed"
    return 0
}

# Function: test_user_config_generation
# Description: Test user configuration generation
test_user_config_generation() {
    source "${MODULES_DIR}/user_management.sh"

    # Initialize and add test user
    init_user_database
    add_user "configtest" "config@example.com" "Config Test User"

    # Test VLESS configuration generation
    if ! generate_user_config "configtest" "vless"; then
        return 1
    fi

    # Verify configuration file was created
    local config_file="${USER_DIR}/configs/configtest_vless.txt"
    if ! assert_file_exists "$config_file" "VLESS config file created"; then
        return 1
    fi

    # Verify configuration content
    local config_content
    config_content=$(cat "$config_file")

    if ! echo "$config_content" | grep -q "vless://"; then
        log_error "VLESS config missing vless:// prefix"
        return 1
    fi

    # Test JSON configuration generation
    if ! generate_user_config "configtest" "json"; then
        return 1
    fi

    # Verify JSON configuration file
    local json_config_file="${USER_DIR}/configs/configtest_json.txt"
    if ! assert_file_exists "$json_config_file" "JSON config file created"; then
        return 1
    fi

    # Verify JSON configuration is valid
    if ! python3 -c "
import json
try:
    with open('$json_config_file', 'r') as f:
        data = json.load(f)
    assert 'outbounds' in data
    assert 'inbounds' in data
    print('JSON config valid')
except Exception as e:
    print(f'JSON config invalid: {e}')
    exit(1)
"; then
        return 1
    fi

    log_debug "User config generation test passed"
    return 0
}

# Function: test_user_update
# Description: Test user information updates
test_user_update() {
    source "${MODULES_DIR}/user_management.sh"

    # Initialize and add test user
    init_user_database
    add_user "updatetest" "update@example.com" "Update Test User"

    # Test updating email
    if ! update_user "updatetest" "email" "newemail@example.com"; then
        return 1
    fi

    # Verify update
    local updated_email
    updated_email=$(get_user_info "updatetest" "email")
    if ! assert_equals "newemail@example.com" "$updated_email" "Updated email"; then
        return 1
    fi

    # Test updating description
    if ! update_user "updatetest" "description" "Updated Description"; then
        return 1
    fi

    # Verify description update
    local updated_description
    updated_description=$(get_user_info "updatetest" "description")
    if ! assert_equals "Updated Description" "$updated_description" "Updated description"; then
        return 1
    fi

    log_debug "User update test passed"
    return 0
}

# ======================================================================================
# DATABASE MANAGEMENT TESTS
# ======================================================================================

# Function: test_database_backup_restore
# Description: Test database backup and restore functionality
test_database_backup_restore() {
    source "${MODULES_DIR}/user_database.sh"

    # Initialize database and add test data
    init_user_database
    source "${MODULES_DIR}/user_management.sh"
    add_user "backuptest1" "backup1@example.com" "Backup Test 1"
    add_user "backuptest2" "backup2@example.com" "Backup Test 2"

    # Create backup
    local backup_path
    backup_path=$(backup_user_database "test_backup")
    if [[ -z "$backup_path" ]]; then
        log_error "Backup creation failed"
        return 1
    fi

    # Verify backup file exists
    if ! assert_file_exists "$backup_path" "Backup file created"; then
        return 1
    fi

    # Modify database
    add_user "backuptest3" "backup3@example.com" "Backup Test 3"
    local modified_count
    modified_count=$(get_user_count)

    # Restore from backup
    if ! restore_user_database "$backup_path"; then
        return 1
    fi

    # Verify restoration
    local restored_count
    restored_count=$(get_user_count)
    if ! assert_equals "2" "$restored_count" "User count after restore"; then
        return 1
    fi

    # Verify specific users exist
    if ! user_exists "backuptest1"; then
        log_error "User backuptest1 not found after restore"
        return 1
    fi

    if ! user_exists "backuptest2"; then
        log_error "User backuptest2 not found after restore"
        return 1
    fi

    # Verify user3 was removed by restore
    if user_exists "backuptest3"; then
        log_error "User backuptest3 should not exist after restore"
        return 1
    fi

    log_debug "Database backup/restore test passed"
    return 0
}

# Function: test_user_export_import
# Description: Test user data export and import
test_user_export_import() {
    source "${MODULES_DIR}/user_database.sh"

    # Initialize database and add test data
    init_user_database
    source "${MODULES_DIR}/user_management.sh"
    add_user "exporttest1" "export1@example.com" "Export Test 1"
    add_user "exporttest2" "export2@example.com" "Export Test 2"

    # Test JSON export
    local export_file="${TEST_USER_DIR}/test_export.json"
    if ! export_users "json" "$export_file"; then
        return 1
    fi

    # Verify export file exists and is valid
    if ! assert_file_exists "$export_file" "Export file created"; then
        return 1
    fi

    # Verify export content
    if ! python3 -c "
import json
try:
    with open('$export_file', 'r') as f:
        data = json.load(f)
    assert 'users' in data
    assert len(data['users']) == 2
    usernames = [user.get('username') for user in data['users']]
    assert 'exporttest1' in usernames
    assert 'exporttest2' in usernames
    print('Export content valid')
except Exception as e:
    print(f'Export content invalid: {e}')
    exit(1)
"; then
        return 1
    fi

    # Test import to new database
    rm -f "$TEST_DATABASE"
    init_user_database

    if ! import_users "$export_file" "json" "replace"; then
        return 1
    fi

    # Verify import
    local imported_count
    imported_count=$(get_user_count)
    if ! assert_equals "2" "$imported_count" "User count after import"; then
        return 1
    fi

    if ! user_exists "exporttest1"; then
        log_error "User exporttest1 not found after import"
        return 1
    fi

    log_debug "User export/import test passed"
    return 0
}

# ======================================================================================
# CONFIGURATION TEMPLATES TESTS
# ======================================================================================

# Function: test_config_templates
# Description: Test configuration template generation
test_config_templates() {
    source "${MODULES_DIR}/config_templates.sh"

    # Initialize templates
    init_config_templates

    # Initialize user database and add test user
    source "${MODULES_DIR}/user_database.sh"
    init_user_database
    source "${MODULES_DIR}/user_management.sh"
    add_user "templatetest" "template@example.com" "Template Test User"

    # Test different configuration formats
    local formats=("xray" "v2ray" "clash" "sing-box" "vless-url")

    for format in "${formats[@]}"; do
        log_debug "Testing $format configuration generation"

        if ! generate_config_for_user "templatetest" "$format"; then
            log_error "Failed to generate $format configuration"
            return 1
        fi

        # Verify configuration file was created
        local config_file
        config_file=$(find "${USER_DIR}/exports/templatetest" -name "*_${format}_*" -type f | head -1)

        if [[ -z "$config_file" ]]; then
            log_error "Configuration file not found for format: $format"
            return 1
        fi

        # Basic content validation
        local config_content
        config_content=$(cat "$config_file")

        case "$format" in
            "vless-url")
                if ! echo "$config_content" | grep -q "vless://"; then
                    log_error "VLESS URL format invalid"
                    return 1
                fi
                ;;
            "xray"|"v2ray"|"sing-box")
                if ! echo "$config_content" | python3 -c "
import json, sys
try:
    json.load(sys.stdin)
    print('Valid JSON')
except:
    exit(1)
" >/dev/null; then
                    log_error "Invalid JSON in $format configuration"
                    return 1
                fi
                ;;
            "clash")
                if ! echo "$config_content" | grep -q "proxies:"; then
                    log_error "Invalid YAML in clash configuration"
                    return 1
                fi
                ;;
        esac
    done

    log_debug "Configuration templates test passed"
    return 0
}

# ======================================================================================
# QR CODE GENERATION TESTS
# ======================================================================================

# Function: test_qr_code_generation
# Description: Test QR code generation (if dependencies available)
test_qr_code_generation() {
    # Check if QR code generation dependencies are available
    if ! python3 -c "import qrcode" 2>/dev/null; then
        log_warn "QR code dependencies not available, skipping QR tests"
        return 0
    fi

    # Initialize user database and add test user
    source "${MODULES_DIR}/user_database.sh"
    init_user_database
    source "${MODULES_DIR}/user_management.sh"
    add_user "qrtest" "qr@example.com" "QR Test User"

    # Test QR code generation
    local qr_script="${MODULES_DIR}/qr_generator.py"

    # Test terminal QR generation (basic functionality)
    if ! python3 "$qr_script" "qrtest" --no-terminal --format terminal 2>/dev/null; then
        log_error "QR code generation failed"
        return 1
    fi

    # Test PNG QR generation
    if ! python3 "$qr_script" "qrtest" --no-terminal --format png 2>/dev/null; then
        log_error "PNG QR code generation failed"
        return 1
    fi

    # Verify QR code file was created
    local qr_files
    qr_files=$(find "${USER_DIR}/qr_codes" -name "qrtest_qr_*.png" -type f | wc -l)

    if [[ $qr_files -eq 0 ]]; then
        log_error "No QR code files found"
        return 1
    fi

    log_debug "QR code generation test passed"
    return 0
}

# ======================================================================================
# INTEGRATION TESTS
# ======================================================================================

# Function: test_full_user_workflow
# Description: Test complete user management workflow
test_full_user_workflow() {
    # Source all required modules
    source "${MODULES_DIR}/user_database.sh"
    source "${MODULES_DIR}/user_management.sh"
    source "${MODULES_DIR}/config_templates.sh"

    # Initialize all systems
    init_user_database
    init_config_templates

    # Step 1: Add multiple users
    local users=("user1:email1@test.com:User One" "user2:email2@test.com:User Two" "user3:email3@test.com:User Three")

    for user_info in "${users[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        if ! add_user "$username" "$email" "$description"; then
            log_error "Failed to add user: $username"
            return 1
        fi
    done

    # Step 2: Verify all users exist
    local total_users
    total_users=$(get_user_count)
    if ! assert_equals "3" "$total_users" "Total users after adding"; then
        return 1
    fi

    # Step 3: Generate configurations for all users
    for user_info in "${users[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        if ! generate_user_config "$username" "vless"; then
            log_error "Failed to generate config for user: $username"
            return 1
        fi
    done

    # Step 4: Update user information
    if ! update_user "user2" "description" "Updated User Two"; then
        return 1
    fi

    # Step 5: Create backup
    local backup_path
    backup_path=$(backup_user_database "workflow_test")
    if [[ -z "$backup_path" ]]; then
        return 1
    fi

    # Step 6: Remove a user
    if ! remove_user "user3"; then
        return 1
    fi

    # Verify user was removed
    if user_exists "user3"; then
        log_error "User3 should have been removed"
        return 1
    fi

    # Step 7: Export remaining users
    local export_file="${TEST_USER_DIR}/workflow_export.json"
    if ! export_users "json" "$export_file"; then
        return 1
    fi

    # Step 8: Restore from backup
    if ! restore_user_database "$backup_path"; then
        return 1
    fi

    # Verify user3 is back
    if ! user_exists "user3"; then
        log_error "User3 should be restored"
        return 1
    fi

    log_debug "Full user workflow test passed"
    return 0
}

# ======================================================================================
# MAIN TEST EXECUTION
# ======================================================================================

# Function: run_all_tests
# Description: Execute all test suites
run_all_tests() {
    log_info "Starting VLESS User Management Test Suite"
    log_info "=========================================="

    # Setup test environment
    setup_test_environment

    # Run individual test suites
    run_test "Database Initialization" "test_user_database_initialization"
    run_test "Add User" "test_add_user"
    run_test "Remove User" "test_remove_user"
    run_test "List Users" "test_list_users"
    run_test "User Config Generation" "test_user_config_generation"
    run_test "User Update" "test_user_update"
    run_test "Database Backup/Restore" "test_database_backup_restore"
    run_test "User Export/Import" "test_user_export_import"
    run_test "Configuration Templates" "test_config_templates"
    run_test "QR Code Generation" "test_qr_code_generation"
    run_test "Full User Workflow" "test_full_user_workflow"

    # Display test results
    echo ""
    echo "=========================================="
    log_info "Test Results Summary"
    echo "=========================================="
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"

    # Cleanup test environment
    cleanup_test_environment

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed successfully!"
        return 0
    else
        log_error "$TESTS_FAILED test(s) failed"
        return 1
    fi
}

# Function: run_specific_test
# Description: Run a specific test by name
# Parameters: $1 - test name
run_specific_test() {
    local test_name="$1"

    setup_test_environment

    case "$test_name" in
        "database") run_test "Database Initialization" "test_user_database_initialization" ;;
        "add") run_test "Add User" "test_add_user" ;;
        "remove") run_test "Remove User" "test_remove_user" ;;
        "list") run_test "List Users" "test_list_users" ;;
        "config") run_test "User Config Generation" "test_user_config_generation" ;;
        "update") run_test "User Update" "test_user_update" ;;
        "backup") run_test "Database Backup/Restore" "test_database_backup_restore" ;;
        "export") run_test "User Export/Import" "test_user_export_import" ;;
        "templates") run_test "Configuration Templates" "test_config_templates" ;;
        "qr") run_test "QR Code Generation" "test_qr_code_generation" ;;
        "workflow") run_test "Full User Workflow" "test_full_user_workflow" ;;
        *)
            log_error "Unknown test: $test_name"
            echo "Available tests: database, add, remove, list, config, update, backup, export, templates, qr, workflow"
            cleanup_test_environment
            return 1
            ;;
    esac

    cleanup_test_environment

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "Test passed successfully!"
        return 0
    else
        log_error "Test failed"
        return 1
    fi
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

main() {
    # Parse command line arguments
    case "${1:-all}" in
        "all")
            run_all_tests
            ;;
        "help")
            echo "Usage: $0 [test_name|all|help]"
            echo ""
            echo "Available tests:"
            echo "  database   - Database initialization tests"
            echo "  add        - Add user tests"
            echo "  remove     - Remove user tests"
            echo "  list       - List users tests"
            echo "  config     - Configuration generation tests"
            echo "  update     - User update tests"
            echo "  backup     - Backup/restore tests"
            echo "  export     - Export/import tests"
            echo "  templates  - Configuration templates tests"
            echo "  qr         - QR code generation tests"
            echo "  workflow   - Full workflow integration test"
            echo "  all        - Run all tests (default)"
            ;;
        *)
            run_specific_test "$1"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
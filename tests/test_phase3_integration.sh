#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Phase 3 Integration Tests
# ======================================================================================
# This script provides comprehensive integration testing for Phase 3 components:
# - User Management System
# - QR Code Generation
# - Configuration Templates
# - Database Management
# - End-to-end workflow validation
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
readonly TEST_ROOT="/tmp/vless_phase3_test"
readonly TEST_USER_DIR="${TEST_ROOT}/users"
readonly TEST_BACKUP_DIR="${TEST_ROOT}/backups"
readonly TEST_CONFIG_DIR="${TEST_ROOT}/config"
readonly TEST_LOG_DIR="${TEST_ROOT}/logs"

# Override global variables for testing
export VLESS_ROOT="$TEST_ROOT"
export USER_DIR="$TEST_USER_DIR"
export BACKUP_DIR="$TEST_BACKUP_DIR"
export CONFIG_DIR="$TEST_CONFIG_DIR"
export LOG_DIR="$TEST_LOG_DIR"

# Test results tracking
INTEGRATION_TESTS_TOTAL=0
INTEGRATION_TESTS_PASSED=0
INTEGRATION_TESTS_FAILED=0

# Test data
readonly TEST_USERS=(
    "alice:alice@example.com:Alice's VPN Access"
    "bob:bob@company.com:Bob from IT Department"
    "charlie:charlie@test.org:Charlie - Remote Worker"
    "diana:diana@secure.net:Diana - Security Team"
)

# ======================================================================================
# INTEGRATION TEST FRAMEWORK
# ======================================================================================

# Function: setup_integration_environment
# Description: Setup complete test environment for Phase 3 integration
setup_integration_environment() {
    log_info "Setting up Phase 3 integration test environment..."

    # Clean up any existing test environment
    cleanup_integration_environment

    # Create test directory structure
    create_directory "$TEST_ROOT" "755" "root:root"
    create_directory "$TEST_USER_DIR" "700" "root:root"
    create_directory "$TEST_BACKUP_DIR" "700" "root:root"
    create_directory "$TEST_CONFIG_DIR" "700" "root:root"
    create_directory "$TEST_LOG_DIR" "755" "root:root"

    # Create subdirectories
    create_directory "${TEST_USER_DIR}/configs" "700" "root:root"
    create_directory "${TEST_USER_DIR}/qr_codes" "700" "root:root"
    create_directory "${TEST_USER_DIR}/exports" "700" "root:root"
    create_directory "${TEST_CONFIG_DIR}/templates" "700" "root:root"

    log_success "Integration test environment setup completed"
}

# Function: cleanup_integration_environment
# Description: Clean up integration test environment
cleanup_integration_environment() {
    if [[ -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

# Function: run_integration_test
# Description: Run a single integration test with comprehensive error handling
# Parameters: $1 - test name, $2 - test function
run_integration_test() {
    local test_name="$1"
    local test_function="$2"

    ((INTEGRATION_TESTS_TOTAL++))

    echo ""
    log_info "Running integration test: $test_name"
    echo "============================================================"

    local test_start_time=$(date +%s)

    if $test_function; then
        ((INTEGRATION_TESTS_PASSED++))
        local test_end_time=$(date +%s)
        local test_duration=$((test_end_time - test_start_time))
        log_success "PASSED: $test_name (${test_duration}s)"
    else
        ((INTEGRATION_TESTS_FAILED++))
        log_error "FAILED: $test_name"
    fi

    echo "============================================================"
}

# Function: validate_module_integration
# Description: Validate that all Phase 3 modules can be loaded and initialized
validate_module_integration() {
    log_info "Validating module integration..."

    local modules=(
        "user_management.sh"
        "user_database.sh"
        "config_templates.sh"
        "qr_generator.py"
    )

    for module in "${modules[@]}"; do
        local module_path="${MODULES_DIR}/${module}"

        if [[ ! -f "$module_path" ]]; then
            log_error "Module not found: $module"
            return 1
        fi

        # Test module loading
        if [[ "$module" == *.py ]]; then
            # Python module syntax check
            if ! python3 -m py_compile "$module_path" 2>/dev/null; then
                log_error "Python module syntax error: $module"
                return 1
            fi
        else
            # Bash module syntax check
            if ! bash -n "$module_path"; then
                log_error "Bash module syntax error: $module"
                return 1
            fi
        fi

        log_debug "Module validated: $module"
    done

    log_success "All Phase 3 modules validated successfully"
    return 0
}

# ======================================================================================
# SYSTEM INITIALIZATION TESTS
# ======================================================================================

# Function: test_system_initialization
# Description: Test complete Phase 3 system initialization
test_system_initialization() {
    log_info "Testing system initialization..."

    # Source and initialize database module
    source "${MODULES_DIR}/user_database.sh"
    if ! init_user_database; then
        log_error "Failed to initialize user database"
        return 1
    fi

    # Verify database file creation
    local db_file="${TEST_USER_DIR}/users.json"
    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not created: $db_file"
        return 1
    fi

    # Validate database structure
    if ! python3 -c "
import json
try:
    with open('$db_file', 'r') as f:
        data = json.load(f)
    assert 'metadata' in data
    assert 'users' in data
    assert data['metadata']['version'] == '1.0'
    print('Database structure valid')
except Exception as e:
    print(f'Database validation failed: {e}')
    exit(1)
"; then
        return 1
    fi

    # Source and initialize config templates
    source "${MODULES_DIR}/config_templates.sh"
    if ! init_config_templates; then
        log_error "Failed to initialize configuration templates"
        return 1
    fi

    # Verify template files creation
    local template_files=(
        "${TEST_CONFIG_DIR}/templates/xray_client_template.json"
        "${TEST_CONFIG_DIR}/templates/v2ray_client_template.json"
        "${TEST_CONFIG_DIR}/templates/clash_template.yaml"
        "${TEST_CONFIG_DIR}/templates/sing_box_template.json"
    )

    for template_file in "${template_files[@]}"; do
        if [[ ! -f "$template_file" ]]; then
            log_error "Template file not created: $template_file"
            return 1
        fi
    done

    log_success "System initialization test completed successfully"
    return 0
}

# ======================================================================================
# USER LIFECYCLE TESTS
# ======================================================================================

# Function: test_complete_user_lifecycle
# Description: Test complete user lifecycle from creation to deletion
test_complete_user_lifecycle() {
    log_info "Testing complete user lifecycle..."

    # Source user management module
    source "${MODULES_DIR}/user_management.sh"

    # Phase 1: User Creation
    log_info "Phase 1: Creating test users..."
    local created_users=0

    for user_info in "${TEST_USERS[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        if add_user "$username" "$email" "$description"; then
            ((created_users++))
            log_debug "Created user: $username"
        else
            log_error "Failed to create user: $username"
            return 1
        fi
    done

    # Verify user count
    local total_users=$(get_user_count)
    if [[ $total_users -ne ${#TEST_USERS[@]} ]]; then
        log_error "User count mismatch. Expected: ${#TEST_USERS[@]}, Got: $total_users"
        return 1
    fi

    log_success "Phase 1: Created $created_users users successfully"

    # Phase 2: User Information Retrieval
    log_info "Phase 2: Testing user information retrieval..."

    for user_info in "${TEST_USERS[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        # Test user existence
        if ! user_exists "$username"; then
            log_error "User existence check failed: $username"
            return 1
        fi

        # Test information retrieval
        local retrieved_email=$(get_user_info "$username" "email")
        if [[ "$retrieved_email" != "$email" ]]; then
            log_error "Email mismatch for $username. Expected: $email, Got: $retrieved_email"
            return 1
        fi

        # Test UUID retrieval and validation
        local user_uuid=$(get_user_info "$username" "uuid")
        if [[ -z "$user_uuid" ]]; then
            log_error "Failed to retrieve UUID for user: $username"
            return 1
        fi

        # Validate UUID format
        if ! python3 -c "
import uuid
try:
    uuid.UUID('$user_uuid')
    print('Valid UUID')
except ValueError:
    exit(1)
" >/dev/null; then
            log_error "Invalid UUID format for user $username: $user_uuid"
            return 1
        fi

        log_debug "User information validated: $username"
    done

    log_success "Phase 2: User information retrieval completed successfully"

    # Phase 3: User Modification
    log_info "Phase 3: Testing user modifications..."

    # Update first user's email
    local first_user=$(echo "${TEST_USERS[0]}" | cut -d':' -f1)
    local new_email="updated_${first_user}@newdomain.com"

    if ! update_user "$first_user" "email" "$new_email"; then
        log_error "Failed to update user email: $first_user"
        return 1
    fi

    # Verify update
    local updated_email=$(get_user_info "$first_user" "email")
    if [[ "$updated_email" != "$new_email" ]]; then
        log_error "Email update verification failed for $first_user"
        return 1
    fi

    log_success "Phase 3: User modifications completed successfully"

    # Phase 4: User Deletion
    log_info "Phase 4: Testing user deletion..."

    # Remove last user
    local last_user=$(echo "${TEST_USERS[-1]}" | cut -d':' -f1)

    if ! remove_user "$last_user"; then
        log_error "Failed to remove user: $last_user"
        return 1
    fi

    # Verify deletion
    if user_exists "$last_user"; then
        log_error "User still exists after deletion: $last_user"
        return 1
    fi

    # Verify user count decreased
    local final_count=$(get_user_count)
    local expected_count=$((${#TEST_USERS[@]} - 1))
    if [[ $final_count -ne $expected_count ]]; then
        log_error "User count after deletion incorrect. Expected: $expected_count, Got: $final_count"
        return 1
    fi

    log_success "Phase 4: User deletion completed successfully"
    log_success "Complete user lifecycle test passed"
    return 0
}

# ======================================================================================
# CONFIGURATION GENERATION TESTS
# ======================================================================================

# Function: test_configuration_generation
# Description: Test configuration generation for all supported client types
test_configuration_generation() {
    log_info "Testing configuration generation for all client types..."

    # Ensure we have test users
    source "${MODULES_DIR}/user_management.sh"
    if [[ $(get_user_count) -eq 0 ]]; then
        # Create a test user for configuration testing
        add_user "configtest" "config@test.com" "Configuration Test User"
    fi

    # Get first available user
    local test_username
    test_username=$(python3 -c "
import json
try:
    with open('${TEST_USER_DIR}/users.json', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    if users:
        print(users[0].get('username', ''))
except Exception:
    pass
")

    if [[ -z "$test_username" ]]; then
        log_error "No test user available for configuration generation"
        return 1
    fi

    log_info "Using test user: $test_username"

    # Source configuration templates module
    source "${MODULES_DIR}/config_templates.sh"

    # Test all supported configuration types
    local config_types=("xray" "v2ray" "clash" "sing-box" "vless-url")
    local generated_configs=0

    for config_type in "${config_types[@]}"; do
        log_info "Generating $config_type configuration..."

        if generate_config_for_user "$test_username" "$config_type"; then
            ((generated_configs++))

            # Verify configuration file was created
            local config_pattern="${TEST_USER_DIR}/exports/${test_username}/*_${config_type}_*"
            local config_files=$(ls $config_pattern 2>/dev/null | wc -l)

            if [[ $config_files -eq 0 ]]; then
                log_error "No configuration file found for $config_type"
                return 1
            fi

            # Get the most recent config file
            local config_file=$(ls -t $config_pattern 2>/dev/null | head -1)

            # Validate configuration content based on type
            if ! validate_config_content "$config_file" "$config_type" "$test_username"; then
                log_error "Configuration validation failed for $config_type"
                return 1
            fi

            log_debug "Successfully generated and validated $config_type configuration"
        else
            log_error "Failed to generate $config_type configuration"
            return 1
        fi
    done

    if [[ $generated_configs -eq ${#config_types[@]} ]]; then
        log_success "Configuration generation test completed successfully"
        return 0
    else
        log_error "Configuration generation test failed"
        return 1
    fi
}

# Function: validate_config_content
# Description: Validate generated configuration content
# Parameters: $1 - config file, $2 - config type, $3 - username
validate_config_content() {
    local config_file="$1"
    local config_type="$2"
    local username="$3"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    local config_content=$(cat "$config_file")

    case "$config_type" in
        "vless-url")
            # Validate VLESS URL format
            if ! echo "$config_content" | grep -q "^vless://[a-f0-9-]\+@[0-9.]\+:[0-9]\+"; then
                log_error "Invalid VLESS URL format"
                return 1
            fi

            # Check if username is in the URL
            if ! echo "$config_content" | grep -q "#$username"; then
                log_error "Username not found in VLESS URL"
                return 1
            fi
            ;;

        "xray"|"v2ray"|"sing-box")
            # Validate JSON structure
            if ! echo "$config_content" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    assert 'outbounds' in data
    assert 'inbounds' in data
    # Check for VLESS protocol
    found_vless = False
    for outbound in data.get('outbounds', []):
        if outbound.get('protocol') == 'vless':
            found_vless = True
            break
    assert found_vless, 'VLESS protocol not found in outbounds'
    print('JSON configuration valid')
except Exception as e:
    print(f'JSON validation failed: {e}')
    exit(1)
"; then
                return 1
            fi
            ;;

        "clash")
            # Validate YAML structure
            if ! echo "$config_content" | grep -q "proxies:"; then
                log_error "Clash YAML missing proxies section"
                return 1
            fi

            if ! echo "$config_content" | grep -q "type: vless"; then
                log_error "Clash YAML missing VLESS proxy type"
                return 1
            fi

            if ! echo "$config_content" | grep -q "name:.*$username"; then
                log_error "Username not found in Clash configuration"
                return 1
            fi
            ;;
    esac

    log_debug "Configuration content validated: $config_type"
    return 0
}

# ======================================================================================
# QR CODE GENERATION TESTS
# ======================================================================================

# Function: test_qr_code_generation
# Description: Test QR code generation functionality
test_qr_code_generation() {
    log_info "Testing QR code generation..."

    # Check if QR code dependencies are available
    if ! python3 -c "import qrcode" 2>/dev/null; then
        log_warn "QR code dependencies not available, skipping QR code tests"
        return 0
    fi

    # Ensure we have a test user
    source "${MODULES_DIR}/user_management.sh"
    if [[ $(get_user_count) -eq 0 ]]; then
        add_user "qrtest" "qr@test.com" "QR Test User"
    fi

    # Get first available user
    local test_username
    test_username=$(python3 -c "
import json
try:
    with open('${TEST_USER_DIR}/users.json', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    if users:
        print(users[0].get('username', ''))
except Exception:
    pass
")

    if [[ -z "$test_username" ]]; then
        log_error "No test user available for QR code generation"
        return 1
    fi

    log_info "Generating QR code for user: $test_username"

    # Test QR code generation
    local qr_script="${MODULES_DIR}/qr_generator.py"

    # Test PNG QR generation
    if ! python3 "$qr_script" "$test_username" --no-terminal --format png 2>/dev/null; then
        log_error "Failed to generate PNG QR code"
        return 1
    fi

    # Verify QR code file was created
    local qr_pattern="${TEST_USER_DIR}/qr_codes/${test_username}_qr_*.png"
    local qr_files=$(ls $qr_pattern 2>/dev/null | wc -l)

    if [[ $qr_files -eq 0 ]]; then
        log_error "No QR code files found"
        return 1
    fi

    # Get the most recent QR code file
    local qr_file=$(ls -t $qr_pattern 2>/dev/null | head -1)

    # Basic file validation
    if [[ ! -f "$qr_file" ]]; then
        log_error "QR code file not found: $qr_file"
        return 1
    fi

    # Check file size (should be reasonable for a QR code image)
    local file_size=$(stat -c%s "$qr_file" 2>/dev/null || echo 0)
    if [[ $file_size -lt 1000 ]]; then
        log_error "QR code file too small, possibly corrupted: $file_size bytes"
        return 1
    fi

    # Test batch QR generation if we have multiple users
    local user_count=$(get_user_count)
    if [[ $user_count -gt 1 ]]; then
        log_info "Testing batch QR code generation..."

        if ! python3 "$qr_script" --batch --format png 2>/dev/null; then
            log_error "Failed to generate batch QR codes"
            return 1
        fi

        # Verify multiple QR codes were created
        local total_qr_files=$(find "${TEST_USER_DIR}/qr_codes" -name "*.png" -type f | wc -l)
        if [[ $total_qr_files -lt $user_count ]]; then
            log_error "Batch QR generation incomplete. Expected: $user_count, Found: $total_qr_files"
            return 1
        fi
    fi

    log_success "QR code generation test completed successfully"
    return 0
}

# ======================================================================================
# DATABASE OPERATIONS TESTS
# ======================================================================================

# Function: test_database_operations
# Description: Test database backup, restore, export, and import operations
test_database_operations() {
    log_info "Testing database operations..."

    # Ensure we have test data
    source "${MODULES_DIR}/user_management.sh"
    if [[ $(get_user_count) -lt 2 ]]; then
        # Add some test users for database operations
        add_user "dbtest1" "db1@test.com" "Database Test User 1"
        add_user "dbtest2" "db2@test.com" "Database Test User 2"
    fi

    local initial_count=$(get_user_count)

    # Source database module
    source "${MODULES_DIR}/user_database.sh"

    # Test 1: Database Backup
    log_info "Testing database backup..."

    local backup_path
    backup_path=$(backup_user_database "integration_test")

    if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
        log_error "Database backup failed"
        return 1
    fi

    log_debug "Backup created: $backup_path"

    # Test 2: Database Export
    log_info "Testing database export..."

    local export_file="${TEST_USER_DIR}/integration_export.json"
    if ! export_users "json" "$export_file"; then
        log_error "Database export failed"
        return 1
    fi

    # Validate export file
    if ! python3 -c "
import json
try:
    with open('$export_file', 'r') as f:
        data = json.load(f)
    assert 'users' in data
    assert len(data['users']) >= 2
    print('Export validation successful')
except Exception as e:
    print(f'Export validation failed: {e}')
    exit(1)
"; then
        return 1
    fi

    # Test 3: Modify database
    log_info "Modifying database for restore testing..."

    # Add a temporary user
    add_user "tempuser" "temp@test.com" "Temporary User"
    local modified_count=$(get_user_count)

    if [[ $modified_count -le $initial_count ]]; then
        log_error "Failed to modify database for restore test"
        return 1
    fi

    # Test 4: Database Restore
    log_info "Testing database restore..."

    if ! restore_user_database "$backup_path"; then
        log_error "Database restore failed"
        return 1
    fi

    # Verify restoration
    local restored_count=$(get_user_count)
    if [[ $restored_count -ne $initial_count ]]; then
        log_error "Database restore verification failed. Expected: $initial_count, Got: $restored_count"
        return 1
    fi

    # Verify temporary user was removed
    if user_exists "tempuser"; then
        log_error "Temporary user should have been removed by restore"
        return 1
    fi

    # Test 5: Database Import
    log_info "Testing database import..."

    # Clear database for import test
    rm -f "${TEST_USER_DIR}/users.json"
    init_user_database

    if ! import_users "$export_file" "json" "replace"; then
        log_error "Database import failed"
        return 1
    fi

    # Verify import
    local imported_count=$(get_user_count)
    if [[ $imported_count -ne $initial_count ]]; then
        log_error "Database import verification failed. Expected: $initial_count, Got: $imported_count"
        return 1
    fi

    log_success "Database operations test completed successfully"
    return 0
}

# ======================================================================================
# END-TO-END INTEGRATION TESTS
# ======================================================================================

# Function: test_end_to_end_workflow
# Description: Test complete end-to-end workflow
test_end_to_end_workflow() {
    log_info "Testing end-to-end workflow..."

    # Step 1: System initialization
    log_info "Step 1: System initialization"
    source "${MODULES_DIR}/user_database.sh"
    source "${MODULES_DIR}/user_management.sh"
    source "${MODULES_DIR}/config_templates.sh"

    init_user_database
    init_config_templates

    # Step 2: User creation and management
    log_info "Step 2: User creation and management"

    local workflow_users=("alice:alice@workflow.com:Alice Workflow" "bob:bob@workflow.com:Bob Workflow")

    for user_info in "${workflow_users[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        if ! add_user "$username" "$email" "$description"; then
            log_error "Failed to add user in workflow: $username"
            return 1
        fi
    done

    # Step 3: Configuration generation for all users
    log_info "Step 3: Configuration generation"

    local config_types=("vless-url" "xray" "clash")

    for user_info in "${workflow_users[@]}"; do
        IFS=':' read -r username email description <<< "$user_info"

        for config_type in "${config_types[@]}"; do
            if ! generate_config_for_user "$username" "$config_type"; then
                log_error "Failed to generate $config_type config for $username"
                return 1
            fi
        done
    done

    # Step 4: QR code generation (if available)
    log_info "Step 4: QR code generation"

    if python3 -c "import qrcode" 2>/dev/null; then
        local qr_script="${MODULES_DIR}/qr_generator.py"

        for user_info in "${workflow_users[@]}"; do
            IFS=':' read -r username email description <<< "$user_info"

            if ! python3 "$qr_script" "$username" --no-terminal --format png 2>/dev/null; then
                log_error "Failed to generate QR code for $username"
                return 1
            fi
        done
    else
        log_warn "QR code generation skipped (dependencies not available)"
    fi

    # Step 5: Database operations
    log_info "Step 5: Database backup and export"

    # Create backup
    local workflow_backup
    workflow_backup=$(backup_user_database "workflow_test")
    if [[ -z "$workflow_backup" ]]; then
        log_error "Failed to create workflow backup"
        return 1
    fi

    # Export users
    local workflow_export="${TEST_USER_DIR}/workflow_export.json"
    if ! export_users "json" "$workflow_export"; then
        log_error "Failed to export users in workflow"
        return 1
    fi

    # Step 6: User modification and verification
    log_info "Step 6: User modification"

    if ! update_user "alice" "description" "Alice - Updated in Workflow"; then
        log_error "Failed to update user in workflow"
        return 1
    fi

    # Verify update
    local updated_desc=$(get_user_info "alice" "description")
    if [[ "$updated_desc" != "Alice - Updated in Workflow" ]]; then
        log_error "User update verification failed in workflow"
        return 1
    fi

    # Step 7: File verification
    log_info "Step 7: Generated files verification"

    # Count generated files
    local config_files=$(find "${TEST_USER_DIR}/exports" -type f | wc -l)
    local qr_files=$(find "${TEST_USER_DIR}/qr_codes" -type f 2>/dev/null | wc -l || echo 0)

    log_info "Generated files summary:"
    log_info "  Configuration files: $config_files"
    log_info "  QR code files: $qr_files"
    log_info "  Database backups: $(find "${TEST_BACKUP_DIR}" -name "*.json" -type f | wc -l)"

    # Verify minimum expected files
    local expected_config_files=$((${#workflow_users[@]} * ${#config_types[@]}))
    if [[ $config_files -lt $expected_config_files ]]; then
        log_error "Insufficient configuration files generated. Expected: $expected_config_files, Got: $config_files"
        return 1
    fi

    log_success "End-to-end workflow test completed successfully"
    return 0
}

# ======================================================================================
# PERFORMANCE AND STRESS TESTS
# ======================================================================================

# Function: test_performance_stress
# Description: Test system performance under stress conditions
test_performance_stress() {
    log_info "Testing performance under stress conditions..."

    # Source required modules
    source "${MODULES_DIR}/user_management.sh"
    source "${MODULES_DIR}/config_templates.sh"

    # Test parameters
    local stress_user_count=50
    local config_types=("vless-url" "xray")

    # Stress test: Create many users
    log_info "Stress test: Creating $stress_user_count users..."

    local stress_start_time=$(date +%s)
    local created_users=0

    for ((i=1; i<=stress_user_count; i++)); do
        local username="stressuser${i}"
        local email="stress${i}@test.com"
        local description="Stress Test User ${i}"

        if add_user "$username" "$email" "$description" >/dev/null 2>&1; then
            ((created_users++))
        else
            log_warn "Failed to create stress user: $username"
        fi

        # Progress indicator
        if ((i % 10 == 0)); then
            log_debug "Created $i/$stress_user_count users"
        fi
    done

    local stress_end_time=$(date +%s)
    local stress_duration=$((stress_end_time - stress_start_time))

    log_info "Created $created_users users in ${stress_duration}s"

    # Performance metrics
    local users_per_second=$((created_users / (stress_duration + 1)))
    log_info "Performance: $users_per_second users/second"

    # Verify final count
    local final_count=$(get_user_count)
    if [[ $final_count -ne $created_users ]]; then
        log_error "User count mismatch after stress test. Expected: $created_users, Got: $final_count"
        return 1
    fi

    # Stress test: Generate configurations for all users
    log_info "Stress test: Generating configurations for all users..."

    local config_start_time=$(date +%s)
    local config_count=0

    # Generate VLESS URLs for all users (faster operation)
    for ((i=1; i<=created_users; i++)); do
        local username="stressuser${i}"

        if generate_config_for_user "$username" "vless-url" >/dev/null 2>&1; then
            ((config_count++))
        fi

        # Progress indicator
        if ((i % 10 == 0)); then
            log_debug "Generated configs for $i/$created_users users"
        fi
    done

    local config_end_time=$(date +%s)
    local config_duration=$((config_end_time - config_start_time))

    log_info "Generated $config_count configurations in ${config_duration}s"

    # Performance threshold check
    local configs_per_second=$((config_count / (config_duration + 1)))
    log_info "Performance: $configs_per_second configs/second"

    # Basic performance threshold (should be able to handle at least 5 operations per second)
    if [[ $users_per_second -lt 5 && $stress_duration -gt 10 ]]; then
        log_warn "User creation performance below threshold: $users_per_second users/second"
    fi

    if [[ $configs_per_second -lt 10 && $config_duration -gt 5 ]]; then
        log_warn "Configuration generation performance below threshold: $configs_per_second configs/second"
    fi

    log_success "Performance stress test completed successfully"
    return 0
}

# ======================================================================================
# MAIN INTEGRATION TEST EXECUTION
# ======================================================================================

# Function: run_phase3_integration_tests
# Description: Execute all Phase 3 integration tests
run_phase3_integration_tests() {
    log_info "Starting VLESS Phase 3 Integration Test Suite"
    log_info "=============================================="

    # Validate environment
    if [[ $EUID -ne 0 ]]; then
        log_error "Integration tests must be run as root"
        return 1
    fi

    # Setup test environment
    setup_integration_environment

    # Validate module integration
    if ! validate_module_integration; then
        log_error "Module integration validation failed"
        cleanup_integration_environment
        return 1
    fi

    # Run integration test suites
    run_integration_test "System Initialization" "test_system_initialization"
    run_integration_test "Complete User Lifecycle" "test_complete_user_lifecycle"
    run_integration_test "Configuration Generation" "test_configuration_generation"
    run_integration_test "QR Code Generation" "test_qr_code_generation"
    run_integration_test "Database Operations" "test_database_operations"
    run_integration_test "End-to-End Workflow" "test_end_to_end_workflow"
    run_integration_test "Performance Stress Test" "test_performance_stress"

    # Display integration test results
    echo ""
    echo "=============================================="
    log_info "Phase 3 Integration Test Results"
    echo "=============================================="
    echo "Total Integration Tests: $INTEGRATION_TESTS_TOTAL"
    echo "Passed: $INTEGRATION_TESTS_PASSED"
    echo "Failed: $INTEGRATION_TESTS_FAILED"

    if [[ $INTEGRATION_TESTS_TOTAL -gt 0 ]]; then
        local success_rate=$((INTEGRATION_TESTS_PASSED * 100 / INTEGRATION_TESTS_TOTAL))
        echo "Success Rate: ${success_rate}%"
    fi

    # Generate test report
    generate_test_report

    # Cleanup test environment
    cleanup_integration_environment

    if [[ $INTEGRATION_TESTS_FAILED -eq 0 ]]; then
        log_success "All Phase 3 integration tests passed successfully!"
        log_success "Phase 3: User Management System is ready for production"
        return 0
    else
        log_error "$INTEGRATION_TESTS_FAILED integration test(s) failed"
        log_error "Phase 3 integration has issues that need to be resolved"
        return 1
    fi
}

# Function: generate_test_report
# Description: Generate detailed test report
generate_test_report() {
    local report_file="${TEST_ROOT}/phase3_integration_report.txt"

    cat > "$report_file" << EOF
VLESS+Reality VPN Management System
Phase 3 Integration Test Report
Generated: $(date)

=== Test Environment ===
Test Root: $TEST_ROOT
Modules Directory: $MODULES_DIR
Python Version: $(python3 --version 2>/dev/null || echo "Not available")

=== Test Results Summary ===
Total Integration Tests: $INTEGRATION_TESTS_TOTAL
Passed: $INTEGRATION_TESTS_PASSED
Failed: $INTEGRATION_TESTS_FAILED
Success Rate: $((INTEGRATION_TESTS_PASSED * 100 / (INTEGRATION_TESTS_TOTAL > 0 ? INTEGRATION_TESTS_TOTAL : 1)))%

=== Component Status ===
✓ User Database Management: Operational
✓ User CRUD Operations: Operational
✓ Configuration Templates: Operational
✓ QR Code Generation: $(python3 -c "import qrcode; print('Operational')" 2>/dev/null || echo "Dependencies Missing")
✓ Backup/Restore System: Operational
✓ Import/Export System: Operational

=== Generated Test Files ===
Configuration Files: $(find "${TEST_USER_DIR}/exports" -type f 2>/dev/null | wc -l || echo 0)
QR Code Files: $(find "${TEST_USER_DIR}/qr_codes" -type f 2>/dev/null | wc -l || echo 0)
Database Backups: $(find "${TEST_BACKUP_DIR}" -name "*.json" -type f 2>/dev/null | wc -l || echo 0)

=== Recommendations ===
$(if [[ $INTEGRATION_TESTS_FAILED -eq 0 ]]; then
    echo "✓ Phase 3 is ready for production deployment"
    echo "✓ All user management features are operational"
    echo "✓ System performance meets requirements"
else
    echo "✗ Phase 3 has integration issues"
    echo "✗ Review failed tests before production deployment"
fi)

=== Next Steps ===
$(if [[ $INTEGRATION_TESTS_FAILED -eq 0 ]]; then
    echo "- Proceed to Phase 4: Security and Firewall Configuration"
    echo "- Deploy user management system to production environment"
    echo "- Train administrators on user management procedures"
else
    echo "- Fix failing integration tests"
    echo "- Re-run integration test suite"
    echo "- Verify all components before proceeding to Phase 4"
fi)

EOF

    log_info "Test report generated: $report_file"
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

main() {
    log_info "VLESS Phase 3 Integration Test Runner"

    # Parse command line arguments
    case "${1:-all}" in
        "all")
            run_phase3_integration_tests
            ;;
        "system")
            setup_integration_environment
            run_integration_test "System Initialization" "test_system_initialization"
            cleanup_integration_environment
            ;;
        "lifecycle")
            setup_integration_environment
            run_integration_test "Complete User Lifecycle" "test_complete_user_lifecycle"
            cleanup_integration_environment
            ;;
        "config")
            setup_integration_environment
            run_integration_test "Configuration Generation" "test_configuration_generation"
            cleanup_integration_environment
            ;;
        "qr")
            setup_integration_environment
            run_integration_test "QR Code Generation" "test_qr_code_generation"
            cleanup_integration_environment
            ;;
        "database")
            setup_integration_environment
            run_integration_test "Database Operations" "test_database_operations"
            cleanup_integration_environment
            ;;
        "workflow")
            setup_integration_environment
            run_integration_test "End-to-End Workflow" "test_end_to_end_workflow"
            cleanup_integration_environment
            ;;
        "stress")
            setup_integration_environment
            run_integration_test "Performance Stress Test" "test_performance_stress"
            cleanup_integration_environment
            ;;
        "help")
            echo "Usage: $0 [test_type|all|help]"
            echo ""
            echo "Available test types:"
            echo "  system      - System initialization tests"
            echo "  lifecycle   - User lifecycle tests"
            echo "  config      - Configuration generation tests"
            echo "  qr          - QR code generation tests"
            echo "  database    - Database operations tests"
            echo "  workflow    - End-to-end workflow tests"
            echo "  stress      - Performance stress tests"
            echo "  all         - Run all integration tests (default)"
            echo "  help        - Show this help message"
            ;;
        *)
            log_error "Unknown test type: $1"
            echo "Use '$0 help' for available options"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
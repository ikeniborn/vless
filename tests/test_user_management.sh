#!/bin/bash

# VLESS+Reality VPN Management System - User Management Unit Tests
# Version: 1.0.0
# Description: Unit tests for user_management.sh module

set -euo pipefail

# Import test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Initialize test suite
init_test_framework "User Management Unit Tests"

# Test configuration
TEST_DB_FILE=""
TEST_CONFIG_DIR=""

# Setup test environment
setup_test_environment() {
    # Create temporary directories for testing
    TEST_CONFIG_DIR=$(create_temp_dir)
    TEST_DB_FILE="${TEST_CONFIG_DIR}/test_users.json"

    # Create mock config files
    mkdir -p "${TEST_CONFIG_DIR}/config"
    cat > "${TEST_CONFIG_DIR}/config/xray_config_template.json" << 'EOF'
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": []
            }
        }
    ]
}
EOF

    # Mock external dependencies
    mock_command "systemctl" "success" ""
    mock_command "docker" "success" ""

    # Set environment variables for testing
    export USER_DB_FILE="$TEST_DB_FILE"
    export PROJECT_ROOT="$TEST_CONFIG_DIR"
}

# Cleanup test environment
cleanup_test_environment() {
    cleanup_temp_files
    [[ -n "$TEST_CONFIG_DIR" ]] && rm -rf "$TEST_CONFIG_DIR"
}

# Helper function to source modules with mocked dependencies
source_modules() {
    # Create a temporary common_utils with mocked functions
    local temp_common_utils
    temp_common_utils=$(create_temp_file)
    cat > "$temp_common_utils" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock common utilities functions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3

LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_debug() { echo "[DEBUG] $*"; }

validate_not_empty() {
    local value="$1"
    local param_name="$2"
    [[ -n "$value" ]] || { log_error "Parameter $param_name cannot be empty"; return 1; }
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

generate_uuid() {
    echo "$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440000")"
}

handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    return "$exit_code"
}
EOF

    # Create a temporary user_database with mocked functions
    local temp_user_db
    temp_user_db=$(create_temp_file)
    cat > "$temp_user_db" << 'EOF'
#!/bin/bash
set -euo pipefail

USER_DB_FILE="${USER_DB_FILE:-/tmp/test_users.json}"

init_user_database() {
    [[ ! -f "$USER_DB_FILE" ]] && echo "[]" > "$USER_DB_FILE"
}

add_user_to_db() {
    local email="$1"
    local uuid="$2"
    local name="${3:-}"
    local flow="${4:-}"

    init_user_database

    local user_entry="{\"email\":\"$email\",\"uuid\":\"$uuid\",\"name\":\"$name\",\"flow\":\"$flow\",\"created\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"active\":true}"

    # Simple JSON array append (not production quality, but works for testing)
    local current_content
    current_content=$(cat "$USER_DB_FILE")
    if [[ "$current_content" == "[]" ]]; then
        echo "[$user_entry]" > "$USER_DB_FILE"
    else
        # Remove closing bracket and add new entry
        echo "${current_content%]}, $user_entry]" > "$USER_DB_FILE"
    fi
}

remove_user_from_db() {
    local uuid="$1"
    init_user_database

    # For testing, just mark as removed
    local temp_file
    temp_file=$(mktemp)
    jq --arg uuid "$uuid" 'map(select(.uuid != $uuid))' "$USER_DB_FILE" > "$temp_file" 2>/dev/null || {
        # Fallback if jq is not available
        grep -v "\"uuid\":\"$uuid\"" "$USER_DB_FILE" > "$temp_file" || echo "[]" > "$temp_file"
    }
    mv "$temp_file" "$USER_DB_FILE"
}

get_user_by_uuid() {
    local uuid="$1"
    init_user_database

    if command -v jq >/dev/null 2>&1; then
        jq -r --arg uuid "$uuid" '.[] | select(.uuid == $uuid) | .email' "$USER_DB_FILE" 2>/dev/null || echo ""
    else
        grep "\"uuid\":\"$uuid\"" "$USER_DB_FILE" | sed 's/.*"email":"\([^"]*\)".*/\1/' || echo ""
    fi
}

list_all_users() {
    init_user_database

    if command -v jq >/dev/null 2>&1; then
        jq -r '.[] | "\(.email) \(.uuid) \(.name // "N/A")"' "$USER_DB_FILE" 2>/dev/null || echo ""
    else
        cat "$USER_DB_FILE"
    fi
}

user_exists() {
    local email="$1"
    init_user_database

    if command -v jq >/dev/null 2>&1; then
        jq -e --arg email "$email" '.[] | select(.email == $email)' "$USER_DB_FILE" >/dev/null 2>&1
    else
        grep -q "\"email\":\"$email\"" "$USER_DB_FILE" 2>/dev/null
    fi
}
EOF

    # Source the mock modules
    source "$temp_common_utils"
    source "$temp_user_db"

    # Now source the actual user management module
    # Temporarily override the source commands in user_management.sh
    local temp_user_mgmt
    temp_user_mgmt=$(create_temp_file)

    # Copy user_management.sh but replace the source lines with our mocks
    sed "s|source.*common_utils.sh|source $temp_common_utils|g; s|source.*user_database.sh|source $temp_user_db|g" \
        "${SCRIPT_DIR}/../modules/user_management.sh" > "$temp_user_mgmt"

    source "$temp_user_mgmt"
}

# Test functions

test_add_user_function() {
    source_modules

    local test_email="test@example.com"
    local test_name="Test User"

    # Test adding a user
    if add_user "$test_email" "$test_name"; then
        pass_test "Should successfully add user"
    else
        fail_test "Should successfully add user"
        return
    fi

    # Verify user was added to database
    if user_exists "$test_email"; then
        pass_test "User should exist in database after adding"
    else
        fail_test "User should exist in database after adding"
    fi
}

test_add_user_with_custom_uuid() {
    source_modules

    local test_email="custom@example.com"
    local custom_uuid="550e8400-e29b-41d4-a716-446655440000"

    # Test adding user with custom UUID
    if add_user "$test_email" "" "" false "$custom_uuid"; then
        pass_test "Should successfully add user with custom UUID"
    else
        fail_test "Should successfully add user with custom UUID"
        return
    fi

    # Verify the specific UUID was used
    local stored_user
    stored_user=$(get_user_by_uuid "$custom_uuid")
    assert_equals "$test_email" "$stored_user" "Should find user by custom UUID"
}

test_add_user_invalid_input() {
    source_modules

    # Test with empty email
    if ! add_user "" "Test User" 2>/dev/null; then
        pass_test "Should reject empty email"
    else
        fail_test "Should reject empty email"
    fi

    # Test with invalid email format
    if ! add_user "invalid-email" "Test User" 2>/dev/null; then
        pass_test "Should reject invalid email format"
    else
        fail_test "Should reject invalid email format"
    fi

    # Test with invalid custom UUID
    if ! add_user "test@example.com" "Test User" "" false "invalid-uuid" 2>/dev/null; then
        pass_test "Should reject invalid UUID format"
    else
        fail_test "Should reject invalid UUID format"
    fi
}

test_remove_user_function() {
    source_modules

    local test_email="remove@example.com"
    local test_uuid

    # First add a user
    add_user "$test_email" "Remove Test"
    test_uuid=$(generate_uuid)

    # Add user with known UUID for testing
    add_user_to_db "$test_email" "$test_uuid" "Remove Test"

    # Test removing the user
    if remove_user "$test_email"; then
        pass_test "Should successfully remove user"
    else
        fail_test "Should successfully remove user"
        return
    fi

    # Verify user was removed
    if ! user_exists "$test_email"; then
        pass_test "User should not exist after removal"
    else
        fail_test "User should not exist after removal"
    fi
}

test_remove_nonexistent_user() {
    source_modules

    # Test removing a user that doesn't exist
    if ! remove_user "nonexistent@example.com" 2>/dev/null; then
        pass_test "Should fail to remove nonexistent user"
    else
        fail_test "Should fail to remove nonexistent user"
    fi
}

test_list_users_function() {
    source_modules

    # Add some test users
    add_user "user1@example.com" "User One"
    add_user "user2@example.com" "User Two"

    # Test listing users
    local user_list
    user_list=$(list_users)

    assert_not_equals "" "$user_list" "User list should not be empty"
    assert_contains "$user_list" "user1@example.com" "Should contain first user"
    assert_contains "$user_list" "user2@example.com" "Should contain second user"
}

test_get_user_config_function() {
    source_modules

    local test_email="config@example.com"
    local test_uuid

    # Add a test user
    add_user "$test_email" "Config Test"

    # Mock the UUID for testing
    test_uuid="550e8400-e29b-41d4-a716-446655440000"
    add_user_to_db "$test_email" "$test_uuid" "Config Test"

    # Test getting user config
    local config
    config=$(get_user_config "$test_email")

    assert_not_equals "" "$config" "Config should not be empty"
    assert_contains "$config" "$test_uuid" "Config should contain user UUID"
    assert_contains "$config" "vless://" "Config should be a VLESS URL"
}

test_search_users_function() {
    source_modules

    # Add test users
    add_user "john.doe@example.com" "John Doe"
    add_user "jane.smith@example.com" "Jane Smith"
    add_user "bob.jones@company.com" "Bob Jones"

    # Test searching by email domain
    local search_result
    search_result=$(search_users "example.com")

    assert_contains "$search_result" "john.doe@example.com" "Should find john.doe"
    assert_contains "$search_result" "jane.smith@example.com" "Should find jane.smith"
    assert_not_contains "$search_result" "bob.jones@company.com" "Should not find bob.jones"

    # Test searching by name
    search_result=$(search_users "John")
    assert_contains "$search_result" "john.doe@example.com" "Should find user by name"
}

test_user_statistics_function() {
    source_modules

    # Add some users
    add_user "stats1@example.com" "Stats User 1"
    add_user "stats2@example.com" "Stats User 2"
    add_user "stats3@example.com" "Stats User 3"

    # Test getting statistics
    local stats
    stats=$(get_user_statistics)

    assert_not_equals "" "$stats" "Statistics should not be empty"
    assert_contains "$stats" "3" "Should show count of 3 users"
}

test_bulk_user_operations() {
    source_modules

    # Create a test file with user list
    local user_list_file
    user_list_file=$(create_temp_file)
    cat > "$user_list_file" << 'EOF'
bulk1@example.com,Bulk User 1
bulk2@example.com,Bulk User 2
bulk3@example.com,Bulk User 3
EOF

    # Test bulk add (if function exists)
    if declare -f bulk_add_users >/dev/null; then
        if bulk_add_users "$user_list_file"; then
            pass_test "Bulk add users should succeed"

            # Verify all users were added
            for email in "bulk1@example.com" "bulk2@example.com" "bulk3@example.com"; do
                if user_exists "$email"; then
                    pass_test "Bulk added user $email should exist"
                else
                    fail_test "Bulk added user $email should exist"
                fi
            done
        else
            fail_test "Bulk add users should succeed"
        fi
    else
        skip_test "bulk_add_users function not implemented"
    fi
}

test_user_config_generation() {
    source_modules

    local test_email="genconfig@example.com"
    local test_uuid="550e8400-e29b-41d4-a716-446655440000"

    # Add user to database
    add_user_to_db "$test_email" "$test_uuid" "Gen Config Test"

    # Mock server configuration
    export SERVER_IP="198.51.100.1"
    export SERVER_PORT="443"

    # Test config generation
    if declare -f generate_client_config >/dev/null; then
        local config
        config=$(generate_client_config "$test_email")

        assert_not_equals "" "$config" "Generated config should not be empty"
        assert_contains "$config" "$test_uuid" "Config should contain user UUID"
        assert_contains "$config" "$SERVER_IP" "Config should contain server IP"
        assert_contains "$config" "$SERVER_PORT" "Config should contain server port"
    else
        skip_test "generate_client_config function not found"
    fi
}

test_user_data_validation() {
    source_modules

    # Test email validation within user management context
    local valid_emails=("test@example.com" "user.name@domain.co.uk" "123@test-domain.org")
    local invalid_emails=("invalid" "@domain.com" "user@" "user space@domain.com")

    for email in "${valid_emails[@]}"; do
        if validate_email "$email"; then
            pass_test "Should validate email: $email"
        else
            fail_test "Should validate email: $email"
        fi
    done

    for email in "${invalid_emails[@]}"; do
        if ! validate_email "$email" 2>/dev/null; then
            pass_test "Should reject invalid email: $email"
        else
            fail_test "Should reject invalid email: $email"
        fi
    done
}

test_concurrent_user_operations() {
    source_modules

    # Test that concurrent operations don't corrupt the database
    local temp_script
    temp_script=$(create_temp_file)

    cat > "$temp_script" << EOF
#!/bin/bash
source_modules() {
    $(declare -f source_modules)
}
source_modules
add_user "concurrent\$1@example.com" "Concurrent User \$1"
EOF
    chmod +x "$temp_script"

    # Run multiple instances in background
    "$temp_script" "1" &
    "$temp_script" "2" &
    "$temp_script" "3" &
    wait

    # Verify all users were added
    local user_count=0
    for i in 1 2 3; do
        if user_exists "concurrent${i}@example.com"; then
            ((user_count++))
        fi
    done

    assert_equals "3" "$user_count" "All concurrent users should be added"
}

# Main execution
main() {
    setup_test_environment
    trap cleanup_test_environment EXIT

    # Run all test functions
    run_all_test_functions

    # Finalize test suite
    finalize_test_suite
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
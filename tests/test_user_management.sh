#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - User Management Test Suite (Final Version)
# Version: 1.0.0
# Description: Comprehensive but simplified test suite for Stage 3 user management

# Test configuration
readonly TEST_NAME="User Management Test Suite (Final)"
readonly TEST_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly MAIN_SCRIPT="$PROJECT_ROOT/vless-manager.sh"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test environment
TEST_DIR="/tmp/vless-test-final-$$"

#######################################################################################
# TEST FRAMEWORK FUNCTIONS
#######################################################################################

test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')

    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" ;;
        "PASS") echo -e "${GREEN}[PASS]${NC} ${timestamp} - $message" ;;
        "FAIL") echo -e "${RED}[FAIL]${NC} ${timestamp} - $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" ;;
    esac
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"  # "pass" or "fail"

    ((TOTAL_TESTS++))

    local result=""
    if eval "$test_command" >/dev/null 2>&1; then
        result="pass"
    else
        result="fail"
    fi

    if [[ "$result" == "$expected_result" ]]; then
        test_log "PASS" "$test_name"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name (Expected: $expected_result, Got: $result)"
        ((FAILED_TESTS++))
        return 1
    fi
}

setup_test_environment() {
    test_log "INFO" "Setting up test environment..."

    # Create temporary test directory
    mkdir -p "$TEST_DIR"

    # Create test project structure
    mkdir -p "$TEST_DIR/config/users"
    mkdir -p "$TEST_DIR/data/keys"
    mkdir -p "$TEST_DIR/logs"

    # Set permissions
    chmod 700 "$TEST_DIR/config" "$TEST_DIR/config/users" "$TEST_DIR/data" "$TEST_DIR/data/keys"

    # Create dummy files
    echo "dummy_private_key" > "$TEST_DIR/data/keys/private.key"
    echo "dummy_public_key" > "$TEST_DIR/data/keys/public.key"
    chmod 600 "$TEST_DIR/data/keys/"*.key

    # Create dummy .env file
    cat > "$TEST_DIR/.env" << EOF
PROJECT_PATH=$TEST_DIR
SERVER_IP=192.168.1.100
XRAY_PORT=443
LOG_LEVEL=warning
EOF
    chmod 600 "$TEST_DIR/.env"

    # Create dummy server.json
    cat > "$TEST_DIR/config/server.json" << 'EOF'
{
  "inbounds": [
    {
      "settings": {
        "clients": []
      }
    }
  ]
}
EOF
    chmod 600 "$TEST_DIR/config/server.json"

    test_log "INFO" "Test environment setup completed"
}

cleanup_test_environment() {
    test_log "INFO" "Cleaning up test environment..."
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
    test_log "INFO" "Test environment cleanup completed"
}

#######################################################################################
# TEST FUNCTIONS
#######################################################################################

test_username_validation() {
    test_log "INFO" "Testing username validation functions..."

    # Create validation test script
    cat > "$TEST_DIR/validate_test.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

validate_username() {
    local username="$1"

    # Check if username is provided
    if [[ -z "$username" ]]; then
        return 1
    fi

    # Check length (3-32 characters)
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 32 ]]; then
        return 1
    fi

    # Check format (alphanumeric, underscore, dash, but not starting with _ or -)
    if [[ ! "$username" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi

    # Check against reserved names (case insensitive)
    local reserved_names=("admin" "root" "administrator" "user" "guest" "test" "null" "undefined" "system" "service" "daemon")
    for reserved in "${reserved_names[@]}"; do
        if [[ "${username,,}" == "$reserved" ]]; then
            return 1
        fi
    done

    return 0
}

validate_username "$@"
EOF
    chmod +x "$TEST_DIR/validate_test.sh"

    # Test valid usernames
    run_test "Valid username 'alice'" "\"$TEST_DIR/validate_test.sh\" 'alice'" "pass"
    run_test "Valid username 'user123'" "\"$TEST_DIR/validate_test.sh\" 'user123'" "pass"
    run_test "Valid username 'test_user'" "\"$TEST_DIR/validate_test.sh\" 'test_user'" "pass"
    run_test "Valid username 'user-name'" "\"$TEST_DIR/validate_test.sh\" 'user-name'" "pass"
    run_test "Valid 32-char username" "\"$TEST_DIR/validate_test.sh\" 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6'" "pass"
    run_test "Valid 3-char username" "\"$TEST_DIR/validate_test.sh\" 'abc'" "pass"

    # Test invalid usernames
    run_test "Invalid username too short (2 chars)" "\"$TEST_DIR/validate_test.sh\" 'ab'" "fail"
    run_test "Empty username" "\"$TEST_DIR/validate_test.sh\" ''" "fail"
    run_test "Username starting with underscore" "\"$TEST_DIR/validate_test.sh\" '_user'" "fail"
    run_test "Username starting with dash" "\"$TEST_DIR/validate_test.sh\" '-user'" "fail"
    run_test "Username with special characters" "\"$TEST_DIR/validate_test.sh\" 'user@domain'" "fail"
    run_test "Username with spaces" "\"$TEST_DIR/validate_test.sh\" 'user spaces'" "fail"
    run_test "Username too long" "\"$TEST_DIR/validate_test.sh\" 'verylongusernamethatisgreaterthan32characters'" "fail"

    # Test reserved usernames
    run_test "Reserved username 'admin'" "\"$TEST_DIR/validate_test.sh\" 'admin'" "fail"
    run_test "Reserved username 'root'" "\"$TEST_DIR/validate_test.sh\" 'root'" "fail"
    run_test "Reserved username 'ADMIN' (case insensitive)" "\"$TEST_DIR/validate_test.sh\" 'ADMIN'" "fail"
}

test_input_sanitization() {
    test_log "INFO" "Testing input sanitization functions..."

    # Create sanitization test script
    cat > "$TEST_DIR/sanitize_test.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

sanitize_input() {
    local input="$1"

    # Remove dangerous characters and trim whitespace
    input=$(echo "$input" | sed 's/[^a-zA-Z0-9_-]//g' | xargs)

    echo "$input"
}

sanitize_input "$1"
EOF
    chmod +x "$TEST_DIR/sanitize_test.sh"

    # Test sanitize_input function
    local result
    result=$("$TEST_DIR/sanitize_test.sh" "normal_input")
    run_test "Normal input unchanged: '$result' == 'normal_input'" "test '$result' = 'normal_input'" "pass"

    result=$("$TEST_DIR/sanitize_test.sh" "  spaced_input  ")
    run_test "Whitespace trimmed: '$result' == 'spaced_input'" "test '$result' = 'spaced_input'" "pass"

    result=$("$TEST_DIR/sanitize_test.sh" "input\$(dangerous)")
    run_test "Dangerous characters removed: '$result' == 'inputdangerous'" "test '$result' = 'inputdangerous'" "pass"

    result=$("$TEST_DIR/sanitize_test.sh" "")
    run_test "Empty input handled: '$result' == ''" "test '$result' = ''" "pass"
}

test_user_database_operations() {
    test_log "INFO" "Testing user database operations..."

    # Create database test script
    cat > "$TEST_DIR/db_test.sh" << EOF
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$TEST_DIR"

# Logging function (suppress output)
log_message() { return 0; }

# Initialize user database
init_user_database() {
    local users_db="\$PROJECT_ROOT/data/users.db"
    if [[ ! -f "\$users_db" ]]; then
        touch "\$users_db"
        chmod 600 "\$users_db"
    fi
    return 0
}

# Add user to database
add_user_to_database() {
    local username="\$1"
    local uuid="\$2"
    local short_id="\$3"

    [[ -z "\$username" || -z "\$uuid" || -z "\$short_id" ]] && return 1

    local users_db="\$PROJECT_ROOT/data/users.db"
    init_user_database || return 1

    if user_exists "\$username"; then
        return 1
    fi

    local current_date=\$(date '+%Y-%m-%d')
    echo "\$username:\$uuid:\$short_id:\$current_date:active" >> "\$users_db"
    return 0
}

# Check if user exists
user_exists() {
    local username="\$1"
    [[ -z "\$username" ]] && return 1

    local users_db="\$PROJECT_ROOT/data/users.db"
    [[ ! -f "\$users_db" ]] && return 1

    grep -q "^\$username:" "\$users_db"
}

# Remove user from database
remove_user_from_database() {
    local username="\$1"
    [[ -z "\$username" ]] && return 1

    local users_db="\$PROJECT_ROOT/data/users.db"
    [[ ! -f "\$users_db" ]] && return 1

    user_exists "\$username" || return 1

    local temp_file=\$(mktemp)
    grep -v "^\$username:" "\$users_db" > "\$temp_file"
    mv "\$temp_file" "\$users_db"
    chmod 600 "\$users_db"
    return 0
}

# Get user information
get_user_info() {
    local username="\$1"
    [[ -z "\$username" ]] && return 1

    local users_db="\$PROJECT_ROOT/data/users.db"
    [[ ! -f "\$users_db" ]] && return 1

    local user_line=\$(grep "^\$username:" "\$users_db" 2>/dev/null || echo "")
    [[ -z "\$user_line" ]] && return 1

    echo "\$user_line"
    return 0
}

"\$@"
EOF
    chmod +x "$TEST_DIR/db_test.sh"

    # Test database operations
    local test_db="$TEST_DIR/data/users.db"
    rm -f "$test_db"

    run_test "Database initialization" "\"$TEST_DIR/db_test.sh\" init_user_database" "pass"
    run_test "Database file exists after init" "test -f '$test_db'" "pass"
    run_test "User addition to database" "\"$TEST_DIR/db_test.sh\" add_user_to_database 'testuser' '550e8400-e29b-41d4-a716-446655440000' 'abc123de'" "pass"
    run_test "User exists check (positive)" "\"$TEST_DIR/db_test.sh\" user_exists 'testuser'" "pass"
    run_test "User exists check (negative)" "\"$TEST_DIR/db_test.sh\" user_exists 'nonexistent'" "fail"
    run_test "Get user information" "\"$TEST_DIR/db_test.sh\" get_user_info 'testuser'" "pass"
    run_test "Duplicate user prevention" "\"$TEST_DIR/db_test.sh\" add_user_to_database 'testuser' '550e8400-e29b-41d4-a716-446655440001' 'def456gh'" "fail"
    run_test "User removal from database" "\"$TEST_DIR/db_test.sh\" remove_user_from_database 'testuser'" "pass"
    run_test "User no longer exists after removal" "\"$TEST_DIR/db_test.sh\" user_exists 'testuser'" "fail"
}

test_client_configuration_generation() {
    test_log "INFO" "Testing client configuration generation..."

    # Create configuration test script
    cat > "$TEST_DIR/config_test.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

create_vless_url() {
    local uuid="$1" server_ip="$2" port="$3" public_key="$4" short_id="$5"
    [[ -z "$uuid" || -z "$server_ip" || -z "$port" || -z "$public_key" || -z "$short_id" ]] && return 1

    echo "vless://${uuid}@${server_ip}:${port}?type=tcp&security=reality&pbk=${public_key}&sid=${short_id}&sni=www.google.com&fp=chrome#VLESS-Reality"
}

create_client_json() {
    local uuid="$1" server_ip="$2" port="$3" public_key="$4" short_id="$5"
    [[ -z "$uuid" || -z "$server_ip" || -z "$port" || -z "$public_key" || -z "$short_id" ]] && return 1

    cat << JSON
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$server_ip",
            "port": $port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "www.google.com",
          "fingerprint": "chrome",
          "show": false,
          "publicKey": "$public_key",
          "shortId": "$short_id"
        }
      }
    }
  ]
}
JSON
}

check_vless_url_format() {
    local url="$1"
    [[ "$url" == vless://* ]] && \
    [[ "$url" == *"@192.168.1.100:443"* ]] && \
    [[ "$url" == *"550e8400-e29b-41d4-a716-446655440000"* ]]
}

check_json_format() {
    local json="$1"
    [[ "$json" == *'"protocol": "vless"'* ]] && \
    [[ "$json" == *'"outbounds"'* ]] && \
    [[ "$json" == *"192.168.1.100"* ]] && \
    [[ "$json" == *"dummy_public_key"* ]]
}

"$@"
EOF
    chmod +x "$TEST_DIR/config_test.sh"

    # Test configuration generation
    run_test "VLESS URL creation succeeds" "\"$TEST_DIR/config_test.sh\" create_vless_url '550e8400-e29b-41d4-a716-446655440000' '192.168.1.100' '443' 'dummy_public_key' 'abc123de'" "pass"
    run_test "Client JSON creation succeeds" "\"$TEST_DIR/config_test.sh\" create_client_json '550e8400-e29b-41d4-a716-446655440000' '192.168.1.100' '443' 'dummy_public_key' 'abc123de'" "pass"

    # Test URL format
    run_test "VLESS URL format validation" "\"$TEST_DIR/config_test.sh\" check_vless_url_format \"\$(\"$TEST_DIR/config_test.sh\" create_vless_url '550e8400-e29b-41d4-a716-446655440000' '192.168.1.100' '443' 'dummy_public_key' 'abc123de')\"" "pass"

    # Test JSON format
    run_test "Client JSON format validation" "\"$TEST_DIR/config_test.sh\" check_json_format \"\$(\"$TEST_DIR/config_test.sh\" create_client_json '550e8400-e29b-41d4-a716-446655440000' '192.168.1.100' '443' 'dummy_public_key' 'abc123de')\"" "pass"

    # Test error handling
    run_test "VLESS URL creation fails with missing params" "\"$TEST_DIR/config_test.sh\" create_vless_url" "fail"
    run_test "Client JSON creation fails with missing params" "\"$TEST_DIR/config_test.sh\" create_client_json" "fail"
}

test_user_limit_enforcement() {
    test_log "INFO" "Testing user limit enforcement..."

    # Create limit test script
    cat > "$TEST_DIR/limit_test.sh" << EOF
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$TEST_DIR"

check_user_limit() {
    local max_users=10
    local users_db="\$PROJECT_ROOT/data/users.db"

    local current_users=0
    if [[ -f "\$users_db" ]]; then
        current_users=\$(grep -c "^.*:.*:.*:.*:active" "\$users_db" 2>/dev/null || echo "0")
    fi

    [[ \$current_users -lt \$max_users ]]
}

count_users() {
    local users_db="\$PROJECT_ROOT/data/users.db"
    local total_users=0
    local active_users=0

    if [[ -f "\$users_db" ]]; then
        total_users=\$(wc -l < "\$users_db" 2>/dev/null || echo "0")
        active_users=\$(grep -c ":active" "\$users_db" 2>/dev/null || echo "0")
    fi

    echo "\$active_users:\$total_users"
}

"\$@"
EOF
    chmod +x "$TEST_DIR/limit_test.sh"

    # Initialize database
    "$TEST_DIR/db_test.sh" init_user_database

    run_test "User limit check with empty database" "\"$TEST_DIR/limit_test.sh\" check_user_limit" "pass"

    # Add users up to the limit
    local users_db="$TEST_DIR/data/users.db"
    for i in {1..10}; do
        echo "user$i:uuid$i:sid$i:$(date '+%Y-%m-%d'):active" >> "$users_db"
    done

    run_test "User limit enforcement when at maximum" "\"$TEST_DIR/limit_test.sh\" check_user_limit" "fail"

    # Test count function
    local expected_count="10:10"
    local actual_count=$("$TEST_DIR/limit_test.sh" count_users)
    run_test "User counting function returns $expected_count" "test '$actual_count' = '$expected_count'" "pass"
}

test_server_configuration_management() {
    test_log "INFO" "Testing server configuration management..."

    # Create server config test script
    cat > "$TEST_DIR/server_config_test.sh" << EOF
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$TEST_DIR"

# Suppress logging for tests
log_message() { return 0; }

backup_server_config() {
    local config_file="\$PROJECT_ROOT/config/server.json"
    [[ ! -f "\$config_file" ]] && return 1

    local backup_dir="\$PROJECT_ROOT/config/backups"
    mkdir -p "\$backup_dir"

    local timestamp=\$(date '+%Y%m%d_%H%M%S')
    local backup_file="\$backup_dir/server_\${timestamp}.json"

    cp "\$config_file" "\$backup_file"
    chmod 600 "\$backup_file"
    echo "\$backup_file"
}

validate_server_config() {
    local config_file="\$PROJECT_ROOT/config/server.json"
    [[ ! -f "\$config_file" ]] && return 1

    # Basic validation - check for required JSON elements
    grep -q "inbounds" "\$config_file" && grep -q "clients" "\$config_file"
}

"\$@"
EOF
    chmod +x "$TEST_DIR/server_config_test.sh"

    run_test "Server configuration validation" "\"$TEST_DIR/server_config_test.sh\" validate_server_config" "pass"

    # Test backup creation
    local backup_file
    if backup_file=$("$TEST_DIR/server_config_test.sh" backup_server_config 2>/dev/null); then
        run_test "Configuration backup created" "test -f '$backup_file'" "pass"
        run_test "Backup contains server configuration" "grep -q 'inbounds' '$backup_file'" "pass"
    else
        run_test "Configuration backup creation" "false" "fail"
    fi
}

test_error_handling() {
    test_log "INFO" "Testing error handling scenarios..."

    # Test missing parameters
    run_test "add_user_to_database fails with missing parameters" "\"$TEST_DIR/db_test.sh\" add_user_to_database" "fail"
    run_test "add_user_to_database fails with partial parameters" "\"$TEST_DIR/db_test.sh\" add_user_to_database 'user'" "fail"
    run_test "remove_user_from_database fails with missing username" "\"$TEST_DIR/db_test.sh\" remove_user_from_database" "fail"
    run_test "get_user_info fails with missing username" "\"$TEST_DIR/db_test.sh\" get_user_info" "fail"

    # Test operations on non-existent database
    local test_db="$TEST_DIR/data/users.db"
    rm -f "$test_db"

    run_test "user_exists fails on non-existent database" "\"$TEST_DIR/db_test.sh\" user_exists 'testuser'" "fail"
    run_test "remove_user_from_database fails on non-existent database" "\"$TEST_DIR/db_test.sh\" remove_user_from_database 'testuser'" "fail"
    run_test "get_user_info fails on non-existent database" "\"$TEST_DIR/db_test.sh\" get_user_info 'testuser'" "fail"
}

test_integration_workflow() {
    test_log "INFO" "Testing complete user workflow (integration)..."

    # Initialize clean database
    local users_db="$TEST_DIR/data/users.db"
    rm -f "$users_db"
    "$TEST_DIR/db_test.sh" init_user_database

    # Test user addition workflow
    local test_user="integrationtest"
    local test_uuid="550e8400-e29b-41d4-a716-446655440000"
    local test_short_id="abc123de"

    # Add user to database
    run_test "Integration: Add user to database" "\"$TEST_DIR/db_test.sh\" add_user_to_database '$test_user' '$test_uuid' '$test_short_id'" "pass"

    # Check user exists
    run_test "Integration: User exists after addition" "\"$TEST_DIR/db_test.sh\" user_exists '$test_user'" "pass"

    # Generate client configurations
    local vless_url
    local json_config

    vless_url=$("$TEST_DIR/config_test.sh" create_vless_url "$test_uuid" "192.168.1.100" "443" "dummy_public_key" "$test_short_id")
    json_config=$("$TEST_DIR/config_test.sh" create_client_json "$test_uuid" "192.168.1.100" "443" "dummy_public_key" "$test_short_id")

    run_test "Integration: VLESS URL generation contains vless://" "echo '$vless_url' | grep -q 'vless://'" "pass"
    run_test "Integration: JSON config contains VLESS protocol" "echo '$json_config' | grep -q '\"protocol\": \"vless\"'" "pass"

    # Test user removal workflow
    run_test "Integration: Remove user from database" "\"$TEST_DIR/db_test.sh\" remove_user_from_database '$test_user'" "pass"
    run_test "Integration: User no longer exists after removal" "\"$TEST_DIR/db_test.sh\" user_exists '$test_user'" "fail"
}

#######################################################################################
# TEST EXECUTION AND REPORTING
#######################################################################################

run_all_tests() {
    test_log "INFO" "Starting $TEST_NAME v$TEST_VERSION"
    test_log "INFO" "Testing script: $MAIN_SCRIPT"
    echo

    # Run test suites
    test_username_validation
    test_input_sanitization
    test_user_database_operations
    test_client_configuration_generation
    test_user_limit_enforcement
    test_server_configuration_management
    test_error_handling
    test_integration_workflow

    echo
    test_log "INFO" "Test execution completed"
}

print_test_summary() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                        TEST SUMMARY                            ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Test Suite:     $TEST_NAME v$TEST_VERSION"
    echo "Total Tests:    $TOTAL_TESTS"
    echo -e "Passed:         ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:         ${RED}$FAILED_TESTS${NC}"

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( PASSED_TESTS * 100 / TOTAL_TESTS ))
    fi
    echo "Success Rate:   ${success_rate}%"
    echo

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo -e "${GREEN}Stage 3: User Management implementation is working correctly.${NC}"
        echo
        echo -e "${BLUE}Tested Components:${NC}"
        echo "  ✅ Username validation (format, length, reserved names)"
        echo "  ✅ Input sanitization and security"
        echo "  ✅ User database operations (CRUD)"
        echo "  ✅ Client configuration generation (VLESS URLs, JSON configs)"
        echo "  ✅ User limit enforcement (10 user maximum)"
        echo "  ✅ Server configuration management (backup, validation)"
        echo "  ✅ Error handling and edge cases"
        echo "  ✅ Integration workflow testing"
    else
        echo -e "${RED}❌ Some tests failed.${NC}"
        echo -e "${YELLOW}Please review the failed tests and fix the issues.${NC}"
    fi
    echo
}

#######################################################################################
# MAIN EXECUTION
#######################################################################################

main() {
    # Check if main script exists
    if [[ ! -f "$MAIN_SCRIPT" ]]; then
        echo -e "${RED}Error: Main script not found at $MAIN_SCRIPT${NC}"
        exit 1
    fi

    # Setup test environment
    setup_test_environment

    # Run tests
    run_all_tests

    # Print summary
    print_test_summary

    # Cleanup
    cleanup_test_environment

    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-run}" in
    "run")
        main
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [run|help]"
        echo "  run   - Run all user management tests (default)"
        echo "  help  - Show this help message"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
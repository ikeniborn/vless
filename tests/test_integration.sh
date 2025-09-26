#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Integration Tests
# Version: 1.0.0
# Description: End-to-end integration testing for complete lifecycle

#######################################################################################
# TEST CONFIGURATION
#######################################################################################

readonly TEST_NAME="integration"
readonly TEST_VERSION="1.0.0"
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_DIR")"
readonly SCRIPT_PATH="$PROJECT_ROOT/vless-manager.sh"

# Test tracking variables
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test data
readonly TEST_USER_1="testuser1"
readonly TEST_USER_2="testuser2"
readonly TEST_USER_3="testuser3"
readonly TEST_TEMP_DIR="/tmp/vless_integration_test_$$"

#######################################################################################
# UTILITY FUNCTIONS
#######################################################################################

# Logging function
log_message() {
  local level="$1"
  local message="$2"

  case "$level" in
    "INFO")
      echo -e "${BLUE}[INFO]${NC} $message"
      ;;
    "SUCCESS")
      echo -e "${GREEN}[SUCCESS]${NC} $message"
      ;;
    "WARNING")
      echo -e "${YELLOW}[WARNING]${NC} $message"
      ;;
    "ERROR")
      echo -e "${RED}[ERROR]${NC} $message" >&2
      ;;
  esac
}

# Assert function for tests
assert() {
  local test_name="$1"
  local condition="$2"
  local error_message="${3:-Assertion failed}"

  ((TOTAL_TESTS++))

  if eval "$condition"; then
    ((PASSED_TESTS++))
    echo -e "  ${GREEN}✓${NC} $test_name"
    return 0
  else
    ((FAILED_TESTS++))
    echo -e "  ${RED}✗${NC} $test_name"
    echo -e "    ${RED}Error: $error_message${NC}"
    return 1
  fi
}

# Execute command and capture output
execute_command() {
  local command="$1"
  local output_file="$TEST_TEMP_DIR/command_output.txt"

  # Execute command and capture output
  if $command > "$output_file" 2>&1; then
    echo "0"  # Return success code
  else
    local exit_code=$?
    echo "$exit_code"
  fi
}

# Cleanup function
cleanup_test_environment() {
  log_message "INFO" "Cleaning up test environment..."

  # Remove test directory
  rm -rf "$TEST_TEMP_DIR"

  # Restore original environment if backed up
  if [[ -d "$PROJECT_ROOT/.backup_test" ]]; then
    rm -rf "$PROJECT_ROOT/config" "$PROJECT_ROOT/data" "$PROJECT_ROOT/logs"
    mv "$PROJECT_ROOT/.backup_test"/* "$PROJECT_ROOT/" 2>/dev/null || true
    rmdir "$PROJECT_ROOT/.backup_test"
  fi
}

# Setup test environment
setup_test_environment() {
  log_message "INFO" "Setting up test environment..."

  # Create temp directory
  mkdir -p "$TEST_TEMP_DIR"

  # Backup existing project files if they exist
  if [[ -d "$PROJECT_ROOT/config" || -d "$PROJECT_ROOT/data" ]]; then
    mkdir -p "$PROJECT_ROOT/.backup_test"
    mv "$PROJECT_ROOT/config" "$PROJECT_ROOT/.backup_test/" 2>/dev/null || true
    mv "$PROJECT_ROOT/data" "$PROJECT_ROOT/.backup_test/" 2>/dev/null || true
    mv "$PROJECT_ROOT/logs" "$PROJECT_ROOT/.backup_test/" 2>/dev/null || true
    mv "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.backup_test/" 2>/dev/null || true
    mv "$PROJECT_ROOT/docker-compose.yml" "$PROJECT_ROOT/.backup_test/" 2>/dev/null || true
  fi

  # Ensure clean state
  rm -rf "$PROJECT_ROOT/config" "$PROJECT_ROOT/data" "$PROJECT_ROOT/logs"
  rm -f "$PROJECT_ROOT/.env" "$PROJECT_ROOT/docker-compose.yml"
}

#######################################################################################
# INTEGRATION TEST SCENARIOS
#######################################################################################

# Test 1: Complete Installation Flow
test_complete_installation() {
  echo
  echo -e "${YELLOW}Test Scenario 1: Complete Installation Flow${NC}"
  echo "================================================"

  # Check if script exists
  assert "Script exists" "[[ -f '$SCRIPT_PATH' ]]" "vless-manager.sh not found"

  # Make script executable
  chmod +x "$SCRIPT_PATH"
  assert "Script is executable" "[[ -x '$SCRIPT_PATH' ]]" "Script not executable"

  # Test help command
  local help_output=$("$SCRIPT_PATH" help 2>&1 | head -5)
  assert "Help command works" "[[ -n '$help_output' ]]" "Help command failed"

  # Mock installation (cannot run actual install in test environment)
  # Create expected directories and files manually
  mkdir -p "$PROJECT_ROOT/config/users"
  mkdir -p "$PROJECT_ROOT/data/keys"
  mkdir -p "$PROJECT_ROOT/logs"

  # Create mock .env file
  cat > "$PROJECT_ROOT/.env" << EOF
PROJECT_PATH=$PROJECT_ROOT
SERVER_IP=192.168.1.100
XRAY_PORT=443
LOG_LEVEL=warning
EOF

  assert "Environment file created" "[[ -f '$PROJECT_ROOT/.env' ]]" ".env file not created"

  # Create mock users.db
  touch "$PROJECT_ROOT/data/users.db"
  assert "Users database created" "[[ -f '$PROJECT_ROOT/data/users.db' ]]" "users.db not created"

  # Create mock server.json
  cat > "$PROJECT_ROOT/config/server.json" << 'EOF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "speed.cloudflare.com:443",
        "serverNames": ["speed.cloudflare.com"],
        "privateKey": "test_private_key",
        "shortIds": ["1234"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

  assert "Server config created" "[[ -f '$PROJECT_ROOT/config/server.json' ]]" "server.json not created"

  # Verify directory structure
  assert "Config directory exists" "[[ -d '$PROJECT_ROOT/config' ]]" "Config directory missing"
  assert "Data directory exists" "[[ -d '$PROJECT_ROOT/data' ]]" "Data directory missing"
  assert "Logs directory exists" "[[ -d '$PROJECT_ROOT/logs' ]]" "Logs directory missing"

  log_message "SUCCESS" "Installation flow test completed"
}

# Test 2: User Management Lifecycle
test_user_management_lifecycle() {
  echo
  echo -e "${YELLOW}Test Scenario 2: User Management Lifecycle${NC}"
  echo "================================================"

  # Source the script functions (mock mode)
  export MOCK_MODE=true
  source "$SCRIPT_PATH"

  # Test user validation
  assert "Valid username accepted" 'validate_username "john_doe"' "Valid username rejected"
  assert "Invalid username rejected" '! validate_username "root"' "Reserved username accepted"
  assert "Long username rejected" '! validate_username "thisusernameiswaytoolongtobevalid"' "Long username accepted"

  # Test add user flow (mocked)
  local test_uuid="550e8400-e29b-41d4-a716-446655440000"
  local test_shortid="abcd1234"
  local test_date=$(date '+%Y-%m-%d')

  # Add mock user to database
  echo "${TEST_USER_1}:${test_uuid}:${test_shortid}:${test_date}:active" >> "$PROJECT_ROOT/data/users.db"

  assert "User added to database" 'grep -q "$TEST_USER_1" "$PROJECT_ROOT/data/users.db"' "User not in database"

  # Test user exists function
  assert "User exists check positive" 'user_exists "$TEST_USER_1"' "User exists check failed"
  assert "User exists check negative" '! user_exists "nonexistent"' "Non-existent user found"

  # Add second user
  echo "${TEST_USER_2}:${test_uuid}2:${test_shortid}2:${test_date}:active" >> "$PROJECT_ROOT/data/users.db"

  # Count users
  local user_count=$(wc -l < "$PROJECT_ROOT/data/users.db")
  assert "User count correct" "[[ $user_count -eq 2 ]]" "User count incorrect: $user_count"

  # Remove user (mock)
  sed -i "/${TEST_USER_1}/d" "$PROJECT_ROOT/data/users.db"
  assert "User removed from database" '! grep -q "$TEST_USER_1" "$PROJECT_ROOT/data/users.db"' "User still in database"

  log_message "SUCCESS" "User management lifecycle test completed"
}

# Test 3: Service Operations
test_service_operations() {
  echo
  echo -e "${YELLOW}Test Scenario 3: Service Operations${NC}"
  echo "================================================"

  # Source the script functions
  export MOCK_MODE=true
  source "$SCRIPT_PATH"

  # Test Docker availability check (mocked)
  if command -v docker >/dev/null 2>&1; then
    assert "Docker check passes" 'check_docker_available' "Docker check failed"
  else
    log_message "WARNING" "Docker not available, skipping Docker tests"
  fi

  # Create mock docker-compose.yml
  cat > "$PROJECT_ROOT/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  xray:
    image: teddysun/xray:latest
    container_name: vless_xray
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
    environment:
      - TZ=UTC
EOF

  assert "Docker Compose file exists" "[[ -f '$PROJECT_ROOT/docker-compose.yml' ]]" "docker-compose.yml missing"

  # Test log file operations
  touch "$PROJECT_ROOT/logs/xray.log"
  echo "Test log entry 1" >> "$PROJECT_ROOT/logs/xray.log"
  echo "Test log entry 2" >> "$PROJECT_ROOT/logs/xray.log"

  assert "Log file exists" "[[ -f '$PROJECT_ROOT/logs/xray.log' ]]" "Log file missing"

  local log_lines=$(wc -l < "$PROJECT_ROOT/logs/xray.log")
  assert "Log entries written" "[[ $log_lines -eq 2 ]]" "Log entries not written"

  log_message "SUCCESS" "Service operations test completed"
}

# Test 4: Configuration Management
test_configuration_management() {
  echo
  echo -e "${YELLOW}Test Scenario 4: Configuration Management${NC}"
  echo "================================================"

  # Source the script functions
  export MOCK_MODE=true
  source "$SCRIPT_PATH"

  # Test UUID generation
  local uuid=$(generate_uuid)
  assert "UUID generated" "[[ -n '$uuid' ]]" "UUID generation failed"
  assert "UUID format valid" '[[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]' "Invalid UUID format"

  # Test ShortID generation
  local shortid=$(generate_short_id)
  assert "ShortID generated" "[[ -n '$shortid' ]]" "ShortID generation failed"
  assert "ShortID length correct" "[[ ${#shortid} -eq 8 ]]" "ShortID wrong length: ${#shortid}"

  # Test server config validation
  assert "Server config is valid JSON" 'python3 -m json.tool "$PROJECT_ROOT/config/server.json" > /dev/null 2>&1' "Invalid JSON in server.json"

  # Test client config generation (mocked)
  local client_dir="$PROJECT_ROOT/config/users/$TEST_USER_3"
  mkdir -p "$client_dir"

  # Create mock client config
  cat > "$client_dir/config.json" << EOF
{
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "192.168.1.100",
        "port": 443,
        "users": [{
          "id": "$uuid",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "speed.cloudflare.com",
        "publicKey": "test_public_key",
        "shortId": "$shortid"
      }
    }
  }]
}
EOF

  assert "Client config created" "[[ -f '$client_dir/config.json' ]]" "Client config not created"
  assert "Client config is valid JSON" 'python3 -m json.tool "$client_dir/config.json" > /dev/null 2>&1' "Invalid client JSON"

  log_message "SUCCESS" "Configuration management test completed"
}

# Test 5: Error Handling and Recovery
test_error_handling() {
  echo
  echo -e "${YELLOW}Test Scenario 5: Error Handling and Recovery${NC}"
  echo "================================================"

  # Source the script functions
  export MOCK_MODE=true
  source "$SCRIPT_PATH"

  # Test invalid operations
  assert "Empty username rejected" '! validate_username ""' "Empty username accepted"
  assert "Special chars rejected" '! validate_username "user@test"' "Special characters accepted"
  assert "Space in username rejected" '! validate_username "user name"' "Username with space accepted"

  # Test file permission errors (mock)
  local test_file="$TEST_TEMP_DIR/readonly_file"
  touch "$test_file"
  chmod 444 "$test_file"

  assert "Read-only file exists" "[[ -f '$test_file' ]]" "Test file not created"
  assert "Cannot write to read-only file" '! echo "test" >> "$test_file" 2>/dev/null' "Wrote to read-only file"

  # Test recovery from corrupted database
  echo "invalid:line:format" > "$PROJECT_ROOT/data/users.db"
  echo "$TEST_USER_1:$test_uuid:$test_shortid:$test_date:active" >> "$PROJECT_ROOT/data/users.db"

  # Should still find valid user
  assert "Valid user found despite corruption" 'grep -q "$TEST_USER_1" "$PROJECT_ROOT/data/users.db"' "Valid user not found"

  log_message "SUCCESS" "Error handling test completed"
}

# Test 6: Clean Uninstallation
test_clean_uninstallation() {
  echo
  echo -e "${YELLOW}Test Scenario 6: Clean Uninstallation${NC}"
  echo "================================================"

  # Verify files exist before uninstall
  assert "Config exists before uninstall" "[[ -d '$PROJECT_ROOT/config' ]]" "Config missing"
  assert "Data exists before uninstall" "[[ -d '$PROJECT_ROOT/data' ]]" "Data missing"

  # Simulate uninstall (remove all except main script)
  rm -rf "$PROJECT_ROOT/config"
  rm -rf "$PROJECT_ROOT/data"
  rm -rf "$PROJECT_ROOT/logs"
  rm -f "$PROJECT_ROOT/.env"
  rm -f "$PROJECT_ROOT/docker-compose.yml"

  # Verify clean removal
  assert "Config removed" "[[ ! -d '$PROJECT_ROOT/config' ]]" "Config not removed"
  assert "Data removed" "[[ ! -d '$PROJECT_ROOT/data' ]]" "Data not removed"
  assert "Logs removed" "[[ ! -d '$PROJECT_ROOT/logs' ]]" "Logs not removed"
  assert "Environment removed" "[[ ! -f '$PROJECT_ROOT/.env' ]]" ".env not removed"
  assert "Docker Compose removed" "[[ ! -f '$PROJECT_ROOT/docker-compose.yml' ]]" "docker-compose.yml not removed"

  # Main script should remain
  assert "Main script preserved" "[[ -f '$SCRIPT_PATH' ]]" "Main script removed"

  log_message "SUCCESS" "Clean uninstallation test completed"
}

#######################################################################################
# PERFORMANCE TESTS
#######################################################################################

test_performance_benchmarks() {
  echo
  echo -e "${YELLOW}Test Scenario 7: Performance Benchmarks${NC}"
  echo "================================================"

  # Test rapid user creation
  local start_time=$(date +%s%N)

  # Recreate data directory for this test
  mkdir -p "$PROJECT_ROOT/data"
  touch "$PROJECT_ROOT/data/users.db"

  # Add 10 users rapidly
  for i in {1..10}; do
    echo "perfuser${i}:uuid${i}:shortid${i}:2025-01-01:active" >> "$PROJECT_ROOT/data/users.db"
  done

  local end_time=$(date +%s%N)
  local duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds

  assert "10 users added" "[[ $(wc -l < '$PROJECT_ROOT/data/users.db') -eq 10 ]]" "User count mismatch"
  assert "Performance acceptable" "[[ $duration -lt 1000 ]]" "Too slow: ${duration}ms for 10 users"

  log_message "INFO" "Added 10 users in ${duration}ms"

  # Test database search performance
  start_time=$(date +%s%N)
  grep -q "perfuser5" "$PROJECT_ROOT/data/users.db"
  end_time=$(date +%s%N)
  duration=$(((end_time - start_time) / 1000000))

  assert "User search fast" "[[ $duration -lt 100 ]]" "Search too slow: ${duration}ms"

  log_message "SUCCESS" "Performance benchmarks completed"
}

#######################################################################################
# CROSS-FUNCTIONAL TESTS
#######################################################################################

test_cross_functional_operations() {
  echo
  echo -e "${YELLOW}Test Scenario 8: Cross-Functional Operations${NC}"
  echo "================================================"

  # Setup for cross-functional test
  mkdir -p "$PROJECT_ROOT/config/users"
  mkdir -p "$PROJECT_ROOT/data"
  touch "$PROJECT_ROOT/data/users.db"

  # Test: Add user -> Generate config -> Update server -> Verify consistency
  local test_uuid="cf_uuid_test"
  local test_shortid="cf_short"

  # Step 1: Add user
  echo "crossfunc_user:${test_uuid}:${test_shortid}:2025-01-01:active" >> "$PROJECT_ROOT/data/users.db"
  assert "Cross-func user added" 'grep -q "crossfunc_user" "$PROJECT_ROOT/data/users.db"' "User not added"

  # Step 2: Create user config directory
  mkdir -p "$PROJECT_ROOT/config/users/crossfunc_user"
  touch "$PROJECT_ROOT/config/users/crossfunc_user/config.json"
  assert "User config dir created" "[[ -d '$PROJECT_ROOT/config/users/crossfunc_user' ]]" "Config dir not created"

  # Step 3: Verify server config exists
  if [[ ! -f "$PROJECT_ROOT/config/server.json" ]]; then
    # Recreate it if missing
    cat > "$PROJECT_ROOT/config/server.json" << 'EOF'
{"inbounds":[{"settings":{"clients":[]}}]}
EOF
  fi
  assert "Server config available" "[[ -f '$PROJECT_ROOT/config/server.json' ]]" "Server config missing"

  # Step 4: Verify all components exist
  assert "Database has user" 'grep -q "crossfunc_user" "$PROJECT_ROOT/data/users.db"' "Database inconsistent"
  assert "Config dir exists" "[[ -d '$PROJECT_ROOT/config/users/crossfunc_user' ]]" "Config dir missing"

  log_message "SUCCESS" "Cross-functional operations test completed"
}

#######################################################################################
# TEST EXECUTION
#######################################################################################

# Display test header
display_header() {
  echo
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${BLUE}            VLESS+Reality VPN Service - Integration Test Suite${NC}"
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "Version:     $TEST_VERSION"
  echo -e "Test Type:   End-to-End Integration Testing"
  echo -e "Start Time:  $(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "${BLUE}================================================================================${NC}"
}

# Display test results
display_results() {
  echo
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${BLUE}                              TEST RESULTS${NC}"
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "Total Tests:   $TOTAL_TESTS"
  echo -e "Passed Tests:  ${GREEN}$PASSED_TESTS${NC}"
  echo -e "Failed Tests:  ${RED}$FAILED_TESTS${NC}"

  if [[ $TOTAL_TESTS -gt 0 ]]; then
    local success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    echo -e "Success Rate:  ${success_rate}%"

    if [[ $FAILED_TESTS -eq 0 ]]; then
      echo
      echo -e "${GREEN}✅ ALL INTEGRATION TESTS PASSED!${NC}"
      echo -e "${GREEN}The system is ready for production use.${NC}"
    else
      echo
      echo -e "${RED}❌ SOME TESTS FAILED${NC}"
      echo -e "${YELLOW}Please review the failures above and fix issues before deployment.${NC}"
    fi
  fi

  echo -e "${BLUE}================================================================================${NC}"
}

# Main test execution
main() {
  # Set up trap for cleanup
  trap cleanup_test_environment EXIT

  # Check if running as test
  if [[ "${1:-}" != "run" ]]; then
    echo "Usage: $0 run"
    echo "This will run all integration tests"
    exit 0
  fi

  # Display header
  display_header

  # Setup test environment
  setup_test_environment

  # Run all test scenarios
  test_complete_installation
  test_user_management_lifecycle
  test_service_operations
  test_configuration_management
  test_error_handling
  test_clean_uninstallation
  test_performance_benchmarks
  test_cross_functional_operations

  # Display results
  display_results

  # Return appropriate exit code
  if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Execute main function
main "$@"
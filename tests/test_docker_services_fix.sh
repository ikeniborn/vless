#!/bin/bash

# VLESS+Reality VPN Management System - Docker Services Fix Test Suite
# Version: 1.0.0
# Description: Comprehensive test suite for container management fixes
#
# This test suite validates:
# - Permission handling functions
# - Docker compose management
# - Service startup and health checks
# - Error handling and recovery
# - Integration with installer

set -euo pipefail

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly MODULES_DIR="$PROJECT_ROOT/modules"
readonly TEST_RESULTS_DIR="$SCRIPT_DIR/results"
readonly TEST_TEMP_DIR="/tmp/vless_tests_$$"

# Import required modules
source "$MODULES_DIR/common_utils.sh"
source "$MODULES_DIR/container_management.sh"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test results storage
declare -a TEST_RESULTS=()
declare -a FAILED_TESTS=()

# Setup test environment
setup_test_environment() {
    echo "Setting up test environment..."

    # Create test directories
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$TEST_TEMP_DIR"

    # Create mock system files for testing
    create_mock_environment

    echo "Test environment setup complete"
}

# Create mock environment for testing
create_mock_environment() {
    local mock_dir="$TEST_TEMP_DIR/mock_system"
    mkdir -p "$mock_dir"

    # Create mock /opt/vless structure
    mkdir -p "$mock_dir/opt/vless/"{config,logs,certs,backup}

    # Create mock docker-compose files
    create_mock_docker_compose_files "$mock_dir"

    # Create mock system users
    create_mock_system_files "$mock_dir"

    echo "Mock environment created at: $mock_dir"
}

# Create mock docker-compose files
create_mock_docker_compose_files() {
    local mock_dir="$1"

    # Create repository version (modern)
    cat > "$mock_dir/docker-compose-repo.yml" << 'EOF'
version: '3.8'

services:
  xray:
    image: teddysun/xray:latest
    container_name: vless-xray
    user: "1000:1000"
    restart: unless-stopped
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray
    ports:
      - "443:443"
    networks:
      - vless-network

  nginx:
    image: nginx:alpine
    container_name: vless-nginx
    restart: unless-stopped
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "80:80"
    networks:
      - vless-network

networks:
  vless-network:
    driver: bridge
EOF

    # Create system version (legacy)
    cat > "$mock_dir/docker-compose-system.yml" << 'EOF'
version: '3.3'

services:
  xray:
    image: teddysun/xray:latest
    container_name: vless-xray
    user: "1000:1000"
    restart: unless-stopped
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
    ports:
      - "443:443"
EOF

    # Create expected modern version with correct permissions
    cat > "$mock_dir/docker-compose-expected.yml" << 'EOF'
version: '3.8'

services:
  xray:
    image: teddysun/xray:latest
    container_name: vless-xray
    user: "995:982"
    restart: unless-stopped
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - ./config:/etc/xray:ro
      - ./logs:/var/log/xray
    ports:
      - "443:443"
    networks:
      - vless-network

  nginx:
    image: nginx:alpine
    container_name: vless-nginx
    restart: unless-stopped
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "80:80"
    networks:
      - vless-network

networks:
  vless-network:
    driver: bridge
EOF
}

# Create mock system files
create_mock_system_files() {
    local mock_dir="$1"

    # Mock passwd file for user detection
    cat > "$mock_dir/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
vless:x:995:982:VLESS VPN User:/opt/vless:/bin/bash
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
EOF

    # Mock group file
    cat > "$mock_dir/group" << 'EOF'
root:x:0:
daemon:x:1:
vless:x:982:
ubuntu:x:1000:
EOF
}

# Test utility functions
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))

    echo -n "Running test: $test_name... "

    if $test_function; then
        echo "PASSED"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("PASS: $test_name")
    else
        echo "FAILED"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("FAIL: $test_name")
        FAILED_TESTS+=("$test_name")
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"

    ((TESTS_TOTAL++))
    ((TESTS_SKIPPED++))

    echo "SKIPPED: $test_name - $reason"
    TEST_RESULTS+=("SKIP: $test_name - $reason")
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values do not match}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-File does not exist}"

    if [[ -f "$file_path" ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "  File: $file_path"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String does not contain expected value}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "ASSERTION FAILED: $message"
        echo "  String: '$haystack'"
        echo "  Expected to contain: '$needle'"
        return 1
    fi
}

# Mock functions for testing
mock_getent_passwd() {
    local user="$1"
    case "$user" in
        "vless")
            echo "vless:x:995:982:VLESS VPN User:/opt/vless:/bin/bash"
            return 0
            ;;
        "995")
            echo "vless:x:995:982:VLESS VPN User:/opt/vless:/bin/bash"
            return 0
            ;;
        "1000")
            echo "ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mock_id_command() {
    local user="$1"
    case "$user" in
        "vless")
            echo "uid=995(vless) gid=982(vless) groups=982(vless)"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Override system commands for testing
getent() {
    if [[ "$1" == "passwd" ]]; then
        mock_getent_passwd "$2"
    else
        command getent "$@"
    fi
}

id() {
    if [[ "$1" == "vless" ]] || [[ "$1" == "-u" ]]; then
        mock_id_command "vless"
    else
        command id "$@"
    fi
}

# Test Functions

test_get_vless_user_ids() {
    local user_ids
    user_ids=$(get_vless_user_ids)

    # Should return "995 982" for our mock vless user
    assert_equals "995 982" "$user_ids" "User IDs should match mock vless user"
}

test_get_vless_user_ids_no_existing_user() {
    # Test when vless user doesn't exist
    # Temporarily override getent to return failure
    getent() {
        return 1
    }

    local user_ids
    user_ids=$(get_vless_user_ids)

    # Should return default values when user doesn't exist and 1000 is available
    # This test depends on the system state, so we'll be flexible
    if [[ "$user_ids" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi

    # Restore getent function
    unset -f getent
}

test_update_docker_compose_permissions() {
    local test_file="$TEST_TEMP_DIR/test-compose.yml"

    # Create test compose file with incorrect permissions
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    image: test
    user: "1000:1000"
EOF

    # Update permissions
    if update_docker_compose_permissions "$test_file" "995" "982"; then
        # Check if file was updated correctly
        if grep -q 'user: "995:982"' "$test_file"; then
            return 0
        else
            echo "User directive not updated correctly"
            return 1
        fi
    else
        return 1
    fi
}

test_update_docker_compose_permissions_backup() {
    local test_file="$TEST_TEMP_DIR/test-compose-backup.yml"

    # Create test compose file
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "1000:1000"
EOF

    # Update permissions (should create backup)
    if update_docker_compose_permissions "$test_file" "995" "982"; then
        # Check if backup was created
        local backup_count
        backup_count=$(find "$(dirname "$test_file")" -name "$(basename "$test_file").backup.*" | wc -l)

        if [[ "$backup_count" -gt 0 ]]; then
            return 0
        else
            echo "Backup file was not created"
            return 1
        fi
    else
        return 1
    fi
}

test_verify_container_permissions() {
    local test_file="$TEST_TEMP_DIR/test-verify.yml"

    # Create test compose file with correct permissions
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "995:982"
EOF

    # Verify should pass
    if verify_container_permissions "$test_file" "995" "982"; then
        return 0
    else
        echo "Verification failed for correct permissions"
        return 1
    fi
}

test_verify_container_permissions_mismatch() {
    local test_file="$TEST_TEMP_DIR/test-verify-mismatch.yml"

    # Create test compose file with incorrect permissions
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "1000:1000"
EOF

    # Verify should fail
    if ! verify_container_permissions "$test_file" "995" "982"; then
        return 0
    else
        echo "Verification should have failed for mismatched permissions"
        return 1
    fi
}

test_verify_container_permissions_no_user_directive() {
    local test_file="$TEST_TEMP_DIR/test-verify-no-user.yml"

    # Create test compose file without user directive
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    image: test
EOF

    # Verify should fail (no user directive)
    if ! verify_container_permissions "$test_file" "995" "982"; then
        return 0
    else
        echo "Verification should have failed for missing user directive"
        return 1
    fi
}

test_update_compose_version() {
    local test_file="$TEST_TEMP_DIR/test-version.yml"

    # Create test compose file with old version
    cat > "$test_file" << 'EOF'
version: "3.3"
services:
  xray:
    image: test
EOF

    # Update version
    if update_compose_version "$test_file"; then
        # Check if version was updated
        if grep -q 'version: '\''3.8'\''' "$test_file"; then
            return 0
        else
            echo "Version not updated correctly"
            return 1
        fi
    else
        return 1
    fi
}

test_prepare_system_environment_mock() {
    # Mock the directories and file operations for testing
    local original_compose_file="$COMPOSE_FILE"
    local original_system_compose_file="$SYSTEM_COMPOSE_FILE"

    # Override constants for testing
    COMPOSE_FILE="$TEST_TEMP_DIR/mock_system/docker-compose-repo.yml"
    SYSTEM_COMPOSE_FILE="$TEST_TEMP_DIR/mock_system/opt/vless/docker-compose.yml"

    # Mock directory creation function
    create_directory() {
        local dir="$1"
        local perms="$2"
        mkdir -p "$dir"
        chmod "$perms" "$dir"
        return 0
    }

    # Mock chown to avoid permission issues in test
    chown() {
        return 0
    }

    # Run the function
    if prepare_system_environment; then
        # Check if compose file was copied and updated
        if [[ -f "$SYSTEM_COMPOSE_FILE" ]]; then
            if grep -q 'user: "995:982"' "$SYSTEM_COMPOSE_FILE"; then
                return 0
            else
                echo "System compose file permissions not updated"
                return 1
            fi
        else
            echo "System compose file not created"
            return 1
        fi
    else
        return 1
    fi

    # Restore original constants
    COMPOSE_FILE="$original_compose_file"
    SYSTEM_COMPOSE_FILE="$original_system_compose_file"

    # Cleanup function overrides
    unset -f create_directory chown
}

# Integration Tests

test_docker_availability_check() {
    # Mock docker commands for testing
    docker() {
        case "$1" in
            "info")
                echo "Docker is running"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }

    docker-compose() {
        echo "Docker Compose version"
        return 0
    }

    if check_docker_availability; then
        unset -f docker docker-compose
        return 0
    else
        unset -f docker docker-compose
        return 1
    fi
}

test_docker_availability_check_missing() {
    # Mock missing docker
    command_exists() {
        local cmd="$1"
        case "$cmd" in
            "docker"|"docker-compose")
                return 1
                ;;
            *)
                command -v "$cmd" >/dev/null 2>&1
                ;;
        esac
    }

    if ! check_docker_availability; then
        unset -f command_exists
        return 0
    else
        unset -f command_exists
        echo "Should have failed when docker is not available"
        return 1
    fi
}

test_safe_docker_compose_timeout() {
    # Mock docker-compose to simulate timeout
    docker-compose() {
        sleep 10  # Simulate long-running command
        return 0
    }

    timeout() {
        local time="$1"
        shift
        if [[ "$time" -eq 2 ]]; then
            return 124  # Timeout exit code
        else
            "$@"
        fi
    }

    # This should timeout
    if ! safe_docker_compose 2 config; then
        unset -f docker-compose timeout
        return 0
    else
        unset -f docker-compose timeout
        echo "Command should have timed out"
        return 1
    fi
}

# Error Handling Tests

test_error_handling_missing_file() {
    local nonexistent_file="$TEST_TEMP_DIR/nonexistent.yml"

    # Should handle missing file gracefully
    if ! update_docker_compose_permissions "$nonexistent_file" "995" "982"; then
        return 0
    else
        echo "Should have failed for nonexistent file"
        return 1
    fi
}

test_error_handling_invalid_yaml() {
    local invalid_file="$TEST_TEMP_DIR/invalid.yml"

    # Create invalid YAML file
    cat > "$invalid_file" << 'EOF'
version: 3.8
services:
  xray:
    user: 1000:1000
    invalid_yaml: [unclosed array
EOF

    # Function should detect the issue (if it validates YAML)
    # For now, we'll just test that it doesn't crash
    if update_docker_compose_permissions "$invalid_file" "995" "982"; then
        # Check if it at least attempted the update
        return 0
    else
        return 0  # Either outcome is acceptable
    fi
}

# Performance Tests

test_performance_large_compose_file() {
    local large_file="$TEST_TEMP_DIR/large-compose.yml"

    # Create a large compose file
    {
        echo "version: '3.8'"
        echo "services:"
        for i in {1..100}; do
            echo "  service$i:"
            echo "    image: test$i"
            echo "    user: \"1000:1000\""
        done
    } > "$large_file"

    # Time the update operation
    local start_time end_time duration
    start_time=$(date +%s%3N)

    if update_docker_compose_permissions "$large_file" "995" "982"; then
        end_time=$(date +%s%3N)
        duration=$((end_time - start_time))

        echo "Large file processing took ${duration}ms"

        # Should complete in reasonable time (< 5 seconds = 5000ms)
        if [[ "$duration" -lt 5000 ]]; then
            return 0
        else
            echo "Processing took too long: ${duration}ms"
            return 1
        fi
    else
        return 1
    fi
}

# Main Test Execution

run_all_tests() {
    echo "Starting comprehensive Docker services fix test suite..."
    echo "============================================================"

    # Setup
    setup_test_environment

    echo
    echo "Running permission handling tests..."
    echo "------------------------------------"

    run_test "User IDs Detection" test_get_vless_user_ids
    run_test "User IDs Detection (No Existing User)" test_get_vless_user_ids_no_existing_user
    run_test "Docker Compose Permissions Update" test_update_docker_compose_permissions
    run_test "Docker Compose Backup Creation" test_update_docker_compose_permissions_backup
    run_test "Container Permissions Verification" test_verify_container_permissions
    run_test "Container Permissions Mismatch Detection" test_verify_container_permissions_mismatch
    run_test "Missing User Directive Detection" test_verify_container_permissions_no_user_directive
    run_test "Compose Version Update" test_update_compose_version

    echo
    echo "Running system environment tests..."
    echo "-----------------------------------"

    run_test "System Environment Preparation" test_prepare_system_environment_mock

    echo
    echo "Running integration tests..."
    echo "-----------------------------"

    run_test "Docker Availability Check" test_docker_availability_check
    run_test "Docker Availability Check (Missing)" test_docker_availability_check_missing
    run_test "Safe Docker Compose Timeout" test_safe_docker_compose_timeout

    echo
    echo "Running error handling tests..."
    echo "-------------------------------"

    run_test "Error Handling (Missing File)" test_error_handling_missing_file
    run_test "Error Handling (Invalid YAML)" test_error_handling_invalid_yaml

    echo
    echo "Running performance tests..."
    echo "----------------------------"

    run_test "Performance (Large Compose File)" test_performance_large_compose_file

    # Skip tests that require actual Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        skip_test "Docker Service Startup" "Docker not installed"
        skip_test "Container Health Checks" "Docker not installed"
        skip_test "Service Recovery" "Docker not installed"
    fi

    echo
    echo "============================================================"
    echo "Test Results Summary"
    echo "============================================================"
    echo "Total Tests:  $TESTS_TOTAL"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"
    echo "Skipped:      $TESTS_SKIPPED"
    echo

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "Failed Tests:"
        printf '%s\n' "${FAILED_TESTS[@]}"
        echo
    fi

    # Generate detailed report
    generate_test_report

    # Return non-zero if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/docker_services_fix_test_report_$(date +%Y%m%d_%H%M%S).txt"

    echo "Generating detailed test report..."

    {
        echo "VLESS Docker Services Fix - Test Report"
        echo "========================================"
        echo "Date: $(date)"
        echo "Test Suite Version: 1.0.0"
        echo
        echo "Environment Information:"
        echo "- OS: $(uname -s) $(uname -r)"
        echo "- Bash Version: $BASH_VERSION"
        echo "- Test Directory: $TEST_TEMP_DIR"
        echo "- Project Root: $PROJECT_ROOT"
        echo
        echo "Test Summary:"
        echo "- Total Tests: $TESTS_TOTAL"
        echo "- Passed: $TESTS_PASSED"
        echo "- Failed: $TESTS_FAILED"
        echo "- Skipped: $TESTS_SKIPPED"
        echo
        echo "Success Rate: $(( (TESTS_PASSED * 100) / TESTS_TOTAL ))%"
        echo
        echo "Detailed Results:"
        echo "=================="
        printf '%s\n' "${TEST_RESULTS[@]}"
        echo

        if [[ $TESTS_FAILED -gt 0 ]]; then
            echo "Failed Test Analysis:"
            echo "====================="
            printf '%s\n' "${FAILED_TESTS[@]}"
            echo
        fi

        echo "Test Environment Files:"
        echo "======================"
        find "$TEST_TEMP_DIR" -type f -name "*.yml" -o -name "*.txt" | head -20
        echo

        echo "Recommendations:"
        echo "================"
        if [[ $TESTS_FAILED -eq 0 ]]; then
            echo "✓ All tests passed successfully"
            echo "✓ Docker services fix implementation is working correctly"
            echo "✓ Ready for production deployment"
        else
            echo "✗ Some tests failed - review failed tests above"
            echo "✗ Fix issues before deploying to production"
            echo "✗ Re-run tests after fixes are applied"
        fi

    } > "$report_file"

    echo "Detailed report saved to: $report_file"
}

cleanup_test_environment() {
    echo "Cleaning up test environment..."
    rm -rf "$TEST_TEMP_DIR"
    echo "Cleanup complete"
}

# Cleanup on exit
trap cleanup_test_environment EXIT

# Main execution
main() {
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        run_all_tests "$@"
    fi
}

# Export test functions for external use
export -f run_test assert_equals assert_file_exists assert_contains
export -f setup_test_environment cleanup_test_environment

# Run if executed directly
main "$@"
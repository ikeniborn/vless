#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Directory Structure and Permissions Test Suite
# Version: 1.0.0
# Description: Comprehensive testing for project structure creation and file permissions
# Author: VLESS Testing Team

#######################################################################################
# TEST CONSTANTS AND CONFIGURATION
#######################################################################################

readonly TEST_SCRIPT_NAME="test_structure"
readonly TEST_VERSION="1.0.0"
readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_ROOT")"
readonly VLESS_MANAGER="$PROJECT_ROOT/vless-manager.sh"

# Test results tracking
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -a FAILED_TEST_NAMES=()

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Expected directory structure
declare -A EXPECTED_DIRS=(
    ["config"]="700"
    ["config/users"]="700"
    ["data"]="700"
    ["data/keys"]="700"
    ["logs"]="755"
)

# Expected files
declare -A EXPECTED_FILES=(
    ["data/users.db"]="600"
    ["logs/xray.log"]="644"
    [".env"]="600"
)

#######################################################################################
# TEST UTILITY FUNCTIONS
#######################################################################################

# Test logging function
test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${BLUE}[STRUCT-INFO]${NC} ${timestamp} - $message"
            ;;
        "PASS")
            echo -e "${GREEN}[STRUCT-PASS]${NC} ${timestamp} - $message"
            ;;
        "FAIL")
            echo -e "${RED}[STRUCT-FAIL]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[STRUCT-WARN]${NC} ${timestamp} - $message"
            ;;
    esac
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-Assertion}"

    ((TOTAL_TESTS++))

    if [[ "$expected" == "$actual" ]]; then
        test_log "PASS" "$test_name: Expected '$expected', got '$actual'"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Expected '$expected', got '$actual'"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_return_code() {
    local expected_code="$1"
    local actual_code="$2"
    local test_name="${3:-Return Code}"

    ((TOTAL_TESTS++))

    if [[ "$expected_code" == "$actual_code" ]]; then
        test_log "PASS" "$test_name: Expected return code $expected_code"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Expected return code $expected_code, got $actual_code"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_directory_exists() {
    local dir_path="$1"
    local test_name="${2:-Directory Existence}"

    ((TOTAL_TESTS++))

    if [[ -d "$dir_path" ]]; then
        test_log "PASS" "$test_name: Directory '$dir_path' exists"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Directory '$dir_path' does not exist"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="${2:-File Existence}"

    ((TOTAL_TESTS++))

    if [[ -f "$file_path" ]]; then
        test_log "PASS" "$test_name: File '$file_path' exists"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: File '$file_path' does not exist"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_permissions() {
    local path="$1"
    local expected_perms="$2"
    local test_name="${3:-Permissions}"

    ((TOTAL_TESTS++))

    if [[ ! -e "$path" ]]; then
        test_log "FAIL" "$test_name: Path '$path' does not exist"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi

    local actual_perms
    actual_perms=$(stat -c %a "$path" 2>/dev/null || stat -f %A "$path" 2>/dev/null || echo "unknown")

    if [[ "$expected_perms" == "$actual_perms" ]]; then
        test_log "PASS" "$test_name: '$path' has correct permissions $expected_perms"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: '$path' has permissions $actual_perms, expected $expected_perms"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_file_content_contains() {
    local file_path="$1"
    local expected_content="$2"
    local test_name="${3:-File Content}"

    ((TOTAL_TESTS++))

    if [[ ! -f "$file_path" ]]; then
        test_log "FAIL" "$test_name: File '$file_path' does not exist"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi

    if grep -q "$expected_content" "$file_path"; then
        test_log "PASS" "$test_name: File '$file_path' contains expected content"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: File '$file_path' does not contain '$expected_content'"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

#######################################################################################
# DIRECTORY STRUCTURE TESTS
#######################################################################################

test_create_directories_fresh() {
    test_log "INFO" "Testing directory creation in fresh environment"

    # Create temporary test directory
    local test_dir="/tmp/vless_struct_test_$$"
    mkdir -p "$test_dir"

    # Test script that uses temporary directory as PROJECT_ROOT
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

# Mock curl to return test IP
curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "203.0.113.1"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"
create_directories
EOF
    chmod +x "$test_script"

    # Execute the test
    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    # Verify return code
    assert_return_code "0" "$return_code" "create_directories return code"

    # Verify all expected directories exist
    for dir_rel in "${!EXPECTED_DIRS[@]}"; do
        local dir_full="$test_dir/$dir_rel"
        assert_directory_exists "$dir_full" "Directory creation: $dir_rel"
    done

    # Verify directory permissions
    for dir_rel in "${!EXPECTED_DIRS[@]}"; do
        local dir_full="$test_dir/$dir_rel"
        local expected_perms="${EXPECTED_DIRS[$dir_rel]}"
        assert_permissions "$dir_full" "$expected_perms" "Directory permissions: $dir_rel"
    done

    # Verify expected files exist
    local users_db="$test_dir/data/users.db"
    local log_file="$test_dir/logs/xray.log"

    assert_file_exists "$users_db" "Users database file"
    assert_file_exists "$log_file" "Log file"

    # Verify file permissions
    assert_permissions "$users_db" "600" "Users database permissions"
    assert_permissions "$log_file" "644" "Log file permissions"

    # Cleanup
    rm -rf "$test_dir"
}

test_create_directories_existing() {
    test_log "INFO" "Testing directory creation with existing directories"

    local test_dir="/tmp/vless_existing_test_$$"
    mkdir -p "$test_dir"

    # Pre-create some directories with different permissions
    mkdir -p "$test_dir/config"
    mkdir -p "$test_dir/data"
    chmod 755 "$test_dir/config"  # Wrong permissions initially
    chmod 755 "$test_dir/data"

    # Create test script
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "203.0.113.1"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"
create_directories
EOF
    chmod +x "$test_script"

    # Execute the test
    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "create_directories with existing dirs"

    # Verify permissions were corrected
    assert_permissions "$test_dir/config" "700" "Existing config directory permissions corrected"
    assert_permissions "$test_dir/data" "700" "Existing data directory permissions corrected"

    # Verify all directories still exist
    for dir_rel in "${!EXPECTED_DIRS[@]}"; do
        local dir_full="$test_dir/$dir_rel"
        assert_directory_exists "$dir_full" "Existing directory preserved: $dir_rel"
    done

    # Cleanup
    rm -rf "$test_dir"
}

test_create_directories_permission_failure() {
    test_log "INFO" "Testing directory creation with permission failures"

    # Create a directory we don't have write access to
    local test_dir="/tmp/vless_noperm_test_$$"
    local restricted_dir="/tmp/vless_restricted_$$"

    mkdir -p "$restricted_dir"
    chmod 444 "$restricted_dir"  # Read-only

    # Test script that tries to create subdirectory in read-only directory
    local test_script="/tmp/test_perm_script_$$.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$restricted_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "203.0.113.1"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"
create_directories 2>&1
EOF
    chmod +x "$test_script"

    # Execute the test (should fail)
    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    # Should fail due to permission denied
    assert_return_code "1" "$return_code" "create_directories permission failure"

    # Cleanup
    chmod 755 "$restricted_dir"  # Restore permissions for cleanup
    rm -rf "$restricted_dir" "$test_script"
}

#######################################################################################
# ENVIRONMENT FILE TESTS
#######################################################################################

test_create_env_file_fresh() {
    test_log "INFO" "Testing environment file creation in fresh environment"

    local test_dir="/tmp/vless_env_test_$$"
    mkdir -p "$test_dir"

    # Mock curl to return test IP
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "192.0.2.100"
    elif [[ "\$@" =~ "ipify.org" ]]; then
        echo "192.0.2.100"
    elif [[ "\$@" =~ "ifconfig.me" ]]; then
        echo "192.0.2.100"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"
create_env_file
EOF
    chmod +x "$test_script"

    # Execute the test
    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "create_env_file return code"

    local env_file="$test_dir/.env"
    assert_file_exists "$env_file" "Environment file created"
    assert_permissions "$env_file" "600" "Environment file permissions"

    # Verify environment file content
    assert_file_content_contains "$env_file" "PROJECT_PATH=$test_dir" "PROJECT_PATH in .env"
    assert_file_content_contains "$env_file" "SERVER_IP=192.0.2.100" "SERVER_IP in .env"
    assert_file_content_contains "$env_file" "XRAY_PORT=443" "XRAY_PORT in .env"
    assert_file_content_contains "$env_file" "REALITY_DEST=speed.cloudflare.com:443" "REALITY_DEST in .env"
    assert_file_content_contains "$env_file" "LOG_LEVEL=warning" "LOG_LEVEL in .env"
    assert_file_content_contains "$env_file" "USERS_DB=$test_dir/data/users.db" "USERS_DB in .env"

    # Cleanup
    rm -rf "$test_dir"
}

test_create_env_file_existing() {
    test_log "INFO" "Testing environment file creation with existing file"

    local test_dir="/tmp/vless_env_existing_$$"
    mkdir -p "$test_dir"

    # Create existing .env file
    local env_file="$test_dir/.env"
    cat > "$env_file" << EOF
# Existing configuration
SERVER_IP=10.0.0.1
CUSTOM_SETTING=value
EOF

    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "192.0.2.200"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"
create_env_file
EOF
    chmod +x "$test_script"

    # Execute the test
    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "create_env_file with existing file"

    # Verify file was overwritten with new content
    assert_file_content_contains "$env_file" "SERVER_IP=192.0.2.200" "Updated SERVER_IP in .env"
    assert_file_content_contains "$env_file" "PROJECT_PATH=$test_dir" "New PROJECT_PATH in .env"

    # Verify old content is gone
    ((TOTAL_TESTS++))
    if ! grep -q "CUSTOM_SETTING=value" "$env_file"; then
        test_log "PASS" "Old .env content was replaced"
        ((PASSED_TESTS++))
    else
        test_log "FAIL" "Old .env content still present"
        FAILED_TEST_NAMES+=("Old .env content replacement")
        ((FAILED_TESTS++))
    fi

    # Cleanup
    rm -rf "$test_dir"
}

test_create_env_file_ip_detection_fallback() {
    test_log "INFO" "Testing IP detection fallback mechanisms"

    local test_dir="/tmp/vless_ip_fallback_$$"
    mkdir -p "$test_dir"

    # Mock curl to simulate network failures and fallback
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"
call_count=0

curl() {
    ((call_count++))
    case "\$call_count" in
        1)
            # First call (icanhazip.com) fails
            return 1
            ;;
        2)
            # Second call (ipify.org) fails
            return 1
            ;;
        3)
            # Third call (ifconfig.me) succeeds
            echo "198.51.100.50"
            ;;
        *)
            return 1
            ;;
    esac
}
export -f curl
export call_count

source "$VLESS_MANAGER"
create_env_file
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "IP detection with fallback"

    local env_file="$test_dir/.env"
    assert_file_content_contains "$env_file" "SERVER_IP=198.51.100.50" "Fallback IP detected"

    # Cleanup
    rm -rf "$test_dir"
}

test_create_env_file_all_ip_detection_fail() {
    test_log "INFO" "Testing IP detection when all services fail"

    local test_dir="/tmp/vless_ip_allfail_$$"
    mkdir -p "$test_dir"

    # Mock curl to always fail
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    return 1  # Always fail
}
export -f curl

source "$VLESS_MANAGER"
create_env_file
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "IP detection fallback to localhost"

    local env_file="$test_dir/.env"
    assert_file_content_contains "$env_file" "SERVER_IP=127.0.0.1" "Localhost fallback IP"

    # Cleanup
    rm -rf "$test_dir"
}

#######################################################################################
# INTEGRATION TESTS
#######################################################################################

test_complete_structure_creation() {
    test_log "INFO" "Testing complete project structure creation"

    local test_dir="/tmp/vless_complete_$$"
    mkdir -p "$test_dir"

    # Test complete structure creation workflow
    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "203.0.113.42"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"

# Create directories first
create_directories

# Then create env file
create_env_file
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Complete structure creation"

    # Verify all directories exist with correct permissions
    for dir_rel in "${!EXPECTED_DIRS[@]}"; do
        local dir_full="$test_dir/$dir_rel"
        local expected_perms="${EXPECTED_DIRS[$dir_rel]}"
        assert_directory_exists "$dir_full" "Complete test - Directory: $dir_rel"
        assert_permissions "$dir_full" "$expected_perms" "Complete test - Permissions: $dir_rel"
    done

    # Verify files exist with correct permissions
    local users_db="$test_dir/data/users.db"
    local log_file="$test_dir/logs/xray.log"
    local env_file="$test_dir/.env"

    assert_file_exists "$users_db" "Complete test - Users database"
    assert_file_exists "$log_file" "Complete test - Log file"
    assert_file_exists "$env_file" "Complete test - Environment file"

    assert_permissions "$users_db" "600" "Complete test - Users DB permissions"
    assert_permissions "$log_file" "644" "Complete test - Log file permissions"
    assert_permissions "$env_file" "600" "Complete test - Env file permissions"

    # Verify environment file content points to correct locations
    assert_file_content_contains "$env_file" "PROJECT_PATH=$test_dir" "Complete test - PROJECT_PATH"
    assert_file_content_contains "$env_file" "USERS_DB=$test_dir/data/users.db" "Complete test - USERS_DB path"
    assert_file_content_contains "$env_file" "LOG_FILE=$test_dir/logs/xray.log" "Complete test - LOG_FILE path"
    assert_file_content_contains "$env_file" "KEYS_DIR=$test_dir/data/keys" "Complete test - KEYS_DIR path"

    # Cleanup
    rm -rf "$test_dir"
}

test_structure_recreation_idempotency() {
    test_log "INFO" "Testing structure creation idempotency"

    local test_dir="/tmp/vless_idempotent_$$"
    mkdir -p "$test_dir"

    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    if [[ "\$@" =~ "icanhazip.com" ]]; then
        echo "203.0.113.99"
    else
        /usr/bin/curl "\$@"
    fi
}
export -f curl

source "$VLESS_MANAGER"

# Run structure creation twice
echo "=== First run ==="
create_directories
create_env_file

echo "=== Second run ==="
create_directories
create_env_file
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Idempotent structure creation"

    # Verify structure is still correct after double creation
    for dir_rel in "${!EXPECTED_DIRS[@]}"; do
        local dir_full="$test_dir/$dir_rel"
        local expected_perms="${EXPECTED_DIRS[$dir_rel]}"
        assert_directory_exists "$dir_full" "Idempotent test - Directory: $dir_rel"
        assert_permissions "$dir_full" "$expected_perms" "Idempotent test - Permissions: $dir_rel"
    done

    local env_file="$test_dir/.env"
    assert_file_exists "$env_file" "Idempotent test - Environment file"
    assert_permissions "$env_file" "600" "Idempotent test - Env file permissions"

    # Cleanup
    rm -rf "$test_dir"
}

#######################################################################################
# SECURITY TESTS
#######################################################################################

test_sensitive_file_permissions() {
    test_log "INFO" "Testing security of sensitive file permissions"

    local test_dir="/tmp/vless_security_$$"
    mkdir -p "$test_dir"

    local test_script="$test_dir/test_script.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PROJECT_ROOT="$test_dir"

curl() {
    echo "203.0.113.123"
}
export -f curl

source "$VLESS_MANAGER"
create_directories
create_env_file
EOF
    chmod +x "$test_script"

    "$test_script" >/dev/null 2>&1

    # Test that sensitive directories are not readable by others
    local config_perms=$(stat -c %a "$test_dir/config" 2>/dev/null || stat -f %A "$test_dir/config" 2>/dev/null)
    local data_perms=$(stat -c %a "$test_dir/data" 2>/dev/null || stat -f %A "$test_dir/data" 2>/dev/null)
    local keys_perms=$(stat -c %a "$test_dir/data/keys" 2>/dev/null || stat -f %A "$test_dir/data/keys" 2>/dev/null)

    assert_equals "700" "$config_perms" "Config directory security (700)"
    assert_equals "700" "$data_perms" "Data directory security (700)"
    assert_equals "700" "$keys_perms" "Keys directory security (700)"

    # Test that sensitive files are not readable by others
    local env_perms=$(stat -c %a "$test_dir/.env" 2>/dev/null || stat -f %A "$test_dir/.env" 2>/dev/null)
    local db_perms=$(stat -c %a "$test_dir/data/users.db" 2>/dev/null || stat -f %A "$test_dir/data/users.db" 2>/dev/null)

    assert_equals "600" "$env_perms" "Environment file security (600)"
    assert_equals "600" "$db_perms" "Users database security (600)"

    # Cleanup
    rm -rf "$test_dir"
}

#######################################################################################
# TEST REPORT AND EXECUTION
#######################################################################################

# Generate test report
generate_structure_test_report() {
    local report_file="/tmp/vless_structure_test_report_$(date +%Y%m%d_%H%M%S).txt"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$report_file" << EOF
================================================================================
VLESS+Reality VPN Service - Directory Structure Test Report
================================================================================

Test Execution Summary:
- Test Suite: Directory Structure and Permissions
- Test Version: $TEST_VERSION
- Execution Time: $end_time
- Total Tests: $TOTAL_TESTS
- Passed Tests: $PASSED_TESTS
- Failed Tests: $FAILED_TESTS
- Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%

Test Categories:
- Directory Structure Creation
- File Creation and Permissions
- Environment Configuration
- Integration Testing
- Security Testing

Expected Project Structure:
$PROJECT_ROOT/
├── config/          (mode: 700)
│   └── users/       (mode: 700)
├── data/            (mode: 700)
│   ├── users.db     (mode: 600)
│   └── keys/        (mode: 700)
├── logs/            (mode: 755)
│   └── xray.log     (mode: 644)
└── .env             (mode: 600)

Tested Scenarios:
✓ Fresh directory structure creation
✓ Directory creation with existing directories
✓ Directory permission handling
✓ Environment file creation
✓ Environment file with existing file
✓ IP detection fallback mechanisms
✓ Complete structure creation workflow
✓ Creation idempotency
✓ Security of sensitive files and directories
✓ Permission failure handling

Security Validations:
✓ Sensitive directories (config, data, keys) have mode 700
✓ Sensitive files (.env, users.db) have mode 600
✓ Log files have appropriate public read permissions (644)
✓ Log directory allows public read access (755)

EOF

    if [[ ${#FAILED_TEST_NAMES[@]} -gt 0 ]]; then
        cat >> "$report_file" << EOF
Failed Tests:
EOF
        for test_name in "${FAILED_TEST_NAMES[@]}"; do
            echo "  - $test_name" >> "$report_file"
        done
        echo >> "$report_file"
    fi

    echo "$report_file"
}

# Main test execution
run_structure_tests() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${GREEN}     VLESS+Reality VPN - Directory Structure Test Suite${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}Version: $TEST_VERSION${NC}"
    echo -e "${WHITE}Start Time: $start_time${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo

    # Directory structure tests
    echo -e "${YELLOW}[1/4] Testing Directory Structure Creation...${NC}"
    test_create_directories_fresh
    test_create_directories_existing
    test_create_directories_permission_failure
    echo

    # Environment file tests
    echo -e "${YELLOW}[2/4] Testing Environment File Creation...${NC}"
    test_create_env_file_fresh
    test_create_env_file_existing
    test_create_env_file_ip_detection_fallback
    test_create_env_file_all_ip_detection_fail
    echo

    # Integration tests
    echo -e "${YELLOW}[3/4] Testing Structure Integration...${NC}"
    test_complete_structure_creation
    test_structure_recreation_idempotency
    echo

    # Security tests
    echo -e "${YELLOW}[4/4] Testing Security and Permissions...${NC}"
    test_sensitive_file_permissions
    echo

    # Generate report
    local report_file=$(generate_structure_test_report)

    # Display results
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}                    STRUCTURE TEST RESULTS${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}Total Tests:${NC}  $TOTAL_TESTS"
    echo -e "${GREEN}Passed Tests:${NC} $PASSED_TESTS"
    echo -e "${RED}Failed Tests:${NC} $FAILED_TESTS"

    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
        echo -e "${WHITE}Success Rate:${NC} ${success_rate}%"
    fi

    echo -e "${WHITE}Report File:${NC}  $report_file"
    echo -e "${BLUE}================================================================================${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL STRUCTURE TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some structure tests failed.${NC}"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
${GREEN}VLESS Structure Test Suite v$TEST_VERSION${NC}

${YELLOW}USAGE:${NC}
    $0 [COMMAND]

${YELLOW}COMMANDS:${NC}
    run                     Run directory structure tests
    help                    Show this help message

${YELLOW}EXAMPLES:${NC}
    $0 run                  Execute structure test suite

EOF
}

# Main execution
main() {
    case "${1:-}" in
        "run")
            run_structure_tests
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        "")
            echo -e "${RED}No command specified${NC}"
            show_usage
            exit 1
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
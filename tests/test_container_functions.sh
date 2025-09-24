#!/bin/bash

# VLESS Docker Services Fix - Function Tests
# Simplified test suite focusing on individual functions

set -euo pipefail

# Test configuration
readonly TEST_DIR="/tmp/vless_test_$$"
readonly MODULES_DIR="/home/ikeniborn/Documents/Project/vless/modules"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create test environment
mkdir -p "$TEST_DIR"

echo "VLESS Docker Services Fix - Function Tests"
echo "==========================================="
echo "Test directory: $TEST_DIR"
echo

# Test utility functions
run_test() {
    local test_name="$1"
    shift
    local test_command=("$@")

    ((TESTS_TOTAL++))
    echo -n "Testing $test_name... "

    if "${test_command[@]}" 2>/dev/null; then
        echo "✓ PASSED"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAILED"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: get_vless_user_ids function
test_get_vless_user_ids() {
    # Source the container management module
    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock getent to return predictable results
    getent() {
        if [[ "$1" == "passwd" && "$2" == "vless" ]]; then
            echo "vless:x:995:982:VLESS User:/opt/vless:/bin/bash"
            return 0
        else
            return 1
        fi
    }

    local result
    result=$(get_vless_user_ids 2>/dev/null || echo "failed")

    if [[ "$result" == "995 982" ]]; then
        return 0
    else
        echo "Expected '995 982', got '$result'"
        return 1
    fi
}

# Test 2: update_docker_compose_permissions function
test_update_docker_compose_permissions() {
    local test_file="$TEST_DIR/test-compose.yml"

    # Create test docker-compose file
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    image: test
    user: "1000:1000"
    restart: unless-stopped
EOF

    # Source the functions
    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock functions to avoid system dependencies
    log_info() { echo "INFO: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }
    log_debug() { echo "DEBUG: $*" >&2; }

    # Test the function
    if update_docker_compose_permissions "$test_file" "995" "982" 2>/dev/null; then
        # Check if the user directive was updated
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

# Test 3: verify_container_permissions function
test_verify_container_permissions() {
    local test_file="$TEST_DIR/verify-compose.yml"

    # Create test file with correct permissions
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "995:982"
EOF

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_debug() { echo "DEBUG: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }

    # Should pass verification
    if verify_container_permissions "$test_file" "995" "982" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Test 4: verify_container_permissions with mismatch
test_verify_container_permissions_mismatch() {
    local test_file="$TEST_DIR/verify-mismatch.yml"

    # Create test file with incorrect permissions
    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "1000:1000"
EOF

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_debug() { echo "DEBUG: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }

    # Should fail verification
    if ! verify_container_permissions "$test_file" "995" "982" 2>/dev/null; then
        return 0
    else
        echo "Should have failed for mismatched permissions"
        return 1
    fi
}

# Test 5: File backup creation
test_backup_creation() {
    local test_file="$TEST_DIR/backup-test.yml"

    cat > "$test_file" << 'EOF'
version: '3.8'
services:
  xray:
    user: "1000:1000"
EOF

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_info() { echo "INFO: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }
    log_debug() { echo "DEBUG: $*" >&2; }

    # Run update (should create backup)
    if update_docker_compose_permissions "$test_file" "995" "982" 2>/dev/null; then
        # Check if backup was created
        if find "$TEST_DIR" -name "backup-test.yml.backup.*" | grep -q .; then
            return 0
        else
            echo "Backup file not created"
            return 1
        fi
    else
        return 1
    fi
}

# Test 6: Docker compose version update
test_compose_version_update() {
    local test_file="$TEST_DIR/version-test.yml"

    cat > "$test_file" << 'EOF'
version: "3.3"
services:
  xray:
    image: test
EOF

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_debug() { echo "DEBUG: $*" >&2; }
    log_info() { echo "INFO: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }

    if update_compose_version "$test_file" 2>/dev/null; then
        if grep -q "version: '3.8'" "$test_file"; then
            return 0
        else
            echo "Version not updated correctly"
            return 1
        fi
    else
        return 1
    fi
}

# Test 7: Error handling for missing files
test_error_handling() {
    local missing_file="$TEST_DIR/nonexistent.yml"

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_error() { echo "ERROR: $*" >&2; }
    log_debug() { echo "DEBUG: $*" >&2; }

    # Should handle missing file gracefully (return error)
    if ! update_docker_compose_permissions "$missing_file" "995" "982" 2>/dev/null; then
        return 0
    else
        echo "Should have failed for missing file"
        return 1
    fi
}

# Test 8: Complex YAML handling
test_complex_yaml() {
    local test_file="$TEST_DIR/complex.yml"

    cat > "$test_file" << 'EOF'
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

  nginx:
    image: nginx:alpine
    container_name: vless-nginx
    restart: unless-stopped
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "80:80"
EOF

    source "$MODULES_DIR/common_utils.sh" 2>/dev/null || true
    source "$MODULES_DIR/container_management.sh" 2>/dev/null || true

    # Mock logging functions
    log_info() { echo "INFO: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*" >&2; }
    log_debug() { echo "DEBUG: $*" >&2; }

    if update_docker_compose_permissions "$test_file" "995" "982" 2>/dev/null; then
        # Should update xray service user but leave nginx unchanged
        if grep -q 'user: "995:982"' "$test_file" && ! grep -A 10 "nginx:" "$test_file" | grep -q "user:"; then
            return 0
        else
            echo "Complex YAML not handled correctly"
            return 1
        fi
    else
        return 1
    fi
}

# Run all tests
echo "Running individual function tests..."
echo "------------------------------------"

run_test "get_vless_user_ids" test_get_vless_user_ids
run_test "update_docker_compose_permissions" test_update_docker_compose_permissions
run_test "verify_container_permissions" test_verify_container_permissions
run_test "verify_container_permissions_mismatch" test_verify_container_permissions_mismatch
run_test "backup_creation" test_backup_creation
run_test "compose_version_update" test_compose_version_update
run_test "error_handling" test_error_handling
run_test "complex_yaml" test_complex_yaml

echo
echo "============================================"
echo "Test Results Summary"
echo "============================================"
echo "Total Tests:  $TESTS_TOTAL"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $((TESTS_FAILED))"

if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
    echo
    echo "✓ ALL TESTS PASSED! The functions are working correctly."
    echo
    echo "Key Results:"
    echo "- get_vless_user_ids() correctly detects system users"
    echo "- update_docker_compose_permissions() properly updates user directives"
    echo "- verify_container_permissions() validates settings correctly"
    echo "- Backup files are created during updates"
    echo "- Version updates work properly"
    echo "- Error handling works for edge cases"
    echo "- Complex YAML files are handled correctly"
else
    echo
    echo "✗ Some tests failed. Review the output above for details."
fi

# Cleanup
rm -rf "$TEST_DIR"

# Exit with appropriate code
if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
    exit 0
else
    exit 1
fi
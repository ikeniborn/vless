#!/bin/bash

# VLESS+Reality VPN Management System - Readonly Variable Conflicts Test Suite
# Version: 1.0.0
# Description: Comprehensive tests for readonly variable conflict resolution
#
# This test suite validates:
# - No conflicts when SCRIPT_DIR is predefined as readonly
# - Proper handling of readonly variables in include guards
# - Safe redefinition patterns in modules
# - Variable scoping and namespace protection

set -euo pipefail

# Test configuration
readonly TEST_NAME="Readonly Variable Conflicts"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Test results tracking
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TOTAL_TESTS=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Test framework functions
start_test() {
    local test_name="$1"
    log_info "Starting test: $test_name"
    ((TOTAL_TESTS++))
}

pass_test() {
    local test_name="$1"
    log_success "PASSED: $test_name"
    ((TESTS_PASSED++))
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    log_error "FAILED: $test_name - $reason"
    ((TESTS_FAILED++))
}

# Test 1: Test predefined readonly SCRIPT_DIR
test_predefined_readonly_script_dir() {
    local test_name="Predefined Readonly SCRIPT_DIR"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Define SCRIPT_DIR as readonly before sourcing modules
readonly SCRIPT_DIR="${MODULES_DIR}"

# Try to source common_utils.sh - should not conflict
source "${MODULES_DIR}/common_utils.sh"

# Verify SCRIPT_DIR is still our predefined value
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR changed unexpectedly: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Readonly SCRIPT_DIR conflict when predefined"
    fi

    rm -f "$temp_script"
}

# Test 2: Test readonly variable redefinition attempts
test_readonly_redefinition() {
    local test_name="Readonly Variable Redefinition"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils.sh first
source "${MODULES_DIR}/common_utils.sh"

# Try to redefine a readonly variable - this should fail gracefully
set +e
readonly LOG_DEBUG=999 2>/dev/null
exit_code=\$?
set -e

# If it failed (which is expected), that's good
if [[ \$exit_code -ne 0 ]]; then
    # Verify original value is preserved
    if [[ "\$LOG_DEBUG" == "0" ]]; then
        exit 0
    else
        echo "LOG_DEBUG value corrupted: \$LOG_DEBUG" >&2
        exit 1
    fi
else
    echo "Readonly variable was unexpectedly redefined" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Readonly variable redefinition handling failed"
    fi

    rm -f "$temp_script"
}

# Test 3: Test include guard readonly protection
test_include_guard_readonly() {
    local test_name="Include Guard Readonly Protection"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils.sh multiple times
source "${MODULES_DIR}/common_utils.sh"

# Try to unset the include guard (should fail)
set +e
unset COMMON_UTILS_LOADED 2>/dev/null
unset_exit_code=\$?
set -e

# Try to redefine the include guard (should fail)
set +e
readonly COMMON_UTILS_LOADED=false 2>/dev/null
redefine_exit_code=\$?
set -e

# Source again - should still be protected
source "${MODULES_DIR}/common_utils.sh"

# If both operations failed (expected) and module is still protected, pass
if [[ \$unset_exit_code -ne 0 ]] && [[ \$redefine_exit_code -ne 0 ]]; then
    exit 0
else
    echo "Include guard protection failed" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Include guard readonly protection failed"
    fi

    rm -f "$temp_script"
}

# Test 4: Test namespace collision protection
test_namespace_collision() {
    local test_name="Namespace Collision Protection"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Define conflicting readonly variables
readonly RED="NOT_RED"
readonly GREEN="NOT_GREEN"
readonly LOG_INFO="NOT_LOG_INFO"

# Source common_utils.sh - should handle conflicts gracefully
source "${MODULES_DIR}/common_utils.sh"

# Check that our variables weren't overwritten
if [[ "\$RED" == "NOT_RED" ]] && [[ "\$GREEN" == "NOT_GREEN" ]] && [[ "\$LOG_INFO" == "NOT_LOG_INFO" ]]; then
    exit 0
else
    echo "Namespace collision occurred" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Namespace collision protection failed"
    fi

    rm -f "$temp_script"
}

# Test 5: Test cross-module readonly conflicts
test_cross_module_readonly() {
    local test_name="Cross-Module Readonly Conflicts"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source multiple modules that might have conflicting readonly variables
source "${MODULES_DIR}/common_utils.sh"
source "${MODULES_DIR}/docker_setup.sh"
source "${MODULES_DIR}/container_management.sh"

# All modules should load without errors
# Test that key constants are defined correctly
[[ "\$LOG_DEBUG" == "0" ]] || exit 1
[[ "\$DOCKER_GPG_URL" == "https://download.docker.com/linux/ubuntu/gpg" ]] || exit 1
[[ "\$PROJECT_NAME" == "vless-vpn" ]] || exit 1

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Cross-module readonly conflicts detected"
    fi

    rm -f "$temp_script"
}

# Test 6: Test variable assignment order
test_variable_assignment_order() {
    local test_name="Variable Assignment Order"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Set some variables before sourcing
TEST_VAR="original"
readonly READONLY_TEST="readonly_original"

# Source module
source "${MODULES_DIR}/common_utils.sh"

# Variables should maintain their values
[[ "\$TEST_VAR" == "original" ]] || exit 1
[[ "\$READONLY_TEST" == "readonly_original" ]] || exit 1

# Module variables should be set
[[ -n "\${LOG_LEVEL:-}" ]] || exit 1
[[ -n "\${PROJECT_ROOT:-}" ]] || exit 1

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Variable assignment order issue"
    fi

    rm -f "$temp_script"
}

# Test 7: Test readonly array conflicts
test_readonly_array_conflicts() {
    local test_name="Readonly Array Conflicts"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Define a readonly array that might conflict
declare -ra CHILD_PROCESSES=("test1" "test2")

# Source common_utils.sh - should handle array conflicts
source "${MODULES_DIR}/common_utils.sh"

# Original array should be preserved
if [[ "\${CHILD_PROCESSES[0]}" == "test1" ]] && [[ "\${CHILD_PROCESSES[1]}" == "test2" ]]; then
    exit 0
else
    echo "Readonly array conflict occurred" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Readonly array conflicts not handled properly"
    fi

    rm -f "$temp_script"
}

# Test 8: Test conditional readonly assignment
test_conditional_readonly_assignment() {
    local test_name="Conditional Readonly Assignment"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Pre-set LOG_LEVEL as readonly
readonly LOG_LEVEL=5

# Source common_utils.sh
source "${MODULES_DIR}/common_utils.sh"

# LOG_LEVEL should retain our predefined value
if [[ "\$LOG_LEVEL" == "5" ]]; then
    exit 0
else
    echo "Conditional readonly assignment failed: LOG_LEVEL=\$LOG_LEVEL" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Conditional readonly assignment not working"
    fi

    rm -f "$temp_script"
}

# Test 9: Test readonly environment variable handling
test_readonly_env_variables() {
    local test_name="Readonly Environment Variables"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Set environment variables as readonly
export VLESS_PORT=8443
readonly VLESS_PORT

export LOG_FILE="/custom/log/file.log"
readonly LOG_FILE

# Source common_utils.sh
source "${MODULES_DIR}/common_utils.sh"

# Environment variables should be preserved
[[ "\$VLESS_PORT" == "8443" ]] || exit 1
[[ "\$LOG_FILE" == "/custom/log/file.log" ]] || exit 1

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Readonly environment variables not preserved"
    fi

    rm -f "$temp_script"
}

# Test 10: Test error recovery from readonly conflicts
test_error_recovery() {
    local test_name="Error Recovery from Readonly Conflicts"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local temp_module=$(mktemp)

    # Create a module that attempts to redefine readonly variables
    cat > "$temp_module" << 'EOF'
#!/bin/bash
set -euo pipefail

# Try to redefine a readonly variable (should fail gracefully)
{
    readonly LOG_DEBUG=999
} 2>/dev/null || true

# Module should continue functioning despite the error
test_function() {
    echo "Module loaded successfully"
}
EOF

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils first
source "${MODULES_DIR}/common_utils.sh"

# Source the problematic module
source "$temp_module"

# Test that functions are still available
if declare -F test_function >/dev/null; then
    # And that original readonly values are preserved
    [[ "\$LOG_DEBUG" == "0" ]] || exit 1
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Error recovery from readonly conflicts failed"
    fi

    rm -f "$temp_script" "$temp_module"
}

# Test summary
print_test_summary() {
    echo
    echo "=============================================="
    echo "Readonly Variable Conflicts Test Results"
    echo "=============================================="
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All readonly variable conflict tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some readonly variable conflict tests failed.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Readonly Variable Conflicts Test Suite"
    echo "Project Root: $PROJECT_ROOT"
    echo "Modules Directory: $MODULES_DIR"
    echo

    # Run all tests
    test_predefined_readonly_script_dir
    test_readonly_redefinition
    test_include_guard_readonly
    test_namespace_collision
    test_cross_module_readonly
    test_variable_assignment_order
    test_readonly_array_conflicts
    test_conditional_readonly_assignment
    test_readonly_env_variables
    test_error_recovery

    # Print summary
    print_test_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
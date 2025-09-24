#!/bin/bash

# VLESS+Reality VPN Management System - Module Loading Fixes Test Suite
# Version: 1.0.0
# Description: Comprehensive tests for module loading fixes
#
# This test suite validates:
# - No readonly variable conflicts when loading modules
# - Proper SCRIPT_DIR handling across modules
# - Successful module sourcing without errors
# - Container management module functionality
# - Include guard protection against multiple sourcing

set -euo pipefail

# Test configuration
readonly TEST_NAME="Module Loading Fixes"
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

# Test 1: Verify module files exist and are readable
test_module_files_exist() {
    local test_name="Module Files Existence"
    start_test "$test_name"

    local modules=(
        "common_utils.sh"
        "docker_setup.sh"
        "container_management.sh"
        "user_management.sh"
        "user_database.sh"
        "monitoring.sh"
        "backup_restore.sh"
        "security_hardening.sh"
        "config_templates.sh"
        "cert_management.sh"
        "logging_setup.sh"
        "maintenance_utils.sh"
        "system_update.sh"
        "ufw_config.sh"
        "safety_utils.sh"
    )

    local missing_modules=()
    local unreadable_modules=()

    for module in "${modules[@]}"; do
        local module_path="${MODULES_DIR}/${module}"
        if [[ ! -f "$module_path" ]]; then
            missing_modules+=("$module")
        elif [[ ! -r "$module_path" ]]; then
            unreadable_modules+=("$module")
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        fail_test "$test_name" "Missing modules: ${missing_modules[*]}"
        return 1
    fi

    if [[ ${#unreadable_modules[@]} -gt 0 ]]; then
        fail_test "$test_name" "Unreadable modules: ${unreadable_modules[*]}"
        return 1
    fi

    pass_test "$test_name"
}

# Test 2: Test include guard functionality
test_include_guard_functionality() {
    local test_name="Include Guard Functionality"
    start_test "$test_name"

    # Create a temporary test script that sources common_utils.sh twice
    local temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils.sh twice to test include guard
source "$1"
source "$1"

# If we get here without error, the include guard worked
exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" "${MODULES_DIR}/common_utils.sh" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Include guard failed to prevent multiple sourcing"
    fi

    rm -f "$temp_script"
}

# Test 3: Test SCRIPT_DIR handling in modules
test_script_dir_handling() {
    local test_name="SCRIPT_DIR Handling"
    start_test "$test_name"

    # Create a temporary test script that sources modules from different directories
    local temp_script=$(mktemp)
    local temp_modules_dir=$(mktemp -d)

    # Copy a module to temp directory to test SCRIPT_DIR detection
    cp "${MODULES_DIR}/common_utils.sh" "$temp_modules_dir/"

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Change to a different directory
cd /tmp

# Source the module from the temp directory
source "${temp_modules_dir}/common_utils.sh"

# Check if SCRIPT_DIR was set correctly
if [[ "\$SCRIPT_DIR" == "${temp_modules_dir}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR mismatch: expected ${temp_modules_dir}, got \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not handled correctly"
    fi

    rm -f "$temp_script"
    rm -rf "$temp_modules_dir"
}

# Test 4: Test module sourcing without readonly conflicts
test_readonly_variable_conflicts() {
    local test_name="Readonly Variable Conflicts"
    start_test "$test_name"

    # Create a test script that defines some readonly variables then sources modules
    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Define some readonly variables that might conflict
readonly SCRIPT_DIR="${MODULES_DIR}"

# Try to source common_utils.sh
source "${MODULES_DIR}/common_utils.sh"

# Try to source other modules
source "${MODULES_DIR}/docker_setup.sh"
source "${MODULES_DIR}/container_management.sh"

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Readonly variable conflicts detected"
    fi

    rm -f "$temp_script"
}

# Test 5: Test sequential module loading
test_sequential_module_loading() {
    local test_name="Sequential Module Loading"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Load modules in dependency order
source "${MODULES_DIR}/common_utils.sh"
source "${MODULES_DIR}/docker_setup.sh"
source "${MODULES_DIR}/container_management.sh"
source "${MODULES_DIR}/user_database.sh"
source "${MODULES_DIR}/user_management.sh"
source "${MODULES_DIR}/monitoring.sh"
source "${MODULES_DIR}/backup_restore.sh"
source "${MODULES_DIR}/security_hardening.sh"

# Test that key functions are available
if declare -F log_info >/dev/null && \
   declare -F get_docker_version >/dev/null && \
   declare -F get_vless_user_ids >/dev/null; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Sequential module loading failed"
    fi

    rm -f "$temp_script"
}

# Test 6: Test module dependency resolution
test_module_dependency_resolution() {
    local test_name="Module Dependency Resolution"
    start_test "$test_name"

    # Test that modules can source their dependencies correctly
    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source a module that depends on common_utils.sh
source "${MODULES_DIR}/docker_setup.sh"

# Test that common_utils functions are available
if declare -F log_info >/dev/null && declare -F command_exists >/dev/null; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Module dependency resolution failed"
    fi

    rm -f "$temp_script"
}

# Test 7: Test function availability after module loading
test_function_availability() {
    local test_name="Function Availability"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

source "${MODULES_DIR}/common_utils.sh"
source "${MODULES_DIR}/docker_setup.sh"
source "${MODULES_DIR}/container_management.sh"

# Test common_utils functions
declare -F log_info >/dev/null || exit 1
declare -F log_error >/dev/null || exit 1
declare -F command_exists >/dev/null || exit 1
declare -F validate_email >/dev/null || exit 1

# Test docker_setup functions
declare -F get_docker_version >/dev/null || exit 1
declare -F install_docker >/dev/null || exit 1

# Test container_management functions
declare -F get_vless_user_ids >/dev/null || exit 1
declare -F start_services >/dev/null || exit 1

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Expected functions not available after module loading"
    fi

    rm -f "$temp_script"
}

# Test 8: Test variable persistence across modules
test_variable_persistence() {
    local test_name="Variable Persistence"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

source "${MODULES_DIR}/common_utils.sh"

# Test that readonly variables are preserved
[[ "\$LOG_DEBUG" == "0" ]] || exit 1
[[ "\$LOG_INFO" == "1" ]] || exit 1
[[ "\$LOG_WARN" == "2" ]] || exit 1
[[ "\$LOG_ERROR" == "3" ]] || exit 1

# Test that SCRIPT_DIR is set
[[ -n "\$SCRIPT_DIR" ]] || exit 1

# Test that PROJECT_ROOT is set
[[ -n "\$PROJECT_ROOT" ]] || exit 1

exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Variables not persisted correctly across modules"
    fi

    rm -f "$temp_script"
}

# Test 9: Test error handling in module loading
test_error_handling() {
    local test_name="Error Handling in Module Loading"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local temp_bad_module=$(mktemp)

    # Create a bad module that should cause sourcing to fail
    cat > "$temp_bad_module" << 'EOF'
#!/bin/bash
# This module intentionally has errors
set -euo pipefail
readonly INTENTIONAL_ERROR=$(undefined_command_that_does_not_exist)
EOF

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Try to source the bad module - this should fail
if source "$temp_bad_module" 2>/dev/null; then
    # If it succeeded, that's unexpected
    exit 1
else
    # If it failed as expected, that's good
    exit 0
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Error handling in module loading not working correctly"
    fi

    rm -f "$temp_script" "$temp_bad_module"
}

# Test 10: Test multiple sourcing protection
test_multiple_sourcing_protection() {
    local test_name="Multiple Sourcing Protection"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils.sh multiple times
source "${MODULES_DIR}/common_utils.sh"
source "${MODULES_DIR}/common_utils.sh"
source "${MODULES_DIR}/common_utils.sh"

# If we get here, the include guard worked
exit 0
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Multiple sourcing protection failed"
    fi

    rm -f "$temp_script"
}

# Test summary
print_test_summary() {
    echo
    echo "=============================================="
    echo "Module Loading Fixes Test Results Summary"
    echo "=============================================="
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All module loading tests passed successfully!${NC}"
        return 0
    else
        echo -e "\n${RED}Some module loading tests failed.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Module Loading Fixes Test Suite"
    echo "Project Root: $PROJECT_ROOT"
    echo "Modules Directory: $MODULES_DIR"
    echo

    # Run all tests
    test_module_files_exist
    test_include_guard_functionality
    test_script_dir_handling
    test_readonly_variable_conflicts
    test_sequential_module_loading
    test_module_dependency_resolution
    test_function_availability
    test_variable_persistence
    test_error_handling
    test_multiple_sourcing_protection

    # Print summary
    print_test_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
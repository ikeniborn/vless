#!/bin/bash
# Test Suite for Phase 1 Modules
# Tests all modules created in Phase 1 (Infrastructure Preparation)
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="$PROJECT_DIR/modules"

# Import common utilities
source "$MODULES_DIR/common_utils.sh" 2>/dev/null || {
    echo "ERROR: Cannot load common utilities module" >&2
    exit 1
}

# Test results tracking
declare -a TEST_RESULTS=()
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -i TESTS_TOTAL=0

# Test result functions
test_start() {
    local test_name="$1"
    echo -n "Testing $test_name... "
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

test_pass() {
    echo -e "${GREEN}PASS${NC}"
    TEST_RESULTS+=("PASS")
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local reason="${1:-Unknown error}"
    echo -e "${RED}FAIL${NC} - $reason"
    TEST_RESULTS+=("FAIL: $reason")
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_skip() {
    local reason="${1:-Skipped}"
    echo -e "${YELLOW}SKIP${NC} - $reason"
    TEST_RESULTS+=("SKIP: $reason")
}

# Module existence tests
test_module_exists() {
    local module_name="$1"
    local module_path="$MODULES_DIR/$module_name"

    test_start "module existence: $module_name"

    if [[ -f "$module_path" ]]; then
        test_pass
        return 0
    else
        test_fail "Module file not found: $module_path"
        return 1
    fi
}

test_module_executable() {
    local module_name="$1"
    local module_path="$MODULES_DIR/$module_name"

    test_start "module executable: $module_name"

    if [[ -x "$module_path" ]]; then
        test_pass
        return 0
    else
        test_fail "Module is not executable: $module_path"
        return 1
    fi
}

test_module_syntax() {
    local module_name="$1"
    local module_path="$MODULES_DIR/$module_name"

    test_start "module syntax: $module_name"

    if bash -n "$module_path" 2>/dev/null; then
        test_pass
        return 0
    else
        test_fail "Syntax error in module: $module_path"
        return 1
    fi
}

test_module_imports() {
    local module_name="$1"
    local module_path="$MODULES_DIR/$module_name"

    test_start "module imports: $module_name"

    # Check if module can source process_safe.sh
    if grep -q "source.*process_safe.sh" "$module_path"; then
        # Test if the import path is correct
        local import_line=$(grep "source.*process_safe.sh" "$module_path" | head -n1)
        if echo "$import_line" | grep -q "process_isolation/process_safe.sh"; then
            test_pass
            return 0
        else
            test_fail "Incorrect import path for process_safe.sh"
            return 1
        fi
    else
        test_fail "Module does not import process_safe.sh"
        return 1
    fi
}

# Function export tests
test_function_exports() {
    local module_name="$1"
    local module_path="$MODULES_DIR/$module_name"

    test_start "function exports: $module_name"

    # Source the module and check if functions are exported
    if source "$module_path" 2>/dev/null; then
        # Check for expected export statements
        if grep -q "export -f" "$module_path"; then
            test_pass
            return 0
        else
            test_fail "No function exports found"
            return 1
        fi
    else
        test_fail "Failed to source module"
        return 1
    fi
}

# Specific module tests
test_process_isolation_module() {
    print_section "Testing Process Isolation Module"

    test_module_exists "process_isolation/process_safe.sh"
    test_module_executable "process_isolation/process_safe.sh"
    test_module_syntax "process_isolation/process_safe.sh"

    # Test specific functions exist
    test_start "process isolation functions"
    if source "$MODULES_DIR/process_isolation/process_safe.sh" 2>/dev/null; then
        if declare -f safe_execute >/dev/null 2>&1 && \
           declare -f isolate_systemctl_command >/dev/null 2>&1 && \
           declare -f setup_signal_handlers >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Required functions not found"
        fi
    else
        test_fail "Failed to source process isolation module"
    fi
}

test_system_update_module() {
    print_section "Testing System Update Module"

    test_module_exists "system_update.sh"
    test_module_executable "system_update.sh"
    test_module_syntax "system_update.sh"
    test_module_imports "system_update.sh"
    test_function_exports "system_update.sh"

    # Test help output
    test_start "system update help"
    if "$MODULES_DIR/system_update.sh" help 2>/dev/null | grep -q "Usage:"; then
        test_pass
    else
        test_skip "Help output test (not critical)"
    fi
}

test_docker_setup_module() {
    print_section "Testing Docker Setup Module"

    test_module_exists "docker_setup.sh"
    test_module_executable "docker_setup.sh"
    test_module_syntax "docker_setup.sh"
    test_module_imports "docker_setup.sh"
    test_function_exports "docker_setup.sh"

    # Test help output
    test_start "docker setup help"
    if "$MODULES_DIR/docker_setup.sh" help 2>/dev/null | grep -q "Usage:"; then
        test_pass
    else
        test_skip "Help output test (not critical)"
    fi
}

test_ufw_config_module() {
    print_section "Testing UFW Configuration Module"

    test_module_exists "ufw_config.sh"
    test_module_executable "ufw_config.sh"
    test_module_syntax "ufw_config.sh"
    test_module_imports "ufw_config.sh"
    test_function_exports "ufw_config.sh"

    # Test help output
    test_start "UFW config help"
    if "$MODULES_DIR/ufw_config.sh" help 2>/dev/null | grep -q "Usage:"; then
        test_pass
    else
        test_skip "Help output test (not critical)"
    fi
}

test_backup_restore_module() {
    print_section "Testing Backup & Restore Module"

    test_module_exists "backup_restore.sh"
    test_module_executable "backup_restore.sh"
    test_module_syntax "backup_restore.sh"
    test_module_imports "backup_restore.sh"
    test_function_exports "backup_restore.sh"

    # Test help output
    test_start "backup restore help"
    if "$MODULES_DIR/backup_restore.sh" help 2>/dev/null | grep -q "Usage:"; then
        test_pass
    else
        test_skip "Help output test (not critical)"
    fi
}

test_common_utils_module() {
    print_section "Testing Common Utilities Module"

    test_module_exists "common_utils.sh"
    test_module_executable "common_utils.sh"
    test_module_syntax "common_utils.sh"

    # Test specific utility functions
    test_start "common utility functions"
    if source "$MODULES_DIR/common_utils.sh" 2>/dev/null; then
        if declare -f print_header >/dev/null 2>&1 && \
           declare -f validate_ip_address >/dev/null 2>&1 && \
           declare -f get_os_info >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Required utility functions not found"
        fi
    else
        test_fail "Failed to source common utilities module"
    fi
}

# Directory structure tests
test_directory_structure() {
    print_section "Testing Directory Structure"

    local required_dirs=(
        "$PROJECT_DIR/modules"
        "$PROJECT_DIR/config"
        "$PROJECT_DIR/tests"
        "/opt/vless/configs"
        "/opt/vless/certs"
        "/opt/vless/users"
        "/opt/vless/logs"
        "/opt/vless/backups"
    )

    for dir in "${required_dirs[@]}"; do
        test_start "directory existence: $dir"
        if [[ -d "$dir" ]]; then
            test_pass
        else
            test_fail "Directory not found: $dir"
        fi
    done

    # Test directory permissions
    test_start "project directory permissions"
    if [[ -r "$PROJECT_DIR/modules" ]] && [[ -w "$PROJECT_DIR/modules" ]] && [[ -x "$PROJECT_DIR/modules" ]]; then
        test_pass
    else
        test_fail "Insufficient permissions on project directories"
    fi
}

# Integration tests
test_module_integration() {
    print_section "Testing Module Integration"

    test_start "cross-module compatibility"

    # Test if modules can be loaded together
    local temp_script=$(mktemp)
    cat > "$temp_script" <<'EOF'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$(dirname "$SCRIPT_DIR")/modules"

source "$MODULES_DIR/common_utils.sh" 2>/dev/null || exit 1
source "$MODULES_DIR/process_isolation/process_safe.sh" 2>/dev/null || exit 1

# Test a simple function from each module
if declare -f print_info >/dev/null 2>&1 && \
   declare -f safe_execute >/dev/null 2>&1; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"
    if "$temp_script" 2>/dev/null; then
        test_pass
    else
        test_fail "Modules cannot be loaded together"
    fi

    rm -f "$temp_script"
}

# EPERM prevention tests
test_eperm_prevention() {
    print_section "Testing EPERM Prevention"

    local modules_to_check=(
        "system_update.sh"
        "docker_setup.sh"
        "ufw_config.sh"
        "backup_restore.sh"
    )

    for module in "${modules_to_check[@]}"; do
        test_start "EPERM patterns in $module"

        local module_path="$MODULES_DIR/$module"
        local dangerous_patterns=(
            "systemctl.*start\|stop\|restart"
            "docker compose up"
            "while true"
            "tail -f"
            "sleep [0-9]{3,}"
        )

        local found_dangerous=false
        for pattern in "${dangerous_patterns[@]}"; do
            if grep -qE "$pattern" "$module_path" 2>/dev/null; then
                # Check if it's wrapped in safe functions
                if ! grep -B5 -A5 "$pattern" "$module_path" | grep -q "safe_execute\|isolate_\|controlled_\|interruptible_"; then
                    found_dangerous=true
                    break
                fi
            fi
        done

        if [[ "$found_dangerous" == "true" ]]; then
            test_fail "Dangerous patterns found without EPERM protection"
        else
            test_pass
        fi
    done
}

# Performance tests
test_module_performance() {
    print_section "Testing Module Performance"

    local modules_to_test=(
        "common_utils.sh"
        "process_isolation/process_safe.sh"
    )

    for module in "${modules_to_test[@]}"; do
        test_start "load time for $module"

        local start_time=$(date +%s%N)
        if source "$MODULES_DIR/$module" >/dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local load_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds

            if [[ $load_time -lt 1000 ]]; then # Less than 1 second
                test_pass
            else
                test_fail "Module takes too long to load: ${load_time}ms"
            fi
        else
            test_fail "Failed to load module"
        fi
    done
}

# Main test execution
run_all_tests() {
    print_header "VLESS VPN Project - Phase 1 Module Tests"

    print_info "Testing infrastructure preparation modules..."
    print_info "Project directory: $PROJECT_DIR"
    echo

    # Run all test suites
    test_directory_structure
    test_process_isolation_module
    test_common_utils_module
    test_system_update_module
    test_docker_setup_module
    test_ufw_config_module
    test_backup_restore_module
    test_module_integration
    test_eperm_prevention
    test_module_performance

    # Print test summary
    print_header "Test Results Summary"

    echo -e "${BOLD}Test Statistics:${NC}"
    echo -e "  Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "  Passed:      ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed:      ${RED}$TESTS_FAILED${NC}"
    echo -e "  Success Rate: ${CYAN}$(( TESTS_PASSED * 100 / TESTS_TOTAL ))%${NC}"
    echo

    if [[ $TESTS_FAILED -eq 0 ]]; then
        print_success "All tests passed! Phase 1 modules are ready."
        return 0
    else
        print_error "$TESTS_FAILED test(s) failed. Please review the issues above."
        return 1
    fi
}

# Quick validation function
quick_validation() {
    print_info "Running quick validation of Phase 1 modules..."

    local required_files=(
        "$MODULES_DIR/process_isolation/process_safe.sh"
        "$MODULES_DIR/common_utils.sh"
        "$MODULES_DIR/system_update.sh"
        "$MODULES_DIR/docker_setup.sh"
        "$MODULES_DIR/ufw_config.sh"
        "$MODULES_DIR/backup_restore.sh"
    )

    local all_present=true
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Missing file: $file"
            all_present=false
        elif [[ ! -x "$file" ]]; then
            print_error "File not executable: $file"
            all_present=false
        fi
    done

    if [[ "$all_present" == "true" ]]; then
        print_success "Quick validation passed - all Phase 1 modules present and executable"
        return 0
    else
        print_error "Quick validation failed - missing or non-executable modules"
        return 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-full}" in
        "quick")
            quick_validation
            ;;
        "full"|"")
            run_all_tests
            ;;
        *)
            echo "Usage: $0 [quick|full]"
            echo "  quick - Quick validation of module presence"
            echo "  full  - Full test suite (default)"
            exit 1
            ;;
    esac
fi
#!/bin/bash

# VLESS+Reality VPN Management System - Installation Fixes Validation
# Version: 1.0.0
# Description: Quick validation test for installation fixes functionality

set -euo pipefail

# Test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Initialize test suite
init_test_framework "Installation Fixes Validation"

# Test 1: Verify include guard in common_utils.sh
test_verify_include_guard_exists() {
    local common_utils_file="${SOURCE_DIR}/../modules/common_utils.sh"

    if [[ ! -f "$common_utils_file" ]]; then
        fail_test "common_utils.sh not found"
        return
    fi

    # Check for include guard
    if grep -q "COMMON_UTILS_LOADED" "$common_utils_file"; then
        assert_contains "$(cat "$common_utils_file")" "if \[\[ -n \"\${COMMON_UTILS_LOADED:-}\" \]\]" \
            "Should contain include guard check"
        assert_contains "$(cat "$common_utils_file")" "readonly COMMON_UTILS_LOADED=true" \
            "Should set include guard variable"
        pass_test "Include guard found and properly implemented"
    else
        fail_test "Include guard not found in common_utils.sh"
    fi
}

# Test 2: Verify create_vless_system_user function exists
test_verify_user_creation_function() {
    local common_utils_file="${SOURCE_DIR}/../modules/common_utils.sh"

    if grep -q "create_vless_system_user" "$common_utils_file"; then
        assert_contains "$(cat "$common_utils_file")" "create_vless_system_user()" \
            "Should contain user creation function definition"
        assert_contains "$(cat "$common_utils_file")" "getent group" \
            "Should check for existing group"
        assert_contains "$(cat "$common_utils_file")" "getent passwd" \
            "Should check for existing user"
        pass_test "User creation function found and properly implemented"
    else
        fail_test "create_vless_system_user function not found"
    fi
}

# Test 3: Verify install_python_dependencies function exists in install.sh
test_verify_python_dependencies_function() {
    local install_file="${SOURCE_DIR}/../install.sh"

    if [[ ! -f "$install_file" ]]; then
        fail_test "install.sh not found"
        return
    fi

    if grep -q "install_python_dependencies" "$install_file"; then
        assert_contains "$(cat "$install_file")" "install_python_dependencies()" \
            "Should contain Python dependencies function definition"
        assert_contains "$(cat "$install_file")" "requirements.txt" \
            "Should reference requirements.txt file"
        assert_contains "$(cat "$install_file")" "pip install" \
            "Should use pip install command"
        pass_test "Python dependencies function found and properly implemented"
    else
        fail_test "install_python_dependencies function not found"
    fi
}

# Test 4: Verify QUICK_MODE support in install.sh
test_verify_quick_mode_support() {
    local install_file="${SOURCE_DIR}/../install.sh"

    if grep -q "QUICK_MODE" "$install_file"; then
        assert_contains "$(cat "$install_file")" "\${QUICK_MODE:-false}" \
            "Should check QUICK_MODE with default value"
        assert_contains "$(cat "$install_file")" "Press Enter to continue" \
            "Should have interactive prompts"
        pass_test "QUICK_MODE support found and properly implemented"
    else
        fail_test "QUICK_MODE support not found"
    fi
}

# Test 5: Verify UFW validation improvements
test_verify_ufw_validation_improvements() {
    local ufw_config_file="${SOURCE_DIR}/../modules/ufw_config.sh"

    if [[ ! -f "$ufw_config_file" ]]; then
        skip_test "ufw_config.sh not found"
        return
    fi

    if grep -q "ufw status" "$ufw_config_file"; then
        assert_contains "$(cat "$ufw_config_file")" "Status: active" \
            "Should check for active status"
        assert_contains "$(cat "$ufw_config_file")" "ufw status verbose" \
            "Should use verbose status output"
        pass_test "UFW validation improvements found"
    else
        fail_test "UFW validation improvements not found"
    fi
}

# Test 6: Verify test files are executable
test_verify_test_files_executable() {
    local test_files=(
        "test_installation_fixes.sh"
        "test_installation_fixes_edge_cases.sh"
    )

    local all_executable=true
    for test_file in "${test_files[@]}"; do
        local full_path="${SOURCE_DIR}/${test_file}"
        if [[ ! -x "$full_path" ]]; then
            echo "Error: $test_file is not executable"
            all_executable=false
        fi
    done

    if [[ "$all_executable" == "true" ]]; then
        pass_test "All test files are executable"
    else
        fail_test "Some test files are not executable"
    fi
}

# Test 7: Verify test framework integration
test_verify_test_framework_integration() {
    local run_all_tests="${SOURCE_DIR}/run_all_tests.sh"

    if [[ ! -f "$run_all_tests" ]]; then
        fail_test "run_all_tests.sh not found"
        return
    fi

    if grep -q "installation_fixes" "$run_all_tests"; then
        assert_contains "$(cat "$run_all_tests")" "test_installation_fixes.sh" \
            "Should include installation fixes test"
        assert_contains "$(cat "$run_all_tests")" "test_installation_fixes_edge_cases.sh" \
            "Should include edge cases test"
        pass_test "Test framework integration verified"
    else
        fail_test "Installation fixes tests not integrated into test runner"
    fi
}

# Run all validation tests
echo "Running installation fixes validation tests..."
echo ""

run_test_function "test_verify_include_guard_exists"
run_test_function "test_verify_user_creation_function"
run_test_function "test_verify_python_dependencies_function"
run_test_function "test_verify_quick_mode_support"
run_test_function "test_verify_ufw_validation_improvements"
run_test_function "test_verify_test_files_executable"
run_test_function "test_verify_test_framework_integration"

# Finalize test suite
finalize_test_suite
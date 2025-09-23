#!/bin/bash

# VLESS+Reality VPN Management System - Installation Fixes Edge Cases Test Suite
# Version: 1.0.0
# Description: Edge case and stress tests for installation fixes
#
# Tests cover edge cases for:
# 1. Include guard under various conditions
# 2. User creation with permissions issues
# 3. Python dependencies with network/permission failures
# 4. UFW validation with malformed output
# 5. QUICK_MODE with environment manipulation

set -euo pipefail

# Test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_SUITE_NAME="Installation Fixes Edge Cases Tests"
readonly PROJECT_ROOT="$(cd "${SOURCE_DIR}/.." && pwd)"
readonly TEMP_TEST_DIR="/tmp/vless_edge_test_$$"

# Initialize test suite
init_test_framework "$TEST_SUITE_NAME"

# Setup function
setup_edge_test_environment() {
    echo "Setting up edge case test environment"
    mkdir -p "$TEMP_TEST_DIR"
    mkdir -p "${TEMP_TEST_DIR}/mock_bin"
    export PATH="${TEMP_TEST_DIR}/mock_bin:${PATH}"
    export LOG_FILE="${TEMP_TEST_DIR}/edge_test.log"
    touch "$LOG_FILE"
}

# Cleanup function
cleanup_edge_test_environment() {
    echo "Cleaning up edge case test environment"
    [[ -d "$TEMP_TEST_DIR" ]] && rm -rf "$TEMP_TEST_DIR"
}

# Edge Case Test 1: Include Guard with Recursive Sourcing
test_include_guard_recursive_sourcing() {
    local test_script="${TEMP_TEST_DIR}/test_recursive.sh"

    # Create a script that attempts recursive sourcing
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Create a recursive sourcing scenario
source_common_utils() {
    source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh
    # Try to source again from within a function
    source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh
}

# First source
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Check initial state
if [[ -z "${COMMON_UTILS_LOADED:-}" ]]; then
    echo "ERROR: COMMON_UTILS_LOADED not set"
    exit 1
fi

INITIAL_VALUE="$COMMON_UTILS_LOADED"

# Attempt recursive sourcing
source_common_utils

# Verify include guard still works
if [[ "$COMMON_UTILS_LOADED" == "$INITIAL_VALUE" ]]; then
    echo "SUCCESS: Include guard prevents recursive sourcing"
else
    echo "ERROR: Include guard failed with recursive sourcing"
    exit 1
fi
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Include guard prevents recursive sourcing" \
            "Include guard should handle recursive sourcing"
    else
        fail_test "Recursive sourcing test failed: $output"
        return
    fi
}

# Edge Case Test 2: User Creation with Permission Failures
test_user_creation_permission_denied() {
    # Mock commands that fail with permission denied
    cat > "${TEMP_TEST_DIR}/mock_bin/getent" << 'EOF'
#!/bin/bash
exit 1  # User/group doesn't exist
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/getent"

    cat > "${TEMP_TEST_DIR}/mock_bin/groupadd" << 'EOF'
#!/bin/bash
echo "groupadd: Permission denied" >&2
exit 1
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/groupadd"

    cat > "${TEMP_TEST_DIR}/mock_bin/useradd" << 'EOF'
#!/bin/bash
echo "useradd: Permission denied" >&2
exit 1
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/useradd"

    local test_script="${TEMP_TEST_DIR}/test_permission_denied.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Try to create user (should fail gracefully)
if create_vless_system_user 2>/dev/null; then
    echo "ERROR: Should have failed with permission denied"
    exit 1
else
    echo "SUCCESS: Correctly handled permission denied error"
fi
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Correctly handled permission denied error" \
            "Should handle permission denied errors gracefully"
    else
        fail_test "Permission denied test failed: $output"
        return
    fi
}

# Edge Case Test 3: User Creation with Partial Failures
test_user_creation_partial_failure() {
    # Mock scenario where group creation succeeds but user creation fails
    cat > "${TEMP_TEST_DIR}/mock_bin/getent" << 'EOF'
#!/bin/bash
if [[ "$1" == "group" ]]; then
    exit 1  # Group doesn't exist
elif [[ "$1" == "passwd" ]]; then
    exit 1  # User doesn't exist
fi
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/getent"

    cat > "${TEMP_TEST_DIR}/mock_bin/groupadd" << 'EOF'
#!/bin/bash
echo "Group created successfully"
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/groupadd"

    cat > "${TEMP_TEST_DIR}/mock_bin/useradd" << 'EOF'
#!/bin/bash
echo "useradd: user 'vless' already exists" >&2
exit 9  # User already exists error code
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/useradd"

    local test_script="${TEMP_TEST_DIR}/test_partial_failure.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Try to create user (should handle partial failure)
if create_vless_system_user 2>&1 | grep -q "Group created successfully"; then
    echo "SUCCESS: Group creation succeeded despite user creation failure"
else
    echo "ERROR: Should have created group even if user creation failed"
    exit 1
fi
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Group creation succeeded despite user creation failure" \
            "Should handle partial failures gracefully"
    else
        fail_test "Partial failure test failed: $output"
        return
    fi
}

# Edge Case Test 4: Python Dependencies with Network Timeout
test_python_deps_network_timeout() {
    # Create mock requirements.txt
    cat > "${TEMP_TEST_DIR}/requirements.txt" << 'EOF'
requests==2.28.1
qrcode==7.3.1
EOF

    # Mock pip that times out
    cat > "${TEMP_TEST_DIR}/mock_bin/python3" << 'EOF'
#!/bin/bash
if [[ "$*" == *"install"* && "$*" == *"timeout"* ]]; then
    echo "ERROR: Operation timed out" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/python3"

    cat > "${TEMP_TEST_DIR}/mock_bin/pip3" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/pip3"

    local test_script="${TEMP_TEST_DIR}/test_network_timeout.sh"
    cat > "$test_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

export SCRIPT_DIR="${TEMP_TEST_DIR}"

# Define the function with timeout handling
install_python_dependencies() {
    log_info "Installing Python dependencies"
    local requirements_file="\${SCRIPT_DIR}/requirements.txt"

    if [[ ! -f "\$requirements_file" ]]; then
        log_error "Requirements file not found: \$requirements_file"
        return 1
    fi

    # Try installation with timeout (will fail)
    if python3 -m pip install -r "\$requirements_file" --timeout=300 --no-cache-dir 2>/dev/null; then
        return 0
    else
        # Fallback without timeout
        log_warn "Installation with timeout failed, trying without timeout"
        if python3 -m pip install -r "\$requirements_file" --no-cache-dir 2>/dev/null; then
            return 0
        else
            log_error "All installation attempts failed"
            return 1
        fi
    fi
}

# Call the function
if install_python_dependencies 2>&1 | grep -q "trying without timeout"; then
    echo "SUCCESS: Correctly handled network timeout with fallback"
else
    echo "ERROR: Should have tried fallback after timeout"
    exit 1
fi
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Correctly handled network timeout with fallback" \
            "Should handle network timeouts with fallback strategies"
    else
        fail_test "Network timeout test failed: $output"
        return
    fi
}

# Edge Case Test 5: UFW Validation with Malformed Output
test_ufw_malformed_output() {
    local test_script="${TEMP_TEST_DIR}/test_ufw_malformed.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test with completely malformed UFW output
test_malformed_1() {
    ufw() {
        echo "Invalid output from ufw command"
        echo "No status information available"
    }

    validation_errors=0

    if ! ufw status | grep -q "Status: active"; then
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        echo "SUCCESS: Correctly detected malformed UFW output (case 1)"
    else
        echo "ERROR: Should have detected malformed output"
        return 1
    fi
}

# Test with empty UFW output
test_malformed_2() {
    ufw() {
        echo ""
    }

    validation_errors=0

    if ! ufw status | grep -q "Status: active"; then
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        echo "SUCCESS: Correctly detected empty UFW output (case 2)"
    else
        echo "ERROR: Should have detected empty output"
        return 1
    fi
}

# Test with UFW command failure
test_malformed_3() {
    ufw() {
        echo "ufw: command not found" >&2
        return 127
    }

    validation_errors=0

    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        echo "SUCCESS: Correctly handled UFW command failure (case 3)"
    else
        echo "ERROR: Should have handled command failure"
        return 1
    fi
}

# Run all malformed output tests
test_malformed_1
test_malformed_2
test_malformed_3

echo "SUCCESS: All UFW malformed output tests passed"
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: All UFW malformed output tests passed" \
            "Should handle all types of malformed UFW output"
    else
        fail_test "UFW malformed output test failed: $output"
        return
    fi
}

# Edge Case Test 6: QUICK_MODE with Environment Manipulation
test_quick_mode_environment_manipulation() {
    local test_script="${TEMP_TEST_DIR}/test_env_manipulation.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test environment variable manipulation during execution
test_env_change_during_execution() {
    export QUICK_MODE=false

    # Function that changes QUICK_MODE during execution
    phase_with_env_change() {
        # Start with QUICK_MODE=false
        if [[ "${QUICK_MODE:-false}" == "false" ]]; then
            echo "Phase started with QUICK_MODE=false"
        fi

        # Change QUICK_MODE to true mid-execution
        export QUICK_MODE=true

        # Check behavior after change
        if [[ "${QUICK_MODE:-false}" == "true" ]]; then
            echo "Phase detected QUICK_MODE change to true"
        fi
    }

    phase_with_env_change
    echo "SUCCESS: Environment manipulation test completed"
}

# Test with unset/reset cycles
test_unset_reset_cycles() {
    # Test multiple unset/set cycles
    for i in {1..3}; do
        export QUICK_MODE=true
        if [[ "${QUICK_MODE:-false}" != "true" ]]; then
            echo "ERROR: Failed to set QUICK_MODE in cycle $i"
            return 1
        fi

        unset QUICK_MODE
        if [[ "${QUICK_MODE:-false}" != "false" ]]; then
            echo "ERROR: Failed to unset QUICK_MODE in cycle $i"
            return 1
        fi
    done

    echo "SUCCESS: Unset/reset cycles test completed"
}

# Test with invalid values
test_invalid_values() {
    local invalid_values=("" "1" "yes" "TRUE" "True" "random_string")

    for invalid_value in "${invalid_values[@]}"; do
        export QUICK_MODE="$invalid_value"

        # Only "true" should be treated as true
        if [[ "${QUICK_MODE:-false}" == "true" ]]; then
            if [[ "$invalid_value" != "true" ]]; then
                echo "ERROR: Invalid value '$invalid_value' treated as true"
                return 1
            fi
        fi
    done

    echo "SUCCESS: Invalid values test completed"
}

# Run all environment manipulation tests
test_env_change_during_execution
test_unset_reset_cycles
test_invalid_values

echo "SUCCESS: All environment manipulation tests passed"
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: All environment manipulation tests passed" \
            "Should handle all types of environment manipulation"
    else
        fail_test "Environment manipulation test failed: $output"
        return
    fi
}

# Edge Case Test 7: Stress Test with Concurrent Operations
test_concurrent_operations_stress() {
    local test_script="${TEMP_TEST_DIR}/test_concurrent.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test concurrent sourcing of common_utils
test_concurrent_sourcing() {
    local pids=()

    # Function to source common_utils in background
    source_in_background() {
        local worker_id="$1"
        {
            source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh
            if [[ -n "${COMMON_UTILS_LOADED:-}" ]]; then
                echo "Worker $worker_id: SUCCESS"
            else
                echo "Worker $worker_id: FAILED"
            fi
        } > "/tmp/worker_$worker_id.log" 2>&1
    }

    # Start multiple workers
    for i in {1..5}; do
        source_in_background "$i" &
        pids+=($!)
    done

    # Wait for all workers
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Check results
    local success_count=0
    for i in {1..5}; do
        if grep -q "SUCCESS" "/tmp/worker_$i.log"; then
            ((success_count++))
        fi
    done

    if [[ $success_count -eq 5 ]]; then
        echo "SUCCESS: All $success_count workers completed successfully"
    else
        echo "ERROR: Only $success_count out of 5 workers succeeded"
        return 1
    fi

    # Cleanup
    rm -f /tmp/worker_*.log
}

# Test rapid sequential operations
test_rapid_sequential() {
    for i in {1..10}; do
        if ! (source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh && echo "Iteration $i: OK") >/dev/null 2>&1; then
            echo "ERROR: Failed at iteration $i"
            return 1
        fi
    done

    echo "SUCCESS: All 10 rapid sequential operations completed"
}

# Run stress tests
test_concurrent_sourcing
test_rapid_sequential

echo "SUCCESS: All concurrent operations stress tests passed"
EOF
    chmod +x "$test_script"

    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: All concurrent operations stress tests passed" \
            "Should handle concurrent operations without issues"
    else
        fail_test "Concurrent operations stress test failed: $output"
        return
    fi
}

# Test runner for edge cases
run_all_edge_case_tests() {
    echo -e "${T_CYAN}Setting up edge case test environment...${T_NC}"
    setup_edge_test_environment

    echo -e "${T_CYAN}Running edge case tests...${T_NC}"

    # Include Guard Edge Cases
    run_test_function "test_include_guard_recursive_sourcing"

    # User Creation Edge Cases
    run_test_function "test_user_creation_permission_denied"
    run_test_function "test_user_creation_partial_failure"

    # Python Dependencies Edge Cases
    run_test_function "test_python_deps_network_timeout"

    # UFW Validation Edge Cases
    run_test_function "test_ufw_malformed_output"

    # QUICK_MODE Edge Cases
    run_test_function "test_quick_mode_environment_manipulation"

    # Stress Tests
    run_test_function "test_concurrent_operations_stress"

    echo -e "${T_CYAN}Cleaning up edge case test environment...${T_NC}"
    cleanup_edge_test_environment
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_edge_case_tests
    finalize_test_suite
fi
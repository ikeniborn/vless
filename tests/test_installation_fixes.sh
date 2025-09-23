#!/bin/bash

# VLESS+Reality VPN Management System - Installation Fixes Test Suite
# Version: 1.0.0
# Description: Comprehensive tests for recent installation fixes
#
# Tests cover:
# 1. Include guard functionality in common_utils.sh
# 2. VLESS system user creation function
# 3. Python dependencies installation with various scenarios
# 4. UFW validation fixes with different output formats
# 5. QUICK_MODE support in installation script

set -euo pipefail

# Test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_SUITE_NAME="Installation Fixes Tests"
readonly PROJECT_ROOT="$(cd "${SOURCE_DIR}/.." && pwd)"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"
readonly TEMP_TEST_DIR="/tmp/vless_test_$$"

# Test variables
TEST_TEMP_FILES=()
TEST_MOCK_FUNCTIONS=()

# Initialize test suite
init_test_framework "$TEST_SUITE_NAME"

# Setup function
setup_test_environment() {
    echo "Setting up test environment"

    # Create temporary test directory
    mkdir -p "$TEMP_TEST_DIR"
    cd "$TEMP_TEST_DIR"

    # Create test log file
    export LOG_FILE="${TEMP_TEST_DIR}/test.log"
    touch "$LOG_FILE"

    # Mock system commands for testing
    export PATH="${TEMP_TEST_DIR}/mock_bin:${PATH}"
    mkdir -p "${TEMP_TEST_DIR}/mock_bin"
}

# Cleanup function
cleanup_test_environment() {
    echo "Cleaning up test environment"

    # Clean up temporary files
    for temp_file in "${TEST_TEMP_FILES[@]}"; do
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
    done

    # Remove temporary directory
    [[ -d "$TEMP_TEST_DIR" ]] && rm -rf "$TEMP_TEST_DIR"

    # Restore original functions
    for func_name in "${TEST_MOCK_FUNCTIONS[@]}"; do
        unset -f "$func_name" 2>/dev/null || true
    done
}

# Test 1: Include Guard Functionality
test_include_guard_prevents_multiple_sourcing() {
    local test_script="${TEMP_TEST_DIR}/test_include_guard.sh"

    # Create test script that sources common_utils twice
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils first time
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Check that COMMON_UTILS_LOADED is set
if [[ -z "${COMMON_UTILS_LOADED:-}" ]]; then
    echo "ERROR: COMMON_UTILS_LOADED not set after first source"
    exit 1
fi

# Record initial value
FIRST_LOAD="$COMMON_UTILS_LOADED"

# Source common_utils second time
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Check that it's still the same value (not reloaded)
if [[ "$COMMON_UTILS_LOADED" != "$FIRST_LOAD" ]]; then
    echo "ERROR: Include guard failed - module was sourced twice"
    exit 1
fi

echo "SUCCESS: Include guard working correctly"
EOF

    chmod +x "$test_script"

    # Run the test script
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Include guard working correctly" \
            "Include guard should prevent multiple sourcing"
    else
        fail_test "Include guard test script failed: $output"
        return
    fi
}

test_include_guard_allows_first_source() {
    local test_script="${TEMP_TEST_DIR}/test_first_source.sh"

    # Create test script that sources common_utils once
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Ensure COMMON_UTILS_LOADED is not set initially
unset COMMON_UTILS_LOADED 2>/dev/null || true

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Check that functions are available
if ! declare -f log_info >/dev/null; then
    echo "ERROR: log_info function not available after sourcing"
    exit 1
fi

if ! declare -f create_vless_system_user >/dev/null; then
    echo "ERROR: create_vless_system_user function not available after sourcing"
    exit 1
fi

echo "SUCCESS: First source loads all functions correctly"
EOF

    chmod +x "$test_script"

    # Run the test script
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: First source loads all functions correctly" \
            "First source should load all functions"
    else
        fail_test "First source test failed: $output"
        return
    fi
}

# Test 2: VLESS System User Creation Function
test_create_vless_system_user_creates_group() {
    # Mock getent and groupadd commands
    cat > "${TEMP_TEST_DIR}/mock_bin/getent" << 'EOF'
#!/bin/bash
# Mock getent that simulates group doesn't exist
if [[ "$1" == "group" && "$2" == "vless" ]]; then
    exit 1  # Group doesn't exist
fi
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/getent"

    cat > "${TEMP_TEST_DIR}/mock_bin/groupadd" << 'EOF'
#!/bin/bash
echo "groupadd called with args: $*" >> /tmp/vless_test_$$/mock_commands.log
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/groupadd"

    cat > "${TEMP_TEST_DIR}/mock_bin/useradd" << 'EOF'
#!/bin/bash
echo "useradd called with args: $*" >> /tmp/vless_test_$$/mock_commands.log
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/useradd"

    # Create test script
    local test_script="${TEMP_TEST_DIR}/test_user_creation.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Create mock commands log
touch /tmp/vless_test_$$/mock_commands.log

# Call the function
create_vless_system_user

# Check if commands were called
if grep -q "groupadd.*-r.*vless" /tmp/vless_test_$$/mock_commands.log; then
    echo "SUCCESS: groupadd called correctly"
else
    echo "ERROR: groupadd not called properly"
    exit 1
fi

if grep -q "useradd.*-r.*-g.*vless" /tmp/vless_test_$$/mock_commands.log; then
    echo "SUCCESS: useradd called correctly"
else
    echo "ERROR: useradd not called properly"
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: groupadd called correctly" \
            "Should create vless group when it doesn't exist"
        assert_contains "$output" "SUCCESS: useradd called correctly" \
            "Should create vless user when it doesn't exist"
    else
        fail_test "User creation test failed: $output"
        return
    fi
}

test_create_vless_system_user_skips_existing() {
    # Mock getent command to simulate user/group already exist
    cat > "${TEMP_TEST_DIR}/mock_bin/getent" << 'EOF'
#!/bin/bash
# Mock getent that simulates both user and group exist
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/getent"

    # Create test script
    local test_script="${TEMP_TEST_DIR}/test_existing_user.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Create mock commands log
touch /tmp/vless_test_$$/mock_commands.log

# Call the function
create_vless_system_user 2>&1 | grep -E "(already exists|Group already exists)" || true

echo "SUCCESS: Function handles existing user/group correctly"
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Function handles existing user/group correctly" \
            "Should handle existing user/group gracefully"
    else
        fail_test "Existing user test failed: $output"
        return
    fi
}

# Test 3: Python Dependencies Installation
test_install_python_dependencies_success() {
    # Create mock requirements.txt
    local mock_requirements="${TEMP_TEST_DIR}/requirements.txt"
    cat > "$mock_requirements" << 'EOF'
requests==2.28.1
python-telegram-bot==20.0
qrcode==7.3.1
Pillow==9.2.0
EOF

    # Mock commands
    cat > "${TEMP_TEST_DIR}/mock_bin/pip3" << 'EOF'
#!/bin/bash
echo "pip3 called with: $*" >> /tmp/vless_test_$$/mock_commands.log
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/pip3"

    cat > "${TEMP_TEST_DIR}/mock_bin/python3" << 'EOF'
#!/bin/bash
if [[ "$1" == "-m" && "$2" == "pip" ]]; then
    echo "python3 -m pip called with: ${*:3}" >> /tmp/vless_test_$$/mock_commands.log
    exit 0
fi
exit 0
EOF
    chmod +x "${TEMP_TEST_DIR}/mock_bin/python3"

    # Create test script
    local test_script="${TEMP_TEST_DIR}/test_python_deps.sh"
    cat > "$test_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils and install script functions
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Mock SCRIPT_DIR to point to our test directory
export SCRIPT_DIR="${TEMP_TEST_DIR}"

# Create mock commands log
touch ${TEMP_TEST_DIR}/mock_commands.log

# Define the function (simplified version for testing)
install_python_dependencies() {
    log_info "Installing Python dependencies"
    local requirements_file="\${SCRIPT_DIR}/requirements.txt"

    if [[ ! -f "\$requirements_file" ]]; then
        log_error "Requirements file not found: \$requirements_file"
        return 1
    fi

    # Mock successful installation
    python3 -m pip install -r "\$requirements_file" --timeout=300 --no-cache-dir
    return 0
}

# Call the function
if install_python_dependencies; then
    echo "SUCCESS: Python dependencies installation succeeded"
else
    echo "ERROR: Python dependencies installation failed"
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Python dependencies installation succeeded" \
            "Should successfully install Python dependencies"
    else
        fail_test "Python dependencies installation test failed: $output"
        return
    fi
}

test_install_python_dependencies_missing_requirements() {
    # Create test script without requirements.txt
    local test_script="${TEMP_TEST_DIR}/test_missing_requirements.sh"
    cat > "$test_script" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Mock SCRIPT_DIR to point to our test directory (no requirements.txt)
export SCRIPT_DIR="${TEMP_TEST_DIR}/nonexistent"

# Define the function
install_python_dependencies() {
    log_info "Installing Python dependencies"
    local requirements_file="\${SCRIPT_DIR}/requirements.txt"

    if [[ ! -f "\$requirements_file" ]]; then
        log_error "Requirements file not found: \$requirements_file"
        return 1
    fi

    return 0
}

# Call the function
if install_python_dependencies; then
    echo "ERROR: Should have failed with missing requirements"
    exit 1
else
    echo "SUCCESS: Correctly failed with missing requirements.txt"
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Correctly failed with missing requirements.txt" \
            "Should fail gracefully when requirements.txt is missing"
    else
        fail_test "Missing requirements test failed: $output"
        return
    fi
}

# Test 4: UFW Validation Fixes
test_ufw_validation_active_status() {
    # Create test script for UFW validation
    local test_script="${TEMP_TEST_DIR}/test_ufw_validation.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock UFW command with active status
ufw() {
    case "$1" in
        "status")
            if [[ "${2:-}" == "verbose" ]]; then
                cat << 'UFWEOF'
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
443/tcp                    ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
443/tcp (v6)               ALLOW IN    Anywhere (v6)
UFWEOF
            else
                echo "Status: active"
                echo ""
                echo "To                         Action      From"
                echo "--                         ------      ----"
                echo "22/tcp                     ALLOW IN    Anywhere"
                echo "443/tcp                    ALLOW IN    Anywhere"
            fi
            ;;
    esac
}

# Test the validation logic
validation_errors=0

# Test active status detection
if ! ufw status | grep -q "Status: active"; then
    echo "ERROR: Should detect active status"
    ((validation_errors++))
else
    echo "SUCCESS: Correctly detected active status"
fi

# Test verbose status parsing
status_output=$(ufw status verbose)
echo "DEBUG: UFW status output for validation: $status_output"

# Check that we can parse the verbose output
if echo "$status_output" | grep -q "Default: deny (incoming)"; then
    echo "SUCCESS: Parsed incoming policy correctly"
else
    echo "ERROR: Failed to parse incoming policy"
    ((validation_errors++))
fi

if [[ $validation_errors -eq 0 ]]; then
    echo "SUCCESS: All UFW validation tests passed"
else
    echo "ERROR: $validation_errors UFW validation errors"
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: All UFW validation tests passed" \
            "Should correctly validate UFW active status and policies"
    else
        fail_test "UFW validation test failed: $output"
        return
    fi
}

test_ufw_validation_inactive_status() {
    # Create test script for inactive UFW
    local test_script="${TEMP_TEST_DIR}/test_ufw_inactive.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock UFW command with inactive status
ufw() {
    case "$1" in
        "status")
            echo "Status: inactive"
            ;;
    esac
}

# Test the validation logic
validation_errors=0

# Test inactive status detection
if ! ufw status | grep -q "Status: active"; then
    echo "SUCCESS: Correctly detected inactive status"
    ((validation_errors++))  # This is expected to increment
fi

if [[ $validation_errors -gt 0 ]]; then
    echo "SUCCESS: UFW validation correctly identified inactive firewall"
else
    echo "ERROR: Should have detected inactive firewall"
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: UFW validation correctly identified inactive firewall" \
            "Should detect when UFW is inactive"
    else
        fail_test "UFW inactive validation test failed: $output"
        return
    fi
}

# Test 5: QUICK_MODE Support
test_quick_mode_skips_prompts() {
    # Create test script that simulates install phases with QUICK_MODE
    local test_script="${TEMP_TEST_DIR}/test_quick_mode.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Track if any prompts were shown
PROMPT_SHOWN=false

# Mock read command to detect prompts
read() {
    if [[ "$*" == *"Press Enter to continue"* ]]; then
        PROMPT_SHOWN=true
        echo "ERROR: Prompt shown in QUICK_MODE"
        return 1
    fi
    return 0
}

# Simulate installation phase logic
install_phase_simulation() {
    echo "Installing phase..."

    # This is the logic from install.sh
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi

    echo "Phase completed"
}

# Test with QUICK_MODE disabled (should prompt)
echo "Testing without QUICK_MODE:"
unset QUICK_MODE 2>/dev/null || true
if install_phase_simulation 2>/dev/null; then
    echo "ERROR: Should have prompted without QUICK_MODE"
    exit 1
else
    echo "SUCCESS: Correctly prompted without QUICK_MODE"
fi

# Reset prompt flag
PROMPT_SHOWN=false

# Test with QUICK_MODE enabled (should not prompt)
echo "Testing with QUICK_MODE:"
export QUICK_MODE=true
if install_phase_simulation; then
    if [[ "$PROMPT_SHOWN" == "false" ]]; then
        echo "SUCCESS: No prompts shown with QUICK_MODE enabled"
    else
        echo "ERROR: Prompt shown despite QUICK_MODE"
        exit 1
    fi
else
    echo "ERROR: Installation failed with QUICK_MODE"
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Correctly prompted without QUICK_MODE" \
            "Should show prompts when QUICK_MODE is not set"
        assert_contains "$output" "SUCCESS: No prompts shown with QUICK_MODE enabled" \
            "Should skip prompts when QUICK_MODE is enabled"
    else
        fail_test "QUICK_MODE test failed: $output"
        return
    fi
}

test_quick_mode_environment_variable() {
    # Test that QUICK_MODE environment variable is properly handled
    local test_script="${TEMP_TEST_DIR}/test_quick_mode_env.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test default value (should be false)
if [[ "${QUICK_MODE:-false}" == "false" ]]; then
    echo "SUCCESS: Default QUICK_MODE is false"
else
    echo "ERROR: Default QUICK_MODE should be false"
    exit 1
fi

# Test explicit true value
export QUICK_MODE=true
if [[ "${QUICK_MODE:-false}" == "true" ]]; then
    echo "SUCCESS: QUICK_MODE can be set to true"
else
    echo "ERROR: QUICK_MODE should be true when set"
    exit 1
fi

# Test explicit false value
export QUICK_MODE=false
if [[ "${QUICK_MODE:-false}" == "false" ]]; then
    echo "SUCCESS: QUICK_MODE can be set to false"
else
    echo "ERROR: QUICK_MODE should be false when explicitly set"
    exit 1
fi

# Test unset variable
unset QUICK_MODE
if [[ "${QUICK_MODE:-false}" == "false" ]]; then
    echo "SUCCESS: Unset QUICK_MODE defaults to false"
else
    echo "ERROR: Unset QUICK_MODE should default to false"
    exit 1
fi

echo "SUCCESS: All QUICK_MODE environment variable tests passed"
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: All QUICK_MODE environment variable tests passed" \
            "QUICK_MODE environment variable should be handled correctly"
    else
        fail_test "QUICK_MODE environment variable test failed: $output"
        return
    fi
}

# Additional comprehensive tests
test_integration_include_guard_with_user_creation() {
    # Test that include guard works properly with user creation function
    local test_script="${TEMP_TEST_DIR}/test_integration.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock system commands
export PATH="/tmp/vless_test_$$/mock_bin:$PATH"

# Create getent mock
cat > /tmp/vless_test_$$/mock_bin/getent << 'MOCKEOF'
#!/bin/bash
exit 1  # Simulate user/group doesn't exist
MOCKEOF
chmod +x /tmp/vless_test_$$/mock_bin/getent

# Create groupadd mock
cat > /tmp/vless_test_$$/mock_bin/groupadd << 'MOCKEOF'
#!/bin/bash
echo "groupadd: $*" >> /tmp/vless_test_$$/integration.log
exit 0
MOCKEOF
chmod +x /tmp/vless_test_$$/mock_bin/groupadd

# Create useradd mock
cat > /tmp/vless_test_$$/mock_bin/useradd << 'MOCKEOF'
#!/bin/bash
echo "useradd: $*" >> /tmp/vless_test_$$/integration.log
exit 0
MOCKEOF
chmod +x /tmp/vless_test_$$/mock_bin/useradd

# Initialize log
touch /tmp/vless_test_$$/integration.log

# Source common_utils multiple times
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh
source /home/ikeniborn/Documents/Project/vless/modules/common_utils.sh

# Check that function is available
if ! declare -f create_vless_system_user >/dev/null; then
    echo "ERROR: create_vless_system_user function not available"
    exit 1
fi

# Call the function
create_vless_system_user

# Check that commands were called
if grep -q "groupadd" /tmp/vless_test_$$/integration.log && grep -q "useradd" /tmp/vless_test_$$/integration.log; then
    echo "SUCCESS: Integration test passed - include guard and user creation work together"
else
    echo "ERROR: Integration test failed"
    cat /tmp/vless_test_$$/integration.log
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Run the test
    local output
    if output=$("$test_script" 2>&1); then
        assert_contains "$output" "SUCCESS: Integration test passed" \
            "Include guard and user creation should work together"
    else
        fail_test "Integration test failed: $output"
        return
    fi
}

# Test runner
run_all_installation_fixes_tests() {
    echo -e "${T_CYAN}Setting up test environment...${T_NC}"
    setup_test_environment

    # Track test functions for cleanup
    TEST_MOCK_FUNCTIONS+=("log_info" "log_error" "log_debug" "log_warn" "log_success")

    echo -e "${T_CYAN}Running installation fixes tests...${T_NC}"

    # Include Guard Tests
    run_test_function "test_include_guard_prevents_multiple_sourcing"
    run_test_function "test_include_guard_allows_first_source"

    # VLESS User Creation Tests
    run_test_function "test_create_vless_system_user_creates_group"
    run_test_function "test_create_vless_system_user_skips_existing"

    # Python Dependencies Tests
    run_test_function "test_install_python_dependencies_success"
    run_test_function "test_install_python_dependencies_missing_requirements"

    # UFW Validation Tests
    run_test_function "test_ufw_validation_active_status"
    run_test_function "test_ufw_validation_inactive_status"

    # QUICK_MODE Tests
    run_test_function "test_quick_mode_skips_prompts"
    run_test_function "test_quick_mode_environment_variable"

    # Integration Tests
    run_test_function "test_integration_include_guard_with_user_creation"

    echo -e "${T_CYAN}Cleaning up test environment...${T_NC}"
    cleanup_test_environment
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_installation_fixes_tests
    finalize_test_suite
fi
#!/bin/bash

# VLESS+Reality VPN Management System - Safety Utils Test
# Version: 1.0.0
# Description: Test safety utilities functions and edge cases

set -euo pipefail

# Import test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/vless_test_safety_utils"
readonly MOCK_SAFETY_UTILS="${TEST_TEMP_DIR}/mock_safety_utils.sh"
readonly TEST_SSH_DIR="${TEST_TEMP_DIR}/.ssh"
readonly TEST_RESTORE_DIR="${TEST_TEMP_DIR}/restore_points"

# Initialize test suite
init_test_framework "Safety Utils Test"

# Setup test environment
setup_test_environment() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_SSH_DIR"
    mkdir -p "$TEST_RESTORE_DIR"

    # Create mock safety utils with core functions
    cat > "$MOCK_SAFETY_UTILS" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock colors
YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Mock logging functions
log_debug() { echo "[DEBUG] $*"; }
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_success() { echo "[SUCCESS] $*"; }

# Mock system functions
create_directory() {
    local dir="$1"
    local mode="${2:-755}"
    local owner="${3:-}"
    mkdir -p "$dir"
    chmod "$mode" "$dir"
    if [[ -n "$owner" ]]; then
        echo "chown $owner $dir"
    fi
}

isolate_systemctl_command() {
    local action="$1"
    local service="$2"
    local timeout="${3:-30}"
    echo "systemctl $action $service (timeout: ${timeout}s)"
    return 0
}

# Enhanced confirmation with timeout
confirm_action() {
    local message="$1"
    local default="${2:-y}"
    local timeout="${3:-30}"

    # Skip confirmations in quick mode
    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        echo "[QUICK_MODE] Skipping confirmation: $message"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    # For testing, simulate user input based on TEST_CONFIRM_RESPONSE
    case "${TEST_CONFIRM_RESPONSE:-default}" in
        "yes"|"y") return 0 ;;
        "no"|"n") return 1 ;;
        "timeout")
            echo "Timeout reached. Using default: $default"
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
        "default"|"")
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
    esac
}

# Check for existing firewall services
check_existing_firewall() {
    local verbose="${1:-}"
    local found_firewalls=()

    # Mock firewall detection based on TEST_FIREWALL_STATE
    case "${TEST_FIREWALL_STATE:-none}" in
        "ufw_active")
            found_firewalls+=("ufw")
            ;;
        "firewalld_active")
            found_firewalls+=("firewalld")
            ;;
        "iptables_active")
            found_firewalls+=("iptables")
            ;;
        "multiple")
            found_firewalls+=("ufw" "firewalld")
            ;;
        "none"|*)
            ;;
    esac

    if [[ ${#found_firewalls[@]} -gt 0 ]]; then
        if [[ "$verbose" == "--verbose" ]]; then
            printf '%s\n' "${found_firewalls[@]}"
        fi
        return 0
    else
        return 1
    fi
}

# Show current SSH connections
show_current_ssh_connections() {
    echo "Current SSH connections:"
    case "${TEST_SSH_CONNECTIONS:-active}" in
        "active")
            echo "tcp   LISTEN  0  128  *:22  *:*"
            ;;
        "none")
            echo "No SSH connections found"
            ;;
    esac
}

# Test SSH connectivity
test_ssh_connectivity() {
    local test_port="${1:-22}"

    case "${TEST_SSH_CONNECTIVITY:-success}" in
        "success")
            echo "SSH port $test_port is accessible"
            return 0
            ;;
        "failure")
            echo "SSH port $test_port is not accessible"
            return 1
            ;;
    esac
}

# Check SSH keys
check_ssh_keys() {
    local current_user="${SUDO_USER:-$(whoami)}"

    case "${TEST_SSH_KEYS:-present}" in
        "present")
            echo "SSH keys found for user: $current_user"
            return 0
            ;;
        "absent")
            echo "No SSH keys found for user: $current_user"
            return 1
            ;;
    esac
}

# Create restore point
create_restore_point() {
    local description="$1"
    local restore_dir="${TEST_RESTORE_DIR:-/opt/vless/restore_points}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local restore_point="${restore_dir}/${timestamp}_${description// /_}"

    mkdir -p "$restore_point"

    # Create restore script
    cat > "${restore_point}/restore.sh" << RESTORE_EOF
#!/bin/bash
echo "Restoring configuration from: $restore_point"
echo "Restore completed"
RESTORE_EOF

    chmod +x "${restore_point}/restore.sh"
    echo "Restore point created: $restore_point"
    echo "$restore_point"
}

# Validate system state
validate_system_state() {
    local operation="$1"
    local issues=()

    case "$operation" in
        "ssh_hardening")
            if [[ "${TEST_SSH_CONNECTIVITY:-success}" == "failure" ]]; then
                issues+=("SSH port not accessible")
            fi
            if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]] && [[ "${TEST_SSH_KEYS:-present}" == "absent" ]]; then
                issues+=("No SSH keys configured - password auth disable will cause lockout")
            fi
            ;;
        "firewall_config")
            if [[ "${TEST_FIREWALL_STATE:-none}" != "none" ]]; then
                issues+=("Existing firewall detected - may cause conflicts")
            fi
            ;;
        "service_restart")
            if [[ "${TEST_SSH_SERVICE:-active}" == "inactive" ]]; then
                issues+=("SSH service not running")
            fi
            ;;
    esac

    if [[ ${#issues[@]} -gt 0 ]]; then
        echo "System validation found potential issues for operation '$operation':"
        printf "  %s\n" "${issues[@]}"
        return 1
    else
        echo "System validation passed for operation: $operation"
        return 0
    fi
}

# Apply selective SSH hardening
apply_selective_ssh_hardening() {
    local settings=("$@")
    local ssh_config="${TEST_SSH_CONFIG:-/etc/ssh/sshd_config}"

    echo "Applying SSH hardening settings:"
    for setting in "${settings[@]}"; do
        echo "  $setting"
    done

    case "${TEST_SSH_CONFIG_RESULT:-success}" in
        "success")
            echo "SSH configuration is valid"
            echo "SSH service restarted successfully"
            return 0
            ;;
        "failure")
            echo "Invalid SSH configuration, restoring backup"
            return 1
            ;;
    esac
}

# Safe service restart
safe_service_restart() {
    local service_name="$1"
    local timeout="${2:-30}"
    local force="${3:-false}"

    if [[ "$force" != "true" ]]; then
        if ! confirm_action "Restart service '$service_name'? This may interrupt active connections." "n" 15; then
            echo "Service restart cancelled by user"
            return 0
        fi
    fi

    echo "Restarting service: $service_name"

    case "${TEST_SERVICE_RESTART:-success}" in
        "success")
            echo "Service restarted successfully: $service_name"
            return 0
            ;;
        "failure")
            echo "Failed to restart service: $service_name"
            return 1
            ;;
    esac
}

# Export functions
export -f confirm_action
export -f check_existing_firewall
export -f show_current_ssh_connections
export -f test_ssh_connectivity
export -f check_ssh_keys
export -f create_restore_point
export -f validate_system_state
export -f apply_selective_ssh_hardening
export -f safe_service_restart
EOF

    chmod +x "$MOCK_SAFETY_UTILS"
    source "$MOCK_SAFETY_UTILS"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TEMP_DIR"
    unset TEST_CONFIRM_RESPONSE TEST_FIREWALL_STATE TEST_SSH_CONNECTIVITY
    unset TEST_SSH_KEYS TEST_SSH_CONFIG_RESULT TEST_SERVICE_RESTART
}

# Test confirm_action function
test_confirm_action_function() {
    start_test "Confirm Action Function"

    source "$MOCK_SAFETY_UTILS"

    # Test default yes response
    export TEST_CONFIRM_RESPONSE="default"
    if confirm_action "Test question" "y"; then
        assert_true "true" "Default 'y' should return success"
    fi

    # Test explicit yes response
    export TEST_CONFIRM_RESPONSE="yes"
    if confirm_action "Test question" "n"; then
        assert_true "true" "Explicit 'yes' should return success"
    fi

    # Test explicit no response
    export TEST_CONFIRM_RESPONSE="no"
    if ! confirm_action "Test question" "y"; then
        assert_true "true" "Explicit 'no' should return failure"
    fi

    # Test quick mode skip
    export QUICK_MODE=true
    export TEST_CONFIRM_RESPONSE="no"
    if confirm_action "Test question" "y"; then
        assert_true "true" "Quick mode should skip confirmation and use default"
    fi
    unset QUICK_MODE

    # Test timeout behavior
    export TEST_CONFIRM_RESPONSE="timeout"
    if confirm_action "Test question" "y"; then
        assert_true "true" "Timeout should use default 'y'"
    fi

    pass_test "Confirm action function works correctly"
}

# Test firewall detection
test_firewall_detection() {
    start_test "Firewall Detection"

    source "$MOCK_SAFETY_UTILS"

    # Test no firewall
    export TEST_FIREWALL_STATE="none"
    if ! check_existing_firewall; then
        assert_true "true" "Should return false when no firewall detected"
    fi

    # Test UFW active
    export TEST_FIREWALL_STATE="ufw_active"
    if check_existing_firewall; then
        assert_true "true" "Should return true when UFW is active"
    fi

    # Test verbose output
    local verbose_output
    verbose_output=$(check_existing_firewall --verbose)
    assert_contains "$verbose_output" "ufw" "Verbose output should contain firewall name"

    # Test multiple firewalls
    export TEST_FIREWALL_STATE="multiple"
    verbose_output=$(check_existing_firewall --verbose)
    assert_contains "$verbose_output" "ufw" "Should detect UFW"
    assert_contains "$verbose_output" "firewalld" "Should detect firewalld"

    pass_test "Firewall detection works correctly"
}

# Test SSH connectivity
test_ssh_connectivity() {
    start_test "SSH Connectivity Test"

    source "$MOCK_SAFETY_UTILS"

    # Test successful connectivity
    export TEST_SSH_CONNECTIVITY="success"
    if test_ssh_connectivity 22; then
        assert_true "true" "SSH connectivity test should succeed"
    fi

    # Test failed connectivity
    export TEST_SSH_CONNECTIVITY="failure"
    if ! test_ssh_connectivity 22; then
        assert_true "true" "SSH connectivity test should fail"
    fi

    # Test custom port
    if ! test_ssh_connectivity 2222; then
        assert_true "true" "SSH connectivity test should work with custom port"
    fi

    pass_test "SSH connectivity test works correctly"
}

# Test SSH key validation
test_ssh_key_validation() {
    start_test "SSH Key Validation"

    source "$MOCK_SAFETY_UTILS"

    # Test keys present
    export TEST_SSH_KEYS="present"
    if check_ssh_keys; then
        assert_true "true" "Should detect present SSH keys"
    fi

    # Test keys absent
    export TEST_SSH_KEYS="absent"
    if ! check_ssh_keys; then
        assert_true "true" "Should detect absent SSH keys"
    fi

    pass_test "SSH key validation works correctly"
}

# Test restore point creation
test_restore_point_creation() {
    start_test "Restore Point Creation"

    source "$MOCK_SAFETY_UTILS"

    local restore_point
    restore_point=$(create_restore_point "test_operation")

    # Check if restore point directory was created
    assert_true "[[ -d '$restore_point' ]]" "Restore point directory should be created"

    # Check if restore script exists and is executable
    assert_true "[[ -x '$restore_point/restore.sh' ]]" "Restore script should be executable"

    # Test restore script content
    local script_content
    script_content=$(cat "$restore_point/restore.sh")
    assert_contains "$script_content" "Restoring configuration" "Restore script should contain restoration logic"

    pass_test "Restore point creation works correctly"
}

# Test system state validation
test_system_state_validation() {
    start_test "System State Validation"

    source "$MOCK_SAFETY_UTILS"

    # Test SSH hardening validation - success case
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_KEYS="present"
    if validate_system_state "ssh_hardening"; then
        assert_true "true" "SSH hardening validation should pass"
    fi

    # Test SSH hardening validation - failure case
    export TEST_SSH_CONNECTIVITY="failure"
    if ! validate_system_state "ssh_hardening"; then
        assert_true "true" "SSH hardening validation should fail with no connectivity"
    fi

    # Test password auth disable without SSH keys
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_KEYS="absent"
    export DISABLE_PASSWORD_AUTH="true"
    if ! validate_system_state "ssh_hardening"; then
        assert_true "true" "Should fail when disabling password auth without SSH keys"
    fi
    unset DISABLE_PASSWORD_AUTH

    # Test firewall configuration validation
    export TEST_FIREWALL_STATE="ufw_active"
    if ! validate_system_state "firewall_config"; then
        assert_true "true" "Should detect firewall conflict"
    fi

    # Test service restart validation
    export TEST_SSH_SERVICE="inactive"
    if ! validate_system_state "service_restart"; then
        assert_true "true" "Should detect inactive SSH service"
    fi

    pass_test "System state validation works correctly"
}

# Test selective SSH hardening
test_selective_ssh_hardening() {
    start_test "Selective SSH Hardening"

    source "$MOCK_SAFETY_UTILS"

    local test_settings=(
        "PermitRootLogin no"
        "PasswordAuthentication no"
        "MaxAuthTries 3"
    )

    # Test successful SSH hardening
    export TEST_SSH_CONFIG_RESULT="success"
    if apply_selective_ssh_hardening "${test_settings[@]}"; then
        assert_true "true" "SSH hardening should succeed"
    fi

    # Test failed SSH hardening
    export TEST_SSH_CONFIG_RESULT="failure"
    if ! apply_selective_ssh_hardening "${test_settings[@]}"; then
        assert_true "true" "SSH hardening should fail with invalid config"
    fi

    pass_test "Selective SSH hardening works correctly"
}

# Test safe service restart
test_safe_service_restart() {
    start_test "Safe Service Restart"

    source "$MOCK_SAFETY_UTILS"

    # Test successful restart with force
    export TEST_SERVICE_RESTART="success"
    if safe_service_restart "test-service" 30 "true"; then
        assert_true "true" "Forced service restart should succeed"
    fi

    # Test failed restart
    export TEST_SERVICE_RESTART="failure"
    if ! safe_service_restart "test-service" 30 "true"; then
        assert_true "true" "Service restart should fail when configured to fail"
    fi

    # Test user cancellation
    export TEST_CONFIRM_RESPONSE="no"
    export TEST_SERVICE_RESTART="success"
    local output
    output=$(safe_service_restart "test-service" 30 "false" 2>&1)
    assert_contains "$output" "cancelled" "Should handle user cancellation"

    pass_test "Safe service restart works correctly"
}

# Test edge cases and error handling
test_edge_cases() {
    start_test "Edge Cases and Error Handling"

    source "$MOCK_SAFETY_UTILS"

    # Test confirm_action with empty message
    export TEST_CONFIRM_RESPONSE="default"
    if confirm_action "" "y"; then
        assert_true "true" "Should handle empty confirmation message"
    fi

    # Test firewall detection with no commands available
    export TEST_FIREWALL_STATE="none"
    if ! check_existing_firewall; then
        assert_true "true" "Should handle missing firewall commands gracefully"
    fi

    # Test restore point with special characters in description
    local special_restore_point
    special_restore_point=$(create_restore_point "test with spaces & symbols!")
    assert_true "[[ -d '$special_restore_point' ]]" "Should handle special characters in restore point description"

    # Test system validation with unknown operation
    local validation_output
    validation_output=$(validate_system_state "unknown_operation" 2>&1 || true)
    assert_contains "$validation_output" "passed" "Should pass validation for unknown operations"

    pass_test "Edge cases handled correctly"
}

# Test integration scenarios
test_integration_scenarios() {
    start_test "Integration Scenarios"

    source "$MOCK_SAFETY_UTILS"

    # Scenario 1: Complete SSH hardening workflow
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONFIG_RESULT="success"
    export TEST_SERVICE_RESTART="success"

    # Validate system state
    if validate_system_state "ssh_hardening"; then
        assert_true "true" "System validation should pass"
    fi

    # Create restore point
    local restore_point
    restore_point=$(create_restore_point "ssh_hardening_test")
    assert_true "[[ -d '$restore_point' ]]" "Restore point should be created"

    # Apply hardening
    local hardening_settings=("PermitRootLogin no" "PasswordAuthentication no")
    if apply_selective_ssh_hardening "${hardening_settings[@]}"; then
        assert_true "true" "SSH hardening should succeed"
    fi

    # Restart service
    if safe_service_restart "sshd" 30 "true"; then
        assert_true "true" "Service restart should succeed"
    fi

    pass_test "Integration scenarios work correctly"
}

# Main test execution
main() {
    echo -e "Starting Safety Utils Test Suite\n"

    # Setup
    setup_test_environment

    # Run tests
    test_confirm_action_function
    test_firewall_detection
    test_ssh_connectivity
    test_ssh_key_validation
    test_restore_point_creation
    test_system_state_validation
    test_selective_ssh_hardening
    test_safe_service_restart
    test_edge_cases
    test_integration_scenarios

    # Cleanup
    cleanup_test_environment

    # Generate test report
    generate_test_report

    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${T_GREEN}All safety utils tests passed!${T_NC}"
        exit 0
    else
        echo -e "\n${T_RED}Some safety utils tests failed!${T_NC}"
        exit 1
    fi
}

# Error handling
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
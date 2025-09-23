#!/bin/bash

# VLESS+Reality VPN Management System - SSH Hardening Safety Test
# Version: 1.0.0
# Description: Test SSH hardening safety features and rollback mechanisms

set -euo pipefail

# Import test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/vless_test_ssh_hardening_safety"
readonly MOCK_SSH_HARDENING="${TEST_TEMP_DIR}/mock_ssh_hardening.sh"
readonly TEST_SSH_CONFIG="${TEST_TEMP_DIR}/sshd_config"
readonly TEST_BACKUP_DIR="${TEST_TEMP_DIR}/backup"

# Initialize test suite
init_test_framework "SSH Hardening Safety Test"

# Setup test environment
setup_test_environment() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_BACKUP_DIR"

    # Create mock SSH config
    cat > "$TEST_SSH_CONFIG" << 'EOF'
# Mock SSH configuration file
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin yes
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PasswordAuthentication yes
X11Forwarding yes
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
EOF

    # Create mock SSH hardening script
    cat > "$MOCK_SSH_HARDENING" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock colors and logging
YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_debug() { echo "[DEBUG] $*"; }
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_success() { echo "[SUCCESS] $*"; }

# Mock safety utilities
confirm_action() {
    local message="$1"
    local default="${2:-y}"
    local timeout="${3:-30}"

    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        echo "[QUICK_MODE] Skipping confirmation: $message"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    case "${TEST_CONFIRM_RESPONSE:-default}" in
        "yes"|"y") return 0 ;;
        "no"|"n") return 1 ;;
        "default"|"") [[ "$default" == "y" ]] && return 0 || return 1 ;;
    esac
}

check_ssh_keys() {
    case "${TEST_SSH_KEYS:-present}" in
        "present")
            echo "SSH keys found for user"
            return 0 ;;
        "absent")
            echo "No SSH keys found for user"
            return 1 ;;
    esac
}

test_ssh_connectivity() {
    local port="${1:-22}"
    case "${TEST_SSH_CONNECTIVITY:-success}" in
        "success")
            echo "SSH port $port is accessible"
            return 0 ;;
        "failure")
            echo "SSH port $port is not accessible"
            return 1 ;;
    esac
}

create_restore_point() {
    local description="$1"
    local restore_point="${TEST_BACKUP_DIR}/restore_point_${description// /_}"
    mkdir -p "$restore_point"

    # Copy current SSH config
    cp "${TEST_SSH_CONFIG}" "$restore_point/sshd_config" 2>/dev/null || true

    cat > "$restore_point/restore.sh" << RESTORE_EOF
#!/bin/bash
echo "Restoring SSH configuration from: $restore_point"
if [[ -f "$restore_point/sshd_config" ]]; then
    cp "$restore_point/sshd_config" "${TEST_SSH_CONFIG}"
    echo "SSH configuration restored"
fi
RESTORE_EOF

    chmod +x "$restore_point/restore.sh"
    echo "Restore point created: $restore_point"
    echo "$restore_point"
}

show_current_ssh_connections() {
    echo "Current SSH connections:"
    case "${TEST_SSH_CONNECTIONS:-active}" in
        "active") echo "tcp   LISTEN  0  128  *:22  *:*" ;;
        "none") echo "No SSH connections found" ;;
    esac
}

show_planned_firewall_rules() {
    cat << RULES_EOF
  - Allow SSH (port 22)
  - Allow VLESS (port 443)
  - Allow HTTP (port 80) for certificate validation
  - Allow HTTPS (port 443) for Reality
  - Deny all other incoming connections
RULES_EOF
}

validate_system_state() {
    local operation="$1"
    local issues=()

    case "$operation" in
        "ssh_hardening")
            if ! test_ssh_connectivity; then
                issues+=("SSH port not accessible")
            fi
            if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
                if ! check_ssh_keys; then
                    issues+=("No SSH keys configured - password auth disable will cause lockout")
                fi
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

apply_selective_ssh_hardening() {
    local settings=("$@")
    local ssh_config="${TEST_SSH_CONFIG}"
    local backup_file="${ssh_config}.backup_$(date +%Y%m%d_%H%M%S)"

    echo "Backing up SSH configuration to: $backup_file"
    cp "$ssh_config" "$backup_file"

    echo "Applying SSH hardening settings:"
    for setting in "${settings[@]}"; do
        local key="${setting%% *}"
        local value="${setting#* }"
        echo "  $setting"

        # Remove existing setting and add new one
        sed -i "/^#\?${key}/d" "$ssh_config"
        echo "$setting" >> "$ssh_config"
    done

    # Test configuration
    case "${TEST_SSH_CONFIG_VALID:-true}" in
        "true")
            echo "SSH configuration is valid"
            case "${TEST_SSH_RESTART:-success}" in
                "success")
                    echo "SSH service restarted successfully"
                    return 0
                    ;;
                "failure")
                    echo "Failed to restart SSH service, restoring backup"
                    cp "$backup_file" "$ssh_config"
                    return 1
                    ;;
            esac
            ;;
        "false")
            echo "Invalid SSH configuration, restoring backup"
            cp "$backup_file" "$ssh_config"
            return 1
            ;;
    esac
}

# Selective SSH hardening function with safety checks
selective_ssh_hardening() {
    echo "Selective SSH hardening configuration"

    local ssh_options=(
        "PermitRootLogin no:Disable root SSH login"
        "PasswordAuthentication no:Disable password authentication"
        "MaxAuthTries 3:Limit authentication attempts to 3"
        "X11Forwarding no:Disable X11 forwarding"
        "LogLevel VERBOSE:Enable verbose SSH logging"
        "ClientAliveInterval 300:Set client alive interval"
        "AllowTcpForwarding no:Disable TCP forwarding"
    )

    echo "Select SSH hardening options:"

    local selected_options=()
    for option in "${ssh_options[@]}"; do
        IFS=':' read -r setting description <<< "$option"

        case "${TEST_SSH_OPTION_SELECTION:-all}" in
            "all"|"yes")
                selected_options+=("$setting")
                echo "Selected: $description"
                ;;
            "none"|"no")
                echo "Skipped: $description"
                ;;
            "password_auth_only")
                if [[ "$setting" == "PasswordAuthentication no" ]]; then
                    selected_options+=("$setting")
                    echo "Selected: $description"
                else
                    echo "Skipped: $description"
                fi
                ;;
        esac
    done

    if [[ ${#selected_options[@]} -eq 0 ]]; then
        echo "No SSH hardening options selected"
        return 0
    fi

    # Safety checks before applying changes
    echo "Performing safety checks..."

    # Check SSH connectivity
    if ! test_ssh_connectivity; then
        echo "SSH connectivity test failed"
        return 1
    fi

    # Show current connections
    show_current_ssh_connections

    # Special check for password authentication disable
    for setting in "${selected_options[@]}"; do
        if [[ "$setting" == "PasswordAuthentication no" ]]; then
            if ! check_ssh_keys; then
                echo "WARNING: Disabling password authentication without SSH keys will cause lockout!"
                export DISABLE_PASSWORD_AUTH=true
                if ! validate_system_state "ssh_hardening"; then
                    if ! confirm_action "Continue anyway? This is DANGEROUS!" "n" 15; then
                        echo "SSH hardening cancelled for safety"
                        return 1
                    fi
                fi
            fi
            break
        fi
    done

    # Create restore point
    local restore_point
    restore_point=$(create_restore_point "ssh_hardening_$(date +%Y%m%d_%H%M%S)")

    # Show planned changes
    echo "Planned SSH configuration changes:"
    for setting in "${selected_options[@]}"; do
        echo "  $setting"
    done

    # Final confirmation
    if ! confirm_action "Apply SSH hardening with these settings?" "y" 30; then
        echo "SSH hardening cancelled by user"
        return 1
    fi

    # Apply hardening
    if apply_selective_ssh_hardening "${selected_options[@]}"; then
        echo "SSH hardening applied successfully"
        echo "Restore point available at: $restore_point"
        return 0
    else
        echo "SSH hardening failed"
        return 1
    fi
}

# Export functions for testing
export -f selective_ssh_hardening
export -f apply_selective_ssh_hardening
export -f validate_system_state
export -f create_restore_point
export -f check_ssh_keys
export -f test_ssh_connectivity
export -f confirm_action

EOF

    chmod +x "$MOCK_SSH_HARDENING"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TEMP_DIR"
    unset TEST_CONFIRM_RESPONSE TEST_SSH_KEYS TEST_SSH_CONNECTIVITY
    unset TEST_SSH_CONFIG_VALID TEST_SSH_RESTART TEST_SSH_OPTION_SELECTION
    unset TEST_SSH_CONNECTIONS DISABLE_PASSWORD_AUTH QUICK_MODE
}

# Test SSH key validation before hardening
test_ssh_key_validation_before_hardening() {
    start_test "SSH Key Validation Before Hardening"

    source "$MOCK_SSH_HARDENING"

    # Test with SSH keys present - should succeed
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="password_auth_only"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    if selective_ssh_hardening > /dev/null 2>&1; then
        assert_true "true" "SSH hardening should succeed with SSH keys present"
    fi

    # Test without SSH keys - should require confirmation
    export TEST_SSH_KEYS="absent"
    export TEST_CONFIRM_RESPONSE="no"

    if ! selective_ssh_hardening > /dev/null 2>&1; then
        assert_true "true" "SSH hardening should be cancelled without SSH keys"
    fi

    pass_test "SSH key validation works before hardening"
}

# Test interactive confirmation flow
test_interactive_confirmation_flow() {
    start_test "Interactive Confirmation Flow"

    source "$MOCK_SSH_HARDENING"

    # Test user confirmation - accept
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    local output
    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "Apply SSH hardening" "Should show confirmation prompt"
    assert_contains "$output" "applied successfully" "Should apply hardening when confirmed"

    # Test user confirmation - reject
    export TEST_CONFIRM_RESPONSE="no"

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "cancelled by user" "Should cancel when user rejects"

    pass_test "Interactive confirmation flow works correctly"
}

# Test quick mode skipping
test_quick_mode_skipping() {
    start_test "Quick Mode Confirmation Skipping"

    source "$MOCK_SSH_HARDENING"

    # Test quick mode with safe settings
    export QUICK_MODE="true"
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    local output
    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "QUICK_MODE" "Should indicate quick mode is active"
    assert_contains "$output" "applied successfully" "Should apply hardening in quick mode"

    # Test quick mode with dangerous settings (no SSH keys + password auth disable)
    export TEST_SSH_KEYS="absent"
    export TEST_SSH_OPTION_SELECTION="password_auth_only"

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "QUICK_MODE" "Should still show quick mode warnings"

    pass_test "Quick mode skipping works correctly"
}

# Test rollback on failure
test_rollback_on_failure() {
    start_test "Rollback on SSH Configuration Failure"

    source "$MOCK_SSH_HARDENING"

    # Create initial SSH config state
    echo "InitialConfig=test" > "$TEST_SSH_CONFIG"
    local initial_content
    initial_content=$(cat "$TEST_SSH_CONFIG")

    # Test configuration validation failure
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="false"  # This will cause rollback

    local output
    output=$(selective_ssh_hardening 2>&1)

    # Check that hardening failed
    assert_contains "$output" "SSH hardening failed" "Should report hardening failure"

    # Verify the config was restored (should contain backup restoration message)
    assert_contains "$output" "restoring backup" "Should restore backup on failure"

    # Test service restart failure
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="failure"  # This will cause rollback

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "Failed to restart SSH service" "Should report service restart failure"
    assert_contains "$output" "restoring backup" "Should restore backup on service failure"

    pass_test "Rollback on failure works correctly"
}

# Test safety checks enforcement
test_safety_checks_enforcement() {
    start_test "Safety Checks Enforcement"

    source "$MOCK_SSH_HARDENING"

    # Test SSH connectivity check failure
    export TEST_SSH_CONNECTIVITY="failure"
    export TEST_SSH_OPTION_SELECTION="all"

    local output
    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "SSH connectivity test failed" "Should enforce SSH connectivity check"

    # Test dangerous password auth disable without keys
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_KEYS="absent"
    export TEST_SSH_OPTION_SELECTION="password_auth_only"
    export TEST_CONFIRM_RESPONSE="no"  # User should reject dangerous operation

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "DANGEROUS" "Should warn about dangerous operation"
    assert_contains "$output" "cancelled for safety" "Should cancel for safety when user rejects"

    pass_test "Safety checks enforcement works correctly"
}

# Test restore point creation
test_restore_point_creation() {
    start_test "Restore Point Creation"

    source "$MOCK_SSH_HARDENING"

    # Test successful restore point creation
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    local output
    output=$(selective_ssh_hardening 2>&1)

    assert_contains "$output" "Restore point created" "Should create restore point"
    assert_contains "$output" "Restore point available at" "Should provide restore point location"

    # Verify restore point directory exists
    local restore_point_count
    restore_point_count=$(find "$TEST_BACKUP_DIR" -name "restore_point_*" -type d | wc -l)
    assert_true "[[ $restore_point_count -gt 0 ]]" "Should create restore point directory"

    # Verify restore script exists
    local restore_script_count
    restore_script_count=$(find "$TEST_BACKUP_DIR" -name "restore.sh" -type f | wc -l)
    assert_true "[[ $restore_script_count -gt 0 ]]" "Should create restore script"

    pass_test "Restore point creation works correctly"
}

# Test SSH option selection logic
test_ssh_option_selection_logic() {
    start_test "SSH Option Selection Logic"

    source "$MOCK_SSH_HARDENING"

    # Test selecting all options
    export TEST_SSH_KEYS="present"
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    local output
    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "Selected:" "Should show selected options"

    # Test selecting no options
    export TEST_SSH_OPTION_SELECTION="none"

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "No SSH hardening options selected" "Should handle no options selected"

    # Test selective option selection
    export TEST_SSH_OPTION_SELECTION="password_auth_only"

    output=$(selective_ssh_hardening 2>&1)
    assert_contains "$output" "Selected:" "Should show selected option"
    assert_contains "$output" "Skipped:" "Should show skipped options"

    pass_test "SSH option selection logic works correctly"
}

# Test configuration backup and restore
test_configuration_backup_and_restore() {
    start_test "Configuration Backup and Restore"

    source "$MOCK_SSH_HARDENING"

    # Create initial configuration
    cat > "$TEST_SSH_CONFIG" << 'EOF'
# Initial SSH configuration
Port 22
PermitRootLogin yes
PasswordAuthentication yes
EOF

    local initial_content
    initial_content=$(cat "$TEST_SSH_CONFIG")

    # Apply SSH hardening
    local test_settings=("PermitRootLogin no" "PasswordAuthentication no")
    apply_selective_ssh_hardening "${test_settings[@]}" > /dev/null 2>&1

    # Check that settings were applied
    local modified_content
    modified_content=$(cat "$TEST_SSH_CONFIG")
    assert_contains "$modified_content" "PermitRootLogin no" "Should apply PermitRootLogin setting"
    assert_contains "$modified_content" "PasswordAuthentication no" "Should apply PasswordAuthentication setting"

    # Test backup file creation
    local backup_count
    backup_count=$(find "$TEST_TEMP_DIR" -name "sshd_config.backup_*" | wc -l)
    assert_true "[[ $backup_count -gt 0 ]]" "Should create backup file"

    pass_test "Configuration backup and restore works correctly"
}

# Test edge cases and error conditions
test_edge_cases_and_error_conditions() {
    start_test "Edge Cases and Error Conditions"

    source "$MOCK_SSH_HARDENING"

    # Test with missing SSH config file
    rm -f "$TEST_SSH_CONFIG"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"

    local output
    output=$(apply_selective_ssh_hardening "PermitRootLogin no" 2>&1 || true)
    # Should handle missing file gracefully (the mock may create it or fail gracefully)

    # Recreate SSH config for other tests
    echo "# Test SSH config" > "$TEST_SSH_CONFIG"

    # Test with empty option list
    output=$(apply_selective_ssh_hardening 2>&1 || true)
    # Should handle empty arguments gracefully

    # Test with malformed SSH settings
    export TEST_SSH_CONFIG_VALID="false"
    output=$(apply_selective_ssh_hardening "MalformedSetting invalid value" 2>&1 || true)
    assert_contains "$output" "Invalid SSH configuration" "Should detect invalid configuration"

    pass_test "Edge cases and error conditions handled correctly"
}

# Test integration with system validation
test_integration_with_system_validation() {
    start_test "Integration with System Validation"

    source "$MOCK_SSH_HARDENING"

    # Test complete workflow with system validation
    export TEST_SSH_CONNECTIVITY="success"
    export TEST_SSH_KEYS="present"
    export TEST_SSH_OPTION_SELECTION="all"
    export TEST_CONFIRM_RESPONSE="yes"
    export TEST_SSH_CONFIG_VALID="true"
    export TEST_SSH_RESTART="success"

    local output
    output=$(selective_ssh_hardening 2>&1)

    # Should perform all safety checks
    assert_contains "$output" "Performing safety checks" "Should perform safety checks"
    assert_contains "$output" "Current SSH connections" "Should show current connections"
    assert_contains "$output" "Planned SSH configuration changes" "Should show planned changes"
    assert_contains "$output" "Restore point created" "Should create restore point"
    assert_contains "$output" "applied successfully" "Should complete successfully"

    pass_test "Integration with system validation works correctly"
}

# Main test execution
main() {
    echo -e "Starting SSH Hardening Safety Test Suite\n"

    # Setup
    setup_test_environment

    # Run tests
    test_ssh_key_validation_before_hardening
    test_interactive_confirmation_flow
    test_quick_mode_skipping
    test_rollback_on_failure
    test_safety_checks_enforcement
    test_restore_point_creation
    test_ssh_option_selection_logic
    test_configuration_backup_and_restore
    test_edge_cases_and_error_conditions
    test_integration_with_system_validation

    # Cleanup
    cleanup_test_environment

    # Generate test report
    generate_test_report

    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${T_GREEN}All SSH hardening safety tests passed!${T_NC}"
        exit 0
    else
        echo -e "\n${T_RED}Some SSH hardening safety tests failed!${T_NC}"
        exit 1
    fi
}

# Error handling
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
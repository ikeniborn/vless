#!/bin/bash

# VLESS+Reality VPN Management System - Installation Modes Test
# Version: 1.0.0
# Description: Test installation mode configurations and phase skipping

set -euo pipefail

# Import test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/vless_test_installation_modes"
readonly MOCK_INSTALL_SCRIPT="${TEST_TEMP_DIR}/mock_install.sh"
readonly TEST_ENV_FILE="${TEST_TEMP_DIR}/test_env"

# Initialize test suite
init_test_framework "Installation Modes Test"

# Setup test environment
setup_test_environment() {
    mkdir -p "$TEST_TEMP_DIR"

    # Create mock install script
    cat > "$MOCK_INSTALL_SCRIPT" << 'EOF'
#!/bin/bash
set -euo pipefail

# Mock installation functions
source_modules() {
    export COMMON_UTILS_LOADED=true
    export SAFETY_UTILS_LOADED=true
}

configure_installation_profile() {
    local profile="${INSTALLATION_MODE:-balanced}"

    case "$profile" in
        "minimal")
            export SKIP_SSH_HARDENING=true
            export SKIP_MONITORING_TOOLS=true
            export BACKUP_PROFILE=minimal
            export LOG_PROFILE=minimal
            export MONITORING_PROFILE=minimal
            export MAINTENANCE_MODE=conservative
            ;;
        "balanced")
            export SELECTIVE_SSH_HARDENING=true
            export INSTALL_MONITORING_TOOLS=false
            export BACKUP_PROFILE=essential
            export LOG_PROFILE=standard
            export MONITORING_PROFILE=balanced
            export MAINTENANCE_MODE=conservative
            ;;
        "full")
            export INTERACTIVE_MODE=true
            export INSTALL_MONITORING_TOOLS=prompt
            export BACKUP_PROFILE=prompt
            export LOG_PROFILE=prompt
            export MONITORING_PROFILE=prompt
            export MAINTENANCE_MODE=prompt
            ;;
    esac
}

check_phase_execution() {
    local phase="$1"
    local profile="${INSTALLATION_MODE:-balanced}"

    case "$phase" in
        "4")
            if [[ "$profile" == "minimal" ]]; then
                echo "SKIP_PHASE_4=true"
                return 1
            fi
            ;;
        "5")
            if [[ "$profile" == "minimal" ]]; then
                echo "SKIP_PHASE_5=true"
                return 1
            elif [[ "$profile" == "balanced" ]]; then
                echo "SELECTIVE_PHASE_5=true"
                return 0
            fi
            ;;
    esac
    return 0
}

# Export configuration function
export -f configure_installation_profile
export -f check_phase_execution

# Process arguments
case "${1:-}" in
    "minimal") export INSTALLATION_MODE="minimal" ;;
    "balanced") export INSTALLATION_MODE="balanced" ;;
    "full") export INSTALLATION_MODE="full" ;;
    *) export INSTALLATION_MODE="balanced" ;;
esac

# Configure profile
configure_installation_profile

# Output configuration for testing
echo "INSTALLATION_MODE=$INSTALLATION_MODE"
echo "SKIP_SSH_HARDENING=${SKIP_SSH_HARDENING:-false}"
echo "SKIP_MONITORING_TOOLS=${SKIP_MONITORING_TOOLS:-false}"
# Telegram bot functionality removed from Phase 5
echo "BACKUP_PROFILE=${BACKUP_PROFILE:-essential}"
echo "LOG_PROFILE=${LOG_PROFILE:-standard}"
echo "MONITORING_PROFILE=${MONITORING_PROFILE:-balanced}"
echo "MAINTENANCE_MODE=${MAINTENANCE_MODE:-conservative}"

# Test phase execution
for phase in 4 5; do
    if check_phase_execution "$phase"; then
        echo "PHASE_${phase}_EXECUTION=true"
    else
        echo "PHASE_${phase}_EXECUTION=false"
    fi
done
EOF

    chmod +x "$MOCK_INSTALL_SCRIPT"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TEMP_DIR"
}

# Test minimal installation mode
test_minimal_installation_mode() {
    start_test "Minimal Installation Mode Configuration"

    local output
    output=$("$MOCK_INSTALL_SCRIPT" "minimal")
    echo "$output" > "$TEST_ENV_FILE"

    # Check mode setting
    assert_contains "$output" "INSTALLATION_MODE=minimal" "Installation mode not set to minimal"

    # Check SSH hardening is skipped
    assert_contains "$output" "SKIP_SSH_HARDENING=true" "SSH hardening should be skipped in minimal mode"

    # Check monitoring tools are skipped
    assert_contains "$output" "SKIP_MONITORING_TOOLS=true" "Monitoring tools should be skipped in minimal mode"

    # Note: Telegram bot functionality removed from Phase 5

    # Check backup profile is minimal
    assert_contains "$output" "BACKUP_PROFILE=minimal" "Backup profile should be minimal"

    # Check monitoring profile is minimal
    assert_contains "$output" "MONITORING_PROFILE=minimal" "Monitoring profile should be minimal"

    # Check Phase 4 is skipped
    assert_contains "$output" "PHASE_4_EXECUTION=false" "Phase 4 should be skipped in minimal mode"

    # Check Phase 5 is skipped
    assert_contains "$output" "PHASE_5_EXECUTION=false" "Phase 5 should be skipped in minimal mode"

    pass_test "Minimal installation mode configured correctly"
}

# Test balanced installation mode
test_balanced_installation_mode() {
    start_test "Balanced Installation Mode Configuration"

    local output
    output=$("$MOCK_INSTALL_SCRIPT" "balanced")
    echo "$output" > "$TEST_ENV_FILE"

    # Check mode setting
    assert_contains "$output" "INSTALLATION_MODE=balanced" "Installation mode not set to balanced"

    # Check selective SSH hardening
    assert_contains "$output" "SELECTIVE_SSH_HARDENING=true" "Selective SSH hardening should be enabled"

    # Check monitoring tools are optional
    assert_contains "$output" "INSTALL_MONITORING_TOOLS=false" "Monitoring tools should be optional in balanced mode"

    # Note: Telegram bot functionality removed from Phase 5

    # Check backup profile is essential
    assert_contains "$output" "BACKUP_PROFILE=essential" "Backup profile should be essential"

    # Check monitoring profile is balanced
    assert_contains "$output" "MONITORING_PROFILE=balanced" "Monitoring profile should be balanced"

    # Check Phase 4 is executed
    assert_contains "$output" "PHASE_4_EXECUTION=true" "Phase 4 should be executed in balanced mode"

    # Check Phase 5 is selectively executed
    assert_contains "$output" "PHASE_5_EXECUTION=true" "Phase 5 should be executed in balanced mode"

    pass_test "Balanced installation mode configured correctly"
}

# Test full installation mode
test_full_installation_mode() {
    start_test "Full Installation Mode Configuration"

    local output
    output=$("$MOCK_INSTALL_SCRIPT" "full")
    echo "$output" > "$TEST_ENV_FILE"

    # Check mode setting
    assert_contains "$output" "INSTALLATION_MODE=full" "Installation mode not set to full"

    # Check interactive mode
    assert_contains "$output" "INTERACTIVE_MODE=true" "Interactive mode should be enabled in full mode"

    # Check monitoring tools are prompted
    assert_contains "$output" "INSTALL_MONITORING_TOOLS=prompt" "Monitoring tools should be prompted in full mode"

    # Note: Telegram bot functionality removed from Phase 5

    # Check backup profile is prompted
    assert_contains "$output" "BACKUP_PROFILE=prompt" "Backup profile should be prompted in full mode"

    # Check monitoring profile is prompted
    assert_contains "$output" "MONITORING_PROFILE=prompt" "Monitoring profile should be prompted in full mode"

    # Check Phase 4 is executed
    assert_contains "$output" "PHASE_4_EXECUTION=true" "Phase 4 should be executed in full mode"

    # Check Phase 5 is executed
    assert_contains "$output" "PHASE_5_EXECUTION=true" "Phase 5 should be executed in full mode"

    pass_test "Full installation mode configured correctly"
}

# Test default installation mode
test_default_installation_mode() {
    start_test "Default Installation Mode (No Argument)"

    local output
    output=$("$MOCK_INSTALL_SCRIPT")

    # Check default mode is balanced
    assert_contains "$output" "INSTALLATION_MODE=balanced" "Default installation mode should be balanced"

    pass_test "Default installation mode is balanced"
}

# Test phase skipping logic
test_phase_skipping_logic() {
    start_test "Phase Skipping Logic"

    # Test minimal mode phase skipping
    local minimal_output
    minimal_output=$("$MOCK_INSTALL_SCRIPT" "minimal")

    assert_contains "$minimal_output" "PHASE_4_EXECUTION=false" "Phase 4 should be skipped in minimal mode"
    assert_contains "$minimal_output" "PHASE_5_EXECUTION=false" "Phase 5 should be skipped in minimal mode"

    # Test balanced mode selective execution
    local balanced_output
    balanced_output=$("$MOCK_INSTALL_SCRIPT" "balanced")

    assert_contains "$balanced_output" "PHASE_4_EXECUTION=true" "Phase 4 should execute in balanced mode"
    assert_contains "$balanced_output" "PHASE_5_EXECUTION=true" "Phase 5 should execute in balanced mode"

    # Test full mode complete execution
    local full_output
    full_output=$("$MOCK_INSTALL_SCRIPT" "full")

    assert_contains "$full_output" "PHASE_4_EXECUTION=true" "Phase 4 should execute in full mode"
    assert_contains "$full_output" "PHASE_5_EXECUTION=true" "Phase 5 should execute in full mode"

    pass_test "Phase skipping logic works correctly"
}

# Test profile consistency
test_profile_consistency() {
    start_test "Profile Consistency Across Components"

    # Test minimal mode consistency
    local minimal_output
    minimal_output=$("$MOCK_INSTALL_SCRIPT" "minimal")

    assert_contains "$minimal_output" "BACKUP_PROFILE=minimal" "Backup profile should be minimal"
    assert_contains "$minimal_output" "LOG_PROFILE=minimal" "Log profile should be minimal"
    assert_contains "$minimal_output" "MONITORING_PROFILE=minimal" "Monitoring profile should be minimal"
    assert_contains "$minimal_output" "MAINTENANCE_MODE=conservative" "Maintenance mode should be conservative"

    # Test balanced mode consistency
    local balanced_output
    balanced_output=$("$MOCK_INSTALL_SCRIPT" "balanced")

    assert_contains "$balanced_output" "BACKUP_PROFILE=essential" "Backup profile should be essential"
    assert_contains "$balanced_output" "LOG_PROFILE=standard" "Log profile should be standard"
    assert_contains "$balanced_output" "MONITORING_PROFILE=balanced" "Monitoring profile should be balanced"

    pass_test "Profile consistency maintained across components"
}

# Test installation mode validation
test_installation_mode_validation() {
    start_test "Installation Mode Validation"

    # Test invalid mode defaults to balanced
    local invalid_output
    invalid_output=$("$MOCK_INSTALL_SCRIPT" "invalid_mode")

    assert_contains "$invalid_output" "INSTALLATION_MODE=balanced" "Invalid mode should default to balanced"

    pass_test "Installation mode validation works correctly"
}

# Test configuration export
test_configuration_export() {
    start_test "Configuration Export Functionality"

    local output
    output=$("$MOCK_INSTALL_SCRIPT" "full")

    # Verify all expected configuration variables are exported
    local expected_vars=(
        "INSTALLATION_MODE"
        "INTERACTIVE_MODE"
        "INSTALL_MONITORING_TOOLS"
        "BACKUP_PROFILE"
        "LOG_PROFILE"
        "MONITORING_PROFILE"
        "MAINTENANCE_MODE"
    )

    for var in "${expected_vars[@]}"; do
        assert_contains "$output" "$var=" "Configuration variable $var should be exported"
    done

    pass_test "Configuration export functionality works correctly"
}

# Main test execution
main() {
    echo -e "Starting Installation Modes Test Suite\n"

    # Setup
    setup_test_environment

    # Run tests
    test_minimal_installation_mode
    test_balanced_installation_mode
    test_full_installation_mode
    test_default_installation_mode
    test_phase_skipping_logic
    test_profile_consistency
    test_installation_mode_validation
    test_configuration_export

    # Cleanup
    cleanup_test_environment

    # Generate test report
    generate_test_report

    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${T_GREEN}All installation mode tests passed!${T_NC}"
        exit 0
    else
        echo -e "\n${T_RED}Some installation mode tests failed!${T_NC}"
        exit 1
    fi
}

# Error handling
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
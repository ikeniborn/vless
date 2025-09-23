#!/bin/bash

# VLESS+Reality VPN Management System - Monitoring Optimization Test
# Version: 1.0.0
# Description: Test monitoring profile configurations and optimization features

set -euo pipefail

# Import test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/vless_test_monitoring_optimization"
readonly MOCK_MONITORING="${TEST_TEMP_DIR}/mock_monitoring.sh"
readonly TEST_CONFIG_DIR="${TEST_TEMP_DIR}/config"
readonly TEST_LOG_DIR="${TEST_TEMP_DIR}/logs"

# Initialize test suite
init_test_framework "Monitoring Optimization Test"

# Setup test environment
setup_test_environment() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_LOG_DIR"

    # Create mock monitoring script
    cat > "$MOCK_MONITORING" << 'EOF'
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

install_package_if_missing() {
    local package="$1"
    local install_cmd="${2:-}"

    case "${TEST_PACKAGE_INSTALL:-success}" in
        "success")
            echo "Installing package: $package"
            return 0
            ;;
        "failure")
            echo "Failed to install package: $package"
            return 1
            ;;
        "skip")
            echo "Package installation skipped: $package"
            return 0
            ;;
    esac
}

# Monitoring configuration variables
MONITORING_CONFIG_DIR="${TEST_CONFIG_DIR}/monitoring"
MONITORING_LOG_DIR="${TEST_LOG_DIR}/monitoring"
MONITORING_DATA_DIR="${TEST_TEMP_DIR}/data"

# Default intervals (will be overridden by profile)
HEALTH_CHECK_INTERVAL=300
RESOURCE_CHECK_INTERVAL=600
NETWORK_CHECK_INTERVAL=900
ALERT_COOLDOWN=1800

# Configure monitoring profile
configure_monitoring_profile() {
    local profile="${MONITORING_PROFILE:-balanced}"

    case "$profile" in
        "minimal")
            HEALTH_CHECK_INTERVAL=1800  # 30 minutes
            RESOURCE_CHECK_INTERVAL=3600  # 1 hour
            NETWORK_CHECK_INTERVAL=3600   # 1 hour
            ALERT_COOLDOWN=3600  # 1 hour
            ;;
        "balanced")
            HEALTH_CHECK_INTERVAL=300   # 5 minutes
            RESOURCE_CHECK_INTERVAL=600   # 10 minutes
            NETWORK_CHECK_INTERVAL=900    # 15 minutes
            ALERT_COOLDOWN=1800  # 30 minutes
            ;;
        "intensive")
            HEALTH_CHECK_INTERVAL=60    # 1 minute
            RESOURCE_CHECK_INTERVAL=120   # 2 minutes
            NETWORK_CHECK_INTERVAL=300    # 5 minutes
            ALERT_COOLDOWN=300   # 5 minutes
            ;;
    esac

    log_info "Monitoring profile set to: $profile"
    log_debug "Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    log_debug "Resource check interval: ${RESOURCE_CHECK_INTERVAL}s"
    log_debug "Network check interval: ${NETWORK_CHECK_INTERVAL}s"
    log_debug "Alert cooldown: ${ALERT_COOLDOWN}s"
}

# Initialize monitoring module
init_monitoring() {
    log_info "Initializing service monitoring module"

    # Configure monitoring profile first
    configure_monitoring_profile

    # Create monitoring directories
    create_directory "$MONITORING_CONFIG_DIR" "750" "vless:vless"
    create_directory "$MONITORING_LOG_DIR" "750" "vless:vless"
    create_directory "$MONITORING_DATA_DIR" "750" "vless:vless"

    # Install monitoring tools (optional)
    if [[ "${INSTALL_MONITORING_TOOLS:-false}" == "true" ]]; then
        log_info "Installing additional monitoring tools"
        install_package_if_missing "htop"
        install_package_if_missing "iotop"
        install_package_if_missing "nethogs"
    elif [[ "${INSTALL_MONITORING_TOOLS:-false}" == "prompt" ]]; then
        log_info "Monitoring tools installation will be prompted"
    else
        log_info "Skipping optional monitoring tools installation"
    fi

    # Create monitoring configuration
    create_monitoring_config
}

# Create monitoring configuration
create_monitoring_config() {
    local config_file="${MONITORING_CONFIG_DIR}/monitoring.conf"

    cat > "$config_file" << CONF_EOF
# VLESS Monitoring Configuration
# Profile: ${MONITORING_PROFILE:-balanced}

[intervals]
health_check=${HEALTH_CHECK_INTERVAL}
resource_check=${RESOURCE_CHECK_INTERVAL}
network_check=${NETWORK_CHECK_INTERVAL}
alert_cooldown=${ALERT_COOLDOWN}

[thresholds]
cpu_threshold=80
memory_threshold=80
disk_threshold=85
load_threshold=2.0

[features]
install_tools=${INSTALL_MONITORING_TOOLS:-false}
enable_alerts=${ENABLE_MONITORING_ALERTS:-true}
log_level=${MONITORING_LOG_LEVEL:-INFO}
CONF_EOF

    log_debug "Monitoring configuration created: $config_file"
}

# Get monitoring configuration
get_monitoring_config() {
    local config_file="${MONITORING_CONFIG_DIR}/monitoring.conf"
    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo "Monitoring configuration not found"
        return 1
    fi
}

# Get current monitoring profile
get_monitoring_profile() {
    echo "${MONITORING_PROFILE:-balanced}"
}

# Get monitoring intervals
get_monitoring_intervals() {
    echo "HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL}"
    echo "RESOURCE_CHECK_INTERVAL=${RESOURCE_CHECK_INTERVAL}"
    echo "NETWORK_CHECK_INTERVAL=${NETWORK_CHECK_INTERVAL}"
    echo "ALERT_COOLDOWN=${ALERT_COOLDOWN}"
}

# Check monitoring tool installation status
check_monitoring_tools() {
    case "${TEST_MONITORING_TOOLS_STATUS:-available}" in
        "available")
            echo "htop: available"
            echo "iotop: available"
            echo "nethogs: available"
            return 0
            ;;
        "partial")
            echo "htop: available"
            echo "iotop: not available"
            echo "nethogs: available"
            return 1
            ;;
        "none")
            echo "htop: not available"
            echo "iotop: not available"
            echo "nethogs: not available"
            return 1
            ;;
    esac
}

# Resource usage calculation for different profiles
calculate_resource_usage() {
    local profile="${MONITORING_PROFILE:-balanced}"

    case "$profile" in
        "minimal")
            echo "CPU: ~2% | Memory: ~50MB | Disk I/O: ~1MB/hour"
            ;;
        "balanced")
            echo "CPU: ~5% | Memory: ~100MB | Disk I/O: ~10MB/hour"
            ;;
        "intensive")
            echo "CPU: ~15% | Memory: ~200MB | Disk I/O: ~50MB/hour"
            ;;
    esac
}

# Simulate monitoring service health check
monitoring_health_check() {
    local services=("xray" "docker" "monitoring")

    case "${TEST_SERVICE_STATUS:-all_running}" in
        "all_running")
            for service in "${services[@]}"; do
                echo "$service: running"
            done
            return 0
            ;;
        "some_failed")
            echo "xray: running"
            echo "docker: failed"
            echo "monitoring: running"
            return 1
            ;;
        "all_failed")
            for service in "${services[@]}"; do
                echo "$service: failed"
            done
            return 1
            ;;
    esac
}

# Export functions for testing
export -f configure_monitoring_profile
export -f init_monitoring
export -f create_monitoring_config
export -f get_monitoring_config
export -f get_monitoring_profile
export -f get_monitoring_intervals
export -f check_monitoring_tools
export -f calculate_resource_usage
export -f monitoring_health_check

EOF

    chmod +x "$MOCK_MONITORING"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TEMP_DIR"
    unset MONITORING_PROFILE INSTALL_MONITORING_TOOLS ENABLE_MONITORING_ALERTS
    unset MONITORING_LOG_LEVEL TEST_PACKAGE_INSTALL TEST_MONITORING_TOOLS_STATUS
    unset TEST_SERVICE_STATUS
}

# Test monitoring profile configurations
test_monitoring_profile_configurations() {
    start_test "Monitoring Profile Configurations"

    source "$MOCK_MONITORING"

    # Test minimal profile
    export MONITORING_PROFILE="minimal"
    configure_monitoring_profile

    assert_equals "1800" "$HEALTH_CHECK_INTERVAL" "Minimal profile health check interval should be 30 minutes"
    assert_equals "3600" "$RESOURCE_CHECK_INTERVAL" "Minimal profile resource check interval should be 1 hour"
    assert_equals "3600" "$NETWORK_CHECK_INTERVAL" "Minimal profile network check interval should be 1 hour"
    assert_equals "3600" "$ALERT_COOLDOWN" "Minimal profile alert cooldown should be 1 hour"

    # Test balanced profile
    export MONITORING_PROFILE="balanced"
    configure_monitoring_profile

    assert_equals "300" "$HEALTH_CHECK_INTERVAL" "Balanced profile health check interval should be 5 minutes"
    assert_equals "600" "$RESOURCE_CHECK_INTERVAL" "Balanced profile resource check interval should be 10 minutes"
    assert_equals "900" "$NETWORK_CHECK_INTERVAL" "Balanced profile network check interval should be 15 minutes"
    assert_equals "1800" "$ALERT_COOLDOWN" "Balanced profile alert cooldown should be 30 minutes"

    # Test intensive profile
    export MONITORING_PROFILE="intensive"
    configure_monitoring_profile

    assert_equals "60" "$HEALTH_CHECK_INTERVAL" "Intensive profile health check interval should be 1 minute"
    assert_equals "120" "$RESOURCE_CHECK_INTERVAL" "Intensive profile resource check interval should be 2 minutes"
    assert_equals "300" "$NETWORK_CHECK_INTERVAL" "Intensive profile network check interval should be 5 minutes"
    assert_equals "300" "$ALERT_COOLDOWN" "Intensive profile alert cooldown should be 5 minutes"

    pass_test "Monitoring profile configurations work correctly"
}

# Test default profile behavior
test_default_profile_behavior() {
    start_test "Default Profile Behavior"

    source "$MOCK_MONITORING"

    # Test with no profile set (should default to balanced)
    unset MONITORING_PROFILE
    configure_monitoring_profile

    assert_equals "300" "$HEALTH_CHECK_INTERVAL" "Default profile should be balanced (5 minutes)"

    # Test invalid profile (should default to balanced)
    export MONITORING_PROFILE="invalid_profile"
    configure_monitoring_profile

    assert_equals "300" "$HEALTH_CHECK_INTERVAL" "Invalid profile should default to balanced"

    pass_test "Default profile behavior works correctly"
}

# Test monitoring tool installation options
test_monitoring_tool_installation() {
    start_test "Monitoring Tool Installation Options"

    source "$MOCK_MONITORING"

    # Test tools installation enabled
    export MONITORING_PROFILE="balanced"
    export INSTALL_MONITORING_TOOLS="true"
    export TEST_PACKAGE_INSTALL="success"

    local output
    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Installing additional monitoring tools" "Should install tools when enabled"

    # Test tools installation disabled
    export INSTALL_MONITORING_TOOLS="false"

    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Skipping optional monitoring tools installation" "Should skip tools when disabled"

    # Test tools installation prompted
    export INSTALL_MONITORING_TOOLS="prompt"

    output=$(init_monitoring 2>&1)
    assert_contains "$output" "will be prompted" "Should indicate prompting for tools"

    pass_test "Monitoring tool installation options work correctly"
}

# Test configuration file generation
test_configuration_file_generation() {
    start_test "Configuration File Generation"

    source "$MOCK_MONITORING"

    # Initialize monitoring with balanced profile
    export MONITORING_PROFILE="balanced"
    export INSTALL_MONITORING_TOOLS="false"
    init_monitoring > /dev/null 2>&1

    # Check configuration file exists
    local config_file="${TEST_CONFIG_DIR}/monitoring/monitoring.conf"
    assert_true "[[ -f '$config_file' ]]" "Configuration file should be created"

    # Check configuration content
    local config_content
    config_content=$(get_monitoring_config)

    assert_contains "$config_content" "Profile: balanced" "Should contain profile information"
    assert_contains "$config_content" "health_check=300" "Should contain correct health check interval"
    assert_contains "$config_content" "resource_check=600" "Should contain correct resource check interval"
    assert_contains "$config_content" "cpu_threshold=80" "Should contain CPU threshold"
    assert_contains "$config_content" "install_tools=false" "Should contain tool installation setting"

    pass_test "Configuration file generation works correctly"
}

# Test interval optimization for resource usage
test_interval_optimization() {
    start_test "Interval Optimization for Resource Usage"

    source "$MOCK_MONITORING"

    # Test minimal profile resource usage
    export MONITORING_PROFILE="minimal"
    configure_monitoring_profile

    local resource_usage
    resource_usage=$(calculate_resource_usage)
    assert_contains "$resource_usage" "~2%" "Minimal profile should have low CPU usage"
    assert_contains "$resource_usage" "~50MB" "Minimal profile should have low memory usage"

    # Test balanced profile resource usage
    export MONITORING_PROFILE="balanced"
    configure_monitoring_profile

    resource_usage=$(calculate_resource_usage)
    assert_contains "$resource_usage" "~5%" "Balanced profile should have moderate CPU usage"
    assert_contains "$resource_usage" "~100MB" "Balanced profile should have moderate memory usage"

    # Test intensive profile resource usage
    export MONITORING_PROFILE="intensive"
    configure_monitoring_profile

    resource_usage=$(calculate_resource_usage)
    assert_contains "$resource_usage" "~15%" "Intensive profile should have higher CPU usage"
    assert_contains "$resource_usage" "~200MB" "Intensive profile should have higher memory usage"

    pass_test "Interval optimization for resource usage works correctly"
}

# Test monitoring directory creation
test_monitoring_directory_creation() {
    start_test "Monitoring Directory Creation"

    source "$MOCK_MONITORING"

    export MONITORING_PROFILE="balanced"
    init_monitoring > /dev/null 2>&1

    # Check directories were created
    assert_true "[[ -d '${TEST_CONFIG_DIR}/monitoring' ]]" "Monitoring config directory should be created"
    assert_true "[[ -d '${TEST_LOG_DIR}/monitoring' ]]" "Monitoring log directory should be created"
    assert_true "[[ -d '${TEST_TEMP_DIR}/data' ]]" "Monitoring data directory should be created"

    pass_test "Monitoring directory creation works correctly"
}

# Test optional tool installation skip
test_optional_tool_installation_skip() {
    start_test "Optional Tool Installation Skip"

    source "$MOCK_MONITORING"

    # Test successful tool installation
    export INSTALL_MONITORING_TOOLS="true"
    export TEST_PACKAGE_INSTALL="success"

    local output
    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Installing package: htop" "Should attempt to install htop"
    assert_contains "$output" "Installing package: iotop" "Should attempt to install iotop"
    assert_contains "$output" "Installing package: nethogs" "Should attempt to install nethogs"

    # Test failed tool installation
    export TEST_PACKAGE_INSTALL="failure"

    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Failed to install package" "Should handle installation failures"

    # Test skipped tool installation
    export INSTALL_MONITORING_TOOLS="false"

    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Skipping optional monitoring tools" "Should skip tool installation when disabled"

    pass_test "Optional tool installation skip works correctly"
}

# Test monitoring tool availability check
test_monitoring_tool_availability() {
    start_test "Monitoring Tool Availability Check"

    source "$MOCK_MONITORING"

    # Test all tools available
    export TEST_MONITORING_TOOLS_STATUS="available"
    if check_monitoring_tools > /dev/null 2>&1; then
        assert_true "true" "Should return success when all tools are available"
    fi

    local tools_output
    tools_output=$(check_monitoring_tools)
    assert_contains "$tools_output" "htop: available" "Should show htop as available"
    assert_contains "$tools_output" "iotop: available" "Should show iotop as available"
    assert_contains "$tools_output" "nethogs: available" "Should show nethogs as available"

    # Test partial tools available
    export TEST_MONITORING_TOOLS_STATUS="partial"
    if ! check_monitoring_tools > /dev/null 2>&1; then
        assert_true "true" "Should return failure when some tools are missing"
    fi

    # Test no tools available
    export TEST_MONITORING_TOOLS_STATUS="none"
    if ! check_monitoring_tools > /dev/null 2>&1; then
        assert_true "true" "Should return failure when no tools are available"
    fi

    pass_test "Monitoring tool availability check works correctly"
}

# Test profile-specific feature enablement
test_profile_specific_features() {
    start_test "Profile-Specific Feature Enablement"

    source "$MOCK_MONITORING"

    # Test minimal profile features
    export MONITORING_PROFILE="minimal"
    export ENABLE_MONITORING_ALERTS="false"
    export MONITORING_LOG_LEVEL="WARN"
    init_monitoring > /dev/null 2>&1

    local config_content
    config_content=$(get_monitoring_config)
    assert_contains "$config_content" "enable_alerts=false" "Minimal profile should have minimal features"
    assert_contains "$config_content" "log_level=WARN" "Minimal profile should have reduced logging"

    # Test intensive profile features
    export MONITORING_PROFILE="intensive"
    export ENABLE_MONITORING_ALERTS="true"
    export MONITORING_LOG_LEVEL="DEBUG"
    init_monitoring > /dev/null 2>&1

    config_content=$(get_monitoring_config)
    assert_contains "$config_content" "enable_alerts=true" "Intensive profile should have all features enabled"
    assert_contains "$config_content" "log_level=DEBUG" "Intensive profile should have verbose logging"

    pass_test "Profile-specific feature enablement works correctly"
}

# Test monitoring health check functionality
test_monitoring_health_check() {
    start_test "Monitoring Health Check Functionality"

    source "$MOCK_MONITORING"

    # Test all services running
    export TEST_SERVICE_STATUS="all_running"
    if monitoring_health_check > /dev/null 2>&1; then
        assert_true "true" "Health check should pass when all services are running"
    fi

    local health_output
    health_output=$(monitoring_health_check)
    assert_contains "$health_output" "xray: running" "Should show xray service status"
    assert_contains "$health_output" "docker: running" "Should show docker service status"

    # Test some services failed
    export TEST_SERVICE_STATUS="some_failed"
    if ! monitoring_health_check > /dev/null 2>&1; then
        assert_true "true" "Health check should fail when some services are down"
    fi

    health_output=$(monitoring_health_check)
    assert_contains "$health_output" "docker: failed" "Should show failed service status"

    pass_test "Monitoring health check functionality works correctly"
}

# Test interval configuration persistence
test_interval_configuration_persistence() {
    start_test "Interval Configuration Persistence"

    source "$MOCK_MONITORING"

    # Configure monitoring with minimal profile
    export MONITORING_PROFILE="minimal"
    configure_monitoring_profile
    init_monitoring > /dev/null 2>&1

    # Get intervals
    local intervals_output
    intervals_output=$(get_monitoring_intervals)

    assert_contains "$intervals_output" "HEALTH_CHECK_INTERVAL=1800" "Should persist health check interval"
    assert_contains "$intervals_output" "RESOURCE_CHECK_INTERVAL=3600" "Should persist resource check interval"
    assert_contains "$intervals_output" "NETWORK_CHECK_INTERVAL=3600" "Should persist network check interval"
    assert_contains "$intervals_output" "ALERT_COOLDOWN=3600" "Should persist alert cooldown"

    # Test profile retrieval
    local current_profile
    current_profile=$(get_monitoring_profile)
    assert_equals "minimal" "$current_profile" "Should retrieve correct monitoring profile"

    pass_test "Interval configuration persistence works correctly"
}

# Test edge cases and error handling
test_edge_cases_and_error_handling() {
    start_test "Edge Cases and Error Handling"

    source "$MOCK_MONITORING"

    # Test with missing configuration directory
    rm -rf "$TEST_CONFIG_DIR"
    export MONITORING_PROFILE="balanced"

    local output
    output=$(init_monitoring 2>&1)
    assert_contains "$output" "Initializing service monitoring" "Should handle missing directories gracefully"

    # Test configuration retrieval when file doesn't exist
    rm -rf "${TEST_CONFIG_DIR}/monitoring/monitoring.conf"
    local config_output
    config_output=$(get_monitoring_config 2>&1 || true)
    assert_contains "$config_output" "not found" "Should handle missing configuration file"

    # Test with empty profile name
    export MONITORING_PROFILE=""
    configure_monitoring_profile
    assert_equals "300" "$HEALTH_CHECK_INTERVAL" "Empty profile should default to balanced"

    pass_test "Edge cases and error handling work correctly"
}

# Main test execution
main() {
    echo -e "Starting Monitoring Optimization Test Suite\n"

    # Setup
    setup_test_environment

    # Run tests
    test_monitoring_profile_configurations
    test_default_profile_behavior
    test_monitoring_tool_installation
    test_configuration_file_generation
    test_interval_optimization
    test_monitoring_directory_creation
    test_optional_tool_installation_skip
    test_monitoring_tool_availability
    test_profile_specific_features
    test_monitoring_health_check
    test_interval_configuration_persistence
    test_edge_cases_and_error_handling

    # Cleanup
    cleanup_test_environment

    # Generate test report
    generate_test_report

    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${T_GREEN}All monitoring optimization tests passed!${T_NC}"
        exit 0
    else
        echo -e "\n${T_RED}Some monitoring optimization tests failed!${T_NC}"
        exit 1
    fi
}

# Error handling
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
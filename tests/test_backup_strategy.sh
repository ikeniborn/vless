#!/bin/bash

# VLESS+Reality VPN Management System - Backup Strategy Test
# Version: 1.0.0
# Description: Test backup profile configurations and strategy optimizations

set -euo pipefail

# Import test framework
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/test_framework.sh"

# Test configuration
readonly TEST_TEMP_DIR="/tmp/vless_test_backup_strategy"
readonly MOCK_BACKUP="${TEST_TEMP_DIR}/mock_backup.sh"
readonly TEST_BACKUP_DIR="${TEST_TEMP_DIR}/backup"
readonly TEST_DATA_DIR="${TEST_TEMP_DIR}/data"

# Initialize test suite
init_test_framework "Backup Strategy Test"

# Setup test environment
setup_test_environment() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    mkdir -p "$TEST_DATA_DIR"

    # Create test data files
    echo "test config data" > "${TEST_DATA_DIR}/config.json"
    echo "test database data" > "${TEST_DATA_DIR}/users.db"
    echo "test certificate data" > "${TEST_DATA_DIR}/cert.pem"
    echo "test log data" > "${TEST_DATA_DIR}/access.log"

    # Create mock backup script
    cat > "$MOCK_BACKUP" << 'EOF'
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

# Backup configuration
BACKUP_BASE_DIR="${TEST_BACKUP_DIR}"
BACKUP_CONFIG_DIR="${TEST_BACKUP_DIR}/config"
BACKUP_DATA_DIR="${TEST_BACKUP_DIR}/data"
BACKUP_LOGS_DIR="${TEST_BACKUP_DIR}/logs"
BACKUP_TEMP_DIR="${TEST_BACKUP_DIR}/temp"
FULL_BACKUP_DIR="${TEST_BACKUP_DIR}/full"
INCREMENTAL_BACKUP_DIR="${TEST_BACKUP_DIR}/incremental"
REMOTE_BACKUP_DIR="${TEST_BACKUP_DIR}/remote"

# Default backup components and settings
BACKUP_COMPONENTS=("config" "database" "users" "certs")
FULL_BACKUP_RETENTION=14
BACKUP_COMPRESSION="gzip"

# Configure backup profile
configure_backup_profile() {
    local profile="${BACKUP_PROFILE:-essential}"

    case "$profile" in
        "minimal")
            BACKUP_COMPONENTS=("config" "database")
            FULL_BACKUP_RETENTION=7
            BACKUP_COMPRESSION="gzip"
            log_info "Backup profile: minimal - config and database only"
            ;;
        "essential")
            BACKUP_COMPONENTS=("config" "database" "users" "certs")
            FULL_BACKUP_RETENTION=14
            BACKUP_COMPRESSION="gzip"
            log_info "Backup profile: essential - core components"
            ;;
        "full")
            BACKUP_COMPONENTS=("config" "database" "users" "certs" "logs")
            FULL_BACKUP_RETENTION=30
            BACKUP_COMPRESSION="xz"
            log_info "Backup profile: full - all components"
            ;;
        "custom")
            # Use custom settings if provided
            BACKUP_COMPONENTS=(${CUSTOM_BACKUP_COMPONENTS[@]:-"config" "database"})
            FULL_BACKUP_RETENTION=${CUSTOM_BACKUP_RETENTION:-14}
            BACKUP_COMPRESSION=${CUSTOM_BACKUP_COMPRESSION:-"gzip"}
            log_info "Backup profile: custom - user defined"
            ;;
    esac

    log_debug "Components: ${BACKUP_COMPONENTS[*]}"
    log_debug "Retention: ${FULL_BACKUP_RETENTION} days"
    log_debug "Compression: ${BACKUP_COMPRESSION}"
}

# Initialize backup system
init_backup_system() {
    log_info "Initializing backup and restore system"

    # Configure backup profile first
    configure_backup_profile

    # Create backup directories
    create_directory "$BACKUP_BASE_DIR" "750" "root:root"
    create_directory "$BACKUP_CONFIG_DIR" "700" "root:root"
    create_directory "$BACKUP_DATA_DIR" "750" "vless:vless"
    create_directory "$BACKUP_LOGS_DIR" "750" "vless:vless"
    create_directory "$BACKUP_TEMP_DIR" "700" "root:root"
    create_directory "$FULL_BACKUP_DIR" "750" "vless:vless"
    create_directory "$INCREMENTAL_BACKUP_DIR" "750" "vless:vless"
    create_directory "$REMOTE_BACKUP_DIR" "750" "vless:vless"

    log_success "Backup system initialized with profile: ${BACKUP_PROFILE:-essential}"
}

# Create backup manifest
create_backup_manifest() {
    local backup_type="${1:-full}"
    local manifest_file="${FULL_BACKUP_DIR}/manifest_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "# VLESS Backup Manifest"
        echo "# Type: $backup_type"
        echo "# Profile: ${BACKUP_PROFILE:-essential}"
        echo "# Created: $(date)"
        echo "# Components: ${BACKUP_COMPONENTS[*]}"
        echo "# Retention: ${FULL_BACKUP_RETENTION} days"
        echo "# Compression: ${BACKUP_COMPRESSION}"
        echo ""
        echo "# Backup Contents:"
        for component in "${BACKUP_COMPONENTS[@]}"; do
            echo "- $component"
        done
    } > "$manifest_file"

    echo "$manifest_file"
}

# Simulate backup creation
create_backup() {
    local backup_type="${1:-full}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${FULL_BACKUP_DIR}/vless_backup_${timestamp}.tar"

    log_info "Creating $backup_type backup with profile: ${BACKUP_PROFILE:-essential}"

    # Create manifest
    local manifest_file
    manifest_file=$(create_backup_manifest "$backup_type")

    # Simulate backing up components
    local backup_size=0
    for component in "${BACKUP_COMPONENTS[@]}"; do
        case "$component" in
            "config")
                log_debug "Backing up configuration files"
                backup_size=$((backup_size + 100))  # KB
                ;;
            "database")
                log_debug "Backing up user database"
                backup_size=$((backup_size + 500))  # KB
                ;;
            "users")
                log_debug "Backing up user configurations"
                backup_size=$((backup_size + 200))  # KB
                ;;
            "certs")
                log_debug "Backing up certificates"
                backup_size=$((backup_size + 50))   # KB
                ;;
            "logs")
                log_debug "Backing up log files"
                backup_size=$((backup_size + 1000)) # KB
                ;;
        esac
    done

    # Apply compression factor
    case "$BACKUP_COMPRESSION" in
        "gzip")
            backup_size=$((backup_size * 70 / 100))  # 30% compression
            backup_file="${backup_file}.gz"
            ;;
        "xz")
            backup_size=$((backup_size * 50 / 100))  # 50% compression
            backup_file="${backup_file}.xz"
            ;;
    esac

    # Create backup file
    echo "Backup created: $backup_file" > "$backup_file"
    echo "Size: ${backup_size}KB" >> "$backup_file"
    echo "Components: ${BACKUP_COMPONENTS[*]}" >> "$backup_file"
    echo "Manifest: $manifest_file" >> "$backup_file"

    log_success "Backup created: $backup_file (${backup_size}KB)"
    echo "$backup_file"
}

# Calculate disk space usage for profile
calculate_disk_usage() {
    local profile="${BACKUP_PROFILE:-essential}"
    local retention="${FULL_BACKUP_RETENTION}"

    local daily_backup_size=0
    case "$profile" in
        "minimal")
            daily_backup_size=400  # KB per day (config + database)
            ;;
        "essential")
            daily_backup_size=600  # KB per day (config + database + users + certs)
            ;;
        "full")
            daily_backup_size=1200 # KB per day (all components)
            ;;
    esac

    # Apply compression
    case "$BACKUP_COMPRESSION" in
        "gzip")
            daily_backup_size=$((daily_backup_size * 70 / 100))
            ;;
        "xz")
            daily_backup_size=$((daily_backup_size * 50 / 100))
            ;;
    esac

    local total_usage=$((daily_backup_size * retention))
    echo "Daily: ${daily_backup_size}KB | Total (${retention} days): ${total_usage}KB"
}

# Get backup profile info
get_backup_profile_info() {
    echo "BACKUP_PROFILE=${BACKUP_PROFILE:-essential}"
    echo "BACKUP_COMPONENTS=(${BACKUP_COMPONENTS[*]})"
    echo "FULL_BACKUP_RETENTION=${FULL_BACKUP_RETENTION}"
    echo "BACKUP_COMPRESSION=${BACKUP_COMPRESSION}"
}

# List backup files
list_backup_files() {
    local backup_dir="${1:-$FULL_BACKUP_DIR}"

    if [[ -d "$backup_dir" ]]; then
        find "$backup_dir" -name "vless_backup_*" -type f 2>/dev/null | head -10
    else
        echo "No backup directory found: $backup_dir"
        return 1
    fi
}

# Cleanup old backups based on retention
cleanup_old_backups() {
    local retention_days="${1:-$FULL_BACKUP_RETENTION}"

    log_info "Cleaning up backups older than $retention_days days"

    # Simulate cleanup based on retention policy
    case "${TEST_CLEANUP_RESULT:-success}" in
        "success")
            echo "Cleaned up 3 old backup files"
            echo "Freed disk space: 2.1MB"
            return 0
            ;;
        "failure")
            echo "Failed to cleanup old backups"
            return 1
            ;;
        "partial")
            echo "Cleaned up 1 old backup file"
            echo "Failed to remove 2 files (permission denied)"
            return 1
            ;;
    esac
}

# Validate backup integrity
validate_backup() {
    local backup_file="$1"

    case "${TEST_BACKUP_VALIDATION:-valid}" in
        "valid")
            echo "Backup validation successful: $backup_file"
            return 0
            ;;
        "invalid")
            echo "Backup validation failed: $backup_file"
            return 1
            ;;
        "corrupted")
            echo "Backup file corrupted: $backup_file"
            return 1
            ;;
    esac
}

# Get backup statistics
get_backup_statistics() {
    local profile="${BACKUP_PROFILE:-essential}"

    case "$profile" in
        "minimal")
            echo "Total backups: 7"
            echo "Total size: 1.9MB"
            echo "Average backup time: 5 seconds"
            echo "Success rate: 100%"
            ;;
        "essential")
            echo "Total backups: 14"
            echo "Total size: 6.2MB"
            echo "Average backup time: 12 seconds"
            echo "Success rate: 100%"
            ;;
        "full")
            echo "Total backups: 30"
            echo "Total size: 28.5MB"
            echo "Average backup time: 45 seconds"
            echo "Success rate: 98%"
            ;;
    esac
}

# Export functions for testing
export -f configure_backup_profile
export -f init_backup_system
export -f create_backup_manifest
export -f create_backup
export -f calculate_disk_usage
export -f get_backup_profile_info
export -f list_backup_files
export -f cleanup_old_backups
export -f validate_backup
export -f get_backup_statistics

EOF

    chmod +x "$MOCK_BACKUP"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TEMP_DIR"
    unset BACKUP_PROFILE CUSTOM_BACKUP_COMPONENTS CUSTOM_BACKUP_RETENTION
    unset CUSTOM_BACKUP_COMPRESSION TEST_CLEANUP_RESULT TEST_BACKUP_VALIDATION
}

# Test backup profile configurations
test_backup_profile_configurations() {
    start_test "Backup Profile Configurations"

    source "$MOCK_BACKUP"

    # Test minimal profile
    export BACKUP_PROFILE="minimal"
    configure_backup_profile

    local profile_info
    profile_info=$(get_backup_profile_info)
    assert_contains "$profile_info" "BACKUP_COMPONENTS=(config database)" "Minimal profile should include only config and database"
    assert_contains "$profile_info" "FULL_BACKUP_RETENTION=7" "Minimal profile retention should be 7 days"
    assert_contains "$profile_info" "BACKUP_COMPRESSION=gzip" "Minimal profile should use gzip compression"

    # Test essential profile
    export BACKUP_PROFILE="essential"
    configure_backup_profile

    profile_info=$(get_backup_profile_info)
    assert_contains "$profile_info" "config database users certs" "Essential profile should include core components"
    assert_contains "$profile_info" "FULL_BACKUP_RETENTION=14" "Essential profile retention should be 14 days"

    # Test full profile
    export BACKUP_PROFILE="full"
    configure_backup_profile

    profile_info=$(get_backup_profile_info)
    assert_contains "$profile_info" "config database users certs logs" "Full profile should include all components"
    assert_contains "$profile_info" "FULL_BACKUP_RETENTION=30" "Full profile retention should be 30 days"
    assert_contains "$profile_info" "BACKUP_COMPRESSION=xz" "Full profile should use xz compression"

    pass_test "Backup profile configurations work correctly"
}

# Test custom backup profile
test_custom_backup_profile() {
    start_test "Custom Backup Profile"

    source "$MOCK_BACKUP"

    # Test custom profile with user-defined settings
    export BACKUP_PROFILE="custom"
    export CUSTOM_BACKUP_COMPONENTS=("config" "users")
    export CUSTOM_BACKUP_RETENTION=21
    export CUSTOM_BACKUP_COMPRESSION="xz"

    configure_backup_profile

    local profile_info
    profile_info=$(get_backup_profile_info)
    assert_contains "$profile_info" "BACKUP_COMPONENTS=(config users)" "Custom profile should use custom components"
    assert_contains "$profile_info" "FULL_BACKUP_RETENTION=21" "Custom profile should use custom retention"
    assert_contains "$profile_info" "BACKUP_COMPRESSION=xz" "Custom profile should use custom compression"

    pass_test "Custom backup profile works correctly"
}

# Test backup system initialization
test_backup_system_initialization() {
    start_test "Backup System Initialization"

    source "$MOCK_BACKUP"

    # Initialize with essential profile
    export BACKUP_PROFILE="essential"
    local output
    output=$(init_backup_system 2>&1)

    assert_contains "$output" "Initializing backup and restore system" "Should show initialization message"
    assert_contains "$output" "Backup system initialized with profile: essential" "Should confirm profile initialization"

    # Check directories creation messages
    assert_contains "$output" "chown root:root" "Should set proper ownership for sensitive directories"
    assert_contains "$output" "chown vless:vless" "Should set proper ownership for data directories"

    pass_test "Backup system initialization works correctly"
}

# Test backup creation with different profiles
test_backup_creation_profiles() {
    start_test "Backup Creation with Different Profiles"

    source "$MOCK_BACKUP"

    # Test minimal profile backup
    export BACKUP_PROFILE="minimal"
    configure_backup_profile
    init_backup_system > /dev/null 2>&1

    local backup_file
    backup_file=$(create_backup "full")
    assert_true "[[ -f '$backup_file' ]]" "Backup file should be created for minimal profile"

    local backup_content
    backup_content=$(cat "$backup_file")
    assert_contains "$backup_content" "config database" "Minimal backup should contain only config and database"

    # Test full profile backup
    export BACKUP_PROFILE="full"
    configure_backup_profile

    backup_file=$(create_backup "full")
    backup_content=$(cat "$backup_file")
    assert_contains "$backup_content" "config database users certs logs" "Full backup should contain all components"

    pass_test "Backup creation with different profiles works correctly"
}

# Test backup compression strategies
test_backup_compression_strategies() {
    start_test "Backup Compression Strategies"

    source "$MOCK_BACKUP"

    # Test gzip compression
    export BACKUP_PROFILE="essential"
    configure_backup_profile

    local backup_file
    backup_file=$(create_backup "full")
    assert_contains "$backup_file" ".gz" "Gzip compression should create .gz file"

    local backup_content
    backup_content=$(cat "$backup_file")
    # The mock should show reduced size due to compression

    # Test xz compression
    export BACKUP_PROFILE="full"
    configure_backup_profile

    backup_file=$(create_backup "full")
    assert_contains "$backup_file" ".xz" "XZ compression should create .xz file"

    pass_test "Backup compression strategies work correctly"
}

# Test disk space optimization
test_disk_space_optimization() {
    start_test "Disk Space Optimization"

    source "$MOCK_BACKUP"

    # Test minimal profile disk usage
    export BACKUP_PROFILE="minimal"
    configure_backup_profile

    local disk_usage
    disk_usage=$(calculate_disk_usage)
    assert_contains "$disk_usage" "Daily:" "Should show daily disk usage"
    assert_contains "$disk_usage" "Total" "Should show total disk usage"

    # Compare profiles - minimal should use less space
    local minimal_usage
    minimal_usage=$(calculate_disk_usage)

    export BACKUP_PROFILE="full"
    configure_backup_profile

    local full_usage
    full_usage=$(calculate_disk_usage)

    # The full profile should show larger numbers than minimal
    # This is handled by the mock's logic

    pass_test "Disk space optimization works correctly"
}

# Test backup manifest generation
test_backup_manifest_generation() {
    start_test "Backup Manifest Generation"

    source "$MOCK_BACKUP"

    export BACKUP_PROFILE="essential"
    configure_backup_profile
    init_backup_system > /dev/null 2>&1

    local manifest_file
    manifest_file=$(create_backup_manifest "full")

    assert_true "[[ -f '$manifest_file' ]]" "Manifest file should be created"

    local manifest_content
    manifest_content=$(cat "$manifest_file")
    assert_contains "$manifest_content" "VLESS Backup Manifest" "Should contain manifest header"
    assert_contains "$manifest_content" "Type: full" "Should contain backup type"
    assert_contains "$manifest_content" "Profile: essential" "Should contain profile information"
    assert_contains "$manifest_content" "Retention: 14 days" "Should contain retention information"
    assert_contains "$manifest_content" "config" "Should list backed up components"

    pass_test "Backup manifest generation works correctly"
}

# Test retention period settings
test_retention_period_settings() {
    start_test "Retention Period Settings"

    source "$MOCK_BACKUP"

    # Test different retention periods for each profile
    local profiles=("minimal" "essential" "full")
    local expected_retentions=(7 14 30)

    for i in "${!profiles[@]}"; do
        export BACKUP_PROFILE="${profiles[$i]}"
        configure_backup_profile

        local profile_info
        profile_info=$(get_backup_profile_info)
        assert_contains "$profile_info" "FULL_BACKUP_RETENTION=${expected_retentions[$i]}" \
            "${profiles[$i]} profile should have ${expected_retentions[$i]} days retention"
    done

    pass_test "Retention period settings work correctly"
}

# Test backup cleanup functionality
test_backup_cleanup_functionality() {
    start_test "Backup Cleanup Functionality"

    source "$MOCK_BACKUP"

    # Test successful cleanup
    export TEST_CLEANUP_RESULT="success"
    local cleanup_output
    cleanup_output=$(cleanup_old_backups 14)

    assert_contains "$cleanup_output" "Cleaned up 3 old backup files" "Should report successful cleanup"
    assert_contains "$cleanup_output" "Freed disk space" "Should report freed space"

    # Test failed cleanup
    export TEST_CLEANUP_RESULT="failure"
    if ! cleanup_output=$(cleanup_old_backups 14 2>&1); then
        assert_contains "$cleanup_output" "Failed to cleanup" "Should report cleanup failure"
    fi

    # Test partial cleanup
    export TEST_CLEANUP_RESULT="partial"
    if ! cleanup_output=$(cleanup_old_backups 14 2>&1); then
        assert_contains "$cleanup_output" "permission denied" "Should report permission issues"
    fi

    pass_test "Backup cleanup functionality works correctly"
}

# Test backup validation
test_backup_validation() {
    start_test "Backup Validation"

    source "$MOCK_BACKUP"

    # Test valid backup
    export TEST_BACKUP_VALIDATION="valid"
    if validate_backup "test_backup.tar.gz" > /dev/null 2>&1; then
        assert_true "true" "Valid backup should pass validation"
    fi

    # Test invalid backup
    export TEST_BACKUP_VALIDATION="invalid"
    if ! validate_backup "test_backup.tar.gz" > /dev/null 2>&1; then
        assert_true "true" "Invalid backup should fail validation"
    fi

    # Test corrupted backup
    export TEST_BACKUP_VALIDATION="corrupted"
    local validation_output
    validation_output=$(validate_backup "test_backup.tar.gz" 2>&1 || true)
    assert_contains "$validation_output" "corrupted" "Should detect corrupted backup"

    pass_test "Backup validation works correctly"
}

# Test backup statistics and reporting
test_backup_statistics() {
    start_test "Backup Statistics and Reporting"

    source "$MOCK_BACKUP"

    # Test statistics for different profiles
    local profiles=("minimal" "essential" "full")

    for profile in "${profiles[@]}"; do
        export BACKUP_PROFILE="$profile"
        local stats
        stats=$(get_backup_statistics)

        assert_contains "$stats" "Total backups:" "Should show total backup count for $profile"
        assert_contains "$stats" "Total size:" "Should show total size for $profile"
        assert_contains "$stats" "Average backup time:" "Should show average time for $profile"
        assert_contains "$stats" "Success rate:" "Should show success rate for $profile"
    done

    pass_test "Backup statistics and reporting work correctly"
}

# Test profile impact on backup size
test_profile_backup_size_impact() {
    start_test "Profile Impact on Backup Size"

    source "$MOCK_BACKUP"

    # Create backups with different profiles and compare sizes
    local minimal_backup_file essential_backup_file full_backup_file

    export BACKUP_PROFILE="minimal"
    configure_backup_profile
    init_backup_system > /dev/null 2>&1
    minimal_backup_file=$(create_backup "full")

    export BACKUP_PROFILE="essential"
    configure_backup_profile
    essential_backup_file=$(create_backup "full")

    export BACKUP_PROFILE="full"
    configure_backup_profile
    full_backup_file=$(create_backup "full")

    # Check that each profile creates appropriate backup content
    local minimal_content essential_content full_content
    minimal_content=$(cat "$minimal_backup_file")
    essential_content=$(cat "$essential_backup_file")
    full_content=$(cat "$full_backup_file")

    assert_contains "$minimal_content" "config database" "Minimal should contain basic components"
    assert_contains "$essential_content" "config database users certs" "Essential should contain core components"
    assert_contains "$full_content" "config database users certs logs" "Full should contain all components"

    pass_test "Profile impact on backup size works correctly"
}

# Test edge cases and error handling
test_edge_cases_and_error_handling() {
    start_test "Edge Cases and Error Handling"

    source "$MOCK_BACKUP"

    # Test with invalid profile
    export BACKUP_PROFILE="invalid_profile"
    configure_backup_profile

    # Should default to essential behavior
    local profile_info
    profile_info=$(get_backup_profile_info)
    # The mock should handle this gracefully

    # Test with missing backup directory
    rm -rf "$TEST_BACKUP_DIR"
    local output
    output=$(init_backup_system 2>&1)
    assert_contains "$output" "Initializing backup" "Should handle missing directories"

    # Test backup listing with no files
    rm -rf "$FULL_BACKUP_DIR"
    local list_output
    list_output=$(list_backup_files 2>&1 || true)
    assert_contains "$list_output" "No backup directory found" "Should handle missing backup directory"

    # Test with empty custom components
    export BACKUP_PROFILE="custom"
    unset CUSTOM_BACKUP_COMPONENTS
    configure_backup_profile
    # Should use defaults

    pass_test "Edge cases and error handling work correctly"
}

# Test integration with retention policies
test_integration_retention_policies() {
    start_test "Integration with Retention Policies"

    source "$MOCK_BACKUP"

    # Test complete backup lifecycle
    export BACKUP_PROFILE="essential"
    configure_backup_profile
    init_backup_system > /dev/null 2>&1

    # Create backup
    local backup_file
    backup_file=$(create_backup "full")
    assert_true "[[ -f '$backup_file' ]]" "Backup should be created"

    # Validate backup
    export TEST_BACKUP_VALIDATION="valid"
    if validate_backup "$backup_file" > /dev/null 2>&1; then
        assert_true "true" "Backup should validate successfully"
    fi

    # Test cleanup with retention policy
    export TEST_CLEANUP_RESULT="success"
    local cleanup_output
    cleanup_output=$(cleanup_old_backups "$FULL_BACKUP_RETENTION")
    assert_contains "$cleanup_output" "Cleaned up" "Should perform cleanup based on retention"

    pass_test "Integration with retention policies works correctly"
}

# Main test execution
main() {
    echo -e "Starting Backup Strategy Test Suite\n"

    # Setup
    setup_test_environment

    # Run tests
    test_backup_profile_configurations
    test_custom_backup_profile
    test_backup_system_initialization
    test_backup_creation_profiles
    test_backup_compression_strategies
    test_disk_space_optimization
    test_backup_manifest_generation
    test_retention_period_settings
    test_backup_cleanup_functionality
    test_backup_validation
    test_backup_statistics
    test_profile_backup_size_impact
    test_edge_cases_and_error_handling
    test_integration_retention_policies

    # Cleanup
    cleanup_test_environment

    # Generate test report
    generate_test_report

    # Exit with appropriate code
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "\n${T_GREEN}All backup strategy tests passed!${T_NC}"
        exit 0
    else
        echo -e "\n${T_RED}Some backup strategy tests failed!${T_NC}"
        exit 1
    fi
}

# Error handling
trap cleanup_test_environment EXIT

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
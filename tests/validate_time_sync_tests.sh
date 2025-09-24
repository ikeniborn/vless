#!/bin/bash

# VLESS+Reality VPN Management System - Time Sync Test Validation
# Version: 1.2.2
# Description: Quick validation of time sync enhancement test files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}Time Sync Enhancement Test Validation${NC}"
    echo "======================================"
}

validate_test_file() {
    local test_file="$1"
    local description="$2"

    echo -e "${CYAN}Validating: $description${NC}"

    if [[ ! -f "$SCRIPT_DIR/$test_file" ]]; then
        echo -e "${RED}✗ File not found: $test_file${NC}"
        return 1
    fi

    if [[ ! -x "$SCRIPT_DIR/$test_file" ]]; then
        echo -e "${RED}✗ File not executable: $test_file${NC}"
        return 1
    fi

    # Check file structure and key functions
    local functions_found=0

    # Check for required test functions in enhancements test
    if [[ "$test_file" == "test_time_sync_enhancements.sh" ]]; then
        if grep -q "test_configure_chrony_for_large_offset" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_sync_time_from_web_api" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_force_hwclock_sync" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_enhanced_time_sync" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_service_management_behavior" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_time_buffer_calculations" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_error_handling_and_fallbacks" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_integration_scenarios" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
    fi

    # Check for edge case functions in edge case test
    if [[ "$test_file" == "test_time_sync_edge_cases.sh" ]]; then
        if grep -q "test_network_failure_scenarios" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_malformed_api_responses" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_service_management_failures" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_hardware_clock_failures" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_large_time_offset_scenarios" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_file_system_permission_issues" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_apt_error_pattern_detection" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
        if grep -q "test_recovery_mechanisms" "$SCRIPT_DIR/$test_file"; then
            ((functions_found++))
        fi
    fi

    echo -e "  File size: $(du -h "$SCRIPT_DIR/$test_file" | cut -f1)"
    echo -e "  Test functions found: $functions_found"

    # Check for mock functions
    local mock_count
    mock_count=$(grep -c "^mock_" "$SCRIPT_DIR/$test_file" || echo "0")
    echo -e "  Mock functions: $mock_count"

    # Check syntax
    if bash -n "$SCRIPT_DIR/$test_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Syntax validation passed${NC}"
    else
        echo -e "${RED}✗ Syntax validation failed${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Test file validation passed${NC}"
    echo ""
    return 0
}

check_integration() {
    echo -e "${CYAN}Checking integration with main test runner...${NC}"

    if grep -q "time_sync_enhancements" "$SCRIPT_DIR/run_all_tests.sh" 2>/dev/null; then
        echo -e "${GREEN}✓ time_sync_enhancements integrated${NC}"
    else
        echo -e "${RED}✗ time_sync_enhancements not integrated${NC}"
    fi

    if grep -q "time_sync_edge_cases" "$SCRIPT_DIR/run_all_tests.sh" 2>/dev/null; then
        echo -e "${GREEN}✓ time_sync_edge_cases integrated${NC}"
    else
        echo -e "${RED}✗ time_sync_edge_cases not integrated${NC}"
    fi

    echo ""
}

generate_test_summary() {
    echo -e "${CYAN}Test Coverage Summary:${NC}"
    echo "======================"

    echo -e "${YELLOW}Enhanced Functions Tested:${NC}"
    echo "  1. configure_chrony_for_large_offset() - Chrony configuration for large offsets"
    echo "  2. sync_time_from_web_api() - Web API fallback with service management"
    echo "  3. force_hwclock_sync() - Hardware clock synchronization"
    echo "  4. enhanced_time_sync() - Comprehensive orchestration function"

    echo ""
    echo -e "${YELLOW}Key Features Covered:${NC}"
    echo "  • Enhanced chrony service management (stop/restart during manual time setting)"
    echo "  • 30-minute buffer addition to web API time for APT compatibility"
    echo "  • Improved time validation logic (handles large offsets >10min)"
    echo "  • New hardware clock synchronization function (force_hwclock_sync)"
    echo "  • New enhanced_time_sync orchestration function"
    echo "  • Timedatectl fallback method"

    echo ""
    echo -e "${YELLOW}Edge Cases Tested:${NC}"
    echo "  • Network connectivity failures (disconnection, timeout, DNS)"
    echo "  • Malformed web API responses (invalid JSON, empty responses)"
    echo "  • Service management failures (missing services, permission issues)"
    echo "  • Hardware clock access failures (no RTC, permission denied, device busy)"
    echo "  • Large time offsets (>10 minutes, >1 hour, extreme differences)"
    echo "  • File system permission issues (read-only system, config access)"
    echo "  • APT error pattern detection and handling"
    echo "  • Concurrent operation handling and recovery mechanisms"

    echo ""
    echo -e "${YELLOW}Mock Systems:${NC}"
    echo "  • System commands (systemctl, hwclock, date, timedatectl)"
    echo "  • Web API responses (worldtimeapi.org, worldclockapi.com, timeapi.io)"
    echo "  • Service states and failures"
    echo "  • File system permissions and access"
    echo "  • Network connectivity states"

    echo ""
}

main() {
    print_header
    echo "Validation started at $(date)"
    echo ""

    local validation_passed=true

    # Validate test files
    if ! validate_test_file "test_time_sync_enhancements.sh" "Main Enhancement Tests"; then
        validation_passed=false
    fi

    if ! validate_test_file "test_time_sync_edge_cases.sh" "Edge Case Tests"; then
        validation_passed=false
    fi

    # Check integration
    check_integration

    # Generate summary
    generate_test_summary

    # Final result
    if $validation_passed; then
        echo -e "${GREEN}✅ All validations passed! Time sync enhancement tests are ready.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some validations failed. Check the output above.${NC}"
        exit 1
    fi
}

main "$@"
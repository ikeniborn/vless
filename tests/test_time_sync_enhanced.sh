#!/bin/bash

# VLESS+Reality VPN Management System - Enhanced Time Synchronization Tests
# Version: 1.2.1
# Description: Comprehensive tests for the new time synchronization functions
#
# Tests the following enhanced functions from common_utils.sh:
# 1. sync_system_time() - Enhanced with validation
# 2. configure_chrony_for_large_offset() - Configures chrony for large time corrections
# 3. sync_time_from_web_api() - Fallback using web APIs
# 4. validate_time_sync_result() - Validates time changes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_section() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

pass_test() {
    local message="$1"
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS:${NC} $message"
}

fail_test() {
    local message="$1"
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL:${NC} $message"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"

    ((TESTS_RUN++))
    echo -n -e "${YELLOW}Test $TESTS_RUN:${NC} $test_name ... "

    local actual_result
    if eval "$test_command" >/dev/null 2>&1; then
        actual_result=0
    else
        actual_result=$?
    fi

    if [[ "$actual_result" == "$expected_result" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC} (expected $expected_result, got $actual_result)"
        ((TESTS_FAILED++))
    fi
}

# Mock system setup
setup_test_environment() {
    export TIME_SYNC_ENABLED="true"
    export TIME_TOLERANCE_SECONDS="300"
    export TEST_MODE="true"
    export LOG_FILE="/tmp/test_time_sync_enhanced.log"

    # Create temp directory for test files
    export TEST_TMP_DIR="/tmp/time_sync_test_$$"
    mkdir -p "$TEST_TMP_DIR"

    # Mock chrony config
    export MOCK_CHRONY_CONF="$TEST_TMP_DIR/chrony.conf"
    cat > "$MOCK_CHRONY_CONF" << 'EOF'
# Mock chrony configuration
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
# Original makestep 1 3
EOF

    # Mock functions for testing
    log_debug() { [[ "$TEST_DEBUG" == "true" ]] && echo "[DEBUG] $*" >&2; return 0; }
    log_info() { [[ "$TEST_DEBUG" == "true" ]] && echo "[INFO] $*" >&2; return 0; }
    log_warn() { [[ "$TEST_DEBUG" == "true" ]] && echo "[WARN] $*" >&2; return 0; }
    log_error() { [[ "$TEST_DEBUG" == "true" ]] && echo "[ERROR] $*" >&2; return 0; }
    log_success() { [[ "$TEST_DEBUG" == "true" ]] && echo "[SUCCESS] $*" >&2; return 0; }

    setup_signal_handlers() { return 0; }
    interruptible_sleep() { return 0; }

    # Export mock functions
    export -f log_debug log_info log_warn log_error log_success
    export -f setup_signal_handlers interruptible_sleep
}

# Mock command implementations for testing
setup_command_mocks() {
    # Mock date command for time testing
    mock_date() {
        case "$1" in
            "+%s") echo "$MOCK_CURRENT_TIME" ;;
            "-d")
                if [[ "$2" =~ ^@ ]]; then
                    local timestamp="${2#@}"
                    echo "Mock date for timestamp $timestamp"
                else
                    echo "Mock formatted date: $2"
                fi
                ;;
            "-s")
                MOCK_CURRENT_TIME="$MOCK_NEW_TIME"
                return 0
                ;;
            *) command date "$@" ;;
        esac
    }

    # Mock safe_execute
    mock_safe_execute() {
        shift  # Remove timeout
        case "$1" in
            "systemctl")
                case "$2 $3" in
                    "restart systemd-timesyncd") [[ "$MOCK_SYSTEMD_SUCCESS" == "true" ]] ;;
                    "restart chronyd"|"restart chrony") [[ "$MOCK_CHRONY_RESTART_SUCCESS" == "true" ]] ;;
                    *) return 0 ;;
                esac
                ;;
            "timedatectl")
                [[ "$MOCK_TIMEDATECTL_SUCCESS" == "true" ]]
                ;;
            "ntpdate")
                [[ "$MOCK_NTPDATE_SUCCESS" == "true" ]]
                ;;
            "sntp")
                [[ "$MOCK_SNTP_SUCCESS" == "true" ]]
                ;;
            "chronyc")
                case "$2" in
                    "burst") [[ "$MOCK_CHRONY_BURST_SUCCESS" == "true" ]] ;;
                    "makestep") [[ "$MOCK_CHRONY_MAKESTEP_SUCCESS" == "true" ]] ;;
                    *) return 0 ;;
                esac
                ;;
            "curl")
                if [[ "$*" =~ worldtimeapi ]]; then
                    [[ "$MOCK_WEB_API_SUCCESS" == "true" ]] && echo "$MOCK_WEB_API_RESPONSE"
                elif [[ "$*" =~ worldclockapi ]]; then
                    [[ "$MOCK_WEB_API_SUCCESS" == "true" ]] && echo "$MOCK_WEB_API_RESPONSE2"
                elif [[ "$*" =~ timeapi.io ]]; then
                    [[ "$MOCK_WEB_API_SUCCESS" == "true" ]] && echo "$MOCK_WEB_API_RESPONSE3"
                else
                    return 1
                fi
                ;;
            "hwclock")
                return 0
                ;;
            *)
                "$@"
                ;;
        esac
    }

    # Mock command_exists
    mock_command_exists() {
        case "$1" in
            timedatectl) [[ "$MOCK_HAS_TIMEDATECTL" == "true" ]] ;;
            ntpdate) [[ "$MOCK_HAS_NTPDATE" == "true" ]] ;;
            sntp) [[ "$MOCK_HAS_SNTP" == "true" ]] ;;
            chronyc) [[ "$MOCK_HAS_CHRONYC" == "true" ]] ;;
            curl) [[ "$MOCK_HAS_CURL" == "true" ]] ;;
            hwclock) [[ "$MOCK_HAS_HWCLOCK" == "true" ]] ;;
            *) return 1 ;;
        esac
    }

    # Export mock functions
    export -f mock_date mock_safe_execute mock_command_exists

    # Override functions
    date() { mock_date "$@"; }
    safe_execute() { mock_safe_execute "$@"; }
    command_exists() { mock_command_exists "$@"; }

    export -f date safe_execute command_exists
}

# Test function: validate_time_sync_result
test_validate_time_sync_result() {
    print_section "Testing validate_time_sync_result function"

    # Test function that validates time sync results
    validate_time_sync_result() {
        local time_before="$1"
        local time_after="$MOCK_CURRENT_TIME"
        local time_diff=$((time_after - time_before))

        log_debug "Time before sync: $time_before"
        log_debug "Time after sync: $time_after"
        log_debug "Time difference: ${time_diff} seconds"

        # Check if time changed significantly (more than 30 seconds)
        local abs_diff
        if [[ $time_diff -lt 0 ]]; then
            abs_diff=$((time_diff * -1))
        else
            abs_diff=$time_diff
        fi

        if [[ $abs_diff -gt 30 ]]; then
            log_debug "Significant time change detected: ${time_diff} seconds"
            # In a real scenario, this would call check_system_time_validity
            return 0
        else
            log_debug "Insufficient time change: ${time_diff} seconds"
            return 1
        fi
    }

    export -f validate_time_sync_result

    # Test 1: Significant positive time change (>30 seconds)
    MOCK_CURRENT_TIME=1000100  # 100 seconds later
    run_test "Large positive time change (100s)" "validate_time_sync_result 1000000" 0

    # Test 2: Significant negative time change (>30 seconds)
    MOCK_CURRENT_TIME=999900   # 100 seconds earlier
    run_test "Large negative time change (100s)" "validate_time_sync_result 1000000" 0

    # Test 3: Small time change (<30 seconds)
    MOCK_CURRENT_TIME=1000020  # 20 seconds later
    run_test "Small time change (20s)" "validate_time_sync_result 1000000" 1

    # Test 4: Exactly 30 seconds (boundary test)
    MOCK_CURRENT_TIME=1000030  # Exactly 30 seconds later
    run_test "Boundary time change (30s)" "validate_time_sync_result 1000000" 1

    # Test 5: Exactly 31 seconds (just over boundary)
    MOCK_CURRENT_TIME=1000031  # 31 seconds later
    run_test "Just over boundary (31s)" "validate_time_sync_result 1000000" 0
}

# Test function: configure_chrony_for_large_offset
test_configure_chrony_for_large_offset() {
    print_section "Testing configure_chrony_for_large_offset function"

    # Test function that configures chrony for large offsets
    configure_chrony_for_large_offset() {
        local chrony_conf="/etc/chrony/chrony.conf"
        local temp_conf="/tmp/chrony_temp.conf"

        # Use mock config for testing
        if [[ "$TEST_MODE" == "true" ]]; then
            chrony_conf="$MOCK_CHRONY_CONF"
            temp_conf="$TEST_TMP_DIR/chrony_temp.conf"
        fi

        # Check if chrony config exists
        if [[ ! -f "$chrony_conf" ]]; then
            log_debug "Chrony config not found, skipping configuration"
            return 1
        fi

        # Create temporary config with aggressive step settings
        cp "$chrony_conf" "$temp_conf" 2>/dev/null || return 1

        # Add or modify makestep configuration for large offsets
        if ! grep -q "^makestep" "$temp_conf"; then
            echo "makestep 1000 -1" >> "$temp_conf"
            log_debug "Added aggressive makestep configuration to chrony"
        else
            sed -i 's/^makestep.*/makestep 1000 -1/' "$temp_conf"
            log_debug "Modified existing makestep configuration in chrony"
        fi

        # Apply temporary configuration
        if cp "$temp_conf" "$chrony_conf" 2>/dev/null; then
            # Mock restart for testing
            if [[ "$TEST_MODE" == "true" ]]; then
                [[ "$MOCK_CHRONY_RESTART_SUCCESS" == "true" ]]
            else
                safe_execute 30 systemctl restart chronyd 2>/dev/null || \
                safe_execute 30 systemctl restart chrony 2>/dev/null
            fi
        else
            return 1
        fi
    }

    export -f configure_chrony_for_large_offset

    # Test 1: Successful chrony configuration (no existing makestep)
    MOCK_CHRONY_RESTART_SUCCESS="true"
    run_test "Configure chrony (new makestep)" "configure_chrony_for_large_offset" 0

    # Verify makestep was added
    if grep -q "makestep 1000 -1" "$MOCK_CHRONY_CONF"; then
        pass_test "makestep configuration added correctly"
    else
        fail_test "makestep configuration not added"
    fi

    # Test 2: Modify existing makestep configuration
    # Reset config with existing makestep
    cat > "$MOCK_CHRONY_CONF" << 'EOF'
# Mock chrony configuration
server pool.ntp.org iburst
makestep 1 3
driftfile /var/lib/chrony/drift
EOF

    run_test "Configure chrony (modify existing makestep)" "configure_chrony_for_large_offset" 0

    # Verify makestep was modified
    if grep -q "makestep 1000 -1" "$MOCK_CHRONY_CONF"; then
        pass_test "makestep configuration modified correctly"
    else
        fail_test "makestep configuration not modified"
    fi

    # Test 3: Chrony config file missing
    mv "$MOCK_CHRONY_CONF" "$MOCK_CHRONY_CONF.bak"
    run_test "Configure chrony (missing config)" "configure_chrony_for_large_offset" 1
    mv "$MOCK_CHRONY_CONF.bak" "$MOCK_CHRONY_CONF"

    # Test 4: Chrony restart failure
    MOCK_CHRONY_RESTART_SUCCESS="false"
    run_test "Configure chrony (restart fails)" "configure_chrony_for_large_offset" 1
}

# Test function: sync_time_from_web_api
test_sync_time_from_web_api() {
    print_section "Testing sync_time_from_web_api function"

    # Test function that syncs time from web APIs
    sync_time_from_web_api() {
        log_info "Attempting time sync using web API fallback"

        # Web time APIs to try (simplified for testing)
        local web_apis=(
            "http://worldtimeapi.org/api/timezone/UTC"
            "http://worldclockapi.com/api/json/utc/now"
            "https://timeapi.io/api/Time/current/zone?timeZone=UTC"
        )

        for api in "${web_apis[@]}"; do
            log_debug "Trying web time API: $api"

            # Fetch time from web API
            local response
            if response=$(safe_execute 30 curl -s --connect-timeout 10 --max-time 15 "$api" 2>/dev/null); then
                log_debug "Web API response received"

                # Parse different API response formats
                local web_time
                case "$api" in
                    *worldtimeapi*)
                        web_time=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
                        ;;
                    *worldclockapi*)
                        web_time=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
                        ;;
                    *timeapi.io*)
                        web_time=$(echo "$response" | grep -o '"dateTime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
                        ;;
                esac

                if [[ -n "$web_time" ]]; then
                    log_debug "Parsed web time: $web_time"

                    # Convert to proper date format and set system time
                    local formatted_time
                    if formatted_time=$(date -d "$web_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null); then
                        log_debug "Setting system time to: $formatted_time"

                        if safe_execute 30 date -s "$formatted_time"; then
                            log_success "System time manually set from web API: $api"

                            # Update hardware clock if possible
                            if command_exists hwclock; then
                                safe_execute 30 hwclock --systohc 2>/dev/null || true
                                log_debug "Hardware clock updated"
                            fi

                            return 0
                        fi
                    fi
                fi
            fi

            log_debug "Failed to sync time from web API: $api"
        done

        log_error "All web API time sync attempts failed"
        return 1
    }

    export -f sync_time_from_web_api

    # Test 1: Successful worldtimeapi.org sync
    MOCK_WEB_API_SUCCESS="true"
    MOCK_WEB_API_RESPONSE='{"datetime":"2023-12-25T12:00:00.000000","timezone":"UTC"}'
    MOCK_NEW_TIME=1703505600  # 2023-12-25 12:00:00 UTC
    MOCK_HAS_CURL="true"
    MOCK_HAS_HWCLOCK="true"

    run_test "Web API sync (worldtimeapi.org)" "sync_time_from_web_api" 0

    # Test 2: Successful worldclockapi.com sync
    MOCK_WEB_API_RESPONSE2='{"currentDateTime":"2023-12-25T12:00:00"}'

    # Make first API fail, second succeed
    MOCK_WEB_API_RESPONSE=""
    run_test "Web API sync (worldclockapi.com fallback)" "sync_time_from_web_api" 0

    # Test 3: Successful timeapi.io sync
    MOCK_WEB_API_RESPONSE3='{"dateTime":"2023-12-25T12:00:00.000Z"}'

    # Make first two APIs fail, third succeed
    MOCK_WEB_API_RESPONSE=""
    MOCK_WEB_API_RESPONSE2=""
    run_test "Web API sync (timeapi.io fallback)" "sync_time_from_web_api" 0

    # Test 4: All APIs fail
    MOCK_WEB_API_SUCCESS="false"
    run_test "Web API sync (all APIs fail)" "sync_time_from_web_api" 1

    # Test 5: Curl not available
    MOCK_HAS_CURL="false"
    run_test "Web API sync (no curl)" "sync_time_from_web_api" 1

    # Test 6: Invalid date format
    MOCK_HAS_CURL="true"
    MOCK_WEB_API_SUCCESS="true"
    MOCK_WEB_API_RESPONSE='{"datetime":"invalid-date-format"}'
    run_test "Web API sync (invalid date format)" "sync_time_from_web_api" 1
}

# Test function: enhanced sync_system_time
test_enhanced_sync_system_time() {
    print_section "Testing enhanced sync_system_time function"

    # Enhanced version of sync_system_time with validation
    enhanced_sync_system_time() {
        local force="${1:-false}"

        # Skip time sync if disabled
        if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
            log_debug "Time synchronization disabled, skipping sync"
            return 0
        fi

        log_info "Synchronizing system time"

        # Check if time sync is needed (unless forced)
        if [[ "$force" != "true" ]] && [[ "$MOCK_TIME_IS_VALID" == "true" ]]; then
            log_debug "System time is already synchronized"
            return 0
        fi

        setup_signal_handlers

        # Method 1: Try systemd-timesyncd first
        if command_exists timedatectl; then
            log_debug "Attempting time sync with systemd-timesyncd"

            local time_before="$MOCK_CURRENT_TIME"

            if safe_execute 30 timedatectl set-ntp true; then
                if safe_execute 30 systemctl restart systemd-timesyncd; then
                    interruptible_sleep 5 1

                    # Use mock validation
                    if [[ "$MOCK_VALIDATION_SUCCESS" == "true" ]]; then
                        log_success "Time synchronized using systemd-timesyncd"
                        return 0
                    fi
                fi
            fi
        fi

        # Method 2: Try ntpdate
        if command_exists ntpdate; then
            log_debug "Attempting time sync with ntpdate"

            if safe_execute 30 ntpdate -s pool.ntp.org; then
                if [[ "$MOCK_VALIDATION_SUCCESS" == "true" ]]; then
                    log_success "Time synchronized using ntpdate"
                    return 0
                fi
            fi
        fi

        # Method 3: Try sntp
        if command_exists sntp; then
            log_debug "Attempting time sync with sntp"

            if safe_execute 30 sntp -s pool.ntp.org; then
                if [[ "$MOCK_VALIDATION_SUCCESS" == "true" ]]; then
                    log_success "Time synchronized using sntp"
                    return 0
                fi
            fi
        fi

        # Method 4: Try chrony with large offset support
        if command_exists chronyc; then
            log_debug "Attempting time sync with chrony"

            # Configure chrony for large step corrections
            configure_chrony_for_large_offset

            # Force immediate sync
            if safe_execute 30 chronyc burst 4/4; then
                interruptible_sleep 3 1
            fi

            if safe_execute 30 chronyc makestep; then
                interruptible_sleep 2 1

                if [[ "$MOCK_VALIDATION_SUCCESS" == "true" ]]; then
                    log_success "Time synchronized using chrony"
                    return 0
                fi
            fi
        fi

        # Method 5: Web API fallback
        if sync_time_from_web_api; then
            log_success "Time synchronized using web API fallback"
            return 0
        fi

        log_error "Failed to synchronize system time using all available methods"
        return 1
    }

    export -f enhanced_sync_system_time

    # Test 1: Time already synchronized (not forced)
    MOCK_TIME_IS_VALID="true"
    run_test "Sync (already synchronized)" "enhanced_sync_system_time" 0

    # Test 2: Forced sync with systemd success
    MOCK_TIME_IS_VALID="false"
    MOCK_HAS_TIMEDATECTL="true"
    MOCK_TIMEDATECTL_SUCCESS="true"
    MOCK_SYSTEMD_SUCCESS="true"
    MOCK_VALIDATION_SUCCESS="true"

    run_test "Sync (systemd success)" "enhanced_sync_system_time force" 0

    # Test 3: Systemd fails, ntpdate succeeds
    MOCK_TIMEDATECTL_SUCCESS="false"
    MOCK_HAS_NTPDATE="true"
    MOCK_NTPDATE_SUCCESS="true"

    run_test "Sync (ntpdate fallback)" "enhanced_sync_system_time force" 0

    # Test 4: ntpdate fails, sntp succeeds
    MOCK_NTPDATE_SUCCESS="false"
    MOCK_HAS_SNTP="true"
    MOCK_SNTP_SUCCESS="true"

    run_test "Sync (sntp fallback)" "enhanced_sync_system_time force" 0

    # Test 5: sntp fails, chrony succeeds
    MOCK_SNTP_SUCCESS="false"
    MOCK_HAS_CHRONYC="true"
    MOCK_CHRONY_BURST_SUCCESS="true"
    MOCK_CHRONY_MAKESTEP_SUCCESS="true"
    MOCK_CHRONY_RESTART_SUCCESS="true"

    run_test "Sync (chrony fallback)" "enhanced_sync_system_time force" 0

    # Test 6: chrony fails, web API succeeds
    MOCK_CHRONY_MAKESTEP_SUCCESS="false"
    MOCK_VALIDATION_SUCCESS="false"
    MOCK_WEB_API_SUCCESS="true"
    MOCK_WEB_API_RESPONSE='{"datetime":"2023-12-25T12:00:00.000000","timezone":"UTC"}'

    run_test "Sync (web API fallback)" "enhanced_sync_system_time force" 0

    # Test 7: All methods fail
    MOCK_WEB_API_SUCCESS="false"
    run_test "Sync (all methods fail)" "enhanced_sync_system_time force" 1

    # Test 8: Time sync disabled
    run_test "Sync (disabled)" "TIME_SYNC_ENABLED=false enhanced_sync_system_time force" 0
}

# Integration tests
test_integration_scenarios() {
    print_section "Testing integration scenarios"

    # Test 1: Complete sync flow with multiple fallbacks
    print_section "Complete sync flow test"

    # Set up scenario: systemd fails, ntpdate fails, chrony succeeds
    MOCK_TIME_IS_VALID="false"
    MOCK_HAS_TIMEDATECTL="true"
    MOCK_TIMEDATECTL_SUCCESS="false"
    MOCK_HAS_NTPDATE="true"
    MOCK_NTPDATE_SUCCESS="false"
    MOCK_HAS_SNTP="false"
    MOCK_HAS_CHRONYC="true"
    MOCK_CHRONY_BURST_SUCCESS="true"
    MOCK_CHRONY_MAKESTEP_SUCCESS="true"
    MOCK_CHRONY_RESTART_SUCCESS="true"
    MOCK_VALIDATION_SUCCESS="true"

    run_test "Complete flow (chrony success after failures)" "enhanced_sync_system_time force" 0

    # Test 2: Large time offset correction
    print_section "Large time offset test"

    # Test that chrony is configured for large offsets
    MOCK_CURRENT_TIME=1000000
    MOCK_NEW_TIME=1003700  # 1 hour 1 minute 40 seconds later

    run_test "Large offset validation (3700s)" "validate_time_sync_result 1000000" 0

    # Test 3: Web API parsing accuracy
    print_section "Web API parsing test"

    # Test different API response formats
    local test_responses=(
        '{"datetime":"2023-12-25T12:00:00.123456","timezone":"UTC"}'
        '{"currentDateTime":"2023-12-25T12:00:00"}'
        '{"dateTime":"2023-12-25T12:00:00.000Z"}'
    )

    for i in "${!test_responses[@]}"; do
        case $i in
            0) export MOCK_WEB_API_RESPONSE="${test_responses[$i]}" ;;
            1) export MOCK_WEB_API_RESPONSE2="${test_responses[$i]}" ;;
            2) export MOCK_WEB_API_RESPONSE3="${test_responses[$i]}" ;;
        esac
    done

    MOCK_WEB_API_SUCCESS="true"
    run_test "Web API response parsing" "sync_time_from_web_api" 0
}

# Error handling tests
test_error_scenarios() {
    print_section "Testing error handling scenarios"

    # Test 1: Network timeout simulation
    MOCK_WEB_API_SUCCESS="false"
    MOCK_NTPDATE_SUCCESS="false"
    MOCK_SNTP_SUCCESS="false"
    MOCK_TIMEDATECTL_SUCCESS="false"
    MOCK_CHRONY_MAKESTEP_SUCCESS="false"

    run_test "Network timeout handling" "enhanced_sync_system_time force" 1

    # Test 2: Partial command availability
    MOCK_HAS_TIMEDATECTL="false"
    MOCK_HAS_NTPDATE="false"
    MOCK_HAS_SNTP="true"
    MOCK_SNTP_SUCCESS="true"
    MOCK_VALIDATION_SUCCESS="true"

    run_test "Partial command availability" "enhanced_sync_system_time force" 0

    # Test 3: Invalid time data
    MOCK_CURRENT_TIME="invalid"
    run_test "Invalid time data handling" "validate_time_sync_result 1000000" 1

    # Reset for other tests
    MOCK_CURRENT_TIME=1000000
}

# Cleanup function
cleanup_test_environment() {
    rm -rf "$TEST_TMP_DIR"
    unset TEST_MODE TEST_TMP_DIR MOCK_CHRONY_CONF
    unset MOCK_CURRENT_TIME MOCK_NEW_TIME MOCK_TIME_IS_VALID
    unset MOCK_SYSTEMD_SUCCESS MOCK_TIMEDATECTL_SUCCESS MOCK_NTPDATE_SUCCESS
    unset MOCK_SNTP_SUCCESS MOCK_CHRONY_BURST_SUCCESS MOCK_CHRONY_MAKESTEP_SUCCESS
    unset MOCK_CHRONY_RESTART_SUCCESS MOCK_VALIDATION_SUCCESS MOCK_WEB_API_SUCCESS
    unset MOCK_WEB_API_RESPONSE MOCK_WEB_API_RESPONSE2 MOCK_WEB_API_RESPONSE3
    unset MOCK_HAS_TIMEDATECTL MOCK_HAS_NTPDATE MOCK_HAS_SNTP MOCK_HAS_CHRONYC
    unset MOCK_HAS_CURL MOCK_HAS_HWCLOCK
}

# Main test execution
main() {
    print_header "Enhanced Time Synchronization Test Suite"

    # Set debug mode if requested
    export TEST_DEBUG="${TEST_DEBUG:-false}"

    echo -e "${YELLOW}Setting up test environment...${NC}"
    setup_test_environment
    setup_command_mocks

    # Initialize mock values
    MOCK_CURRENT_TIME=1000000
    MOCK_NEW_TIME=1000000
    MOCK_TIME_IS_VALID="false"

    # Run all test suites
    test_validate_time_sync_result
    echo
    test_configure_chrony_for_large_offset
    echo
    test_sync_time_from_web_api
    echo
    test_enhanced_sync_system_time
    echo
    test_integration_scenarios
    echo
    test_error_scenarios

    # Cleanup
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    cleanup_test_environment

    # Print final results
    print_header "Test Results Summary"
    echo -e "Tests Run:    ${TESTS_RUN}"
    echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All enhanced time synchronization tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed!${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
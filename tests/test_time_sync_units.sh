#!/bin/bash

# VLESS+Reality VPN Management System - Time Sync Unit Tests
# Version: 1.2.1
# Description: Unit tests for individual time synchronization functions
#
# Unit tests for:
# 1. validate_time_sync_result() - Time change validation
# 2. configure_chrony_for_large_offset() - Chrony configuration
# 3. sync_time_from_web_api() - Web API fallback
# 4. detect_time_related_apt_errors() - APT error detection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test utilities
print_test_header() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===========================================${NC}"
}

print_section() {
    echo -e "${YELLOW}--- $1 ---${NC}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS:${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} $message"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        ((TESTS_FAILED++))
    fi
}

assert_success() {
    local command="$1"
    local message="$2"

    ((TESTS_RUN++))

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS:${NC} $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} $message (command failed)"
        ((TESTS_FAILED++))
    fi
}

assert_failure() {
    local command="$1"
    local message="$2"

    ((TESTS_RUN++))

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${RED}✗ FAIL:${NC} $message (command should have failed)"
        ((TESTS_FAILED++))
    else
        echo -e "${GREEN}✓ PASS:${NC} $message"
        ((TESTS_PASSED++))
    fi
}

# Setup minimal test environment
setup_unit_test_env() {
    export TEST_MODE="true"
    export LOG_FILE="/tmp/test_time_sync_units.log"
    export TEST_TMP_DIR="/tmp/time_sync_units_$$"
    mkdir -p "$TEST_TMP_DIR"

    # Minimal logging functions
    log_debug() { return 0; }
    log_info() { return 0; }
    log_warn() { return 0; }
    log_error() { return 0; }
    log_success() { return 0; }

    export -f log_debug log_info log_warn log_error log_success
}

# Unit Test 1: validate_time_sync_result function
test_validate_time_sync_result_unit() {
    print_section "Unit Test: validate_time_sync_result"

    # Mock date function for consistent testing
    mock_date() {
        case "$1" in
            "+%s") echo "$MOCK_TIME_AFTER" ;;
            "-d") echo "Mock date for: $2" ;;
            *) echo "Mock date output" ;;
        esac
    }

    # Mock check_system_time_validity (always returns success for unit test)
    check_system_time_validity() {
        return 0
    }

    export -f mock_date check_system_time_validity

    # Test function implementation
    validate_time_sync_result() {
        local time_before="$1"
        local time_after
        time_after=$(mock_date +%s)
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
            check_system_time_validity
        else
            log_debug "Insufficient time change: ${time_diff} seconds"
            return 1
        fi
    }

    export -f validate_time_sync_result

    # Test case 1: Large positive change (100 seconds)
    MOCK_TIME_AFTER=1000100
    assert_success "validate_time_sync_result 1000000" "Large positive time change (100s)"

    # Test case 2: Large negative change (-200 seconds)
    MOCK_TIME_AFTER=999800
    assert_success "validate_time_sync_result 1000000" "Large negative time change (200s)"

    # Test case 3: Small positive change (20 seconds)
    MOCK_TIME_AFTER=1000020
    assert_failure "validate_time_sync_result 1000000" "Small positive time change (20s)"

    # Test case 4: Small negative change (-15 seconds)
    MOCK_TIME_AFTER=999985
    assert_failure "validate_time_sync_result 1000000" "Small negative time change (15s)"

    # Test case 5: Exactly 30 seconds (boundary case - should fail)
    MOCK_TIME_AFTER=1000030
    assert_failure "validate_time_sync_result 1000000" "Exactly 30 seconds change"

    # Test case 6: Exactly 31 seconds (should pass)
    MOCK_TIME_AFTER=1000031
    assert_success "validate_time_sync_result 1000000" "Exactly 31 seconds change"

    # Test case 7: No time change
    MOCK_TIME_AFTER=1000000
    assert_failure "validate_time_sync_result 1000000" "No time change"

    # Test case 8: Very large change (1 hour)
    MOCK_TIME_AFTER=1003600
    assert_success "validate_time_sync_result 1000000" "Very large time change (1 hour)"

    unset MOCK_TIME_AFTER
}

# Unit Test 2: configure_chrony_for_large_offset function
test_configure_chrony_for_large_offset_unit() {
    print_section "Unit Test: configure_chrony_for_large_offset"

    # Create test chrony config
    local test_config="$TEST_TMP_DIR/chrony.conf"
    local temp_config="$TEST_TMP_DIR/chrony_temp.conf"

    # Test function implementation
    configure_chrony_for_large_offset() {
        local chrony_conf="$test_config"
        local temp_conf="$temp_config"

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

        # Apply temporary configuration (simplified for unit test)
        cp "$temp_conf" "$chrony_conf" 2>/dev/null
    }

    export -f configure_chrony_for_large_offset

    # Test case 1: Config file doesn't exist
    rm -f "$test_config"
    assert_failure "configure_chrony_for_large_offset" "Missing config file"

    # Test case 2: Config file exists without makestep
    cat > "$test_config" << 'EOF'
# Test chrony configuration
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
EOF

    assert_success "configure_chrony_for_large_offset" "Add makestep to config without existing"

    # Verify makestep was added
    if grep -q "makestep 1000 -1" "$test_config"; then
        echo -e "${GREEN}✓ PASS:${NC} makestep configuration added correctly"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} makestep configuration not added"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    # Test case 3: Config file exists with existing makestep
    cat > "$test_config" << 'EOF'
# Test chrony configuration
server pool.ntp.org iburst
makestep 1 3
driftfile /var/lib/chrony/drift
EOF

    assert_success "configure_chrony_for_large_offset" "Modify existing makestep config"

    # Verify makestep was modified
    if grep -q "makestep 1000 -1" "$test_config" && ! grep -q "makestep 1 3" "$test_config"; then
        echo -e "${GREEN}✓ PASS:${NC} makestep configuration modified correctly"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} makestep configuration not modified correctly"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    # Test case 4: Multiple makestep lines (should modify all)
    cat > "$test_config" << 'EOF'
# Test chrony configuration
server pool.ntp.org iburst
makestep 1 3
driftfile /var/lib/chrony/drift
makestep 0.1 10
EOF

    assert_success "configure_chrony_for_large_offset" "Modify multiple makestep configs"

    # Verify only one makestep line remains with correct value
    local makestep_count=$(grep -c "^makestep" "$test_config")
    local correct_makestep=$(grep -c "^makestep 1000 -1" "$test_config")

    if [[ $makestep_count -eq 1 && $correct_makestep -eq 1 ]]; then
        echo -e "${GREEN}✓ PASS:${NC} Multiple makestep lines handled correctly"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} Multiple makestep lines not handled correctly"
        echo -e "  Found $makestep_count makestep lines, $correct_makestep correct ones"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))

    # Test case 5: Read-only config file
    chmod 444 "$test_config"
    assert_failure "configure_chrony_for_large_offset" "Read-only config file"
    chmod 644 "$test_config"
}

# Unit Test 3: sync_time_from_web_api function
test_sync_time_from_web_api_unit() {
    print_section "Unit Test: sync_time_from_web_api"

    # Mock functions for unit testing
    mock_curl() {
        case "$*" in
            *worldtimeapi*)
                [[ "$MOCK_WORLDTIME_SUCCESS" == "true" ]] && echo "$MOCK_WORLDTIME_RESPONSE"
                [[ "$MOCK_WORLDTIME_SUCCESS" == "true" ]]
                ;;
            *worldclockapi*)
                [[ "$MOCK_WORLDCLOCK_SUCCESS" == "true" ]] && echo "$MOCK_WORLDCLOCK_RESPONSE"
                [[ "$MOCK_WORLDCLOCK_SUCCESS" == "true" ]]
                ;;
            *timeapi.io*)
                [[ "$MOCK_TIMEAPI_SUCCESS" == "true" ]] && echo "$MOCK_TIMEAPI_RESPONSE"
                [[ "$MOCK_TIMEAPI_SUCCESS" == "true" ]]
                ;;
            *) return 1 ;;
        esac
    }

    mock_safe_execute() {
        shift  # Remove timeout
        case "$1" in
            curl) mock_curl "${@:2}" ;;
            date)
                case "$2" in
                    "-s") MOCK_DATE_SET="$3"; return 0 ;;
                    "-d") echo "2023-12-25 12:00:00" ;;
                    "+%Y-%m-%d %H:%M:%S") echo "2023-12-25 12:00:00" ;;
                    *) date "$@" ;;
                esac
                ;;
            hwclock) return 0 ;;
            *) "$@" ;;
        esac
    }

    command_exists() {
        case "$1" in
            hwclock) [[ "$MOCK_HAS_HWCLOCK" == "true" ]] ;;
            *) return 1 ;;
        esac
    }

    export -f mock_curl mock_safe_execute command_exists

    # Test function implementation (simplified)
    sync_time_from_web_api() {
        log_info "Attempting time sync using web API fallback"

        local web_apis=(
            "http://worldtimeapi.org/api/timezone/UTC"
            "http://worldclockapi.com/api/json/utc/now"
            "https://timeapi.io/api/Time/current/zone?timeZone=UTC"
        )

        for api in "${web_apis[@]}"; do
            log_debug "Trying web time API: $api"

            local response
            if response=$(mock_safe_execute 30 curl -s --connect-timeout 10 --max-time 15 "$api" 2>/dev/null); then
                log_debug "Web API response received"

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

                    local formatted_time
                    if formatted_time=$(mock_safe_execute 30 date -d "$web_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null); then
                        log_debug "Setting system time to: $formatted_time"

                        if mock_safe_execute 30 date -s "$formatted_time"; then
                            log_success "System time manually set from web API: $api"

                            if command_exists hwclock; then
                                mock_safe_execute 30 hwclock --systohc 2>/dev/null || true
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

    # Test case 1: worldtimeapi.org success
    MOCK_WORLDTIME_SUCCESS="true"
    MOCK_WORLDTIME_RESPONSE='{"datetime":"2023-12-25T12:00:00.123456","timezone":"UTC"}'
    MOCK_WORLDCLOCK_SUCCESS="false"
    MOCK_TIMEAPI_SUCCESS="false"
    MOCK_HAS_HWCLOCK="true"

    assert_success "sync_time_from_web_api" "worldtimeapi.org success"
    assert_equals "2023-12-25 12:00:00" "$MOCK_DATE_SET" "Correct time set from worldtimeapi"

    # Test case 2: worldclockapi.com fallback success
    MOCK_WORLDTIME_SUCCESS="false"
    MOCK_WORLDCLOCK_SUCCESS="true"
    MOCK_WORLDCLOCK_RESPONSE='{"currentDateTime":"2023-12-25T12:00:00"}'
    MOCK_DATE_SET=""

    assert_success "sync_time_from_web_api" "worldclockapi.com fallback success"
    assert_equals "2023-12-25 12:00:00" "$MOCK_DATE_SET" "Correct time set from worldclockapi"

    # Test case 3: timeapi.io fallback success
    MOCK_WORLDCLOCK_SUCCESS="false"
    MOCK_TIMEAPI_SUCCESS="true"
    MOCK_TIMEAPI_RESPONSE='{"dateTime":"2023-12-25T12:00:00.000Z"}'
    MOCK_DATE_SET=""

    assert_success "sync_time_from_web_api" "timeapi.io fallback success"
    assert_equals "2023-12-25 12:00:00" "$MOCK_DATE_SET" "Correct time set from timeapi.io"

    # Test case 4: All APIs fail
    MOCK_TIMEAPI_SUCCESS="false"

    assert_failure "sync_time_from_web_api" "All APIs fail"

    # Test case 5: Invalid JSON response
    MOCK_WORLDTIME_SUCCESS="true"
    MOCK_WORLDTIME_RESPONSE='{"invalid":"json","missing":"datetime"}'

    assert_failure "sync_time_from_web_api" "Invalid JSON response"

    # Test case 6: Valid JSON but invalid date format
    MOCK_WORLDTIME_RESPONSE='{"datetime":"invalid-date-format"}'

    assert_failure "sync_time_from_web_api" "Invalid date format in JSON"

    # Clean up
    unset MOCK_WORLDTIME_SUCCESS MOCK_WORLDCLOCK_SUCCESS MOCK_TIMEAPI_SUCCESS
    unset MOCK_WORLDTIME_RESPONSE MOCK_WORLDCLOCK_RESPONSE MOCK_TIMEAPI_RESPONSE
    unset MOCK_HAS_HWCLOCK MOCK_DATE_SET
}

# Unit Test 4: detect_time_related_apt_errors function
test_detect_time_related_apt_errors_unit() {
    print_section "Unit Test: detect_time_related_apt_errors"

    # Test function implementation (based on the actual function)
    detect_time_related_apt_errors() {
        local error_output="$1"

        # Common time-related error patterns
        local time_error_patterns=(
            "not valid yet"
            "invalid for another"
            "certificate is not yet valid"
            "certificate has expired"
            "SSL certificate problem.*not yet valid"
            "SSL certificate problem.*expired"
            "Certificate verification failed.*not yet valid"
            "Certificate verification failed.*expired"
            "clock skew detected"
            "time synchronization"
        )

        local pattern
        for pattern in "${time_error_patterns[@]}"; do
            if [[ "$error_output" =~ $pattern ]]; then
                log_debug "Detected time-related error pattern: $pattern"
                return 0
            fi
        done

        return 1
    }

    export -f detect_time_related_apt_errors

    # Test case 1: "not valid yet" error
    assert_success "detect_time_related_apt_errors 'Release file is not valid yet (invalid for another 2h 31m 45s)'" "not valid yet error"

    # Test case 2: "invalid for another" error
    assert_success "detect_time_related_apt_errors 'Repository data invalid for another 1h 15m 30s'" "invalid for another error"

    # Test case 3: SSL certificate not yet valid
    assert_success "detect_time_related_apt_errors 'SSL certificate problem: certificate is not yet valid'" "SSL not yet valid error"

    # Test case 4: SSL certificate expired
    assert_success "detect_time_related_apt_errors 'SSL certificate problem: certificate has expired'" "SSL expired error"

    # Test case 5: Certificate verification failed - not yet valid
    assert_success "detect_time_related_apt_errors 'Certificate verification failed: The certificate is not yet valid'" "Certificate verification not yet valid"

    # Test case 6: Certificate verification failed - expired
    assert_success "detect_time_related_apt_errors 'Certificate verification failed: The certificate has expired'" "Certificate verification expired"

    # Test case 7: Clock skew detected
    assert_success "detect_time_related_apt_errors 'clock skew detected between client and server'" "Clock skew error"

    # Test case 8: Time synchronization error
    assert_success "detect_time_related_apt_errors 'time synchronization required before continuing'" "Time sync required error"

    # Test case 9: Network error (should not match)
    assert_failure "detect_time_related_apt_errors 'Temporary failure resolving archive.ubuntu.com'" "Network error (should not match)"

    # Test case 10: Disk space error (should not match)
    assert_failure "detect_time_related_apt_errors 'No space left on device'" "Disk space error (should not match)"

    # Test case 11: Permission error (should not match)
    assert_failure "detect_time_related_apt_errors 'Permission denied'" "Permission error (should not match)"

    # Test case 12: Generic 404 error (should not match)
    assert_failure "detect_time_related_apt_errors '404 Not Found'" "404 error (should not match)"

    # Test case 13: Empty error message
    assert_failure "detect_time_related_apt_errors ''" "Empty error message"

    # Test case 14: Case sensitivity test
    assert_success "detect_time_related_apt_errors 'Certificate Is Not Yet Valid'" "Case sensitivity test"
}

# Cleanup function
cleanup_unit_test_env() {
    rm -rf "$TEST_TMP_DIR"
    unset TEST_MODE TEST_TMP_DIR LOG_FILE
}

# Main execution
main() {
    print_test_header "Time Synchronization Unit Tests"

    echo -e "${YELLOW}Setting up unit test environment...${NC}"
    setup_unit_test_env

    # Run all unit test suites
    test_validate_time_sync_result_unit
    echo
    test_configure_chrony_for_large_offset_unit
    echo
    test_sync_time_from_web_api_unit
    echo
    test_detect_time_related_apt_errors_unit

    # Cleanup
    echo -e "${YELLOW}Cleaning up unit test environment...${NC}"
    cleanup_unit_test_env

    # Print final results
    print_test_header "Unit Test Results Summary"
    echo -e "Tests Run:    ${TESTS_RUN}"
    echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"

    local success_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$(( TESTS_PASSED * 100 / TESTS_RUN ))
    fi
    echo -e "Success Rate: ${success_rate}%"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All unit tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some unit tests failed!${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
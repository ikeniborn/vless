#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Comprehensive Test Runner
# Version: 1.0.0
# Description: Main test orchestrator for all VLESS manager test suites
# Author: VLESS Testing Team

#######################################################################################
# TEST RUNNER CONSTANTS AND CONFIGURATION
#######################################################################################

readonly RUNNER_NAME="run_all_tests"
readonly RUNNER_VERSION="1.0.0"
readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_ROOT")"

# Test suite configuration
declare -A TEST_SUITES=(
    ["requirements"]="System Requirements Tests"
    ["installation"]="Docker Installation Tests"
    ["structure"]="Directory Structure Tests"
    ["main"]="Main Integration Tests"
)

declare -A SUITE_RESULTS=(
    ["requirements"]="PENDING"
    ["installation"]="PENDING"
    ["structure"]="PENDING"
    ["main"]="PENDING"
)

declare -i TOTAL_SUITES=0
declare -i PASSED_SUITES=0
declare -i FAILED_SUITES=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Test execution options
VERBOSE_OUTPUT=false
STOP_ON_FAILURE=false
GENERATE_SUMMARY=true
RUN_SPECIFIC_SUITE=""

#######################################################################################
# UTILITY FUNCTIONS
#######################################################################################

# Logging function with colors and timestamps
runner_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${BLUE}[RUNNER-INFO]${NC} ${timestamp} - $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[RUNNER-SUCCESS]${NC} ${timestamp} - $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[RUNNER-WARNING]${NC} ${timestamp} - $message"
            ;;
        "ERROR")
            echo -e "${RED}[RUNNER-ERROR]${NC} ${timestamp} - $message" >&2
            ;;
    esac
}

# Display header with project information
display_header() {
    local start_time="$1"

    echo
    echo -e "${BOLD}${BLUE}=================================================================================${NC}"
    echo -e "${BOLD}${GREEN}                  VLESS+Reality VPN Service - Test Suite Runner${NC}"
    echo -e "${BOLD}${BLUE}=================================================================================${NC}"
    echo -e "${WHITE}Version:${NC}        $RUNNER_VERSION"
    echo -e "${WHITE}Project:${NC}        VLESS+Reality VPN Service Manager"
    echo -e "${WHITE}Start Time:${NC}     $start_time"
    echo -e "${WHITE}Test Root:${NC}      $TEST_ROOT"
    echo -e "${WHITE}Project Root:${NC}   $PROJECT_ROOT"
    echo -e "${BOLD}${BLUE}=================================================================================${NC}"
    echo
}

# Display test suite summary
display_suite_summary() {
    echo -e "${YELLOW}Test Suites Available:${NC}"

    local i=1
    for suite in "${!TEST_SUITES[@]}"; do
        local description="${TEST_SUITES[$suite]}"
        local status="${SUITE_RESULTS[$suite]}"
        local status_color=""

        case "$status" in
            "PASSED")  status_color="${GREEN}" ;;
            "FAILED")  status_color="${RED}" ;;
            "RUNNING") status_color="${YELLOW}" ;;
            "PENDING") status_color="${BLUE}" ;;
            *)         status_color="${WHITE}" ;;
        esac

        echo -e "  ${BOLD}[$i]${NC} ${WHITE}$suite${NC} - $description [${status_color}$status${NC}]"
        ((i++))
    done
    echo
}

# Check test suite dependencies
check_dependencies() {
    runner_log "INFO" "Checking test dependencies..."

    # Check if vless-manager.sh exists
    if [[ ! -f "$PROJECT_ROOT/vless-manager.sh" ]]; then
        runner_log "ERROR" "VLESS manager script not found: $PROJECT_ROOT/vless-manager.sh"
        return 1
    fi

    # Check if individual test scripts exist
    local missing_tests=()
    for suite in "${!TEST_SUITES[@]}"; do
        local test_script="$TEST_ROOT/test_${suite}.sh"
        if [[ ! -f "$test_script" ]]; then
            missing_tests+=("$test_script")
        fi
    done

    if [[ ${#missing_tests[@]} -gt 0 ]]; then
        runner_log "ERROR" "Missing test scripts:"
        for missing in "${missing_tests[@]}"; do
            runner_log "ERROR" "  - $missing"
        done
        return 1
    fi

    # Check shell capabilities
    if ! command -v bash >/dev/null 2>&1; then
        runner_log "ERROR" "Bash shell not available"
        return 1
    fi

    # Check required utilities
    local required_utils=("date" "mkdir" "chmod" "stat")
    for util in "${required_utils[@]}"; do
        if ! command -v "$util" >/dev/null 2>&1; then
            runner_log "WARNING" "Utility '$util' not available - some tests may fail"
        fi
    done

    runner_log "SUCCESS" "All dependencies verified"
    return 0
}

# Run individual test suite
run_test_suite() {
    local suite_name="$1"
    local suite_description="${TEST_SUITES[$suite_name]}"
    local test_script="$TEST_ROOT/test_${suite_name}.sh"

    runner_log "INFO" "Starting test suite: $suite_name ($suite_description)"
    SUITE_RESULTS[$suite_name]="RUNNING"

    echo -e "${YELLOW}================================================================================${NC}"
    echo -e "${YELLOW}                   RUNNING: $suite_description${NC}"
    echo -e "${YELLOW}================================================================================${NC}"

    local start_time=$(date +%s)
    local output_file="/tmp/vless_test_${suite_name}_$$.log"
    local return_code=0

    # Make test script executable
    chmod +x "$test_script"

    # Run the test suite
    if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
        "$test_script" run 2>&1 | tee "$output_file"
        return_code=${PIPESTATUS[0]}
    else
        "$test_script" run > "$output_file" 2>&1
        return_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Process results
    ((TOTAL_SUITES++))

    if [[ $return_code -eq 0 ]]; then
        SUITE_RESULTS[$suite_name]="PASSED"
        ((PASSED_SUITES++))
        runner_log "SUCCESS" "Test suite '$suite_name' PASSED (${duration}s)"

        if [[ "$VERBOSE_OUTPUT" == "false" ]]; then
            # Show summary from log
            if grep -q "SUCCESS RATE\|PASSED\|Test Results" "$output_file"; then
                echo -e "${GREEN}Test Results Summary:${NC}"
                grep -E "(Total Tests|Passed Tests|Failed Tests|Success Rate)" "$output_file" | tail -4 || true
            fi
        fi

    else
        SUITE_RESULTS[$suite_name]="FAILED"
        ((FAILED_SUITES++))
        runner_log "ERROR" "Test suite '$suite_name' FAILED (${duration}s)"

        if [[ "$VERBOSE_OUTPUT" == "false" ]]; then
            echo -e "${RED}Failure Details:${NC}"
            tail -20 "$output_file" | grep -E "(FAIL|ERROR|Failed)" || tail -10 "$output_file"
        fi

        if [[ "$STOP_ON_FAILURE" == "true" ]]; then
            runner_log "ERROR" "Stopping test execution due to failure"
            rm -f "$output_file"
            return 1
        fi
    fi

    echo

    # Archive log file
    if [[ -n "${TEST_ARCHIVE_DIR:-}" ]]; then
        mv "$output_file" "$TEST_ARCHIVE_DIR/test_${suite_name}_$(date +%Y%m%d_%H%M%S).log"
    else
        rm -f "$output_file"
    fi

    return $return_code
}

# Generate comprehensive test report
generate_comprehensive_report() {
    local report_file="/tmp/vless_comprehensive_test_report_$(date +%Y%m%d_%H%M%S).txt"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$report_file" << EOF
================================================================================
VLESS+Reality VPN Service Manager - Comprehensive Test Report
================================================================================

Execution Summary:
- Test Runner Version: $RUNNER_VERSION
- Execution Time: $end_time
- Total Test Suites: $TOTAL_SUITES
- Passed Suites: $PASSED_SUITES
- Failed Suites: $FAILED_SUITES
- Success Rate: $(( TOTAL_SUITES > 0 ? (PASSED_SUITES * 100) / TOTAL_SUITES : 0 ))%

Test Environment:
- Operating System: $(uname -s) $(uname -r)
- Architecture: $(uname -m)
- Shell: $BASH_VERSION
- User: $(whoami)
- Working Directory: $(pwd)

Test Suites Results:
EOF

    for suite in "${!TEST_SUITES[@]}"; do
        local description="${TEST_SUITES[$suite]}"
        local result="${SUITE_RESULTS[$suite]}"

        cat >> "$report_file" << EOF
- $suite: $result
  Description: $description
EOF
    done

    cat >> "$report_file" << EOF

Test Coverage Overview:
1. System Requirements Tests:
   - Root privilege validation
   - OS compatibility (Ubuntu 20.04+, Debian 11+)
   - Architecture support (x86_64, ARM64)
   - Resource requirements (RAM: 512MB+, Disk: 1GB+)
   - Port availability (443)

2. Docker Installation Tests:
   - Docker CE installation and verification
   - Docker Compose installation and verification
   - Service startup and configuration
   - Installation error handling

3. Directory Structure Tests:
   - Project directory creation
   - File permissions and security
   - Environment configuration
   - Structure integrity

4. Main Integration Tests:
   - Full installation workflow
   - Function unit testing
   - Error handling and edge cases
   - Multi-platform compatibility

Overall Assessment:
EOF

    if [[ $FAILED_SUITES -eq 0 && $TOTAL_SUITES -gt 0 ]]; then
        cat >> "$report_file" << EOF
✅ ALL TEST SUITES PASSED
   - System is ready for production deployment
   - All components tested successfully
   - No critical issues identified
EOF
    elif [[ $FAILED_SUITES -gt 0 ]]; then
        cat >> "$report_file" << EOF
❌ SOME TEST SUITES FAILED
   - Review failed test suites before deployment
   - Address identified issues and re-run tests
   - Failed suites: $FAILED_SUITES out of $TOTAL_SUITES
EOF
    else
        cat >> "$report_file" << EOF
⚠️  NO TEST SUITES EXECUTED
   - Verify test environment and dependencies
   - Check test script availability and permissions
EOF
    fi

    cat >> "$report_file" << EOF

Recommendations:
EOF

    if [[ $FAILED_SUITES -eq 0 && $TOTAL_SUITES -gt 0 ]]; then
        cat >> "$report_file" << EOF
- System validation complete - proceed with deployment
- Consider running tests in production environment
- Set up automated testing for future changes
EOF
    else
        cat >> "$report_file" << EOF
- Fix failed test cases before proceeding
- Review test logs for specific error details
- Verify system meets all requirements
- Consider testing in different environments
EOF
    fi

    cat >> "$report_file" << EOF

For detailed test results, review individual test suite logs.

Report generated by VLESS Test Runner v$RUNNER_VERSION
================================================================================
EOF

    echo "$report_file"
}

# Display final results summary
display_final_results() {
    local report_file="$1"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${BOLD}${BLUE}=================================================================================${NC}"
    echo -e "${BOLD}${WHITE}                           FINAL TEST RESULTS${NC}"
    echo -e "${BOLD}${BLUE}=================================================================================${NC}"

    echo -e "${WHITE}Execution Complete:${NC}   $end_time"
    echo -e "${WHITE}Total Test Suites:${NC}    $TOTAL_SUITES"
    echo -e "${GREEN}Passed Suites:${NC}       $PASSED_SUITES"
    echo -e "${RED}Failed Suites:${NC}       $FAILED_SUITES"

    if [[ $TOTAL_SUITES -gt 0 ]]; then
        local success_rate=$(( (PASSED_SUITES * 100) / TOTAL_SUITES ))
        echo -e "${WHITE}Success Rate:${NC}        ${success_rate}%"
    fi

    echo -e "${WHITE}Comprehensive Report:${NC} $report_file"
    echo

    # Display individual suite results
    echo -e "${YELLOW}Suite Results:${NC}"
    for suite in "${!TEST_SUITES[@]}"; do
        local result="${SUITE_RESULTS[$suite]}"
        local result_color=""

        case "$result" in
            "PASSED")  result_color="${GREEN}" ;;
            "FAILED")  result_color="${RED}" ;;
            *)         result_color="${YELLOW}" ;;
        esac

        echo -e "  • ${WHITE}$suite${NC}: ${result_color}$result${NC}"
    done

    echo -e "${BOLD}${BLUE}=================================================================================${NC}"

    if [[ $FAILED_SUITES -eq 0 && $TOTAL_SUITES -gt 0 ]]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! System is ready for deployment.${NC}"
        return 0
    elif [[ $FAILED_SUITES -gt 0 ]]; then
        echo -e "${RED}❌ Some test suites failed. Please review and fix issues.${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠️  No tests were executed.${NC}"
        return 1
    fi
}

#######################################################################################
# MAIN EXECUTION FUNCTIONS
#######################################################################################

# Run all test suites
run_all_suites() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    display_header "$start_time"

    # Check dependencies
    if ! check_dependencies; then
        runner_log "ERROR" "Dependency check failed"
        return 1
    fi

    # Initialize results
    for suite in "${!TEST_SUITES[@]}"; do
        SUITE_RESULTS[$suite]="PENDING"
    done

    display_suite_summary

    # Create archive directory if needed
    if [[ -n "${TEST_ARCHIVE_DIR:-}" ]]; then
        mkdir -p "$TEST_ARCHIVE_DIR"
        runner_log "INFO" "Test logs will be archived to: $TEST_ARCHIVE_DIR"
    fi

    # Run test suites in logical order
    local execution_order=("requirements" "installation" "structure" "main")

    for suite in "${execution_order[@]}"; do
        if [[ -n "$RUN_SPECIFIC_SUITE" && "$RUN_SPECIFIC_SUITE" != "$suite" ]]; then
            runner_log "INFO" "Skipping test suite: $suite (not selected)"
            continue
        fi

        if [[ -v TEST_SUITES[$suite] ]]; then
            run_test_suite "$suite"

            # Update display
            if [[ "$VERBOSE_OUTPUT" == "false" ]]; then
                display_suite_summary
            fi
        fi
    done

    # Generate final report
    local report_file=""
    if [[ "$GENERATE_SUMMARY" == "true" ]]; then
        report_file=$(generate_comprehensive_report)
        runner_log "SUCCESS" "Comprehensive test report generated: $report_file"
    fi

    # Display final results
    display_final_results "$report_file"
}

# Run specific test suite
run_specific_suite() {
    local suite_name="$1"

    if [[ ! -v TEST_SUITES[$suite_name] ]]; then
        runner_log "ERROR" "Unknown test suite: $suite_name"
        echo -e "${YELLOW}Available suites:${NC}"
        for suite in "${!TEST_SUITES[@]}"; do
            echo "  - $suite"
        done
        return 1
    fi

    RUN_SPECIFIC_SUITE="$suite_name"
    run_all_suites
}

# Show usage information
show_usage() {
    cat << EOF
${GREEN}VLESS Test Runner v$RUNNER_VERSION${NC}

${YELLOW}DESCRIPTION:${NC}
    Comprehensive test orchestrator for VLESS+Reality VPN Service Manager
    Runs all test suites and provides detailed reporting

${YELLOW}USAGE:${NC}
    $0 [COMMAND] [OPTIONS]

${YELLOW}COMMANDS:${NC}
    run                     Run all test suites
    run-suite SUITE         Run specific test suite
    list                    List available test suites
    help                    Show this help message

${YELLOW}OPTIONS:${NC}
    -v, --verbose           Enable verbose output
    -s, --stop-on-fail      Stop execution on first failure
    -a, --archive DIR       Archive test logs to directory
    --no-report             Don't generate comprehensive report

${YELLOW}AVAILABLE TEST SUITES:${NC}
EOF

    for suite in "${!TEST_SUITES[@]}"; do
        echo "    $suite - ${TEST_SUITES[$suite]}"
    done

    cat << EOF

${YELLOW}EXAMPLES:${NC}
    $0 run                          # Run all test suites
    $0 run -v --stop-on-fail        # Run with verbose output, stop on failure
    $0 run-suite requirements       # Run only requirements tests
    $0 list                         # Show available test suites
    $0 --archive /tmp/test-logs run # Archive logs and run all tests

${YELLOW}EXIT CODES:${NC}
    0    All tests passed
    1    Some tests failed or error occurred
    2    Invalid arguments or usage

EOF
}

# List available test suites
list_suites() {
    echo -e "${GREEN}Available Test Suites:${NC}"
    echo

    for suite in "${!TEST_SUITES[@]}"; do
        local description="${TEST_SUITES[$suite]}"
        local test_file="$TEST_ROOT/test_${suite}.sh"
        local status=""

        if [[ -f "$test_file" && -x "$test_file" ]]; then
            status="${GREEN}[AVAILABLE]${NC}"
        else
            status="${RED}[MISSING]${NC}"
        fi

        echo -e "  ${BOLD}$suite${NC} - $description $status"
    done
    echo
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            run)
                return 0
                ;;
            run-suite)
                if [[ -z "${2:-}" ]]; then
                    runner_log "ERROR" "Suite name required for run-suite command"
                    return 2
                fi
                RUN_SPECIFIC_SUITE="$2"
                shift
                return 0
                ;;
            list)
                list_suites
                exit 0
                ;;
            -v|--verbose)
                VERBOSE_OUTPUT=true
                ;;
            -s|--stop-on-fail)
                STOP_ON_FAILURE=true
                ;;
            -a|--archive)
                if [[ -z "${2:-}" ]]; then
                    runner_log "ERROR" "Archive directory required for --archive option"
                    return 2
                fi
                TEST_ARCHIVE_DIR="$2"
                shift
                ;;
            --no-report)
                GENERATE_SUMMARY=false
                ;;
            help|-h|--help)
                show_usage
                exit 0
                ;;
            *)
                runner_log "ERROR" "Unknown argument: $1"
                show_usage
                return 2
                ;;
        esac
        shift
    done

    # Default to run if no command specified
    return 0
}

#######################################################################################
# MAIN SCRIPT EXECUTION
#######################################################################################

# Main function
main() {
    # Handle case where no arguments provided
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    # Parse arguments
    if ! parse_arguments "$@"; then
        exit 2
    fi

    # Execute based on parsed options
    if [[ -n "$RUN_SPECIFIC_SUITE" ]]; then
        run_specific_suite "$RUN_SPECIFIC_SUITE"
    else
        run_all_suites
    fi
}

# Execute main function with all arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
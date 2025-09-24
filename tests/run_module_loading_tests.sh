#!/bin/bash

# VLESS+Reality VPN Management System - Module Loading Tests Master Runner
# Version: 1.0.0
# Description: Master test runner for all module loading fix tests
#
# This script orchestrates execution of all module loading test suites:
# - Module loading fixes tests
# - Readonly variable conflicts tests
# - SCRIPT_DIR handling tests
# - Container management module tests

set -euo pipefail

# Test configuration
readonly TEST_SUITE_NAME="Module Loading Fixes"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Test suite files
readonly TEST_SUITES=(
    "test_module_loading_fixes.sh"
    "test_readonly_variable_conflicts.sh"
    "test_script_dir_handling.sh"
    "test_container_management_module.sh"
)

# Results tracking
declare -g TOTAL_SUITES=0
declare -g PASSED_SUITES=0
declare -g FAILED_SUITES=0
declare -g TOTAL_TESTS=0
declare -g TOTAL_PASSED=0
declare -g TOTAL_FAILED=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
VERBOSE=${VERBOSE:-false}
STOP_ON_FAILURE=${STOP_ON_FAILURE:-false}
GENERATE_REPORT=${GENERATE_REPORT:-true}
REPORT_FILE="${SCRIPT_DIR}/results/module_loading_tests_$(date +%Y%m%d_%H%M%S).txt"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_header() {
    echo -e "${CYAN}$*${NC}"
}

# Help function
show_help() {
    cat << EOF
Module Loading Tests Master Runner

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --verbose           Enable verbose output
    -s, --stop-on-failure   Stop execution on first test suite failure
    -n, --no-report         Skip generating test report
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    VERBOSE                 Enable verbose output (true/false)
    STOP_ON_FAILURE         Stop on first failure (true/false)
    GENERATE_REPORT         Generate test report (true/false)

EXAMPLES:
    $0                      Run all tests with default settings
    $0 --verbose            Run with verbose output
    $0 --stop-on-failure    Stop on first test suite failure
    $0 --no-report          Run without generating report

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--stop-on-failure)
                STOP_ON_FAILURE=true
                shift
                ;;
            -n|--no-report)
                GENERATE_REPORT=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment"

    # Create results directory if it doesn't exist
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        mkdir -p "${SCRIPT_DIR}/results"
    fi

    # Verify all test suite files exist
    local missing_suites=()
    for suite in "${TEST_SUITES[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${suite}" ]]; then
            missing_suites+=("$suite")
        elif [[ ! -x "${SCRIPT_DIR}/${suite}" ]]; then
            log_warn "Making $suite executable"
            chmod +x "${SCRIPT_DIR}/${suite}"
        fi
    done

    if [[ ${#missing_suites[@]} -gt 0 ]]; then
        log_error "Missing test suite files: ${missing_suites[*]}"
        exit 1
    fi

    log_success "Test environment setup complete"
}

# Display test banner
show_banner() {
    local border="═══════════════════════════════════════════════════════════════════════"
    echo -e "${BLUE}${border}${NC}"
    echo -e "${WHITE}                    Module Loading Fixes Test Suite                    ${NC}"
    echo -e "${WHITE}                           $(date '+%Y-%m-%d %H:%M:%S')                            ${NC}"
    echo -e "${BLUE}${border}${NC}"
    echo
}

# Run a single test suite
run_test_suite() {
    local suite_name="$1"
    local suite_path="${SCRIPT_DIR}/${suite_name}"

    ((TOTAL_SUITES++))

    log_header "Running Test Suite: ${suite_name}"
    echo "─────────────────────────────────────────────────────────"

    local start_time=$(date +%s)
    local output_file

    if [[ "$GENERATE_REPORT" == "true" ]]; then
        output_file="${SCRIPT_DIR}/results/${suite_name%.sh}_output.txt"
    else
        output_file="/dev/null"
    fi

    # Run the test suite
    local exit_code=0
    if [[ "$VERBOSE" == "true" ]]; then
        "$suite_path" 2>&1 | tee "$output_file" || exit_code=$?
    else
        "$suite_path" >"$output_file" 2>&1 || exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse results from output
    local suite_tests=0
    local suite_passed=0
    local suite_failed=0

    if [[ -f "$output_file" ]] && [[ "$output_file" != "/dev/null" ]]; then
        suite_tests=$(grep -o "Total tests: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")
        suite_passed=$(grep -o "Passed: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")
        suite_failed=$(grep -o "Failed: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")
    fi

    # Update totals
    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))
    TOTAL_PASSED=$((TOTAL_PASSED + suite_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + suite_failed))

    # Display results
    if [[ $exit_code -eq 0 ]]; then
        ((PASSED_SUITES++))
        log_success "PASSED: ${suite_name} (${duration}s) - Tests: ${suite_tests}, Passed: ${suite_passed}, Failed: ${suite_failed}"
    else
        ((FAILED_SUITES++))
        log_error "FAILED: ${suite_name} (${duration}s) - Tests: ${suite_tests}, Passed: ${suite_passed}, Failed: ${suite_failed}"

        if [[ "$VERBOSE" == "false" ]] && [[ -f "$output_file" ]] && [[ "$output_file" != "/dev/null" ]]; then
            echo "Last 10 lines of output:"
            tail -10 "$output_file" 2>/dev/null || echo "No output available"
        fi

        if [[ "$STOP_ON_FAILURE" == "true" ]]; then
            log_error "Stopping execution due to test suite failure"
            return $exit_code
        fi
    fi

    echo
    return $exit_code
}

# Generate comprehensive test report
generate_test_report() {
    if [[ "$GENERATE_REPORT" != "true" ]]; then
        return 0
    fi

    log_info "Generating comprehensive test report"

    cat > "$REPORT_FILE" << EOF
Module Loading Fixes Test Suite Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Project: VLESS+Reality VPN Management System

EXECUTIVE SUMMARY
═════════════════
Total Test Suites: $TOTAL_SUITES
Passed Suites:     $PASSED_SUITES
Failed Suites:     $FAILED_SUITES
Success Rate:      $(( TOTAL_SUITES > 0 ? (PASSED_SUITES * 100) / TOTAL_SUITES : 0 ))%

Total Tests:       $TOTAL_TESTS
Passed Tests:      $TOTAL_PASSED
Failed Tests:      $TOTAL_FAILED
Test Success Rate: $(( TOTAL_TESTS > 0 ? (TOTAL_PASSED * 100) / TOTAL_TESTS : 0 ))%

TEST SUITE DETAILS
══════════════════
EOF

    # Add details for each test suite
    for suite in "${TEST_SUITES[@]}"; do
        local output_file="${SCRIPT_DIR}/results/${suite%.sh}_output.txt"
        echo "" >> "$REPORT_FILE"
        echo "Test Suite: $suite" >> "$REPORT_FILE"
        echo "─────────────────────────────────────" >> "$REPORT_FILE"

        if [[ -f "$output_file" ]]; then
            local suite_tests=$(grep -o "Total tests: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")
            local suite_passed=$(grep -o "Passed: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")
            local suite_failed=$(grep -o "Failed: [0-9]*" "$output_file" 2>/dev/null | tail -1 | grep -o "[0-9]*" || echo "0")

            echo "Tests: $suite_tests, Passed: $suite_passed, Failed: $suite_failed" >> "$REPORT_FILE"

            # Add failed test details if any
            if [[ $suite_failed -gt 0 ]]; then
                echo "" >> "$REPORT_FILE"
                echo "Failed Tests:" >> "$REPORT_FILE"
                grep "FAILED:" "$output_file" 2>/dev/null | sed 's/^/  /' >> "$REPORT_FILE" || echo "  No failure details available" >> "$REPORT_FILE"
            fi
        else
            echo "No output file found" >> "$REPORT_FILE"
        fi
    done

    # Add system information
    cat >> "$REPORT_FILE" << EOF

SYSTEM INFORMATION
══════════════════
Hostname:     $(hostname)
OS:           $(uname -s)
Kernel:       $(uname -r)
Architecture: $(uname -m)
Date:         $(date)
User:         $(whoami)
Working Dir:  $(pwd)

ENVIRONMENT
═══════════
VERBOSE:            $VERBOSE
STOP_ON_FAILURE:    $STOP_ON_FAILURE
GENERATE_REPORT:    $GENERATE_REPORT

PROJECT PATHS
═════════════
Script Directory:   $SCRIPT_DIR
Project Root:       $PROJECT_ROOT
Report File:        $REPORT_FILE
EOF

    log_success "Test report generated: $REPORT_FILE"
}

# Display final summary
show_final_summary() {
    local border="═══════════════════════════════════════════════════════════════════════"
    echo -e "${BLUE}${border}${NC}"
    echo -e "${WHITE}                    Module Loading Tests Final Summary                  ${NC}"
    echo -e "${BLUE}${border}${NC}"
    echo

    echo -e "Test Suites:   ${CYAN}$TOTAL_SUITES${NC}"
    if [[ $PASSED_SUITES -gt 0 ]]; then
        echo -e "Passed Suites: ${GREEN}$PASSED_SUITES${NC}"
    fi
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo -e "Failed Suites: ${RED}$FAILED_SUITES${NC}"
    fi
    echo

    echo -e "Total Tests:   ${CYAN}$TOTAL_TESTS${NC}"
    if [[ $TOTAL_PASSED -gt 0 ]]; then
        echo -e "Passed Tests:  ${GREEN}$TOTAL_PASSED${NC}"
    fi
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        echo -e "Failed Tests:  ${RED}$TOTAL_FAILED${NC}"
    fi

    # Calculate success rates
    local suite_success_rate=0
    local test_success_rate=0

    if [[ $TOTAL_SUITES -gt 0 ]]; then
        suite_success_rate=$(( (PASSED_SUITES * 100) / TOTAL_SUITES ))
    fi

    if [[ $TOTAL_TESTS -gt 0 ]]; then
        test_success_rate=$(( (TOTAL_PASSED * 100) / TOTAL_TESTS ))
    fi

    echo
    echo -e "Suite Success Rate: ${CYAN}${suite_success_rate}%${NC}"
    echo -e "Test Success Rate:  ${CYAN}${test_success_rate}%${NC}"

    if [[ "$GENERATE_REPORT" == "true" ]]; then
        echo
        echo -e "Report File: ${CYAN}$REPORT_FILE${NC}"
    fi

    echo

    # Final status message
    if [[ $FAILED_SUITES -eq 0 ]]; then
        log_success "All module loading fix tests passed successfully!"
        echo -e "${GREEN}✓ Module loading fixes are working correctly${NC}"
        echo -e "${GREEN}✓ No readonly variable conflicts detected${NC}"
        echo -e "${GREEN}✓ SCRIPT_DIR handling is proper${NC}"
        echo -e "${GREEN}✓ Container management module is functional${NC}"
        return 0
    else
        log_error "Some module loading tests failed"
        echo -e "${RED}✗ Module loading issues detected${NC}"
        if [[ $FAILED_SUITES -lt $TOTAL_SUITES ]]; then
            echo -e "${YELLOW}⚠ Partial success - some test suites passed${NC}"
        fi
        return 1
    fi
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files"

    # Remove temporary output files if not in verbose mode and not generating report
    if [[ "$VERBOSE" == "false" ]] && [[ "$GENERATE_REPORT" != "true" ]]; then
        rm -f "${SCRIPT_DIR}/results/"*_output.txt 2>/dev/null || true
    fi
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Display banner
    show_banner

    # Setup test environment
    setup_test_environment

    # Display configuration
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Verbose:           $VERBOSE"
    echo "  Stop on Failure:   $STOP_ON_FAILURE"
    echo "  Generate Report:   $GENERATE_REPORT"
    echo "  Project Root:      $PROJECT_ROOT"
    echo "  Test Suites:       ${#TEST_SUITES[@]}"
    echo

    # Run all test suites
    local overall_exit_code=0
    for suite in "${TEST_SUITES[@]}"; do
        if ! run_test_suite "$suite"; then
            overall_exit_code=1
            if [[ "$STOP_ON_FAILURE" == "true" ]]; then
                break
            fi
        fi
    done

    # Generate report if requested
    generate_test_report

    # Show final summary
    show_final_summary

    # Cleanup
    cleanup

    return $overall_exit_code
}

# Trap for cleanup on exit
trap cleanup EXIT

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
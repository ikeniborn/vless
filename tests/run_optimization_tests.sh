#!/bin/bash

# VLESS+Reality VPN Management System - Optimization Tests Runner
# Version: 1.0.0
# Description: Master test runner for Phase 4-5 optimization changes

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_RESULTS_DIR="${SCRIPT_DIR}/results"
readonly TEST_SUMMARY_FILE="${TEST_RESULTS_DIR}/optimization_tests_summary.txt"
readonly TEST_REPORT_FILE="${TEST_RESULTS_DIR}/optimization_tests_report.html"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Test suite definitions
declare -A TEST_SUITES=(
    ["installation_modes"]="test_installation_modes.sh"
    ["safety_utils"]="test_safety_utils.sh"
    ["ssh_hardening_safety"]="test_ssh_hardening_safety.sh"
    ["monitoring_optimization"]="test_monitoring_optimization.sh"
    ["backup_strategy"]="test_backup_strategy.sh"
)

# Test results tracking
declare -A TEST_RESULTS=()
declare -A TEST_DURATIONS=()
declare -A TEST_DETAILS=()

# Global counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Initialize test environment
init_test_environment() {
    echo -e "${CYAN}Initializing Phase 4-5 Optimization Tests Environment${NC}"

    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Clear previous results
    rm -f "$TEST_SUMMARY_FILE" "$TEST_REPORT_FILE"

    # Count total test suites
    TOTAL_SUITES=${#TEST_SUITES[@]}

    echo -e "${WHITE}Test Environment Initialized${NC}"
    echo -e "Results directory: ${TEST_RESULTS_DIR}"
    echo -e "Total test suites: ${TOTAL_SUITES}\n"
}

# Print usage information
print_usage() {
    cat << EOF
VLESS+Reality VPN Management System - Optimization Tests Runner

Usage: $0 [OPTIONS] [TEST_SUITE...]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Enable quiet mode (errors only)
    -f, --fail-fast         Stop on first test failure
    -r, --report            Generate HTML report
    -s, --summary           Show summary only
    --parallel              Run tests in parallel (experimental)
    --timeout SECONDS       Set timeout for each test suite (default: 300)

TEST_SUITES:
    installation_modes      Test installation mode configurations
    safety_utils           Test safety utilities functions
    ssh_hardening_safety   Test SSH hardening safety features
    monitoring_optimization Test monitoring profile optimizations
    backup_strategy        Test backup profile and strategy configurations
    all                    Run all test suites (default)

EXAMPLES:
    $0                                    # Run all tests
    $0 safety_utils monitoring_optimization  # Run specific tests
    $0 --verbose --report                 # Run all tests with verbose output and HTML report
    $0 --fail-fast installation_modes    # Run installation tests, stop on failure

ENVIRONMENT VARIABLES:
    QUICK_MODE=true         Skip interactive confirmations in tests
    TEST_TIMEOUT=600        Override default test timeout (seconds)
    PARALLEL_TESTS=true     Enable parallel test execution
    VERBOSE_TESTS=true      Enable verbose test output

EOF
}

# Parse command line arguments
parse_arguments() {
    local args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--verbose)
                export VERBOSE_TESTS=true
                ;;
            -q|--quiet)
                export QUIET_TESTS=true
                ;;
            -f|--fail-fast)
                export FAIL_FAST=true
                ;;
            -r|--report)
                export GENERATE_REPORT=true
                ;;
            -s|--summary)
                export SUMMARY_ONLY=true
                ;;
            --parallel)
                export PARALLEL_TESTS=true
                ;;
            --timeout)
                export TEST_TIMEOUT="$2"
                shift
                ;;
            --*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                exit 1
                ;;
            *)
                args+=("$1")
                ;;
        esac
        shift
    done

    # Set default arguments if none provided
    if [[ ${#args[@]} -eq 0 ]]; then
        args=("all")
    fi

    echo "${args[@]}"
}

# Check if test suite exists
test_suite_exists() {
    local suite_name="$1"
    [[ -n "${TEST_SUITES[$suite_name]:-}" ]]
}

# Get test suites to run
get_test_suites_to_run() {
    local requested_suites=("$@")
    local suites_to_run=()

    for suite in "${requested_suites[@]}"; do
        if [[ "$suite" == "all" ]]; then
            suites_to_run=($(printf '%s\n' "${!TEST_SUITES[@]}" | sort))
            break
        elif test_suite_exists "$suite"; then
            suites_to_run+=("$suite")
        else
            echo -e "${RED}Warning: Test suite '$suite' not found${NC}" >&2
            echo -e "Available suites: ${!TEST_SUITES[*]}" >&2
        fi
    done

    echo "${suites_to_run[@]}"
}

# Run individual test suite
run_test_suite() {
    local suite_name="$1"
    local test_script="${TEST_SUITES[$suite_name]}"
    local test_path="${SCRIPT_DIR}/${test_script}"
    local start_time end_time duration

    echo -e "${BLUE}Running test suite: ${WHITE}$suite_name${NC}"

    # Check if test script exists
    if [[ ! -f "$test_path" ]]; then
        echo -e "${RED}Error: Test script not found: $test_path${NC}"
        TEST_RESULTS["$suite_name"]="ERROR"
        TEST_DETAILS["$suite_name"]="Test script not found"
        return 1
    fi

    # Make sure test script is executable
    chmod +x "$test_path"

    # Record start time
    start_time=$(date +%s)

    # Run test with timeout
    local timeout_duration="${TEST_TIMEOUT:-300}"
    local test_output_file="${TEST_RESULTS_DIR}/${suite_name}_output.log"
    local test_result=0

    if [[ "${VERBOSE_TESTS:-false}" == "true" ]]; then
        echo -e "${CYAN}Executing: $test_path${NC}"
        if timeout "$timeout_duration" "$test_path" 2>&1 | tee "$test_output_file"; then
            test_result=0
        else
            test_result=$?
        fi
    else
        if timeout "$timeout_duration" "$test_path" > "$test_output_file" 2>&1; then
            test_result=0
        else
            test_result=$?
        fi
    fi

    # Record end time and calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    TEST_DURATIONS["$suite_name"]=$duration

    # Analyze test result
    if [[ $test_result -eq 0 ]]; then
        echo -e "${GREEN}✓ Test suite '$suite_name' PASSED${NC} (${duration}s)"
        TEST_RESULTS["$suite_name"]="PASSED"
        TEST_DETAILS["$suite_name"]="All tests passed successfully"
        ((PASSED_SUITES++))
    elif [[ $test_result -eq 124 ]]; then
        echo -e "${YELLOW}⚠ Test suite '$suite_name' TIMEOUT${NC} (${timeout_duration}s)"
        TEST_RESULTS["$suite_name"]="TIMEOUT"
        TEST_DETAILS["$suite_name"]="Test suite timed out after ${timeout_duration} seconds"
        ((FAILED_SUITES++))
    else
        echo -e "${RED}✗ Test suite '$suite_name' FAILED${NC} (${duration}s)"
        TEST_RESULTS["$suite_name"]="FAILED"

        # Extract failure details from output
        local failure_details=""
        if [[ -f "$test_output_file" ]]; then
            failure_details=$(grep -E "(FAIL|ERROR|fail|error)" "$test_output_file" | head -3 | tr '\n' '; ' || true)
        fi
        TEST_DETAILS["$suite_name"]="${failure_details:-Test suite failed with exit code $test_result}"
        ((FAILED_SUITES++))

        # Show last few lines of output for debugging
        if [[ "${QUIET_TESTS:-false}" != "true" ]]; then
            echo -e "${YELLOW}Last few lines of output:${NC}"
            tail -10 "$test_output_file" 2>/dev/null || echo "No output available"
        fi

        # Fail fast if enabled
        if [[ "${FAIL_FAST:-false}" == "true" ]]; then
            echo -e "${RED}Fail-fast mode enabled. Stopping test execution.${NC}"
            return 1
        fi
    fi

    return $test_result
}

# Run tests in parallel
run_tests_parallel() {
    local suites_to_run=("$@")
    local pids=()
    local suite

    echo -e "${CYAN}Running tests in parallel mode${NC}"

    # Start all test suites in background
    for suite in "${suites_to_run[@]}"; do
        (run_test_suite "$suite") &
        pids+=($!)
    done

    # Wait for all tests to complete
    local overall_result=0
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local suite=${suites_to_run[$i]}

        if wait $pid; then
            echo -e "${GREEN}Background test '$suite' completed successfully${NC}"
        else
            echo -e "${RED}Background test '$suite' failed${NC}"
            overall_result=1
        fi
    done

    return $overall_result
}

# Run tests sequentially
run_tests_sequential() {
    local suites_to_run=("$@")
    local overall_result=0

    echo -e "${CYAN}Running tests in sequential mode${NC}"

    for suite in "${suites_to_run[@]}"; do
        if ! run_test_suite "$suite"; then
            overall_result=1
            if [[ "${FAIL_FAST:-false}" == "true" ]]; then
                break
            fi
        fi
        echo # Add spacing between test suites
    done

    return $overall_result
}

# Generate test summary
generate_summary() {
    local total_duration=0

    # Calculate total duration
    for duration in "${TEST_DURATIONS[@]}"; do
        total_duration=$((total_duration + duration))
    done

    # Write summary to file
    {
        echo "VLESS+Reality VPN Management System - Optimization Tests Summary"
        echo "================================================================"
        echo "Generated: $(date)"
        echo ""
        echo "OVERALL RESULTS:"
        echo "  Total test suites: $TOTAL_SUITES"
        echo "  Passed: $PASSED_SUITES"
        echo "  Failed: $FAILED_SUITES"
        echo "  Skipped: $SKIPPED_SUITES"
        echo "  Total duration: ${total_duration}s"
        echo ""
        echo "DETAILED RESULTS:"

        # Sort test suites for consistent output
        local sorted_suites=($(printf '%s\n' "${!TEST_RESULTS[@]}" | sort))

        for suite in "${sorted_suites[@]}"; do
            local result="${TEST_RESULTS[$suite]}"
            local duration="${TEST_DURATIONS[$suite]:-0}"
            local details="${TEST_DETAILS[$suite]:-No details available}"

            echo "  $suite:"
            echo "    Status: $result"
            echo "    Duration: ${duration}s"
            echo "    Details: $details"
            echo ""
        done
    } > "$TEST_SUMMARY_FILE"

    # Display summary
    echo -e "\n${PURPLE}TEST EXECUTION SUMMARY${NC}"
    echo "======================"
    echo -e "Total test suites: ${WHITE}$TOTAL_SUITES${NC}"
    echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
    echo -e "Skipped: ${YELLOW}$SKIPPED_SUITES${NC}"
    echo -e "Total duration: ${WHITE}${total_duration}s${NC}"
    echo ""

    # Show individual results
    for suite in "${sorted_suites[@]}"; do
        local result="${TEST_RESULTS[$suite]}"
        local duration="${TEST_DURATIONS[$suite]:-0}"

        case "$result" in
            "PASSED")
                echo -e "  ${GREEN}✓${NC} $suite (${duration}s)"
                ;;
            "FAILED")
                echo -e "  ${RED}✗${NC} $suite (${duration}s)"
                ;;
            "TIMEOUT")
                echo -e "  ${YELLOW}⚠${NC} $suite (timeout)"
                ;;
            "ERROR")
                echo -e "  ${RED}!${NC} $suite (error)"
                ;;
            *)
                echo -e "  ${PURPLE}?${NC} $suite (${duration}s)"
                ;;
        esac
    done

    echo -e "\nSummary saved to: ${TEST_SUMMARY_FILE}"
}

# Generate HTML report
generate_html_report() {
    if [[ "${GENERATE_REPORT:-false}" != "true" ]]; then
        return 0
    fi

    echo -e "${CYAN}Generating HTML report...${NC}"

    local total_duration=0
    for duration in "${TEST_DURATIONS[@]}"; do
        total_duration=$((total_duration + duration))
    done

    cat > "$TEST_REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VLESS Optimization Tests Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007acc; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .summary { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .metrics { display: flex; justify-content: space-around; text-align: center; }
        .metric { padding: 10px; }
        .metric-value { font-size: 2em; font-weight: bold; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .timeout { color: #ffc107; }
        .error { color: #fd7e14; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: bold; }
        tr:hover { background-color: #f5f5f5; }
        .status-badge { padding: 4px 8px; border-radius: 4px; font-weight: bold; text-transform: uppercase; font-size: 0.8em; }
        .status-passed { background-color: #d4edda; color: #155724; }
        .status-failed { background-color: #f8d7da; color: #721c24; }
        .status-timeout { background-color: #fff3cd; color: #856404; }
        .status-error { background-color: #f5c6cb; color: #721c24; }
        .footer { margin-top: 40px; text-align: center; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>VLESS+Reality VPN Management System - Optimization Tests Report</h1>

        <div class="summary">
            <h2>Executive Summary</h2>
            <p><strong>Generated:</strong> $(date)</p>
            <p><strong>Test Duration:</strong> ${total_duration} seconds</p>

            <div class="metrics">
                <div class="metric">
                    <div class="metric-value">${TOTAL_SUITES}</div>
                    <div>Total Suites</div>
                </div>
                <div class="metric">
                    <div class="metric-value passed">${PASSED_SUITES}</div>
                    <div>Passed</div>
                </div>
                <div class="metric">
                    <div class="metric-value failed">${FAILED_SUITES}</div>
                    <div>Failed</div>
                </div>
                <div class="metric">
                    <div class="metric-value timeout">${SKIPPED_SUITES}</div>
                    <div>Skipped</div>
                </div>
            </div>
        </div>

        <h2>Detailed Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Test Suite</th>
                    <th>Status</th>
                    <th>Duration (s)</th>
                    <th>Details</th>
                </tr>
            </thead>
            <tbody>
EOF

    # Add test results to HTML
    local sorted_suites=($(printf '%s\n' "${!TEST_RESULTS[@]}" | sort))
    for suite in "${sorted_suites[@]}"; do
        local result="${TEST_RESULTS[$suite]}"
        local duration="${TEST_DURATIONS[$suite]:-0}"
        local details="${TEST_DETAILS[$suite]:-No details available}"

        local status_class=""
        case "$result" in
            "PASSED") status_class="status-passed" ;;
            "FAILED") status_class="status-failed" ;;
            "TIMEOUT") status_class="status-timeout" ;;
            "ERROR") status_class="status-error" ;;
        esac

        cat >> "$TEST_REPORT_FILE" << EOF
                <tr>
                    <td><strong>$suite</strong></td>
                    <td><span class="status-badge $status_class">$result</span></td>
                    <td>$duration</td>
                    <td>$details</td>
                </tr>
EOF
    done

    cat >> "$TEST_REPORT_FILE" << EOF
            </tbody>
        </table>

        <h2>Test Suite Descriptions</h2>
        <ul>
            <li><strong>installation_modes:</strong> Tests installation mode configurations (minimal, balanced, full) and phase skipping logic</li>
            <li><strong>safety_utils:</strong> Tests safety utilities functions including confirmation dialogs, SSH key validation, and system state checks</li>
            <li><strong>ssh_hardening_safety:</strong> Tests SSH hardening safety features, rollback mechanisms, and user protection</li>
            <li><strong>monitoring_optimization:</strong> Tests monitoring profile configurations and resource optimization strategies</li>
            <li><strong>backup_strategy:</strong> Tests backup profile configurations, compression strategies, and retention policies</li>
        </ul>

        <div class="footer">
            <p>Report generated by VLESS+Reality VPN Management System Test Suite</p>
            <p>For more information, see the project documentation</p>
        </div>
    </div>
</body>
</html>
EOF

    echo -e "HTML report saved to: ${TEST_REPORT_FILE}"
}

# Main test execution function
main() {
    echo -e "${WHITE}VLESS+Reality VPN Management System - Phase 4-5 Optimization Tests${NC}"
    echo -e "${WHITE}=================================================================${NC}\n"

    # Parse command line arguments
    local requested_suites
    read -a requested_suites <<< "$(parse_arguments "$@")"

    # Initialize test environment
    init_test_environment

    # Get test suites to run
    local suites_to_run
    read -a suites_to_run <<< "$(get_test_suites_to_run "${requested_suites[@]}")"

    if [[ ${#suites_to_run[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No valid test suites specified${NC}"
        exit 1
    fi

    echo -e "${CYAN}Test suites to run: ${WHITE}${suites_to_run[*]}${NC}\n"

    # Run tests
    local test_result=0
    if [[ "${PARALLEL_TESTS:-false}" == "true" ]]; then
        run_tests_parallel "${suites_to_run[@]}" || test_result=1
    else
        run_tests_sequential "${suites_to_run[@]}" || test_result=1
    fi

    # Generate summary and reports
    if [[ "${SUMMARY_ONLY:-false}" != "true" ]]; then
        generate_summary
        generate_html_report
    else
        generate_summary
    fi

    # Final result
    echo -e "\n${WHITE}Test execution completed${NC}"

    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}All optimization tests passed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some optimization tests failed. See summary for details.${NC}"
        exit 1
    fi
}

# Error handling
set -E
trap 'echo -e "\n${RED}Test execution interrupted${NC}"' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
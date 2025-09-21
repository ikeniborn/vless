#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Master Test Runner
# ======================================================================================
# Comprehensive test runner that executes all test suites across 5 implementation phases
# and generates a consolidated test report.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TEST_RESULTS_DIR="${SCRIPT_DIR}/results"
readonly MASTER_LOG="${TEST_RESULTS_DIR}/master_test_log.log"
readonly MASTER_REPORT="${TEST_RESULTS_DIR}/test_results.md"

# Test suite files
readonly TEST_SUITES=(
    "test_phase1_integration.sh"
    "test_phase2_integration.sh"
    "test_phase3_integration.sh"
    "test_phase4_security.sh"
    "test_phase5_integration.sh"
    "test_common_utils.sh"
    "test_docker_services.sh"
    "test_user_management.sh"
    "test_backup_restore.sh"
)

# Python test files
readonly PYTHON_TESTS=(
    "test_telegram_bot_integration.py"
)

# Global test counters
TOTAL_TESTS_RUN=0
TOTAL_TESTS_PASSED=0
TOTAL_TESTS_FAILED=0
TOTAL_SUITES_RUN=0
TOTAL_SUITES_PASSED=0
TOTAL_SUITES_FAILED=0

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# ======================================================================================
# UTILITY FUNCTIONS
# ======================================================================================

# Function: log_message
# Description: Log message with timestamp to both console and log file
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local colored_message=""

    case "$level" in
        "INFO")  colored_message="${BLUE}[INFO]${NC} $message" ;;
        "PASS")  colored_message="${GREEN}[PASS]${NC} $message" ;;
        "FAIL")  colored_message="${RED}[FAIL]${NC} $message" ;;
        "WARN")  colored_message="${YELLOW}[WARN]${NC} $message" ;;
        "DEBUG") colored_message="${CYAN}[DEBUG]${NC} $message" ;;
        *)       colored_message="$message" ;;
    esac

    echo -e "$colored_message"
    echo "[$timestamp] [$level] $message" >> "$MASTER_LOG"
}

# Function: print_header
# Description: Print formatted section header
print_header() {
    local title="$1"
    local length=${#title}
    local padding=$(( (80 - length) / 2 ))

    echo ""
    echo -e "${MAGENTA}$(printf '=%.0s' {1..80})${NC}"
    echo -e "${MAGENTA}$(printf '%*s' $padding '')${title}$(printf '%*s' $padding '')${NC}"
    echo -e "${MAGENTA}$(printf '=%.0s' {1..80})${NC}"
    echo ""
}

# Function: setup_test_environment
# Description: Initialize test environment and directories
setup_test_environment() {
    log_message "INFO" "Setting up master test environment..."

    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Initialize master log
    echo "VLESS+Reality VPN Management System - Master Test Log" > "$MASTER_LOG"
    echo "Test Run Started: $(date)" >> "$MASTER_LOG"
    echo "===========================================" >> "$MASTER_LOG"

    # Export test mode for all child scripts
    export TEST_MODE="true"
    export DRY_RUN="true"
    export SKIP_INTERACTIVE="true"

    log_message "INFO" "Test environment initialized successfully"
}

# Function: run_shell_test_suite
# Description: Execute a shell test suite and collect results
run_shell_test_suite() {
    local test_file="$1"
    local test_path="${SCRIPT_DIR}/${test_file}"

    if [[ ! -f "$test_path" ]]; then
        log_message "WARN" "Test file not found: $test_file"
        return 1
    fi

    log_message "INFO" "Running test suite: $test_file"

    # Make sure test file is executable
    chmod +x "$test_path"

    # Run the test suite and capture output
    local suite_output=""
    local suite_exit_code=0

    if suite_output=$(cd "$SCRIPT_DIR" && "./$test_file" 2>&1); then
        suite_exit_code=0
        log_message "PASS" "Test suite completed: $test_file"
    else
        suite_exit_code=$?
        log_message "FAIL" "Test suite failed: $test_file (exit code: $suite_exit_code)"
    fi

    # Parse test results from output
    local tests_run=0
    local tests_passed=0
    local tests_failed=0

    # Try to extract test counts from output
    if echo "$suite_output" | grep -q "Tests run:"; then
        tests_run=$(echo "$suite_output" | grep "Tests run:" | tail -1 | sed 's/.*Tests run: \([0-9]*\).*/\1/' || echo "0")
        tests_passed=$(echo "$suite_output" | grep "Passed:" | tail -1 | sed 's/.*Passed: \([0-9]*\).*/\1/' || echo "0")
        tests_failed=$(echo "$suite_output" | grep "Failed:" | tail -1 | sed 's/.*Failed: \([0-9]*\).*/\1/' || echo "0")
    else
        # Fallback: count PASS/FAIL messages
        tests_passed=$(echo "$suite_output" | grep -c '\[PASS\]' 2>/dev/null || echo "0")
        tests_failed=$(echo "$suite_output" | grep -c '\[FAIL\]' 2>/dev/null || echo "0")
    fi

    # Ensure all variables are numeric and clean
    tests_run=$(echo "${tests_run:-0}" | tr -cd '0-9' | head -c 10)
    tests_passed=$(echo "${tests_passed:-0}" | tr -cd '0-9' | head -c 10)
    tests_failed=$(echo "${tests_failed:-0}" | tr -cd '0-9' | head -c 10)

    # Set defaults if empty
    tests_run=${tests_run:-0}
    tests_passed=${tests_passed:-0}
    tests_failed=${tests_failed:-0}

    # Calculate tests_run if not already set
    if [[ $tests_run -eq 0 && ($tests_passed -gt 0 || $tests_failed -gt 0) ]]; then
        tests_run=$((tests_passed + tests_failed))
    fi

    # Update global counters
    TOTAL_TESTS_RUN=$((TOTAL_TESTS_RUN + tests_run))
    TOTAL_TESTS_PASSED=$((TOTAL_TESTS_PASSED + tests_passed))
    TOTAL_TESTS_FAILED=$((TOTAL_TESTS_FAILED + tests_failed))
    TOTAL_SUITES_RUN=$((TOTAL_SUITES_RUN + 1))

    if [[ $suite_exit_code -eq 0 && $tests_failed -eq 0 ]]; then
        TOTAL_SUITES_PASSED=$((TOTAL_SUITES_PASSED + 1))
    else
        TOTAL_SUITES_FAILED=$((TOTAL_SUITES_FAILED + 1))
    fi

    # Log detailed results
    log_message "INFO" "Suite results - Run: $tests_run, Passed: $tests_passed, Failed: $tests_failed"

    # Save suite output to separate file
    echo "$suite_output" > "${TEST_RESULTS_DIR}/${test_file%.sh}_output.log"

    return $suite_exit_code
}

# Function: run_python_test_suite
# Description: Execute Python test suite using pytest
run_python_test_suite() {
    local test_file="$1"
    local test_path="${SCRIPT_DIR}/${test_file}"

    if [[ ! -f "$test_path" ]]; then
        log_message "WARN" "Python test file not found: $test_file"
        return 1
    fi

    log_message "INFO" "Running Python test suite: $test_file"

    # Check if pytest is available
    if ! command -v pytest >/dev/null 2>&1; then
        log_message "WARN" "pytest not found, attempting to run with python3 -m pytest"
        if ! python3 -c "import pytest" >/dev/null 2>&1; then
            log_message "WARN" "pytest not available, skipping Python tests"
            return 1
        fi
    fi

    # Run pytest with verbose output
    local suite_output=""
    local suite_exit_code=0

    if suite_output=$(cd "$SCRIPT_DIR" && python3 -m pytest "$test_file" -v --tb=short 2>&1); then
        suite_exit_code=0
        log_message "PASS" "Python test suite completed: $test_file"
    else
        suite_exit_code=$?
        log_message "FAIL" "Python test suite failed: $test_file (exit code: $suite_exit_code)"
    fi

    # Parse pytest results
    local tests_run=0
    local tests_passed=0
    local tests_failed=0

    if echo "$suite_output" | grep -q "passed\|failed\|error"; then
        tests_passed=$(echo "$suite_output" | grep -o '[0-9]* passed' | head -1 | sed 's/ passed//' 2>/dev/null || echo "0")
        tests_failed=$(echo "$suite_output" | grep -o '[0-9]* failed' | head -1 | sed 's/ failed//' 2>/dev/null || echo "0")
        local tests_error=$(echo "$suite_output" | grep -o '[0-9]* error' | head -1 | sed 's/ error//' 2>/dev/null || echo "0")
        tests_failed=$((tests_failed + tests_error))
    fi

    # Ensure all variables are numeric and clean
    tests_run=$(echo "${tests_run:-0}" | tr -cd '0-9' | head -c 10)
    tests_passed=$(echo "${tests_passed:-0}" | tr -cd '0-9' | head -c 10)
    tests_failed=$(echo "${tests_failed:-0}" | tr -cd '0-9' | head -c 10)

    # Set defaults if empty
    tests_run=${tests_run:-0}
    tests_passed=${tests_passed:-0}
    tests_failed=${tests_failed:-0}

    # Calculate tests_run if not already set
    if [[ $tests_run -eq 0 && ($tests_passed -gt 0 || $tests_failed -gt 0) ]]; then
        tests_run=$((tests_passed + tests_failed))
    fi

    # Update global counters
    TOTAL_TESTS_RUN=$((TOTAL_TESTS_RUN + tests_run))
    TOTAL_TESTS_PASSED=$((TOTAL_TESTS_PASSED + tests_passed))
    TOTAL_TESTS_FAILED=$((TOTAL_TESTS_FAILED + tests_failed))
    TOTAL_SUITES_RUN=$((TOTAL_SUITES_RUN + 1))

    if [[ $suite_exit_code -eq 0 && $tests_failed -eq 0 ]]; then
        TOTAL_SUITES_PASSED=$((TOTAL_SUITES_PASSED + 1))
    else
        TOTAL_SUITES_FAILED=$((TOTAL_SUITES_FAILED + 1))
    fi

    # Log detailed results
    log_message "INFO" "Python suite results - Run: $tests_run, Passed: $tests_passed, Failed: $tests_failed"

    # Save suite output
    echo "$suite_output" > "${TEST_RESULTS_DIR}/${test_file%.py}_output.log"

    return $suite_exit_code
}

# Function: generate_test_report
# Description: Generate comprehensive test report in Markdown format
generate_test_report() {
    log_message "INFO" "Generating comprehensive test report..."

    local report_date=$(date '+%Y-%m-%d %H:%M:%S')
    local success_rate=0

    if [[ $TOTAL_TESTS_RUN -gt 0 ]]; then
        success_rate=$((TOTAL_TESTS_PASSED * 100 / TOTAL_TESTS_RUN))
    fi

    cat > "$MASTER_REPORT" << EOF
# VLESS+Reality VPN Management System - Test Results

**Test Run Date:** $report_date
**Test Environment:** CI/CD Pipeline (Dry-run mode)
**Project Version:** 1.0

## Executive Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total Test Suites** | $TOTAL_SUITES_RUN | 100% |
| **Suites Passed** | $TOTAL_SUITES_PASSED | $((TOTAL_SUITES_RUN > 0 ? TOTAL_SUITES_PASSED * 100 / TOTAL_SUITES_RUN : 0))% |
| **Suites Failed** | $TOTAL_SUITES_FAILED | $((TOTAL_SUITES_RUN > 0 ? TOTAL_SUITES_FAILED * 100 / TOTAL_SUITES_RUN : 0))% |
| **Total Individual Tests** | $TOTAL_TESTS_RUN | 100% |
| **Tests Passed** | $TOTAL_TESTS_PASSED | $success_rate% |
| **Tests Failed** | $TOTAL_TESTS_FAILED | $((TOTAL_TESTS_RUN > 0 ? TOTAL_TESTS_FAILED * 100 / TOTAL_TESTS_RUN : 0))% |

## Overall Status

EOF

    if [[ $TOTAL_SUITES_FAILED -eq 0 && $TOTAL_TESTS_FAILED -eq 0 ]]; then
        echo "✅ **ALL TESTS PASSED** - System is ready for deployment" >> "$MASTER_REPORT"
    elif [[ $TOTAL_TESTS_FAILED -le $((TOTAL_TESTS_RUN / 10)) ]]; then
        echo "⚠️ **MOSTLY PASSING** - Minor issues detected, review recommended" >> "$MASTER_REPORT"
    else
        echo "❌ **SIGNIFICANT FAILURES** - Critical issues detected, deployment blocked" >> "$MASTER_REPORT"
    fi

    cat >> "$MASTER_REPORT" << EOF

## Test Suite Results

| Test Suite | Status | Tests Run | Passed | Failed | Success Rate |
|------------|--------|-----------|--------|--------|--------------|
EOF

    # Add results for each test suite
    for test_suite in "${TEST_SUITES[@]}" "${PYTHON_TESTS[@]}"; do
        local output_file="${TEST_RESULTS_DIR}/${test_suite%.*}_output.log"
        local status="❌ FAILED"
        local tests_run=0
        local tests_passed=0
        local tests_failed=0
        local success_rate=0

        if [[ -f "$output_file" ]]; then
            # Extract results from output file
            if grep -q '\[PASS\]\|\[FAIL\]' "$output_file"; then
                tests_passed=$(grep -c '\[PASS\]' "$output_file" || echo "0")
                tests_failed=$(grep -c '\[FAIL\]' "$output_file" || echo "0")
                tests_run=$((tests_passed + tests_failed))
            elif grep -q 'passed\|failed' "$output_file"; then
                tests_passed=$(grep -o '[0-9]* passed' "$output_file" | head -1 | sed 's/ passed//' || echo "0")
                tests_failed=$(grep -o '[0-9]* failed' "$output_file" | head -1 | sed 's/ failed//' || echo "0")
                tests_run=$((tests_passed + tests_failed))
            fi

            if [[ $tests_failed -eq 0 && $tests_run -gt 0 ]]; then
                status="✅ PASSED"
            elif [[ $tests_run -eq 0 ]]; then
                status="⚠️ NO TESTS"
            fi

            if [[ $tests_run -gt 0 ]]; then
                success_rate=$((tests_passed * 100 / tests_run))
            fi
        else
            status="📁 NOT FOUND"
        fi

        echo "| $test_suite | $status | $tests_run | $tests_passed | $tests_failed | ${success_rate}% |" >> "$MASTER_REPORT"
    done

    cat >> "$MASTER_REPORT" << EOF

## Phase Coverage Analysis

### Phase 1: Foundation & Utilities
- **Common Utilities:** Logging, color output, utility functions
- **Installation:** System setup and configuration
- **Status:** $(grep -q "test_phase1_integration.sh.*✅" "$MASTER_REPORT" && echo "✅ PASSED" || echo "❌ FAILED")

### Phase 2: Container Infrastructure
- **Docker Setup:** Container configuration and management
- **Service Management:** Docker Compose integration
- **Status:** $(grep -q "test_phase2_integration.sh.*✅" "$MASTER_REPORT" && echo "✅ PASSED" || echo "❌ FAILED")

### Phase 3: User Management
- **User Database:** SQLite database operations
- **User Operations:** Create, delete, modify users
- **Status:** $(grep -q "test_phase3_integration.sh.*✅" "$MASTER_REPORT" && echo "✅ PASSED" || echo "❌ FAILED")

### Phase 4: Security & Integration
- **Security Hardening:** UFW firewall, certificate management
- **System Integration:** Component integration testing
- **Status:** $(grep -q "test_phase4_security.sh.*✅" "$MASTER_REPORT" && echo "✅ PASSED" || echo "❌ FAILED")

### Phase 5: Monitoring & Management
- **Monitoring:** System health checks and alerts
- **Telegram Bot:** User interface and management
- **Status:** $(grep -q "test_phase5_integration.sh.*✅" "$MASTER_REPORT" && echo "✅ PASSED" || echo "❌ FAILED")

## Test Coverage Details

### Unit Tests
- **Common Utilities:** Function-level testing of utility modules
- **User Management:** Database operations and user lifecycle
- **Docker Services:** Container management operations

### Integration Tests
- **Phase Integration:** End-to-end testing of each implementation phase
- **Cross-component:** Testing interaction between different modules
- **System-wide:** Full system integration verification

### Security Tests
- **Configuration Validation:** Security settings and hardening
- **Access Control:** User permissions and authentication
- **Network Security:** Firewall rules and network isolation

## Recommendations

EOF

    if [[ $TOTAL_TESTS_FAILED -eq 0 ]]; then
        cat >> "$MASTER_REPORT" << EOF
✅ **System Ready for Production**
- All tests passing successfully
- No critical issues detected
- Deployment can proceed

EOF
    else
        cat >> "$MASTER_REPORT" << EOF
⚠️ **Issues Require Attention**
- $TOTAL_TESTS_FAILED test(s) failing
- Review failed tests before deployment
- Check logs for detailed error information

### Priority Actions:
1. Review failed test logs in \`tests/results/\` directory
2. Fix identified issues
3. Re-run test suite to verify fixes
4. Update documentation if needed

EOF
    fi

    cat >> "$MASTER_REPORT" << EOF
## Log Files

- **Master Log:** \`tests/results/master_test_log.log\`
- **Individual Suite Logs:** \`tests/results/*_output.log\`

---
*Generated by VLESS+Reality VPN Management System Test Runner v1.0*
*Test run completed at: $report_date*
EOF

    log_message "INFO" "Test report generated: $MASTER_REPORT"
}

# Function: print_summary
# Description: Print test execution summary to console
print_summary() {
    print_header "TEST EXECUTION SUMMARY"

    echo -e "${CYAN}Test Suites:${NC}"
    echo -e "  Total Run: $TOTAL_SUITES_RUN"
    echo -e "  Passed:    ${GREEN}$TOTAL_SUITES_PASSED${NC}"
    echo -e "  Failed:    ${RED}$TOTAL_SUITES_FAILED${NC}"
    echo ""

    echo -e "${CYAN}Individual Tests:${NC}"
    echo -e "  Total Run: $TOTAL_TESTS_RUN"
    echo -e "  Passed:    ${GREEN}$TOTAL_TESTS_PASSED${NC}"
    echo -e "  Failed:    ${RED}$TOTAL_TESTS_FAILED${NC}"
    echo ""

    local success_rate=0
    if [[ $TOTAL_TESTS_RUN -gt 0 ]]; then
        success_rate=$((TOTAL_TESTS_PASSED * 100 / TOTAL_TESTS_RUN))
    fi

    echo -e "${CYAN}Success Rate:${NC} $success_rate%"
    echo ""

    if [[ $TOTAL_SUITES_FAILED -eq 0 && $TOTAL_TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! System ready for deployment.${NC}"
    else
        echo -e "${YELLOW}⚠️  Some tests failed. Review logs for details.${NC}"
    fi

    echo ""
    echo -e "${CYAN}Results saved to:${NC} $MASTER_REPORT"
    echo -e "${CYAN}Logs available in:${NC} $TEST_RESULTS_DIR"
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

main() {
    print_header "VLESS+Reality VPN Management System - Master Test Runner"

    # Setup test environment
    setup_test_environment

    # Run all shell test suites
    print_header "RUNNING SHELL TEST SUITES"
    for test_suite in "${TEST_SUITES[@]}"; do
        run_shell_test_suite "$test_suite" || true  # Continue on failure
        echo ""
    done

    # Run Python test suites
    print_header "RUNNING PYTHON TEST SUITES"
    for test_suite in "${PYTHON_TESTS[@]}"; do
        run_python_test_suite "$test_suite" || true  # Continue on failure
        echo ""
    done

    # Generate comprehensive report
    print_header "GENERATING TEST REPORT"
    generate_test_report

    # Print summary
    print_summary

    # Copy report to project root for visibility
    cp "$MASTER_REPORT" "/home/ikeniborn/Documents/Project/vless/tests/test_results.md"

    log_message "INFO" "Master test run completed"

    # Exit with appropriate code
    if [[ $TOTAL_SUITES_FAILED -eq 0 && $TOTAL_TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Test Results Aggregator
# ======================================================================================
# Standalone utility for aggregating and analyzing test results from multiple sources.
# Can be used independently of the master test runner.
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
readonly AGGREGATED_REPORT="${TEST_RESULTS_DIR}/aggregated_results.md"
readonly DETAILED_LOG="${TEST_RESULTS_DIR}/aggregated_log.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Global counters
TOTAL_LOG_FILES=0
TOTAL_SUITES_FOUND=0
TOTAL_TESTS_AGGREGATED=0
TOTAL_PASSED_AGGREGATED=0
TOTAL_FAILED_AGGREGATED=0

# ======================================================================================
# UTILITY FUNCTIONS
# ======================================================================================

# Function: log_message
# Description: Log message with timestamp
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
    echo "[$timestamp] [$level] $message" >> "$DETAILED_LOG"
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

# Function: analyze_log_file
# Description: Analyze individual test log file and extract metrics
analyze_log_file() {
    local log_file="$1"
    local file_name=$(basename "$log_file")

    log_message "DEBUG" "Analyzing log file: $file_name"

    if [[ ! -f "$log_file" ]]; then
        log_message "WARN" "Log file not found: $log_file"
        return 1
    fi

    # Initialize counters for this file
    local tests_run=0
    local tests_passed=0
    local tests_failed=0
    local suite_status="UNKNOWN"

    # Extract test results based on different patterns
    if grep -q '\[PASS\]\|\[FAIL\]' "$log_file"; then
        # Shell script pattern
        tests_passed=$(grep -c '\[PASS\]' "$log_file" || echo "0")
        tests_failed=$(grep -c '\[FAIL\]' "$log_file" || echo "0")
        tests_run=$((tests_passed + tests_failed))

        if [[ $tests_failed -eq 0 && $tests_run -gt 0 ]]; then
            suite_status="PASSED"
        elif [[ $tests_run -eq 0 ]]; then
            suite_status="NO_TESTS"
        else
            suite_status="FAILED"
        fi

    elif grep -q 'passed\|failed\|error' "$log_file"; then
        # Python pytest pattern
        tests_passed=$(grep -o '[0-9]* passed' "$log_file" | head -1 | sed 's/ passed//' || echo "0")
        tests_failed=$(grep -o '[0-9]* failed' "$log_file" | head -1 | sed 's/ failed//' || echo "0")
        local tests_error=$(grep -o '[0-9]* error' "$log_file" | head -1 | sed 's/ error//' || echo "0")
        tests_failed=$((tests_failed + tests_error))
        tests_run=$((tests_passed + tests_failed))

        if [[ $tests_failed -eq 0 && $tests_run -gt 0 ]]; then
            suite_status="PASSED"
        elif [[ $tests_run -eq 0 ]]; then
            suite_status="NO_TESTS"
        else
            suite_status="FAILED"
        fi

    elif grep -q "Tests run:\|Passed:\|Failed:" "$log_file"; then
        # Alternative shell script pattern
        tests_run=$(grep "Tests run:" "$log_file" | tail -1 | sed 's/.*Tests run: \([0-9]*\).*/\1/' || echo "0")
        tests_passed=$(grep "Passed:" "$log_file" | tail -1 | sed 's/.*Passed: \([0-9]*\).*/\1/' || echo "0")
        tests_failed=$(grep "Failed:" "$log_file" | tail -1 | sed 's/.*Failed: \([0-9]*\).*/\1/' || echo "0")

        if [[ $tests_failed -eq 0 && $tests_run -gt 0 ]]; then
            suite_status="PASSED"
        elif [[ $tests_run -eq 0 ]]; then
            suite_status="NO_TESTS"
        else
            suite_status="FAILED"
        fi
    fi

    # Update global counters
    TOTAL_TESTS_AGGREGATED=$((TOTAL_TESTS_AGGREGATED + tests_run))
    TOTAL_PASSED_AGGREGATED=$((TOTAL_PASSED_AGGREGATED + tests_passed))
    TOTAL_FAILED_AGGREGATED=$((TOTAL_FAILED_AGGREGATED + tests_failed))
    TOTAL_SUITES_FOUND=$((TOTAL_SUITES_FOUND + 1))

    # Log results
    log_message "INFO" "$file_name: $suite_status - Run: $tests_run, Passed: $tests_passed, Failed: $tests_failed"

    # Return suite data (used by calling function)
    echo "$file_name|$suite_status|$tests_run|$tests_passed|$tests_failed"
}

# Function: extract_error_summary
# Description: Extract error messages and failures from log files
extract_error_summary() {
    local log_file="$1"
    local error_file="${TEST_RESULTS_DIR}/errors_$(basename "$log_file").txt"

    # Extract error patterns
    {
        echo "=== ERRORS AND FAILURES FROM $(basename "$log_file") ==="
        echo ""

        # Extract FAIL messages
        if grep -n '\[FAIL\]' "$log_file" >/dev/null 2>&1; then
            echo "--- FAILED TESTS ---"
            grep -n '\[FAIL\]' "$log_file" || true
            echo ""
        fi

        # Extract ERROR messages
        if grep -n '\[ERROR\]' "$log_file" >/dev/null 2>&1; then
            echo "--- ERROR MESSAGES ---"
            grep -n '\[ERROR\]' "$log_file" || true
            echo ""
        fi

        # Extract Python test failures
        if grep -A 5 -B 2 'FAILED\|ERROR' "$log_file" >/dev/null 2>&1; then
            echo "--- PYTHON TEST FAILURES ---"
            grep -A 5 -B 2 'FAILED\|ERROR' "$log_file" || true
            echo ""
        fi

        # Extract assertion errors
        if grep -A 3 -B 1 'AssertionError\|assert' "$log_file" >/dev/null 2>&1; then
            echo "--- ASSERTION ERRORS ---"
            grep -A 3 -B 1 'AssertionError\|assert' "$log_file" || true
            echo ""
        fi

    } > "$error_file"

    # Only keep error file if it has actual content
    if [[ $(wc -l < "$error_file") -le 3 ]]; then
        rm -f "$error_file"
    else
        log_message "DEBUG" "Error summary saved: $error_file"
    fi
}

# Function: generate_aggregated_report
# Description: Generate comprehensive aggregated test report
generate_aggregated_report() {
    log_message "INFO" "Generating aggregated test report..."

    local report_date=$(date '+%Y-%m-%d %H:%M:%S')
    local success_rate=0

    if [[ $TOTAL_TESTS_AGGREGATED -gt 0 ]]; then
        success_rate=$((TOTAL_PASSED_AGGREGATED * 100 / TOTAL_TESTS_AGGREGATED))
    fi

    cat > "$AGGREGATED_REPORT" << EOF
# VLESS+Reality VPN Management System - Aggregated Test Results

**Analysis Date:** $report_date
**Log Files Analyzed:** $TOTAL_LOG_FILES
**Test Suites Found:** $TOTAL_SUITES_FOUND

## Aggregated Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total Tests Executed** | $TOTAL_TESTS_AGGREGATED | 100% |
| **Tests Passed** | $TOTAL_PASSED_AGGREGATED | $success_rate% |
| **Tests Failed** | $TOTAL_FAILED_AGGREGATED | $((TOTAL_TESTS_AGGREGATED > 0 ? TOTAL_FAILED_AGGREGATED * 100 / TOTAL_TESTS_AGGREGATED : 0))% |

## Overall Health Status

EOF

    if [[ $TOTAL_FAILED_AGGREGATED -eq 0 && $TOTAL_TESTS_AGGREGATED -gt 0 ]]; then
        echo "✅ **EXCELLENT** - All tests passing, system healthy" >> "$AGGREGATED_REPORT"
    elif [[ $success_rate -ge 90 ]]; then
        echo "🟢 **GOOD** - High success rate, minor issues detected" >> "$AGGREGATED_REPORT"
    elif [[ $success_rate -ge 75 ]]; then
        echo "🟡 **FAIR** - Moderate success rate, attention needed" >> "$AGGREGATED_REPORT"
    elif [[ $success_rate -ge 50 ]]; then
        echo "🟠 **POOR** - Low success rate, significant issues" >> "$AGGREGATED_REPORT"
    else
        echo "🔴 **CRITICAL** - Very low success rate, system unstable" >> "$AGGREGATED_REPORT"
    fi

    cat >> "$AGGREGATED_REPORT" << EOF

## Detailed Suite Analysis

| Log File | Status | Tests Run | Passed | Failed | Success Rate |
|----------|--------|-----------|--------|--------|--------------|
EOF

    # Analyze all log files
    local suite_data_file="${TEST_RESULTS_DIR}/suite_data.tmp"
    > "$suite_data_file"

    # Find and analyze all log files
    while IFS= read -r -d '' log_file; do
        if [[ -f "$log_file" ]]; then
            analyze_log_file "$log_file" >> "$suite_data_file"
            extract_error_summary "$log_file"
            TOTAL_LOG_FILES=$((TOTAL_LOG_FILES + 1))
        fi
    done < <(find "$TEST_RESULTS_DIR" -name "*.log" -print0 2>/dev/null || true)

    # Add suite data to report
    while IFS='|' read -r file_name suite_status tests_run tests_passed tests_failed; do
        local success_rate_suite=0
        if [[ $tests_run -gt 0 ]]; then
            success_rate_suite=$((tests_passed * 100 / tests_run))
        fi

        local status_icon=""
        case "$suite_status" in
            "PASSED") status_icon="✅ PASSED" ;;
            "FAILED") status_icon="❌ FAILED" ;;
            "NO_TESTS") status_icon="⚠️ NO TESTS" ;;
            *) status_icon="❓ UNKNOWN" ;;
        esac

        echo "| $file_name | $status_icon | $tests_run | $tests_passed | $tests_failed | ${success_rate_suite}% |" >> "$AGGREGATED_REPORT"
    done < "$suite_data_file"

    rm -f "$suite_data_file"

    cat >> "$AGGREGATED_REPORT" << EOF

## Test Coverage by Component

### System Components Tested
EOF

    # Analyze coverage by component
    local components=(
        "common_utils:Common utilities and logging"
        "user_management:User database and management"
        "docker_services:Container and service management"
        "security:Security hardening and configuration"
        "backup_restore:Backup and restore functionality"
        "telegram_bot:Telegram bot interface"
        "phase1:Phase 1 integration"
        "phase2:Phase 2 integration"
        "phase3:Phase 3 integration"
        "phase4:Phase 4 integration"
        "phase5:Phase 5 integration"
    )

    for component_info in "${components[@]}"; do
        IFS=':' read -r component_name component_desc <<< "$component_info"
        local component_tested="❌ Not tested"

        if ls "$TEST_RESULTS_DIR"/*"$component_name"*.log >/dev/null 2>&1; then
            component_tested="✅ Tested"
        fi

        echo "- **$component_desc:** $component_tested" >> "$AGGREGATED_REPORT"
    done

    cat >> "$AGGREGATED_REPORT" << EOF

## Error Analysis

EOF

    # Check for error summary files
    local error_files_found=0
    if ls "$TEST_RESULTS_DIR"/errors_*.txt >/dev/null 2>&1; then
        error_files_found=$(ls "$TEST_RESULTS_DIR"/errors_*.txt | wc -l)

        echo "**Error Summary Files Generated:** $error_files_found" >> "$AGGREGATED_REPORT"
        echo "" >> "$AGGREGATED_REPORT"
        echo "Detailed error analysis available in:" >> "$AGGREGATED_REPORT"

        for error_file in "$TEST_RESULTS_DIR"/errors_*.txt; do
            local base_name=$(basename "$error_file")
            echo "- \`$base_name\`" >> "$AGGREGATED_REPORT"
        done
    else
        echo "**No errors detected in analyzed logs** ✅" >> "$AGGREGATED_REPORT"
    fi

    cat >> "$AGGREGATED_REPORT" << EOF

## Recommendations

EOF

    if [[ $TOTAL_FAILED_AGGREGATED -eq 0 && $TOTAL_TESTS_AGGREGATED -gt 0 ]]; then
        cat >> "$AGGREGATED_REPORT" << EOF
### ✅ System Status: HEALTHY
- All tests are passing successfully
- No critical issues detected
- System is ready for production use
- Continue monitoring for any regressions

EOF
    elif [[ $success_rate -ge 90 ]]; then
        cat >> "$AGGREGATED_REPORT" << EOF
### 🟢 System Status: GOOD
- High success rate indicates stable system
- Minor failures detected - review and fix
- System suitable for staging/testing
- Address failing tests before production

### Immediate Actions:
1. Review error summary files for failure details
2. Fix identified issues in failing tests
3. Re-run affected test suites
4. Monitor for recurring patterns

EOF
    else
        cat >> "$AGGREGATED_REPORT" << EOF
### 🔴 System Status: NEEDS ATTENTION
- Significant number of test failures detected
- System stability may be compromised
- Immediate intervention required

### Critical Actions:
1. **PRIORITY 1:** Review all error summary files
2. **PRIORITY 2:** Fix critical failures first
3. **PRIORITY 3:** Re-run full test suite
4. **PRIORITY 4:** Investigate root causes
5. **PRIORITY 5:** Update test procedures if needed

### Failure Analysis:
- Failed Tests: $TOTAL_FAILED_AGGREGATED / $TOTAL_TESTS_AGGREGATED
- Success Rate: $success_rate%
- Review pattern of failures for systemic issues

EOF
    fi

    cat >> "$AGGREGATED_REPORT" << EOF
## Files and Logs

### Analysis Results
- **Aggregated Report:** \`$AGGREGATED_REPORT\`
- **Detailed Log:** \`$DETAILED_LOG\`
- **Source Directory:** \`$TEST_RESULTS_DIR\`

### Log Files Analyzed
EOF

    # List all analyzed log files
    find "$TEST_RESULTS_DIR" -name "*.log" | sort | while read -r log_file; do
        local file_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
        local file_date=$(stat -c%y "$log_file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        echo "- \`$(basename "$log_file")\` (${file_size} bytes, $file_date)" >> "$AGGREGATED_REPORT"
    done

    cat >> "$AGGREGATED_REPORT" << EOF

---
*Generated by VLESS+Reality VPN Test Results Aggregator v1.0*
*Analysis completed at: $report_date*
*Total files processed: $TOTAL_LOG_FILES*
EOF

    log_message "INFO" "Aggregated report generated: $AGGREGATED_REPORT"
}

# Function: print_summary
# Description: Print aggregation summary to console
print_summary() {
    print_header "TEST RESULTS AGGREGATION SUMMARY"

    echo -e "${CYAN}Files Processed:${NC}"
    echo -e "  Log Files: $TOTAL_LOG_FILES"
    echo -e "  Test Suites: $TOTAL_SUITES_FOUND"
    echo ""

    echo -e "${CYAN}Test Results:${NC}"
    echo -e "  Total Tests: $TOTAL_TESTS_AGGREGATED"
    echo -e "  Passed:      ${GREEN}$TOTAL_PASSED_AGGREGATED${NC}"
    echo -e "  Failed:      ${RED}$TOTAL_FAILED_AGGREGATED${NC}"
    echo ""

    local success_rate=0
    if [[ $TOTAL_TESTS_AGGREGATED -gt 0 ]]; then
        success_rate=$((TOTAL_PASSED_AGGREGATED * 100 / TOTAL_TESTS_AGGREGATED))
    fi

    echo -e "${CYAN}Success Rate:${NC} $success_rate%"
    echo ""

    if [[ $TOTAL_FAILED_AGGREGATED -eq 0 && $TOTAL_TESTS_AGGREGATED -gt 0 ]]; then
        echo -e "${GREEN}🎉 All aggregated tests passed!${NC}"
    elif [[ $success_rate -ge 90 ]]; then
        echo -e "${YELLOW}⚠️  Minor issues detected in test results.${NC}"
    else
        echo -e "${RED}❌ Significant issues found in test results.${NC}"
    fi

    echo ""
    echo -e "${CYAN}Report saved to:${NC} $AGGREGATED_REPORT"
    echo -e "${CYAN}Detailed log:${NC} $DETAILED_LOG"
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

main() {
    local mode="${1:-aggregate}"

    print_header "VLESS+Reality VPN Test Results Aggregator"

    # Initialize aggregation environment
    mkdir -p "$TEST_RESULTS_DIR"

    echo "Test Results Aggregation - $(date)" > "$DETAILED_LOG"
    echo "===========================================" >> "$DETAILED_LOG"

    case "$mode" in
        "aggregate")
            log_message "INFO" "Starting test results aggregation..."
            generate_aggregated_report
            print_summary
            ;;
        "clean")
            log_message "INFO" "Cleaning old aggregation files..."
            rm -f "$TEST_RESULTS_DIR"/aggregated_*.md
            rm -f "$TEST_RESULTS_DIR"/aggregated_*.log
            rm -f "$TEST_RESULTS_DIR"/errors_*.txt
            log_message "INFO" "Cleanup completed"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [aggregate|clean|help]"
            echo ""
            echo "Commands:"
            echo "  aggregate  - Analyze all log files and generate report (default)"
            echo "  clean      - Remove old aggregation files"
            echo "  help       - Show this help message"
            ;;
        *)
            log_message "WARN" "Unknown command: $mode"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
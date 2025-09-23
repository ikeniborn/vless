#!/bin/bash

# VLESS+Reality VPN Management System - Installation Fixes Test Runner
# Version: 1.0.0
# Description: Dedicated runner for installation fixes tests
#
# This script runs all installation fixes tests in sequence and provides
# a comprehensive report of the test results.

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly RESULTS_DIR="${SCRIPT_DIR}/results"
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Test execution tracking
declare -A TEST_RESULTS=(
    ["validation"]=0
    ["main"]=0
    ["edge_cases"]=0
)

# Initialize results directory
initialize_test_runner() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        VLESS+Reality VPN - Installation Fixes Test Runner      ║${NC}"
    echo -e "${CYAN}║                        Version 1.0.0                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    mkdir -p "$RESULTS_DIR"

    echo -e "${BLUE}📁 Results Directory: ${WHITE}$RESULTS_DIR${NC}"
    echo -e "${BLUE}📊 Test Timestamp: ${WHITE}$TIMESTAMP${NC}"
    echo ""
}

# Run individual test suite
run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local description="$3"

    echo -e "${YELLOW}▶ Running: ${WHITE}$description${NC}"
    echo -e "${BLUE}  Script: ${test_script}${NC}"
    echo ""

    local start_time=$(date +%s)
    local result_file="${RESULTS_DIR}/${test_name}_${TIMESTAMP}.log"

    if timeout 300 "$test_script" > "$result_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo -e "${GREEN}✓ ${test_name} PASSED${NC} (${duration}s)"
        TEST_RESULTS["$test_name"]=1

        # Show summary from log
        if grep -q "Test Suite Results" "$result_file"; then
            echo -e "${CYAN}  Summary:${NC}"
            grep -A 10 "Test Suite Results" "$result_file" | grep -E "(Total|Passed|Failed|Skipped|Success Rate)" | sed 's/^/    /'
        fi
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo -e "${RED}✗ ${test_name} FAILED${NC} (${duration}s)"
        TEST_RESULTS["$test_name"]=0

        # Show error details
        echo -e "${RED}  Error Details:${NC}"
        tail -10 "$result_file" | sed 's/^/    /'
    fi

    echo -e "${BLUE}  Log: ${result_file}${NC}"
    echo ""
}

# Generate final report
generate_final_report() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    FINAL TEST REPORT                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_tests=3
    local passed_tests=0

    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ ${TEST_RESULTS[$test_name]} -eq 1 ]]; then
            ((passed_tests++))
            echo -e "${GREEN}✓ ${test_name} test suite: PASSED${NC}"
        else
            echo -e "${RED}✗ ${test_name} test suite: FAILED${NC}"
        fi
    done

    echo ""
    echo -e "${WHITE}Test Summary:${NC}"
    echo -e "  Total Test Suites: $total_tests"
    echo -e "  Passed: ${GREEN}$passed_tests${NC}"
    echo -e "  Failed: ${RED}$((total_tests - passed_tests))${NC}"

    local success_rate=$((passed_tests * 100 / total_tests))
    echo -e "  Success Rate: ${WHITE}${success_rate}%${NC}"

    echo ""
    if [[ $passed_tests -eq $total_tests ]]; then
        echo -e "${GREEN}🎉 ALL INSTALLATION FIXES TESTS PASSED!${NC}"
        echo -e "${GREEN}   Installation fixes are working correctly.${NC}"
        return 0
    else
        echo -e "${RED}❌ SOME TESTS FAILED${NC}"
        echo -e "${RED}   Please review the test logs for details.${NC}"
        return 1
    fi
}

# Show test information
show_test_info() {
    echo -e "${CYAN}Installation Fixes Test Coverage:${NC}"
    echo ""
    echo -e "${WHITE}1. Include Guard Functionality${NC}"
    echo -e "   • Prevents multiple sourcing of common_utils.sh"
    echo -e "   • Handles recursive sourcing scenarios"
    echo ""
    echo -e "${WHITE}2. VLESS System User Creation${NC}"
    echo -e "   • Creates vless user and group if they don't exist"
    echo -e "   • Handles existing users gracefully"
    echo -e "   • Tests permission denied scenarios"
    echo ""
    echo -e "${WHITE}3. Python Dependencies Installation${NC}"
    echo -e "   • Installs packages from requirements.txt"
    echo -e "   • Handles missing files and network timeouts"
    echo -e "   • Multiple fallback strategies"
    echo ""
    echo -e "${WHITE}4. UFW Validation Improvements${NC}"
    echo -e "   • Parses UFW status output correctly"
    echo -e "   • Handles malformed output gracefully"
    echo -e "   • Tests active/inactive status detection"
    echo ""
    echo -e "${WHITE}5. QUICK_MODE Support${NC}"
    echo -e "   • Skips interactive prompts when enabled"
    echo -e "   • Environment variable handling"
    echo -e "   • Integration with installation phases"
    echo ""
}

# Check test prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking test prerequisites...${NC}"

    # Check if test files exist
    local test_files=(
        "test_installation_fixes_validation.sh"
        "test_installation_fixes.sh"
        "test_installation_fixes_edge_cases.sh"
    )

    local missing_files=()
    for test_file in "${test_files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${test_file}" ]]; then
            missing_files+=("$test_file")
        elif [[ ! -x "${SCRIPT_DIR}/${test_file}" ]]; then
            chmod +x "${SCRIPT_DIR}/${test_file}"
            echo -e "${YELLOW}  Made ${test_file} executable${NC}"
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing test files:${NC}"
        for file in "${missing_files[@]}"; do
            echo -e "   • $file"
        done
        return 1
    fi

    echo -e "${GREEN}✓ All test files found and executable${NC}"
    echo ""
    return 0
}

# Main execution
main() {
    initialize_test_runner

    if ! check_prerequisites; then
        echo -e "${RED}Prerequisites check failed. Exiting.${NC}"
        exit 1
    fi

    show_test_info

    echo -e "${CYAN}Starting test execution...${NC}"
    echo ""

    # Run tests in order of complexity
    run_test_suite "validation" \
                  "${SCRIPT_DIR}/test_installation_fixes_validation.sh" \
                  "Installation Fixes Validation Tests"

    run_test_suite "main" \
                  "${SCRIPT_DIR}/test_installation_fixes.sh" \
                  "Installation Fixes Main Test Suite"

    run_test_suite "edge_cases" \
                  "${SCRIPT_DIR}/test_installation_fixes_edge_cases.sh" \
                  "Installation Fixes Edge Cases Tests"

    # Generate final report
    if generate_final_report; then
        exit 0
    else
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    "-h"|"--help")
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Run all installation fixes tests and generate a comprehensive report."
        echo ""
        echo "Options:"
        echo "  -h, --help    Show this help message"
        echo "  -i, --info    Show test information only"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_TIMEOUT      Timeout for individual tests (default: 300s)"
        echo "  VERBOSE_OUTPUT    Enable verbose output (default: false)"
        echo ""
        exit 0
        ;;
    "-i"|"--info")
        show_test_info
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use -h or --help for usage information."
        exit 1
        ;;
esac
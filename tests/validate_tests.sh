#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Test Validation Script
# Version: 1.0.0
# Description: Quick validation that all test scripts are properly configured
# Author: VLESS Testing Team

readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_ROOT")"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}VLESS Test Framework Validation${NC}"
echo "=================================="
echo

# Check if vless-manager.sh exists
echo -n "Checking main script... "
if [[ -f "$PROJECT_ROOT/vless-manager.sh" ]]; then
    echo -e "${GREEN}✓ Found${NC}"
else
    echo -e "${RED}✗ Missing: $PROJECT_ROOT/vless-manager.sh${NC}"
    exit 1
fi

# Check test scripts
echo -n "Checking test scripts... "
expected_tests=(
    "test_requirements.sh"
    "test_installation.sh"
    "test_structure.sh"
    "test_vless_manager.sh"
    "run_all_tests.sh"
)

missing_tests=()
for test_file in "${expected_tests[@]}"; do
    if [[ ! -f "$TEST_ROOT/$test_file" ]]; then
        missing_tests+=("$test_file")
    fi
done

if [[ ${#missing_tests[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All present${NC}"
else
    echo -e "${RED}✗ Missing: ${missing_tests[*]}${NC}"
    exit 1
fi

# Check executability
echo -n "Checking script permissions... "
non_executable=()
for test_file in "${expected_tests[@]}"; do
    if [[ ! -x "$TEST_ROOT/$test_file" ]]; then
        non_executable+=("$test_file")
    fi
done

if [[ ${#non_executable[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All executable${NC}"
else
    echo -e "${YELLOW}⚠ Non-executable: ${non_executable[*]}${NC}"
    echo "  Fix with: chmod +x ${non_executable[*]}"
fi

# Check syntax
echo -n "Checking script syntax... "
syntax_errors=()
for test_file in "${expected_tests[@]}"; do
    if ! bash -n "$TEST_ROOT/$test_file" 2>/dev/null; then
        syntax_errors+=("$test_file")
    fi
done

if [[ ${#syntax_errors[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All valid${NC}"
else
    echo -e "${RED}✗ Syntax errors: ${syntax_errors[*]}${NC}"
    exit 1
fi

# Quick help test
echo -n "Testing help commands... "
help_failures=()
for test_file in "run_all_tests.sh" "test_requirements.sh" "test_installation.sh" "test_structure.sh" "test_vless_manager.sh"; do
    if ! "$TEST_ROOT/$test_file" help >/dev/null 2>&1; then
        help_failures+=("$test_file")
    fi
done

if [[ ${#help_failures[@]} -eq 0 ]]; then
    echo -e "${GREEN}✓ All working${NC}"
else
    echo -e "${YELLOW}⚠ Help issues: ${help_failures[*]}${NC}"
fi

# Test suite detection
echo -n "Testing suite detection... "
if "$TEST_ROOT/run_all_tests.sh" list >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
    exit 1
fi

echo
echo -e "${GREEN}✓ Test Framework Validation Complete!${NC}"
echo
echo "Quick Start:"
echo "  ./run_all_tests.sh run              # Run all tests"
echo "  ./run_all_tests.sh run-suite main   # Run specific suite"
echo "  ./run_all_tests.sh list             # List available suites"
echo
echo "For detailed information, see README_TESTS.md"
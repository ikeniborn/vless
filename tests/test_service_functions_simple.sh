#!/bin/bash

# Simple test for service functions

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0

# Test environment
export SOURCING_MODE=true
export TEST_MODE=true
export PROJECT_PATH="/tmp/vless_test_$$"
mkdir -p "$PROJECT_PATH"

# Disable error trap for testing
trap - ERR

# Source the main script
source ./vless-manager.sh 2>/dev/null

# Re-disable error trap after sourcing
trap - ERR

echo "Testing Service Functions"
echo "========================="

# Test 1: show_help function
echo -n "Test 1: show_help function exists... "
if type -t show_help > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Test 2: show_help output
echo -n "Test 2: show_help displays correct output... "
# Call function directly, not in subshell
show_help > /tmp/help_output_$$.txt 2>&1
output=$(cat /tmp/help_output_$$.txt)
rm -f /tmp/help_output_$$.txt
if echo "$output" | grep -q "VLESS+Reality VPN Service Manager" && \
   echo "$output" | grep -q "System Commands:" && \
   echo "$output" | grep -q "help.*Show this help message"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Test 3: backup_service function exists
echo -n "Test 3: backup_service function exists... "
if type -t backup_service > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Test 4: backup with no installation
echo -n "Test 4: backup_service detects no installation... "
rm -f "$PROJECT_PATH/.env" 2>/dev/null
backup_service > /tmp/backup_output_$$.txt 2>&1
output=$(cat /tmp/backup_output_$$.txt)
rm -f /tmp/backup_output_$$.txt
if echo "$output" | grep -q "Service not installed"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Test 5: uninstall_service function exists
echo -n "Test 5: uninstall_service function exists... "
if type -t uninstall_service > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Test 6: help command in main
echo -n "Test 6: main function handles help command... "
main help > /tmp/main_output_$$.txt 2>&1
output=$(cat /tmp/main_output_$$.txt)
rm -f /tmp/main_output_$$.txt
if echo "$output" | grep -q "VLESS+Reality VPN Service Manager"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi

# Clean up
rm -rf "$PROJECT_PATH"

# Summary
echo
echo "========================="
echo "Results:"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "========================="

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
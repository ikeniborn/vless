#!/bin/bash
# Test script for common_utils.sh color variables fix
# Tests that all color variables are properly defined and functions work correctly

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "Testing $test_name... "

    if eval "$test_command" >/dev/null 2>&1; then
        echo "✓ PASSED"
        ((TESTS_PASSED++))
    else
        echo "✗ FAILED"
        ((TESTS_FAILED++))
    fi
}

echo "======================================"
echo "Common Utils Color Variables Test"
echo "======================================"
echo

# Test 1: Source the common_utils.sh file
echo "Test 1: Loading common_utils.sh module"
if source "$PROJECT_DIR/modules/common_utils.sh" 2>/dev/null; then
    echo "✓ Module loaded successfully"
    ((TESTS_PASSED++))
else
    echo "✗ Failed to load module"
    ((TESTS_FAILED++))
    exit 1
fi
echo

# Test 2: Check if all color variables are defined
echo "Test 2: Checking color variables definition"
MISSING_VARS=0
for var in RED GREEN YELLOW BLUE CYAN PURPLE WHITE BOLD NC; do
    if [[ -z "${!var:-}" ]]; then
        echo "  ✗ $var is not defined"
        MISSING_VARS=1
    else
        echo "  ✓ $var is defined"
    fi
done

if [[ $MISSING_VARS -eq 0 ]]; then
    echo "✓ All color variables are defined"
    ((TESTS_PASSED++))
else
    echo "✗ Some color variables are missing"
    ((TESTS_FAILED++))
fi
echo

# Test 3: Test print_header function
echo "Test 3: Testing print_header function"
run_test "print_header" "print_header 'Test Header'"
echo

# Test 4: Test print_info function
echo "Test 4: Testing print functions"
run_test "print_info" "print_info 'Test info message'"
run_test "print_success" "print_success 'Test success message'"
run_test "print_warning" "print_warning 'Test warning message'"
run_test "print_error" "print_error 'Test error message'"
run_test "print_step" "print_step '1' 'Test step'"
echo

# Test 5: Test with unset color variables (simulate the original problem)
echo "Test 5: Testing with unset color variables"
(
    # Create a subshell and unset WHITE
    unset WHITE
    # The function should still work with the fallback
    if print_header "Test with unset WHITE" >/dev/null 2>&1; then
        echo "✓ print_header works with unset WHITE (uses fallback)"
        ((TESTS_PASSED++))
    else
        echo "✗ print_header fails with unset WHITE"
        ((TESTS_FAILED++))
    fi
)
echo

# Test 6: Test show_progress function
echo "Test 6: Testing show_progress function"
run_test "show_progress" "show_progress 5 10 'Testing'"
echo

# Test 7: Test check_color_variables function
echo "Test 7: Testing check_color_variables function"
if check_color_variables; then
    echo "✓ check_color_variables passed"
    ((TESTS_PASSED++))
else
    echo "✗ check_color_variables failed"
    ((TESTS_FAILED++))
fi
echo

# Test 8: Test individual color variable checks work
echo "Test 8: Testing individual color variable checks"
TEST_SCRIPT=$(cat << 'EOF'
# Unset all color variables
unset RED GREEN YELLOW BLUE CYAN PURPLE WHITE BOLD NC

# Source the script again - should redefine all variables
source modules/common_utils.sh

# Check if all variables are now defined
check_color_variables
EOF
)

if bash -c "$TEST_SCRIPT" 2>/dev/null; then
    echo "✓ Individual color checks work correctly"
    ((TESTS_PASSED++))
else
    echo "✗ Individual color checks failed"
    ((TESTS_FAILED++))
fi
echo

# Summary
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed successfully!"
    exit 0
else
    echo "✗ Some tests failed. Please review the output above."
    exit 1
fi
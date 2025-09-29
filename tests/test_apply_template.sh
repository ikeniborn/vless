#!/bin/bash
# Test script for apply_template function
# Tests the sed fix for complex character escaping

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_ROOT/scripts/lib/colors.sh"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/config.sh"

# Test results counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local expected_result="$2"
    shift 2

    echo -n "Testing $test_name... "

    # Run the test
    if eval "$@" > /dev/null 2>&1; then
        if [ -n "$expected_result" ] && [ "$expected_result" = "fail" ]; then
            echo "❌ FAILED (expected to fail but passed)"
            ((TESTS_FAILED++))
        else
            echo "✓ PASSED"
            ((TESTS_PASSED++))
        fi
    else
        if [ -n "$expected_result" ] && [ "$expected_result" = "fail" ]; then
            echo "✓ PASSED (correctly failed)"
            ((TESTS_PASSED++))
        else
            echo "❌ FAILED"
            ((TESTS_FAILED++))
        fi
    fi
}

# Create test template
TEST_TEMPLATE="/tmp/test_template.txt"
cat > "$TEST_TEMPLATE" << 'EOF'
Domain: {{DOMAIN}}
Path: {{PATH}}
UUID: {{UUID}}
Key: {{KEY}}
EOF

# Test 1: Normal values
run_test "normal values" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test1.txt" "DOMAIN=example.com" "PATH=/api" "UUID=123-456" "KEY=abc123"'

# Test 2: Values with forward slashes
run_test "forward slashes" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test2.txt" "DOMAIN=example.com/sub" "PATH=/api/v1/test" "UUID=123/456" "KEY=abc/123"'

# Test 3: Values with backslashes
run_test "backslashes" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test3.txt" "DOMAIN=example\\\\com" "PATH=\\\\api" "UUID=123\\\\456" "KEY=abc\\\\123"'

# Test 4: Values with ampersands
run_test "ampersands" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test4.txt" "DOMAIN=example.com&param=1" "PATH=/api&test" "UUID=123&456" "KEY=abc&123"'

# Test 5: Mixed special characters
run_test "mixed special chars" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test5.txt" "DOMAIN=example.com/path&param=1" "PATH=/api\\\\test&value" "UUID=123\\\\456/789" "KEY=abc&123/xyz"'

# Test 6: Empty values
run_test "empty values" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test6.txt" "DOMAIN=" "PATH=" "UUID=" "KEY="'

# Test 7: Values with spaces
run_test "values with spaces" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test7.txt" "DOMAIN=example domain" "PATH=/api path" "UUID=123 456" "KEY=abc 123"'

# Test 8: Real-world REALITY config values
run_test "REALITY config values" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test8.txt" "DOMAIN=speed.cloudflare.com:443" "PATH=cloudflare.com" "UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890" "KEY=WFc5ymBhfGnW4kO6xZNpIjLwqnGIqHLUVRLYcEJVBAI"'

# Verify test 8 output contains expected values
if grep -q "speed.cloudflare.com:443" "/tmp/test8.txt" 2>/dev/null; then
    echo "  └─ Verification: REALITY_DEST substitution ✓"
    ((TESTS_PASSED++))
else
    echo "  └─ Verification: REALITY_DEST substitution ❌"
    ((TESTS_FAILED++))
fi

# Test 9: Values with pipe characters
run_test "pipe characters" "pass" \
    'apply_template "$TEST_TEMPLATE" "/tmp/test9.txt" "DOMAIN=example.com|port:443" "PATH=/api|v1" "UUID=123|456|789" "KEY=key|with|pipes"'

# Verify test 9 output contains pipe characters
if grep -q "example.com|port:443" "/tmp/test9.txt" 2>/dev/null; then
    echo "  └─ Verification: Pipe character handling ✓"
    ((TESTS_PASSED++))
else
    echo "  └─ Verification: Pipe character handling ❌"
    ((TESTS_FAILED++))
fi

# Clean up test files
rm -f /tmp/test*.txt "$TEST_TEMPLATE"

# Summary
echo ""
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
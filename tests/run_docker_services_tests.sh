#!/bin/bash

# VLESS Docker Services Fix - Test Runner
# This script runs the Docker services fix tests in isolation

set -euo pipefail

cd "$(dirname "$0")/.."

echo "Starting Docker Services Fix Test Suite..."
echo "=========================================="

# Run the test script in a subshell to avoid variable conflicts
if (
    # Set test-specific environment
    export TEST_MODE=true

    # Source and run tests
    bash ./tests/test_docker_services_fix.sh
); then
    echo
    echo "✓ All tests completed successfully!"
    exit 0
else
    echo
    echo "✗ Some tests failed. Check the results above."
    exit 1
fi
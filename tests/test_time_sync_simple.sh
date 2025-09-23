#!/bin/bash

# Simple Time Sync Function Tests
set -euo pipefail

echo "========================================="
echo "Testing Time Synchronization Functions"
echo "========================================="

# Set up environment
export TIME_SYNC_ENABLED="true"
export TIME_TOLERANCE_SECONDS="300"
export LOG_FILE="/tmp/test_time_sync.log"

# Source the module
echo "Sourcing common_utils.sh..."
if source "../modules/common_utils.sh" 2>/dev/null; then
    echo "✓ Module sourced successfully"
else
    echo "✗ Failed to source module"
    exit 1
fi

echo ""
echo "Testing function definitions..."

# Test function existence
if declare -f check_system_time_validity >/dev/null 2>&1; then
    echo "✓ check_system_time_validity function exists"
else
    echo "✗ check_system_time_validity function missing"
fi

if declare -f sync_system_time >/dev/null 2>&1; then
    echo "✓ sync_system_time function exists"
else
    echo "✗ sync_system_time function missing"
fi

if declare -f detect_time_related_apt_errors >/dev/null 2>&1; then
    echo "✓ detect_time_related_apt_errors function exists"
else
    echo "✗ detect_time_related_apt_errors function missing"
fi

if declare -f safe_apt_update >/dev/null 2>&1; then
    echo "✓ safe_apt_update function exists"
else
    echo "✗ safe_apt_update function missing"
fi

echo ""
echo "Testing configuration variables..."

if [[ -n "${TIME_SYNC_ENABLED:-}" ]]; then
    echo "✓ TIME_SYNC_ENABLED is set: $TIME_SYNC_ENABLED"
else
    echo "✗ TIME_SYNC_ENABLED not set"
fi

if [[ -n "${TIME_TOLERANCE_SECONDS:-}" ]]; then
    echo "✓ TIME_TOLERANCE_SECONDS is set: $TIME_TOLERANCE_SECONDS"
else
    echo "✗ TIME_TOLERANCE_SECONDS not set"
fi

if [[ ${#NTP_SERVERS[@]} -gt 0 ]]; then
    echo "✓ NTP_SERVERS array has ${#NTP_SERVERS[@]} servers"
else
    echo "✗ NTP_SERVERS array is empty"
fi

echo ""
echo "Testing error pattern detection..."

# Test time-related error patterns
time_error="Release file is not valid yet (invalid for another 2h 31m 45s)"
if detect_time_related_apt_errors "$time_error"; then
    echo "✓ Detects 'not valid yet' error pattern"
else
    echo "✗ Failed to detect 'not valid yet' error pattern"
fi

ssl_error="SSL certificate problem: certificate is not yet valid"
if detect_time_related_apt_errors "$ssl_error"; then
    echo "✓ Detects SSL certificate error pattern"
else
    echo "✗ Failed to detect SSL certificate error pattern"
fi

# Test non-time-related errors are not detected
network_error="Temporary failure resolving 'archive.ubuntu.com'"
if detect_time_related_apt_errors "$network_error"; then
    echo "✗ Incorrectly detected network error as time-related"
else
    echo "✓ Correctly ignores network errors"
fi

echo ""
echo "Testing install_package_if_missing integration..."

# Test that install_package_if_missing uses safe_apt_update
if declare -f install_package_if_missing >/dev/null 2>&1; then
    function_content=$(declare -f install_package_if_missing)
    if echo "$function_content" | grep -q "safe_apt_update"; then
        echo "✓ install_package_if_missing uses safe_apt_update"
    else
        echo "✗ install_package_if_missing does not use safe_apt_update"
    fi
else
    echo "✗ install_package_if_missing function not found"
fi

echo ""
echo "========================================="
echo "Time sync function tests completed"
echo "========================================="
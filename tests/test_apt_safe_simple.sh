#!/bin/bash

# Simple APT Safe Update Tests
set -euo pipefail

echo "========================================="
echo "Testing APT Safe Update Functions"
echo "========================================="

# Set up environment
export TIME_SYNC_ENABLED="true"
export TIME_TOLERANCE_SECONDS="300"
export LOG_FILE="/tmp/test_apt_safe.log"

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
if declare -f safe_apt_update >/dev/null 2>&1; then
    echo "✓ safe_apt_update function exists"
else
    echo "✗ safe_apt_update function missing"
fi

if declare -f detect_time_related_apt_errors >/dev/null 2>&1; then
    echo "✓ detect_time_related_apt_errors function exists"
else
    echo "✗ detect_time_related_apt_errors function missing"
fi

echo ""
echo "Testing APT error pattern detection..."

# Test various time-related error patterns
test_patterns=(
    "not valid yet"
    "invalid for another"
    "certificate is not yet valid"
    "certificate will be valid from"
    "Release file.*is not yet valid"
    "Release file.*will be valid from"
    "The following signatures were invalid"
    "Certificate verification failed"
    "SSL certificate problem"
    "server certificate verification failed"
)

for pattern in "${test_patterns[@]}"; do
    test_error="Error: This is a test with pattern: $pattern"
    if detect_time_related_apt_errors "$test_error"; then
        echo "✓ Detects pattern: $pattern"
    else
        echo "✗ Failed to detect pattern: $pattern"
    fi
done

echo ""
echo "Testing non-time-related error rejection..."

# Test that non-time-related errors are correctly ignored
non_time_patterns=(
    "Temporary failure resolving"
    "No space left on device"
    "Permission denied"
    "Connection refused"
    "Unable to acquire lock"
)

for pattern in "${non_time_patterns[@]}"; do
    test_error="Error: This is a test with pattern: $pattern"
    if detect_time_related_apt_errors "$test_error"; then
        echo "✗ Incorrectly detected non-time error: $pattern"
    else
        echo "✓ Correctly ignored non-time error: $pattern"
    fi
done

echo ""
echo "Testing real APT error examples..."

# Real-world time-related errors
real_time_errors=(
    "W: Release file for http://archive.ubuntu.com/ubuntu/dists/focal/InRelease is not valid yet (invalid for another 2h 31m 45s)"
    "W: Failed to fetch https://example.com/dists/focal/InRelease  SSL certificate problem: certificate is not yet valid"
    "E: The repository 'http://archive.ubuntu.com/ubuntu focal InRelease' is not signed."
    "W: GPG error: The following signatures were invalid: EXPKEYSIG 3B4FE6ACC0B21F32"
)

for error in "${real_time_errors[@]}"; do
    if detect_time_related_apt_errors "$error"; then
        echo "✓ Detects real-world time error"
    else
        echo "✗ Failed to detect real-world time error"
    fi
done

# Real-world non-time-related errors
real_non_time_errors=(
    "W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/focal/InRelease  Temporary failure resolving 'archive.ubuntu.com'"
    "E: Write error - write (28: No space left on device)"
    "E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)"
)

for error in "${real_non_time_errors[@]}"; do
    if detect_time_related_apt_errors "$error"; then
        echo "✗ Incorrectly detected real-world non-time error as time-related"
    else
        echo "✓ Correctly ignored real-world non-time error"
    fi
done

echo ""
echo "Testing module integration..."

# Check that other modules use safe_apt_update through install_package_if_missing
modules_dir="../modules"
modules_using_install_package=0
modules_checked=0

if [[ -d "$modules_dir" ]]; then
    for module_file in "$modules_dir"/*.sh; do
        [[ -f "$module_file" ]] || continue
        module_name=$(basename "$module_file")

        # Skip common_utils.sh as it defines the functions
        [[ "$module_name" == "common_utils.sh" ]] && continue

        ((modules_checked++))

        if grep -q "install_package_if_missing" "$module_file"; then
            ((modules_using_install_package++))
            echo "✓ $module_name uses install_package_if_missing"
        fi

        # Check for direct apt-get update usage (should be avoided)
        if grep -q "apt-get[[:space:]]\+update" "$module_file" && \
           ! grep -q "safe_apt_update" "$module_file"; then
            echo "⚠ $module_name might use direct apt-get update"
        fi
    done

    echo "✓ Checked $modules_checked modules, $modules_using_install_package use install_package_if_missing"
else
    echo "⚠ Modules directory not found"
fi

echo ""
echo "Testing function signatures..."

# Test that safe_apt_update has the expected signature
safe_apt_update_content=$(declare -f safe_apt_update)
if echo "$safe_apt_update_content" | grep -q "max_retries"; then
    echo "✓ safe_apt_update accepts retry parameter"
else
    echo "✗ safe_apt_update missing retry parameter"
fi

if echo "$safe_apt_update_content" | grep -q "detect_time_related_apt_errors"; then
    echo "✓ safe_apt_update calls detect_time_related_apt_errors"
else
    echo "✗ safe_apt_update doesn't call detect_time_related_apt_errors"
fi

if echo "$safe_apt_update_content" | grep -q "sync_system_time"; then
    echo "✓ safe_apt_update calls sync_system_time"
else
    echo "✗ safe_apt_update doesn't call sync_system_time"
fi

echo ""
echo "========================================="
echo "APT safe update tests completed"
echo "========================================="
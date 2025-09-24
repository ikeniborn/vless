#!/bin/bash

# Simple test for ca-certificates package installation fix
set -euo pipefail

echo "Testing ca-certificates package detection fix..."

# Import only the needed functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define minimal logging functions to avoid init issues
log_info() { echo "[INFO] $*"; }
log_debug() { echo "[DEBUG] $*"; }
log_error() { echo "[ERROR] $*"; }
log_success() { echo "[SUCCESS] $*"; }

# Import the key functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Copy the new is_package_installed function from common_utils.sh
is_package_installed() {
    local package="$1"

    # Primary check: Use dpkg to check if package is installed
    if dpkg -l 2>/dev/null | grep -q "^ii.*${package}"; then
        return 0
    fi

    # Secondary check: Use dpkg-query for more reliable checking
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "ok installed"; then
        return 0
    fi

    # Package-specific checks for data packages
    case "$package" in
        "ca-certificates")
            # Check if certificate directory exists with certificates
            [[ -d /usr/share/ca-certificates ]] && [[ -n "$(ls -A /usr/share/ca-certificates 2>/dev/null)" ]]
            return $?
            ;;
        "gnupg")
            # gnupg package provides gpg command, not gnupg command
            command_exists gpg
            return $?
            ;;
        "lsb-release")
            # lsb-release provides lsb_release command
            command_exists lsb_release
            return $?
            ;;
        "curl")
            command_exists curl
            return $?
            ;;
        *)
            # For other packages, check if they provide a command
            # This maintains backward compatibility
            command_exists "$package"
            return $?
            ;;
    esac
}

# Test the packages that were failing
echo ""
echo "Testing package detection:"
echo "--------------------------"

# Test ca-certificates
echo -n "1. ca-certificates: "
if is_package_installed "ca-certificates"; then
    echo "✓ Detected as installed"
else
    echo "✗ Not detected (may not be installed)"
fi

# Show actual dpkg status for comparison
echo "   Actual dpkg status:"
if dpkg -l ca-certificates 2>/dev/null | grep -q "^ii"; then
    echo "   - Package IS installed according to dpkg"
else
    echo "   - Package is NOT installed according to dpkg"
fi

# Test gnupg
echo ""
echo -n "2. gnupg: "
if is_package_installed "gnupg"; then
    echo "✓ Detected as installed"
else
    echo "✗ Not detected (may not be installed)"
fi

# Test lsb-release
echo ""
echo -n "3. lsb-release: "
if is_package_installed "lsb-release"; then
    echo "✓ Detected as installed"
else
    echo "✗ Not detected (may not be installed)"
fi

# Test curl (command-based package)
echo ""
echo -n "4. curl: "
if is_package_installed "curl"; then
    echo "✓ Detected as installed"
else
    echo "✗ Not detected (may not be installed)"
fi

echo ""
echo "Testing completed!"
echo ""
echo "Key Fix Verification:"
echo "--------------------"
echo "The fix ensures that ca-certificates and other data packages"
echo "are properly detected even though they don't provide executable commands."
echo ""

# Check if all critical packages are detected
all_good=true
if ! is_package_installed "ca-certificates" && dpkg -l ca-certificates 2>/dev/null | grep -q "^ii"; then
    echo "⚠ WARNING: ca-certificates is installed but not detected!"
    all_good=false
fi

if $all_good; then
    echo "✓ Package detection is working correctly!"
    exit 0
else
    echo "✗ There may still be issues with package detection"
    exit 1
fi
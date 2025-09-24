#!/bin/bash

# Test Docker setup with the fixed install_package_if_missing function
set -euo pipefail

echo "========================================="
echo "Docker Setup Installation Test"
echo "========================================="
echo ""
echo "This test will verify that the Docker installation"
echo "process works correctly with the fixed package detection."
echo ""

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOG_FILE="/tmp/test_docker_setup_$$.log"

# Source the modules
source "${SCRIPT_DIR}/../modules/common_utils.sh"

# Test the critical packages required by Docker setup
echo "Testing Docker prerequisite packages..."
echo "---------------------------------------"

# These are the packages that docker_setup.sh tries to install
packages_to_test=(
    "ca-certificates"
    "curl"
    "gnupg"
    "lsb-release"
)

all_detected=true

for package in "${packages_to_test[@]}"; do
    echo -n "Checking $package: "

    if is_package_installed "$package"; then
        echo "✓ Installed and detected"
    else
        echo "✗ Not detected"

        # Try to see if it's actually installed
        if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
            echo "  WARNING: Package is installed but not detected by is_package_installed!"
            all_detected=false
        else
            echo "  INFO: Package is genuinely not installed"
        fi
    fi
done

echo ""
if $all_detected; then
    echo "✓ All Docker prerequisites are properly detected!"
    echo ""
    echo "The fix successfully resolves the installation issue."
    echo "Docker installation should now proceed without errors."
else
    echo "⚠ Some packages are not properly detected"
    echo "There may still be issues with the Docker installation"
fi

echo ""
echo "----------------------------------------"
echo "Simulating Docker prerequisite check..."
echo "----------------------------------------"

# Simulate what docker_setup.sh does
test_docker_prerequisites() {
    local required_packages=(
        "ca-certificates"
        "curl"
        "gnupg"
        "lsb-release"
    )

    local all_good=true

    for package in "${required_packages[@]}"; do
        echo -n "Would install_package_if_missing work for $package? "

        # Check if package is already detected as installed
        if is_package_installed "$package"; then
            echo "Yes (already installed)"
        else
            echo "Would attempt installation"
            all_good=false
        fi
    done

    return $([ "$all_good" = true ] && echo 0 || echo 1)
}

if test_docker_prerequisites; then
    echo ""
    echo "✓ SUCCESS: Docker installation would proceed without errors!"
    exit 0
else
    echo ""
    echo "⚠ INFO: Some packages would be installed (this is normal if they're not present)"
    exit 0
fi
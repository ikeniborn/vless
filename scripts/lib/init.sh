#!/bin/bash

# Library initialization script with robust path detection

# Function to find the real script directory
find_script_dir() {
    local SOURCE="${BASH_SOURCE[0]}"
    local DIR=""

    # Try readlink first (most reliable)
    if command -v readlink >/dev/null 2>&1; then
        SOURCE="$(readlink -f "$SOURCE" 2>/dev/null)" || SOURCE="${BASH_SOURCE[0]}"
    fi

    # Get directory of the script
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

    # Check if we're in the right place
    if [ -f "$DIR/colors.sh" ]; then
        echo "$DIR"
        return 0
    fi

    # If not found, try common locations
    for CHECK_DIR in \
        "/opt/vless/scripts/lib" \
        "$VLESS_HOME/scripts/lib" \
        "$(dirname "$(dirname "$SOURCE")")/lib" \
        "$SCRIPT_DIR/lib"
    do
        if [ -f "$CHECK_DIR/colors.sh" ]; then
            echo "$CHECK_DIR"
            return 0
        fi
    done

    # Failed to find
    return 1
}

# Find the library directory
LIB_DIR=$(find_script_dir)

if [ -z "$LIB_DIR" ]; then
    echo "Error: Cannot locate VLESS library files" >&2
    echo "Please ensure VLESS is properly installed" >&2
    exit 1
fi

# Load all required libraries
for lib in colors.sh utils.sh config.sh; do
    if [ -f "$LIB_DIR/$lib" ]; then
        source "$LIB_DIR/$lib"
    else
        echo "Error: Required library $lib not found in $LIB_DIR" >&2
        exit 1
    fi
done

# Export for use in scripts
export VLESS_LIB_DIR="$LIB_DIR"
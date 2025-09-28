#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Check root
check_root

print_header "VLESS Symlink Repair Tool"

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    print_error "VLESS is not installed at $VLESS_HOME"
    print_info "Please run install.sh first"
    exit 1
fi

# Check if scripts exist in VLESS_HOME
if [ ! -d "$VLESS_HOME/scripts" ]; then
    print_error "Scripts directory not found at $VLESS_HOME/scripts"
    print_info "Installation may be corrupted"
    exit 1
fi

print_step "Checking and repairing VLESS command symlinks..."

# Define commands and their script files
declare -A COMMANDS=(
    ["vless-users"]="user-manager.sh"
    ["vless-logs"]="logs.sh"
    ["vless-backup"]="backup.sh"
    ["vless-update"]="update.sh"
)

# Track repair status
REPAIRS_MADE=0
ALL_OK=true

# Check and repair each symlink
for CMD in "${!COMMANDS[@]}"; do
    SCRIPT="${COMMANDS[$CMD]}"
    SYMLINK="/usr/local/bin/$CMD"
    TARGET="$VLESS_HOME/scripts/$SCRIPT"

    # Check if target script exists
    if [ ! -f "$TARGET" ]; then
        print_error "Script not found: $TARGET"
        ALL_OK=false
        continue
    fi

    # Check if symlink exists and is correct
    if [ -L "$SYMLINK" ]; then
        # Symlink exists, check if it points to the correct target
        CURRENT_TARGET=$(readlink -f "$SYMLINK" 2>/dev/null || echo "")
        if [ "$CURRENT_TARGET" = "$TARGET" ]; then
            print_success "$CMD symlink is correct"
        else
            print_warning "$CMD symlink points to wrong target"
            print_step "Fixing $CMD symlink..."
            rm -f "$SYMLINK"
            ln -sf "$TARGET" "$SYMLINK"
            print_success "$CMD symlink repaired"
            ((REPAIRS_MADE++))
        fi
    elif [ -f "$SYMLINK" ]; then
        # Regular file exists instead of symlink
        print_warning "$CMD exists as regular file, not symlink"
        print_step "Converting to symlink..."
        rm -f "$SYMLINK"
        ln -sf "$TARGET" "$SYMLINK"
        print_success "$CMD converted to symlink"
        ((REPAIRS_MADE++))
    else
        # Symlink doesn't exist
        print_warning "$CMD symlink missing"
        print_step "Creating $CMD symlink..."
        ln -sf "$TARGET" "$SYMLINK"
        print_success "$CMD symlink created"
        ((REPAIRS_MADE++))
    fi
done

echo

# Summary
if [ $REPAIRS_MADE -eq 0 ]; then
    print_success "All symlinks are correct. No repairs needed."
else
    print_success "Repaired $REPAIRS_MADE symlink(s)"
fi

if [ "$ALL_OK" = false ]; then
    print_warning "Some scripts were missing. Please check your installation."
    exit 1
fi

# Test commands
print_header "Testing Commands"

for CMD in "${!COMMANDS[@]}"; do
    if command -v "$CMD" >/dev/null 2>&1; then
        print_success "$CMD is available"
    else
        print_error "$CMD is not available in PATH"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = true ]; then
    echo
    print_success "All VLESS commands are ready to use!"
    print_info "Available commands:"
    for CMD in "${!COMMANDS[@]}"; do
        echo "  - $CMD"
    done | sort
else
    echo
    print_error "Some commands are not available. Please check your PATH."
    exit 1
fi
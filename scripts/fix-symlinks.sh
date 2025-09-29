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

# Check PATH configuration
print_step "Checking PATH configuration for root user..."
ROOT_PATH=$(sudo -i sh -c 'echo $PATH')
print_info "Root user PATH: $ROOT_PATH"

if ! echo "$ROOT_PATH" | grep -q "/usr/local/bin"; then
    print_warning "/usr/local/bin is not in root's PATH"
    print_step "Adding /usr/local/bin to root's PATH..."

    # Add to root's .bashrc
    if [ -f "/root/.bashrc" ]; then
        if ! grep -q "PATH=.*\/usr\/local\/bin" "/root/.bashrc"; then
            echo 'export PATH="$PATH:/usr/local/bin"' >> "/root/.bashrc"
            print_success "Added /usr/local/bin to /root/.bashrc"
        fi
    fi

    # Add to /etc/profile for system-wide effect
    if [ -f "/etc/profile" ]; then
        if ! grep -q "PATH=.*\/usr\/local\/bin" "/etc/profile"; then
            echo 'export PATH="$PATH:/usr/local/bin"' >> "/etc/profile"
            print_success "Added /usr/local/bin to /etc/profile"
        fi
    fi
else
    print_success "/usr/local/bin is already in root's PATH"
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
WRAPPERS_CREATED=0
ALL_OK=true

# Ensure directories exist
if [ ! -d "/usr/local/bin" ]; then
    print_info "Creating /usr/local/bin directory..."
    mkdir -p "/usr/local/bin"
    chmod 755 "/usr/local/bin"
fi

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

    # Make sure target is executable
    if [ ! -x "$TARGET" ]; then
        chmod +x "$TARGET"
        print_info "Made $TARGET executable"
    fi

    # Use robust symlink creation
    print_step "Processing $CMD..."

    # Try to create/repair symlink
    if create_robust_symlink "$TARGET" "$SYMLINK"; then
        # Validate the symlink
        validation_result=$(validate_symlink "$SYMLINK" "$TARGET" 2>&1 || echo $?)

        if [ -z "$validation_result" ] || [ "$validation_result" = "0" ]; then
            print_success "$CMD symlink is correct"
        else
            print_warning "$CMD symlink created but validation returned: $validation_result"
            ((REPAIRS_MADE++))
        fi
    else
        print_error "Failed to create symlink for $CMD"
        ALL_OK=false
    fi

    # Create fallback wrapper in /usr/bin
    WRAPPER="/usr/bin/$CMD"
    print_step "Creating fallback wrapper for $CMD..."

    cat > "$WRAPPER" << EOF
#!/bin/bash
# Fallback wrapper for $CMD
exec "$TARGET" "\$@"
EOF

    chmod 755 "$WRAPPER"
    print_info "Created fallback wrapper: $WRAPPER"
    ((WRAPPERS_CREATED++))
done

echo

# Summary
if [ $REPAIRS_MADE -eq 0 ]; then
    print_success "All symlinks are correct. No repairs needed."
else
    print_success "Repaired $REPAIRS_MADE symlink(s)"
fi

if [ $WRAPPERS_CREATED -gt 0 ]; then
    print_success "Created $WRAPPERS_CREATED fallback wrapper(s)"
fi

if [ "$ALL_OK" = false ]; then
    print_warning "Some scripts were missing. Please check your installation."
fi

# Test commands availability
print_header "Testing Commands Availability"

print_step "Testing in current shell..."
for CMD in "${!COMMANDS[@]}"; do
    if command -v "$CMD" >/dev/null 2>&1; then
        print_success "$CMD is available in current shell"
    else
        print_warning "$CMD is not available in current shell PATH"
    fi
done

print_step "Testing for root user (sudo -i)..."
for CMD in "${!COMMANDS[@]}"; do
    if sudo -i which "$CMD" >/dev/null 2>&1; then
        print_success "$CMD is available for root user"
    elif [ -f "/usr/bin/$CMD" ]; then
        print_info "$CMD available via fallback: /usr/bin/$CMD"
    else
        print_error "$CMD is not available for root user"
        ALL_OK=false
    fi
done

print_step "Testing direct execution..."
for CMD in "${!COMMANDS[@]}"; do
    # Test primary symlink
    if [ -x "/usr/local/bin/$CMD" ]; then
        print_success "Primary: /usr/local/bin/$CMD is executable"
    else
        print_warning "Primary: /usr/local/bin/$CMD not executable"
    fi

    # Test fallback wrapper
    if [ -x "/usr/bin/$CMD" ]; then
        print_success "Fallback: /usr/bin/$CMD is executable"
    else
        print_warning "Fallback: /usr/bin/$CMD not executable"
    fi
done

echo

if [ "$ALL_OK" = true ]; then
    print_success "All VLESS commands are ready to use!"
    print_info ""
    print_info "Commands are available in multiple ways:"
    print_info "  1. Direct: sudo vless-users"
    print_info "  2. Root shell: sudo -i → vless-users"
    print_info "  3. Full path: /usr/local/bin/vless-users"
    print_info "  4. Fallback: /usr/bin/vless-users"
    print_info ""
    print_info "Available commands:"
    for CMD in "${!COMMANDS[@]}"; do
        echo "  - $CMD"
    done | sort
else
    print_warning "Some commands may not be available in all contexts"
    print_info ""
    print_info "Troubleshooting steps:"
    print_info "  1. Restart your shell or run: source /etc/profile"
    print_info "  2. For root user: sudo -i → source ~/.bashrc"
    print_info "  3. Use full paths: /usr/local/bin/vless-* or /usr/bin/vless-*"
    print_info "  4. Check permissions: ls -la /opt/vless/scripts/"
fi
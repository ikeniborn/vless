#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VLESS_HOME="/opt/vless"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Check root
check_root

print_header "VLESS Reinstallation Script v1.0"

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    print_error "VLESS is not installed at $VLESS_HOME"
    print_info "Please run install.sh for fresh installation"
    exit 1
fi

# Function to backup current configuration
backup_configuration() {
    print_header "Backing Up Current Configuration"

    local BACKUP_DIR="/tmp/vless-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup important files
    local FILES_TO_BACKUP=(
        "$VLESS_HOME/.env"
        "$VLESS_HOME/config/config.json"
        "$VLESS_HOME/data/users.json"
        "$VLESS_HOME/data/keys/private.key"
        "$VLESS_HOME/data/keys/public.key"
    )

    for file in "${FILES_TO_BACKUP[@]}"; do
        if [ -f "$file" ]; then
            local relative_path="${file#$VLESS_HOME/}"
            local backup_file="$BACKUP_DIR/$relative_path"
            mkdir -p "$(dirname "$backup_file")"
            cp -p "$file" "$backup_file"
            print_success "Backed up: $relative_path"
        else
            print_warning "File not found: $file"
        fi
    done

    # Backup QR codes if they exist
    if [ -d "$VLESS_HOME/data/qr_codes" ]; then
        cp -rp "$VLESS_HOME/data/qr_codes" "$BACKUP_DIR/data/"
        print_success "Backed up QR codes"
    fi

    print_info "Backup saved to: $BACKUP_DIR"
    echo "$BACKUP_DIR"
}

# Function to clean up old installation
cleanup_old_installation() {
    print_header "Cleaning Up Old Installation"

    # Stop Docker container if running
    if [ -f "$VLESS_HOME/docker-compose.yml" ]; then
        print_step "Stopping Xray container..."
        cd "$VLESS_HOME"
        docker-compose down 2>/dev/null || true
        cd - > /dev/null
    fi

    # Remove old symlinks
    print_step "Removing old symlinks..."
    local COMMANDS=("vless-users" "vless-logs" "vless-backup" "vless-update")

    for CMD in "${COMMANDS[@]}"; do
        # Remove from /usr/local/bin
        if [ -L "/usr/local/bin/$CMD" ] || [ -f "/usr/local/bin/$CMD" ]; then
            rm -f "/usr/local/bin/$CMD"
            print_info "Removed: /usr/local/bin/$CMD"
        fi

        # Remove from /usr/bin
        if [ -L "/usr/bin/$CMD" ] || [ -f "/usr/bin/$CMD" ]; then
            rm -f "/usr/bin/$CMD"
            print_info "Removed: /usr/bin/$CMD"
        fi
    done

    # Clean up Docker networks
    local network_name="vless-reality_vless-network"
    if docker network ls | grep -q "$network_name"; then
        docker network rm "$network_name" 2>/dev/null || true
        print_info "Removed Docker network: $network_name"
    fi

    print_success "Old installation cleaned up"
}

# Function to reinstall VLESS
reinstall_vless() {
    print_header "Reinstalling VLESS"

    # Copy new scripts
    print_step "Updating scripts..."
    if [ -d "$REPO_DIR/scripts" ]; then
        cp -r "$REPO_DIR/scripts/"* "$VLESS_HOME/scripts/"
        chmod 750 "$VLESS_HOME/scripts/"*.sh
        chmod 640 "$VLESS_HOME/scripts/lib/"*.sh
        print_success "Scripts updated"
    else
        print_error "Scripts directory not found in repository"
        exit 1
    fi

    # Copy templates
    print_step "Updating templates..."
    if [ -d "$REPO_DIR/templates" ]; then
        cp -r "$REPO_DIR/templates/"* "$VLESS_HOME/templates/"
        print_success "Templates updated"
    else
        print_warning "Templates directory not found"
    fi

    print_success "VLESS files reinstalled"
}

# Function to restore configuration
restore_configuration() {
    local BACKUP_DIR=$1

    print_header "Restoring Configuration"

    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        print_error "Invalid backup directory"
        return 1
    fi

    # Restore important files
    local FILES_TO_RESTORE=(
        ".env"
        "config/config.json"
        "data/users.json"
        "data/keys/private.key"
        "data/keys/public.key"
    )

    for relative_path in "${FILES_TO_RESTORE[@]}"; do
        local backup_file="$BACKUP_DIR/$relative_path"
        local target_file="$VLESS_HOME/$relative_path"

        if [ -f "$backup_file" ]; then
            mkdir -p "$(dirname "$target_file")"
            cp -p "$backup_file" "$target_file"
            print_success "Restored: $relative_path"

            # Set proper permissions
            case "$relative_path" in
                *.key|*.json|.env)
                    chmod 600 "$target_file"
                    ;;
            esac
        else
            print_warning "Backup not found: $relative_path"
        fi
    done

    # Restore QR codes
    if [ -d "$BACKUP_DIR/data/qr_codes" ]; then
        cp -rp "$BACKUP_DIR/data/qr_codes" "$VLESS_HOME/data/"
        print_success "Restored QR codes"
    fi

    print_success "Configuration restored"
}

# Function to recreate symlinks with enhanced validation
recreate_symlinks() {
    print_header "Creating Enhanced Symlinks"

    # Source the updated utils.sh with new functions
    source "$VLESS_HOME/scripts/lib/utils.sh"

    # Check and update PATH for root
    print_step "Configuring PATH for root user..."
    ensure_in_path "/usr/local/bin" "/root/.bashrc"
    ensure_in_path "/usr/local/bin" "/etc/profile"

    # Define commands
    declare -A COMMANDS=(
        ["vless-users"]="user-manager.sh"
        ["vless-logs"]="logs.sh"
        ["vless-backup"]="backup.sh"
        ["vless-update"]="update.sh"
    )

    # Create symlinks in /usr/local/bin
    print_step "Creating primary symlinks in /usr/local/bin..."
    for CMD in "${!COMMANDS[@]}"; do
        local TARGET="$VLESS_HOME/scripts/${COMMANDS[$CMD]}"
        local SYMLINK="/usr/local/bin/$CMD"

        if create_robust_symlink "$TARGET" "$SYMLINK"; then
            print_success "Created symlink: $CMD"
        else
            print_error "Failed to create symlink: $CMD"
        fi
    done

    # Create fallback wrappers in /usr/bin
    print_step "Creating fallback wrappers in /usr/bin..."
    for CMD in "${!COMMANDS[@]}"; do
        local TARGET="$VLESS_HOME/scripts/${COMMANDS[$CMD]}"
        local WRAPPER="/usr/bin/$CMD"

        cat > "$WRAPPER" << EOF
#!/bin/bash
# Fallback wrapper for $CMD
exec "$TARGET" "\$@"
EOF
        chmod 755 "$WRAPPER"
        print_info "Created fallback: $WRAPPER"
    done

    # Test symlinks
    print_step "Testing command availability..."
    local all_ok=true

    for CMD in "${!COMMANDS[@]}"; do
        if test_command_availability "$CMD" true; then
            print_success "$CMD is available for root"
        else
            print_warning "$CMD may not be in PATH"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        print_success "All commands are properly configured"
    else
        print_warning "Some commands may require shell restart to work"
        print_info "Run: source /etc/profile && source ~/.bashrc"
    fi
}

# Function to restart service
restart_service() {
    print_header "Starting Xray Service"

    cd "$VLESS_HOME"

    # Check for Docker
    if ! command_exists docker; then
        print_error "Docker is not installed"
        return 1
    fi

    # Start container
    print_step "Starting Xray container..."
    docker-compose up -d

    # Wait for service
    if wait_for_service "xray-server" 30; then
        print_success "Xray container started"

        # Health check
        if check_xray_health "xray-server"; then
            print_success "Xray service is healthy"
        else
            print_warning "Service started but health check failed"
        fi
    else
        print_error "Failed to start Xray container"
        return 1
    fi
}

# Main reinstallation flow
main() {
    print_info "This will reinstall VLESS while preserving your configuration"

    if ! confirm_action "Do you want to continue?" "y"; then
        print_info "Reinstallation cancelled"
        exit 0
    fi

    # Step 1: Backup current configuration
    BACKUP_DIR=$(backup_configuration)

    # Step 2: Clean up old installation
    cleanup_old_installation

    # Step 3: Reinstall VLESS files
    reinstall_vless

    # Step 4: Restore configuration
    restore_configuration "$BACKUP_DIR"

    # Step 5: Recreate symlinks with enhanced features
    recreate_symlinks

    # Step 6: Fix permissions
    if [ -f "$VLESS_HOME/scripts/fix-permissions.sh" ]; then
        print_step "Fixing permissions..."
        bash "$VLESS_HOME/scripts/fix-permissions.sh"
    fi

    # Step 7: Restart service
    restart_service

    # Final message
    print_header "Reinstallation Complete!"

    print_success "VLESS has been reinstalled successfully"
    print_info ""
    print_info "Configuration has been preserved from backup"
    print_info "All user data and settings remain intact"
    print_info ""
    print_info "Enhanced symlinks created in:"
    print_info "  Primary:  /usr/local/bin/vless-*"
    print_info "  Fallback: /usr/bin/vless-*"
    print_info ""
    print_info "Available commands:"
    print_info "  vless-users   - Manage users"
    print_info "  vless-logs    - View logs"
    print_info "  vless-backup  - Create backup"
    print_info "  vless-update  - Update Xray"
    print_info ""
    print_info "If commands are not immediately available:"
    print_info "  1. Restart your shell"
    print_info "  2. Or run: source /etc/profile"
    print_info ""
    print_info "Backup saved at: $BACKUP_DIR"
}

# Run main function
main "$@"
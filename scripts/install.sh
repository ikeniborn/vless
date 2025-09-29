#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/domains.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Configuration variables
VLESS_HOME="/opt/vless"
SERVER_IP=""
SERVER_PORT="443"
REALITY_DEST=""
REALITY_SERVER_NAME=""
ADMIN_SHORT_ID=""
ADMIN_EMAIL=""
ADMIN_UUID=""
PRIVATE_KEY=""
PUBLIC_KEY=""

# Installation functions
install_dependencies() {
    print_header "Installing Dependencies"
    
    # Update package list
    print_step "Updating package list..."
    apt-get update -qq
    
    # Install required packages
    local packages=("curl" "wget" "jq" "qrencode" "openssl" "ca-certificates" "lsb-release" "gnupg")
    
    for package in "${packages[@]}"; do
        if ! command_exists "$package"; then
            print_step "Installing $package..."
            apt-get install -y -qq "$package"
        else
            print_success "$package is already installed"
        fi
    done
    
    # Install Docker if not present
    if ! command_exists "docker"; then
        print_step "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        print_success "Docker installed successfully"
    else
        print_success "Docker is already installed"
    fi
    
    # Install Docker Compose if not present
    if ! command_exists "docker-compose"; then
        print_step "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        print_success "Docker Compose installed successfully"
    else
        print_success "Docker Compose is already installed"
    fi
}

collect_parameters() {
    print_header "Configuration Setup"
    
    # Step 1: Server IP
    print_step "[1/4] Detecting server IP address..."
    local detected_ip=$(get_external_ip)
    
    if [ -n "$detected_ip" ]; then
        print_info "Detected IP: $detected_ip"
        if confirm_action "Is this correct?" "y"; then
            SERVER_IP="$detected_ip"
            print_success "IP address confirmed"
        else
            while true; do
                read -p "Enter server IP address: " SERVER_IP
                if validate_ip "$SERVER_IP"; then
                    print_success "Valid IP address"
                    break
                else
                    print_error "Invalid IP address format"
                fi
            done
        fi
    else
        print_warning "Could not detect external IP automatically"
        while true; do
            read -p "Enter server IP address: " SERVER_IP
            if validate_ip "$SERVER_IP"; then
                print_success "Valid IP address"
                break
            else
                print_error "Invalid IP address format"
            fi
        done
    fi
    
    # Step 2: Server Port
    print_step "[2/4] Server port configuration"
    read -p "Enter server port [443]: " input_port
    SERVER_PORT="${input_port:-443}"
    
    if validate_port "$SERVER_PORT"; then
        if check_port_available "$SERVER_PORT"; then
            print_success "Port $SERVER_PORT is available"
        else
            print_warning "Port $SERVER_PORT appears to be in use"
            if ! confirm_action "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    else
        print_error "Invalid port number"
        exit 1
    fi

    # Configure firewall for the port
    configure_firewall_for_vless "$SERVER_PORT"
    
    # Step 3: REALITY Domain
    print_step "[3/4] REALITY domain selection"
    REALITY_DEST=$(select_reality_domain)
    REALITY_SERVER_NAME=$(get_domain_name "$REALITY_DEST")
    print_success "Selected domain: $REALITY_DEST"
    
    # Step 4: Admin configuration
    print_step "[4/4] Administrator setup"
    
    print_info "Generating admin UUID..."
    ADMIN_UUID=$(generate_uuid)
    print_success "Admin UUID: $ADMIN_UUID"
    
    print_info "Generating admin Short ID..."
    ADMIN_SHORT_ID=$(generate_short_id)
    print_success "Admin Short ID: $ADMIN_SHORT_ID"
    
    read -p "Enter admin email (optional, press Enter to skip): " ADMIN_EMAIL
    if [ -n "$ADMIN_EMAIL" ]; then
        if validate_email "$ADMIN_EMAIL"; then
            print_success "Valid email format"
        else
            print_warning "Invalid email format, skipping..."
            ADMIN_EMAIL=""
        fi
    fi
}

confirm_configuration() {
    print_header "Configuration Summary"
    
    echo "----------------------------------------"
    echo "Server IP:        $SERVER_IP"
    echo "Server Port:      $SERVER_PORT"
    echo "REALITY Target:   $REALITY_DEST"
    echo "REALITY SNI:      $REALITY_SERVER_NAME"
    echo "Admin UUID:       $ADMIN_UUID"
    echo "Admin Short ID:   $ADMIN_SHORT_ID"
    if [ -n "$ADMIN_EMAIL" ]; then
        echo "Admin Email:      $ADMIN_EMAIL"
    fi
    echo "Installation Dir: $VLESS_HOME"
    echo "----------------------------------------"
    
    if ! confirm_action "Is this configuration correct?" "y"; then
        print_warning "Installation cancelled"
        exit 0
    fi
}

create_directories() {
    print_header "Creating Directory Structure"
    
    local dirs=(
        "$VLESS_HOME"
        "$VLESS_HOME/config"
        "$VLESS_HOME/scripts"
        "$VLESS_HOME/scripts/lib"
        "$VLESS_HOME/data"
        "$VLESS_HOME/data/keys"
        "$VLESS_HOME/data/qr_codes"
        "$VLESS_HOME/backups"
        "$VLESS_HOME/logs"
        "$VLESS_HOME/templates"
    )
    
    for dir in "${dirs[@]}"; do
        if create_directory "$dir"; then
            print_success "Created: $dir"
        else
            print_info "Already exists: $dir"
        fi
    done
    
    # Set specific permissions
    chmod 750 "$VLESS_HOME/config" "$VLESS_HOME/scripts"
    chmod 700 "$VLESS_HOME/data" "$VLESS_HOME/data/keys" "$VLESS_HOME/backups"
    chmod 755 "$VLESS_HOME/logs"
}

copy_files() {
    print_header "Copying Files"
    
    # Copy scripts
    print_step "Copying scripts..."
    cp -r "$REPO_DIR/scripts/"* "$VLESS_HOME/scripts/"
    chmod 750 "$VLESS_HOME/scripts/"*.sh
    chmod 640 "$VLESS_HOME/scripts/lib/"*.sh
    
    # Copy templates
    print_step "Copying templates..."
    cp -r "$REPO_DIR/templates/"* "$VLESS_HOME/templates/"
    
    print_success "Files copied successfully"
}

generate_keys() {
    print_header "Generating X25519 Keys"

    # Pull Docker image first
    print_step "Pulling Xray Docker image..."
    docker pull teddysun/xray:latest

    # Generate keys using Docker
    print_step "Generating X25519 key pair..."

    # Generate both keys in one command
    # xray x25519 outputs: PrivateKey, Password (which is PublicKey), and Hash32
    local key_output=$(docker run --rm teddysun/xray:latest xray x25519)

    # Extract private key (PrivateKey: field)
    PRIVATE_KEY=$(echo "$key_output" | grep "PrivateKey:" | awk '{print $2}')

    if [ -z "$PRIVATE_KEY" ]; then
        print_error "Failed to generate private key"
        print_info "Debug output: $key_output"
        exit 1
    fi

    # Extract public key (Password: field is actually the public key)
    PUBLIC_KEY=$(echo "$key_output" | grep "Password:" | awk '{print $2}')

    if [ -z "$PUBLIC_KEY" ]; then
        print_error "Failed to generate public key"
        print_info "Debug output: $key_output"
        exit 1
    fi

    # Save keys
    echo "$PRIVATE_KEY" > "$VLESS_HOME/data/keys/private.key"
    echo "$PUBLIC_KEY" > "$VLESS_HOME/data/keys/public.key"
    chmod 600 "$VLESS_HOME/data/keys/"*.key

    print_success "Keys generated successfully"
    print_info "Private key saved to: $VLESS_HOME/data/keys/private.key"
    print_info "Public key saved to: $VLESS_HOME/data/keys/public.key"
}

create_configuration() {
    print_header "Creating Configuration"
    
    # Create .env file
    print_step "Creating environment file..."
    cat > "$VLESS_HOME/.env" << EOF
# Server Configuration
SERVER_IP=$SERVER_IP
SERVER_PORT=$SERVER_PORT

# REALITY Configuration
REALITY_DEST=$REALITY_DEST
REALITY_SERVER_NAME=$REALITY_SERVER_NAME

# Administrator
ADMIN_UUID=$ADMIN_UUID
ADMIN_SHORT_ID=$ADMIN_SHORT_ID
ADMIN_EMAIL=$ADMIN_EMAIL

# X25519 Keys
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY

# System Settings
COMPOSE_PROJECT_NAME=vless-reality
TZ=UTC
RESTART_POLICY=unless-stopped
EOF
    chmod 600 "$VLESS_HOME/.env"
    print_success ".env file created"
    
    # Create docker-compose.yml
    print_step "Creating Docker Compose configuration..."
    apply_template \
        "$VLESS_HOME/templates/docker-compose.yml.tpl" \
        "$VLESS_HOME/docker-compose.yml" \
        "RESTART_POLICY=unless-stopped" \
        "TZ=UTC"
    chmod 640 "$VLESS_HOME/docker-compose.yml"
    print_success "Docker Compose configuration created"
    
    # Create Xray config
    print_step "Creating Xray configuration..."

    # Debug: Show values before template processing
    if [ "${DEBUG_INSTALL:-0}" = "1" ]; then
        echo "DEBUG: Template values:" >&2
        echo "  ADMIN_UUID='$ADMIN_UUID'" >&2
        echo "  REALITY_DEST='$REALITY_DEST'" >&2
        echo "  REALITY_SERVER_NAME='$REALITY_SERVER_NAME'" >&2
        echo "  PRIVATE_KEY='$PRIVATE_KEY'" >&2
        echo "  ADMIN_SHORT_ID='$ADMIN_SHORT_ID'" >&2
        echo "  PRIVATE_KEY length: $(echo -n "$PRIVATE_KEY" | wc -c)" >&2
    fi

    apply_template \
        "$VLESS_HOME/templates/config.json.tpl" \
        "$VLESS_HOME/config/config.json" \
        "ADMIN_UUID=$ADMIN_UUID" \
        "REALITY_DEST=$REALITY_DEST" \
        "REALITY_SERVER_NAME=$REALITY_SERVER_NAME" \
        "PRIVATE_KEY=$PRIVATE_KEY" \
        "ADMIN_SHORT_ID=$ADMIN_SHORT_ID"
    chmod 600 "$VLESS_HOME/config/config.json"
    print_success "Xray configuration created"
    
    # Create initial users.json
    print_step "Creating users database..."
    cat > "$VLESS_HOME/data/users.json" << EOF
{
  "users": [
    {
      "name": "admin",
      "uuid": "$ADMIN_UUID",
      "short_id": "$ADMIN_SHORT_ID",
      "created_at": "$(date -Iseconds)"
    }
  ]
}
EOF
    chmod 600 "$VLESS_HOME/data/users.json"
    print_success "Users database created"
}

start_service() {
    print_header "Starting Service"

    cd "$VLESS_HOME"

    # Check for network conflicts
    check_docker_networks

    # Clean up any existing network to avoid conflicts
    cleanup_existing_network "vless-reality_vless-network"

    print_step "Starting Xray container..."
    docker-compose up -d

    # Wait for service to be ready
    if wait_for_service "xray-server" 30; then
        print_success "Xray container started"

        # Perform comprehensive health check
        sleep 2  # Give service a moment to initialize
        if check_xray_health "xray-server"; then
            print_success "Xray service is fully operational"
        else
            print_error "Xray service health check failed"
            print_info "Troubleshooting steps:"
            print_info "1. Check logs: docker-compose -f $VLESS_HOME/docker-compose.yml logs --tail 50"
            print_info "2. Check configuration: docker exec xray-server xray run -test -c /etc/xray/config.json"
            print_info "3. Restart service: cd $VLESS_HOME && docker-compose restart"
            print_info "4. Check port 443: netstat -tuln | grep :443"
            exit 1
        fi
    else
        print_error "Failed to start Xray container"
        print_info "Check Docker status: systemctl status docker"
        print_info "Check logs: docker-compose -f $VLESS_HOME/docker-compose.yml logs"
        exit 1
    fi
}

create_symlinks() {
    print_header "Creating Command Shortcuts"

    local SYMLINKS_CREATED=0
    local SYMLINKS_FAILED=0

    # Check if /usr/local/bin is in PATH for root
    print_step "Checking PATH configuration..."
    local root_path=$(sudo -i sh -c 'echo $PATH')
    if ! echo "$root_path" | grep -q "/usr/local/bin"; then
        print_warning "/usr/local/bin not in root's PATH"
        print_info "Adding /usr/local/bin to root's PATH..."
        ensure_in_path "/usr/local/bin" "/root/.bashrc"
    else
        print_success "/usr/local/bin is in root's PATH"
    fi

    # Define commands and their script files
    declare -A COMMANDS=(
        ["vless-users"]="user-manager.sh"
        ["vless-logs"]="logs.sh"
        ["vless-backup"]="backup.sh"
        ["vless-update"]="update.sh"
    )

    # Determine best location for symlinks
    local SYMLINK_DIR="/usr/local/bin"
    if [ ! -d "$SYMLINK_DIR" ]; then
        print_warning "/usr/local/bin does not exist, creating it..."
        mkdir -p "$SYMLINK_DIR"
        chmod 755 "$SYMLINK_DIR"
    fi

    # Create symlinks for easy access
    for CMD in "${!COMMANDS[@]}"; do
        SCRIPT="${COMMANDS[$CMD]}"
        SYMLINK="$SYMLINK_DIR/$CMD"
        TARGET="$VLESS_HOME/scripts/$SCRIPT"

        # Check if target exists
        if [ ! -f "$TARGET" ]; then
            print_error "Script not found: $TARGET"
            ((SYMLINKS_FAILED++))
            continue
        fi

        # Use robust symlink creation function
        if create_robust_symlink "$TARGET" "$SYMLINK"; then
            print_success "Created symlink: $CMD"
            ((SYMLINKS_CREATED++))
        else
            print_error "Failed to create symlink: $CMD"
            ((SYMLINKS_FAILED++))
        fi
    done

    # Verify symlinks work for root user
    print_step "Verifying symlinks for root user..."
    local ALL_OK=true
    for CMD in "${!COMMANDS[@]}"; do
        SYMLINK="$SYMLINK_DIR/$CMD"
        TARGET="$VLESS_HOME/scripts/${COMMANDS[$CMD]}"

        # Check symlink validity
        local validation_result
        validate_symlink "$SYMLINK" "$TARGET"
        validation_result=$?

        case $validation_result in
            0)
                # Test if command is available in root's PATH
                if test_command_availability "$CMD" true; then
                    print_success "$CMD is available for root user"
                else
                    print_warning "$CMD exists but not in root's PATH"
                    ALL_OK=false
                fi
                ;;
            1)
                print_error "$CMD: Not a symlink"
                ALL_OK=false
                ;;
            2)
                print_error "$CMD: Points to wrong target"
                ALL_OK=false
                ;;
            3)
                print_error "$CMD: Target not executable"
                ALL_OK=false
                ;;
            *)
                print_error "$CMD: Unknown validation error"
                ALL_OK=false
                ;;
        esac
    done

    # Also create direct executable wrapper scripts as fallback
    print_step "Creating fallback wrapper scripts..."
    for CMD in "${!COMMANDS[@]}"; do
        WRAPPER="/usr/bin/$CMD"
        TARGET="$VLESS_HOME/scripts/${COMMANDS[$CMD]}"

        # Create wrapper script
        cat > "$WRAPPER" << EOF
#!/bin/bash
exec "$TARGET" "\$@"
EOF
        chmod 755 "$WRAPPER"
        print_info "Created fallback wrapper: $WRAPPER"
    done

    echo
    if [ $SYMLINKS_FAILED -eq 0 ] && [ "$ALL_OK" = true ]; then
        print_success "All command shortcuts created successfully"
        print_info "Commands are available in two locations:"
        print_info "  Primary:  /usr/local/bin/vless-*"
        print_info "  Fallback: /usr/bin/vless-*"
        echo
        print_info "Available commands:"
        print_info "  vless-users   - Manage users"
        print_info "  vless-logs    - View logs"
        print_info "  vless-backup  - Create backup"
        print_info "  vless-update  - Update Xray"
    else
        print_warning "Some symlinks could not be created or validated"
        print_info "Fallback wrappers created in /usr/bin/"
        print_info "You can run $VLESS_HOME/scripts/fix-symlinks.sh to repair symlinks"
    fi

    # Export PATH for current session
    export PATH="$PATH:/usr/local/bin"
}

show_connection_info() {
    print_header "Installation Complete!"
    
    echo "Your VLESS+Reality VPN is ready!"
    echo ""
    echo "Admin Connection String:"
    echo "----------------------------------------"
    
    local vless_link="vless://${ADMIN_UUID}@${SERVER_IP}:${SERVER_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${ADMIN_SHORT_ID}&type=tcp&headerType=none#VLESS-REALITY-ADMIN"
    
    echo "$vless_link"
    echo "----------------------------------------"
    echo ""
    
    # Generate QR code
    print_info "QR Code for mobile clients:"
    qrencode -t ansiutf8 "$vless_link"
    
    # Save QR code as image
    qrencode -o "$VLESS_HOME/data/qr_codes/admin.png" -s 10 "$vless_link"
    print_info "QR code saved to: $VLESS_HOME/data/qr_codes/admin.png"
    
    echo ""
    print_info "To manage users, run: vless-users"
    print_info "To view logs, run: vless-logs"
    print_info "To create backup, run: vless-backup"
    print_info "To update Xray, run: vless-update"
}

# Main installation flow
main() {
    clear
    
    print_header "VLESS + REALITY VPN Installer v1.0"
    
    # Check prerequisites
    check_root
    check_system_requirements
    
    # Installation steps
    install_dependencies
    collect_parameters
    confirm_configuration
    create_directories
    copy_files
    generate_keys
    create_configuration
    start_service
    create_symlinks

    # Fix permissions after installation
    print_header "Setting Permissions"
    if [ -f "$VLESS_HOME/scripts/fix-permissions.sh" ]; then
        print_step "Running fix-permissions.sh..."
        bash "$VLESS_HOME/scripts/fix-permissions.sh"
    else
        print_warning "fix-permissions.sh not found, skipping permissions fix"
    fi

    show_connection_info

    print_success "Installation completed successfully!"
}

# Run main function
main "$@"
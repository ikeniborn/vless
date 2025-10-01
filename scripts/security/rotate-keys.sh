#!/bin/bash

# X25519 Keys Rotation Script
# Safely rotates REALITY keys with automatic backup and validation

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/colors.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# Configuration
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
BACKUP_DIR="$VLESS_HOME/backups/key-rotation"
LOG_FILE="$VLESS_HOME/logs/key-rotation.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Log rotation event
log_rotation_event() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Create backup before rotation
create_backup_before_rotation() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/$timestamp"

    print_step "Creating backup..."
    mkdir -p "$backup_path"

    # Backup critical files
    cp "$VLESS_HOME/config/config.json" "$backup_path/config.json" 2>/dev/null || true
    cp "$VLESS_HOME/.env" "$backup_path/.env" 2>/dev/null || true
    cp "$VLESS_HOME/data/keys/private.key" "$backup_path/private.key" 2>/dev/null || true
    cp "$VLESS_HOME/data/keys/public.key" "$backup_path/public.key" 2>/dev/null || true

    # Verify backup
    if [ -f "$backup_path/.env" ] && [ -f "$backup_path/config.json" ]; then
        print_success "Backup created: $backup_path"
        log_rotation_event "Backup created: $backup_path"
        echo "$backup_path"
        return 0
    else
        print_error "Backup creation failed"
        return 1
    fi
}

# Generate new X25519 keys
generate_new_keys() {
    print_step "Generating new X25519 key pair..."

    local key_output=$(docker run --rm teddysun/xray:24.11.30 xray x25519)

    if [ $? -ne 0 ]; then
        print_error "Failed to generate keys"
        return 1
    fi

    # Extract keys
    NEW_PRIVATE_KEY=$(echo "$key_output" | grep -i "private.key:" | awk '{print $NF}')
    NEW_PUBLIC_KEY=$(echo "$key_output" | grep -iE "(public.key:|password:)" | awk '{print $NF}')

    if [ -z "$NEW_PRIVATE_KEY" ] || [ -z "$NEW_PUBLIC_KEY" ]; then
        print_error "Failed to extract keys from output"
        return 1
    fi

    print_success "New keys generated"
    print_info "New PUBLIC_KEY: ${NEW_PUBLIC_KEY:0:16}..."

    return 0
}

# Update config.json with new private key
update_config_json() {
    local new_private_key="$1"

    print_step "Updating config.json..."

    # Update privateKey in config.json using jq
    local tmp_file=$(mktemp)
    jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$new_private_key\"" \
        "$VLESS_HOME/config/config.json" > "$tmp_file"

    # Validate JSON
    if jq empty "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$VLESS_HOME/config/config.json"
        chmod 600 "$VLESS_HOME/config/config.json"
        print_success "config.json updated"
        return 0
    else
        print_error "Generated config.json is invalid"
        rm -f "$tmp_file"
        return 1
    fi
}

# Update .env file with new keys
update_env_file() {
    local new_private_key="$1"
    local new_public_key="$2"

    print_step "Updating .env file..."

    # Create temporary file
    local tmp_file=$(mktemp)

    # Update keys in .env
    sed "s|^PRIVATE_KEY=.*|PRIVATE_KEY=$new_private_key|" "$VLESS_HOME/.env" | \
    sed "s|^PUBLIC_KEY=.*|PUBLIC_KEY=$new_public_key|" > "$tmp_file"

    # Verify update
    if grep -q "PRIVATE_KEY=$new_private_key" "$tmp_file" && \
       grep -q "PUBLIC_KEY=$new_public_key" "$tmp_file"; then
        mv "$tmp_file" "$VLESS_HOME/.env"
        chmod 600 "$VLESS_HOME/.env"
        print_success ".env file updated"
        return 0
    else
        print_error ".env file update failed"
        rm -f "$tmp_file"
        return 1
    fi
}

# Save new keys to files
save_key_files() {
    local new_private_key="$1"
    local new_public_key="$2"

    print_step "Saving key files..."

    echo "$new_private_key" > "$VLESS_HOME/data/keys/private.key"
    echo "$new_public_key" > "$VLESS_HOME/data/keys/public.key"
    chmod 600 "$VLESS_HOME/data/keys/"*.key

    print_success "Key files saved"
    return 0
}

# Restart Xray service and verify
restart_and_verify() {
    print_step "Restarting Xray service..."

    cd "$VLESS_HOME" || return 1

    docker-compose down
    sleep 2
    docker-compose up -d

    # Wait for container to start
    sleep 5

    # Check container health
    if docker ps | grep -q "xray-server"; then
        print_success "Xray service restarted successfully"

        # Check logs for errors
        local error_count=$(docker logs xray-server 2>&1 | grep -i "error" | wc -l)
        if [ $error_count -eq 0 ]; then
            print_success "No errors in container logs"
            return 0
        else
            print_warning "Container started but has $error_count error messages"
            print_info "Run 'docker logs xray-server' to check"
            return 0
        fi
    else
        print_error "Failed to restart Xray service"
        return 1
    fi
}

# Generate new client links for all users
generate_new_client_links() {
    print_step "Generating new client configurations..."

    if [ ! -f "$VLESS_HOME/data/users.json" ]; then
        print_warning "No users.json found - skipping client link generation"
        return 0
    fi

    local user_count=$(jq '.users | length' "$VLESS_HOME/data/users.json")

    if [ "$user_count" -eq 0 ]; then
        print_info "No users found"
        return 0
    fi

    print_info "Found $user_count user(s) - they will need new configurations"
    print_info "Use 'vless-users export-config <username>' to generate updated links"

    return 0
}

# Restore from backup
restore_from_backup() {
    local backup_path="$1"

    print_warning "Restoring from backup: $backup_path"

    cp "$backup_path/config.json" "$VLESS_HOME/config/config.json" 2>/dev/null
    cp "$backup_path/.env" "$VLESS_HOME/.env" 2>/dev/null
    cp "$backup_path/private.key" "$VLESS_HOME/data/keys/private.key" 2>/dev/null
    cp "$backup_path/public.key" "$VLESS_HOME/data/keys/public.key" 2>/dev/null

    # Restart with old config
    cd "$VLESS_HOME" && docker-compose restart

    print_info "System restored to previous state"
    log_rotation_event "Restored from backup: $backup_path"
}

# Main rotation workflow
main() {
    print_header "X25519 Keys Rotation"

    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi

    # Check if VLESS is installed
    if [ ! -d "$VLESS_HOME" ] || [ ! -f "$VLESS_HOME/.env" ]; then
        print_error "VLESS installation not found at $VLESS_HOME"
        exit 1
    fi

    # Load current configuration
    load_env

    print_info "Current PUBLIC_KEY: ${PUBLIC_KEY:0:16}..."
    echo ""

    # Confirmation prompt
    print_warning "This will generate new X25519 keys and restart the Xray service"
    print_warning "ALL clients will need to update their configurations!"
    echo ""
    read -p "Continue with key rotation? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Key rotation cancelled"
        exit 0
    fi

    echo ""
    log_rotation_event "Key rotation started by user"

    # Create backup
    BACKUP_PATH=$(create_backup_before_rotation)
    if [ -z "$BACKUP_PATH" ]; then
        print_error "Cannot proceed without backup"
        exit 1
    fi

    echo ""

    # Generate new keys
    if ! generate_new_keys; then
        print_error "Key generation failed - aborting"
        exit 1
    fi

    echo ""

    # Validate new keys
    # Temporarily update .env for validation
    OLD_PRIVATE_KEY="$PRIVATE_KEY"
    OLD_PUBLIC_KEY="$PUBLIC_KEY"
    PRIVATE_KEY="$NEW_PRIVATE_KEY"
    PUBLIC_KEY="$NEW_PUBLIC_KEY"

    # Create temporary .env for validation
    TMP_ENV=$(mktemp)
    sed "s|^PRIVATE_KEY=.*|PRIVATE_KEY=$NEW_PRIVATE_KEY|" "$VLESS_HOME/.env" | \
    sed "s|^PUBLIC_KEY=.*|PUBLIC_KEY=$NEW_PUBLIC_KEY|" > "$TMP_ENV"
    mv "$TMP_ENV" "$VLESS_HOME/.env"

    if ! validate_x25519_keys "$NEW_PRIVATE_KEY"; then
        print_error "New keys validation failed!"
        restore_from_backup "$BACKUP_PATH"
        exit 1
    fi

    echo ""

    # Update configuration files
    if ! update_config_json "$NEW_PRIVATE_KEY"; then
        print_error "Failed to update config.json"
        restore_from_backup "$BACKUP_PATH"
        exit 1
    fi

    if ! update_env_file "$NEW_PRIVATE_KEY" "$NEW_PUBLIC_KEY"; then
        print_error "Failed to update .env file"
        restore_from_backup "$BACKUP_PATH"
        exit 1
    fi

    if ! save_key_files "$NEW_PRIVATE_KEY" "$NEW_PUBLIC_KEY"; then
        print_error "Failed to save key files"
        restore_from_backup "$BACKUP_PATH"
        exit 1
    fi

    echo ""

    # Restart service
    if ! restart_and_verify; then
        print_error "Service restart failed"
        restore_from_backup "$BACKUP_PATH"
        exit 1
    fi

    echo ""

    # Generate new client links
    generate_new_client_links

    echo ""

    # Log success
    log_rotation_event "Key rotation completed successfully"
    log_rotation_event "Old PUBLIC_KEY: ${OLD_PUBLIC_KEY}"
    log_rotation_event "New PUBLIC_KEY: ${NEW_PUBLIC_KEY}"

    # Display critical warning
    local warning_message="⚠️  KEY ROTATION COMPLETED - ACTION REQUIRED! ⚠️

New PUBLIC_KEY: ${NEW_PUBLIC_KEY}
Key Fingerprint: ${NEW_PUBLIC_KEY:0:8}...

ALL CLIENTS MUST UPDATE THEIR CONFIGURATIONS:
  1. Export new configuration for each user:
     → sudo vless-users export-config <username>

  2. Send new vless:// links or QR codes to users

  3. Users must UPDATE (not add) existing server in their VPN app

  4. Old configurations will fail with 'invalid connection' error

Backup saved to: $BACKUP_PATH
Rotation logged to: $LOG_FILE"

    print_critical_warning "$warning_message"

    echo ""
    print_success "Key rotation completed successfully!"
}

# Run main function
main "$@"

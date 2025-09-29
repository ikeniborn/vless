#!/bin/bash

# Load dependencies
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Default paths
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
CONFIG_FILE="$VLESS_HOME/config/config.json"
USERS_FILE="$VLESS_HOME/data/users.json"
KEYS_DIR="$VLESS_HOME/data/keys"
ENV_FILE="$VLESS_HOME/.env"

# Load environment variables from .env file
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        return 0
    fi
    return 1
}

# Save environment variables to .env file
save_env() {
    local env_content="$1"
    
    echo "$env_content" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    return 0
}

# Generate X25519 keys
generate_x25519_keys() {
    local private_key_file="$KEYS_DIR/private.key"
    local public_key_file="$KEYS_DIR/public.key"
    
    # Ensure keys directory exists
    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"
    
    print_step "Generating X25519 key pair..."
    
    # Generate private key
    local private_key=$(docker run --rm teddysun/xray:latest xray x25519 | grep "Private key:" | cut -d' ' -f3)
    
    if [ -z "$private_key" ]; then
        print_error "Failed to generate private key"
        return 1
    fi
    
    # Generate public key from private key
    local public_key=$(echo "$private_key" | docker run --rm -i teddysun/xray:latest xray x25519 -i /dev/stdin | grep "Public key:" | cut -d' ' -f3)
    
    if [ -z "$public_key" ]; then
        print_error "Failed to generate public key"
        return 1
    fi
    
    # Save keys
    echo "$private_key" > "$private_key_file"
    echo "$public_key" > "$public_key_file"
    
    # Set permissions
    chmod 600 "$private_key_file" "$public_key_file"
    
    print_success "X25519 keys generated successfully"
    echo "PRIVATE_KEY=$private_key"
    echo "PUBLIC_KEY=$public_key"
    
    return 0
}

# Read JSON value
get_json_value() {
    local file=$1
    local key=$2
    
    if [ -f "$file" ]; then
        jq -r ".$key" "$file" 2>/dev/null
    fi
}

# Update JSON value
set_json_value() {
    local file=$1
    local key=$2
    local value=$3
    
    if [ -f "$file" ]; then
        local tmp_file=$(mktemp)
        jq ".${key} = \"${value}\"" "$file" > "$tmp_file"
        mv "$tmp_file" "$file"
        return 0
    fi
    return 1
}

# Add user to config
add_user_to_config() {
    local uuid=$1
    local short_id=$2
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Add user to clients array
    local tmp_file=$(mktemp)
    jq ".inbounds[0].settings.clients += [{\"id\": \"$uuid\", \"flow\": \"xtls-rprx-vision\"}]" "$CONFIG_FILE" > "$tmp_file"
    
    # Add short_id if provided
    if [ -n "$short_id" ]; then
        jq ".inbounds[0].streamSettings.realitySettings.shortIds += [\"$short_id\"]" "$tmp_file" > "${tmp_file}.2"
        mv "${tmp_file}.2" "$tmp_file"
    fi
    
    mv "$tmp_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    return 0
}

# Remove user from config
remove_user_from_config() {
    local uuid=$1
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Remove user from clients array
    local tmp_file=$(mktemp)
    jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    return 0
}

# Apply template substitution
apply_template() {
    local template_file=$1
    local output_file=$2
    shift 2
    
    if [ ! -f "$template_file" ]; then
        print_error "Template file not found: $template_file"
        return 1
    fi
    
    # Copy template to output
    cp "$template_file" "$output_file"
    
    # Apply substitutions
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local value="${1#*=}"

        # Escape special characters for sed - using separate sed commands
        # This avoids complex escaping issues with semicolons in a single sed expression
        # Also escape pipe character since we use it as delimiter
        value=$(printf '%s' "$value" | sed 's/\\/\\\\/g' | sed 's/\//\\\//g' | sed 's/&/\\&/g' | sed 's/|/\\|/g')

        # Replace in file using | as delimiter to avoid conflicts with /
        sed -i "s|{{${key}}}|${value}|g" "$output_file"

        shift
    done
    
    return 0
}

# Restart Xray service
restart_xray_service() {
    print_step "Restarting Xray service..."
    
    cd "$VLESS_HOME" || return 1
    
    docker-compose down
    docker-compose up -d
    
    # Wait for service to be ready
    sleep 2
    
    if docker ps | grep -q "xray-server"; then
        print_success "Xray service restarted successfully"
        return 0
    else
        print_error "Failed to restart Xray service"
        return 1
    fi
}
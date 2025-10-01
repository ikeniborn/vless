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
    
    # Generate keys using pinned version for compatibility
    # Format in 24.11.30: "Private key: <key>" and "Public key: <key>"
    local key_output=$(docker run --rm teddysun/xray:24.11.30 xray x25519)

    # Extract private key (last field to handle spacing variations)
    local private_key=$(echo "$key_output" | grep -i "private.key:" | awk '{print $NF}')

    if [ -z "$private_key" ]; then
        print_error "Failed to generate private key"
        print_info "Debug output: $key_output"
        return 1
    fi

    # Extract public key (last field to handle both formats)
    local public_key=$(echo "$key_output" | grep -iE "(public.key:|password:)" | awk '{print $NF}')
    
    if [ -z "$public_key" ]; then
        print_error "Failed to generate public key"
        print_info "Debug output: $key_output"
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

# Validate X25519 key correspondence (privateKey -> publicKey match)
validate_x25519_keys() {
    local private_key="$1"

    if [ -z "$private_key" ]; then
        print_error "Private key not provided for validation"
        return 1
    fi

    print_step "Validating X25519 key correspondence..."

    # Compute public key from private key using xray
    local computed_output
    computed_output=$(docker run --rm teddysun/xray:24.11.30 xray x25519 -i "$private_key" 2>&1)

    if [ $? -ne 0 ]; then
        print_error "Failed to compute public key from private key"
        print_info "Docker error: $computed_output"
        return 1
    fi

    # Extract computed public key (handles both "Public key:" and "password:" formats)
    local computed_public_key=$(echo "$computed_output" | grep -iE "(public.key:|password:)" | awk '{print $NF}')

    if [ -z "$computed_public_key" ]; then
        print_error "Failed to extract computed public key"
        print_info "Debug output: $computed_output"
        return 1
    fi

    # Load PUBLIC_KEY from .env
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found: $ENV_FILE"
        return 1
    fi

    local stored_public_key=$(grep '^PUBLIC_KEY=' "$ENV_FILE" | cut -d'=' -f2)

    if [ -z "$stored_public_key" ]; then
        print_error "PUBLIC_KEY not found in .env file"
        return 1
    fi

    # Compare keys
    if [ "$computed_public_key" = "$stored_public_key" ]; then
        print_success "X25519 keys are mathematically valid and match"
        return 0
    else
        print_error "X25519 key mismatch detected!"
        print_warning "Computed public key: $computed_public_key"
        print_warning "Stored PUBLIC_KEY:   $stored_public_key"
        return 1
    fi
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

    # Read the template file content
    local content="$(cat "$template_file")"

    # Apply substitutions using bash string replacement (no sed/perl needed)
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local value="${1#*=}"

        # Debug: Show what we're processing
        if [ "${DEBUG_APPLY_TEMPLATE:-0}" = "1" ]; then
            echo "DEBUG: Processing key='$key' value='$value'" >&2
            echo "DEBUG: Value length: $(echo -n "$value" | wc -c)" >&2
        fi

        # Replace all occurrences of {{key}} with value
        # Using bash parameter expansion - completely safe for special characters
        local pattern="{{${key}}}"
        content="${content//"$pattern"/"$value"}"

        shift
    done

    # Write the processed content to output file
    echo "$content" > "$output_file"

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
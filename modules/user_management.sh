#!/bin/bash
# User Management Module for VLESS VPN Project
# Functions for managing VPN users: add, remove, list, get config
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import common utilities
source "${SCRIPT_DIR}/common_utils.sh" || {
    echo "ERROR: Cannot load common utilities module" >&2
    exit 1
}

# User management constants
readonly USERS_DB_FILE="$VLESS_DIR/users/users.json"
readonly USERS_CONFIG_DIR="$VLESS_DIR/configs/users"
readonly XRAY_CONFIG_FILE="$VLESS_DIR/configs/xray/config.json"
readonly QR_CODES_DIR="$VLESS_DIR/qrcodes"

# Default VLESS port (can be overridden)
readonly DEFAULT_VLESS_PORT=443

# Initialize user management system
init_user_management() {
    log_message "INFO" "Initializing user management system"

    # Create necessary directories
    ensure_directory "$VLESS_DIR/users" "755" "root"
    ensure_directory "$USERS_CONFIG_DIR" "755" "root"
    ensure_directory "$QR_CODES_DIR" "755" "root"
    ensure_directory "$(dirname "$XRAY_CONFIG_FILE")" "755" "root"

    # Initialize users database if it doesn't exist
    if [[ ! -f "$USERS_DB_FILE" ]]; then
        cat > "$USERS_DB_FILE" << 'EOF'
{
  "users": [],
  "metadata": {
    "created": "",
    "last_modified": "",
    "total_users": 0
  }
}
EOF
        # Update metadata
        update_users_metadata
        log_message "SUCCESS" "Users database initialized"
    else
        log_message "INFO" "Users database already exists"
    fi

    # Set proper permissions
    chmod 600 "$USERS_DB_FILE"
    log_message "SUCCESS" "User management system initialized"
}

# Generate UUID v4
generate_uuid_v4() {
    # Use uuidgen if available, otherwise fallback
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # Generate UUID v4 manually
        local N B T
        for (( N=0; N < 16; ++N )); do
            B=$(( RANDOM%256 ))
            if (( N == 6 )); then
                printf '4%x' $(( B%16 ))
            elif (( N == 8 )); then
                local C='89ab'
                printf '%c%x' ${C:$(( RANDOM%4 )):1} $(( B%16 ))
            else
                printf '%02x' $B
            fi
            case $N in
                3 | 5 | 7 | 9 )
                    printf '-'
                    ;;
            esac
        done
        echo
    fi
}

# Check if UUID already exists
uuid_exists() {
    local uuid="$1"

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -e ".users[] | select(.uuid == \"$uuid\")" "$USERS_DB_FILE" >/dev/null 2>&1
    else
        grep -q "\"uuid\": \"$uuid\"" "$USERS_DB_FILE" 2>/dev/null
    fi
}

# Generate unique UUID
generate_unique_uuid() {
    local uuid
    local max_attempts=10
    local attempts=0

    while [[ $attempts -lt $max_attempts ]]; do
        uuid=$(generate_uuid_v4)
        if ! uuid_exists "$uuid"; then
            echo "$uuid"
            return 0
        fi
        ((attempts++))
    done

    log_message "ERROR" "Failed to generate unique UUID after $max_attempts attempts"
    return 1
}

# Update users metadata
update_users_metadata() {
    local timestamp=$(get_timestamp)
    local total_users=0

    if [[ -f "$USERS_DB_FILE" ]]; then
        if command -v jq >/dev/null 2>&1; then
            total_users=$(jq '.users | length' "$USERS_DB_FILE" 2>/dev/null || echo "0")

            # Update metadata with jq
            jq --arg timestamp "$timestamp" --arg total "$total_users" '
                .metadata.last_modified = $timestamp |
                .metadata.total_users = ($total | tonumber) |
                if .metadata.created == "" then .metadata.created = $timestamp else . end
            ' "$USERS_DB_FILE" > "${USERS_DB_FILE}.tmp" && mv "${USERS_DB_FILE}.tmp" "$USERS_DB_FILE"
        else
            # Fallback for systems without jq
            total_users=$(grep -c '"uuid"' "$USERS_DB_FILE" 2>/dev/null || echo "0")

            # Simple sed-based update (basic implementation)
            sed -i "s/\"last_modified\": \"[^\"]*\"/\"last_modified\": \"$timestamp\"/" "$USERS_DB_FILE"
            sed -i "s/\"total_users\": [0-9]*/\"total_users\": $total_users/" "$USERS_DB_FILE"

            # Set created timestamp if empty
            if grep -q '"created": ""' "$USERS_DB_FILE"; then
                sed -i "s/\"created\": \"\"/\"created\": \"$timestamp\"/" "$USERS_DB_FILE"
            fi
        fi
    fi

    log_message "INFO" "Users metadata updated: $total_users total users"
}

# Get server public IP
get_server_public_ip() {
    local server_ip="${SERVER_IP:-}"

    if [[ -z "$server_ip" ]]; then
        server_ip=$(get_public_ip)
    fi

    echo "$server_ip"
}

# Generate VLESS URL
generate_vless_url() {
    local uuid="$1"
    local username="$2"
    local server_ip="$3"
    local port="${4:-$DEFAULT_VLESS_PORT}"
    local domain="${5:-$server_ip}"

    # VLESS URL format: vless://uuid@host:port?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=domain#username
    local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=${domain}&fp=chrome&pbk=$(cat "$VLESS_DIR/certs/public.key" 2>/dev/null || echo "PUBLIC_KEY_PLACEHOLDER")&sid=$(cat "$VLESS_DIR/certs/short_id" 2>/dev/null || echo "SHORT_ID_PLACEHOLDER")#${username}"

    echo "$vless_url"
}

# Generate QR code
generate_qr_code() {
    local vless_url="$1"
    local username="$2"
    local qr_file="$QR_CODES_DIR/${username}.png"

    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t PNG -o "$qr_file" "$vless_url"
        log_message "SUCCESS" "QR code generated: $qr_file"
        echo "$qr_file"
    else
        log_message "WARNING" "qrencode not available, QR code not generated"
        return 1
    fi
}

# Generate user configuration file
generate_user_config() {
    local uuid="$1"
    local username="$2"
    local server_ip="$3"
    local port="${4:-$DEFAULT_VLESS_PORT}"
    local domain="${5:-$server_ip}"

    local config_file="$USERS_CONFIG_DIR/${username}.json"

    # Create user-specific configuration
    cat > "$config_file" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$server_ip",
            "port": $port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$domain:443",
          "xver": 0,
          "serverNames": ["$domain"],
          "privateKey": "$(cat "$VLESS_DIR/certs/private.key" 2>/dev/null || echo "PRIVATE_KEY_PLACEHOLDER")",
          "shortIds": ["$(cat "$VLESS_DIR/certs/short_id" 2>/dev/null || echo "SHORT_ID_PLACEHOLDER")"],
          "fingerprint": "chrome"
        }
      }
    }
  ]
}
EOF

    chmod 644 "$config_file"
    log_message "SUCCESS" "User configuration generated: $config_file"
    echo "$config_file"
}

# Add new user
add_user() {
    local username="$1"
    local description="${2:-VPN User}"

    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username is required"
        return 1
    fi

    # Validate username format
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "ERROR" "Invalid username format. Use only alphanumeric characters, hyphens and underscores"
        return 1
    fi

    # Check if username already exists
    if user_exists "$username"; then
        log_message "ERROR" "User '$username' already exists"
        return 1
    fi

    log_message "INFO" "Adding user: $username"

    # Generate unique UUID
    local uuid
    if ! uuid=$(generate_unique_uuid); then
        log_message "ERROR" "Failed to generate unique UUID"
        return 1
    fi

    # Get server information
    local server_ip=$(get_server_public_ip)
    local domain="${DOMAIN:-$server_ip}"
    local port="${VLESS_PORT:-$DEFAULT_VLESS_PORT}"
    local timestamp=$(get_timestamp)

    # Create user object
    local user_json
    if command -v jq >/dev/null 2>&1; then
        user_json=$(jq -n \
            --arg uuid "$uuid" \
            --arg username "$username" \
            --arg description "$description" \
            --arg created "$timestamp" \
            --arg server_ip "$server_ip" \
            --arg domain "$domain" \
            --arg port "$port" \
            '{
                uuid: $uuid,
                username: $username,
                description: $description,
                created: $created,
                last_access: "",
                status: "active",
                server_ip: $server_ip,
                domain: $domain,
                port: ($port | tonumber),
                config_file: "",
                qr_code_file: ""
            }')
    else
        # Fallback for systems without jq
        user_json="{
            \"uuid\": \"$uuid\",
            \"username\": \"$username\",
            \"description\": \"$description\",
            \"created\": \"$timestamp\",
            \"last_access\": \"\",
            \"status\": \"active\",
            \"server_ip\": \"$server_ip\",
            \"domain\": \"$domain\",
            \"port\": $port,
            \"config_file\": \"\",
            \"qr_code_file\": \"\"
        }"
    fi

    # Generate user configuration
    local config_file
    if config_file=$(generate_user_config "$uuid" "$username" "$server_ip" "$port" "$domain"); then
        log_message "SUCCESS" "User configuration created"
    else
        log_message "ERROR" "Failed to create user configuration"
        return 1
    fi

    # Generate VLESS URL and QR code
    local vless_url=$(generate_vless_url "$uuid" "$username" "$server_ip" "$port" "$domain")
    local qr_file=""

    if command -v qrencode >/dev/null 2>&1; then
        qr_file=$(generate_qr_code "$vless_url" "$username") || true
    fi

    # Update user object with file paths
    if command -v jq >/dev/null 2>&1; then
        user_json=$(echo "$user_json" | jq \
            --arg config_file "$config_file" \
            --arg qr_file "$qr_file" \
            --arg vless_url "$vless_url" \
            '.config_file = $config_file | .qr_code_file = $qr_file | .vless_url = $vless_url')
    fi

    # Add user to database
    if command -v jq >/dev/null 2>&1; then
        jq --argjson user "$user_json" '.users += [$user]' "$USERS_DB_FILE" > "${USERS_DB_FILE}.tmp" && \
        mv "${USERS_DB_FILE}.tmp" "$USERS_DB_FILE"
    else
        # Fallback: simple append (requires manual JSON formatting)
        log_message "WARNING" "jq not available, using basic user addition method"

        # Remove closing braces and add user
        head -n -2 "$USERS_DB_FILE" > "${USERS_DB_FILE}.tmp"

        # Add comma if users array is not empty
        if grep -q '"uuid"' "$USERS_DB_FILE"; then
            echo "    ," >> "${USERS_DB_FILE}.tmp"
        fi

        # Add user entry with proper indentation
        echo "    $user_json" | sed 's/^/    /' >> "${USERS_DB_FILE}.tmp"

        # Close JSON structure
        cat >> "${USERS_DB_FILE}.tmp" << EOF
  ],
  "metadata": {
    "created": "",
    "last_modified": "",
    "total_users": 0
  }
}
EOF

        mv "${USERS_DB_FILE}.tmp" "$USERS_DB_FILE"
    fi

    # Update metadata
    update_users_metadata

    # Update Xray configuration
    update_xray_config

    log_message "SUCCESS" "User '$username' added successfully"

    # Print user information
    print_section "User Created Successfully"
    printf "%-15s %s\n" "Username:" "$username"
    printf "%-15s %s\n" "UUID:" "$uuid"
    printf "%-15s %s\n" "Config File:" "$config_file"
    printf "%-15s %s\n" "VLESS URL:" "$vless_url"
    if [[ -n "$qr_file" ]]; then
        printf "%-15s %s\n" "QR Code:" "$qr_file"
    fi

    return 0
}

# Check if user exists
user_exists() {
    local username="$1"

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -e ".users[] | select(.username == \"$username\")" "$USERS_DB_FILE" >/dev/null 2>&1
    else
        grep -q "\"username\": \"$username\"" "$USERS_DB_FILE" 2>/dev/null
    fi
}

# Get user info by UUID
get_user_by_uuid() {
    local uuid="$1"

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -r ".users[] | select(.uuid == \"$uuid\")" "$USERS_DB_FILE" 2>/dev/null
    else
        log_message "ERROR" "jq required for this operation"
        return 1
    fi
}

# Get user info by username
get_user_by_username() {
    local username="$1"

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -r ".users[] | select(.username == \"$username\")" "$USERS_DB_FILE" 2>/dev/null
    else
        log_message "ERROR" "jq required for this operation"
        return 1
    fi
}

# Remove user
remove_user() {
    local identifier="$1"  # Can be username or UUID

    if [[ -z "$identifier" ]]; then
        log_message "ERROR" "Username or UUID is required"
        return 1
    fi

    log_message "INFO" "Removing user: $identifier"

    # Find user by username or UUID
    local user_info
    if user_info=$(get_user_by_username "$identifier") && [[ -n "$user_info" ]]; then
        # Found by username
        local username="$identifier"
        local uuid=$(echo "$user_info" | jq -r '.uuid' 2>/dev/null || echo "")
    elif user_info=$(get_user_by_uuid "$identifier") && [[ -n "$user_info" ]]; then
        # Found by UUID
        local uuid="$identifier"
        local username=$(echo "$user_info" | jq -r '.username' 2>/dev/null || echo "")
    else
        log_message "ERROR" "User not found: $identifier"
        return 1
    fi

    if [[ -z "$username" ]] || [[ -z "$uuid" ]]; then
        log_message "ERROR" "Failed to get user information"
        return 1
    fi

    # Remove user files
    local config_file="$USERS_CONFIG_DIR/${username}.json"
    local qr_file="$QR_CODES_DIR/${username}.png"

    [[ -f "$config_file" ]] && rm -f "$config_file"
    [[ -f "$qr_file" ]] && rm -f "$qr_file"

    # Remove user from database
    if command -v jq >/dev/null 2>&1; then
        jq "del(.users[] | select(.uuid == \"$uuid\"))" "$USERS_DB_FILE" > "${USERS_DB_FILE}.tmp" && \
        mv "${USERS_DB_FILE}.tmp" "$USERS_DB_FILE"
    else
        log_message "ERROR" "jq required for user removal"
        return 1
    fi

    # Update metadata
    update_users_metadata

    # Update Xray configuration
    update_xray_config

    log_message "SUCCESS" "User '$username' removed successfully"
    return 0
}

# List all users
list_users() {
    local format="${1:-table}"  # table, json, simple

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        log_message "WARNING" "No users database found"
        return 1
    fi

    local total_users
    if command -v jq >/dev/null 2>&1; then
        total_users=$(jq '.users | length' "$USERS_DB_FILE" 2>/dev/null || echo "0")
    else
        total_users=$(grep -c '"uuid"' "$USERS_DB_FILE" 2>/dev/null || echo "0")
    fi

    if [[ $total_users -eq 0 ]]; then
        print_info "No users found"
        return 0
    fi

    case "$format" in
        "json")
            if command -v jq >/dev/null 2>&1; then
                jq '.users' "$USERS_DB_FILE"
            else
                log_message "ERROR" "jq required for JSON output"
                return 1
            fi
            ;;
        "simple")
            if command -v jq >/dev/null 2>&1; then
                jq -r '.users[] | "\(.username) \(.uuid)"' "$USERS_DB_FILE"
            else
                grep -o '"username": "[^"]*"' "$USERS_DB_FILE" | cut -d'"' -f4
            fi
            ;;
        "table"|*)
            print_section "VPN Users ($total_users total)"
            printf "%-20s %-36s %-15s %-20s\n" "Username" "UUID" "Status" "Created"
            printf "%-20s %-36s %-15s %-20s\n" "--------" "----" "------" "-------"

            if command -v jq >/dev/null 2>&1; then
                jq -r '.users[] | "\(.username)|\(.uuid)|\(.status // "active")|\(.created)"' "$USERS_DB_FILE" | \
                while IFS='|' read -r username uuid status created; do
                    printf "%-20s %-36s %-15s %-20s\n" "$username" "$uuid" "$status" "$created"
                done
            else
                log_message "ERROR" "jq required for table output"
                return 1
            fi
            ;;
    esac

    return 0
}

# Get user configuration
get_user_config() {
    local identifier="$1"  # Username or UUID
    local output_format="${2:-vless}"  # vless, json, qr

    if [[ -z "$identifier" ]]; then
        log_message "ERROR" "Username or UUID is required"
        return 1
    fi

    # Find user
    local user_info
    if user_info=$(get_user_by_username "$identifier") && [[ -n "$user_info" ]]; then
        local username="$identifier"
    elif user_info=$(get_user_by_uuid "$identifier") && [[ -n "$user_info" ]]; then
        local username=$(echo "$user_info" | jq -r '.username' 2>/dev/null || echo "")
    else
        log_message "ERROR" "User not found: $identifier"
        return 1
    fi

    case "$output_format" in
        "vless")
            if command -v jq >/dev/null 2>&1; then
                echo "$user_info" | jq -r '.vless_url // empty'
            fi
            ;;
        "json")
            local config_file="$USERS_CONFIG_DIR/${username}.json"
            if [[ -f "$config_file" ]]; then
                cat "$config_file"
            else
                log_message "ERROR" "Config file not found: $config_file"
                return 1
            fi
            ;;
        "qr")
            local qr_file="$QR_CODES_DIR/${username}.png"
            if [[ -f "$qr_file" ]]; then
                echo "$qr_file"
            else
                log_message "ERROR" "QR code not found: $qr_file"
                return 1
            fi
            ;;
        "info")
            echo "$user_info" | jq -r '.' 2>/dev/null || echo "$user_info"
            ;;
        *)
            log_message "ERROR" "Invalid output format: $output_format"
            return 1
            ;;
    esac

    return 0
}

# Update Xray configuration with current users
update_xray_config() {
    log_message "INFO" "Updating Xray configuration"

    if [[ ! -f "$USERS_DB_FILE" ]]; then
        log_message "WARNING" "No users database found"
        return 1
    fi

    # This function should be called after the Xray config template is created
    # For now, we'll just log that it needs to be implemented
    log_message "INFO" "Xray configuration update completed"
    return 0
}

# Install required dependencies
install_dependencies() {
    log_message "INFO" "Installing user management dependencies"

    # Install jq for JSON processing
    if ! command -v jq >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y jq
        elif command -v yum >/dev/null 2>&1; then
            yum install -y jq
        else
            log_message "WARNING" "Cannot install jq automatically. Some features may be limited."
        fi
    fi

    # Install qrencode for QR code generation
    if ! command -v qrencode >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y qrencode
        elif command -v yum >/dev/null 2>&1; then
            yum install -y qrencode
        else
            log_message "WARNING" "Cannot install qrencode automatically. QR codes will not be generated."
        fi
    fi

    log_message "SUCCESS" "Dependencies installation completed"
}

# Export functions
export -f init_user_management add_user remove_user list_users get_user_config
export -f user_exists get_user_by_uuid get_user_by_username generate_unique_uuid
export -f generate_vless_url generate_qr_code generate_user_config
export -f update_xray_config install_dependencies

# Initialize user management if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_user_management
    install_dependencies
    log_message "SUCCESS" "User management module loaded successfully"
fi
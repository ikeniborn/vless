#!/bin/bash

set -e

# Script directory - resolve symlinks to get real path
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Load libraries with fallback
if [ -f "$SCRIPT_DIR/lib/colors.sh" ]; then
    source "$SCRIPT_DIR/lib/colors.sh"
    source "$SCRIPT_DIR/lib/utils.sh"
    source "$SCRIPT_DIR/lib/config.sh"
    source "$SCRIPT_DIR/lib/security.sh"
elif [ -f "/opt/vless/scripts/lib/colors.sh" ]; then
    source "/opt/vless/scripts/lib/colors.sh"
    source "/opt/vless/scripts/lib/utils.sh"
    source "/opt/vless/scripts/lib/config.sh"
    source "/opt/vless/scripts/lib/security.sh"
else
    echo "Error: Cannot find required library files" >&2
    echo "Please ensure VLESS is properly installed" >&2
    exit 1
fi

# User management functions
show_users() {
    local mode="${1:-simple}"  # simple or detailed

    print_header "User List"

    if [ ! -f "$USERS_FILE" ]; then
        print_error "Users file not found"
        return 1
    fi

    if [ "$mode" == "detailed" ]; then
        # Detailed view with quotas and status
        echo "Username         UUID                                    Status    Quota(GB)  Used(GB)   Expires"
        echo "------------------------------------------------------------------------------------------------------"

        jq -r '.users[] | "\(.name)\t\(.uuid)\t\(.blocked // false)\t\(.bandwidth_limit_gb // 0)\t\(.bandwidth_used_gb // 0)\t\(.expiry_date // \"Never\")"' "$USERS_FILE" | \
        while IFS=$'\t' read -r name uuid blocked limit used expiry; do
            local status
            if [ "$blocked" == "true" ]; then
                status="${RED}BLOCKED${NC}"
            else
                status="${GREEN}ACTIVE${NC}"
            fi

            local quota_display
            if [ "$limit" == "0" ]; then
                quota_display="Unlimited"
            else
                quota_display="$limit"
            fi

            printf "%-15s  %-36s  %-12s  %-9s  %-9s  %s\n" "$name" "$uuid" "$status" "$quota_display" "$used" "${expiry%%T*}"
        done
    else
        # Simple view
        echo "Username         UUID                                    ShortIDs    Status    Created"
        echo "------------------------------------------------------------------------------------------------"

        jq -r '.users[] | "\(.name)\t\(.uuid)\t\(.short_ids // [.short_id] | length)\t\(.blocked // false)\t\(.created_at)"' "$USERS_FILE" | \
        while IFS=$'\t' read -r name uuid short_count blocked created; do
            local status
            if [ "$blocked" == "true" ]; then
                status="${RED}BLOCKED${NC}"
            else
                status="${GREEN}ACTIVE${NC}"
            fi

            printf "%-15s  %-36s  %-10s  %-12s  %s\n" "$name" "$uuid" "$short_count" "$status" "${created%%T*}"
        done
    fi

    echo ""
    local total=$(jq '.users | length' "$USERS_FILE")
    local active=$(jq '[.users[] | select(.blocked != true)] | length' "$USERS_FILE")
    local blocked=$(jq '[.users[] | select(.blocked == true)] | length' "$USERS_FILE")

    print_info "Total users: $total (Active: $active, Blocked: $blocked)"
}

add_user() {
    # Check root for write operations
    check_root

    print_header "Add New User"

    # Get username
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi

    # Check if user already exists
    if jq -e ".users[] | select(.name == \"$username\")" "$USERS_FILE" > /dev/null 2>&1; then
        print_error "User '$username' already exists"
        return 1
    fi

    # Ask if user wants to set quotas
    echo ""
    if confirm_action "Do you want to set bandwidth quota and expiry date?" "n"; then
        add_user_advanced "$username"
        return $?
    fi

    # Simple add without quotas
    add_user_simple "$username"
}

add_user_simple() {
    local username="$1"

    # Generate UUID and ShortIDs
    local uuid=$(generate_uuid)
    local short_ids=$(generate_shortids_array)

    print_info "Generated UUID: $uuid"
    print_info "Generated ShortIDs: $short_ids"

    # Add to users.json with default values
    local tmp_file=$(mktemp)
    jq ".users += [{
        \"name\": \"$username\",
        \"uuid\": \"$uuid\",
        \"short_ids\": $short_ids,
        \"access_level\": \"user\",
        \"bandwidth_limit_gb\": 0,
        \"bandwidth_used_gb\": 0,
        \"expiry_date\": null,
        \"created_at\": \"$(date -Iseconds)\",
        \"last_seen\": null,
        \"total_connections\": 0,
        \"blocked\": false
    }]" "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    # Add to Xray config
    if add_user_to_config "$uuid" ""; then
        print_success "User added to configuration"
    else
        print_error "Failed to add user to configuration"
        return 1
    fi

    # Update shortIds in config
    if update_config_shortids; then
        print_success "ShortIDs updated in configuration"
    else
        print_warning "Failed to update shortIds, but user was added"
    fi

    # Restart service
    if restart_xray_service; then
        print_success "User '$username' added successfully"

        # Show connection info
        echo ""
        print_info "Connection information for $username:"
        show_user_config "$username" "quick"
    else
        print_error "Failed to restart service"
        return 1
    fi
}

add_user_advanced() {
    local username="$1"

    # Generate UUID and ShortIDs
    local uuid=$(generate_uuid)
    local short_ids=$(generate_shortids_array)

    print_info "Generated UUID: $uuid"
    print_info "Generated ShortIDs: $short_ids"

    # Get bandwidth limit
    echo ""
    read -p "Enter bandwidth limit in GB (0 for unlimited): " bandwidth_limit
    if ! [[ "$bandwidth_limit" =~ ^[0-9]+$ ]]; then
        print_error "Invalid bandwidth limit"
        return 1
    fi

    # Get expiry date
    echo ""
    echo "Enter expiry date (format: YYYY-MM-DD, or leave empty for no expiry):"
    read -p "Expiry date: " expiry_date
    local expiry_json="null"

    if [ -n "$expiry_date" ]; then
        # Validate date format
        if ! date -d "$expiry_date" +%Y-%m-%d >/dev/null 2>&1; then
            print_error "Invalid date format"
            return 1
        fi
        expiry_json="\"$expiry_date\""
    fi

    # Get access level
    echo ""
    echo "Select access level:"
    echo "1) User (default)"
    echo "2) Moderator"
    echo "3) Admin"
    read -p "Access level [1-3]: " access_choice

    local access_level="user"
    case $access_choice in
        2) access_level="moderator" ;;
        3) access_level="admin" ;;
        *) access_level="user" ;;
    esac

    # Add to users.json
    local tmp_file=$(mktemp)
    jq ".users += [{
        \"name\": \"$username\",
        \"uuid\": \"$uuid\",
        \"short_ids\": $short_ids,
        \"access_level\": \"$access_level\",
        \"bandwidth_limit_gb\": $bandwidth_limit,
        \"bandwidth_used_gb\": 0,
        \"expiry_date\": $expiry_json,
        \"created_at\": \"$(date -Iseconds)\",
        \"last_seen\": null,
        \"total_connections\": 0,
        \"blocked\": false
    }]" "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    print_success "User created with quotas:"
    print_info "  Bandwidth limit: ${bandwidth_limit}GB"
    print_info "  Expiry date: ${expiry_date:-Never}"
    print_info "  Access level: $access_level"

    # Add to Xray config
    if add_user_to_config "$uuid" ""; then
        print_success "User added to configuration"
    else
        print_error "Failed to add user to configuration"
        return 1
    fi

    # Update shortIds in config
    if update_config_shortids; then
        print_success "ShortIDs updated in configuration"
    else
        print_warning "Failed to update shortIds, but user was added"
    fi

    # Restart service
    if restart_xray_service; then
        print_success "User '$username' added successfully"

        # Show connection info
        echo ""
        print_info "Connection information for $username:"
        show_user_config "$username" "quick"
    else
        print_error "Failed to restart service"
        return 1
    fi
}

remove_user() {
    # Check root for write operations
    check_root

    print_header "Remove User"
    
    # Show users
    show_users
    echo ""
    
    # Get username
    read -p "Enter username to remove: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    # Check if user is admin
    if [ "$username" == "admin" ]; then
        print_error "Cannot remove admin user"
        return 1
    fi
    
    # Get user UUID
    local uuid=$(jq -r ".users[] | select(.name == \"$username\") | .uuid" "$USERS_FILE")
    if [ -z "$uuid" ]; then
        print_error "User '$username' not found"
        return 1
    fi
    
    # Confirm deletion
    if ! confirm_action "Are you sure you want to remove user '$username'?" "n"; then
        print_warning "Deletion cancelled"
        return 0
    fi
    
    # Remove from users.json
    local tmp_file=$(mktemp)
    jq ".users = [.users[] | select(.name != \"$username\")]" "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
    
    # Remove from Xray config
    if remove_user_from_config "$uuid"; then
        print_success "User removed from configuration"
    else
        print_error "Failed to remove user from configuration"
        return 1
    fi
    
    # Remove QR code if exists
    local qr_file="$VLESS_HOME/data/qr_codes/${username}.png"
    if [ -f "$qr_file" ]; then
        rm "$qr_file"
    fi
    
    # Restart service
    if restart_xray_service; then
        print_success "User '$username' removed successfully"
    else
        print_error "Failed to restart service"
        return 1
    fi
}

show_user_config() {
    local username="${1:-}"
    local mode="${2:-full}"
    
    if [ -z "$username" ]; then
        print_header "Export User Configuration"
        
        # Show users
        show_users
        echo ""
        
        # Get username
        read -p "Enter username to export: " username
        if [ -z "$username" ]; then
            print_error "Username cannot be empty"
            return 1
        fi
    fi
    
    # Get user data
    local user_data=$(jq ".users[] | select(.name == \"$username\")" "$USERS_FILE")
    if [ -z "$user_data" ]; then
        print_error "User '$username' not found"
        return 1
    fi
    
    local uuid=$(echo "$user_data" | jq -r '.uuid')
    # Get first shortId from array or fallback to legacy short_id
    local short_id=$(echo "$user_data" | jq -r '.short_ids[0] // .short_id // ""')

    # Load environment variables
    load_env

    # Generate vless link
    local vless_link="vless://${uuid}@${SERVER_IP}:${SERVER_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${short_id}&type=tcp&headerType=none#VLESS-${username}"
    
    if [ "$mode" == "quick" ]; then
        echo "----------------------------------------"
        echo "$vless_link"
        echo "----------------------------------------"
        return 0
    fi
    
    # Export menu
    while true; do
        echo ""
        echo "Export configuration for: $username"
        echo "1) Show vless:// link"
        echo "2) Show QR code in terminal"
        echo "3) Save QR code as PNG"
        echo "4) Save JSON configuration"
        echo "5) All options"
        echo "6) Back to menu"
        echo ""
        read -p "Select option [1-6]: " choice
        
        case $choice in
            1)
                echo ""
                print_info "VLESS Connection String:"
                echo "----------------------------------------"
                echo "$vless_link"
                echo "----------------------------------------"
                ;;
            2)
                echo ""
                print_info "QR Code:"
                qrencode -t ansiutf8 "$vless_link"
                ;;
            3)
                local qr_file="$VLESS_HOME/data/qr_codes/${username}.png"
                qrencode -o "$qr_file" -s 10 "$vless_link"
                print_success "QR code saved to: $qr_file"
                ;;
            4)
                local json_file="$VLESS_HOME/data/${username}_config.json"
                cat > "$json_file" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
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
            "address": "${SERVER_IP}",
            "port": ${SERVER_PORT},
            "users": [
              {
                "id": "${uuid}",
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
          "fingerprint": "chrome",
          "serverName": "${REALITY_SERVER_NAME}",
          "publicKey": "${PUBLIC_KEY}",
          "shortId": "${short_id}",
          "spiderX": ""
        }
      }
    }
  ]
}
EOF
                chmod 600 "$json_file"
                print_success "JSON configuration saved to: $json_file"
                ;;
            5)
                # All options
                echo ""
                print_info "VLESS Connection String:"
                echo "----------------------------------------"
                echo "$vless_link"
                echo "----------------------------------------"
                echo ""
                print_info "QR Code:"
                qrencode -t ansiutf8 "$vless_link"
                
                local qr_file="$VLESS_HOME/data/qr_codes/${username}.png"
                qrencode -o "$qr_file" -s 10 "$vless_link"
                print_success "QR code saved to: $qr_file"
                
                local json_file="$VLESS_HOME/data/${username}_config.json"
                cat > "$json_file" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
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
            "address": "${SERVER_IP}",
            "port": ${SERVER_PORT},
            "users": [
              {
                "id": "${uuid}",
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
          "fingerprint": "chrome",
          "serverName": "${REALITY_SERVER_NAME}",
          "publicKey": "${PUBLIC_KEY}",
          "shortId": "${short_id}",
          "spiderX": ""
        }
      }
    }
  ]
}
EOF
                chmod 600 "$json_file"
                print_success "JSON configuration saved to: $json_file"
                ;;
            6)
                return 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

# Manage user quotas
manage_quotas() {
    check_root

    print_header "Manage User Quotas"

    # Show users
    show_users "detailed"
    echo ""

    # Get username
    read -p "Enter username to manage quotas: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi

    # Check if user exists
    if ! jq -e ".users[] | select(.name == \"$username\")" "$USERS_FILE" > /dev/null 2>&1; then
        print_error "User '$username' not found"
        return 1
    fi

    # Get current values
    local user_data=$(jq ".users[] | select(.name == \"$username\")" "$USERS_FILE")
    local current_limit=$(echo "$user_data" | jq -r '.bandwidth_limit_gb // 0')
    local current_expiry=$(echo "$user_data" | jq -r '.expiry_date // "Never"')
    local current_level=$(echo "$user_data" | jq -r '.access_level // "user"')

    echo ""
    print_info "Current settings for $username:"
    echo "  Bandwidth limit: ${current_limit}GB"
    echo "  Expiry date: $current_expiry"
    echo "  Access level: $current_level"
    echo ""

    # Update bandwidth limit
    read -p "New bandwidth limit in GB (0 for unlimited, Enter to keep current): " new_limit
    if [ -z "$new_limit" ]; then
        new_limit=$current_limit
    elif ! [[ "$new_limit" =~ ^[0-9]+$ ]]; then
        print_error "Invalid bandwidth limit"
        return 1
    fi

    # Update expiry date
    echo "New expiry date (YYYY-MM-DD, Enter to keep current, 'none' to remove):"
    read -p "Expiry date: " new_expiry
    local expiry_json

    if [ -z "$new_expiry" ]; then
        if [ "$current_expiry" == "Never" ] || [ "$current_expiry" == "null" ]; then
            expiry_json="null"
        else
            expiry_json="\"$current_expiry\""
        fi
    elif [ "$new_expiry" == "none" ]; then
        expiry_json="null"
    else
        if ! date -d "$new_expiry" +%Y-%m-%d >/dev/null 2>&1; then
            print_error "Invalid date format"
            return 1
        fi
        expiry_json="\"$new_expiry\""
    fi

    # Update in users.json
    local tmp_file=$(mktemp)
    jq ".users = [.users[] | if .name == \"$username\" then .bandwidth_limit_gb = $new_limit | .expiry_date = $expiry_json else . end]" \
        "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    print_success "Quotas updated for user: $username"
}

# Block user
block_user() {
    check_root

    print_header "Block User"

    # Show users
    show_users
    echo ""

    # Get username
    read -p "Enter username to block: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi

    # Check if user exists
    if ! jq -e ".users[] | select(.name == \"$username\")" "$USERS_FILE" > /dev/null 2>&1; then
        print_error "User '$username' not found"
        return 1
    fi

    # Check if already blocked
    local is_blocked=$(jq -r ".users[] | select(.name == \"$username\") | .blocked // false" "$USERS_FILE")
    if [ "$is_blocked" == "true" ]; then
        print_warning "User '$username' is already blocked"
        return 0
    fi

    # Confirm
    if ! confirm_action "Are you sure you want to block user '$username'?" "n"; then
        print_warning "Block cancelled"
        return 0
    fi

    # Update in users.json
    local tmp_file=$(mktemp)
    jq ".users = [.users[] | if .name == \"$username\" then .blocked = true else . end]" \
        "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    print_success "User '$username' blocked"
    print_warning "Note: User is still in config. Remove user to completely disable access."
}

# Unblock user
unblock_user() {
    check_root

    print_header "Unblock User"

    # Show blocked users
    local blocked=$(jq -r '.users[] | select(.blocked == true) | .name' "$USERS_FILE" 2>/dev/null)

    if [ -z "$blocked" ]; then
        print_info "No blocked users found"
        return 0
    fi

    echo "Blocked users:"
    echo "$blocked"
    echo ""

    # Get username
    read -p "Enter username to unblock: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi

    # Check if user exists and is blocked
    local is_blocked=$(jq -r ".users[] | select(.name == \"$username\") | .blocked // false" "$USERS_FILE")
    if [ "$is_blocked" != "true" ]; then
        print_error "User '$username' is not blocked"
        return 1
    fi

    # Update in users.json
    local tmp_file=$(mktemp)
    jq ".users = [.users[] | if .name == \"$username\" then .blocked = false else . end]" \
        "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    print_success "User '$username' unblocked"
}

# Main menu
main_menu() {
    while true; do
        print_header "VLESS User Manager"

        echo "1) Show user list"
        echo "2) Show detailed user list (with quotas)"
        echo "3) Add new user"
        echo "4) Remove user"
        echo "5) Export user configuration"
        echo "6) Manage user quotas"
        echo "7) Block user"
        echo "8) Unblock user"
        echo "9) Exit"
        echo ""
        read -p "Select option [1-9]: " choice

        case $choice in
            1)
                show_users
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                show_users "detailed"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                add_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                remove_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                show_user_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                manage_quotas
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
                block_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            8)
                unblock_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            9)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        clear
    done
}

# Check if running as root (only for operations that need it)
# Will check individually in functions that modify data

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    print_error "VLESS is not installed. Please run install.sh first."
    exit 1
fi

# Run main menu
main_menu
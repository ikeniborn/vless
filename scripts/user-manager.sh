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
elif [ -f "/opt/vless/scripts/lib/colors.sh" ]; then
    source "/opt/vless/scripts/lib/colors.sh"
    source "/opt/vless/scripts/lib/utils.sh"
    source "/opt/vless/scripts/lib/config.sh"
else
    echo "Error: Cannot find required library files" >&2
    echo "Please ensure VLESS is properly installed" >&2
    exit 1
fi

# User management functions
show_users() {
    print_header "User List"
    
    if [ ! -f "$USERS_FILE" ]; then
        print_error "Users file not found"
        return 1
    fi
    
    echo "Username         UUID                                    Short ID    Created"
    echo "--------------------------------------------------------------------------------"
    
    jq -r '.users[] | "\(.name)\t\(.uuid)\t\(.short_id)\t\(.created_at)"' "$USERS_FILE" | \
    while IFS=$'\t' read -r name uuid short_id created; do
        printf "%-15s  %-36s  %-10s  %s\n" "$name" "$uuid" "$short_id" "${created%%T*}"
    done
    
    echo ""
    local total=$(jq '.users | length' "$USERS_FILE")
    print_info "Total users: $total"
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
    
    # Generate UUID and Short ID
    local uuid=$(generate_uuid)
    local short_id=$(generate_short_id)
    
    print_info "Generated UUID: $uuid"
    print_info "Generated Short ID: $short_id"
    
    # Add to users.json
    local tmp_file=$(mktemp)
    jq ".users += [{\"name\": \"$username\", \"uuid\": \"$uuid\", \"short_id\": \"$short_id\", \"created_at\": \"$(date -Iseconds)\"}]" "$USERS_FILE" > "$tmp_file"
    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
    
    # Add to Xray config
    if add_user_to_config "$uuid" "$short_id"; then
        print_success "User added to configuration"
    else
        print_error "Failed to add user to configuration"
        return 1
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
    local short_id=$(echo "$user_data" | jq -r '.short_id')
    
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

# Main menu
main_menu() {
    while true; do
        print_header "VLESS User Manager"
        
        echo "1) Show user list"
        echo "2) Add new user"
        echo "3) Remove user"
        echo "4) Export user configuration"
        echo "5) Exit"
        echo ""
        read -p "Select option [1-5]: " choice
        
        case $choice in
            1)
                show_users
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                add_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                remove_user
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                show_user_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
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
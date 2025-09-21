#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - User Management Module
# ======================================================================================
# This module provides CRUD operations for VPN users with UUID management.
# Handles user creation, deletion, modification, and configuration generation.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# User management specific variables
readonly USER_DATABASE="${USER_DIR}/users.json"
readonly USER_CONFIGS_DIR="${USER_DIR}/configs"
readonly DEFAULT_PORT=443
readonly DEFAULT_FLOW="xtls-rprx-vision"

# ======================================================================================
# USER DATABASE FUNCTIONS
# ======================================================================================

# Function: init_user_database
# Description: Initialize the user database file
init_user_database() {
    log_info "Initializing user database..."

    # Create user directories
    create_directory "$USER_DIR" "700" "root:root"
    create_directory "$USER_CONFIGS_DIR" "700" "root:root"

    # Initialize empty JSON database if it doesn't exist
    if [[ ! -f "$USER_DATABASE" ]]; then
        echo '{"users": [], "metadata": {"created": "'$(date -Iseconds)'", "version": "1.0"}}' > "$USER_DATABASE"
        chmod 600 "$USER_DATABASE"
        chown root:root "$USER_DATABASE"
        log_success "User database initialized: $USER_DATABASE"
    else
        log_info "User database already exists: $USER_DATABASE"
    fi
}

# Function: get_user_count
# Description: Get the current number of users
# Returns: Number of users
get_user_count() {
    if [[ ! -f "$USER_DATABASE" ]]; then
        echo 0
        return
    fi

    python3 -c "
import json
try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)
    print(len(data.get('users', [])))
except Exception:
    print(0)
"
}

# Function: user_exists
# Description: Check if a user exists by username or UUID
# Parameters: $1 - username or UUID
# Returns: 0 if exists, 1 if not
user_exists() {
    local identifier="$1"

    if [[ ! -f "$USER_DATABASE" ]]; then
        return 1
    fi

    local exists=$(python3 -c "
import json
try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        if user.get('username') == '$identifier' or user.get('uuid') == '$identifier':
            print('true')
            exit()
    print('false')
except Exception:
    print('false')
")

    [[ "$exists" == "true" ]]
}

# ======================================================================================
# USER CRUD OPERATIONS
# ======================================================================================

# Function: add_user
# Description: Add a new user with unique UUID
# Parameters: $1 - username, $2 - email (optional), $3 - description (optional)
# Returns: 0 on success, 1 on failure
add_user() {
    local username="$1"
    local email="${2:-}"
    local description="${3:-VPN User}"

    # Validate username
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty"
        return 1
    fi

    # Check username format (alphanumeric, underscore, hyphen only)
    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid username format: $username (only alphanumeric, underscore, and hyphen allowed)"
        return 1
    fi

    # Check if user already exists
    if user_exists "$username"; then
        log_error "User already exists: $username"
        return 1
    fi

    # Generate unique UUID
    local uuid
    uuid=$(generate_uuid)
    if [[ -z "$uuid" ]]; then
        log_error "Failed to generate UUID for user: $username"
        return 1
    fi

    # Ensure UUID is unique
    while user_exists "$uuid"; do
        uuid=$(generate_uuid)
    done

    log_info "Adding user: $username (UUID: $uuid)"

    # Initialize database if needed
    init_user_database

    # Add user to database
    local created_date=$(date -Iseconds)
    python3 -c "
import json
import sys

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    new_user = {
        'username': '$username',
        'uuid': '$uuid',
        'email': '$email',
        'description': '$description',
        'created_date': '$created_date',
        'last_modified': '$created_date',
        'enabled': True,
        'statistics': {
            'total_connections': 0,
            'last_connection': None,
            'data_usage': 0
        }
    }

    data['users'].append(new_user)

    with open('$USER_DATABASE', 'w') as f:
        json.dump(data, f, indent=2)

    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"

    if [[ $? -eq 0 ]]; then
        log_success "User added successfully: $username"

        # Generate initial user configuration
        if generate_user_config "$username"; then
            log_success "User configuration generated for: $username"
        else
            log_warn "Failed to generate configuration for: $username"
        fi

        return 0
    else
        log_error "Failed to add user: $username"
        return 1
    fi
}

# Function: remove_user
# Description: Remove user and clean up configurations
# Parameters: $1 - username or UUID
# Returns: 0 on success, 1 on failure
remove_user() {
    local identifier="$1"

    if [[ -z "$identifier" ]]; then
        log_error "Username or UUID cannot be empty"
        return 1
    fi

    # Check if user exists
    if ! user_exists "$identifier"; then
        log_error "User does not exist: $identifier"
        return 1
    fi

    log_info "Removing user: $identifier"

    # Get username for cleanup
    local username
    username=$(get_user_info "$identifier" "username")

    # Remove user from database
    python3 -c "
import json
import sys

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    original_count = len(data['users'])
    data['users'] = [user for user in data['users']
                    if user.get('username') != '$identifier' and user.get('uuid') != '$identifier']

    if len(data['users']) == original_count:
        print('ERROR: User not found')
        sys.exit(1)

    with open('$USER_DATABASE', 'w') as f:
        json.dump(data, f, indent=2)

    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"

    if [[ $? -eq 0 ]]; then
        # Clean up user configuration files
        if [[ -n "$username" ]]; then
            rm -f "${USER_CONFIGS_DIR}/${username}"_*.{json,txt,png} 2>/dev/null || true
        fi

        log_success "User removed successfully: $identifier"
        return 0
    else
        log_error "Failed to remove user: $identifier"
        return 1
    fi
}

# Function: list_users
# Description: Display all users with statistics
# Parameters: $1 - format (table|json) default: table
list_users() {
    local format="${1:-table}"

    if [[ ! -f "$USER_DATABASE" ]]; then
        log_warn "No user database found"
        return 1
    fi

    local user_count
    user_count=$(get_user_count)

    if [[ $user_count -eq 0 ]]; then
        echo "No users found."
        return 0
    fi

    log_info "Total users: $user_count"

    if [[ "$format" == "json" ]]; then
        python3 -c "
import json
with open('$USER_DATABASE', 'r') as f:
    data = json.load(f)
print(json.dumps(data['users'], indent=2))
"
    else
        # Table format
        echo ""
        printf "%-20s %-36s %-15s %-20s %-10s\n" "USERNAME" "UUID" "EMAIL" "CREATED" "STATUS"
        printf "%-20s %-36s %-15s %-20s %-10s\n" "--------" "----" "-----" "-------" "------"

        python3 -c "
import json
from datetime import datetime

with open('$USER_DATABASE', 'r') as f:
    data = json.load(f)

for user in data.get('users', []):
    username = user.get('username', 'N/A')
    uuid = user.get('uuid', 'N/A')
    email = user.get('email', 'N/A')[:15]
    created = user.get('created_date', 'N/A')[:19].replace('T', ' ')
    status = 'Enabled' if user.get('enabled', False) else 'Disabled'

    print(f'{username:<20} {uuid:<36} {email:<15} {created:<20} {status:<10}')
"
        echo ""
    fi
}

# Function: get_user_info
# Description: Get specific information about a user
# Parameters: $1 - username or UUID, $2 - field name
# Returns: Field value
get_user_info() {
    local identifier="$1"
    local field="$2"

    if [[ ! -f "$USER_DATABASE" ]]; then
        return 1
    fi

    python3 -c "
import json
try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        if user.get('username') == '$identifier' or user.get('uuid') == '$identifier':
            print(user.get('$field', ''))
            exit()
except Exception:
    pass
"
}

# Function: update_user
# Description: Update user information
# Parameters: $1 - username or UUID, $2 - field, $3 - new value
# Returns: 0 on success, 1 on failure
update_user() {
    local identifier="$1"
    local field="$2"
    local new_value="$3"

    if ! user_exists "$identifier"; then
        log_error "User does not exist: $identifier"
        return 1
    fi

    log_info "Updating user $identifier: $field = $new_value"

    python3 -c "
import json
import sys
from datetime import datetime

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    for user in data['users']:
        if user.get('username') == '$identifier' or user.get('uuid') == '$identifier':
            user['$field'] = '$new_value'
            user['last_modified'] = datetime.now().isoformat()
            break
    else:
        print('ERROR: User not found')
        sys.exit(1)

    with open('$USER_DATABASE', 'w') as f:
        json.dump(data, f, indent=2)

    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"

    if [[ $? -eq 0 ]]; then
        log_success "User updated successfully: $identifier"
        return 0
    else
        log_error "Failed to update user: $identifier"
        return 1
    fi
}

# ======================================================================================
# CONFIGURATION GENERATION
# ======================================================================================

# Function: generate_user_config
# Description: Generate client configuration for a user
# Parameters: $1 - username or UUID, $2 - format (vless|json) default: vless
# Returns: 0 on success, 1 on failure
generate_user_config() {
    local identifier="$1"
    local format="${2:-vless}"

    if ! user_exists "$identifier"; then
        log_error "User does not exist: $identifier"
        return 1
    fi

    # Get user information
    local username uuid
    username=$(get_user_info "$identifier" "username")
    uuid=$(get_user_info "$identifier" "uuid")

    if [[ -z "$username" || -z "$uuid" ]]; then
        log_error "Failed to get user information for: $identifier"
        return 1
    fi

    # Get server public IP
    local server_ip
    server_ip=$(get_public_ip)
    if [[ -z "$server_ip" ]]; then
        log_error "Failed to determine server public IP"
        return 1
    fi

    local config_file="${USER_CONFIGS_DIR}/${username}_${format}.txt"

    case "$format" in
        "vless")
            # Generate VLESS URL
            local vless_url="vless://${uuid}@${server_ip}:${DEFAULT_PORT}?type=tcp&security=reality&pbk=&fp=chrome&sni=www.google.com&sid=&spx=%2F&flow=${DEFAULT_FLOW}#${username}"
            echo "$vless_url" > "$config_file"
            log_success "VLESS configuration generated: $config_file"
            ;;
        "json")
            # Generate JSON configuration
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
            "address": "${server_ip}",
            "port": ${DEFAULT_PORT},
            "users": [
              {
                "id": "${uuid}",
                "flow": "${DEFAULT_FLOW}"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "www.google.com",
          "fingerprint": "chrome"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "outboundTag": "proxy",
        "domain": [
          "geosite:geolocation-!cn"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": [
          "geosite:cn"
        ]
      }
    ]
  }
}
EOF
            log_success "JSON configuration generated: $config_file"
            ;;
        *)
            log_error "Unsupported configuration format: $format"
            return 1
            ;;
    esac

    chmod 600 "$config_file"
    chown root:root "$config_file"

    return 0
}

# Function: get_user_config
# Description: Display user configuration
# Parameters: $1 - username or UUID, $2 - format (vless|json) default: vless
get_user_config() {
    local identifier="$1"
    local format="${2:-vless}"

    if ! user_exists "$identifier"; then
        log_error "User does not exist: $identifier"
        return 1
    fi

    local username
    username=$(get_user_info "$identifier" "username")
    local config_file="${USER_CONFIGS_DIR}/${username}_${format}.txt"

    # Generate config if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        if ! generate_user_config "$identifier" "$format"; then
            log_error "Failed to generate configuration for: $identifier"
            return 1
        fi
    fi

    echo ""
    log_info "Configuration for user: $username (format: $format)"
    echo "----------------------------------------"
    cat "$config_file"
    echo "----------------------------------------"
    echo ""

    return 0
}

# ======================================================================================
# USER MANAGEMENT CLI INTERFACE
# ======================================================================================

# Function: show_user_menu
# Description: Display interactive user management menu
show_user_menu() {
    while true; do
        echo ""
        echo "=================================================="
        echo "        VLESS VPN User Management System"
        echo "=================================================="
        echo "1. Add User"
        echo "2. Remove User"
        echo "3. List Users"
        echo "4. Show User Configuration"
        echo "5. Generate QR Code"
        echo "6. Update User Information"
        echo "7. User Statistics"
        echo "8. Export User Data"
        echo "9. Back to Main Menu"
        echo "=================================================="
        echo -n "Select an option (1-9): "

        local choice
        read -r choice

        case "$choice" in
            1)
                echo -n "Enter username: "
                read -r username
                echo -n "Enter email (optional): "
                read -r email
                echo -n "Enter description (optional): "
                read -r description

                if add_user "$username" "$email" "$description"; then
                    echo ""
                    echo "User added successfully! Here's the configuration:"
                    get_user_config "$username"
                fi
                ;;
            2)
                echo -n "Enter username or UUID to remove: "
                read -r identifier
                echo -n "Are you sure you want to remove user '$identifier'? (y/N): "
                read -r confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    remove_user "$identifier"
                fi
                ;;
            3)
                list_users
                ;;
            4)
                echo -n "Enter username or UUID: "
                read -r identifier
                echo -n "Enter format (vless/json) [vless]: "
                read -r format
                format=${format:-vless}

                get_user_config "$identifier" "$format"
                ;;
            5)
                echo -n "Enter username or UUID: "
                read -r identifier

                if command -v python3 >/dev/null && python3 -c "import qrcode" 2>/dev/null; then
                    # Generate QR code using the Python module
                    local username
                    username=$(get_user_info "$identifier" "username")
                    if [[ -n "$username" ]]; then
                        python3 "${SCRIPT_DIR}/qr_generator.py" "$identifier"
                    fi
                else
                    log_error "QR code generation requires Python 3 and qrcode library"
                    echo "Install with: pip3 install qrcode[pil]"
                fi
                ;;
            6)
                echo -n "Enter username or UUID: "
                read -r identifier
                echo -n "Enter field to update (email/description): "
                read -r field
                echo -n "Enter new value: "
                read -r new_value

                update_user "$identifier" "$field" "$new_value"
                ;;
            7)
                echo "User Statistics:"
                echo "Total users: $(get_user_count)"
                echo ""
                list_users
                ;;
            8)
                echo "Exporting user data..."
                local export_file="/tmp/vless_users_$(date +%Y%m%d_%H%M%S).json"
                if [[ -f "$USER_DATABASE" ]]; then
                    cp "$USER_DATABASE" "$export_file"
                    log_success "User data exported to: $export_file"
                else
                    log_error "No user database found"
                fi
                ;;
            9)
                echo "Returning to main menu..."
                break
                ;;
            *)
                log_error "Invalid option. Please select 1-9."
                ;;
        esac

        echo ""
        echo "Press Enter to continue..."
        read -r
    done
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Main function for direct script execution
main() {
    log_info "VLESS User Management System"

    # Validate root privileges
    validate_root

    # Initialize user database
    init_user_database

    # Handle command line arguments
    case "${1:-menu}" in
        "add")
            shift
            add_user "$@"
            ;;
        "remove")
            shift
            remove_user "$@"
            ;;
        "list")
            shift
            list_users "$@"
            ;;
        "config")
            shift
            get_user_config "$@"
            ;;
        "update")
            shift
            update_user "$@"
            ;;
        "menu")
            show_user_menu
            ;;
        *)
            echo "Usage: $0 {add|remove|list|config|update|menu}"
            echo ""
            echo "Commands:"
            echo "  add <username> [email] [description]  - Add a new user"
            echo "  remove <username|uuid>               - Remove a user"
            echo "  list [table|json]                    - List all users"
            echo "  config <username|uuid> [vless|json]  - Show user configuration"
            echo "  update <username|uuid> <field> <value> - Update user information"
            echo "  menu                                 - Interactive menu"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
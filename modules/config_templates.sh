#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Configuration Templates Module
# ======================================================================================
# This module provides templates for different VPN client applications and
# configuration export functionality in multiple formats.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration templates specific variables
readonly TEMPLATES_DIR="${CONFIG_DIR}/templates"
readonly EXPORT_DIR="${USER_DIR}/exports"
readonly DEFAULT_PORT=443
readonly DEFAULT_FLOW="xtls-rprx-vision"
readonly DEFAULT_SNI="www.google.com"
readonly DEFAULT_FINGERPRINT="chrome"

# ======================================================================================
# INITIALIZATION FUNCTIONS
# ======================================================================================

# Function: init_config_templates
# Description: Initialize configuration templates system
init_config_templates() {
    log_info "Initializing configuration templates system..."

    # Create necessary directories
    create_directory "$TEMPLATES_DIR" "700" "root:root"
    create_directory "$EXPORT_DIR" "700" "root:root"

    # Create template files
    create_xray_client_template
    create_v2ray_client_template
    create_clash_template
    create_sing_box_template

    log_success "Configuration templates system initialized"
}

# ======================================================================================
# TEMPLATE CREATION FUNCTIONS
# ======================================================================================

# Function: create_xray_client_template
# Description: Create Xray client configuration template
create_xray_client_template() {
    local template_file="${TEMPLATES_DIR}/xray_client_template.json"

    cat > "$template_file" << 'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "udp": true,
        "auth": "noauth"
      },
      "tag": "socks-in"
    },
    {
      "port": 10809,
      "protocol": "http",
      "settings": {},
      "tag": "http-in"
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "{{SERVER_IP}}",
            "port": {{SERVER_PORT}},
            "users": [
              {
                "id": "{{USER_UUID}}",
                "flow": "{{FLOW}}",
                "encryption": "none"
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
          "dest": "{{SNI}}:443",
          "xver": 0,
          "serverNames": [
            "{{SNI}}"
          ],
          "privateKey": "",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            ""
          ],
          "fingerprint": "{{FINGERPRINT}}"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn",
          "geoip:private"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "outboundTag": "proxy",
        "network": "tcp,udp"
      }
    ]
  }
}
EOF

    chmod 600 "$template_file"
    log_debug "Created Xray client template: $template_file"
}

# Function: create_v2ray_client_template
# Description: Create V2Ray client configuration template
create_v2ray_client_template() {
    local template_file="${TEMPLATES_DIR}/v2ray_client_template.json"

    cat > "$template_file" << 'EOF'
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
    },
    {
      "port": 1081,
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "{{SERVER_IP}}",
            "port": {{SERVER_PORT}},
            "users": [
              {
                "id": "{{USER_UUID}}",
                "flow": "{{FLOW}}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "{{SNI}}",
          "fingerprint": "{{FINGERPRINT}}"
        }
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": [
          "geosite:cn"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "ip": [
          "geoip:cn",
          "geoip:private"
        ]
      }
    ]
  }
}
EOF

    chmod 600 "$template_file"
    log_debug "Created V2Ray client template: $template_file"
}

# Function: create_clash_template
# Description: Create Clash client configuration template
create_clash_template() {
    local template_file="${TEMPLATES_DIR}/clash_template.yaml"

    cat > "$template_file" << 'EOF'
port: 7890
socks-port: 7891
allow-lan: false
mode: Rule
log-level: info
ipv6: true
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:53
  ipv6: false
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query

proxies:
  - name: "{{USERNAME}}-VLESS"
    type: vless
    server: {{SERVER_IP}}
    port: {{SERVER_PORT}}
    uuid: {{USER_UUID}}
    network: tcp
    tls: true
    udp: true
    flow: {{FLOW}}
    client-fingerprint: {{FINGERPRINT}}
    reality-opts:
      public-key: ""
      short-id: ""
    servername: {{SNI}}

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "{{USERNAME}}-VLESS"
      - DIRECT

  - name: "Auto"
    type: url-test
    proxies:
      - "{{USERNAME}}-VLESS"
    url: 'http://www.gstatic.com/generate_204'
    interval: 300

rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF

    chmod 600 "$template_file"
    log_debug "Created Clash client template: $template_file"
}

# Function: create_sing_box_template
# Description: Create sing-box client configuration template
create_sing_box_template() {
    local template_file="${TEMPLATES_DIR}/sing_box_template.json"

    cat > "$template_file" << 'EOF'
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "geosite": "cn",
        "server": "local"
      }
    ]
  },
  "inbounds": [
    {
      "type": "mixed",
      "listen": "::",
      "listen_port": 2080,
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "{{SERVER_IP}}",
      "server_port": {{SERVER_PORT}},
      "uuid": "{{USER_UUID}}",
      "flow": "{{FLOW}}",
      "tls": {
        "enabled": true,
        "server_name": "{{SNI}}",
        "utls": {
          "enabled": true,
          "fingerprint": "{{FINGERPRINT}}"
        },
        "reality": {
          "enabled": true,
          "public_key": "",
          "short_id": ""
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "geoip": {
      "download_url": "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db",
      "download_detour": "direct"
    },
    "geosite": {
      "download_url": "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db",
      "download_detour": "direct"
    },
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geosite": "cn",
        "geoip": "cn",
        "outbound": "direct"
      }
    ],
    "final": "proxy"
  }
}
EOF

    chmod 600 "$template_file"
    log_debug "Created sing-box client template: $template_file"
}

# ======================================================================================
# CONFIGURATION GENERATION FUNCTIONS
# ======================================================================================

# Function: substitute_template_variables
# Description: Replace template variables with actual values
# Parameters: $1 - template content, $2 - server_ip, $3 - user_uuid, $4 - username
substitute_template_variables() {
    local template_content="$1"
    local server_ip="$2"
    local user_uuid="$3"
    local username="$4"
    local server_port="${5:-$DEFAULT_PORT}"
    local flow="${6:-$DEFAULT_FLOW}"
    local sni="${7:-$DEFAULT_SNI}"
    local fingerprint="${8:-$DEFAULT_FINGERPRINT}"

    # Replace all template variables
    echo "$template_content" | sed \
        -e "s/{{SERVER_IP}}/$server_ip/g" \
        -e "s/{{SERVER_PORT}}/$server_port/g" \
        -e "s/{{USER_UUID}}/$user_uuid/g" \
        -e "s/{{USERNAME}}/$username/g" \
        -e "s/{{FLOW}}/$flow/g" \
        -e "s/{{SNI}}/$sni/g" \
        -e "s/{{FINGERPRINT}}/$fingerprint/g"
}

# Function: generate_vless_url
# Description: Generate VLESS connection URL
# Parameters: $1 - server_ip, $2 - user_uuid, $3 - username
generate_vless_url() {
    local server_ip="$1"
    local user_uuid="$2"
    local username="$3"
    local server_port="${4:-$DEFAULT_PORT}"
    local flow="${5:-$DEFAULT_FLOW}"
    local sni="${6:-$DEFAULT_SNI}"
    local fingerprint="${7:-$DEFAULT_FINGERPRINT}"

    echo "vless://${user_uuid}@${server_ip}:${server_port}?type=tcp&security=reality&pbk=&fp=${fingerprint}&sni=${sni}&sid=&spx=%2F&flow=${flow}#${username}"
}

# Function: generate_config_for_user
# Description: Generate configuration for a specific user and client type
# Parameters: $1 - username or UUID, $2 - client type (xray|v2ray|clash|sing-box|vless-url)
generate_config_for_user() {
    local identifier="$1"
    local client_type="$2"

    # Validate client type
    case "$client_type" in
        "xray"|"v2ray"|"clash"|"sing-box"|"vless-url") ;;
        *)
            log_error "Unsupported client type: $client_type"
            log_info "Supported types: xray, v2ray, clash, sing-box, vless-url"
            return 1
            ;;
    esac

    # Get user information from user management module
    if ! command -v python3 >/dev/null; then
        log_error "Python 3 is required for user data processing"
        return 1
    fi

    # Check if user database exists
    local user_database="${USER_DIR}/users.json"
    if [[ ! -f "$user_database" ]]; then
        log_error "User database not found: $user_database"
        return 1
    fi

    # Get user data
    local user_data
    user_data=$(python3 -c "
import json
try:
    with open('$user_database', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        if user.get('username') == '$identifier' or user.get('uuid') == '$identifier':
            print(json.dumps(user))
            exit()
    print('USER_NOT_FOUND')
except Exception as e:
    print(f'ERROR: {e}')
")

    if [[ "$user_data" == "USER_NOT_FOUND" ]]; then
        log_error "User not found: $identifier"
        return 1
    elif [[ "$user_data" == ERROR* ]]; then
        log_error "Failed to read user data: $user_data"
        return 1
    fi

    # Extract user information
    local username user_uuid
    username=$(echo "$user_data" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('username', ''))")
    user_uuid=$(echo "$user_data" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('uuid', ''))")

    if [[ -z "$username" || -z "$user_uuid" ]]; then
        log_error "Invalid user data for: $identifier"
        return 1
    fi

    # Get server public IP
    local server_ip
    server_ip=$(get_public_ip)
    if [[ -z "$server_ip" ]]; then
        log_error "Failed to determine server public IP"
        return 1
    fi

    log_info "Generating $client_type configuration for user: $username"

    # Create export directory for this user
    local user_export_dir="${EXPORT_DIR}/${username}"
    create_directory "$user_export_dir" "700" "root:root"

    local output_file="${user_export_dir}/${username}_${client_type}_$(date +%Y%m%d_%H%M%S)"

    case "$client_type" in
        "vless-url")
            output_file="${output_file}.txt"
            generate_vless_url "$server_ip" "$user_uuid" "$username" > "$output_file"
            ;;
        "xray")
            output_file="${output_file}.json"
            local template_content
            template_content=$(cat "${TEMPLATES_DIR}/xray_client_template.json")
            substitute_template_variables "$template_content" "$server_ip" "$user_uuid" "$username" > "$output_file"
            ;;
        "v2ray")
            output_file="${output_file}.json"
            local template_content
            template_content=$(cat "${TEMPLATES_DIR}/v2ray_client_template.json")
            substitute_template_variables "$template_content" "$server_ip" "$user_uuid" "$username" > "$output_file"
            ;;
        "clash")
            output_file="${output_file}.yaml"
            local template_content
            template_content=$(cat "${TEMPLATES_DIR}/clash_template.yaml")
            substitute_template_variables "$template_content" "$server_ip" "$user_uuid" "$username" > "$output_file"
            ;;
        "sing-box")
            output_file="${output_file}.json"
            local template_content
            template_content=$(cat "${TEMPLATES_DIR}/sing_box_template.json")
            substitute_template_variables "$template_content" "$server_ip" "$user_uuid" "$username" > "$output_file"
            ;;
    esac

    # Set proper permissions
    chmod 600 "$output_file"
    chown root:root "$output_file"

    log_success "Configuration generated: $output_file"
    echo "Configuration file: $output_file"

    return 0
}

# Function: export_all_user_configs
# Description: Export configurations for all users in specified format
# Parameters: $1 - client type
export_all_user_configs() {
    local client_type="$1"

    local user_database="${USER_DIR}/users.json"
    if [[ ! -f "$user_database" ]]; then
        log_error "User database not found: $user_database"
        return 1
    fi

    # Get list of all users
    local usernames
    usernames=$(python3 -c "
import json
try:
    with open('$user_database', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        print(user.get('username', ''))
except Exception:
    pass
")

    if [[ -z "$usernames" ]]; then
        log_warn "No users found in database"
        return 1
    fi

    local success_count=0
    local total_count=0

    log_info "Exporting $client_type configurations for all users..."

    while IFS= read -r username; do
        [[ -z "$username" ]] && continue
        ((total_count++))

        if generate_config_for_user "$username" "$client_type"; then
            ((success_count++))
        else
            log_error "Failed to generate configuration for user: $username"
        fi
    done <<< "$usernames"

    log_info "Export completed: $success_count/$total_count configurations generated"
    return 0
}

# ======================================================================================
# CONFIGURATION DISPLAY FUNCTIONS
# ======================================================================================

# Function: display_config_for_user
# Description: Display configuration content for a user
# Parameters: $1 - username or UUID, $2 - client type
display_config_for_user() {
    local identifier="$1"
    local client_type="$2"

    # Generate config to temporary location
    local temp_export_dir="${EXPORT_DIR}"
    local original_export_dir="$EXPORT_DIR"

    if generate_config_for_user "$identifier" "$client_type"; then
        # Find the most recent config file for this user and type
        local username
        username=$(python3 -c "
import json
try:
    with open('${USER_DIR}/users.json', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        if user.get('username') == '$identifier' or user.get('uuid') == '$identifier':
            print(user.get('username', ''))
            exit()
except Exception:
    pass
")

        local config_file
        config_file=$(find "${EXPORT_DIR}/${username}" -name "*_${client_type}_*" -type f | sort | tail -1)

        if [[ -f "$config_file" ]]; then
            echo ""
            log_info "Configuration for user: $username (type: $client_type)"
            echo "========================================================"
            cat "$config_file"
            echo "========================================================"
            echo "Configuration file: $config_file"
            echo ""
        else
            log_error "Configuration file not found"
            return 1
        fi
    else
        return 1
    fi
}

# ======================================================================================
# MAIN CLI INTERFACE
# ======================================================================================

# Function: show_config_menu
# Description: Interactive configuration management menu
show_config_menu() {
    while true; do
        echo ""
        echo "=================================================="
        echo "      VLESS Configuration Templates Manager"
        echo "=================================================="
        echo "1. Generate User Configuration"
        echo "2. Display User Configuration"
        echo "3. Export All User Configurations"
        echo "4. List Available Templates"
        echo "5. Regenerate Templates"
        echo "6. Back to Main Menu"
        echo "=================================================="
        echo -n "Select an option (1-6): "

        local choice
        read -r choice

        case "$choice" in
            1)
                echo -n "Enter username or UUID: "
                read -r identifier
                echo "Available client types:"
                echo "  1) xray      - Xray client configuration"
                echo "  2) v2ray     - V2Ray client configuration"
                echo "  3) clash     - Clash client configuration"
                echo "  4) sing-box  - sing-box client configuration"
                echo "  5) vless-url - VLESS URL for mobile apps"
                echo -n "Select client type (1-5): "
                read -r type_choice

                local client_type
                case "$type_choice" in
                    1) client_type="xray" ;;
                    2) client_type="v2ray" ;;
                    3) client_type="clash" ;;
                    4) client_type="sing-box" ;;
                    5) client_type="vless-url" ;;
                    *) log_error "Invalid choice"; continue ;;
                esac

                generate_config_for_user "$identifier" "$client_type"
                ;;
            2)
                echo -n "Enter username or UUID: "
                read -r identifier
                echo "Available client types:"
                echo "  1) xray      2) v2ray     3) clash     4) sing-box     5) vless-url"
                echo -n "Select client type (1-5): "
                read -r type_choice

                local client_type
                case "$type_choice" in
                    1) client_type="xray" ;;
                    2) client_type="v2ray" ;;
                    3) client_type="clash" ;;
                    4) client_type="sing-box" ;;
                    5) client_type="vless-url" ;;
                    *) log_error "Invalid choice"; continue ;;
                esac

                display_config_for_user "$identifier" "$client_type"
                ;;
            3)
                echo "Available client types:"
                echo "  1) xray      2) v2ray     3) clash     4) sing-box     5) vless-url"
                echo -n "Select client type for batch export (1-5): "
                read -r type_choice

                local client_type
                case "$type_choice" in
                    1) client_type="xray" ;;
                    2) client_type="v2ray" ;;
                    3) client_type="clash" ;;
                    4) client_type="sing-box" ;;
                    5) client_type="vless-url" ;;
                    *) log_error "Invalid choice"; continue ;;
                esac

                export_all_user_configs "$client_type"
                ;;
            4)
                echo ""
                echo "Available Templates:"
                echo "==================="
                if [[ -d "$TEMPLATES_DIR" ]]; then
                    ls -la "$TEMPLATES_DIR"
                else
                    echo "Templates directory not found"
                fi
                ;;
            5)
                echo "Regenerating templates..."
                init_config_templates
                ;;
            6)
                echo "Returning to main menu..."
                break
                ;;
            *)
                log_error "Invalid option. Please select 1-6."
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
    log_info "VLESS Configuration Templates Manager"

    # Validate root privileges
    validate_root

    # Initialize templates system
    init_config_templates

    # Handle command line arguments
    case "${1:-menu}" in
        "generate")
            shift
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 generate <username|uuid> <client_type>"
                echo "Client types: xray, v2ray, clash, sing-box, vless-url"
                exit 1
            fi
            generate_config_for_user "$1" "$2"
            ;;
        "display")
            shift
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 display <username|uuid> <client_type>"
                exit 1
            fi
            display_config_for_user "$1" "$2"
            ;;
        "export-all")
            shift
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 export-all <client_type>"
                exit 1
            fi
            export_all_user_configs "$1"
            ;;
        "init")
            init_config_templates
            ;;
        "menu")
            show_config_menu
            ;;
        *)
            echo "Usage: $0 {generate|display|export-all|init|menu}"
            echo ""
            echo "Commands:"
            echo "  generate <user> <type>    - Generate configuration for specific user"
            echo "  display <user> <type>     - Display configuration for specific user"
            echo "  export-all <type>         - Export configurations for all users"
            echo "  init                      - Initialize/regenerate templates"
            echo "  menu                      - Interactive menu"
            echo ""
            echo "Client types: xray, v2ray, clash, sing-box, vless-url"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
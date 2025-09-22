#!/bin/bash

# VLESS+Reality VPN Management System - Configuration Templates Module
# Version: 1.0.0
# Description: Generate Xray-core configuration with Reality support
#
# This module provides:
# - VLESS inbound configuration with Reality
# - SNI-based traffic routing
# - Fallback configuration for unrecognized traffic
# - UUID generation for server keys
# - Dynamic port configuration
# - Log level and file configuration

set -euo pipefail

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Default configuration values
readonly DEFAULT_VLESS_PORT=443
readonly DEFAULT_FALLBACK_PORT=80
readonly DEFAULT_LOG_LEVEL="warning"
readonly DEFAULT_SNI_DOMAINS=("www.microsoft.com" "www.google.com" "www.cloudflare.com")

# Configuration directories
readonly SYSTEM_CONFIG_DIR="/opt/vless/config"
readonly PROJECT_CONFIG_DIR="${SCRIPT_DIR}/../config"

# Generate X25519 key pair for Reality
generate_reality_keypair() {
    log_debug "Generating X25519 key pair for Reality..."

    # Use Xray to generate keys if available, otherwise use openssl
    if command_exists xray; then
        local output
        output=$(xray x25519 2>/dev/null) || {
            log_error "Failed to generate Reality keys with xray"
            return 1
        }

        local private_key
        local public_key
        private_key=$(echo "$output" | grep "Private key:" | cut -d' ' -f3)
        public_key=$(echo "$output" | grep "Public key:" | cut -d' ' -f3)

        echo "PRIVATE_KEY=$private_key"
        echo "PUBLIC_KEY=$public_key"
    else
        # Fallback to openssl if xray is not available
        if command_exists openssl; then
            local private_key
            local public_key
            private_key=$(openssl rand -base64 32 | tr -d '=' | tr '/+' '_-' | cut -c1-43)
            public_key=$(openssl rand -base64 32 | tr -d '=' | tr '/+' '_-' | cut -c1-43)

            log_warn "Using fallback key generation (install xray for proper keys)"
            echo "PRIVATE_KEY=$private_key"
            echo "PUBLIC_KEY=$public_key"
        else
            log_error "Neither xray nor openssl available for key generation"
            return 1
        fi
    fi
}

# Generate short ID for Reality
generate_short_id() {
    local length="${1:-8}"  # Default length 8, can be 2-16

    # Validate length
    if [[ $length -lt 2 || $length -gt 16 ]]; then
        log_error "Short ID length must be between 2 and 16"
        return 1
    fi

    # Generate random hex string
    openssl rand -hex $((length / 2)) 2>/dev/null || \
    python3 -c "import secrets; print(secrets.token_hex($((length / 2))))" 2>/dev/null || \
    xxd -l $((length / 2)) -p /dev/urandom | tr -d '\n'
}

# Get server's external IP
get_server_ip() {
    local ip
    ip=$(get_external_ip)

    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        # Fallback to local IP detection
        ip=$(ip route get 8.8.8.8 | awk '/src/ {print $7; exit}' 2>/dev/null) || \
        ip=$(hostname -I | awk '{print $1}' 2>/dev/null) || \
        echo "127.0.0.1"

        log_warn "Using detected local IP: $ip"
        echo "$ip"
    fi
}

# Validate domain name
validate_domain() {
    local domain="$1"
    local domain_pattern='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'

    if [[ $domain =~ $domain_pattern ]] && [[ ${#domain} -le 253 ]]; then
        return 0
    else
        return 1
    fi
}

# Test domain TLS connectivity
test_domain_tls() {
    local domain="$1"
    local port="${2:-443}"

    log_debug "Testing TLS connectivity to $domain:$port"

    if timeout 10 openssl s_client -connect "$domain:$port" -servername "$domain" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        log_debug "TLS test successful for $domain"
        return 0
    else
        log_warn "TLS test failed for $domain"
        return 1
    fi
}

# Select best SNI domain
select_sni_domain() {
    local domains=("$@")
    local best_domain=""

    log_info "Testing SNI domains for best connectivity..."

    for domain in "${domains[@]}"; do
        if validate_domain "$domain" && test_domain_tls "$domain"; then
            best_domain="$domain"
            log_success "Selected SNI domain: $domain"
            break
        fi
    done

    if [[ -z "$best_domain" ]]; then
        # Fallback to first domain without testing
        best_domain="${domains[0]}"
        log_warn "Using fallback SNI domain: $best_domain"
    fi

    echo "$best_domain"
}

# Generate Xray configuration
generate_xray_config() {
    local config_file="$1"
    local vless_port="${2:-$DEFAULT_VLESS_PORT}"
    local fallback_port="${3:-$DEFAULT_FALLBACK_PORT}"
    local log_level="${4:-$DEFAULT_LOG_LEVEL}"
    local custom_domains=("${@:5}")

    log_info "Generating Xray configuration: $config_file"

    # Use custom domains or default
    local sni_domains=("${custom_domains[@]:-${DEFAULT_SNI_DOMAINS[@]}}")

    # Generate server keys
    local keys_output
    keys_output=$(generate_reality_keypair) || {
        log_error "Failed to generate Reality keys"
        return 1
    }

    local private_key
    local public_key
    private_key=$(echo "$keys_output" | grep "PRIVATE_KEY=" | cut -d'=' -f2)
    public_key=$(echo "$keys_output" | grep "PUBLIC_KEY=" | cut -d'=' -f2)

    # Generate short IDs
    local short_id
    short_id=$(generate_short_id 8)

    # Select SNI domain
    local sni_domain
    sni_domain=$(select_sni_domain "${sni_domains[@]}")

    # Get server IP
    local server_ip
    server_ip=$(get_server_ip)

    # Create configuration directory
    create_directory "$(dirname "$config_file")" "755"

    # Generate configuration
    cat > "$config_file" << EOF
{
  "log": {
    "loglevel": "$log_level",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": $vless_port,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "$fallback_port",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$sni_domain:443",
          "xver": 0,
          "serverNames": [
            "$sni_domain"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      }
    },
    {
      "tag": "fallback-http",
      "port": $fallback_port,
      "protocol": "http",
      "settings": {
        "timeout": 300,
        "accounts": []
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    # Set secure permissions
    chmod 600 "$config_file"

    # Save configuration metadata
    local meta_file="${config_file}.meta"
    cat > "$meta_file" << EOF
# Xray Configuration Metadata
# Generated: $(date)
# Server IP: $server_ip
# VLESS Port: $vless_port
# Fallback Port: $fallback_port
# SNI Domain: $sni_domain
# Public Key: $public_key
# Short ID: $short_id
EOF

    chmod 600 "$meta_file"

    log_success "Xray configuration generated successfully"
    log_info "Configuration file: $config_file"
    log_info "Metadata file: $meta_file"
    log_info "Server IP: $server_ip"
    log_info "Public Key: $public_key"
    log_info "Short ID: $short_id"
    log_info "SNI Domain: $sni_domain"

    return 0
}

# Add user to Xray configuration
add_user_to_config() {
    local config_file="$1"
    local user_uuid="$2"
    local user_email="${3:-user@example.com}"
    local user_flow="${4:-}"

    validate_not_empty "$config_file" "config_file"
    validate_not_empty "$user_uuid" "user_uuid"

    if ! validate_uuid "$user_uuid"; then
        log_error "Invalid UUID format: $user_uuid"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    log_info "Adding user to configuration: $user_email ($user_uuid)"

    # Backup current configuration
    local backup_file
    backup_file=$(backup_file "$config_file")

    # Create user object
    local user_config
    if [[ -n "$user_flow" ]]; then
        user_config=$(cat << EOF
{
  "id": "$user_uuid",
  "email": "$user_email",
  "flow": "$user_flow"
}
EOF
)
    else
        user_config=$(cat << EOF
{
  "id": "$user_uuid",
  "email": "$user_email"
}
EOF
)
    fi

    # Add user to clients array using jq
    if command_exists jq; then
        local temp_file
        temp_file=$(mktemp)

        if jq --argjson user "$user_config" \
           '.inbounds[0].settings.clients += [$user]' \
           "$config_file" > "$temp_file"; then
            mv "$temp_file" "$config_file"
            chmod 600 "$config_file"
            log_success "User added to configuration successfully"
        else
            log_error "Failed to add user to configuration"
            restore_file "$backup_file"
            return 1
        fi
    else
        log_error "jq is required for configuration management"
        return 1
    fi

    return 0
}

# Remove user from Xray configuration
remove_user_from_config() {
    local config_file="$1"
    local user_uuid="$2"

    validate_not_empty "$config_file" "config_file"
    validate_not_empty "$user_uuid" "user_uuid"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    log_info "Removing user from configuration: $user_uuid"

    # Backup current configuration
    local backup_file
    backup_file=$(backup_file "$config_file")

    # Remove user from clients array using jq
    if command_exists jq; then
        local temp_file
        temp_file=$(mktemp)

        if jq --arg uuid "$user_uuid" \
           '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != $uuid)]' \
           "$config_file" > "$temp_file"; then
            mv "$temp_file" "$config_file"
            chmod 600 "$config_file"
            log_success "User removed from configuration successfully"
        else
            log_error "Failed to remove user from configuration"
            restore_file "$backup_file"
            return 1
        fi
    else
        log_error "jq is required for configuration management"
        return 1
    fi

    return 0
}

# List users in Xray configuration
list_users_in_config() {
    local config_file="$1"

    validate_not_empty "$config_file" "config_file"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    if command_exists jq; then
        log_info "Users in configuration:"
        jq -r '.inbounds[0].settings.clients[] | "\(.email) (\(.id))"' "$config_file" 2>/dev/null || {
            log_warn "No users found or configuration format error"
            return 1
        }
    else
        log_error "jq is required for configuration management"
        return 1
    fi

    return 0
}

# Validate Xray configuration
validate_xray_config() {
    local config_file="$1"

    validate_not_empty "$config_file" "config_file"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    log_info "Validating Xray configuration: $config_file"

    # Check JSON syntax
    if command_exists jq; then
        if ! jq empty "$config_file" 2>/dev/null; then
            log_error "Invalid JSON syntax in configuration file"
            return 1
        fi
    else
        # Fallback to Python for JSON validation
        if ! python3 -m json.tool "$config_file" >/dev/null 2>&1; then
            log_error "Invalid JSON syntax in configuration file"
            return 1
        fi
    fi

    # Test with xray if available
    if command_exists xray; then
        if xray test -c "$config_file" >/dev/null 2>&1; then
            log_success "Xray configuration validation passed"
        else
            log_error "Xray configuration validation failed"
            return 1
        fi
    else
        log_warn "xray not available for full validation (JSON syntax OK)"
    fi

    return 0
}

# Get configuration information
get_config_info() {
    local config_file="$1"
    local meta_file="${config_file}.meta"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    echo "=== Xray Configuration Information ==="
    echo "Config File: $config_file"
    echo "File Size: $(stat -c%s "$config_file" 2>/dev/null || echo "unknown") bytes"
    echo "Last Modified: $(stat -c%y "$config_file" 2>/dev/null || echo "unknown")"
    echo

    # Show metadata if available
    if [[ -f "$meta_file" ]]; then
        echo "=== Configuration Metadata ==="
        grep -v "^#" "$meta_file" 2>/dev/null || echo "No metadata available"
        echo
    fi

    # Show user count
    if command_exists jq; then
        local user_count
        user_count=$(jq '.inbounds[0].settings.clients | length' "$config_file" 2>/dev/null || echo "0")
        echo "Active Users: $user_count"
        echo
    fi

    # Show port configuration
    if command_exists jq; then
        echo "=== Port Configuration ==="
        jq -r '.inbounds[] | "Protocol: \(.protocol), Port: \(.port), Tag: \(.tag)"' "$config_file" 2>/dev/null
        echo
    fi
}

# Create default Xray configuration template
create_default_config() {
    local output_file="${1:-${PROJECT_CONFIG_DIR}/xray_config_template.json}"

    log_info "Creating default Xray configuration template: $output_file"

    # Create directory if it doesn't exist
    create_directory "$(dirname "$output_file")" "755"

    # Generate configuration with default values
    generate_xray_config "$output_file" "$DEFAULT_VLESS_PORT" "$DEFAULT_FALLBACK_PORT" "$DEFAULT_LOG_LEVEL" "${DEFAULT_SNI_DOMAINS[@]}"

    log_success "Default configuration template created: $output_file"
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN Configuration Templates Module

Usage: $0 [OPTIONS]

Options:
    --generate FILE         Generate new Xray configuration
    --port PORT            VLESS port (default: $DEFAULT_VLESS_PORT)
    --fallback-port PORT   Fallback port (default: $DEFAULT_FALLBACK_PORT)
    --log-level LEVEL      Log level (default: $DEFAULT_LOG_LEVEL)
    --sni-domain DOMAIN    SNI domain (can be used multiple times)
    --add-user CONFIG UUID EMAIL   Add user to configuration
    --remove-user CONFIG UUID      Remove user from configuration
    --list-users CONFIG           List users in configuration
    --validate CONFIG             Validate configuration
    --info CONFIG                Show configuration information
    --create-template             Create default template
    --help                       Show this help message

Examples:
    $0 --generate /opt/vless/config/config.json
    $0 --generate config.json --port 8443 --sni-domain example.com
    $0 --add-user config.json "$(uuidgen)" "user@example.com"
    $0 --validate config.json
    $0 --create-template

EOF
}

# Main execution
main() {
    local action=""
    local config_file=""
    local vless_port="$DEFAULT_VLESS_PORT"
    local fallback_port="$DEFAULT_FALLBACK_PORT"
    local log_level="$DEFAULT_LOG_LEVEL"
    local sni_domains=()
    local user_uuid=""
    local user_email=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --generate)
                action="generate"
                config_file="$2"
                shift 2
                ;;
            --port)
                vless_port="$2"
                shift 2
                ;;
            --fallback-port)
                fallback_port="$2"
                shift 2
                ;;
            --log-level)
                log_level="$2"
                shift 2
                ;;
            --sni-domain)
                sni_domains+=("$2")
                shift 2
                ;;
            --add-user)
                action="add-user"
                config_file="$2"
                user_uuid="$3"
                user_email="$4"
                shift 4
                ;;
            --remove-user)
                action="remove-user"
                config_file="$2"
                user_uuid="$3"
                shift 3
                ;;
            --list-users)
                action="list-users"
                config_file="$2"
                shift 2
                ;;
            --validate)
                action="validate"
                config_file="$2"
                shift 2
                ;;
            --info)
                action="info"
                config_file="$2"
                shift 2
                ;;
            --create-template)
                action="create-template"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Setup signal handlers for process isolation
    setup_signal_handlers

    # Install required packages
    install_package_if_missing "jq"

    # Execute requested action
    case "$action" in
        "generate")
            validate_not_empty "$config_file" "config_file"
            if validate_port "$vless_port" && validate_port "$fallback_port"; then
                generate_xray_config "$config_file" "$vless_port" "$fallback_port" "$log_level" "${sni_domains[@]}"
            else
                log_error "Invalid port configuration"
                exit 1
            fi
            ;;
        "add-user")
            validate_not_empty "$config_file" "config_file"
            validate_not_empty "$user_uuid" "user_uuid"
            validate_not_empty "$user_email" "user_email"
            add_user_to_config "$config_file" "$user_uuid" "$user_email"
            ;;
        "remove-user")
            validate_not_empty "$config_file" "config_file"
            validate_not_empty "$user_uuid" "user_uuid"
            remove_user_from_config "$config_file" "$user_uuid"
            ;;
        "list-users")
            validate_not_empty "$config_file" "config_file"
            list_users_in_config "$config_file"
            ;;
        "validate")
            validate_not_empty "$config_file" "config_file"
            validate_xray_config "$config_file"
            ;;
        "info")
            validate_not_empty "$config_file" "config_file"
            get_config_info "$config_file"
            ;;
        "create-template")
            create_default_config
            ;;
        "")
            log_error "No action specified"
            show_help
            exit 1
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
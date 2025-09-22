#!/bin/bash

# VLESS+Reality VPN Management System - User Management Module
# Version: 1.0.0
# Description: High-level user management interface
#
# This module provides:
# - Add user with automatic UUID generation
# - Remove user with cleanup
# - List users with statistics
# - User search and filtering
# - Bulk user operations
# - Client configuration generation

set -euo pipefail

# Import common utilities and dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"
source "${SCRIPT_DIR}/user_database.sh"

# Configuration files
readonly XRAY_CONFIG_FILE="/opt/vless/config/config.json"
readonly PROJECT_XRAY_CONFIG="${SCRIPT_DIR}/../config/xray_config_template.json"
readonly DEFAULT_DB_FILE="/opt/vless/users/users.json"

# User management operations

# Add new user with automatic configuration
add_user() {
    local user_email="$1"
    local user_name="${2:-}"
    local user_flow="${3:-}"
    local auto_uuid="${4:-true}"
    local custom_uuid="${5:-}"

    validate_not_empty "$user_email" "user_email"

    log_info "Adding new user: $user_email"

    # Generate or validate UUID
    local user_uuid
    if [[ "$auto_uuid" == "true" ]]; then
        user_uuid=$(generate_uuid)
        log_info "Generated UUID: $user_uuid"
    else
        user_uuid="$custom_uuid"
        if ! validate_uuid "$user_uuid"; then
            log_error "Invalid UUID format: $user_uuid"
            return 1
        fi
    fi

    # Use email as name if not provided
    if [[ -z "$user_name" ]]; then
        user_name="$user_email"
    fi

    # Add user to database
    if ! add_user_to_database "$DEFAULT_DB_FILE" "$user_uuid" "$user_email" "$user_name" "$user_flow"; then
        log_error "Failed to add user to database"
        return 1
    fi

    # Add user to Xray configuration
    local config_file
    if [[ -f "$XRAY_CONFIG_FILE" ]]; then
        config_file="$XRAY_CONFIG_FILE"
    elif [[ -f "$PROJECT_XRAY_CONFIG" ]]; then
        config_file="$PROJECT_XRAY_CONFIG"
    else
        log_error "No Xray configuration file found"
        return 1
    fi

    if ! "${SCRIPT_DIR}/config_templates.sh" --add-user "$config_file" "$user_uuid" "$user_email"; then
        log_error "Failed to add user to Xray configuration"
        # Remove from database if Xray config failed
        remove_user_from_database "$DEFAULT_DB_FILE" "$user_uuid"
        return 1
    fi

    # Reload Xray configuration if service is running
    if docker ps --format '{{.Names}}' | grep -q "vless-xray"; then
        log_info "Reloading Xray configuration..."
        if ! "${SCRIPT_DIR}/container_management.sh" --reload; then
            log_warn "Failed to reload Xray configuration automatically"
            log_warn "Please restart the service manually: ./container_management.sh --restart xray"
        fi
    fi

    log_success "User added successfully: $user_email ($user_uuid)"

    # Generate client configuration
    generate_user_config "$user_uuid" "display"

    return 0
}

# Remove user with cleanup
remove_user() {
    local identifier="$1"  # Can be UUID or email

    validate_not_empty "$identifier" "identifier"

    log_info "Removing user: $identifier"

    # Find user UUID if email was provided
    local user_uuid
    if validate_uuid "$identifier"; then
        user_uuid="$identifier"
    else
        # Search by email
        user_uuid=$(jq -r --arg email "$identifier" \
                    '.users | to_entries[] | select(.value.email == $email) | .key' \
                    "$DEFAULT_DB_FILE" 2>/dev/null || echo "")

        if [[ -z "$user_uuid" ]]; then
            log_error "User not found: $identifier"
            return 1
        fi
    fi

    # Get user info before removal
    local user_info
    user_info=$(get_user_from_database "$DEFAULT_DB_FILE" "$user_uuid" "json" 2>/dev/null || echo "{}")
    local user_email
    user_email=$(echo "$user_info" | jq -r '.email // "unknown"')

    # Remove from Xray configuration
    local config_file
    if [[ -f "$XRAY_CONFIG_FILE" ]]; then
        config_file="$XRAY_CONFIG_FILE"
    elif [[ -f "$PROJECT_XRAY_CONFIG" ]]; then
        config_file="$PROJECT_XRAY_CONFIG"
    else
        log_warn "No Xray configuration file found for cleanup"
    fi

    if [[ -n "$config_file" ]]; then
        if ! "${SCRIPT_DIR}/config_templates.sh" --remove-user "$config_file" "$user_uuid"; then
            log_warn "Failed to remove user from Xray configuration"
        fi
    fi

    # Remove from database
    if ! remove_user_from_database "$DEFAULT_DB_FILE" "$user_uuid"; then
        log_error "Failed to remove user from database"
        return 1
    fi

    # Reload Xray configuration if service is running
    if docker ps --format '{{.Names}}' | grep -q "vless-xray"; then
        log_info "Reloading Xray configuration..."
        if ! "${SCRIPT_DIR}/container_management.sh" --reload; then
            log_warn "Failed to reload Xray configuration automatically"
            log_warn "Please restart the service manually: ./container_management.sh --restart xray"
        fi
    fi

    log_success "User removed successfully: $user_email ($user_uuid)"

    return 0
}

# List users with enhanced formatting
list_users() {
    local format="${1:-enhanced}"  # enhanced, table, csv, json
    local filter="${2:-all}"       # all, active, disabled, expired
    local search="${3:-}"           # Search term for email/name

    log_info "Listing users (format: $format, filter: $filter)"

    # Check if database exists
    if [[ ! -f "$DEFAULT_DB_FILE" ]]; then
        log_warn "User database not found. No users exist yet."
        return 0
    fi

    case "$format" in
        "enhanced")
            echo "=== VLESS VPN Users ==="
            echo

            # Show statistics first
            get_database_statistics "$DEFAULT_DB_FILE" | grep -A 10 "User Statistics:"
            echo

            # Show user list in table format
            echo "User List:"
            if [[ -n "$search" ]]; then
                # Filter by search term
                jq -r --arg search "$search" --arg filter "$filter" \
                   '.users | to_entries[] |
                    select(.value.email | contains($search) or .value.name | contains($search)) |
                    select(if $filter == "all" then true
                           elif $filter == "active" then .value.status == "active"
                           elif $filter == "disabled" then .value.status == "disabled"
                           elif $filter == "expired" then .value.status == "expired"
                           else true end) |
                    .value |
                    [.email, (.name // .email)[0:20], .status, (.created[0:19] | gsub("T"; " ")),
                     (.traffic_used | tostring)] |
                    @tsv' "$DEFAULT_DB_FILE" | \
                {
                    printf "%-30s %-20s %-10s %-20s %-15s\n" "Email" "Name" "Status" "Created" "Traffic Used"
                    printf "%-30s %-20s %-10s %-20s %-15s\n" "------------------------------" \
                           "--------------------" "----------" "--------------------" "---------------"
                    while IFS=$'\t' read -r email name status created traffic; do
                        printf "%-30s %-20s %-10s %-20s %-15s\n" "$email" "$name" "$status" "$created" "$traffic"
                    done
                }
            else
                list_users_in_database "$DEFAULT_DB_FILE" "table" "$filter"
            fi
            ;;
        "table"|"csv"|"json")
            if [[ -n "$search" ]]; then
                log_warn "Search filtering not implemented for $format format"
            fi
            list_users_in_database "$DEFAULT_DB_FILE" "$format" "$filter"
            ;;
        *)
            log_error "Invalid format: $format (use: enhanced, table, csv, json)"
            return 1
            ;;
    esac
}

# Get user information with client configuration
get_user_info() {
    local identifier="$1"  # Can be UUID or email
    local show_config="${2:-true}"

    validate_not_empty "$identifier" "identifier"

    # Find user UUID if email was provided
    local user_uuid
    if validate_uuid "$identifier"; then
        user_uuid="$identifier"
    else
        # Search by email
        user_uuid=$(jq -r --arg email "$identifier" \
                    '.users | to_entries[] | select(.value.email == $email) | .key' \
                    "$DEFAULT_DB_FILE" 2>/dev/null || echo "")

        if [[ -z "$user_uuid" ]]; then
            log_error "User not found: $identifier"
            return 1
        fi
    fi

    # Get user information
    echo "=== User Information ==="
    get_user_from_database "$DEFAULT_DB_FILE" "$user_uuid" "table"
    echo

    # Show client configuration if requested
    if [[ "$show_config" == "true" ]]; then
        generate_user_config "$user_uuid" "display"
    fi
}

# Update user status
update_user_status() {
    local identifier="$1"  # Can be UUID or email
    local new_status="$2"   # active, disabled, expired

    validate_not_empty "$identifier" "identifier"
    validate_not_empty "$new_status" "new_status"

    # Validate status
    case "$new_status" in
        "active"|"disabled"|"expired")
            ;;
        *)
            log_error "Invalid status: $new_status (use: active, disabled, expired)"
            return 1
            ;;
    esac

    # Find user UUID if email was provided
    local user_uuid
    if validate_uuid "$identifier"; then
        user_uuid="$identifier"
    else
        # Search by email
        user_uuid=$(jq -r --arg email "$identifier" \
                    '.users | to_entries[] | select(.value.email == $email) | .key' \
                    "$DEFAULT_DB_FILE" 2>/dev/null || echo "")

        if [[ -z "$user_uuid" ]]; then
            log_error "User not found: $identifier"
            return 1
        fi
    fi

    # Update user status
    if update_user_in_database "$DEFAULT_DB_FILE" "$user_uuid" "status" "$new_status"; then
        log_success "User status updated to: $new_status"

        # If disabling user, optionally remove from Xray config
        if [[ "$new_status" == "disabled" ]]; then
            read -p "Remove user from active Xray configuration? (y/n): " remove_choice
            if [[ "$remove_choice" =~ ^[Yy] ]]; then
                local config_file
                if [[ -f "$XRAY_CONFIG_FILE" ]]; then
                    config_file="$XRAY_CONFIG_FILE"
                elif [[ -f "$PROJECT_XRAY_CONFIG" ]]; then
                    config_file="$PROJECT_XRAY_CONFIG"
                fi

                if [[ -n "$config_file" ]]; then
                    "${SCRIPT_DIR}/config_templates.sh" --remove-user "$config_file" "$user_uuid"
                    "${SCRIPT_DIR}/container_management.sh" --reload
                fi
            fi
        fi

        # If activating user, add back to Xray config
        if [[ "$new_status" == "active" ]]; then
            local user_info
            user_info=$(get_user_from_database "$DEFAULT_DB_FILE" "$user_uuid" "json")
            local user_email
            user_email=$(echo "$user_info" | jq -r '.email')

            local config_file
            if [[ -f "$XRAY_CONFIG_FILE" ]]; then
                config_file="$XRAY_CONFIG_FILE"
            elif [[ -f "$PROJECT_XRAY_CONFIG" ]]; then
                config_file="$PROJECT_XRAY_CONFIG"
            fi

            if [[ -n "$config_file" ]]; then
                "${SCRIPT_DIR}/config_templates.sh" --add-user "$config_file" "$user_uuid" "$user_email"
                "${SCRIPT_DIR}/container_management.sh" --reload
            fi
        fi
    else
        log_error "Failed to update user status"
        return 1
    fi
}

# Generate client configuration
generate_user_config() {
    local user_uuid="$1"
    local output_type="${2:-display}"  # display, vless, json, qr

    validate_not_empty "$user_uuid" "user_uuid"

    # Get user information
    local user_info
    user_info=$(get_user_from_database "$DEFAULT_DB_FILE" "$user_uuid" "json" 2>/dev/null)
    if [[ -z "$user_info" ]]; then
        log_error "User not found: $user_uuid"
        return 1
    fi

    local user_email
    user_email=$(echo "$user_info" | jq -r '.email')

    # Get server configuration
    local server_ip
    server_ip=$(get_external_ip || echo "YOUR_SERVER_IP")

    local config_file
    if [[ -f "$XRAY_CONFIG_FILE" ]]; then
        config_file="$XRAY_CONFIG_FILE"
    elif [[ -f "$PROJECT_XRAY_CONFIG" ]]; then
        config_file="$PROJECT_XRAY_CONFIG"
    else
        log_error "No Xray configuration file found"
        return 1
    fi

    # Extract server configuration
    local vless_port
    local sni_domain
    local public_key
    local short_id

    vless_port=$(jq -r '.inbounds[0].port' "$config_file" 2>/dev/null || echo "443")
    sni_domain=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$config_file" 2>/dev/null || echo "www.microsoft.com")

    # Get public key and short ID from metadata file if available
    local meta_file="${config_file}.meta"
    if [[ -f "$meta_file" ]]; then
        public_key=$(grep "Public Key:" "$meta_file" | cut -d' ' -f3)
        short_id=$(grep "Short ID:" "$meta_file" | cut -d' ' -f3)
    else
        public_key="YOUR_PUBLIC_KEY"
        short_id="YOUR_SHORT_ID"
    fi

    # Generate VLESS URL
    local vless_url="vless://${user_uuid}@${server_ip}:${vless_port}?type=tcp&security=reality&sni=${sni_domain}&fp=chrome&pbk=${public_key}&sid=${short_id}&flow=xtls-rprx-vision#${user_email}"

    # Generate JSON configuration
    local json_config
    json_config=$(cat << EOF
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$server_ip",
            "port": $vless_port,
            "users": [
              {
                "id": "$user_uuid",
                "email": "$user_email",
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
          "serverName": "$sni_domain",
          "fingerprint": "chrome",
          "publicKey": "$public_key",
          "shortId": "$short_id"
        }
      }
    }
  ]
}
EOF
)

    # Output based on type
    case "$output_type" in
        "display")
            echo "=== Client Configuration ==="
            echo "User: $user_email"
            echo "UUID: $user_uuid"
            echo "Server: $server_ip:$vless_port"
            echo "SNI: $sni_domain"
            echo "Public Key: $public_key"
            echo "Short ID: $short_id"
            echo
            echo "VLESS URL:"
            echo "$vless_url"
            echo
            echo "To generate QR code: $0 --get-config $user_uuid qr"
            ;;
        "vless")
            echo "$vless_url"
            ;;
        "json")
            echo "$json_config"
            ;;
        "qr")
            if [[ -f "${SCRIPT_DIR}/qr_generator.py" ]]; then
                echo "Generating QR code for: $user_email"
                python3 "${SCRIPT_DIR}/qr_generator.py" --text "$vless_url" --format ascii
            else
                log_error "QR generator not available"
                echo "VLESS URL: $vless_url"
            fi
            ;;
        *)
            log_error "Invalid output type: $output_type (use: display, vless, json, qr)"
            return 1
            ;;
    esac
}

# Bulk user operations
bulk_add_users() {
    local users_file="$1"

    validate_not_empty "$users_file" "users_file"

    if [[ ! -f "$users_file" ]]; then
        log_error "Users file not found: $users_file"
        return 1
    fi

    log_info "Adding users from file: $users_file"

    local line_number=0
    local success_count=0
    local error_count=0

    while IFS=',' read -r email name flow; do
        ((line_number++))

        # Skip empty lines and comments
        if [[ -z "$email" || "$email" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Trim whitespace
        email=$(echo "$email" | xargs)
        name=$(echo "$name" | xargs)
        flow=$(echo "$flow" | xargs)

        log_info "Adding user $line_number: $email"

        if add_user "$email" "$name" "$flow"; then
            ((success_count++))
        else
            ((error_count++))
            log_error "Failed to add user: $email"
        fi
    done < "$users_file"

    log_info "Bulk user addition completed"
    log_info "Successfully added: $success_count users"
    if [[ $error_count -gt 0 ]]; then
        log_warn "Failed to add: $error_count users"
    fi
}

# Export users
export_users() {
    local output_file="${1:-/tmp/vless-users-$(date +%Y%m%d_%H%M%S).csv}"
    local format="${2:-csv}"

    log_info "Exporting users to: $output_file"

    case "$format" in
        "csv")
            list_users_in_database "$DEFAULT_DB_FILE" "csv" "all" > "$output_file"
            ;;
        "json")
            list_users_in_database "$DEFAULT_DB_FILE" "json" "all" > "$output_file"
            ;;
        *)
            log_error "Invalid export format: $format (use: csv, json)"
            return 1
            ;;
    esac

    if [[ -f "$output_file" ]]; then
        log_success "Users exported to: $output_file"
        log_info "File size: $(stat -c%s "$output_file") bytes"
    else
        log_error "Failed to export users"
        return 1
    fi
}

# Search users
search_users() {
    local search_term="$1"
    local field="${2:-all}"  # all, email, name, uuid

    validate_not_empty "$search_term" "search_term"

    log_info "Searching users for: $search_term (field: $field)"

    if [[ ! -f "$DEFAULT_DB_FILE" ]]; then
        log_warn "User database not found"
        return 0
    fi

    case "$field" in
        "all")
            jq -r --arg term "$search_term" \
               '.users | to_entries[] |
                select(.value.email | contains($term) or
                       .value.name | contains($term) or
                       .key | contains($term)) |
                .value |
                [.email, .name, .uuid, .status] | @tsv' "$DEFAULT_DB_FILE" | \
            {
                echo "Found users matching '$search_term':"
                printf "%-30s %-20s %-36s %-10s\n" "Email" "Name" "UUID" "Status"
                printf "%-30s %-20s %-36s %-10s\n" "------------------------------" \
                       "--------------------" "------------------------------------" "----------"
                while IFS=$'\t' read -r email name uuid status; do
                    printf "%-30s %-20s %-36s %-10s\n" "$email" "$name" "$uuid" "$status"
                done
            }
            ;;
        "email")
            jq -r --arg term "$search_term" \
               '.users | to_entries[] | select(.value.email | contains($term)) | .value.email' \
               "$DEFAULT_DB_FILE"
            ;;
        "name")
            jq -r --arg term "$search_term" \
               '.users | to_entries[] | select(.value.name | contains($term)) | .value.name' \
               "$DEFAULT_DB_FILE"
            ;;
        "uuid")
            jq -r --arg term "$search_term" \
               '.users | to_entries[] | select(.key | contains($term)) | .key' \
               "$DEFAULT_DB_FILE"
            ;;
        *)
            log_error "Invalid search field: $field (use: all, email, name, uuid)"
            return 1
            ;;
    esac
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN User Management Module

Usage: $0 [OPTIONS]

User Operations:
    --add-user EMAIL [NAME] [FLOW]      Add new user with auto-generated UUID
    --add-user-custom EMAIL UUID [NAME] Add user with custom UUID
    --remove-user IDENTIFIER            Remove user (UUID or email)
    --list-users [FORMAT] [FILTER]      List users
    --get-info IDENTIFIER               Get user information
    --update-status IDENTIFIER STATUS   Update user status
    --get-config IDENTIFIER [TYPE]      Generate client configuration

Bulk Operations:
    --bulk-add FILE                     Add users from CSV file
    --export [FILE] [FORMAT]            Export users to file
    --search TERM [FIELD]               Search users

Database Operations:
    --init-db                           Initialize user database
    --backup-db [NAME]                  Backup user database
    --stats                             Show database statistics

Formats:
    enhanced                            Enhanced table with statistics (default)
    table                              Simple table format
    csv                                CSV format
    json                               JSON format

Filters:
    all                                All users (default)
    active                             Active users only
    disabled                           Disabled users only
    expired                            Expired users only

Status Values:
    active                             User is active and can connect
    disabled                           User is disabled, cannot connect
    expired                            User has expired

Config Types:
    display                            Show all configuration details (default)
    vless                             VLESS URL only
    json                              JSON configuration
    qr                                QR code (ASCII)

Examples:
    $0 --add-user "user@example.com" "John Doe"
    $0 --list-users enhanced active
    $0 --get-info "user@example.com"
    $0 --get-config "user@example.com" qr
    $0 --update-status "user@example.com" disabled
    $0 --remove-user "user@example.com"
    $0 --search "john" all
    $0 --export users.csv csv
    $0 --stats

Bulk CSV Format (for --bulk-add):
    email,name,flow
    user1@example.com,User One,
    user2@example.com,User Two,xtls-rprx-vision

EOF
}

# Main execution
main() {
    local action=""
    local user_email=""
    local user_name=""
    local user_flow=""
    local user_uuid=""
    local identifier=""
    local format="enhanced"
    local filter="all"
    local output_type="display"
    local status=""
    local file=""
    local search_term=""
    local search_field="all"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --add-user)
                action="add-user"
                user_email="$2"
                user_name="${3:-}"
                user_flow="${4:-}"
                shift 2
                [[ -n "$user_name" && ! "$user_name" =~ ^-- ]] && shift
                [[ -n "$user_flow" && ! "$user_flow" =~ ^-- ]] && shift
                ;;
            --add-user-custom)
                action="add-user-custom"
                user_email="$2"
                user_uuid="$3"
                user_name="${4:-}"
                shift 3
                [[ -n "$user_name" && ! "$user_name" =~ ^-- ]] && shift
                ;;
            --remove-user)
                action="remove-user"
                identifier="$2"
                shift 2
                ;;
            --list-users)
                action="list-users"
                format="${2:-enhanced}"
                filter="${3:-all}"
                shift
                [[ "$format" =~ ^(enhanced|table|csv|json)$ ]] && shift
                [[ "$filter" =~ ^(all|active|disabled|expired)$ ]] && shift
                ;;
            --get-info)
                action="get-info"
                identifier="$2"
                shift 2
                ;;
            --update-status)
                action="update-status"
                identifier="$2"
                status="$3"
                shift 3
                ;;
            --get-config)
                action="get-config"
                identifier="$2"
                output_type="${3:-display}"
                shift 2
                [[ "$output_type" =~ ^(display|vless|json|qr)$ ]] && shift
                ;;
            --bulk-add)
                action="bulk-add"
                file="$2"
                shift 2
                ;;
            --export)
                action="export"
                file="${2:-}"
                format="${3:-csv}"
                shift
                [[ -n "$file" && ! "$file" =~ ^-- ]] && shift
                [[ "$format" =~ ^(csv|json)$ ]] && shift
                ;;
            --search)
                action="search"
                search_term="$2"
                search_field="${3:-all}"
                shift 2
                [[ "$search_field" =~ ^(all|email|name|uuid)$ ]] && shift
                ;;
            --init-db)
                action="init-db"
                shift
                ;;
            --backup-db)
                action="backup-db"
                file="${2:-}"
                shift
                [[ -n "$file" && ! "$file" =~ ^-- ]] && shift
                ;;
            --stats)
                action="stats"
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
        "add-user")
            validate_not_empty "$user_email" "user_email"
            add_user "$user_email" "$user_name" "$user_flow"
            ;;
        "add-user-custom")
            validate_not_empty "$user_email" "user_email"
            validate_not_empty "$user_uuid" "user_uuid"
            add_user "$user_email" "$user_name" "$user_flow" "false" "$user_uuid"
            ;;
        "remove-user")
            validate_not_empty "$identifier" "identifier"
            remove_user "$identifier"
            ;;
        "list-users")
            list_users "$format" "$filter"
            ;;
        "get-info")
            validate_not_empty "$identifier" "identifier"
            get_user_info "$identifier"
            ;;
        "update-status")
            validate_not_empty "$identifier" "identifier"
            validate_not_empty "$status" "status"
            update_user_status "$identifier" "$status"
            ;;
        "get-config")
            validate_not_empty "$identifier" "identifier"
            generate_user_config "$identifier" "$output_type"
            ;;
        "bulk-add")
            validate_not_empty "$file" "file"
            bulk_add_users "$file"
            ;;
        "export")
            export_users "$file" "$format"
            ;;
        "search")
            validate_not_empty "$search_term" "search_term"
            search_users "$search_term" "$search_field"
            ;;
        "init-db")
            init_user_database "$DEFAULT_DB_FILE"
            ;;
        "backup-db")
            backup_database "$DEFAULT_DB_FILE" "$file"
            ;;
        "stats")
            get_database_statistics "$DEFAULT_DB_FILE"
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
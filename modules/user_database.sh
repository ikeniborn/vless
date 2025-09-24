#!/bin/bash

# VLESS+Reality VPN Management System - User Database Module
# Version: 1.0.0
# Description: JSON-based user database with CRUD operations
#
# This module provides:
# - JSON schema for user records
# - UUID generation and validation
# - User metadata (creation date, last activity)
# - Database backup and recovery
# - Concurrent access protection
# - Database integrity validation

set -euo pipefail

# Include guard to prevent multiple sourcing
if [[ -n "${USER_DATABASE_LOADED:-}" ]]; then
    return 0
fi
readonly USER_DATABASE_LOADED=true

# Import common utilities
# Check if SCRIPT_DIR is already defined (e.g., by parent script)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/common_utils.sh"

# Database configuration
readonly DEFAULT_DB_FILE="/opt/vless/users/users.json"
readonly DB_BACKUP_DIR="/opt/vless/backup/users"
readonly DB_LOCK_FILE="/tmp/vless-db.lock"
readonly LOCK_TIMEOUT=30

# User status constants
readonly USER_STATUS_ACTIVE="active"
readonly USER_STATUS_DISABLED="disabled"
readonly USER_STATUS_EXPIRED="expired"

# Database lock management
acquire_db_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if (set -C; echo $$ > "$DB_LOCK_FILE") 2>/dev/null; then
            log_debug "Database lock acquired (PID: $$)"
            return 0
        fi

        if [[ -f "$DB_LOCK_FILE" ]]; then
            local lock_pid
            lock_pid=$(cat "$DB_LOCK_FILE" 2>/dev/null || echo "unknown")
            if [[ "$lock_pid" != "unknown" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                log_warn "Removing stale lock file (PID: $lock_pid)"
                rm -f "$DB_LOCK_FILE"
                continue
            fi
        fi

        log_debug "Waiting for database lock (attempt $((elapsed + 1))/$timeout)..."
        sleep 1
        ((elapsed++))
    done

    log_error "Failed to acquire database lock after ${timeout}s"
    return 1
}

# Release database lock
release_db_lock() {
    if [[ -f "$DB_LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$DB_LOCK_FILE" 2>/dev/null || echo "unknown")
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$DB_LOCK_FILE"
            log_debug "Database lock released (PID: $$)"
        else
            log_warn "Lock file PID mismatch: expected $$, found $lock_pid"
        fi
    fi
}

# Ensure cleanup on exit
trap release_db_lock EXIT

# Initialize user database
init_user_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"

    log_info "Initializing user database: $db_file"

    # Create database directory
    create_directory "$(dirname "$db_file")" "700"
    create_directory "$DB_BACKUP_DIR" "700"

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for initialization"
        return 1
    fi

    # Create empty database if it doesn't exist
    if [[ ! -f "$db_file" ]]; then
        local initial_db='{
  "metadata": {
    "version": "1.0.0",
    "created": "'$(date -Iseconds)'",
    "last_modified": "'$(date -Iseconds)'",
    "total_users": 0,
    "schema_version": 1
  },
  "users": {}
}'

        echo "$initial_db" > "$db_file"
        chmod 600 "$db_file"
        log_success "User database initialized"
    else
        log_info "User database already exists"
    fi

    # Release lock
    release_db_lock

    # Validate database
    validate_database "$db_file"
}

# Validate database structure and integrity
validate_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    log_debug "Validating database structure: $db_file"

    # Check JSON syntax
    if ! jq empty "$db_file" 2>/dev/null; then
        log_error "Database has invalid JSON syntax"
        return 1
    fi

    # Check required fields
    local required_fields=(".metadata" ".metadata.version" ".metadata.created" ".users")
    local field

    for field in "${required_fields[@]}"; do
        if ! jq -e "$field" "$db_file" >/dev/null 2>&1; then
            log_error "Database missing required field: $field"
            return 1
        fi
    done

    # Validate user records
    local invalid_users
    invalid_users=$(jq -r '.users | to_entries[] | select(.value.uuid == null or .value.email == null or .value.created == null) | .key' "$db_file" 2>/dev/null || echo "")

    if [[ -n "$invalid_users" ]]; then
        log_error "Database contains invalid user records: $invalid_users"
        return 1
    fi

    log_debug "Database validation passed"
    return 0
}

# Backup database
backup_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local backup_name="${2:-backup-$(date +%Y%m%d_%H%M%S)}"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    local backup_file="$DB_BACKUP_DIR/${backup_name}.json"

    log_info "Creating database backup: $backup_file"

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for backup"
        return 1
    fi

    # Create backup
    if cp "$db_file" "$backup_file"; then
        chmod 600 "$backup_file"
        log_success "Database backup created: $backup_file"
        echo "$backup_file"
    else
        log_error "Failed to create database backup"
        release_db_lock
        return 1
    fi

    # Release lock
    release_db_lock
}

# Restore database from backup
restore_database() {
    local backup_file="$1"
    local db_file="${2:-$DEFAULT_DB_FILE}"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_warn "Restoring database from backup: $backup_file"

    # Validate backup file first
    if ! validate_database "$backup_file"; then
        log_error "Backup file is invalid or corrupted"
        return 1
    fi

    # Create current backup before restore
    if [[ -f "$db_file" ]]; then
        local current_backup
        current_backup=$(backup_database "$db_file" "pre-restore-$(date +%Y%m%d_%H%M%S)")
        log_info "Current database backed up to: $current_backup"
    fi

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for restore"
        return 1
    fi

    # Restore from backup
    if cp "$backup_file" "$db_file"; then
        chmod 600 "$db_file"
        log_success "Database restored from backup"
    else
        log_error "Failed to restore database from backup"
        release_db_lock
        return 1
    fi

    # Release lock
    release_db_lock
}

# Update database metadata
update_database_metadata() {
    local db_file="${1:-$DEFAULT_DB_FILE}"

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for metadata update"
        return 1
    fi

    # Update metadata
    local temp_file
    temp_file=$(mktemp)

    if jq --arg timestamp "$(date -Iseconds)" \
       '.metadata.last_modified = $timestamp | .metadata.total_users = (.users | length)' \
       "$db_file" > "$temp_file"; then
        mv "$temp_file" "$db_file"
        chmod 600 "$db_file"
        log_debug "Database metadata updated"
    else
        log_error "Failed to update database metadata"
        rm -f "$temp_file"
        release_db_lock
        return 1
    fi

    # Release lock
    release_db_lock
}

# Add user to database
add_user_to_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local user_uuid="$2"
    local user_email="$3"
    local user_name="${4:-}"
    local user_flow="${5:-}"

    validate_not_empty "$user_uuid" "user_uuid"
    validate_not_empty "$user_email" "user_email"

    if ! validate_uuid "$user_uuid"; then
        log_error "Invalid UUID format: $user_uuid"
        return 1
    fi

    log_info "Adding user to database: $user_email ($user_uuid)"

    # Initialize database if it doesn't exist
    if [[ ! -f "$db_file" ]]; then
        init_user_database "$db_file"
    fi

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for user addition"
        return 1
    fi

    # Check if user already exists
    if jq -e --arg uuid "$user_uuid" '.users | has($uuid)' "$db_file" >/dev/null 2>&1; then
        log_error "User already exists: $user_uuid"
        release_db_lock
        return 1
    fi

    # Create user record
    local user_record
    user_record=$(cat << EOF
{
  "uuid": "$user_uuid",
  "email": "$user_email",
  "name": "${user_name:-$user_email}",
  "flow": "${user_flow:-}",
  "status": "$USER_STATUS_ACTIVE",
  "created": "$(date -Iseconds)",
  "last_modified": "$(date -Iseconds)",
  "last_activity": null,
  "traffic_used": 0,
  "traffic_limit": null,
  "expiry_date": null,
  "notes": ""
}
EOF
)

    # Add user to database
    local temp_file
    temp_file=$(mktemp)

    if jq --argjson user "$user_record" --arg uuid "$user_uuid" \
       '.users[$uuid] = $user' \
       "$db_file" > "$temp_file"; then
        mv "$temp_file" "$db_file"
        chmod 600 "$db_file"
        log_success "User added to database successfully"
    else
        log_error "Failed to add user to database"
        rm -f "$temp_file"
        release_db_lock
        return 1
    fi

    # Update metadata
    update_database_metadata "$db_file"

    # Release lock
    release_db_lock
}

# Remove user from database
remove_user_from_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local user_uuid="$2"

    validate_not_empty "$user_uuid" "user_uuid"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    log_info "Removing user from database: $user_uuid"

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for user removal"
        return 1
    fi

    # Check if user exists
    if ! jq -e --arg uuid "$user_uuid" '.users | has($uuid)' "$db_file" >/dev/null 2>&1; then
        log_error "User not found: $user_uuid"
        release_db_lock
        return 1
    fi

    # Remove user from database
    local temp_file
    temp_file=$(mktemp)

    if jq --arg uuid "$user_uuid" \
       'del(.users[$uuid])' \
       "$db_file" > "$temp_file"; then
        mv "$temp_file" "$db_file"
        chmod 600 "$db_file"
        log_success "User removed from database successfully"
    else
        log_error "Failed to remove user from database"
        rm -f "$temp_file"
        release_db_lock
        return 1
    fi

    # Update metadata
    update_database_metadata "$db_file"

    # Release lock
    release_db_lock
}

# Update user in database
update_user_in_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local user_uuid="$2"
    local field="$3"
    local value="$4"

    validate_not_empty "$user_uuid" "user_uuid"
    validate_not_empty "$field" "field"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    log_info "Updating user in database: $user_uuid (field: $field)"

    # Acquire lock
    if ! acquire_db_lock; then
        log_error "Failed to acquire database lock for user update"
        return 1
    fi

    # Check if user exists
    if ! jq -e --arg uuid "$user_uuid" '.users | has($uuid)' "$db_file" >/dev/null 2>&1; then
        log_error "User not found: $user_uuid"
        release_db_lock
        return 1
    fi

    # Update user field
    local temp_file
    temp_file=$(mktemp)

    # Handle different value types
    local jq_value
    case "$field" in
        "traffic_used"|"traffic_limit")
            # Numeric fields
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                jq_value="$value"
            else
                log_error "Invalid numeric value for $field: $value"
                release_db_lock
                return 1
            fi
            ;;
        "status")
            # Validate status values
            case "$value" in
                "$USER_STATUS_ACTIVE"|"$USER_STATUS_DISABLED"|"$USER_STATUS_EXPIRED")
                    jq_value="\"$value\""
                    ;;
                *)
                    log_error "Invalid status value: $value"
                    release_db_lock
                    return 1
                    ;;
            esac
            ;;
        *)
            # String fields
            jq_value="\"$value\""
            ;;
    esac

    if jq --arg uuid "$user_uuid" --arg field "$field" --argjson value "$jq_value" --arg timestamp "$(date -Iseconds)" \
       '.users[$uuid][$field] = $value | .users[$uuid].last_modified = $timestamp' \
       "$db_file" > "$temp_file"; then
        mv "$temp_file" "$db_file"
        chmod 600 "$db_file"
        log_success "User updated in database successfully"
    else
        log_error "Failed to update user in database"
        rm -f "$temp_file"
        release_db_lock
        return 1
    fi

    # Update metadata
    update_database_metadata "$db_file"

    # Release lock
    release_db_lock
}

# Get user from database
get_user_from_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local user_uuid="$2"
    local format="${3:-json}"  # json, csv, or table

    validate_not_empty "$user_uuid" "user_uuid"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    # Check if user exists
    if ! jq -e --arg uuid "$user_uuid" '.users | has($uuid)' "$db_file" >/dev/null 2>&1; then
        log_error "User not found: $user_uuid"
        return 1
    fi

    # Get user data
    case "$format" in
        "json")
            jq --arg uuid "$user_uuid" '.users[$uuid]' "$db_file"
            ;;
        "csv")
            jq -r --arg uuid "$user_uuid" \
               '["UUID","Email","Name","Status","Created","Traffic Used","Expiry"],
                (.users[$uuid] | [.uuid, .email, .name, .status, .created, .traffic_used, (.expiry_date // "N/A")]) |
                @csv' "$db_file"
            ;;
        "table")
            jq -r --arg uuid "$user_uuid" \
               '.users[$uuid] |
                "UUID: " + .uuid + "\n" +
                "Email: " + .email + "\n" +
                "Name: " + .name + "\n" +
                "Status: " + .status + "\n" +
                "Created: " + .created + "\n" +
                "Traffic Used: " + (.traffic_used | tostring) + " bytes\n" +
                "Expiry Date: " + (.expiry_date // "N/A") + "\n" +
                "Notes: " + .notes' "$db_file"
            ;;
        *)
            log_error "Invalid format: $format (use: json, csv, table)"
            return 1
            ;;
    esac
}

# List all users in database
list_users_in_database() {
    local db_file="${1:-$DEFAULT_DB_FILE}"
    local format="${2:-table}"  # json, csv, or table
    local filter="${3:-all}"    # all, active, disabled, expired

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    # Build filter expression
    local filter_expr
    case "$filter" in
        "all")
            filter_expr="true"
            ;;
        "active")
            filter_expr=".status == \"$USER_STATUS_ACTIVE\""
            ;;
        "disabled")
            filter_expr=".status == \"$USER_STATUS_DISABLED\""
            ;;
        "expired")
            filter_expr=".status == \"$USER_STATUS_EXPIRED\""
            ;;
        *)
            log_error "Invalid filter: $filter (use: all, active, disabled, expired)"
            return 1
            ;;
    esac

    # Get and format user data
    case "$format" in
        "json")
            jq --argjson filter_expr "$filter_expr" \
               '.users | to_entries | map(select(.value | $filter_expr)) | from_entries' \
               "$db_file"
            ;;
        "csv")
            echo "UUID,Email,Name,Status,Created,Traffic Used,Expiry"
            jq -r --arg filter_expr "$filter_expr" \
               '.users | to_entries[] | select(.value | '"$filter_expr"') |
                .value | [.uuid, .email, .name, .status, .created, .traffic_used, (.expiry_date // "N/A")] |
                @csv' "$db_file"
            ;;
        "table")
            printf "%-36s %-30s %-20s %-10s %-20s %-15s %-15s\n" \
                   "UUID" "Email" "Name" "Status" "Created" "Traffic Used" "Expiry"
            printf "%-36s %-30s %-20s %-10s %-20s %-15s %-15s\n" \
                   "------------------------------------" "------------------------------" \
                   "--------------------" "----------" "--------------------" \
                   "---------------" "---------------"
            jq -r --arg filter_expr "$filter_expr" \
               '.users | to_entries[] | select(.value | '"$filter_expr"') |
                .value |
                [.uuid, .email, (.name // .email)[0:20], .status, (.created[0:19] | gsub("T"; " ")),
                 (.traffic_used | tostring), (.expiry_date // "N/A")[0:15]] |
                @tsv' "$db_file" | \
            while IFS=$'\t' read -r uuid email name status created traffic expiry; do
                printf "%-36s %-30s %-20s %-10s %-20s %-15s %-15s\n" \
                       "$uuid" "$email" "$name" "$status" "$created" "$traffic" "$expiry"
            done
            ;;
        *)
            log_error "Invalid format: $format (use: json, csv, table)"
            return 1
            ;;
    esac
}

# Get database statistics
get_database_statistics() {
    local db_file="${1:-$DEFAULT_DB_FILE}"

    if [[ ! -f "$db_file" ]]; then
        log_error "Database file not found: $db_file"
        return 1
    fi

    echo "=== User Database Statistics ==="
    echo "Database File: $db_file"
    echo "File Size: $(stat -c%s "$db_file" 2>/dev/null || echo "unknown") bytes"
    echo "Last Modified: $(stat -c%y "$db_file" 2>/dev/null || echo "unknown")"
    echo

    # Database metadata
    jq -r '.metadata |
           "Database Version: " + .version + "\n" +
           "Created: " + .created + "\n" +
           "Last Modified: " + .last_modified + "\n" +
           "Schema Version: " + (.schema_version | tostring)' "$db_file" 2>/dev/null
    echo

    # User statistics
    local total_users
    local active_users
    local disabled_users
    local expired_users

    total_users=$(jq '.users | length' "$db_file" 2>/dev/null || echo "0")
    active_users=$(jq --arg status "$USER_STATUS_ACTIVE" '.users | [.[] | select(.status == $status)] | length' "$db_file" 2>/dev/null || echo "0")
    disabled_users=$(jq --arg status "$USER_STATUS_DISABLED" '.users | [.[] | select(.status == $status)] | length' "$db_file" 2>/dev/null || echo "0")
    expired_users=$(jq --arg status "$USER_STATUS_EXPIRED" '.users | [.[] | select(.status == $status)] | length' "$db_file" 2>/dev/null || echo "0")

    echo "User Statistics:"
    echo "  Total Users: $total_users"
    echo "  Active Users: $active_users"
    echo "  Disabled Users: $disabled_users"
    echo "  Expired Users: $expired_users"
    echo

    # Traffic statistics (if available)
    local total_traffic
    total_traffic=$(jq '.users | [.[].traffic_used] | add // 0' "$db_file" 2>/dev/null || echo "0")
    echo "Total Traffic Used: $(human_readable_size "$total_traffic")"
    echo
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN User Database Module

Usage: $0 [OPTIONS]

Database Operations:
    --init [FILE]                   Initialize user database
    --backup [FILE] [NAME]          Create database backup
    --restore BACKUP [FILE]         Restore from backup
    --validate [FILE]              Validate database integrity
    --stats [FILE]                 Show database statistics

User Operations:
    --add-user UUID EMAIL [NAME] [FLOW]    Add user to database
    --remove-user UUID                     Remove user from database
    --update-user UUID FIELD VALUE         Update user field
    --get-user UUID [FORMAT]               Get user information
    --list-users [FORMAT] [FILTER]         List all users

Options:
    --db-file FILE                 Database file path (default: $DEFAULT_DB_FILE)
    --help                         Show this help message

Formats:
    json                           JSON format
    csv                            CSV format
    table                          Table format (default)

Filters:
    all                            All users (default)
    active                         Active users only
    disabled                       Disabled users only
    expired                        Expired users only

Examples:
    $0 --init                                    # Initialize database
    $0 --add-user "\$(uuidgen)" "user@example.com" "John Doe"
    $0 --list-users table active               # List active users in table format
    $0 --get-user UUID json                    # Get user info in JSON format
    $0 --update-user UUID status disabled     # Disable user
    $0 --backup                                # Create backup
    $0 --stats                                 # Show statistics

EOF
}

# Main execution
main() {
    local action=""
    local db_file="$DEFAULT_DB_FILE"
    local user_uuid=""
    local user_email=""
    local user_name=""
    local user_flow=""
    local field=""
    local value=""
    local format="table"
    local filter="all"
    local backup_file=""
    local backup_name=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --init)
                action="init"
                shift
                ;;
            --backup)
                action="backup"
                backup_name="${2:-}"
                [[ -n "$backup_name" && ! "$backup_name" =~ ^-- ]] && shift
                shift
                ;;
            --restore)
                action="restore"
                backup_file="$2"
                shift 2
                ;;
            --validate)
                action="validate"
                shift
                ;;
            --stats)
                action="stats"
                shift
                ;;
            --add-user)
                action="add-user"
                user_uuid="$2"
                user_email="$3"
                user_name="${4:-}"
                user_flow="${5:-}"
                shift 3
                [[ -n "$user_name" && ! "$user_name" =~ ^-- ]] && shift
                [[ -n "$user_flow" && ! "$user_flow" =~ ^-- ]] && shift
                ;;
            --remove-user)
                action="remove-user"
                user_uuid="$2"
                shift 2
                ;;
            --update-user)
                action="update-user"
                user_uuid="$2"
                field="$3"
                value="$4"
                shift 4
                ;;
            --get-user)
                action="get-user"
                user_uuid="$2"
                format="${3:-table}"
                shift 2
                [[ "$format" != "json" && "$format" != "csv" && "$format" != "table" ]] || shift
                ;;
            --list-users)
                action="list-users"
                format="${2:-table}"
                filter="${3:-all}"
                shift
                [[ "$format" != "json" && "$format" != "csv" && "$format" != "table" ]] || shift
                [[ "$filter" != "all" && "$filter" != "active" && "$filter" != "disabled" && "$filter" != "expired" ]] || shift
                ;;
            --db-file)
                db_file="$2"
                shift 2
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
        "init")
            init_user_database "$db_file"
            ;;
        "backup")
            backup_database "$db_file" "$backup_name"
            ;;
        "restore")
            validate_not_empty "$backup_file" "backup_file"
            restore_database "$backup_file" "$db_file"
            ;;
        "validate")
            validate_database "$db_file"
            ;;
        "stats")
            get_database_statistics "$db_file"
            ;;
        "add-user")
            validate_not_empty "$user_uuid" "user_uuid"
            validate_not_empty "$user_email" "user_email"
            add_user_to_database "$db_file" "$user_uuid" "$user_email" "$user_name" "$user_flow"
            ;;
        "remove-user")
            validate_not_empty "$user_uuid" "user_uuid"
            remove_user_from_database "$db_file" "$user_uuid"
            ;;
        "update-user")
            validate_not_empty "$user_uuid" "user_uuid"
            validate_not_empty "$field" "field"
            update_user_in_database "$db_file" "$user_uuid" "$field" "$value"
            ;;
        "get-user")
            validate_not_empty "$user_uuid" "user_uuid"
            get_user_from_database "$db_file" "$user_uuid" "$format"
            ;;
        "list-users")
            list_users_in_database "$db_file" "$format" "$filter"
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
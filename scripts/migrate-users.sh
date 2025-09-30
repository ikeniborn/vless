#!/bin/bash

# VLESS Users Database Migration Script
# Migrates users.json from old schema to new schema with quota support
# Version: 1.0
# Date: 2025-09-30

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Global variables
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
USERS_FILE="$VLESS_HOME/data/users.json"
BACKUP_DIR="$VLESS_HOME/backups/migration"

# ============================================================================
# Migration Functions
# ============================================================================

# Check if migration is needed
check_migration_needed() {
    if [ ! -f "$USERS_FILE" ]; then
        print_error "Users file not found: $USERS_FILE"
        print_info "No migration needed - file will be created with new schema"
        return 1
    fi

    # Check if file already has new schema (check for short_ids array)
    local has_new_schema=$(jq -r '.users[0] | has("short_ids")' "$USERS_FILE" 2>/dev/null || echo "false")

    if [ "$has_new_schema" = "true" ]; then
        print_success "Users database already has new schema"
        print_info "No migration needed"
        return 1
    fi

    return 0
}

# Create backup before migration
create_backup() {
    print_info "Creating backup before migration..."

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Create timestamped backup
    local backup_file="$BACKUP_DIR/users.json.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$USERS_FILE" "$backup_file"

    print_success "Backup created: $backup_file"
    echo ""
}

# Migrate single user to new schema
migrate_user() {
    local user_json="$1"

    # Extract existing fields
    local name=$(echo "$user_json" | jq -r '.name')
    local uuid=$(echo "$user_json" | jq -r '.uuid')
    local short_id=$(echo "$user_json" | jq -r '.short_id // ""')
    local created_at=$(echo "$user_json" | jq -r '.created_at')

    # Convert short_id to short_ids array
    local short_ids
    if [ -n "$short_id" ] && [ "$short_id" != "null" ]; then
        # Create variations: 8, 6, 4 chars
        local id_8="$short_id"
        local id_6="${short_id:0:6}"
        local id_4="${short_id:0:4}"
        short_ids="[\"$id_8\", \"$id_6\", \"$id_4\"]"
    else
        short_ids="[]"
    fi

    # Create new user object with all fields
    cat <<EOF
{
  "name": "$name",
  "uuid": "$uuid",
  "short_ids": $short_ids,
  "access_level": "user",
  "bandwidth_limit_gb": 0,
  "bandwidth_used_gb": 0,
  "expiry_date": null,
  "created_at": "$created_at",
  "last_seen": null,
  "total_connections": 0,
  "blocked": false
}
EOF
}

# Perform migration
perform_migration() {
    print_header "Migrating Users Database"

    # Read all users
    local user_count=$(jq '.users | length' "$USERS_FILE")
    print_info "Found $user_count user(s) to migrate"
    echo ""

    # Create temporary file for new JSON
    local tmp_file=$(mktemp)

    # Start building new JSON
    echo '{"users": [' > "$tmp_file"

    # Migrate each user
    local first=true
    jq -c '.users[]' "$USERS_FILE" | while read -r user; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$tmp_file"
        fi

        migrate_user "$user" >> "$tmp_file"
    done

    # Close JSON array
    echo ']}' >> "$tmp_file"

    # Validate generated JSON
    if ! jq empty "$tmp_file" 2>/dev/null; then
        print_error "Generated JSON is invalid"
        rm -f "$tmp_file"
        return 1
    fi

    # Format JSON properly
    local formatted_file=$(mktemp)
    jq '.' "$tmp_file" > "$formatted_file"

    # Replace original file
    mv "$formatted_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    # Cleanup
    rm -f "$tmp_file"

    print_success "Migration completed successfully"
    return 0
}

# Display migration summary
show_migration_summary() {
    print_header "Migration Summary"

    local total_users=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")

    echo "Total users migrated: $total_users"
    echo ""
    echo "New fields added to each user:"
    echo "  • short_ids (array)    - Multiple shortId variations"
    echo "  • access_level         - User access level (default: user)"
    echo "  • bandwidth_limit_gb   - Bandwidth quota in GB (0 = unlimited)"
    echo "  • bandwidth_used_gb    - Used bandwidth in GB"
    echo "  • expiry_date          - Account expiration date"
    echo "  • last_seen            - Last connection timestamp"
    echo "  • total_connections    - Total connection count"
    echo "  • blocked              - Account blocked status"
    echo ""
    print_info "Users file: $USERS_FILE"
}

# Rollback migration
rollback_migration() {
    print_warning "Rolling back migration..."

    local latest_backup=$(ls -t "$BACKUP_DIR"/users.json.backup.* 2>/dev/null | head -n1)

    if [ -z "$latest_backup" ]; then
        print_error "No backup found for rollback"
        return 1
    fi

    cp "$latest_backup" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    print_success "Rollback completed from: $latest_backup"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check root privileges
    check_root

    print_header "VLESS Users Database Migration"
    echo "This script will migrate your users.json to the new schema"
    echo "with quota management and extended user information"
    echo ""

    # Check if migration is needed
    if ! check_migration_needed; then
        exit 0
    fi

    # Show current structure
    print_info "Current users.json structure:"
    jq '.users[0] // {}' "$USERS_FILE" 2>/dev/null || echo "{}"
    echo ""

    # Confirm migration
    if ! confirm_action "Do you want to proceed with migration?" "n"; then
        print_warning "Migration cancelled"
        exit 0
    fi

    # Create backup
    create_backup

    # Perform migration
    if perform_migration; then
        echo ""
        show_migration_summary
        echo ""
        print_success "✓ Migration successful!"
        print_info "Backup saved in: $BACKUP_DIR"
        echo ""
        print_warning "Note: You may need to restart Xray service for changes to take effect"
    else
        echo ""
        print_error "Migration failed"
        if confirm_action "Do you want to rollback to previous version?" "y"; then
            rollback_migration
        fi
        exit 1
    fi
}

# Run main function
main "$@"
#!/bin/bash

# Security functions library for VLESS+REALITY
# Provides cryptographic operations, shortId management, and security utilities

# Load dependencies
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

if [ -z "$VLESS_HOME" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
fi

# Global variables
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
USERS_FILE="$VLESS_HOME/data/users.json"
CONFIG_FILE="$VLESS_HOME/config/config.json"

# ============================================================================
# Short ID Generation Functions
# ============================================================================

# Generate a single random shortId (8 hex characters)
# Usage: generate_user_shortid
# Returns: 8-character hex string (lowercase)
# Example: a1b2c3d4
generate_user_shortid() {
    openssl rand -hex 4 | tr '[:upper:]' '[:lower:]'
}

# Generate array of shortIds with different lengths
# Usage: generate_shortids_array
# Returns: JSON array of shortIds ["8chars", "6chars", "4chars"]
# Example: ["a1b2c3d4", "a1b2c3", "a1b2"]
generate_shortids_array() {
    local base_id=$(generate_user_shortid)
    local id_8="${base_id}"
    local id_6="${base_id:0:6}"
    local id_4="${base_id:0:4}"

    # Return JSON array
    echo "[\"$id_8\", \"$id_6\", \"$id_4\"]"
}

# Validate shortId format
# Usage: validate_shortid <shortid>
# Parameters:
#   $1 - shortId to validate
# Returns: 0 if valid, 1 if invalid
# Valid formats: 2, 4, 6, or 8 hex characters (lowercase)
validate_shortid() {
    local shortid="$1"

    # Check if empty
    if [ -z "$shortid" ]; then
        return 1
    fi

    # Check if contains only hex characters (lowercase)
    if ! [[ $shortid =~ ^[0-9a-f]+$ ]]; then
        return 1
    fi

    # Check length (must be even and between 2-8)
    local len=${#shortid}
    if [[ $len -eq 2 || $len -eq 4 || $len -eq 6 || $len -eq 8 ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# Short ID Rotation Functions
# ============================================================================

# Rotate shortIds for a specific user
# Usage: rotate_shortids <username>
# Parameters:
#   $1 - username to rotate shortIds for
# Returns: 0 on success, 1 on failure
# Note: Requires root privileges, creates backup, restarts Xray service
rotate_shortids() {
    local username="$1"

    # Validate input
    if [ -z "$username" ]; then
        print_error "Username is required"
        return 1
    fi

    # Check if users file exists
    if [ ! -f "$USERS_FILE" ]; then
        print_error "Users file not found: $USERS_FILE"
        return 1
    fi

    # Check if user exists
    if ! jq -e ".users[] | select(.name == \"$username\")" "$USERS_FILE" > /dev/null 2>&1; then
        print_error "User '$username' not found"
        return 1
    fi

    # Generate new shortIds array
    local new_shortids=$(generate_shortids_array)

    print_info "Rotating shortIds for user: $username"
    print_info "New shortIds: $new_shortids"

    # Create backup before modification
    local backup_file="${USERS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$USERS_FILE" "$backup_file"
    print_success "Backup created: $backup_file"

    # Update users.json with new shortIds
    local tmp_file=$(mktemp)
    if ! jq ".users = [.users[] | if .name == \"$username\" then .short_ids = $new_shortids else . end]" \
        "$USERS_FILE" > "$tmp_file"; then
        print_error "Failed to update users.json"
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
    print_success "Updated users.json"

    # Update config.json shortIds array
    print_info "Updating Xray configuration..."
    if ! update_config_shortids; then
        print_error "Failed to update config.json"
        print_warning "Restoring from backup..."
        cp "$backup_file" "$USERS_FILE"
        return 1
    fi

    print_success "ShortIds rotated successfully for user: $username"
    print_warning "Note: Service restart required for changes to take effect"

    return 0
}

# Update config.json with all shortIds from users.json
# Usage: update_config_shortids
# Returns: 0 on success, 1 on failure
# Note: This is a helper function called by rotate_shortids
update_config_shortids() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        return 1
    fi

    if [ ! -f "$USERS_FILE" ]; then
        print_error "Users file not found: $USERS_FILE"
        return 1
    fi

    # Extract all shortIds from all users (flatten the arrays)
    local all_shortids=$(jq -r '[.users[].short_ids[]] | unique | @json' "$USERS_FILE")

    # Also include empty string for compatibility
    all_shortids=$(echo "$all_shortids" | jq '. = [""] + .')

    # Update config.json
    local tmp_file=$(mktemp)
    if ! jq ".inbounds[0].streamSettings.realitySettings.shortIds = $all_shortids" \
        "$CONFIG_FILE" > "$tmp_file"; then
        print_error "Failed to update config.json"
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    return 0
}

# ============================================================================
# User Quota Management Functions
# ============================================================================

# Check if user has exceeded bandwidth quota
# Usage: check_bandwidth_quota <username>
# Parameters:
#   $1 - username to check
# Returns: 0 if within quota, 1 if exceeded, 2 if unlimited (0 limit)
check_bandwidth_quota() {
    local username="$1"

    if [ -z "$username" ]; then
        print_error "Username is required"
        return 1
    fi

    # Get user data
    local user_data=$(jq -r ".users[] | select(.name == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [ -z "$user_data" ]; then
        print_error "User '$username' not found"
        return 1
    fi

    # Extract quota values
    local limit=$(echo "$user_data" | jq -r '.bandwidth_limit_gb // 0')
    local used=$(echo "$user_data" | jq -r '.bandwidth_used_gb // 0')

    # Check if unlimited (limit = 0)
    if [ "$limit" -eq 0 ]; then
        return 2
    fi

    # Compare used vs limit
    if awk "BEGIN {exit !($used >= $limit)}"; then
        return 1  # Exceeded
    else
        return 0  # Within quota
    fi
}

# Check if user account has expired
# Usage: check_expiry_date <username>
# Parameters:
#   $1 - username to check
# Returns: 0 if valid, 1 if expired, 2 if no expiry set
check_expiry_date() {
    local username="$1"

    if [ -z "$username" ]; then
        print_error "Username is required"
        return 1
    fi

    # Get user data
    local user_data=$(jq -r ".users[] | select(.name == \"$username\")" "$USERS_FILE" 2>/dev/null)
    if [ -z "$user_data" ]; then
        print_error "User '$username' not found"
        return 1
    fi

    # Extract expiry date
    local expiry=$(echo "$user_data" | jq -r '.expiry_date // "null"')

    # Check if no expiry set
    if [ "$expiry" = "null" ] || [ -z "$expiry" ]; then
        return 2
    fi

    # Compare dates (convert to epoch)
    local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
    local now_epoch=$(date +%s)

    if [ -z "$expiry_epoch" ]; then
        print_error "Invalid expiry date format"
        return 1
    fi

    if [ $now_epoch -ge $expiry_epoch ]; then
        return 1  # Expired
    else
        return 0  # Valid
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

# Print security-related system information
# Usage: print_security_info
print_security_info() {
    print_header "Security Information"

    if [ -f "$USERS_FILE" ]; then
        local total_users=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")
        local blocked_users=$(jq '[.users[] | select(.blocked == true)] | length' "$USERS_FILE" 2>/dev/null || echo "0")

        echo "Total users: $total_users"
        echo "Blocked users: $blocked_users"
        echo "Active users: $((total_users - blocked_users))"
    else
        echo "Users file not found"
    fi

    echo ""
}

# Export functions for use in other scripts
export -f generate_user_shortid
export -f generate_shortids_array
export -f validate_shortid
export -f rotate_shortids
export -f update_config_shortids
export -f check_bandwidth_quota
export -f check_expiry_date
export -f print_security_info
#!/bin/bash
# ============================================================================
# VLESS Reality Deployment System
# Module: User Management
# Version: 1.0.0
# Tasks: EPIC-6 (TASK-6.1 through TASK-6.5)
# ============================================================================
#
# Purpose:
#   Complete user management system for VLESS Reality VPN. Handles user
#   creation, deletion, UUID generation, JSON storage with atomic operations,
#   and Xray configuration updates.
#
# Functions:
#   1. create_user()                  - Create new VPN user
#   2. remove_user()                  - Remove existing user
#   3. list_users()                   - List all users
#   4. user_exists()                  - Check if user exists
#   5. get_user_info()                - Get user details
#   6. validate_username()            - Validate username format
#   7. generate_uuid()                - Generate UUID v4
#   8. add_user_to_json()             - Add user to users.json (atomic)
#   9. remove_user_from_json()        - Remove user from users.json (atomic)
#   10. add_client_to_xray()          - Add client to xray_config.json
#   11. remove_client_from_xray()     - Remove client from xray_config.json
#   12. reload_xray()                 - Reload Xray configuration
#   13. generate_vless_uri()          - Generate VLESS connection URI
#
# Usage:
#   source lib/user_management.sh
#   create_user "alice"
#   remove_user "alice"
#   list_users
#
# Dependencies:
#   - jq (JSON processing)
#   - uuidgen or /proc/sys/kernel/random/uuid
#   - flock (file locking for atomic operations)
#   - docker (for Xray container management)
#
# Author: Claude Code Agent
# Date: 2025-10-02
# ============================================================================

set -euo pipefail

# Source QR generator module for client configuration export
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/qr_generator.sh" ]]; then
    source "${SCRIPT_DIR}/qr_generator.sh"
fi

# ============================================================================
# Global Variables
# ============================================================================

# Installation paths (only define if not already set)
[[ -z "${VLESS_HOME:-}" ]] && readonly VLESS_HOME="/opt/vless"
[[ -z "${USERS_JSON:-}" ]] && readonly USERS_JSON="${VLESS_HOME}/data/users.json"
[[ -z "${XRAY_CONFIG:-}" ]] && readonly XRAY_CONFIG="${VLESS_HOME}/config/xray_config.json"
[[ -z "${ENV_FILE:-}" ]] && readonly ENV_FILE="${VLESS_HOME}/.env"
[[ -z "${CLIENTS_DIR:-}" ]] && readonly CLIENTS_DIR="${VLESS_HOME}/data/clients"
[[ -z "${LOCK_FILE:-}" ]] && readonly LOCK_FILE="/var/lock/vless_users.lock"

# Container name (only define if not already set)
[[ -z "${XRAY_CONTAINER:-}" ]] && readonly XRAY_CONTAINER="vless_xray"

# Colors for output (only define if not already set to avoid conflicts)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

# ============================================================================
# TASK-6.2: UUID Generation
# ============================================================================

generate_uuid() {
    # Try uuidgen first (most common)
    if command -v uuidgen &>/dev/null; then
        uuidgen
        return 0
    fi

    # Fallback to /proc/sys/kernel/random/uuid (Linux)
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
        return 0
    fi

    # Fallback to manual generation using /dev/urandom
    if [[ -r /dev/urandom ]]; then
        # Generate UUID v4 manually
        local uuid
        uuid=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')

        # Format as UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        # Set version (4) and variant bits
        uuid="${uuid:0:8}-${uuid:8:4}-4${uuid:13:3}-${uuid:16:4}-${uuid:20:12}"
        echo "$uuid"
        return 0
    fi

    log_error "No UUID generation method available"
    return 1
}

# =============================================================================
# FUNCTION: generate_short_id
# =============================================================================
# Description:
#   Generate unique 8-byte (16 hex characters) shortId for VLESS Reality protocol.
#   Each user should have a unique shortId for better connection management and security.
#
# Arguments: None
#
# Returns:
#   Stdout: 16-character hexadecimal shortId (lowercase)
#   Exit:   0 on success, 1 on failure
#
# Example:
#   short_id=$(generate_short_id)
#   # Output: a1b2c3d4e5f67890 (16 hex characters = 8 bytes)
#
# Related: VLESS Reality Protocol - shortIds for user identification
# Reference: https://deepwiki.com/XTLS/Xray-examples/2.3-vless-+-tcp-+-reality
# =============================================================================
generate_short_id() {
    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found - required for shortId generation"
        return 1
    fi

    # Generate 8 random bytes and convert to 16 hex characters
    # This matches the format used during installation for server's default shortId
    openssl rand -hex 8
}

# =============================================================================
# FUNCTION: generate_proxy_password
# =============================================================================
# Description:
#   Generate secure 32-character hexadecimal password for proxy authentication.
#   Used for SOCKS5 and HTTP proxy user authentication.
#
# Arguments: None
#
# Returns:
#   Stdout: 32-character hexadecimal password (lowercase)
#   Exit:   0 on success, 1 on failure
#
# Example:
#   password=$(generate_proxy_password)
#   # Output: a1b2c3d4e5f67890a1b2c3d4e5f67890 (32 characters)
#
# Related: TASK-11.1 (SOCKS5 Proxy), TASK-11.2 (HTTP Proxy)
# =============================================================================
generate_proxy_password() {
    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found - required for password generation"
        return 1
    fi

    # Generate 16 random bytes and convert to 32 hex characters (v3.2 security enhancement)
    openssl rand -hex 16
}

# ============================================================================
# Username Validation
# ============================================================================

validate_username() {
    local username="$1"

    # Check if empty
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty"
        return 1
    fi

    # Check length (3-32 characters)
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 32 ]]; then
        log_error "Username must be 3-32 characters long"
        return 1
    fi

    # Check format: alphanumeric + underscore/dash only
    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Username can only contain letters, numbers, underscore, and dash"
        return 1
    fi

    # Check reserved names
    local reserved_names=("root" "admin" "administrator" "system" "default" "test")
    for reserved in "${reserved_names[@]}"; do
        if [[ "${username,,}" == "$reserved" ]]; then
            log_error "Username '$username' is reserved"
            return 1
        fi
    done

    return 0
}

# ============================================================================
# Fingerprint Validation
# ============================================================================

validate_fingerprint() {
    local fingerprint="$1"

    # List of valid TLS fingerprints supported by Xray Reality protocol
    # Reference: https://deepwiki.com/XTLS/Xray-examples/2.3-vless-+-tcp-+-reality
    local valid_fingerprints=("chrome" "firefox" "safari" "edge" "360" "qq" "ios" "android" "random" "randomized")

    # Check if fingerprint is in valid list
    for valid_fp in "${valid_fingerprints[@]}"; do
        if [[ "$fingerprint" == "$valid_fp" ]]; then
            return 0
        fi
    done

    log_error "Invalid fingerprint: $fingerprint"
    log_info "Valid fingerprints: ${valid_fingerprints[*]}"
    return 1
}

# =============================================================================
# FUNCTION: validate_external_proxy_assignment (v5.24)
# =============================================================================
# Description:
#   Validate that external_proxy_id exists in external_proxy.json database.
#   Prevents user creation with non-existent proxy configuration.
#
# Arguments:
#   $1 - proxy_id (string, can be empty for direct routing)
#
# Returns:
#   0 - Valid proxy_id (exists in database) or empty (direct routing)
#   1 - Invalid proxy_id (not found in database)
#
# Example:
#   validate_external_proxy_assignment "proxy-corporate-123456"  # Check if exists
#   validate_external_proxy_assignment ""  # Returns 0 (direct routing is valid)
# =============================================================================
validate_external_proxy_assignment() {
    local proxy_id="${1:-}"

    # Empty proxy_id is valid (direct routing)
    if [[ -z "$proxy_id" ]]; then
        return 0
    fi

    # Check if external_proxy.json exists
    local external_proxy_db="/opt/vless/config/external_proxy.json"
    if [[ ! -f "$external_proxy_db" ]]; then
        log_error "External proxy database not found: $external_proxy_db"
        log_info "Run 'vless-external-proxy add' to configure external proxies first"
        return 1
    fi

    # Check if proxy_id exists in database
    local proxy_exists
    proxy_exists=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id) | .id' "$external_proxy_db" 2>/dev/null)

    if [[ -z "$proxy_exists" ]]; then
        log_error "External proxy not found: $proxy_id"
        log_info "Available proxies:"
        jq -r '.proxies[] | "  - \(.id) (\(.type)://\(.address):\(.port))"' "$external_proxy_db" 2>/dev/null || echo "  (none configured)"
        return 1
    fi

    # Proxy exists
    return 0
}

# ============================================================================
# User Existence Check
# ============================================================================

user_exists() {
    local username="$1"

    if [[ ! -f "$USERS_JSON" ]]; then
        return 1
    fi

    if jq -e ".users[] | select(.username == \"$username\")" "$USERS_JSON" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Get User Information
# ============================================================================

get_user_info() {
    local username="$1"

    if [[ ! -f "$USERS_JSON" ]]; then
        log_error "Users database not found: $USERS_JSON"
        return 1
    fi

    local user_info
    user_info=$(jq -r ".users[] | select(.username == \"$username\")" "$USERS_JSON" 2>/dev/null)

    if [[ -z "$user_info" ]]; then
        log_error "User '$username' not found"
        return 1
    fi

    echo "$user_info"
    return 0
}

# ============================================================================
# TASK-6.3: JSON Storage with flock (Atomic Operations)
# ============================================================================

add_user_to_json() {
    local username="$1"
    local uuid="$2"
    local proxy_password="${3:-}"  # Optional proxy password (TASK-11.1)
    local short_id="${4:-}"        # Optional shortId (v1.2 schema update)
    local fingerprint="${5:-chrome}"  # Optional fingerprint (v1.3 schema update, default: chrome)
    local external_proxy_id="${6:-}"  # Optional external_proxy_id (v5.24 per-user routing)

    log_info "Adding user to database..."

    # Create lock file directory if it doesn't exist
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    # Atomic update with exclusive lock
    (
        # Acquire exclusive lock (will wait if locked)
        flock -x 200

        # Check if users.json exists
        if [[ ! -f "$USERS_JSON" ]]; then
            log_error "Users database not found: $USERS_JSON"
            return 1
        fi

        # Double-check user doesn't exist (race condition protection)
        if jq -e ".users[] | select(.username == \"$username\")" "$USERS_JSON" &>/dev/null; then
            log_error "User '$username' already exists (race condition detected)"
            return 1
        fi

        # Create temporary file in same directory (atomic mv requires same filesystem)
        local temp_file="${USERS_JSON}.tmp.$$"

        # Build user object based on provided parameters
        local user_obj
        user_obj="{
            \"username\": \"$username\",
            \"uuid\": \"$uuid\""

        # Add shortId if provided (v1.2 schema - per-user shortIds)
        if [[ -n "$short_id" ]]; then
            user_obj+=",
            \"shortId\": \"$short_id\""
        fi

        # Add proxy_password if provided
        if [[ -n "$proxy_password" ]]; then
            user_obj+=",
            \"proxy_password\": \"$proxy_password\""
        fi

        # Add fingerprint (v1.3 schema - TLS fingerprint for client configuration)
        user_obj+=",
            \"fingerprint\": \"$fingerprint\""

        # Add external_proxy_id if provided (v5.24 schema - per-user external proxy routing)
        if [[ -n "$external_proxy_id" ]]; then
            user_obj+=",
            \"external_proxy_id\": \"$external_proxy_id\""
        else
            user_obj+=",
            \"external_proxy_id\": null"
        fi

        # Add timestamps
        user_obj+=",
            \"created\": \"$(date -Iseconds)\",
            \"created_timestamp\": $(date +%s)
        }"

        # Add user to JSON
        jq --argjson user "$user_obj" '.users += [$user]' "$USERS_JSON" > "$temp_file"

        # Verify JSON is valid
        if ! jq empty "$temp_file" 2>/dev/null; then
            log_error "Generated invalid JSON"
            rm -f "$temp_file"
            return 1
        fi

        # Atomic move
        mv "$temp_file" "$USERS_JSON"

        # Set proper permissions
        chmod 600 "$USERS_JSON"
        chown root:root "$USERS_JSON" 2>/dev/null || true

    ) 200>"$LOCK_FILE"

    log_success "User added to database"
    return 0
}

remove_user_from_json() {
    local username="$1"

    log_info "Removing user from database..."

    # Atomic update with exclusive lock
    (
        # Acquire exclusive lock
        flock -x 200

        # Check if users.json exists
        if [[ ! -f "$USERS_JSON" ]]; then
            log_error "Users database not found: $USERS_JSON"
            return 1
        fi

        # Check user exists
        if ! jq -e ".users[] | select(.username == \"$username\")" "$USERS_JSON" &>/dev/null; then
            log_error "User '$username' not found in database"
            return 1
        fi

        # Create temporary file
        local temp_file="${USERS_JSON}.tmp.$$"

        # Remove user from JSON
        jq ".users = [.users[] | select(.username != \"$username\")]" "$USERS_JSON" > "$temp_file"

        # Verify JSON is valid
        if ! jq empty "$temp_file" 2>/dev/null; then
            log_error "Generated invalid JSON"
            rm -f "$temp_file"
            return 1
        fi

        # Atomic move
        mv "$temp_file" "$USERS_JSON"

        # Set proper permissions
        chmod 600 "$USERS_JSON"

    ) 200>"$LOCK_FILE"

    log_success "User removed from database"
    return 0
}

# ============================================================================
# TASK-6.4: Xray Config Update
# ============================================================================

add_client_to_xray() {
    local username="$1"
    local uuid="$2"
    local short_id="${3:-}"  # Optional shortId (v1.2 schema update)

    log_info "Adding client to Xray configuration..."

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray configuration not found: $XRAY_CONFIG"
        return 1
    fi

    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$$"

    # Add client to inbounds[0].settings.clients array
    local temp_file="${XRAY_CONFIG}.tmp.$$"

    jq ".inbounds[0].settings.clients += [{
        \"id\": \"$uuid\",
        \"email\": \"${username}@vless.local\",
        \"flow\": \"xtls-rprx-vision\"
    }]" "$XRAY_CONFIG" > "$temp_file"

    # Add shortId to realitySettings.shortIds array if provided (v1.2 - unique per user)
    if [[ -n "$short_id" ]]; then
        log_info "Adding user shortId to realitySettings..."

        # Check if shortId already exists in the array (avoid duplicates)
        local short_id_exists
        short_id_exists=$(jq --arg sid "$short_id" \
            '.inbounds[0].streamSettings.realitySettings.shortIds | index($sid)' \
            "$temp_file")

        if [[ "$short_id_exists" == "null" ]]; then
            # ShortId doesn't exist, add it
            local temp_file2="${XRAY_CONFIG}.tmp2.$$"
            jq --arg sid "$short_id" \
                '.inbounds[0].streamSettings.realitySettings.shortIds += [$sid]' \
                "$temp_file" > "$temp_file2"
            mv "$temp_file2" "$temp_file"
            log_success "ShortId added to realitySettings array"
        else
            log_info "ShortId already exists in array (skipping duplicate)"
        fi
    fi

    # Verify JSON is valid
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Generated invalid Xray configuration"
        rm -f "$temp_file"
        mv "${XRAY_CONFIG}.bak.$$" "$XRAY_CONFIG"
        return 1
    fi

    # Validate with xray -test (if container is running)
    # Note: Container has read-only filesystem, so we validate by mounting the file
    if docker ps --format '{{.Names}}' | grep -q "^${XRAY_CONTAINER}$"; then
        # Check if public proxy mode with TLS is enabled (requires certificate mounting) - v3.4
        local enable_public_proxy="false"
        local enable_proxy_tls="false"
        if [[ -f "$ENV_FILE" ]]; then
            enable_public_proxy=$(grep -E "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" | cut -d'=' -f2 || echo "false")
            enable_proxy_tls=$(grep -E "^ENABLE_PROXY_TLS=" "$ENV_FILE" | cut -d'=' -f2 || echo "false")
        fi

        # Build docker run command with conditional certificate mounting
        local docker_cmd="docker run --rm -v $temp_file:/tmp/test_config.json:ro"
        if [[ "$enable_public_proxy" == "true" ]] && [[ "$enable_proxy_tls" == "true" ]] && [[ -d "/etc/letsencrypt" ]]; then
            docker_cmd="$docker_cmd -v /etc/letsencrypt:/certs:ro"
        fi
        docker_cmd="$docker_cmd ${XRAY_IMAGE:-teddysun/xray:24.11.30} xray -test -config=/tmp/test_config.json"

        # Validate configuration and capture output
        local validation_output
        if ! validation_output=$($docker_cmd 2>&1); then
            log_error "Xray configuration validation failed:"
            echo "$validation_output" >&2
            rm -f "$temp_file"
            mv "${XRAY_CONFIG}.bak.$$" "$XRAY_CONFIG"
            return 1
        fi
    fi

    # Apply configuration
    mv "$temp_file" "$XRAY_CONFIG"
    rm -f "${XRAY_CONFIG}.bak.$$"

    log_success "Client added to Xray configuration"
    return 0
}

remove_client_from_xray() {
    local uuid="$1"
    local username="${2:-}"  # Optional username for shortId removal (v1.2)

    log_info "Removing client from Xray configuration..."

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray configuration not found: $XRAY_CONFIG"
        return 1
    fi

    # Get user's shortId from users.json if username provided
    local user_short_id=""
    if [[ -n "$username" ]] && [[ -f "$USERS_JSON" ]]; then
        user_short_id=$(jq -r ".users[] | select(.username == \"$username\") | .shortId // empty" "$USERS_JSON" 2>/dev/null)
    fi

    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$$"

    # Remove client from inbounds[0].settings.clients array
    local temp_file="${XRAY_CONFIG}.tmp.$$"

    jq ".inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != \"$uuid\")]" \
        "$XRAY_CONFIG" > "$temp_file"

    # Remove user's shortId from realitySettings.shortIds array (v1.2)
    if [[ -n "$user_short_id" ]]; then
        log_info "Removing user shortId from realitySettings..."

        local temp_file2="${XRAY_CONFIG}.tmp2.$$"
        jq --arg sid "$user_short_id" \
            '.inbounds[0].streamSettings.realitySettings.shortIds = [.inbounds[0].streamSettings.realitySettings.shortIds[] | select(. != $sid)]' \
            "$temp_file" > "$temp_file2"
        mv "$temp_file2" "$temp_file"
        log_success "ShortId removed from realitySettings array"
    fi

    # Verify JSON is valid
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Generated invalid Xray configuration"
        rm -f "$temp_file"
        mv "${XRAY_CONFIG}.bak.$$" "$XRAY_CONFIG"
        return 1
    fi

    # Validate with xray -test (if container is running)
    if docker ps --format '{{.Names}}' | grep -q "^${XRAY_CONTAINER}$"; then
        # Check if public proxy mode with TLS is enabled (requires certificate mounting) - v3.4
        local enable_public_proxy="false"
        local enable_proxy_tls="false"
        if [[ -f "$ENV_FILE" ]]; then
            enable_public_proxy=$(grep -E "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" | cut -d'=' -f2 || echo "false")
            enable_proxy_tls=$(grep -E "^ENABLE_PROXY_TLS=" "$ENV_FILE" | cut -d'=' -f2 || echo "false")
        fi

        # Build docker run command with conditional certificate mounting
        local docker_cmd="docker run --rm -v $temp_file:/tmp/test_config.json:ro"
        if [[ "$enable_public_proxy" == "true" ]] && [[ "$enable_proxy_tls" == "true" ]] && [[ -d "/etc/letsencrypt" ]]; then
            docker_cmd="$docker_cmd -v /etc/letsencrypt:/certs:ro"
        fi
        docker_cmd="$docker_cmd ${XRAY_IMAGE:-teddysun/xray:24.11.30} xray -test -config=/tmp/test_config.json"

        # Validate configuration and capture output
        local validation_output
        if ! validation_output=$($docker_cmd 2>&1); then
            log_error "Xray configuration validation failed:"
            echo "$validation_output" >&2
            rm -f "$temp_file"
            mv "${XRAY_CONFIG}.bak.$$" "$XRAY_CONFIG"
            return 1
        fi
    fi

    # Apply configuration
    mv "$temp_file" "$XRAY_CONFIG"
    rm -f "${XRAY_CONFIG}.bak.$$"

    log_success "Client removed from Xray configuration"
    return 0
}

# =============================================================================
# FUNCTION: apply_per_user_routing (v5.24)
# =============================================================================
# Description: Apply per-user external proxy routing (outbounds + routing rules)
# Arguments: None (reads from users.json)
# Returns: 0 on success, 1 on failure
#
# Logic:
#   1. Update Xray outbounds for each unique proxy_id
#   2. Generate per-user routing rules
#   3. Update xray_config.json with new routing
# =============================================================================
apply_per_user_routing() {
    log_info "Applying per-user external proxy routing..."

    # Source xray_routing_manager to use routing functions
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"

    if [[ -f "/opt/vless/lib/xray_routing_manager.sh" ]]; then
        source "/opt/vless/lib/xray_routing_manager.sh"
    elif [[ -f "${script_dir}/xray_routing_manager.sh" ]]; then
        source "${script_dir}/xray_routing_manager.sh"
    else
        log_error "xray_routing_manager.sh not found"
        return 1
    fi

    # Step 1: Update outbounds for each unique proxy
    if ! update_per_user_xray_outbounds; then
        log_error "Failed to update per-user outbounds"
        return 1
    fi

    # Step 2: Generate and apply per-user routing rules
    log_info "Generating per-user routing rules..."
    local routing_json
    routing_json=$(generate_per_user_routing_rules 2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate routing rules"
        return 1
    fi

    # Step 3: Update xray_config.json with new routing
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray config not found: $XRAY_CONFIG"
        return 1
    fi

    local temp_file="${XRAY_CONFIG}.tmp.$$"

    # Update routing section
    echo "$routing_json" | jq -s '.[0]' > /tmp/routing_rules.json || {
        log_error "Failed to parse routing JSON"
        return 1
    }

    jq --slurpfile routing /tmp/routing_rules.json \
        '.routing = $routing[0]' \
        "$XRAY_CONFIG" > "$temp_file"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to update routing rules in Xray config"
        rm -f "$temp_file" /tmp/routing_rules.json
        return 1
    fi

    # Validate JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Generated invalid Xray configuration"
        rm -f "$temp_file" /tmp/routing_rules.json
        return 1
    fi

    # Apply changes
    mv "$temp_file" "$XRAY_CONFIG"
    rm -f /tmp/routing_rules.json

    log_success "Per-user routing applied successfully"
    return 0
}

reload_xray() {
    log_info "Reloading Xray configuration..."

    local compose_dir="/opt/vless"

    if ! docker ps --format '{{.Names}}' | grep -q "^${XRAY_CONTAINER}$"; then
        log_warning "Xray container is not running, skipping reload"
        return 0
    fi

    # Try graceful reload via HUP signal first (using docker compose)
    if (cd "$compose_dir" && docker compose kill -s HUP xray) 2>/dev/null; then
        log_success "Xray configuration reloaded (HUP signal)"
        return 0
    else
        log_warning "Failed to send HUP signal, restarting container..."
        if (cd "$compose_dir" && docker compose restart xray) 2>/dev/null; then
            log_success "Xray container restarted"
            return 0
        else
            log_error "Failed to restart Xray container"
            return 1
        fi
    fi
}

# ============================================================================
# Generate VLESS URI
# ============================================================================

generate_vless_uri() {
    local username="$1"
    local uuid="$2"

    # Get server information
    local server_ip
    server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")

    # v5.1: Hardcoded port 443 (HAProxy external port for clients)
    # Xray listens on internal port 8443, but HAProxy forwards from 443
    local server_port=443

    local public_key
    public_key=$(cat "${VLESS_HOME}/keys/public.key" 2>/dev/null || echo "PUBLIC_KEY")

    # Get user-specific shortId from users.json (v1.2 schema - unique per user)
    # Fallback to config's shortIds[0] for backward compatibility with existing users
    local short_id
    if [[ -f "$USERS_JSON" ]]; then
        short_id=$(jq -r ".users[] | select(.username == \"$username\") | .shortId // empty" "$USERS_JSON" 2>/dev/null)
    fi

    # Fallback to config's first shortId if user doesn't have one (backward compatibility)
    if [[ -z "$short_id" || "$short_id" == "null" ]]; then
        short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_CONFIG" 2>/dev/null || echo "")
        log_warning "User '$username' does not have individual shortId, using server default (backward compatibility)"
    fi

    local server_name
    server_name=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$XRAY_CONFIG" 2>/dev/null || echo "www.google.com")

    # Get user-specific fingerprint from users.json (v1.3 schema)
    # Fallback to "chrome" for backward compatibility with existing users
    local fingerprint
    if [[ -f "$USERS_JSON" ]]; then
        fingerprint=$(jq -r ".users[] | select(.username == \"$username\") | .fingerprint // \"chrome\"" "$USERS_JSON" 2>/dev/null || echo "chrome")
    else
        fingerprint="chrome"
    fi

    # Construct VLESS URI
    # Format: vless://UUID@SERVER:PORT?param1=value1&param2=value2#REMARK
    local uri="vless://${uuid}@${server_ip}:${server_port}?"
    uri+="encryption=none"
    uri+="&flow=xtls-rprx-vision"
    uri+="&security=reality"
    uri+="&sni=${server_name}"
    uri+="&fp=${fingerprint}"
    uri+="&pbk=${public_key}"
    uri+="&sid=${short_id}"
    uri+="&type=tcp"
    uri+="#${username}"

    echo "$uri"
}

# ============================================================================
# Proxy Account Management (TASK-11.1, TASK-11.2)
# ============================================================================

# =============================================================================
# FUNCTION: update_proxy_accounts
# =============================================================================
# Description: Add user to SOCKS5/HTTP proxy accounts in xray_config.json
# Arguments:
#   $1 - username
#   $2 - proxy_password
# Returns: 0 on success, 1 on failure
# Related: TASK-11.1 (SOCKS5), TASK-11.2 (HTTP)
# =============================================================================
update_proxy_accounts() {
    local username="$1"
    local proxy_password="$2"

    # Check if SOCKS5 proxy inbound exists
    if ! jq -e '.inbounds[] | select(.tag == "socks5-proxy")' "${XRAY_CONFIG}" >/dev/null 2>&1; then
        log_info "Proxy support not enabled, skipping proxy account configuration"
        return 0
    fi

    log_info "Adding user to proxy accounts..."

    # Create account object
    local account_json
    account_json=$(jq -n \
        --arg user "$username" \
        --arg pass "$proxy_password" \
        '{user: $user, pass: $pass}')

    # Use temporary file for atomic update
    local temp_file
    temp_file=$(mktemp)

    # Add account to SOCKS5 inbound
    if ! jq --argjson account "$account_json" \
       '(.inbounds[] | select(.tag == "socks5-proxy") | .settings.accounts) += [$account]' \
       "${XRAY_CONFIG}" > "$temp_file"; then
        log_error "Failed to update SOCKS5 proxy accounts"
        rm -f "$temp_file"
        return 1
    fi

    # Add account to HTTP inbound (TASK-11.2) if it exists
    if jq -e '.inbounds[] | select(.tag == "http-proxy")' "$temp_file" >/dev/null 2>&1; then
        local temp_file2
        temp_file2=$(mktemp)

        if ! jq --argjson account "$account_json" \
           '(.inbounds[] | select(.tag == "http-proxy") | .settings.accounts) += [$account]' \
           "$temp_file" > "$temp_file2"; then
            log_error "Failed to update HTTP proxy accounts"
            rm -f "$temp_file" "$temp_file2"
            return 1
        fi

        # Replace temp file
        mv "$temp_file2" "$temp_file"
    fi

    # Move temp file to config (atomic)
    if ! mv "$temp_file" "${XRAY_CONFIG}"; then
        log_error "Failed to save updated Xray config"
        rm -f "$temp_file"
        return 1
    fi

    # Verify update - check SOCKS5 (required) and HTTP (optional)
    local socks5_ok=false
    local http_ok=false

    if jq -e --arg user "$username" \
       '.inbounds[] | select(.tag == "socks5-proxy") | .settings.accounts[] | select(.user == $user)' \
       "${XRAY_CONFIG}" >/dev/null 2>&1; then
        socks5_ok=true
        log_success "User added to SOCKS5 proxy accounts"
    fi

    if jq -e '.inbounds[] | select(.tag == "http-proxy")' "${XRAY_CONFIG}" >/dev/null 2>&1; then
        if jq -e --arg user "$username" \
           '.inbounds[] | select(.tag == "http-proxy") | .settings.accounts[] | select(.user == $user)' \
           "${XRAY_CONFIG}" >/dev/null 2>&1; then
            http_ok=true
            log_success "User added to HTTP proxy accounts"
        fi
    fi

    if $socks5_ok; then
        return 0
    else
        log_error "Failed to verify proxy account addition"
        return 1
    fi
}

# ============================================================================
# TASK-11.3: Proxy Password Management
# ============================================================================

# =============================================================================
# FUNCTION: show_proxy_credentials
# =============================================================================
# Description: Display proxy credentials for a user
# Arguments:
#   $1 - username
# Returns: 0 on success, 1 on failure
# Related: TASK-11.3 (Proxy Password Management)
# =============================================================================
show_proxy_credentials() {
    local username="$1"

    # Validate user exists
    if ! user_exists "$username"; then
        log_error "User '$username' not found"
        return 1
    fi

    # Get proxy password from users.json
    local proxy_password
    proxy_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" "$USERS_JSON" 2>/dev/null)

    if [[ -z "$proxy_password" || "$proxy_password" == "null" ]]; then
        log_warning "User '$username' does not have proxy credentials"
        log_info "Proxy support may not be enabled for this installation"
        return 1
    fi

    # Load environment variables to determine proxy mode
    local enable_public_proxy="false"
    local domain=""
    local server_ip

    if [[ -f "$ENV_FILE" ]]; then
        enable_public_proxy=$(grep -E "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "false")
        domain=$(grep -E "^DOMAIN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi

    # Get server IP for display
    server_ip=$(get_server_ip)

    # Determine proxy schemes and host based on mode
    local socks_scheme="socks5"
    local http_scheme="http"
    local proxy_host="${server_ip}"
    local mode_label="Localhost Only"

    if [[ "$enable_public_proxy" == "true" ]] && [[ -n "$domain" ]]; then
        socks_scheme="socks5s"
        http_scheme="https"
        proxy_host="${domain}"
        mode_label="Public Access with TLS (v4.0)"
    fi

    # Display credentials
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY CREDENTIALS: $username ($mode_label)"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Username: $username"
    echo "Password: $proxy_password"
    echo ""
    if [[ "$enable_public_proxy" == "true" ]]; then
        echo "⚠️  WARNING: Proxy accessible from public internet"
        echo ""
    fi
    echo "─────────────────────────────────────────────────────"
    echo "SOCKS5 Proxy:"
    echo "  Host:     ${proxy_host}"
    echo "  Port:     1080"
    echo "  URI:      ${socks_scheme}://${username}:${proxy_password}@${proxy_host}:1080"
    echo ""
    echo "HTTP Proxy:"
    echo "  Host:     ${proxy_host}"
    echo "  Port:     8118"
    echo "  URI:      ${http_scheme}://${username}:${proxy_password}@${proxy_host}:8118"
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "Usage Examples:"
    echo ""
    if [[ "$enable_public_proxy" == "true" ]]; then
        echo "  curl --proxy ${http_scheme}://${username}:${proxy_password}@${proxy_host}:8118 https://ifconfig.me"
    else
        echo "  curl --socks5 ${username}:${proxy_password}@${proxy_host}:1080 https://ifconfig.me"
        echo "  curl --proxy ${http_scheme}://${username}:${proxy_password}@${proxy_host}:8118 https://ifconfig.me"
    fi
    echo ""
    echo "VSCode (settings.json):"
    echo "  \"http.proxy\": \"${http_scheme}://${proxy_host}:8118\","
    echo "  \"http.proxyAuthorization\": \"$(echo -n "${username}:${proxy_password}" | base64)\""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: reset_proxy_password
# =============================================================================
# Description: Reset proxy password for a user
# Arguments:
#   $1 - username
# Returns: 0 on success, 1 on failure
# Related: TASK-11.3 (Proxy Password Management)
# =============================================================================
reset_proxy_password() {
    local username="$1"

    # Validate user exists
    if ! user_exists "$username"; then
        log_error "User '$username' not found"
        return 1
    fi

    # Check if user has proxy password
    local old_password
    old_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" "$USERS_JSON" 2>/dev/null)

    if [[ -z "$old_password" || "$old_password" == "null" ]]; then
        log_error "User '$username' does not have proxy credentials"
        log_info "Proxy support may not be enabled for this installation"
        return 1
    fi

    log_info "Resetting proxy password for user: $username"

    # Generate new password
    local new_password
    new_password=$(generate_proxy_password)
    if [[ -z "$new_password" ]]; then
        log_error "Failed to generate new password"
        return 1
    fi

    log_success "Generated new password: $new_password"

    # Update users.json with file locking
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    (
        flock -x 200

        local temp_file="${USERS_JSON}.tmp.$$"

        # Update proxy_password field
        if ! jq ".users |= map(if .username == \"$username\" then .proxy_password = \"$new_password\" else . end)" \
           "$USERS_JSON" > "$temp_file"; then
            log_error "Failed to update users.json"
            rm -f "$temp_file"
            return 1
        fi

        # Validate JSON
        if ! jq empty "$temp_file" 2>/dev/null; then
            log_error "Generated invalid JSON"
            rm -f "$temp_file"
            return 1
        fi

        # Atomic move
        mv "$temp_file" "$USERS_JSON"
        chmod 600 "$USERS_JSON"

    ) 200>"$LOCK_FILE"

    log_success "Updated users.json"

    # Update Xray config (remove old account, add new one)
    # First, remove old accounts
    if jq -e '.inbounds[] | select(.tag == "socks5-proxy")' "${XRAY_CONFIG}" >/dev/null 2>&1; then
        log_info "Updating proxy accounts in Xray config..."

        local temp_file
        temp_file=$(mktemp)

        # Remove user from SOCKS5
        if ! jq "(.inbounds[] | select(.tag == \"socks5-proxy\") | .settings.accounts) |= map(select(.user != \"$username\"))" \
           "${XRAY_CONFIG}" > "$temp_file"; then
            log_error "Failed to remove old SOCKS5 account"
            rm -f "$temp_file"
            return 1
        fi

        # Remove user from HTTP (if exists)
        if jq -e '.inbounds[] | select(.tag == "http-proxy")' "$temp_file" >/dev/null 2>&1; then
            local temp_file2
            temp_file2=$(mktemp)

            if ! jq "(.inbounds[] | select(.tag == \"http-proxy\") | .settings.accounts) |= map(select(.user != \"$username\"))" \
               "$temp_file" > "$temp_file2"; then
                log_error "Failed to remove old HTTP account"
                rm -f "$temp_file" "$temp_file2"
                return 1
            fi

            mv "$temp_file2" "$temp_file"
        fi

        # Save intermediate state
        mv "$temp_file" "${XRAY_CONFIG}"
    fi

    # Add new account with new password
    if ! update_proxy_accounts "$username" "$new_password"; then
        log_error "Failed to add new proxy accounts"
        return 1
    fi

    # Reload Xray
    log_info "Reloading Xray configuration..."
    if ! reload_xray; then
        log_warning "Xray reload failed, but password was reset"
    fi

    # Regenerate proxy configuration files with new password (TASK-11.4)
    log_info "Regenerating proxy configuration files..."
    if ! export_all_proxy_configs "$username" "$new_password"; then
        log_warning "Failed to regenerate proxy configs"
    fi

    # Load environment variables to determine proxy mode
    local enable_public_proxy="false"
    local domain=""
    local server_ip

    if [[ -f "$ENV_FILE" ]]; then
        enable_public_proxy=$(grep -E "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "false")
        domain=$(grep -E "^DOMAIN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi

    # Get server IP for display
    server_ip=$(get_server_ip)

    # Determine proxy schemes and host based on mode
    local socks_scheme="socks5"
    local http_scheme="http"
    local proxy_host="${server_ip}"
    local mode_label="v3.2"

    if [[ "$enable_public_proxy" == "true" ]] && [[ -n "$domain" ]]; then
        socks_scheme="socks5s"
        http_scheme="https"
        proxy_host="${domain}"
        mode_label="v4.0 - Public TLS"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY PASSWORD RESET SUCCESSFUL ($mode_label)"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Username: $username"
    echo "New Password: $new_password"
    echo ""
    if [[ "$enable_public_proxy" == "true" ]]; then
        echo "⚠️  WARNING: Proxy accessible from public internet"
        echo ""
    fi
    echo "SOCKS5: ${socks_scheme}://${username}:${new_password}@${proxy_host}:1080"
    echo "HTTP:   ${http_scheme}://${username}:${new_password}@${proxy_host}:8118"
    echo ""
    echo "NOTE: Proxy config files updated in /opt/vless/data/clients/$username/"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return 0
}

# ============================================================================
# TASK-11.4: Proxy Configuration File Export
# ============================================================================

# =============================================================================
# FUNCTION: get_server_ip
# =============================================================================
# Description: Get external server IP address from ENV_FILE or auto-detect
# Returns: IP address string or "SERVER_IP_NOT_DETECTED" fallback
# Related: v3.2 Public Proxy Support
# =============================================================================
get_server_ip() {
    local server_ip

    # Try reading from ENV_FILE first (preferred method)
    if [[ -f "$ENV_FILE" ]]; then
        server_ip=$(grep "^SERVER_IP=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    fi

    # Fallback: auto-detect if not in ENV_FILE or if empty
    if [[ -z "$server_ip" || "$server_ip" == "SERVER_IP_NOT_DETECTED" ]]; then
        server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    fi

    # Final fallback
    if [[ -z "$server_ip" ]]; then
        server_ip="SERVER_IP_NOT_DETECTED"
        log_warning "Failed to detect server IP address"
    fi

    echo "$server_ip"
}

# =============================================================================
# FUNCTION: export_socks5_config
# =============================================================================
# Description: Export SOCKS5 proxy configuration to file
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: socks5_config.txt with SOCKS5 URI
# Related: TASK-11.4 (Proxy Configuration Export)
# Note: v3.3 - Uses socks5s:// (TLS) for public proxy, socks5:// for localhost
# =============================================================================
export_socks5_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # v4.3: HAProxy-based TLS termination (unified architecture)
    # Architecture: Client → HAProxy (TLS) → Xray (plaintext)
    # IMPORTANT: HAProxy ALWAYS uses TLS when ENABLE_PUBLIC_PROXY=true
    local scheme="socks5"
    local host

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: Public proxy with HAProxy TLS termination
        scheme="socks5s"  # SOCKS5 with TLS (HAProxy provides TLS termination)
        host="${DOMAIN}"  # Use domain for TLS certificate validation
    else
        # Localhost-only, no TLS
        scheme="socks5"
        host="127.0.0.1"
    fi

    # Write SOCKS5 URI (port 1080 exposed by HAProxy, not Xray)
    echo "${scheme}://${username}:${password}@${host}:1080" \
        > "$output_dir/socks5_config.txt"

    chmod 600 "$output_dir/socks5_config.txt"
    return 0
}

# =============================================================================
# FUNCTION: export_http_config
# =============================================================================
# Description: Export HTTP proxy configuration to file
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: http_config.txt with HTTP URI
# Related: TASK-11.4 (Proxy Configuration Export)
# Note: v3.3 - Uses https:// (TLS) for public proxy, http:// for localhost
# =============================================================================
export_http_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # v4.3: HAProxy-based TLS termination (unified architecture)
    # Architecture: Client → HAProxy (TLS) → Xray (plaintext)
    # IMPORTANT: HAProxy ALWAYS uses TLS when ENABLE_PUBLIC_PROXY=true
    local scheme="http"
    local host

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: Public proxy with HAProxy TLS termination
        scheme="https"  # HTTPS proxy with TLS (HAProxy provides TLS termination)
        host="${DOMAIN}"  # Use domain for TLS certificate validation
    else
        # Localhost-only, no TLS
        scheme="http"
        host="127.0.0.1"
    fi

    # Write HTTP URI (port 8118 exposed by HAProxy, not Xray)
    echo "${scheme}://${username}:${password}@${host}:8118" \
        > "$output_dir/http_config.txt"

    chmod 600 "$output_dir/http_config.txt"
    return 0
}

# =============================================================================
# FUNCTION: export_vscode_config
# =============================================================================
# Description: Export VSCode proxy settings to JSON file
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: vscode_settings.json with VSCode proxy configuration
# Related: TASK-11.4 (Proxy Configuration Export)
# =============================================================================
export_vscode_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # Determine proxy URL based on mode (v3.3)
    local proxy_url
    local strict_ssl="false"

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: Public proxy with HAProxy TLS termination
        proxy_url="https://${DOMAIN}:8118"
        strict_ssl="true"  # Validate TLS certificate
    else
        # Localhost-only, no TLS (proxies bind to 127.0.0.1)
        proxy_url="http://127.0.0.1:8118"
        strict_ssl="false"
    fi

    # Generate base64 encoded credentials for VSCode proxyAuthorization
    # VSCode does not support credentials in http.proxy URL, requires separate auth header
    local auth_base64
    auth_base64=$(echo -n "${username}:${password}" | base64)

    # Write VSCode settings JSON with HTTP proxy and base64 auth
    # Note: Using HTTP proxy (port 8118) instead of SOCKS5 for better VSCode compatibility
    cat > "$output_dir/vscode_settings.json" <<EOF
{
  "http.proxy": "${proxy_url}",
  "http.proxyAuthorization": "${auth_base64}",
  "http.proxyStrictSSL": ${strict_ssl},
  "http.proxySupport": "on"
}
EOF

    chmod 600 "$output_dir/vscode_settings.json"
    return 0
}

# =============================================================================
# FUNCTION: export_docker_config
# =============================================================================
# Description: Export Docker daemon proxy configuration to JSON file
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: docker_daemon.json with Docker proxy configuration
# Related: TASK-11.4 (Proxy Configuration Export)
# =============================================================================
export_docker_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # Determine proxy URL based on mode (v3.3)
    local proxy_url

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: Public proxy with HAProxy TLS termination
        proxy_url="https://${username}:${password}@${DOMAIN}:8118"
    else
        # Localhost-only, no TLS (proxies bind to 127.0.0.1)
        proxy_url="http://${username}:${password}@127.0.0.1:8118"
    fi

    # Write Docker daemon config JSON
    cat > "$output_dir/docker_daemon.json" <<EOF
{
  "proxies": {
    "default": {
      "httpProxy": "${proxy_url}",
      "httpsProxy": "${proxy_url}",
      "noProxy": "localhost,127.0.0.0/8"
    }
  }
}
EOF

    chmod 600 "$output_dir/docker_daemon.json"
    return 0
}

# =============================================================================
# FUNCTION: export_bash_config
# =============================================================================
# Description: Export Bash proxy environment variables to shell script
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: bash_exports.sh with proxy environment variables
# Related: TASK-11.4 (Proxy Configuration Export)
# =============================================================================
export_bash_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # Determine proxy URL based on mode (v3.3)
    local proxy_url
    local mode_label

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: Public proxy with HAProxy TLS termination
        proxy_url="https://${username}:${password}@${DOMAIN}:8118"
        mode_label="v4.3 - Public Access with HAProxy TLS"
    else
        # Localhost-only, no TLS (proxies bind to 127.0.0.1)
        proxy_url="http://${username}:${password}@127.0.0.1:8118"
        mode_label="Localhost Only (No TLS)"
    fi

    # Write bash exports script
    cat > "$output_dir/bash_exports.sh" <<EOF
#!/bin/bash
# VLESS Reality Proxy Configuration (${mode_label})
# Usage: source bash_exports.sh

export http_proxy="${proxy_url}"
export https_proxy="${proxy_url}"
export HTTP_PROXY="\$http_proxy"
export HTTPS_PROXY="\$https_proxy"
export NO_PROXY="localhost,127.0.0.0/8"

echo "Proxy environment variables set (${mode_label}):"
echo "  http_proxy=\$http_proxy"
echo "  https_proxy=\$https_proxy"
EOF

    chmod 700 "$output_dir/bash_exports.sh"
    return 0
}

# =============================================================================
# FUNCTION: export_git_config
# =============================================================================
# Description: Export Git proxy configuration instructions to text file
# Arguments:
#   $1 - username
#   $2 - proxy_password
#   $3 - output_dir (optional, defaults to /opt/vless/data/clients/$username)
# Returns: 0 on success, 1 on failure
# Output: git_config.txt with Git proxy setup commands
# Related: TASK-3.6 (v3.3 Git Config)
# =============================================================================
export_git_config() {
    local username="$1"
    local password="$2"
    local output_dir="${3:-${CLIENTS_DIR}/${username}}"

    # Create directory if not exists
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"

    # Determine proxy URL based on mode (v4.0 - simplified)
    local socks_proxy
    local http_proxy

    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        # v4.3: HAProxy ALWAYS uses TLS for public mode
        socks_proxy="socks5s://${username}:${password}@${DOMAIN}:1080"
        http_proxy="https://${username}:${password}@${DOMAIN}:8118"
    else
        # Localhost-only, no TLS
        socks_proxy="socks5://${username}:${password}@127.0.0.1:1080"
        http_proxy="http://${username}:${password}@127.0.0.1:8118"
    fi

    # Write Git config instructions
    cat > "$output_dir/git_config.txt" <<EOF
# Git Proxy Configuration
# VLESS Reality VPN - Git Setup Instructions

## Option 1: SOCKS5 Proxy (Recommended)
# Configure Git to use SOCKS5 proxy for all operations:
git config --global http.proxy ${socks_proxy}
git config --global https.proxy ${socks_proxy}

# Or for a specific repository:
cd /path/to/repo
git config http.proxy ${socks_proxy}
git config https.proxy ${socks_proxy}

## Option 2: HTTP Proxy
# Alternatively, use HTTP proxy:
git config --global http.proxy ${http_proxy}
git config --global https.proxy ${http_proxy}

## Remove Proxy Configuration
# To remove proxy settings:
git config --global --unset http.proxy
git config --global --unset https.proxy

## Verify Configuration
# Check current Git proxy settings:
git config --global --get http.proxy
git config --global --get https.proxy

## Test Git Operations
# Test cloning a repository:
git clone https://github.com/torvalds/linux.git

## Notes:
# - SOCKS5 proxy is recommended for better performance
# - Use --global flag for system-wide configuration
# - Use repository-specific config for selective proxy usage
# - Git proxy works for both HTTP and SSH protocols when using http.proxy
EOF

    chmod 600 "$output_dir/git_config.txt"
    return 0
}

# =============================================================================
# FUNCTION: export_all_proxy_configs
# =============================================================================
# Description: Export all 6 proxy configuration files for a user (v3.3)
# Arguments:
#   $1 - username
#   $2 - proxy_password (optional, will read from users.json if not provided)
# Returns: 0 on success, 1 on failure
# Output: 6 proxy config files in /opt/vless/data/clients/$username/
# Related: TASK-11.4 (Proxy Configuration Export)
# =============================================================================
export_all_proxy_configs() {
    local username="$1"
    local proxy_password="${2:-}"

    # Load environment variables from .env file (v3.4 TLS support)
    # Required for export functions to determine protocol (socks5/socks5s, http/https)
    if [[ -f "$ENV_FILE" ]]; then
        # Export variables so they're available in export_* functions
        export ENABLE_PUBLIC_PROXY=$(grep -E "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
        export ENABLE_PROXY_TLS=$(grep -E "^ENABLE_PROXY_TLS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
        export DOMAIN=$(grep -E "^DOMAIN=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)

        # Set defaults if not found in .env
        [[ -z "$ENABLE_PUBLIC_PROXY" ]] && export ENABLE_PUBLIC_PROXY="false"
        [[ -z "$ENABLE_PROXY_TLS" ]] && export ENABLE_PROXY_TLS="false"
        [[ -z "$DOMAIN" ]] && export DOMAIN=""
    else
        # .env file not found, use defaults (no TLS)
        export ENABLE_PUBLIC_PROXY="false"
        export ENABLE_PROXY_TLS="false"
        export DOMAIN=""
    fi

    # If password not provided, read from users.json
    if [[ -z "$proxy_password" ]]; then
        proxy_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" "$USERS_JSON" 2>/dev/null)

        if [[ -z "$proxy_password" || "$proxy_password" == "null" ]]; then
            log_warning "No proxy password found for user '$username'"
            log_info "Skipping proxy config export (proxy may not be enabled)"
            return 0
        fi
    fi

    local output_dir="${CLIENTS_DIR}/${username}"

    log_info "Exporting proxy configurations for user '$username'..."

    # Export all 6 config files (v3.3)
    export_socks5_config "$username" "$proxy_password" "$output_dir" || return 1
    export_http_config "$username" "$proxy_password" "$output_dir" || return 1
    export_vscode_config "$username" "$proxy_password" "$output_dir" || return 1
    export_docker_config "$username" "$proxy_password" "$output_dir" || return 1
    export_bash_config "$username" "$proxy_password" "$output_dir" || return 1
    export_git_config "$username" "$proxy_password" "$output_dir" || return 1

    log_success "Proxy configs exported to: $output_dir/"
    log_info "Files: socks5_config.txt, http_config.txt, vscode_settings.json, docker_daemon.json, bash_exports.sh, git_config.txt"

    return 0
}

# =============================================================================
# FUNCTION: regenerate_configs (v3.3)
# =============================================================================
# Description: Regenerate all proxy configuration files for existing user
#              Useful for v3.2 → v3.3 migration (IP → domain, plaintext → TLS)
# Arguments:
#   $1 - username
# Returns: 0 on success, 1 on failure
# Related: TASK-5.2 (v3.3 Migration Support)
# =============================================================================
regenerate_configs() {
    local username="$1"

    echo ""
    log_info "Regenerating configurations for user: $username"
    echo ""

    # Step 1: Validate user exists
    if ! user_exists "$username"; then
        log_error "User '$username' not found"
        return 1
    fi

    # Step 2: Get user data from users.json
    local user_info
    user_info=$(get_user_info "$username")
    if [[ -z "$user_info" ]]; then
        log_error "Failed to retrieve user information"
        return 1
    fi

    local uuid
    local proxy_password

    uuid=$(echo "$user_info" | jq -r '.uuid')
    proxy_password=$(echo "$user_info" | jq -r '.proxy_password // empty')

    log_success "Retrieved user data:"
    log_info "  UUID: $uuid"
    if [[ -n "$proxy_password" ]]; then
        log_info "  Proxy password: [exists]"
    else
        log_warning "  Proxy password: [not set - proxy may not be enabled]"
    fi

    # Step 3: Regenerate VLESS configuration
    local user_dir="${CLIENTS_DIR}/${username}"
    mkdir -p "$user_dir"
    chmod 700 "$user_dir"

    log_info "Regenerating VLESS configuration..."

    # Generate VLESS URI
    local vless_uri
    vless_uri=$(generate_vless_uri "$username" "$uuid")

    # Save VLESS URI
    echo "$vless_uri" > "${user_dir}/vless_uri.txt"
    chmod 600 "${user_dir}/vless_uri.txt"
    log_success "VLESS URI updated"

    # Generate QR code if qrencode available
    if command -v qrencode &>/dev/null; then
        qrencode -o "${user_dir}/vless_qr.png" -t PNG -s 10 "$vless_uri" 2>/dev/null
        chmod 600 "${user_dir}/vless_qr.png"
        log_success "QR code regenerated"
    else
        log_warning "qrencode not available - QR code not generated"
    fi

    # Step 4: Regenerate proxy configurations (if proxy enabled)
    if [[ -n "$proxy_password" ]]; then
        log_info "Regenerating proxy configurations..."

        if ! export_all_proxy_configs "$username" "$proxy_password"; then
            log_error "Failed to regenerate proxy configs"
            return 1
        fi

        log_success "Proxy configs regenerated (6 files)"
    else
        log_info "Proxy not enabled, skipping proxy config regeneration"
    fi

    # Step 5: Display summary
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  CONFIGURATION REGENERATION COMPLETE"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "User:      $username"
    echo "UUID:      $uuid"
    echo "Directory: $user_dir"
    echo ""

    if [[ -n "$proxy_password" ]]; then
        # Determine mode
        local mode_label="Localhost Only"
        local host

        if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
            mode_label="Public Access with TLS"
            host="${DOMAIN}"
        else
            host=$(get_server_ip)
        fi

        echo "Proxy Mode: $mode_label"
        echo ""
        echo "VLESS Config Files:"
        echo "  • vless_uri.txt"
        if [[ -f "${user_dir}/vless_qr.png" ]]; then
            echo "  • vless_qr.png"
        fi
        echo ""
        echo "Proxy Config Files (v3.3):"
        echo "  • socks5_config.txt"
        echo "  • http_config.txt"
        echo "  • vscode_settings.json"
        echo "  • docker_daemon.json"
        echo "  • bash_exports.sh"
        echo "  • git_config.txt"
        echo ""
        echo "Proxy URIs:"
        if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
            echo "  SOCKS5: socks5s://${username}:${proxy_password}@${host}:1080"
            echo "  HTTP:   https://${username}:${proxy_password}@${host}:8118"
        else
            echo "  SOCKS5: socks5://${username}:${proxy_password}@${host}:1080"
            echo "  HTTP:   http://${username}:${proxy_password}@${host}:8118"
        fi
    else
        echo "Files:"
        echo "  • vless_uri.txt"
        if [[ -f "${user_dir}/vless_qr.png" ]]; then
            echo "  • vless_qr.png"
        fi
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return 0
}

# ============================================================================
# TASK-6.1: User Creation Workflow
# ============================================================================

create_user() {
    local username="$1"

    echo ""
    log_info "Creating new VPN user: $username"
    echo ""

    # Step 1: Validate username
    if ! validate_username "$username"; then
        return 1
    fi

    # Step 2: Check if user already exists
    if user_exists "$username"; then
        log_error "User '$username' already exists"
        return 1
    fi

    # Step 3: Generate UUID
    local uuid
    uuid=$(generate_uuid)
    if [[ -z "$uuid" ]]; then
        log_error "Failed to generate UUID"
        return 1
    fi
    log_success "Generated UUID: $uuid"

    # Step 3.1: Generate unique shortId (v1.2 schema - per-user shortIds)
    local short_id
    short_id=$(generate_short_id)
    if [[ -z "$short_id" ]]; then
        log_error "Failed to generate shortId"
        return 1
    fi
    log_success "Generated shortId: $short_id"

    # Step 3.5: Generate proxy password (TASK-11.1)
    local proxy_password
    proxy_password=$(generate_proxy_password)
    if [[ -z "$proxy_password" ]]; then
        log_error "Failed to generate proxy password"
        return 1
    fi
    log_success "Generated proxy password: $proxy_password"

    # Step 3.6: Select TLS fingerprint for device type
    echo ""
    log_info "Select TLS fingerprint for client device:"
    echo "  1) Android (chrome fingerprint) - Recommended for Android devices"
    echo "  2) iOS (safari fingerprint) - Recommended for iOS/macOS devices"
    echo "  3) Other/Universal (firefox fingerprint) - Universal compatibility"
    echo ""

    local fingerprint="chrome"  # Default
    local fingerprint_choice

    while true; do
        read -r -p "Enter choice [1-3, default: 1]: " fingerprint_choice

        # Default to 1 if empty
        if [[ -z "$fingerprint_choice" ]]; then
            fingerprint_choice="1"
        fi

        case "$fingerprint_choice" in
            1)
                fingerprint="chrome"
                log_success "Selected fingerprint: chrome (Android)"
                break
                ;;
            2)
                fingerprint="safari"
                log_success "Selected fingerprint: safari (iOS/macOS)"
                break
                ;;
            3)
                fingerprint="firefox"
                log_success "Selected fingerprint: firefox (Universal)"
                break
                ;;
            *)
                log_error "Invalid choice. Please enter 1, 2, or 3"
                ;;
        esac
    done

    # Step 3.7: Select external proxy (optional, v5.24)
    echo ""
    log_info "External Proxy Configuration (optional):"
    echo "  Route this user's traffic through an external proxy?"
    echo ""

    local external_proxy_id=""
    local external_proxy_db="/opt/vless/config/external_proxy.json"

    # Check if external proxies are configured
    if [[ -f "$external_proxy_db" ]]; then
        local proxy_count
        proxy_count=$(jq -r '.proxies | length' "$external_proxy_db" 2>/dev/null || echo "0")

        if [[ "$proxy_count" != "0" ]]; then
            echo "  Available external proxies:"
            jq -r '.proxies[] | "    \(.id): \(.type)://\(.address):\(.port)"' "$external_proxy_db" 2>/dev/null
            echo "    none: Direct routing (no external proxy)"
            echo ""

            local proxy_choice
            while true; do
                read -r -p "Enter proxy ID or 'none' [default: none]: " proxy_choice

                # Default to none if empty
                if [[ -z "$proxy_choice" ]]; then
                    proxy_choice="none"
                fi

                if [[ "$proxy_choice" == "none" ]]; then
                    log_success "Selected: Direct routing (no external proxy)"
                    external_proxy_id=""
                    break
                else
                    # Validate proxy exists
                    if validate_external_proxy_assignment "$proxy_choice"; then
                        external_proxy_id="$proxy_choice"
                        log_success "Selected external proxy: $external_proxy_id"
                        break
                    else
                        log_error "Invalid proxy ID. Please try again or enter 'none'"
                    fi
                fi
            done
        else
            echo "  No external proxies configured."
            echo "  Run 'vless-external-proxy add' to configure an external proxy."
            echo ""
            log_info "Using direct routing (no external proxy)"
            external_proxy_id=""
        fi
    else
        echo "  No external proxies configured."
        echo "  Run 'vless-external-proxy add' to configure an external proxy."
        echo ""
        log_info "Using direct routing (no external proxy)"
        external_proxy_id=""
    fi

    # Step 4: Create user directory
    local user_dir="${CLIENTS_DIR}/${username}"
    if ! mkdir -p "$user_dir"; then
        log_error "Failed to create user directory: $user_dir"
        return 1
    fi
    chmod 700 "$user_dir"
    log_success "Created user directory: $user_dir"

    # Step 5: Add user to users.json (atomic) with proxy password, shortId, fingerprint, and external_proxy_id (v5.24)
    if ! add_user_to_json "$username" "$uuid" "$proxy_password" "$short_id" "$fingerprint" "$external_proxy_id"; then
        # Cleanup on failure
        rm -rf "$user_dir"
        return 1
    fi

    # Step 6: Add client to Xray configuration (VLESS) and shortId to realitySettings
    if ! add_client_to_xray "$username" "$uuid" "$short_id"; then
        # Rollback: remove from users.json
        log_warning "Rolling back user creation..."
        remove_user_from_json "$username"
        rm -rf "$user_dir"
        return 1
    fi

    # Step 6.5: Add user to proxy accounts (TASK-11.1)
    if ! update_proxy_accounts "$username" "$proxy_password"; then
        log_warning "Failed to add user to proxy accounts (continuing anyway)"
        # Don't fail completely - proxy is optional feature
    fi

    # Step 6.6: Apply per-user routing (v5.24)
    # Only if external_proxy_id is set, otherwise skip
    if [[ -n "$external_proxy_id" ]]; then
        log_info "Applying per-user external proxy routing..."
        if ! apply_per_user_routing; then
            log_warning "Failed to apply per-user routing (continuing anyway)"
            # Don't fail completely - routing will be applied on next reload
        fi
    fi

    # Step 7: Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed, but user was created successfully"
    fi

    # Step 8: Generate VLESS URI
    local vless_uri
    vless_uri=$(generate_vless_uri "$username" "$uuid")

    # Step 9: Generate QR code and export connection config (EPIC-7)
    log_success "User '$username' created successfully!"
    echo ""

    if command -v generate_qr_code &>/dev/null; then
        # QR generator is available, use it
        generate_qr_code "$username" "$uuid" "$vless_uri"
    else
        # Fallback: just save URI
        echo "$vless_uri" > "${user_dir}/vless_uri.txt"
        chmod 600 "${user_dir}/vless_uri.txt"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Username:  $username"
        echo "  UUID:      $uuid"
        echo "  Directory: $user_dir"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "VLESS URI:"
        echo "$vless_uri"
        echo ""
        echo "URI saved to: ${user_dir}/vless_uri.txt"
        echo ""
        log_warning "QR code generator not available. Install qrencode: apt-get install qrencode"
        echo ""
    fi

    # Step 10: Export proxy configuration files (TASK-11.4)
    if ! export_all_proxy_configs "$username" "$proxy_password"; then
        log_warning "Failed to export proxy configs (continuing anyway)"
    else
        # v5.1: Display proxy URIs after successful export
        local socks5_uri
        local http_uri
        local user_dir="${CLIENTS_DIR}/${username}"

        if [[ -f "${user_dir}/socks5_config.txt" ]]; then
            socks5_uri=$(cat "${user_dir}/socks5_config.txt")
        fi

        if [[ -f "${user_dir}/http_config.txt" ]]; then
            http_uri=$(cat "${user_dir}/http_config.txt")
        fi

        if [[ -n "$socks5_uri" ]] || [[ -n "$http_uri" ]]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  PROXY CONFIGURATION"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            [[ -n "$socks5_uri" ]] && echo "SOCKS5: $socks5_uri"
            [[ -n "$http_uri" ]] && echo "HTTP:   $http_uri"
            echo ""
            echo "Config files saved to: ${user_dir}/"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
        fi
    fi

    return 0
}

# ============================================================================
# TASK-6.5: User Removal
# ============================================================================

remove_user() {
    local username="$1"

    echo ""
    log_info "Removing VPN user: $username"
    echo ""

    # Step 1: Validate username
    if ! validate_username "$username"; then
        return 1
    fi

    # Step 2: Check if user exists
    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    # Step 3: Get user UUID
    local uuid
    uuid=$(jq -r ".users[] | select(.username == \"$username\") | .uuid" "$USERS_JSON" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        log_error "Failed to retrieve UUID for user '$username'"
        return 1
    fi

    # Step 4: Remove client from Xray configuration and shortId from array (v1.2)
    if ! remove_client_from_xray "$uuid" "$username"; then
        log_error "Failed to remove client from Xray configuration"
        return 1
    fi

    # Step 5: Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed"
    fi

    # Step 6: Remove from users.json
    if ! remove_user_from_json "$username"; then
        log_error "Failed to remove user from database"
        return 1
    fi

    # Step 7: Remove user directory
    local user_dir="${CLIENTS_DIR}/${username}"
    if [[ -d "$user_dir" ]]; then
        rm -rf "$user_dir"
        log_success "Removed user directory: $user_dir"
    fi

    # Display success message
    echo ""
    log_success "User '$username' removed successfully!"
    echo ""

    return 0
}

# ============================================================================
# List All Users
# ============================================================================

list_users() {
    if [[ ! -f "$USERS_JSON" ]]; then
        log_error "Users database not found: $USERS_JSON"
        return 1
    fi

    local user_count
    user_count=$(jq '.users | length' "$USERS_JSON" 2>/dev/null || echo "0")

    if [[ "$user_count" -eq 0 ]]; then
        echo ""
        log_info "No users found"
        echo ""
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VPN Users ($user_count total)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    jq -r '.users[] | "  \(.username)\n    UUID: \(.uuid)\n    Created: \(.created)\n"' "$USERS_JSON"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# ============================================================================
# Set External Proxy for User (v5.24)
# ============================================================================

cmd_set_user_proxy() {
    local username="$1"
    local proxy_id="${2:-}"

    # Validate username
    if [[ -z "$username" ]]; then
        log_error "Username required"
        echo "Usage: vless set-proxy <username> <proxy-id|none>"
        return 1
    fi

    # Check if user exists
    if ! user_exists "$username"; then
        log_error "User '$username' not found"
        return 1
    fi

    # Handle "none" keyword
    if [[ "$proxy_id" == "none" ]] || [[ "$proxy_id" == "null" ]] || [[ -z "$proxy_id" ]]; then
        proxy_id=""
    fi

    # Validate proxy ID (if not empty)
    if [[ -n "$proxy_id" ]]; then
        if ! validate_external_proxy_assignment "$proxy_id"; then
            return 1
        fi
    fi

    log_info "Updating external proxy assignment for user: $username"

    # Update users.json with flock
    (
        flock -x 200 || {
            log_error "Failed to acquire lock on users database"
            return 1
        }

        # Update external_proxy_id field
        local temp_file
        temp_file=$(mktemp)

        if [[ -n "$proxy_id" ]]; then
            jq --arg username "$username" \
               --arg proxy_id "$proxy_id" \
               '(.users[] | select(.username == $username) | .external_proxy_id) = $proxy_id' \
               "$USERS_JSON" > "$temp_file"
        else
            # Set to null for direct routing
            jq --arg username "$username" \
               '(.users[] | select(.username == $username) | .external_proxy_id) = null' \
               "$USERS_JSON" > "$temp_file"
        fi

        if [[ $? -eq 0 ]]; then
            mv "$temp_file" "$USERS_JSON"
            chmod 600 "$USERS_JSON"
        else
            rm -f "$temp_file"
            log_error "Failed to update users database"
            return 1
        fi

    ) 200>"${USERS_JSON}.lock"

    # Apply per-user routing
    log_info "Applying per-user routing configuration..."
    if ! apply_per_user_routing; then
        log_warning "Failed to apply per-user routing (changes saved to database)"
        return 1
    fi

    # Display result
    echo ""
    if [[ -n "$proxy_id" ]]; then
        log_success "✓ User '$username' now routes through external proxy: $proxy_id"
    else
        log_success "✓ User '$username' now uses direct routing (no external proxy)"
    fi

    echo ""
    log_info "Xray will reload automatically within 30 seconds"
    log_info "Or run: sudo docker restart vless_xray"
    echo ""

    return 0
}

# ============================================================================
# Show External Proxy for User (v5.24)
# ============================================================================

cmd_show_user_proxy() {
    local username="$1"

    # Validate username
    if [[ -z "$username" ]]; then
        log_error "Username required"
        echo "Usage: vless show-proxy <username>"
        return 1
    fi

    # Check if user exists
    if ! user_exists "$username"; then
        log_error "User '$username' not found"
        return 1
    fi

    # Get proxy assignment from users.json
    local proxy_id
    proxy_id=$(jq -r --arg username "$username" \
        '.users[] | select(.username == $username) | .external_proxy_id // "null"' \
        "$USERS_JSON" 2>/dev/null)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  External Proxy Assignment: $username"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$proxy_id" == "null" ]] || [[ -z "$proxy_id" ]]; then
        echo "  Routing Mode: Direct (no external proxy)"
        echo "  Outbound Tag: direct"
        echo ""
        echo "  Traffic Flow:"
        echo "    Client → HAProxy → Xray → Internet"
    else
        # Get proxy details from external_proxy.json
        local ext_proxy_db="/opt/vless/config/external_proxy.json"
        if [[ -f "$ext_proxy_db" ]]; then
            local proxy_type proxy_address proxy_port test_status
            proxy_type=$(jq -r --arg id "$proxy_id" \
                '.proxies[] | select(.id == $id) | .type' \
                "$ext_proxy_db" 2>/dev/null || echo "unknown")
            proxy_address=$(jq -r --arg id "$proxy_id" \
                '.proxies[] | select(.id == $id) | .address' \
                "$ext_proxy_db" 2>/dev/null || echo "unknown")
            proxy_port=$(jq -r --arg id "$proxy_id" \
                '.proxies[] | select(.id == $id) | .port' \
                "$ext_proxy_db" 2>/dev/null || echo "unknown")
            test_status=$(jq -r --arg id "$proxy_id" \
                '.proxies[] | select(.id == $id) | .metadata.test_result.status // "never tested"' \
                "$ext_proxy_db" 2>/dev/null || echo "never tested")

            echo "  Routing Mode: Via External Proxy"
            echo "  Proxy ID: $proxy_id"
            echo "  Outbound Tag: external-proxy-$proxy_id"
            echo ""
            echo "  Proxy Details:"
            echo "    Type: $proxy_type"
            echo "    Address: $proxy_address:$proxy_port"
            echo "    Test Status: $test_status"
            echo ""
            echo "  Traffic Flow:"
            echo "    Client → HAProxy → Xray → External Proxy → Internet"
        else
            echo "  Routing Mode: Via External Proxy"
            echo "  Proxy ID: $proxy_id"
            echo "  Outbound Tag: external-proxy-$proxy_id"
            echo ""
            echo "  ⚠️  External proxy database not found"
        fi
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# ============================================================================
# List All Proxy Assignments (v5.24)
# ============================================================================

cmd_list_proxy_assignments() {
    if [[ ! -f "$USERS_JSON" ]]; then
        log_error "Users database not found: $USERS_JSON"
        return 1
    fi

    local user_count
    user_count=$(jq '.users | length' "$USERS_JSON" 2>/dev/null || echo "0")

    if [[ "$user_count" -eq 0 ]]; then
        echo ""
        log_info "No users found"
        echo ""
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  External Proxy Assignments ($user_count users)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Group users by proxy assignment
    local direct_users=()
    local proxied_users=()

    # Read all users and group them
    while IFS=$'\t' read -r username proxy_id; do
        if [[ "$proxy_id" == "null" ]] || [[ -z "$proxy_id" ]]; then
            direct_users+=("$username")
        else
            proxied_users+=("$username:$proxy_id")
        fi
    done < <(jq -r '.users[] | "\(.username)\t\(.external_proxy_id // "null")"' "$USERS_JSON")

    # Display direct routing users
    if [[ ${#direct_users[@]} -gt 0 ]]; then
        echo "  Direct Routing (${#direct_users[@]} users):"
        for username in "${direct_users[@]}"; do
            echo "    • $username → direct"
        done
        echo ""
    fi

    # Display proxied users (grouped by proxy_id)
    if [[ ${#proxied_users[@]} -gt 0 ]]; then
        # Group by proxy_id
        declare -A proxy_groups
        for entry in "${proxied_users[@]}"; do
            local user="${entry%%:*}"
            local pid="${entry##*:}"
            proxy_groups["$pid"]+="$user "
        done

        echo "  Via External Proxy (${#proxied_users[@]} users):"
        for proxy_id in "${!proxy_groups[@]}"; do
            local users_list="${proxy_groups[$proxy_id]}"
            local user_array=($users_list)

            # Get proxy details
            local ext_proxy_db="/opt/vless/config/external_proxy.json"
            local proxy_info="$proxy_id"
            if [[ -f "$ext_proxy_db" ]]; then
                local proxy_type proxy_address
                proxy_type=$(jq -r --arg id "$proxy_id" \
                    '.proxies[] | select(.id == $id) | .type' \
                    "$ext_proxy_db" 2>/dev/null || echo "")
                proxy_address=$(jq -r --arg id "$proxy_id" \
                    '.proxies[] | select(.id == $id) | .address' \
                    "$ext_proxy_db" 2>/dev/null || echo "")

                if [[ -n "$proxy_type" ]] && [[ -n "$proxy_address" ]]; then
                    proxy_info="$proxy_id ($proxy_type://$proxy_address)"
                fi
            fi

            echo "    Proxy: $proxy_info"
            for user in "${user_array[@]}"; do
                echo "      • $user"
            done
            echo ""
        done
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show summary
    echo "Summary:"
    echo "  Total Users: $user_count"
    echo "  Direct Routing: ${#direct_users[@]}"
    echo "  Via External Proxy: ${#proxied_users[@]}"
    echo ""

    return 0
}

# ============================================================================
# Export Functions
# ============================================================================

# Export all functions for use by other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f create_user
    export -f remove_user
    export -f list_users
    export -f user_exists
    export -f get_user_info
    export -f validate_username
    export -f validate_fingerprint
    export -f validate_external_proxy_assignment
    export -f generate_uuid
    export -f generate_short_id
    export -f regenerate_configs
    export -f add_user_to_json
    export -f remove_user_from_json
    export -f add_client_to_xray
    export -f remove_client_from_xray
    export -f apply_per_user_routing
    export -f reload_xray
    export -f cmd_set_user_proxy
    export -f cmd_show_user_proxy
    export -f cmd_list_proxy_assignments
    export -f generate_vless_uri
    export -f export_socks5_config
    export -f export_http_config
    export -f export_vscode_config
    export -f export_docker_config
    export -f export_bash_config
    export -f export_git_config
    export -f export_all_proxy_configs
    export -f get_server_ip
    export -f log_info
    export -f log_success
    export -f log_warning
    export -f log_error
fi

# ============================================================================
# Main Execution (if run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    case "${1:-}" in
        create|add)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 create <username>"
                exit 1
            fi
            create_user "$2"
            ;;
        remove|delete|rm)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 remove <username>"
                exit 1
            fi
            remove_user "$2"
            ;;
        list|ls)
            list_users
            ;;
        regenerate|regen)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 regenerate <username>"
                exit 1
            fi
            regenerate_configs "$2"
            ;;
        *)
            echo "Usage: $0 {create|remove|list|regenerate} [username]"
            echo ""
            echo "Commands:"
            echo "  create <username>     - Create new VPN user"
            echo "  remove <username>     - Remove existing user"
            echo "  list                  - List all users"
            echo "  regenerate <username> - Regenerate config files (v3.3 migration)"
            echo ""
            exit 1
            ;;
    esac
fi

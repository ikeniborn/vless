#!/bin/bash
#
# External Proxy Manager Module
# Part of familyTraffic VPN Deployment System (v5.33)
#
# Purpose: Manage external proxy configuration for routing traffic through
#          upstream SOCKS5/HTTP proxies after Xray processing
#
# Usage: source this file from orchestrator.sh or CLI scripts
#
# Architecture: Client → HAProxy → Xray → External Proxy → Internet
#
# Version: 5.23.1
# Date: 2025-10-27

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Color codes for output
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && CYAN='\033[0;36m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# Paths
[[ -z "${EXTERNAL_PROXY_DB:-}" ]] && readonly EXTERNAL_PROXY_DB="/opt/familytraffic/config/external_proxy.json"
[[ -z "${XRAY_CONFIG:-}" ]] && readonly XRAY_CONFIG="/opt/familytraffic/config/xray_config.json"

# Supported proxy types
[[ -z "${SUPPORTED_PROXY_TYPES:-}" ]] && readonly SUPPORTED_PROXY_TYPES=("socks5" "socks5s" "http" "https")

# Default retry settings
[[ -z "${DEFAULT_MAX_RETRY_ATTEMPTS:-}" ]] && readonly DEFAULT_MAX_RETRY_ATTEMPTS=3
[[ -z "${DEFAULT_BACKOFF_MULTIPLIER:-}" ]] && readonly DEFAULT_BACKOFF_MULTIPLIER=2

# =============================================================================
# FUNCTION: init_external_proxy_db
# =============================================================================
# Description: Initialize external_proxy.json database
# Arguments: None
# Returns: 0 on success, 1 on failure
# =============================================================================
init_external_proxy_db() {
    echo -e "${CYAN}Initializing external proxy database...${NC}"

    # Check if file already exists
    if [[ -f "$EXTERNAL_PROXY_DB" ]]; then
        echo "  ℹ️  Database already exists: $EXTERNAL_PROXY_DB"

        # Validate existing JSON
        if jq empty "$EXTERNAL_PROXY_DB" 2>/dev/null; then
            echo -e "${GREEN}  ✓ Existing database is valid${NC}"
            return 0
        else
            echo -e "${YELLOW}  ⚠️  Existing database is corrupted, recreating...${NC}"
        fi
    fi

    # Create directory if missing
    local db_dir
    db_dir=$(dirname "$EXTERNAL_PROXY_DB")
    if [[ ! -d "$db_dir" ]]; then
        mkdir -p "$db_dir" || {
            echo -e "${RED}Failed to create directory: $db_dir${NC}" >&2
            return 1
        }
    fi

    # Create initial database structure
    local timestamp
    timestamp=$(date -Iseconds)

    cat > "$EXTERNAL_PROXY_DB" <<EOF
{
  "enabled": false,
  "proxies": [],
  "routing": {
    "mode": "all-traffic",
    "fallback": "retry-then-block"
  },
  "metadata": {
    "created": "${timestamp}",
    "last_modified": "${timestamp}",
    "version": "5.23.1"
  }
}
EOF

    # Validate created file
    if ! jq empty "$EXTERNAL_PROXY_DB" 2>/dev/null; then
        echo -e "${RED}Failed to create valid JSON database${NC}" >&2
        return 1
    fi

    # Set permissions (600 - sensitive data)
    chmod 600 "$EXTERNAL_PROXY_DB"
    chown root:root "$EXTERNAL_PROXY_DB" 2>/dev/null || true

    echo "  ✓ Database created: $EXTERNAL_PROXY_DB"
    echo "  ✓ Permissions: 600 (read/write for root only)"
    echo -e "${GREEN}✓ External proxy database initialized${NC}"
    return 0
}

# =============================================================================
# FUNCTION: validate_proxy_config
# =============================================================================
# Description: Validate proxy configuration parameters
# Arguments:
#   $1 - type (socks5, socks5s, http, https)
#   $2 - address (hostname or IP)
#   $3 - port (1-65535)
#   $4 - username (optional, can be empty)
#   $5 - password (optional, can be empty)
# Returns: 0 if valid, 1 if invalid
# =============================================================================
validate_proxy_config() {
    local type="${1:-}"
    local address="${2:-}"
    local port="${3:-}"
    local username="${4:-}"
    local password="${5:-}"

    local errors=0

    # Validate type
    if [[ -z "$type" ]]; then
        echo -e "${RED}  ✗ Proxy type is required${NC}" >&2
        ((errors++))
    elif ! [[ " ${SUPPORTED_PROXY_TYPES[*]} " =~ " ${type} " ]]; then
        echo -e "${RED}  ✗ Invalid proxy type: $type${NC}" >&2
        echo -e "${YELLOW}    Supported types: ${SUPPORTED_PROXY_TYPES[*]}${NC}" >&2
        ((errors++))
    fi

    # Validate address
    if [[ -z "$address" ]]; then
        echo -e "${RED}  ✗ Proxy address is required${NC}" >&2
        ((errors++))
    elif [[ ${#address} -gt 253 ]]; then
        echo -e "${RED}  ✗ Address too long (max 253 chars): ${#address}${NC}" >&2
        ((errors++))
    fi

    # Validate port
    if [[ -z "$port" ]]; then
        echo -e "${RED}  ✗ Proxy port is required${NC}" >&2
        ((errors++))
    elif ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}  ✗ Port must be numeric: $port${NC}" >&2
        ((errors++))
    elif [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        echo -e "${RED}  ✗ Port out of range (1-65535): $port${NC}" >&2
        ((errors++))
    fi

    # Validate authentication (both username and password required if one is provided)
    if [[ -n "$username" && -z "$password" ]]; then
        echo -e "${RED}  ✗ Password required when username is provided${NC}" >&2
        ((errors++))
    elif [[ -z "$username" && -n "$password" ]]; then
        echo -e "${RED}  ✗ Username required when password is provided${NC}" >&2
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}✗ Validation failed with $errors error(s)${NC}" >&2
        return 1
    fi

    echo -e "${GREEN}✓ Configuration is valid${NC}"
    return 0
}

# =============================================================================
# FUNCTION: generate_proxy_id
# =============================================================================
# Description: Generate unique proxy ID based on address and timestamp
# Arguments:
#   $1 - address (hostname or IP)
# Returns: Echoes generated ID
# =============================================================================
generate_proxy_id() {
    local address="${1:-unknown}"
    local timestamp
    timestamp=$(date +%s)

    # Sanitize address (remove special chars, convert to lowercase)
    local sanitized_address
    sanitized_address=$(echo "$address" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    # Generate ID: proxy-<sanitized_address>-<timestamp_last6>
    local id="proxy-${sanitized_address}-${timestamp:(-6)}"

    echo "$id"
}

# =============================================================================
# FUNCTION: add_external_proxy
# =============================================================================
# Description: Add external proxy to database
# Arguments:
#   $1 - type (socks5, socks5s, http, https)
#   $2 - address
#   $3 - port
#   $4 - username (optional)
#   $5 - password (optional)
#   $6 - tls_server_name (optional, defaults to address)
#   $7 - allow_insecure (optional, defaults to false)
# Returns: 0 on success, 1 on failure
# Outputs: Proxy ID on success
# =============================================================================
add_external_proxy() {
    local type="${1:-}"
    local address="${2:-}"
    local port="${3:-}"
    local username="${4:-}"
    local password="${5:-}"
    local tls_server_name="${6:-$address}"
    local allow_insecure="${7:-false}"

    echo -e "${CYAN}Adding external proxy...${NC}"

    # Validate configuration
    if ! validate_proxy_config "$type" "$address" "$port" "$username" "$password"; then
        return 1
    fi

    # Initialize database if needed
    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        init_external_proxy_db || return 1
    fi

    # Generate unique ID
    local proxy_id
    proxy_id=$(generate_proxy_id "$address")
    echo "  ✓ Generated proxy ID: $proxy_id"

    # Check if proxy with same address:port already exists
    local existing_count
    existing_count=$(jq -r --arg addr "$address" --arg port "$port" \
        '.proxies | map(select(.address == $addr and (.port | tostring) == $port)) | length' \
        "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "0")

    if [[ "$existing_count" != "0" ]]; then
        echo -e "${YELLOW}  ⚠️  Proxy with address $address:$port already exists${NC}"
        echo -e "${YELLOW}  Use 'familytraffic-external-proxy update' to modify existing proxy${NC}"
        return 1
    fi

    # Determine if TLS is enabled
    local tls_enabled="false"
    if [[ "$type" == "socks5s" || "$type" == "https" ]]; then
        tls_enabled="true"
    fi

    # Create proxy object
    local timestamp
    timestamp=$(date -Iseconds)

    local proxy_json
    proxy_json=$(jq -n \
        --arg id "$proxy_id" \
        --arg type "$type" \
        --arg address "$address" \
        --arg port "$port" \
        --arg username "$username" \
        --arg password "$password" \
        --arg tls_enabled "$tls_enabled" \
        --arg tls_server_name "$tls_server_name" \
        --arg allow_insecure "$allow_insecure" \
        --arg created "$timestamp" \
        '{
            id: $id,
            type: $type,
            address: $address,
            port: ($port | tonumber),
            tls: {
                enabled: ($tls_enabled == "true"),
                server_name: $tls_server_name,
                allow_insecure: ($allow_insecure == "true")
            },
            auth: (if $username != "" then {
                username: $username,
                password: $password
            } else null end),
            retry: {
                enabled: true,
                max_attempts: 3,
                backoff_multiplier: 2
            },
            active: false,
            metadata: {
                created: $created,
                last_modified: $created,
                last_test: null,
                test_result: null
            }
        }')

    # Add proxy to database
    local temp_file
    temp_file=$(mktemp)

    jq --argjson proxy "$proxy_json" --arg timestamp "$timestamp" \
        '.proxies += [$proxy] | .metadata.last_modified = $timestamp' \
        "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to add proxy to database${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo "  ✓ Type: $type"
    echo "  ✓ Address: $address:$port"
    echo "  ✓ TLS: $tls_enabled"
    if [[ -n "$username" ]]; then
        echo "  ✓ Authentication: enabled (user: $username)"
    else
        echo "  ✓ Authentication: disabled"
    fi
    echo "  ✓ Retry: enabled (3 attempts, backoff 2x)"

    echo -e "${GREEN}✓ Proxy added successfully: $proxy_id${NC}"
    echo "$proxy_id"  # Output ID for scripts
    return 0
}

# =============================================================================
# FUNCTION: list_external_proxies
# =============================================================================
# Description: List all external proxies in database
# Arguments: None
# Returns: 0 on success, 1 on failure
# =============================================================================
list_external_proxies() {
    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${YELLOW}No external proxies configured${NC}"
        return 0
    fi

    local proxy_count
    proxy_count=$(jq -r '.proxies | length' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "0")

    if [[ "$proxy_count" == "0" ]]; then
        echo -e "${YELLOW}No external proxies configured${NC}"
        return 0
    fi

    echo -e "${CYAN}External Proxies ($proxy_count):${NC}"
    echo ""

    # Get enabled status
    local enabled
    enabled=$(jq -r '.enabled' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "false")

    if [[ "$enabled" == "true" ]]; then
        echo -e "  Status: ${GREEN}✓ ENABLED${NC}"
    else
        echo -e "  Status: ${YELLOW}✗ DISABLED${NC}"
    fi
    echo ""

    # List each proxy
    jq -r '.proxies[] |
        "  ID: " + .id +
        "\n    Type: " + .type +
        "\n    Address: " + .address + ":" + (.port | tostring) +
        "\n    TLS: " + (if .tls.enabled then "enabled" else "disabled" end) +
        "\n    Auth: " + (if .auth then "enabled (user: " + .auth.username + ")" else "disabled" end) +
        "\n    Active: " + (if .active then "✓ YES" else "✗ NO" end) +
        "\n    Created: " + .metadata.created +
        "\n"' \
        "$EXTERNAL_PROXY_DB"

    return 0
}

# =============================================================================
# FUNCTION: get_external_proxy
# =============================================================================
# Description: Get external proxy configuration by ID
# Arguments:
#   $1 - proxy_id
# Returns: 0 on success, 1 if not found
# Outputs: JSON object of proxy configuration
# =============================================================================
get_external_proxy() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${RED}External proxy database not found${NC}" >&2
        return 1
    fi

    local proxy_json
    proxy_json=$(jq -r --arg id "$proxy_id" '.proxies[] | select(.id == $id)' "$EXTERNAL_PROXY_DB" 2>/dev/null)

    if [[ -z "$proxy_json" || "$proxy_json" == "null" ]]; then
        echo -e "${RED}Proxy not found: $proxy_id${NC}" >&2
        return 1
    fi

    echo "$proxy_json"
    return 0
}

# =============================================================================
# FUNCTION: update_external_proxy
# =============================================================================
# Description: Update external proxy configuration
# Arguments:
#   $1 - proxy_id
#   $2 - field (type|address|port|username|password|tls_server_name|allow_insecure)
#   $3 - new_value
# Returns: 0 on success, 1 on failure
# =============================================================================
update_external_proxy() {
    local proxy_id="${1:-}"
    local field="${2:-}"
    local new_value="${3:-}"

    if [[ -z "$proxy_id" || -z "$field" ]]; then
        echo -e "${RED}Proxy ID and field are required${NC}" >&2
        return 1
    fi

    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${RED}External proxy database not found${NC}" >&2
        return 1
    fi

    # Check if proxy exists
    if ! get_external_proxy "$proxy_id" >/dev/null 2>&1; then
        return 1
    fi

    echo -e "${CYAN}Updating proxy $proxy_id...${NC}"

    local timestamp
    timestamp=$(date -Iseconds)

    local temp_file
    temp_file=$(mktemp)

    # Update based on field
    case "$field" in
        type)
            if ! [[ " ${SUPPORTED_PROXY_TYPES[*]} " =~ " ${new_value} " ]]; then
                echo -e "${RED}Invalid proxy type: $new_value${NC}" >&2
                rm -f "$temp_file"
                return 1
            fi
            jq --arg id "$proxy_id" --arg value "$new_value" --arg ts "$timestamp" \
                '(.proxies[] | select(.id == $id) | .type) = $value |
                 (.proxies[] | select(.id == $id) | .metadata.last_modified) = $ts |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file"
            ;;
        address)
            jq --arg id "$proxy_id" --arg value "$new_value" --arg ts "$timestamp" \
                '(.proxies[] | select(.id == $id) | .address) = $value |
                 (.proxies[] | select(.id == $id) | .metadata.last_modified) = $ts |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file"
            ;;
        port)
            if ! [[ "$new_value" =~ ^[0-9]+$ ]] || [[ "$new_value" -lt 1 || "$new_value" -gt 65535 ]]; then
                echo -e "${RED}Invalid port: $new_value${NC}" >&2
                rm -f "$temp_file"
                return 1
            fi
            jq --arg id "$proxy_id" --arg value "$new_value" --arg ts "$timestamp" \
                '(.proxies[] | select(.id == $id) | .port) = ($value | tonumber) |
                 (.proxies[] | select(.id == $id) | .metadata.last_modified) = $ts |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file"
            ;;
        username)
            jq --arg id "$proxy_id" --arg value "$new_value" --arg ts "$timestamp" \
                '(.proxies[] | select(.id == $id) | .auth.username) = $value |
                 (.proxies[] | select(.id == $id) | .metadata.last_modified) = $ts |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file"
            ;;
        password)
            jq --arg id "$proxy_id" --arg value "$new_value" --arg ts "$timestamp" \
                '(.proxies[] | select(.id == $id) | .auth.password) = $value |
                 (.proxies[] | select(.id == $id) | .metadata.last_modified) = $ts |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file"
            ;;
        *)
            echo -e "${RED}Unknown field: $field${NC}" >&2
            rm -f "$temp_file"
            return 1
            ;;
    esac

    mv "$temp_file" "$EXTERNAL_PROXY_DB"

    echo "  ✓ Updated $field: $new_value"
    echo -e "${GREEN}✓ Proxy updated successfully${NC}"
    return 0
}

# =============================================================================
# FUNCTION: remove_external_proxy
# =============================================================================
# Description: Remove external proxy from database
# Arguments:
#   $1 - proxy_id
# Returns: 0 on success, 1 on failure
# =============================================================================
remove_external_proxy() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${RED}External proxy database not found${NC}" >&2
        return 1
    fi

    # Check if proxy exists
    if ! get_external_proxy "$proxy_id" >/dev/null 2>&1; then
        return 1
    fi

    echo -e "${CYAN}Removing proxy $proxy_id...${NC}"

    local timestamp
    timestamp=$(date -Iseconds)

    local temp_file
    temp_file=$(mktemp)

    jq --arg id "$proxy_id" --arg ts "$timestamp" \
        '.proxies = [.proxies[] | select(.id != $id)] |
         .metadata.last_modified = $ts' \
        "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to remove proxy from database${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo -e "${GREEN}✓ Proxy removed successfully${NC}"
    return 0
}

# =============================================================================
# FUNCTION: set_active_proxy
# =============================================================================
# Description: Set proxy as active (deactivate all others)
# Arguments:
#   $1 - proxy_id
# Returns: 0 on success, 1 on failure
# =============================================================================
set_active_proxy() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${RED}External proxy database not found${NC}" >&2
        return 1
    fi

    # Check if proxy exists
    if ! get_external_proxy "$proxy_id" >/dev/null 2>&1; then
        return 1
    fi

    echo -e "${CYAN}Activating proxy $proxy_id...${NC}"

    local timestamp
    timestamp=$(date -Iseconds)

    local temp_file
    temp_file=$(mktemp)

    # Deactivate all proxies, then activate the specified one
    jq --arg id "$proxy_id" --arg ts "$timestamp" \
        '(.proxies[] | .active) = false |
         (.proxies[] | select(.id == $id) | .active) = true |
         .metadata.last_modified = $ts' \
        "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to activate proxy${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo -e "${GREEN}✓ Proxy activated successfully${NC}"
    return 0
}

# =============================================================================
# FUNCTION: test_proxy_connectivity
# =============================================================================
# Description: Test connectivity to external proxy
# Arguments:
#   $1 - proxy_id
# Returns: 0 if reachable, 1 if unreachable
# =============================================================================
test_proxy_connectivity() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Testing proxy connectivity...${NC}"

    # Get proxy configuration
    local proxy_json
    proxy_json=$(get_external_proxy "$proxy_id" 2>/dev/null) || return 1

    local type address port username password tls_enabled
    type=$(echo "$proxy_json" | jq -r '.type')
    address=$(echo "$proxy_json" | jq -r '.address')
    port=$(echo "$proxy_json" | jq -r '.port')
    username=$(echo "$proxy_json" | jq -r '.auth.username // empty')
    password=$(echo "$proxy_json" | jq -r '.auth.password // empty')
    tls_enabled=$(echo "$proxy_json" | jq -r '.tls.enabled')

    echo "  Testing: $type://$address:$port"

    # Test with curl (3 attempts)
    local max_attempts=3
    local attempt=1
    local test_url="https://1.1.1.1"

    while [[ $attempt -le $max_attempts ]]; do
        echo "  Attempt $attempt/$max_attempts..."

        local start_time
        start_time=$(date +%s%3N)

        # Build curl proxy argument based on type
        local proxy_arg
        if [[ "$type" == "socks5" || "$type" == "socks5s" ]]; then
            if [[ -n "$username" ]]; then
                proxy_arg="socks5://${username}:${password}@${address}:${port}"
            else
                proxy_arg="socks5://${address}:${port}"
            fi
        else  # http/https
            if [[ -n "$username" ]]; then
                proxy_arg="http://${username}:${password}@${address}:${port}"
            else
                proxy_arg="http://${address}:${port}"
            fi
        fi

        # Execute test
        if curl -s -o /dev/null -w "%{http_code}" --proxy "$proxy_arg" --connect-timeout 10 "$test_url" >/dev/null 2>&1; then
            local end_time
            end_time=$(date +%s%3N)
            local latency=$((end_time - start_time))

            echo -e "  ${GREEN}✓ SUCCESS${NC} (latency: ${latency}ms)"

            # Update test result in database
            local timestamp
            timestamp=$(date -Iseconds)
            local temp_file
            temp_file=$(mktemp)

            jq --arg id "$proxy_id" --arg ts "$timestamp" --arg result "success" --arg latency "$latency" \
                '(.proxies[] | select(.id == $id) | .metadata.last_test) = $ts |
                 (.proxies[] | select(.id == $id) | .metadata.test_result) = {
                     status: $result,
                     latency_ms: ($latency | tonumber),
                     timestamp: $ts
                 } |
                 .metadata.last_modified = $ts' \
                "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

            return 0
        fi

        echo -e "  ${YELLOW}✗ Failed (attempt $attempt)${NC}"
        ((attempt++))
        sleep 2
    done

    echo -e "${RED}✗ All attempts failed${NC}"

    # Update test result in database
    local timestamp
    timestamp=$(date -Iseconds)
    local temp_file
    temp_file=$(mktemp)

    jq --arg id "$proxy_id" --arg ts "$timestamp" --arg result "failed" \
        '(.proxies[] | select(.id == $id) | .metadata.last_test) = $ts |
         (.proxies[] | select(.id == $id) | .metadata.test_result) = {
             status: $result,
             timestamp: $ts
         } |
         .metadata.last_modified = $ts' \
        "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

    return 1
}

# =============================================================================
# FUNCTION: generate_xray_outbound_json
# =============================================================================
# Description: Generate Xray outbound configuration JSON for external proxy
# Arguments:
#   $1 - proxy_id
# Returns: 0 on success, 1 on failure
# Outputs: JSON object for Xray outbound configuration
# =============================================================================
generate_xray_outbound_json() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    # Get proxy configuration
    local proxy_json
    proxy_json=$(get_external_proxy "$proxy_id" 2>/dev/null) || return 1

    local type address port username password tls_enabled tls_server_name allow_insecure
    type=$(echo "$proxy_json" | jq -r '.type')
    address=$(echo "$proxy_json" | jq -r '.address')
    port=$(echo "$proxy_json" | jq -r '.port')
    username=$(echo "$proxy_json" | jq -r '.auth.username // empty')
    password=$(echo "$proxy_json" | jq -r '.auth.password // empty')
    tls_enabled=$(echo "$proxy_json" | jq -r '.tls.enabled')
    tls_server_name=$(echo "$proxy_json" | jq -r '.tls.server_name')
    allow_insecure=$(echo "$proxy_json" | jq -r '.tls.allow_insecure')

    # Determine Xray protocol (socks5s → socks, https → http)
    local xray_protocol
    if [[ "$type" == "socks5" || "$type" == "socks5s" ]]; then
        xray_protocol="socks"
    else
        xray_protocol="http"
    fi

    # Build outbound JSON
    local outbound_json

    if [[ -n "$username" ]]; then
        # With authentication
        outbound_json=$(jq -n \
            --arg protocol "$xray_protocol" \
            --arg address "$address" \
            --arg port "$port" \
            --arg username "$username" \
            --arg password "$password" \
            --arg tls_enabled "$tls_enabled" \
            --arg tls_server_name "$tls_server_name" \
            --arg allow_insecure "$allow_insecure" \
            '{
                protocol: $protocol,
                tag: "external-proxy",
                settings: {
                    servers: [{
                        address: $address,
                        port: ($port | tonumber),
                        users: [{
                            user: $username,
                            pass: $password
                        }]
                    }]
                },
                streamSettings: (if ($tls_enabled == "true") then {
                    network: "tcp",
                    security: "tls",
                    tlsSettings: {
                        serverName: $tls_server_name,
                        allowInsecure: ($allow_insecure == "true")
                    }
                } else {
                    network: "tcp",
                    security: "none"
                } end)
            }')
    else
        # Without authentication
        outbound_json=$(jq -n \
            --arg protocol "$xray_protocol" \
            --arg address "$address" \
            --arg port "$port" \
            --arg tls_enabled "$tls_enabled" \
            --arg tls_server_name "$tls_server_name" \
            --arg allow_insecure "$allow_insecure" \
            '{
                protocol: $protocol,
                tag: "external-proxy",
                settings: {
                    servers: [{
                        address: $address,
                        port: ($port | tonumber)
                    }]
                },
                streamSettings: (if ($tls_enabled == "true") then {
                    network: "tcp",
                    security: "tls",
                    tlsSettings: {
                        serverName: $tls_server_name,
                        allowInsecure: ($allow_insecure == "true")
                    }
                } else {
                    network: "tcp",
                    security: "none"
                } end)
            }')
    fi

    echo "$outbound_json"
    return 0
}

# =============================================================================
# Get Routing Status (v5.24 - Enhanced with Per-User Assignments)
# =============================================================================

get_routing_status() {
    local ext_proxy_db="$EXTERNAL_PROXY_DB"
    local users_json="/opt/familytraffic/data/users.json"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  External Proxy Routing Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if database exists
    if [[ ! -f "$ext_proxy_db" ]]; then
        echo "  Status: Not configured"
        echo "  Hint: familytraffic-external-proxy add"
        echo ""
        return 0
    fi

    # Get basic status
    local enabled
    enabled=$(jq -r '.enabled' "$ext_proxy_db" 2>/dev/null || echo "false")

    local proxy_count
    proxy_count=$(jq -r '.proxies | length' "$ext_proxy_db" 2>/dev/null || echo "0")

    local routing_mode
    routing_mode=$(jq -r '.routing.mode' "$ext_proxy_db" 2>/dev/null || echo "unknown")

    echo "  Feature Status: $(if [[ "$enabled" == "true" ]]; then echo "ENABLED"; else echo "DISABLED"; fi)"
    echo "  Routing Mode: $routing_mode"
    echo "  Total Proxies: $proxy_count"

    # Show active proxy (server-level, deprecated in v5.24)
    if [[ "$enabled" == "true" ]]; then
        local active_proxy_id
        active_proxy_id=$(jq -r '.proxies[] | select(.active == true) | .id' \
            "$ext_proxy_db" 2>/dev/null || echo "")

        if [[ -n "$active_proxy_id" ]]; then
            echo ""
            echo "  Server-Level Proxy (deprecated in v5.24):"
            local proxy_type proxy_address proxy_port
            proxy_type=$(jq -r --arg id "$active_proxy_id" \
                '.proxies[] | select(.id == $id) | .type' \
                "$ext_proxy_db" 2>/dev/null)
            proxy_address=$(jq -r --arg id "$active_proxy_id" \
                '.proxies[] | select(.id == $id) | .address' \
                "$ext_proxy_db" 2>/dev/null)
            proxy_port=$(jq -r --arg id "$active_proxy_id" \
                '.proxies[] | select(.id == $id) | .port' \
                "$ext_proxy_db" 2>/dev/null)

            echo "    Active Proxy: $active_proxy_id"
            echo "    Type: $proxy_type"
            echo "    Address: $proxy_address:$proxy_port"
        fi
    fi

    # Show per-user assignments (v5.24)
    echo ""
    echo "  Per-User Proxy Assignments (v5.24):"
    echo ""

    if [[ ! -f "$users_json" ]]; then
        echo "    ${YELLOW}Users database not found${NC}"
        echo ""
        return 0
    fi

    local total_users
    total_users=$(jq -r '.users | length' "$users_json" 2>/dev/null || echo "0")

    if [[ "$total_users" -eq 0 ]]; then
        echo "    No users configured"
        echo ""
        return 0
    fi

    # Count users by proxy assignment
    local direct_count proxied_count
    direct_count=$(jq -r '[.users[] | select(.external_proxy_id == null or .external_proxy_id == "")] | length' \
        "$users_json" 2>/dev/null || echo "0")
    proxied_count=$(jq -r '[.users[] | select(.external_proxy_id != null and .external_proxy_id != "")] | length' \
        "$users_json" 2>/dev/null || echo "0")

    echo "    Total Users: $total_users"
    echo "      Direct Routing: $direct_count"
    echo "      Via External Proxy: $proxied_count"

    # Show users per proxy
    if [[ "$proxied_count" -gt 0 ]]; then
        echo ""
        echo "    Users by Proxy:"

        # Get unique proxy IDs from users
        local unique_proxies
        unique_proxies=$(jq -r '[.users[] | select(.external_proxy_id != null and .external_proxy_id != "") | .external_proxy_id] | unique | .[]' \
            "$users_json" 2>/dev/null)

        if [[ -n "$unique_proxies" ]]; then
            while IFS= read -r proxy_id; do
                # Get users for this proxy
                local users_list
                users_list=$(jq -r --arg pid "$proxy_id" \
                    '[.users[] | select(.external_proxy_id == $pid) | .username] | join(", ")' \
                    "$users_json" 2>/dev/null)

                local user_count
                user_count=$(jq -r --arg pid "$proxy_id" \
                    '[.users[] | select(.external_proxy_id == $pid)] | length' \
                    "$users_json" 2>/dev/null)

                # Get proxy details
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

                echo ""
                echo "      Proxy: $proxy_info"
                echo "        Users ($user_count): $users_list"
            done <<< "$unique_proxies"
        fi

        echo ""
        echo "    Hint: familytraffic list-proxy-assignments (detailed view)"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# Export functions
export -f init_external_proxy_db
export -f validate_proxy_config
export -f generate_proxy_id
export -f add_external_proxy
export -f list_external_proxies
export -f get_external_proxy
export -f update_external_proxy
export -f remove_external_proxy
export -f set_active_proxy
export -f test_proxy_connectivity
export -f generate_xray_outbound_json
export -f get_routing_status

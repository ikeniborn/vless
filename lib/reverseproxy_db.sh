#!/bin/bash
# ==============================================================================
# VLESS Reality Deployment System
# Module: Reverse Proxy Database Management
# ==============================================================================
#
# Purpose:
#   JSON-based database for reverse proxy configurations (v4.3 HAProxy)
#
# Database Location:
#   /opt/familytraffic/config/reverse_proxies.json
#
# Schema:
#   {
#     "version": "1.0",
#     "proxies": [
#       {
#         "id": 1,
#         "domain": "example.com",
#         "target_site": "https://target.com",
#         "target_ipv4": "1.2.3.4",
#         "target_ipv4_last_checked": "2025-10-20T00:00:00Z",
#         "port": 9443,
#         "username": "user",
#         "password": "secretpassword",
#         "xray_inbound_port": 18443,
#         "xray_inbound_tag": "http-in-example",
#         "certificate_expires": "2025-01-20T00:00:00Z",
#         "certificate_renewed_at": "2024-10-20T00:00:00Z",
#         "enabled": true,
#         "created_at": "2024-10-20T00:00:00Z",
#         "notes": ""
#       }
#     ]
#   }
#
# Functions:
#   - init_database()              # Initialize database
#   - get_proxy(domain)            # Get single proxy by domain
#   - get_proxy_count()            # Count all proxies
#   - list_proxies()               # List all proxies
#   - add_proxy(...)               # Add new proxy
#   - remove_proxy(domain)         # Remove proxy
#   - update_proxy(domain, field, value)  # Update field
#   - update_certificate_info(...) # Update cert info
#   - get_next_port()              # Get next available port
#   - proxy_exists(domain)         # Check if proxy exists
#
# Version: 4.3.0
# Author: familyTraffic Development Team
# Date: 2025-10-20
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

readonly DB_FILE="/opt/familytraffic/config/reverse_proxies.json"
readonly DB_LOCK="/var/lock/vless_reverseproxy_db.lock"
readonly MIN_PORT=9443
readonly MAX_PORT=9452

# ==============================================================================
# Helper Functions
# ==============================================================================

db_lock() {
    mkdir -p "$(dirname "$DB_LOCK")"
    exec 200>"$DB_LOCK"
    flock -x 200
}

db_unlock() {
    flock -u 200 2>/dev/null || true
}

# ==============================================================================
# Function: init_database
# ==============================================================================
# Description: Initialize reverse proxy database if not exists
# Returns: 0 on success
# ==============================================================================
init_database() {
    # Check if file exists AND is not empty AND is valid JSON
    if [[ -f "$DB_FILE" ]] && [[ -s "$DB_FILE" ]] && jq empty "$DB_FILE" 2>/dev/null; then
        return 0
    fi

    mkdir -p "$(dirname "$DB_FILE")"

    cat > "$DB_FILE" <<'EOF'
{
  "version": "1.0",
  "proxies": [],
  "created_at": "",
  "updated_at": ""
}
EOF

    # Update timestamps
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg time "$now" '.created_at = $time | .updated_at = $time' "$DB_FILE" > "${DB_FILE}.tmp"
    mv "${DB_FILE}.tmp" "$DB_FILE"

    chmod 600 "$DB_FILE"
    chown root:root "$DB_FILE" 2>/dev/null || true

    return 0
}

# ==============================================================================
# Function: proxy_exists
# ==============================================================================
# Description: Check if proxy with domain exists
# Arguments: $1 - domain
# Returns: 0 if exists, 1 if not
# ==============================================================================
proxy_exists() {
    local domain="$1"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    if jq -e --arg domain "$domain" '.proxies[] | select(.domain == $domain)' "$DB_FILE" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# ==============================================================================
# Function: get_proxy
# ==============================================================================
# Description: Get proxy configuration by domain
# Arguments: $1 - domain
# Returns: 0 on success, prints JSON to stdout
# ==============================================================================
get_proxy() {
    local domain="$1"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    local proxy=$(jq --arg domain "$domain" '.proxies[] | select(.domain == $domain)' "$DB_FILE" 2>/dev/null)

    if [[ -z "$proxy" ]]; then
        return 1
    fi

    echo "$proxy"
    return 0
}

# ==============================================================================
# Function: get_proxy_count
# ==============================================================================
# Description: Get total number of proxies
# Returns: Prints count to stdout
# ==============================================================================
get_proxy_count() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo "0"
        return 0
    fi

    jq '.proxies | length' "$DB_FILE" 2>/dev/null || echo "0"
}

# ==============================================================================
# Function: list_proxies
# ==============================================================================
# Description: List all proxies
# Returns: Prints JSON array to stdout
# ==============================================================================
list_proxies() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo "[]"
        return 0
    fi

    jq '.proxies' "$DB_FILE" 2>/dev/null || echo "[]"
}

# ==============================================================================
# Function: get_next_port
# ==============================================================================
# Description: Get next available port in range 9443-9452
# Returns: Prints port number or empty if all used
# ==============================================================================
get_next_port() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo "$MIN_PORT"
        return 0
    fi

    # Get used ports
    local used_ports=$(jq -r '.proxies[].port' "$DB_FILE" 2>/dev/null | sort -n)

    # Find first available port
    for port in $(seq $MIN_PORT $MAX_PORT); do
        if ! echo "$used_ports" | grep -q "^${port}$"; then
            echo "$port"
            return 0
        fi
    done

    # No ports available
    return 1
}

# ==============================================================================
# Function: get_next_available_port
# ==============================================================================
# Description: Get next available port by checking both DB and actual nginx configs
# Returns: Prints port number or empty if all used
# v5.8: Enhanced port detection - checks both DB and nginx configs to prevent conflicts
# ==============================================================================
get_next_available_port() {
    local config_dir="/opt/familytraffic/config/reverse-proxy"

    # Collect used ports from database
    local db_ports=""
    if [[ -f "$DB_FILE" ]]; then
        db_ports=$(jq -r '.proxies[].port' "$DB_FILE" 2>/dev/null | sort -n)
    fi

    # Collect used ports from nginx configs (parse listen directives)
    local nginx_ports=""
    if [[ -d "$config_dir" ]]; then
        nginx_ports=$(grep -h "listen.*:" "$config_dir"/*.conf 2>/dev/null | \
                      grep -oP 'listen\s+[\d.]+:\K\d+' | \
                      sort -n | uniq)
    fi

    # Merge both lists and remove duplicates
    local all_ports=$(echo -e "${db_ports}\n${nginx_ports}" | sort -n | uniq | grep -v '^$')

    # Find first available port
    for port in $(seq $MIN_PORT $MAX_PORT); do
        if ! echo "$all_ports" | grep -q "^${port}$"; then
            echo "$port"
            return 0
        fi
    done

    # No ports available
    echo "ERROR: All ports (9443-9452) are in use" >&2
    return 1
}

# ==============================================================================
# Function: add_proxy
# ==============================================================================
# Description: Add new proxy to database
# Arguments:
#   $1 - domain
#   $2 - target_site
#   $3 - port
#   $4 - username
#   $5 - password
#   $6 - xray_inbound_port
#   $7 - xray_inbound_tag
#   $8 - certificate_expires (ISO 8601)
#   $9 - target_ipv4 (optional, resolved if empty)
#   $10 - notes (optional)
# Returns: 0 on success, 1 on failure
# v5.2: Added target_ipv4 and target_ipv4_last_checked fields
# ==============================================================================
add_proxy() {
    local domain="$1"
    local target_site="$2"
    local port="$3"
    local username="$4"
    local password="$5"
    local xray_port="$6"
    local xray_tag="$7"
    local cert_expires="$8"
    local target_ipv4="${9:-}"
    local notes="${10:-}"

    init_database

    # Check if already exists
    if proxy_exists "$domain"; then
        echo "Error: Proxy for domain '$domain' already exists" >&2
        return 1
    fi

    # Resolve target_ipv4 if not provided (requires nginx_config_generator.sh sourced)
    if [[ -z "$target_ipv4" ]] && type resolve_target_ipv4 &>/dev/null; then
        target_ipv4=$(resolve_target_ipv4 "$target_site" 2>/dev/null) || target_ipv4=""
    fi

    db_lock

    # Get next ID
    local next_id=$(jq '(.proxies | map(.id) | max // 0) + 1' "$DB_FILE")

    # Build proxy entry
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Use --arg for all parameters and handle type conversion in jq
    # This avoids --argjson issues with "N/A" strings
    local proxy_entry=$(jq -n \
        --arg id "$next_id" \
        --arg domain "$domain" \
        --arg target "$target_site" \
        --arg target_ip "$target_ipv4" \
        --arg port "$port" \
        --arg user "$username" \
        --arg pass "$password" \
        --arg xray_port "$xray_port" \
        --arg xray_tag "$xray_tag" \
        --arg cert_expires "$cert_expires" \
        --arg created "$now" \
        --arg notes "$notes" \
        '{
            id: ($id | tonumber),
            domain: $domain,
            target_site: $target,
            target_ipv4: $target_ip,
            target_ipv4_last_checked: $created,
            port: ($port | tonumber),
            username: $user,
            password: $pass,
            xray_inbound_port: (if $xray_port == "N/A" or $xray_port == "" then null else ($xray_port | tonumber) end),
            xray_inbound_tag: (if $xray_tag == "N/A" or $xray_tag == "" then null else $xray_tag end),
            certificate_expires: $cert_expires,
            certificate_renewed_at: $created,
            enabled: true,
            created_at: $created,
            notes: $notes
        }')

    # Add to database
    jq --argjson entry "$proxy_entry" --arg time "$now" \
       '.proxies += [$entry] | .updated_at = $time' \
       "$DB_FILE" > "${DB_FILE}.tmp"

    mv "${DB_FILE}.tmp" "$DB_FILE"
    chmod 600 "$DB_FILE"

    db_unlock

    return 0
}

# ==============================================================================
# Function: remove_proxy
# ==============================================================================
# Description: Remove proxy from database
# Arguments: $1 - domain
# Returns: 0 on success, 1 on failure
# ==============================================================================
remove_proxy() {
    local domain="$1"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    if ! proxy_exists "$domain"; then
        return 1
    fi

    db_lock

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg domain "$domain" --arg time "$now" \
       'del(.proxies[] | select(.domain == $domain)) | .updated_at = $time' \
       "$DB_FILE" > "${DB_FILE}.tmp"

    mv "${DB_FILE}.tmp" "$DB_FILE"
    chmod 600 "$DB_FILE"

    db_unlock

    return 0
}

# ==============================================================================
# Function: update_proxy
# ==============================================================================
# Description: Update specific field of proxy
# Arguments:
#   $1 - domain
#   $2 - field name (e.g., "enabled", "notes")
#   $3 - new value
# Returns: 0 on success, 1 on failure
# ==============================================================================
update_proxy() {
    local domain="$1"
    local field="$2"
    local value="$3"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    if ! proxy_exists "$domain"; then
        return 1
    fi

    db_lock

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update field (handle boolean/number/string)
    local update_expr
    if [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
        # Boolean
        update_expr="(.proxies[] | select(.domain == \"$domain\") | .$field) = ($value | fromjson)"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        # Number
        update_expr="(.proxies[] | select(.domain == \"$domain\") | .$field) = ($value | tonumber)"
    else
        # String
        update_expr="(.proxies[] | select(.domain == \"$domain\") | .$field) = \"$value\""
    fi

    jq "$update_expr | .updated_at = \"$now\"" "$DB_FILE" > "${DB_FILE}.tmp"

    mv "${DB_FILE}.tmp" "$DB_FILE"
    chmod 600 "$DB_FILE"

    db_unlock

    return 0
}

# ==============================================================================
# Function: update_certificate_info
# ==============================================================================
# Description: Update certificate expiry and renewal date
# Arguments:
#   $1 - domain
#   $2 - certificate_expires (ISO 8601)
#   $3 - certificate_renewed_at (ISO 8601)
# Returns: 0 on success, 1 on failure
# ==============================================================================
update_certificate_info() {
    local domain="$1"
    local cert_expires="$2"
    local cert_renewed="$3"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    if ! proxy_exists "$domain"; then
        return 1
    fi

    db_lock

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg domain "$domain" \
       --arg expires "$cert_expires" \
       --arg renewed "$cert_renewed" \
       --arg time "$now" \
       '(.proxies[] | select(.domain == $domain)) |=
        (.certificate_expires = $expires |
         .certificate_renewed_at = $renewed) |
        .updated_at = $time' \
       "$DB_FILE" > "${DB_FILE}.tmp"

    mv "${DB_FILE}.tmp" "$DB_FILE"
    chmod 600 "$DB_FILE"

    db_unlock

    return 0
}

# ==============================================================================
# Function: update_target_ipv4
# ==============================================================================
# Description: Update target site IPv4 address and last checked timestamp
# Arguments:
#   $1 - domain
#   $2 - target_ipv4 (new IPv4 address)
# Returns: 0 on success, 1 on failure
# v5.2: New function for IP monitoring
# ==============================================================================
update_target_ipv4() {
    local domain="$1"
    local target_ipv4="$2"

    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi

    if ! proxy_exists "$domain"; then
        return 1
    fi

    db_lock

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg domain "$domain" \
       --arg ipv4 "$target_ipv4" \
       --arg time "$now" \
       '(.proxies[] | select(.domain == $domain)) |=
        (.target_ipv4 = $ipv4 |
         .target_ipv4_last_checked = $time) |
        .updated_at = $time' \
       "$DB_FILE" > "${DB_FILE}.tmp"

    mv "${DB_FILE}.tmp" "$DB_FILE"
    chmod 600 "$DB_FILE"

    db_unlock

    return 0
}

# ==============================================================================
# Export Functions
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f init_database
    export -f proxy_exists
    export -f get_proxy
    export -f get_proxy_count
    export -f list_proxies
    export -f get_next_port
    export -f get_next_available_port
    export -f add_proxy
    export -f remove_proxy
    export -f update_proxy
    export -f update_certificate_info
    export -f update_target_ipv4
fi

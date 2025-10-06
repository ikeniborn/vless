#!/bin/bash
# ============================================================================
# VLESS Reality Deployment System
# Module: Proxy IP Whitelist Management (Server-Level)
# Version: 3.6
# ============================================================================
#
# Purpose:
#   Server-level IP whitelist management for SOCKS5/HTTP proxy servers.
#   Manages allowed source IPs that can connect to proxy inbounds.
#
# Architecture:
#   - Single whitelist for ALL proxy users (server-level, not per-user)
#   - Stored in: /opt/vless/config/proxy_allowed_ips.json
#   - Applied via Xray routing rules (source field only, no user field)
#   - Works for HTTP/SOCKS5/VLESS protocols
#
# Functions:
#   1. init_proxy_whitelist()          - Initialize with localhost
#   2. get_proxy_allowed_ips()         - Get current IP list
#   3. set_proxy_allowed_ips()         - Set complete IP list
#   4. add_proxy_allowed_ip()          - Add single IP
#   5. remove_proxy_allowed_ip()       - Remove IP
#   6. reset_proxy_allowed_ips()       - Reset to localhost
#   7. show_proxy_allowed_ips()        - Display formatted list
#   8. regenerate_proxy_routing()      - Update Xray routing rules
#   9. validate_ip()                   - Validate IP format
#
# Note: Replaces per-user IP whitelisting from v3.5 which didn't work
#       for HTTP/SOCKS5 protocols (user field only works for VLESS)
#
# Author: Claude Code Agent
# Date: 2025-10-06
# ============================================================================

set -euo pipefail

# ============================================================================
# Global Variables (conditional to avoid conflicts when sourced by CLI)
# ============================================================================

readonly PROXY_IPS_FILE="/opt/vless/config/proxy_allowed_ips.json"
[[ -z "${XRAY_CONFIG:-}" ]] && readonly XRAY_CONFIG="/opt/vless/config/xray_config.json"
[[ -z "${LOCK_FILE:-}" ]] && readonly LOCK_FILE="/var/lock/vless_proxy_ips.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

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
# FUNCTION: validate_ip
# ============================================================================
# Description: Validate IP address format (IPv4, IPv6, CIDR notation)
# Arguments:
#   $1 - IP address or CIDR range to validate
# Returns: 0 if valid, 1 if invalid
# ============================================================================
validate_ip() {
    local ip="$1"

    # Check if empty
    if [[ -z "$ip" ]]; then
        log_error "IP address cannot be empty"
        return 1
    fi

    # IPv4 with optional CIDR (e.g., 192.168.1.1 or 192.168.1.0/24)
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$'

    # IPv6 with optional CIDR (simplified check)
    local ipv6_regex='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}(\/[0-9]{1,3})?$'

    if [[ "$ip" =~ $ipv4_regex ]]; then
        # Validate IPv4 octets (0-255)
        local ip_part="${ip%%/*}"  # Remove CIDR if present
        IFS='.' read -ra OCTETS <<< "$ip_part"

        for octet in "${OCTETS[@]}"; do
            if [[ $octet -gt 255 ]]; then
                log_error "Invalid IPv4 address: $ip (octet > 255)"
                return 1
            fi
        done

        # Validate CIDR prefix if present
        if [[ "$ip" == *"/"* ]]; then
            local prefix="${ip##*/}"
            if [[ $prefix -lt 0 ]] || [[ $prefix -gt 32 ]]; then
                log_error "Invalid IPv4 CIDR prefix: /$prefix (must be 0-32)"
                return 1
            fi
        fi

        return 0
    elif [[ "$ip" =~ $ipv6_regex ]]; then
        # Basic IPv6 validation (full validation is complex)
        # Validate CIDR prefix if present
        if [[ "$ip" == *"/"* ]]; then
            local prefix="${ip##*/}"
            if [[ $prefix -lt 0 ]] || [[ $prefix -gt 128 ]]; then
                log_error "Invalid IPv6 CIDR prefix: /$prefix (must be 0-128)"
                return 1
            fi
        fi

        return 0
    else
        log_error "Invalid IP address format: $ip"
        log_info "Supported formats:"
        log_info "  - IPv4: 192.168.1.1"
        log_info "  - IPv4 CIDR: 10.0.0.0/24"
        log_info "  - IPv6: 2001:db8::1"
        log_info "  - IPv6 CIDR: 2001:db8::/32"
        return 1
    fi
}

# ============================================================================
# FUNCTION: init_proxy_whitelist
# ============================================================================
# Description: Initialize proxy IP whitelist with default (localhost)
# Returns: 0 on success, 1 on failure
# ============================================================================
init_proxy_whitelist() {
    log_info "Initializing proxy IP whitelist..."

    # Create config directory if doesn't exist
    local config_dir
    config_dir=$(dirname "$PROXY_IPS_FILE")
    mkdir -p "$config_dir"

    # Create whitelist file with localhost only
    cat > "$PROXY_IPS_FILE" <<EOF
{
  "version": "1.0",
  "allowed_ips": ["127.0.0.1"],
  "updated_at": "$(date -Iseconds)"
}
EOF

    chmod 600 "$PROXY_IPS_FILE"
    chown root:root "$PROXY_IPS_FILE" 2>/dev/null || true

    log_success "Proxy whitelist initialized (localhost only)"
    return 0
}

# ============================================================================
# FUNCTION: get_proxy_allowed_ips
# ============================================================================
# Description: Get current allowed IPs for proxy access
# Returns: 0 on success, 1 on failure
# Output: JSON array of allowed IPs to stdout
# ============================================================================
get_proxy_allowed_ips() {
    if [[ ! -f "$PROXY_IPS_FILE" ]]; then
        # Initialize if doesn't exist
        init_proxy_whitelist >/dev/null 2>&1
    fi

    local allowed_ips
    allowed_ips=$(jq -r '.allowed_ips // ["127.0.0.1"]' "$PROXY_IPS_FILE" 2>/dev/null)

    if [[ -z "$allowed_ips" || "$allowed_ips" == "null" ]]; then
        echo '["127.0.0.1"]'
        return 0
    fi

    echo "$allowed_ips"
    return 0
}

# ============================================================================
# FUNCTION: set_proxy_allowed_ips
# ============================================================================
# Description: Set allowed IPs for proxy access (replaces existing list)
# Arguments:
#   $1 - comma-separated list of IPs (e.g., "127.0.0.1,10.0.0.0/24")
# Returns: 0 on success, 1 on failure
# ============================================================================
set_proxy_allowed_ips() {
    local ips_csv="$1"

    # Parse comma-separated IPs into array
    IFS=',' read -ra ips_array <<< "$ips_csv"

    # Validate all IPs before making changes
    log_info "Validating IP addresses..."
    local valid_ips=()
    for ip in "${ips_array[@]}"; do
        # Trim whitespace
        ip=$(echo "$ip" | xargs)

        if validate_ip "$ip"; then
            valid_ips+=("$ip")
            log_success "Valid: $ip"
        else
            log_error "Validation failed for: $ip"
            return 1
        fi
    done

    # Ensure at least one IP
    if [[ ${#valid_ips[@]} -eq 0 ]]; then
        log_error "At least one IP address is required"
        return 1
    fi

    # Build JSON array
    local json_array
    json_array=$(printf '%s\n' "${valid_ips[@]}" | jq -R . | jq -s .)

    log_info "Updating proxy allowed IPs..."

    # Update file with locking
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    (
        flock -x 200

        # Create/update file
        cat > "$PROXY_IPS_FILE" <<EOF
{
  "version": "1.0",
  "allowed_ips": $json_array,
  "updated_at": "$(date -Iseconds)"
}
EOF

        chmod 600 "$PROXY_IPS_FILE"
        chown root:root "$PROXY_IPS_FILE" 2>/dev/null || true

    ) 200>"$LOCK_FILE"

    log_success "Proxy IP whitelist updated"

    # Regenerate routing rules
    if ! regenerate_proxy_routing; then
        log_error "Failed to regenerate routing rules"
        return 1
    fi

    # Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed, changes may not be applied"
        return 1
    fi

    log_success "Xray configuration reloaded"

    # Display updated IPs
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY IP WHITELIST UPDATED"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Allowed IPs:"
    for ip in "${valid_ips[@]}"; do
        echo "  • $ip"
    done
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return 0
}

# ============================================================================
# FUNCTION: add_proxy_allowed_ip
# ============================================================================
# Description: Add a single IP to proxy whitelist (without duplicates)
# Arguments:
#   $1 - IP address to add
# Returns: 0 on success, 1 on failure
# ============================================================================
add_proxy_allowed_ip() {
    local new_ip="$1"

    # Validate IP format
    if ! validate_ip "$new_ip"; then
        return 1
    fi

    # Get current allowed IPs
    local current_ips
    current_ips=$(get_proxy_allowed_ips)

    # Check if IP already exists
    if echo "$current_ips" | jq -e --arg ip "$new_ip" 'index($ip) != null' >/dev/null 2>&1; then
        log_warning "IP '$new_ip' already in proxy whitelist"
        return 0
    fi

    log_info "Adding IP to proxy whitelist: $new_ip"

    # Update file with locking
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    (
        flock -x 200

        # Read current IPs
        local current_json
        current_json=$(jq -c '.allowed_ips // ["127.0.0.1"]' "$PROXY_IPS_FILE" 2>/dev/null)

        # Add new IP
        local updated_json
        updated_json=$(echo "$current_json" | jq --arg ip "$new_ip" '. += [$ip]')

        # Write updated file
        cat > "$PROXY_IPS_FILE" <<EOF
{
  "version": "1.0",
  "allowed_ips": $updated_json,
  "updated_at": "$(date -Iseconds)"
}
EOF

        chmod 600 "$PROXY_IPS_FILE"

    ) 200>"$LOCK_FILE"

    log_success "IP added to proxy whitelist"

    # Regenerate routing rules
    if ! regenerate_proxy_routing; then
        log_error "Failed to regenerate routing rules"
        return 1
    fi

    # Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed, changes may not be applied"
        return 1
    fi

    log_success "Xray configuration reloaded"

    # Display updated list
    local updated_ips
    updated_ips=$(get_proxy_allowed_ips)

    echo ""
    log_success "IP '$new_ip' added to proxy whitelist"
    echo ""
    echo "Current allowed IPs:"
    echo "$updated_ips" | jq -r '.[]' | while read -r ip; do
        echo "  • $ip"
    done
    echo ""

    return 0
}

# ============================================================================
# FUNCTION: remove_proxy_allowed_ip
# ============================================================================
# Description: Remove a specific IP from proxy whitelist
# Arguments:
#   $1 - IP address to remove
# Returns: 0 on success, 1 on failure
# Note: Will not remove the last IP (ensures at least localhost remains)
# ============================================================================
remove_proxy_allowed_ip() {
    local remove_ip="$1"

    # Get current allowed IPs
    local current_ips
    current_ips=$(get_proxy_allowed_ips)

    # Check if IP exists in list
    if ! echo "$current_ips" | jq -e --arg ip "$remove_ip" 'index($ip) != null' >/dev/null 2>&1; then
        log_error "IP '$remove_ip' not found in proxy whitelist"
        return 1
    fi

    # Check if this is the last IP
    local ip_count
    ip_count=$(echo "$current_ips" | jq 'length')

    if [[ $ip_count -le 1 ]]; then
        log_error "Cannot remove last IP address"
        log_info "At least one IP must remain in the whitelist"
        log_info "Use 'reset-proxy-ips' to reset to localhost only"
        return 1
    fi

    log_info "Removing IP from proxy whitelist: $remove_ip"

    # Update file with locking
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    (
        flock -x 200

        # Remove IP
        local updated_json
        updated_json=$(jq --arg ip "$remove_ip" '.allowed_ips = (.allowed_ips - [$ip])' "$PROXY_IPS_FILE")

        # Write updated file
        echo "$updated_json" | jq '.updated_at = $time' --arg time "$(date -Iseconds)" > "$PROXY_IPS_FILE"

        chmod 600 "$PROXY_IPS_FILE"

    ) 200>"$LOCK_FILE"

    log_success "IP removed from proxy whitelist"

    # Regenerate routing rules
    if ! regenerate_proxy_routing; then
        log_error "Failed to regenerate routing rules"
        return 1
    fi

    # Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed, changes may not be applied"
        return 1
    fi

    log_success "Xray configuration reloaded"

    # Display updated list
    local updated_ips
    updated_ips=$(get_proxy_allowed_ips)

    echo ""
    log_success "IP '$remove_ip' removed from proxy whitelist"
    echo ""
    echo "Remaining allowed IPs:"
    echo "$updated_ips" | jq -r '.[]' | while read -r ip; do
        echo "  • $ip"
    done
    echo ""

    return 0
}

# ============================================================================
# FUNCTION: reset_proxy_allowed_ips
# ============================================================================
# Description: Reset proxy whitelist to default (localhost only)
# Returns: 0 on success, 1 on failure
# ============================================================================
reset_proxy_allowed_ips() {
    log_info "Resetting proxy whitelist to default (localhost only)"

    # Update file with locking
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null || true

    (
        flock -x 200

        # Reset to localhost only
        cat > "$PROXY_IPS_FILE" <<EOF
{
  "version": "1.0",
  "allowed_ips": ["127.0.0.1"],
  "updated_at": "$(date -Iseconds)"
}
EOF

        chmod 600 "$PROXY_IPS_FILE"

    ) 200>"$LOCK_FILE"

    log_success "Proxy whitelist reset to default"

    # Regenerate routing rules
    if ! regenerate_proxy_routing; then
        log_error "Failed to regenerate routing rules"
        return 1
    fi

    # Reload Xray
    if ! reload_xray; then
        log_warning "Xray reload failed, changes may not be applied"
        return 1
    fi

    log_success "Xray configuration reloaded"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY WHITELIST RESET"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Allowed IPs: 127.0.0.1 (localhost only)"
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return 0
}

# ============================================================================
# FUNCTION: show_proxy_allowed_ips
# ============================================================================
# Description: Display proxy whitelist in human-readable format
# Returns: 0 on success, 1 on failure
# ============================================================================
show_proxy_allowed_ips() {
    # Get allowed IPs
    local allowed_ips
    allowed_ips=$(get_proxy_allowed_ips)

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY IP WHITELIST (Server-Level)"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Allowed Source IPs:"
    echo "$allowed_ips" | jq -r '.[]' | while read -r ip; do
        echo "  • $ip"
    done
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "These IPs can connect to SOCKS5 (1080) and HTTP (8118) proxies."
    echo "Connections from other IPs will be blocked."
    echo ""
    echo "Note: This is a server-level whitelist (applies to all proxy users)."
    echo ""

    return 0
}

# ============================================================================
# FUNCTION: regenerate_proxy_routing
# ============================================================================
# Description: Regenerate Xray routing rules based on proxy IP whitelist
# Returns: 0 on success, 1 on failure
# ============================================================================
regenerate_proxy_routing() {
    if [[ ! -f "$PROXY_IPS_FILE" ]]; then
        log_warning "Proxy IP whitelist not found, initializing..."
        init_proxy_whitelist >/dev/null 2>&1
    fi

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray config not found: $XRAY_CONFIG"
        return 1
    fi

    log_info "Regenerating proxy routing rules..."

    # Read allowed IPs
    local allowed_ips
    allowed_ips=$(jq -c '.allowed_ips // ["127.0.0.1"]' "$PROXY_IPS_FILE" 2>/dev/null)

    # Build routing rules (NO user field, only source)
    local routing_rules
    routing_rules=$(jq -n \
        --argjson source "$allowed_ips" \
        '[
            {
                type: "field",
                inboundTag: ["socks5-proxy", "http-proxy"],
                source: $source,
                outboundTag: "direct"
            },
            {
                type: "field",
                inboundTag: ["socks5-proxy", "http-proxy"],
                outboundTag: "blocked"
            }
        ]')

    # Build complete routing object
    local routing_json
    routing_json=$(jq -n \
        --argjson rules "$routing_rules" \
        '{
            domainStrategy: "AsIs",
            rules: $rules
        }')

    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$$"

    # Update routing section
    local temp_file="${XRAY_CONFIG}.tmp.$$"
    if ! jq --argjson routing "$routing_json" '.routing = $routing' "$XRAY_CONFIG" > "$temp_file"; then
        log_error "Failed to update routing rules"
        rm -f "$temp_file"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Generated invalid Xray configuration"
        rm -f "$temp_file"
        mv "${XRAY_CONFIG}.bak.$$" "$XRAY_CONFIG"
        return 1
    fi

    # Apply changes
    mv "$temp_file" "$XRAY_CONFIG"
    rm -f "${XRAY_CONFIG}.bak.$$"

    local ip_count
    ip_count=$(echo "$allowed_ips" | jq 'length')

    log_success "Proxy routing rules regenerated ($ip_count IPs)"

    return 0
}

# ============================================================================
# FUNCTION: reload_xray (stub - expects function from user_management.sh)
# ============================================================================
reload_xray() {
    # This function should be provided by user_management.sh
    # If not available, provide basic implementation
    if ! type reload_xray_container &>/dev/null; then
        local compose_dir="/opt/vless"
        if docker ps --format '{{.Names}}' | grep -q "^vless_xray$"; then
            (cd "$compose_dir" && docker compose restart xray) 2>/dev/null
            return $?
        fi
        return 0
    fi

    reload_xray_container
}

# ============================================================================
# Export Functions
# ============================================================================

# Export all functions for use by other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f init_proxy_whitelist
    export -f get_proxy_allowed_ips
    export -f set_proxy_allowed_ips
    export -f add_proxy_allowed_ip
    export -f remove_proxy_allowed_ip
    export -f reset_proxy_allowed_ips
    export -f show_proxy_allowed_ips
    export -f regenerate_proxy_routing
    export -f validate_ip
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
        init)
            init_proxy_whitelist
            ;;
        show|get)
            show_proxy_allowed_ips
            ;;
        set)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 set <ip1,ip2,...>"
                exit 1
            fi
            set_proxy_allowed_ips "$2"
            ;;
        add)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 add <ip>"
                exit 1
            fi
            add_proxy_allowed_ip "$2"
            ;;
        remove)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 remove <ip>"
                exit 1
            fi
            remove_proxy_allowed_ip "$2"
            ;;
        reset)
            reset_proxy_allowed_ips
            ;;
        regenerate)
            regenerate_proxy_routing
            ;;
        *)
            echo "Usage: $0 {init|show|set|add|remove|reset|regenerate}"
            echo ""
            echo "Commands:"
            echo "  init                  - Initialize whitelist (localhost only)"
            echo "  show                  - Show current whitelist"
            echo "  set <ip1,ip2,...>     - Set complete IP list"
            echo "  add <ip>              - Add single IP"
            echo "  remove <ip>           - Remove IP"
            echo "  reset                 - Reset to localhost"
            echo "  regenerate            - Regenerate routing rules"
            echo ""
            exit 1
            ;;
    esac
fi

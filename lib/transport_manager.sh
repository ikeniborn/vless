#!/usr/bin/env bash
# lib/transport_manager.sh
# Transport Management (v5.33)
# Manages Tier 2 transport configurations (WebSocket, XHTTP, gRPC)
#
# Functions:
#   1. add_transport()      - Add transport with subdomain routing
#   2. list_transports()    - List configured transports
#   3. remove_transport()   - Remove transport and cleanup
#
# Dependencies:
#   - lib/nginx_stream_generator.sh (generate_nginx_config)
#   - lib/orchestrator.sh (create_xray_config)
#   - docker (docker exec vless_nginx nginx -s reload, docker restart vless_xray)
#
# Data file: ${VLESS_HOME}/data/transports.json

# Transport state file
TRANSPORTS_JSON="${VLESS_HOME:-/opt/vless}/data/transports.json"

# ============================================================================
# INTERNAL: _init_transports_json
# ============================================================================
_init_transports_json() {
    if [[ ! -f "$TRANSPORTS_JSON" ]]; then
        echo '{"transports":[]}' > "$TRANSPORTS_JSON"
        chmod 600 "$TRANSPORTS_JSON"
    fi
}

# ============================================================================
# FUNCTION: add_transport (v5.33)
# ============================================================================
# Description: Add a Tier 2 transport with subdomain routing.
#   - Updates transports.json
#   - Regenerates xray_config.json with Tier 2 inbounds
#   - Regenerates nginx.conf with SNI map entry + http server block
#   - Reloads vless_xray (docker restart) and vless_nginx (nginx -s reload)
# Arguments:
#   $1 - transport_type: ws|xhttp|grpc
#   $2 - subdomain: e.g., ws.example.com
# Returns: 0 on success, 1 on failure
# ============================================================================
add_transport() {
    local transport_type="$1"
    local subdomain="$2"

    _init_transports_json

    # Validate type
    case "$transport_type" in
        ws|xhttp|grpc) ;;
        *) log_error "Unknown transport type: $transport_type (must be: ws, xhttp, grpc)"; return 1 ;;
    esac

    # Validate subdomain format
    if [[ -z "$subdomain" ]] || ! [[ "$subdomain" =~ \. ]]; then
        log_error "Invalid subdomain: '$subdomain' (expected format: sub.example.com)"
        return 1
    fi

    # Determine internal Xray port
    local port
    case "$transport_type" in
        ws)    port=8444 ;;
        xhttp) port=8445 ;;
        grpc)  port=8446 ;;
    esac

    # Check if transport type already configured
    local existing
    existing=$(jq -r --arg t "$transport_type" '.transports[] | select(.type == $t) | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null)
    if [[ -n "$existing" ]]; then
        log_error "Transport '$transport_type' already configured for subdomain: $existing"
        log_info "Run 'vless remove-transport $transport_type' first to reconfigure"
        return 1
    fi

    # Add to transports.json
    local temp
    temp="${TRANSPORTS_JSON}.tmp.$$"
    jq --arg t "$transport_type" --arg s "$subdomain" --argjson p "$port" \
        '.transports += [{"type": $t, "subdomain": $s, "port": $p, "enabled": true}]' \
        "$TRANSPORTS_JSON" > "$temp" && mv "$temp" "$TRANSPORTS_JSON"

    log_success "Transport '$transport_type' registered: $subdomain → vless_xray:$port"

    # Source required libs (may already be sourced by scripts/vless)
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -f "${lib_dir}/nginx_stream_generator.sh" ]] && source "${lib_dir}/nginx_stream_generator.sh"
    [[ -f "${lib_dir}/orchestrator.sh" ]] && source "${lib_dir}/orchestrator.sh"

    # Regenerate Xray config with Tier 2 inbounds
    log_info "Regenerating Xray config with Tier 2 inbounds..."
    local enable_proxy="${ENABLE_PUBLIC_PROXY:-false}"
    if create_xray_config "$enable_proxy" "true" 2>&1; then
        log_success "Xray config regenerated with Tier 2 inbounds"
    else
        log_error "Failed to regenerate Xray config"
        return 1
    fi

    # Rebuild Nginx config with all current transport subdomains
    _regenerate_nginx_config || return 1

    # Reload containers
    log_info "Reloading containers..."
    docker restart vless_xray 2>/dev/null && log_success "vless_xray restarted" || \
        log_warning "Failed to restart vless_xray (may not be running)"
    docker exec vless_nginx nginx -s reload 2>/dev/null && log_success "vless_nginx reloaded" || \
        log_warning "Failed to reload vless_nginx (may not be running)"

    log_success "Transport '$transport_type' is now active on $subdomain:443"
    return 0
}

# ============================================================================
# INTERNAL: _regenerate_nginx_config
# ============================================================================
# Re-reads all transports from transports.json and regenerates nginx.conf
# ============================================================================
_regenerate_nginx_config() {
    local cert_domain="${CERT_DOMAIN:-${VLESS_DOMAIN:-${DOMAIN:-}}}"
    if [[ -z "$cert_domain" ]]; then
        log_error "CERT_DOMAIN / VLESS_DOMAIN / DOMAIN not set — cannot regenerate nginx.conf"
        return 1
    fi

    local nginx_conf_dir="${VLESS_DIR:-/opt/vless}/config/nginx"
    mkdir -p "$nginx_conf_dir" || {
        log_error "Failed to create $nginx_conf_dir"
        return 1
    }

    # Read all transport subdomains from transports.json
    local ws_sub xhttp_sub grpc_sub
    ws_sub=$(jq -r '.transports[] | select(.type == "ws") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null || true)
    xhttp_sub=$(jq -r '.transports[] | select(.type == "xhttp") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null || true)
    grpc_sub=$(jq -r '.transports[] | select(.type == "grpc") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null || true)

    local has_tier2="false"
    [[ -n "$ws_sub" || -n "$xhttp_sub" || -n "$grpc_sub" ]] && has_tier2="true"

    log_info "Regenerating nginx.conf (ws='$ws_sub' xhttp='$xhttp_sub' grpc='$grpc_sub')..."
    if generate_nginx_config "$cert_domain" "$has_tier2" "$ws_sub" "$xhttp_sub" "$grpc_sub" \
        > "${nginx_conf_dir}/nginx.conf"; then
        log_success "nginx.conf regenerated"
    else
        log_error "Failed to regenerate nginx.conf"
        return 1
    fi

    return 0
}

# ============================================================================
# FUNCTION: list_transports (v5.33)
# ============================================================================
# Description: Display all configured Tier 2 transports in tabular format
# Arguments: none
# Returns: 0 always
# ============================================================================
list_transports() {
    _init_transports_json

    local count
    count=$(jq '.transports | length' "$TRANSPORTS_JSON" 2>/dev/null || echo "0")

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Tier 2 Transports"
    echo "═══════════════════════════════════════════════════════"

    if [[ "$count" == "0" ]]; then
        echo "  No transports configured."
        echo "  Use: sudo vless add-transport ws ws.subdomain.example.com"
    else
        printf "  %-8s %-35s %-6s %-8s\n" "TYPE" "SUBDOMAIN" "PORT" "STATUS"
        echo "  ────────────────────────────────────────────────────────"
        jq -r '.transports[] | [.type, .subdomain, (.port|tostring), (if .enabled then "active" else "disabled" end)] | @tsv' \
            "$TRANSPORTS_JSON" | while IFS=$'\t' read -r t s p e; do
            printf "  %-8s %-35s %-6s %-8s\n" "$t" "$s" "$p" "$e"
        done
    fi
    echo ""
    return 0
}

# ============================================================================
# FUNCTION: remove_transport (v5.33)
# ============================================================================
# Description: Remove a Tier 2 transport.
#   - Removes from transports.json
#   - Removes inbound from xray_config.json
#   - Regenerates nginx.conf (removing the server block and SNI map entry)
#   - Restarts vless_xray
# Arguments:
#   $1 - transport_type: ws|xhttp|grpc
# Returns: 0 on success, 1 on failure
# ============================================================================
remove_transport() {
    local transport_type="$1"

    _init_transports_json

    local existing
    existing=$(jq -r --arg t "$transport_type" '.transports[] | select(.type == $t) | .subdomain' "$TRANSPORTS_JSON")

    if [[ -z "$existing" ]]; then
        log_error "Transport '$transport_type' is not configured"
        return 1
    fi

    # Remove from transports.json
    local temp
    temp="${TRANSPORTS_JSON}.tmp.$$"
    jq --arg t "$transport_type" '.transports = [.transports[] | select(.type != $t)]' \
        "$TRANSPORTS_JSON" > "$temp" && mv "$temp" "$TRANSPORTS_JSON"

    log_success "Transport '$transport_type' removed from transports.json"

    # Remove inbound from xray_config.json
    local xray_config="${XRAY_CONFIG:-/opt/vless/config/xray_config.json}"
    local tag
    case "$transport_type" in
        ws)    tag="vless-websocket" ;;
        xhttp) tag="vless-xhttp" ;;
        grpc)  tag="vless-grpc" ;;
    esac

    if [[ -f "$xray_config" ]]; then
        local xray_temp
        xray_temp="${xray_config}.tmp.$$"
        jq --arg tag "$tag" '.inbounds = [.inbounds[] | select(.tag != $tag)]' \
            "$xray_config" > "$xray_temp" && mv "$xray_temp" "$xray_config"
        log_success "Removed inbound '$tag' from xray_config.json"
    else
        log_warning "xray_config.json not found — skipping inbound removal"
    fi

    # Regenerate nginx.conf without removed transport
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -f "${lib_dir}/nginx_stream_generator.sh" ]] && source "${lib_dir}/nginx_stream_generator.sh"
    _regenerate_nginx_config || log_warning "Failed to regenerate nginx.conf after removal"

    # Reload containers
    docker restart vless_xray 2>/dev/null && log_success "vless_xray restarted" || \
        log_warning "Failed to restart vless_xray"
    docker exec vless_nginx nginx -s reload 2>/dev/null && log_success "vless_nginx reloaded" || \
        log_warning "Failed to reload vless_nginx"

    log_success "Transport '$transport_type' ($existing) removed successfully"
    return 0
}

export -f add_transport
export -f list_transports
export -f remove_transport

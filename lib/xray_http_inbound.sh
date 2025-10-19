#!/bin/bash
# ==============================================================================
# VLESS Reality Deployment System
# Module: Xray HTTP Inbound Management (Reverse Proxy)
# ==============================================================================
#
# Purpose:
#   Manage Xray HTTP inbounds for reverse proxy functionality
#
# Features:
#   - Add/remove HTTP inbounds dynamically
#   - Integrate with Xray outbounds
#   - Hot-reload Xray configuration
#
# Xray Config Location:
#   /opt/vless/config/xray_config.json
#
# Inbound Format:
#   {
#     "tag": "http-in-domain",
#     "port": 18443,
#     "listen": "127.0.0.1",
#     "protocol": "http",
#     "settings": {
#       "allowTransparent": false
#     }
#   }
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-20
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

readonly XRAY_CONFIG="/opt/vless/config/xray_config.json"
readonly XRAY_CONTAINER="vless_xray"

# ==============================================================================
# Function: add_reverseproxy_inbound
# ==============================================================================
# Description: Add HTTP inbound to Xray config for reverse proxy
# Arguments:
#   $1 - inbound_tag (e.g., "http-in-claude")
#   $2 - port (e.g., 18443)
# Returns: 0 on success, 1 on failure
# ==============================================================================
add_reverseproxy_inbound() {
    local tag="$1"
    local port="$2"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo "Error: Xray config not found: $XRAY_CONFIG" >&2
        return 1
    fi

    # Check if inbound already exists
    if jq -e --arg tag "$tag" '.inbounds[] | select(.tag == $tag)' "$XRAY_CONFIG" >/dev/null 2>&1; then
        echo "Warning: Inbound '$tag' already exists" >&2
        return 0
    fi

    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak"

    # Create new inbound
    local new_inbound=$(jq -n \
        --arg tag "$tag" \
        --argjson port "$port" \
        '{
            tag: $tag,
            port: $port,
            listen: "127.0.0.1",
            protocol: "http",
            settings: {
                allowTransparent: false
            }
        }')

    # Add to inbounds array
    jq --argjson inbound "$new_inbound" '.inbounds += [$inbound]' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

    # Validate JSON
    if ! jq empty "${XRAY_CONFIG}.tmp" 2>/dev/null; then
        echo "Error: Generated invalid Xray configuration" >&2
        mv "${XRAY_CONFIG}.bak" "$XRAY_CONFIG"
        rm -f "${XRAY_CONFIG}.tmp"
        return 1
    fi

    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"

    return 0
}

# ==============================================================================
# Function: remove_reverseproxy_inbound
# ==============================================================================
# Description: Remove HTTP inbound from Xray config
# Arguments:
#   $1 - inbound_tag (e.g., "http-in-claude")
# Returns: 0 on success, 1 on failure
# ==============================================================================
remove_reverseproxy_inbound() {
    local tag="$1"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo "Error: Xray config not found: $XRAY_CONFIG" >&2
        return 1
    fi

    # Check if inbound exists
    if ! jq -e --arg tag "$tag" '.inbounds[] | select(.tag == $tag)' "$XRAY_CONFIG" >/dev/null 2>&1; then
        echo "Warning: Inbound '$tag' not found" >&2
        return 0
    fi

    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak"

    # Remove inbound
    jq --arg tag "$tag" 'del(.inbounds[] | select(.tag == $tag))' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"

    # Validate JSON
    if ! jq empty "${XRAY_CONFIG}.tmp" 2>/dev/null; then
        echo "Error: Generated invalid Xray configuration" >&2
        mv "${XRAY_CONFIG}.bak" "$XRAY_CONFIG"
        rm -f "${XRAY_CONFIG}.tmp"
        return 1
    fi

    mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"

    return 0
}

# ==============================================================================
# Function: reload_xray
# ==============================================================================
# Description: Reload Xray container to apply configuration changes
# Returns: 0 on success, 1 on failure
# ==============================================================================
reload_xray() {
    if ! docker ps | grep -q "$XRAY_CONTAINER"; then
        echo "Warning: Xray container not running" >&2
        return 1
    fi

    # Restart container (Docker will use updated config)
    if docker restart "$XRAY_CONTAINER" >/dev/null 2>&1; then
        # Wait for healthcheck
        sleep 3
        return 0
    else
        echo "Error: Failed to reload Xray" >&2
        return 1
    fi
}

# ==============================================================================
# Export Functions
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f add_reverseproxy_inbound
    export -f remove_reverseproxy_inbound
    export -f reload_xray
fi

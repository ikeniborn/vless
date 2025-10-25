#!/bin/bash
#
# Xray Routing Manager Module
# Part of VLESS+Reality VPN Deployment System (v5.23)
#
# Purpose: Manage Xray routing rules for directing traffic through external proxies
#
# Usage: source this file from orchestrator.sh or CLI scripts
#
# Version: 5.23.0
# Date: 2025-10-25

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
readonly XRAY_CONFIG="${XRAY_CONFIG:-/opt/vless/config/xray_config.json}"
readonly EXTERNAL_PROXY_DB="${EXTERNAL_PROXY_DB:-/opt/vless/config/external_proxy.json}"

# =============================================================================
# FUNCTION: generate_routing_rules_json
# =============================================================================
# Description: Generate Xray routing configuration based on mode
# Arguments:
#   $1 - mode (all-traffic | selective | disabled)
#   $2 - outbound_tag (default: "external-proxy")
# Returns: 0 on success, 1 on failure
# Outputs: JSON object for routing section
# =============================================================================
generate_routing_rules_json() {
    local mode="${1:-all-traffic}"
    local outbound_tag="${2:-external-proxy}"

    case "$mode" in
        all-traffic)
            # Route all traffic through external proxy
            cat <<EOF
{
  "domainStrategy": "AsIs",
  "rules": [
    {
      "type": "field",
      "network": "tcp,udp",
      "outboundTag": "${outbound_tag}"
    }
  ]
}
EOF
            ;;

        selective)
            # Selective routing (domain/IP-based rules)
            # Users can add custom rules via add_routing_rule function
            cat <<EOF
{
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    {
      "type": "field",
      "domain": ["geosite:category-ads-all"],
      "outboundTag": "blocked"
    }
  ]
}
EOF
            ;;

        disabled)
            # No routing rules, use default outbound (direct)
            cat <<EOF
{
  "domainStrategy": "AsIs",
  "rules": []
}
EOF
            ;;

        *)
            echo -e "${RED}Invalid routing mode: $mode${NC}" >&2
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# FUNCTION: enable_proxy_routing
# =============================================================================
# Description: Enable routing through external proxy
# Arguments: None (reads from external_proxy.json)
# Returns: 0 on success, 1 on failure
# =============================================================================
enable_proxy_routing() {
    echo -e "${CYAN}Enabling proxy routing...${NC}"

    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo -e "${RED}External proxy database not found${NC}" >&2
        return 1
    fi

    # Get routing mode from database
    local routing_mode
    routing_mode=$(jq -r '.routing.mode' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "all-traffic")

    # Check if there's an active proxy
    local active_proxy_id
    active_proxy_id=$(jq -r '.proxies[] | select(.active == true) | .id' "$EXTERNAL_PROXY_DB" 2>/dev/null)

    if [[ -z "$active_proxy_id" ]]; then
        echo -e "${YELLOW}No active proxy found. Please activate a proxy first.${NC}"
        echo -e "${YELLOW}Use: vless-external-proxy switch <proxy-id>${NC}"
        return 1
    fi

    echo "  ✓ Active proxy: $active_proxy_id"
    echo "  ✓ Routing mode: $routing_mode"

    # Generate routing configuration
    local routing_json
    routing_json=$(generate_routing_rules_json "$routing_mode" "external-proxy") || return 1

    # Update xray_config.json with new routing
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Xray config not found: $XRAY_CONFIG${NC}" >&2
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    # Insert or update routing section
    jq --argjson routing "$routing_json" \
        '.routing = $routing' \
        "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to update Xray config${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$XRAY_CONFIG" 2>/dev/null; then
        echo -e "${RED}Invalid JSON in Xray config after update${NC}" >&2
        return 1
    fi

    # Mark as enabled in database
    local timestamp
    timestamp=$(date -Iseconds)
    temp_file=$(mktemp)

    jq --arg ts "$timestamp" \
        '.enabled = true |
         .metadata.last_modified = $ts' \
        "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"

    echo -e "${GREEN}✓ Proxy routing enabled${NC}"
    echo ""
    echo "⚠️  IMPORTANT: Restart Xray container to apply changes:"
    echo "   docker restart vless_xray"
    return 0
}

# =============================================================================
# FUNCTION: disable_proxy_routing
# =============================================================================
# Description: Disable routing through external proxy (fallback to direct)
# Arguments: None
# Returns: 0 on success, 1 on failure
# =============================================================================
disable_proxy_routing() {
    echo -e "${CYAN}Disabling proxy routing...${NC}"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Xray config not found: $XRAY_CONFIG${NC}" >&2
        return 1
    fi

    # Generate disabled routing configuration
    local routing_json
    routing_json=$(generate_routing_rules_json "disabled") || return 1

    local temp_file
    temp_file=$(mktemp)

    # Update routing section
    jq --argjson routing "$routing_json" \
        '.routing = $routing' \
        "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to update Xray config${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    # Mark as disabled in database
    if [[ -f "$EXTERNAL_PROXY_DB" ]]; then
        local timestamp
        timestamp=$(date -Iseconds)
        temp_file=$(mktemp)

        jq --arg ts "$timestamp" \
            '.enabled = false |
             .metadata.last_modified = $ts' \
            "$EXTERNAL_PROXY_DB" > "$temp_file" && mv "$temp_file" "$EXTERNAL_PROXY_DB"
    fi

    echo -e "${GREEN}✓ Proxy routing disabled${NC}"
    echo ""
    echo "⚠️  IMPORTANT: Restart Xray container to apply changes:"
    echo "   docker restart vless_xray"
    return 0
}

# =============================================================================
# FUNCTION: update_xray_outbounds
# =============================================================================
# Description: Add or update external proxy outbound in xray_config.json
# Arguments:
#   $1 - proxy_id (from external_proxy.json)
# Returns: 0 on success, 1 on failure
# =============================================================================
update_xray_outbounds() {
    local proxy_id="${1:-}"

    if [[ -z "$proxy_id" ]]; then
        echo -e "${RED}Proxy ID is required${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Updating Xray outbounds...${NC}"

    # Source external_proxy_manager to use generate_xray_outbound_json
    if [[ -f "/opt/vless/lib/external_proxy_manager.sh" ]]; then
        source "/opt/vless/lib/external_proxy_manager.sh"
    elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/external_proxy_manager.sh" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/external_proxy_manager.sh"
    else
        echo -e "${RED}external_proxy_manager.sh not found${NC}" >&2
        return 1
    fi

    # Generate outbound JSON
    local outbound_json
    outbound_json=$(generate_xray_outbound_json "$proxy_id") || return 1

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Xray config not found: $XRAY_CONFIG${NC}" >&2
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    # Check if external-proxy outbound already exists
    local existing_count
    existing_count=$(jq '[.outbounds[] | select(.tag == "external-proxy")] | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

    if [[ "$existing_count" == "0" ]]; then
        # Add new outbound (insert before "blocked" outbound for proper order)
        jq --argjson outbound "$outbound_json" \
            '.outbounds = [.outbounds[0]] + [$outbound] + .outbounds[1:]' \
            "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"
        echo "  ✓ Added external-proxy outbound"
    else
        # Update existing outbound
        jq --argjson outbound "$outbound_json" \
            '(.outbounds[] | select(.tag == "external-proxy")) = $outbound' \
            "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"
        echo "  ✓ Updated external-proxy outbound"
    fi

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to update outbounds${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$XRAY_CONFIG" 2>/dev/null; then
        echo -e "${RED}Invalid JSON in Xray config after update${NC}" >&2
        return 1
    fi

    echo -e "${GREEN}✓ Xray outbounds updated${NC}"
    return 0
}

# =============================================================================
# FUNCTION: remove_xray_outbound
# =============================================================================
# Description: Remove external proxy outbound from xray_config.json
# Arguments: None
# Returns: 0 on success, 1 on failure
# =============================================================================
remove_xray_outbound() {
    echo -e "${CYAN}Removing external-proxy outbound...${NC}"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Xray config not found: $XRAY_CONFIG${NC}" >&2
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    # Remove outbound with tag "external-proxy"
    jq '.outbounds = [.outbounds[] | select(.tag != "external-proxy")]' \
        "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to remove outbound${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo -e "${GREEN}✓ External-proxy outbound removed${NC}"
    return 0
}

# =============================================================================
# FUNCTION: add_routing_rule
# =============================================================================
# Description: Add custom routing rule to xray_config.json
# Arguments:
#   $1 - rule_type (domain | ip | port | network)
#   $2 - match_value (e.g., "example.com", "1.1.1.1", "80")
#   $3 - outbound_tag (e.g., "external-proxy", "direct", "blocked")
# Returns: 0 on success, 1 on failure
# =============================================================================
add_routing_rule() {
    local rule_type="${1:-}"
    local match_value="${2:-}"
    local outbound_tag="${3:-external-proxy}"

    if [[ -z "$rule_type" || -z "$match_value" ]]; then
        echo -e "${RED}Rule type and match value are required${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Adding routing rule...${NC}"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Xray config not found: $XRAY_CONFIG${NC}" >&2
        return 1
    fi

    # Build rule JSON based on type
    local rule_json
    case "$rule_type" in
        domain)
            rule_json=$(jq -n --arg domain "$match_value" --arg tag "$outbound_tag" \
                '{type: "field", domain: [$domain], outboundTag: $tag}')
            ;;
        ip)
            rule_json=$(jq -n --arg ip "$match_value" --arg tag "$outbound_tag" \
                '{type: "field", ip: [$ip], outboundTag: $tag}')
            ;;
        port)
            rule_json=$(jq -n --arg port "$match_value" --arg tag "$outbound_tag" \
                '{type: "field", port: $port, outboundTag: $tag}')
            ;;
        network)
            rule_json=$(jq -n --arg network "$match_value" --arg tag "$outbound_tag" \
                '{type: "field", network: $network, outboundTag: $tag}')
            ;;
        *)
            echo -e "${RED}Invalid rule type: $rule_type${NC}" >&2
            return 1
            ;;
    esac

    local temp_file
    temp_file=$(mktemp)

    # Add rule to routing.rules array
    jq --argjson rule "$rule_json" \
        '.routing.rules += [$rule]' \
        "$XRAY_CONFIG" > "$temp_file" && mv "$temp_file" "$XRAY_CONFIG"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to add routing rule${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo "  ✓ Type: $rule_type"
    echo "  ✓ Match: $match_value"
    echo "  ✓ Outbound: $outbound_tag"
    echo -e "${GREEN}✓ Routing rule added${NC}"
    return 0
}

# =============================================================================
# FUNCTION: get_routing_status
# =============================================================================
# Description: Get current routing configuration status
# Arguments: None
# Returns: 0 on success, 1 on failure
# Outputs: Routing status information
# =============================================================================
get_routing_status() {
    echo -e "${CYAN}Routing Status:${NC}"
    echo ""

    # Check if external proxy is enabled
    if [[ ! -f "$EXTERNAL_PROXY_DB" ]]; then
        echo "  Status: ${YELLOW}Not configured${NC}"
        return 0
    fi

    local enabled
    enabled=$(jq -r '.enabled' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "false")

    if [[ "$enabled" == "true" ]]; then
        echo "  Status: ${GREEN}✓ ENABLED${NC}"

        # Get active proxy
        local active_proxy
        active_proxy=$(jq -r '.proxies[] | select(.active == true) |
            "    Active Proxy: " + .id + "\n" +
            "    Type: " + .type + "\n" +
            "    Address: " + .address + ":" + (.port | tostring)' \
            "$EXTERNAL_PROXY_DB" 2>/dev/null)

        if [[ -n "$active_proxy" ]]; then
            echo "$active_proxy"
        else
            echo "    ${YELLOW}⚠️  No active proxy${NC}"
        fi

        # Get routing mode
        local routing_mode
        routing_mode=$(jq -r '.routing.mode' "$EXTERNAL_PROXY_DB" 2>/dev/null || echo "unknown")
        echo "    Routing Mode: $routing_mode"

        # Get routing rules count
        if [[ -f "$XRAY_CONFIG" ]]; then
            local rules_count
            rules_count=$(jq '.routing.rules | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")
            echo "    Routing Rules: $rules_count"
        fi
    else
        echo "  Status: ${YELLOW}✗ DISABLED${NC}"
        echo "    All traffic routes through 'direct' outbound"
    fi

    return 0
}

# Export functions
export -f generate_routing_rules_json
export -f enable_proxy_routing
export -f disable_proxy_routing
export -f update_xray_outbounds
export -f remove_xray_outbound
export -f add_routing_rule
export -f get_routing_status

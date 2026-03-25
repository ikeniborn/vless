#!/bin/bash
# lib/haproxy_config_manager.sh
#
# HAProxy Configuration Manager — DEPRECATED (v5.33)
#
# HAProxy was removed in v5.33. All traffic is now handled by the single
# familytraffic container (nginx + xray + supervisord).
# This module is replaced by: lib/nginx_stream_generator.sh
#
# All functions are preserved as no-op stubs for call-site compatibility.
# Do NOT use these functions — they will log a deprecation warning and return 0.
#
# Version: 5.33.0 (stub)
# Author: familyTraffic Development Team
# Date: 2025-10-17

set -euo pipefail

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [haproxy-config] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [haproxy-config] ERROR: $*" >&2
}

_haproxy_stub_warn() {
    local fn="${1:-unknown}"
    log "ℹ️  ${fn}: HAProxy removed in v5.33 — this is a no-op stub"
    log "    Use lib/nginx_stream_generator.sh for SNI routing configuration"
}

# =============================================================================
# No-op stubs (preserved for call-site compatibility)
# =============================================================================

generate_haproxy_config() {
    _haproxy_stub_warn "generate_haproxy_config"
    return 0
}

add_reverse_proxy_route() {
    _haproxy_stub_warn "add_reverse_proxy_route"
    return 0
}

remove_reverse_proxy_route() {
    _haproxy_stub_warn "remove_reverse_proxy_route"
    return 0
}

validate_haproxy_config() {
    _haproxy_stub_warn "validate_haproxy_config"
    return 0
}

reload_haproxy() {
    _haproxy_stub_warn "reload_haproxy"
    return 0
}

check_haproxy_status() {
    _haproxy_stub_warn "check_haproxy_status"
    return 0
}

list_haproxy_routes() {
    _haproxy_stub_warn "list_haproxy_routes"
    return 0
}

# =============================================================================
# Main execution (for testing)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "⚠️  haproxy_config_manager.sh is DEPRECATED in v5.33"
    echo "   HAProxy removed — use lib/nginx_stream_generator.sh instead"
    exit 0
fi

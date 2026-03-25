#!/bin/bash
################################################################################
# lib/validation.sh
#
# Reverse Proxy Validation Module (stub — v5.33)
# HAProxy and nginx_reverseproxy were removed in v5.33 (single-container arch).
# Both validate_reverse_proxy() and validate_reverse_proxy_removed() are kept
# as no-op stubs to preserve call-site compatibility with existing callers.
#
# Usage:
#   source lib/validation.sh
#   validate_reverse_proxy "example.com" 9443        # no-op, returns 0
#   validate_reverse_proxy_removed "example.com" 9443 # no-op, returns 0
#
# Version: 5.33.0
# Author: familyTraffic Development Team
# Date: 2026-02-25
################################################################################

set -euo pipefail

# Logging functions (if not already defined)
if ! command -v log &> /dev/null; then
    log() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [validation] $*" >&2
    }
fi

if ! command -v log_error &> /dev/null; then
    log_error() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [validation] ERROR: $*" >&2
    }
fi

# =============================================================================
# Function: validate_reverse_proxy  [NO-OP STUB — v5.33]
# Description: Reverse proxy (HAProxy + nginx_reverseproxy) was removed in
#              v5.33 as part of the migration to single-container architecture.
#              This stub preserves call-site compatibility; always returns 0.
# =============================================================================
validate_reverse_proxy() {
    local domain="${1:-}"
    local port="${2:-}"
    log "ℹ️  validate_reverse_proxy: reverse proxy removed in v5.33 — skipping validation for ${domain}:${port}"
    log "    Single-container (familytraffic) handles nginx internally via supervisord."
    log "    To verify nginx: docker exec familytraffic supervisorctl status nginx"
    return 0
}

# =============================================================================
# Function: validate_reverse_proxy_removed  [NO-OP STUB — v5.33]
# Description: Reverse proxy (HAProxy + nginx_reverseproxy) was removed in
#              v5.33. There is nothing to "verify removed" — it's gone by design.
#              This stub preserves call-site compatibility; always returns 0.
# =============================================================================
validate_reverse_proxy_removed() {
    local domain="${1:-}"
    local port="${2:-}"
    log "ℹ️  validate_reverse_proxy_removed: reverse proxy removed in v5.33 — nothing to verify for ${domain}:${port}"
    return 0
}

################################################################################
# Module loaded successfully
################################################################################

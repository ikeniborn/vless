#!/bin/sh
# ============================================================================
# MTProxy Docker Entrypoint Script (v6.0)
# ============================================================================
#
# Purpose:
#   Initialize and start MTProxy server with configuration from mounted files
#
# Configuration files (mounted from /opt/familytraffic/config/mtproxy/):
#   - mtproxy_config.json: Main configuration (port, workers)
#   - proxy-secret: MTProxy secret(s) (one per line for multi-user)
#   - proxy-multi.conf: Telegram DC addresses
#
# Environment variables:
#   MTPROXY_PORT: Public port (default: from config file or 8443)
#   MTPROXY_WORKERS: Worker threads (default: from config file or 2)
#   MTPROXY_STATS_PORT: Stats endpoint port (default: 8888)
#   MTPROXY_DEBUG: Enable debug logging (default: false)
#
# Author: VLESS Development Team
# Date: 2025-11-08
# ============================================================================

set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[MTProxy]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[MTProxy ✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[MTProxy ⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[MTProxy ✗]${NC} $*" >&2
}

# Configuration paths
CONFIG_DIR="/etc/mtproxy"
CONFIG_FILE="${CONFIG_DIR}/mtproxy_config.json"
SECRET_FILE="${CONFIG_DIR}/proxy-secret"
MULTI_CONF="${CONFIG_DIR}/proxy-multi.conf"
LOG_DIR="/var/log/mtproxy"

log_info "MTProxy starting..."
log_info "Configuration directory: ${CONFIG_DIR}"

# ============================================================================
# Validation: Check required files
# ============================================================================

if [ ! -f "${SECRET_FILE}" ]; then
    log_error "Secret file not found: ${SECRET_FILE}"
    log_error "Please mount /opt/familytraffic/config/mtproxy/ to /etc/mtproxy/"
    exit 1
fi

if [ ! -f "${MULTI_CONF}" ]; then
    log_warning "proxy-multi.conf not found: ${MULTI_CONF}"
    log_warning "MTProxy will work, but without Telegram DC address hints"
fi

# ============================================================================
# Parse configuration from mtproxy_config.json (if exists)
# ============================================================================

MTPROXY_PORT="${MTPROXY_PORT:-8443}"
MTPROXY_WORKERS="${MTPROXY_WORKERS:-2}"
MTPROXY_STATS_PORT="${MTPROXY_STATS_PORT:-8888}"

if [ -f "${CONFIG_FILE}" ]; then
    log_info "Loading configuration from: ${CONFIG_FILE}"

    # Extract port and workers using grep/sed (no jq in alpine)
    if command -v jq >/dev/null 2>&1; then
        # Use jq if available
        MTPROXY_PORT=$(jq -r '.port // 8443' "${CONFIG_FILE}")
        MTPROXY_WORKERS=$(jq -r '.workers // 2' "${CONFIG_FILE}")
        MTPROXY_STATS_PORT=$(jq -r '.stats_port // 8888' "${CONFIG_FILE}")
    else
        # Fallback to grep/sed parsing (less robust but works)
        MTPROXY_PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "${CONFIG_FILE}" | grep -o '[0-9]*' || echo "8443")
        MTPROXY_WORKERS=$(grep -o '"workers"[[:space:]]*:[[:space:]]*[0-9]*' "${CONFIG_FILE}" | grep -o '[0-9]*' || echo "2")
        MTPROXY_STATS_PORT=$(grep -o '"stats_port"[[:space:]]*:[[:space:]]*[0-9]*' "${CONFIG_FILE}" | grep -o '[0-9]*' || echo "8888")
    fi

    log_success "Configuration loaded"
else
    log_warning "Config file not found: ${CONFIG_FILE}"
    log_warning "Using defaults: port=${MTPROXY_PORT}, workers=${MTPROXY_WORKERS}"
fi

# ============================================================================
# Validate secret file
# ============================================================================

# Count secrets (one per line)
SECRET_COUNT=$(wc -l < "${SECRET_FILE}")

if [ "${SECRET_COUNT}" -eq 0 ]; then
    log_error "No secrets found in ${SECRET_FILE}"
    log_error "File must contain at least one secret (32/34 hex characters)"
    exit 1
fi

log_success "Found ${SECRET_COUNT} secret(s)"

# ============================================================================
# Build MTProxy command arguments
# ============================================================================

MTPROXY_CMD="mtproto-proxy"
MTPROXY_ARGS=""

# Port
MTPROXY_ARGS="${MTPROXY_ARGS} -p ${MTPROXY_PORT}"

# Stats port (localhost only - use 127.0.0.1 binding)
MTPROXY_ARGS="${MTPROXY_ARGS} -H ${MTPROXY_STATS_PORT}"

# Workers
MTPROXY_ARGS="${MTPROXY_ARGS} -M ${MTPROXY_WORKERS}"

# Secret file
MTPROXY_ARGS="${MTPROXY_ARGS} -S ${SECRET_FILE}"

# Multi-config (Telegram DC addresses) if exists
if [ -f "${MULTI_CONF}" ]; then
    MTPROXY_ARGS="${MTPROXY_ARGS} -C ${MULTI_CONF}"
fi

# Log to stdout/stderr (Docker best practice)
MTPROXY_ARGS="${MTPROXY_ARGS} --log-level info"

# Debug mode (if enabled)
if [ "${MTPROXY_DEBUG:-false}" = "true" ]; then
    MTPROXY_ARGS="${MTPROXY_ARGS} --log-level debug"
    log_warning "Debug logging enabled"
fi

# ============================================================================
# Display configuration summary
# ============================================================================

log_info "╔══════════════════════════════════════════════════════════╗"
log_info "║         MTProxy Configuration Summary                    ║"
log_info "╚══════════════════════════════════════════════════════════╝"
log_info "  Port:           ${MTPROXY_PORT}"
log_info "  Stats Port:     ${MTPROXY_STATS_PORT} (localhost only)"
log_info "  Workers:        ${MTPROXY_WORKERS}"
log_info "  Secrets:        ${SECRET_COUNT}"
log_info "  Multi-user:     $([ "${SECRET_COUNT}" -gt 1 ] && echo "YES (v6.1)" || echo "NO (v6.0)")"
log_info "  Secret file:    ${SECRET_FILE}"
log_info "  Multi-conf:     $([ -f "${MULTI_CONF}" ] && echo "YES" || echo "NO")"
log_info "════════════════════════════════════════════════════════════"

# ============================================================================
# Signal handling (graceful shutdown)
# ============================================================================

# Trap SIGTERM and SIGINT for graceful shutdown
trap 'log_info "Received shutdown signal, stopping MTProxy..."; kill -TERM "$MTPROXY_PID"; wait "$MTPROXY_PID"; exit 0' TERM INT

# ============================================================================
# Start MTProxy
# ============================================================================

log_success "Starting MTProxy..."
log_info "Command: ${MTPROXY_CMD} ${MTPROXY_ARGS}"

# Execute MTProxy (replace shell with MTProxy process)
# shellcheck disable=SC2086
exec ${MTPROXY_CMD} ${MTPROXY_ARGS} &

MTPROXY_PID=$!
log_success "MTProxy started (PID: ${MTPROXY_PID})"

# Wait for MTProxy process
wait "$MTPROXY_PID"

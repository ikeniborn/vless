#!/bin/bash
# lib/docker_compose_generator.sh
#
# Docker Compose Configuration Generator (v4.3 Unified HAProxy)
# Generates docker-compose.yml dynamically via heredoc (no static files)
#
# Features:
# - Full docker-compose.yml generation via heredoc
# - HAProxy unified TLS termination (ports 443, 1080, 8118)
# - stunnel REMOVED (replaced by HAProxy)
# - Dynamic port management for nginx reverse proxy (9443-9452)
# - Integration with lib/docker_compose_manager.sh
# - PRD v4.1 compliant (no templates, all heredoc)
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-17

set -euo pipefail

# Configuration
VLESS_DIR="${VLESS_DIR:-/opt/familytraffic}"
DOCKER_COMPOSE_FILE="${VLESS_DIR}/docker-compose.yml"
DOCKER_SUBNET="${DOCKER_SUBNET:-172.20.0.0/16}"
# v5.1: VLESS_PORT is internal port 8443 (HAProxy listens on 443 externally)
VLESS_PORT="${VLESS_PORT:-8443}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [docker-compose-gen] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [docker-compose-gen] ERROR: $*" >&2
}

# =============================================================================
# Function: generate_docker_compose
# Description: Generates complete docker-compose.yml via heredoc (v4.3 unified HAProxy)
#
# Parameters:
#   $@ - nginx_ports: Array of ports for nginx reverse proxy (e.g., 9443 9444)
#        NEW in v4.3: ports are 9443-9452 (not 8443-8452)
#        Empty array = no ports exposed (reverse proxy not configured)
#
# Returns:
#   0 on success, 1 on failure
#
# Output:
#   Creates /opt/familytraffic/docker-compose.yml
#
# Example:
#   generate_docker_compose 9443 9444 9445
# =============================================================================
generate_docker_compose() {
    local nginx_ports=("$@")
    local enable_reverse_proxy="${ENABLE_REVERSE_PROXY:-false}"
    local enable_mtproxy="${ENABLE_MTPROXY:-false}"

    log "Generating docker-compose.yml (heredoc-based, v6.0 with MTProxy)"
    log "  VLESS Port: ${VLESS_PORT} (Xray internal port)"
    log "  Docker Subnet: ${DOCKER_SUBNET}"
    log "  Reverse Proxy: ${enable_reverse_proxy}"
    log "  Nginx Ports: ${nginx_ports[*]:-none} (localhost only)"
    log "  MTProxy: ${enable_mtproxy}"

    # Create backup if file exists
    if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
        cp "${DOCKER_COMPOSE_FILE}" "${DOCKER_COMPOSE_FILE}.bak"
        log "  Backup created: ${DOCKER_COMPOSE_FILE}.bak"
    fi

    # Generate nginx ports section (localhost-only, new range 9443-9452)
    local nginx_ports_yaml=""
    if [ ${#nginx_ports[@]} -gt 0 ]; then
        for port in "${nginx_ports[@]}"; do
            nginx_ports_yaml+="
      - \"127.0.0.1:${port}:${port}\""
        done
    else
        # Empty ports array (reverse proxy not configured)
        nginx_ports_yaml=" []  # Empty by default - populated dynamically"
    fi

    # v5.33: nginx_service_section removed — single container handles all services
    # Reverse proxy legacy removed per plan

    # Generate MTProxy service section conditionally (v6.0)
    local mtproxy_service_section=""
    if [[ "${enable_mtproxy}" == "true" ]]; then
        # Read MTProxy configuration if exists
        local mtproxy_port="${MTPROXY_PORT:-8443}"
        local mtproxy_stats_port="${MTPROXY_STATS_PORT:-8888}"

        mtproxy_service_section=$(cat <<'MTPROXY_SERVICE'

  # ===========================================================================
  # MTProxy Service (v6.0 - Telegram Proxy)
  # Official Telegram MTProxy for transport obfuscation
  # ===========================================================================
  mtproxy:
    build:
      context: ${VLESS_DIR}
      dockerfile: docker/mtproxy/Dockerfile
    image: vless/mtproxy:latest
    container_name: vless_mtproxy
    restart: unless-stopped
    ports:
      - "8443:8443"                    # MTProxy public port (Telegram traffic)
      - "127.0.0.1:8888:8888"          # Stats endpoint (localhost only)
    volumes:
      - ${VLESS_DIR}/config/mtproxy:/etc/mtproxy:ro
      - ${VLESS_DIR}/logs/mtproxy:/var/log/mtproxy
      - ${VLESS_DIR}/data/mtproxy:/var/lib/mtproxy
    networks:
      - vless_reality_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
MTPROXY_SERVICE
)
    else
        mtproxy_service_section=$(cat <<'NO_MTPROXY_SERVICE'

  # ===========================================================================
  # MTProxy Service: DISABLED (v6.0)
  # MTProxy was not enabled during installation
  # To enable: run 'sudo vless-mtproxy-setup'
  # ===========================================================================
NO_MTPROXY_SERVICE
)
    fi

    # Generate docker-compose.yml via heredoc (v5.33 single container)
    # Note: 'version' attribute removed (obsolete in Docker Compose v2)
    cat > "${DOCKER_COMPOSE_FILE}" <<EOF
services:
  # ===========================================================================
  # familytraffic — single container (nginx + xray + certbot + supervisord)
  # v5.33: replaces multi-container architecture (single container consolidation)
  # network_mode: host — all processes share host network, Docker DNS unused
  # ===========================================================================
  familytraffic:
    image: \${GHCR_IMAGE:-ghcr.io/OWNER/familytraffic}:\${VERSION:-latest}
    container_name: familytraffic
    network_mode: host
    restart: unless-stopped
    volumes:
      # nginx config (generated by lib/nginx_stream_generator.sh)
      - /opt/familytraffic/config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      # supervisord config
      - /etc/familytraffic/supervisord.conf:/etc/familytraffic/supervisord.conf:ro
      # xray config (mapped to expected path inside container)
      - /opt/familytraffic/config/xray_config.json:/etc/xray/config.json:ro
      # users json (live-reloadable via xray)
      - /opt/familytraffic/data/users.json:/etc/xray/users.json:ro
      # Let's Encrypt certificates (read-write for certbot renewal)
      - /etc/letsencrypt:/etc/letsencrypt
      # ACME webroot for certbot --webroot renewal
      - /var/www/html:/var/www/html
    env_file:
      - /opt/familytraffic/.env
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
EOF

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "✅ docker-compose.yml generated successfully"
        log "  Location: ${DOCKER_COMPOSE_FILE}"
        return 0
    else
        log_error "❌ Failed to generate docker-compose.yml"

        # Restore backup if generation failed
        if [ -f "${DOCKER_COMPOSE_FILE}.bak" ]; then
            mv "${DOCKER_COMPOSE_FILE}.bak" "${DOCKER_COMPOSE_FILE}"
            log "  Backup restored"
        fi

        return 1
    fi
}

# =============================================================================
# Function: validate_docker_compose
# Description: Validates generated docker-compose.yml
#
# Returns:
#   0 if valid, 1 if invalid
# =============================================================================
validate_docker_compose() {
    log "Validating docker-compose.yml..."

    if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
        log_error "docker-compose.yml not found: ${DOCKER_COMPOSE_FILE}"
        return 1
    fi

    # Validate YAML syntax
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f "${DOCKER_COMPOSE_FILE}" config > /dev/null 2>&1; then
            log "✅ docker-compose.yml is valid"
            return 0
        else
            log_error "❌ docker-compose.yml has syntax errors"
            docker-compose -f "${DOCKER_COMPOSE_FILE}" config 2>&1 | head -10
            return 1
        fi
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        if docker compose -f "${DOCKER_COMPOSE_FILE}" config > /dev/null 2>&1; then
            log "✅ docker-compose.yml is valid"
            return 0
        else
            log_error "❌ docker-compose.yml has syntax errors"
            docker compose -f "${DOCKER_COMPOSE_FILE}" config 2>&1 | head -10
            return 1
        fi
    else
        log "⚠️  Warning: docker-compose not found, skipping validation"
        return 0
    fi
}

# =============================================================================
# Function: get_current_nginx_ports
# Description: Extracts current nginx ports from docker-compose.yml (v4.3)
#
# Returns:
#   Array of ports (one per line) to stdout
#
# Note: v4.3 ports are 9443-9452 with localhost binding (127.0.0.1:PORT:PORT)
# =============================================================================
get_current_nginx_ports() {
    if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
        return 0
    fi

    # Extract ports from nginx service using grep/sed
    # v4.3 Format: - "127.0.0.1:9443:9443" → 9443
    # v5.21: Increased -A 20 → -A 30 to ensure ports section is captured
    grep -A 30 "^  nginx:" "${DOCKER_COMPOSE_FILE}" \
        | grep -E '^\s+- "(127\.0\.0\.1:)?[0-9]+:[0-9]+"' \
        | sed -E 's/.*"(127\.0\.0\.1:)?([0-9]+):[0-9]+".*/\2/' \
        | grep -E '^94[4-5][0-9]$' \
        || true
}

# =============================================================================
# Main execution (for testing)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [ $# -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  generate [PORT1 PORT2 ...]  - Generate docker-compose.yml with nginx ports"
        echo "  validate                     - Validate existing docker-compose.yml"
        echo "  get-ports                    - Show current nginx ports"
        echo ""
        echo "Examples:"
        echo "  $0 generate                 # No nginx ports (reverse proxy not configured)"
        echo "  $0 generate 9443 9444       # With 2 nginx ports (v4.3)"
        echo "  $0 validate                 # Validate syntax"
        echo "  $0 get-ports                # List current ports"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        generate)
            generate_docker_compose "$@" && validate_docker_compose
            ;;
        validate)
            validate_docker_compose
            ;;
        get-ports)
            get_current_nginx_ports
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
fi

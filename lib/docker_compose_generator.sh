#!/bin/bash
# lib/docker_compose_generator.sh
#
# Docker Compose Configuration Generator (v5.33 single-container)
#
# Relationship with the static docker-compose.yml in the repo root:
#   - docker-compose.yml (repo root) — base service definition, version-controlled,
#     synced to /opt/familytraffic/ by CI/CD on every test deploy
#   - generate_docker_compose() below — writes the same base block PLUS appends
#     the optional MTProxy service section when ENABLE_MTPROXY=true
#   - CI/CD deploy ONLY updates the base block; if MTProxy is enabled on the server,
#     run `familytraffic-mtproxy-setup` once after the first CI deploy to re-append
#     the MTProxy block below the sentinel comment line
#
# Version: 5.33.0
# Author: familyTraffic Development Team
# Date: 2026-02-25

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

        # WARN-4 fix: mtproxy section now correctly interpolated into compose heredoc below
        # WARN-5 fix: no vless_reality_net — MTProxy uses standalone bridge (separate from host-mode container)
        # Note: ${INSTALL_ROOT} uses double-quotes so the var is expanded at generation time
        mtproxy_service_section="
  # ===========================================================================
  # MTProxy Service (v6.0 - Telegram Proxy)
  # Standalone container — communicates directly with Telegram servers
  # No shared network with familytraffic (host-mode container uses host network)
  # ===========================================================================
  mtproxy:
    build:
      context: ${INSTALL_ROOT}
      dockerfile: docker/mtproxy/Dockerfile
    image: familytraffic/mtproxy:latest
    container_name: familytraffic_mtproxy
    restart: unless-stopped
    ports:
      - \"${MTPROXY_PORT:-8443}:${MTPROXY_PORT:-8443}\"
      - \"127.0.0.1:${MTPROXY_STATS_PORT:-8888}:${MTPROXY_STATS_PORT:-8888}\"
    volumes:
      - ${INSTALL_ROOT}/config/mtproxy:/etc/mtproxy:ro
      - ${INSTALL_ROOT}/data/mtproxy:/var/lib/mtproxy
    logging:
      driver: \"json-file\"
      options:
        max-size: \"10m\"
        max-file: \"3\"
    healthcheck:
      test: [\"CMD\", \"nc\", \"-z\", \"127.0.0.1\", \"${MTPROXY_PORT:-8443}\"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s"
    else
        mtproxy_service_section="
  # MTProxy: DISABLED — enable via sudo familytraffic-mtproxy-setup"
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
      # BUG-1 fix: supervisord.conf is baked into image — do NOT mount from host
      # (/etc/familytraffic/ does not exist on host; mounting it would shadow the baked file)
      # xray config (exact file path — do NOT mount the data/ directory)
      - /opt/familytraffic/config/xray_config.json:/etc/xray/config.json:ro
      # users json (live-reloadable via xray SIGHUP)
      - /opt/familytraffic/data/users.json:/etc/xray/users.json:ro
      # Let's Encrypt certificates (read-write: certbot renew writes new certs)
      - /etc/letsencrypt:/etc/letsencrypt
      # ACME webroot for certbot --webroot renewal (nginx serves /.well-known/)
      - /var/www/html:/var/www/html
    env_file:
      - /opt/familytraffic/.env
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      # nc provided by netcat-openbsd installed in Dockerfile (WARN-1 fix)
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
${mtproxy_service_section}
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

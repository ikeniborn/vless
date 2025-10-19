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
VLESS_DIR="${VLESS_DIR:-/opt/vless}"
DOCKER_COMPOSE_FILE="${VLESS_DIR}/docker-compose.yml"
DOCKER_SUBNET="${DOCKER_SUBNET:-172.20.0.0/16}"
VLESS_PORT="${VLESS_PORT:-443}"

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
#   Creates /opt/vless/docker-compose.yml
#
# Example:
#   generate_docker_compose 9443 9444 9445
# =============================================================================
generate_docker_compose() {
    local nginx_ports=("$@")

    log "Generating docker-compose.yml (heredoc-based, v4.3 unified HAProxy)"
    log "  VLESS Port: ${VLESS_PORT} (HAProxy backend)"
    log "  Docker Subnet: ${DOCKER_SUBNET}"
    log "  Nginx Ports: ${nginx_ports[*]:-none} (localhost only)"

    # Create backup if file exists
    if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
        cp "${DOCKER_COMPOSE_FILE}" "${DOCKER_COMPOSE_FILE}.bak"
        log "  Backup created: ${DOCKER_COMPOSE_FILE}.bak"
    fi

    # Generate nginx ports section (localhost-only, new range 9443-9452)
    local nginx_ports_yaml=""
    if [ ${#nginx_ports[@]} -gt 0 ]; then
        for port in "${nginx_ports[@]}"; do
            nginx_ports_yaml+="      - \"127.0.0.1:${port}:${port}\"\n"
        done
    else
        # Empty ports array (reverse proxy not configured)
        nginx_ports_yaml="[]  # Empty by default - populated dynamically"
    fi

    # Generate docker-compose.yml via heredoc (v4.3)
    # Note: 'version' attribute removed (obsolete in Docker Compose v2)
    cat > "${DOCKER_COMPOSE_FILE}" <<EOF
services:
  # ===========================================================================
  # HAProxy Service (v4.3 NEW - Unified TLS Termination)
  # Handles ALL ports: 443 (SNI routing), 1080 (SOCKS5 TLS), 8118 (HTTP TLS)
  # ===========================================================================
  haproxy:
    image: haproxy:2.8-alpine
    container_name: vless_haproxy
    restart: unless-stopped
    network_mode: host  # Direct access to host network stack
    volumes:
      - ${VLESS_DIR}/config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro  # Certificates for all ports
      - ${VLESS_DIR}/logs/haproxy/:/var/log/haproxy/
    cap_add:
      - NET_BIND_SERVICE
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ===========================================================================
  # Xray-core Service (VLESS Reality + Proxy Inbounds)
  # ===========================================================================
  xray:
    image: teddysun/xray:24.11.30
    container_name: vless_xray
    restart: unless-stopped
    user: nobody
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - ${VLESS_DIR}/config/xray_config.json:/etc/xray/config.json:ro
      - ${VLESS_DIR}/logs/xray/:/var/log/xray/
    ports:
      # v4.3 CHANGE: VLESS на localhost only (HAProxy forwards)
      - "127.0.0.1:8443:8443"
      # Note: SOCKS5/HTTP plaintext ports (10800/18118) not exposed to host
      # HAProxy (host mode) accesses these via 127.0.0.1
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
      timeout: 10s
      retries: 3
      start_period: 10s

  # ===========================================================================
  # Nginx Reverse Proxy Service (v4.3 UPDATE)
  # Site-Specific Reverse Proxy for Blocked Websites
  # ===========================================================================
  nginx:
    image: nginx:alpine
    container_name: vless_nginx_reverseproxy
    restart: unless-stopped
    user: nginx
    volumes:
      # Main reverse proxy configs (generated by lib/nginx_config_generator.sh)
      - ${VLESS_DIR}/config/reverse-proxy/:/etc/nginx/conf.d/reverse-proxy/:ro

      # HTTP context config (rate limiting, fail2ban log format)
      # Generated by lib/nginx_config_generator.sh::generate_reverseproxy_http_context()
      - ${VLESS_DIR}/config/reverse-proxy/http_context.conf:/etc/nginx/conf.d/reverse-proxy/http_context.conf:ro

      # Let's Encrypt certificates (read-only)
      - /etc/letsencrypt:/etc/letsencrypt:ro

      # Logs for fail2ban monitoring
      - ${VLESS_DIR}/logs/nginx/:/var/log/nginx/

    # v4.3 CHANGE: Port mappings now localhost-only (9443-9452, not 8443-8452)
    # Managed dynamically via lib/docker_compose_manager.sh
    ports: ${nginx_ports_yaml}

    networks:
      - vless_reality_net

    depends_on:
      - xray

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # Health check
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

    # Tmpfs mounts for nginx cache (required when running as user: nginx)
    tmpfs:
      - /var/cache/nginx:uid=101,gid=101
      - /var/run:uid=101,gid=101

  # ===========================================================================
  # Certbot Nginx Service (v4.3 NEW - ACME HTTP-01 Challenges)
  # Runs only when needed for certificate acquisition
  # ===========================================================================
  certbot_nginx:
    image: nginx:alpine
    container_name: vless_certbot_nginx
    restart: "no"  # Do not restart automatically
    network_mode: host  # Direct access to port 80
    volumes:
      - ${VLESS_DIR}/config/certbot-nginx/:/etc/nginx/conf.d/:ro
      - /var/www/certbot:/var/www/certbot:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    profiles:
      - certbot  # Start only with: docker-compose --profile certbot up

  # ===========================================================================
  # Nginx Fake Site Service (VLESS Reality Fallback)
  # Shows legitimate website for invalid VLESS connections
  # ===========================================================================
  fake-site:
    image: nginx:alpine
    container_name: vless_fake_site
    restart: unless-stopped
    user: nginx
    volumes:
      - ${VLESS_DIR}/fake-site/:/etc/nginx/conf.d/:ro
      - ${VLESS_DIR}/logs/fake-site/:/var/log/nginx/
    networks:
      - vless_reality_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # Tmpfs mounts for nginx cache (required when running as user: nginx)
    tmpfs:
      - /var/cache/nginx:uid=101,gid=101
      - /var/run:uid=101,gid=101

# =============================================================================
# Networks
# =============================================================================
# Network is created externally by orchestrator.sh (Step 9: create_docker_network)
# Docker Compose uses existing network instead of trying to manage it
networks:
  vless_reality_net:
    external: true
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
    grep -A 20 "^  nginx:" "${DOCKER_COMPOSE_FILE}" \
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

#!/bin/bash
#
# Installation Orchestrator Module
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Orchestrate the complete installation process by creating directory
#          structure, generating configurations, setting up networking, and
#          deploying Docker containers.
# Usage: source this file from install.sh
#
# TASK-1.7: Installation orchestration (5h)
#
# This module uses parameters collected by interactive_params.sh:
#   - REALITY_DEST
#   - REALITY_DEST_PORT
#   - VLESS_PORT
#   - DOCKER_SUBNET
#

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Color codes for output
# Only define if not already set (to avoid conflicts when sourced after install.sh)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && CYAN='\033[0;36m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# Installation paths
readonly INSTALL_ROOT="/opt/vless"
readonly CONFIG_DIR="${INSTALL_ROOT}/config"
readonly DATA_DIR="${INSTALL_ROOT}/data"
readonly LOGS_DIR="${INSTALL_ROOT}/logs"
readonly KEYS_DIR="${INSTALL_ROOT}/keys"
readonly SCRIPTS_DIR="${INSTALL_ROOT}/scripts"
readonly FAKESITE_DIR="${INSTALL_ROOT}/fake-site"
readonly DOCS_DIR="${INSTALL_ROOT}/docs"
readonly TESTS_DIR="${INSTALL_ROOT}/tests"

# Docker configuration
readonly DOCKER_NETWORK_NAME="vless_reality_net"
readonly XRAY_IMAGE="teddysun/xray:24.11.30"
readonly NGINX_IMAGE="nginx:alpine"
readonly XRAY_CONTAINER_NAME="vless_xray"
readonly NGINX_CONTAINER_NAME="vless_nginx"

# Configuration files
readonly XRAY_CONFIG="${CONFIG_DIR}/xray_config.json"
readonly USERS_JSON="${DATA_DIR}/users.json"
readonly DOCKER_COMPOSE_FILE="${INSTALL_ROOT}/docker-compose.yml"
readonly NGINX_CONFIG="${FAKESITE_DIR}/default.conf"
readonly ENV_FILE="${INSTALL_ROOT}/.env"

# UFW configuration
readonly UFW_AFTER_RULES="/etc/ufw/after.rules"
readonly UFW_BACKUP_DIR="/tmp/ufw_backup_$(date +%Y%m%d_%H%M%S)"

# Generated keys and IDs (will be set during execution)
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=""

# =============================================================================
# FUNCTION: orchestrate_installation
# =============================================================================
# Description: Main orchestration function that coordinates all installation steps
# Called by: install.sh main() at Step 8
# Returns: 0 on success, 1 on failure
# =============================================================================
orchestrate_installation() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           INSTALLATION ORCHESTRATION                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Create directory structure
    create_directory_structure || {
        echo -e "${RED}Failed to create directory structure${NC}" >&2
        return 1
    }

    # Step 2: Generate X25519 keys
    generate_reality_keys || {
        echo -e "${RED}Failed to generate Reality keys${NC}" >&2
        return 1
    }

    # Step 3: Generate Short ID
    generate_short_id || {
        echo -e "${RED}Failed to generate Short ID${NC}" >&2
        return 1
    }

    # Step 4: Create Xray configuration (with optional proxy support)
    # v3.2: Use ENABLE_PUBLIC_PROXY to determine if proxy inbounds should be created
    create_xray_config "${ENABLE_PUBLIC_PROXY:-false}" || {
        echo -e "${RED}Failed to create Xray configuration${NC}" >&2
        return 1
    }

    # Step 5: Create empty users.json
    create_users_json || {
        echo -e "${RED}Failed to create users.json${NC}" >&2
        return 1
    }

    # Step 6: Create Nginx configuration
    create_nginx_config || {
        echo -e "${RED}Failed to create Nginx configuration${NC}" >&2
        return 1
    }

    # Step 7: Create docker-compose.yml
    create_docker_compose || {
        echo -e "${RED}Failed to create docker-compose.yml${NC}" >&2
        return 1
    }

    # Step 8: Create .env file
    create_env_file || {
        echo -e "${RED}Failed to create .env file${NC}" >&2
        return 1
    }

    # Step 9: Create Docker network
    create_docker_network || {
        echo -e "${RED}Failed to create Docker network${NC}" >&2
        return 1
    }

    # Step 9.5: Setup fail2ban (v3.2 - conditional on ENABLE_PUBLIC_PROXY)
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        echo ""
        echo -e "${CYAN}[9.5/12] Setting up fail2ban for public proxy protection...${NC}"

        # Source fail2ban module
        if [[ -f "${SCRIPT_DIR}/lib/fail2ban_setup.sh" ]]; then
            source "${SCRIPT_DIR}/lib/fail2ban_setup.sh"
        fi

        if ! setup_fail2ban_for_proxy; then
            echo -e "${RED}Failed to setup fail2ban${NC}" >&2
            echo -e "${YELLOW}WARNING: Public proxy will be less secure without fail2ban${NC}"
            echo -e "${YELLOW}Continue installation? [y/N]: ${NC}" >&2
            read -r response
            if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
                return 1
            fi
        fi
    fi

    # Step 10: Configure UFW firewall
    configure_ufw || {
        echo -e "${RED}Failed to configure UFW${NC}" >&2
        return 1
    }

    # Step 10.5: Configure proxy firewall rules (v3.2 - conditional on ENABLE_PUBLIC_PROXY)
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        configure_proxy_firewall_rules || {
            echo -e "${RED}Failed to configure proxy firewall rules${NC}" >&2
            return 1
        }
    fi

    # Step 11: Deploy containers
    deploy_containers || {
        echo -e "${RED}Failed to deploy containers${NC}" >&2
        return 1
    }

    # Step 12: Install CLI tools
    install_cli_tools || {
        echo -e "${RED}Failed to install CLI tools${NC}" >&2
        return 1
    }

    # Step 13: Set permissions
    set_permissions || {
        echo -e "${RED}Failed to set permissions${NC}" >&2
        return 1
    }

    echo ""
    echo -e "${GREEN}✓ Installation orchestration completed successfully${NC}"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: create_directory_structure
# =============================================================================
# Description: Create /opt/vless directory structure with proper permissions
# Returns: 0 on success, 1 on failure
# =============================================================================
create_directory_structure() {
    echo -e "${CYAN}[1/12] Creating directory structure...${NC}"

    # Create main installation directory
    if [[ ! -d "${INSTALL_ROOT}" ]]; then
        mkdir -p "${INSTALL_ROOT}" || {
            echo -e "${RED}Failed to create ${INSTALL_ROOT}${NC}" >&2
            return 1
        }
        echo "  ✓ Created ${INSTALL_ROOT}"
    else
        echo "  ✓ ${INSTALL_ROOT} already exists"
    fi

    # Create subdirectories
    local directories=(
        "${CONFIG_DIR}"
        "${DATA_DIR}"
        "${DATA_DIR}/clients"
        "${DATA_DIR}/backups"
        "${INSTALL_ROOT}/backup"
        "${INSTALL_ROOT}/lib"
        "${LOGS_DIR}"
        "${KEYS_DIR}"
        "${SCRIPTS_DIR}"
        "${FAKESITE_DIR}"
        "${DOCS_DIR}"
        "${TESTS_DIR}"
        "${TESTS_DIR}/unit"
        "${TESTS_DIR}/integration"
    )

    for dir in "${directories[@]}"; do
        # Always ensure directory exists (mkdir -p is idempotent)
        mkdir -p "$dir" || {
            echo -e "${RED}Failed to create $dir${NC}" >&2
            return 1
        }
        if [[ -d "$dir" ]]; then
            echo "  ✓ $dir exists"
        fi
    done

    echo -e "${GREEN}✓ Directory structure created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: generate_reality_keys
# =============================================================================
# Description: Generate X25519 keypair for Reality protocol
# Sets: PRIVATE_KEY, PUBLIC_KEY
# Returns: 0 on success, 1 on failure
# =============================================================================
generate_reality_keys() {
    echo -e "${CYAN}[2/12] Generating X25519 Reality keys...${NC}"

    # Check if xray command is available (should be from Docker image)
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker command not found${NC}" >&2
        return 1
    fi

    # Generate keys using xray Docker image
    local key_output
    key_output=$(docker run --rm "${XRAY_IMAGE}" xray x25519 2>/dev/null)

    if [[ -z "$key_output" ]]; then
        echo -e "${RED}Failed to generate X25519 keys${NC}" >&2
        return 1
    fi

    # Parse private and public keys
    PRIVATE_KEY=$(echo "$key_output" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$key_output" | grep "Public key:" | awk '{print $3}')

    if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
        echo -e "${RED}Failed to parse keys from xray output${NC}" >&2
        echo "Output was: $key_output" >&2
        return 1
    fi

    # Save keys to files
    echo "$PRIVATE_KEY" > "${KEYS_DIR}/private.key" || return 1
    echo "$PUBLIC_KEY" > "${KEYS_DIR}/public.key" || return 1

    echo "  ✓ Private key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -10}"
    echo "  ✓ Public key: ${PUBLIC_KEY:0:10}...${PUBLIC_KEY: -10}"
    echo "  ✓ Keys saved to ${KEYS_DIR}/"

    echo -e "${GREEN}✓ Reality keys generated${NC}"
    return 0
}

# =============================================================================
# FUNCTION: generate_short_id
# =============================================================================
# Description: Generate Short ID for Reality protocol
# Sets: SHORT_ID
# Returns: 0 on success, 1 on failure
# =============================================================================
generate_short_id() {
    echo -e "${CYAN}[3/12] Generating Short ID...${NC}"

    # Generate 8-byte (16 hex characters) short ID
    SHORT_ID=$(openssl rand -hex 8)

    if [[ -z "$SHORT_ID" ]]; then
        echo -e "${RED}Failed to generate Short ID${NC}" >&2
        return 1
    fi

    echo "  ✓ Short ID: ${SHORT_ID}"

    echo -e "${GREEN}✓ Short ID generated${NC}"
    return 0
}

# =============================================================================
# FUNCTION: generate_socks5_inbound_json
# =============================================================================
# Description: Generate SOCKS5 proxy inbound configuration for Xray
# Returns: JSON string for SOCKS5 inbound (to be appended to inbounds array)
# Related: TASK-11.1 (SOCKS5 Proxy Inbound Configuration)
# =============================================================================
generate_socks5_inbound_json() {
    cat <<'EOF'
  ,{
    "tag": "socks5-proxy",
    "listen": "0.0.0.0",
    "port": 1080,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [],
      "udp": false,
      "ip": "0.0.0.0"
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }
EOF
}

# =============================================================================
# FUNCTION: generate_http_inbound_json
# =============================================================================
# Description: Generate HTTP proxy inbound configuration for Xray
# Returns: JSON string for HTTP inbound (to be appended to inbounds array)
# Related: TASK-11.2 (HTTP Proxy Inbound Configuration)
# =============================================================================
generate_http_inbound_json() {
    cat <<'EOF'
  ,{
    "tag": "http-proxy",
    "listen": "0.0.0.0",
    "port": 8118,
    "protocol": "http",
    "settings": {
      "accounts": [],
      "allowTransparent": false,
      "userLevel": 0
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }
EOF
}

# =============================================================================
# FUNCTION: create_xray_config
# =============================================================================
# Description: Create Xray configuration file (xray_config.json)
# Uses: PRIVATE_KEY, SHORT_ID, REALITY_DEST, REALITY_DEST_PORT, VLESS_PORT
# Arguments:
#   $1 - enable_proxy (optional): "true" to enable SOCKS5/HTTP proxy support
#                                 "false" (default) for VLESS only
# Returns: 0 on success, 1 on failure
# Updated: TASK-11.1 - Added proxy support parameter
# =============================================================================
create_xray_config() {
    local enable_proxy="${1:-false}"
    echo -e "${CYAN}[4/12] Creating Xray configuration...${NC}"

    # Validate required variables
    if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$SHORT_ID" ]] || \
       [[ -z "$REALITY_DEST" ]] || [[ -z "$REALITY_DEST_PORT" ]] || \
       [[ -z "$VLESS_PORT" ]]; then
        echo -e "${RED}Missing required configuration parameters${NC}" >&2
        return 1
    fi

    # Create Xray configuration
    cat > "${XRAY_CONFIG}" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "port": ${VLESS_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [],
      "decryption": "none",
      "fallbacks": [
        {
          "dest": "vless_nginx:80"
        }
      ]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${REALITY_DEST}:${REALITY_DEST_PORT}",
        "xver": 0,
        "serverNames": ["${REALITY_DEST}"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}", ""]
      }
    }
  }$(if [[ "$enable_proxy" == "true" ]]; then
    generate_socks5_inbound_json
    generate_http_inbound_json
fi)],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }]
}
EOF

    if [[ ! -f "${XRAY_CONFIG}" ]]; then
        echo -e "${RED}Failed to create ${XRAY_CONFIG}${NC}" >&2
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "${XRAY_CONFIG}" 2>/dev/null; then
        echo -e "${RED}Invalid JSON in ${XRAY_CONFIG}${NC}" >&2
        return 1
    fi

    echo "  ✓ Configuration file: ${XRAY_CONFIG}"
    echo "  ✓ Listen port: ${VLESS_PORT}"
    echo "  ✓ Destination: ${REALITY_DEST}:${REALITY_DEST_PORT}"
    echo "  ✓ Fallback to Nginx configured"

    if [[ "$enable_proxy" == "true" ]]; then
        local server_ip
        server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
        echo "  ✓ SOCKS5 Proxy enabled (0.0.0.0:1080) - PUBLIC ACCESS"
        echo "  ✓ HTTP Proxy enabled (0.0.0.0:8118) - PUBLIC ACCESS"
        echo "  ⚠️  External URI: socks5://user:pass@${server_ip}:1080"
        echo "  ⚠️  WARNING: Proxy accessible from internet"
    fi

    echo -e "${GREEN}✓ Xray configuration created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: configure_proxy_firewall_rules
# =============================================================================
# Description: Open UFW ports for public proxy access with rate limiting
# Arguments:
#   None (uses global ENABLE_PUBLIC_PROXY variable)
# Returns: 0 on success, 1 on failure
# Related: v3.2 Public Proxy Support - TASK-2.2
# =============================================================================
configure_proxy_firewall_rules() {
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" != "true" ]]; then
        echo "  ℹ️  Public proxy disabled, skipping firewall rules"
        return 0
    fi

    echo -e "${CYAN}Configuring firewall for public proxy...${NC}"

    # Ensure UFW is active
    if ! ufw status | grep -q "Status: active"; then
        echo -e "${RED}UFW is not active${NC}" >&2
        return 1
    fi

    # Check if SOCKS5 port rule already exists
    if ! ufw status numbered | grep -q "1080/tcp"; then
        echo "  Adding SOCKS5 port (1080/tcp) with rate limiting..."
        if ! ufw limit 1080/tcp comment 'VLESS SOCKS5 Proxy (rate-limited)'; then
            echo -e "${RED}Failed to add SOCKS5 firewall rule${NC}" >&2
            return 1
        fi
        echo -e "${GREEN}  ✓ SOCKS5 port opened with rate limiting${NC}"
    else
        echo "  ✓ SOCKS5 port already open"
    fi

    # Check if HTTP port rule already exists
    if ! ufw status numbered | grep -q "8118/tcp"; then
        echo "  Adding HTTP port (8118/tcp) with rate limiting..."
        if ! ufw limit 8118/tcp comment 'VLESS HTTP Proxy (rate-limited)'; then
            echo -e "${RED}Failed to add HTTP firewall rule${NC}" >&2
            return 1
        fi
        echo -e "${GREEN}  ✓ HTTP port opened with rate limiting${NC}"
    else
        echo "  ✓ HTTP port already open"
    fi

    # Reload UFW to apply rules
    echo "  Reloading UFW..."
    if ! ufw reload &>/dev/null; then
        echo -e "${YELLOW}Warning: Failed to reload UFW${NC}"
    fi

    echo -e "${GREEN}✓ Firewall configured for public proxy${NC}"
    echo ""
    echo "Active proxy ports:"
    ufw status numbered | grep -E "(1080|8118)/tcp" || true
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: create_users_json
# =============================================================================
# Description: Create empty users.json file
# Returns: 0 on success, 1 on failure
# =============================================================================
create_users_json() {
    echo -e "${CYAN}[5/12] Creating users database...${NC}"

    # Create empty users JSON structure
    cat > "${USERS_JSON}" <<'EOF'
{
  "users": [],
  "metadata": {
    "created": "",
    "last_modified": ""
  }
}
EOF

    # Set timestamps
    local timestamp
    timestamp=$(date -Iseconds)

    # Use temporary file for atomic update
    local temp_file
    temp_file=$(mktemp)

    jq ".metadata.created = \"${timestamp}\" | .metadata.last_modified = \"${timestamp}\"" \
       "${USERS_JSON}" > "$temp_file" && mv "$temp_file" "${USERS_JSON}"

    if [[ ! -f "${USERS_JSON}" ]]; then
        echo -e "${RED}Failed to create ${USERS_JSON}${NC}" >&2
        return 1
    fi

    echo "  ✓ Users database: ${USERS_JSON}"
    echo "  ✓ Initial state: empty (0 users)"

    echo -e "${GREEN}✓ Users database created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_nginx_config
# =============================================================================
# Description: Create Nginx reverse proxy configuration
# Uses: REALITY_DEST, REALITY_DEST_PORT
# Returns: 0 on success, 1 on failure
# =============================================================================
create_nginx_config() {
    echo -e "${CYAN}[6/12] Creating Nginx configuration...${NC}"

    # Validate required variables
    if [[ -z "$REALITY_DEST" ]] || [[ -z "$REALITY_DEST_PORT" ]]; then
        echo -e "${RED}Missing destination configuration${NC}" >&2
        return 1
    fi

    # Create Nginx configuration for fake-site
    cat > "${NGINX_CONFIG}" <<EOF
# Nginx Reverse Proxy Configuration for VLESS Reality Fake-site
# This configuration proxies to ${REALITY_DEST}:${REALITY_DEST_PORT}
# to make the server appear as a normal HTTPS website

server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Proxy settings
    location / {
        proxy_pass https://${REALITY_DEST}:${REALITY_DEST_PORT};
        proxy_ssl_server_name on;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;

        # Headers
        proxy_set_header Host ${REALITY_DEST};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;

        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;

        # Caching (1 hour for successful responses)
        proxy_cache_valid 200 1h;
        proxy_cache_valid 301 302 10m;
        proxy_cache_valid 404 1m;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
EOF

    if [[ ! -f "${NGINX_CONFIG}" ]]; then
        echo -e "${RED}Failed to create ${NGINX_CONFIG}${NC}" >&2
        return 1
    fi

    echo "  ✓ Nginx configuration: ${NGINX_CONFIG}"
    echo "  ✓ Proxying to: https://${REALITY_DEST}:${REALITY_DEST_PORT}"
    echo "  ✓ Cache: 1h for 200 OK responses"

    echo -e "${GREEN}✓ Nginx configuration created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_docker_compose
# =============================================================================
# Description: Create docker-compose.yml for container orchestration
# Uses: XRAY_IMAGE, NGINX_IMAGE, VLESS_PORT, DOCKER_NETWORK_NAME
# Returns: 0 on success, 1 on failure
# =============================================================================
create_docker_compose() {
    echo -e "${CYAN}[7/12] Creating Docker Compose configuration...${NC}"

    # Create docker-compose.yml
    cat > "${DOCKER_COMPOSE_FILE}" <<EOF
version: '3.8'

services:
  xray:
    image: ${XRAY_IMAGE}
    container_name: ${XRAY_CONTAINER_NAME}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "nc -z 127.0.0.1 1080 && nc -z 127.0.0.1 8118 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    networks:
      - ${DOCKER_NETWORK_NAME}
    ports:
      - "${VLESS_PORT}:${VLESS_PORT}"
    volumes:
      - ${CONFIG_DIR}:/etc/xray:ro
      - ${LOGS_DIR}:/var/log/xray
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    command: xray run -c /etc/xray/xray_config.json

  nginx:
    image: ${NGINX_IMAGE}
    container_name: ${NGINX_CONTAINER_NAME}
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK_NAME}
    volumes:
      - ${FAKESITE_DIR}/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ${LOGS_DIR}/nginx:/var/log/nginx
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETGID
      - SETUID
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
      - /var/cache/nginx
      - /var/run
    depends_on:
      - xray

networks:
  ${DOCKER_NETWORK_NAME}:
    external: true
EOF

    if [[ ! -f "${DOCKER_COMPOSE_FILE}" ]]; then
        echo -e "${RED}Failed to create ${DOCKER_COMPOSE_FILE}${NC}" >&2
        return 1
    fi

    echo "  ✓ Docker Compose file: ${DOCKER_COMPOSE_FILE}"
    echo "  ✓ Xray image: ${XRAY_IMAGE}"
    echo "  ✓ Nginx image: ${NGINX_IMAGE}"
    echo "  ✓ Network: ${DOCKER_NETWORK_NAME}"
    echo "  ✓ Security: hardened containers with minimal capabilities"

    echo -e "${GREEN}✓ Docker Compose configuration created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_env_file
# =============================================================================
# Description: Create .env file with environment variables
# Uses: REALITY_DEST, REALITY_DEST_PORT, VLESS_PORT, DOCKER_SUBNET, PUBLIC_KEY
# Returns: 0 on success, 1 on failure
# =============================================================================
create_env_file() {
    echo -e "${CYAN}[8/12] Creating environment file...${NC}"

    # Detect external server IP
    local server_ip
    server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP_NOT_DETECTED")

    cat > "${ENV_FILE}" <<EOF
# VLESS Reality VPN Environment Variables
# Generated: $(date -Iseconds)
# DO NOT commit this file to version control

# Reality Protocol Configuration
REALITY_DEST=${REALITY_DEST}
REALITY_DEST_PORT=${REALITY_DEST_PORT}
VLESS_PORT=${VLESS_PORT}
DOCKER_SUBNET=${DOCKER_SUBNET}

# Server Information (v3.2 - for public proxy configs)
SERVER_IP=${server_ip}

# Keys (for reference only, actual keys in ${KEYS_DIR}/)
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}

# Docker Configuration
DOCKER_NETWORK=${DOCKER_NETWORK_NAME}
XRAY_IMAGE=${XRAY_IMAGE}
NGINX_IMAGE=${NGINX_IMAGE}

# Paths
INSTALL_ROOT=${INSTALL_ROOT}
CONFIG_DIR=${CONFIG_DIR}
DATA_DIR=${DATA_DIR}
EOF

    if [[ ! -f "${ENV_FILE}" ]]; then
        echo -e "${RED}Failed to create ${ENV_FILE}${NC}" >&2
        return 1
    fi

    echo "  ✓ Environment file: ${ENV_FILE}"

    echo -e "${GREEN}✓ Environment file created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_docker_network
# =============================================================================
# Description: Create Docker bridge network with specified subnet
# Uses: DOCKER_SUBNET, DOCKER_NETWORK_NAME
# Returns: 0 on success, 1 on failure
# =============================================================================
create_docker_network() {
    echo -e "${CYAN}[9/12] Creating Docker network...${NC}"

    # Check if network already exists
    if docker network inspect "${DOCKER_NETWORK_NAME}" &>/dev/null; then
        echo "  ✓ Network ${DOCKER_NETWORK_NAME} already exists"
        return 0
    fi

    # Create Docker bridge network
    docker network create \
        --driver bridge \
        --subnet "${DOCKER_SUBNET}" \
        "${DOCKER_NETWORK_NAME}" || {
        echo -e "${RED}Failed to create Docker network${NC}" >&2
        return 1
    }

    echo "  ✓ Network name: ${DOCKER_NETWORK_NAME}"
    echo "  ✓ Subnet: ${DOCKER_SUBNET}"
    echo "  ✓ Driver: bridge"

    echo -e "${GREEN}✓ Docker network created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: configure_ufw
# =============================================================================
# Description: Configure UFW firewall with Docker forwarding support
# Uses: VLESS_PORT, DOCKER_SUBNET
# Returns: 0 on success, 1 on failure
# =============================================================================
configure_ufw() {
    echo -e "${CYAN}[10/12] Configuring UFW firewall...${NC}"

    # Check if UFW is installed
    if ! command -v ufw &>/dev/null; then
        echo "  ⚠ UFW not installed, skipping firewall configuration"
        return 0
    fi

    # Backup UFW configuration
    echo "  Creating UFW backup..."
    mkdir -p "${UFW_BACKUP_DIR}"
    if [[ -f "${UFW_AFTER_RULES}" ]]; then
        cp "${UFW_AFTER_RULES}" "${UFW_BACKUP_DIR}/after.rules.backup"
        echo "  ✓ Backup saved to ${UFW_BACKUP_DIR}"
    fi

    # Add Docker forwarding rules to UFW (if not already present)
    if ! grep -q "VLESS REALITY" "${UFW_AFTER_RULES}" 2>/dev/null; then
        echo "  Adding Docker forwarding rules..."

        cat >> "${UFW_AFTER_RULES}" <<EOF

# BEGIN VLESS REALITY DOCKER FORWARDING RULES
# Added: $(date -Iseconds)
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${DOCKER_SUBNET} -j MASQUERADE
COMMIT
# END VLESS REALITY DOCKER FORWARDING RULES
EOF
        echo "  ✓ Docker forwarding rules added"
    else
        echo "  ✓ Docker forwarding rules already present"
    fi

    # Allow VLESS port (check if rule already exists first)
    echo "  Allowing port ${VLESS_PORT}..."
    if ufw status numbered | grep -q "${VLESS_PORT}/tcp.*ALLOW"; then
        echo "  ✓ Port ${VLESS_PORT}/tcp already allowed"
    else
        ufw allow "${VLESS_PORT}/tcp" comment 'VLESS Reality VPN' || {
            echo -e "${YELLOW}Warning: Failed to add UFW rule${NC}"
        }
        echo "  ✓ Port ${VLESS_PORT}/tcp allowed"
    fi

    # Reload UFW to apply changes
    echo "  Reloading UFW..."
    ufw reload || {
        echo -e "${YELLOW}Warning: Failed to reload UFW${NC}"
    }
    echo "  ✓ Docker forwarding configured for ${DOCKER_SUBNET}"

    echo -e "${GREEN}✓ UFW firewall configured${NC}"
    return 0
}

# =============================================================================
# FUNCTION: deploy_containers
# =============================================================================
# Description: Deploy Docker containers using docker-compose
# Returns: 0 on success, 1 on failure
# =============================================================================
deploy_containers() {
    echo -e "${CYAN}[11/12] Deploying Docker containers...${NC}"

    # Change to installation directory
    cd "${INSTALL_ROOT}" || {
        echo -e "${RED}Failed to change to ${INSTALL_ROOT}${NC}" >&2
        return 1
    }

    # Pull images
    echo "  Pulling Docker images..."
    docker compose pull || {
        echo -e "${RED}Failed to pull Docker images${NC}" >&2
        return 1
    }
    echo "  ✓ Images pulled"

    # Start containers
    echo "  Starting containers..."
    docker compose up -d || {
        echo -e "${RED}Failed to start containers${NC}" >&2
        return 1
    }

    # Wait for containers to be healthy
    echo "  Waiting for containers to start..."
    sleep 5

    # Check container status
    if docker ps | grep -q "${XRAY_CONTAINER_NAME}"; then
        echo "  ✓ Xray container running"
    else
        echo -e "${RED}Xray container failed to start${NC}" >&2
        docker compose logs xray
        return 1
    fi

    if docker ps | grep -q "${NGINX_CONTAINER_NAME}"; then
        echo "  ✓ Nginx container running"
    else
        echo -e "${RED}Nginx container failed to start${NC}" >&2
        docker compose logs nginx
        return 1
    fi

    echo -e "${GREEN}✓ Containers deployed successfully${NC}"
    return 0
}

# =============================================================================
# FUNCTION: install_cli_tools
# =============================================================================
# Description: Install CLI management tools and create symlinks
# Returns: 0 on success, 1 on failure
# =============================================================================
install_cli_tools() {
    echo -e "${CYAN}[12/13] Installing CLI tools...${NC}"

    # Get the project root (assuming script is in lib/ subdirectory)
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local cli_source="${project_root}/cli/vless"

    # Check if CLI script exists in project
    if [[ ! -f "$cli_source" ]]; then
        echo -e "${YELLOW}  ⚠ CLI script not found in project: $cli_source${NC}"
        echo "  ℹ CLI tool installation skipped"
        return 0
    fi

    # Copy CLI script to installation directory
    cp "$cli_source" "${SCRIPTS_DIR}/vless" || {
        echo -e "${RED}Failed to copy CLI script${NC}" >&2
        return 1
    }

    # Make it executable
    chmod 755 "${SCRIPTS_DIR}/vless" || {
        echo -e "${RED}Failed to set execute permission${NC}" >&2
        return 1
    }

    # Create symlink in /usr/local/bin
    ln -sf "${SCRIPTS_DIR}/vless" /usr/local/bin/vless || {
        echo -e "${RED}Failed to create symlink${NC}" >&2
        return 1
    }

    # Copy lib modules to installation
    local lib_modules=(
        "user_management.sh"
        "qr_generator.sh"
    )

    for module in "${lib_modules[@]}"; do
        if [[ -f "${project_root}/lib/${module}" ]]; then
            cp "${project_root}/lib/${module}" "${INSTALL_ROOT}/lib/" || {
                echo -e "${YELLOW}  ⚠ Warning: Failed to copy ${module}${NC}"
            }
        fi
    done

    echo "  ✓ CLI script installed: ${SCRIPTS_DIR}/vless"
    echo "  ✓ Symlink created: /usr/local/bin/vless"
    echo "  ✓ Command available: vless"

    echo -e "${GREEN}✓ CLI tools installed${NC}"
    return 0
}

# =============================================================================
# FUNCTION: set_permissions
# =============================================================================
# Description: Set appropriate file and directory permissions
# Returns: 0 on success, 1 on failure
# =============================================================================
set_permissions() {
    echo -e "${CYAN}[13/13] Setting file permissions...${NC}"

    # Sensitive directories: 700 (root only)
    # Set permissions on each directory individually to ensure all exist
    for sensitive_dir in "${CONFIG_DIR}" "${DATA_DIR}" "${DATA_DIR}/clients" "${DATA_DIR}/backups" "${KEYS_DIR}" "${INSTALL_ROOT}/backup"; do
        if [[ -d "$sensitive_dir" ]]; then
            chmod 700 "$sensitive_dir" 2>/dev/null || true
        fi
    done

    # Sensitive files: 600 (root read/write only)
    find "${CONFIG_DIR}" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "${KEYS_DIR}" -type f -exec chmod 600 {} \; 2>/dev/null || true
    chmod 600 "${ENV_FILE}" 2>/dev/null || true

    # Readable directories: 755
    chmod 755 "${LOGS_DIR}" "${SCRIPTS_DIR}" "${FAKESITE_DIR}" \
              "${DOCS_DIR}" "${TESTS_DIR}" 2>/dev/null || true

    # Readable files: 644
    find "${LOGS_DIR}" -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 644 "${DOCKER_COMPOSE_FILE}" 2>/dev/null || true
    chmod 644 "${NGINX_CONFIG}" 2>/dev/null || true

    # Executable scripts: 755
    find "${SCRIPTS_DIR}" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    echo "  ✓ Sensitive files: 600 (root only)"
    echo "  ✓ Config/keys directories: 700 (root only)"
    echo "  ✓ Logs/scripts: 755/644 (readable)"

    echo -e "${GREEN}✓ Permissions set${NC}"
    return 0
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Export main function for use by install.sh
export -f orchestrate_installation

# Export helper functions (for testing and debugging)
export -f create_directory_structure
export -f generate_reality_keys
export -f generate_short_id
export -f generate_socks5_inbound_json
export -f generate_http_inbound_json
export -f create_xray_config
export -f configure_proxy_firewall_rules
export -f create_users_json
export -f create_nginx_config
export -f create_docker_compose
export -f create_env_file
export -f create_docker_network
export -f configure_ufw
export -f deploy_containers
export -f install_cli_tools
export -f set_permissions

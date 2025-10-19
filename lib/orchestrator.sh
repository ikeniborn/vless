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
# IMPORT v4.3 MODULES
# =============================================================================
# Source HAProxy and docker-compose generators (v4.3 unified architecture)
# These modules are required for HAProxy configuration and docker-compose generation
SCRIPT_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR_LIB}/haproxy_config_manager.sh" ]] && source "${SCRIPT_DIR_LIB}/haproxy_config_manager.sh"
[[ -f "${SCRIPT_DIR_LIB}/docker_compose_generator.sh" ]] && source "${SCRIPT_DIR_LIB}/docker_compose_generator.sh"

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
readonly NGINX_CONTAINER_NAME="vless_nginx_reverseproxy"  # v4.3: Full container name
readonly HAPROXY_CONTAINER_NAME="vless_haproxy"  # v4.3: HAProxy unified TLS termination

# Configuration files (conditional to avoid conflicts when sourced by CLI)
[[ -z "${XRAY_CONFIG:-}" ]] && readonly XRAY_CONFIG="${CONFIG_DIR}/xray_config.json"
[[ -z "${USERS_JSON:-}" ]] && readonly USERS_JSON="${DATA_DIR}/users.json"
readonly DOCKER_COMPOSE_FILE="${INSTALL_ROOT}/docker-compose.yml"
readonly NGINX_CONFIG="${FAKESITE_DIR}/default.conf"
[[ -z "${ENV_FILE:-}" ]] && readonly ENV_FILE="${INSTALL_ROOT}/.env"

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

    # Step 1.5: Set initial permissions (CRITICAL: before container deployment)
    # Set ownership for log directories so containers can write logs
    echo -e "${CYAN}[1.5/12] Setting initial permissions for log directories...${NC}"
    if [[ -d "${LOGS_DIR}/xray" ]]; then
        chown -R 65534:65534 "${LOGS_DIR}/xray" || {
            echo -e "${RED}Failed to set xray logs ownership${NC}" >&2
            return 1
        }
        chmod 755 "${LOGS_DIR}/xray"
    fi
    if [[ -d "${LOGS_DIR}/nginx" ]]; then
        chown -R 101:101 "${LOGS_DIR}/nginx" || {
            echo -e "${RED}Failed to set nginx logs ownership${NC}" >&2
            return 1
        }
        chmod 755 "${LOGS_DIR}/nginx"
    fi
    if [[ -d "${LOGS_DIR}/fake-site" ]]; then
        chown -R 101:101 "${LOGS_DIR}/fake-site" || {
            echo -e "${RED}Failed to set fake-site logs ownership${NC}" >&2
            return 1
        }
        chmod 755 "${LOGS_DIR}/fake-site"
    fi
    if [[ -d "${LOGS_DIR}/haproxy" ]]; then
        chown -R root:root "${LOGS_DIR}/haproxy" || {
            echo -e "${RED}Failed to set haproxy logs ownership${NC}" >&2
            return 1
        }
        chmod 755 "${LOGS_DIR}/haproxy"
    fi

    # Set permissions on Let's Encrypt live directory for HAProxy access
    # HAProxy (host network mode, non-root) needs rx to traverse path
    if [[ -d "/etc/letsencrypt/live" ]]; then
        chmod 755 /etc/letsencrypt/live || {
            echo -e "${YELLOW}Warning: Failed to set permissions on /etc/letsencrypt/live${NC}" >&2
            # Non-critical: Continue installation (certificates may not be configured yet)
        }
    fi

    echo "  ✓ Log directory permissions set"

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

    # Step 5.5: Initialize proxy_allowed_ips.json (v3.6 - server-level IP whitelist)
    init_proxy_allowed_ips || {
        echo -e "${RED}Failed to initialize proxy IP whitelist${NC}" >&2
        return 1
    }

    # Step 6: Create Nginx configuration
    create_nginx_config || {
        echo -e "${RED}Failed to create Nginx configuration${NC}" >&2
        return 1
    }

    # Step 6.3: Generate Nginx reverse proxy HTTP context (v4.3)
    # Source nginx_config_generator.sh if not already loaded
    if [[ -f "${SCRIPT_DIR_LIB}/nginx_config_generator.sh" ]]; then
        source "${SCRIPT_DIR_LIB}/nginx_config_generator.sh"
        if ! generate_reverseproxy_http_context; then
            echo -e "${YELLOW}Warning: Failed to generate nginx HTTP context${NC}"
            # Non-critical: Continue installation
        fi
    fi

    # Step 6.5: Generate HAProxy configuration (v4.3 unified TLS termination)
    generate_haproxy_config_wrapper || {
        echo -e "${RED}Failed to generate HAProxy configuration${NC}" >&2
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

    # Step 9.5: Setup fail2ban (v3.3 - for all proxy modes: localhost + public)
    if [[ "${ENABLE_PROXY:-false}" == "true" ]]; then
        echo ""
        echo -e "${CYAN}[9.5/12] Setting up fail2ban for proxy protection...${NC}"

        # Source fail2ban module
        if [[ -f "${SCRIPT_DIR}/lib/fail2ban_setup.sh" ]]; then
            source "${SCRIPT_DIR}/lib/fail2ban_setup.sh"
        fi

        if ! setup_fail2ban_for_proxy; then
            echo -e "${RED}Failed to setup fail2ban${NC}" >&2
            echo -e "${YELLOW}WARNING: Proxy will be less secure without fail2ban protection${NC}"
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
        "${CONFIG_DIR}/reverse-proxy"  # v4.3: Nginx reverse proxy configs
        "${DATA_DIR}"
        "${DATA_DIR}/clients"
        "${DATA_DIR}/backups"
        "${INSTALL_ROOT}/backup"
        "${INSTALL_ROOT}/lib"
        "${LOGS_DIR}"
        "${LOGS_DIR}/xray"
        "${LOGS_DIR}/haproxy"
        "${LOGS_DIR}/nginx"
        "${LOGS_DIR}/fake-site"
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
# FUNCTION: generate_routing_json
# =============================================================================
# Description: Generate routing rules for server-level IP whitelisting (v3.6)
# Returns: JSON string for routing section
# Logic:
#   - Read allowed IPs from proxy_allowed_ips.json (server-level)
#   - Allow connections from whitelisted IPs to proxy ports
#   - Block all other connections to proxy ports
# Related: v3.6 Server-Level IP Whitelisting
# Note: NO per-user IP filtering (user field doesn't work for HTTP/SOCKS5)
# =============================================================================
generate_routing_json() {
    local proxy_ips_file="/opt/vless/config/proxy_allowed_ips.json"
    local allowed_ips='["127.0.0.1"]'  # Default: localhost only
    local docker_subnet=""

    # v4.3: HAProxy runs in host network mode, no need for Docker subnet
    # All traffic from HAProxy to Xray uses 127.0.0.1 (localhost)

    # Check if proxy_allowed_ips.json exists (user-defined overrides)
    if [[ -f "$proxy_ips_file" ]]; then
        # Read allowed IPs from file
        local user_ips=$(jq -c '.allowed_ips' "$proxy_ips_file" 2>/dev/null)

        # Validate JSON and use if valid
        if [[ -n "$user_ips" ]] && [[ "$user_ips" != "null" ]] && echo "$user_ips" | jq empty 2>/dev/null; then
            allowed_ips="$user_ips"
        else
            # Fallback to defaults if file is corrupted (v4.3: localhost only)
            allowed_ips='["127.0.0.1"]'
        fi
    fi

    # Generate routing configuration with server-level IP whitelist
    # v4.3+ HAProxy Architecture: Blocking rule removed because:
    #   - Ports 10800/18118 NOT exposed publicly (HAProxy terminates TLS on 1080/8118)
    #   - Docker network provides isolation
    #   - HAProxy connects from Docker network IP (not whitelisted 127.0.0.1)
    #   - Blocking rule would break HAProxy → Xray proxy connections
    # Rule 1: Allow whitelisted IPs to access proxy ports (legacy, kept for future use)
    cat <<EOF
,
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks5-proxy", "http-proxy"],
        "source": ${allowed_ips},
        "outboundTag": "direct"
      }
    ]
  }
EOF
}

# =============================================================================
# FUNCTION: generate_socks5_inbound_json
# =============================================================================
# Description: Generate SOCKS5 proxy inbound configuration for Xray
# Returns: JSON string for SOCKS5 inbound (to be appended to inbounds array)
# Related: TASK-11.1 (SOCKS5 Proxy Inbound Configuration)
# Note: v4.3 - TLS handled by HAProxy, Xray uses plaintext localhost inbound
# =============================================================================
generate_socks5_inbound_json() {
    # v4.3: HAProxy unified TLS termination
    # Architecture: Client → HAProxy (TLS, 0.0.0.0:1080) → Xray (plaintext, 127.0.0.1:10800)
    #
    # IMPORTANT: Xray ALWAYS listens on localhost (127.0.0.1:10800)
    # - HAProxy handles TLS termination on public port 1080
    # - Xray handles authentication (username/password MANDATORY)
    # - No TLS streamSettings in Xray config (handled by HAProxy)

    cat <<'EOF'
  ,{
    "tag": "socks5-proxy",
    "listen": "0.0.0.0",
    "port": 10800,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [],
      "udp": false,
      "ip": "127.0.0.1"
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
# Note: v4.3 - TLS handled by HAProxy, Xray uses plaintext localhost inbound
# =============================================================================
generate_http_inbound_json() {
    # v4.3: HAProxy unified TLS termination
    # Architecture: Client → HAProxy (TLS, 0.0.0.0:8118) → Xray (plaintext, 127.0.0.1:18118)
    #
    # IMPORTANT: Xray ALWAYS listens on localhost (127.0.0.1:18118)
    # - HAProxy handles TLS termination on public port 8118
    # - Xray handles authentication (username/password MANDATORY)
    # - No TLS streamSettings in Xray config (handled by HAProxy)

    cat <<'EOF'
  ,{
    "tag": "http-proxy",
    "listen": "0.0.0.0",
    "port": 18118,
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
          "dest": "vless_fake_site:80"
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
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]$(if [[ "$enable_proxy" == "true" ]]; then
    generate_routing_json
fi)
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

    # Set permissions to 644 (readable by Xray container user: nobody)
    chmod 644 "${XRAY_CONFIG}"
    chown root:root "${XRAY_CONFIG}" 2>/dev/null || true

    echo "  ✓ Configuration file: ${XRAY_CONFIG}"
    echo "  ✓ Listen port: ${VLESS_PORT}"
    echo "  ✓ Destination: ${REALITY_DEST}:${REALITY_DEST_PORT}"
    echo "  ✓ Fallback to Nginx configured"

    if [[ "$enable_proxy" == "true" ]]; then
        if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
            # v3.3: TLS-encrypted public proxy
            local domain="${DOMAIN:-SERVER_DOMAIN}"
            echo "  ✓ SOCKS5 Proxy (0.0.0.0:1080) - TLS-ENCRYPTED PUBLIC ACCESS"
            echo "  ✓ HTTP Proxy (0.0.0.0:8118) - TLS-ENCRYPTED PUBLIC ACCESS"
            echo "  ✓ TLS Certificate: ${domain}"
            echo "  ⚠️  SOCKS5 URI: socks5s://user:pass@${domain}:1080"
            echo "  ⚠️  HTTP URI: https://user:pass@${domain}:8118"
            echo "  ⚠️  WARNING: Proxies require TLS-capable clients (v3.3)"
        else
            # v3.1: Localhost-only proxy (no TLS needed)
            echo "  ✓ SOCKS5 Proxy (127.0.0.1:1080) - LOCALHOST ONLY"
            echo "  ✓ HTTP Proxy (127.0.0.1:8118) - LOCALHOST ONLY"
            echo "  ℹ️  Access via VPN connection only"
        fi
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
# FUNCTION: init_proxy_allowed_ips
# =============================================================================
# Description: Initialize proxy_allowed_ips.json with default localhost-only access
# Returns: 0 on success, 1 on failure
# Related: v3.6 Server-Level IP Whitelisting
# =============================================================================
init_proxy_allowed_ips() {
    echo -e "${CYAN}[5.5/13] Initializing proxy IP whitelist...${NC}"

    local proxy_ips_file="${CONFIG_DIR}/proxy_allowed_ips.json"
    local default_ips='["127.0.0.1"]'

    # v4.3: HAProxy runs in host network mode, only localhost needed
    # All traffic from HAProxy to Xray uses 127.0.0.1

    # Create proxy_allowed_ips.json with appropriate defaults
    cat > "$proxy_ips_file" <<EOF
{
  "allowed_ips": ${default_ips},
  "metadata": {
    "created": "",
    "last_modified": "",
    "description": "Server-level IP whitelist for proxy access (v3.6+v4.0)"
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
       "$proxy_ips_file" > "$temp_file" && mv "$temp_file" "$proxy_ips_file"

    if [[ ! -f "$proxy_ips_file" ]]; then
        echo -e "${RED}Failed to create ${proxy_ips_file}${NC}" >&2
        return 1
    fi

    # Set permissions (600 - root only)
    chmod 600 "$proxy_ips_file" || {
        echo -e "${RED}Failed to set permissions on ${proxy_ips_file}${NC}" >&2
        return 1
    }

    echo "  ✓ Proxy IP whitelist: $proxy_ips_file"
    echo "  ✓ Default: localhost only (127.0.0.1)"
    echo "  ✓ Manage with: vless {show|set|add|remove|reset}-proxy-ips"

    echo -e "${GREEN}✓ Proxy IP whitelist initialized${NC}"
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
# FUNCTION: generate_haproxy_config_wrapper
# =============================================================================
# Description: Wrapper for lib/haproxy_config_manager.sh::generate_haproxy_config()
# Uses: DOMAIN (from interactive_params.sh)
# Returns: 0 on success, 1 on failure
# =============================================================================
generate_haproxy_config_wrapper() {
    echo -e "${CYAN}[6.5/12] Generating HAProxy configuration (v4.3 unified TLS)...${NC}"

    # Extract main domain from DOMAIN (remove subdomain if present)
    local main_domain="${DOMAIN}"
    local vless_domain="${DOMAIN}"

    # Generate random stats password
    local stats_password
    stats_password=$(openssl rand -hex 8)

    # Call the imported function from haproxy_config_manager.sh
    if ! generate_haproxy_config "${vless_domain}" "${main_domain}" "${stats_password}"; then
        echo -e "${RED}Failed to generate HAProxy configuration${NC}" >&2
        return 1
    fi

    echo "  ✓ HAProxy config: ${CONFIG_DIR}/haproxy.cfg"
    echo "  ✓ Frontend ports: 443 (SNI), 1080 (SOCKS5), 8118 (HTTP)"
    echo "  ✓ TLS certificates: /etc/letsencrypt (mounted)"
    echo "  ✓ Stats URL: http://127.0.0.1:9000/stats"
    echo "  ✓ Stats password: ${stats_password}"

    echo -e "${GREEN}✓ HAProxy configuration created${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_docker_compose
# =============================================================================
# Description: Wrapper for lib/docker_compose_generator.sh::generate_docker_compose()
# Uses: XRAY_IMAGE, NGINX_IMAGE, VLESS_PORT, DOCKER_NETWORK_NAME (via env)
# Returns: 0 on success, 1 on failure
# =============================================================================
create_docker_compose() {
    echo -e "${CYAN}[7/12] Creating Docker Compose configuration (v4.3 unified HAProxy)...${NC}"

    # Set required environment variables for the external generator
    # Note: VLESS_DIR already set in docker_compose_generator.sh (sourced at top)
    export DOCKER_SUBNET="${DOCKER_SUBNET}"
    export VLESS_PORT="${VLESS_PORT}"

    # Call external generator with empty nginx_ports array (managed dynamically)
    # nginx_ports will be added later by lib/docker_compose_manager.sh when reverse proxies are configured
    if ! generate_docker_compose; then
        echo -e "${RED}Failed to generate docker-compose.yml${NC}" >&2
        return 1
    fi

    # Verify file was created
    if [[ ! -f "${DOCKER_COMPOSE_FILE}" ]]; then
        echo -e "${RED}Docker compose file not found after generation${NC}" >&2
        return 1
    fi

    echo "  ✓ Docker Compose file: ${DOCKER_COMPOSE_FILE}"
    echo "  ✓ HAProxy image: haproxy:2.8-alpine (NEW in v4.3)"
    echo "  ✓ Xray image: ${XRAY_IMAGE}"
    echo "  ✓ Nginx image: ${NGINX_IMAGE}"
    echo "  ✓ Network: ${DOCKER_NETWORK_NAME}"
    echo "  ✓ Security: hardened containers with minimal capabilities"

    # v4.3: HAProxy unified architecture
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        echo "  ✓ Mode: PUBLIC PROXY with HAProxy unified TLS (v4.3)"
        echo "  ✓ HAProxy: Handles ALL ports (443, 1080, 8118) with TLS/passthrough"
        echo "  ✓ Xray: Localhost ports 8443 (VLESS), 10800 (SOCKS5), 18118 (HTTP)"
        echo "  ✓ TLS certificates: /etc/letsencrypt mounted to HAProxy"
        echo "  ✓ Architecture: Client → HAProxy (TLS) → Xray (auth) → Internet"
    else
        echo "  ✓ Mode: VLESS-only with HAProxy passthrough (v4.3)"
        echo "  ✓ Exposed ports: 443 (VLESS Reality via HAProxy)"
        echo "  ✓ Xray: Localhost 8443 (HAProxy forwards from port 443)"
    fi

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

# Proxy Configuration (v3.4)
ENABLE_PROXY=${ENABLE_PROXY:-false}
ENABLE_PUBLIC_PROXY=${ENABLE_PUBLIC_PROXY:-false}
ENABLE_PROXY_TLS=${ENABLE_PROXY_TLS:-false}

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

# TLS Certificate Configuration (v3.3 - for public proxy mode)
DOMAIN=${DOMAIN:-}
EMAIL=${EMAIL:-}
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

    # v4.3: Remove old reverse proxy port rules (8443-8452) if they exist
    echo "  Removing old reverse proxy port rules (v4.2: 8443-8452)..."
    local removed_count=0
    for old_port in {8443..8452}; do
        if ufw status numbered | grep -q "${old_port}/tcp"; then
            # Find rule number and delete
            local rule_nums=$(ufw status numbered | grep "${old_port}/tcp" | grep -oP '^\[\s*\K\d+' || true)
            if [[ -n "$rule_nums" ]]; then
                for rule_num in $rule_nums; do
                    echo "y" | ufw delete "$rule_num" &>/dev/null || true
                    ((removed_count++))
                done
            fi
        fi
    done
    if [[ $removed_count -gt 0 ]]; then
        echo "  ✓ Removed $removed_count old reverse proxy port rules"
    else
        echo "  ✓ No old reverse proxy port rules found"
    fi

    # v5.1: Allow HAProxy external port 443 (NOT VLESS_PORT which is internal 8443)
    # HAProxy listens on 443 externally, forwards to Xray on 8443 internally
    local haproxy_external_port=443
    echo "  Allowing port ${haproxy_external_port} (HAProxy external frontend)..."
    if ufw status numbered | grep -q "${haproxy_external_port}/tcp.*ALLOW"; then
        echo "  ✓ Port ${haproxy_external_port}/tcp already allowed"
    else
        ufw allow "${haproxy_external_port}/tcp" comment 'HAProxy VLESS+Reverse Proxy (v4.3)' || {
            echo -e "${YELLOW}Warning: Failed to add UFW rule${NC}"
        }
        echo "  ✓ Port ${haproxy_external_port}/tcp allowed"
    fi

    # v4.3: Ensure ports 9443-9452 are NOT exposed (localhost-only nginx backends)
    echo "  Verifying nginx backend ports (9443-9452) are NOT exposed..."
    local exposed_nginx_ports=()
    for nginx_port in {9443..9452}; do
        if ufw status numbered | grep -q "${nginx_port}/tcp"; then
            exposed_nginx_ports+=("$nginx_port")
        fi
    done
    if [[ ${#exposed_nginx_ports[@]} -gt 0 ]]; then
        echo -e "${YELLOW}  ⚠️  WARNING: Nginx backend ports exposed: ${exposed_nginx_ports[*]}${NC}"
        echo "  These ports should be localhost-only (127.0.0.1) in v4.3"
        echo "  Removing rules..."
        for port in "${exposed_nginx_ports[@]}"; do
            local rule_nums=$(ufw status numbered | grep "${port}/tcp" | grep -oP '^\[\s*\K\d+' || true)
            if [[ -n "$rule_nums" ]]; then
                for rule_num in $rule_nums; do
                    echo "y" | ufw delete "$rule_num" &>/dev/null || true
                done
            fi
        done
        echo "  ✓ Nginx backend ports secured (localhost-only)"
    else
        echo "  ✓ Nginx backend ports are localhost-only (correct)"
    fi

    # Reload UFW to apply changes
    echo "  Reloading UFW..."
    ufw reload || {
        echo -e "${YELLOW}Warning: Failed to reload UFW${NC}"
    }
    echo "  ✓ Docker forwarding configured for ${DOCKER_SUBNET}"

    echo -e "${GREEN}✓ UFW firewall configured (v4.3)${NC}"
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

    # Pre-flight checks: Verify critical files exist before starting containers
    echo "  Running pre-flight checks..."
    local missing_files=()

    # Check required configuration files
    [[ ! -f "${XRAY_CONFIG}" ]] && missing_files+=("${XRAY_CONFIG}")
    [[ ! -f "${NGINX_CONFIG}" ]] && missing_files+=("${NGINX_CONFIG}")
    [[ ! -f "${DOCKER_COMPOSE_FILE}" ]] && missing_files+=("${DOCKER_COMPOSE_FILE}")
    [[ ! -f "${ENV_FILE}" ]] && missing_files+=("${ENV_FILE}")
    [[ ! -f "${KEYS_DIR}/private.key" ]] && missing_files+=("${KEYS_DIR}/private.key")
    [[ ! -f "${KEYS_DIR}/public.key" ]] && missing_files+=("${KEYS_DIR}/public.key")

    # v4.3: HAProxy config checked via docker-compose generator (lib/haproxy_config_manager.sh)

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${RED}✗ Pre-flight check failed: Missing critical files (${#missing_files[@]})${NC}" >&2
        for file in "${missing_files[@]}"; do
            echo "    - $file"
        done
        echo -e "${RED}Cannot start containers without these files${NC}" >&2
        return 1
    fi
    echo "  ✓ All critical files present"

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

    # Check container status using docker inspect (more reliable than grep)
    local xray_status=$(docker inspect "${XRAY_CONTAINER_NAME}" -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
    if [[ "$xray_status" == "running" ]]; then
        echo "  ✓ Xray container running"

        # Check healthcheck status (if available)
        local xray_health=$(docker inspect "${XRAY_CONTAINER_NAME}" -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
        if [[ "$xray_health" == "healthy" ]]; then
            echo "  ✓ Xray container healthy"
        elif [[ "$xray_health" == "starting" ]]; then
            echo "  ℹ Xray container health: starting (will be checked later)"
        elif [[ "$xray_health" != "no-healthcheck" ]]; then
            echo -e "${YELLOW}  ⚠ Xray container health: $xray_health${NC}"
        fi
    else
        echo -e "${RED}Xray container failed to start (status: $xray_status)${NC}" >&2
        docker compose logs xray
        return 1
    fi

    local nginx_status=$(docker inspect "${NGINX_CONTAINER_NAME}" -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
    if [[ "$nginx_status" == "running" ]]; then
        echo "  ✓ Nginx container running"

        # Check healthcheck status (added in v4.1.1)
        local nginx_health=$(docker inspect "${NGINX_CONTAINER_NAME}" -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
        if [[ "$nginx_health" == "healthy" ]]; then
            echo "  ✓ Nginx container healthy"
        elif [[ "$nginx_health" == "starting" ]]; then
            echo "  ℹ Nginx container health: starting (will be checked later)"
        elif [[ "$nginx_health" != "no-healthcheck" ]]; then
            echo -e "${YELLOW}  ⚠ Nginx container health: $nginx_health${NC}"
        fi

        # Check Nginx logs for critical errors (ignore informational messages)
        local nginx_logs=$(docker logs "${NGINX_CONTAINER_NAME}" 2>&1 | tail -20)
        if echo "$nginx_logs" | grep -q "nginx: \[emerg\]"; then
            echo -e "${RED}Nginx has critical errors in logs${NC}" >&2
            docker compose logs nginx
            return 1
        fi
        # Ignore read-only warnings - these are expected with security-hardened containers
        if echo "$nginx_logs" | grep -qE "(can not modify|read-only file system)"; then
            echo "  ℹ Nginx running in read-only mode (expected for security)"
        fi
    else
        echo -e "${RED}Nginx container failed to start (status: $nginx_status)${NC}" >&2
        docker compose logs nginx
        return 1
    fi

    # v4.3: Check HAProxy container (unified TLS termination in bridge network)
    local haproxy_status=$(docker inspect "${HAPROXY_CONTAINER_NAME}" -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
    if [[ "$haproxy_status" == "running" ]]; then
        echo "  ✓ HAProxy container running"

        # Check for bind errors in logs (common issue: Permission denied on ports)
        local haproxy_logs=$(docker logs "${HAPROXY_CONTAINER_NAME}" 2>&1 | tail -20)
        if echo "$haproxy_logs" | grep -q "cannot bind socket"; then
            echo -e "${RED}HAProxy has bind errors (check logs)${NC}" >&2
            docker compose logs haproxy
            return 1
        fi
    else
        echo -e "${RED}HAProxy container failed to start (status: $haproxy_status)${NC}" >&2
        docker compose logs haproxy
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
    local cli_source="${project_root}/scripts/vless"

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

    # Copy lib modules to installation (required for CLI to function)
    local lib_modules=(
        "user_management.sh"
        "qr_generator.sh"
        "proxy_whitelist.sh"
        "ufw_whitelist.sh"
        "security_tests.sh"
    )

    for module in "${lib_modules[@]}"; do
        if [[ -f "${project_root}/lib/${module}" ]]; then
            cp "${project_root}/lib/${module}" "${INSTALL_ROOT}/lib/" || {
                echo -e "${RED}Failed to copy ${module}${NC}" >&2
                return 1
            }

            # Set permissions: 755 for executable scripts, 644 for sourced modules
            if [[ "${module}" == "security_tests.sh" ]]; then
                chmod 755 "${INSTALL_ROOT}/lib/${module}" || {
                    echo -e "${RED}Failed to set permissions on ${module}${NC}" >&2
                    return 1
                }
            else
                chmod 644 "${INSTALL_ROOT}/lib/${module}" || {
                    echo -e "${RED}Failed to set permissions on ${module}${NC}" >&2
                    return 1
                }
            fi

            echo "  ✓ Copied ${module} to ${INSTALL_ROOT}/lib/"
        else
            echo -e "${RED}Required module not found: ${module}${NC}" >&2
            return 1
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

    # Set ownership for xray logs (container runs as user: nobody = UID 65534)
    # This allows xray container to write logs without permission errors
    if [[ -d "${LOGS_DIR}/xray" ]]; then
        chown -R 65534:65534 "${LOGS_DIR}/xray" 2>/dev/null || true
        chmod 755 "${LOGS_DIR}/xray" 2>/dev/null || true
    fi

    # Set ownership for nginx logs (containers run as user: nginx = UID 101)
    # This allows nginx containers to write logs without permission errors
    if [[ -d "${LOGS_DIR}/nginx" ]]; then
        chown -R 101:101 "${LOGS_DIR}/nginx" 2>/dev/null || true
        chmod 755 "${LOGS_DIR}/nginx" 2>/dev/null || true
    fi
    if [[ -d "${LOGS_DIR}/fake-site" ]]; then
        chown -R 101:101 "${LOGS_DIR}/fake-site" 2>/dev/null || true
        chmod 755 "${LOGS_DIR}/fake-site" 2>/dev/null || true
    fi

    # Readable files: 644
    find "${LOGS_DIR}" -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 644 "${DOCKER_COMPOSE_FILE}" 2>/dev/null || true
    chmod 644 "${NGINX_CONFIG}" 2>/dev/null || true

    # Executable scripts: 755
    find "${SCRIPTS_DIR}" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    echo "  ✓ Sensitive files: 600 (root only)"
    echo "  ✓ Config/keys directories: 700 (root only)"
    echo "  ✓ Xray logs ownership: nobody:nobody (65534:65534)"
    echo "  ✓ Nginx logs ownership: nginx:nginx (101:101)"
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

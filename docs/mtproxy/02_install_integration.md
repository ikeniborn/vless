# MTProxy Integration with install.sh

**Version:** 1.0
**Status:** ⏳ TODO (Deferred to v6.2 - PHASE 6 not implemented)
**Priority:** MEDIUM
**Last Updated:** 2025-11-08
**Note:** Core MTProxy features (v6.0+v6.1) are COMPLETED. This document describes installation wizard integration which is deferred to v6.2 release.
**Related Documents:**
- [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md) - Base implementation plan
- [01_advanced_features.md](01_advanced_features.md) - Advanced features specification
- [README.md](README.md) - Quick reference

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Integration Overview](#2-integration-overview)
3. [Heredoc Configuration Patterns](#3-heredoc-configuration-patterns)
4. [mtproxy-setup Script Structure](#4-mtproxy-setup-script-structure)
5. [Docker Compose Integration](#5-docker-compose-integration)
6. [Configuration File Generation](#6-configuration-file-generation)
7. [Opt-in Installation Flow](#7-opt-in-installation-flow)
8. [Testing & Validation](#8-testing--validation)
9. [Appendix: Code Examples](#9-appendix-code-examples)

---

## 1. Executive Summary

**Goal:** Integrate MTProxy installation into existing install.sh workflow following VLESS PRD v4.1+ heredoc patterns.

**Key Requirements:**
- ✅ Opt-in installation (non-intrusive)
- ✅ Heredoc-based config generation (NO templates/)
- ✅ Integration with install.sh main workflow
- ✅ Consistent with existing VLESS architecture patterns
- ✅ Support both v6.0 (base) and v6.1 (advanced) features

**Integration Points:**
1. **install.sh** - Add opt-in prompt after Step 10
2. **lib/mtproxy_manager.sh** - NEW module for MTProxy operations
3. **scripts/mtproxy-setup** - Standalone setup wizard
4. **Docker Compose** - Add mtproxy service via heredoc

**Compliance:**
- ✅ PRD v4.1+ heredoc requirement (no templates/)
- ✅ Modular architecture (lib/*.sh)
- ✅ Consistent error handling
- ✅ Logging standards

---

## 2. Integration Overview

### 2.1 Current install.sh Workflow

**Existing Steps (v5.26.1):**
```
Step 1:  Check root privileges
Step 2:  Detect operating system
Step 3:  Validate OS compatibility
Step 4:  Check dependencies
Step 5:  Install missing dependencies
Step 6:  Detect old installations
Step 7:  Collect installation parameters
Step 7.5: Acquire TLS certificate (if public proxy + TLS enabled)
Step 8:  Orchestrate installation (create /opt/vless)
Step 9:  Verify installation
Step 9.5: Save version file
Step 10: Display sudoers configuration
```

### 2.2 Proposed Integration Point

**Option A: Post-Installation Prompt (RECOMMENDED)**

Add opt-in prompt AFTER Step 10, before final success message:

```bash
main() {
    # ... existing steps 1-10 ...

    # Step 10: Display sudoers instructions
    print_step 10 "Displaying sudoers configuration"
    display_sudoers_instructions

    # NEW: Step 10.5 - MTProxy opt-in (v6.0)
    echo ""
    print_message "${COLOR_CYAN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "${COLOR_CYAN}" "  OPTIONAL: MTPROXY FOR TELEGRAM (v6.0)"
    print_message "${COLOR_CYAN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_message "${COLOR_BLUE}" "MTProxy is Telegram's official proxy protocol for bypassing censorship."
    print_message "${COLOR_BLUE}" "It provides transport obfuscation and one-tap connection in Telegram."
    echo ""

    # Check for non-interactive mode
    if [[ -n "${VLESS_AUTO_INSTALL_MTPROXY:-}" ]]; then
        mtproxy_choice="${VLESS_AUTO_INSTALL_MTPROXY}"
        print_message "${COLOR_CYAN}" "Non-interactive mode: Using VLESS_AUTO_INSTALL_MTPROXY=$mtproxy_choice"
    else
        read -t 30 -rp "Would you like to install MTProxy? (y/n) [default=n]: " mtproxy_choice || mtproxy_choice="n"
        [[ -z "$mtproxy_choice" ]] && mtproxy_choice="n"
    fi

    if [[ "$mtproxy_choice" =~ ^[Yy]$ ]]; then
        print_message "${COLOR_BLUE}" "Starting MTProxy installation wizard..."
        /opt/vless/scripts/mtproxy-setup || {
            print_warning "MTProxy installation failed, but VLESS installation is complete"
        }
    else
        print_message "${COLOR_YELLOW}" "MTProxy installation skipped"
        print_message "${COLOR_CYAN}" "You can install it later with: sudo mtproxy-setup"
    fi

    # Final success message
    echo ""
    print_message "${COLOR_GREEN}" "╔══════════════════════════════════════════════════════════════╗"
    # ... rest of final success message ...
}
```

**Why Option A:**
- ✅ Non-intrusive (opt-in after main installation complete)
- ✅ Doesn't affect TOTAL_STEPS count (keeps existing logic)
- ✅ Clear separation of concerns
- ✅ Easy rollback (skip if user declines)
- ✅ Supports non-interactive mode via environment variable

**Alternative: Option B (Not Recommended)**

Add as Step 11, increment TOTAL_STEPS to 11:
- ❌ Requires modifying step counter
- ❌ Makes MTProxy appear mandatory (even if skippable)
- ❌ Breaks semantic separation (MTProxy is optional service)

### 2.3 Directory Structure After Integration

```
/opt/vless/
├── config/
│   ├── xray_config.json              # Existing
│   ├── haproxy.cfg                   # Existing
│   └── mtproxy/                      # NEW v6.0
│       ├── mtproxy_config.json       # MTProxy settings (port, workers)
│       ├── secrets.json              # User secrets DB (v6.0: single, v6.1: multi-user)
│       └── proxy-secret              # AES secret file
│
├── data/
│   └── mtproxy/                      # NEW v6.0
│       ├── stats.json                # Statistics cache
│       └── promoted_channel.txt      # Promoted channel ID (v6.1)
│
├── logs/
│   └── mtproxy/                      # NEW v6.0
│       └── mtproxy.log
│
└── scripts/
    ├── mtproxy-setup           # NEW v6.0 - Interactive setup wizard
    ├── mtproxy                 # NEW v6.0 - Management CLI
    └── mtproxy-uninstall       # NEW v6.0 - Complete removal
```

---

## 3. Heredoc Configuration Patterns

**PRD Requirement (v4.1+):** All configuration files MUST be generated via heredoc (NO templates/ directory).

### 3.1 Heredoc Best Practices (from PRD v4.1)

**Pattern: Quoted Heredoc (Prevent Variable Expansion)**

Use `<<'EOF'` (quoted delimiter) when content contains literal `$` characters:

```bash
cat > "$output_file" <<'EOF'
{
  "key": "$literal_value",
  "var": "not expanded"
}
EOF
```

**Pattern: Unquoted Heredoc (Enable Variable Expansion)**

Use `<<EOF` (unquoted delimiter) for config with bash variables:

```bash
cat > "$output_file" <<EOF
{
  "port": ${PORT},
  "domain": "${DOMAIN}"
}
EOF
```

**Pattern: Indented Heredoc (Readable Script)**

Use `<<-EOF` (hyphen) to allow leading tabs for indentation:

```bash
generate_config() {
	cat > "$output_file" <<-EOF
		{
		  "indented": true
		}
	EOF
}
```

### 3.2 MTProxy Configuration Heredoc Patterns

**Example 1: MTProxy Docker Compose Service (v6.0)**

```bash
generate_mtproxy_docker_compose() {
    local mtproxy_port="${1:-8443}"
    local mtproxy_secret="$2"
    local compose_file="/opt/vless/docker-compose.yml"

    # Append MTProxy service to existing docker-compose.yml
    cat >> "$compose_file" <<EOF

  # MTProxy Service (v6.0)
  mtproxy:
    image: alpine:latest
    container_name: vless_mtproxy
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "${mtproxy_port}:8443"  # Public MTProxy port
    volumes:
      - /opt/vless/config/mtproxy:/etc/mtproxy:ro
      - /opt/vless/logs/mtproxy:/var/log/mtproxy
    environment:
      - TZ=UTC
      - MTPROXY_SECRET=${mtproxy_secret}
    command: >
      sh -c "
      apk add --no-cache git build-base openssl-dev zlib-dev &&
      git clone https://github.com/TelegramMessenger/MTProxy.git /tmp/mtproxy &&
      cd /tmp/mtproxy && make &&
      ./objs/bin/mtproto-proxy -u nobody -p 8888 -H 8443 \\
        -S \\\${MTPROXY_SECRET} \\
        --aes-pwd /etc/mtproxy/proxy-secret \\
        /etc/mtproxy/proxy-multi.conf -M 1
      "
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    print_success "MTProxy service added to docker-compose.yml"
}
```

**Example 2: MTProxy Configuration File (JSON)**

```bash
generate_mtproxy_config() {
    local config_file="/opt/vless/config/mtproxy/mtproxy_config.json"
    local port="${1:-8443}"
    local workers="${2:-1}"

    cat > "$config_file" <<EOF
{
  "version": "6.0",
  "port": ${port},
  "workers": ${workers},
  "stats_endpoint": true,
  "stats_port": 8888,
  "secret_type": "dd",
  "max_users": 1,
  "promoted_channel": null,
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    chmod 600 "$config_file"
    print_success "MTProxy config generated: $config_file"
}
```

**Example 3: Secrets Database (v6.0 Single-User)**

```bash
generate_secrets_db_v60() {
    local secrets_file="/opt/vless/config/mtproxy/secrets.json"
    local secret="$1"

    cat > "$secrets_file" <<EOF
{
  "version": "1.0",
  "mode": "single-user",
  "secrets": [
    {
      "secret": "${secret}",
      "type": "dd",
      "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "description": "Default MTProxy secret"
    }
  ]
}
EOF

    chmod 600 "$secrets_file"
    print_success "Secrets database created: $secrets_file"
}
```

**Example 4: Multi-User Secrets Database (v6.1)**

```bash
generate_secrets_db_v61() {
    local secrets_file="/opt/vless/config/mtproxy/secrets.json"

    # Initialize empty multi-user database
    cat > "$secrets_file" <<'EOF'
{
  "version": "2.0",
  "mode": "multi-user",
  "max_users": 50,
  "secrets": []
}
EOF

    chmod 600 "$secrets_file"
    print_success "Multi-user secrets database initialized: $secrets_file"
}

add_user_secret_v61() {
    local username="$1"
    local secret="$2"
    local secret_type="${3:-dd}"
    local secrets_file="/opt/vless/config/mtproxy/secrets.json"

    # Use jq to add user secret
    local temp_file
    temp_file=$(mktemp)

    jq --arg user "$username" \
       --arg secret "$secret" \
       --arg type "$secret_type" \
       --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.secrets += [{
           "username": $user,
           "secret": $secret,
           "type": $type,
           "created_at": $created,
           "last_rotated": null
       }]' "$secrets_file" > "$temp_file"

    mv "$temp_file" "$secrets_file"
    chmod 600 "$secrets_file"

    print_success "User secret added: $username"
}
```

**Example 5: MTProxy proxy-secret File**

```bash
generate_proxy_secret_file() {
    local secret_file="/opt/vless/config/mtproxy/proxy-secret"

    # Generate AES secret (32 bytes hex)
    head -c 16 /dev/urandom | xxd -ps -c 16 > "$secret_file"

    chmod 600 "$secret_file"
    print_success "Proxy secret file created: $secret_file"
}
```

### 3.3 Heredoc Pattern Summary

| Use Case | Pattern | Variables | Example |
|----------|---------|-----------|---------|
| JSON config with vars | `<<EOF` (unquoted) | Expanded | `"port": ${PORT}` |
| Literal content | `<<'EOF'` (quoted) | NOT expanded | `"var": "$literal"` |
| Indented script | `<<-EOF` (hyphen) | Expanded (tabs OK) | Function body |
| Multi-line command | `<< 'EOF'` | NOT expanded | Docker CMD |

---

## 4. mtproxy-setup Script Structure

**Location:** `/opt/vless/scripts/mtproxy-setup`

**Purpose:** Interactive wizard for MTProxy installation (v6.0 base functionality).

### 4.1 Script Header

```bash
#!/bin/bash
################################################################################
# VLESS MTProxy Setup Wizard
#
# Description:
#   Interactive installation wizard for MTProxy Telegram proxy integration.
#   Supports both v6.0 (single-user) and v6.1 (multi-user) modes.
#
# Usage:
#   sudo mtproxy-setup              # Interactive wizard
#   MTPROXY_AUTO_MODE=yes sudo mtproxy-setup  # Non-interactive (defaults)
#
# Requirements:
#   - Must be run as root
#   - VLESS installation must be complete (/opt/vless exists)
#   - Docker and Docker Compose installed
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Permission error (not root)
#   3 - VLESS not installed
#
# Version: 6.0.0
# Date: 2025-11-08
################################################################################

set -euo pipefail

# Version tracking
readonly MTPROXY_VERSION="6.0.0"
readonly REQUIRED_VLESS_VERSION="5.33"

# Installation root (HARDCODED - cannot be changed)
readonly INSTALL_ROOT="/opt/vless"

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'
```

### 4.2 Core Functions

```bash
################################################################################
# Function: check_prerequisites
# Description: Verify VLESS installation and dependencies
################################################################################
check_prerequisites() {
    print_step "Checking prerequisites"

    # Check root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 2
    fi

    # Check VLESS installation
    if [[ ! -d "$INSTALL_ROOT" ]]; then
        print_error "VLESS installation not found at $INSTALL_ROOT"
        print_error "Please install VLESS first: sudo ./install.sh"
        exit 3
    fi

    # Check VLESS version
    if [[ -f "${INSTALL_ROOT}/.version" ]]; then
        local vless_version
        vless_version=$(cat "${INSTALL_ROOT}/.version")
        print_message "${COLOR_CYAN}" "  VLESS version: v${vless_version}"
    else
        print_warning "VLESS version file not found, assuming compatible"
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 3
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose not found. Please install Docker Compose first."
        exit 3
    fi

    print_success "Prerequisites check passed"
}

################################################################################
# Function: collect_mtproxy_parameters
# Description: Interactive parameter collection for MTProxy
################################################################################
collect_mtproxy_parameters() {
    print_step "Collecting MTProxy parameters"

    # Check for non-interactive mode
    if [[ -n "${MTPROXY_AUTO_MODE:-}" ]]; then
        print_message "${COLOR_CYAN}" "Non-interactive mode: Using default parameters"
        MTPROXY_PORT="8443"
        MTPROXY_WORKERS="1"
        MTPROXY_SECRET_TYPE="dd"
        MTPROXY_ENABLE_PROMOTED_CHANNEL="false"
        return 0
    fi

    echo ""
    print_message "${COLOR_BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "${COLOR_BLUE}" "  MTPROXY CONFIGURATION"
    print_message "${COLOR_BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 1. Port selection
    read -rp "MTProxy port [default=8443]: " MTPROXY_PORT
    MTPROXY_PORT="${MTPROXY_PORT:-8443}"

    # Validate port
    if ! [[ "$MTPROXY_PORT" =~ ^[0-9]+$ ]] || [ "$MTPROXY_PORT" -lt 1 ] || [ "$MTPROXY_PORT" -gt 65535 ]; then
        print_error "Invalid port number. Using default: 8443"
        MTPROXY_PORT="8443"
    fi

    # Check port conflicts
    if ss -tuln | grep -q ":${MTPROXY_PORT} "; then
        print_warning "Port $MTPROXY_PORT is already in use"
        read -rp "Continue anyway? (y/n) [default=n]: " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled due to port conflict"
            exit 1
        fi
    fi

    # 2. Workers count
    read -rp "Number of workers [default=1, recommended=1]: " MTPROXY_WORKERS
    MTPROXY_WORKERS="${MTPROXY_WORKERS:-1}"

    # 3. Secret type
    echo ""
    print_message "${COLOR_CYAN}" "Secret types:"
    print_message "${COLOR_CYAN}" "  1) Standard (32 hex chars)"
    print_message "${COLOR_CYAN}" "  2) Random padding (dd prefix, recommended for DPI bypass)"
    print_message "${COLOR_CYAN}" "  3) Fake-TLS (ee prefix, advanced, requires domain)"
    read -rp "Select secret type [default=2]: " secret_choice
    secret_choice="${secret_choice:-2}"

    case "$secret_choice" in
        1) MTPROXY_SECRET_TYPE="standard" ;;
        2) MTPROXY_SECRET_TYPE="dd" ;;
        3)
            MTPROXY_SECRET_TYPE="ee"
            read -rp "Enter domain for fake-TLS (e.g., www.google.com): " MTPROXY_FAKE_TLS_DOMAIN
            ;;
        *)
            print_warning "Invalid choice, using default (dd)"
            MTPROXY_SECRET_TYPE="dd"
            ;;
    esac

    # 4. Promoted channel (v6.1 preview)
    echo ""
    read -rp "Enable promoted channel? (y/n) [default=n, requires @MTProxybot registration]: " promoted_choice
    if [[ "$promoted_choice" =~ ^[Yy]$ ]]; then
        MTPROXY_ENABLE_PROMOTED_CHANNEL="true"
        print_message "${COLOR_YELLOW}" "Note: You'll need to register with @MTProxybot and provide the tag after installation"
    else
        MTPROXY_ENABLE_PROMOTED_CHANNEL="false"
    fi

    # Display summary
    echo ""
    print_message "${COLOR_GREEN}" "Configuration summary:"
    print_message "${COLOR_CYAN}" "  Port: $MTPROXY_PORT"
    print_message "${COLOR_CYAN}" "  Workers: $MTPROXY_WORKERS"
    print_message "${COLOR_CYAN}" "  Secret type: $MTPROXY_SECRET_TYPE"
    print_message "${COLOR_CYAN}" "  Promoted channel: $MTPROXY_ENABLE_PROMOTED_CHANNEL"
    echo ""

    read -rp "Proceed with installation? (y/n) [default=y]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]?$ ]]; then
        print_error "Installation cancelled by user"
        exit 0
    fi

    print_success "Parameters collected"
}

################################################################################
# Function: generate_mtproxy_secret
# Description: Generate MTProxy secret based on type
# Arguments:
#   $1 - Secret type (standard/dd/ee)
#   $2 - Domain (required for ee type)
################################################################################
generate_mtproxy_secret() {
    local secret_type="$1"
    local domain="${2:-}"

    case "$secret_type" in
        standard)
            # Standard secret: 16 bytes (32 hex chars)
            head -c 16 /dev/urandom | xxd -ps -c 16
            ;;
        dd)
            # Random padding: dd + 16 bytes (34 hex chars total)
            echo -n "dd"
            head -c 16 /dev/urandom | xxd -ps -c 16
            ;;
        ee)
            # Fake-TLS: ee + 16 bytes + domain_hex
            if [[ -z "$domain" ]]; then
                print_error "Domain required for fake-TLS secret"
                exit 1
            fi

            local base_secret
            base_secret=$(head -c 16 /dev/urandom | xxd -ps -c 16)

            local domain_hex
            domain_hex=$(echo -n "$domain" | xxd -ps -c 1000)

            echo "ee${base_secret}${domain_hex}"
            ;;
        *)
            print_error "Invalid secret type: $secret_type"
            exit 1
            ;;
    esac
}

################################################################################
# Function: setup_mtproxy_directories
# Description: Create MTProxy directory structure
################################################################################
setup_mtproxy_directories() {
    print_step "Creating MTProxy directories"

    mkdir -p "${INSTALL_ROOT}/config/mtproxy"
    mkdir -p "${INSTALL_ROOT}/data/mtproxy"
    mkdir -p "${INSTALL_ROOT}/logs/mtproxy"

    chmod 700 "${INSTALL_ROOT}/config/mtproxy"
    chmod 755 "${INSTALL_ROOT}/data/mtproxy"
    chmod 755 "${INSTALL_ROOT}/logs/mtproxy"

    print_success "Directories created"
}

################################################################################
# Function: generate_mtproxy_configs
# Description: Generate all MTProxy configuration files using heredoc
################################################################################
generate_mtproxy_configs() {
    print_step "Generating MTProxy configurations"

    # 1. Generate MTProxy secret
    local secret
    if [[ "$MTPROXY_SECRET_TYPE" == "ee" ]]; then
        secret=$(generate_mtproxy_secret "ee" "$MTPROXY_FAKE_TLS_DOMAIN")
    else
        secret=$(generate_mtproxy_secret "$MTPROXY_SECRET_TYPE")
    fi

    print_message "${COLOR_CYAN}" "  Generated secret: ${secret:0:10}... (truncated for security)"

    # 2. Generate proxy-secret file (AES secret)
    generate_proxy_secret_file

    # 3. Generate mtproxy_config.json
    generate_mtproxy_config "$MTPROXY_PORT" "$MTPROXY_WORKERS"

    # 4. Generate secrets database (v6.0 single-user mode)
    generate_secrets_db_v60 "$secret"

    # 5. Generate proxy-multi.conf (empty for v6.0)
    touch "${INSTALL_ROOT}/config/mtproxy/proxy-multi.conf"
    chmod 600 "${INSTALL_ROOT}/config/mtproxy/proxy-multi.conf"

    # 6. Store secret for later use (client config generation)
    echo "$secret" > "${INSTALL_ROOT}/config/mtproxy/.current_secret"
    chmod 600 "${INSTALL_ROOT}/config/mtproxy/.current_secret"

    print_success "Configurations generated"
}

################################################################################
# Function: integrate_with_docker_compose
# Description: Add MTProxy service to docker-compose.yml
################################################################################
integrate_with_docker_compose() {
    print_step "Integrating MTProxy with Docker Compose"

    local compose_file="${INSTALL_ROOT}/docker-compose.yml"

    # Check if MTProxy service already exists
    if grep -q "container_name: vless_mtproxy" "$compose_file" 2>/dev/null; then
        print_warning "MTProxy service already exists in docker-compose.yml"
        read -rp "Replace existing service? (y/n) [default=n]: " replace
        if [[ "$replace" =~ ^[Yy]$ ]]; then
            # Remove old service (complex sed operation - use temp file)
            print_message "${COLOR_CYAN}" "  Removing old MTProxy service..."
            # TODO: Implement safe removal (or manual instruction)
            print_warning "Manual removal required. Please edit docker-compose.yml"
            return 1
        else
            print_message "${COLOR_YELLOW}" "Skipping Docker Compose integration"
            return 0
        fi
    fi

    # Get secret from .current_secret file
    local secret
    secret=$(cat "${INSTALL_ROOT}/config/mtproxy/.current_secret")

    # Add MTProxy service
    generate_mtproxy_docker_compose "$MTPROXY_PORT" "$secret"

    print_success "Docker Compose integration complete"
}

################################################################################
# Function: configure_firewall
# Description: Add UFW rules for MTProxy port
################################################################################
configure_firewall() {
    print_step "Configuring firewall rules"

    if ! command -v ufw &> /dev/null; then
        print_warning "UFW not installed, skipping firewall configuration"
        return 0
    fi

    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        print_warning "UFW is not active, skipping firewall rules"
        return 0
    fi

    # Add allow rule for MTProxy port
    ufw allow "${MTPROXY_PORT}/tcp" comment "MTProxy Telegram" >/dev/null 2>&1 || {
        print_warning "Failed to add UFW rule (may already exist)"
    }

    print_success "Firewall rules configured"
}

################################################################################
# Function: deploy_mtproxy_container
# Description: Start MTProxy Docker container
################################################################################
deploy_mtproxy_container() {
    print_step "Deploying MTProxy container"

    cd "$INSTALL_ROOT" || {
        print_error "Failed to change directory to $INSTALL_ROOT"
        exit 1
    }

    # Stop existing container if running
    if docker ps -a --format '{{.Names}}' | grep -q "^vless_mtproxy$"; then
        print_message "${COLOR_CYAN}" "  Stopping existing MTProxy container..."
        docker stop vless_mtproxy >/dev/null 2>&1 || true
        docker rm vless_mtproxy >/dev/null 2>&1 || true
    fi

    # Start MTProxy service
    print_message "${COLOR_CYAN}" "  Starting MTProxy service..."
    docker compose up -d mtproxy || {
        print_error "Failed to start MTProxy container"
        print_error "Check logs: docker logs vless_mtproxy"
        exit 1
    }

    # Wait for container to be healthy
    print_message "${COLOR_CYAN}" "  Waiting for container to be ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker ps --filter "name=vless_mtproxy" --filter "health=healthy" --format '{{.Names}}' | grep -q "vless_mtproxy"; then
            print_success "MTProxy container is healthy"
            return 0
        fi
        sleep 2
        ((retries--))
    done

    print_warning "Container started but health check pending"
    print_message "${COLOR_CYAN}" "Check status: docker ps -a | grep mtproxy"
}

################################################################################
# Function: generate_client_config
# Description: Generate client configuration (deep link, QR code)
################################################################################
generate_client_config() {
    print_step "Generating client configuration"

    # Get server public IP
    local server_ip
    server_ip=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")

    # Get secret
    local secret
    secret=$(cat "${INSTALL_ROOT}/config/mtproxy/.current_secret")

    # Generate tg:// deep link
    local deep_link="tg://proxy?server=${server_ip}&port=${MTPROXY_PORT}&secret=${secret}"

    # Save to file
    local config_file="${INSTALL_ROOT}/data/mtproxy/client_config.txt"
    cat > "$config_file" <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MTPROXY CLIENT CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Server: ${server_ip}
Port: ${MTPROXY_PORT}
Secret: ${secret}

Deep Link (tap to connect in Telegram):
${deep_link}

Manual Configuration:
1. Open Telegram app
2. Go to Settings > Data and Storage > Proxy Settings
3. Add Proxy:
   - Server: ${server_ip}
   - Port: ${MTPROXY_PORT}
   - Secret: ${secret}

OR scan QR code (if generated)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Version: v${MTPROXY_VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    chmod 644 "$config_file"

    # Display to user
    echo ""
    cat "$config_file"
    echo ""

    print_success "Client configuration generated: $config_file"
    print_message "${COLOR_CYAN}" "Deep link: $deep_link"
}

################################################################################
# Function: display_final_instructions
# Description: Show post-installation instructions
################################################################################
display_final_instructions() {
    echo ""
    print_message "${COLOR_GREEN}" "╔══════════════════════════════════════════════════════════════╗"
    print_message "${COLOR_GREEN}" "║                                                              ║"
    print_message "${COLOR_GREEN}" "║          MTProxy Installation Completed!                     ║"
    print_message "${COLOR_GREEN}" "║                                                              ║"
    print_message "${COLOR_GREEN}" "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    print_message "${COLOR_CYAN}" "Next Steps:"
    print_message "${COLOR_YELLOW}" "  1. Connect Telegram: Tap deep link or scan QR code"
    print_message "${COLOR_YELLOW}" "  2. Check status: sudo mtproxy stats"
    print_message "${COLOR_YELLOW}" "  3. View logs: docker logs vless_mtproxy"
    echo ""

    print_message "${COLOR_CYAN}" "Management Commands:"
    print_message "${COLOR_YELLOW}" "  sudo mtproxy stats       # View statistics"
    print_message "${COLOR_YELLOW}" "  sudo mtproxy show-config # Show configuration"
    print_message "${COLOR_YELLOW}" "  sudo vless status              # Overall status (includes MTProxy)"
    echo ""

    if [[ "$MTPROXY_ENABLE_PROMOTED_CHANNEL" == "true" ]]; then
        print_message "${COLOR_CYAN}" "Promoted Channel Setup:"
        print_message "${COLOR_YELLOW}" "  1. Message @MTProxybot in Telegram"
        print_message "${COLOR_YELLOW}" "  2. Register your proxy and get TAG"
        print_message "${COLOR_YELLOW}" "  3. Run: sudo mtproxy set-promoted-channel <TAG>"
        echo ""
    fi

    print_message "${COLOR_CYAN}" "Configuration Location: ${INSTALL_ROOT}/config/mtproxy/"
    print_message "${COLOR_CYAN}" "Client Config: ${INSTALL_ROOT}/data/mtproxy/client_config.txt"
    echo ""
}
```

### 4.3 Main Workflow

```bash
################################################################################
# Function: main
# Description: Main setup workflow
################################################################################
main() {
    # Display banner
    echo ""
    print_message "${COLOR_CYAN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "${COLOR_CYAN}" "  MTPROXY INSTALLATION WIZARD v${MTPROXY_VERSION}"
    print_message "${COLOR_CYAN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Workflow
    check_prerequisites
    collect_mtproxy_parameters
    setup_mtproxy_directories
    generate_mtproxy_configs
    integrate_with_docker_compose
    configure_firewall
    deploy_mtproxy_container
    generate_client_config
    display_final_instructions

    print_message "${COLOR_GREEN}" "✓ Installation complete!"
}

# Script entry point
main "$@"
```

---

## 5. Docker Compose Integration

### 5.1 MTProxy Service Definition (v6.0)

```yaml
  # MTProxy Service (v6.0 - Telegram Proxy)
  mtproxy:
    build:
      context: ./docker/mtproxy
      dockerfile: Dockerfile
    container_name: vless_mtproxy
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "${MTPROXY_PORT:-8443}:8443"
    volumes:
      - ./config/mtproxy:/etc/mtproxy:ro
      - ./logs/mtproxy:/var/log/mtproxy
      - ./data/mtproxy:/var/lib/mtproxy
    environment:
      - TZ=UTC
      - MTPROXY_SECRET=${MTPROXY_SECRET}
      - MTPROXY_PORT=8443
      - MTPROXY_WORKERS=${MTPROXY_WORKERS:-1}
    command: >
      /usr/local/bin/mtproto-proxy
      -u mtproxy
      -p 8888
      -H 8443
      -S ${MTPROXY_SECRET}
      --aes-pwd /etc/mtproxy/proxy-secret
      /etc/mtproxy/proxy-multi.conf
      -M ${MTPROXY_WORKERS:-1}
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - xray
```

### 5.2 Dockerfile (Heredoc Generation)

```bash
generate_mtproxy_dockerfile() {
    local dockerfile_dir="${INSTALL_ROOT}/docker/mtproxy"
    mkdir -p "$dockerfile_dir"

    cat > "${dockerfile_dir}/Dockerfile" <<'EOF'
# MTProxy Dockerfile (Official Telegram MTProto Proxy)
# Built from source: https://github.com/TelegramMessenger/MTProxy

FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    openssl-dev \
    zlib-dev

# Clone and build MTProxy
RUN git clone https://github.com/TelegramMessenger/MTProxy.git /tmp/mtproxy && \
    cd /tmp/mtproxy && \
    make

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    zlib \
    curl \
    netcat-openbsd

# Copy compiled binary from builder
COPY --from=builder /tmp/mtproxy/objs/bin/mtproto-proxy /usr/local/bin/

# Create mtproxy user
RUN adduser -D -s /sbin/nologin mtproxy

# Create directories
RUN mkdir -p /etc/mtproxy /var/log/mtproxy /var/lib/mtproxy && \
    chown mtproxy:mtproxy /var/log/mtproxy /var/lib/mtproxy

# Expose ports
EXPOSE 8443 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD nc -z 127.0.0.1 8443 || exit 1

# Default command (overridden in docker-compose.yml)
CMD ["/usr/local/bin/mtproto-proxy", "-h"]
EOF

    print_success "Dockerfile generated: ${dockerfile_dir}/Dockerfile"
}
```

---

## 6. Configuration File Generation

### 6.1 MTProxy Configuration Schema

```json
{
  "version": "6.0",
  "port": 8443,
  "workers": 1,
  "stats_endpoint": true,
  "stats_port": 8888,
  "secret_type": "dd",
  "max_users": 1,
  "promoted_channel": null,
  "features": {
    "multi_user": false,
    "fake_tls": false,
    "promoted_channels": false
  },
  "created_at": "2025-11-08T00:00:00Z",
  "updated_at": "2025-11-08T00:00:00Z"
}
```

### 6.2 Secrets Database Schema (v6.0)

```json
{
  "version": "1.0",
  "mode": "single-user",
  "secrets": [
    {
      "secret": "dd0123456789abcdef0123456789abcdef",
      "type": "dd",
      "created_at": "2025-11-08T00:00:00Z",
      "description": "Default MTProxy secret"
    }
  ]
}
```

### 6.3 Secrets Database Schema (v6.1 Multi-User)

```json
{
  "version": "2.0",
  "mode": "multi-user",
  "max_users": 50,
  "secrets": [
    {
      "username": "alice",
      "secret": "dd0123456789abcdef0123456789abcdef",
      "type": "dd",
      "created_at": "2025-11-08T00:00:00Z",
      "last_rotated": null
    },
    {
      "username": "bob",
      "secret": "ee0123456789abcdef0123456789abcdef7777772e676f6f676c652e636f6d",
      "type": "ee",
      "fake_tls_domain": "www.google.com",
      "created_at": "2025-11-08T01:00:00Z",
      "last_rotated": null
    }
  ]
}
```

---

## 7. Opt-in Installation Flow

### 7.1 User Journey (Interactive Mode)

```
[User runs: sudo ./install.sh]

Step 1-10: VLESS installation (existing workflow)
  ↓
[Installation complete - at final success message]
  ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  OPTIONAL: MTPROXY FOR TELEGRAM (v6.0)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MTProxy is Telegram's official proxy protocol for bypassing censorship.
It provides transport obfuscation and one-tap connection in Telegram.

Would you like to install MTProxy? (y/n) [default=n]:
  ↓
[User enters: y]
  ↓
Starting MTProxy installation wizard...
  ↓
[mtproxy-setup runs]
  ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MTPROXY CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MTProxy port [default=8443]:
  ↓
[User presses Enter - accepts default]
  ↓
Number of workers [default=1, recommended=1]:
  ↓
[User presses Enter]
  ↓
Secret types:
  1) Standard (32 hex chars)
  2) Random padding (dd prefix, recommended for DPI bypass)
  3) Fake-TLS (ee prefix, advanced, requires domain)
Select secret type [default=2]:
  ↓
[User enters: 2]
  ↓
Enable promoted channel? (y/n) [default=n]:
  ↓
[User enters: n]
  ↓
Configuration summary:
  Port: 8443
  Workers: 1
  Secret type: dd
  Promoted channel: false

Proceed with installation? (y/n) [default=y]:
  ↓
[User presses Enter]
  ↓
[Installation progress]
[1/8] Creating MTProxy directories...        ✓
[2/8] Generating MTProxy configurations...   ✓
[3/8] Integrating with Docker Compose...     ✓
[4/8] Configuring firewall rules...          ✓
[5/8] Deploying MTProxy container...         ✓
[6/8] Waiting for container health...        ✓
[7/8] Generating client configuration...     ✓
[8/8] Finalizing installation...             ✓
  ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MTPROXY CLIENT CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Server: 1.2.3.4
Port: 8443
Secret: dd0123456789abcdef0123456789abcdef

Deep Link (tap to connect in Telegram):
tg://proxy?server=1.2.3.4&port=8443&secret=dd0123456789abcdef0123456789abcdef

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ↓
╔══════════════════════════════════════════════════════════════╗
║          MTProxy Installation Completed!                     ║
╚══════════════════════════════════════════════════════════════╝

Next Steps:
  1. Connect Telegram: Tap deep link or scan QR code
  2. Check status: sudo mtproxy stats
  3. View logs: docker logs vless_mtproxy

[End of installation]
```

### 7.2 Non-Interactive Mode

```bash
# Option 1: Skip MTProxy installation
sudo ./install.sh
# (Press 'n' when prompted, or timeout after 30s defaults to 'n')

# Option 2: Auto-install MTProxy with defaults
VLESS_AUTO_INSTALL_MTPROXY=yes sudo ./install.sh

# Option 3: Auto-install with custom parameters
VLESS_AUTO_INSTALL_MTPROXY=yes \
MTPROXY_PORT=8443 \
MTPROXY_WORKERS=2 \
MTPROXY_SECRET_TYPE=dd \
sudo ./install.sh
```

---

## 8. Testing & Validation

### 8.1 Installation Validation Checklist

```bash
#!/bin/bash
# MTProxy installation validation script

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MTPROXY INSTALLATION VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Check directories
echo "[1/10] Checking directory structure..."
if [[ -d "/opt/vless/config/mtproxy" ]] && \
   [[ -d "/opt/vless/data/mtproxy" ]] && \
   [[ -d "/opt/vless/logs/mtproxy" ]]; then
    echo "  ✓ Directories exist"
else
    echo "  ✗ Missing directories"
    exit 1
fi

# 2. Check configuration files
echo "[2/10] Checking configuration files..."
required_files=(
    "/opt/vless/config/mtproxy/mtproxy_config.json"
    "/opt/vless/config/mtproxy/secrets.json"
    "/opt/vless/config/mtproxy/proxy-secret"
)
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✓ $file"
    else
        echo "  ✗ Missing: $file"
        exit 1
    fi
done

# 3. Check Docker container
echo "[3/10] Checking Docker container..."
if docker ps --format '{{.Names}}' | grep -q "^vless_mtproxy$"; then
    echo "  ✓ Container running"
else
    echo "  ✗ Container not running"
    exit 1
fi

# 4. Check container health
echo "[4/10] Checking container health..."
health=$(docker inspect --format='{{.State.Health.Status}}' vless_mtproxy 2>/dev/null)
if [[ "$health" == "healthy" ]]; then
    echo "  ✓ Container healthy"
else
    echo "  ✗ Container unhealthy (status: $health)"
    exit 1
fi

# 5. Check port listening
echo "[5/10] Checking MTProxy port..."
if ss -tuln | grep -q ":8443 "; then
    echo "  ✓ Port 8443 listening"
else
    echo "  ✗ Port 8443 not listening"
    exit 1
fi

# 6. Check UFW rules
echo "[6/10] Checking firewall rules..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "8443.*ALLOW"; then
        echo "  ✓ UFW rule configured"
    else
        echo "  ⚠ UFW rule not found (may be optional)"
    fi
else
    echo "  ⚠ UFW not installed (skipped)"
fi

# 7. Check secrets
echo "[7/10] Validating secrets..."
if jq -e '.secrets | length > 0' /opt/vless/config/mtproxy/secrets.json >/dev/null 2>&1; then
    echo "  ✓ Secrets configured"
else
    echo "  ✗ No secrets found"
    exit 1
fi

# 8. Check stats endpoint
echo "[8/10] Testing stats endpoint..."
if docker exec vless_mtproxy nc -z 127.0.0.1 8888 2>/dev/null; then
    echo "  ✓ Stats endpoint accessible"
else
    echo "  ✗ Stats endpoint not accessible"
    exit 1
fi

# 9. Check client config
echo "[9/10] Checking client configuration..."
if [[ -f "/opt/vless/data/mtproxy/client_config.txt" ]]; then
    echo "  ✓ Client config generated"
else
    echo "  ✗ Client config missing"
    exit 1
fi

# 10. Check docker-compose.yml
echo "[10/10] Validating docker-compose.yml..."
if grep -q "container_name: vless_mtproxy" /opt/vless/docker-compose.yml; then
    echo "  ✓ MTProxy service in docker-compose.yml"
else
    echo "  ✗ MTProxy service not found in docker-compose.yml"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ ALL VALIDATION CHECKS PASSED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### 8.2 Functional Testing

```bash
# Test 1: Generate test secret
test_generate_secret() {
    echo "Testing secret generation..."

    # Standard secret (32 hex)
    secret=$(head -c 16 /dev/urandom | xxd -ps -c 16)
    if [[ ${#secret} -eq 32 ]]; then
        echo "  ✓ Standard secret: $secret"
    else
        echo "  ✗ Invalid standard secret length: ${#secret}"
        return 1
    fi

    # dd secret (34 hex)
    dd_secret="dd${secret}"
    if [[ ${#dd_secret} -eq 34 ]] && [[ "$dd_secret" == dd* ]]; then
        echo "  ✓ Random padding secret: $dd_secret"
    else
        echo "  ✗ Invalid dd secret"
        return 1
    fi
}

# Test 2: Verify container connectivity
test_container_connectivity() {
    echo "Testing container connectivity..."

    if docker exec vless_mtproxy nc -z 127.0.0.1 8443; then
        echo "  ✓ MTProxy port accessible inside container"
    else
        echo "  ✗ MTProxy port NOT accessible"
        return 1
    fi
}

# Test 3: Check stats endpoint
test_stats_endpoint() {
    echo "Testing stats endpoint..."

    # Note: Stats endpoint requires manual trigger or client connections
    if docker exec vless_mtproxy nc -z 127.0.0.1 8888; then
        echo "  ✓ Stats endpoint listening"
    else
        echo "  ⚠ Stats endpoint not accessible (may require client connections)"
    fi
}

# Run all tests
test_generate_secret
test_container_connectivity
test_stats_endpoint
```

---

## 9. Appendix: Code Examples

### 9.1 Complete mtproxy Management CLI

```bash
#!/bin/bash
# /opt/vless/scripts/mtproxy
# MTProxy management CLI (placeholder - full implementation in Phase 2)

set -euo pipefail

readonly INSTALL_ROOT="/opt/vless"
readonly CONFIG_DIR="${INSTALL_ROOT}/config/mtproxy"
readonly DATA_DIR="${INSTALL_ROOT}/data/mtproxy"

# Colors
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

print_error() {
    echo -e "${COLOR_RED}✗ ERROR: $1${COLOR_RESET}" >&2
}

print_success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}"
}

print_message() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

cmd_stats() {
    echo "MTProxy Statistics:"
    echo ""

    # Container status
    if docker ps --filter "name=vless_mtproxy" --format '{{.Names}}' | grep -q "vless_mtproxy"; then
        print_success "Container: Running"

        # Health status
        health=$(docker inspect --format='{{.State.Health.Status}}' vless_mtproxy 2>/dev/null || echo "unknown")
        echo "  Health: $health"
    else
        print_error "Container: Not running"
        return 1
    fi

    # Port status
    echo ""
    echo "Port Status:"
    if ss -tuln | grep -q ":8443 "; then
        print_success "Port 8443: Listening"
    else
        print_error "Port 8443: Not listening"
    fi

    # TODO: Parse actual stats from /stats endpoint (requires client connections)
    echo ""
    echo "Note: Detailed statistics require active client connections"
}

cmd_show_config() {
    local username="${1:-}"

    if [[ -f "${DATA_DIR}/client_config.txt" ]]; then
        cat "${DATA_DIR}/client_config.txt"
    else
        print_error "Client configuration not found"
        return 1
    fi
}

cmd_help() {
    cat <<EOF
MTProxy Management CLI v6.0

Usage: mtproxy <command> [arguments]

Commands:
  stats               Show MTProxy statistics
  show-config         Show client configuration
  help                Show this help message

v6.1 Commands (Coming Soon):
  add-user <username>           Add user with unique secret
  remove-user <username>        Remove user
  list-users                    List all users
  set-promoted-channel <tag>    Set promoted channel
EOF
}

# Main command dispatcher
case "${1:-help}" in
    stats)
        cmd_stats
        ;;
    show-config)
        cmd_show_config "${2:-}"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        cmd_help
        exit 1
        ;;
esac
```

### 9.2 Uninstall Script

```bash
#!/bin/bash
# /opt/vless/scripts/mtproxy-uninstall
# Complete MTProxy removal

set -euo pipefail

readonly INSTALL_ROOT="/opt/vless"
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

print_message() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠ $1${COLOR_RESET}"
}

print_success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${COLOR_RED}✗ This script must be run as root${COLOR_RESET}" >&2
    exit 2
fi

echo ""
print_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message "  MTPROXY UNINSTALLATION"
print_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_warning "This will remove:"
echo "  - MTProxy Docker container and image"
echo "  - MTProxy configuration files"
echo "  - MTProxy logs"
echo "  - UFW firewall rules"
echo ""

read -rp "Are you sure you want to uninstall MTProxy? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Uninstall cancelled"
    exit 0
fi

echo ""
print_message "[1/6] Stopping MTProxy container..."
docker stop vless_mtproxy >/dev/null 2>&1 || print_warning "Container not running"
print_success "Container stopped"

print_message "[2/6] Removing MTProxy container..."
docker rm vless_mtproxy >/dev/null 2>&1 || print_warning "Container not found"
print_success "Container removed"

print_message "[3/6] Removing MTProxy image..."
docker rmi alpine:latest >/dev/null 2>&1 || print_warning "Image not removed (may be used by other containers)"
print_success "Image cleanup attempted"

print_message "[4/6] Removing MTProxy files..."
rm -rf "${INSTALL_ROOT}/config/mtproxy"
rm -rf "${INSTALL_ROOT}/data/mtproxy"
rm -rf "${INSTALL_ROOT}/logs/mtproxy"
rm -rf "${INSTALL_ROOT}/docker/mtproxy"
print_success "Files removed"

print_message "[5/6] Removing UFW rules..."
if command -v ufw &> /dev/null; then
    ufw delete allow 8443/tcp >/dev/null 2>&1 || print_warning "UFW rule not found"
    print_success "Firewall rules removed"
else
    print_warning "UFW not installed, skipping"
fi

print_message "[6/6] Cleaning docker-compose.yml..."
# TODO: Remove MTProxy service from docker-compose.yml
print_warning "Manual cleanup required: Remove MTProxy service from ${INSTALL_ROOT}/docker-compose.yml"

echo ""
print_success "MTProxy uninstallation complete!"
echo ""
```

---

## Document Status

**Created:** 2025-11-08
**Last Updated:** 2025-11-08
**Version:** 1.0 (Initial draft)
**Status:** 📝 DRAFT (Ready for review)

**Next Steps:**
1. ⏳ Review by project stakeholders
2. ⏳ Code review of heredoc patterns
3. ⏳ Integration testing with install.sh
4. ⏳ Update Implementation Phases (00_mtproxy_integration_plan.md)

**Related Work:**
- [ ] Implement lib/mtproxy_manager.sh module
- [ ] Update install.sh with opt-in prompt
- [ ] Create mtproxy-setup script
- [ ] Generate MTProxy Dockerfile
- [ ] Test heredoc configuration generation

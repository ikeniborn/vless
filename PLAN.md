# VLESS REALITY Deployment System - Implementation Plan

**Project:** VLESS + Reality VPN Deployment System with Integrated Proxy Support
**Version:** 4.0
**Status:** Ready for Implementation (Updated with Proxy Integration)
**Estimated Duration:** 6 weeks (234 hours)
**Date:** 2025-10-04
**Based on PRD:** v1.1 (2025-10-03)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Timeline & Milestones](#timeline--milestones)
3. [Epic Breakdown](#epic-breakdown)
4. [Detailed Task List](#detailed-task-list)
5. [User-Specific Decisions](#user-specific-decisions)
6. [Critical Risks & Mitigation](#critical-risks--mitigation)
7. [Testing Strategy](#testing-strategy)
8. [Success Criteria](#success-criteria)
9. [Quick Start Guide](#quick-start-guide)

---

## Project Overview

### Vision
Production-grade CLI-based VLESS+Reality VPN deployment system with integrated SOCKS5/HTTP proxy support, enabling non-technical users to install, configure, and manage Reality protocol servers with application-level proxying in under 5 minutes.

### Technology Stack
- **VPN Protocol:** VLESS + Reality (Xray-core 24.11.30)
- **Proxy Protocols:** SOCKS5 (port 1080), HTTP (port 8118)
- **Containerization:** Docker + Docker Compose (bridge network)
- **Reverse Proxy:** Nginx (fake-site masquerading)
- **Scripting:** Bash 4.0+
- **Tools:** jq, qrencode, ufw, flock, openssl
- **Testing:** bats, shellcheck

### Target Environment
- **Platforms:** Ubuntu 20.04+, Debian 10+
- **Scale:** 10-50 concurrent users
- **Installation Path:** `/opt/vless` (hard-coded)
- **Storage:** JSON files

---

## Timeline & Milestones

### Week 1-2: Core Infrastructure (72 hours)
**Epics:** EPIC-1, EPIC-2, EPIC-5

**Deliverables:**
- Interactive installation script with dependency auto-install
- Docker bridge network configuration (vless_reality_net)
- UFW firewall integration with Docker forwarding
- Docker Compose orchestration

**Milestone:** Complete installation on clean Ubuntu 22.04 VM

---

### Week 2-3: Protocol Implementation (32 hours)
**Epics:** EPIC-3, EPIC-4

**Deliverables:**
- Xray-core Reality configuration (config.json)
- X25519 key pair generation
- Nginx fake-site reverse proxy
- TLS 1.3 parameter tuning

**Milestone:** Successful client connection with Reality protocol

---

### Week 3: User Management (32 hours)
**Epics:** EPIC-6, EPIC-7

**Deliverables:**
- User creation with UUID + proxy password generation
- QR code generation (400x400px PNG + ANSI terminal)
- VLESS URI construction
- User removal with cleanup

**Milestone:** Add/remove users via CLI in <6 seconds

---

### Week 4: Operations (24 hours)
**Epics:** EPIC-8, EPIC-9

**Deliverables:**
- Service start/stop/restart commands
- Update mechanism (preserve subnet/port)
- Log filtering (ERROR, WARN, INFO levels)
- Security hardening

**Milestone:** Full operational control via CLI

---

### Week 5: Proxy Server Integration (40 hours) - **NEW**
**Epic:** EPIC-11

**Deliverables:**
- SOCKS5 proxy inbound (127.0.0.1:1080, password auth)
- HTTP proxy inbound (127.0.0.1:8118, password auth)
- Proxy password generation and management
- 5 additional client config formats (SOCKS5, HTTP, VSCode, Docker, Bash)
- Proxy CLI commands (vless-user show --proxy, proxy-reset)

**Milestone:** All 8 config files generated per user, proxies accessible through VPN tunnel

---

### Week 6: Testing & Release (24 hours)
**Epic:** EPIC-10

**Deliverables:**
- Unit tests (bats framework, 80% coverage)
- Integration tests on 3 VPS environments
- Performance testing (50 concurrent users)
- Proxy functionality tests (SOCKS5/HTTP accessibility, authentication)
- Security audit (nmap, wireshark, proxy port isolation)

**Milestone:** ≥85% weighted success score achieved

---

## Epic Breakdown

### EPIC-1: Core Installation System (24 hours) - **CRITICAL**
**Priority:** Critical | **Complexity:** High

**Tasks:**
1. TASK-1.1: Installation script entry point (2h) ✅ COMPLETE (2025-10-02)
2. TASK-1.2: OS detection and validation (3h) ✅ COMPLETE (2025-10-02)
3. TASK-1.3: Dependency auto-installation (4h) ✅ COMPLETE (2025-10-02)
4. TASK-1.4: Old installation detection (4h) ✅ COMPLETE (2025-10-02)
5. TASK-1.5: Interactive parameter collection (3h) ✅ COMPLETE (2025-10-02)
6. TASK-1.6: Sudoers configuration display (1h) ✅ COMPLETE (2025-10-02)
7. TASK-1.7: Installation orchestration (5h) ✅ COMPLETE (2025-10-02)
8. TASK-1.8: Post-installation verification (2h) ✅ COMPLETE (2025-10-02)

**Dependencies:** None (starting point)

---

### EPIC-2: Network Configuration (32 hours) - **CRITICAL**
**Priority:** Critical | **Complexity:** Very High

**Tasks:**
1. TASK-2.1: Subnet/port generation (3h) ✅ COMPLETE (2025-10-02)
2. TASK-2.2: Docker bridge network creation (4h) ✅ COMPLETE (2025-10-02)
3. TASK-2.3: UFW basic rules (6h) ✅ COMPLETE (2025-10-02)
4. TASK-2.4: **UFW Docker forwarding** (10h) ✅ COMPLETE (2025-10-02)
5. TASK-2.5: Port forwarding rules (4h) ✅ COMPLETE (2025-10-02)
6. TASK-2.6: Network validation (3h)
7. TASK-2.7: Network persistence (2h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-1 complete

---

### EPIC-3: Reality Protocol Configuration (24 hours) - **CRITICAL** - **UPDATED**
**Priority:** Critical | **Complexity:** High

**Tasks:**
1. TASK-3.1: X25519 key pair generation (4h) ✅ COMPLETE (2025-10-02)
2. TASK-3.2: Short-ID generation (2h) ✅ COMPLETE (2025-10-02)
3. TASK-3.3: **Xray config.json creation with 3 inbounds** (12h) ⚠️ **UPDATED FOR PROXY**
   - VLESS Reality inbound (port 443)
   - SOCKS5 proxy inbound (127.0.0.1:1080)
   - HTTP proxy inbound (127.0.0.1:8118)
4. TASK-3.4: Reality protocol parameters (4h) ✅ COMPLETE (2025-10-02)
5. TASK-3.5: Configuration validation (2h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-1, EPIC-2 complete
**Implementation:** All tasks implemented in lib/orchestrator.sh and lib/verification.sh
**Update Required:** TASK-3.3 needs modification to include proxy inbounds (see EPIC-11)

---

### EPIC-4: Fake-site Configuration (12 hours)
**Priority:** High | **Complexity:** Medium

**Tasks:**
1. TASK-4.1: Nginx reverse proxy setup (4h) ✅ COMPLETE (2025-10-02)
2. TASK-4.2: Target site selection (2h) ✅ COMPLETE (2025-10-02)
3. TASK-4.3: SNI configuration (3h) ✅ COMPLETE (2025-10-02)
4. TASK-4.4: Caching strategy (1h cache for 200 OK) (2h) ✅ COMPLETE (2025-10-02)
5. TASK-4.5: Nginx testing (1h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-3 complete
**Implementation:** All tasks implemented in lib/orchestrator.sh (create_nginx_config)

---

### EPIC-5: Docker Orchestration (8 hours)
**Priority:** Critical | **Complexity:** Medium

**Tasks:**
1. TASK-5.1: docker-compose.yml template (3h) ✅ COMPLETE (2025-10-02)
2. TASK-5.2: Volume mounts configuration (2h) ✅ COMPLETE (2025-10-02)
3. TASK-5.3: Container networking (2h) ✅ COMPLETE (2025-10-02)
4. TASK-5.4: Compose validation (1h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-2, EPIC-3 complete
**Implementation:** All tasks implemented in lib/orchestrator.sh (create_docker_compose, deploy_containers)
**Security:** Hardened containers (cap_drop ALL, no-new-privileges, read_only)

---

### EPIC-6: User Management (26 hours) - **CRITICAL** - **UPDATED**
**Priority:** Critical | **Complexity:** High

**Tasks:**
1. TASK-6.1: User creation workflow with proxy password (8h) ⚠️ **UPDATED FOR PROXY**
   - UUID generation
   - shortId generation
   - **Proxy password generation (openssl rand -base64 16)**
   - Update 3 inbounds (VLESS + SOCKS5 + HTTP)
2. TASK-6.2: UUID generation (2h) ✅ COMPLETE (2025-10-02)
3. TASK-6.3: JSON storage with flock + proxy_password field (6h) ⚠️ **UPDATED**
4. TASK-6.4: Xray config update for 3 inbounds (6h) ⚠️ **UPDATED**
5. TASK-6.5: User removal (4h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-3, EPIC-5, EPIC-11 complete
**Implementation:** lib/user_management.sh (estimated ~900 lines with proxy support, 22+ functions)
**Update Required:** Add proxy_password generation, update users.json schema to v1.1

---

### EPIC-7: Client Configuration Export (20 hours) - **UPDATED**
**Priority:** High | **Complexity:** Medium

**Tasks:**
1. TASK-7.1: VLESS URI construction (3h) ✅ COMPLETE (2025-10-02)
2. TASK-7.2: QR code generation (400x400px PNG + ANSI) (4h) ✅ COMPLETE (2025-10-02)
3. TASK-7.3: Connection info display (2h) ✅ COMPLETE (2025-10-02)
4. TASK-7.4: Export VLESS configs (3 files) (2h) ✅ COMPLETE (2025-10-02)
5. TASK-7.5: **Export proxy configs (5 additional files)** (6h) ⚠️ **NEW**
   - socks5_config.txt (connection string)
   - http_config.txt (connection string)
   - vscode_settings.json (VSCode proxy config)
   - docker_daemon.json (Docker proxy config)
   - bash_exports.sh (environment variables)
6. TASK-7.6: Validation (all 8 files) (2h) ⚠️ **UPDATED**
7. TASK-7.7: Display proxy credentials in CLI (1h) ⚠️ **NEW**

**Dependencies:** EPIC-6, EPIC-11 complete
**Implementation:** lib/qr_generator.sh (estimated ~800 lines with proxy export, 18+ functions)
**Total Files Per User:** 8 (3 VLESS + 5 proxy configs)

---

### EPIC-8: Service Operations (16 hours)
**Priority:** High | **Complexity:** Medium

**Tasks:**
1. TASK-8.1: Start/stop/restart commands (4h) ✅ COMPLETE (2025-10-02)
2. TASK-8.2: Status display (3h) ✅ COMPLETE (2025-10-02)
3. TASK-8.3: Update mechanism (preserve subnet/port) (6h) ✅ COMPLETE (2025-10-02)
4. TASK-8.4: Log display with filtering (3h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-5 complete
**Implementation:** lib/service_operations.sh (857 lines, 33 functions)

---

### EPIC-9: Security & Hardening (8 hours)
**Priority:** High | **Complexity:** Medium

**Tasks:**
1. TASK-9.1: File permissions (2h) ✅ COMPLETE (2025-10-02)
2. TASK-9.2: Docker security options (2h) ✅ COMPLETE (2025-10-02)
3. TASK-9.3: UFW hardening (2h) ✅ COMPLETE (2025-10-02)
4. TASK-9.4: Security audit (2h) ✅ COMPLETE (2025-10-02)

**Dependencies:** EPIC-2, EPIC-5 complete
**Implementation:** lib/security_hardening.sh (711 lines, 17 functions)

---

### EPIC-10: Testing & Documentation (24 hours)
**Priority:** Critical | **Complexity:** High

**Tasks:**
1. TASK-10.1: Unit test framework setup (3h) ✅ COMPLETE (2025-10-02)
2. TASK-10.2: Unit tests for core functions (8h) ✅ COMPLETE (2025-10-02)
3. TASK-10.3: Integration tests (6h) ✅ COMPLETE (2025-10-02)
4. TASK-10.4: Performance tests (4h) ✅ COMPLETE (2025-10-02)
5. TASK-10.5: Documentation (3h) ✅ COMPLETE (2025-10-02)

**Dependencies:** All epics complete
**Implementation:** tests/ directory with bats framework, README.md, comprehensive documentation

---

### EPIC-11: Proxy Server Integration (40 hours) - **NEW** - **CRITICAL**
**Priority:** Critical | **Complexity:** High

**Tasks:**
1. TASK-11.1: SOCKS5 proxy inbound configuration (8h)
2. TASK-11.2: HTTP proxy inbound configuration (8h)
3. TASK-11.3: Proxy password generation and storage (4h)
4. TASK-11.4: Proxy configuration export (8 files per user) (8h)
5. TASK-11.5: Proxy CLI commands (show --proxy, proxy-reset) (6h)
6. TASK-11.6: Update Xray config with 3 inbounds (4h)
7. TASK-11.7: Proxy functionality testing (2h)

**Dependencies:** EPIC-3 (Xray configuration), EPIC-6 (User management) complete

**Implementation:**
- lib/proxy_management.sh (new file, ~600 lines estimated)
- Update lib/user_management.sh (add proxy_password generation)
- Update lib/qr_generator.sh (add proxy config export)

**New Requirements from PRD v1.1:**
- FR-022: SOCKS5 Proxy Inbound (127.0.0.1:1080, password auth, TCP only)
- FR-023: HTTP Proxy Inbound (127.0.0.1:8118, password auth, HTTP/HTTPS)
- FR-024: Proxy Configuration Management (8 config files per user)

**Security Considerations:**
- Localhost-only binding (127.0.0.1) - NOT exposed to internet
- Individual password per user (auto-generated 16 chars)
- Accessible only through established VPN tunnel
- UFW does NOT expose ports 1080/8118

---

## Detailed Task List

### Week 1: Installation & Networking

#### TASK-1.1: Installation Script Entry Point (2h)
**File:** `/opt/vless/install.sh`

```bash
#!/bin/bash
set -euo pipefail

# Main entry point
main() {
    check_root
    detect_os
    check_dependencies
    detect_old_installation
    collect_parameters
    install_system
    verify_installation
}

main "$@"
```

**Acceptance Criteria:**
- Script accepts no arguments (interactive mode)
- Exits with error code if not run as root
- All functions called in correct order

---

#### TASK-1.3: Dependency Auto-Installation (4h) ⚠️ **USER DECISION Q-001**
**Implementation:** Auto-install all missing dependencies

```bash
install_dependencies() {
    local deps=("docker.io" "docker-compose" "ufw" "jq" "qrencode")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            echo "Installing $dep..."
            apt-get update -qq
            apt-get install -y "$dep"
        fi
    done

    # Docker special handling
    if ! systemctl is-active --quiet docker; then
        systemctl enable --now docker
    fi
}
```

**Acceptance Criteria:**
- Installs Docker if missing via apt
- Installs docker-compose, ufw, jq, qrencode
- Validates installation after each package
- No user prompts (fully automated)

---

#### TASK-2.4: UFW Docker Forwarding Integration (10h) ⚠️ **HIGHEST RISK**
**File:** `/etc/ufw/after.rules`

```bash
configure_ufw_docker() {
    local subnet="$1"
    local backup="/etc/ufw/after.rules.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup original
    cp /etc/ufw/after.rules "$backup"

    # Add Docker forwarding rules
    cat >> /etc/ufw/after.rules <<EOF

# BEGIN VLESS REALITY RULES
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $subnet -j MASQUERADE
COMMIT
# END VLESS REALITY RULES
EOF

    # Reload UFW
    ufw reload

    # Validate container internet access
    docker run --rm --network vless_reality_net alpine ping -c 3 8.8.8.8 || {
        echo "ERROR: Container cannot access internet"
        mv "$backup" /etc/ufw/after.rules
        ufw reload
        return 1
    }
}
```

**Testing:**
1. Test on Ubuntu 20.04, 22.04, Debian 11
2. Validate with `ping 8.8.8.8` from container
3. Check with `iptables -t nat -L` for MASQUERADE rule

**Rollback Plan:**
- Automatic restore from backup if validation fails
- Manual cleanup: remove VLESS REALITY RULES section

---

#### TASK-3.3: Xray config.json Creation (8h) ⚠️ **HIGH RISK**
**File:** `/opt/vless/config/xray_config.json`

```bash
generate_xray_config() {
    local private_key="$1"
    local short_id="$2"
    local dest_server="$3"
    local dest_port="$4"
    local listen_port="$5"

    cat > /opt/vless/config/xray_config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": $listen_port,
    "protocol": "vless",
    "settings": {
      "clients": [],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$dest_server:$dest_port",
        "xver": 0,
        "serverNames": ["$dest_server"],
        "privateKey": "$private_key",
        "shortIds": ["$short_id"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }]
}
EOF

    # Validate with xray
    xray -test -config=/opt/vless/config/xray_config.json || return 1
}
```

**Validation:**
- Must follow XTLS/Xray-examples exactly
- Test with `xray -test -config=...`
- Wireshark TLS handshake inspection (must show dest_server SNI)

---

### Week 3: User Management

#### TASK-6.1: User Creation Workflow (6h) ⚠️ **USER DECISION Q-004**
**Implementation:** Single user creation per invocation

```bash
create_user() {
    local username="$1"
    local uuid=$(uuidgen)
    local user_dir="/opt/vless/data/clients/$username"

    # Validate username
    [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        echo "Invalid username format"
        return 1
    }

    # Check if exists
    if jq -e ".users[] | select(.username == \"$username\")" /opt/vless/data/users.json &>/dev/null; then
        echo "User already exists"
        return 1
    fi

    # Create user directory
    mkdir -p "$user_dir"
    chmod 700 "$user_dir"

    # Add to users.json with file locking
    (
        flock -x 200
        jq ".users += [{\"username\": \"$username\", \"uuid\": \"$uuid\", \"created\": \"$(date -Iseconds)\"}]" \
            /opt/vless/data/users.json > /tmp/users.json.tmp
        mv /tmp/users.json.tmp /opt/vless/data/users.json
    ) 200>/var/lock/vless_users.lock

    # Update Xray config
    update_xray_config "$uuid"

    # Generate QR codes
    generate_qr_code "$username" "$uuid"

    echo "User created: $username"
}
```

**Acceptance Criteria:**
- Single user per invocation (no batch mode)
- Username validation (alphanumeric + underscore/dash)
- UUID uniqueness check
- Atomic JSON update with flock
- Time: <5 seconds

---

#### TASK-7.2: QR Code Generation (4h) ⚠️ **USER DECISION Q-007**
**Implementation:** Both PNG (400x400px) and ANSI terminal variants

```bash
generate_qr_code() {
    local username="$1"
    local uuid="$2"
    local server_ip=$(curl -s ifconfig.me)
    local server_port=$(jq -r '.inbounds[0].port' /opt/vless/config/xray_config.json)
    local public_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' /opt/vless/config/xray_config.json)
    local short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /opt/vless/config/xray_config.json)
    local server_name=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /opt/vless/config/xray_config.json)

    # Construct VLESS URI
    local uri="vless://${uuid}@${server_ip}:${server_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#${username}"

    local output_dir="/opt/vless/data/clients/$username"

    # PNG: 400x400 pixels (qrencode -s 10 = 40 modules * 10 pixels/module)
    qrencode -t PNG -s 10 -o "$output_dir/qrcode.png" <<< "$uri"

    # ANSI terminal display
    echo "QR Code for $username:"
    qrencode -t ANSIUTF8 <<< "$uri"

    echo ""
    echo "PNG saved to: $output_dir/qrcode.png"
    echo "URI: $uri"
}
```

**Acceptance Criteria:**
- PNG: 400x400 pixels (use `-s 10` flag)
- ANSI: Display in terminal with UTF-8 encoding
- Both variants generated for every user
- Saved to `/opt/vless/data/clients/<username>/qrcode.png`

---

### Week 4: Operations

#### TASK-8.3: Update Mechanism (6h) ⚠️ **USER DECISION Q-003**
**Implementation:** Preserve subnet and port on update

```bash
update_system() {
    local backup_dir="/opt/vless_backup_$(date +%Y%m%d_%H%M%S)"

    # Backup current installation
    cp -r /opt/vless "$backup_dir"

    # Read existing values
    local current_subnet=$(docker network inspect vless_reality_net -f '{{(index .IPAM.Config 0).Subnet}}')
    local current_port=$(jq -r '.inbounds[0].port' /opt/vless/config/xray_config.json)

    # Pull latest Docker image
    docker-compose -f /opt/vless/docker-compose.yml pull

    # Recreate containers (preserve network and port)
    docker-compose -f /opt/vless/docker-compose.yml up -d --force-recreate

    # Validate
    if ! docker ps | grep -q vless_xray; then
        echo "Update failed, restoring backup..."
        rm -rf /opt/vless
        mv "$backup_dir" /opt/vless
        docker-compose -f /opt/vless/docker-compose.yml up -d
        return 1
    fi

    echo "Update successful"
    echo "Subnet preserved: $current_subnet"
    echo "Port preserved: $current_port"
}
```

**Acceptance Criteria:**
- Subnet preserved from existing docker network
- Port preserved from existing xray_config.json
- users.json preserved (no data loss)
- Automatic rollback on failure

---

#### TASK-8.4: Log Display with Filtering (3h) ⚠️ **USER DECISION Q-006**
**Implementation:** Support filtering by log level

```bash
show_logs() {
    local level="${1:-all}"  # all, error, warn, info
    local lines="${2:-50}"

    case "$level" in
        error)
            docker-compose -f /opt/vless/docker-compose.yml logs --tail="$lines" | grep -E '\[Error\]|\[ERROR\]'
            ;;
        warn)
            docker-compose -f /opt/vless/docker-compose.yml logs --tail="$lines" | grep -E '\[Warning\]|\[WARN\]'
            ;;
        info)
            docker-compose -f /opt/vless/docker-compose.yml logs --tail="$lines" | grep -E '\[Info\]|\[INFO\]'
            ;;
        all)
            docker-compose -f /opt/vless/docker-compose.yml logs --tail="$lines"
            ;;
        *)
            echo "Invalid log level: $level"
            echo "Usage: vless logs [error|warn|info|all] [lines]"
            return 1
            ;;
    esac
}
```

**Usage:**
```bash
vless logs error      # Show only errors
vless logs warn 100   # Show last 100 warnings
vless logs all        # Show all logs
```

---

### Week 5: Proxy Server Integration

#### TASK-11.1: SOCKS5 Proxy Inbound Configuration (8h) ⚠️ **NEW**
**Implementation:** Add SOCKS5 inbound to Xray config.json

```bash
generate_socks5_inbound() {
    local username="$1"
    local password="$2"

    cat >> /tmp/inbound_socks5.json <<EOF
{
  "tag": "socks5-proxy",
  "listen": "127.0.0.1",
  "port": 1080,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [
      {
        "user": "$username",
        "pass": "$password"
      }
    ],
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
```

**Acceptance Criteria:**
- Listens on 127.0.0.1:1080 ONLY (not 0.0.0.0)
- Password authentication required
- UDP disabled (TCP only per FR-022)
- Port NOT mapped in docker-compose.yml
- Accessible only from inside container (through VPN tunnel)

**Validation:**
```bash
# Inside container test
docker exec vless-reality netstat -tuln | grep 1080
# Expected: 127.0.0.1:1080 LISTEN

# Outside container test (should FAIL)
nc -zv SERVER_IP 1080
# Expected: Connection refused (port not exposed)
```

---

#### TASK-11.2: HTTP Proxy Inbound Configuration (8h) ⚠️ **NEW**
**Implementation:** Add HTTP proxy inbound to Xray config.json

```bash
generate_http_inbound() {
    local username="$1"
    local password="$2"

    cat >> /tmp/inbound_http.json <<EOF
{
  "tag": "http-proxy",
  "listen": "127.0.0.1",
  "port": 8118,
  "protocol": "http",
  "settings": {
    "accounts": [
      {
        "user": "$username",
        "pass": "$password"
      }
    ],
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
```

**Acceptance Criteria:**
- Listens on 127.0.0.1:8118 ONLY
- Password authentication required
- Supports HTTP and HTTPS proxying
- Port NOT mapped in docker-compose.yml

---

#### TASK-11.3: Proxy Password Generation (4h) ⚠️ **NEW**
**Implementation:** Auto-generate 16-character password per user

```bash
generate_proxy_password() {
    # Generate 16-character base64 password
    openssl rand -base64 16 | tr -d '\n'
}

# Usage in user creation
create_user_with_proxy() {
    local username="$1"
    local uuid=$(uuidgen)
    local shortId=$(openssl rand -hex 8)
    local proxy_password=$(generate_proxy_password)

    # Store in users.json
    jq ".users += [{
        \"username\": \"$username\",
        \"uuid\": \"$uuid\",
        \"shortId\": \"$shortId\",
        \"proxy_password\": \"$proxy_password\",
        \"created\": \"$(date -Iseconds)\",
        \"enabled\": true
    }]" /opt/vless/data/users.json > /tmp/users.json.tmp

    mv /tmp/users.json.tmp /opt/vless/data/users.json
}
```

**Acceptance Criteria:**
- Password is 16 characters (base64 encoded)
- Unique per user
- Stored in users.json with 600 permissions
- Same password used for both SOCKS5 and HTTP

---

#### TASK-11.4: Proxy Configuration Export (8h) ⚠️ **NEW**
**Implementation:** Generate 5 additional config files per user

**File 1: socks5_config.txt**
```bash
echo "socks5://${username}:${proxy_password}@127.0.0.1:1080" \
    > "/opt/vless/data/clients/${username}/socks5_config.txt"
```

**File 2: http_config.txt**
```bash
echo "http://${username}:${proxy_password}@127.0.0.1:8118" \
    > "/opt/vless/data/clients/${username}/http_config.txt"
```

**File 3: vscode_settings.json**
```json
{
  "http.proxy": "socks5://username:password@127.0.0.1:1080",
  "http.proxyStrictSSL": false
}
```

**File 4: docker_daemon.json**
```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://username:password@127.0.0.1:8118",
      "httpsProxy": "http://username:password@127.0.0.1:8118"
    }
  }
}
```

**File 5: bash_exports.sh**
```bash
export http_proxy="http://username:password@127.0.0.1:8118"
export https_proxy="http://username:password@127.0.0.1:8118"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
```

**Acceptance Criteria:**
- All 5 files created in `/opt/vless/data/clients/{username}/`
- Files have 600 permissions
- Passwords embedded correctly
- Total 8 files per user (3 VLESS + 5 proxy)

---

#### TASK-11.5: Proxy CLI Commands (6h) ⚠️ **NEW**
**Implementation:** Add proxy management commands

**Command 1: vless-user show --proxy**
```bash
vless_user_show_proxy() {
    local username="$1"
    local proxy_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" /opt/vless/data/users.json)

    echo "PROXY CREDENTIALS FOR: $username"
    echo "======================================="
    echo "SOCKS5: socks5://${username}:${proxy_password}@127.0.0.1:1080"
    echo "HTTP:   http://${username}:${proxy_password}@127.0.0.1:8118"
    echo ""
    echo "Config files: /opt/vless/data/clients/${username}/"
}
```

**Command 2: vless-user proxy-reset**
```bash
vless_user_proxy_reset() {
    local username="$1"
    local new_password=$(generate_proxy_password)

    # Update users.json
    jq ".users |= map(if .username == \"$username\" then .proxy_password = \"$new_password\" else . end)" \
        /opt/vless/data/users.json > /tmp/users.json.tmp
    mv /tmp/users.json.tmp /opt/vless/data/users.json

    # Update Xray config (SOCKS5 and HTTP inbounds)
    update_proxy_accounts_in_config "$username" "$new_password"

    # Reload Xray
    docker-compose -f /opt/vless/docker-compose.yml restart xray

    # Regenerate proxy config files
    regenerate_proxy_configs "$username" "$new_password"

    echo "Proxy password reset for: $username"
    echo "New password: $new_password"
}
```

**Acceptance Criteria:**
- `vless-user show <user> --proxy` displays proxy credentials
- `vless-user proxy-reset <user>` regenerates password
- Password updated in users.json, config.json, all 5 proxy config files
- Xray reloads without downtime

---

#### TASK-11.6: Update Xray Config with 3 Inbounds (4h) ⚠️ **NEW**
**Implementation:** Merge VLESS + SOCKS5 + HTTP inbounds

```bash
generate_complete_xray_config() {
    cat > /opt/vless/config/xray_config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [{"dest": "nginx:8080"}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "google.com:443",
          "xver": 0,
          "serverNames": ["google.com", "www.google.com"],
          "privateKey": "PRIVATE_KEY",
          "shortIds": [""]
        }
      }
    },
    {
      "tag": "socks5-proxy",
      "listen": "127.0.0.1",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [],
        "udp": false
      }
    },
    {
      "tag": "http-proxy",
      "listen": "127.0.0.1",
      "port": 8118,
      "protocol": "http",
      "settings": {
        "accounts": [],
        "allowTransparent": false
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"}
  ]
}
EOF
}
```

**Acceptance Criteria:**
- All 3 inbounds present in config.json
- Validates with `xray -test -config=...`
- VLESS on 0.0.0.0:443, SOCKS5/HTTP on 127.0.0.1

---

#### TASK-11.7: Proxy Functionality Testing (2h) ⚠️ **NEW**
**Implementation:** Automated tests for proxy functionality

**Test 1: SOCKS5 Accessibility**
```bash
# Through VPN tunnel
curl --socks5 username:password@127.0.0.1:1080 https://ifconfig.me
# Expected: Server IP (proxied through VPN)

# Direct access (should FAIL)
curl --socks5 username:password@SERVER_IP:1080 https://ifconfig.me
# Expected: Connection refused
```

**Test 2: HTTP Accessibility**
```bash
# Through VPN tunnel
curl --proxy http://username:password@127.0.0.1:8118 https://ifconfig.me
# Expected: Server IP

# Direct access (should FAIL)
curl --proxy http://username:password@SERVER_IP:8118 https://ifconfig.me
# Expected: Connection refused
```

**Test 3: Authentication**
```bash
# Without credentials (should FAIL)
curl --socks5 127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication required

# Wrong password (should FAIL)
curl --socks5 username:wrongpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication failed
```

**Acceptance Criteria:**
- SOCKS5/HTTP accessible through VPN tunnel
- NOT accessible from external network
- Authentication required and enforced
- All test scripts automated in tests/integration/

---

## User-Specific Decisions

All 8 clarification questions have been answered and integrated:

| ID | Question | Decision | Implementation |
|----|----------|----------|----------------|
| Q-001 | Dependency installation | **Auto-install all** | TASK-1.3: apt-get install for Docker, docker-compose, UFW, jq, qrencode |
| Q-002 | Sudoers configuration | **Manual step** | TASK-1.6: Display instructions, do not modify /etc/sudoers |
| Q-003 | Update behavior | **Preserve subnet/port** | TASK-8.3: Read from docker network and xray_config.json |
| Q-004 | User creation mode | **Single user** per invocation | TASK-6.1: No batch mode, one user at a time |
| Q-005 | Caching strategy | **Minimal (1h for 200 OK)** | TASK-4.4: `proxy_cache_valid 200 1h;` |
| Q-006 | Log filtering | **Support filtering** | TASK-8.4: --level flag (error/warn/info/all) |
| Q-007 | QR code variants | **Both (400x400px PNG + ANSI)** | TASK-7.2: qrencode -s 10 (PNG) + qrencode -t ANSIUTF8 |
| Q-008 | Testing environment | **Local first, then VPS** | Week 5: Local VM → Ubuntu 20.04 → 22.04 → Debian 11 |

---

## Critical Risks & Mitigation

### RISK-2.4: UFW+Docker Integration (Very High Severity)
**Problem:** UFW blocks all VPN traffic, service becomes unusable

**Mitigation:**
1. **Extensive Testing:** Ubuntu 20.04, 22.04, Debian 11
2. **Validation:** Container internet test (`ping 8.8.8.8` from container)
3. **Rollback:** Automatic backup restore if validation fails
4. **Documentation:** Manual configuration steps as fallback

**Detection:**
```bash
# Test command
docker run --rm --network vless_reality_net alpine ping -c 3 8.8.8.8

# Expected: 3 packets transmitted, 3 received
# Failure: 100% packet loss
```

---

### RISK-3.3: Invalid Xray Configuration (High Severity)
**Problem:** Invalid config.json breaks Reality protocol, clients cannot connect

**Mitigation:**
1. **Follow XTLS/Xray-examples exactly** (no deviation)
2. **Config Validation:** `xray -test -config=...`
3. **TLS Inspection:** Wireshark handshake analysis (must show destination SNI)
4. **Client Testing:** V2RayN on Windows + Android

**Validation:**
```bash
# Validate config
xray -test -config=/opt/vless/config/xray_config.json

# Expected: Configuration OK
# Failure: Error message with line number
```

---

### RISK-1.4: Undetected Old Installations (Medium Severity)
**Problem:** Port conflicts, data loss from undetected old installations

**Mitigation:**
1. **Multi-Level Detection:** Docker containers, UFW rules, /opt/vless directory
2. **Mandatory Backup:** `/opt/vless_backup_$(date)` before cleanup
3. **User Confirmation:** Prompt before removing old data
4. **Manual Cleanup Script:** If auto-detection fails

**Detection:**
```bash
# Check Docker containers
docker ps -a | grep vless

# Check UFW rules
ufw status | grep 443

# Check directory
test -d /opt/vless && echo "Old installation found"
```

---

### RISK-11.1: Proxy Port Exposure (High Severity) - **NEW**
**Problem:** Proxy ports (1080, 8118) accidentally exposed to internet, allowing unauthorized access

**Mitigation:**
1. **Localhost Binding:** ALWAYS bind to 127.0.0.1, NEVER 0.0.0.0
2. **Docker Compose Validation:** Ensure ports NOT mapped in docker-compose.yml
3. **UFW Verification:** Confirm ports 1080/8118 NOT in ufw rules
4. **External Access Test:** Automated test from external host (must fail)
5. **Code Review:** Every proxy config change reviewed for binding address

**Detection:**
```bash
# Check Xray is binding to localhost only
docker exec vless-reality netstat -tuln | grep -E '(1080|8118)'
# Expected: 127.0.0.1:1080 and 127.0.0.1:8118 (NOT 0.0.0.0)

# Check ports not exposed in docker-compose
grep -E '(1080|8118)' /opt/vless/docker-compose.yml
# Expected: No port mappings (should return nothing)

# Test external access (from different machine)
nc -zv SERVER_IP 1080
nc -zv SERVER_IP 8118
# Expected: Connection refused (both should FAIL)
```

**Severity:** High - If exposed, attackers can use server as open proxy (bandwidth abuse, legal liability)

---

### RISK-11.2: Proxy Authentication Bypass (Medium Severity) - **NEW**
**Problem:** Proxy authentication not enforced, allowing unauthenticated access

**Mitigation:**
1. **Config Validation:** Verify "auth": "password" in SOCKS5 inbound
2. **Automated Testing:** Test connection without credentials (must fail)
3. **Wrong Password Test:** Test with incorrect credentials (must fail)
4. **Password Strength:** Use openssl rand -base64 16 (16-char minimum)

**Detection:**
```bash
# Test without credentials (should FAIL)
curl --socks5 127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication required error

# Test with wrong password (should FAIL)
curl --socks5 user:wrongpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication failed error

# Test with correct credentials (should SUCCEED)
curl --socks5 user:correctpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Server IP returned
```

---

## Testing Strategy

### Test-Driven Development (TDD)
Write tests before implementation for all critical functions.

**Framework:** bats (Bash Automated Testing System)

**Setup:**
```bash
# Install bats
npm install -g bats

# Create test structure
mkdir -p tests/{unit,integration,acceptance}
```

---

### Unit Tests (TASK-10.2)
**Target:** 80% code coverage

**Example:**
```bash
# tests/unit/test_os_detection.bats
@test "detect_os returns Ubuntu on Ubuntu 22.04" {
    run detect_os
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Ubuntu 22.04" ]]
}

@test "detect_os fails on unsupported OS" {
    # Mock /etc/os-release
    run detect_os
    [ "$status" -eq 1 ]
}
```

**Run:**
```bash
bats tests/unit/test_os_detection.bats
```

---

### Integration Tests (TASK-10.3)
**Scenarios:**
1. Fresh installation → User creation → Client connection
2. Update with existing users → Verify connectivity
3. User removal → Verify cleanup

**Example:**
```bash
# tests/integration/test_full_workflow.bats
@test "full workflow: install → add user → connect" {
    # Install
    run /opt/vless/install.sh
    [ "$status" -eq 0 ]

    # Add user
    run /opt/vless/vless add-user testuser
    [ "$status" -eq 0 ]

    # Verify Xray config updated
    grep -q "testuser" /opt/vless/config/xray_config.json

    # Test connection (requires client)
    # ... client connection test
}
```

---

### Performance Tests (TASK-10.4)
**Metrics:**
- Installation time: <5 minutes
- User creation: <5 seconds
- 50 concurrent connections: 99.5% uptime over 24h

**Tools:** Apache Bench, custom Bash timers

---

### Security Tests (TASK-10.5)
**Tests:**
1. **Port Scan:** `nmap -p- <server_ip>` (only configured port open)
2. **TLS Handshake:** Wireshark capture (verify Reality masquerading)
3. **DPI Test:** Deep packet inspection with tshark (no VLESS signature)
4. **File Permissions:** All /opt/vless files owned by root, 700 perms

---

## Success Criteria

### Weighted Scoring (Minimum: 85%) - **UPDATED FOR PROXY**

| Metric | Target | Weight | Measurement |
|--------|--------|--------|-------------|
| **Installation Time** | <5 min | 18% | Time from script start to "Installation Complete" |
| **User Creation Time** | <6 sec | 22% | UUID + proxy password gen → QR + proxy configs display |
| **Connection Reliability** | 99.5% uptime | 20% | 24h test with 10 clients |
| **Proxy Functionality** | 100% | 12% | SOCKS5/HTTP accessible through VPN, authentication enforced |
| **Security Compliance** | 0 critical vulns | 20% | nmap + wireshark + proxy port isolation |
| **Config Completeness** | 8 files per user | 8% | All VLESS + proxy configs generated |

**Calculation:**
```
Score = (Installation × 0.18) + (User Creation × 0.22) + (Reliability × 0.20) +
        (Proxy Functionality × 0.12) + (Security × 0.20) + (Config Completeness × 0.08)

Pass: Score ≥ 85%
```

**Proxy Functionality Tests:**
1. SOCKS5 accessible at 127.0.0.1:1080 through VPN tunnel
2. HTTP accessible at 127.0.0.1:8118 through VPN tunnel
3. Ports 1080/8118 NOT accessible from external network
4. Authentication required and enforced
5. VSCode, Docker, Bash integration configs valid

---

## Quick Start Guide

### Prerequisites
- Ubuntu 20.04+ or Debian 10+ VPS
- Root access
- Internet connection

### Installation (5 minutes)
```bash
# Clone repository (replace <repo_url> with actual Git URL)
git clone <repo_url>
cd vless

# Run installation (will create /opt/vless during installation)
sudo ./install.sh

# Follow interactive prompts:
# 1. Docker subnet (auto: 172.20.0.0/16)
# 2. Xray port (auto: 443)
# 3. Destination server (e.g., www.google.com)
# 4. Destination port (auto: 443)
```

### Create First User (<6 seconds with proxy support)
```bash
# Add user (creates VLESS + proxy configs)
sudo /opt/vless/vless add-user alice

# Output:
# User created: alice
# UUID: 12345678-1234-1234-1234-123456789012
# Proxy Password: Ab12Cd34Ef56Gh78
#
# [QR code displayed in terminal]
#
# VLESS Config saved to: /opt/vless/data/clients/alice/
# - vless_config.json
# - vless_uri.txt
# - qrcode.png
#
# Proxy Configs:
# - socks5_config.txt (socks5://alice:PASSWORD@127.0.0.1:1080)
# - http_config.txt (http://alice:PASSWORD@127.0.0.1:8118)
# - vscode_settings.json
# - docker_daemon.json
# - bash_exports.sh
```

### View Proxy Credentials
```bash
# Show proxy credentials
sudo vless-user show alice --proxy

# Output:
# PROXY CREDENTIALS FOR: alice
# =======================================
# SOCKS5: socks5://alice:Ab12Cd34Ef56Gh78@127.0.0.1:1080
# HTTP:   http://alice:Ab12Cd34Ef56Gh78@127.0.0.1:8118
#
# Config files: /opt/vless/data/clients/alice/

# Reset proxy password
sudo vless-user proxy-reset alice
```

### Manage Service
```bash
# Status (now shows proxy ports)
vless status
# VLESS Port:    443 (LISTENING)
# SOCKS5 Proxy:  127.0.0.1:1080 (ACTIVE)
# HTTP Proxy:    127.0.0.1:8118 (ACTIVE)

# Restart
vless restart

# View logs (errors only)
vless logs error

# Update system (preserve config + proxy passwords)
vless update
```

### Remove User
```bash
vless remove-user alice
```

---

## File Structure

**Note:** This is the structure AFTER installation. During development, files are in the project directory and copied to `/opt/vless/` by the orchestrator during installation.

```
/opt/vless/                 # Created during installation
├── vless                   # CLI management script (copied from project)
├── docker-compose.yml      # Docker orchestration
├── config/
│   ├── xray_config.json    # Xray Reality configuration
│   └── nginx.conf          # Nginx reverse proxy config
├── data/
│   ├── users.json          # User database (JSON) with proxy_password field
│   └── clients/
│       └── <username>/
│           ├── vless_config.json    # v2rayN/v2rayNG format
│           ├── vless_uri.txt        # VLESS URI
│           ├── qrcode.png           # 400x400px QR code
│           ├── socks5_config.txt    # SOCKS5 connection string
│           ├── http_config.txt      # HTTP proxy connection string
│           ├── vscode_settings.json # VSCode proxy config
│           ├── docker_daemon.json   # Docker proxy config
│           └── bash_exports.sh      # Bash environment variables
├── keys/
│   ├── private.key         # X25519 private key
│   └── public.key          # X25519 public key
├── logs/
│   └── xray.log            # Xray logs
├── scripts/                # Additional utility scripts
│   ├── backup.sh           # Backup utilities
│   └── maintenance.sh      # Maintenance tasks
├── docs/                   # Additional documentation
│   ├── api.md              # API documentation
│   └── troubleshooting.md  # Troubleshooting guide
└── tests/                  # Test files
    ├── unit/               # Unit tests
    └── integration/        # Integration tests
```

**Project Development Structure:**

During development (before installation), files are organized in the project repository:

```
/home/ikeniborn/Documents/Project/vless/  # Project root
├── install.sh              # Main installation script
├── PLAN.md                 # Implementation plan
├── PRD.md                  # Product requirements
├── lib/                    # Installation modules
│   ├── os_detection.sh     # OS detection
│   ├── dependencies.sh     # Dependency management
│   ├── old_install_detect.sh # Old installation detection
│   ├── interactive_params.sh # Parameter collection
│   ├── sudoers_info.sh     # Sudoers instructions
│   ├── orchestrator.sh     # Installation orchestration
│   ├── verification.sh     # Post-install verification
│   ├── user_management.sh  # User CRUD operations (updated for proxy)
│   ├── proxy_management.sh # Proxy server configuration (NEW)
│   ├── qr_generator.sh     # QR code and config export (updated for 8 files)
│   └── service_operations.sh # Service management (updated for proxy status)
├── docs/                   # Additional documentation
│   ├── OLD_INSTALL_DETECT_REPORT.md
│   ├── INTERACTIVE_PARAMS_REPORT.md
│   └── SUDOERS_INFO_REPORT.md
├── tests/                  # Test files
│   ├── unit/               # Unit tests (bats framework)
│   └── integration/        # Integration tests
├── scripts/                # Additional utility scripts
│   ├── dev-helpers/        # Development helpers
│   └── ci/                 # CI/CD scripts
└── requests/               # Task request templates
    └── request_implement.xml
```

---

## Next Steps

### Week 0: Pre-Development
- [ ] Set up Git repository
- [ ] Install bats testing framework
- [ ] Provision 3 VPS instances (Ubuntu 20.04, 22.04, Debian 11)
- [ ] Review XTLS/Xray-examples documentation

### Week 1: Begin Implementation
**Start with:** TASK-1.1 (Installation script entry point)

```bash
# Work in project directory
cd /home/ikeniborn/Documents/Project/vless
touch install.sh
chmod +x install.sh

# Write first test
cat > tests/unit/test_install.bats <<'EOF'
@test "install.sh exists and is executable" {
    [ -x "./install.sh" ]
}
EOF

# Run test
bats tests/unit/test_install.bats
```

---

## Documentation References

- **Primary:** [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples) - Reality configuration
- **Docker:** [Docker Compose Documentation](https://docs.docker.com/compose/)
- **Testing:** [Bats: Bash Automated Testing System](https://github.com/bats-core/bats-core)
- **Xray:** [teddysun/xray:24.11.30](https://hub.docker.com/r/teddysun/xray)

---

## Support & Contact

- **Planning Documents:** `/home/ikeniborn/Documents/Project/vless/workflow/`
  - `01_analysis.xml` - Deep PRD analysis
  - `02_strategic_plan.xml` - Strategic roadmap
  - `03_detailed_plan.xml` - Detailed task breakdown
  - `05_master_plan.xml` - Consolidated plan
  - `05_execution_guide.md` - Developer guide
  - `05_executive_summary.md` - Executive overview

- **Implementation Status:** Ready for Week 1

---

**End of Plan**

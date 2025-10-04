# VLESS REALITY - Proxy Server Integration Extension Plan

**Project:** VLESS + Reality VPN with Proxy Support
**Plan Version:** 4.0 Extension
**Status:** Ready for Implementation
**Extension Scope:** Proxy Server Integration (SOCKS5 + HTTP)
**Total Extension Hours:** 58 hours
**Date:** 2025-10-04
**Based on:** PLAN.md v4.0, PRD.md v1.1

---

## Table of Contents

1. [Extension Overview](#extension-overview)
2. [Epic 11: Proxy Server Integration (NEW)](#epic-11-proxy-server-integration-new)
3. [Updated Tasks from Other Epics](#updated-tasks-from-other-epics)
4. [New Security Risks](#new-security-risks)
5. [Testing Requirements](#testing-requirements)
6. [Implementation Checklist](#implementation-checklist)

---

## Extension Overview

### Scope

This extension adds SOCKS5 and HTTP proxy server functionality to the existing VLESS + Reality VPN deployment system, enabling application-level proxying for tools like VSCode, Docker, Git, and terminal applications.

### Key Features

- **SOCKS5 Proxy:** Port 1080, localhost-only binding, password authentication, TCP only
- **HTTP Proxy:** Port 8118, localhost-only binding, password authentication, HTTP/HTTPS support
- **Individual Authentication:** Unique 16-character password per user (auto-generated)
- **Localhost-Only Access:** Proxies bind to 127.0.0.1 (accessible only through VPN tunnel)
- **8 Config Files Per User:** 3 VLESS configs + 5 proxy configs
- **Proxy Management:** CLI commands for viewing credentials and resetting passwords

### New Requirements from PRD v1.1

- **FR-022:** SOCKS5 Proxy Inbound (127.0.0.1:1080, password auth, TCP only)
- **FR-023:** HTTP Proxy Inbound (127.0.0.1:8118, password auth, HTTP/HTTPS)
- **FR-024:** Proxy Configuration Management (8 config files per user)

### Total Extension Hours

| Component | Hours |
|-----------|-------|
| EPIC-11: Proxy Server Integration (NEW) | 40 |
| EPIC-3: TASK-3.3 (UPDATED) | +4 |
| EPIC-6: Tasks 6.1, 6.3, 6.4 (UPDATED) | +6 |
| EPIC-7: Tasks 7.5, 7.6, 7.7 (NEW/UPDATED) | +8 |
| **Total** | **58 hours** |

---

## EPIC-11: Proxy Server Integration (NEW)

**Priority:** Critical
**Complexity:** High
**Total Hours:** 40 hours
**Dependencies:** EPIC-3 (Xray configuration), EPIC-6 (User management) complete

### Overview

Integrate SOCKS5 and HTTP proxy servers into Xray-core, enabling users to configure applications (VSCode, Docker, Git, etc.) to route traffic through the VPN connection.

### Security Model

```
┌─────────────────────────────────────────────────────────┐
│ External Network (Internet)                             │
│                                                          │
│  ✗ Direct access to 1080/8118 BLOCKED                   │
│  ✗ Ports NOT in UFW rules                               │
│  ✗ Ports NOT mapped in docker-compose.yml               │
└─────────────────────────────────────────────────────────┘
                         │
                         │ VLESS Connection (443)
                         ▼
┌─────────────────────────────────────────────────────────┐
│ VLESS Reality VPN Tunnel                                │
│                                                          │
│  ✓ Authenticated user connected                         │
│  ✓ Encrypted tunnel established                         │
└─────────────────────────────────────────────────────────┘
                         │
                         │ Inside Container Network
                         ▼
┌─────────────────────────────────────────────────────────┐
│ Container (vless-reality)                               │
│                                                          │
│  127.0.0.1:1080  ← SOCKS5 Proxy (localhost only)        │
│  127.0.0.1:8118  ← HTTP Proxy (localhost only)          │
│                                                          │
│  ✓ Access only from inside container                    │
│  ✓ Password authentication required                     │
│  ✓ Individual credentials per user                      │
└─────────────────────────────────────────────────────────┘
```

### File Deliverables

**New File:**
- `lib/proxy_management.sh` (~600 lines, 15+ functions)

**Updated Files:**
- `lib/user_management.sh` (add proxy_password generation)
- `lib/qr_generator.sh` (add 5 proxy config exports)
- `lib/service_operations.sh` (add proxy status display)
- `/opt/vless/config/xray_config.json` (3 inbounds: VLESS + SOCKS5 + HTTP)

**Per-User Config Files (5 new files per user):**
1. `socks5_config.txt` - SOCKS5 connection string
2. `http_config.txt` - HTTP proxy connection string
3. `vscode_settings.json` - VSCode proxy configuration
4. `docker_daemon.json` - Docker daemon proxy settings
5. `bash_exports.sh` - Bash environment variables

---

### TASK-11.1: SOCKS5 Proxy Inbound Configuration ✓ COMPLETED (8 hours)

**Status:** ✓ COMPLETED - 2025-10-04
**Priority:** Critical
**File:** `/opt/vless/config/xray_config.json` (inbounds array)
**Implemented in:** lib/orchestrator.sh, lib/user_management.sh, lib/interactive_params.sh
**Workflow Documentation:** workflow/04_implementation_summary_task_11_1.md

**Implementation:**

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

**Key Requirements:**

1. **Localhost Binding:** MUST bind to `127.0.0.1` (NOT `0.0.0.0`)
2. **Password Authentication:** `"auth": "password"` required
3. **TCP Only:** `"udp": false` (per FR-022)
4. **Port Isolation:** Port 1080 NOT exposed in docker-compose.yml
5. **Multi-User Support:** Each user has entry in `accounts` array

**Acceptance Criteria:**

- ✓ Listens on 127.0.0.1:1080 ONLY (verified with `netstat -tuln`)
- ✓ Password authentication enforced (test with wrong password fails)
- ✓ UDP disabled (TCP connections only)
- ✓ Port NOT mapped in docker-compose.yml ports section
- ✓ Accessible from inside container, NOT from external network
- ✓ Configuration validates with `xray -test -config=...`

**Validation Commands:**

```bash
# Inside container test (should show 127.0.0.1:1080)
docker exec vless-reality netstat -tuln | grep 1080
# Expected: tcp        0      0 127.0.0.1:1080          0.0.0.0:*               LISTEN

# Outside container test (should FAIL)
nc -zv SERVER_IP 1080
# Expected: Connection refused

# Check docker-compose.yml (should return nothing)
grep -E '1080' /opt/vless/docker-compose.yml
# Expected: (no port mapping)

# Test authentication
curl --socks5 username:password@127.0.0.1:1080 https://ifconfig.me
# Expected: Server IP (success)

curl --socks5 username:wrongpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication failed
```

**Time Breakdown:**
- Inbound config generation: 2h
- Multi-user accounts management: 2h
- Docker network configuration: 2h
- Testing and validation: 2h

---

### TASK-11.2: HTTP Proxy Inbound Configuration (8 hours)

**Priority:** Critical
**File:** `/opt/vless/config/xray_config.json` (inbounds array)

**Implementation:**

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

**Key Requirements:**

1. **Localhost Binding:** MUST bind to `127.0.0.1`
2. **Password Authentication:** Required for all connections
3. **HTTP/HTTPS Support:** Handles both protocols (per FR-023)
4. **Port Isolation:** Port 8118 NOT exposed externally
5. **Transparent Proxy Disabled:** `"allowTransparent": false`

**Acceptance Criteria:**

- ✓ Listens on 127.0.0.1:8118 ONLY
- ✓ Password authentication enforced
- ✓ Supports both HTTP and HTTPS proxying
- ✓ Port NOT mapped in docker-compose.yml
- ✓ NOT accessible from external network
- ✓ Configuration validates with Xray

**Validation Commands:**

```bash
# Inside container test
docker exec vless-reality netstat -tuln | grep 8118
# Expected: tcp        0      0 127.0.0.1:8118          0.0.0.0:*               LISTEN

# Outside container test (should FAIL)
nc -zv SERVER_IP 8118
# Expected: Connection refused

# Test HTTP proxying
curl --proxy http://username:password@127.0.0.1:8118 http://ifconfig.me
# Expected: Server IP (success)

# Test HTTPS proxying
curl --proxy http://username:password@127.0.0.1:8118 https://ifconfig.me
# Expected: Server IP (success)

# Test authentication
curl --proxy http://127.0.0.1:8118 https://ifconfig.me
# Expected: Authentication required (failure)
```

**Time Breakdown:**
- Inbound config generation: 2h
- HTTP/HTTPS handling: 2h
- Multi-user accounts: 2h
- Testing and validation: 2h

---

### TASK-11.3: Proxy Password Generation and Storage (4 hours)

**Priority:** Critical
**Files:** `lib/user_management.sh`, `/opt/vless/data/users.json`

**Implementation:**

```bash
generate_proxy_password() {
    # Generate 16-character base64 password
    # Example output: "AbCdEfGh12345678"
    openssl rand -base64 16 | tr -d '\n'
}

# Updated user creation function
create_user_with_proxy() {
    local username="$1"
    local uuid=$(uuidgen)
    local shortId=$(openssl rand -hex 8)
    local proxy_password=$(generate_proxy_password)

    # Validate password length
    if [ ${#proxy_password} -lt 16 ]; then
        echo "ERROR: Generated password too short: ${#proxy_password} chars"
        return 1
    fi

    # Store in users.json with file locking
    (
        flock -x 200

        jq ".users += [{
            \"username\": \"$username\",
            \"uuid\": \"$uuid\",
            \"shortId\": \"$shortId\",
            \"proxy_password\": \"$proxy_password\",
            \"created\": \"$(date -Iseconds)\",
            \"enabled\": true
        }]" /opt/vless/data/users.json > /tmp/users.json.tmp

        # Validate JSON syntax
        if ! jq empty /tmp/users.json.tmp 2>/dev/null; then
            echo "ERROR: Invalid JSON generated"
            rm /tmp/users.json.tmp
            return 1
        fi

        mv /tmp/users.json.tmp /opt/vless/data/users.json

    ) 200>/var/lock/vless_users.lock
}
```

**Updated users.json Schema (v1.1):**

```json
{
  "version": "1.1",
  "users": [
    {
      "username": "alice",
      "uuid": "12345678-1234-1234-1234-123456789012",
      "shortId": "a1b2c3d4e5f67890",
      "proxy_password": "AbCdEfGh12345678",
      "created": "2025-10-04T12:00:00Z",
      "enabled": true
    }
  ]
}
```

**Key Requirements:**

1. **Password Length:** Minimum 16 characters (base64 encoding)
2. **Uniqueness:** Different password per user
3. **Storage:** users.json with 600 permissions (root-only)
4. **Same Password:** Used for both SOCKS5 and HTTP proxies
5. **Atomic Updates:** File locking with flock

**Acceptance Criteria:**

- ✓ Password is exactly 16+ characters (base64)
- ✓ Unique per user (no collisions)
- ✓ Stored in users.json with proxy_password field
- ✓ File permissions: 600 (root only)
- ✓ Atomic JSON update (flock protection)
- ✓ JSON validates after update

**Validation:**

```bash
# Check password length
jq -r '.users[0].proxy_password' /opt/vless/data/users.json | wc -c
# Expected: 17 or more (16 chars + newline)

# Check uniqueness (should return nothing if all unique)
jq -r '.users[].proxy_password' /opt/vless/data/users.json | sort | uniq -d

# Check file permissions
stat -c '%a' /opt/vless/data/users.json
# Expected: 600

# Validate JSON syntax
jq empty /opt/vless/data/users.json
# Expected: (no output = valid)
```

**Time Breakdown:**
- Password generation logic: 1h
- users.json schema update: 1h
- File locking implementation: 1h
- Testing and validation: 1h

---

### TASK-11.4: Proxy Configuration Export (8 files per user) (8 hours)

**Priority:** High
**File:** `lib/qr_generator.sh` (update to export 8 files total)

**Implementation:**

**File 1: socks5_config.txt**
```bash
export_socks5_config() {
    local username="$1"
    local password="$2"
    local output_dir="/opt/vless/data/clients/$username"

    echo "socks5://${username}:${password}@127.0.0.1:1080" \
        > "$output_dir/socks5_config.txt"

    chmod 600 "$output_dir/socks5_config.txt"
}
```

**File 2: http_config.txt**
```bash
export_http_config() {
    local username="$1"
    local password="$2"
    local output_dir="/opt/vless/data/clients/$username"

    echo "http://${username}:${password}@127.0.0.1:8118" \
        > "$output_dir/http_config.txt"

    chmod 600 "$output_dir/http_config.txt"
}
```

**File 3: vscode_settings.json**
```bash
export_vscode_config() {
    local username="$1"
    local password="$2"
    local output_dir="/opt/vless/data/clients/$username"

    cat > "$output_dir/vscode_settings.json" <<EOF
{
  "http.proxy": "socks5://${username}:${password}@127.0.0.1:1080",
  "http.proxyStrictSSL": false,
  "http.proxySupport": "on"
}
EOF

    chmod 600 "$output_dir/vscode_settings.json"
}
```

**File 4: docker_daemon.json**
```bash
export_docker_config() {
    local username="$1"
    local password="$2"
    local output_dir="/opt/vless/data/clients/$username"

    cat > "$output_dir/docker_daemon.json" <<EOF
{
  "proxies": {
    "default": {
      "httpProxy": "http://${username}:${password}@127.0.0.1:8118",
      "httpsProxy": "http://${username}:${password}@127.0.0.1:8118",
      "noProxy": "localhost,127.0.0.0/8"
    }
  }
}
EOF

    chmod 600 "$output_dir/docker_daemon.json"
}
```

**File 5: bash_exports.sh**
```bash
export_bash_config() {
    local username="$1"
    local password="$2"
    local output_dir="/opt/vless/data/clients/$username"

    cat > "$output_dir/bash_exports.sh" <<'EOF'
#!/bin/bash
# VLESS Reality Proxy Configuration
# Usage: source bash_exports.sh

export http_proxy="http://USERNAME:PASSWORD@127.0.0.1:8118"
export https_proxy="http://USERNAME:PASSWORD@127.0.0.1:8118"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export NO_PROXY="localhost,127.0.0.0/8"

echo "Proxy environment variables set:"
echo "  http_proxy=$http_proxy"
echo "  https_proxy=$https_proxy"
EOF

    # Replace placeholders
    sed -i "s/USERNAME/$username/g" "$output_dir/bash_exports.sh"
    sed -i "s/PASSWORD/$password/g" "$output_dir/bash_exports.sh"

    chmod 700 "$output_dir/bash_exports.sh"
}
```

**Master Export Function:**
```bash
export_all_configs() {
    local username="$1"
    local proxy_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" /opt/vless/data/users.json)

    # Create user directory if not exists
    mkdir -p "/opt/vless/data/clients/$username"
    chmod 700 "/opt/vless/data/clients/$username"

    # Export VLESS configs (existing - 3 files)
    export_vless_config "$username"
    export_vless_uri "$username"
    generate_qr_code "$username"

    # Export proxy configs (new - 5 files)
    export_socks5_config "$username" "$proxy_password"
    export_http_config "$username" "$proxy_password"
    export_vscode_config "$username" "$proxy_password"
    export_docker_config "$username" "$proxy_password"
    export_bash_config "$username" "$proxy_password"

    echo "All 8 config files exported to: /opt/vless/data/clients/$username/"
}
```

**Acceptance Criteria:**

- ✓ All 5 proxy config files created per user
- ✓ Total 8 files per user (3 VLESS + 5 proxy)
- ✓ File permissions: 600 for configs, 700 for bash script
- ✓ Passwords correctly embedded (no placeholders)
- ✓ All files in `/opt/vless/data/clients/{username}/` directory
- ✓ Directory permissions: 700 (user-only access)

**Validation:**

```bash
# Count files
ls -1 /opt/vless/data/clients/alice/ | wc -l
# Expected: 8

# Check permissions
ls -la /opt/vless/data/clients/alice/
# Expected: -rw------- (600) for configs, -rwx------ (700) for bash

# Test VSCode config syntax
jq empty /opt/vless/data/clients/alice/vscode_settings.json
# Expected: (no output = valid JSON)

# Test Docker config syntax
jq empty /opt/vless/data/clients/alice/docker_daemon.json
# Expected: (no output = valid JSON)

# Test bash script
bash -n /opt/vless/data/clients/alice/bash_exports.sh
# Expected: (no output = valid syntax)
```

**Time Breakdown:**
- SOCKS5/HTTP config export: 1h
- VSCode config export: 1h
- Docker config export: 1.5h
- Bash config export: 1.5h
- Integration and master function: 2h
- Testing all 5 formats: 1h

---

### TASK-11.5: Proxy CLI Commands (6 hours)

**Priority:** High
**Files:** `lib/user_management.sh`, `/usr/local/bin/vless-user`

**Implementation:**

**Command 1: vless-user show --proxy**
```bash
vless_user_show_proxy() {
    local username="$1"

    # Validate user exists
    if ! jq -e ".users[] | select(.username == \"$username\")" /opt/vless/data/users.json &>/dev/null; then
        echo "ERROR: User '$username' not found"
        return 1
    fi

    # Get credentials
    local proxy_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" /opt/vless/data/users.json)

    # Display credentials
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  PROXY CREDENTIALS FOR: $username"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "SOCKS5 Proxy:"
    echo "  socks5://${username}:${proxy_password}@127.0.0.1:1080"
    echo ""
    echo "HTTP Proxy:"
    echo "  http://${username}:${proxy_password}@127.0.0.1:8118"
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "Config Files Location:"
    echo "  /opt/vless/data/clients/${username}/"
    echo ""
    echo "Available Configs:"
    echo "  • socks5_config.txt       (SOCKS5 connection string)"
    echo "  • http_config.txt         (HTTP connection string)"
    echo "  • vscode_settings.json    (VSCode proxy settings)"
    echo "  • docker_daemon.json      (Docker daemon config)"
    echo "  • bash_exports.sh         (Bash environment vars)"
    echo "═══════════════════════════════════════════════════════"
    echo ""
}
```

**Command 2: vless-user proxy-reset**
```bash
vless_user_proxy_reset() {
    local username="$1"

    # Validate user exists
    if ! jq -e ".users[] | select(.username == \"$username\")" /opt/vless/data/users.json &>/dev/null; then
        echo "ERROR: User '$username' not found"
        return 1
    fi

    # Generate new password
    local new_password=$(generate_proxy_password)

    echo "Resetting proxy password for user: $username"
    echo ""

    # Update users.json
    (
        flock -x 200

        jq ".users |= map(if .username == \"$username\" then .proxy_password = \"$new_password\" else . end)" \
            /opt/vless/data/users.json > /tmp/users.json.tmp

        mv /tmp/users.json.tmp /opt/vless/data/users.json

    ) 200>/var/lock/vless_users.lock

    # Update Xray config (both SOCKS5 and HTTP inbounds)
    update_proxy_accounts_in_config "$username" "$new_password"

    # Reload Xray (no downtime, graceful reload)
    echo "Reloading Xray configuration..."
    docker-compose -f /opt/vless/docker-compose.yml restart xray

    # Regenerate proxy config files
    echo "Regenerating proxy configuration files..."
    export_socks5_config "$username" "$new_password"
    export_http_config "$username" "$new_password"
    export_vscode_config "$username" "$new_password"
    export_docker_config "$username" "$new_password"
    export_bash_config "$username" "$new_password"

    echo ""
    echo "✓ Proxy password reset successfully"
    echo ""
    echo "New credentials:"
    echo "  Username: $username"
    echo "  Password: $new_password"
    echo ""
    echo "Updated files:"
    echo "  /opt/vless/data/clients/${username}/"
    echo "    • socks5_config.txt"
    echo "    • http_config.txt"
    echo "    • vscode_settings.json"
    echo "    • docker_daemon.json"
    echo "    • bash_exports.sh"
    echo ""
}

# Helper function to update config.json
update_proxy_accounts_in_config() {
    local username="$1"
    local new_password="$2"
    local config="/opt/vless/config/xray_config.json"

    # Update SOCKS5 inbound
    jq ".inbounds |= map(
        if .tag == \"socks5-proxy\" then
            .settings.accounts |= map(
                if .user == \"$username\" then
                    .pass = \"$new_password\"
                else . end
            )
        else . end
    )" "$config" > /tmp/config.json.tmp

    # Update HTTP inbound
    jq ".inbounds |= map(
        if .tag == \"http-proxy\" then
            .settings.accounts |= map(
                if .user == \"$username\" then
                    .pass = \"$new_password\"
                else . end
            )
        else . end
    )" /tmp/config.json.tmp > /tmp/config.json.tmp2

    # Validate config
    if xray -test -config=/tmp/config.json.tmp2 &>/dev/null; then
        mv /tmp/config.json.tmp2 "$config"
        rm -f /tmp/config.json.tmp
    else
        echo "ERROR: Config validation failed, rollback"
        rm -f /tmp/config.json.tmp /tmp/config.json.tmp2
        return 1
    fi
}
```

**Acceptance Criteria:**

- ✓ `vless-user show <user> --proxy` displays proxy credentials
- ✓ Shows both SOCKS5 and HTTP connection strings
- ✓ Lists all 5 proxy config files with descriptions
- ✓ `vless-user proxy-reset <user>` regenerates password
- ✓ Password updated in users.json, config.json, all 5 config files
- ✓ Xray reloads gracefully (no service interruption)
- ✓ Commands validate user exists before operating
- ✓ File locking prevents concurrent modifications

**Usage Examples:**

```bash
# Show proxy credentials
sudo vless-user show alice --proxy

# Reset proxy password
sudo vless-user proxy-reset alice

# Verify new password in config
sudo vless-user show alice --proxy
```

**Time Breakdown:**
- show --proxy command: 2h
- proxy-reset command: 2h
- Config update helper: 1h
- Testing and edge cases: 1h

---

### TASK-11.6: Update Xray Config with 3 Inbounds (4 hours)

**Priority:** Critical
**File:** `lib/orchestrator.sh`, `/opt/vless/config/xray_config.json`

**Implementation:**

```bash
generate_complete_xray_config() {
    local private_key="$1"
    local short_id="$2"
    local dest_server="$3"
    local dest_port="$4"
    local listen_port="$5"

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
      "port": $listen_port,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "nginx:8080",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${dest_server}:${dest_port}",
          "xver": 0,
          "serverNames": ["${dest_server}"],
          "privateKey": "${private_key}",
          "shortIds": ["${short_id}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
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
        "udp": false,
        "ip": "127.0.0.1"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "http-proxy",
      "listen": "127.0.0.1",
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
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    # Validate config
    if ! xray -test -config=/opt/vless/config/xray_config.json; then
        echo "ERROR: Xray config validation failed"
        return 1
    fi

    echo "✓ Xray config generated with 3 inbounds (VLESS + SOCKS5 + HTTP)"
}
```

**Add User to All 3 Inbounds:**
```bash
add_user_to_all_inbounds() {
    local username="$1"
    local uuid="$2"
    local shortId="$3"
    local proxy_password="$4"
    local config="/opt/vless/config/xray_config.json"

    # Add to VLESS inbound
    jq ".inbounds |= map(
        if .tag == \"vless-reality\" then
            .settings.clients += [{
                \"id\": \"$uuid\",
                \"flow\": \"xtls-rprx-vision\",
                \"email\": \"${username}@local\"
            }]
        else . end
    )" "$config" > /tmp/config.tmp

    # Add to SOCKS5 inbound
    jq ".inbounds |= map(
        if .tag == \"socks5-proxy\" then
            .settings.accounts += [{
                \"user\": \"$username\",
                \"pass\": \"$proxy_password\"
            }]
        else . end
    )" /tmp/config.tmp > /tmp/config.tmp2

    # Add to HTTP inbound
    jq ".inbounds |= map(
        if .tag == \"http-proxy\" then
            .settings.accounts += [{
                \"user\": \"$username\",
                \"pass\": \"$proxy_password\"
            }]
        else . end
    )" /tmp/config.tmp2 > /tmp/config.tmp3

    # Validate final config
    if xray -test -config=/tmp/config.tmp3 &>/dev/null; then
        mv /tmp/config.tmp3 "$config"
        rm -f /tmp/config.tmp /tmp/config.tmp2
        echo "✓ User added to all 3 inbounds"
    else
        echo "ERROR: Config validation failed"
        rm -f /tmp/config.tmp /tmp/config.tmp2 /tmp/config.tmp3
        return 1
    fi
}
```

**Acceptance Criteria:**

- ✓ All 3 inbounds present in config.json
- ✓ VLESS on 0.0.0.0:{listen_port}, SOCKS5/HTTP on 127.0.0.1
- ✓ Validates with `xray -test -config=...`
- ✓ SOCKS5 accounts array starts empty
- ✓ HTTP accounts array starts empty
- ✓ User creation updates all 3 inbounds
- ✓ Config syntax valid after user addition

**Validation:**

```bash
# Check all 3 inbounds exist
jq '.inbounds | length' /opt/vless/config/xray_config.json
# Expected: 3

# Check tags
jq -r '.inbounds[].tag' /opt/vless/config/xray_config.json
# Expected:
# vless-reality
# socks5-proxy
# http-proxy

# Check SOCKS5 binding
jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .listen' /opt/vless/config/xray_config.json
# Expected: 127.0.0.1

# Check HTTP binding
jq -r '.inbounds[] | select(.tag == "http-proxy") | .listen' /opt/vless/config/xray_config.json
# Expected: 127.0.0.1

# Validate full config
xray -test -config=/opt/vless/config/xray_config.json
# Expected: Configuration OK
```

**Time Breakdown:**
- Config template with 3 inbounds: 1h
- User addition to all inbounds: 1.5h
- Validation logic: 1h
- Testing: 0.5h

---

### TASK-11.7: Proxy Functionality Testing (2 hours)

**Priority:** High
**Files:** `tests/integration/test_proxy_functionality.bats`

**Implementation:**

**Test 1: SOCKS5 Accessibility**
```bash
@test "SOCKS5 proxy accessible through VPN tunnel" {
    # Assumes VPN connection established
    run curl --socks5 testuser:password@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SERVER_IP" ]]
}

@test "SOCKS5 proxy NOT accessible from external network" {
    # From external host
    run nc -zv SERVER_IP 1080
    [ "$status" -ne 0 ]
    [[ "$output" =~ "refused" ]]
}
```

**Test 2: HTTP Accessibility**
```bash
@test "HTTP proxy accessible through VPN tunnel" {
    run curl --proxy http://testuser:password@127.0.0.1:8118 https://ifconfig.me
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SERVER_IP" ]]
}

@test "HTTP proxy NOT accessible from external network" {
    run nc -zv SERVER_IP 8118
    [ "$status" -ne 0 ]
}
```

**Test 3: Authentication Enforcement**
```bash
@test "SOCKS5 requires authentication" {
    run curl --socks5 127.0.0.1:1080 https://ifconfig.me
    [ "$status" -ne 0 ]
}

@test "SOCKS5 rejects wrong password" {
    run curl --socks5 testuser:wrongpass@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -ne 0 ]
}

@test "HTTP requires authentication" {
    run curl --proxy http://127.0.0.1:8118 https://ifconfig.me
    [ "$status" -ne 0 ]
}
```

**Test 4: Port Isolation**
```bash
@test "Port 1080 NOT in UFW rules" {
    run ufw status
    [[ ! "$output" =~ "1080" ]]
}

@test "Port 8118 NOT in UFW rules" {
    run ufw status
    [[ ! "$output" =~ "8118" ]]
}

@test "Port 1080 NOT in docker-compose.yml" {
    run grep -q "1080" /opt/vless/docker-compose.yml
    [ "$status" -ne 0 ]
}

@test "Port 8118 NOT in docker-compose.yml" {
    run grep -q "8118" /opt/vless/docker-compose.yml
    [ "$status" -ne 0 ]
}
```

**Test 5: Localhost Binding Verification**
```bash
@test "SOCKS5 binds to localhost only" {
    run docker exec vless-reality netstat -tuln
    [[ "$output" =~ "127.0.0.1:1080" ]]
    [[ ! "$output" =~ "0.0.0.0:1080" ]]
}

@test "HTTP binds to localhost only" {
    run docker exec vless-reality netstat -tuln
    [[ "$output" =~ "127.0.0.1:8118" ]]
    [[ ! "$output" =~ "0.0.0.0:8118" ]]
}
```

**Acceptance Criteria:**

- ✓ All 15 tests pass
- ✓ SOCKS5/HTTP accessible through VPN tunnel
- ✓ NOT accessible from external network
- ✓ Authentication required and enforced
- ✓ Ports NOT in UFW rules
- ✓ Ports NOT in docker-compose.yml
- ✓ Binds to 127.0.0.1 ONLY (not 0.0.0.0)

**Time Breakdown:**
- Test script creation: 1h
- Manual validation: 0.5h
- Edge case testing: 0.5h

---

## Updated Tasks from Other Epics

### EPIC-3: Reality Protocol Configuration

#### TASK-3.3: Xray config.json Creation with 3 Inbounds (12 hours) - UPDATED

**Original Hours:** 8h
**Updated Hours:** 12h (+4h)
**Reason:** Adding SOCKS5 and HTTP inbounds to existing VLESS configuration

**Changes from Original Task:**

1. **Config Template:** Now includes 3 inbounds instead of 1
2. **Validation:** Must validate all 3 inbound configurations
3. **Integration:** SOCKS5/HTTP must coexist with VLESS Reality

**Updated Implementation:** See TASK-11.6 for complete config structure

**Additional Requirements:**

- ✓ All 3 inbounds in single config.json
- ✓ VLESS Reality inbound unchanged (backward compatible)
- ✓ SOCKS5 on 127.0.0.1:1080
- ✓ HTTP on 127.0.0.1:8118
- ✓ Config validates with `xray -test`

**Time Breakdown:**
- Original VLESS config: 8h (already complete)
- Add SOCKS5 inbound: +2h
- Add HTTP inbound: +2h
- **Total:** 12h

---

### EPIC-6: User Management

#### TASK-6.1: User Creation Workflow with Proxy Password (8 hours) - UPDATED

**Original Hours:** 6h
**Updated Hours:** 8h (+2h)
**Reason:** Adding proxy password generation and storage

**Changes from Original Task:**

1. **Password Generation:** Add `generate_proxy_password()` call
2. **users.json Schema:** Add `proxy_password` field
3. **Multi-Inbound Update:** Update 3 inbounds (VLESS + SOCKS5 + HTTP)

**Updated Workflow:**

```bash
create_user() {
    local username="$1"

    # Generate credentials
    local uuid=$(uuidgen)
    local shortId=$(openssl rand -hex 8)
    local proxy_password=$(generate_proxy_password)  # NEW

    # Update users.json (with proxy_password field)
    # Update config.json (all 3 inbounds)  # CHANGED
    # Generate client configs (8 files instead of 3)  # CHANGED

    echo "User created: $username"
    echo "Proxy password: $proxy_password"  # NEW
}
```

**Time Breakdown:**
- Original user creation: 6h
- Add proxy password generation: +1h
- Update 3 inbounds instead of 1: +1h
- **Total:** 8h

---

#### TASK-6.3: JSON Storage with flock + proxy_password Field (6 hours) - UPDATED

**Original Hours:** 4h
**Updated Hours:** 6h (+2h)
**Reason:** Schema update to v1.1 with proxy_password field

**Changes from Original Task:**

1. **Schema Version:** Update from 1.0 to 1.1
2. **New Field:** Add `proxy_password` to user object
3. **Migration:** Convert existing users.json if upgrading

**Updated Schema:**

```json
{
  "version": "1.1",
  "users": [
    {
      "username": "alice",
      "uuid": "...",
      "shortId": "...",
      "proxy_password": "AbCdEfGh12345678",
      "created": "2025-10-04T12:00:00Z",
      "enabled": true
    }
  ]
}
```

**Migration Function:**

```bash
migrate_users_json_to_v1_1() {
    local current_version=$(jq -r '.version' /opt/vless/data/users.json)

    if [ "$current_version" = "1.0" ]; then
        echo "Migrating users.json from v1.0 to v1.1..."

        jq '.version = "1.1" | .users |= map(. + {
            "proxy_password": "GENERATE_ON_NEXT_LOGIN"
        })' /opt/vless/data/users.json > /tmp/users_v1.1.json

        mv /tmp/users_v1.1.json /opt/vless/data/users.json
    fi
}
```

**Time Breakdown:**
- Original JSON storage: 4h
- Add proxy_password field: +1h
- Migration logic: +1h
- **Total:** 6h

---

#### TASK-6.4: Xray Config Update for 3 Inbounds (6 hours) - UPDATED

**Original Hours:** 4h
**Updated Hours:** 6h (+2h)
**Reason:** Update 3 inbounds instead of 1

**Changes from Original Task:**

1. **VLESS Inbound:** Add user to clients array (original)
2. **SOCKS5 Inbound:** Add user to accounts array (NEW)
3. **HTTP Inbound:** Add user to accounts array (NEW)

**Implementation:** See TASK-11.6 `add_user_to_all_inbounds()` function

**Time Breakdown:**
- Original VLESS update: 4h
- Add SOCKS5 account: +1h
- Add HTTP account: +1h
- **Total:** 6h

---

### EPIC-7: Client Configuration Export

#### TASK-7.5: Export Proxy Configs (5 Additional Files) (6 hours) - NEW

**Hours:** 6h
**Priority:** High
**Deliverables:** 5 new config file formats per user

**Files to Generate:**

1. `socks5_config.txt` - Connection string
2. `http_config.txt` - Connection string
3. `vscode_settings.json` - VSCode proxy configuration
4. `docker_daemon.json` - Docker daemon proxy settings
5. `bash_exports.sh` - Bash environment variables

**Implementation:** See TASK-11.4 for complete details

**Time Breakdown:**
- SOCKS5/HTTP configs: 1h
- VSCode config: 1h
- Docker config: 1.5h
- Bash config: 1.5h
- Integration: 1h

---

#### TASK-7.6: Validation (All 8 Files) (2 hours) - UPDATED

**Original Hours:** 1h
**Updated Hours:** 2h (+1h)
**Reason:** Validate 8 files instead of 3

**Validation Checks:**

1. **VLESS Configs (3 files):**
   - vless_config.json (JSON syntax)
   - vless_uri.txt (URI format)
   - qrcode.png (400x400px image)

2. **Proxy Configs (5 files):**
   - socks5_config.txt (connection string format)
   - http_config.txt (connection string format)
   - vscode_settings.json (JSON syntax)
   - docker_daemon.json (JSON syntax)
   - bash_exports.sh (bash syntax check)

**Validation Script:**

```bash
validate_all_user_configs() {
    local username="$1"
    local config_dir="/opt/vless/data/clients/$username"
    local errors=0

    # Check all 8 files exist
    local required_files=(
        "vless_config.json"
        "vless_uri.txt"
        "qrcode.png"
        "socks5_config.txt"
        "http_config.txt"
        "vscode_settings.json"
        "docker_daemon.json"
        "bash_exports.sh"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$config_dir/$file" ]; then
            echo "ERROR: Missing file: $file"
            ((errors++))
        fi
    done

    # Validate JSON syntax
    for json_file in vless_config.json vscode_settings.json docker_daemon.json; do
        if ! jq empty "$config_dir/$json_file" 2>/dev/null; then
            echo "ERROR: Invalid JSON: $json_file"
            ((errors++))
        fi
    done

    # Validate bash script
    if ! bash -n "$config_dir/bash_exports.sh"; then
        echo "ERROR: Invalid bash syntax: bash_exports.sh"
        ((errors++))
    fi

    # Validate QR code image
    if ! file "$config_dir/qrcode.png" | grep -q "PNG image data, 400 x 400"; then
        echo "ERROR: Invalid QR code image"
        ((errors++))
    fi

    return $errors
}
```

**Time Breakdown:**
- Original validation (3 files): 1h
- Add proxy validation (5 files): +1h
- **Total:** 2h

---

#### TASK-7.7: Display Proxy Credentials in CLI (1 hour) - NEW

**Hours:** 1h
**Priority:** Medium
**Deliverable:** Enhanced `vless-user show` command with proxy credentials

**Implementation:**

```bash
# Enhanced user display
vless_user_show() {
    local username="$1"
    local show_proxy="${2:-false}"  # --proxy flag

    # Show VLESS info (original)
    show_vless_credentials "$username"

    # Show proxy info if requested
    if [ "$show_proxy" = "--proxy" ]; then
        vless_user_show_proxy "$username"
    fi
}
```

**CLI Output:**

```
sudo vless-user show alice --proxy

═══════════════════════════════════════════════════
  USER: alice
═══════════════════════════════════════════════════

VLESS Credentials:
  UUID: 12345678-1234-1234-1234-123456789012
  Server: 1.2.3.4:443
  SNI: google.com

  Config: /opt/vless/data/clients/alice/vless_config.json
  URI: /opt/vless/data/clients/alice/vless_uri.txt
  QR Code: /opt/vless/data/clients/alice/qrcode.png

───────────────────────────────────────────────────

PROXY Credentials:
  SOCKS5: socks5://alice:AbCdEfGh12345678@127.0.0.1:1080
  HTTP:   http://alice:AbCdEfGh12345678@127.0.0.1:8118

  Configs:
    • socks5_config.txt
    • http_config.txt
    • vscode_settings.json
    • docker_daemon.json
    • bash_exports.sh

═══════════════════════════════════════════════════
```

**Time Breakdown:** 1h (simple CLI enhancement)

---

## New Security Risks

### RISK-11.1: Proxy Port Exposure (High Severity)

**Threat:** Proxy ports (1080, 8118) accidentally exposed to internet

**Impact:** Server becomes open proxy, enabling:
- Bandwidth abuse (unlimited traffic routing)
- Legal liability (proxy used for illegal activities)
- IP reputation damage (blacklisting)
- Resource exhaustion (CPU/bandwidth)

**Attack Vector:**

1. Attacker scans internet for open proxies
2. Finds exposed port 1080 or 8118
3. Uses server as free proxy without authentication
4. Server owner faces consequences

**Likelihood:** Medium (human error in configuration)
**Severity:** High (legal and resource impact)
**Risk Score:** **HIGH**

**Mitigation Strategies:**

1. **Localhost Binding (CRITICAL):**
   - ALWAYS bind to `127.0.0.1` in Xray config
   - NEVER use `0.0.0.0` for proxy inbounds
   - Code review every proxy config change

2. **Docker Compose Validation:**
   - Ensure ports 1080/8118 NOT in `ports:` section
   - Automated check during deployment
   - CI/CD validation before merge

3. **UFW Verification:**
   - Confirm ports NOT in UFW allow rules
   - Automated test: `ufw status | grep -E '(1080|8118)'` must return nothing

4. **External Access Test:**
   - Automated test from external host (must fail)
   - Run on every deployment
   - Part of integration test suite

5. **Code Review:**
   - Every proxy config change reviewed by 2 people
   - Explicit check for binding address

**Detection Commands:**

```bash
# 1. Check Xray binding address
docker exec vless-reality netstat -tuln | grep -E '(1080|8118)'
# Expected: 127.0.0.1:1080 and 127.0.0.1:8118 (NOT 0.0.0.0)

# 2. Check docker-compose.yml
grep -E '(1080|8118)' /opt/vless/docker-compose.yml
# Expected: No output (no port mapping)

# 3. Check UFW rules
ufw status | grep -E '(1080|8118)'
# Expected: No output (ports not allowed)

# 4. Test external access (from different machine)
nc -zv SERVER_IP 1080
nc -zv SERVER_IP 8118
# Expected: Connection refused (both should FAIL)

# 5. Test from inside container
docker exec vless-reality curl --socks5 127.0.0.1:1080 https://ifconfig.me
# Expected: Success (server IP returned)
```

**Automated Test:**

```bash
# tests/security/test_proxy_port_isolation.bats

@test "Proxy ports NOT exposed externally" {
    # Test from external host
    run nc -zv SERVER_IP 1080
    [ "$status" -ne 0 ]

    run nc -zv SERVER_IP 8118
    [ "$status" -ne 0 ]
}

@test "Proxy binds to localhost only" {
    run docker exec vless-reality netstat -tuln
    [[ "$output" =~ "127.0.0.1:1080" ]]
    [[ ! "$output" =~ "0.0.0.0:1080" ]]
    [[ "$output" =~ "127.0.0.1:8118" ]]
    [[ ! "$output" =~ "0.0.0.0:8118" ]]
}
```

**Incident Response:**

If ports are exposed:

1. **IMMEDIATE:**
   - Stop Xray container: `docker-compose stop xray`
   - Block ports in UFW: `ufw deny 1080/tcp` and `ufw deny 8118/tcp`

2. **FIX:**
   - Update config.json: Change `"listen": "0.0.0.0"` to `"listen": "127.0.0.1"`
   - Remove port mappings from docker-compose.yml
   - Validate config: `xray -test -config=...`

3. **VERIFY:**
   - Restart container: `docker-compose up -d xray`
   - Run all detection commands
   - Confirm external access blocked

4. **POST-INCIDENT:**
   - Review access logs for abuse
   - Check bandwidth usage
   - Monitor IP reputation

---

### RISK-11.2: Proxy Authentication Bypass (Medium Severity)

**Threat:** Proxy authentication not enforced, allowing unauthenticated access

**Impact:**
- Unauthorized users can use proxy
- Bandwidth theft
- Resource exhaustion
- Cannot track usage per user

**Attack Vector:**

1. User establishes VLESS VPN connection (authenticated)
2. Tries to access SOCKS5/HTTP without proxy credentials
3. If authentication disabled: Gets free proxy access
4. Can share proxy access without sharing VPN credentials

**Likelihood:** Low (configuration error)
**Severity:** Medium (resource impact, no legal liability)
**Risk Score:** **MEDIUM**

**Mitigation Strategies:**

1. **Config Validation:**
   - Verify `"auth": "password"` in SOCKS5 inbound
   - Verify `"accounts": [...]` not empty
   - Automated check during config generation

2. **Automated Testing:**
   - Test connection without credentials (must fail)
   - Test with wrong credentials (must fail)
   - Test with correct credentials (must succeed)

3. **Password Strength:**
   - Minimum 16 characters (enforced)
   - Use `openssl rand -base64 16` (secure random)
   - Never accept user-provided passwords

4. **Config Template Protection:**
   - Use version-controlled templates
   - Code review for template changes
   - Automated validation on commit

**Detection Commands:**

```bash
# 1. Verify auth mode in config
jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .settings.auth' \
    /opt/vless/config/xray_config.json
# Expected: password

# 2. Verify accounts not empty
jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .settings.accounts | length' \
    /opt/vless/config/xray_config.json
# Expected: > 0

# 3. Test without credentials (should FAIL)
curl --socks5 127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication required error

# 4. Test with wrong password (should FAIL)
curl --socks5 user:wrongpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Authentication failed error

# 5. Test with correct credentials (should SUCCEED)
curl --socks5 user:correctpass@127.0.0.1:1080 https://ifconfig.me
# Expected: Server IP returned
```

**Automated Test:**

```bash
# tests/security/test_proxy_authentication.bats

@test "SOCKS5 requires authentication" {
    run curl --socks5 127.0.0.1:1080 https://ifconfig.me
    [ "$status" -ne 0 ]
}

@test "SOCKS5 rejects wrong password" {
    run curl --socks5 testuser:wrongpass@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -ne 0 ]
}

@test "SOCKS5 accepts correct password" {
    # Get real password from users.json
    password=$(jq -r '.users[0].proxy_password' /opt/vless/data/users.json)
    username=$(jq -r '.users[0].username' /opt/vless/data/users.json)

    run curl --socks5 ${username}:${password}@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -eq 0 ]
}

@test "HTTP requires authentication" {
    run curl --proxy http://127.0.0.1:8118 https://ifconfig.me
    [ "$status" -ne 0 ]
}
```

**Incident Response:**

If authentication bypass detected:

1. **IMMEDIATE:**
   - Disable proxy inbounds (comment out in config.json)
   - Restart Xray: `docker-compose restart xray`

2. **FIX:**
   - Update config: Set `"auth": "password"`
   - Regenerate all proxy passwords
   - Update all user accounts in config

3. **VERIFY:**
   - Test all authentication scenarios
   - Run automated test suite
   - Confirm all tests pass

4. **POST-INCIDENT:**
   - Notify all users to update configs
   - Review access logs for unauthorized usage
   - Update templates to prevent recurrence

---

## Testing Requirements

### Integration Tests

**File:** `tests/integration/test_proxy_integration.bats`

**Test Suite:**

```bash
# Test 1: Full user workflow with proxy
@test "User creation generates all 8 config files" {
    run sudo vless-user add testproxy
    [ "$status" -eq 0 ]

    # Count files
    file_count=$(ls -1 /opt/vless/data/clients/testproxy/ | wc -l)
    [ "$file_count" -eq 8 ]
}

# Test 2: Proxy credentials in users.json
@test "users.json contains proxy_password field" {
    run jq -r '.users[0] | has("proxy_password")' /opt/vless/data/users.json
    [ "$output" = "true" ]
}

# Test 3: All 3 inbounds in config.json
@test "config.json has 3 inbounds" {
    inbound_count=$(jq '.inbounds | length' /opt/vless/config/xray_config.json)
    [ "$inbound_count" -eq 3 ]
}

# Test 4: SOCKS5 functionality
@test "SOCKS5 proxy works with correct credentials" {
    username=$(jq -r '.users[0].username' /opt/vless/data/users.json)
    password=$(jq -r '.users[0].proxy_password' /opt/vless/data/users.json)

    run curl --socks5 ${username}:${password}@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -eq 0 ]
}

# Test 5: HTTP functionality
@test "HTTP proxy works with correct credentials" {
    username=$(jq -r '.users[0].username' /opt/vless/data/users.json)
    password=$(jq -r '.users[0].proxy_password' /opt/vless/data/users.json)

    run curl --proxy http://${username}:${password}@127.0.0.1:8118 https://ifconfig.me
    [ "$status" -eq 0 ]
}

# Test 6: Proxy password reset
@test "Proxy password reset updates all configs" {
    username="testproxy"

    # Get old password
    old_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" /opt/vless/data/users.json)

    # Reset password
    run sudo vless-user proxy-reset $username
    [ "$status" -eq 0 ]

    # Get new password
    new_password=$(jq -r ".users[] | select(.username == \"$username\") | .proxy_password" /opt/vless/data/users.json)

    # Verify changed
    [ "$old_password" != "$new_password" ]

    # Verify new password works
    run curl --socks5 ${username}:${new_password}@127.0.0.1:1080 https://ifconfig.me
    [ "$status" -eq 0 ]
}

# Test 7: Config file validation
@test "All JSON config files are valid" {
    for user_dir in /opt/vless/data/clients/*/; do
        for json_file in vless_config.json vscode_settings.json docker_daemon.json; do
            run jq empty "$user_dir/$json_file"
            [ "$status" -eq 0 ]
        done
    done
}

# Test 8: Bash script validation
@test "bash_exports.sh has valid syntax" {
    for user_dir in /opt/vless/data/clients/*/; do
        run bash -n "$user_dir/bash_exports.sh"
        [ "$status" -eq 0 ]
    done
}
```

### Security Tests

**File:** `tests/security/test_proxy_security.bats`

```bash
# Test 1: Port isolation
@test "Proxy ports NOT in UFW rules" {
    run ufw status
    [[ ! "$output" =~ "1080" ]]
    [[ ! "$output" =~ "8118" ]]
}

# Test 2: Docker compose port mapping
@test "Proxy ports NOT in docker-compose.yml" {
    run grep -E '(1080|8118)' /opt/vless/docker-compose.yml
    [ "$status" -ne 0 ]
}

# Test 3: Localhost binding
@test "SOCKS5 binds to localhost only" {
    run docker exec vless-reality netstat -tuln
    [[ "$output" =~ "127.0.0.1:1080" ]]
    [[ ! "$output" =~ "0.0.0.0:1080" ]]
}

# Test 4: Authentication enforcement
@test "SOCKS5 requires authentication" {
    run curl --socks5 127.0.0.1:1080 https://ifconfig.me
    [ "$status" -ne 0 ]
}

# Test 5: Password strength
@test "Proxy passwords are 16+ characters" {
    for password in $(jq -r '.users[].proxy_password' /opt/vless/data/users.json); do
        [ ${#password} -ge 16 ]
    done
}

# Test 6: File permissions
@test "Proxy config files have 600 permissions" {
    for user_dir in /opt/vless/data/clients/*/; do
        for config_file in socks5_config.txt http_config.txt vscode_settings.json docker_daemon.json; do
            perms=$(stat -c '%a' "$user_dir/$config_file")
            [ "$perms" = "600" ]
        done
    done
}
```

### Performance Tests

**Target:** User creation with proxy support in < 6 seconds

```bash
# tests/performance/test_user_creation_time.bats

@test "User creation with proxy completes in < 6 seconds" {
    start=$(date +%s)

    run sudo vless-user add perftest
    [ "$status" -eq 0 ]

    end=$(date +%s)
    duration=$((end - start))

    [ "$duration" -lt 6 ]
}
```

---

## Implementation Checklist

### Phase 1: Core Proxy Infrastructure (Week 5, Days 1-2)

- [ ] **TASK-11.1:** SOCKS5 Proxy Inbound Configuration (8h)
  - [ ] Create `generate_socks5_inbound()` function
  - [ ] Add to Xray config template
  - [ ] Validate localhost binding (127.0.0.1)
  - [ ] Test authentication enforcement
  - [ ] Verify external access blocked

- [ ] **TASK-11.2:** HTTP Proxy Inbound Configuration (8h)
  - [ ] Create `generate_http_inbound()` function
  - [ ] Add to Xray config template
  - [ ] Validate localhost binding
  - [ ] Test HTTP/HTTPS support
  - [ ] Verify authentication

### Phase 2: User Management Integration (Week 5, Days 3-4)

- [ ] **TASK-11.3:** Proxy Password Generation (4h)
  - [ ] Implement `generate_proxy_password()` (openssl rand -base64 16)
  - [ ] Update users.json schema to v1.1
  - [ ] Add proxy_password field to user objects
  - [ ] Validate password length (16+ chars)
  - [ ] Test atomic JSON updates with flock

- [ ] **TASK-11.6:** Update Xray Config with 3 Inbounds (4h)
  - [ ] Update `generate_complete_xray_config()` with all 3 inbounds
  - [ ] Implement `add_user_to_all_inbounds()` function
  - [ ] Validate config with `xray -test`
  - [ ] Test multi-user scenarios

- [ ] **EPIC-3 TASK-3.3:** Update Xray Config Creation (+4h)
  - [ ] Merge proxy inbounds into existing config template
  - [ ] Ensure backward compatibility with VLESS-only configs
  - [ ] Validate all 3 inbounds coexist

- [ ] **EPIC-6 TASK-6.1:** Update User Creation Workflow (+2h)
  - [ ] Add proxy password generation to user creation
  - [ ] Update all 3 inbounds (VLESS + SOCKS5 + HTTP)

- [ ] **EPIC-6 TASK-6.3:** Update JSON Storage (+2h)
  - [ ] Add proxy_password field to user objects
  - [ ] Implement schema migration from v1.0 to v1.1

- [ ] **EPIC-6 TASK-6.4:** Update Config for 3 Inbounds (+2h)
  - [ ] Update all 3 inbounds when adding/removing users

### Phase 3: Configuration Export (Week 5, Day 4)

- [ ] **TASK-11.4:** Proxy Configuration Export (8h)
  - [ ] Create `export_socks5_config()`
  - [ ] Create `export_http_config()`
  - [ ] Create `export_vscode_config()`
  - [ ] Create `export_docker_config()`
  - [ ] Create `export_bash_config()`
  - [ ] Implement `export_all_configs()` master function
  - [ ] Validate all 8 files per user

- [ ] **EPIC-7 TASK-7.5:** Export Proxy Configs (6h)
  - [ ] Generate all 5 proxy config files
  - [ ] Validate file permissions (600)
  - [ ] Test all config formats

- [ ] **EPIC-7 TASK-7.6:** Validate All 8 Files (+1h)
  - [ ] Add validation for 5 proxy configs
  - [ ] JSON syntax checks
  - [ ] Bash script validation

- [ ] **EPIC-7 TASK-7.7:** Display Proxy Credentials (1h)
  - [ ] Enhance `vless-user show` with --proxy flag
  - [ ] Display SOCKS5 and HTTP credentials

### Phase 4: CLI Commands (Week 5, Day 5)

- [ ] **TASK-11.5:** Proxy CLI Commands (6h)
  - [ ] Implement `vless-user show --proxy`
  - [ ] Implement `vless-user proxy-reset <user>`
  - [ ] Create `update_proxy_accounts_in_config()` helper
  - [ ] Test password reset workflow
  - [ ] Verify Xray reload without downtime

### Phase 5: Testing & Validation (Week 6, Days 1-2)

- [ ] **TASK-11.7:** Proxy Functionality Testing (2h)
  - [ ] Create integration test suite (test_proxy_integration.bats)
  - [ ] Create security test suite (test_proxy_security.bats)
  - [ ] Test SOCKS5 accessibility (through VPN tunnel)
  - [ ] Test HTTP accessibility (through VPN tunnel)
  - [ ] Test authentication enforcement
  - [ ] Test external access blocked
  - [ ] Test port isolation (UFW, docker-compose)
  - [ ] Test localhost binding
  - [ ] Performance test (user creation < 6 sec)

- [ ] **Security Validation:**
  - [ ] Run RISK-11.1 detection commands
  - [ ] Run RISK-11.2 detection commands
  - [ ] Verify all security tests pass
  - [ ] External port scan (nmap)
  - [ ] Wireshark packet capture analysis

### Phase 6: Documentation & Cleanup (Week 6, Day 2)

- [ ] Update PLAN.md with completion status
- [ ] Update README.md with proxy usage examples
- [ ] Create proxy troubleshooting guide
- [ ] Update Quick Start Guide with proxy commands
- [ ] Document security best practices
- [ ] Create user migration guide (v1.0 to v1.1)

---

## Success Criteria (Extension)

### Functional Requirements

- ✓ All 7 tasks in EPIC-11 completed
- ✓ All updated tasks in EPIC-3, EPIC-6, EPIC-7 completed
- ✓ SOCKS5 proxy accessible at 127.0.0.1:1080 through VPN tunnel
- ✓ HTTP proxy accessible at 127.0.0.1:8118 through VPN tunnel
- ✓ 8 config files generated per user (3 VLESS + 5 proxy)
- ✓ Proxy passwords 16+ characters, auto-generated
- ✓ CLI commands `vless-user show --proxy` and `proxy-reset` functional

### Security Requirements

- ✓ Ports 1080/8118 NOT exposed externally (external access test fails)
- ✓ Ports 1080/8118 NOT in UFW rules
- ✓ Ports 1080/8118 NOT mapped in docker-compose.yml
- ✓ Proxies bind to 127.0.0.1 ONLY (not 0.0.0.0)
- ✓ Authentication required and enforced (test without creds fails)
- ✓ Wrong password rejected (test with wrong password fails)
- ✓ All proxy config files have 600 permissions

### Performance Requirements

- ✓ User creation time: < 6 seconds (with proxy support)
- ✓ Proxy password reset: < 5 seconds
- ✓ Config export (8 files): < 3 seconds
- ✓ Xray reload: < 3 seconds (graceful, no downtime)

### Testing Requirements

- ✓ All integration tests pass (8/8 tests in test_proxy_integration.bats)
- ✓ All security tests pass (6/6 tests in test_proxy_security.bats)
- ✓ Performance test passes (user creation < 6 sec)
- ✓ RISK-11.1 detection commands pass (port isolation verified)
- ✓ RISK-11.2 detection commands pass (authentication verified)

### Weighted Success Score (Updated)

| Metric | Target | Weight | Status |
|--------|--------|--------|--------|
| **Proxy Functionality** | 100% | 12% | TBD |
| **Config Completeness** | 8 files/user | 8% | TBD |
| **User Creation Time** | < 6 sec | 22% | TBD |
| **Security Compliance** | 0 critical vulns | 20% | TBD |
| **Installation Time** | < 5 min | 18% | (Existing) |
| **Connection Reliability** | 99.5% uptime | 20% | (Existing) |

**Pass Threshold:** ≥ 85% weighted score

---

## Estimated Timeline

### Week 5: Proxy Integration (40 hours)

**Monday (8h):**
- TASK-11.1: SOCKS5 Proxy Inbound (8h)

**Tuesday (8h):**
- TASK-11.2: HTTP Proxy Inbound (8h)

**Wednesday (8h):**
- TASK-11.3: Proxy Password Generation (4h)
- TASK-11.6: Update Xray Config with 3 Inbounds (4h)

**Thursday (8h):**
- TASK-11.4: Proxy Configuration Export (8h)

**Friday (8h):**
- TASK-11.5: Proxy CLI Commands (6h)
- TASK-11.7: Proxy Functionality Testing (2h)

### Week 6: Integration & Testing (18 hours from 24)

**Monday (8h):**
- EPIC-3 TASK-3.3: Update (+4h)
- EPIC-6 TASK-6.1: Update (+2h)
- EPIC-6 TASK-6.3: Update (+2h)

**Tuesday (8h):**
- EPIC-6 TASK-6.4: Update (+2h)
- EPIC-7 TASK-7.5: New (6h)

**Wednesday (2h):**
- EPIC-7 TASK-7.6: Update (+1h)
- EPIC-7 TASK-7.7: New (1h)

**Total Extension:** 58 hours over 1.5 weeks

---

## File Structure Update

```
/opt/vless/
├── config/
│   ├── xray_config.json          # NOW: 3 inbounds (VLESS + SOCKS5 + HTTP)
│   └── nginx.conf                # No changes
├── data/
│   ├── users.json                # NOW: v1.1 schema with proxy_password field
│   └── clients/
│       └── <username>/
│           ├── vless_config.json    # Existing
│           ├── vless_uri.txt        # Existing
│           ├── qrcode.png           # Existing
│           ├── socks5_config.txt    # NEW: SOCKS5 connection string
│           ├── http_config.txt      # NEW: HTTP connection string
│           ├── vscode_settings.json # NEW: VSCode proxy config
│           ├── docker_daemon.json   # NEW: Docker proxy config
│           └── bash_exports.sh      # NEW: Bash environment variables

Development Structure:
/home/ikeniborn/Documents/Project/vless/lib/
├── orchestrator.sh           # Updated: generate_complete_xray_config()
├── user_management.sh        # Updated: create_user_with_proxy()
├── qr_generator.sh           # Updated: export_all_configs() (8 files)
├── service_operations.sh     # Updated: show proxy status
└── proxy_management.sh       # NEW: 600 lines, 15 functions
```

---

## Dependencies

### Before Starting

**Prerequisites:**
- EPIC-1 through EPIC-10 completed
- VLESS Reality working correctly
- All existing tests passing
- At least 1 test user created

**Tools Required:**
- Xray-core 24.11.30 (supports SOCKS5 + HTTP inbounds)
- jq 1.5+ (JSON processing)
- curl (proxy testing)
- netcat (nc) for port scanning
- openssl (password generation)

### Task Dependencies

```
TASK-11.1 (SOCKS5)  ─┐
                     ├─→ TASK-11.6 (3 Inbounds) ─→ TASK-11.3 (Password) ─→ TASK-11.4 (Export) ─→ TASK-11.5 (CLI)
TASK-11.2 (HTTP)    ─┘                                                                              │
                                                                                                     ├─→ TASK-11.7 (Testing)
EPIC-3.3 (UPDATED) ──────────────────────────────────────────────────────────────────────────────┘
EPIC-6 (UPDATED) ────────────────────────────────────────────────────────────────────────────────┘
EPIC-7 (UPDATED) ────────────────────────────────────────────────────────────────────────────────┘
```

---

## Notes

### Backward Compatibility

- **users.json v1.0 → v1.1:** Migration function provided (`migrate_users_json_to_v1_1()`)
- **Existing Users:** Need proxy password generation on first login after upgrade
- **VLESS Configs:** Unchanged, fully backward compatible
- **Xray Config:** Adding inbounds does not break existing VLESS inbound

### Future Enhancements (Out of Scope)

- Web-based proxy configuration UI
- Proxy usage statistics per user
- Dynamic port allocation (instead of fixed 1080/8118)
- SOCKS4 support (only SOCKS5 in v1.1)
- Proxy chaining capabilities
- Per-application proxy rules

---

**END OF EXTENSION PLAN**

This extension plan adds proxy server functionality while maintaining full backward compatibility with the existing VLESS Reality VPN system. Total extension effort: 58 hours over 1.5 weeks.

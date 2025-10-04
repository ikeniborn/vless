# Implementation Plan: v3.1 → v3.2 (Public Proxy Support)

**Project:** VLESS Reality VPN - Public Proxy Migration
**Version:** 3.2
**Date:** 2025-10-04
**Branch:** `proxy-public` (feature branch)
**Base Branch:** `proxy` (v3.1)
**Estimated Total Time:** 12-16 hours

---

## Executive Summary

### Scope of Changes

**Architectural Change:** Transform localhost-only proxy (127.0.0.1) to publicly accessible proxy (0.0.0.0)

**Impact:**
- 🔴 **BREAKING CHANGE:** All v3.1 proxy configs become invalid
- 🟡 **Security Risk:** Public internet exposure requires fail2ban + rate limiting
- 🟢 **User Benefit:** Proxy accessible without VPN connection

**Files Modified:** 7 files (~250 lines)
**New Files:** 1 module (`lib/fail2ban_setup.sh`, ~150 lines)
**Tests Required:** 8 integration tests + 3 security tests

---

## Implementation Phases

```
PHASE 1: Core Proxy Changes (4-6h)
  ├─ TASK-1.1: Update proxy inbound binding (1h)
  ├─ TASK-1.2: Enhance password generation (30min)
  ├─ TASK-1.3: Update config export functions (2h)
  └─ TASK-1.4: Update display functions (30min)

PHASE 2: Security Hardening (4-6h)
  ├─ TASK-2.1: Create fail2ban module (3h)
  ├─ TASK-2.2: Update UFW firewall rules (1h)
  ├─ TASK-2.3: Add Docker healthchecks (1h)
  └─ TASK-2.4: Update dependencies (30min)

PHASE 3: Installation Flow (2-3h)
  ├─ TASK-3.1: Add interactive prompt (1h)
  ├─ TASK-3.2: Conditional proxy activation (1h)
  └─ TASK-3.3: Integration with install.sh (30min)

PHASE 4: Testing & Documentation (2-3h)
  ├─ TASK-4.1: Integration tests (1h)
  ├─ TASK-4.2: Security tests (1h)
  └─ TASK-4.3: Update documentation (1h)
```

---

## PHASE 1: Core Proxy Changes (4-6 hours)

### TASK-1.1: Update Proxy Inbound Binding (1 hour)

**File:** `lib/orchestrator.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~8

#### Changes Required

**Change 1: SOCKS5 Inbound Listen Address**
```bash
# Location: lib/orchestrator.sh:303
# BEFORE (v3.1):
"listen": "127.0.0.1",

# AFTER (v3.2):
"listen": "0.0.0.0",
```

**Change 2: SOCKS5 IP Setting**
```bash
# Location: lib/orchestrator.sh:310
# BEFORE (v3.1):
"ip": "127.0.0.1"

# AFTER (v3.2):
"ip": "0.0.0.0"
```

**Change 3: HTTP Inbound Listen Address**
```bash
# Location: lib/orchestrator.sh:331
# BEFORE (v3.1):
"listen": "127.0.0.1",

# AFTER (v3.2):
"listen": "0.0.0.0",
```

**Change 4: Update Console Output Messages**
```bash
# Location: lib/orchestrator.sh:430-431
# BEFORE (v3.1):
echo "  ✓ SOCKS5 Proxy enabled (127.0.0.1:1080)"
echo "  ✓ HTTP Proxy enabled (127.0.0.1:8118)"

# AFTER (v3.2):
local server_ip
server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
echo "  ✓ SOCKS5 Proxy enabled (0.0.0.0:1080) - Public Access"
echo "  ✓ HTTP Proxy enabled (0.0.0.0:8118) - Public Access"
echo "  ✓ External URI: socks5://user:pass@${server_ip}:1080"
```

#### Implementation Steps

1. Open `lib/orchestrator.sh`
2. Locate `generate_socks5_inbound_json()` function (line 299)
3. Change line 303: `"listen": "127.0.0.1"` → `"listen": "0.0.0.0"`
4. Change line 310: `"ip": "127.0.0.1"` → `"ip": "0.0.0.0"`
5. Locate `generate_http_inbound_json()` function (line 327)
6. Change line 331: `"listen": "127.0.0.1"` → `"listen": "0.0.0.0"`
7. Update console messages in `create_xray_config()` (lines 430-431)
8. Validate JSON syntax: `jq . /opt/vless/config/xray_config.json`

#### Acceptance Criteria

- [ ] SOCKS5 inbound listens on `0.0.0.0:1080`
- [ ] HTTP inbound listens on `0.0.0.0:8118`
- [ ] JSON syntax valid (`jq` validation passes)
- [ ] Console output shows "Public Access" warning

---

### TASK-1.2: Enhance Password Generation (30 minutes)

**File:** `lib/user_management.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~2

#### Changes Required

**Change 1: Update generate_proxy_password() Function**
```bash
# Location: lib/user_management.sh:155
# BEFORE (v3.1):
generate_proxy_password() {
    openssl rand -hex 8
}

# AFTER (v3.2):
generate_proxy_password() {
    openssl rand -hex 16    # 32 characters (16 bytes * 2 hex chars)
}
```

#### Implementation Steps

1. Open `lib/user_management.sh`
2. Locate `generate_proxy_password()` function (around line 150)
3. Change `openssl rand -hex 8` → `openssl rand -hex 16`
4. Update function comment to reflect 32-character output
5. Test password generation:
   ```bash
   password=$(openssl rand -hex 16)
   echo ${#password}  # Should output: 32
   ```

#### Acceptance Criteria

- [ ] New passwords are 32 characters long
- [ ] Passwords are hexadecimal (0-9, a-f)
- [ ] Function comment updated
- [ ] Test validates 32-char output

---

### TASK-1.3: Update Config Export Functions (2 hours)

**File:** `lib/user_management.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~15

#### Changes Required

All 5 export functions must replace `127.0.0.1` with `SERVER_IP` variable.

**Step 1: Add SERVER_IP Detection Helper**
```bash
# Location: lib/user_management.sh (before export functions, ~line 825)
# NEW FUNCTION:

# =============================================================================
# FUNCTION: get_server_ip
# =============================================================================
# Description: Get external server IP address
# Returns: IP address string or "SERVER_IP" fallback
# =============================================================================
get_server_ip() {
    local server_ip

    # Try multiple IP detection services for reliability
    server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)

    if [[ -z "$server_ip" ]]; then
        server_ip=$(curl -s --max-time 5 api.ipify.org 2>/dev/null)
    fi

    if [[ -z "$server_ip" ]]; then
        server_ip=$(curl -s --max-time 5 icanhazip.com 2>/dev/null)
    fi

    # Fallback if all services fail
    if [[ -z "$server_ip" ]]; then
        log_warning "Failed to detect external IP, using placeholder"
        server_ip="SERVER_IP"
    fi

    echo "$server_ip"
}
```

**Step 2: Update export_socks5_config()**
```bash
# Location: lib/user_management.sh:851
# BEFORE (v3.1):
echo "socks5://${username}:${password}@127.0.0.1:1080" \
    > "$output_dir/socks5_config.txt"

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)
echo "socks5://${username}:${password}@${server_ip}:1080" \
    > "$output_dir/socks5_config.txt"
```

**Step 3: Update export_http_config()**
```bash
# Location: lib/user_management.sh:880
# BEFORE (v3.1):
echo "http://${username}:${password}@127.0.0.1:8118" \
    > "$output_dir/http_config.txt"

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)
echo "http://${username}:${password}@${server_ip}:8118" \
    > "$output_dir/http_config.txt"
```

**Step 4: Update export_vscode_config()**
```bash
# Location: lib/user_management.sh:911
# BEFORE (v3.1):
  "http.proxy": "socks5://${username}:${password}@127.0.0.1:1080",

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)

cat > "$output_dir/vscode_settings.json" <<EOF
{
  "http.proxy": "socks5://${username}:${password}@${server_ip}:1080",
  "http.proxyStrictSSL": false,
  "http.proxySupport": "on"
}
EOF
```

**Step 5: Update export_docker_config()**
```bash
# Location: lib/user_management.sh:947-948
# BEFORE (v3.1):
      "httpProxy": "http://${username}:${password}@127.0.0.1:8118",
      "httpsProxy": "http://${username}:${password}@127.0.0.1:8118",

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)

cat > "$output_dir/docker_daemon.json" <<EOF
{
  "proxies": {
    "default": {
      "httpProxy": "http://${username}:${password}@${server_ip}:8118",
      "httpsProxy": "http://${username}:${password}@${server_ip}:8118",
      "noProxy": "localhost,127.0.0.0/8"
    }
  }
}
EOF
```

**Step 6: Update export_bash_config()**
```bash
# Location: lib/user_management.sh:986-987
# BEFORE (v3.1):
export http_proxy="http://${username}:${password}@127.0.0.1:8118"
export https_proxy="http://${username}:${password}@127.0.0.1:8118"

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)

cat > "$output_dir/bash_exports.sh" <<EOF
#!/bin/bash
# VLESS Reality Proxy Configuration (v3.2 - Public Access)
# Usage: source bash_exports.sh

export http_proxy="http://${username}:${password}@${server_ip}:8118"
export https_proxy="http://${username}:${password}@${server_ip}:8118"
export HTTP_PROXY="\$http_proxy"
export HTTPS_PROXY="\$https_proxy"
export NO_PROXY="localhost,127.0.0.0/8"

echo "Proxy environment variables set (v3.2 - Public Access):"
echo "  http_proxy=\$http_proxy"
echo "  https_proxy=\$https_proxy"
EOF
```

#### Implementation Steps

1. Open `lib/user_management.sh`
2. Add `get_server_ip()` function before export functions
3. Update all 5 export functions to use `get_server_ip()`
4. Replace all `127.0.0.1` with `${server_ip}` variable
5. Test IP detection: `bash -c "source lib/user_management.sh; get_server_ip"`
6. Verify output contains valid IP or "SERVER_IP" fallback

#### Acceptance Criteria

- [ ] `get_server_ip()` function added
- [ ] All 5 export functions use `get_server_ip()`
- [ ] No hardcoded `127.0.0.1` in any export function
- [ ] IP detection works with 3 fallback services
- [ ] Config files contain external IP address

---

### TASK-1.4: Update Display Functions (30 minutes)

**File:** `lib/user_management.sh`
**Priority:** 🟡 MEDIUM
**Lines Changed:** ~10

#### Changes Required

**Update show_proxy_credentials() Function**
```bash
# Location: lib/user_management.sh:658-675
# BEFORE (v3.1):
echo "SOCKS5 Proxy:"
echo "  Host:     127.0.0.1"
echo "  Port:     1080"
echo "  URI:      socks5://${username}:${proxy_password}@127.0.0.1:1080"
echo ""
echo "HTTP Proxy:"
echo "  Host:     127.0.0.1"
echo "  Port:     8118"
echo "  URI:      http://${username}:${proxy_password}@127.0.0.1:8118"
echo ""
echo "Usage Examples:"
echo "  curl --socks5 ${username}:${proxy_password}@127.0.0.1:1080 https://ifconfig.me"
echo "  curl --proxy http://${username}:${proxy_password}@127.0.0.1:8118 https://ifconfig.me"
echo ""
echo "VSCode (settings.json):"
echo "  \"http.proxy\": \"http://${username}:${proxy_password}@127.0.0.1:8118\""

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)

echo "SOCKS5 Proxy (PUBLIC ACCESS):"
echo "  Host:     ${server_ip}"
echo "  Port:     1080"
echo "  URI:      socks5://${username}:${proxy_password}@${server_ip}:1080"
echo ""
echo "HTTP Proxy (PUBLIC ACCESS):"
echo "  Host:     ${server_ip}"
echo "  Port:     8118"
echo "  URI:      http://${username}:${proxy_password}@${server_ip}:8118"
echo ""
echo "Usage Examples:"
echo "  curl --socks5 ${username}:${proxy_password}@${server_ip}:1080 https://ifconfig.me"
echo "  curl --proxy http://${username}:${proxy_password}@${server_ip}:8118 https://ifconfig.me"
echo ""
echo "VSCode (settings.json):"
echo "  \"http.proxy\": \"socks5://${username}:${proxy_password}@${server_ip}:1080\""
```

**Update reset_proxy_password() Function**
```bash
# Location: lib/user_management.sh:815-816
# BEFORE (v3.1):
echo "SOCKS5: socks5://${username}:${new_password}@127.0.0.1:1080"
echo "HTTP:   http://${username}:${new_password}@127.0.0.1:8118"

# AFTER (v3.2):
local server_ip
server_ip=$(get_server_ip)
echo "SOCKS5: socks5://${username}:${new_password}@${server_ip}:1080"
echo "HTTP:   http://${username}:${new_password}@${server_ip}:8118"
```

#### Implementation Steps

1. Open `lib/user_management.sh`
2. Locate `show_proxy_credentials()` function
3. Add `get_server_ip()` call at function start
4. Replace all `127.0.0.1` with `${server_ip}`
5. Add "PUBLIC ACCESS" labels to output
6. Repeat for `reset_proxy_password()` function

#### Acceptance Criteria

- [ ] Display functions use `get_server_ip()`
- [ ] "PUBLIC ACCESS" warning visible in output
- [ ] No `127.0.0.1` in user-facing messages
- [ ] Examples use external IP

---

## PHASE 2: Security Hardening (4-6 hours)

### TASK-2.1: Create Fail2ban Module (3 hours)

**File:** `lib/fail2ban_setup.sh` (NEW)
**Priority:** 🔴 CRITICAL
**Lines:** ~150 new lines

#### Complete Module Implementation

```bash
#!/bin/bash
################################################################################
# VLESS Reality VPN - Fail2ban Setup Module
#
# Description:
#   Installs and configures fail2ban to protect SOCKS5 and HTTP proxy ports
#   from brute-force authentication attacks.
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 10+
#   - Root privileges
#   - Xray error logs at /opt/vless/logs/xray/error.log
#
# Features:
#   - Auto-install fail2ban if missing
#   - Create custom filter for Xray authentication failures
#   - Configure jails for SOCKS5 (1080) and HTTP (8118)
#   - Ban after 5 failed attempts for 1 hour
#
# Version: 3.2
# Date: 2025-10-04
################################################################################

set -euo pipefail

# Import colors (if available)
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/colors.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# =============================================================================
# FUNCTION: check_fail2ban_installed
# =============================================================================
# Description: Check if fail2ban is installed
# Returns: 0 if installed, 1 if not installed
# =============================================================================
check_fail2ban_installed() {
    if command -v fail2ban-server &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# FUNCTION: install_fail2ban
# =============================================================================
# Description: Install fail2ban package
# Returns: 0 on success, 1 on failure
# =============================================================================
install_fail2ban() {
    echo -e "${CYAN}Installing fail2ban...${NC}"

    # Update package list
    if ! apt-get update -qq; then
        echo -e "${RED}Failed to update package list${NC}" >&2
        return 1
    fi

    # Install fail2ban
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban; then
        echo -e "${RED}Failed to install fail2ban${NC}" >&2
        return 1
    fi

    # Enable and start service
    systemctl enable fail2ban &>/dev/null || true
    systemctl start fail2ban || true

    echo -e "${GREEN}✓ Fail2ban installed${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_vless_proxy_filter
# =============================================================================
# Description: Create custom fail2ban filter for Xray proxy authentication
# Returns: 0 on success, 1 on failure
# =============================================================================
create_vless_proxy_filter() {
    echo -e "${CYAN}Creating fail2ban filter for VLESS proxy...${NC}"

    local filter_file="/etc/fail2ban/filter.d/vless-proxy.conf"

    cat > "$filter_file" <<'EOF'
# Fail2ban filter for VLESS Reality Proxy (SOCKS5 + HTTP)
#
# Matches Xray authentication failure patterns in error logs
#
# Author: VLESS Reality VPN v3.2
# Date: 2025-10-04

[Definition]

# Match authentication failures in Xray logs
failregex = ^.* rejected .* from <HOST>.*$
            ^.* authentication failed .* from <HOST>.*$
            ^.* invalid credentials .* from <HOST>.*$
            ^.* proxy: failed to .* from <HOST>.*$

# Ignore successful connections
ignoreregex = ^.* accepted .* from .*$
              ^.* established .* from .*$
EOF

    if [[ ! -f "$filter_file" ]]; then
        echo -e "${RED}Failed to create filter file${NC}" >&2
        return 1
    fi

    chmod 644 "$filter_file"
    echo -e "${GREEN}✓ Filter created: $filter_file${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_vless_proxy_jails
# =============================================================================
# Description: Create fail2ban jails for SOCKS5 and HTTP proxy
# Returns: 0 on success, 1 on failure
# =============================================================================
create_vless_proxy_jails() {
    echo -e "${CYAN}Creating fail2ban jails for proxy ports...${NC}"

    local jail_file="/etc/fail2ban/jail.d/vless-proxy.conf"

    cat > "$jail_file" <<'EOF'
# Fail2ban jails for VLESS Reality Proxy
#
# Protects SOCKS5 (1080) and HTTP (8118) proxy ports from brute-force attacks
#
# Configuration:
#   - maxretry: 5 failed attempts
#   - bantime: 3600 seconds (1 hour)
#   - findtime: 600 seconds (10 minutes)
#
# Author: VLESS Reality VPN v3.2
# Date: 2025-10-04

[vless-socks5]
enabled  = true
port     = 1080
protocol = tcp
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600
action   = iptables-multiport[name=vless-socks5, port="1080", protocol=tcp]

[vless-http]
enabled  = true
port     = 8118
protocol = tcp
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600
action   = iptables-multiport[name=vless-http, port="8118", protocol=tcp]
EOF

    if [[ ! -f "$jail_file" ]]; then
        echo -e "${RED}Failed to create jail file${NC}" >&2
        return 1
    fi

    chmod 644 "$jail_file"
    echo -e "${GREEN}✓ Jails created: $jail_file${NC}"
    return 0
}

# =============================================================================
# FUNCTION: reload_fail2ban
# =============================================================================
# Description: Reload fail2ban to apply new configuration
# Returns: 0 on success, 1 on failure
# =============================================================================
reload_fail2ban() {
    echo -e "${CYAN}Reloading fail2ban...${NC}"

    if ! systemctl reload fail2ban; then
        echo -e "${YELLOW}Reload failed, trying restart...${NC}"
        if ! systemctl restart fail2ban; then
            echo -e "${RED}Failed to restart fail2ban${NC}" >&2
            return 1
        fi
    fi

    # Wait for service to stabilize
    sleep 2

    echo -e "${GREEN}✓ Fail2ban reloaded${NC}"
    return 0
}

# =============================================================================
# FUNCTION: verify_fail2ban_jails
# =============================================================================
# Description: Verify that VLESS proxy jails are active
# Returns: 0 if both jails active, 1 if any jail inactive
# =============================================================================
verify_fail2ban_jails() {
    echo -e "${CYAN}Verifying fail2ban jails...${NC}"

    local socks5_status
    local http_status

    socks5_status=$(fail2ban-client status vless-socks5 2>/dev/null || echo "FAIL")
    http_status=$(fail2ban-client status vless-http 2>/dev/null || echo "FAIL")

    if [[ "$socks5_status" == "FAIL" ]]; then
        echo -e "${RED}✗ SOCKS5 jail not active${NC}"
        return 1
    fi

    if [[ "$http_status" == "FAIL" ]]; then
        echo -e "${RED}✗ HTTP jail not active${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Both jails active (vless-socks5, vless-http)${NC}"
    return 0
}

# =============================================================================
# FUNCTION: setup_fail2ban_for_proxy
# =============================================================================
# Description: Main entry point - complete fail2ban setup for VLESS proxy
# Returns: 0 on success, 1 on failure
# =============================================================================
setup_fail2ban_for_proxy() {
    echo ""
    echo "═════════════════════════════════════════════════════"
    echo "  FAIL2BAN SETUP (v3.2 - Public Proxy Protection)"
    echo "═════════════════════════════════════════════════════"
    echo ""

    # Check if fail2ban is installed
    if ! check_fail2ban_installed; then
        echo -e "${YELLOW}Fail2ban not found, installing...${NC}"
        if ! install_fail2ban; then
            echo -e "${RED}Failed to install fail2ban${NC}" >&2
            return 1
        fi
    else
        echo -e "${GREEN}✓ Fail2ban already installed${NC}"
    fi

    # Create filter
    if ! create_vless_proxy_filter; then
        return 1
    fi

    # Create jails
    if ! create_vless_proxy_jails; then
        return 1
    fi

    # Reload fail2ban
    if ! reload_fail2ban; then
        return 1
    fi

    # Verify jails
    if ! verify_fail2ban_jails; then
        echo -e "${YELLOW}Warning: Jails verification failed${NC}"
        echo -e "${YELLOW}Check fail2ban logs: journalctl -u fail2ban -n 50${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ Fail2ban setup complete${NC}"
    echo ""
    echo "Configuration:"
    echo "  - SOCKS5 jail active (port 1080)"
    echo "  - HTTP jail active (port 8118)"
    echo "  - Max retries: 5"
    echo "  - Ban time: 3600 seconds (1 hour)"
    echo "  - Find time: 600 seconds (10 minutes)"
    echo ""
    echo "Monitor banned IPs:"
    echo "  sudo fail2ban-client status vless-socks5"
    echo "  sudo fail2ban-client status vless-http"
    echo "═════════════════════════════════════════════════════"
    echo ""

    return 0
}

# Export functions for use in other modules
export -f check_fail2ban_installed
export -f install_fail2ban
export -f create_vless_proxy_filter
export -f create_vless_proxy_jails
export -f reload_fail2ban
export -f verify_fail2ban_jails
export -f setup_fail2ban_for_proxy
```

#### Implementation Steps

1. Create new file: `lib/fail2ban_setup.sh`
2. Copy complete module code above
3. Set executable permissions: `chmod 755 lib/fail2ban_setup.sh`
4. Test syntax: `bash -n lib/fail2ban_setup.sh`
5. Test installation (dry run):
   ```bash
   source lib/fail2ban_setup.sh
   check_fail2ban_installed && echo "Already installed" || echo "Not installed"
   ```

#### Acceptance Criteria

- [ ] Module file created and executable
- [ ] All 7 functions implemented
- [ ] Filter file template correct
- [ ] Jail file template correct
- [ ] Syntax validation passes
- [ ] Functions exported

---

### TASK-2.2: Update UFW Firewall Rules (1 hour)

**File:** `lib/orchestrator.sh` or new `lib/firewall_setup.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~30

#### Implementation

**Option A: Add to orchestrator.sh** (Recommended)

```bash
# Location: lib/orchestrator.sh (after create_xray_config function)

# =============================================================================
# FUNCTION: configure_proxy_firewall_rules
# =============================================================================
# Description: Open UFW ports for public proxy access with rate limiting
# Arguments:
#   None (uses global ENABLE_PUBLIC_PROXY variable)
# Returns: 0 on success, 1 on failure
# Related: v3.2 Public Proxy Support
# =============================================================================
configure_proxy_firewall_rules() {
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" != "true" ]]; then
        log_info "Public proxy disabled, skipping firewall rules"
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
    if ! ufw reload; then
        echo -e "${YELLOW}Warning: Failed to reload UFW${NC}"
    fi

    echo -e "${GREEN}✓ Firewall configured for public proxy${NC}"
    echo ""
    echo "Active proxy ports:"
    ufw status numbered | grep -E "(1080|8118)/tcp"
    echo ""

    return 0
}

export -f configure_proxy_firewall_rules
```

#### Implementation Steps

1. Open `lib/orchestrator.sh`
2. Add `configure_proxy_firewall_rules()` function after line ~436
3. Update `install.sh` or main orchestration to call this function
4. Test UFW rule creation:
   ```bash
   sudo ufw limit 1080/tcp comment 'Test'
   sudo ufw status numbered | grep 1080
   sudo ufw delete <rule_number>
   ```

#### Acceptance Criteria

- [ ] Function `configure_proxy_firewall_rules()` added
- [ ] SOCKS5 rule uses `ufw limit` (not `ufw allow`)
- [ ] HTTP rule uses `ufw limit` (not `ufw allow`)
- [ ] Rules include comments for clarity
- [ ] Duplicate rules not created
- [ ] UFW reloads successfully

---

### TASK-2.3: Add Docker Healthchecks (1 hour)

**File:** `lib/orchestrator.sh`
**Priority:** 🟡 MEDIUM
**Lines Changed:** ~15

#### Changes Required

**Update create_docker_compose() Function**

```bash
# Location: lib/orchestrator.sh (create_docker_compose function)
# Add healthcheck to xray service definition

# BEFORE (v3.1):
services:
  xray:
    image: ${XRAY_IMAGE}
    container_name: ${XRAY_CONTAINER}
    restart: unless-stopped
    # ... rest of config

# AFTER (v3.2):
services:
  xray:
    image: ${XRAY_IMAGE}
    container_name: ${XRAY_CONTAINER}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "nc -z 127.0.0.1 1080 && nc -z 127.0.0.1 8118 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    # ... rest of config
```

**Note:** Healthcheck tests localhost (127.0.0.1) even though proxy binds to 0.0.0.0. This is correct - we test internal availability.

#### Implementation Steps

1. Open `lib/orchestrator.sh`
2. Locate `create_docker_compose()` function
3. Find Xray service definition in docker-compose.yml template
4. Add `healthcheck` block after `restart: unless-stopped`
5. Ensure `netcat` (nc) is available in container (usually pre-installed)
6. Test healthcheck syntax:
   ```bash
   docker run --rm teddysun/xray:24.11.30 sh -c "command -v nc"
   # Should return: /usr/bin/nc or similar
   ```

#### Acceptance Criteria

- [ ] Healthcheck added to Xray service
- [ ] Test command uses `nc -z` (connection test)
- [ ] Interval: 30 seconds
- [ ] Timeout: 10 seconds
- [ ] Retries: 3
- [ ] Start period: 10 seconds
- [ ] Docker Compose validates successfully

---

### TASK-2.4: Update Dependencies (30 minutes)

**File:** `lib/dependencies.sh`
**Priority:** 🟡 MEDIUM
**Lines Changed:** ~10

#### Changes Required

**Add fail2ban to Dependency Check**

```bash
# Location: lib/dependencies.sh (check_dependencies function or similar)

# BEFORE (v3.1):
REQUIRED_PACKAGES=(
    "docker.io"
    "docker-compose"
    "ufw"
    "jq"
    "qrencode"
)

# AFTER (v3.2):
REQUIRED_PACKAGES=(
    "docker.io"
    "docker-compose"
    "ufw"
    "jq"
    "qrencode"
    "fail2ban"    # v3.2: Public proxy protection
    "netcat"      # v3.2: Healthcheck support
)
```

**Update Installation Logic**

```bash
# Add conditional fail2ban installation
if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
    if ! command -v fail2ban-server &>/dev/null; then
        echo "Installing fail2ban (required for public proxy)..."
        apt-get install -y fail2ban
    fi
fi

# Verify netcat for healthchecks
if ! command -v nc &>/dev/null; then
    echo "Installing netcat..."
    apt-get install -y netcat
fi
```

#### Implementation Steps

1. Open `lib/dependencies.sh`
2. Locate `REQUIRED_PACKAGES` array or similar
3. Add `fail2ban` and `netcat` to list
4. Update dependency check logic to be conditional on `ENABLE_PUBLIC_PROXY`
5. Test dependency detection:
   ```bash
   command -v fail2ban-server && echo "Found" || echo "Not found"
   command -v nc && echo "Found" || echo "Not found"
   ```

#### Acceptance Criteria

- [ ] `fail2ban` added to dependency list
- [ ] `netcat` added to dependency list
- [ ] Installation conditional on `ENABLE_PUBLIC_PROXY`
- [ ] Dependency check validates versions
- [ ] Error messages clear if dependencies missing

---

## PHASE 3: Installation Flow (2-3 hours)

### TASK-3.1: Add Interactive Prompt (1 hour)

**File:** `lib/interactive_params.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~40

#### Implementation

**Add Function: prompt_enable_public_proxy()**

```bash
# Location: lib/interactive_params.sh (after existing prompt functions)

# =============================================================================
# FUNCTION: prompt_enable_public_proxy
# =============================================================================
# Description: Ask user if they want to enable public proxy access
# Sets: ENABLE_PUBLIC_PROXY (true/false)
# Returns: 0 always
# Related: v3.2 Public Proxy Support
# =============================================================================
prompt_enable_public_proxy() {
    echo ""
    echo "═════════════════════════════════════════════════════"
    echo "  PROXY CONFIGURATION (v3.2)"
    echo "═════════════════════════════════════════════════════"
    echo ""
    echo "VLESS Reality supports dual proxy modes:"
    echo ""
    echo "1. VLESS-ONLY MODE (default, safer):"
    echo "   - Only VLESS VPN available"
    echo "   - No SOCKS5/HTTP proxies"
    echo "   - Best for VPN-only use cases"
    echo ""
    echo "2. PUBLIC PROXY MODE (v3.2 feature):"
    echo "   - SOCKS5 + HTTP proxies accessible from internet"
    echo "   - No VPN client required"
    echo "   - Requires fail2ban and rate limiting"
    echo ""
    echo "⚠️  WARNING: Public proxy exposes ports 1080 and 8118"
    echo "⚠️  to the internet. Ensure your server can handle"
    echo "⚠️  potential abuse and DDoS attempts."
    echo ""
    echo "Security measures (auto-configured if YES):"
    echo "  ✓ Fail2ban (ban after 5 failed auth attempts)"
    echo "  ✓ UFW rate limiting (10 connections/min per IP)"
    echo "  ✓ 32-character passwords (vs 16 in v3.1)"
    echo ""

    local response
    while true; do
        read -r -p "Enable public proxy access? [y/N]: " response
        response=${response,,}  # Convert to lowercase

        case "$response" in
            y|yes)
                echo ""
                echo "⚠️  FINAL CONFIRMATION ⚠️"
                echo ""
                echo "You are about to enable PUBLIC INTERNET access to"
                echo "SOCKS5 (port 1080) and HTTP (port 8118) proxies."
                echo ""
                echo "This means ANYONE on the internet can ATTEMPT to"
                echo "connect to your proxy (authentication still required)."
                echo ""
                echo "Recommended for:"
                echo "  ✓ Private VPS with trusted users"
                echo "  ✓ Development/testing environments"
                echo "  ✓ Users who cannot install VPN clients"
                echo ""
                echo "NOT recommended for:"
                echo "  ✗ Shared hosting environments"
                echo "  ✗ Servers with weak DDoS protection"
                echo "  ✗ Compliance-sensitive deployments"
                echo ""

                read -r -p "Proceed with public proxy? [y/N]: " confirm
                confirm=${confirm,,}

                if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
                    ENABLE_PUBLIC_PROXY="true"
                    echo ""
                    echo -e "${GREEN}✓ Public proxy mode enabled${NC}"
                    echo ""
                    echo "Next steps:"
                    echo "  1. Fail2ban will be installed"
                    echo "  2. UFW ports 1080, 8118 will be opened"
                    echo "  3. All passwords will be 32 characters"
                    echo ""
                    break
                else
                    echo ""
                    echo "Public proxy canceled, falling back to VLESS-only mode"
                    ENABLE_PUBLIC_PROXY="false"
                    break
                fi
                ;;
            n|no|"")
                ENABLE_PUBLIC_PROXY="false"
                echo ""
                echo -e "${GREEN}✓ VLESS-only mode (no public proxy)${NC}"
                echo ""
                break
                ;;
            *)
                echo "Invalid response. Please enter 'y' or 'n'"
                ;;
        esac
    done

    export ENABLE_PUBLIC_PROXY
    return 0
}

export -f prompt_enable_public_proxy
```

#### Implementation Steps

1. Open `lib/interactive_params.sh`
2. Add `prompt_enable_public_proxy()` function
3. Update main interactive flow to call this function
4. Test interactive prompt:
   ```bash
   source lib/interactive_params.sh
   prompt_enable_public_proxy
   echo "Result: $ENABLE_PUBLIC_PROXY"
   ```

#### Acceptance Criteria

- [ ] Function `prompt_enable_public_proxy()` added
- [ ] Double confirmation for YES response
- [ ] Clear warnings about security risks
- [ ] Default is NO (safer)
- [ ] `ENABLE_PUBLIC_PROXY` exported
- [ ] Prompt works in interactive mode

---

### TASK-3.2: Conditional Proxy Activation (1 hour)

**File:** `lib/orchestrator.sh` and `install.sh`
**Priority:** 🔴 CRITICAL
**Lines Changed:** ~20

#### Changes Required

**Update create_xray_config() Call**

```bash
# Location: install.sh or orchestrator main flow

# BEFORE (v3.1):
create_xray_config "true"  # Always enable proxy

# AFTER (v3.2):
if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
    create_xray_config "true"
else
    create_xray_config "false"  # VLESS-only mode
fi
```

**Update Installation Flow**

```bash
# Location: install.sh (main installation sequence)

# After interactive parameter collection:
if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
    # Setup fail2ban BEFORE creating configs
    source lib/fail2ban_setup.sh
    setup_fail2ban_for_proxy || {
        echo "Fail2ban setup failed. Aborting public proxy installation."
        exit 1
    }

    # Configure firewall rules
    configure_proxy_firewall_rules || {
        echo "Firewall configuration failed. Aborting public proxy installation."
        exit 1
    }
fi

# Then proceed with normal installation
create_directory_structure
generate_reality_keys
# ... etc
```

#### Implementation Steps

1. Open `install.sh`
2. Locate main installation flow
3. Add conditional logic after parameter collection
4. Call `setup_fail2ban_for_proxy` if public proxy enabled
5. Call `configure_proxy_firewall_rules` if public proxy enabled
6. Pass `ENABLE_PUBLIC_PROXY` to `create_xray_config()`

#### Acceptance Criteria

- [ ] Fail2ban setup called ONLY if public proxy enabled
- [ ] Firewall rules added ONLY if public proxy enabled
- [ ] VLESS-only mode works without proxy inbounds
- [ ] Public proxy mode creates 3 inbounds (VLESS + SOCKS5 + HTTP)
- [ ] Installation fails gracefully if fail2ban setup fails

---

### TASK-3.3: Integration with install.sh (30 minutes)

**File:** `install.sh`
**Priority:** 🟡 MEDIUM
**Lines Changed:** ~15

#### Changes Required

**Source New Module**

```bash
# Location: install.sh (module sourcing section, ~line 150)

# BEFORE (v3.1):
source "${SCRIPT_DIR}/lib/os_detection.sh"
source "${SCRIPT_DIR}/lib/dependencies.sh"
source "${SCRIPT_DIR}/lib/old_install_detect.sh"
source "${SCRIPT_DIR}/lib/interactive_params.sh"
source "${SCRIPT_DIR}/lib/orchestrator.sh"
source "${SCRIPT_DIR}/lib/verification.sh"

# AFTER (v3.2):
source "${SCRIPT_DIR}/lib/os_detection.sh"
source "${SCRIPT_DIR}/lib/dependencies.sh"
source "${SCRIPT_DIR}/lib/old_install_detect.sh"
source "${SCRIPT_DIR}/lib/interactive_params.sh"
source "${SCRIPT_DIR}/lib/fail2ban_setup.sh"     # v3.2: Public proxy security
source "${SCRIPT_DIR}/lib/orchestrator.sh"
source "${SCRIPT_DIR}/lib/verification.sh"
```

**Update Installation Summary**

```bash
# Location: install.sh (final summary output, ~line 400)

# Add to summary:
echo ""
echo "Proxy Configuration:"
if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
    echo "  Mode:           Public Access (v3.2)"
    echo "  SOCKS5:         0.0.0.0:1080 (public)"
    echo "  HTTP:           0.0.0.0:8118 (public)"
    echo "  Security:"
    echo "    - Fail2ban:   ✓ Active (5 retries, 1h ban)"
    echo "    - Rate Limit: ✓ Active (10/min per IP)"
    echo "    - Password:   32 characters"
else
    echo "  Mode:           VLESS-only (no proxy)"
fi
```

#### Implementation Steps

1. Open `install.sh`
2. Add `source lib/fail2ban_setup.sh` to module loading
3. Update final summary to include proxy configuration
4. Test module loading:
   ```bash
   bash -n install.sh  # Syntax check
   ```

#### Acceptance Criteria

- [ ] `fail2ban_setup.sh` sourced correctly
- [ ] Module loading order correct
- [ ] Final summary shows proxy mode
- [ ] Syntax validation passes

---

## PHASE 4: Testing & Documentation (2-3 hours)

### TASK-4.1: Integration Tests (1 hour)

**File:** `tests/integration/test_public_proxy.sh` (NEW)
**Priority:** 🔴 CRITICAL

#### Test Cases to Implement

**Test 1: Public Proxy Access**
```bash
#!/bin/bash
# Test: Verify proxy accessible from external IP

SERVER_IP=$(curl -s ifconfig.me)
USERNAME="testuser"
PASSWORD="$(openssl rand -hex 16)"

# Create test user
sudo vless-user add "$USERNAME"

# Wait for Xray reload
sleep 3

# Test SOCKS5 from external (simulate external client)
if curl --connect-timeout 10 --socks5 "${USERNAME}:${PASSWORD}@${SERVER_IP}:1080" https://ifconfig.me; then
    echo "✓ SOCKS5 proxy accessible"
else
    echo "✗ SOCKS5 proxy NOT accessible"
    exit 1
fi

# Test HTTP proxy
if curl --connect-timeout 10 --proxy "http://${USERNAME}:${PASSWORD}@${SERVER_IP}:8118" https://ifconfig.me; then
    echo "✓ HTTP proxy accessible"
else
    echo "✗ HTTP proxy NOT accessible"
    exit 1
fi

echo "✓ Test passed: Public proxy access works"
```

**Test 2: Fail2ban Protection**
```bash
#!/bin/bash
# Test: Verify fail2ban blocks after 5 failed attempts

SERVER_IP=$(curl -s ifconfig.me)
USERNAME="testuser"

# Attempt 6 connections with wrong password
for i in {1..6}; do
    curl --connect-timeout 5 --socks5 "${USERNAME}:wrongpass@${SERVER_IP}:1080" https://ifconfig.me 2>/dev/null || true
    sleep 1
done

# Check if current IP is banned
BANNED_IPS=$(sudo fail2ban-client status vless-socks5 | grep "Banned IP list" | awk -F':' '{print $2}')

if echo "$BANNED_IPS" | grep -q "$(curl -s ifconfig.me)"; then
    echo "✓ Fail2ban correctly banned IP after failed attempts"

    # Unban for further testing
    sudo fail2ban-client unban "$(curl -s ifconfig.me)"
else
    echo "✗ Fail2ban did NOT ban IP (expected after 5 failures)"
    exit 1
fi

echo "✓ Test passed: Fail2ban protection works"
```

**Test 3: Config Files Validation**
```bash
#!/bin/bash
# Test: Verify all config files use SERVER_IP (not 127.0.0.1)

SERVER_IP=$(curl -s ifconfig.me)
USERNAME="testuser"
CONFIG_DIR="/opt/vless/data/clients/${USERNAME}"

# Check for 127.0.0.1 in config files (should be NONE)
if grep -r "127.0.0.1" "$CONFIG_DIR"/*.txt "$CONFIG_DIR"/*.json "$CONFIG_DIR"/*.sh 2>/dev/null; then
    echo "✗ Found 127.0.0.1 in config files (should use SERVER_IP)"
    exit 1
else
    echo "✓ No 127.0.0.1 found in config files"
fi

# Verify SERVER_IP is present
if grep -r "$SERVER_IP" "$CONFIG_DIR"/*.txt "$CONFIG_DIR"/*.json "$CONFIG_DIR"/*.sh 2>/dev/null; then
    echo "✓ SERVER_IP found in config files"
else
    echo "✗ SERVER_IP NOT found in config files"
    exit 1
fi

echo "✓ Test passed: Config files use SERVER_IP correctly"
```

#### Implementation Steps

1. Create `tests/integration/test_public_proxy.sh`
2. Implement all 3 test cases
3. Make executable: `chmod +x tests/integration/test_public_proxy.sh`
4. Run tests: `sudo ./tests/integration/test_public_proxy.sh`

#### Acceptance Criteria

- [ ] All 3 test cases implemented
- [ ] Tests executable
- [ ] Tests pass on fresh v3.2 installation
- [ ] Tests cleanup after themselves

---

### TASK-4.2: Security Tests (1 hour)

**Test Cases:**

1. **Port Scanning Test:**
   ```bash
   nmap -p 1-65535 <SERVER_IP>
   # Expected: Only 22, 443, 1080, 8118 open
   ```

2. **Password Strength Test:**
   ```bash
   jq -r '.users[].proxy_password | length' /opt/vless/config/users.json
   # Expected: All passwords = 32 characters
   ```

3. **UFW Rate Limiting Test:**
   ```bash
   # Rapid connection test (20 connections in 10 seconds)
   for i in {1..20}; do
       curl --connect-timeout 1 --socks5 user:pass@<SERVER_IP>:1080 https://ifconfig.me &
   done
   wait
   # Expected: Some connections rejected
   ```

#### Acceptance Criteria

- [ ] All security tests pass
- [ ] No unexpected ports open
- [ ] All passwords 32+ characters
- [ ] Rate limiting effective

---

### TASK-4.3: Update Documentation (1 hour)

**Files to Update:**

1. **README.md:**
   - Update version to 3.2
   - Add "Public Proxy" to features
   - Update installation instructions (mention prompt)
   - Add security warnings

2. **CLAUDE.md:**
   - Update PROJECT OVERVIEW to v3.2
   - Add FR-012 details (already done in this session)
   - Update security requirements
   - Add fail2ban configuration

3. **Create MIGRATION_v3.1_to_v3.2.md:**
   ```markdown
   # Migration Guide: v3.1 → v3.2

   ## Breaking Changes
   - All proxy configs use SERVER_IP (not 127.0.0.1)
   - Password length increased to 32 chars

   ## Steps
   1. Backup current installation
   2. Update code
   3. Run installer (answer YES to public proxy)
   4. Regenerate all client configs
   5. Distribute new configs to users
   ```

#### Acceptance Criteria

- [ ] README.md updated
- [ ] CLAUDE.md updated
- [ ] Migration guide created
- [ ] All docs reference v3.2

---

## Timeline and Milestones

### Week 1: Core Implementation (PHASE 1-2)

| Day | Tasks | Hours | Status |
|-----|-------|-------|--------|
| Day 1 | TASK-1.1, TASK-1.2 | 2h | ⏸️ Pending |
| Day 2 | TASK-1.3, TASK-1.4 | 3h | ⏸️ Pending |
| Day 3 | TASK-2.1 (fail2ban) | 3h | ⏸️ Pending |
| Day 4 | TASK-2.2, TASK-2.3, TASK-2.4 | 3h | ⏸️ Pending |

**Milestone 1:** Core proxy changes + Security hardening complete ✅

### Week 2: Integration and Testing (PHASE 3-4)

| Day | Tasks | Hours | Status |
|-----|-------|-------|--------|
| Day 5 | TASK-3.1, TASK-3.2 | 2h | ⏸️ Pending |
| Day 6 | TASK-3.3, TASK-4.1 | 2h | ⏸️ Pending |
| Day 7 | TASK-4.2, TASK-4.3 | 2h | ⏸️ Pending |

**Milestone 2:** Full v3.2 implementation complete ✅

---

## Risk Management

### High-Risk Items

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fail2ban breaks existing setup | MEDIUM | HIGH | Test on fresh VM first, keep backups |
| UFW rules conflict | LOW | MEDIUM | Validate before apply, use `--dry-run` |
| Password length breaks clients | LOW | LOW | Document in migration guide |
| Public exposure causes abuse | MEDIUM | HIGH | Mandatory fail2ban + rate limiting |

### Rollback Triggers

- Fail2ban doesn't start after configuration
- UFW blocks legitimate traffic
- Xray container fails healthcheck
- Integration tests fail > 50%

### Rollback Procedure

1. Stop containers: `docker-compose down`
2. Restore v3.1 configs from backup
3. Remove fail2ban jails: `rm /etc/fail2ban/jail.d/vless-proxy.conf`
4. Remove UFW rules: `ufw delete allow 1080/tcp; ufw delete allow 8118/tcp`
5. Restart with v3.1 code

---

## Validation Checklist (Before Merge)

### Code Quality ✅
- [ ] All functions documented
- [ ] No hardcoded IPs (except 0.0.0.0)
- [ ] Error handling on all critical paths
- [ ] Logging at appropriate levels
- [ ] No secrets in code

### Security ✅
- [ ] Fail2ban active and tested
- [ ] UFW rate limiting verified
- [ ] Passwords 32+ characters
- [ ] No unnecessary ports open
- [ ] Healthchecks working

### Testing ✅
- [ ] All 8 integration tests pass
- [ ] All 3 security tests pass
- [ ] Fresh installation works
- [ ] Migration from v3.1 works
- [ ] No regressions in VLESS-only mode

### Documentation ✅
- [ ] README.md updated
- [ ] CLAUDE.md updated
- [ ] Migration guide created
- [ ] Code comments complete

---

## Post-Deployment Tasks

1. Monitor fail2ban logs for 48 hours:
   ```bash
   journalctl -u fail2ban -f
   ```

2. Track banned IPs:
   ```bash
   sudo fail2ban-client status vless-socks5
   sudo fail2ban-client status vless-http
   ```

3. Monitor Xray error logs:
   ```bash
   tail -f /opt/vless/logs/xray/error.log
   ```

4. Check for DDoS patterns:
   ```bash
   sudo ufw status verbose
   ```

---

**END OF PLAN_FIX.md**

**Status:** 📋 Ready for Implementation
**Next Step:** Begin PHASE 1 - TASK-1.1 (Update Proxy Inbound Binding)

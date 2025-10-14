# CLAUDE.md - Project Memory

**Project:** VLESS + Reality VPN Server
**Version:** 2.1 (Optimized)
**Last Updated:** 2025-10-03
**Purpose:** Unified project memory combining workflow execution rules and project-specific technical documentation

---

## TABLE OF CONTENTS

### PROJECT-SPECIFIC DOCUMENTATION
6. [Project Overview](#part-ii-project-specific-documentation)
7. [Critical System Parameters](#7-critical-system-parameters)
8. [Project Structure](#8-project-structure)
9. [Critical Requirements](#9-critical-requirements-for-validation)
10. [Non-Functional Requirements](#10-non-functional-requirements-nfr)
11. [Common Failure Points & Solutions](#11-common-failure-points--solutions)
12. [Testing Checklist](#12-testing-checklist)
13. [Technical Details](#13-technical-details)
14. [Scalability & Constraints](#14-scalability--constraints)
15. [Security & Debug](#15-security--debug)
16. [Success Metrics](#16-success-metrics)


# PROJECT-SPECIFIC DOCUMENTATION

## 6. PROJECT OVERVIEW

**Project Name:** VLESS + Reality VPN Server
**Version:** 4.1 (stunnel TLS Termination + Heredoc Config Generation)
**Target Scale:** 10-50 concurrent users
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, SOCKS5, HTTP, stunnel, Nginx

**Core Value Proposition:**
- Deploy production-ready VPN in < 5 minutes
- Zero manual configuration through intelligent automation
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- **Dual proxy support (SOCKS5 + HTTP) with unified credentials**
- **Multi-format config export (5 formats: SOCKS5, HTTP, VSCode, Docker, Bash)**
- **TLS termination via stunnel (v4.0+)** - separation of concerns
- No domain/certificate management required
- Coexists with Outline, Wireguard, other VPN services

**Key Innovation:**
Reality protocol "steals" TLS handshake from legitimate websites (google.com, microsoft.com), making VPN traffic mathematically indistinguishable from normal HTTPS. Deep Packet Inspection systems cannot detect the VPN.

**Architecture Evolution:**
- **v3.1:** Dual proxy support (SOCKS5 + HTTP) with localhost-only binding
- **v4.0:** stunnel TLS termination - Client → stunnel (TLS 1.3, ports 1080/8118) → Xray (plaintext, ports 10800/18118) → Internet
- **v4.1:** Heredoc config generation (no templates/, simplified dependencies, removed envsubst)

**Proxy Architecture (v4.0+):**
stunnel handles TLS termination for proxy connections. Separation of concerns: stunnel = TLS layer, Xray = proxy logic. Simpler Xray config (no TLS streamSettings). Proxy URIs use `https://` and `socks5s://` for TLS connections (v4.1 fix). Single password for both SOCKS5 and HTTP. Auto-generates 5 config file formats per user.

---

## 7. CRITICAL SYSTEM PARAMETERS

### Technology Stack (MUST FOLLOW EXACTLY)

```yaml
Docker & Orchestration:
  docker_engine: "20.10+"          # Minimum version
  docker_compose: "v2.0+"          # v2 syntax required
  compose_command: "docker compose" # NOT docker-compose

Container Images (FIXED VERSIONS):
  xray: "teddysun/xray:24.11.30"   # DO NOT change without testing
  stunnel: "dweomer/stunnel:latest" # NEW in v4.0: TLS termination
  nginx: "nginx:alpine"             # Latest alpine

Operating System:
  primary: "Ubuntu 20.04+, 22.04 LTS, 24.04 LTS"
  secondary: "Debian 10+, 11, 12"
  not_supported: "CentOS, RHEL, Fedora" # firewalld vs UFW

Shell & Tools:
  bash: "4.0+"
  jq: "1.5+"                        # JSON processing
  qrencode: "latest"                # QR code generation
  openssl: "system default"         # Key generation, SNI
  uuidgen: "system default"         # UUID generation

Security Testing Tools:
  tcpdump: "latest"                 # Packet capture for security tests (required)
  nmap: "latest"                    # Network scanning and port validation (required)
  tshark: "latest"                  # Advanced TLS analysis (optional, Wireshark CLI)
  fail2ban: "latest"                # Brute-force protection
  certbot: "latest"                 # Let's Encrypt certificate management
  dnsutils: "latest"                # DNS tools (dig) for validation
```

### Protocol Configuration

```yaml
VPN Protocol:
  protocol: "VLESS"                 # VMess-Less, no encryption
  security: "Reality"               # TLS 1.3 masquerading
  flow: "xtls-rprx-vision"         # Performance optimization
  transport: "TCP"                  # Base transport

Reality Settings:
  key_algorithm: "X25519"           # Elliptic curve DH
  tls_version: "1.3"                # Required for Reality
  dest_default: "google.com:443"    # Masquerading target
  sni_extraction: "required"        # Must succeed
  validation_timeout: "10s"         # Max time for dest check

Proxy Protocols (v3.1+, TLS via stunnel v4.0+):
  socks5:
    port: 1080
    listen: "127.0.0.1"             # Localhost-only in Xray
    auth: "password"                # Required
    udp: false                      # TCP only
  http:
    port: 8118
    listen: "127.0.0.1"             # Localhost-only in Xray
    auth: "password"                # Required
    allowTransparent: false         # Security hardening
    protocols: ["HTTP", "HTTPS"]    # Both supported

stunnel TLS Termination (NEW in v4.0):
  architecture: |
    Client → stunnel (TLS 1.3, ports 1080/8118)
           → Xray (plaintext, localhost 10800/18118)
           → Internet

  stunnel_config:
    tls_version: "TLSv1.3"          # Only TLS 1.3 allowed
    ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
    certificates: "/etc/letsencrypt" # Shared with VLESS
    listen_socks5: "0.0.0.0:1080"
    listen_http: "0.0.0.0:8118"
    forward_socks5: "vless_xray:10800"
    forward_http: "vless_xray:18118"
    config_generation: "heredoc in lib/stunnel_setup.sh (v4.1)"

  xray_inbound_changes_v4:
    socks5:
      old_v3: "listen: 0.0.0.0:1080, security: tls"
      new_v4: "listen: 127.0.0.1:10800, security: none"
    http:
      old_v3: "listen: 0.0.0.0:8118, security: tls"
      new_v4: "listen: 127.0.0.1:18118, security: none"

  proxy_uri_schemes_v4_1:
    http_proxy: "https://user:pass@domain:8118"
    socks5_proxy: "socks5s://user:pass@domain:1080"
    note: "Scheme 's' suffix = SSL/TLS (https, socks5s)"

  benefits:
    - "Separation of concerns: stunnel=TLS, Xray=proxy logic"
    - "Mature TLS stack (stunnel 20+ years production)"
    - "Simpler Xray config (no TLS streamSettings)"
    - "Easier certificate management"
    - "Separate logs for debugging"
```

### Network Architecture

```yaml
Docker Network:
  name: "vless_reality_net"
  driver: "bridge"
  subnet_default: "172.20.0.0/16"
  subnet_detection: "automatic"     # Scans existing networks
  isolation: "complete"             # Separate from other VPNs

Ports:
  vless_default: 443
  vless_alternatives: [8443, 2053, 2083, 2087]
  nginx_internal: 8080              # Not exposed to host
  socks5_proxy: 1080                # NEW: Localhost-only (127.0.0.1)
  http_proxy: 8118                  # NEW: Localhost-only (127.0.0.1)
  port_detection: "automatic"       # ss -tulnp check

Firewall (UFW):
  status_required: "active"
  docker_integration: "/etc/ufw/after.rules"
  rule_format: "allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'"
  proxy_ports_exposed: false        # NEW: Ports 1080/8118 NOT in docker-compose.yml
```

### Installation Path (HARDCODED)

```yaml
Base Path: "/opt/vless/"            # CANNOT be changed

Directory Structure:
  config/:     "700"                # Sensitive configs
  data/:       "700"                # User data, backups
  logs/:       "755"                # Access/error logs
  fake-site/:  "755"                # Nginx configs
  scripts/:    "755"                # Management scripts

File Permissions:
  config.json:         "600"
  stunnel.conf:        "600"        # NEW in v4.0: stunnel TLS config
  users.json:          "600"        # v1.1 with proxy_password field
  reality_keys.json:   "600"
  .env:                "600"
  docker-compose.yml:  "644"
  scripts/*.sh:        "755"

Client Config Files (v3.1+, URI schemes fixed in v4.1):
  socks5_config.txt:       "600"    # socks5s://user:pass@domain:1080
  http_config.txt:         "600"    # https://user:pass@domain:8118
  vscode_settings.json:    "600"
  docker_daemon.json:      "600"
  bash_exports.sh:         "700"    # Executable
  # NOTE: Uses https:// and socks5s:// for TLS (v4.1 fix)

Symlinks:
  location: "/usr/local/bin/"
  pattern: "vless-*"
  permissions: "755"                # Sudo-accessible
```

---

## 8. PROJECT STRUCTURE

### Development Structure (Before Installation)

```
/home/ikeniborn/Documents/Project/vless/
├── install.sh                      # Main installer entry point
├── PLAN.md                         # Implementation roadmap
├── PRD.md                          # Product requirements
├── CLAUDE.md                       # This file - project memory
├── lib/                            # Installation modules
│   ├── os_detection.sh
│   ├── dependencies.sh
│   ├── old_install_detect.sh
│   ├── interactive_params.sh
│   ├── sudoers_info.sh
│   ├── orchestrator.sh
│   └── verification.sh
├── docs/                           # Additional documentation
├── tests/                          # Test suite
│   ├── unit/
│   └── integration/
├── scripts/                        # Dev utilities
└── requests/                       # Workflow templates
```

### Production Structure (After Installation)

```
/opt/vless/                         # Created by installer
├── config/                         # 700, owner: root
│   ├── config.json                 # 600 - Xray config (3 inbounds: VLESS + plaintext SOCKS5/HTTP)
│   ├── stunnel.conf                # 600 - stunnel TLS termination config (v4.0+)
│   ├── users.json                  # 600 - User database (v1.1 with proxy_password)
│   └── reality_keys.json           # 600 - X25519 key pair
├── data/                           # 700, user data
│   ├── clients/                    # Per-user configs
│   │   └── <username>/             # NEW: 8 files per user (3 VLESS + 5 proxy)
│   │       ├── vless_config.json   # VLESS client config
│   │       ├── vless_uri.txt       # VLESS connection string
│   │       ├── qrcode.png          # QR code for mobile
│   │       ├── socks5_config.txt   # NEW: SOCKS5 URI
│   │       ├── http_config.txt     # NEW: HTTP URI
│   │       ├── vscode_settings.json # NEW: VSCode proxy settings
│   │       ├── docker_daemon.json  # NEW: Docker daemon config
│   │       └── bash_exports.sh     # NEW: Bash environment variables
│   └── backups/                    # Automatic backups
├── logs/                           # 755, log files
├── fake-site/                      # 755, Nginx configs
├── scripts/                        # 755, management tools
├── .env                            # 600 - Environment variables
└── docker-compose.yml              # 644 - Container orchestration

/usr/local/bin/                     # Symlinks (sudo-accessible)
├── vless-install
├── vless-user                      # NEW: Now supports show-proxy, reset-proxy-password
├── vless-start / stop / restart / status / logs  # NEW: status shows proxy info
├── vless-update
└── vless-uninstall
```

---

## 9. CRITICAL REQUIREMENTS FOR VALIDATION

### FR-001: Interactive Installation (CRITICAL - Priority 1)

**Target:** Installation completes in < 5 minutes

**Requirements:**
```yaml
Validation BEFORE Application:
  - All parameters validated before use
  - Clear error messages with fix suggestions
  - Cancel and retry capability at any step
  - Progress indicators for long operations

Environment Detection:
  - OS version and architecture
  - Docker and compose versions (install if missing)
  - UFW status (install/enable if needed)
  - Existing VPN services (Outline, Wireguard)
  - Occupied ports and Docker subnets
  - Old VLESS installations
```

**Acceptance Criteria:**
```
✓ All parameters prompted with intelligent defaults
✓ Each parameter validated immediately after input
✓ Errors include actionable guidance (not just "failed")
✓ Can cancel at any point without leaving partial state
✓ Total time < 5 minutes on clean Ubuntu 22.04 (10 Mbps)
```

---

### FR-002: Old Installation Detection (CRITICAL - Priority 1)

**Requirement:** Detect existing installations and offer safe options

**Detection Checks:**
```bash
# 1. Check directory
if [ -d "/opt/vless/" ]; then echo "Old installation found"; fi

# 2. Check containers
docker ps -a --format '{{.Names}}' | grep -E '^vless-'

# 3. Check networks
docker network ls --format '{{.Name}}' | grep -E '^vless_'

# 4. Check symlinks
ls -la /usr/local/bin/vless-* 2>/dev/null
```

**User Options:**
```yaml
1. DELETE: Backup + complete removal + fresh install
2. UPDATE: Preserve users/keys + update containers
3. CANCEL: No changes, safe exit
```

**Acceptance Criteria:**
✓ All detection checks work
✓ DELETE: Complete removal + backup to /tmp/
✓ UPDATE: Users and keys preserved
✓ CANCEL: No changes made
✓ Backup created BEFORE destructive operations

---

### FR-004: Dest Site Validation (CRITICAL - Priority 1)

**Requirement:** Validate destination site for Reality masquerading

**Default Options:**
```yaml
1: "google.com:443"          # Default
2: "www.microsoft.com:443"
3: "www.apple.com:443"
4: "www.cloudflare.com:443"
5: "Custom"
```

**Validation Steps:**
```bash
# 1. TLS 1.3 Support (REQUIRED)
curl -vI https://${dest} 2>&1 | grep -i "TLSv1.3"

# 2. SNI Extraction (REQUIRED)
openssl s_client -servername ${dest} -connect ${dest}:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"

# 3. Reachability (REQUIRED)
curl -s -o /dev/null -w "%{http_code}" https://${dest}
```

**Validation Criteria:**
```yaml
TLS 1.3:      REQUIRED
SNI Extract:  REQUIRED
Reachability: REQUIRED
Latency:      < 10 seconds
```

**Acceptance Criteria:**
✓ All validation steps execute
✓ Validation completes in < 10 seconds
✓ Clear feedback on failures
✓ Alternatives offered on failure
✓ Cannot proceed with invalid dest

---

### FR-005: User Creation (CRITICAL - Priority 1)

**Requirement:** Create user in < 5 seconds with automatic config generation

**Command:**
```bash
sudo vless-user add <username>
```

**Workflow:**
```yaml
1. Validate username (alphanumeric, 3-32 chars, unique)
2. Generate UUID (uuidgen)
3. Generate shortId (openssl rand -hex 8)
4. Update users.json (atomic with file lock)
5. Update config.json
6. Reload Xray (docker-compose restart xray)
7. Generate client configs (JSON, URI, QR code)
8. Save to data/clients/{username}/
9. Display to user
```

**Acceptance Criteria:**
✓ Total time < 5 seconds
✓ UUID & shortId unique
✓ Xray reloads without errors
✓ Client configs generated (all 3 formats)
✓ Files saved with correct permissions (600)
✓ No data corruption

---

### FR-011: UFW Integration (CRITICAL - Priority 1)

**Requirement:** Configure UFW firewall with Docker forwarding support

**Critical Files:**
```
/etc/ufw/ufw.conf
/etc/ufw/after.rules        # Docker chains added here
/etc/ufw/before.rules
```

**Required Rules in /etc/ufw/after.rules:**
```iptables
# BEGIN VLESS Reality Docker Integration
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
COMMIT
```

**Acceptance Criteria:**
✓ UFW detected (install if missing)
✓ UFW enabled (prompt if inactive)
✓ Port rule added without duplication
✓ Docker chains added to after.rules
✓ Containers can access Internet
✓ External connections work

---

### FR-012: Proxy Server Integration (CRITICAL - Priority 1) - v3.1, TLS via stunnel v4.0+

**Requirement:** Dual proxy support (SOCKS5 + HTTP) with localhost-only binding and TLS termination via stunnel

**Implementation:**
```yaml
TLS Termination (v4.0+):
  method: "stunnel separate container"
  architecture: "Client (TLS) → stunnel (ports 1080/8118) → Xray plaintext (ports 10800/18118) → Internet"
  benefits:
    - "Xray config simplified (no TLS streamSettings)"
    - "Mature TLS stack (stunnel 20+ years production)"
    - "Separate logs for debugging"
    - "Certificate management centralized"

Proxy Configuration:
  socks5:
    external_port: 1080          # stunnel listens (TLS 1.3)
    internal_port: 10800         # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"          # Xray binding (NOT exposed to internet)
    auth: "password"             # Required
    protocol: "socks"

  http:
    external_port: 8118          # stunnel listens (TLS 1.3)
    internal_port: 18118         # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"          # Xray binding (NOT exposed to internet)
    auth: "password"             # Required
    protocol: "http"
    allowTransparent: false

Config Generation (v4.1):
  method: "heredoc in lib/stunnel_setup.sh"
  previous_v4.0: "templates/stunnel.conf.template + envsubst"
  change_rationale: "Unified with Xray/docker-compose generation (all heredoc)"
  dependencies_removed: "envsubst (GNU gettext)"

Credential Management:
  password_generation: "openssl rand -hex 8"  # 16 characters
  password_storage: "users.json v1.1 (proxy_password field)"
  single_password: true                        # Same for SOCKS5 + HTTP

Config File Export (5 formats per user, v4.1 URI fix):
  - socks5_config.txt        # socks5s://user:pass@domain:1080 (TLS)
  - http_config.txt          # https://user:pass@domain:8118 (TLS)
  - vscode_settings.json     # VSCode proxy settings
  - docker_daemon.json       # Docker daemon config
  - bash_exports.sh          # Environment variables (executable)

Proxy URI Schemes Explained:
  http://   - Plaintext HTTP (NOT USED, localhost-only deprecated)
  https://  - HTTP with TLS (v4.0+, stunnel termination) ✅
  socks5:// - Plaintext SOCKS5 (NOT USED, localhost-only deprecated)
  socks5s://- SOCKS5 with TLS (v4.0+, stunnel termination) ✅
  socks5h://- SOCKS5 with DNS via proxy (NOT a TLS replacement!)
```

**Security Requirements:**
```yaml
Network Binding:
  - Proxies bind ONLY to 127.0.0.1 (localhost)
  - NOT accessible from external network
  - Require VPN connection first (must connect via VLESS)
  - Ports 1080/8118 NOT exposed in docker-compose.yml

Authentication:
  - Password required for both SOCKS5 and HTTP
  - 16-character random hex passwords
  - Stored in users.json with 600 permissions

File Permissions:
  - Config files (txt, json): 600 (owner read/write only)
  - Bash script: 700 (owner read/write/execute)
  - Client directory: 700 (owner access only)
```

**Workflow Integration:**
```bash
# User creation (auto-generates proxy password + configs)
sudo vless-user add alice
# Output: UUID + proxy password + 8 config files (VLESS + 5 proxy configs)
# Proxy configs use https:// and socks5s:// URIs (v4.1 fix)

# Show proxy credentials
sudo vless-user show-proxy alice
# Output:
#   SOCKS5: socks5s://alice:PASSWORD@domain:1080
#   HTTP:   https://alice:PASSWORD@domain:8118
# Usage examples provided for VSCode, Docker, Git

# Reset proxy password (regenerates all configs)
sudo vless-user reset-proxy-password alice
# Output: New password + updated config files (all 5 formats regenerated)

# Service status (shows proxy info)
sudo vless-status
# Output: Proxy enabled/disabled + SOCKS5/HTTP details + stunnel status (v4.0+)
```

**Acceptance Criteria:**
✓ Proxies bind to 127.0.0.1 ONLY (not 0.0.0.0)
✓ Password authentication enforced
✓ Single password for both SOCKS5 and HTTP
✓ 5 config file formats generated per user
✓ Auto-generation on user creation
✓ Auto-regeneration on password reset
✓ Service status shows proxy info
✓ Ports NOT exposed in docker-compose.yml
✓ External access blocked (verifiable with nmap)
✓ Backward compatible (VLESS-only mode works)

---

## 10. NON-FUNCTIONAL REQUIREMENTS (NFR)

### Performance Targets

```yaml
Installation:
  target: "< 5 minutes"
  baseline: "Clean Ubuntu 22.04, 10 Mbps internet"

User Creation:
  target: "< 5 seconds"
  scalability: "Consistent up to 50 users"

Container Startup:
  target: "< 10 seconds"

Config Reload:
  target: "< 3 seconds"

Operations (50 users):
  user_list: "< 1 second"
  user_show: "< 1 second"
```

### Reliability Requirements

```yaml
Uptime:
  target: "99.9%"

Restart Policy:
  docker_compose: "restart: unless-stopped"

Config Validation:
  before_apply: "100% of changes"
  methods:
    - JSON syntax: jq . config.json
    - Xray test: xray run -test -c config.json
  rollback: "Keep previous config for auto-restore"
```

### Security Requirements

```yaml
File Permissions (ENFORCED):
  /opt/vless/config/:                 "700"
  config.json / users.json / keys:    "600"
  scripts:                            "755"

Container Security:
  xray_user: "nobody (UID 65534)"
  nginx_user: "nginx"
  capabilities: drop ALL, add NET_BIND_SERVICE

Key Management:
  algorithm: "X25519"
  private_key: NEVER transmitted, 600 perms, root only
  public_key: Freely distributable
  rotation: Supported via CLI

Network Security:
  ufw_status: "active (required)"
  exposed_ports: ${VLESS_PORT}/tcp only
  docker_isolation: Separate network
```

### Usability Requirements

```yaml
CLI Design:
  command_prefix: "vless-*"
  help_text: "Available for all commands"
  success_metric: "80% tasks without docs lookup"

Error Messages (MUST INCLUDE):
  - Clear problem description
  - Context (where/when)
  - Root cause
  - Actionable fix steps with commands
```

---

## 11. COMMON FAILURE POINTS & SOLUTIONS

### Issue 1: UFW Blocks Docker Traffic

**Symptoms:** Containers run, but no Internet access inside

**Detection:**
```bash
docker exec vless-reality ping -c 1 8.8.8.8  # Fails
ufw status numbered  # Check rules
grep "DOCKER-USER" /etc/ufw/after.rules  # Check chains
```

**Solution:**
```bash
# Add Docker chains to /etc/ufw/after.rules (see FR-011)
sudo ufw reload
```

---

### Issue 2: Port 443 Already Occupied

**Symptoms:** Installation fails, "port is already allocated"

**Detection:**
```bash
sudo ss -tulnp | grep :443
sudo lsof -i :443
```

**Solution:** Offer alternative ports (8443, 2053) or ask user to resolve

---

### Issue 3: Docker Subnet Conflicts

**Symptoms:** Network creation fails, "Pool overlaps"

**Detection:**
```bash
docker network ls --format '{{.Name}}'
for net in $(docker network ls --format '{{.Name}}'); do
  docker network inspect $net | jq -r '.[0].IPAM.Config[0].Subnet'
done
```

**Solution:** Auto-scan 172.16-31.0.0/16 range, find free subnet

---

### Issue 4: Dest Validation Fails

**Root Causes:**
1. DNS resolution failure
2. Firewall blocking outbound HTTPS
3. Dest site temporarily unavailable
4. TLS < 1.3

**Solution:** Offer alternative destinations, allow retry

---

### Issue 5: Containers Won't Start

**Detection:**
```bash
docker ps -a | grep vless  # Check status
docker logs vless-reality  # Check errors
```

**Common Causes:**
- Invalid config.json
- Missing volume mounts
- Port already bound
- Network doesn't exist

**Debug Workflow:**
```bash
1. jq . /opt/vless/config/config.json
2. xray run -test -c config.json
3. docker network inspect vless_reality_net
4. ss -tulnp | grep ${VLESS_PORT}
5. docker logs vless-reality
6. docker-compose up (no -d, see live errors)
```

---

## 12. TESTING CHECKLIST

### Fresh Installation Test
**Environment:** Clean Ubuntu 22.04, no Docker, no UFW

**Success Criteria:**
- [ ] Installation < 5 minutes
- [ ] Docker/UFW auto-installed & configured
- [ ] Both containers running
- [ ] Admin user created with QR
- [ ] Port accessible
- [ ] Containers have Internet

### User Management Test
- [ ] Create user < 5 seconds
- [ ] QR code displayed
- [ ] All 3 config formats generated
- [ ] List/Show/Remove operations work

### Multi-VPN Coexistence Test
**Pre-conditions:** Outline VPN running

**Success:**
- [ ] Different subnets auto-detected
- [ ] Both VPNs work simultaneously
- [ ] No routing conflicts

### DPI Resistance Test
- [ ] Wireshark: Traffic looks like HTTPS
- [ ] nmap: Reports HTTPS service (not VPN)
- [ ] Browser: Shows dest site (proxied)
- [ ] Invalid auth → fake-site (not rejected)

### Update & Data Preservation Test
- [ ] All 10 users preserved after update
- [ ] Reality keys unchanged
- [ ] Client configs still valid
- [ ] Total downtime < 30 seconds

---

## 13. TECHNICAL DETAILS

### Reality Key Management

**Generation:**
```bash
xray x25519
# Output: Private key: ..., Public key: ...
```

**Storage:** `/opt/vless/config/reality_keys.json` (600 perms)
```json
{
  "private_key": "...",
  "public_key": "...",
  "generated_at": "2025-10-01T12:00:00Z",
  "algorithm": "X25519"
}
```

**Security:**
- Private key: NEVER leave server, NEVER in client configs
- Public key: Distributed in all client configs
- Keys can be rotated (requires client config updates)

---

### User Data Structure

**File:** `/opt/vless/config/users.json` (600 perms)
```json
{
  "version": "1.0",
  "users": [
    {
      "username": "admin",
      "uuid": "12345678-1234-1234-1234-123456789012",
      "shortId": "a1b2c3d4e5f67890",
      "email": "admin@local",
      "created_at": "2025-10-01T12:00:00Z",
      "enabled": true
    }
  ]
}
```

**Atomic Operations:**
```bash
# Add user with file lock
(
  flock -x 200
  jq '.users += [NEW_USER]' users.json > users.json.tmp
  mv users.json.tmp users.json
) 200>/var/lock/vless-users.lock
```

---

### Client Configuration Formats

**1. JSON (v2rayN/v2rayNG):**
```json
{
  "outbounds": [{
    "protocol": "vless",
    "settings": { "vnext": [{ "address": "SERVER_IP", "port": 443 }] },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "google.com",
        "publicKey": "PUBLIC_KEY",
        "shortId": "SHORT_ID"
      }
    }
  }]
}
```

**2. VLESS URI:**
```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#USERNAME
```

**3. QR Code:**
```bash
qrencode -o qrcode.png -t PNG -s 10 "vless://..."
qrencode -t ANSIUTF8 "vless://..."  # Terminal
```

---

### Xray Configuration (config.json)

**Key Sections:**
- **log**: Access and error logging
- **inbounds**: VLESS listening configuration
- **clients[]**: Array of authorized users
- **fallbacks**: Redirect invalid connections to Nginx
- **realitySettings**: Reality protocol parameters
- **serverNames**: SNI values (must match dest site)
- **shortIds**: Additional authentication layer
- **outbounds**: Traffic routing (freedom = direct, blackhole = blocked)

---

### Nginx Configuration (fake-site)

**Purpose:**
- Receives fallback traffic from Xray
- Proxies requests to destination site (google.com)
- Makes server appear as normal HTTPS website
- Enhances DPI resistance

**File:** `/opt/vless/fake-site/default.conf`
```nginx
server {
    listen 8080;
    location / {
        proxy_pass https://google.com;
        proxy_ssl_server_name on;
        proxy_set_header Host google.com;
    }
}
```

---

## 14. SCALABILITY & CONSTRAINTS

### Current Design (10-50 Users)

**Architecture:**
```yaml
User Storage: JSON files
Locking: File-based (flock)
Orchestration: Docker Compose
Management: Bash scripts
```

**Performance:**
```yaml
User Operations (50 users):
  add: "< 5 seconds"
  list: "< 1 second"

File Sizes:
  users.json: "~10 KB (50 users)"
  config.json: "~30 KB (50 users)"

Memory:
  Xray: "~80 MB (50 concurrent)"
  Nginx: "~20 MB"
```

**Design Strengths:**
- Simple architecture
- No database overhead
- JSON files easily backed up
- Fast for target scale (10-50 users)

**Design Limitations:**
- JSON parsing slowdown beyond 100 users
- File locking contention with high concurrent ops
- No horizontal scaling

**Recommendation:**
For > 50 users, use multiple independent instances (server1: users 1-50, server2: users 51-100) rather than architectural redesign.

---

## 15. SECURITY & DEBUG

### Security Threat Matrix

| Threat | Severity | Mitigation |
|--------|----------|------------|
| DPI Detection | HIGH | Reality protocol TLS masquerading |
| Private Key Compromise | CRITICAL | 600 perms, root-only, never transmitted |
| Brute Force UUID | MEDIUM | UUID + shortId (2^192 space) |
| Container Escape | HIGH | Non-root user, minimal capabilities |

### Security Best Practices

**1. Key Rotation:**
```bash
# When: Suspected compromise, every 6-12 months, after admin turnover
1. xray x25519  # Generate new keys
2. Update config.json with new private key
3. Regenerate all client configs
4. docker-compose restart xray
```

**2. System Hardening:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install unattended-upgrades
# SSH hardening: /etc/ssh/sshd_config
# PermitRootLogin no, PasswordAuthentication no
```

### Quick Debug Commands

**System Status:**
```bash
sudo vless-status
docker ps
docker network inspect vless_reality_net
sudo ss -tulnp | grep 443
sudo ufw status numbered
```

**Logs:**
```bash
sudo vless-logs -f
docker logs vless-reality --tail 50
docker logs vless-fake-site
```

**Config Validation:**
```bash
jq . /opt/vless/config/config.json
docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 xray run -test -c /etc/xray/config.json
```

**Network Tests:**
```bash
docker exec vless-reality ping -c 1 8.8.8.8
docker exec vless-reality curl -I https://www.google.com
```

**User Management:**
```bash
cat /opt/vless/config/users.json | jq .
jq '.users | length' /opt/vless/config/users.json
jq -r '.users[].uuid' /opt/vless/config/users.json | sort | uniq -d  # Check UUID uniqueness
```

**Security Testing:**
```bash
# Run comprehensive security test suite
sudo vless test-security

# Quick mode (skip long-running tests)
sudo vless test-security --quick

# Skip packet capture tests
sudo vless test-security --skip-pcap

# Development mode (run without installation)
sudo vless test-security --dev-mode

# Verbose output
sudo vless test-security --verbose

# Combined options
sudo vless test-security --quick --verbose
```

**Security Test Coverage:**
- TLS 1.3 configuration (Reality Protocol)
- stunnel TLS termination (Public Proxy Mode)
- Traffic encryption validation (packet capture)
- Certificate security
- DPI resistance (Deep Packet Inspection)
- SSL/TLS vulnerabilities
- Proxy protocol security (SOCKS5/HTTP)
- Data leak detection

**Test Output:**
- Passed/Failed/Skipped count
- Security warnings
- Critical issues
- Detailed test results

---

## 16. SUCCESS METRICS

### Performance Targets

```yaml
Installation: < 5 minutes (baseline: Ubuntu 22.04, 10 Mbps)
User Creation: < 5 seconds (consistent up to 50 users)
Container Startup: < 10 seconds
Config Reload: < 3 seconds
```

### Test Results

```yaml
DPI Resistance:
  - Wireshark: Traffic identical to HTTPS ✓
  - nmap: Reports HTTPS service (not VPN) ✓
  - Browser: Shows dest site ✓
  - Invalid auth: Fallback to fake-site ✓

Multi-VPN:
  - Different subnets detected ✓
  - Both VPNs work simultaneously ✓

Update:
  - User data preserved ✓
  - Downtime < 30 seconds ✓
```

### Overall Success Formula

```yaml
Weighted Score:
  installation_time: 20%
  user_creation: 25%
  dpi_resistance: 20%
  multi_vpn: 15%
  data_preservation: 10%
  cli_usability: 10%

Target: ≥ 85% weighted score
```

---

**END OF OPTIMIZED PROJECT MEMORY**

**Version History:**
```
v2.1 - 2025-10-03: Optimized version (-33% size, all critical info preserved)
v2.0 - 2025-10-02: Unified document (workflow + project)
v1.0 - 2025-10-01: Initial project memory
```

This document serves as the single source of truth for both workflow execution rules and project-specific technical documentation for the VLESS + Reality VPN Server project.

# CLAUDE.md - Project Memory

**Project:** VLESS + Reality VPN Server
**Version:** 4.3 (HAProxy Unified Architecture)
**Last Updated:** 2025-10-18
**Purpose:** Unified project memory combining workflow execution rules and project-specific technical documentation

Рекомендации по использованию:
  Для быстрого ознакомления: Начните с docs/prd/00_summary.md
  Для разработки: docs/prd/02_functional_requirements.md + docs/prd/04_architecture.md
  Для тестирования: docs/prd/05_testing.md + docs/prd/03_nfr.md
  Для troubleshooting: docs/prd/06_appendix.md


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
17. [PRD Documentation Structure](#17-prd-documentation-structure)


# PROJECT-SPECIFIC DOCUMENTATION

## 6. PROJECT OVERVIEW

**Project Name:** VLESS + Reality VPN Server
**Version:** 4.3 (HAProxy Unified Architecture)
**Target Scale:** 10-50 concurrent users
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, SOCKS5, HTTP, HAProxy, Nginx

**Core Value Proposition:**
- Deploy production-ready VPN in < 5 minutes
- Zero manual configuration through intelligent automation
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- **Dual proxy support (SOCKS5 + HTTP) with unified credentials**
- **Multi-format config export (5 formats: SOCKS5, HTTP, VSCode, Docker, Bash)**
- **Unified TLS and routing via HAProxy (v4.3)** - single container architecture
- **Subdomain-based reverse proxy (https://domain, NO port!)**
- No domain/certificate management required
- Coexists with Outline, Wireguard, other VPN services

**Key Innovation:**
Reality protocol "steals" TLS handshake from legitimate websites (google.com, microsoft.com), making VPN traffic mathematically indistinguishable from normal HTTPS. Deep Packet Inspection systems cannot detect the VPN.

**Architecture Evolution:**
- **v3.1:** Dual proxy support (SOCKS5 + HTTP) with localhost-only binding
- **v4.0:** stunnel TLS termination - Client → stunnel (TLS 1.3, ports 1080/8118) → Xray (plaintext, ports 10800/18118) → Internet
- **v4.1:** Heredoc config generation (no templates/, simplified dependencies, removed envsubst)
- **v4.3:** HAProxy Unified Architecture - Client → HAProxy (SNI routing 443, TLS termination 1080/8118) → Xray/Nginx → Internet

**HAProxy Architecture (v4.3 - Current):**
HAProxy handles ALL TLS termination and routing in single container. **stunnel removed completely**. Port 443: SNI routing (VLESS Reality passthrough + Reverse Proxy subdomain routing). Ports 1080/8118: TLS termination for proxies. Nginx reverse proxy backends on localhost:9443-9452 (NOT exposed). Subdomain-based reverse proxy access (https://domain, NO port!). Graceful reload for zero-downtime updates. Dynamic ACL management for reverse proxy routes. Single unified log stream. Auto-generates 5 config file formats per user.

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
  haproxy: "haproxy:latest"         # NEW v4.3: Unified TLS & routing (REPLACES stunnel)
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

Proxy Protocols (v3.1+, TLS via HAProxy v4.3):
  socks5:
    external_port: 1080             # HAProxy listens (TLS 1.3)
    internal_port: 10800            # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"             # Xray binding (NOT exposed to internet)
    auth: "password"                # Required
    udp: false                      # TCP only
  http:
    external_port: 8118             # HAProxy listens (TLS 1.3)
    internal_port: 18118            # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"             # Xray binding (NOT exposed to internet)
    auth: "password"                # Required
    allowTransparent: false         # Security hardening
    protocols: ["HTTP", "HTTPS"]    # Both supported

HAProxy Unified Architecture (NEW in v4.3):
  architecture: |
    Port 443 (HAProxy Frontend - SNI Routing):
      → VLESS Reality: SNI passthrough → Xray:8443 (Reality TLS)
      → Reverse Proxies: SNI routing → Nginx:9443-9452 (localhost HTTPS)

    Port 1080 (HAProxy Frontend - SOCKS5 TLS Termination):
      → Xray:10800 (plaintext SOCKS5)

    Port 8118 (HAProxy Frontend - HTTP TLS Termination):
      → Xray:18118 (plaintext HTTP)

  haproxy_config:
    frontends:
      - name: "vless-reality"
        port: 443
        mode: tcp
        action: SNI routing (TLS passthrough for Reality, SNI routing for Reverse Proxy)
        backends:
          - VLESS Reality (default, SNI passthrough)
          - Reverse Proxy Nginx (9443-9452, SNI-based routing)

      - name: "socks5-tls"
        port: 1080
        mode: tcp
        action: TLS termination → Xray:10800 (plaintext)

      - name: "http-tls"
        port: 8118
        mode: tcp
        action: TLS termination → Xray:18118 (plaintext)

    certificates: "/opt/vless/certs/combined.pem"  # fullchain + privkey concatenated
    tls_version: "TLSv1.3"                        # Only TLS 1.3 allowed
    ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
    config_generation: "heredoc in lib/haproxy_config_manager.sh (v4.3)"
    graceful_reload: "haproxy -sf <old_pid>"      # zero downtime
    stats_page: "http://127.0.0.1:9000/stats"
    dynamic_acl: "sed-based updates for reverse proxy routes"

  xray_inbound_changes_v4_3:
    vless_reality:
      port: 8443 (internal, not 443 - HAProxy handles 443)
      listen: "0.0.0.0"
      note: "HAProxy SNI passthrough, NO TLS termination"
    socks5:
      port: 10800 (internal, localhost)
      listen: "127.0.0.1"
      note: "HAProxy terminates TLS on port 1080"
    http:
      port: 18118 (internal, localhost)
      listen: "127.0.0.1"
      note: "HAProxy terminates TLS on port 8118"

  reverse_proxy_v4_3:
    access_format: "https://domain (NO port!)"    # v4.3 KEY CHANGE
    port_range: "9443-9452 (localhost-only, NOT publicly exposed)"
    nginx_binding: "127.0.0.1:9443-9452"
    public_access: "HAProxy Frontend 443 (SNI routing)"
    max_domains: 10
    architecture: "Client → HAProxy:443 (SNI) → Nginx:9443-9452 → Xray → Target"

  benefits:
    - "Simplified Architecture: 1 container instead of 2 (stunnel REMOVED)"
    - "Subdomain-Based Access: https://domain (NO port number!)"
    - "SNI Routing Security: NO TLS decryption for reverse proxy"
    - "Unified Management: All TLS and routing in single HAProxy config"
    - "Graceful Reload: Zero-downtime route updates"
    - "Dynamic ACL Management: Add/remove reverse proxy routes without restart"
    - "Single Log Stream: Unified HAProxy logs for all frontends"
    - "Better Performance: Industry-standard load balancer (20+ years production)"

  migration_from_v4_0_v4_2:
    stunnel_removed: true
    haproxy_replaces_stunnel: true
    backward_compatible: true  # Client configs unchanged
    zero_downtime: true        # Graceful transition
    user_data_preserved: true  # Users, keys, reverse proxies
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
  vless_default: 443                # HAProxy SNI routing (VLESS + Reverse Proxy)
  vless_alternatives: [8443, 2053, 2083, 2087]
  nginx_internal: 8080              # Not exposed to host
  socks5_proxy: 1080                # HAProxy TLS termination
  http_proxy: 8118                  # HAProxy TLS termination
  haproxy_stats: 9000               # HAProxy stats page (localhost)
  reverse_proxy_backends: "9443-9452"  # Nginx localhost-only (v4.3)
  port_detection: "automatic"       # ss -tulnp check

Firewall (UFW):
  status_required: "active"
  docker_integration: "/etc/ufw/after.rules"
  rule_format: "allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'"
  proxy_ports_exposed: "1080, 8118 (HAProxy TLS termination)"
  reverse_proxy_ports_exposed: false  # 9443-9452 localhost-only (v4.3)
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
  certs/:      "700"                # NEW v4.3: combined.pem certificates

File Permissions:
  config.json:         "600"
  haproxy.cfg:         "600"        # NEW in v4.3: HAProxy config
  users.json:          "600"        # v1.1 with proxy_password field
  reality_keys.json:   "600"
  .env:                "600"
  docker-compose.yml:  "644"
  scripts/*.sh:        "755"
  combined.pem:        "600"        # NEW v4.3: HAProxy certificates

Client Config Files (v3.1+, URI schemes fixed in v4.1):
  socks5_config.txt:       "600"    # socks5s://user:pass@domain:1080
  http_config.txt:         "600"    # https://user:pass@domain:8118
  vscode_settings.json:    "600"
  docker_daemon.json:      "600"
  bash_exports.sh:         "700"    # Executable
  # NOTE: Uses https:// and socks5s:// for TLS (v4.1 fix, HAProxy termination v4.3)

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
├── PRD.md                          # Product requirements (consolidated, see docs/prd/)
├── CLAUDE.md                       # This file - project memory
├── CHANGELOG.md                    # Version history, migration guides
├── README.md                       # User guide, installation instructions
├── lib/                            # Installation modules
│   ├── os_detection.sh
│   ├── dependencies.sh
│   ├── old_install_detect.sh
│   ├── interactive_params.sh
│   ├── sudoers_info.sh
│   ├── orchestrator.sh
│   ├── haproxy_config_manager.sh   # NEW v4.3: HAProxy config generation
│   ├── certificate_manager.sh      # NEW v4.3: combined.pem management
│   └── verification.sh
├── docs/                           # Additional documentation
│   └── prd/                        # PRD modular structure
│       ├── README.md               # PRD navigation
│       ├── 00_summary.md           # Executive summary
│       ├── 01_overview.md          # Document control
│       ├── 02_functional_requirements.md  # FR-* requirements
│       ├── 03_nfr.md               # Non-functional requirements
│       ├── 04_architecture.md      # Section 4.7 HAProxy architecture
│       ├── 05_testing.md           # v4.3 test suite
│       └── 06_appendix.md          # Implementation, security
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
│   ├── haproxy.cfg                 # 600 - HAProxy unified config (v4.3, REPLACES stunnel.conf)
│   ├── users.json                  # 600 - User database (v1.1 with proxy_password)
│   ├── reality_keys.json           # 600 - X25519 key pair
│   ├── reverse_proxies.json        # 600 - Reverse proxy database (v4.3)
│   ├── reverse-proxy/              # 700 - Nginx reverse proxy configs
│   │   ├── domain1.conf            # Per-domain Nginx config
│   │   ├── domain2.conf
│   │   ├── .htpasswd-domain1       # Per-domain Basic Auth
│   │   └── .htpasswd-domain2
│   └── nginx/                      # Nginx configs (fake-site, reverse-proxy)
├── data/                           # 700, user data
│   ├── clients/                    # Per-user configs
│   │   └── <username>/             # 8 files per user (3 VLESS + 5 proxy)
│   │       ├── vless_config.json   # VLESS client config
│   │       ├── vless_uri.txt       # VLESS connection string
│   │       ├── qrcode.png          # QR code for mobile
│   │       ├── socks5_config.txt   # SOCKS5 URI (socks5s://)
│   │       ├── http_config.txt     # HTTP URI (https://)
│   │       ├── vscode_settings.json # VSCode proxy settings
│   │       ├── docker_daemon.json  # Docker daemon config
│   │       └── bash_exports.sh     # Bash environment variables
│   └── backups/                    # Automatic backups
├── logs/                           # 755, log files
│   ├── haproxy/                    # NEW v4.3: HAProxy logs
│   │   └── haproxy.log             # Unified log stream
│   ├── xray/
│   │   └── error.log
│   └── nginx/
│       ├── reverse-proxy-error.log # Reverse proxy error log
│       └── fake-site-error.log
├── certs/                          # 700 - NEW v4.3: HAProxy certificates
│   └── combined.pem                # 600 - fullchain + privkey concatenated
├── fake-site/                      # 755, Nginx configs
├── scripts/                        # 755, management tools
├── .env                            # 600 - Environment variables
└── docker-compose.yml              # 644 - Container orchestration

/usr/local/bin/                     # Symlinks (sudo-accessible)
├── vless-install
├── vless-user                      # Supports show-proxy, reset-proxy-password
├── vless-proxy                     # NEW v4.3: add/list/show/remove (subdomain-based)
├── vless-start / stop / restart / status / logs  # status shows proxy + HAProxy info
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
6. Reload Xray (docker compose restart xray)
7. Generate client configs (JSON, URI, QR code)
8. Save to data/clients/{username}/
9. Display to user
```

**Acceptance Criteria:**
✓ Total time < 5 seconds
✓ UUID & shortId unique
✓ Xray reloads without errors
✓ Client configs generated (all 8 files: 3 VLESS + 5 proxy)
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

### FR-012: Proxy Server Integration (CRITICAL - Priority 1) - v3.1, TLS via HAProxy v4.3

**Requirement:** Dual proxy support (SOCKS5 + HTTP) with localhost-only binding and TLS termination via HAProxy

**Implementation:**
```yaml
TLS Termination (v4.3):
  method: "HAProxy unified container"
  architecture: "Client (TLS) → HAProxy (ports 1080/8118) → Xray plaintext (ports 10800/18118) → Internet"
  benefits:
    - "Unified architecture: 1 container instead of 2 (stunnel REMOVED)"
    - "HAProxy: Industry-standard load balancer (20+ years production)"
    - "SNI routing + TLS termination in single config"
    - "Graceful reload for zero-downtime updates"

Proxy Configuration:
  socks5:
    external_port: 1080          # HAProxy listens (TLS 1.3)
    internal_port: 10800         # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"          # Xray binding (NOT exposed to internet)
    auth: "password"             # Required
    protocol: "socks"

  http:
    external_port: 8118          # HAProxy listens (TLS 1.3)
    internal_port: 18118         # Xray listens (plaintext, localhost)
    listen: "127.0.0.1"          # Xray binding (NOT exposed to internet)
    auth: "password"             # Required
    protocol: "http"
    allowTransparent: false

Config Generation (v4.3):
  method: "heredoc in lib/haproxy_config_manager.sh"
  previous_v4.0_v4.2: "templates/stunnel.conf.template + envsubst (deprecated)"
  change_rationale: "Unified architecture (HAProxy replaces stunnel)"
  dependencies_removed: "stunnel container, stunnel.conf"

Credential Management:
  password_generation: "openssl rand -hex 8"  # 16 characters
  password_storage: "users.json v1.1 (proxy_password field)"
  single_password: true                        # Same for SOCKS5 + HTTP

Config File Export (5 formats per user, v4.1 URI fix, v4.3 HAProxy):
  - socks5_config.txt        # socks5s://user:pass@domain:1080 (TLS via HAProxy)
  - http_config.txt          # https://user:pass@domain:8118 (TLS via HAProxy)
  - vscode_settings.json     # VSCode proxy settings
  - docker_daemon.json       # Docker daemon config
  - bash_exports.sh          # Environment variables (executable)

Proxy URI Schemes Explained:
  http://   - Plaintext HTTP (NOT USED, deprecated)
  https://  - HTTP with TLS (v4.0+, HAProxy termination v4.3) ✅
  socks5:// - Plaintext SOCKS5 (NOT USED, deprecated)
  socks5s://- SOCKS5 with TLS (v4.0+, HAProxy termination v4.3) ✅
  socks5h://- SOCKS5 with DNS via proxy (NOT a TLS replacement!)
```

**Security Requirements:**
```yaml
Network Binding:
  - Proxies bind ONLY to 127.0.0.1 (localhost)
  - NOT accessible from external network
  - Require VPN connection first (must connect via VLESS)
  - Ports 1080/8118 exposed via HAProxy (TLS encrypted)

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
# Output: UUID + proxy password + 8 config files (3 VLESS + 5 proxy configs)
# Proxy configs use https:// and socks5s:// URIs (HAProxy TLS termination)

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
# Output: Proxy enabled/disabled + SOCKS5/HTTP details + HAProxy status (v4.3)
```

**Acceptance Criteria:**
✓ Proxies bind to 127.0.0.1 ONLY (not 0.0.0.0)
✓ Password authentication enforced
✓ Single password for both SOCKS5 and HTTP
✓ 5 config file formats generated per user
✓ Auto-generation on user creation
✓ Auto-regeneration on password reset
✓ Service status shows proxy info
✓ HAProxy handles TLS termination (ports 1080/8118)
✓ External access via HAProxy (TLS encrypted, verifiable with nmap)
✓ Backward compatible (VLESS-only mode works)

---

### FR-014: Subdomain-Based Reverse Proxy (NEW v4.3)

**Requirement:** Support up to 10 reverse proxies with subdomain-based access (NO port!)

**Access Format:** `https://domain` (NO port number!) - v4.3 KEY CHANGE

**Architecture:**
```
Client → HAProxy Frontend 443 (SNI routing, NO TLS decryption)
       → Nginx Backend:9443-9452 (localhost)
       → Xray Outbound
       → Target Site
```

**Port Range:** 9443-9452 (localhost-only, NOT publicly exposed)

**Public Access:** ALL via HAProxy frontend 443 (SNI routing)

**CLI Commands:**
```bash
# Add reverse proxy (interactive, subdomain-based)
sudo vless-proxy add
# Prompts for subdomain and target site
# Output: https://subdomain.example.com (NO :9443!)

# List all reverse proxies
sudo vless-proxy list
# Output: Shows all reverse proxies with subdomains, targets, credentials

# Show reverse proxy details
sudo vless-proxy show subdomain.example.com
# Output: Shows credentials, certificate expiry, fail2ban status

# Remove reverse proxy
sudo vless-proxy remove subdomain.example.com
# Output: Removes HAProxy ACL, Nginx config, Xray inbound, cleanup
```

**Configuration:**
- HAProxy dynamic ACLs (`# === DYNAMIC_REVERSE_PROXY_ROUTES ===`)
- Nginx configs: `/opt/vless/config/reverse-proxy/domain.conf`
- Database: `/opt/vless/config/reverse_proxies.json` (v4.3 schema)

**Acceptance Criteria:**
✓ Subdomain-based access (NO port!)
✓ SNI routing without TLS decryption (HAProxy passthrough)
✓ Dynamic ACL management (add/remove routes)
✓ Graceful HAProxy reload (0 downtime)
✓ Port range 9443-9452 (localhost-only)
✓ Max 10 domains per server
✓ fail2ban HAProxy + Nginx filters (multi-layer protection)

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
  haproxy_graceful_reload: "< 1 second (zero downtime)"

Reverse Proxy Setup:
  target: "< 2 minutes (subdomain-based, NO port!)"

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
    - HAProxy test: haproxy -c -f haproxy.cfg
  rollback: "Keep previous config for auto-restore"
```

### Security Requirements

```yaml
File Permissions (ENFORCED):
  /opt/vless/config/:                 "700"
  config.json / users.json / keys:    "600"
  haproxy.cfg / combined.pem:         "600"
  scripts:                            "755"

Container Security:
  xray_user: "nobody (UID 65534)"
  nginx_user: "nginx"
  haproxy_user: "haproxy"
  capabilities: drop ALL, add NET_BIND_SERVICE

Key Management:
  algorithm: "X25519"
  private_key: NEVER transmitted, 600 perms, root only
  public_key: Freely distributable
  rotation: Supported via CLI

Network Security:
  ufw_status: "active (required)"
  exposed_ports: 443/tcp (VLESS + Reverse Proxy), 1080/tcp, 8118/tcp
  docker_isolation: Separate network
  haproxy_sni_routing: "NO TLS decryption for reverse proxy"
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
docker exec vless_xray ping -c 1 8.8.8.8  # Fails
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
docker logs vless_xray  # Check errors
docker logs vless_haproxy  # NEW v4.3: Check HAProxy errors
```

**Common Causes:**
- Invalid config.json
- Invalid haproxy.cfg (v4.3)
- Missing volume mounts
- Port already bound
- Network doesn't exist

**Debug Workflow:**
```bash
1. jq . /opt/vless/config/config.json
2. xray run -test -c config.json
3. haproxy -c -f /opt/vless/config/haproxy.cfg  # NEW v4.3
4. docker network inspect vless_reality_net
5. ss -tulnp | grep ${VLESS_PORT}
6. docker logs vless_xray
7. docker logs vless_haproxy  # NEW v4.3
8. docker compose up (no -d, see live errors)
```

---

### Issue 6: HAProxy Not Routing Reverse Proxy (NEW v4.3)

**Symptoms:** 503 Service Unavailable for subdomain

**Detection:**
```bash
# Check HAProxy stats
curl http://127.0.0.1:9000/stats

# Check HAProxy logs
docker logs vless_haproxy --tail 50

# Verify SNI route exists
grep "subdomain.example.com" /opt/vless/config/haproxy.cfg

# Check Nginx backend status
docker logs vless_reverse_proxy_nginx --tail 50
```

**Solution:**
```bash
# Verify dynamic ACL section in haproxy.cfg
grep "DYNAMIC_REVERSE_PROXY_ROUTES" /opt/vless/config/haproxy.cfg

# Check Nginx backend port allocation
jq '.reverse_proxies[] | {domain, nginx_backend_port}' /opt/vless/config/reverse_proxies.json

# Verify Nginx container listening
docker exec vless_reverse_proxy_nginx ss -tulnp | grep 9443

# Manual HAProxy reload
docker exec vless_haproxy haproxy -sf $(docker exec vless_haproxy cat /var/run/haproxy.pid)
```

---

### Issue 7: HAProxy Graceful Reload Failed (NEW v4.3)

**Symptoms:** HAProxy not reloading after config change

**Detection:**
```bash
# Check HAProxy container
docker ps | grep haproxy

# Check HAProxy process
docker exec vless_haproxy ps aux | grep haproxy

# Check HAProxy config validity
docker exec vless_haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

**Solution:**
```bash
# Manual config validation
haproxy -c -f /opt/vless/config/haproxy.cfg

# Manual reload
docker exec vless_haproxy haproxy -sf $(docker exec vless_haproxy cat /var/run/haproxy.pid)

# Full restart (if reload fails)
docker compose restart haproxy
```

---

## 12. TESTING CHECKLIST

### Fresh Installation Test
**Environment:** Clean Ubuntu 22.04, no Docker, no UFW

**Success Criteria:**
- [ ] Installation < 5 minutes
- [ ] Docker/UFW auto-installed & configured
- [ ] HAProxy container running (v4.3)
- [ ] Xray container running
- [ ] Nginx container running
- [ ] Admin user created with QR
- [ ] Port 443 accessible (HAProxy SNI routing)
- [ ] Containers have Internet

### User Management Test
- [ ] Create user < 5 seconds
- [ ] QR code displayed
- [ ] All 8 config files generated (3 VLESS + 5 proxy)
- [ ] List/Show/Remove operations work

### Reverse Proxy Test (NEW v4.3)
- [ ] Add reverse proxy (subdomain-based, NO port!)
- [ ] HAProxy SNI routing works (https://domain)
- [ ] Nginx backend responds (localhost:9443-9452)
- [ ] HTTP Basic Auth enforced
- [ ] fail2ban HAProxy + Nginx filters active
- [ ] Remove reverse proxy cleanly

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

### HAProxy Tests (NEW v4.3)
- [ ] HAProxy frontend 443 SNI routing works
- [ ] HAProxy frontend 1080 TLS termination works
- [ ] HAProxy frontend 8118 TLS termination works
- [ ] HAProxy stats page accessible (http://127.0.0.1:9000/stats)
- [ ] Graceful reload works (haproxy -sf)
- [ ] fail2ban HAProxy filter active

### Update & Data Preservation Test
- [ ] All 10 users preserved after update
- [ ] Reality keys unchanged
- [ ] Client configs still valid
- [ ] Total downtime < 30 seconds
- [ ] HAProxy replaces stunnel (v4.0-v4.2 → v4.3 migration)

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
  "version": "1.1",
  "users": [
    {
      "username": "admin",
      "uuid": "12345678-1234-1234-1234-123456789012",
      "shortId": "a1b2c3d4e5f67890",
      "email": "admin@local",
      "proxy_password": "4fd0a3936e5a1e28b7c9d0f1e2a3b4c5",
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

### Reverse Proxy Data Structure (NEW v4.3)

**File:** `/opt/vless/config/reverse_proxies.json` (600 perms)
```json
{
  "version": "2.0",
  "reverse_proxies": [
    {
      "domain": "claude.ikeniborn.ru",
      "target_site": "claude.ai",
      "nginx_backend_port": 9443,
      "xray_inbound_port": 10080,
      "username": "a3f9c2e1",
      "password_hash": "$2y$10$...",
      "created_at": "2025-10-18T12:00:00Z",
      "certificate": "/etc/letsencrypt/live/claude.ikeniborn.ru/",
      "certificate_expires": "2026-01-16T12:00:00Z",
      "last_renewed": "2025-10-18T12:00:00Z",
      "enabled": true
    }
  ]
}
```

**Note:** `nginx_backend_port` is localhost-only (NOT exposed to internet). Access via HAProxy frontend 443 (SNI routing).

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

### HAProxy Configuration (haproxy.cfg) - v4.3

**Key Sections:**
- **global**: Log settings, maxconn, TLS settings
- **defaults**: Timeouts, retries, logging
- **frontend vless-reality**: SNI routing (port 443)
- **frontend socks5-tls**: SOCKS5 TLS termination (port 1080)
- **frontend http-tls**: HTTP TLS termination (port 8118)
- **frontend stats**: Stats page (port 9000, localhost)
- **backend xray_reality**: VLESS Reality backend
- **backend xray_socks5**: SOCKS5 plaintext backend
- **backend xray_http**: HTTP plaintext backend
- **backend nginx_***: Dynamic Nginx backends (reverse proxy)

**Dynamic ACL Section:**
```haproxy
# === DYNAMIC_REVERSE_PROXY_ROUTES ===
# ACLs and use_backend directives added by lib/haproxy_config_manager.sh
# Example:
#   acl is_claude req.ssl_sni -i claude.ikeniborn.ru
#   use_backend nginx_claude if is_claude
```

---

### Xray Configuration (config.json)

**Key Sections:**
- **log**: Access and error logging
- **inbounds**: VLESS (8443), SOCKS5 plaintext (10800), HTTP plaintext (18118), Reverse Proxy (10080-10089)
- **clients[]**: Array of authorized users
- **fallbacks**: Redirect invalid connections to Nginx
- **realitySettings**: Reality protocol parameters
- **serverNames**: SNI values (must match dest site)
- **shortIds**: Additional authentication layer
- **outbounds**: Traffic routing (freedom = direct, blackhole = blocked)

**v4.3 Changes:**
- VLESS inbound: port 8443 (internal, HAProxy handles 443)
- SOCKS5/HTTP inbounds: NO TLS streamSettings (HAProxy terminates TLS)
- Reverse proxy inbounds: localhost:10080-10089 (HAProxy routes to Nginx:9443-9452)

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

### Nginx Reverse Proxy Configuration (v4.3)

**Purpose:**
- Subdomain-based reverse proxy to target sites
- Localhost-only binding (ports 9443-9452)
- HTTP Basic Auth protection
- Proxies to Xray outbound → target site

**File:** `/opt/vless/config/reverse-proxy/domain.conf`
```nginx
upstream xray_reverseproxy_1 {
    server vless_xray:10080;
    keepalive 32;
}

server {
    listen 9443 ssl http2;
    server_name subdomain.example.com;

    ssl_certificate /etc/letsencrypt/live/subdomain.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/subdomain.example.com/privkey.pem;
    ssl_protocols TLSv1.3;

    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/conf.d/reverse-proxy/.htpasswd-subdomain;

    if ($host != "subdomain.example.com") {
        return 444;
    }

    location / {
        proxy_pass http://xray_reverseproxy_1;
        proxy_set_header Host target-site.com;  # Hardcoded
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
TLS & Routing: HAProxy unified container
```

**Performance:**
```yaml
User Operations (50 users):
  add: "< 5 seconds"
  list: "< 1 second"

File Sizes:
  users.json: "~10 KB (50 users)"
  config.json: "~30 KB (50 users)"
  haproxy.cfg: "~15 KB (10 reverse proxies)"

Memory:
  Xray: "~80 MB (50 concurrent)"
  Nginx: "~20 MB"
  HAProxy: "~30 MB"
```

**Design Strengths:**
- Simple architecture
- No database overhead
- JSON files easily backed up
- Fast for target scale (10-50 users)
- Unified TLS and routing (HAProxy)

**Design Limitations:**
- JSON parsing slowdown beyond 100 users
- File locking contention with high concurrent ops
- No horizontal scaling
- Max 10 reverse proxy domains per server

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
| Reverse Proxy Abuse | HIGH | HTTP Basic Auth + fail2ban HAProxy/Nginx filters |
| SNI Spoofing | MEDIUM | HAProxy ACL validation, default backend rejection |

### Security Best Practices

**1. Key Rotation:**
```bash
# When: Suspected compromise, every 6-12 months, after admin turnover
1. xray x25519  # Generate new keys
2. Update config.json with new private key
3. Regenerate all client configs
4. docker compose restart xray
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
sudo ss -tulnp | grep 1080
sudo ss -tulnp | grep 8118
sudo ufw status numbered
```

**Logs:**
```bash
sudo vless-logs -f
docker logs vless_xray --tail 50
docker logs vless_haproxy --tail 50  # NEW v4.3
docker logs vless_reverse_proxy_nginx --tail 50
```

**Config Validation:**
```bash
jq . /opt/vless/config/config.json
docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 xray run -test -c /etc/xray/config.json
haproxy -c -f /opt/vless/config/haproxy.cfg  # NEW v4.3
```

**Network Tests:**
```bash
docker exec vless_xray ping -c 1 8.8.8.8
docker exec vless_xray curl -I https://www.google.com
```

**HAProxy Tests (NEW v4.3):**
```bash
# Stats page
curl http://127.0.0.1:9000/stats

# SNI routing test
curl -I --resolve subdomain.example.com:443:127.0.0.1 https://subdomain.example.com

# TLS termination test (SOCKS5)
openssl s_client -connect localhost:1080

# TLS termination test (HTTP)
openssl s_client -connect localhost:8118
```

**User Management:**
```bash
cat /opt/vless/config/users.json | jq .
jq '.users | length' /opt/vless/config/users.json
jq -r '.users[].uuid' /opt/vless/config/users.json | sort | uniq -d  # Check UUID uniqueness
```

**Reverse Proxy Management (NEW v4.3):**
```bash
# List all reverse proxies
sudo vless-proxy list

# Show reverse proxy details
sudo vless-proxy show subdomain.example.com

# Check HAProxy ACL
grep "subdomain.example.com" /opt/vless/config/haproxy.cfg

# Check Nginx backend
docker exec vless_reverse_proxy_nginx cat /etc/nginx/conf.d/reverse-proxy/subdomain.example.com.conf
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
- HAProxy TLS termination (Public Proxy Mode, v4.3)
- Traffic encryption validation (packet capture)
- Certificate security
- DPI resistance (Deep Packet Inspection)
- SSL/TLS vulnerabilities
- Proxy protocol security (SOCKS5/HTTP)
- Data leak detection
- Reverse proxy security (HTTP Basic Auth, fail2ban)

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
HAProxy Graceful Reload: < 1 second (zero downtime, v4.3)
Reverse Proxy Setup: < 2 minutes (subdomain-based, NO port!, v4.3)
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
  - HAProxy replaces stunnel (v4.0-v4.2 → v4.3) ✓

Reverse Proxy (v4.3):
  - Subdomain-based access ✓
  - SNI routing without TLS decryption ✓
  - HAProxy graceful reload ✓
  - fail2ban HAProxy + Nginx filters ✓
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

## 17. PRD DOCUMENTATION STRUCTURE

The Product Requirements Document is split into 7 modular files for better navigation:

### File Structure

- **[00_summary.md](docs/prd/00_summary.md)** - Executive Summary, quick navigation, v4.3 overview
- **[01_overview.md](docs/prd/01_overview.md)** - Document Control, Version History, Product Overview
- **[02_functional_requirements.md](docs/prd/02_functional_requirements.md)** - All FR-* requirements (HAProxy v4.3, Reverse Proxy, Certificates, IP Whitelisting, fail2ban, etc.)
- **[03_nfr.md](docs/prd/03_nfr.md)** - Non-Functional Requirements (Security, Performance, Reliability)
- **[04_architecture.md](docs/prd/04_architecture.md)** - Section 4.7 HAProxy Unified Architecture (v4.3), Network Diagrams, Data Flow
- **[05_testing.md](docs/prd/05_testing.md)** - v4.3 Automated Test Suite, TLS Integration Tests, Security Tests
- **[06_appendix.md](docs/prd/06_appendix.md)** - Implementation Details, Security Risk Matrix, Success Metrics, Dependencies

### Recommendations

**For quick overview:** Start with [00_summary.md](docs/prd/00_summary.md)
**For development:** [02_functional_requirements.md](docs/prd/02_functional_requirements.md) + [04_architecture.md](docs/prd/04_architecture.md)
**For testing:** [05_testing.md](docs/prd/05_testing.md) + [03_nfr.md](docs/prd/03_nfr.md)
**For troubleshooting:** [06_appendix.md](docs/prd/06_appendix.md)

### Key PRD Sections for v4.3

- **FR-HAPROXY-001:** HAProxy Unified Architecture (CRITICAL)
- **FR-REVERSE-PROXY-001:** Subdomain-Based Reverse Proxy (v4.3)
- **Section 4.7:** HAProxy Unified Architecture (Technical Details)
- **NFR-RPROXY-002:** Reverse Proxy Performance Targets (v4.3)

**For detailed specs, see:** [docs/prd/README.md](docs/prd/README.md)

---

**END OF OPTIMIZED PROJECT MEMORY**

**Version History:**
```
v4.3 - 2025-10-18: HAProxy Unified Architecture (replaces stunnel, subdomain-based reverse proxy)
v4.2 - 2025-10-17: Reverse proxy planning (intermediate version)
v4.1 - 2025-10-07: Heredoc config generation (removed templates/, envsubst)
v4.0 - 2025-10-06: stunnel TLS termination (deprecated in v4.3)
v2.1 - 2025-10-03: Optimized version (-33% size, all critical info preserved)
v2.0 - 2025-10-02: Unified document (workflow + project)
v1.0 - 2025-10-01: Initial project memory
```

This document serves as the single source of truth for both workflow execution rules and project-specific technical documentation for the VLESS + Reality VPN Server project.

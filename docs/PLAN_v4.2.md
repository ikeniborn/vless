# Implementation Plan: v4.2 - Site-Specific Reverse Proxy

**Version:** 4.2
**Feature:** Site-Specific Reverse Proxy (FR-REVERSE-PROXY-001)
**Status:** 🚧 IN DEVELOPMENT
**Start Date:** 2025-10-16
**Target Release:** 2025-11-15 (30 days)
**Project Lead:** Development Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Release Scope](#2-release-scope)
3. [Implementation Phases](#3-implementation-phases)
4. [Technical Architecture](#4-technical-architecture)
5. [File Structure Changes](#5-file-structure-changes)
6. [Database Schema Changes](#6-database-schema-changes)
7. [Security Requirements](#7-security-requirements)
8. [Testing Strategy](#8-testing-strategy)
9. [Release Checklist](#9-release-checklist)
10. [Rollback Plan](#10-rollback-plan)
11. [Timeline & Milestones](#11-timeline--milestones)

---

## 1. Executive Summary

### 1.1 Goals

**Primary Goal:** Implement site-specific reverse proxy functionality to allow users to access blocked websites through their own domain with Let's Encrypt certificates.

**Key Objectives:**
1. ✅ Pass security review (CONDITIONAL APPROVAL granted with required fixes)
2. 🚧 Implement MANDATORY security mitigations (VULN-001, VULN-002)
3. 🚧 Develop setup wizard (`vless-setup-proxy`)
4. 🚧 Develop CLI management tool (`vless-proxy`)
5. 🚧 Support up to 10 domains per server
6. 🚧 Achieve 100% test coverage for security-critical components

### 1.2 Success Criteria

| Metric | Target | Validation |
|--------|--------|------------|
| **Security Review Status** | APPROVED | All MANDATORY mitigations implemented |
| **Test Coverage** | ≥ 90% | Security tests + Integration tests pass |
| **Setup Time** | < 10 minutes | Timed test from domain → working proxy |
| **Zero-Day Vulnerabilities** | 0 | Penetration testing completed |
| **Documentation Completeness** | 100% | User guide + API docs + troubleshooting |

### 1.3 Out of Scope (v4.2)

- ❌ WebSocket proxying (deferred to v4.3)
- ❌ Custom SSL certificates (Let's Encrypt only)
- ❌ Load balancing / High Availability
- ❌ CDN integration
- ❌ Web UI for management (CLI only)

---

## 2. Release Scope

### 2.1 New Features

**FR-REVERSE-PROXY-001: Site-Specific Reverse Proxy**

**Core Capabilities:**
- Nginx reverse proxy with TLS termination (TLS 1.3 only)
- HTTP Basic Auth with bcrypt hashing
- Xray domain-based routing
- Let's Encrypt automatic certificate acquisition & renewal
- Support for 10 domains per server (ports 8443-8452)
- fail2ban integration (MANDATORY)
- UFW firewall rules (per domain)
- Configurable ports (default 8443)

**User Workflow:**
```
1. Admin: sudo vless-setup-proxy
   → Enter domain (myproxy.example.com)
   → Enter target site (blocked-site.com)
   → Choose port (default 8443)
   → System obtains Let's Encrypt cert
   → System generates credentials
   → Admin receives: https://user:pass@myproxy.example.com:8443

2. User: Opens browser → https://myproxy.example.com:8443
   → Enters credentials (HTTP Basic Auth)
   → Accesses blocked-site.com seamlessly

3. Admin: sudo vless-proxy list
   → See all configured reverse proxies
   sudo vless-proxy remove myproxy.example.com
   → Remove when no longer needed
```

### 2.2 Security Improvements

**MANDATORY Fixes (from Security Review):**
1. **VULN-001 (CRITICAL):** Host Header Injection
   - Implementation: Section 7.3.1 of Security Review
   - Nginx Host header validation + default server block
   - Acceptance: Test Suite 3 passes

2. **VULN-002 (HIGH):** Missing HSTS Header
   - Implementation: Section 7.1.1 of Security Review
   - HSTS header with 1-year max-age + includeSubDomains
   - Acceptance: Test Suite 2 passes

**RECOMMENDED Fixes:**
3. **VULN-003 (MEDIUM):** No Connection Limits
   - Connection limit: 5 per IP
   - Request rate limit: 10 req/s per IP

4. **VULN-004 (MEDIUM):** No Request Rate Limiting
   - Nginx `limit_req_zone` configuration

5. **VULN-005 (MEDIUM):** No Maximum Request Body Size
   - Max body size: 10 MB

### 2.3 Breaking Changes

**NONE** - v4.2 is fully backward compatible with v4.1.

- Existing VLESS Reality VPN: Unchanged
- Existing Dual Proxy (SOCKS5/HTTP): Unchanged
- Reverse proxy is additive feature (opt-in)

---

## 3. Implementation Phases

### Phase 1: Security Hardening (Days 1-5)

**Goal:** Fix CRITICAL and HIGH vulnerabilities from Security Review

**Tasks:**
1. **VULN-001 Fix: Host Header Validation**
   - Update nginx config generation in `lib/nginx_config_generator.sh`
   - Add Host header validation (`if ($host != ...)`)
   - Add default server block (catch invalid hosts)
   - Test with curl -H "Host: evil.com"

2. **VULN-002 Fix: HSTS Header**
   - Add HSTS header to nginx config
   - max-age=31536000 (1 year)
   - includeSubDomains + preload
   - Add security headers (X-Frame-Options, X-Content-Type-Options, etc.)

3. **VULN-003/004/005 Fix: Rate Limiting**
   - Add `limit_conn_zone` (5 connections per IP)
   - Add `limit_req_zone` (10 req/s per IP, burst 20)
   - Add `client_max_body_size 10m`
   - Add timeout configuration

4. **Update FR-REVERSE-PROXY-001.md**
   - Incorporate all security fixes into spec
   - Update Nginx config examples
   - Update test cases
   - Change status to "Security Review APPROVED"

**Deliverables:**
- [ ] Updated nginx config template with all security fixes
- [ ] Test scripts for VULN-001, 002, 003, 004, 005
- [ ] FR-REVERSE-PROXY-001.md updated to DRAFT v3 (security hardened)

**Acceptance Criteria:**
- [ ] All MANDATORY test suites pass (Section 8.1 of Security Review)
- [ ] Penetration testing with testssl.sh returns A+ rating
- [ ] No CRITICAL or HIGH vulnerabilities remain

---

### Phase 2: Core Infrastructure (Days 6-12)

**Goal:** Build core reverse proxy infrastructure

**Tasks:**

**2.1 Nginx Configuration Generator (heredoc)**
- File: `lib/nginx_config_generator.sh`
- Function: `generate_reverseproxy_nginx_config()`
- Inputs: domain, target_site, port, username, password_hash
- Output: `/opt/vless/config/reverse-proxy/<domain>.conf`
- Template features:
  - TLS 1.3 only
  - Let's Encrypt certificate paths
  - HTTP Basic Auth (.htpasswd file)
  - Host header validation (VULN-001 fix)
  - HSTS header (VULN-002 fix)
  - Rate limiting (VULN-003/004/005 fix)
  - Error logging only (no access log)
  - proxy_pass to Xray HTTP inbound

**2.2 Xray HTTP Inbound Generator**
- File: `lib/xray_http_inbound.sh`
- Function: `add_http_inbound()`
- Port allocation: 10080-10089 (sequential)
- Domain-based routing rules
- Update `/opt/vless/config/config.json` atomically

**2.3 Let's Encrypt Integration**
- File: `lib/letsencrypt_integration.sh`
- Function: `obtain_certificate(domain)`
- certbot standalone mode (port 80 temporary)
- UFW rule management (open 80, close after)
- Certificate validation
- Deploy hook for nginx reload

**2.4 fail2ban Configuration**
- File: `lib/fail2ban_config.sh`
- Function: `setup_reverseproxy_fail2ban()`
- Multi-port filter (8443-8452)
- Error log parsing
- Rate limit violation detection
- UFW ban action

**2.5 Docker Compose Updates**
- Update `docker-compose.yml.template` (or use heredoc)
- Add nginx service volumes:
  - `/opt/vless/config/reverse-proxy/:/etc/nginx/conf.d/reverse-proxy/:ro`
  - `/etc/letsencrypt:/etc/letsencrypt:ro`
  - `/opt/vless/logs/nginx/:/var/log/nginx/`
- Network: `vless_reality_net`
- Restart policy: `unless-stopped`

**2.6 Database Schema**
- File: `/opt/vless/config/reverse_proxies.json`
- Schema:
```json
{
  "version": "1.0",
  "proxies": [
    {
      "domain": "myproxy.example.com",
      "target_site": "blocked-site.com",
      "port": 8443,
      "username": "user_abcdef12",
      "password_hash": "$2b$12$...",
      "xray_inbound_port": 10080,
      "xray_inbound_tag": "reverse-proxy-1",
      "nginx_config_path": "/opt/vless/config/reverse-proxy/myproxy.example.com.conf",
      "certificate_path": "/etc/letsencrypt/live/myproxy.example.com/",
      "created_at": "2025-10-16T12:00:00Z",
      "last_renewed": "2025-10-16T12:00:00Z",
      "enabled": true
    }
  ]
}
```

**Deliverables:**
- [ ] `lib/nginx_config_generator.sh` (200+ lines)
- [ ] `lib/xray_http_inbound.sh` (150+ lines)
- [ ] `lib/letsencrypt_integration.sh` (100+ lines)
- [ ] `lib/fail2ban_config.sh` (100+ lines)
- [ ] `reverse_proxies.json` schema documented
- [ ] Docker Compose nginx service configured

**Acceptance Criteria:**
- [ ] Nginx config generation creates valid config (nginx -t passes)
- [ ] Xray HTTP inbound added to config.json (xray run -test passes)
- [ ] Let's Encrypt cert obtained successfully (domain validation works)
- [ ] fail2ban detects and bans test attacks
- [ ] nginx service starts and proxies requests correctly

---

### Phase 3: CLI Tools Development (Days 13-22)

**Goal:** Develop user-facing CLI tools

#### 3.1 Setup Wizard: vless-setup-proxy

**File:** `cli/vless-setup-proxy`

**Functionality:**
```bash
#!/bin/bash
# Interactive wizard for reverse proxy setup

# 1. Prerequisites check
check_prerequisites() {
  - Docker running
  - VLESS v4.1+ installed
  - Root/sudo access
  - DNS validation (domain → server IP)
}

# 2. User input (interactive)
gather_input() {
  - Domain name (myproxy.example.com)
  - Target site (blocked-site.com)
  - Port (default 8443, custom allowed)
  - Email (for Let's Encrypt notifications)
}

# 3. Validation
validate_input() {
  - Domain DNS points to server
  - Port not in use
  - Target site reachable
  - Email valid format
}

# 4. Certificate acquisition
obtain_certificate() {
  - UFW: Open port 80 temporarily
  - certbot certonly --standalone -d $DOMAIN --email $EMAIL
  - UFW: Close port 80
  - Verify certificate obtained
}

# 5. Credential generation
generate_credentials() {
  - Username: user_$(openssl rand -hex 4)
  - Password: $(openssl rand -hex 16) # 32 characters
  - bcrypt hash: htpasswd -nbB $USERNAME $PASSWORD
}

# 6. Configuration generation
generate_configs() {
  - Nginx config: call nginx_config_generator.sh
  - Xray HTTP inbound: call xray_http_inbound.sh
  - fail2ban filter: call fail2ban_config.sh
  - UFW rule: ufw allow $PORT/tcp comment 'VLESS Reverse Proxy'
  - Save to reverse_proxies.json
}

# 7. Container restart
restart_containers() {
  - docker-compose restart xray
  - docker-compose restart nginx
  - Wait for health check
}

# 8. Validation test
test_proxy() {
  - curl -u $USERNAME:$PASSWORD https://$DOMAIN:$PORT/ -I
  - Expected: 200 OK or 301/302 redirect
}

# 9. Display credentials
show_credentials() {
  echo "✅ Reverse Proxy configured successfully!"
  echo ""
  echo "Access URL: https://$DOMAIN:$PORT/"
  echo "Username: $USERNAME"
  echo "Password: $PASSWORD"
  echo ""
  echo "Full URI: https://$USERNAME:$PASSWORD@$DOMAIN:$PORT/"
  echo ""
  echo "Management commands:"
  echo "  vless-proxy show $DOMAIN"
  echo "  vless-proxy remove $DOMAIN"
}
```

**Acceptance Criteria:**
- [ ] Script completes setup in < 10 minutes
- [ ] DNS validation works correctly
- [ ] Certificate obtained successfully
- [ ] All configs generated without errors
- [ ] Test access succeeds
- [ ] Credentials displayed clearly

---

#### 3.2 Management CLI: vless-proxy

**File:** `cli/vless-proxy`

**Commands:**

##### 3.2.1 add - Add new reverse proxy
```bash
vless-proxy add <domain> <target> [--port PORT]

# Example:
vless-proxy add myproxy.example.com blocked-site.com
vless-proxy add proxy2.example.com target2.com --port 9443

# Implementation:
- Validate inputs (domain, target reachable, port available)
- Check limit (max 10 proxies)
- Call vless-setup-proxy with provided params
- Non-interactive mode (use defaults or fail)
```

##### 3.2.2 list - List all reverse proxies
```bash
vless-proxy list

# Output:
┌────────────────────────────┬───────────────────────┬──────┬─────────┐
│ Domain                     │ Target Site           │ Port │ Status  │
├────────────────────────────┼───────────────────────┼──────┼─────────┤
│ myproxy.example.com        │ blocked-site.com      │ 8443 │ ✅ Active│
│ proxy2.example.com         │ target2.com           │ 9443 │ ✅ Active│
└────────────────────────────┴───────────────────────┴──────┴─────────┘

Total: 2/10 reverse proxies configured

# Implementation:
- Read reverse_proxies.json
- Check status (nginx config exists, cert valid, xray inbound present)
- Format table output
```

##### 3.2.3 show - Show details for specific proxy
```bash
vless-proxy show myproxy.example.com

# Output:
Reverse Proxy: myproxy.example.com
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configuration:
  Domain:              myproxy.example.com
  Target Site:         blocked-site.com
  Port:                8443
  Status:              ✅ Active

Access:
  URL:                 https://myproxy.example.com:8443/
  Username:            user_abc123
  Password:            [use 'show-password' to reveal]
  Full URI:            https://user_abc123:****@myproxy.example.com:8443/

Xray:
  Inbound Tag:         reverse-proxy-1
  Inbound Port:        10080 (localhost)
  Routing Rule:        domain = blocked-site.com

Certificate:
  Issued By:           Let's Encrypt
  Valid Until:         2025-12-15 12:00:00 UTC (89 days left)
  Auto-Renewal:        ✅ Enabled (certbot cron)

Security:
  TLS Version:         TLS 1.3 only
  HSTS:                ✅ Enabled (max-age=31536000)
  fail2ban:            ✅ Active (5 retries → 1 hour ban)
  Rate Limiting:       ✅ 10 req/s per IP, max 5 connections

Files:
  Nginx Config:        /opt/vless/config/reverse-proxy/myproxy.example.com.conf
  Certificate:         /etc/letsencrypt/live/myproxy.example.com/
  htpasswd:            /opt/vless/config/reverse-proxy/.htpasswd-myproxy

Created:               2025-10-16 12:00:00 UTC
Last Renewed:          2025-10-16 12:00:00 UTC

# Implementation:
- Read reverse_proxies.json entry
- Check nginx config exists
- Check certificate validity (openssl x509 -enddate)
- Check xray inbound in config.json
- Check fail2ban status
- Format detailed output
```

##### 3.2.4 remove - Remove reverse proxy
```bash
vless-proxy remove myproxy.example.com

# Confirmation prompt:
⚠️  WARNING: Remove reverse proxy 'myproxy.example.com'?

This will:
  - Remove Nginx configuration
  - Remove Xray HTTP inbound
  - Remove fail2ban filter
  - Remove UFW firewall rule
  - Revoke Let's Encrypt certificate (optional)
  - Remove credentials

Target site: blocked-site.com
Port: 8443

Continue? [y/N]:

# Implementation:
- Confirm with user
- Remove nginx config file
- Remove xray HTTP inbound from config.json
- Remove fail2ban filter
- Remove UFW rule: ufw delete allow $PORT/tcp
- Optional: certbot revoke (ask user)
- Remove from reverse_proxies.json
- Restart containers
```

##### 3.2.5 renew-cert - Manually renew certificate
```bash
vless-proxy renew-cert myproxy.example.com

# Output:
Renewing certificate for myproxy.example.com...
✅ Certificate renewed successfully
   Valid until: 2026-01-15 12:00:00 UTC (90 days)
✅ Nginx reloaded

# Implementation:
- certbot renew --cert-name myproxy.example.com --force-renewal
- Verify new certificate
- Reload nginx: docker-compose restart nginx
- Update last_renewed in reverse_proxies.json
```

**Deliverables:**
- [ ] `cli/vless-setup-proxy` (400+ lines)
- [ ] `cli/vless-proxy` (600+ lines)
- [ ] Symlinks in `/usr/local/bin/`
- [ ] Help text for all commands
- [ ] Error handling for all edge cases

**Acceptance Criteria:**
- [ ] All 5 commands work correctly
- [ ] Input validation prevents invalid configurations
- [ ] Atomic operations (no partial states)
- [ ] Clear error messages with actionable guidance
- [ ] Help text comprehensive and accurate

---

### Phase 4: Testing & Validation (Days 23-27)

**Goal:** Comprehensive testing of all components

#### 4.1 Unit Tests

**Test Files:**
- `tests/unit/test_nginx_config_generator.sh`
- `tests/unit/test_xray_http_inbound.sh`
- `tests/unit/test_letsencrypt_integration.sh`
- `tests/unit/test_reverseproxy_cli.sh`

**Coverage:**
- [ ] Config generation functions
- [ ] Input validation functions
- [ ] Port allocation logic
- [ ] Credential generation
- [ ] JSON manipulation (jq)

#### 4.2 Integration Tests

**Test File:** `tests/integration/test_reverseproxy_e2e.sh`

**Scenarios:**
1. **End-to-end setup**
   - Run vless-setup-proxy
   - Verify all configs generated
   - Test access with credentials
   - Verify target site content proxied

2. **Multi-domain setup**
   - Add 3 reverse proxies (different ports)
   - Verify no conflicts
   - Test all 3 proxies simultaneously

3. **Certificate renewal**
   - Force certificate renewal
   - Verify new certificate
   - Test access still works

4. **Remove proxy**
   - Remove one proxy
   - Verify cleanup complete
   - Verify other proxies unaffected

#### 4.3 Security Tests

**Test Files (from Security Review Section 8):**

##### Test Suite 1: Authentication & Authorization
**File:** `tests/security/test_auth.sh`
- Valid credentials → 200 OK
- Invalid credentials → 401 Unauthorized
- No credentials → 401 Unauthorized
- fail2ban protection (6 wrong attempts → IP banned)

##### Test Suite 2: TLS Configuration
**File:** `tests/security/test_tls.sh`
- TLS 1.3 only (TLS 1.2 rejected)
- HSTS header present (max-age=31536000)
- Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- Strong cipher suites only

##### Test Suite 3: Host Header Validation (CRITICAL)
**File:** `tests/security/test_host_header.sh`
- Valid Host header → 200 OK
- Invalid Host header → 444 No Response
- Empty Host header → 400 Bad Request
- Spoofed Host header → blocked (cannot bypass domain restriction)

##### Test Suite 4: Rate Limiting & DoS Protection
**File:** `tests/security/test_rate_limiting.sh`
- Connection limit (max 5 concurrent per IP)
- Request rate limit (10 req/s per IP)
- Body size limit (max 10 MB)
- Timeout configuration

##### Test Suite 5: Domain Restriction
**File:** `tests/security/test_domain_restriction.sh`
- Access to target site works
- Attempt to access different site via Host header fails
- Attempt to use as open proxy fails

#### 4.4 Penetration Testing

**Tools:**
- `testssl.sh` - TLS configuration audit (target: A+ rating)
- `nikto` - Web vulnerability scan
- `nmap` - Port and service detection
- `wfuzz` - Fuzzing for edge cases

**Commands:**
```bash
# TLS audit
testssl.sh --full https://myproxy.example.com:8443

# Vulnerability scan
nikto -h https://myproxy.example.com:8443 -ssl

# Port scan
nmap -p 8443 -sV --script ssl-enum-ciphers myproxy.example.com

# Host header fuzzing
wfuzz -c -z file,wordlist.txt -H "Host: FUZZ" https://myproxy.example.com:8443/
```

**Acceptance Criteria:**
- [ ] testssl.sh: A+ rating, no warnings
- [ ] nikto: No CRITICAL vulnerabilities
- [ ] nmap: Only TLS 1.3 ciphers detected
- [ ] wfuzz: No Host header injection possible

#### 4.5 Performance Testing

**Metrics:**
- Setup time: < 10 minutes (target)
- Access latency: < 50ms overhead (vs direct access)
- Concurrent connections: 50+ simultaneous users
- Memory usage: < 100 MB per proxy

**Tools:**
- `ab` (Apache Bench) - Load testing
- `time` - Setup time measurement

**Commands:**
```bash
# Setup time
time sudo vless-setup-proxy

# Load testing (50 concurrent, 1000 requests)
ab -n 1000 -c 50 -A user:pass https://myproxy.example.com:8443/

# Memory usage
docker stats vless_nginx --no-stream
```

**Deliverables:**
- [ ] All unit tests passing (100% coverage)
- [ ] All integration tests passing
- [ ] All 5 security test suites passing
- [ ] Penetration testing report (no CRITICAL/HIGH findings)
- [ ] Performance test results (all metrics met)

**Acceptance Criteria:**
- [ ] Zero CRITICAL or HIGH vulnerabilities
- [ ] All test suites pass (unit + integration + security)
- [ ] Performance targets met
- [ ] No regressions in existing v4.1 functionality

---

### Phase 5: Documentation & Release (Days 28-30)

**Goal:** Complete documentation and prepare release

#### 5.1 User Documentation

**Files to Create/Update:**

1. **README.md** - Add reverse proxy section
```markdown
## Reverse Proxy (v4.2+)

Access blocked websites through your own domain.

### Quick Start
```bash
# Setup reverse proxy
sudo vless-setup-proxy

# Manage proxies
sudo vless-proxy list
sudo vless-proxy show myproxy.example.com
sudo vless-proxy remove myproxy.example.com
```

### Use Cases
- Access blocked websites via web browser
- No VPN client required
- Works on any device with web browser
- Share access with team (HTTP Basic Auth)
```

2. **docs/REVERSE_PROXY_GUIDE.md** - Comprehensive guide
- Setup instructions (step-by-step with screenshots)
- Configuration options
- Security best practices
- Troubleshooting
- FAQ

3. **docs/REVERSE_PROXY_API.md** - CLI tool reference
- All commands documented
- Parameters and flags
- Examples
- Return codes

#### 5.2 Developer Documentation

**Files to Create:**

1. **docs/ARCHITECTURE_v4.2.md** - Architecture changes
- New components (nginx service, reverse proxy configs)
- Data flow diagrams
- File structure changes
- Database schema

2. **docs/SECURITY_v4.2.md** - Security documentation
- Threat model
- Security controls
- Vulnerability mitigations
- Security testing procedures

#### 5.3 Release Notes

**File:** `CHANGELOG.md`

**Entry:**
```markdown
## [4.2.0] - 2025-11-15

### 🎉 New Features

#### Site-Specific Reverse Proxy (FR-REVERSE-PROXY-001)
- Access blocked websites through your own domain with Let's Encrypt certificates
- HTTP Basic Auth with bcrypt hashing for secure access
- Support for up to 10 domains per server (ports 8443-8452)
- Mandatory fail2ban protection (5 retries → 1 hour ban)
- Xray domain-based routing for access control
- Configurable ports (default 8443)

**CLI Tools:**
- `vless-setup-proxy` - Interactive setup wizard
- `vless-proxy add/list/show/remove/renew-cert` - Management commands

**Use Cases:**
- Share blocked site access with team
- No VPN client needed (works in any web browser)
- Professional-looking URLs (your-domain.com)
- Ideal for web-based tools and services

### 🔒 Security Improvements

**CRITICAL Fixes:**
- Fixed VULN-001: Host Header Injection (CVSS 8.6)
  - Added Nginx Host header validation
  - Added default server block to catch invalid requests
  - Prevents abuse as open proxy

- Fixed VULN-002: Missing HSTS Header (CVSS 6.5)
  - Added HSTS header (max-age=31536000, includeSubDomains)
  - Added security headers (X-Frame-Options, X-Content-Type-Options, etc.)
  - Prevents SSL strip attacks

**Additional Hardening:**
- Connection limits (5 concurrent per IP)
- Request rate limiting (10 req/s per IP, burst 20)
- Maximum request body size (10 MB)
- Timeouts to prevent slowloris attacks
- fail2ban for rate limit violations

### 📝 Documentation

- New: Reverse Proxy Setup Guide (docs/REVERSE_PROXY_GUIDE.md)
- New: Reverse Proxy CLI Reference (docs/REVERSE_PROXY_API.md)
- New: Architecture v4.2 Documentation (docs/ARCHITECTURE_v4.2.md)
- New: Security v4.2 Documentation (docs/SECURITY_v4.2.md)
- Updated: README.md with reverse proxy section
- Updated: PRD split structure (docs/prd/FR-REVERSE-PROXY-001.md)

### 🧪 Testing

- 5 new security test suites (authentication, TLS, Host header, rate limiting, domain restriction)
- Integration tests for multi-domain setup
- Penetration testing with testssl.sh, nikto, nmap
- Performance testing (load, latency, memory)

### 🛠️ Technical Changes

**New Files:**
- `lib/reverseproxy_setup.sh` - Setup library functions
- `lib/nginx_config_generator.sh` - Nginx heredoc config generation
- `lib/xray_http_inbound.sh` - Xray HTTP inbound management
- `lib/letsencrypt_integration.sh` - Let's Encrypt automation
- `lib/fail2ban_config.sh` - fail2ban multi-port configuration
- `cli/vless-setup-proxy` - Setup wizard
- `cli/vless-proxy` - CLI management tool
- `/opt/vless/config/reverse_proxies.json` - Database schema

**Docker Compose:**
- Added nginx service with reverse proxy configs
- Shared Let's Encrypt certificates with xray

### 🔄 Migration Notes

**v4.1 → v4.2:**
- ✅ Fully backward compatible
- No changes required to existing VLESS/proxy configurations
- Reverse proxy is opt-in (not enabled by default)
- Run `sudo vless-update` to upgrade

### 📊 Security Review

- Security Review Status: ✅ APPROVED
- Vulnerabilities Fixed: 2 CRITICAL, 3 MEDIUM
- Test Coverage: 92%
- Penetration Testing: Passed (testssl.sh A+ rating)

### 🐛 Bug Fixes

- None (v4.2 is feature-only release)

### ⚠️ Breaking Changes

- None

### 📈 Performance

- Setup Time: 8.5 minutes (avg) - within 10 min target
- Access Latency: 35ms overhead - within 50ms target
- Memory Usage: 85 MB per proxy - within 100 MB target
```

#### 5.4 Migration Guide

**File:** `docs/MIGRATION_v4.1_to_v4.2.md`

```markdown
# Migration Guide: v4.1 → v4.2

## Overview

v4.2 is fully backward compatible with v4.1. No action required unless you want to use the new reverse proxy feature.

## What's Changed

- New feature added: Site-specific reverse proxy
- No changes to existing VLESS or dual proxy functionality

## Migration Steps

### Option 1: Update without reverse proxy (automatic)
```bash
sudo vless-update
# Reverse proxy not configured, system works as before
```

### Option 2: Update and add reverse proxy (manual)
```bash
# 1. Update to v4.2
sudo vless-update

# 2. Setup reverse proxy (optional)
sudo vless-setup-proxy
# Follow interactive wizard
```

## Rollback

If issues occur:
```bash
# Restore v4.1 backup
sudo vless-restore /tmp/vless_backup_<timestamp>
```

## Support

- Issues: https://github.com/user/vless/issues
- Documentation: docs/REVERSE_PROXY_GUIDE.md
```

**Deliverables:**
- [ ] README.md updated
- [ ] docs/REVERSE_PROXY_GUIDE.md created
- [ ] docs/REVERSE_PROXY_API.md created
- [ ] docs/ARCHITECTURE_v4.2.md created
- [ ] docs/SECURITY_v4.2.md created
- [ ] CHANGELOG.md entry written
- [ ] docs/MIGRATION_v4.1_to_v4.2.md created

**Acceptance Criteria:**
- [ ] All documentation complete and accurate
- [ ] Examples tested and working
- [ ] Troubleshooting section covers common issues
- [ ] Migration guide validated

---

## 4. Technical Architecture

### 4.1 System Components (v4.2)

```
┌─────────────────────────────────────────────────────────────────┐
│                      INTERNET (Untrusted)                        │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ TLS 1.3 Encrypted
                        │
        ┌───────────────┴────────────────┐
        │                                │
        │ Port 443 (VLESS Reality)       │ Port 8443-8452 (Reverse Proxy)
        │                                │
        ↓                                ↓
┌───────────────────────────────────────────────────────────────┐
│                    UFW FIREWALL                                │
│  - VLESS: 443/tcp (ALLOW)                                     │
│  - Proxy: 1080/tcp, 8118/tcp (LIMIT 10/min)                  │
│  - Reverse Proxy: 8443-8452/tcp (ALLOW, fail2ban)            │
│  - ACME: 80/tcp (temporary, certbot only)                    │
└───────────────────────┬───────────────────────────────────────┘
                        │
                        ↓
┌───────────────────────────────────────────────────────────────┐
│               DOCKER CONTAINERS (vless_reality_net)            │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ stunnel (TLS termination for SOCKS5/HTTP proxy)          │ │
│  │  - Ports: 1080, 8118                                     │ │
│  │  - Forwards to: vless_xray:10800, :18118                 │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ nginx (NEW in v4.2)                                      │ │
│  │  - TLS termination (ports 8443-8452)                     │ │
│  │  - HTTP Basic Auth (bcrypt)                              │ │
│  │  - Host header validation (VULN-001 fix)                 │ │
│  │  - HSTS header (VULN-002 fix)                            │ │
│  │  - Rate limiting (VULN-003/004/005 fix)                  │ │
│  │  - Forwards to: vless_xray:10080-10089                   │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ xray (VLESS + Dual Proxy + Reverse Proxy routing)       │ │
│  │                                                          │ │
│  │  Inbounds:                                               │ │
│  │  1. VLESS Reality (port 443)                             │ │
│  │  2. SOCKS5 plaintext (localhost:10800)                   │ │
│  │  3. HTTP plaintext (localhost:18118)                     │ │
│  │  4-13. HTTP reverse proxy (localhost:10080-10089) NEW   │ │
│  │                                                          │ │
│  │  Routing Rules (NEW in v4.2):                            │ │
│  │  - inbound=reverse-proxy-1 → domain=blocked-site.com     │ │
│  │  - inbound=reverse-proxy-2 → domain=target2.com          │ │
│  │  - ... (up to 10)                                        │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ nginx-fake-site (VLESS fallback, unchanged)              │ │
│  │  - Port: 8080 (internal)                                 │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                        │
                        │ Direct connection
                        ↓
┌───────────────────────────────────────────────────────────────┐
│                    TARGET SITES (Internet)                     │
│  - blocked-site.com (via reverse-proxy-1)                     │
│  - target2.com (via reverse-proxy-2)                          │
│  - ... (up to 10 targets)                                     │
│  - Any site (via VLESS/proxy)                                 │
└───────────────────────────────────────────────────────────────┘
```

### 4.2 Request Flow: Reverse Proxy Access

```
1. User opens browser: https://myproxy.example.com:8443/page
   ↓
2. Browser → UFW Firewall (port 8443 allowed)
   ↓
3. nginx container receives request
   ↓
4. nginx validates:
   ✓ TLS 1.3 handshake
   ✓ Host header = myproxy.example.com (VULN-001 check)
   ✓ HTTP Basic Auth credentials (bcrypt verify)
   ✓ Rate limit not exceeded (10 req/s)
   ✓ Connection limit not exceeded (5 concurrent)
   ↓
5. nginx proxies to: http://vless_xray:10080/page
   Sets Host header: blocked-site.com
   ↓
6. xray receives on localhost:10080 (inbound: reverse-proxy-1)
   ↓
7. xray routing rules check:
   ✓ inboundTag = reverse-proxy-1
   ✓ domain = blocked-site.com (from Host header)
   → outbound: direct (allow)
   ↓
8. xray connects to: blocked-site.com:443/page
   ↓
9. Response flows back:
   blocked-site.com → xray → nginx → User browser
```

### 4.3 Port Allocation Strategy

| Port Range | Purpose | Count | Exposure |
|------------|---------|-------|----------|
| 443 | VLESS Reality VPN | 1 | Public |
| 1080 | SOCKS5 Proxy (stunnel TLS) | 1 | Public |
| 8118 | HTTP Proxy (stunnel TLS) | 1 | Public |
| 8443-8452 | Reverse Proxy (nginx TLS) | 10 | Public |
| 10800 | SOCKS5 Proxy (xray plaintext) | 1 | Localhost |
| 18118 | HTTP Proxy (xray plaintext) | 1 | Localhost |
| 10080-10089 | Reverse Proxy (xray plaintext) | 10 | Localhost |
| 8080 | Fake Site (nginx) | 1 | Docker network |
| 80 | ACME HTTP-01 Challenge | 1 | Public (temporary) |

**Total Public Ports:** 13 (1 VLESS + 2 proxy + 10 reverse proxy)

---

## 5. File Structure Changes

### 5.1 New Files (v4.2)

```
/opt/vless/                                    # Production installation
├── config/
│   ├── reverse_proxies.json                   # NEW: Reverse proxy database
│   └── reverse-proxy/                         # NEW: Nginx configs
│       ├── myproxy.example.com.conf
│       ├── proxy2.example.com.conf
│       └── .htpasswd-myproxy                  # bcrypt hashed passwords
│       └── .htpasswd-proxy2
│
├── logs/
│   └── nginx/                                 # NEW: Nginx logs
│       └── reverse-proxy-error.log
│
└── cli/                                       # NEW: CLI commands directory
    ├── vless-setup-proxy               # NEW: Setup wizard
    └── vless-proxy                            # NEW: Management CLI

/usr/local/bin/                                # Symlinks
├── vless-setup-proxy → /opt/vless/cli/vless-setup-proxy
└── vless-proxy → /opt/vless/cli/vless-proxy

/home/ikeniborn/Documents/Project/vless/       # Development
├── cli/                                       # NEW: CLI commands
│   ├── vless-setup-proxy               # NEW: Setup wizard
│   └── vless-proxy                            # NEW: Management CLI
│
├── lib/
│   ├── reverseproxy_setup.sh                  # NEW: Setup functions
│   ├── nginx_config_generator.sh              # NEW: Nginx config generation
│   ├── xray_http_inbound.sh                   # NEW: Xray HTTP inbound
│   ├── letsencrypt_integration.sh             # NEW: Let's Encrypt automation
│   └── fail2ban_config.sh                     # NEW: fail2ban multi-port
│
├── docs/
│   ├── PLAN_v4.2.md                           # THIS FILE
│   ├── REVERSE_PROXY_GUIDE.md                 # NEW: User guide
│   ├── REVERSE_PROXY_API.md                   # NEW: CLI reference
│   ├── ARCHITECTURE_v4.2.md                   # NEW: Architecture docs
│   ├── SECURITY_v4.2.md                       # NEW: Security docs
│   ├── MIGRATION_v4.1_to_v4.2.md             # NEW: Migration guide
│   └── prd/
│       ├── FR-REVERSE-PROXY-001.md            # Updated to DRAFT v3
│       └── FR-REVERSE-PROXY-001_SECURITY_REVIEW.md  # Security review
│
└── tests/
    ├── unit/
    │   ├── test_nginx_config_generator.sh     # NEW
    │   ├── test_xray_http_inbound.sh          # NEW
    │   └── test_reverseproxy_cli.sh           # NEW
    ├── integration/
    │   └── test_reverseproxy_e2e.sh           # NEW
    └── security/
        ├── test_auth.sh                       # NEW
        ├── test_tls.sh                        # NEW
        ├── test_host_header.sh                # NEW (VULN-001)
        ├── test_rate_limiting.sh              # NEW (VULN-003/004/005)
        └── test_domain_restriction.sh         # NEW
```

### 5.2 Modified Files (v4.2)

```
/opt/vless/
├── config/
│   └── config.json                            # MODIFIED: Add 10 HTTP inbounds
│
└── docker-compose.yml                         # MODIFIED: Add nginx service

/home/ikeniborn/Documents/Project/vless/
├── README.md                                  # MODIFIED: Add reverse proxy section
├── CHANGELOG.md                               # MODIFIED: Add v4.2 entry
├── install.sh                                 # MODIFIED: Add reverse proxy option
└── docs/prd/
    ├── 00_summary.md                          # MODIFIED: Add FR-REVERSE-PROXY-001
    ├── 02_functional_requirements.md          # MODIFIED: Add FR summary
    └── README.md                              # MODIFIED: Update structure
```

---

## 6. Database Schema Changes

### 6.1 New Schema: reverse_proxies.json

**File:** `/opt/vless/config/reverse_proxies.json`

**Schema Version:** 1.0

```json
{
  "version": "1.0",
  "metadata": {
    "max_proxies": 10,
    "port_range": "8443-8452",
    "xray_port_range": "10080-10089",
    "created_at": "2025-10-16T12:00:00Z",
    "last_modified": "2025-10-16T12:00:00Z"
  },
  "proxies": [
    {
      "id": 1,
      "domain": "myproxy.example.com",
      "target_site": "blocked-site.com",
      "port": 8443,
      "username": "user_abc12345",
      "password_hash": "$2b$12$Xy6RnQz...",
      "xray_inbound_port": 10080,
      "xray_inbound_tag": "reverse-proxy-1",
      "nginx_config_path": "/opt/vless/config/reverse-proxy/myproxy.example.com.conf",
      "htpasswd_path": "/opt/vless/config/reverse-proxy/.htpasswd-myproxy",
      "certificate_path": "/etc/letsencrypt/live/myproxy.example.com/",
      "certificate_issued": "2025-10-16T12:00:00Z",
      "certificate_expires": "2026-01-14T12:00:00Z",
      "last_renewed": "2025-10-16T12:00:00Z",
      "ufw_rule_number": 12,
      "fail2ban_enabled": true,
      "created_at": "2025-10-16T12:00:00Z",
      "enabled": true,
      "notes": "Production proxy for team access"
    }
  ]
}
```

**Field Descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | integer | Yes | Sequential ID (1-10) |
| domain | string | Yes | Reverse proxy domain (myproxy.example.com) |
| target_site | string | Yes | Target site to proxy (blocked-site.com) |
| port | integer | Yes | Public port (8443-8452) |
| username | string | Yes | HTTP Basic Auth username (user_XXXXXXXX) |
| password_hash | string | Yes | bcrypt hash of password |
| xray_inbound_port | integer | Yes | Xray localhost port (10080-10089) |
| xray_inbound_tag | string | Yes | Xray inbound tag (reverse-proxy-N) |
| nginx_config_path | string | Yes | Path to nginx config file |
| htpasswd_path | string | Yes | Path to .htpasswd file |
| certificate_path | string | Yes | Path to Let's Encrypt certificate |
| certificate_issued | ISO8601 | Yes | Certificate issue date |
| certificate_expires | ISO8601 | Yes | Certificate expiration date |
| last_renewed | ISO8601 | Yes | Last renewal date |
| ufw_rule_number | integer | Yes | UFW rule number for removal |
| fail2ban_enabled | boolean | Yes | fail2ban protection status |
| created_at | ISO8601 | Yes | Proxy creation timestamp |
| enabled | boolean | Yes | Active status |
| notes | string | No | Admin notes |

### 6.2 Schema Operations

**Add Proxy:**
```bash
jq '.proxies += [NEW_PROXY_OBJECT]' reverse_proxies.json > reverse_proxies.json.tmp
mv reverse_proxies.json.tmp reverse_proxies.json
```

**Remove Proxy:**
```bash
jq '.proxies = [.proxies[] | select(.domain != "myproxy.example.com")]' \
  reverse_proxies.json > reverse_proxies.json.tmp
mv reverse_proxies.json.tmp reverse_proxies.json
```

**Update Certificate Dates:**
```bash
jq '(.proxies[] | select(.domain == "myproxy.example.com") |
    .certificate_expires) = "2026-04-15T12:00:00Z"' \
  reverse_proxies.json > reverse_proxies.json.tmp
mv reverse_proxies.json.tmp reverse_proxies.json
```

### 6.3 File Permissions

```
/opt/vless/config/reverse_proxies.json           # 600 (root only)
/opt/vless/config/reverse-proxy/*.conf           # 600 (root only)
/opt/vless/config/reverse-proxy/.htpasswd-*      # 600 (root only)
```

---

## 7. Security Requirements

### 7.1 MANDATORY Security Mitigations

**From Security Review (FR-REVERSE-PROXY-001_SECURITY_REVIEW.md Section 7)**

#### 7.1.1 VULN-001 Fix: Host Header Validation (CRITICAL)
**Priority:** 🔴 MANDATORY
**Timeline:** Phase 1 (Days 1-5)

**Implementation:**
```nginx
# Primary server block (myproxy.example.com)
server {
    listen 8443 ssl http2;
    server_name myproxy.example.com;  # Exact match required

    # Explicit Host validation (defense in depth)
    if ($host != "myproxy.example.com") {
        return 444;  # Close connection without response
    }

    location / {
        # CRITICAL: Set Host header to target site (hardcoded)
        proxy_set_header Host blocked-site.com;
        # Do NOT use $host or $http_host (attacker-controlled)

        proxy_pass http://vless_xray:10080;
    }
}

# Default server block (catch invalid Host headers)
server {
    listen 8443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;

    return 444;  # Reject all requests
}
```

**Validation Test:**
```bash
# Test: Valid Host header (should work)
curl -H "Host: myproxy.example.com" -u user:pass https://myproxy.example.com:8443/ -w "%{http_code}\n"
# Expected: 200

# Test: Invalid Host header (should be rejected)
curl -H "Host: evil.com" -u user:pass https://myproxy.example.com:8443/ -w "%{http_code}\n"
# Expected: 444 or connection closed
```

**Acceptance:** Test Suite 3 passes (tests/security/test_host_header.sh)

---

#### 7.1.2 VULN-002 Fix: HSTS Header (HIGH)
**Priority:** 🔴 MANDATORY
**Timeline:** Phase 1 (Days 1-5)

**Implementation:**
```nginx
server {
    listen 8443 ssl http2;
    server_name myproxy.example.com;

    # HSTS header (1 year, include subdomains, preload eligible)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Additional security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    location / {
        # ... proxy config
    }
}
```

**Validation Test:**
```bash
# Test: HSTS header present
curl -I https://myproxy.example.com:8443 | grep -i strict-transport-security
# Expected: strict-transport-security: max-age=31536000; includeSubDomains; preload
```

**Acceptance:** Test Suite 2 passes (tests/security/test_tls.sh)

---

### 7.2 RECOMMENDED Security Mitigations

#### 7.2.1 VULN-003/004/005 Fix: Rate Limiting (MEDIUM)
**Priority:** 🟡 RECOMMENDED
**Timeline:** Phase 1 (Days 1-5)

**Implementation:**
```nginx
http {
    # Connection limit zone (by IP)
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

    # Request rate limit zone (10 req/s per IP)
    limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;

    server {
        listen 8443 ssl http2;
        server_name myproxy.example.com;

        # Limit: max 5 concurrent connections per IP
        limit_conn conn_limit_per_ip 5;

        # Limit: max 10 req/s per IP, burst 20
        limit_req zone=req_limit_per_ip burst=20 nodelay;

        # Max request body size: 10 MB
        client_max_body_size 10m;

        # Timeouts (prevent slowloris)
        client_body_timeout 10s;
        client_header_timeout 10s;
        send_timeout 10s;
        keepalive_timeout 30s;

        # Error responses for limit violations
        limit_conn_status 429;
        limit_req_status 429;

        location / {
            # ... proxy config
        }
    }
}
```

**Validation Test:**
```bash
# Test: Connection limit (open 6 connections)
for i in {1..6}; do (curl -u user:pass https://proxy.example.com:8443/ --max-time 30 &); done
# Expected: 6th connection gets 429

# Test: Request rate limit (50 rapid requests)
for i in {1..50}; do curl -u user:pass https://proxy.example.com:8443/ -w "%{http_code}\n"; done | grep 429
# Expected: Some 429 responses
```

**Acceptance:** Test Suite 4 passes (tests/security/test_rate_limiting.sh)

---

### 7.3 Security Testing Requirements

**All tests from Section 8 of Security Review MUST pass before release:**

1. ✅ Test Suite 1: Authentication & Authorization
2. ✅ Test Suite 2: TLS Configuration
3. ✅ Test Suite 3: Host Header Validation (CRITICAL)
4. ✅ Test Suite 4: Rate Limiting & DoS Protection
5. ✅ Test Suite 5: Domain Restriction

**Penetration Testing:**
- testssl.sh: A+ rating required
- nikto: No CRITICAL vulnerabilities
- nmap: Only TLS 1.3 ciphers

---

## 8. Testing Strategy

### 8.1 Test Pyramid

```
                 ▲
                ╱ ╲
               ╱ E2E╲         (1 test)
              ╱───────╲
             ╱ Integr.╲       (4 tests)
            ╱───────────╲
           ╱   Security ╲     (5 test suites)
          ╱──────────────╲
         ╱   Unit Tests   ╲   (15+ tests)
        ╱──────────────────╲
```

### 8.2 Test Coverage Goals

| Test Type | Target Coverage | Actual | Status |
|-----------|----------------|--------|--------|
| Unit Tests | 80%+ | TBD | Pending |
| Integration Tests | 100% critical paths | TBD | Pending |
| Security Tests | 100% vulnerabilities | TBD | Pending |
| E2E Tests | 100% user workflows | TBD | Pending |

### 8.3 Test Execution

**Development (continuous):**
```bash
# Run unit tests
bash tests/unit/test_all.sh

# Run single test
bash tests/unit/test_nginx_config_generator.sh
```

**Pre-commit (automated):**
```bash
# Run all tests
bash tests/run_all_tests.sh

# Must pass before commit
```

**Pre-release (manual):**
```bash
# Security tests
bash tests/security/test_all.sh

# Penetration testing
testssl.sh --full https://myproxy.example.com:8443
nikto -h https://myproxy.example.com:8443 -ssl

# Performance testing
ab -n 1000 -c 50 -A user:pass https://myproxy.example.com:8443/
```

---

## 9. Release Checklist

### 9.1 Code Complete (Phase 3 End)

- [ ] All source files created and tested
- [ ] All unit tests passing
- [ ] Code review completed
- [ ] No TODO/FIXME comments in production code

### 9.2 Security Approval (Phase 4 End)

- [ ] All MANDATORY security mitigations implemented
- [ ] All 5 security test suites passing
- [ ] Penetration testing completed (no CRITICAL/HIGH findings)
- [ ] Security review re-approval obtained

### 9.3 Documentation Complete (Phase 5 End)

- [ ] README.md updated
- [ ] CHANGELOG.md entry written
- [ ] User guide created (REVERSE_PROXY_GUIDE.md)
- [ ] CLI reference created (REVERSE_PROXY_API.md)
- [ ] Architecture documentation updated
- [ ] Migration guide created

### 9.4 Quality Assurance

- [ ] All integration tests passing
- [ ] E2E test passing
- [ ] Performance targets met (< 10 min setup, < 50ms latency)
- [ ] No regressions in v4.1 functionality
- [ ] Tested on Ubuntu 22.04 and 24.04

### 9.5 Release Preparation

- [ ] Version bumped to 4.2.0 in all files
- [ ] Git tag created: `v4.2.0`
- [ ] Release notes finalized
- [ ] Backup/rollback procedure tested

### 9.6 Deployment

- [ ] Staged environment deployment successful
- [ ] Smoke tests passed in staging
- [ ] Production deployment plan approved
- [ ] Rollback plan ready

### 9.7 Post-Release

- [ ] Monitor for issues (first 48 hours)
- [ ] User feedback collection
- [ ] Performance monitoring
- [ ] Security incident response ready

---

## 10. Rollback Plan

### 10.1 Backup Strategy

**Before Installation:**
```bash
# Automatic backup in vless-update
/opt/vless/ → /tmp/vless_backup_$(date +%Y%m%d_%H%M%S).tar.gz
```

**Backup Contents:**
- config.json (Xray config)
- users.json (user database)
- reverse_proxies.json (reverse proxy database)
- docker-compose.yml
- All configs in /opt/vless/config/
- All scripts in /opt/vless/scripts/

### 10.2 Rollback Triggers

**When to rollback:**
1. CRITICAL security vulnerability discovered
2. Service outage > 15 minutes
3. Data corruption detected
4. Unrecoverable errors during update

### 10.3 Rollback Procedure

**Automatic Rollback (if update fails):**
```bash
# Installer detects failure
echo "❌ Update failed, rolling back to v4.1..."

# Restore backup
tar -xzf /tmp/vless_backup_*.tar.gz -C /opt/vless/

# Restart containers
cd /opt/vless && docker-compose down && docker-compose up -d

# Verify v4.1 working
vless-status
```

**Manual Rollback (if issues found post-update):**
```bash
# Find backup
ls -lt /tmp/vless_backup_*.tar.gz | head -1

# Stop containers
cd /opt/vless && docker-compose down

# Restore v4.1
sudo vless-restore /tmp/vless_backup_20251116_120000.tar.gz

# Verify
vless-status
```

### 10.4 Recovery Time Objective (RTO)

**Target:** < 5 minutes to restore v4.1 functionality

**Recovery Steps Time:**
1. Stop containers: 30 seconds
2. Restore backup: 1 minute
3. Start containers: 1 minute
4. Verification: 1 minute
5. Buffer: 1.5 minutes

**Total:** ~4.5 minutes

### 10.5 Rollback Validation

**After rollback:**
```bash
# Check version
vless-status | grep Version
# Expected: v4.1

# Test VLESS
vless-user list
# Expected: All users present

# Test proxy (if configured)
vless-user show-proxy <user>
# Expected: Proxy credentials shown

# Check reverse proxy removed
ls /opt/vless/config/reverse-proxy/ 2>/dev/null
# Expected: Directory not found (v4.1 doesn't have this)
```

---

## 11. Timeline & Milestones

### 11.1 Project Timeline

```
Week 1 (Days 1-7): Security Hardening + Core Infrastructure
├─ Day 1-2:  VULN-001 (Host Header Validation)
├─ Day 2-3:  VULN-002 (HSTS Header)
├─ Day 3-4:  VULN-003/004/005 (Rate Limiting)
├─ Day 4-5:  Security fixes validation
├─ Day 5-6:  Nginx config generator
├─ Day 6-7:  Xray HTTP inbound generator
└─ Milestone 1: Security hardening complete ✅

Week 2 (Days 8-14): Core Infrastructure + CLI Development Start
├─ Day 8-9:   Let's Encrypt integration
├─ Day 9-10:  fail2ban configuration
├─ Day 10-11: Docker Compose updates
├─ Day 11-12: Database schema implementation
├─ Day 12-14: vless-setup-proxy (50% done)
└─ Milestone 2: Core infrastructure complete ✅

Week 3 (Days 15-21): CLI Development
├─ Day 15-16: vless-setup-proxy (complete)
├─ Day 16-18: vless-proxy (add, list, show)
├─ Day 18-20: vless-proxy (remove, renew-cert)
├─ Day 20-21: CLI testing and refinement
└─ Milestone 3: CLI tools complete ✅

Week 4 (Days 22-28): Testing & Documentation
├─ Day 22-23: Unit tests
├─ Day 23-24: Integration tests
├─ Day 24-25: Security tests (all 5 suites)
├─ Day 25-26: Penetration testing
├─ Day 26-28: Documentation (all guides)
└─ Milestone 4: Testing & docs complete ✅

Week 5 (Days 29-30): Release Preparation
├─ Day 29:    Release checklist validation
├─ Day 30:    Final review and release
└─ Milestone 5: v4.2 RELEASED 🎉

Target Release Date: 2025-11-15 (30 days from start)
```

### 11.2 Milestones

| Milestone | Date | Deliverables | Status |
|-----------|------|-------------|--------|
| **M1: Security Hardening** | Day 7 | VULN-001/002 fixed, rate limiting, FR updated | Pending |
| **M2: Core Infrastructure** | Day 14 | Nginx/Xray generators, Let's Encrypt, Docker | Pending |
| **M3: CLI Tools** | Day 21 | vless-setup-proxy, vless-proxy (5 commands) | Pending |
| **M4: Testing & Docs** | Day 28 | All tests passing, all docs complete | Pending |
| **M5: Release** | Day 30 | v4.2 deployed to production | Pending |

### 11.3 Critical Path

**Dependencies:**
1. M1 (Security) → M2 (Infrastructure) → M3 (CLI) → M4 (Testing) → M5 (Release)
2. Security fixes MUST be complete before infrastructure development
3. All MANDATORY tests MUST pass before release

**Risk Factors:**
- Let's Encrypt API rate limits (test carefully)
- Docker Compose nginx service networking issues
- Multi-domain certificate management complexity

**Mitigation:**
- Use Let's Encrypt staging environment for testing
- Thorough Docker network testing in dev environment
- Start with single domain, scale to multiple

---

## 12. Success Metrics

### 12.1 Quantitative Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Setup Time | < 10 minutes | `time vless-setup-proxy` |
| Access Latency | < 50ms overhead | `ab` benchmark vs direct access |
| Test Coverage | ≥ 90% | Test suite execution |
| Security Rating | A+ (testssl.sh) | Penetration testing |
| Zero-Day Vulnerabilities | 0 CRITICAL/HIGH | Security review + pentest |
| Documentation Completeness | 100% | Checklist validation |

### 12.2 Qualitative Metrics

| Metric | Success Criteria |
|--------|------------------|
| User Satisfaction | Positive feedback from beta testers |
| Code Quality | Clean code review, no major refactoring needed |
| Maintainability | Clear code structure, comprehensive docs |
| Security Posture | APPROVED status from security review |

---

## 13. Risks & Mitigation

### 13.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Let's Encrypt rate limits hit | MEDIUM | HIGH | Use staging environment for testing |
| Docker networking issues | LOW | MEDIUM | Thorough testing in dev environment |
| Certificate renewal failures | LOW | HIGH | Implement monitoring and alerting |
| Host header bypass found | LOW | CRITICAL | Thorough security testing before release |
| Performance degradation | MEDIUM | MEDIUM | Performance testing and optimization |

### 13.2 Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Security fixes take longer | MEDIUM | HIGH | Start with security fixes (Phase 1) |
| Testing finds major issues | MEDIUM | HIGH | Allocate buffer time (Days 29-30) |
| Documentation incomplete | LOW | MEDIUM | Start docs early (parallel with dev) |

### 13.3 Security Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| New vulnerability discovered | LOW | CRITICAL | Continuous security testing |
| fail2ban bypass found | LOW | HIGH | Multiple layers of protection |
| Certificate private key leak | LOW | CRITICAL | File permissions 600, regular audits |

---

## 14. Communication Plan

### 14.1 Stakeholders

| Stakeholder | Role | Communication Frequency |
|-------------|------|------------------------|
| Development Team | Implementation | Daily standups |
| Security Team | Review and approval | Weekly + ad-hoc |
| QA Team | Testing | Weekly + ad-hoc |
| Users | Beta testing | On release |

### 14.2 Status Updates

**Weekly Status Reports:**
- Progress on current phase
- Blockers and risks
- Next week's plan
- Ask for feedback

**Milestone Announcements:**
- M1: Security hardening complete
- M2: Core infrastructure complete
- M3: CLI tools complete
- M4: Testing complete
- M5: Release announcement

---

## 15. Appendices

### 15.1 Glossary

| Term | Definition |
|------|------------|
| **Reverse Proxy** | Server that forwards client requests to target site |
| **HTTP Basic Auth** | Authentication method using username:password in HTTP header |
| **HSTS** | HTTP Strict Transport Security (force HTTPS) |
| **fail2ban** | Intrusion prevention tool that bans IPs after failed attempts |
| **Let's Encrypt** | Free automated certificate authority |
| **bcrypt** | Password hashing algorithm (adaptive, slow by design) |
| **VULN-001** | Critical Host Header Injection vulnerability |
| **VULN-002** | High-severity Missing HSTS Header vulnerability |

### 15.2 References

**Security Review:**
- [FR-REVERSE-PROXY-001_SECURITY_REVIEW.md](FR-REVERSE-PROXY-001_SECURITY_REVIEW.md)

**Functional Requirements:**
- [FR-REVERSE-PROXY-001.md](docs/prd/FR-REVERSE-PROXY-001.md)

**External Documentation:**
- [Nginx Security Best Practices](https://docs.nginx.com/nginx/admin-guide/security-controls/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [CIS Nginx Benchmark](https://www.cisecurity.org/benchmark/nginx)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-16
**Status:** 📋 APPROVED FOR IMPLEMENTATION
**Next Review:** After each milestone completion

---

**END OF IMPLEMENTATION PLAN v4.2**

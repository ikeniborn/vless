# Product Requirements Document (PRD) v3.2

**Project:** VLESS + Reality VPN Server with Public Proxy Support
**Version:** 3.2
**Date:** 2025-10-04
**Status:** Draft
**Previous Version:** 3.1 (localhost-only proxy)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 3.2 | 2025-10-04 | System | Public proxy support (architectural change from v3.1) |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Executive Summary

### What Changed in v3.2

**CRITICAL ARCHITECTURAL CHANGE:** Proxy servers now publicly accessible from internet without requiring VPN connection.

**Key Changes:**
- **Proxy Binding:** `127.0.0.1` → `0.0.0.0` (public internet access)
- **Password Length:** 16 chars → 32 chars (enhanced security)
- **Firewall:** Open ports 1080, 8118 with rate limiting
- **Security:** Mandatory fail2ban + rate limiting for public exposure
- **Use Case:** Proxy accessible without VPN connection

**Migration Impact:**
- ⚠️ **Breaking Change:** Existing v3.1 configs with `127.0.0.1` will NOT work
- Users must regenerate all proxy config files
- No backward compatibility with v3.1 proxy configs

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + Proxy server deployable in < 5 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing
- **Public SOCKS5 Proxy:** Direct internet access on port 1080 (NEW in v3.2)
- **Public HTTP Proxy:** Web/IDE proxy on port 8118 (NEW in v3.2)
- **Hybrid Mode:** VPN for some devices, proxy for others

### 1.2 Target Users

- **Primary:** System administrators deploying VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** Proxy for desktop applications (no VPN client needed)
- **Use Case 3:** Mixed deployment (VPN + Proxy simultaneously)

### 1.3 Key Differentiators

| Feature | v3.1 | v3.2 (NEW) |
|---------|------|------------|
| Proxy Access | Localhost-only (127.0.0.1) | Public (0.0.0.0) |
| VPN Required | YES (for proxy use) | NO (direct proxy access) |
| Password Length | 16 chars | 32 chars |
| Fail2ban | Optional | **MANDATORY** |
| Rate Limiting | N/A | **MANDATORY** |
| Firewall Ports | 443 only | 443 + 1080 + 8118 |
| Config URIs | `socks5://user:pass@127.0.0.1:1080` | `socks5://user:pass@<SERVER_IP>:1080` |

---

## 2. Functional Requirements

### FR-001: Public Proxy Binding (CRITICAL - NEW)

**Requirement:** SOCKS5 and HTTP proxies MUST be accessible from public internet.

**Acceptance Criteria:**
- [ ] SOCKS5 listens on `0.0.0.0:1080` (not `127.0.0.1:1080`)
- [ ] HTTP listens on `0.0.0.0:8118` (not `127.0.0.1:8118`)
- [ ] External clients can connect directly (no VPN required)
- [ ] Verified with: `nmap -p 1080,8118 <SERVER_IP>` shows ports open
- [ ] Connection test: `curl --socks5 user:pass@<SERVER_IP>:1080 https://ifconfig.me`

**Technical Implementation:**
```json
{
  "inbounds": [
    {
      "tag": "socks5-proxy",
      "listen": "0.0.0.0",        // CHANGED from 127.0.0.1
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [],
        "udp": false,
        "ip": "0.0.0.0"           // CHANGED from 127.0.0.1
      }
    },
    {
      "tag": "http-proxy",
      "listen": "0.0.0.0",        // CHANGED from 127.0.0.1
      "port": 8118,
      "protocol": "http",
      "settings": {
        "accounts": [],
        "allowTransparent": false
      }
    }
  ]
}
```

---

### FR-002: Enhanced Password Security (CRITICAL - NEW)

**Requirement:** Proxy passwords MUST be 32+ characters to mitigate brute-force attacks.

**Acceptance Criteria:**
- [ ] Password generation: `openssl rand -hex 16` (32 hex chars)
- [ ] All new users get 32-char passwords
- [ ] Password reset generates 32-char passwords
- [ ] No manual password entry (auto-generated only)

**Before (v3.1):**
```bash
openssl rand -hex 8   # 16 characters
# Example: 4fd0a3936e5a1e28
```

**After (v3.2):**
```bash
openssl rand -hex 16  # 32 characters
# Example: 4fd0a3936e5a1e28b7c9d0f1e2a3b4c5
```

---

### FR-003: Fail2ban Integration (CRITICAL - NEW)

**Requirement:** Fail2ban MUST protect proxy ports from brute-force attacks.

**Acceptance Criteria:**
- [ ] Fail2ban installed and enabled
- [ ] Jail created for SOCKS5 (port 1080)
- [ ] Jail created for HTTP (port 8118)
- [ ] Ban after 5 failed auth attempts
- [ ] Ban duration: 1 hour (3600 seconds)
- [ ] Find time: 10 minutes (600 seconds)
- [ ] Logs monitored: `/opt/vless/logs/xray/error.log`

**Jail Configuration:**
```ini
# /etc/fail2ban/jail.d/vless-proxy.conf
[vless-socks5]
enabled  = true
port     = 1080
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600

[vless-http]
enabled  = true
port     = 8118
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600
```

**Filter:**
```ini
# /etc/fail2ban/filter.d/vless-proxy.conf
[Definition]
failregex = ^.* rejected .* from <HOST>.*$
            ^.* authentication failed .* from <HOST>.*$
ignoreregex =
```

---

### FR-004: UFW Firewall Rules (CRITICAL - NEW)

**Requirement:** UFW MUST allow proxy ports with rate limiting.

**Acceptance Criteria:**
- [ ] Port 1080/tcp open with rate limit (10 conn/minute per IP)
- [ ] Port 8118/tcp open with rate limit (10 conn/minute per IP)
- [ ] Port 443/tcp remains open (VLESS)
- [ ] Rules persist across reboots
- [ ] Rules applied ONLY if `ENABLE_PUBLIC_PROXY=true`

**UFW Commands:**
```bash
# SOCKS5 with rate limiting
sudo ufw limit 1080/tcp comment 'VLESS SOCKS5 Proxy (rate-limited)'

# HTTP with rate limiting
sudo ufw limit 8118/tcp comment 'VLESS HTTP Proxy (rate-limited)'

# Verify
sudo ufw status numbered
```

**Expected Output:**
```
To                         Action      From
--                         ------      ----
443/tcp                    ALLOW       Anywhere                  # VLESS Reality VPN
1080/tcp                   LIMIT       Anywhere                  # VLESS SOCKS5 Proxy (rate-limited)
8118/tcp                   LIMIT       Anywhere                  # VLESS HTTP Proxy (rate-limited)
```

---

### FR-005: Updated Config File Export (CRITICAL - MODIFIED)

**Requirement:** All 5 proxy config file formats MUST use `<SERVER_IP>` instead of `127.0.0.1`.

**Acceptance Criteria:**
- [ ] `socks5_config.txt`: `socks5://user:pass@<SERVER_IP>:1080`
- [ ] `http_config.txt`: `http://user:pass@<SERVER_IP>:8118`
- [ ] `vscode_settings.json`: Uses `<SERVER_IP>`
- [ ] `docker_daemon.json`: Uses `<SERVER_IP>`
- [ ] `bash_exports.sh`: Uses `<SERVER_IP>`
- [ ] SERVER_IP auto-detected via `curl -s ifconfig.me`

**File Examples:**

**1. socks5_config.txt (BEFORE vs AFTER):**
```
# v3.1 (localhost-only)
socks5://alice:4fd0a3936e5a1e28@127.0.0.1:1080

# v3.2 (public)
socks5://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080
```

**2. vscode_settings.json:**
```json
{
  "http.proxy": "socks5://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080",
  "http.proxyStrictSSL": false,
  "http.proxySupport": "on"
}
```

**3. bash_exports.sh:**
```bash
#!/bin/bash
export http_proxy="http://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118"
export https_proxy="http://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export NO_PROXY="localhost,127.0.0.0/8"
```

---

### FR-006: Hybrid Mode Installation (CRITICAL - NEW)

**Requirement:** Installer MUST ask whether to enable public proxy access.

**Acceptance Criteria:**
- [ ] Interactive prompt: `"Enable public proxy access? [y/N]"`
- [ ] Default: NO (safer default)
- [ ] If YES:
  - Install fail2ban
  - Configure fail2ban jails
  - Open UFW ports 1080, 8118
  - Set proxy listen to `0.0.0.0`
  - Generate 32-char passwords
- [ ] If NO:
  - Keep VLESS-only mode
  - No proxy inbounds
  - No fail2ban for proxy

**Installation Flow:**
```
[8/12] Configuring Security...
  ✓ UFW firewall enabled
  ✓ VLESS port 443 opened

  Enable public proxy access? [y/N]: y

  ⚠️  WARNING: Public proxy will be accessible from internet.
  ⚠️  Ensure your server can handle potential abuse.
  ⚠️  Fail2ban and rate limiting will be configured.

  Continue? [y/N]: y

  ✓ Installing fail2ban...
  ✓ Configuring fail2ban jails for ports 1080, 8118...
  ✓ Opening UFW port 1080/tcp with rate limiting...
  ✓ Opening UFW port 8118/tcp with rate limiting...
  ✓ Proxy will listen on 0.0.0.0 (public internet)
  ✓ Passwords will be 32 characters
```

---

### FR-007: Healthchecks (NEW)

**Requirement:** Docker containers MUST have healthchecks for proxy services.

**Acceptance Criteria:**
- [ ] Xray container has healthcheck for SOCKS5
- [ ] Xray container has healthcheck for HTTP
- [ ] Healthcheck interval: 30 seconds
- [ ] Healthcheck timeout: 10 seconds
- [ ] Unhealthy after 3 consecutive failures

**Docker Compose:**
```yaml
services:
  xray:
    image: teddysun/xray:24.11.30
    container_name: vless-reality
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "1080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
```

---

### FR-008: Connection Limits (NEW)

**Requirement:** Limit concurrent connections per user to prevent abuse.

**Acceptance Criteria:**
- [ ] Maximum 10 concurrent connections per proxy user
- [ ] Enforced at Xray level (if supported) OR fail2ban
- [ ] No bandwidth limits (as per Q5.1)

**Note:** Xray doesn't natively support per-user connection limits. This will be handled via fail2ban rate limiting at IP level.

---

## 3. Non-Functional Requirements

### NFR-001: Security (CRITICAL)

| Aspect | Requirement | Status |
|--------|-------------|--------|
| Password Strength | 32+ characters (hex) | NEW |
| Fail2ban | MANDATORY for public proxy | NEW |
| Rate Limiting | 10 conn/min per IP (UFW) | NEW |
| Open Ports | 443, 1080, 8118 only | MODIFIED |
| Logs | NO traffic logging (privacy) | CONFIRMED |
| Authentication | Password-only (no anonymous) | CONFIRMED |

### NFR-002: Performance

| Metric | Target | Baseline |
|--------|--------|----------|
| Proxy Latency | < 50ms (add to connection) | Local network |
| Max Concurrent Users | 10 users | Per Q5.1 |
| Concurrent Conns/User | 10 connections | Per Q5.1 |
| Bandwidth | Unlimited | Per Q5.1 |

### NFR-003: Availability

| Aspect | Requirement |
|--------|-------------|
| Uptime Target | Business operational (99%+) |
| Healthchecks | 30s interval, 3 retries |
| Auto-restart | `restart: unless-stopped` |
| Failure Recovery | Docker auto-restart on crash |

### NFR-004: Compliance

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Traffic Logging | NO | Per Q5.2 (privacy) |
| Connection Logging | YES (fail2ban only) | Security requirement |
| IP Logging | YES (fail2ban only) | Abuse prevention |

---

## 4. Technical Architecture

### 4.1 Network Architecture (v3.2)

```
┌─────────────────────────────────────────────────────────────┐
│                      INTERNET                               │
└────────────┬──────────────────┬─────────────────────────────┘
             │                  │
             │ Port 443         │ Ports 1080, 8118
             │ (VLESS)          │ (SOCKS5, HTTP)
             │                  │
       ┌─────▼──────────────────▼─────┐
       │     SERVER (Ubuntu/Debian)   │
       │   ┌─────────────────────┐    │
       │   │   UFW Firewall      │    │
       │   │  - 443 ALLOW        │    │
       │   │  - 1080 LIMIT ←NEW  │    │
       │   │  - 8118 LIMIT ←NEW  │    │
       │   └─────────┬───────────┘    │
       │             │                 │
       │   ┌─────────▼───────────┐    │
       │   │   Fail2ban ←NEW     │    │
       │   │  - SOCKS5 jail      │    │
       │   │  - HTTP jail        │    │
       │   │  - 5 retries → ban  │    │
       │   └─────────┬───────────┘    │
       │             │                 │
       │   ┌─────────▼───────────┐    │
       │   │ Docker: vless-reality│   │
       │   │  Xray-core          │    │
       │   │  ┌──────────────┐   │    │
       │   │  │ VLESS :443   │   │    │
       │   │  ├──────────────┤   │    │
       │   │  │ SOCKS5:1080  │←NEW    │
       │   │  │ listen:0.0.0.0│   │    │
       │   │  ├──────────────┤   │    │
       │   │  │ HTTP  :8118  │←NEW    │
       │   │  │ listen:0.0.0.0│   │    │
       │   │  └──────────────┘   │    │
       │   └─────────────────────┘    │
       └──────────────────────────────┘

CHANGED from v3.1:
  - Proxy listen: 127.0.0.1 → 0.0.0.0
  - UFW: +1080, +8118 with LIMIT
  - Fail2ban: NEW jails for proxy ports
```

### 4.2 Data Flow: Public Proxy Connection

```
Client (no VPN)
  │
  ├─ Uses proxy URI: socks5://user:pass@<SERVER_IP>:1080
  │
  ▼
UFW Firewall (port 1080)
  │
  ├─ Rate limit: 10 conn/min
  │
  ▼
Fail2ban (monitors Xray logs)
  │
  ├─ Failed auth? → Ban IP for 1 hour
  │
  ▼
Xray (SOCKS5 inbound on 0.0.0.0:1080)
  │
  ├─ Authenticate: user:password (32 chars)
  │
  ├─ Success? → Forward traffic
  └─ Failure? → Log + reject (fail2ban counts)
```

### 4.3 File Structure (v3.2)

```
/opt/vless/
├── config/
│   ├── xray_config.json        # 3 inbounds (VLESS + SOCKS5 + HTTP)
│   │                           # SOCKS5/HTTP listen: 0.0.0.0 ←CHANGED
│   └── users.json              # v1.1 with proxy_password (32 chars) ←CHANGED
│
├── data/clients/<user>/
│   ├── vless_config.json       # VLESS config
│   ├── socks5_config.txt       # socks5://user:pass@<SERVER_IP>:1080 ←CHANGED
│   ├── http_config.txt         # http://user:pass@<SERVER_IP>:8118 ←CHANGED
│   ├── vscode_settings.json    # Uses SERVER_IP ←CHANGED
│   ├── docker_daemon.json      # Uses SERVER_IP ←CHANGED
│   └── bash_exports.sh         # Uses SERVER_IP ←CHANGED
│
└── logs/xray/
    ├── access.log              # NOT logged (privacy)
    └── error.log               # Monitored by fail2ban ←NEW

/etc/fail2ban/
├── jail.d/
│   └── vless-proxy.conf        # Proxy jails ←NEW
└── filter.d/
    └── vless-proxy.conf        # Xray log filters ←NEW
```

---

## 5. Implementation Changes (v3.1 → v3.2)

### 5.1 Code Changes Required

| File | Lines Changed | Description |
|------|---------------|-------------|
| `lib/orchestrator.sh` | ~15 lines | Change listen: 127.0.0.1 → 0.0.0.0, add UFW rules |
| `lib/user_management.sh` | ~20 lines | Change all 127.0.0.1 → SERVER_IP, password length 32 |
| `lib/interactive_params.sh` | ~30 lines | Add "Enable public proxy?" prompt |
| `lib/fail2ban_setup.sh` | ~150 lines | NEW module for fail2ban installation & config |
| `lib/dependencies.sh` | ~5 lines | Add fail2ban to dependency list |
| `lib/security_hardening.sh` | ~20 lines | Add UFW proxy rules with rate limiting |
| `install.sh` | ~10 lines | Call fail2ban_setup if ENABLE_PUBLIC_PROXY=true |

**Total Estimated Changes:** ~250 lines across 7 files + 1 new module

### 5.2 Migration Path (v3.1 → v3.2)

**For Existing v3.1 Users:**

⚠️ **BREAKING CHANGES:**
1. All proxy config files will become invalid
2. Proxies will be accessible from internet (security risk if not prepared)

**Migration Steps:**
1. Backup current installation
2. Update code to v3.2
3. Run installer (will ask about public proxy)
4. If YES:
   - Fail2ban will be installed
   - UFW rules updated
   - All user passwords regenerated (32 chars)
   - All proxy config files regenerated with SERVER_IP
5. Distribute new config files to users

---

## 6. Security Risk Assessment

### 6.1 Threat Model (NEW in v3.2)

| Threat | Likelihood | Impact | Mitigation | Status |
|--------|------------|--------|------------|--------|
| Brute-force password | HIGH | HIGH | 32-char passwords + fail2ban | ✅ MITIGATED |
| DDoS on proxy ports | MEDIUM | MEDIUM | UFW rate limiting (10/min) | ✅ MITIGATED |
| Account sharing abuse | MEDIUM | LOW | 10 conn limit per user | ⚠️ PARTIAL |
| Traffic analysis | LOW | LOW | HTTPS encryption | ✅ INHERENT |
| IP ban evasion | MEDIUM | LOW | 1-hour ban + monitoring | ⚠️ PARTIAL |

### 6.2 Security Measures Summary

| Layer | Measure | Effectiveness |
|-------|---------|---------------|
| Network | UFW firewall + rate limiting | HIGH |
| Application | Password authentication (32 chars) | HIGH |
| Monitoring | Fail2ban (5 retries → 1h ban) | MEDIUM |
| Logging | Error logs only (no traffic) | Privacy-preserving |

---

## 7. Testing Requirements

### 7.1 Integration Tests (NEW)

**Test Case 1: Public Proxy Access**
```bash
# From external client (NOT on VPN)
curl --socks5 alice:PASSWORD@<SERVER_IP>:1080 https://ifconfig.me
# Expected: Returns external IP address

curl --proxy http://alice:PASSWORD@<SERVER_IP>:8118 https://ifconfig.me
# Expected: Returns external IP address
```

**Test Case 2: Fail2ban Protection**
```bash
# Attempt 6 connections with wrong password
for i in {1..6}; do
  curl --socks5 alice:wrongpass@<SERVER_IP>:1080 https://ifconfig.me
done

# Check IP is banned
sudo fail2ban-client status vless-socks5
# Expected: Client IP in banned list
```

**Test Case 3: Rate Limiting**
```bash
# Attempt 20 rapid connections
for i in {1..20}; do
  curl --connect-timeout 1 --socks5 alice:PASSWORD@<SERVER_IP>:1080 https://ifconfig.me &
done

# Expected: Some connections rejected (rate limit exceeded)
```

**Test Case 4: Config File Validation**
```bash
# Check all config files use SERVER_IP (not 127.0.0.1)
grep -r "127.0.0.1" /opt/vless/data/clients/alice/
# Expected: NO matches (except in comments)
```

### 7.2 Security Tests (NEW)

**Test Case 5: Port Scanning**
```bash
nmap -p 1-65535 <SERVER_IP>
# Expected: Only 443, 1080, 8118 open
```

**Test Case 6: Password Strength**
```bash
# Check password length in users.json
jq -r '.users[0].proxy_password | length' /opt/vless/config/users.json
# Expected: 32
```

---

## 8. Acceptance Criteria (v3.2)

### Phase 1: Core Implementation ✅
- [ ] Proxy binds to `0.0.0.0` (not `127.0.0.1`)
- [ ] Passwords are 32 characters
- [ ] Fail2ban installed and configured
- [ ] UFW ports 1080, 8118 open with rate limiting
- [ ] All 5 config file formats use `SERVER_IP`

### Phase 2: Security Hardening ✅
- [ ] Fail2ban jails active for SOCKS5 and HTTP
- [ ] Rate limiting effective (10 conn/min per IP)
- [ ] No ports open except 443, 1080, 8118
- [ ] Healthchecks working (30s interval)

### Phase 3: Testing ✅
- [ ] Public proxy access works (Test Case 1)
- [ ] Fail2ban blocks after 5 failures (Test Case 2)
- [ ] Rate limiting blocks excess connections (Test Case 3)
- [ ] No `127.0.0.1` in client configs (Test Case 4)
- [ ] Only required ports open (Test Case 5)
- [ ] Password length = 32 (Test Case 6)

### Phase 4: Documentation ✅
- [ ] README.md updated with v3.2 features
- [ ] CLAUDE.md updated with security warnings
- [ ] Migration guide (v3.1 → v3.2)
- [ ] PLAN_FIX.md created with implementation plan

---

## 9. Out of Scope (v3.2)

The following are explicitly NOT included:

- ❌ Traffic logging (privacy requirement)
- ❌ Per-user bandwidth limits (Q5.1: unlimited)
- ❌ Horizontal scaling (>10 users)
- ❌ Web UI for management
- ❌ Automatic backup/restore
- ❌ Custom fail2ban retry/ban times (fixed: 5/3600/600)

---

## 10. Success Metrics

| Metric | Target | Validation |
|--------|--------|------------|
| Installation Time | < 5 minutes | Timed test on clean Ubuntu 22.04 |
| Public Proxy Works | 100% | External client test (no VPN) |
| Fail2ban Blocks | 100% after 5 failures | Brute-force test |
| Rate Limiting | 100% > 10 conn/min | Concurrent connection test |
| Security Audit | 0 critical issues | nmap + manual review |
| Password Strength | 32 characters | Automated check |

---

## 11. Dependencies

### 11.1 External Dependencies (UPDATED)

| Dependency | Version | Purpose | NEW in v3.2 |
|------------|---------|---------|-------------|
| Docker | 20.10+ | Container runtime | - |
| Docker Compose | v2.0+ | Orchestration | - |
| UFW | System default | Firewall | - |
| jq | 1.5+ | JSON processing | - |
| qrencode | Latest | QR codes | - |
| **fail2ban** | **0.11+** | **Brute-force protection** | **✅ YES** |
| **netcat** | **System default** | **Healthchecks** | **✅ YES** |

### 11.2 Installation Order

1. OS detection
2. Docker + Docker Compose
3. UFW
4. **fail2ban** ← NEW
5. jq, qrencode
6. **netcat (nc)** ← NEW

---

## 12. Rollback Plan

**If v3.2 deployment fails:**

1. **Backup exists:** Restore from `/tmp/vless_backup_<timestamp>/`
2. **Firewall issues:** Close ports 1080, 8118 immediately
   ```bash
   sudo ufw delete allow 1080/tcp
   sudo ufw delete allow 8118/tcp
   ```
3. **Fail2ban issues:** Uninstall fail2ban
   ```bash
   sudo systemctl stop fail2ban
   sudo apt remove -y fail2ban
   ```
4. **Config rollback:** Restore v3.1 configs with `127.0.0.1` binding

---

## 13. Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | User | 2025-10-04 | Approved via chat |
| Tech Lead | Claude | 2025-10-04 | PRD Draft Complete |

---

**END OF PRD v3.2**

**Next Steps:**
1. Review and approve PRD v3.2
2. Create PLAN_FIX.md (detailed implementation plan)
3. Create security assessment document
4. Begin implementation on `proxy-public` feature branch

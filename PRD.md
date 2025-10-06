# Product Requirements Document (PRD) v3.3

**Project:** VLESS + Reality VPN Server with Secure Public Proxy Support
**Version:** 3.3
**Date:** 2025-10-05
**Status:** Draft
**Previous Version:** 3.2 (public proxy without TLS - **SECURITY VULNERABILITY**)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 3.3 | 2025-10-05 | System | **CRITICAL SECURITY FIX:** Mandatory TLS encryption for public proxies via Let's Encrypt |
| 3.2 | 2025-10-04 | System | Public proxy support (SECURITY ISSUE: no encryption) |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Executive Summary

### Critical Security Issue in v3.2

**🚨 VULNERABILITY IDENTIFIED:** v3.2 exposes SOCKS5 (port 1080) and HTTP (port 8118) proxies on `0.0.0.0` **WITHOUT encryption**.

**Impact:**
- ❌ User credentials transmitted in plaintext
- ❌ All proxy traffic visible to MITM attackers
- ❌ Password authentication bypassed via network sniffing
- ❌ Fail2ban ineffective against passive eavesdropping

**Risk Level:** **CRITICAL** - Production deployment NOT RECOMMENDED

---

### What Changed in v3.3

**PRIMARY GOAL:** Eliminate v3.2 security vulnerability by adding **mandatory TLS encryption** to all public proxy inbounds.

**Key Changes:**

| Component | v3.2 (Vulnerable) | v3.3 (Secure) |
|-----------|-------------------|---------------|
| **SOCKS5 Proxy** | Plain TCP on 0.0.0.0:1080 | TLS 1.3 encrypted (socks5s://) |
| **HTTP Proxy** | Plain HTTP on 0.0.0.0:8118 | HTTPS encrypted |
| **Certificates** | N/A | Let's Encrypt (auto-managed) |
| **Client URIs** | `socks5://user:pass@server:1080` | `socks5s://user:pass@server:1080` |
| **Client URIs** | `http://user:pass@server:8118` | `https://user:pass@server:8118` |
| **Security Level** | ❌ Plaintext credentials | ✅ TLS 1.3 encrypted tunnel |

**New Features:**
- ✅ **TLS Encryption:** Mandatory for SOCKS5 and HTTP proxies (Xray `streamSettings.security="tls"`)
- ✅ **Let's Encrypt Integration:** Automated certificate acquisition via certbot
- ✅ **Auto-Renewal:** Certbot cron job updates certificates every 60-80 days
- ✅ **Zero Manual Intervention:** Deploy hook auto-restarts Xray after cert renewal
- ✅ **Client Compatibility:** VSCode (HTTPS proxy native) and Git (socks5s:// native)
- ✅ **Trusted Certificates:** No SSL warnings (Let's Encrypt publicly trusted)

**Migration Impact:**
- ⚠️ **BREAKING CHANGE:** All v3.2 proxy configs become invalid
- ⚠️ **Domain Required:** Must have domain pointing to server IP for Let's Encrypt
- ⚠️ **Config Regeneration:** Users must regenerate all 5 proxy config formats
- ✅ **No Impact on VLESS:** VPN functionality unchanged

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + **Secure** Proxy server deployable in < 7 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing
- **Secure SOCKS5 Proxy:** TLS-encrypted proxy on port 1080 (**NEW in v3.3**)
- **Secure HTTP Proxy:** HTTPS proxy on port 8118 (**NEW in v3.3**)
- **Hybrid Mode:** VPN for some devices, encrypted proxy for others
- **Zero Trust Network:** No plaintext proxy access, TLS mandatory

### 1.2 Target Users

- **Primary:** System administrators deploying secure VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** **Encrypted proxy for desktop applications** (VSCode, Git) ← **ENHANCED**
- **Use Case 3:** Mixed deployment (VPN + Encrypted Proxy simultaneously)
- **Use Case 4:** Development teams requiring secure proxy for CI/CD pipelines

### 1.3 Key Differentiators

| Feature | v3.1 | v3.2 (Vulnerable) | v3.3 (Secure) |
|---------|------|-------------------|---------------|
| Proxy Access | Localhost (127.0.0.1) | Public (0.0.0.0) | Public (0.0.0.0) |
| VPN Required | YES | NO | NO |
| **Encryption** | N/A | ❌ **NONE** | ✅ **TLS 1.3** |
| **Certificate** | N/A | ❌ None | ✅ **Let's Encrypt** |
| Password Length | 16 chars | 32 chars | 32 chars |
| Fail2ban | Optional | Mandatory | Mandatory |
| Rate Limiting | N/A | UFW 10/min | UFW 10/min |
| Firewall Ports | 443 only | 443 + 1080 + 8118 | 443 + 1080 + 8118 + **80 (temp)** |
| Config URIs | `socks5://...@127.0.0.1:1080` | `socks5://...@server:1080` | `socks5s://...@server:1080` |
| **Security Level** | Low (localhost) | ❌ **CRITICAL RISK** | ✅ **Production-Ready** |

---

## 2. Functional Requirements

### FR-TLS-001: TLS Encryption для SOCKS5 Inbound (CRITICAL - NEW)

**Requirement:** SOCKS5 proxy MUST use TLS 1.3 encryption with Let's Encrypt certificates.

**Acceptance Criteria:**
- [ ] Xray `config.json` contains `streamSettings.security="tls"` for SOCKS5 inbound
- [ ] TLS handshake successful: `openssl s_client -connect server:1080 -starttls socks5`
- [ ] Certificate verified: Let's Encrypt CA trusted
- [ ] No fallback to plain SOCKS5 (enforced by config validation)
- [ ] Clients with `socks5s://` URI connect without errors
- [ ] Wireshark capture shows TLS 1.3 encrypted stream (no plaintext SOCKS5)

**Technical Implementation:**
```json
{
  "inbounds": [
    {
      "tag": "socks5-tls",
      "listen": "0.0.0.0",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [],
        "udp": false
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "/etc/xray/certs/live/${DOMAIN}/fullchain.pem",
            "keyFile": "/etc/xray/certs/live/${DOMAIN}/privkey.pem"
          }],
          "alpn": ["http/1.1"]
        }
      }
    }
  ]
}
```

**User Story:** As a developer, I want to use Git with `socks5s://` proxy so that my credentials and code are encrypted during clone/push operations.

---

### FR-TLS-002: TLS Encryption для HTTP Inbound (CRITICAL - NEW)

**Requirement:** HTTP proxy MUST use HTTPS (TLS 1.3) with Let's Encrypt certificates.

**Acceptance Criteria:**
- [ ] Xray `config.json` contains `streamSettings.security="tls"` for HTTP inbound
- [ ] HTTPS handshake successful: `curl -I --proxy https://user:pass@server:8118 https://google.com`
- [ ] Certificate verified: Let's Encrypt CA trusted
- [ ] No fallback to plain HTTP (enforced by config validation)
- [ ] VSCode can use HTTPS proxy URL without SSL warnings
- [ ] Wireshark capture shows TLS 1.3 encrypted stream (no plaintext HTTP)

**Technical Implementation:**
```json
{
  "inbounds": [
    {
      "tag": "http-tls",
      "listen": "0.0.0.0",
      "port": 8118,
      "protocol": "http",
      "settings": {
        "accounts": [],
        "allowTransparent": false
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "/etc/xray/certs/live/${DOMAIN}/fullchain.pem",
            "keyFile": "/etc/xray/certs/live/${DOMAIN}/privkey.pem"
          }],
          "alpn": ["http/1.1"]
        }
      }
    }
  ]
}
```

**User Story:** As a developer, I want to configure VSCode with HTTPS proxy so that extensions and updates are downloaded securely without SSL warnings.

---

### FR-CERT-001: Автоматическое получение Let's Encrypt сертификатов (CRITICAL - NEW)

**Requirement:** Installation script MUST automatically obtain Let's Encrypt certificates via certbot.

**Acceptance Criteria:**
- [ ] `install.sh` integrates certbot installation (apt install certbot)
- [ ] DNS validation check: `dig +short ${DOMAIN}` matches server IP
- [ ] UFW temporarily opens port 80 for ACME HTTP-01 challenge
- [ ] Certbot runs: `certbot certonly --standalone --non-interactive --agree-tos --email ${EMAIL} --domain ${DOMAIN}`
- [ ] Certificates saved to `/etc/letsencrypt/live/${DOMAIN}/`
- [ ] UFW closes port 80 after certbot completes
- [ ] Docker volume mount added: `/etc/letsencrypt:/etc/xray/certs:ro`
- [ ] Xray container can read certificates (verified on startup)
- [ ] Clear error messages on failure (DNS, port 80 occupied, rate limit)

**Installation Flow:**
```
[7/14] Configuring TLS Certificates...
  ✓ Domain: vpn.example.com
  ✓ DNS check: 203.0.113.42 (matches server IP)
  ✓ Email: admin@example.com

  ⚠️  Port 80 will be temporarily opened for ACME challenge

  ✓ Opening UFW port 80/tcp (temporary)...
  ✓ Running certbot...
     - Requesting certificate for vpn.example.com
     - ACME HTTP-01 challenge successful
     - Certificate saved: /etc/letsencrypt/live/vpn.example.com/fullchain.pem
  ✓ Closing UFW port 80/tcp...
  ✓ Mounting certificates to Xray container...
  ✓ TLS certificates ready
```

**User Story:** As a system administrator, I want certbot to automatically obtain certificates during installation so that I don't need to manually configure TLS.

---

### FR-CERT-002: Автоматическое обновление Let's Encrypt сертификатов (CRITICAL - NEW)

**Requirement:** Certbot MUST automatically renew certificates every 60-80 days with zero downtime.

**Acceptance Criteria:**
- [ ] Cron job created: `/etc/cron.d/certbot-vless-renew`
- [ ] Schedule: `0 0,12 * * *` (runs twice daily)
- [ ] Command: `certbot renew --quiet --deploy-hook "/usr/local/bin/vless-cert-renew"`
- [ ] Deploy hook script restarts Xray: `docker-compose -f /opt/vless/docker-compose.yml restart xray`
- [ ] Dry-run test passes: `certbot renew --dry-run`
- [ ] Xray downtime during renewal < 5 seconds
- [ ] Logs available: `/var/log/letsencrypt/letsencrypt.log`
- [ ] Email alerts on failure (Let's Encrypt default)
- [ ] Grace period: 30 days before expiry (renewal starts at 60 days)

**Cron Configuration:**
```bash
# /etc/cron.d/certbot-vless-renew
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Renew Let's Encrypt certificates twice daily
0 0,12 * * * root certbot renew --quiet --deploy-hook "/usr/local/bin/vless-cert-renew" >> /opt/vless/logs/certbot-renew.log 2>&1
```

**Deploy Hook Script:**
```bash
#!/bin/bash
# /usr/local/bin/vless-cert-renew

echo "$(date): Certificate renewed, restarting Xray..."
docker-compose -f /opt/vless/docker-compose.yml restart xray
echo "$(date): Xray restarted successfully"
```

**User Story:** As a system administrator, I want certificates to renew automatically without manual intervention so that I avoid service downtime due to expired certificates.

---

### FR-CONFIG-001: Генерация клиентских конфигураций с TLS URIs (HIGH - MODIFIED)

**Requirement:** `vless-user` commands MUST generate client configurations with TLS URI schemes.

**Acceptance Criteria:**
- [ ] `vless-user add` generates `socks5_config.txt` with `socks5s://user:pass@server:1080`
- [ ] `vless-user add` generates `http_config.txt` with `https://user:pass@server:8118`
- [ ] `vscode_settings.json` contains `"http.proxy": "https://user:pass@server:8118"`
- [ ] `vscode_settings.json` contains `"http.proxyStrictSSL": true`
- [ ] `git_config.txt` contains `git config http.proxy socks5s://user:pass@server:1080`
- [ ] `bash_exports.sh` contains `export https_proxy=https://user:pass@server:8118`
- [ ] No `socks5://` or `http://` schemes in any config file (plain protocols forbidden)

**File Examples:**

**1. socks5_config.txt (v3.2 vs v3.3):**
```
# v3.2 (VULNERABLE - plaintext)
socks5://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# v3.3 (SECURE - TLS encrypted)
socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080
```

**2. http_config.txt (v3.2 vs v3.3):**
```
# v3.2 (VULNERABLE - plaintext)
http://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118

# v3.3 (SECURE - HTTPS)
https://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118
```

**3. vscode_settings.json:**
```json
{
  "http.proxy": "https://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118",
  "http.proxyStrictSSL": true,
  "http.proxySupport": "on"
}
```

**4. git_config.txt:**
```bash
# Configure Git to use SOCKS5 with TLS
git config --global http.proxy socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# Alternative: Use socks5h:// for DNS resolution via proxy
git config --global http.proxy socks5h://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080
```

**5. bash_exports.sh:**
```bash
#!/bin/bash

# HTTPS Proxy (TLS encrypted)
export https_proxy="https://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118"
export HTTPS_PROXY="$https_proxy"

# For tools that support HTTP proxy but connect to HTTPS targets
export http_proxy="$https_proxy"
export HTTP_PROXY="$https_proxy"

# No proxy for localhost
export NO_PROXY="localhost,127.0.0.0/8"
export no_proxy="$NO_PROXY"
```

**User Story:** As a user, I want to receive ready-to-use TLS config files so that I don't need to manually figure out the correct URI schemes.

---

### FR-VSCODE-001: VSCode Integration через HTTPS Proxy (HIGH - NEW)

**Requirement:** VSCode MUST work seamlessly with HTTPS proxy for extensions, updates, and Git operations.

**Acceptance Criteria:**
- [ ] VSCode settings.json с `"http.proxy": "https://user:pass@server:8118"`
- [ ] VSCode settings.json с `"http.proxyStrictSSL": true` (enforces cert validation)
- [ ] Extensions Marketplace accessible and searchable via proxy
- [ ] Extension installation works via proxy
- [ ] Git operations in VSCode use proxy
- [ ] No SSL certificate warnings (Let's Encrypt trusted by VSCode)
- [ ] No manual certificate installation required

**VSCode Configuration:**
```json
{
  "http.proxy": "https://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118",
  "http.proxyStrictSSL": true,
  "http.proxySupport": "on",
  "http.proxyAuthorization": null
}
```

**Testing:**
1. Open VSCode with proxy config
2. Navigate to Extensions (Ctrl+Shift+X)
3. Search for "Python" extension
4. Install extension
5. Verify network traffic goes through proxy (check Xray logs)

**User Story:** As a developer, I want to configure VSCode with HTTPS proxy so that I can install extensions and update VSCode securely without SSL warnings.

---

### FR-GIT-001: Git Integration через SOCKS5s Proxy (HIGH - NEW)

**Requirement:** Git MUST clone repositories and perform operations via socks5s:// proxy.

**Acceptance Criteria:**
- [ ] Git config с `http.proxy socks5s://user:pass@server:1080` works without errors
- [ ] `git clone https://github.com/user/repo.git` via proxy successful
- [ ] `git push` via proxy successful
- [ ] `git pull` via proxy successful
- [ ] TLS certificate validated (Let's Encrypt trusted by Git)
- [ ] No manual certificate installation required
- [ ] DNS resolution via proxy: `socks5h://` alternative supported

**Git Configuration:**
```bash
# SOCKS5 with TLS (socks5s://)
git config --global http.proxy socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# Alternative: DNS resolution via proxy (socks5h://)
git config --global http.proxy socks5h://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# Verify
git config --get http.proxy
```

**Testing:**
```bash
# Clone test repository
git clone https://github.com/torvalds/linux.git

# Verify proxy usage in Xray logs
sudo docker logs vless-reality | grep "SOCKS"
```

**User Story:** As a developer, I want to use Git with socks5s:// proxy so that my code and credentials are encrypted during clone/push operations.

---

### FR-PUBLIC-001: Public Proxy Binding (CRITICAL - UNCHANGED from v3.2)

**Requirement:** SOCKS5 and HTTP proxies MUST be accessible from public internet (unchanged from v3.2, but now with TLS).

**Acceptance Criteria:**
- [ ] SOCKS5 listens on `0.0.0.0:1080` (TLS encrypted)
- [ ] HTTP listens on `0.0.0.0:8118` (TLS encrypted)
- [ ] External clients can connect directly (no VPN required)
- [ ] Verified with: `nmap -p 1080,8118 <SERVER_IP>` shows ports open
- [ ] **NEW:** TLS handshake verified: `openssl s_client -connect server:1080`
- [ ] Connection test: `curl --socks5 user:pass@<SERVER_IP>:1080 https://ifconfig.me`

---

### FR-PASSWORD-001: Enhanced Password Security (CRITICAL - UNCHANGED from v3.2)

**Requirement:** Proxy passwords MUST be 32+ characters to mitigate brute-force attacks.

**Acceptance Criteria:**
- [ ] Password generation: `openssl rand -hex 16` (32 hex chars)
- [ ] All new users get 32-char passwords
- [ ] Password reset generates 32-char passwords
- [ ] No manual password entry (auto-generated only)

---

### FR-FAIL2BAN-001: Fail2ban Integration (CRITICAL - UNCHANGED from v3.2)

**Requirement:** Fail2ban MUST protect proxy ports from brute-force attacks.

**Acceptance Criteria:**
- [ ] Fail2ban installed and enabled
- [ ] Jail created for SOCKS5 (port 1080)
- [ ] Jail created for HTTP (port 8118)
- [ ] Ban after 5 failed auth attempts
- [ ] Ban duration: 1 hour (3600 seconds)
- [ ] Find time: 10 minutes (600 seconds)
- [ ] Logs monitored: `/opt/vless/logs/xray/error.log`

---

### FR-UFW-001: UFW Firewall Rules (CRITICAL - MODIFIED)

**Requirement:** UFW MUST allow proxy ports with rate limiting + temporary port 80 for ACME challenge.

**Acceptance Criteria:**
- [ ] Port 1080/tcp open with rate limit (10 conn/minute per IP)
- [ ] Port 8118/tcp open with rate limit (10 conn/minute per IP)
- [ ] Port 443/tcp remains open (VLESS)
- [ ] **NEW:** Port 80/tcp temporarily opened during certbot run (auto-closed after)
- [ ] Rules persist across reboots
- [ ] Rules applied ONLY if `ENABLE_PUBLIC_PROXY=true`

**UFW Commands:**
```bash
# SOCKS5 with rate limiting (unchanged)
sudo ufw limit 1080/tcp comment 'VLESS SOCKS5 Proxy (TLS, rate-limited)'

# HTTP with rate limiting (unchanged)
sudo ufw limit 8118/tcp comment 'VLESS HTTP Proxy (TLS, rate-limited)'

# Temporary port 80 for ACME challenge (NEW)
sudo ufw allow 80/tcp comment 'ACME HTTP-01 challenge (temporary)'
# (Automatically closed after certbot completes)

# Verify
sudo ufw status numbered
```

---

### FR-MIGRATION-001: Migration Path v3.2 → v3.3 (CRITICAL - NEW)

**Requirement:** Clear migration process with breaking change warnings and config regeneration.

**Acceptance Criteria:**
- [ ] Migration guide document: `MIGRATION_v3.2_to_v3.3.md`
- [ ] `vless-update` shows breaking change warning before update
- [ ] `vless-user regenerate` command for batch config regeneration
- [ ] Changelog documents breaking changes
- [ ] README.md updated with v3.3 TLS requirements
- [ ] Old v3.2 configs do NOT work with v3.3 (validation enforced)

**Migration Warning (vless-update):**
```
⚠️  WARNING: v3.3 BREAKING CHANGES

v3.3 adds mandatory TLS encryption for proxy security.

BREAKING CHANGES:
  1. Domain required for Let's Encrypt certificates
  2. All proxy config files will be regenerated
  3. Old configs (socks5://, http://) will NOT work
  4. New configs use TLS URIs (socks5s://, https://)

REQUIRED ACTIONS AFTER UPDATE:
  1. Provide domain name and email for Let's Encrypt
  2. Run: sudo vless-user regenerate (updates all user configs)
  3. Distribute new config files to all users

Estimated downtime: 2-3 minutes (certbot + container restart)

Continue with update? [y/N]:
```

**Migration Guide Structure:**
```markdown
# Migration Guide: v3.2 → v3.3

## Prerequisites
- Domain name pointing to server IP (DNS A record)
- Email address for Let's Encrypt notifications

## Breaking Changes
1. Plain proxy (socks5://, http://) removed - TLS mandatory
2. All client configs must be regenerated
3. Port 80 temporarily required for ACME challenge

## Migration Steps
1. Backup: `sudo vless-backup`
2. Update: `sudo vless-update`
   - Installer will ask for domain and email
   - Certbot will run automatically
   - Port 80 opened temporarily (auto-closed)
3. Regenerate configs: `sudo vless-user regenerate`
4. Distribute new configs to users (vscode_settings.json, git_config.txt, etc.)

## Rollback
If migration fails:
1. Restore backup: `sudo vless-restore /tmp/vless_backup_<timestamp>`
2. Old v3.2 configs will work again
```

---

## 3. Non-Functional Requirements

### NFR-SEC-001: Mandatory TLS Policy (CRITICAL - NEW)

**Requirement:** TLS encryption MANDATORY for all public proxy inbounds. NO plain proxy allowed.

**Metrics:**
- [ ] 100% публичных прокси с TLS
- [ ] 0 plain proxy endpoints на public interface
- [ ] Audit: `nmap -sV -p 1080,8118 server` shows TLS/SSL detected
- [ ] Config validation: `jq '.inbounds[] | select(.listen=="0.0.0.0") | .streamSettings.security' config.json` returns "tls" for all

**Validation Script:**
```bash
#!/bin/bash
# Validate mandatory TLS for public proxies

CONFIG="/opt/vless/config/xray_config.json"

# Check each public inbound has TLS
jq -r '.inbounds[] | select(.listen=="0.0.0.0") | "\(.tag): \(.streamSettings.security // "NONE")"' "$CONFIG" | while read line; do
  if [[ "$line" =~ "NONE" ]]; then
    echo "❌ CRITICAL: Plain proxy detected on public interface"
    echo "   $line"
    exit 1
  fi
done

echo "✅ All public proxies have TLS enabled"
```

---

### NFR-OPS-001: Zero Manual Intervention для Certificate Renewal (CRITICAL - NEW)

**Requirement:** Сертификаты ДОЛЖНЫ обновляться автоматически без вмешательства администратора.

**Metrics:**
- [ ] 100% автоматизация renewal (cron/systemd timer)
- [ ] 0 manual steps для cert updates
- [ ] Мониторинг: cert expiry alerts за 30 дней до истечения
- [ ] Email notifications при renewal failures (Let's Encrypt default)

---

### NFR-PERF-001: TLS Performance Overhead (MEDIUM - NEW)

**Requirement:** TLS encryption НЕ ДОЛЖНО значительно влиять на производительность прокси.

**Metrics:**
- [ ] Latency overhead < 2ms (TLS handshake amortized over connection reuse)
- [ ] CPU overhead < 5% (TLS 1.3 + AES-NI hardware acceleration)
- [ ] Throughput degradation < 10% vs plain proxy
- [ ] Target: 10-50 concurrent users без performance issues

**Benchmark:**
```bash
# Baseline (no proxy)
time curl -s https://ifconfig.me

# With TLS proxy
time curl -s --proxy https://user:pass@server:8118 https://ifconfig.me

# Compare latency
```

---

### NFR-COMPAT-001: Client Compatibility (HIGH - NEW)

**Requirement:** Система ДОЛЖНА быть совместима с VSCode и Git клиентами без дополнительной настройки.

**Metrics:**
- [ ] VSCode (all versions 1.60+) - HTTPS proxy support confirmed
- [ ] Git (all versions 2.0+) - SOCKS5s support confirmed
- [ ] 100% success rate для основных операций (clone, push, extensions)
- [ ] No SSL certificate warnings (Let's Encrypt trusted by default)

---

### NFR-USABILITY-001: Installation Simplicity (MEDIUM - NEW)

**Requirement:** Установка с TLS НЕ ДОЛЖНА усложнять процесс для пользователя.

**Metrics:**
- [ ] Installation time < 7 минут (было 5 мин для v3.2, +2 мин для certbot)
- [ ] User prompts: только домен и email для Let's Encrypt
- [ ] Автоматическая валидация домена (DNS check перед certbot)
- [ ] Clear error messages on failure (DNS, port 80, rate limit)

---

### NFR-RELIABILITY-001: Cert Renewal Reliability (HIGH - NEW)

**Requirement:** Автоматическое обновление сертификатов ДОЛЖНО быть надежным.

**Metrics:**
- [ ] Cert renewal success rate > 99%
- [ ] Retry logic для failed renewals (certbot built-in: 3 attempts)
- [ ] Alert mechanism при repeated renewal failures (email notifications)
- [ ] Grace period: 30 дней до истечения для troubleshooting
- [ ] Downtime during renewal < 5 seconds

---

## 4. Technical Architecture

### 4.1 Network Architecture (v3.3 with TLS)

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└────────────┬──────────────────┬─────────────────────────────────┘
             │                  │
             │ Port 443         │ Ports 1080, 8118
             │ (VLESS)          │ (SOCKS5-TLS, HTTPS)
             │                  │
       ┌─────▼──────────────────▼─────┐
       │     SERVER (Ubuntu/Debian)   │
       │   ┌─────────────────────┐    │
       │   │   UFW Firewall      │    │
       │   │  - 443 ALLOW        │    │
       │   │  - 1080 LIMIT       │    │
       │   │  - 8118 LIMIT       │    │
       │   │  - 80 TEMP ←NEW     │    │  (for ACME)
       │   └─────────┬───────────┘    │
       │             │                 │
       │   ┌─────────▼───────────┐    │
       │   │   Fail2ban          │    │
       │   │  - SOCKS5 jail      │    │
       │   │  - HTTP jail        │    │
       │   │  - 5 retries → ban  │    │
       │   └─────────┬───────────┘    │
       │             │                 │
       │   ┌─────────▼──────────────┐ │
       │   │ Let's Encrypt Certs   │ │  ←NEW
       │   │ /etc/letsencrypt/     │ │
       │   │  └─ live/${DOMAIN}/   │ │
       │   │     ├─ fullchain.pem  │ │
       │   │     └─ privkey.pem    │ │
       │   └─────────┬──────────────┘ │
       │             │ Mount (ro)     │
       │             ↓                │
       │   ┌─────────────────────┐   │
       │   │ Docker: vless-reality│   │
       │   │  Xray-core          │   │
       │   │  ┌──────────────┐   │   │
       │   │  │ VLESS :443   │   │   │
       │   │  │ (Reality)    │   │   │
       │   │  ├──────────────┤   │   │
       │   │  │ SOCKS5:1080  │   │   │  ←MODIFIED
       │   │  │ listen:0.0.0.0│  │   │
       │   │  │ TLS 1.3 ✅   │   │   │  (NEW)
       │   │  ├──────────────┤   │   │
       │   │  │ HTTP  :8118  │   │   │  ←MODIFIED
       │   │  │ listen:0.0.0.0│  │   │
       │   │  │ TLS 1.3 ✅   │   │   │  (NEW)
       │   │  └──────────────┘   │   │
       │   └─────────────────────┘   │
       │                             │
       │   ┌─────────────────────┐   │
       │   │  Certbot (cron)     │   │  ←NEW
       │   │  - Runs 2x daily    │   │
       │   │  - Auto-renews certs│   │
       │   │  - Restarts Xray    │   │
       │   └─────────────────────┘   │
       └──────────────────────────────┘

CHANGED from v3.2:
  ✅ TLS Layer added to SOCKS5/HTTP inbounds
  ✅ Let's Encrypt certificates integrated
  ✅ Certbot auto-renewal cron job
  ✅ Port 80 temporarily opened for ACME challenge
  ✅ Docker volume mount: /etc/letsencrypt → container
```

---

### 4.2 Data Flow: TLS Proxy Connection (NEW)

```
┌─────────────────────────────────────────────────────────────┐
│                   CLIENT (VSCode/Git)                       │
│                                                             │
│  Config: socks5s://user:pass@server:1080                   │
│      OR: https://user:pass@server:8118                     │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 1. TCP Connection + TLS ClientHello
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                   UFW FIREWALL                              │
│  Rate Limit: 10 conn/min per IP                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 2. TLS ClientHello forwarded
                      ↓
┌─────────────────────────────────────────────────────────────┐
│              XRAY (SOCKS5/HTTP Inbound with TLS)            │
│                                                             │
│  Step 3: TLS Handshake                                     │
│    - Xray sends ServerHello + Let's Encrypt certificate    │
│    - Client validates certificate (Let's Encrypt CA)       │
│    - Encrypted tunnel established (TLS 1.3)                │
│                                                             │
│  Step 4: Authentication                                     │
│    - Client sends SOCKS5/HTTP request (encrypted in TLS)   │
│    - Xray decrypts → checks password (32 chars)            │
│                                                             │
│  Step 5: Success Path                                      │
│    ✅ Auth OK → Route traffic → Internet                   │
│                                                             │
│  Step 6: Failure Path                                      │
│    ❌ Auth FAIL → Log error + reject                       │
│                  → Fail2ban counts failure                  │
│                  → After 5 failures → Ban IP (1 hour)       │
└─────────────────────────────────────────────────────────────┘

SECURITY BENEFITS vs v3.2:
  ✅ Credentials encrypted in TLS tunnel (NOT plaintext)
  ✅ MITM attacker sees only TLS 1.3 encrypted stream
  ✅ Password sniffing impossible (encrypted)
  ✅ Let's Encrypt certificate trusted (no warnings)
```

---

### 4.3 Certificate Lifecycle (NEW)

```
┌──────────────────────────────────────────────────────────────┐
│                    INITIAL INSTALLATION                      │
└─────────────────────┬────────────────────────────────────────┘
                      │
                      │ 1. User provides DOMAIN + EMAIL
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                  DNS VALIDATION CHECK                       │
│  dig +short ${DOMAIN} → verify matches server IP           │
└─────────────────────┬───────────────────────────────────────┘
                      │ ✅ DNS OK
                      │
                      │ 2. Temporarily open port 80 (UFW)
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                    CERTBOT RUN                              │
│  certbot certonly --standalone --domain ${DOMAIN}           │
│                                                             │
│  ACME HTTP-01 Challenge:                                   │
│    - Let's Encrypt → HTTP request to http://domain/.well-known/acme-challenge/
│    - Certbot → Responds with challenge token               │
│    - Let's Encrypt → Validates domain control              │
│    - Certificate issued → /etc/letsencrypt/live/${DOMAIN}/│
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 3. Close port 80 (UFW)
                      │ 4. Mount /etc/letsencrypt to container
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                   XRAY STARTS WITH TLS                      │
│  Reads certificates from:                                   │
│    /etc/xray/certs/live/${DOMAIN}/fullchain.pem            │
│    /etc/xray/certs/live/${DOMAIN}/privkey.pem              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ Certificate valid for 90 days
                      │
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                 AUTO-RENEWAL (every 60 days)                │
│                                                             │
│  Cron runs: 0 0,12 * * * (twice daily)                     │
│                                                             │
│  certbot renew --quiet --deploy-hook "..."                 │
│    │                                                        │
│    ├─ IF < 30 days until expiry:                          │
│    │    - ACME challenge (port 80 re-opened temporarily)  │
│    │    - New certificate issued                           │
│    │    - Deploy hook executes:                            │
│    │      docker-compose restart xray                      │
│    │    - Xray downtime: < 5 seconds                       │
│    │                                                        │
│    └─ IF > 30 days:                                        │
│         - No action (cert still valid)                     │
└─────────────────────────────────────────────────────────────┘

FAILURE HANDLING:
  - Retry: certbot built-in (3 attempts with backoff)
  - Email alert: Let's Encrypt sends failure notifications
  - Grace period: 30 days before actual cert expiry
  - Manual override: sudo certbot renew --force-renewal
```

---

### 4.4 File Structure (v3.3)

```
/opt/vless/
├── config/
│   ├── xray_config.json        # 3 inbounds with TLS streamSettings ←MODIFIED
│   │                           # SOCKS5/HTTP: streamSettings.security="tls"
│   └── users.json              # v1.1 with proxy_password (32 chars)
│
├── data/clients/<user>/
│   ├── vless_config.json       # VLESS config (unchanged)
│   ├── socks5_config.txt       # socks5s://user:pass@server:1080 ←MODIFIED
│   ├── http_config.txt         # https://user:pass@server:8118 ←MODIFIED
│   ├── vscode_settings.json    # Uses HTTPS proxy ←MODIFIED
│   ├── docker_daemon.json      # Uses HTTPS proxy ←MODIFIED
│   └── bash_exports.sh         # Uses HTTPS proxy ←MODIFIED
│
├── logs/
│   ├── xray/
│   │   ├── access.log          # NOT logged (privacy)
│   │   └── error.log           # Monitored by fail2ban
│   └── certbot-renew.log       # Renewal logs ←NEW
│
└── scripts/
    └── vless-cert-renew        # Deploy hook script ←NEW

/etc/letsencrypt/               ←NEW
├── live/${DOMAIN}/
│   ├── fullchain.pem           # Public cert + intermediates
│   ├── privkey.pem             # Private key (600 perms)
│   ├── cert.pem                # Domain cert only
│   └── chain.pem               # Intermediate certs
├── renewal/${DOMAIN}.conf      # Certbot renewal config
└── archive/${DOMAIN}/          # Old cert versions

/etc/fail2ban/
├── jail.d/
│   └── vless-proxy.conf        # Proxy jails (unchanged)
└── filter.d/
    └── vless-proxy.conf        # Xray log filters (unchanged)

/etc/cron.d/
└── certbot-vless-renew         # Auto-renewal cron ←NEW

/usr/local/bin/
└── vless-cert-renew            # Deploy hook script ←NEW
```

---

### 4.5 Docker Compose Configuration (v3.3)

**MODIFIED: Added volume mount for Let's Encrypt certificates**

```yaml
version: '3.8'

services:
  xray:
    image: teddysun/xray:24.11.30
    container_name: vless-reality
    restart: unless-stopped
    network_mode: host
    volumes:
      - /opt/vless/config:/etc/xray:ro
      - /etc/letsencrypt:/etc/xray/certs:ro  # ←NEW: Mount Let's Encrypt certs
    environment:
      - TZ=UTC
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "1080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  nginx:
    image: nginx:alpine
    container_name: vless-fake-site
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - /opt/vless/fake-site:/etc/nginx/conf.d:ro

networks:
  vless_reality_net:
    driver: bridge
```

**Key Changes:**
- ✅ Added `/etc/letsencrypt:/etc/xray/certs:ro` volume mount
- ✅ Read-only mount for security (Xray cannot modify certs)
- ✅ Xray reads certs from `/etc/xray/certs/live/${DOMAIN}/`

---

## 5. Implementation Changes (v3.2 → v3.3)

### 5.1 Code Changes Required

| File | Lines Changed | Description |
|------|---------------|-------------|
| `lib/orchestrator.sh` | ~30 lines | Add streamSettings.security="tls" to SOCKS5/HTTP inbounds |
| `lib/user_management.sh` | ~25 lines | Change socks5:// → socks5s://, http:// → https:// |
| `lib/interactive_params.sh` | ~40 lines | Add domain/email prompts for Let's Encrypt |
| `lib/certbot_setup.sh` | ~200 lines | **NEW module** for certbot installation & config |
| `lib/dependencies.sh` | ~10 lines | Add certbot to dependency list |
| `lib/security_hardening.sh` | ~30 lines | Add port 80 temporary management, UFW rules update |
| `install.sh` | ~20 lines | Call certbot_setup, DNS validation |
| `docker-compose.yml` | ~5 lines | Add /etc/letsencrypt volume mount |
| `scripts/vless-cert-renew` | ~20 lines | **NEW script** - deploy hook for Xray restart |

**Total Estimated Changes:** ~380 lines across 9 files + 2 new modules/scripts

---

### 5.2 Migration Path (v3.2 → v3.3)

**For Existing v3.2 Users:**

⚠️ **CRITICAL BREAKING CHANGES:**
1. Domain required (must point to server IP)
2. All proxy config files will become invalid (plain → TLS URIs)
3. Port 80 must be temporarily available for ACME challenge

**Migration Steps:**

**Pre-Migration:**
```bash
# 1. Verify prerequisites
dig +short vpn.example.com    # Must return server IP
sudo ss -tulnp | grep :80      # Port 80 must be free (or temporarily stoppable)
sudo ufw status                # UFW must be active
```

**Migration:**
```bash
# 2. Backup current installation
sudo vless-backup

# 3. Update to v3.3
sudo vless-update
# Will prompt for:
#   - Domain name: vpn.example.com
#   - Email: admin@example.com

# Installer will:
#   - Install certbot
#   - Validate DNS (dig check)
#   - Temporarily open port 80
#   - Run certbot certonly
#   - Update config.json with TLS streamSettings
#   - Add /etc/letsencrypt volume mount
#   - Close port 80
#   - Setup cron for auto-renewal
#   - Restart Xray

# 4. Regenerate all user configs
sudo vless-user regenerate
# Regenerates configs for all users with TLS URIs

# 5. Distribute new configs to users
# Copy files from /opt/vless/data/clients/<user>/
```

**Post-Migration Verification:**
```bash
# Verify certificates
sudo ls -la /etc/letsencrypt/live/vpn.example.com/
# Expected: fullchain.pem, privkey.pem

# Verify TLS on SOCKS5
openssl s_client -connect server:1080
# Expected: TLS handshake success, Let's Encrypt cert shown

# Verify TLS on HTTP
curl -I --proxy https://user:pass@server:8118 https://google.com
# Expected: HTTP/1.1 200 OK

# Verify cron job
sudo crontab -l | grep certbot
# Expected: 0 0,12 * * * certbot renew...

# Test dry-run renewal
sudo certbot renew --dry-run
# Expected: Congratulations, all renewals succeeded
```

**Rollback (if needed):**
```bash
# Restore v3.2 backup
sudo vless-restore /tmp/vless_backup_<timestamp>/

# Remove certbot (optional)
sudo apt remove -y certbot
```

---

## 6. Security Risk Assessment

### 6.1 Threat Model (v3.3 vs v3.2)

| Threat | v3.2 Risk | v3.3 Risk | Mitigation |
|--------|-----------|-----------|------------|
| **Credential Sniffing** | ❌ **CRITICAL** | ✅ **MITIGATED** | TLS 1.3 encryption |
| **MITM Attack** | ❌ **CRITICAL** | ✅ **MITIGATED** | Let's Encrypt trusted cert |
| **Password Brute-force** | ⚠️ HIGH | ⚠️ MEDIUM | 32-char passwords + fail2ban |
| **Traffic Analysis** | ⚠️ MEDIUM | ✅ LOW | TLS encrypted payload |
| **DDoS on proxy ports** | ⚠️ MEDIUM | ⚠️ MEDIUM | UFW rate limiting (10/min) |
| **Cert Expiry Downtime** | N/A | ⚠️ LOW | Auto-renewal + 30-day grace |
| **Let's Encrypt Rate Limit** | N/A | ⚠️ LOW | Cert backup/restore + staging |

### 6.2 Security Improvements Summary

| Security Layer | v3.2 | v3.3 | Improvement |
|----------------|------|------|-------------|
| **Encryption** | ❌ None | ✅ TLS 1.3 | **CRITICAL FIX** |
| **Certificate** | ❌ None | ✅ Let's Encrypt | Trusted CA |
| **Password** | ✅ 32 chars | ✅ 32 chars | Unchanged |
| **Fail2ban** | ✅ Active | ✅ Active | Unchanged |
| **Rate Limiting** | ✅ UFW 10/min | ✅ UFW 10/min | Unchanged |
| **Port Management** | ✅ 443+1080+8118 | ✅ +80 (temp) | ACME challenge |

**Overall Security Posture:**
- v3.2: ❌ **NOT PRODUCTION-READY** (plaintext credentials)
- v3.3: ✅ **PRODUCTION-READY** (TLS encrypted, trusted certs)

---

## 7. Testing Requirements

### 7.1 TLS Integration Tests (NEW)

**Test Case 1: TLS Handshake - SOCKS5**
```bash
# Verify TLS on SOCKS5 port
openssl s_client -connect server:1080 -showcerts

# Expected Output:
# - Certificate chain displayed
# - Issuer: Let's Encrypt
# - Subject: CN=vpn.example.com
# - Verify return code: 0 (ok)
```

**Test Case 2: TLS Handshake - HTTP/HTTPS**
```bash
# Verify HTTPS on HTTP proxy port
curl -I --proxy https://user:pass@server:8118 https://google.com

# Expected Output:
# HTTP/1.1 200 OK
# (no SSL warnings)
```

**Test Case 3: Certificate Validation**
```bash
# Check certificate validity
openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -text

# Expected:
# - Issuer: Let's Encrypt
# - Validity: 90 days from issuance
# - Subject Alt Name: DNS:vpn.example.com
```

**Test Case 4: Auto-Renewal Dry-Run**
```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# Expected Output:
# Congratulations, all simulated renewals succeeded
```

**Test Case 5: Deploy Hook Execution**
```bash
# Manually trigger deploy hook
sudo /usr/local/bin/vless-cert-renew

# Expected:
# - Xray restarts successfully
# - Downtime < 5 seconds
# - docker logs shows restart
```

---

### 7.2 Client Integration Tests (NEW)

**Test Case 6: VSCode Extension via HTTPS Proxy**
```json
// VSCode settings.json
{
  "http.proxy": "https://alice:PASSWORD@server:8118",
  "http.proxyStrictSSL": true
}
```

**Steps:**
1. Apply settings.json
2. Open Extensions (Ctrl+Shift+X)
3. Search "Python"
4. Install extension

**Expected:**
- ✅ Extension installs successfully
- ✅ No SSL certificate warnings
- ✅ Xray logs show HTTPS connection

**Test Case 7: Git Clone via SOCKS5s Proxy**
```bash
# Configure Git
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

# Clone repository
git clone https://github.com/torvalds/linux.git

# Expected:
# - Clone succeeds
# - No TLS errors
# - Xray logs show SOCKS5 connection
```

---

### 7.3 Security Tests (v3.3)

**Test Case 8: Wireshark Traffic Capture**
```bash
# Capture proxy traffic
sudo tcpdump -i any -w /tmp/proxy_traffic.pcap port 1080

# Analyze in Wireshark
wireshark /tmp/proxy_traffic.pcap

# Expected:
# - TLS 1.3 handshake visible
# - Application Data encrypted
# - NO plaintext SOCKS5/HTTP
# - NO plaintext credentials
```

**Test Case 9: Nmap Service Detection**
```bash
# Scan proxy ports
nmap -sV -p 1080,8118 server

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 1080/tcp open  ssl/socks
# 8118/tcp open  ssl/http
```

**Test Case 10: Config Validation - No Plain Proxy**
```bash
# Ensure no plain proxy on public interface
jq '.inbounds[] | select(.listen=="0.0.0.0") | {tag, security: .streamSettings.security}' /opt/vless/config/xray_config.json

# Expected:
# {"tag": "socks5-tls", "security": "tls"}
# {"tag": "http-tls", "security": "tls"}
# (NO entries with "security": null or missing)
```

---

### 7.4 Backward Compatibility Tests (v3.2 → v3.3)

**Test Case 11: Old Configs Must Fail**
```bash
# Try connecting with old v3.2 plain config
curl --socks5 alice:PASSWORD@server:1080 https://ifconfig.me

# Expected:
# - Connection FAILS (plain SOCKS5 not accepted)
# - Error: "TLS handshake required"
```

**Test Case 12: New Configs Must Work**
```bash
# Connect with new v3.3 TLS config
curl --socks5 alice:PASSWORD@server:1080 --proxy-insecure https://ifconfig.me
# (Note: --proxy-insecure needed if testing with self-signed, NOT needed with Let's Encrypt)

# Expected:
# - Connection succeeds
# - Returns external IP
```

---

## 8. Acceptance Criteria (v3.3)

### Phase 1: Core TLS Implementation ✅

- [ ] Certbot installed and configured
- [ ] Let's Encrypt certificates obtained during installation
- [ ] Xray config.json has `streamSettings.security="tls"` for SOCKS5
- [ ] Xray config.json has `streamSettings.security="tls"` for HTTP
- [ ] Docker volume mount: `/etc/letsencrypt:/etc/xray/certs:ro`
- [ ] All 5 config file formats use TLS URIs (socks5s://, https://)

### Phase 2: Certificate Management ✅

- [ ] Cron job created: `/etc/cron.d/certbot-vless-renew`
- [ ] Deploy hook script: `/usr/local/bin/vless-cert-renew`
- [ ] Dry-run renewal test passes: `certbot renew --dry-run`
- [ ] Deploy hook restarts Xray successfully
- [ ] Downtime during renewal < 5 seconds

### Phase 3: Security Hardening ✅

- [ ] No plain proxy on public interface (validation enforced)
- [ ] TLS handshake successful on both ports (1080, 8118)
- [ ] Let's Encrypt certificate trusted (no warnings)
- [ ] Fail2ban active for SOCKS5 and HTTP (unchanged from v3.2)
- [ ] Rate limiting effective (10 conn/min per IP)
- [ ] Port 80 auto-managed (open during certbot, closed after)

### Phase 4: Client Integration ✅

- [ ] VSCode works with HTTPS proxy (Test Case 6)
- [ ] Git works with socks5s:// proxy (Test Case 7)
- [ ] No SSL certificate warnings in clients
- [ ] Config files copy-paste ready (no manual editing required)

### Phase 5: Migration & Documentation ✅

- [ ] Migration guide created: `MIGRATION_v3.2_to_v3.3.md`
- [ ] `vless-update` shows breaking change warning
- [ ] `vless-user regenerate` command implemented
- [ ] README.md updated with v3.3 TLS requirements
- [ ] PRD.md v3.3 finalized (this document)

### Phase 6: Testing ✅

- [ ] All 12 test cases pass (Test Cases 1-12)
- [ ] Wireshark confirms TLS encryption (Test Case 8)
- [ ] Nmap detects TLS on ports (Test Case 9)
- [ ] Old v3.2 configs fail (Test Case 11)
- [ ] New v3.3 configs work (Test Case 12)

---

## 9. Out of Scope (v3.3)

The following are explicitly NOT included:

- ❌ Self-signed certificates (Let's Encrypt only)
- ❌ Plain proxy fallback option (TLS mandatory)
- ❌ Manual certificate installation (certbot only)
- ❌ Alternative ACME challenges (DNS-01, TLS-ALPN-01)
- ❌ Reality protocol for proxy inbounds (TLS chosen for compatibility)
- ❌ Certificate monitoring dashboard (email alerts only)
- ❌ Traffic logging (privacy requirement, unchanged)
- ❌ Per-user bandwidth limits (unlimited, unchanged)

---

## 10. Success Metrics

| Metric | v3.2 Target | v3.3 Target | Validation |
|--------|-------------|-------------|------------|
| **Installation Time** | < 5 minutes | **< 7 minutes** | Timed test (+2 min for certbot) |
| **Security Audit** | ❌ CRITICAL ISSUES | ✅ **0 critical issues** | nmap + Wireshark |
| **TLS Handshake** | N/A | ✅ **100% success** | Test Cases 1-2 |
| **Cert Renewal** | N/A | ✅ **> 99% success** | Dry-run + production monitoring |
| **Client Compatibility** | N/A | ✅ **100% (VSCode, Git)** | Test Cases 6-7 |
| **Password Strength** | 32 characters | 32 characters | Unchanged |
| **Fail2ban Blocks** | 100% after 5 failures | 100% after 5 failures | Unchanged |
| **Migration Success** | N/A | ✅ **100% config regen** | vless-user regenerate |

---

## 11. Dependencies

### 11.1 External Dependencies (UPDATED)

| Dependency | Version | Purpose | NEW in v3.3 |
|------------|---------|---------|-------------|
| Docker | 20.10+ | Container runtime | - |
| Docker Compose | v2.0+ | Orchestration | - |
| UFW | System default | Firewall | - |
| jq | 1.5+ | JSON processing | - |
| qrencode | Latest | QR codes | - |
| fail2ban | 0.11+ | Brute-force protection | - |
| netcat | System default | Healthchecks | - |
| **certbot** | **2.0+** | **Let's Encrypt client** | **✅ YES** |
| **openssl** | **1.1.1+** | **TLS testing** | **✅ YES (testing)** |

### 11.2 Installation Order

1. OS detection
2. Docker + Docker Compose
3. UFW
4. fail2ban
5. **certbot** ← NEW
6. jq, qrencode, netcat
7. **openssl** (usually pre-installed)

---

## 12. Rollback Plan

**If v3.3 deployment fails:**

**Scenario 1: Certbot Failure**
```bash
# If Let's Encrypt rate limit hit or DNS issues
# Option A: Wait for rate limit reset (1 week)
# Option B: Use different (sub)domain
# Option C: Rollback to v3.2 (VULNERABLE - not recommended)

sudo vless-restore /tmp/vless_backup_<timestamp>/
```

**Scenario 2: TLS Configuration Issues**
```bash
# Check Xray logs for TLS errors
sudo docker logs vless-reality | grep -i tls

# Common issues:
# - Certificate path incorrect
# - Permissions on /etc/letsencrypt/
# - Volume mount missing

# Fix and restart
sudo docker-compose restart xray
```

**Scenario 3: Complete Rollback to v3.2**
```bash
# Restore v3.2 backup
sudo vless-restore /tmp/vless_backup_<timestamp>/

# Remove certbot
sudo systemctl stop certbot.timer
sudo apt remove -y certbot

# Remove cron job
sudo rm /etc/cron.d/certbot-vless-renew

# Remove deploy hook
sudo rm /usr/local/bin/vless-cert-renew

# ⚠️  WARNING: v3.2 has CRITICAL security vulnerability
# Only use for temporary rollback, migrate to v3.3 ASAP
```

---

## 13. Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | User | 2025-10-05 | Approved (v3.3 security fix) |
| Tech Lead | Claude | 2025-10-05 | PRD v3.3 Draft Complete |
| Security Review | Required | Pending | ⚠️ v3.2 = CRITICAL RISK |

---

## 14. References

### 14.1 Technical Documentation

- Xray TLS Configuration: https://xtls.github.io/config/transport.html#tlsobject
- Let's Encrypt ACME HTTP-01: https://letsencrypt.org/docs/challenge-types/
- Certbot User Guide: https://eff-certbot.readthedocs.io/
- SOCKS5 RFC 1928: https://www.rfc-editor.org/rfc/rfc1928
- TLS 1.3 RFC 8446: https://www.rfc-editor.org/rfc/rfc8446

### 14.2 Workflow Artifacts

- Phase 1: `/home/ikeniborn/Documents/Project/vless/workflow/phase1_technical_analysis.xml`
- Phase 2: `/home/ikeniborn/Documents/Project/vless/workflow/phase2_requirements_specification.xml`
- Phase 3: `/home/ikeniborn/Documents/Project/vless/workflow/phase3_unified_understanding.xml`
- User Responses: `/home/ikeniborn/Documents/Project/vless/workflow/phase1_user_responses.xml`

---

**END OF PRD v3.3**

**Next Steps:**
1. ✅ Review and approve PRD v3.3
2. Create detailed implementation plan (PLAN.md update)
3. Create migration guide (MIGRATION_v3.2_to_v3.3.md)
4. Create security assessment document
5. Begin implementation on `proxy-public` feature branch (merge with TLS changes)

---

**Version History:**
```
v3.3 - 2025-10-05: CRITICAL SECURITY FIX - Mandatory TLS encryption for public proxies
v3.2 - 2025-10-04: Public proxy support (SECURITY ISSUE: no encryption)
v3.1 - 2025-10-03: Dual proxy support (SOCKS5 + HTTP, localhost-only)
v3.0 - 2025-10-01: Base VLESS Reality VPN system
```

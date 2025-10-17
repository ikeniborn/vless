# PRD v4.1 - Functional Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 2. Functional Requirements

### FR-STUNNEL-001: stunnel TLS Termination (CRITICAL - NEW in v4.0)

**Requirement:** TLS termination MUST be handled by stunnel (separate container) instead of Xray streamSettings.

**Architecture:**
```
Client → stunnel (TLS 1.3, ports 1080/8118)
       → Xray (plaintext, localhost 10800/18118)
       → Internet
```

**Acceptance Criteria:**
- [ ] stunnel container runs and listens on 0.0.0.0:1080 and 0.0.0.0:8118
- [ ] Xray inbounds changed to localhost:10800 (SOCKS5) and localhost:18118 (HTTP)
- [ ] No TLS streamSettings in Xray config (plaintext inbounds only)
- [ ] stunnel uses Let's Encrypt certificates (same as v3.x)
- [ ] TLS 1.3 only (SSLv2/v3, TLSv1/1.1/1.2 disabled)
- [ ] Strong cipher suites: TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256
- [ ] Client connections work identically to v3.x (same URIs, same ports)
- [ ] stunnel logs separate from Xray logs
- [ ] Docker network handles stunnel ↔ Xray communication

**Technical Implementation:**

**stunnel.conf:**
```ini
[socks5-tls]
accept = 0.0.0.0:1080
connect = vless_xray:10800
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3
ciphersuites = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256

[http-tls]
accept = 0.0.0.0:8118
connect = vless_xray:18118
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3
```

**Xray config (SOCKS5 inbound):**
```json
{
  "tag": "socks5-plaintext",
  "listen": "127.0.0.1",
  "port": 10800,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [{"user": "username", "pass": "password"}],
    "udp": false
  }
  // IMPORTANT: NO streamSettings section - plaintext inbound
  // TLS termination handled by stunnel container on port 1080
  // Architecture: Client → stunnel:1080 (TLS) → Xray:10800 (plaintext) → Internet
}
```

**docker-compose.yml (NEW service):**
```yaml
stunnel:
  image: dweomer/stunnel:latest
  container_name: vless_stunnel
  ports:
    - "1080:1080"
    - "8118:8118"
  volumes:
    - ./config/stunnel.conf:/etc/stunnel/stunnel.conf:ro
    - ./certs:/certs:ro
    - ./logs/stunnel:/var/log/stunnel
  networks:
    - vless_reality_net
  restart: unless-stopped
  depends_on:
    - xray
```

**Benefits:**
1. Separation of concerns: stunnel = TLS, Xray = proxy logic
2. Mature TLS stack (stunnel has 20+ years production use)
3. Simpler Xray configuration (no TLS complexity)
4. Better debugging (separate logs)
5. Easier certificate management
6. Performance: stunnel optimized specifically for TLS termination

**User Story:** As a system administrator, I want TLS termination in a dedicated component so that Xray configuration is simpler and debugging is easier.

---

### FR-CONFIG-GENERATION: Configuration Generation Method (HISTORICAL)

**Status:** ❌ v4.0 Template-Based Approach DEPRECATED in v4.1

**Version History:**
- **v4.0 (deprecated)**: Template-based config generation with envsubst
- **v4.1 (current)**: Heredoc-based generation in lib/ modules (lib/stunnel_setup.sh, lib/orchestrator.sh)

**Current Implementation:** All configuration files (stunnel.conf, docker-compose.yml, xray_config.json) generated via heredoc in lib/*.sh modules.

**Migration:** Templates/ directory removed in v4.1. See [CLAUDE.md Section 7](../../CLAUDE.md#7-critical-system-parameters) for current implementation details.

---

**NOTE:** FR-TLS-001 (SOCKS5 TLS in Xray streamSettings) was **DEPRECATED in v4.0** and **REMOVED from PRD in v4.1**. TLS termination is now handled by stunnel (see FR-STUNNEL-001).

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

### FR-IP-001: Server-Level IP-Based Access Control (v3.6 - UPDATED)

**Requirement:** System MUST support server-level IP whitelisting for proxy access using Xray routing rules.

> **Breaking Change from v3.5:** Migrated from per-user to server-level due to protocol limitation - HTTP/SOCKS5 protocols don't provide user identifiers in Xray routing context. The `user` field only works for VLESS protocol.

**Acceptance Criteria:**
- [ ] `proxy_allowed_ips.json` created in `/opt/vless/config/` (default: `["127.0.0.1"]`)
- [ ] New installations default to localhost-only access
- [ ] IP validation supports IPv4, IPv6, and CIDR notation
- [ ] Xray routing rules generated dynamically (server-level)
- [ ] 5 CLI commands for server-level IP management implemented
- [ ] Changes applied via container reload (< 3 seconds)
- [ ] Routing matches: `source` (IP array) ONLY - no `user` field
- [ ] Unmatched connections routed to `blackhole` outbound
- [ ] README documentation includes migration guide from v3.5
- [ ] Migration script `migrate_proxy_ips.sh` included

**Technical Implementation:**

**proxy_allowed_ips.json Structure (NEW in v3.6):**
```json
{
  "allowed_ips": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "metadata": {
    "created": "2025-10-06T12:00:00Z",
    "last_modified": "2025-10-06T14:30:00Z",
    "description": "Server-level IP whitelist for proxy access (v3.6)"
  }
}
```

**Xray Routing Rules (auto-generated - server-level):**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks5-proxy", "http-proxy"],
        "source": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["socks5-proxy", "http-proxy"],
        "outboundTag": "blocked"
      }
    ]
  }
}
```

**Key Difference:** NO `user` field in routing rules - only `source` (IPs). This works for HTTP/SOCKS5 protocols.

**CLI Commands (v3.6 - server-level):**
```bash
vless show-proxy-ips                    # Display server-level whitelist
vless set-proxy-ips <ips>               # Set complete IP list (comma-separated)
vless add-proxy-ip <ip>                 # Add single IP (no duplicates)
vless remove-proxy-ip <ip>              # Remove IP (min 1 required)
vless reset-proxy-ips                   # Reset to 127.0.0.1
```

**IP Validation:**
- IPv4: `192.168.1.100` (octets 0-255)
- IPv4 CIDR: `10.0.0.0/24` (prefix 0-32)
- IPv6: `2001:db8::1`
- IPv6 CIDR: `2001:db8::/32` (prefix 0-128)

**Routing Evaluation (v3.6):**
1. User connects to SOCKS5/HTTP proxy with credentials
2. Xray checks source IP against server-level whitelist
3. If match → `direct` outbound (allowed)
4. If no match → `blackhole` outbound (blocked)
5. Catch-all rule blocks all other proxy connections

**Use Cases:**
1. **Fixed Network**: Restrict to office/home network ranges
2. **VPN-Only**: Allow only 10.0.0.0/8 (after VLESS connection)
3. **Multi-Location**: Whitelist multiple office locations (CIDR ranges)
4. **Private Deployment**: Localhost-only for local development
5. **Compliance**: Enforce IP-based access policies (organization-wide)

**Security Notes:**
- Server-level whitelist applies to ALL proxy users
- Individual user IP restrictions NOT supported (protocol limitation)
- Use separate VPN instances for different IP requirements
- IP whitelisting is NOT a password replacement
- Defense-in-depth: IP + password + fail2ban
- IPs can be spoofed in cloud environments
- Effective for fixed IPs (residential ISPs, data centers)

**Migration from v3.5 to v3.6:**

**Automatic Migration Script:**
```bash
sudo /opt/vless/scripts/migrate_proxy_ips.sh
```

Script performs:
1. Collects all unique IPs from `users.json` `allowed_ips` fields
2. Creates `proxy_allowed_ips.json` with collected IPs
3. Regenerates routing rules (server-level, no `user` field)
4. Reloads Xray container
5. Optionally removes `allowed_ips` field from users (cleanup)

**Breaking Changes:**
- ❌ Per-user commands removed: `show-allowed-ips`, `set-allowed-ips`, etc.
- ✅ Server-level commands added: `show-proxy-ips`, `set-proxy-ips`, etc.
- ❌ `allowed_ips` field in `users.json` deprecated
- ✅ New file: `/opt/vless/config/proxy_allowed_ips.json`

**User Story:** As a network administrator, I want to restrict proxy access to authorized IP ranges so that only connections from approved networks can use the proxy service, applying the same restrictions to all users.

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
# Configure Git to use SOCKS5 with TLS (RECOMMENDED)
git config --global http.proxy socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# Alternative: DNS resolution via proxy (NO TLS - use with caution)
git config --global http.proxy socks5h://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080
# ⚠️ WARNING: socks5h:// does NOT provide TLS encryption
# Only use if DNS privacy is required AND you trust the network path to proxy server
```

**SOCKS5 URI Schemes Explained:**

| Scheme | TLS Encryption | DNS Resolution | Use Case |
|--------|----------------|----------------|----------|
| `socks5://` | ❌ None | Local | ⛔ **DO NOT USE** (plaintext, insecure) |
| `socks5s://` | ✅ TLS 1.3 | Local | ✅ **RECOMMENDED** - Secure proxy with TLS (v4.0+) |
| `socks5h://` | ❌ None | Via Proxy | ⚠️ **Optional** - DNS privacy (NOT a TLS replacement!) |

**Key Points:**
- `socks5s://` = SOCKS5 with TLS (the "s" suffix means SSL/TLS)
- `socks5h://` = SOCKS5 with DNS resolution via proxy (the "h" suffix means hostname)
- **For v4.0+:** ALWAYS use `socks5s://` for TLS encryption (stunnel termination)
- `socks5h://` can be combined: `socks5sh://` for TLS + DNS via proxy (Git does NOT support this)
- **Security:** `socks5h://` alone provides NO encryption - only DNS privacy

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

### FR-FAIL2BAN-001: Fail2ban Integration (CRITICAL - ENHANCED in v3.3)

**Requirement:** Fail2ban MUST protect proxy ports from brute-force attacks in ALL proxy modes (localhost-only and public).

**Rationale:**
- **Localhost-only (127.0.0.1)**: Protects against brute-force attacks via VPN connection
- **Public (0.0.0.0)**: Protects against brute-force attacks from internet

**Acceptance Criteria:**
- [ ] Fail2ban installed when `ENABLE_PROXY=true` (regardless of public/localhost mode)
- [ ] Jail created for SOCKS5 (port 1080)
- [ ] Jail created for HTTP (port 8118)
- [ ] Ban after 5 failed auth attempts
- [ ] Ban duration: 1 hour (3600 seconds)
- [ ] Find time: 10 minutes (600 seconds)
- [ ] Logs monitored: `/opt/vless/logs/xray/error.log`
- [ ] Works for both localhost (via VPN) and public (from internet) attacks

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

### FR-REVERSE-PROXY-001: Site-Specific Reverse Proxy (NEW v4.2)

**Status:** 📝 DRAFT v3 (Security Hardened - 2025-10-17)
**Priority:** CRITICAL (Security fixes mandatory)
**Security Review:** ✅ APPROVED (with mandatory mitigations implemented)
**Dependencies:** FR-CERT-001, FR-CERT-002 (Let's Encrypt integration)

---

#### 1. Requirement Statement

**Requirement:** Система ДОЛЖНА поддерживать настройку reverse proxy для доступа к конкретному целевому сайту через отдельный домен с HTTP Basic Authentication и настраиваемым портом.

**Rationale:**
- Обход блокировок конкретных сайтов через reverse proxy
- Доступ к geo-restricted контенту (Netflix, YouTube и т.д.)
- Скрытие IP пользователя при доступе к одному сайту
- Простота использования: не требуется настройка VPN или proxy в браузере
- Поддержка нескольких reverse proxy доменов на одном сервере (до 10)

**Key Requirements:**
- ✅ Configurable port (default: 8443, range: 8443-8452)
- ✅ Multiple domains support (up to 10 per server)
- ✅ Error logging only (access log disabled for privacy)
- ✅ Mandatory fail2ban integration (5 failures → 1 hour ban)
- ✅ Security hardening (VULN-001/002/003/004/005 fixes implemented)
- ❌ WebSocket support explicitly NOT included (HTTP/HTTPS only)

---

#### 2. User Story

**As a** пользователь с заблокированным доступом к сайту
**I want** настроить reverse proxy на своем домене с возможностью выбора порта
**So that** я могу получить доступ к заблокированному сайту через свой домен без настройки VPN

**Example Workflow:**
```
1. Запускает: sudo vless-setup-proxy myproxy.example.com blocked-site.com
2. Вводит порт: 8443 (или custom: 9443)
3. Получает credentials: username / password
4. Открывает https://myproxy.example.com:8443 в браузере
5. Вводит credentials
6. Видит контент с blocked-site.com
```

**Architecture:** См. [04_architecture.md Section 4.6](04_architecture.md#46-reverse-proxy-architecture-v42)

---

#### 3. Acceptance Criteria

**AC-1: Interactive Configuration**
- [ ] DNS validation: `dig +short ${DOMAIN}` matches server IP
- [ ] Port configuration: default 8443 or user-specified
- [ ] Port availability check: `ss -tulnp | grep :${PORT}`
- [ ] Port conflict validation (against 443, 1080, 8118, existing reverse proxies)
- [ ] Target site validation: `curl -I https://${TARGET_SITE}`
- [ ] Email for Let's Encrypt

**AC-2: Automatic Certificate Acquisition**
- [ ] certbot obtains certificate for reverse proxy domain
- [ ] Port 80 temporarily opened for ACME challenge
- [ ] Certificates saved to `/etc/letsencrypt/live/${DOMAIN}/`
- [ ] Port 80 closed after successful acquisition

**AC-3: Credentials Generation**
- [ ] Username: `openssl rand -hex 4` (8 characters)
- [ ] Password: `openssl rand -hex 16` (32 characters)
- [ ] .htpasswd file: `htpasswd -bc .htpasswd-${DOMAIN} username password`
- [ ] Credentials saved to `/opt/vless/config/reverse_proxies.json`

**AC-4: Configuration Updates**
- [ ] Nginx config created with configurable port
- [ ] Xray config updated (new inbound + routing rules)
- [ ] docker-compose.yml updated (new port mapping via lib/docker_compose_manager.sh)
- [ ] fail2ban jail config created (multi-port support)
- [ ] UFW rule added: `ufw allow ${PORT}/tcp comment 'VLESS Reverse Proxy'`
- [ ] Config validation: `nginx -t`, `xray run -test -c config.json`

**AC-5: Service Restart**
- [ ] `docker compose up -d` applies changes
- [ ] Healthcheck: nginx and xray containers running
- [ ] Port listening: `ss -tulnp | grep ${PORT}`
- [ ] fail2ban jail active: `fail2ban-client status vless-reverseproxy`

**AC-6: Access Without Auth → 401 Unauthorized**
```bash
curl -I https://myproxy.example.com:8443
# Expected: HTTP/1.1 401 Unauthorized
```

**AC-7: Access With Valid Auth → 200 OK**
```bash
curl -I -u username:password https://myproxy.example.com:8443
# Expected: HTTP/1.1 200 OK (content from blocked-site.com)
```

**AC-8: Access With Invalid Auth → 401 Unauthorized**
```bash
curl -I -u wrong:credentials https://myproxy.example.com:8443
# Expected: HTTP/1.1 401 Unauthorized
```

**AC-9: Domain Restriction**
- User cannot access other sites via reverse proxy (blocked by Xray routing)

**AC-10: CLI - vless-proxy add**
```bash
# Default port
sudo vless-proxy add myproxy.example.com blocked-site.com
# Output: Domain: https://myproxy.example.com:8443

# Custom port
sudo vless-proxy add proxy2.example.com target2.com --port 9443
# Output: Domain: https://proxy2.example.com:9443
```

**AC-11: CLI - vless-proxy list**
```bash
sudo vless-proxy list
# Output: Lists all reverse proxies with ports and target sites
```

**AC-12: CLI - vless-proxy show <domain>**
```bash
sudo vless-proxy show myproxy.example.com
# Output: Shows credentials, certificate expiry, fail2ban status
```

**AC-13: CLI - vless-proxy remove <domain>**
```bash
sudo vless-proxy remove myproxy.example.com
# Output: Removes config, updates docker-compose.yml, deletes UFW rule
```

**AC-14: Port Configuration Validation**
- [ ] Default port works: 8443
- [ ] Custom port works: 9443
- [ ] Port conflict (system service) blocked: 443
- [ ] Port conflict (existing proxy) blocked: 8443
- [ ] Port already in use blocked: 22

**AC-15: Multiple Domains Support**
- [ ] Support up to 10 reverse proxy domains per server
- [ ] Sequential port allocation: 8443-8452
- [ ] Port reuse after domain removal
- [ ] 11th domain blocked with clear error

**AC-16: fail2ban Integration (MANDATORY)**
- [ ] fail2ban jail created for all reverse proxy ports
- [ ] 5 failed auth attempts trigger IP ban
- [ ] Ban duration: 1 hour
- [ ] UFW blocks banned IPs
- [ ] Auto-unban after timeout

**AC-17: Security Headers Validation**
- [ ] HSTS header present: `max-age=31536000`
- [ ] X-Frame-Options: DENY
- [ ] X-Content-Type-Options: nosniff
- [ ] X-XSS-Protection: 1; mode=block

---

#### 4. Security Requirements

**SEC-1: TLS 1.3 Only**
- [ ] Nginx: `ssl_protocols TLSv1.3;`
- [ ] Strong ciphers: `TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256`

**SEC-2: HTTP Basic Auth (MANDATORY)**
- [ ] Username: 8 characters (hex)
- [ ] Password: 32 characters (hex)
- [ ] bcrypt hashed in .htpasswd
- [ ] No plaintext password storage

**SEC-3: Domain Restriction**
- [ ] Xray routing: ONLY specified target domain allowed
- [ ] Catch-all rule: `outboundTag: block`
- [ ] No wildcard domains

**SEC-4: Rate Limiting**
- [ ] UFW: 10 connections/minute per IP per port
- [ ] Nginx: `limit_req_zone` 10 requests/second, burst 20
- [ ] Connection limit: 5 concurrent per IP

**SEC-5: Host Header Validation (VULN-001 FIX - CRITICAL)**
- [ ] Explicit Host validation: `if ($host != "domain") { return 444; }`
- [ ] Default server block catches invalid Host headers
- [ ] Hardcoded `proxy_set_header Host` (NOT $host)

**SEC-6: HSTS Header (VULN-002 FIX - HIGH)**
- [ ] HSTS: `max-age=31536000; includeSubDomains; preload`
- [ ] Additional security headers (X-Frame-Options, X-Content-Type-Options, etc.)

**SEC-7: DoS Protection (VULN-003/004/005 FIX - MEDIUM)**
- [ ] Connection limit: 5 concurrent per IP
- [ ] Request rate limit: 10 req/s per IP
- [ ] Max request body size: 10 MB
- [ ] Timeouts: 10s (prevent slowloris)

**SEC-8: Error Logging ONLY**
- [ ] Access log: DISABLED (privacy requirement)
- [ ] Error log: ENABLED (for fail2ban + debugging)
- [ ] Log level: warn (auth failures, connection errors)
- [ ] Log rotation: 7 days retention

**SEC-9: fail2ban Integration (MANDATORY)**
```ini
# /etc/fail2ban/jail.d/vless-reverseproxy.conf
[vless-reverseproxy]
enabled = true
port = 8443,8444,8445,8446,8447,8448,8449,8450,8451,8452
filter = vless-reverseproxy
logpath = /opt/vless/logs/nginx/reverse-proxy-error.log
maxretry = 5
bantime = 3600
findtime = 600
action = ufw
```

---

#### 5. File Structure

```
/opt/vless/
├── config/
│   ├── xray_config.json               # Updated: +multiple reverse-proxy inbounds
│   ├── reverse_proxies.json           # NEW: Credentials + port info
│   └── reverse-proxy/                 # NEW: Nginx reverse proxy configs
│       ├── proxy1.example.com.conf    # Per-domain config (heredoc-generated)
│       ├── proxy2.example.com.conf
│       ├── .htpasswd-proxy1           # Per-domain Basic Auth (bcrypt hashed)
│       └── .htpasswd-proxy2
│
├── logs/
│   └── nginx/
│       └── reverse-proxy-error.log    # NEW: Error log ONLY (no access log)
│
└── lib/                               # NEW: Reverse proxy modules
    ├── nginx_config_generator.sh      # Generates Nginx configs via heredoc
    ├── reverseproxy_db.sh             # Manages reverse_proxies.json
    └── letsencrypt_integration.sh     # Extends FR-CERT-001/002

/etc/fail2ban/                          # NEW: fail2ban configs
├── jail.d/
│   └── vless-reverseproxy.conf        # Multi-port jail
└── filter.d/
    └── vless-reverseproxy.conf        # Nginx auth failure filter

/usr/local/bin/
├── vless-setup-proxy → /opt/vless/cli/vless-setup-proxy
└── vless-proxy → /opt/vless/cli/vless-proxy
```

---

#### 6. Configuration File Formats

**reverse_proxies.json:**
```json
{
  "version": "1.0",
  "reverse_proxies": [
    {
      "domain": "myproxy.example.com",
      "target_site": "blocked-site.com",
      "port": 9443,
      "xray_inbound_port": 10080,
      "username": "a3f9c2e1",
      "password_hash": "$2y$10$...",
      "created_at": "2025-10-16T21:00:00Z",
      "certificate": "/etc/letsencrypt/live/myproxy.example.com/",
      "certificate_expires": "2026-01-14T21:00:00Z",
      "last_renewed": "2025-10-16T21:00:00Z",
      "enabled": true
    }
  ]
}
```

---

#### 7. Implementation Scope

**In Scope (v4.2):**
- ✅ CLI tools: `vless-setup-proxy`, `vless-proxy` (add/list/show/remove)
- ✅ Nginx config generation via heredoc (lib/nginx_config_generator.sh)
- ✅ Xray HTTP inbound management (lib/xray_http_inbound.sh)
- ✅ Let's Encrypt integration (extends FR-CERT-001/002)
- ✅ fail2ban multi-port support
- ✅ UFW firewall rules (per domain)
- ✅ Sequential port allocation (8443-8452)
- ✅ Dynamic docker-compose.yml updates (lib/docker_compose_manager.sh)
- ✅ Security hardening (VULN-001/002/003/004/005 fixes)

**Out of Scope:**
- ❌ WebSocket proxying (HTTP/HTTPS only)
- ❌ GRPC proxying
- ❌ Multiple target sites per domain (load balancing)
- ❌ Custom authentication (OAuth, LDAP) - only Basic Auth
- ❌ CDN integration (Cloudflare, etc.)
- ❌ Content caching (reverse proxy is transparent)
- ❌ Access logging (privacy requirement - only error log)

---

#### 8. Comparison with Existing Proxy

| Feature | Existing Proxy (SOCKS5/HTTP) | Reverse Proxy (NEW) |
|---------|------------------------------|---------------------|
| Client | Desktop apps (VSCode, Git, Docker) | Web Browser |
| Protocol | SOCKS5s, HTTPS proxy | HTTPS reverse proxy |
| Authentication | Password (32-char) | HTTP Basic Auth (bcrypt) |
| Target Site | Any (user choice) | Specific (admin choice) |
| Use Case | Proxy for all applications | Access to 1 blocked site |
| Port Range | 1080, 8118 (fixed) | 8443-8452 (configurable) |

---

#### 9. Success Metrics

**Functional:**
- [ ] 100% acceptance criteria passed (17 AC total)
- [ ] All security tests passed (TLS, auth, domain restriction, fail2ban)

**Performance:**
- [ ] Latency < 50ms overhead per domain
- [ ] 1000 concurrent connections per domain
- [ ] 1 Gbps aggregate throughput (10 domains × 100 Mbps)

**Usability:**
- [ ] Setup time < 5 minutes per domain
- [ ] Zero manual configuration after script run
- [ ] Port configuration: < 30 seconds per domain

**Security:**
- [ ] fail2ban ban rate: 99% (5 failed attempts → ban)
- [ ] No access log leaks (privacy validated)
- [ ] Error log contains auth failures only
- [ ] All VULN-001/002/003/004/005 fixes validated

---

**User Story:**
- Как системный администратор, я хочу предоставить доступ к заблокированным сайтам через свой домен
- Чтобы пользователи могли обходить блокировки без VPN клиента
- С защитой через HTTP Basic Auth и fail2ban

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

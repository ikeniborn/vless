# Product Requirements Document (PRD) v4.1

**Project:** VLESS + Reality VPN Server with Secure Public Proxy & IP Access Control
**Version:** 4.1
**Date:** 2025-10-07
**Status:** Implemented
**Previous Version:** 4.0 (stunnel TLS termination + template-based configuration)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 4.1 | 2025-10-07 | System | **Heredoc migration + Proxy URI fix**: Remove templates/, heredoc config generation, fix proxy URI schemes (https://, socks5s://) |
| 4.0 | 2025-10-06 | System | **stunnel integration**: TLS termination via stunnel + template-based configuration |
| 3.6 | 2025-10-06 | System | **Server-level IP whitelist**: Migration from per-user to server-level proxy access control |
| 3.5 | 2025-10-06 | System | **IP-based access control**: Per-user IP whitelisting for proxy servers |
| 3.4 | 2025-10-05 | System | **Optional TLS**: Made TLS encryption optional (plaintext mode for dev/testing) |
| 3.3 | 2025-10-05 | System | **CRITICAL SECURITY FIX:** Mandatory TLS encryption for public proxies via Let's Encrypt |
| 3.2 | 2025-10-04 | System | Public proxy support (SECURITY ISSUE: no encryption) |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Implementation Status (v4.1)

| Feature | PRD Section | Status | Notes |
|---------|-------------|--------|-------|
| stunnel TLS termination | FR-STUNNEL-001 | ✅ COMPLETE | stunnel container + heredoc config (v4.0/v4.1) |
| Config generation (heredoc) | - | ✅ COMPLETE | lib/stunnel_setup.sh, no templates/ (v4.1) |
| Proxy URI schemes fix | FR-CONFIG-001 | ✅ COMPLETE | https://, socks5s:// (v4.1 bugfix) |
| Docker Compose stunnel service | Section 4.5 | ✅ COMPLETE | vless_stunnel container (v4.0) |
| IP whitelisting (server-level) | FR-IP-001 | ✅ COMPLETE | proxy_allowed_ips.json + optional UFW (v4.0) |
| Xray plaintext inbounds | FR-STUNNEL-001 | ✅ COMPLETE | localhost:10800/18118 (v4.0) |
| 6 proxy config files | FR-CONFIG-001 | ✅ COMPLETE | All formats with correct URIs (v4.1) |
| Template-based configs | FR-TEMPLATE-001 | ❌ DEPRECATED | Replaced by heredoc in v4.1 |

**Overall Status:** v4.1 is **100% implemented** (all active features complete, templates deprecated).

---

## Executive Summary

### Current Version: v4.1 (Implemented)

**Latest Updates:**
- ✅ **v4.1 (2025-10-07)**: Heredoc config generation + Proxy URI fix (https://, socks5s://)
- ✅ **v4.0 (2025-10-06)**: stunnel TLS termination architecture
- ✅ **v3.6 (2025-10-06)**: Server-level IP whitelist (migration from v3.5 per-user)
- ✅ **v3.5 (2025-10-06)**: Per-user IP-based access control for proxy servers
- ✅ **v3.4 (2025-10-05)**: Optional TLS encryption (plaintext mode for dev/testing)
- ✅ **v3.3 (2025-10-05)**: Mandatory TLS encryption for public proxies

**System Capabilities:**
- **VLESS Reality VPN:** DPI-resistant VPN tunnel
- **Dual Proxy Modes:** SOCKS5 (1080) + HTTP (8118)
- **TLS Termination:** stunnel handles TLS 1.3 encryption (v4.0+)
- **Heredoc Config Generation:** All configs via heredoc (v4.1, simplified from v4.0 templates)
- **Correct Proxy URIs:** https:// and socks5s:// for TLS connections (v4.1 fix)
- **IP Whitelisting:** Server-level + optional UFW firewall rules (v4.0+)
- **Multi-Format Configs:** 6 auto-generated config files per user

---

### What's New in v4.1

**PRIMARY FEATURE:** Heredoc config generation + Proxy URI scheme fix.

**Key Changes:**

| Component | v4.0 | v4.1 | Status |
|-----------|------|------|--------|
| **Config Generation** | templates/ + envsubst | heredoc in lib/*.sh | ✅ IMPLEMENTED |
| **stunnel.conf** | templates/stunnel.conf.template | heredoc in lib/stunnel_setup.sh | ✅ IMPLEMENTED |
| **Proxy URI Schemes** | http://, socks5:// | https://, socks5s:// | ✅ IMPLEMENTED (BUGFIX) |
| **Dependencies** | bash, envsubst | bash only | ✅ SIMPLIFIED |

**Benefits:**
- **Unified codebase**: All configs (Xray, stunnel, docker-compose) use heredoc
- **Simpler dependencies**: Removed envsubst (GNU gettext) requirement
- **Correct proxy URIs**: https:// and socks5s:// for TLS connections
- **Fewer files**: 1 file instead of 2 (template + script)

---

### What's New in v4.0

**PRIMARY FEATURE:** stunnel-based TLS termination architecture.

**Key Architectural Changes:**

| Component | v3.x | v4.0 | Status |
|-----------|------|------|--------|
| **TLS Handling** | Xray streamSettings | stunnel (separate container) | ✅ IMPLEMENTED |
| **Proxy Ports** | 1080/8118 (TLS in Xray) | 1080/8118 (stunnel) → 10800/18118 (Xray plaintext) | ✅ IMPLEMENTED |
| **Configuration** | Inline heredocs in scripts | Template files (v4.0), heredoc (v4.1) | ✅ IMPLEMENTED (v4.1) |
| **IP Whitelisting** | Xray routing only | Xray routing + optional UFW | ✅ IMPLEMENTED |

**New CLI Commands (4):**
```bash
vless add-ufw-ip <ip>             # Add IP to UFW whitelist for proxy ports
vless remove-ufw-ip <ip>          # Remove IP from UFW whitelist
vless show-ufw-ips                # Display UFW proxy rules
vless reset-ufw-ips               # Remove all UFW proxy rules
```

**Architecture Overview:**
```
Client → stunnel (TLS termination, ports 1080/8118)
       → Xray (plaintext proxy, localhost 10800/18118)
       → Internet
```

**Technical Implementation (v4.0/v4.1):**
- **v4.1:** `lib/stunnel_setup.sh` - stunnel config generation via heredoc (removed templates/)
- **v4.1:** `lib/user_management.sh` - proxy URI fix (https://, socks5s://)
- **v4.0:** stunnel container - TLS 1.3 termination for proxy ports
- **v4.0:** `lib/ufw_whitelist.sh` - UFW-based IP whitelisting
- **v4.0:** `lib/orchestrator.sh` - removed TLS from Xray inbounds, added stunnel service

**Benefits:**
1. **Mature TLS Stack:** stunnel has 20+ years of production stability
2. **Simpler Xray Config:** No TLS complexity in Xray, focus on proxy logic
3. **Better Debugging:** Separate logs for TLS (stunnel) vs proxy (Xray)
4. **Template-Based:** All configs generated from templates, easier to version and review
5. **Optional UFW:** Host-level firewall rules for additional security layer
6. **Defense-in-Depth:** Multiple security layers (stunnel TLS + Xray auth + UFW + fail2ban)

**Migration from v3.x:**
- Existing installations will be migrated automatically during update
- Client configs remain compatible (same ports, same URIs)
- Zero downtime migration (rolling restart)
- Backward compatibility maintained

---

### Version History Summary

**For detailed migration guides and breaking changes, see:** [CHANGELOG.md](../CHANGELOG.md)

| Version | Date | Key Feature | Status | Notes |
|---------|------|-------------|--------|-------|
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix | ✅ **CURRENT** | https://, socks5s://, removed templates/ |
| **v4.0** | 2025-10-06 | stunnel TLS termination architecture | ✅ Implemented | Separate TLS layer, plaintext Xray inbounds |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | ⚠️ Superseded | Migration from v3.5 per-user to server-level |
| **v3.5** | 2025-10-06 | Per-user IP-based access control | ⚠️ Superseded | Xray routing rules, deprecated in v3.6 |
| **v3.4** | 2025-10-05 | Optional TLS encryption | ⚠️ Superseded | Plaintext mode for dev/testing |
| **v3.3** | 2025-10-05 | Mandatory TLS for public proxies | ⚠️ Superseded | Let's Encrypt integration, certbot |
| **v3.2** | 2025-10-04 | Public proxy support (no encryption) | ❌ Deprecated | SECURITY ISSUE - plaintext credentials |
| **v3.1** | 2025-10-03 | Dual proxy (SOCKS5 + HTTP, localhost) | ⚠️ Superseded | Localhost-only binding, VPN required |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | ⚠️ Superseded | No proxy support |

**Current Production Architecture (v4.1):**
- **VLESS Reality VPN:** DPI-resistant tunnel (port 443)
- **stunnel TLS Termination:** Handles TLS 1.3 for proxy ports (1080, 8118)
- **Dual Proxy:** SOCKS5 + HTTP with unified credentials
- **IP Whitelisting:** Server-level Xray routing + optional UFW firewall
- **Config Generation:** Heredoc-based (all configs inline in lib/*.sh)
- **Client Configs:** 6 formats with correct TLS URI schemes

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + **Secure** Proxy server deployable in < 7 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing
- **Secure SOCKS5 Proxy:** TLS-encrypted proxy on port 1080 (v4.0+ stunnel termination)
- **Secure HTTP Proxy:** HTTPS proxy on port 8118 (v4.0+ stunnel termination)
- **Hybrid Mode:** VPN for some devices, encrypted proxy for others
- **Zero Trust Network:** No plaintext proxy access, TLS mandatory

### 1.2 Target Users

- **Primary:** System administrators deploying secure VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** Encrypted proxy for desktop applications (VSCode, Git, Docker)
- **Use Case 3:** Mixed deployment (VPN + Encrypted Proxy simultaneously)
- **Use Case 4:** Development teams requiring secure proxy for CI/CD pipelines

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

**Migration:** Templates/ directory removed in v4.1. See [CLAUDE.md Section 7](CLAUDE.md#7-critical-system-parameters) for current implementation details.

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

### 4.4 File Structure (v4.1)

```
/opt/vless/
├── config/
│   ├── xray_config.json        # 3 inbounds: VLESS + plaintext SOCKS5/HTTP ←MODIFIED v4.0
│   │                           # SOCKS5/HTTP: NO streamSettings (plaintext inbounds)
│   │                           # TLS handled by stunnel (see stunnel.conf)
│   ├── stunnel.conf            # stunnel TLS termination config ←NEW v4.0
│   │                           # Generated via heredoc (no templates/) ←MODIFIED v4.1
│   └── users.json              # v1.1 with proxy_password (32 chars)
│
├── data/clients/<user>/
│   ├── vless_config.json       # VLESS config (unchanged)
│   ├── socks5_config.txt       # socks5s://user:pass@server:1080 ←MODIFIED v4.1 (BUGFIX)
│   ├── http_config.txt         # https://user:pass@server:8118 ←MODIFIED v4.1 (BUGFIX)
│   ├── vscode_settings.json    # Uses HTTPS proxy ←MODIFIED v3.3
│   ├── docker_daemon.json      # Uses HTTPS proxy ←MODIFIED v3.3
│   └── bash_exports.sh         # Uses HTTPS proxy ←MODIFIED v3.3
│
├── logs/
│   ├── xray/
│   │   ├── access.log          # NOT logged (privacy)
│   │   └── error.log           # Monitored by fail2ban
│   ├── stunnel/                # stunnel logs ←NEW v4.0
│   │   └── stunnel.log         # TLS termination logs
│   └── certbot-renew.log       # Renewal logs ←NEW v3.3
│
└── scripts/
    └── vless-cert-renew        # Deploy hook script ←NEW v3.3

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

### 4.5 Docker Compose Configuration (v4.1)

**MAJOR UPDATE v4.0:** Added stunnel service for TLS termination
**UPDATE v4.1:** Xray uses plaintext inbounds (stunnel handles TLS)

```yaml
version: '3.8'

services:
  stunnel:
    image: dweomer/stunnel:latest
    container_name: vless_stunnel
    restart: unless-stopped
    ports:
      - "1080:1080"   # SOCKS5 with TLS
      - "8118:8118"   # HTTP with TLS
    volumes:
      - /opt/vless/config/stunnel.conf:/etc/stunnel/stunnel.conf:ro
      - /etc/letsencrypt:/certs:ro  # Let's Encrypt certificates
      - /opt/vless/logs/stunnel:/var/log/stunnel
    networks:
      - vless_reality_net
    depends_on:
      - xray

  xray:
    image: teddysun/xray:24.11.30
    container_name: vless_xray
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "${VLESS_PORT}:${VLESS_PORT}"  # VLESS Reality port (default: 443)
    volumes:
      - /opt/vless/config:/etc/xray:ro
      # NOTE: Certificates mounted to stunnel, NOT Xray (v4.0 architecture change)
    environment:
      - TZ=UTC
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "10800"]  # Plaintext SOCKS5 port
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  nginx:
    image: nginx:alpine
    container_name: vless_fake_site
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

**Key Changes (v4.0/v4.1):**
- ✅ **NEW:** stunnel service for TLS termination (ports 1080/8118)
- ✅ **MODIFIED:** Xray uses Docker network (not host mode)
- ✅ **MODIFIED:** Xray inbounds are plaintext (localhost 10800/18118)
- ✅ **MODIFIED:** Certificates mounted to stunnel container
- ✅ **REMOVED:** Xray `/etc/letsencrypt` mount (stunnel handles TLS)
- ✅ **Architecture:** Client → stunnel (TLS) → Xray (plaintext) → Internet

---

## 5. Implementation Details & Migration History

**For implementation specifics and historical migration guides, see:**
- **[CHANGELOG.md](../CHANGELOG.md)** - Detailed version history, breaking changes, migration guides
- **[CLAUDE.md Section 8](CLAUDE.md#8-project-structure)** - Current implementation architecture (v4.1)

**Current v4.1 Implementation Summary:**
- **Config Generation:** Heredoc-based (lib/stunnel_setup.sh, lib/orchestrator.sh, lib/user_management.sh)
- **TLS Termination:** stunnel container (separate from Xray)
- **Proxy Ports:** stunnel:1080/8118 (TLS) → Xray:10800/18118 (plaintext)
- **IP Whitelisting:** server-level via proxy_allowed_ips.json + Xray routing + optional UFW
- **Client Configs:** 6 formats auto-generated with correct URI schemes (https://, socks5s://)

---

## 6. Security Risk Assessment

**For detailed security analysis, threat modeling, and mitigation strategies, see:**
- **[CLAUDE.md Section 15](CLAUDE.md#15-security--debug)** - Security Threat Matrix, Best Practices, Debug Commands
- **[CHANGELOG.md](../CHANGELOG.md)** - Historical security improvements (v3.2 → v3.3 TLS migration)

**Current v4.1 Security Posture:**
- ✅ **TLS 1.3 Encryption:** stunnel termination for all proxy connections (v4.0+)
- ✅ **Let's Encrypt Certificates:** Automated certificate management with auto-renewal
- ✅ **32-Character Passwords:** Brute-force resistant credentials
- ✅ **fail2ban Protection:** Automated IP banning after 5 failed attempts
- ✅ **UFW Rate Limiting:** 10 connections/minute per IP on proxy ports
- ✅ **DPI Resistance:** Reality protocol makes VPN traffic indistinguishable from HTTPS

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

## 8. Acceptance Criteria

**For historical v3.x acceptance criteria and migration checklists, see:**
- **[CHANGELOG.md](../CHANGELOG.md)** - Phase-by-phase acceptance criteria for v3.2 → v3.3, v3.5 → v3.6, v4.0, v4.1 releases

**v4.1 Implementation Status:** All features ✅ **COMPLETE** (see Implementation Status table at document top)

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

**For detailed performance targets, test results, and success criteria, see:**
- **[CLAUDE.md Section 16](CLAUDE.md#16-success-metrics)** - Current v4.1 success metrics, performance targets, overall success formula

---

## 11. Dependencies

**For complete dependency list with versions and installation requirements, see:**
- **[CLAUDE.md Section 7](CLAUDE.md#7-critical-system-parameters)** - Technology Stack (Docker, Xray, stunnel), Shell & Tools, Security Testing Tools

---

## 12. Rollback & Troubleshooting

**For rollback procedures, troubleshooting guides, and common failure points, see:**
- **[CLAUDE.md Section 11](CLAUDE.md#11-common-failure-points--solutions)** - Issue detection, solutions, debug workflows
- **[CHANGELOG.md](../CHANGELOG.md)** - Historical rollback scenarios (v3.2 → v3.3, v3.5 → v3.6)

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

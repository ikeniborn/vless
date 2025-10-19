# PRD v4.3 - Functional Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 2. Functional Requirements

### FR-HAPROXY-001: HAProxy Unified Architecture (CRITICAL - NEW in v4.3)

**Requirement:** ALL TLS termination and routing MUST be handled by a single HAProxy container (replaces stunnel from v4.0-v4.2).

**Architecture:**
```
Port 443 (HAProxy Frontend - SNI Routing, NO TLS termination for Reality):
  → VLESS Reality: SNI passthrough → Xray:8443 (Reality TLS)
  → Reverse Proxies: SNI routing → Nginx:9443-9452 (HTTPS)

Port 1080 (HAProxy Frontend - SOCKS5 TLS Termination):
  → Xray:10800 (plaintext SOCKS5)

Port 8118 (HAProxy Frontend - HTTP TLS Termination):
  → Xray:18118 (plaintext HTTP)
```

**Acceptance Criteria:**
- [ ] HAProxy container runs and listens on 0.0.0.0:443, 0.0.0.0:1080, 0.0.0.0:8118
- [ ] Frontend 443: SNI routing (mode tcp, req.ssl_sni inspection)
- [ ] Frontend 1080: TLS termination (bind ssl crt combined.pem) → Xray:10800
- [ ] Frontend 8118: TLS termination (bind ssl crt combined.pem) → Xray:18118
- [ ] Xray inbounds remain plaintext (localhost:10800/18118, no TLS streamSettings)
- [ ] HAProxy uses combined.pem certificates (fullchain + privkey concatenated)
- [ ] TLS 1.3 only (for frontends 1080/8118)
- [ ] Strong cipher suites: TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256
- [ ] Client connections work identically to v4.0-v4.2 (same URIs, same ports)
- [ ] HAProxy logs unified (single log stream for all frontends)
- [ ] Docker network handles HAProxy ↔ Xray/Nginx communication
- [ ] Graceful reload: `haproxy -sf $(cat /var/run/haproxy.pid)` (zero downtime)
- [ ] Dynamic ACL management: add/remove reverse proxy routes without full restart
- [ ] stunnel container completely removed from docker-compose.yml

**Technical Implementation:**

**haproxy.cfg (3 Frontends):**
```haproxy
# Frontend 1: SNI Routing (port 443)
frontend vless-reality
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # === DYNAMIC_REVERSE_PROXY_ROUTES ===
    # ACLs and use_backend directives added dynamically by lib/haproxy_config_manager.sh
    # Example:
    #   acl is_claude req.ssl_sni -i claude.ikeniborn.ru
    #   use_backend nginx_claude if is_claude

    default_backend xray_reality

# Frontend 2: SOCKS5 TLS Termination (port 1080)
frontend socks5-tls
    bind *:1080 ssl crt /opt/vless/certs/combined.pem
    mode tcp
    default_backend xray_socks5

# Frontend 3: HTTP Proxy TLS Termination (port 8118)
frontend http-tls
    bind *:8118 ssl crt /opt/vless/certs/combined.pem
    mode tcp
    default_backend xray_http

# Backends
backend xray_reality
    mode tcp
    server xray vless_xray:8443

backend xray_socks5
    mode tcp
    server xray vless_xray:10800

backend xray_http
    mode tcp
    server xray vless_xray:18118

# Dynamic backends (added via add_reverse_proxy_route())
# Example:
# backend nginx_claude
#     mode tcp
#     server nginx vless_reverse_proxy_nginx:9443

# Stats page
frontend stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
```

**Xray config (SOCKS5 inbound - NO CHANGES from v4.0):**
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
  // TLS termination handled by HAProxy container on port 1080 (v4.3)
  // Architecture: Client → HAProxy:1080 (TLS) → Xray:10800 (plaintext) → Internet
}
```

**docker-compose.yml (NEW service - replaces stunnel):**
```yaml
haproxy:
  image: haproxy:latest
  container_name: vless_haproxy
  ports:
    - "443:443"   # VLESS Reality + Reverse Proxy (SNI routing)
    - "1080:1080" # SOCKS5 with TLS
    - "8118:8118" # HTTP with TLS
    - "127.0.0.1:9000:9000"  # Stats page (localhost only)
  volumes:
    - ./config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    - ./certs:/opt/vless/certs:ro  # combined.pem certificates
    - ./logs/haproxy:/var/log/haproxy
  networks:
    - vless_reality_net
  restart: unless-stopped
  depends_on:
    - xray
    - nginx
```

**Benefits (vs v4.0-v4.2 stunnel architecture):**
1. Single container (HAProxy) instead of 2 (stunnel + HAProxy)
2. Unified logging (all TLS/routing in one log stream)
3. Better performance (HAProxy is industry-standard load balancer)
4. SNI routing security (NO TLS decryption for reverse proxy)
5. Simpler deployment (1 service to manage)
6. Graceful reload (zero downtime for config changes)
7. Dynamic ACL management (add/remove routes without restart)
8. Subdomain-based reverse proxy (https://domain, NO port!)

**User Story:** As a system administrator, I want a unified TLS and routing layer so that I have simpler architecture, better performance, and easier management compared to the dual stunnel+HAProxy setup.

---

### FR-CONFIG-GENERATION: Configuration Generation Method (HISTORICAL)

**Status:** ❌ v4.0 Template-Based Approach DEPRECATED in v4.1

**Version History:**
- **v4.0 (deprecated)**: Template-based config generation with envsubst
- **v4.1-v4.2 (deprecated)**: Heredoc-based generation in lib/stunnel_setup.sh
- **v4.3 (current)**: Heredoc-based generation in lib/haproxy_config_manager.sh

**Current Implementation:** All configuration files (haproxy.cfg, docker-compose.yml, xray_config.json) generated via heredoc in lib/*.sh modules.

**Migration:** Templates/ directory removed in v4.1. stunnel_setup.sh replaced by haproxy_config_manager.sh in v4.3. See [CLAUDE.md Section 7](../../CLAUDE.md#7-critical-system-parameters) for current implementation details.

---

**NOTE:**
- FR-STUNNEL-001 (stunnel TLS termination) was **INTRODUCED in v4.0** and **DEPRECATED in v4.3** (replaced by FR-HAPROXY-001).
- FR-TLS-001 (SOCKS5 TLS in Xray streamSettings) was **DEPRECATED in v4.0** and **REMOVED from PRD in v4.1**. TLS termination is now handled by HAProxy (see FR-HAPROXY-001).

---

### FR-TLS-002: TLS Encryption для HTTP Inbound (CRITICAL - v4.3 UPDATED)

**Requirement:** HTTP proxy MUST use HTTPS (TLS 1.3) with Let's Encrypt certificates via HAProxy termination.

**Acceptance Criteria:**
- [ ] HAProxy frontend 8118 performs TLS termination (bind ssl crt combined.pem)
- [ ] HTTPS handshake successful: `curl -I --proxy https://user:pass@server:8118 https://google.com`
- [ ] Certificate verified: Let's Encrypt CA trusted
- [ ] No fallback to plain HTTP (enforced by config validation)
- [ ] VSCode can use HTTPS proxy URL without SSL warnings
- [ ] Wireshark capture shows TLS 1.3 encrypted stream (no plaintext HTTP)
- [ ] Xray HTTP inbound is plaintext (no TLS streamSettings) - HAProxy handles TLS

**Technical Implementation (v4.3):**
```json
{
  "inbounds": [
    {
      "tag": "http-plaintext",
      "listen": "127.0.0.1",
      "port": 18118,
      "protocol": "http",
      "settings": {
        "accounts": [],
        "allowTransparent": false
      }
      // NOTE: NO streamSettings - plaintext inbound
      // TLS handled by HAProxy frontend 8118
    }
  ]
}
```

**HAProxy Configuration (v4.3):**
```haproxy
frontend http-tls
    bind *:8118 ssl crt /opt/vless/certs/combined.pem
    mode tcp
    default_backend xray_http

backend xray_http
    mode tcp
    server xray vless_xray:18118
```

**User Story:** As a developer, I want to configure VSCode with HTTPS proxy so that extensions and updates are downloaded securely without SSL warnings.

---

### FR-CERT-001: Автоматическое получение Let's Encrypt сертификатов (CRITICAL - v4.3 UPDATED)

**Requirement:** Installation script MUST automatically obtain Let's Encrypt certificates via certbot and generate combined.pem for HAProxy.

**Acceptance Criteria:**
- [ ] `install.sh` integrates certbot installation (apt install certbot)
- [ ] DNS validation check: `dig +short ${DOMAIN}` matches server IP
- [ ] UFW temporarily opens port 80 for ACME HTTP-01 challenge
- [ ] Certbot runs: `certbot certonly --standalone --non-interactive --agree-tos --email ${EMAIL} --domain ${DOMAIN}`
- [ ] Certificates saved to `/etc/letsencrypt/live/${DOMAIN}/`
- [ ] **NEW v4.3:** combined.pem generated: `cat fullchain.pem privkey.pem > /opt/vless/certs/combined.pem`
- [ ] **NEW v4.3:** combined.pem permissions: 600 (HAProxy requires this)
- [ ] UFW closes port 80 after certbot completes
- [ ] Docker volume mount added: `/opt/vless/certs:/opt/vless/certs:ro` (HAProxy container)
- [ ] HAProxy container can read combined.pem (verified on startup)
- [ ] Clear error messages on failure (DNS, port 80 occupied, rate limit)

**Installation Flow (v4.3 UPDATED):**
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
  ✓ Generating combined.pem for HAProxy...
     - combined.pem: /opt/vless/certs/combined.pem (600 perms)
  ✓ Closing UFW port 80/tcp...
  ✓ Mounting certificates to HAProxy container...
  ✓ TLS certificates ready
```

**User Story:** As a system administrator, I want certbot to automatically obtain certificates during installation and generate combined.pem so that I don't need to manually configure TLS for HAProxy.

---

### FR-IP-001: Server-Level IP-Based Access Control (v3.6 - UNCHANGED in v4.3)

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

### FR-CERT-002: Автоматическое обновление Let's Encrypt сертификатов (CRITICAL - v4.3 UPDATED)

**Requirement:** Certbot MUST automatically renew certificates every 60-80 days with zero downtime and regenerate combined.pem for HAProxy.

**Acceptance Criteria:**
- [ ] Cron job created: `/etc/cron.d/certbot-vless-renew`
- [ ] Schedule: `0 0,12 * * *` (runs twice daily)
- [ ] Command: `certbot renew --quiet --deploy-hook "/usr/local/bin/vless-cert-renew"`
- [ ] **NEW v4.3:** Deploy hook script regenerates combined.pem
- [ ] **NEW v4.3:** HAProxy graceful reload: `haproxy -sf $(cat /var/run/haproxy.pid)`
- [ ] Dry-run test passes: `certbot renew --dry-run`
- [ ] HAProxy downtime during renewal < 5 seconds (graceful reload)
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

**Deploy Hook Script (v4.3 UPDATED):**
```bash
#!/bin/bash
# /usr/local/bin/vless-cert-renew

echo "$(date): Certificate renewed, regenerating combined.pem..."

# Regenerate combined.pem for HAProxy
DOMAIN=$(cat /opt/vless/config/.env | grep DOMAIN | cut -d= -f2)
cat /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
    /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
    > /opt/vless/certs/combined.pem
chmod 600 /opt/vless/certs/combined.pem

# Graceful HAProxy reload (zero downtime)
docker exec vless_haproxy haproxy -sf $(cat /var/run/haproxy.pid)

echo "$(date): HAProxy reloaded successfully"
```

**User Story:** As a system administrator, I want certificates to renew automatically without manual intervention and HAProxy to reload gracefully so that I avoid service downtime due to expired certificates.

---

### FR-CONFIG-001: Генерация клиентских конфигураций с TLS URIs (HIGH - v4.3 UNCHANGED)

**Requirement:** `vless-user` commands MUST generate client configurations with TLS URI schemes (HAProxy handles TLS).

**Acceptance Criteria:**
- [ ] `vless-user add` generates `socks5_config.txt` with `socks5s://user:pass@server:1080`
- [ ] `vless-user add` generates `http_config.txt` with `https://user:pass@server:8118`
- [ ] `vscode_settings.json` contains `"http.proxy": "https://user:pass@server:8118"`
- [ ] `vscode_settings.json` contains `"http.proxyStrictSSL": true`
- [ ] `git_config.txt` contains `git config http.proxy socks5s://user:pass@server:1080`
- [ ] `bash_exports.sh` contains `export https_proxy=https://user:pass@server:8118`
- [ ] No `socks5://` or `http://` schemes in any config file (plain protocols forbidden)

**File Examples:**

**1. socks5_config.txt (v3.2 vs v3.3+):**
```
# v3.2 (VULNERABLE - plaintext)
socks5://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080

# v3.3+ (SECURE - TLS encrypted via HAProxy v4.3)
socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:1080
```

**2. http_config.txt (v3.2 vs v3.3+):**
```
# v3.2 (VULNERABLE - plaintext)
http://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@203.0.113.42:8118

# v3.3+ (SECURE - HTTPS via HAProxy v4.3)
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
| `socks5s://` | ✅ TLS 1.3 (HAProxy v4.3) | Local | ✅ **RECOMMENDED** - Secure proxy with TLS |
| `socks5h://` | ❌ None | Via Proxy | ⚠️ **Optional** - DNS privacy (NOT a TLS replacement!) |

**Key Points:**
- `socks5s://` = SOCKS5 with TLS (the "s" suffix means SSL/TLS)
- `socks5h://` = SOCKS5 with DNS resolution via proxy (the "h" suffix means hostname)
- **For v4.3:** ALWAYS use `socks5s://` for TLS encryption (HAProxy termination)
- `socks5h://` can be combined: `socks5sh://` for TLS + DNS via proxy (Git does NOT support this)
- **Security:** `socks5h://` alone provides NO encryption - only DNS privacy

**5. bash_exports.sh:**
```bash
#!/bin/bash

# HTTPS Proxy (TLS encrypted via HAProxy)
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

### FR-VSCODE-001: VSCode Integration через HTTPS Proxy (HIGH - v4.3 UNCHANGED)

**Requirement:** VSCode MUST work seamlessly with HTTPS proxy for extensions, updates, and Git operations (TLS via HAProxy).

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
5. Verify network traffic goes through proxy (check HAProxy logs)

**User Story:** As a developer, I want to configure VSCode with HTTPS proxy so that I can install extensions and update VSCode securely without SSL warnings.

---

### FR-GIT-001: Git Integration через SOCKS5s Proxy (HIGH - v4.3 UNCHANGED)

**Requirement:** Git MUST clone repositories and perform operations via socks5s:// proxy (TLS via HAProxy).

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
# SOCKS5 with TLS (socks5s://) - HAProxy termination
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

# Verify proxy usage in HAProxy logs (v4.3)
sudo docker logs vless_haproxy | grep "socks5-tls"
```

**User Story:** As a developer, I want to use Git with socks5s:// proxy so that my code and credentials are encrypted during clone/push operations.

---

### FR-PUBLIC-001: Public Proxy Binding (CRITICAL - v4.3 UNCHANGED)

**Requirement:** SOCKS5 and HTTP proxies MUST be accessible from public internet (unchanged from v3.2, but now with TLS via HAProxy).

**Acceptance Criteria:**
- [ ] HAProxy listens on `0.0.0.0:1080` (TLS encrypted)
- [ ] HAProxy listens on `0.0.0.0:8118` (TLS encrypted)
- [ ] External clients can connect directly (no VPN required)
- [ ] Verified with: `nmap -p 1080,8118 <SERVER_IP>` shows ports open
- [ ] **v4.3:** TLS handshake verified: `openssl s_client -connect server:1080`
- [ ] Connection test: `curl --socks5 user:pass@<SERVER_IP>:1080 https://ifconfig.me`

---

### FR-PASSWORD-001: Enhanced Password Security (CRITICAL - v4.3 UNCHANGED)

**Requirement:** Proxy passwords MUST be 32+ characters to mitigate brute-force attacks.

**Acceptance Criteria:**
- [ ] Password generation: `openssl rand -hex 16` (32 hex chars)
- [ ] All new users get 32-char passwords
- [ ] Password reset generates 32-char passwords
- [ ] No manual password entry (auto-generated only)

---

### FR-FAIL2BAN-001: Fail2ban Integration (CRITICAL - v4.3 UPDATED)

**Requirement:** Fail2ban MUST protect proxy ports from brute-force attacks in ALL proxy modes with HAProxy filter integration.

**Rationale:**
- **Localhost-only (127.0.0.1)**: Protects against brute-force attacks via VPN connection
- **Public (0.0.0.0)**: Protects against brute-force attacks from internet
- **v4.3:** Multi-layer protection (HAProxy + Nginx filters)

**Acceptance Criteria:**
- [ ] Fail2ban installed when `ENABLE_PROXY=true` (regardless of public/localhost mode)
- [ ] **NEW v4.3:** HAProxy filter created (`/etc/fail2ban/filter.d/haproxy-sni.conf`)
- [ ] **NEW v4.3:** HAProxy jail created (`/etc/fail2ban/jail.d/vless-haproxy.conf`)
- [ ] Jail created for SOCKS5 (port 1080)
- [ ] Jail created for HTTP (port 8118)
- [ ] Ban after 5 failed auth attempts
- [ ] Ban duration: 1 hour (3600 seconds)
- [ ] Find time: 10 minutes (600 seconds)
- [ ] Logs monitored: `/opt/vless/logs/haproxy/haproxy.log` (v4.3)
- [ ] Works for both localhost (via VPN) and public (from internet) attacks

**HAProxy Filter (NEW v4.3):**
```ini
# /etc/fail2ban/filter.d/haproxy-sni.conf
[Definition]
failregex = ^.*haproxy.*<HOST>.*SSL handshake failure
            ^.*haproxy.*<HOST>.*Connection reset by peer
ignoreregex =
```

**HAProxy Jail (NEW v4.3):**
```ini
# /etc/fail2ban/jail.d/vless-haproxy.conf
[vless-haproxy]
enabled = true
port = 443,1080,8118
filter = haproxy-sni
logpath = /opt/vless/logs/haproxy/haproxy.log
maxretry = 5
bantime = 3600
findtime = 600
action = ufw
```

---

### FR-UFW-001: UFW Firewall Rules (CRITICAL - v4.3 UPDATED)

**Requirement:** UFW MUST allow proxy ports with rate limiting + temporary port 80 for ACME challenge (HAProxy ports 443, 1080, 8118).

**Acceptance Criteria:**
- [ ] Port 443/tcp open (VLESS Reality + Reverse Proxy via HAProxy)
- [ ] Port 1080/tcp open with rate limit (10 conn/minute per IP) - HAProxy SOCKS5
- [ ] Port 8118/tcp open with rate limit (10 conn/minute per IP) - HAProxy HTTP
- [ ] **NEW v4.3:** Port 80/tcp temporarily opened during certbot run (auto-closed after)
- [ ] Rules persist across reboots
- [ ] Rules applied ONLY if `ENABLE_PUBLIC_PROXY=true`

**UFW Commands:**
```bash
# VLESS Reality + Reverse Proxy (HAProxy v4.3)
sudo ufw allow 443/tcp comment 'VLESS Reality + Reverse Proxy (HAProxy SNI routing)'

# SOCKS5 with rate limiting (HAProxy v4.3)
sudo ufw limit 1080/tcp comment 'VLESS SOCKS5 Proxy (TLS via HAProxy, rate-limited)'

# HTTP with rate limiting (HAProxy v4.3)
sudo ufw limit 8118/tcp comment 'VLESS HTTP Proxy (TLS via HAProxy, rate-limited)'

# Temporary port 80 for ACME challenge (v4.3)
sudo ufw allow 80/tcp comment 'ACME HTTP-01 challenge (temporary)'
# (Automatically closed after certbot completes)

# Verify
sudo ufw status numbered
```

---

### FR-MIGRATION-001: Migration Path v3.2 → v3.3+ → v4.3 (CRITICAL - v4.3 UPDATED)

**Requirement:** Clear migration process with breaking change warnings and config regeneration.

**Acceptance Criteria:**
- [ ] Migration guide document: `MIGRATION_v3.2_to_v3.3.md`, `MIGRATION_v4.0_to_v4.3.md`
- [ ] `vless-update` shows breaking change warning before update
- [ ] `vless-user regenerate` command for batch config regeneration
- [ ] Changelog documents breaking changes
- [ ] README.md updated with v4.3 requirements
- [ ] Old v3.2 configs do NOT work with v3.3+ (validation enforced)
- [ ] **NEW v4.3:** stunnel container automatically removed during update
- [ ] **NEW v4.3:** HAProxy container automatically deployed
- [ ] **NEW v4.3:** combined.pem generated from existing certificates

**Migration Warning (vless-update v4.3):**
```
⚠️  WARNING: v4.3 BREAKING CHANGES (HAProxy Unified Architecture)

v4.3 replaces stunnel with HAProxy for unified TLS and routing.

BREAKING CHANGES:
  1. stunnel container removed (replaced by HAProxy)
  2. Reverse proxy URLs changed: https://domain:9443 → https://domain (NO port!)
  3. combined.pem certificate format required
  4. HAProxy configuration replaces stunnel.conf
  5. Port range changed: 8443-8452 → 9443-9452 (localhost-only)

AUTOMATIC ACTIONS:
  1. stunnel container stopped and removed
  2. HAProxy container deployed
  3. combined.pem generated from existing certificates
  4. Reverse proxy URLs updated (if configured)
  5. UFW rules updated (port 443 for SNI routing)

Estimated downtime: 2-3 minutes (container transition)

Continue with update? [y/N]:
```

**Migration Guide Structure (v4.3):**
```markdown
# Migration Guide: v4.0-v4.2 → v4.3

## Prerequisites
- Domain name pointing to server IP (DNS A record)
- Existing Let's Encrypt certificates

## Breaking Changes
1. stunnel container removed - HAProxy replaces it
2. Reverse proxy access: https://domain:9443 → https://domain (NO port!)
3. Port range: 8443-8452 → 9443-9452 (localhost-only)
4. combined.pem certificate format required
5. HAProxy configuration replaces stunnel.conf

## Migration Steps
1. Backup: `sudo vless-backup`
2. Update: `sudo vless-update`
   - Installer will remove stunnel container
   - HAProxy container deployed automatically
   - combined.pem generated from existing certificates
   - Reverse proxy routes migrated (URLs updated)
3. Verify: `sudo vless-status` (check HAProxy running)
4. Test: VLESS clients (unchanged), proxy clients (unchanged), reverse proxy (new URLs)

## Rollback
If migration fails:
1. Restore backup: `sudo vless-restore /tmp/vless_backup_<timestamp>`
2. Old v4.0-v4.2 configs will work again
```

---

### FR-REVERSE-PROXY-001: Subdomain-Based Reverse Proxy (v4.3 UPDATED)

**Status:** ✅ IMPLEMENTED v4.3 (HAProxy SNI Routing)
**Priority:** CRITICAL (Subdomain-based access)
**Security Review:** ✅ APPROVED (HAProxy SNI routing, no TLS decryption)
**Dependencies:** FR-CERT-001, FR-CERT-002 (Let's Encrypt integration), FR-HAPROXY-001

---

#### 1. Requirement Statement

**Requirement:** Система ДОЛЖНА поддерживать настройку reverse proxy для доступа к конкретному целевому сайту через subdomain с HTTP Basic Authentication (NO port number in URL).

**Rationale:**
- Обход блокировок конкретных сайтов через reverse proxy
- Доступ к geo-restricted контенту (Netflix, YouTube и т.д.)
- Скрытие IP пользователя при доступе к одному сайту
- Простота использования: не требуется настройка VPN или proxy в браузере
- **v4.3:** Subdomain-based access (https://domain, NO port!)
- Поддержка нескольких reverse proxy доменов на одном сервере (до 10)

**Key Requirements:**
- ✅ **v4.3:** Subdomain-based access (https://domain, NO port number!)
- ✅ **v4.3:** HAProxy SNI routing (NO TLS decryption)
- ✅ **v4.3:** Localhost-only Nginx backends (ports 9443-9452)
- ✅ Multiple domains support (up to 10 per server)
- ✅ Error logging only (access log disabled for privacy)
- ✅ Mandatory fail2ban integration (5 failures → 1 hour ban, HAProxy + Nginx filters)
- ✅ Security hardening (VULN-001/002/003/004/005 fixes implemented)
- ❌ WebSocket support explicitly NOT included (HTTP/HTTPS only)

---

#### 2. User Story

**As a** пользователь с заблокированным доступом к сайту
**I want** настроить reverse proxy на своем subdomain
**So that** я могу получить доступ к заблокированному сайту через свой домен без указания порта

**Example Workflow (v4.3):**
```
1. Запускает: sudo vless-proxy add
2. Вводит subdomain: claude.ikeniborn.ru
3. Вводит target site: claude.ai
4. Получает credentials: username / password
5. Открывает https://claude.ikeniborn.ru в браузере (NO :9443!)
6. Вводит credentials
7. Видит контент с claude.ai
```

**Architecture:** См. [04_architecture.md Section 4.7](04_architecture.md#47-haproxy-unified-architecture-v43)

---

#### 3. Acceptance Criteria

**AC-1: Interactive Configuration (v4.3 UPDATED)**
- [ ] DNS validation: `dig +short ${DOMAIN}` matches server IP
- [ ] **REMOVED:** Port configuration (uses default 443 via HAProxy SNI routing)
- [ ] Target site validation: `curl -I https://${TARGET_SITE}`
- [ ] Email for Let's Encrypt
- [ ] **NEW v4.3:** HAProxy ACL generation (dynamic sed-based updates)
- [ ] **NEW v4.3:** Nginx backend port allocation (9443-9452, sequential)

**AC-2: Automatic Certificate Acquisition (v4.3 UPDATED)**
- [ ] certbot obtains certificate for reverse proxy domain
- [ ] Port 80 temporarily opened for ACME challenge
- [ ] Certificates saved to `/etc/letsencrypt/live/${DOMAIN}/`
- [ ] **NEW v4.3:** combined.pem NOT required (Nginx uses fullchain+privkey directly)
- [ ] Port 80 closed after successful acquisition

**AC-3: Credentials Generation (UNCHANGED)**
- [ ] Username: `openssl rand -hex 4` (8 characters)
- [ ] Password: `openssl rand -hex 16` (32 characters)
- [ ] .htpasswd file: `htpasswd -bc .htpasswd-${DOMAIN} username password`
- [ ] Credentials saved to `/opt/vless/config/reverse_proxies.json`

**AC-4: Configuration Updates (v4.3 UPDATED)**
- [ ] **NEW v4.3:** HAProxy ACL added dynamically (sed-based)
- [ ] **NEW v4.3:** HAProxy backend added for Nginx port
- [ ] Nginx config created (server block for localhost:9443-9452)
- [ ] Xray config updated (new inbound + routing rules)
- [ ] docker-compose.yml updated (Nginx port mapping via lib/docker_compose_manager.sh)
- [ ] fail2ban jail config created (multi-port support, HAProxy + Nginx filters)
- [ ] **REMOVED:** UFW rule for reverse proxy port (все через HAProxy port 443)
- [ ] Config validation: `nginx -t`, `xray run -test -c config.json`, `haproxy -c -f haproxy.cfg`

**AC-5: Service Restart (v4.3 UPDATED)**
- [ ] `docker compose up -d` applies changes
- [ ] **NEW v4.3:** HAProxy graceful reload: `haproxy -sf $(cat /var/run/haproxy.pid)`
- [ ] Healthcheck: haproxy, nginx, xray containers running
- [ ] Port listening: `ss -tulnp | grep :443` (HAProxy)
- [ ] fail2ban jail active: `fail2ban-client status vless-haproxy`

**AC-6: Access Without Auth → 401 Unauthorized (v4.3 UPDATED)**
```bash
curl -I https://claude.ikeniborn.ru  # NO :9443!
# Expected: HTTP/1.1 401 Unauthorized
```

**AC-7: Access With Valid Auth → 200 OK (v4.3 UPDATED)**
```bash
curl -I -u username:password https://claude.ikeniborn.ru  # NO :9443!
# Expected: HTTP/1.1 200 OK (content from claude.ai)
```

**AC-8: Access With Invalid Auth → 401 Unauthorized (v4.3 UPDATED)**
```bash
curl -I -u wrong:credentials https://claude.ikeniborn.ru  # NO :9443!
# Expected: HTTP/1.1 401 Unauthorized
```

**AC-9: Domain Restriction (UNCHANGED)**
- User cannot access other sites via reverse proxy (blocked by Xray routing)

**AC-10: CLI - vless-proxy add (v4.3 UPDATED)**
```bash
# Interactive setup (subdomain-based, NO port!)
sudo vless-proxy add
# Prompts for subdomain and target site
# Output: Domain: https://subdomain.example.com (NO :9443!)

# Non-interactive (for automation)
sudo vless-proxy add subdomain.example.com target.com
# Output: Domain: https://subdomain.example.com
```

**AC-11: CLI - vless-proxy list (UNCHANGED)**
```bash
sudo vless-proxy list
# Output: Lists all reverse proxies with subdomains and target sites
```

**AC-12: CLI - vless-proxy show <domain> (UNCHANGED)**
```bash
sudo vless-proxy show subdomain.example.com
# Output: Shows credentials, certificate expiry, fail2ban status
```

**AC-13: CLI - vless-proxy remove <domain> (v4.3 UPDATED)**
```bash
sudo vless-proxy remove subdomain.example.com
# Output: Removes HAProxy ACL, Nginx config, Xray inbound, docker-compose.yml entry
# NO UFW rule removal (все через HAProxy port 443)
```

**AC-14: Port Configuration Validation (v4.3 UPDATED)**
- [ ] **REMOVED:** User port selection (HAProxy uses port 443 for all)
- [ ] **NEW:** Nginx backend port allocation (9443-9452, sequential, automatic)
- [ ] **NEW:** 11th domain blocked with clear error (max 10 domains)

**AC-15: Multiple Domains Support (v4.3 UPDATED)**
- [ ] Support up to 10 reverse proxy domains per server
- [ ] **NEW:** Sequential Nginx backend port allocation: 9443-9452 (localhost-only)
- [ ] Port reuse after domain removal
- [ ] 11th domain blocked with clear error

**AC-16: fail2ban Integration (v4.3 UPDATED - MANDATORY)**
- [ ] **NEW v4.3:** fail2ban HAProxy filter created
- [ ] **NEW v4.3:** fail2ban Nginx filter created (separate from HAProxy)
- [ ] fail2ban jail created for ALL ports (443, 9443-9452)
- [ ] 5 failed auth attempts trigger IP ban
- [ ] Ban duration: 1 hour
- [ ] UFW blocks banned IPs
- [ ] Auto-unban after timeout

**AC-17: Security Headers Validation (UNCHANGED)**
- [ ] HSTS header present: `max-age=31536000`
- [ ] X-Frame-Options: DENY
- [ ] X-Content-Type-Options: nosniff
- [ ] X-XSS-Protection: 1; mode=block

---

#### 4. Security Requirements

**SEC-1: TLS 1.3 Only (v4.3 UPDATED)**
- [ ] **NEW v4.3:** HAProxy: TLS passthrough (NO termination for reverse proxy)
- [ ] Nginx: `ssl_protocols TLSv1.3;`
- [ ] Strong ciphers: `TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256`

**SEC-2: HTTP Basic Auth (MANDATORY - UNCHANGED)**
- [ ] Username: 8 characters (hex)
- [ ] Password: 32 characters (hex)
- [ ] bcrypt hashed in .htpasswd
- [ ] No plaintext password storage

**SEC-3: Domain Restriction (UNCHANGED)**
- [ ] Xray routing: ONLY specified target domain allowed
- [ ] Catch-all rule: `outboundTag: block`
- [ ] No wildcard domains

**SEC-4: Rate Limiting (v4.3 UPDATED)**
- [ ] **NEW v4.3:** HAProxy: connection tracking (maxconn per frontend)
- [ ] UFW: 10 connections/minute per IP for port 443
- [ ] Nginx: `limit_req_zone` 10 requests/second, burst 20
- [ ] Connection limit: 5 concurrent per IP

**SEC-5: Host Header Validation (VULN-001 FIX - CRITICAL - UNCHANGED)**
- [ ] Explicit Host validation: `if ($host != "domain") { return 444; }`
- [ ] Default server block catches invalid Host headers
- [ ] Hardcoded `proxy_set_header Host` (NOT $host)

**SEC-6: HSTS Header (VULN-002 FIX - HIGH - UNCHANGED)**
- [ ] HSTS: `max-age=31536000; includeSubDomains; preload`
- [ ] Additional security headers (X-Frame-Options, X-Content-Type-Options, etc.)

**SEC-7: DoS Protection (VULN-003/004/005 FIX - MEDIUM - UNCHANGED)**
- [ ] Connection limit: 5 concurrent per IP
- [ ] Request rate limit: 10 req/s per IP
- [ ] Max request body size: 10 MB
- [ ] Timeouts: 10s (prevent slowloris)

**SEC-8: Error Logging ONLY (UNCHANGED)**
- [ ] Access log: DISABLED (privacy requirement)
- [ ] Error log: ENABLED (for fail2ban + debugging)
- [ ] Log level: warn (auth failures, connection errors)
- [ ] Log rotation: 7 days retention

**SEC-9: fail2ban Integration (v4.3 UPDATED - MANDATORY)**
```ini
# /etc/fail2ban/jail.d/vless-haproxy.conf (v4.3)
[vless-haproxy]
enabled = true
port = 443,1080,8118
filter = haproxy-sni
logpath = /opt/vless/logs/haproxy/haproxy.log
maxretry = 5
bantime = 3600
findtime = 600
action = ufw

# /etc/fail2ban/jail.d/vless-reverseproxy.conf (v4.3)
[vless-reverseproxy]
enabled = true
port = 9443,9444,9445,9446,9447,9448,9449,9450,9451,9452
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
│   ├── haproxy.cfg                     # v4.3: HAProxy config with dynamic ACLs
│   ├── xray_config.json                # Updated: +multiple reverse-proxy inbounds
│   ├── reverse_proxies.json            # Credentials + port info
│   └── reverse-proxy/                  # Nginx reverse proxy configs
│       ├── proxy1.example.com.conf     # Per-domain config (heredoc-generated)
│       ├── proxy2.example.com.conf
│       ├── .htpasswd-proxy1            # Per-domain Basic Auth (bcrypt hashed)
│       └── .htpasswd-proxy2
│
├── logs/
│   ├── haproxy/                        # v4.3: HAProxy logs
│   │   └── haproxy.log                 # SNI routing + TLS termination logs
│   └── nginx/
│       └── reverse-proxy-error.log     # Error log ONLY (no access log)
│
└── lib/                                # v4.3: HAProxy management modules
    ├── haproxy_config_manager.sh       # NEW: Dynamic ACL management
    ├── certificate_manager.sh          # NEW: combined.pem generation
    ├── nginx_config_generator.sh       # Generates Nginx configs via heredoc
    ├── reverseproxy_db.sh              # Manages reverse_proxies.json
    └── letsencrypt_integration.sh      # Extends FR-CERT-001/002

/etc/fail2ban/                          # v4.3: fail2ban configs
├── jail.d/
│   ├── vless-haproxy.conf              # Multi-port jail (HAProxy)
│   └── vless-reverseproxy.conf         # Multi-port jail (Nginx)
└── filter.d/
    ├── haproxy-sni.conf                # HAProxy filter
    └── vless-reverseproxy.conf         # Nginx auth failure filter

/usr/local/bin/
└── vless-proxy → /opt/vless/scripts/vless-proxy  # Unified CLI (add/list/show/remove)
```

---

#### 6. Configuration File Formats

**reverse_proxies.json (v4.3 UPDATED):**
```json
{
  "version": "1.0",
  "reverse_proxies": [
    {
      "domain": "claude.ikeniborn.ru",
      "target_site": "claude.ai",
      "nginx_backend_port": 9443,
      "xray_inbound_port": 10080,
      "username": "a3f9c2e1",
      "password_hash": "$2y$10$...",
      "created_at": "2025-10-16T21:00:00Z",
      "certificate": "/etc/letsencrypt/live/claude.ikeniborn.ru/",
      "certificate_expires": "2026-01-14T21:00:00Z",
      "last_renewed": "2025-10-16T21:00:00Z",
      "enabled": true
    }
  ]
}
```

**Note:** `nginx_backend_port` is NEW in v4.3 (replaces `port` field from v4.2). This port is localhost-only (NOT exposed to internet).

---

#### 7. Implementation Scope

**In Scope (v4.3):**
- ✅ CLI tools: `vless-proxy` (add/list/show/remove) - subdomain-based
- ✅ HAProxy ACL management (lib/haproxy_config_manager.sh)
- ✅ Nginx config generation via heredoc (lib/nginx_config_generator.sh)
- ✅ Xray HTTP inbound management (lib/xray_http_inbound.sh)
- ✅ Let's Encrypt integration (extends FR-CERT-001/002)
- ✅ fail2ban multi-port support (HAProxy + Nginx filters)
- ✅ **REMOVED:** UFW firewall rules per domain (все через HAProxy port 443)
- ✅ Sequential port allocation (9443-9452, localhost-only)
- ✅ Dynamic docker-compose.yml updates (lib/docker_compose_manager.sh)
- ✅ Security hardening (VULN-001/002/003/004/005 fixes)
- ✅ Graceful HAProxy reload (zero downtime)

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

| Feature | Existing Proxy (SOCKS5/HTTP) | Reverse Proxy (v4.3) |
|---------|------------------------------|---------------------|
| Client | Desktop apps (VSCode, Git, Docker) | Web Browser |
| Protocol | SOCKS5s, HTTPS proxy | HTTPS reverse proxy |
| Authentication | Password (32-char) | HTTP Basic Auth (bcrypt) |
| Target Site | Any (user choice) | Specific (admin choice) |
| Use Case | Proxy for all applications | Access to 1 blocked site |
| Access | https://domain:1080, https://domain:8118 | https://subdomain.domain (NO port!) |
| Port Range | 1080, 8118 (fixed, HAProxy TLS termination) | 9443-9452 (localhost-only, NOT exposed) |

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
- [ ] Setup time < 2 minutes per domain (subdomain-based, NO port!)
- [ ] Zero manual configuration after script run
- [ ] Subdomain access: < 10 seconds per domain

**Security:**
- [ ] fail2ban ban rate: 99% (5 failed attempts → ban)
- [ ] No access log leaks (privacy validated)
- [ ] Error log contains auth failures only
- [ ] All VULN-001/002/003/004/005 fixes validated

---

**User Story:**
- Как системный администратор, я хочу предоставить доступ к заблокированным сайтам через subdomain
- Чтобы пользователи могли обходить блокировки без VPN клиента и без указания порта в URL
- С защитой через HTTP Basic Auth и fail2ban (HAProxy + Nginx)

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

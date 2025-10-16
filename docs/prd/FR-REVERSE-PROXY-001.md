# FR-REVERSE-PROXY-001: Site-Specific Reverse Proxy (NEW v4.2)

**Status:** 📝 DRAFT v2 (with clarifications - 2025-10-16)
**Priority:** HIGH
**Version:** v4.2 (next minor release)
**Breaking Changes:** None (backward compatible)
**Dependencies:** FR-CERT-001, FR-CERT-002 (Let's Encrypt integration)

---

## 1. Requirement Statement

**Requirement:** Система ДОЛЖНА поддерживать настройку reverse proxy для доступа к конкретному целевому сайту через отдельный домен с HTTP Basic Authentication и настраиваемым портом.

**Rationale:**
- Обход блокировок конкретных сайтов через reverse proxy
- Доступ к geo-restricted контенту (Netflix, YouTube и т.д.)
- Скрытие IP пользователя при доступе к одному сайту
- Простота использования: не требуется настройка VPN или proxy в браузере
- Поддержка нескольких reverse proxy доменов на одном сервере (до 10)

**Key Requirements (Updated):**
- ✅ Configurable port (default: 8443)
- ✅ Multiple domains support (up to 10 per server)
- ✅ Error logging only (access log disabled for privacy)
- ✅ Mandatory fail2ban integration
- ❌ WebSocket support explicitly NOT included

---

## 2. User Story

**As a** пользователь с заблокированным доступом к сайту
**I want** настроить reverse proxy на своем домене с возможностью выбора порта
**So that** я могу получить доступ к заблокированному сайту через свой домен без настройки VPN

**Example:**
```
User хочет получить доступ к blocked-site.com
1. Запускает: sudo vless-setup-reverseproxy
2. Вводит домен: myproxy.example.com
3. Вводит порт: 8443 (или custom: 9443)
4. Вводит целевой сайт: blocked-site.com
5. Получает credentials: username / password
6. Открывает https://myproxy.example.com:8443 в браузере
7. Вводит credentials
8. Видит контент с blocked-site.com
```

---

## 3. Architecture

### 3.1 High-Level Architecture (Updated: Configurable Port + Multiple Domains)

```
┌─────────────────────────────────────────────────────────────┐
│                    USER BROWSER                             │
│  https://myproxy.example.com:8443 (Domain 1)               │
│  https://proxy2.example.com:8444 (Domain 2)                │
│  https://proxy3.example.com:9443 (Domain 3, custom port)   │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 1. HTTPS Request (TLS 1.3)
                      │    + Basic Auth credentials
                      ↓
┌─────────────────────────────────────────────────────────────┐
│               UFW FIREWALL (Server)                         │
│  Ports: 8443, 8444, 9443 /tcp: ALLOW (rate limited)       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 2. TLS ClientHello
                      ↓
┌─────────────────────────────────────────────────────────────┐
│        NGINX CONTAINER (vless_nginx)                        │
│  Multiple server blocks (one per domain):                  │
│                                                             │
│  Server 1: listen 8443 ssl; server_name proxy1.example.com│
│    - TLS Termination (Let's Encrypt cert 1)               │
│    - HTTP Basic Auth (credentials 1)                       │
│    - proxy_pass to Xray localhost:10080                    │
│    - error_log ONLY (no access_log)                        │
│                                                             │
│  Server 2: listen 8444 ssl; server_name proxy2.example.com│
│    - TLS Termination (Let's Encrypt cert 2)               │
│    - HTTP Basic Auth (credentials 2)                       │
│    - proxy_pass to Xray localhost:10081                    │
│                                                             │
│  Server 3: listen 9443 ssl; server_name proxy3.example.com│
│    - TLS Termination (Let's Encrypt cert 3)               │
│    - HTTP Basic Auth (credentials 3)                       │
│    - proxy_pass to Xray localhost:10082                    │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 3. HTTP (plaintext, localhost)
                      ↓
┌─────────────────────────────────────────────────────────────┐
│         XRAY CONTAINER (vless_xray)                         │
│  Multiple inbounds (one per reverse proxy):                │
│                                                             │
│  Inbound 1:                                                 │
│    - Tag: reverse-proxy-1                                  │
│    - Listen: 127.0.0.1:10080                               │
│  Routing 1:                                                 │
│    - InboundTag: reverse-proxy-1                           │
│    - Domain: target1.com ONLY                              │
│                                                             │
│  Inbound 2:                                                 │
│    - Tag: reverse-proxy-2                                  │
│    - Listen: 127.0.0.1:10081                               │
│  Routing 2:                                                 │
│    - InboundTag: reverse-proxy-2                           │
│    - Domain: target2.com ONLY                              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 4. HTTP/HTTPS to target sites
                      ↓
┌─────────────────────────────────────────────────────────────┐
│     TARGET SITES (target1.com, target2.com, ...)          │
└─────────────────────────────────────────────────────────────┘

SECURITY LAYERS:
  ✅ TLS 1.3 Encryption (Nginx)
  ✅ HTTP Basic Auth (Nginx)
  ✅ Domain restriction (Xray routing per inbound)
  ✅ Rate limiting (UFW + Nginx)
  ✅ fail2ban (MANDATORY, multi-port)
  ✅ Error logging only (privacy)
```

**Port Allocation Strategy:**
- Domain 1: 8443 (default)
- Domain 2: 8444 (default + 1)
- Domain 3: 8445 (default + 2)
- ...
- Domain 10: 8452 (default + 9)
- Custom: user-specified port (validated for conflicts)

### 3.2 Component Details

**1. Nginx Reverse Proxy Configuration (Updated: Configurable Port + Error Log Only):**

```nginx
# /opt/vless/reverse-proxy/myproxy.example.com.conf

upstream xray_reverseproxy_1 {
    server vless_xray:10080;
    keepalive 32;
}

server {
    listen 8443 ssl http2;  # Configurable port (default 8443)
    server_name myproxy.example.com;

    # TLS Configuration
    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;

    # HTTP Basic Auth
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/reverse-proxy/.htpasswd-myproxy;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=reverseproxy:10m rate=10r/s;
    limit_req zone=reverseproxy burst=20 nodelay;

    # Logging (UPDATED: error log only, no access log)
    access_log off;  # Privacy: no access logging
    error_log /var/log/nginx/reverse-proxy-error.log warn;

    # Proxy to Xray
    location / {
        proxy_pass http://xray_reverseproxy_1;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host blocked-site.com;  # Target site
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

**2. Xray Reverse Proxy Inbound (per domain):**

```json
{
  "inbounds": [
    {
      "tag": "reverse-proxy-1",
      "protocol": "http",
      "listen": "127.0.0.1",
      "port": 10080,
      "settings": {
        "allowTransparent": false,
        "userLevel": 0
      }
    },
    {
      "tag": "reverse-proxy-2",
      "protocol": "http",
      "listen": "127.0.0.1",
      "port": 10081,
      "settings": {
        "allowTransparent": false,
        "userLevel": 0
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-1"],
        "domain": ["target1.com"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-1"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-2"],
        "domain": ["target2.com"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-2"],
        "outboundTag": "block"
      }
    ]
  },
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
```

**3. Docker Compose Updates (Multi-Port):**

```yaml
services:
  nginx:
    container_name: vless_nginx
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"       # fake-site (existing)
      - "8443:8443"                # reverse proxy 1 (NEW)
      - "8444:8444"                # reverse proxy 2 (NEW)
      - "8445:8445"                # reverse proxy 3 (NEW)
      - "8446:8446"                # reverse proxy 4 (NEW)
      - "8447:8447"                # reverse proxy 5 (NEW)
      - "8448:8448"                # reverse proxy 6 (NEW)
      - "8449:8449"                # reverse proxy 7 (NEW)
      - "8450:8450"                # reverse proxy 8 (NEW)
      - "8451:8451"                # reverse proxy 9 (NEW)
      - "8452:8452"                # reverse proxy 10 (NEW)
      # Note: Custom ports can be added dynamically via docker-compose config update
    volumes:
      - ./fake-site:/etc/nginx/conf.d/fake-site:ro
      - ./reverse-proxy:/etc/nginx/conf.d/reverse-proxy:ro  # NEW
      - /etc/letsencrypt:/etc/letsencrypt:ro  # NEW
      - ./logs/nginx:/var/log/nginx
    networks:
      - vless_reality_net
    depends_on:
      - xray
```

---

## 4. Acceptance Criteria

### 4.1 Setup Script (vless-setup-reverseproxy)

**AC-1: Interactive Configuration (Updated: Port Configuration)**
- [ ] Скрипт запрашивает домен для reverse proxy (myproxy.example.com)
- [ ] DNS validation: `dig +short ${DOMAIN}` matches server IP
- [ ] **NEW:** Запрашивает порт: "Enter port [8443]:" (default or custom)
- [ ] **NEW:** Port availability check: `ss -tulnp | grep :${PORT}`
- [ ] **NEW:** Port conflict validation (against 443, 1080, 8118, existing reverse proxies)
- [ ] Запрашивает целевой сайт (blocked-site.com)
- [ ] Проверка доступности целевого сайта: `curl -I https://${TARGET_SITE}`
- [ ] Запрашивает email для Let's Encrypt

**Port Validation Logic:**
```bash
# Check if port is already in use
if ss -tulnp | grep -q ":${PORT}"; then
  echo "Error: Port ${PORT} is already in use"
  exit 1
fi

# Check if port conflicts with system services
RESERVED_PORTS=(443 1080 8118)
if [[ " ${RESERVED_PORTS[@]} " =~ " ${PORT} " ]]; then
  echo "Error: Port ${PORT} is reserved for system services"
  exit 1
fi

# Check if port is used by another reverse proxy
if jq -e ".reverse_proxies[] | select(.port == ${PORT})" /opt/vless/config/reverse_proxy_users.json > /dev/null 2>&1; then
  echo "Error: Port ${PORT} is already used by another reverse proxy"
  exit 1
fi
```

**AC-2: Automatic Certificate Acquisition**
- [ ] certbot получает сертификат для reverse proxy домена
- [ ] Port 80 временно открыт для ACME challenge
- [ ] Сертификаты сохранены в `/etc/letsencrypt/live/${DOMAIN}/`
- [ ] Port 80 закрыт после успешного получения сертификата

**AC-3: Credentials Generation**
- [ ] Генерация username: `openssl rand -hex 4` (8 chars)
- [ ] Генерация password: `openssl rand -hex 16` (32 chars)
- [ ] Создание `.htpasswd` файла: `htpasswd -bc .htpasswd-${DOMAIN} username password`
- [ ] Сохранение credentials в `/opt/vless/config/reverse_proxy_users.json`

**AC-4: Configuration Updates**
- [ ] Создание Nginx конфига для reverse proxy (с указанным портом)
- [ ] Обновление Xray конфига (новый inbound + routing rules)
- [ ] Обновление docker-compose.yml (новый порт mapping)
- [ ] **NEW:** Создание fail2ban jail config (multi-port support)
- [ ] **NEW:** UFW rule для нового порта: `ufw allow ${PORT}/tcp comment 'VLESS Reverse Proxy'`
- [ ] Валидация всех конфигов: `nginx -t`, `xray run -test -c config.json`

**AC-5: Service Restart**
- [ ] docker-compose up -d (применение изменений)
- [ ] Healthcheck: nginx и xray контейнеры работают
- [ ] Port listening: `ss -tulnp | grep ${PORT}`
- [ ] **NEW:** fail2ban jail active: `fail2ban-client status vless-reverseproxy`

**AC-6: Output (Updated: Show Custom Port)**
```
✅ Reverse proxy successfully configured!

Domain: https://myproxy.example.com:9443  # Custom port shown
Target Site: blocked-site.com
Username: a3f9c2e1
Password: 7d4b9e1f2a8c6d3e5b7f1a9c4e2d8b6f

Security:
  - TLS 1.3 encryption (Let's Encrypt)
  - HTTP Basic Auth (bcrypt hashed)
  - Domain restriction (target site only)
  - fail2ban protection (5 attempts → 1 hour ban)
  - Rate limiting (10 req/sec per IP)

Usage:
  1. Open https://myproxy.example.com:9443 in browser
  2. Enter credentials when prompted
  3. You will see content from blocked-site.com

Configuration files:
  - Nginx config: /opt/vless/reverse-proxy/myproxy.example.com.conf
  - Xray config: /opt/vless/config/xray_config.json (updated)
  - Credentials: /opt/vless/config/reverse_proxy_users.json
  - fail2ban jail: /etc/fail2ban/jail.d/vless-reverseproxy.conf
```

### 4.2 Functional Tests

**AC-7: Access Without Auth**
```bash
curl -I https://myproxy.example.com:8443

# Expected:
# HTTP/1.1 401 Unauthorized
# WWW-Authenticate: Basic realm="Restricted Access"
```

**AC-8: Access With Valid Auth**
```bash
curl -I -u username:password https://myproxy.example.com:8443

# Expected:
# HTTP/1.1 200 OK (content from blocked-site.com)
```

**AC-9: Access With Invalid Auth**
```bash
curl -I -u wrong:credentials https://myproxy.example.com:8443

# Expected:
# HTTP/1.1 401 Unauthorized
```

**AC-10: Domain Restriction**
```bash
# User tries to access other site via reverse proxy
# (through manipulating headers)

# Expected: Blocked by Xray routing rules
```

### 4.3 CLI Commands (Updated: --port flag)

**AC-11: vless-rproxy add (with --port flag)**
```bash
# Default port
sudo vless-rproxy add myproxy.example.com blocked-site.com

# Output:
# ✅ Reverse proxy added
# Domain: https://myproxy.example.com:8443
# Target: blocked-site.com
# Username: a3f9c2e1
# Password: 7d4b9e1f2a8c6d3e5b7f1a9c4e2d8b6f

# Custom port
sudo vless-rproxy add proxy2.example.com target2.com --port 9443

# Output:
# ✅ Reverse proxy added
# Domain: https://proxy2.example.com:9443
# Target: target2.com
# Username: b4e8d3f2
# Password: 8e5c0a2f3b9d7e1f4a6c8b0d9e1f5a3c
```

**AC-12: vless-rproxy list (show ports)**
```bash
sudo vless-rproxy list

# Output:
# REVERSE PROXIES:
#   1. myproxy.example.com:8443 → blocked-site.com (user: a3f9c2e1) [Active]
#   2. proxy2.example.com:9443 → target2.com (user: b4e8d3f2) [Active]
#   3. proxy3.example.com:8444 → target3.com (user: c5f9e4a3) [Active]
```

**AC-13: vless-rproxy show <domain>**
```bash
sudo vless-rproxy show myproxy.example.com

# Output:
# REVERSE PROXY: myproxy.example.com
#   Target Site: blocked-site.com
#   Port: 9443
#   Username: a3f9c2e1
#   Password: 7d4b9e1f2a8c6d3e5b7f1a9c4e2d8b6f
#   Certificate: /etc/letsencrypt/live/myproxy.example.com/
#   Expires: 2025-04-15 (89 days)
#   Status: Active
#   fail2ban: Enabled (5 failed attempts logged)
```

**AC-14: vless-rproxy remove <domain>**
```bash
sudo vless-rproxy remove myproxy.example.com

# Output:
# ⚠️  WARNING: This will remove reverse proxy for myproxy.example.com
# Continue? [y/N]: y
# ✅ Reverse proxy removed
# - Nginx config deleted
# - Xray routing rules removed
# - fail2ban jail updated (port removed)
# - UFW rule removed
# - Certificate retained (use certbot delete manually if needed)
```

### 4.4 NEW Acceptance Criteria (Port + Multiple Domains + fail2ban)

**AC-15: Port Configuration Validation**
```bash
# Test 1: Default port
sudo vless-rproxy add test1.example.com target1.com
# Expected: Uses port 8443

# Test 2: Custom port
sudo vless-rproxy add test2.example.com target2.com --port 9443
# Expected: Uses port 9443

# Test 3: Port conflict (system service)
sudo vless-rproxy add test3.example.com target3.com --port 443
# Expected: Error - port 443 is reserved for VLESS VPN

# Test 4: Port conflict (already used by reverse proxy)
sudo vless-rproxy add test4.example.com target4.com --port 8443
# Expected: Error - port 8443 already used by test1.example.com

# Test 5: Port already in use by other service
sudo vless-rproxy add test5.example.com target5.com --port 22
# Expected: Error - port 22 is already in use
```

**AC-16: Multiple Domains Support**
```bash
# Add 10 domains (max limit)
for i in {1..10}; do
  sudo vless-rproxy add proxy${i}.example.com target${i}.com
done

# List all
sudo vless-rproxy list
# Expected: 10 domains listed with sequential ports (8443-8452)

# Try to add 11th domain
sudo vless-rproxy add proxy11.example.com target11.com
# Expected: Error - maximum 10 reverse proxy domains reached

# Remove one domain
sudo vless-rproxy remove proxy1.example.com

# Add new domain (should work now)
sudo vless-rproxy add proxy11.example.com target11.com
# Expected: Success - uses available port (8443)
```

**AC-17: fail2ban Integration (MANDATORY)**
```bash
# Test 1: Check fail2ban jail exists and is active
sudo fail2ban-client status vless-reverseproxy
# Expected:
# Status for the jail: vless-reverseproxy
# |- Filter
# |  |- Currently failed: 0
# |  |- Total failed: 0
# |  `- File list: /opt/vless/logs/nginx/reverse-proxy-error.log
# `- Actions
#    |- Currently banned: 0
#    |- Total banned: 0
#    `- Banned IP list:

# Test 2: Trigger 5 failed auth attempts
for i in {1..5}; do
  curl -u wrong:credentials https://proxy1.example.com:8443
  sleep 2
done

# Test 3: Check if IP is banned
sudo fail2ban-client status vless-reverseproxy
# Expected:
# |- Currently failed: 0
# |- Total failed: 5
# |- Currently banned: 1
# `- Banned IP list: 203.0.113.42

# Test 4: Verify UFW block
sudo ufw status | grep 203.0.113.42
# Expected: IP blocked in UFW

# Test 5: Wait 1 hour and verify unban (or use fail2ban-client unban)
sudo fail2ban-client unban 203.0.113.42
sudo fail2ban-client status vless-reverseproxy
# Expected:
# |- Currently banned: 0
```

---

## 5. Security Requirements

### 5.1 Mandatory Security

**SEC-1: TLS 1.3 Only**
- [ ] Nginx: `ssl_protocols TLSv1.3;`
- [ ] Strong ciphers: `TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256`
- [ ] Perfect Forward Secrecy enabled

**SEC-2: HTTP Basic Auth**
- [ ] MANDATORY for all reverse proxy endpoints
- [ ] Username: 8 characters (hex)
- [ ] Password: 32 characters (hex)
- [ ] bcrypt hashed in `.htpasswd` file
- [ ] No plaintext password storage

**SEC-3: Domain Restriction**
- [ ] Xray routing: ONLY specified target domain allowed per inbound
- [ ] Catch-all rule: `outboundTag: block` for other domains
- [ ] No wildcard domains (explicit list only)

**SEC-4: Rate Limiting**
- [ ] UFW: 10 connections/minute per IP per port
- [ ] Nginx: `limit_req_zone` 10 requests/second
- [ ] Burst: 20 requests (with nodelay)

**SEC-5: Security Headers**
- [ ] Strict-Transport-Security: max-age=31536000
- [ ] X-Frame-Options: SAMEORIGIN
- [ ] X-Content-Type-Options: nosniff
- [ ] X-XSS-Protection: 1; mode=block

### 5.2 Logging & Monitoring (Updated: Error Log Only)

**SEC-6: Error Logging ONLY (UPDATED)**
- [ ] **Access log: DISABLED** (privacy requirement - no IP/URL logging)
- [ ] **Error log: ENABLED** (for fail2ban + debugging)
- [ ] Log level: warn (auth failures, connection errors)
- [ ] Log rotation: logrotate (7 days retention)

**Nginx Config:**
```nginx
# Privacy: no access logging
access_log off;

# Error logging for fail2ban + debugging
error_log /var/log/nginx/reverse-proxy-error.log warn;
```

**Error Log Format (Examples):**
```
2025/10/16 21:45:00 [error] 123#123: *1 user "wrong_user" was not found in "/etc/nginx/reverse-proxy/.htpasswd", client: 203.0.113.42, server: myproxy.example.com, request: "GET / HTTP/1.1"
2025/10/16 21:45:02 [error] 123#123: *2 user "alice" password mismatch, client: 203.0.113.42, server: myproxy.example.com, request: "GET / HTTP/1.1"
```

**SEC-7: fail2ban Integration (UPDATED: MANDATORY)**
```ini
# /etc/fail2ban/jail.d/vless-reverseproxy.conf
[vless-reverseproxy]
enabled = true
port = 8443,8444,8445,8446,8447,8448,8449,8450,8451,8452  # All reverse proxy ports
filter = vless-reverseproxy
logpath = /opt/vless/logs/nginx/reverse-proxy-error.log
maxretry = 5
bantime = 3600
findtime = 600
action = ufw
```

**fail2ban Filter:**
```ini
# /etc/fail2ban/filter.d/vless-reverseproxy.conf
[Definition]
failregex = ^ .* user .* was not found in ".*", client: <HOST>, server: .*$
            ^ .* user .* password mismatch, client: <HOST>, server: .*$
ignoreregex =
```

**fail2ban Action (UFW):**
- Ban IP in UFW firewall
- Block all traffic from banned IP
- Auto-unban after 1 hour

---

## 6. File Structure (v4.2 - Updated)

```
/opt/vless/
├── config/
│   ├── xray_config.json               # Updated: +multiple reverse-proxy inbounds
│   └── reverse_proxy_users.json       # NEW: Credentials + port info
│
├── reverse-proxy/                      # NEW: Nginx reverse proxy configs
│   ├── proxy1.example.com.conf        # Per-domain config
│   ├── proxy2.example.com.conf
│   ├── .htpasswd-proxy1               # Per-domain Basic Auth (hashed)
│   └── .htpasswd-proxy2
│
├── logs/
│   └── nginx/
│       └── reverse-proxy-error.log    # NEW: Error log ONLY (no access log)
│
└── scripts/
    ├── vless-setup-reverseproxy       # NEW: Setup script
    └── vless-rproxy                   # NEW: Management CLI

/etc/fail2ban/                          # NEW: fail2ban configs
├── jail.d/
│   └── vless-reverseproxy.conf        # NEW: Multi-port jail
└── filter.d/
    └── vless-reverseproxy.conf        # NEW: Nginx auth failure filter

/usr/local/bin/
├── vless-setup-reverseproxy → /opt/vless/scripts/vless-setup-reverseproxy
└── vless-rproxy → /opt/vless/scripts/vless-rproxy
```

---

## 7. Configuration File Formats

### 7.1 reverse_proxy_users.json (Updated: Add Port Field)

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
      "enabled": true
    },
    {
      "domain": "proxy2.example.com",
      "target_site": "target2.com",
      "port": 8444,
      "xray_inbound_port": 10081,
      "username": "b4e8d3f2",
      "password_hash": "$2y$10$...",
      "created_at": "2025-10-16T21:30:00Z",
      "certificate": "/etc/letsencrypt/live/proxy2.example.com/",
      "certificate_expires": "2026-01-14T21:30:00Z",
      "enabled": true
    }
  ]
}
```

---

## 8. Non-Functional Requirements (Updated: Multiple Domains)

**NFR-RPROXY-001: Performance**
- [ ] Latency overhead < 50ms (vs direct access)
- [ ] Throughput: 100 Mbps per reverse proxy instance
- [ ] Max concurrent connections: 1000 per domain
- [ ] **NEW:** Total throughput with 10 domains: 1 Gbps aggregate

**NFR-RPROXY-002: Scalability (UPDATED)**
- [ ] Support up to 10 reverse proxy domains per server
- [ ] Each domain: 1 target site (1:1 mapping)
- [ ] **NEW:** Each domain: unique port (8443-8452 default range)
- [ ] **NEW:** Each domain: separate Xray inbound (10080-10089)
- [ ] **NEW:** Port allocation: sequential or user-specified

**NFR-RPROXY-003: Reliability**
- [ ] Uptime: 99.9%
- [ ] Auto-recovery: Container restart on failure
- [ ] Certificate auto-renewal (same as v3.3+)
- [ ] **NEW:** fail2ban: 99% ban success rate

---

## 9. Out of Scope (UPDATED: WebSocket Explicitly)

**NOT Included in v4.2:**
- ❌ **WebSocket proxying (HTTP/HTTPS only) - EXPLICITLY NOT SUPPORTED**
  - Reason: WebSocket requires different Nginx configuration (`proxy_set_header Upgrade/Connection`)
  - Alternative: Use VLESS VPN for WebSocket applications
  - Future: May be added in v4.3 if needed
- ❌ GRPC proxying
- ❌ Multiple target sites per domain (load balancing)
- ❌ Custom authentication (OAuth, LDAP) - only Basic Auth
- ❌ CDN integration (Cloudflare, etc.)
- ❌ Content caching (reverse proxy is transparent)
- ❌ Access logging (privacy requirement - only error log)

---

## 10. Multiple Domains Architecture (NEW SECTION)

### 10.1 Port Allocation Strategy

**Default Sequential Allocation:**
```
Domain 1: port 8443 (first reverse proxy)
Domain 2: port 8444 (auto-assigned)
Domain 3: port 8445 (auto-assigned)
...
Domain 10: port 8452 (last available)
```

**Custom Port Allocation:**
```bash
# User specifies custom port
sudo vless-rproxy add proxy.example.com target.com --port 9443

# System checks:
# 1. Port availability (ss -tulnp)
# 2. Port conflicts (443, 1080, 8118)
# 3. Port uniqueness (no duplicates in reverse_proxy_users.json)
```

**Port Limits:**
- Min: 1024 (unprivileged ports)
- Max: 65535
- Reserved: 443, 1080, 8118 (system services)
- Max domains: 10 per server

### 10.2 Xray Inbound Port Mapping

Each reverse proxy domain gets its own Xray inbound:

```
Public Port    →    Nginx    →    Xray Inbound Port
8443           →    proxy1   →    127.0.0.1:10080
8444           →    proxy2   →    127.0.0.1:10081
8445           →    proxy3   →    127.0.0.1:10082
...
8452 (or custom) →  proxy10  →   127.0.0.1:10089
```

**Xray Inbound Port Allocation:**
- Base: 10080
- Domain N: 10080 + (N - 1)
- Range: 10080-10089 (10 inbounds max)

### 10.3 UFW Firewall Rules (Per Domain)

```bash
# Domain 1
sudo ufw allow 8443/tcp comment 'VLESS Reverse Proxy 1: proxy1.example.com'

# Domain 2
sudo ufw allow 8444/tcp comment 'VLESS Reverse Proxy 2: proxy2.example.com'

# Domain 3 (custom port)
sudo ufw allow 9443/tcp comment 'VLESS Reverse Proxy 3: proxy3.example.com'

# List all rules
sudo ufw status numbered
```

### 10.4 CLI Usage Examples

```bash
# Example 1: Add 3 domains with default ports
sudo vless-rproxy add proxy1.example.com target1.com
# Port: 8443 (auto-assigned)

sudo vless-rproxy add proxy2.example.com target2.com
# Port: 8444 (auto-assigned)

sudo vless-rproxy add proxy3.example.com target3.com
# Port: 8445 (auto-assigned)

# Example 2: Add domain with custom port
sudo vless-rproxy add vip.example.com important-site.com --port 9000
# Port: 9000 (user-specified)

# Example 3: List all domains
sudo vless-rproxy list
# Output:
#   1. proxy1.example.com:8443 → target1.com
#   2. proxy2.example.com:8444 → target2.com
#   3. proxy3.example.com:8445 → target3.com
#   4. vip.example.com:9000 → important-site.com

# Example 4: Remove domain (port is freed)
sudo vless-rproxy remove proxy2.example.com
# Port 8444 is now available for reuse

# Example 5: Add new domain (reuses freed port)
sudo vless-rproxy add new.example.com new-site.com
# Port: 8444 (reused from removed domain)
```

---

## 11. Migration & Backward Compatibility

**Backward Compatibility:**
- ✅ Existing VLESS VPN functionality unchanged
- ✅ Existing SOCKS5/HTTP proxy unchanged
- ✅ Existing ports (443, 1080, 8118) unchanged
- ✅ New ports 8443-8452 for reverse proxy (no conflicts)
- ✅ fail2ban integration does not affect existing services

**Migration from v4.1 to v4.2:**
- No breaking changes
- Optional feature (not installed by default)
- Requires manual setup via `vless-setup-reverseproxy`
- fail2ban automatically installed if not present

---

## 12. Success Metrics (Updated)

**Functional:**
- [ ] 100% acceptance criteria passed (17 AC total: original 14 + new 3)
- [ ] All 17 AC tests passed
- [ ] Security tests passed (TLS, auth, domain restriction, fail2ban)

**Performance:**
- [ ] Latency < 50ms overhead per domain
- [ ] 1000 concurrent connections per domain
- [ ] 10 Gbps aggregate throughput (10 domains × 1 Gbps)

**Usability:**
- [ ] Setup time < 5 minutes per domain
- [ ] Zero manual configuration after script run
- [ ] Port configuration: < 30 seconds per domain

**Security:**
- [ ] fail2ban ban rate: 99% (5 failed attempts → ban)
- [ ] No access log leaks (privacy validated)
- [ ] Error log contains auth failures only

---

## 13. References

### 13.1 Technical Documentation

- Nginx reverse proxy: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- Nginx Basic Auth: https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html
- Xray HTTP protocol: https://xtls.github.io/config/protocols/http.html
- Xray routing: https://xtls.github.io/config/routing.html
- fail2ban: https://www.fail2ban.org/wiki/index.php/Main_Page
- UFW: https://help.ubuntu.com/community/UFW

### 13.2 Related PRD Sections

- [FR-CERT-001](02_functional_requirements.md#fr-cert-001) - Let's Encrypt integration (reused)
- [FR-CERT-002](02_functional_requirements.md#fr-cert-002) - Auto-renewal (reused)
- [FR-FAIL2BAN-001](02_functional_requirements.md#fr-fail2ban-001) - fail2ban integration (extended)
- [FR-UFW-001](02_functional_requirements.md#fr-ufw-001) - UFW firewall rules (extended)
- [04_architecture.md](04_architecture.md) - Network architecture (extended)

---

## 14. Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | User | 2025-10-16 | ✅ Approved with clarifications |
| Tech Lead | Claude | 2025-10-16 | FR-REVERSE-PROXY-001 DRAFT v2 Complete |
| Security Review | Required | Pending | TLS + Basic Auth + fail2ban + Privacy (error log only) |

---

**END OF FR-REVERSE-PROXY-001 (DRAFT v2)**

**Changes from DRAFT v1:**
- ✅ Added configurable port support (default 8443, user-specified)
- ✅ Added multiple domains support (up to 10 per server)
- ✅ Changed logging: access log OFF, error log ON (privacy)
- ✅ Changed fail2ban: OPTIONAL → MANDATORY
- ✅ Added WebSocket to "Out of Scope" (explicitly NOT supported)
- ✅ Added 3 new acceptance criteria (AC-15, AC-16, AC-17)
- ✅ Updated all examples with port configuration
- ✅ Updated NFR with multi-domain scalability
- ✅ Added Section 10: Multiple Domains Architecture

**Next Steps:**
1. ✅ Review draft v2 with product owner (APPROVED)
2. Validate architecture with security team
3. Create PLAN.md for v4.2 implementation
4. Develop vless-setup-reverseproxy script
5. Develop vless-rproxy CLI tool
6. Test reverse proxy functionality (17 AC tests)
7. Update main PRD documentation

---

**Created:** 2025-10-16
**Updated:** 2025-10-16 (DRAFT v2 with clarifications)
**Status:** 📝 DRAFT v2
**Version:** v4.2 (proposed)

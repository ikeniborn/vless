# PRD v4.1 - Technical Architecture

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

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

### 4.6 Reverse Proxy Architecture (v4.2)

**Feature Status:** 📝 DRAFT v3 (Security Hardened - 2025-10-17)
**Security Review:** ✅ APPROVED (VULN-001/002/003/004/005 mitigated)

#### 4.6.1 High-Level Architecture

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
│        NGINX CONTAINER (vless_nginx_reverseproxy)           │
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

#### 4.6.2 Component Configuration

**Nginx Reverse Proxy Server Block (with VULN-001/002 fixes):**

```nginx
# /opt/vless/config/reverse-proxy/myproxy.example.com.conf

upstream xray_reverseproxy_1 {
    server vless_xray:10080;
    keepalive 32;
}

# Primary server block (with Host header validation)
server {
    listen 8443 ssl http2;  # Configurable port
    server_name myproxy.example.com;  # EXACT match required

    # TLS Configuration
    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;

    # HTTP Basic Auth
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/conf.d/reverse-proxy/.htpasswd-myproxy;

    # VULN-001 FIX: Host Header Validation (CRITICAL)
    if ($host != "myproxy.example.com") {
        return 444;  # Close connection without response
    }

    # VULN-002 FIX: HSTS Header (HIGH)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Additional Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Rate Limiting
    limit_req zone=reverseproxy burst=20 nodelay;
    limit_conn conn_limit_per_ip 5;

    # Logging (error log only, no access log)
    access_log off;  # Privacy: no access logging
    error_log /var/log/nginx/reverse-proxy-error.log warn;

    # Proxy to Xray
    location / {
        proxy_pass http://xray_reverseproxy_1;
        proxy_http_version 1.1;

        # VULN-001 FIX: Hardcoded Host header (NOT $host)
        proxy_set_header Host blocked-site.com;  # Target site (hardcoded)

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts (prevent slowloris)
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# VULN-001 FIX: Default server block (catch invalid Host headers)
server {
    listen 8443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;

    # Reject all requests with invalid Host header
    return 444;  # No response
}
```

**Nginx HTTP Context Configuration (rate limiting):**

```nginx
http {
    # VULN-003 FIX: Connection limit zone
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

    # VULN-004 FIX: Request rate limit zone
    limit_req_zone $binary_remote_addr zone=reverseproxy:10m rate=10r/s;

    # VULN-005 FIX: Maximum request body size
    client_max_body_size 10m;

    # Timeouts (prevent slowloris attacks)
    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;
    keepalive_timeout 30s;

    # Error responses for limit violations
    limit_conn_status 429;  # Too Many Requests
    limit_req_status 429;

    # Include server blocks
    include /etc/nginx/conf.d/reverse-proxy/*.conf;
}
```

**Xray Reverse Proxy Inbound Configuration:**

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
  }
}
```

#### 4.6.3 Port Mapping Strategy

Each reverse proxy domain gets its own unique port mapping:

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

**Port Validation:**
- Reserved: 443 (VLESS), 1080 (SOCKS5), 8118 (HTTP)
- Min: 1024 (unprivileged)
- Max: 65535
- Max domains: 10 per server

#### 4.6.4 Docker Compose Integration

**Dynamic Port Mapping (v4.2):**

```yaml
services:
  nginx:
    container_name: vless_nginx_reverseproxy
    image: nginx:alpine
    restart: unless-stopped
    ports:
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
      # Note: Ports managed dynamically via lib/docker_compose_manager.sh
    volumes:
      - ./config/reverse-proxy/:/etc/nginx/conf.d/reverse-proxy/:ro
      - ./config/reverse-proxy-http-context.conf:/etc/nginx/conf.d/reverse-proxy-http-context.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./logs/nginx/:/var/log/nginx/
    networks:
      - vless_reality_net
    depends_on:
      - xray
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3
```

**Key Features:**
- ✅ Configurable ports (default 8443-8452)
- ✅ Multi-domain support (up to 10)
- ✅ Dynamic port allocation via `lib/docker_compose_manager.sh`
- ✅ Separate Nginx container for reverse proxy
- ✅ Integration with existing VLESS/SOCKS5/HTTP services

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

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
/opt/familytraffic/
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
    └── familytraffic-cert-renew        # Deploy hook script ←NEW v3.3

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
│   └── familytraffic-proxy.conf        # Proxy jails (unchanged)
└── filter.d/
    └── familytraffic-proxy.conf        # Xray log filters (unchanged)

/etc/cron.d/
└── certbot-vless-renew         # Auto-renewal cron ←NEW

/usr/local/bin/
└── familytraffic-cert-renew            # Deploy hook script ←NEW
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
    container_name: familytraffic-stunnel
    restart: unless-stopped
    ports:
      - "1080:1080"   # SOCKS5 with TLS
      - "8118:8118"   # HTTP with TLS
    volumes:
      - /opt/familytraffic/config/stunnel.conf:/etc/stunnel/stunnel.conf:ro
      - /etc/letsencrypt:/certs:ro  # Let's Encrypt certificates
      - /opt/familytraffic/logs/stunnel:/var/log/stunnel
    networks:
      - familytraffic_net
    depends_on:
      - xray

  xray:
    image: teddysun/xray:24.11.30
    container_name: familytraffic
    restart: unless-stopped
    networks:
      - familytraffic_net
    ports:
      - "${VLESS_PORT}:${VLESS_PORT}"  # VLESS Reality port (default: 443)
    volumes:
      - /opt/familytraffic/config:/etc/xray:ro
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
    container_name: familytraffic-fake-site
    restart: unless-stopped
    networks:
      - familytraffic_net
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - /opt/familytraffic/fake-site:/etc/nginx/conf.d:ro

networks:
  familytraffic_net:
    driver: bridge
```

**Key Changes (v4.0/v4.1):**
- ✅ **NEW:** stunnel service for TLS termination (ports 1080/8118)
- ✅ **MODIFIED:** Xray uses Docker network (not host mode)
- ✅ **MODIFIED:** Xray inbounds are plaintext (localhost 10800/18118)
- ✅ **MODIFIED:** Certificates mounted to stunnel container
- ✅ **REMOVED:** Xray `/etc/letsencrypt` mount (stunnel handles TLS)
- ✅ **Architecture:** Client → stunnel (TLS) → Xray (plaintext) → Internet

### 4.6 Reverse Proxy Architecture (v4.2 - DEPRECATED)

**⚠️ DEPRECATED:** This section describes v4.2 architecture (before HAProxy unified).
**Current Implementation:** See Section 4.7 for v4.3 HAProxy architecture.

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
│        NGINX CONTAINER (familytraffic-nginx)           │
│  Multiple server blocks (one per domain):                  │
│                                                             │
│  Server 1: listen 8443 ssl; server_name proxy1.example.com│
│    - TLS Termination (Let's Encrypt cert 1)               │
│    - HTTP Basic Auth (credentials 1)                       │
│    - proxy_pass https://target1-ip (DIRECT, resolved IPv4)│
│    - error_log ONLY (no access_log)                        │
│                                                             │
│  Server 2: listen 8444 ssl; server_name proxy2.example.com│
│    - TLS Termination (Let's Encrypt cert 2)               │
│    - HTTP Basic Auth (credentials 2)                       │
│    - proxy_pass https://target2-ip (DIRECT, resolved IPv4)│
│                                                             │
│  Server 3: listen 9443 ssl; server_name proxy3.example.com│
│    - TLS Termination (Let's Encrypt cert 3)               │
│    - HTTP Basic Auth (credentials 3)                       │
│    - proxy_pass https://target3-ip (DIRECT, resolved IPv4)│
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ 3. HTTPS (upstream SSL, hardcoded IPv4)
                      ↓
┌─────────────────────────────────────────────────────────────┐
│     TARGET SITES (target1.com, target2.com, ...)          │
└─────────────────────────────────────────────────────────────┘

SECURITY LAYERS:
  ✅ TLS 1.3 Encryption (Nginx)
  ✅ HTTP Basic Auth (Nginx)
  ✅ IPv4-only resolution (prevents IPv6 unreachable errors)
  ✅ IP monitoring (auto-update when DNS changes)
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
# /opt/familytraffic/config/reverse-proxy/myproxy.example.com.conf
# v5.2+: Direct proxy to target site (NO Xray inbound)

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

    # Direct proxy to target site (v5.2+)
    location / {
        # IPv4-only proxy_pass (resolved at config generation time)
        # Auto-monitored by vless-monitor-reverse-proxy-ips cron job
        proxy_pass https://1.2.3.4;  # Resolved IPv4 of blocked-site.com
        resolver 8.8.8.8 ipv4=on valid=300s;
        resolver_timeout 5s;
        proxy_http_version 1.1;

        # SSL settings for upstream (target site)
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_ssl_server_name on;  # Enable SNI for upstream

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

**⚠️ DEPRECATED - Xray Inbound Configuration (v4.2 only)**

This section is kept for historical reference only. **v5.2+ uses direct proxy** (Nginx → Target Site) without Xray inbound.

**Current Implementation (v5.2+):**
- Nginx proxies directly to target site via `proxy_pass https://target-ip`
- IPv4 resolution at config generation time (prevents IPv6 unreachable errors)
- IP monitoring via cron job (auto-update when DNS changes)
- See Section 4.7 for current architecture

#### 4.6.3 Port Mapping Strategy (v4.3+)

Each reverse proxy domain gets its own unique port mapping:

```
Public Access     →    HAProxy (SNI)    →    Nginx Backend    →    Target Site
https://domain    →    Port 443         →    localhost:9443   →    https://target-ip
```

**Nginx Backend Port Allocation:**
- Base: 9443
- Domain N: 9443 + (N - 1)
- Range: 9443-9452 (10 backends max)

**Port Validation:**
- Reserved: 443 (HAProxy), 1080 (SOCKS5), 8118 (HTTP), 9000 (HAProxy stats)
- Backend ports: 9443-9452 (localhost-only, NOT exposed to internet)
- Min: 1024 (unprivileged)
- Max: 65535
- Max domains: 10 per server

#### 4.6.4 Docker Compose Integration

**Dynamic Port Mapping (v4.2):**

```yaml
services:
  nginx:
    container_name: familytraffic-nginx
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
      - familytraffic_net
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

### 4.7 HAProxy Unified Architecture (v4.3)

**Version:** 4.3.0
**Status:** Current Implementation
**Purpose:** Single HAProxy container for ALL TLS termination and routing

#### 4.7.1 Architectural Shift from v4.2

**v4.2 Architecture (stunnel + HAProxy dual setup):**
```
Port 443 (stunnel TLS termination)
  → HAProxy (SNI routing only)
    → VLESS Reality: Xray:8443
    → Reverse Proxies: Nginx:8443-8452

Ports 1080/8118 (stunnel TLS termination for proxies)
  → Xray plaintext proxies
```

**v4.3+ Architecture (HAProxy unified with parallel routing):**
```
5 Docker Containers (familytraffic_net bridge network):

                                    ┌─ Static ACL: SNI = vless.example.com
Client → HAProxy (SNI Router 443) ──┤   → backend xray_vless (Xray:8443, Reality TLS) → Internet
                                    │
                                    ├─ Dynamic ACLs: SNI = reverse proxy domains
                                    │   → backend nginx_<domain> (Nginx:9443-9452, HTTPS) → Internet
                                    │
                                    └─ No ACL match: unknown SNI
                                        → backend blackhole → DROP (security hardening)

Client → HAProxy (TLS Term 1080) ───→ backend xray_socks5_plaintext (Xray:10800) → Internet
Client → HAProxy (TLS Term 8118) ───→ backend xray_http_plaintext (Xray:18118) → Internet

Containers:
  - familytraffic-haproxy (HAProxy 2.8-alpine) - TLS termination + SNI routing
  - familytraffic (Xray 24.11.30) - VPN core + SOCKS5/HTTP proxy
  - familytraffic-nginx (Nginx Alpine) - Reverse proxy backends
  - familytraffic-certbot (profile: certbot) - ACME HTTP-01 challenges
  - familytraffic-fake-site (Nginx) - VLESS Reality fallback
```

**Key Changes:**
- ❌ **stunnel removed completely**
- ✅ **HAProxy handles all 3 ports** (443, 1080, 8118)
- ✅ **5 containers total** (1 HAProxy, 1 Xray, 3 Nginx variants)
- ✅ **Parallel routing** (HAProxy routes to Xray OR Nginx OR blackhole based on SNI)
- ✅ **Static ACL for VLESS** (explicit domain match, NOT default backend)
- ✅ **Blackhole backend** (drops unknown SNI for security)
- ✅ **Subdomain-based access** (https://domain, no port!)
- ✅ **Unified configuration, logging, monitoring**

#### 4.7.2 HAProxy Configuration Structure

**File:** `/opt/familytraffic/config/haproxy.cfg`

**3 Frontends:**

```haproxy
# Frontend 1: SNI Routing (port 443)
frontend https_sni_router
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # Static ACL for VLESS Reality (REQUIRED - explicit domain match)
    acl is_vless req_ssl_sni -i vless.example.com
    use_backend xray_vless if is_vless

    # === DYNAMIC_REVERSE_PROXY_ROUTES ===
    # (ACLs and use_backend directives added dynamically)
    # Example:
    #   acl is_claude req.ssl_sni -i claude.ikeniborn.ru
    #   use_backend nginx_claude if is_claude

    # Default: drop unknown SNI (security hardening)
    default_backend blackhole

# Frontend 2: SOCKS5 TLS Termination (port 1080)
frontend socks5_tls
    bind *:1080 ssl crt /etc/letsencrypt/live/example.com/combined.pem
    mode tcp
    default_backend xray_socks5_plaintext

# Frontend 3: HTTP Proxy TLS Termination (port 8118)
frontend http_proxy_tls
    bind *:8118 ssl crt /etc/letsencrypt/live/example.com/combined.pem
    mode tcp
    default_backend xray_http_plaintext
```

**Backends:**

```haproxy
# Backend for VLESS Reality (TCP passthrough, NO TLS termination)
backend xray_vless
    mode tcp
    server xray familytraffic:8443 check inter 10s fall 3 rise 2

# Backend for SOCKS5 (plaintext to Xray)
backend xray_socks5_plaintext
    mode tcp
    server xray familytraffic:10800 check inter 10s fall 3 rise 2

# Backend for HTTP Proxy (plaintext to Xray)
backend xray_http_plaintext
    mode tcp
    server xray familytraffic:18118 check inter 10s fall 3 rise 2

# Blackhole backend for unknown/invalid SNI (security hardening)
backend blackhole
    mode tcp
    # No servers configured - connections are dropped

# Dynamic Nginx backends (added via add_reverse_proxy_route())
backend nginx_claude
    mode tcp
    server nginx familytraffic-nginx:9443 check inter 10s fall 3 rise 2

backend nginx_proxy2
    mode tcp
    server nginx familytraffic-nginx:9444 check inter 10s fall 3 rise 2
```

**Stats Page:**

```haproxy
listen stats
    bind 127.0.0.1:9000  # Localhost only
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats show-legends
    stats auth admin:password
```

**SECURITY WARNING:**
- HAProxy config binds stats to `127.0.0.1:9000` (localhost only)
- However, `docker-compose.yml` exposes port as `"9000:9000"` which binds to `0.0.0.0:9000`
- **RECOMMENDATION:** Change docker-compose.yml to `"127.0.0.1:9000:9000"` (explicit localhost)
- **CURRENT MITIGATION:** UFW firewall blocks port 9000 by default
- **Access:** Use SSH tunnel for remote access: `ssh -L 9000:localhost:9000 user@server`

#### 4.7.3 Dynamic Routing Management

**Module:** `lib/haproxy_config_manager.sh`

**Key Functions:**

```bash
# Add reverse proxy route
add_reverse_proxy_route() {
    local domain="$1"
    local backend_port="$2"

    # 1. Add ACL: acl is_${sanitized_domain} req.ssl_sni -i ${domain}
    # 2. Add backend: backend nginx_${sanitized_domain}
    # 3. Add routing: use_backend nginx_${sanitized_domain} if is_${sanitized_domain}
    # 4. Validate config
    # 5. Graceful reload (haproxy -sf <old_pid>)
}

# Remove reverse proxy route
remove_reverse_proxy_route() {
    local domain="$1"

    # 1. Remove ACL line
    # 2. Remove backend section
    # 3. Remove use_backend line
    # 4. Validate config
    # 5. Graceful reload
}

# List active routes
list_haproxy_routes() {
    # Parse haproxy.cfg for active ACLs and backends
    # Returns: domain → backend_port mappings
}

# Graceful reload (zero downtime)
reload_haproxy() {
    local old_pid=$(cat /var/run/haproxy.pid)
    docker exec familytraffic-haproxy haproxy -f /etc/haproxy/haproxy.cfg -sf $old_pid
}
```

#### 4.7.4 Certificate Management for HAProxy

**combined.pem Format:**

```
-----BEGIN CERTIFICATE-----
(fullchain.pem contents)
-----END CERTIFICATE-----
-----BEGIN PRIVATE KEY-----
(privkey.pem contents)
-----END PRIVATE KEY-----
```

**Creation Workflow:**

1. **Certbot acquisition:** `certbot certonly --nginx -d domain.com`
2. **combined.pem creation:**
   ```bash
   cat /etc/letsencrypt/live/domain.com/fullchain.pem \
       /etc/letsencrypt/live/domain.com/privkey.pem \
       > /opt/familytraffic/certs/combined.pem
   chmod 600 /opt/familytraffic/certs/combined.pem
   ```
3. **HAProxy reload:** `reload_haproxy()`

**Module:** `lib/certificate_manager.sh`

**Functions:**
- `create_haproxy_combined_cert(domain)` - Creates combined.pem from Let's Encrypt certs
- `validate_haproxy_cert(combined_pem_path)` - Validates cert and key format
- `reload_haproxy_after_cert_update()` - Graceful HAProxy reload

**Renewal:**
- **Cron job:** `/etc/cron.d/familytraffic-cert-renew`
- **Script:** `scripts/familytraffic-cert-renew`
- **Frequency:** Daily check (certbot renew --quiet)
- **Post-hook:** Regenerate combined.pem + reload HAProxy

#### 4.7.5 Port Allocation Strategy (v4.3)

| Service | Port | Binding | Protocol | Backend |
|---------|------|---------|----------|---------|
| **HAProxy** | | | | |
| VLESS Reality | 443 | 0.0.0.0 | SNI Passthrough | Xray:8443 |
| SOCKS5 TLS | 1080 | 0.0.0.0 | TLS Termination | Xray:10800 |
| HTTP TLS | 8118 | 0.0.0.0 | TLS Termination | Xray:18118 |
| Stats Page | 9000 | 127.0.0.1 | HTTP | - |
| **Xray** | | | | |
| VLESS Reality | 8443 | 127.0.0.1 | Reality TLS | Internet |
| SOCKS5 | 10800 | 127.0.0.1 | Plaintext | Internet |
| HTTP | 18118 | 127.0.0.1 | Plaintext | Internet |
| **Nginx** | | | | |
| Reverse Proxies | 9443-9452 | 127.0.0.1 | HTTPS | Xray:10800 → Internet |

**Key Principles:**
- ✅ HAProxy: Public-facing (0.0.0.0), all TLS termination
- ✅ Xray/Nginx: Localhost-only (127.0.0.1), not exposed
- ✅ Port range 9443-9452 (NOT 8443-8452) for reverse proxies
- ✅ NO UFW rules for 9443-9452 (localhost-only, protected by HAProxy)

#### 4.7.6 Subdomain-Based Access (v4.3)

**Old (v4.2):** `https://claude.ikeniborn.ru:8443`
**New (v4.3):** `https://claude.ikeniborn.ru` ← NO PORT NUMBER

**How it works:**

1. **DNS:** `claude.ikeniborn.ru` → Server IP
2. **Client:** Connects to `https://claude.ikeniborn.ru` (port 443 implied)
3. **HAProxy Frontend (port 443):**
   - Inspects SNI (Server Name Indication)
   - Matches ACL: `req.ssl_sni -i claude.ikeniborn.ru`
   - Routes to backend: `nginx_claude` (Nginx:9443)
4. **Nginx (port 9443):**
   - Serves content or proxies to target
   - All on localhost (not exposed to internet)

**Benefits:**
- ✅ Cleaner URLs (no port numbers)
- ✅ Standard HTTPS port (443)
- ✅ Better UX (users expect https://domain)
- ✅ Works with browser bookmarks/autocomplete
- ✅ SSL/TLS "just works" (no warnings)

#### 4.7.7 Integration with Existing Services

**VLESS Reality:**
- ✅ Works unchanged (HAProxy SNI passthrough to Xray:8443)
- ✅ Reality protocol remains intact (no TLS termination)
- ✅ Client config unchanged

**SOCKS5/HTTP Proxies:**
- ✅ HAProxy terminates TLS (instead of stunnel)
- ✅ Xray receives plaintext (simpler config)
- ✅ Client URIs: `socks5s://` and `https://` (TLS via HAProxy)

**Reverse Proxies:**
- ✅ HAProxy SNI routing (instead of direct access)
- ✅ Subdomain-based (no port numbers)
- ✅ Nginx on localhost:9443-9452 (instead of 0.0.0.0:8443-8452)

**fail2ban:**
- ✅ Protects all 3 HAProxy frontends (443, 1080, 8118)
- ✅ Filter: `/etc/fail2ban/filter.d/haproxy-sni.conf`
- ✅ Jail: `/etc/fail2ban/jail.d/familytraffic-haproxy.conf`

#### 4.7.8 Comparison: v4.2 vs v4.3

| Feature | v4.2 (stunnel + HAProxy) | v4.3+ (HAProxy Unified) |
|---------|--------------------------|------------------------|
| **Containers** | 2 (stunnel + HAProxy) | 5 total (1 HAProxy, 1 Xray, 3 Nginx) |
| **TLS for VLESS** | stunnel termination | HAProxy SNI passthrough |
| **TLS for Proxies** | stunnel termination | HAProxy TLS termination |
| **TLS for Reverse Proxies** | Direct Nginx HTTPS | HAProxy SNI routing |
| **Port 443** | stunnel → HAProxy (SNI only) | HAProxy (SNI + passthrough) |
| **Reverse Proxy Access** | https://domain:8443 | https://domain (NO port!) |
| **Reverse Proxy Ports** | 8443-8452 (public) | 9443-9452 (localhost) |
| **Configuration** | 2 files (stunnel.conf + haproxy.cfg) | 1 file (haproxy.cfg) |
| **Logging** | 2 log streams | 1 unified log |
| **Stats/Monitoring** | HAProxy stats only | HAProxy stats (unified) |
| **Complexity** | Higher (2 layers) | Lower (1 layer) |
| **Maintenance** | 2 services to manage | 1 service to manage |

**Migration from v4.2:**
- ✅ Automatic (handled by `vless-install` update)
- ✅ Zero downtime (graceful transition)
- ✅ User data preserved (users, keys, reverse proxies)
- ✅ Backward compatible (existing clients work)

#### 4.7.9 Container Infrastructure (v4.3+)

**Total Containers:** 5 (familytraffic_net bridge network)

**1. familytraffic-haproxy (HAProxy 2.8-alpine)**
- **Purpose:** Unified TLS termination and SNI-based routing
- **Ports:**
  - 443 (SNI Router): VLESS Reality + Reverse Proxy subdomains
  - 1080 (SOCKS5 TLS): TLS termination → Xray plaintext
  - 8118 (HTTP TLS): TLS termination → Xray plaintext
  - 9000 (Stats): localhost only, HTTP stats page
- **Key Features:**
  - Static ACL for VLESS domain matching
  - Dynamic ACL management for reverse proxies
  - Blackhole backend for unknown SNI (security)
  - Graceful reload (zero downtime)
- **Lifecycle:** Always running

**2. familytraffic (Xray 24.11.30)**
- **Purpose:** VPN core + SOCKS5/HTTP proxy engine
- **Ports (Docker network only, NOT on host):**
  - 8443: VLESS Reality inbound
  - 10800: SOCKS5 proxy (plaintext, HAProxy terminates TLS)
  - 18118: HTTP proxy (plaintext, HAProxy terminates TLS)
- **Key Features:**
  - Reality protocol (TLS 1.3 masquerading)
  - Fallback to familytraffic-fake-site for invalid connections
  - Security: runs as user nobody, cap_drop: ALL
- **Lifecycle:** Always running

**3. familytraffic-nginx (Nginx Alpine)**
- **Purpose:** Site-specific reverse proxy backends for blocked websites
- **Ports (localhost only):**
  - 127.0.0.1:9443-9452 (max 10 domains)
  - Accessed via HAProxy SNI routing (NO direct exposure)
- **Key Features:**
  - HTTP Basic Auth per domain
  - Rate limiting (100 req/s per IP)
  - fail2ban integration
  - Security headers (HSTS, CSP, X-Frame-Options)
  - IPv4 hardcoding for target sites (prevents IPv6 issues)
- **Tmpfs mounts:** `/var/cache/nginx`, `/var/run` (uid=101, gid=101)
- **Lifecycle:** Always running

**4. familytraffic-certbot (Nginx Alpine)**
- **Purpose:** Temporary web server for ACME HTTP-01 challenges
- **Port:** 80 (network_mode: host)
- **Docker Compose Profile:** `certbot` (NOT started by default)
- **Usage:**
  ```bash
  # Start for certificate acquisition
  docker compose --profile certbot up -d certbot_nginx

  # Stop after certificate obtained
  docker compose stop certbot_nginx
  ```
- **Key Features:**
  - Serves `/.well-known/acme-challenge/` from `/var/www/certbot`
  - Redirects all other requests to HTTPS
  - Network mode: host (direct access to port 80 without HAProxy)
- **Lifecycle:** On-demand only (during cert acquisition/renewal)

**5. familytraffic-fake-site (Nginx Alpine)**
- **Purpose:** VLESS Reality fallback - shows legitimate website for invalid VPN connections
- **Access:** Only via Xray fallback (internal, NOT public)
- **Key Features:**
  - Static HTML page mimicking normal website
  - Masks VPN server as regular HTTPS site
  - Critical for Reality protocol stealth
- **Tmpfs mounts:** `/var/cache/nginx`, `/var/run` (uid=101, gid=101)
- **Lifecycle:** Always running

**Port Exposure Summary:**

| Container | Exposed on Host | Docker Network Only | Access Method |
|-----------|-----------------|---------------------|---------------|
| familytraffic-haproxy | 443, 1080, 8118, 9000 | - | Direct (public) |
| familytraffic | - | 8443, 10800, 18118 | Via HAProxy |
| familytraffic-nginx | 127.0.0.1:9443-9452 | - | Via HAProxy SNI |
| familytraffic-certbot | 80 (on-demand) | - | Direct (temp) |
| familytraffic-fake-site | - | Internal | Via Xray fallback |

**IMPORTANT:** Xray ports (8443, 10800, 18118) use `expose:` NOT `ports:` in docker-compose.yml, preventing direct host access. All traffic MUST go through HAProxy for TLS termination and routing.

---

### 4.8 External Proxy Architecture (v5.23, Enhanced v5.33)

**Version:** 5.33.0 (TLS Server Name validation & auto-activation UX)
**Status:** Current Implementation
**Purpose:** Upstream proxy chaining for additional anonymity and policy compliance

#### 4.8.1 Architecture Overview

**Traffic Flow:**
```
Client → HAProxy (TLS) → Xray (VPN Core) → External SOCKS5s/HTTPS Proxy → Internet
```

**Key Components:**
1. **External Proxy Manager** (lib/external_proxy_manager.sh)
2. **Xray Routing Manager** (lib/xray_routing_manager.sh)
3. **CLI Tool** (scripts/familytraffic-external-proxy)
4. **Proxy Database** (/opt/familytraffic/config/external_proxy.json)

#### 4.8.2 Detailed Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                   │
└────────────────────┬─────────────────────────────────────────────────┘
                     │
                     │ (Traffic from target sites)
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│            External SOCKS5s/HTTPS Proxy                              │
│            (User-configured upstream proxy)                          │
│                                                                      │
│  Examples:                                                           │
│   - Commercial proxy service (Bright Data, Oxylabs)                 │
│   - Corporate proxy (company policy)                                │
│   - Privacy proxy (additional anonymity layer)                      │
│                                                                      │
│  Configuration:                                                      │
│   - Protocol: socks5s (TLS 1.3) or https                            │
│   - Authentication: username + password                             │
│   - Retry: 3 attempts, exponential backoff (2x)                     │
└────────────────────┬─────────────────────────────────────────────────┘
                     │
                     │ (Xray outbound: external-proxy)
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Xray Container (familytraffic)                       │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Outbounds (3 configured):                                  │    │
│  │                                                              │    │
│  │  1. "external-proxy" (tag) - DYNAMIC                        │    │
│  │     - Protocol: socks | http                                │    │
│  │     - Server: proxy.example.com:1080                        │    │
│  │     - TLS: enabled (for socks5s/https)                      │    │
│  │     - Auth: username + password                             │    │
│  │     - Generated by: generate_xray_outbound_json()           │    │
│  │                                                              │    │
│  │  2. "direct" (tag) - STATIC                                 │    │
│  │     - Protocol: freedom (direct internet)                   │    │
│  │     - Fallback if external proxy disabled                   │    │
│  │                                                              │    │
│  │  3. "blocked" (tag) - STATIC                                │    │
│  │     - Protocol: blackhole (drop packets)                    │    │
│  │     - Used for blocking specific domains/IPs                │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Routing Rules (mode-dependent):                            │    │
│  │                                                              │    │
│  │  Mode: "all-traffic" (default)                              │    │
│  │  ┌──────────────────────────────────────────────────┐      │    │
│  │  │ Rule 1:                                           │      │    │
│  │  │   Type: field                                     │      │    │
│  │  │   Network: tcp,udp                                │      │    │
│  │  │   OutboundTag: "external-proxy" ← ALL TRAFFIC    │      │    │
│  │  └──────────────────────────────────────────────────┘      │    │
│  │                                                              │    │
│  │  Mode: "disabled" (direct routing)                          │    │
│  │  ┌──────────────────────────────────────────────────┐      │    │
│  │  │ Rule 1:                                           │      │    │
│  │  │   Type: field                                     │      │    │
│  │  │   Network: tcp,udp                                │      │    │
│  │  │   OutboundTag: "direct" ← BYPASS PROXY          │      │    │
│  │  └──────────────────────────────────────────────────┘      │    │
│  │                                                              │    │
│  │  Mode: "selective" (future - domain/IP-based)               │    │
│  │  - Users can add custom rules via add_routing_rule()        │    │
│  └────────────────────────────────────────────────────────────┘    │
└────────────────────┬─────────────────────────────────────────────────┘
                     │
                     │ (HAProxy routes to Xray)
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  HAProxy Container (familytraffic-haproxy)                   │
│                                                                      │
│  Port 443:  VLESS Reality (SNI passthrough) → Xray:8443            │
│  Port 1080: SOCKS5 TLS termination → Xray:10800 (plaintext)        │
│  Port 8118: HTTP TLS termination → Xray:18118 (plaintext)          │
└────────────────────┬─────────────────────────────────────────────────┘
                     │
                     │ (Client connections)
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                           CLIENT                                     │
│                                                                      │
│  VLESS Client: connects to port 443 (Reality protocol)              │
│  SOCKS5 Client: connects to port 1080 (TLS encrypted)               │
│  HTTP Client: connects to port 8118 (TLS encrypted)                 │
└──────────────────────────────────────────────────────────────────────┘
```

#### 4.8.3 Data Flow Example (All-Traffic Mode)

**Scenario:** User browses https://google.com via VLESS VPN with external proxy enabled

```
1. CLIENT → HAProxy (Port 443)
   - VLESS Reality connection (TLS 1.3 masquerading as google.com)
   - SNI: vless.example.com

2. HAProxy → Xray (Port 8443, internal)
   - SNI routing: is_vless ACL matched
   - Backend: xray_vless
   - TCP passthrough (NO TLS termination for Reality)

3. Xray Inbound Processing
   - Protocol: VLESS (Reality variant)
   - Decrypts user request: GET https://google.com
   - Checks routing rules

4. Xray Routing Decision (all-traffic mode)
   - Rule: network=tcp,udp → outboundTag="external-proxy"
   - Matched! → Route to external proxy

5. Xray → External Proxy (proxy.example.com:1080)
   - Protocol: SOCKS5 with TLS (socks5s)
   - TLS handshake: ClientHello → ServerHello
   - SNI: proxy.example.com (server name validation)
   - Authentication: username + password (SOCKS5 auth)
   - Request: CONNECT google.com:443

6. External Proxy → Google
   - Proxy makes request to https://google.com
   - Response: 200 OK + HTML content

7. Response Flow (reverse path)
   External Proxy → Xray → HAProxy → Client
   - All layers decrypted/encrypted accordingly
   - Client receives google.com HTML
```

**Key Points:**
- **2 TLS layers**: Client↔Xray (Reality), Xray↔External Proxy (socks5s)
- **Traffic masquerading**: ISP sees HTTPS to vless.example.com (Reality stealth)
- **Proxy anonymity**: Google sees IP of external proxy (NOT VPN server IP)
- **Retry mechanism**: If proxy fails, Xray retries 3 times before fallback

#### 4.8.4 Configuration Files

**1. External Proxy Database (/opt/familytraffic/config/external_proxy.json)**

```json
{
  "enabled": true,
  "proxies": [
    {
      "id": "proxy-abc123",
      "type": "socks5s",
      "address": "proxy.example.com",
      "port": 1080,
      "username": "myuser",
      "password": "secretpass",
      "tls": {
        "enabled": true,
        "server_name": "proxy.example.com",
        "allow_insecure": false
      },
      "retry": {
        "enabled": true,
        "max_attempts": 3,
        "backoff_multiplier": 2
      },
      "test_status": "success",
      "latency": 45,
      "last_test_at": "2025-10-25T14:30:00Z",
      "active": true,
      "created_at": "2025-10-25T12:00:00Z"
    }
  ],
  "routing": {
    "mode": "all-traffic",
    "fallback": "retry-then-block"
  },
  "metadata": {
    "created": "2025-10-25T12:00:00Z",
    "last_modified": "2025-10-25T14:30:00Z",
    "version": "5.23.0"
  }
}
```

**2. Xray Outbound Configuration (Generated Dynamically)**

```json
{
  "outbounds": [
    {
      "protocol": "socks",
      "tag": "external-proxy",
      "settings": {
        "servers": [
          {
            "address": "proxy.example.com",
            "port": 1080,
            "users": [
              {
                "user": "myuser",
                "pass": "secretpass"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "proxy.example.com",
          "allowInsecure": false
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
```

**3. Xray Routing Rules (All-Traffic Mode)**

```json
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "external-proxy"
      }
    ]
  }
}
```

#### 4.8.5 Routing Modes

**Mode 1: all-traffic (Default)**
- All VPN traffic routed through external proxy
- Use case: Maximum anonymity, corporate policy compliance
- Performance impact: +50-150ms latency (proxy hop)

**Mode 2: disabled**
- All traffic routed directly (bypass proxy)
- Use case: Proxy unreachable, testing, cost optimization
- Performance impact: None (direct internet access)

**Mode 3: selective (Future Extension)**
- Domain/IP-based routing rules
- Use case: Route specific domains through proxy, others direct
- Example:
  ```json
  {
    "type": "field",
    "domain": ["netflix.com", "geosite:streaming"],
    "outboundTag": "external-proxy"
  },
  {
    "type": "field",
    "network": "tcp,udp",
    "outboundTag": "direct"
  }
  ```

#### 4.8.6 Retry Mechanism

**Configuration:**
- Max attempts: 3
- Backoff multiplier: 2x
- Timing: 1s, 2s, 4s (exponential)

**Failure Scenarios:**

**Scenario 1: Temporary Network Glitch**
```
Attempt 1: FAIL (timeout 10s) → Wait 1s
Attempt 2: FAIL (timeout 10s) → Wait 2s
Attempt 3: SUCCESS ✓
→ Traffic flows through proxy
```

**Scenario 2: Proxy Completely Down**
```
Attempt 1: FAIL (connection refused) → Wait 1s
Attempt 2: FAIL (connection refused) → Wait 2s
Attempt 3: FAIL (connection refused) → Wait 4s
→ Fallback action (based on routing.fallback):
  - "retry-then-block": Route to "blocked" outbound (DROP)
  - "retry-then-direct": Route to "direct" outbound (bypass proxy)
```

#### 4.8.7 CLI Management Interface

**Command:** `familytraffic-external-proxy`
**Symlink:** `/usr/local/bin/familytraffic-external-proxy` → `/opt/familytraffic/scripts/familytraffic-external-proxy`

**Workflow Example:**
```bash
# Step 1: Add new proxy
$ sudo familytraffic-external-proxy add

Select proxy type:
  1) socks5 (plaintext - localhost only)
  2) socks5s (TLS encrypted - RECOMMENDED)
  3) http (plaintext)
  4) https (TLS encrypted)
> 2

Enter proxy address: proxy.example.com
Enter proxy port [1080]: 1080
Enter username: myuser
Enter password: ********

Testing connection...
✓ Connection successful
  Latency: 45ms
  Test timestamp: 2025-10-25 14:30:00

Proxy added successfully!
  ID: proxy-abc123
  Type: socks5s
  Address: proxy.example.com:1080

Next steps:
  1. Activate: familytraffic-external-proxy switch proxy-abc123
  2. Enable routing: familytraffic-external-proxy enable

# Step 2: Activate proxy
$ sudo familytraffic-external-proxy switch proxy-abc123
✓ Proxy proxy-abc123 set as active
✓ Xray outbound updated

# Step 3: Enable routing
$ sudo familytraffic-external-proxy enable
✓ Routing rules updated (mode: all-traffic)
✓ Restarting Xray container...
✓ Xray container restarted successfully
✓ External proxy routing is now active

# Step 4: Verify status
$ sudo familytraffic status

External Proxy Status (v5.33):
  ✓ External Proxy ENABLED
  Active Proxy: proxy-abc123
    Type: socks5s
    Address: proxy.example.com:1080
    Last Test: success (45ms)
  Routing Mode: all-traffic
  Total Proxies: 1
```

#### 4.8.8 Module Architecture

**lib/external_proxy_manager.sh (841 lines, 11 functions)**

**Core Functions:**
1. `init_external_proxy_db()` - Create external_proxy.json during installation
2. `validate_proxy_config()` - Validate proxy type, address, port, credentials
3. `generate_proxy_id()` - Generate unique ID (proxy-[8 hex chars])
4. `add_external_proxy()` - Add new proxy to database with TLS/auth config
5. `list_external_proxies()` - Display all proxies in table format
6. `get_external_proxy()` - Retrieve proxy details by ID
7. `update_external_proxy()` - Update proxy fields (address, credentials, TLS)
8. `remove_external_proxy()` - Remove proxy from database
9. `set_active_proxy()` - Set active=true for selected proxy, false for others
10. `test_proxy_connectivity()` - HTTP GET через прокси с latency measurement
11. `generate_xray_outbound_json()` - Generate Xray outbound config JSON

**lib/xray_routing_manager.sh (419 lines, 7 functions)**

**Core Functions:**
1. `generate_routing_rules_json(mode, outbound_tag)` - Generate routing rules JSON
2. `enable_proxy_routing()` - Update xray_config.json routing section, set enabled=true
3. `disable_proxy_routing()` - Update routing to disabled mode, set enabled=false
4. `update_xray_outbounds()` - Add/update external-proxy outbound in xray_config.json
5. `remove_xray_outbound()` - Remove external-proxy outbound from config
6. `add_routing_rule()` - Add custom routing rule (for selective mode)
7. `get_routing_status()` - Display current routing configuration

#### 4.8.9 Integration Points

**Installation (lib/orchestrator.sh):**
```bash
# Step 5.6: Initialize external proxy database
if declare -f init_external_proxy_db >/dev/null 2>&1; then
    init_external_proxy_db || {
        echo -e "${YELLOW}Warning: Failed to initialize external proxy database${NC}"
    }
fi
```

**Status Display (scripts/vless):**
```bash
# External Proxy Status (v5.33)
echo ""
echo -e "${CYAN}External Proxy Status (v5.33):${NC}"
if [[ -f "${INSTALL_ROOT}/config/external_proxy.json" ]]; then
    local ext_proxy_enabled=$(jq -r '.enabled' "${INSTALL_ROOT}/config/external_proxy.json")

    if [[ "$ext_proxy_enabled" == "true" ]]; then
        echo -e "  ${GREEN}✓ External Proxy ENABLED${NC}"
        # ... display active proxy details ...
    else
        echo -e "  ${YELLOW}✗ External proxy routing is disabled (direct mode)${NC}"
    fi
fi
```

**Auto-Restart Integration (scripts/familytraffic-external-proxy):**
```bash
cmd_enable() {
    enable_proxy_routing

    # AUTO-RESTART XRAY CONTAINER
    echo -e "${CYAN}Restarting Xray container...${NC}"
    if docker restart familytraffic >/dev/null 2>&1; then
        sleep 3  # Wait for container health check
        echo -e "${GREEN}✓ Xray container restarted successfully${NC}"
    fi
}
```

#### 4.8.10 Security Considerations

**1. Credential Storage**
- Database file: 600 permissions (root:root)
- Passwords stored in plaintext (database-level encryption)
- CLI output: credentials masked (****) except in show command

**2. TLS Validation**
- Server name matching (SNI validation)
- Certificate verification (default: strict)
- Allow insecure option: only for testing (self-signed certs)

**3. Retry Security**
- Max 3 attempts per connection
- Exponential backoff (prevents DoS on upstream proxy)
- Configurable fallback action (block vs direct)

**4. Database Integrity**
- JSON schema validation on init/update
- Atomic writes (temp file + mv)
- Backup before destructive operations

#### 4.8.11 Performance Metrics

**Latency Impact:**
- Typical proxy hop: +50-100ms
- TLS handshake overhead: ~30ms (first connection)
- Connection pooling: subsequent requests faster

**Throughput:**
- Depends on upstream proxy bandwidth
- No additional overhead from Xray (efficient proxying)
- HAProxy layer: negligible impact (<1%)

**Resource Usage:**
- Memory: +5MB (Xray outbound config)
- CPU: <1% (routing decision overhead)
- Network: No additional bandwidth (transparent proxy)

#### 4.8.12 Troubleshooting

**Issue 1: Proxy Connection Fails**
```bash
# Test manually
$ sudo familytraffic-external-proxy test proxy-abc123
❌ Connection failed
  Error: Connection refused

# Check logs
$ docker logs familytraffic | tail -20
[Error] [proxy/socks] connection refused from proxy.example.com:1080

# Solution: Verify proxy credentials, network reachability
$ ping proxy.example.com
$ telnet proxy.example.com 1080
```

**Issue 2: Xray Not Routing Through Proxy**
```bash
# Check status
$ sudo familytraffic-external-proxy status
Routing: enabled
Active Proxy: proxy-abc123

# Verify Xray config
$ jq '.routing.rules[0].outboundTag' /opt/familytraffic/config/xray_config.json
"external-proxy"  # ← should match

# Solution: Restart Xray
$ sudo familytraffic-external-proxy enable  # auto-restarts
```

**Issue 3: Database Corruption**
```bash
# Validate JSON
$ jq . /opt/familytraffic/config/external_proxy.json
parse error: Invalid numeric literal at line 5, column 12

# Solution: Restore from backup
$ sudo cp /opt/familytraffic/config/external_proxy.json.bak \
          /opt/familytraffic/config/external_proxy.json
```

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

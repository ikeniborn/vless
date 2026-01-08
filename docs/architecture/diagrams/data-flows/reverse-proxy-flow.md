# Subdomain-Based Reverse Proxy Traffic Flow

**Purpose:** Visualize the complete reverse proxy flow for subdomain-based routing without port numbers

**Protocol:** HTTPS (TLS 1.3) with SNI-based routing

**Features:**
- SNI-based routing at HAProxy (NO TLS decryption)
- Subdomain-based access (https://subdomain.domain.com)
- NO port numbers required (clean URLs)
- TLS passthrough to Nginx reverse proxy backends
- Support for 10 concurrent subdomains (ports 9443-9452)
- Advanced features: OAuth2, WebSocket, CSP, custom headers

---

## Main Flow Diagram

```mermaid
graph TB
    Client[Client Browser]
    HAProxy[HAProxy<br/>Port 443 SNI Router]
    SNIDecision{SNI<br/>Inspection}
    VLESSBackend[Xray Backend<br/>VLESS Domain]
    NginxBackend[Nginx Backend<br/>Subdomain Match]
    FakeSite[Fake Site<br/>Unknown SNI]
    UpstreamApp[Upstream Application<br/>Target Service]

    Client -->|TLS 1.3 ClientHello<br/>SNI: app.example.com| HAProxy

    HAProxy --> SNIDecision

    SNIDecision -->|SNI = vless.example.com| VLESSBackend
    SNIDecision -->|SNI = app.example.com| NginxBackend
    SNIDecision -.->|SNI unknown| FakeSite

    NginxBackend -->|TLS Termination<br/>at Nginx| NginxBackend
    NginxBackend -->|HTTP/HTTPS Proxy| UpstreamApp

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style HAProxy fill:#fff4e1,stroke:#ff9900,stroke-width:2px
    style NginxBackend fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style UpstreamApp fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style VLESSBackend fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style FakeSite fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
```

---

## Detailed Step-by-Step Flow

### Step 1: Client HTTPS Request

```mermaid
sequenceDiagram
    participant Client
    participant DNS
    participant HAProxy

    Note over Client: User navigates to<br/>https://app.example.com

    Client->>DNS: Resolve app.example.com
    DNS->>Client: A record → server_ip

    Client->>HAProxy: TLS 1.3 ClientHello<br/>SNI: app.example.com<br/>Port 443
    Note over Client,HAProxy: SNI (Server Name Indication)<br/>sent in cleartext during handshake
```

**Key Concept:** SNI allows HAProxy to route based on domain name **without decrypting TLS**.

### Step 2: HAProxy SNI Inspection & Routing

```mermaid
graph TB
    HAProxyIn[HAProxy Port 443<br/>TLS Listener]
    SNIExtract[Extract SNI from<br/>TLS ClientHello]
    ACLMatch{ACL Matching}

    VLESSMatch[ACL: is_vless<br/>vless.example.com]
    AppMatch[ACL: is_app<br/>app.example.com]
    UnknownSNI[No ACL Match]

    RouteXray[Route to Xray:8443<br/>TLS Passthrough]
    RouteNginx[Route to Nginx:9443<br/>TLS Passthrough]
    RouteFake[Route to Fake Site:80<br/>HTTP]

    HAProxyIn --> SNIExtract
    SNIExtract --> ACLMatch

    ACLMatch --> VLESSMatch
    ACLMatch --> AppMatch
    ACLMatch --> UnknownSNI

    VLESSMatch --> RouteXray
    AppMatch --> RouteNginx
    UnknownSNI --> RouteFake

    style HAProxyIn fill:#fff4e1
    style SNIExtract fill:#ffe1f5
    style RouteXray fill:#e1e1f5
    style RouteNginx fill:#e1ffe1
    style RouteFake fill:#f5e1e1
```

**HAProxy Configuration Snippet:**
```haproxy
frontend https_sni_router
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # Static ACL for VLESS
    acl is_vless req_ssl_sni -i vless.example.com
    use_backend xray_vless if is_vless

    # Dynamic ACLs for reverse proxy subdomains
    # DYNAMIC_REVERSE_PROXY_ROUTES
    acl is_app req_ssl_sni -i app.example.com
    use_backend nginx_app if is_app
    # END_DYNAMIC_REVERSE_PROXY_ROUTES

    default_backend fake_site_fallback
```

**Important:** HAProxy uses `mode tcp` (TLS passthrough), NOT `mode http` (TLS termination).

### Step 3: Nginx TLS Termination & Backend Routing

```mermaid
graph TB
    NginxIn[Nginx Port 9443<br/>TLS Listener]
    TLSDecrypt[TLS Decryption<br/>Let's Encrypt Cert]
    RequestParse[Parse HTTP Request<br/>Host, Path, Headers]
    LocationMatch{Location<br/>Matching}

    ProxyPass[proxy_pass to<br/>Upstream Application]
    OAuth2Check[OAuth2 Validation<br/>if enabled]
    WebSocketUpgrade[WebSocket Upgrade<br/>if ws:// URL]

    NginxIn --> TLSDecrypt
    TLSDecrypt --> RequestParse
    RequestParse --> LocationMatch

    LocationMatch -->|Path match| ProxyPass
    LocationMatch -->|OAuth2 enabled| OAuth2Check
    LocationMatch -->|WebSocket| WebSocketUpgrade

    OAuth2Check -->|Valid token| ProxyPass
    OAuth2Check -.->|Invalid| Return401[Return 401]

    style NginxIn fill:#e1ffe1
    style TLSDecrypt fill:#ffe1f5
    style ProxyPass fill:#e1f5ff
    style OAuth2Check fill:#fff9e1
```

**Nginx Configuration Example** (`/opt/vless/config/reverse-proxy/app.example.com.conf`):
```nginx
server {
    listen 9443 ssl http2;
    server_name app.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self';" always;

    # Rate limiting
    limit_req zone=reverseproxy_app_example_com burst=200 nodelay;

    location / {
        proxy_pass https://backend.internal:8443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # OAuth2 validation (optional)
        # auth_request /oauth2/auth;
    }

    # OAuth2 endpoint (optional)
    # location = /oauth2/auth {
    #     internal;
    #     proxy_pass https://oauth2-proxy.internal/oauth2/auth;
    # }
}
```

### Step 4: Upstream Application Processing

```mermaid
sequenceDiagram
    participant Client
    participant HAProxy
    participant Nginx
    participant UpstreamApp

    Client->>HAProxy: TLS ClientHello (SNI: app.example.com)
    HAProxy->>Nginx: Passthrough TLS to Nginx:9443
    Nginx->>Nginx: Decrypt TLS with Let's Encrypt cert
    Nginx->>UpstreamApp: HTTP/HTTPS Proxy Request<br/>Headers: X-Real-IP, X-Forwarded-For

    UpstreamApp->>UpstreamApp: Process request
    UpstreamApp->>Nginx: HTTP Response

    Nginx->>Nginx: Add security headers<br/>(HSTS, CSP, etc.)
    Nginx->>Client: TLS-encrypted HTTP Response

    Note over Client: Clean URL experience:<br/>https://app.example.com/<br/>NO port numbers!
```

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Client Side"
        Client[Web Browser<br/>https://app.example.com]
    end

    subgraph "VPN Server - HAProxy Layer"
        HAProxy443[HAProxy Port 443<br/>SNI Router<br/>TLS Passthrough]
    end

    subgraph "VPN Server - Nginx Layer"
        Nginx9443[Nginx Port 9443<br/>TLS Terminator<br/>Reverse Proxy]
    end

    subgraph "Upstream Service"
        Backend[Backend Application<br/>Port 8443/80]
    end

    subgraph "Alternative Paths"
        XrayVLESS[Xray VLESS<br/>Port 8443]
        FakeSite[Fake Site<br/>Port 80]
    end

    Client -->|1. TLS ClientHello<br/>SNI: app.example.com| HAProxy443

    HAProxy443 -->|2a. SNI = VLESS| XrayVLESS
    HAProxy443 -->|2b. SNI = app.example.com<br/>TLS Passthrough| Nginx9443
    HAProxy443 -.->|2c. Unknown SNI| FakeSite

    Nginx9443 -->|3. Decrypt TLS<br/>proxy_pass| Backend

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:3px
    style HAProxy443 fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Nginx9443 fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Backend fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style XrayVLESS fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style FakeSite fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
```

---

## Port Allocation Strategy

### HAProxy Frontend (Public)
- **Port 443:** Unified HTTPS endpoint for ALL subdomains

### Nginx Backends (Internal, Docker network only)
- **9443-9452:** 10 backend slots for reverse proxy subdomains
- Each subdomain gets a unique Nginx server block on one of these ports
- HAProxy routes based on SNI to the corresponding port

**Example Allocation:**
| Subdomain | HAProxy ACL | Nginx Port | Backend |
|-----------|-------------|------------|---------|
| vless.example.com | is_vless | 8443 (Xray) | VLESS Reality |
| app.example.com | is_app | 9443 | Nginx → https://backend:8443 |
| api.example.com | is_api | 9444 | Nginx → http://api-server:80 |
| chat.example.com | is_chat | 9445 | Nginx → ws://chat-server:3000 |

**Why 10 slots?**
- Reasonable limit for small-to-medium deployments
- Each slot requires: DNS A record, Let's Encrypt cert, Nginx config, HAProxy ACL
- Can be expanded by adding more ports (9453-9462, etc.)

---

## Dynamic ACL Management

### Adding a New Subdomain

**Workflow:**
```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless-proxy CLI
    participant HAProxyMgr as haproxy_config_manager.sh
    participant NginxMgr as reverseproxy_db.sh
    participant HAProxy
    participant Nginx

    Admin->>CLI: vless-proxy add
    CLI->>Admin: Interactive wizard:<br/>1. Domain name?<br/>2. Target URL?<br/>3. Advanced options?

    Admin->>CLI: Provide: app.example.com<br/>Target: https://backend:8443

    CLI->>NginxMgr: add_reverse_proxy_domain()
    NginxMgr->>NginxMgr: Allocate free port (9443)
    NginxMgr->>NginxMgr: Generate Nginx config:<br/>/opt/vless/config/reverse-proxy/app.example.com.conf

    NginxMgr->>HAProxyMgr: update_haproxy_dynamic_acl()
    HAProxyMgr->>HAProxyMgr: Add ACL to DYNAMIC section:<br/>acl is_app req_ssl_sni -i app.example.com<br/>use_backend nginx_app if is_app

    HAProxyMgr->>HAProxy: Reload HAProxy (graceful)
    NginxMgr->>Nginx: Reload Nginx (graceful)

    HAProxy->>Admin: ✓ HAProxy ACL added
    Nginx->>Admin: ✓ Nginx config loaded
    CLI->>Admin: ✓ Reverse proxy added successfully
```

**HAProxy Dynamic ACL Section:**
```haproxy
# DYNAMIC_REVERSE_PROXY_ROUTES
acl is_app req_ssl_sni -i app.example.com
use_backend nginx_app if is_app

acl is_api req_ssl_sni -i api.example.com
use_backend nginx_api if is_api

acl is_chat req_ssl_sni -i chat.example.com
use_backend nginx_chat if is_chat
# END_DYNAMIC_REVERSE_PROXY_ROUTES
```

**Important:** This section is between markers, allowing automated updates without breaking static rules.

---

## Advanced Features

### Feature 1: OAuth2 Integration

```nginx
server {
    listen 9443 ssl http2;
    server_name app.example.com;

    # OAuth2 validation
    location / {
        auth_request /oauth2/auth;
        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;

        proxy_pass https://backend:8443;
        proxy_set_header X-User $user;
        proxy_set_header X-Email $email;
    }

    # OAuth2 proxy endpoint
    location = /oauth2/auth {
        internal;
        proxy_pass https://oauth2-proxy.internal:4180/oauth2/auth;
        proxy_set_header X-Original-URI $request_uri;
    }

    # OAuth2 callback
    location /oauth2/callback {
        proxy_pass https://oauth2-proxy.internal:4180/oauth2/callback;
    }
}
```

**Flow with OAuth2:**
1. Client requests `https://app.example.com/`
2. Nginx checks auth via `/oauth2/auth` (internal sub-request)
3. If not authenticated, redirect to OAuth2 provider (Google, GitHub, etc.)
4. User logs in, OAuth2 proxy validates token
5. Nginx adds `X-User` and `X-Email` headers to backend request

### Feature 2: WebSocket Support

```nginx
# WebSocket connection upgrade
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 9445 ssl http2;
    server_name chat.example.com;

    location / {
        proxy_pass http://chat-server:3000;

        # WebSocket-specific headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Prevent timeouts for long-lived connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
```

**WebSocket Flow:**
1. Client sends WebSocket upgrade request
2. Nginx detects `Upgrade: websocket` header
3. Nginx forwards upgrade to backend
4. Backend accepts, connection becomes bidirectional WebSocket

### Feature 3: Custom Security Headers

```nginx
server {
    listen 9443 ssl http2;
    server_name app.example.com;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;

    location / {
        proxy_pass https://backend:8443;
    }
}
```

### Feature 4: Rate Limiting

```nginx
# Define rate limit zone in http_context.conf
limit_req_zone $binary_remote_addr zone=reverseproxy_app_example_com:10m rate=100r/s;

server {
    listen 9443 ssl http2;
    server_name app.example.com;

    # Apply rate limiting
    limit_req zone=reverseproxy_app_example_com burst=200 nodelay;
    limit_req_status 429;

    location / {
        proxy_pass https://backend:8443;
    }
}
```

**Rate Limiting Behavior:**
- **rate=100r/s:** Average rate limit (100 requests per second)
- **burst=200:** Allow bursts up to 200 requests
- **nodelay:** Process burst requests immediately (no queueing)
- **429 status:** Return HTTP 429 Too Many Requests when limit exceeded

---

## DNS Configuration Requirements

**For each subdomain, configure DNS A record:**

```dns
; Main domain
example.com.           IN  A  203.0.113.10

; VLESS subdomain
vless.example.com.     IN  A  203.0.113.10

; Reverse proxy subdomains
app.example.com.       IN  A  203.0.113.10
api.example.com.       IN  A  203.0.113.10
chat.example.com.      IN  A  203.0.113.10
```

**Important:** All subdomains must point to the same server IP (HAProxy handles routing).

---

## Let's Encrypt Certificate Management

### Wildcard Certificate (Recommended)

**Advantages:**
- Single certificate for all subdomains (`*.example.com`)
- Simpler management (one renewal process)
- No need to re-issue when adding new subdomains

**Obtaining:**
```bash
sudo certbot certonly --dns-<provider> \
  -d example.com \
  -d *.example.com \
  --email admin@example.com \
  --agree-tos
```

**Requires:** DNS API access for DNS-01 challenge (Cloudflare, Route53, etc.)

### Individual Certificates (Alternative)

**Obtaining:**
```bash
sudo certbot certonly --standalone \
  -d app.example.com \
  --email admin@example.com \
  --agree-tos
```

**Disadvantages:**
- Separate certificate for each subdomain
- More renewal processes
- More complex HAProxy/Nginx configuration

---

## Performance Characteristics

**Latency Overhead:**
- HAProxy SNI inspection: < 1ms (no TLS decryption)
- Nginx TLS termination: ~2-3ms
- Nginx proxy_pass: ~1-2ms
- **Total:** ~4-6ms (minimal overhead)

**Throughput:**
- HAProxy: 10 Gbps+ (TLS passthrough is very efficient)
- Nginx: 1-5 Gbps (depends on backend response time)
- Bottleneck: Typically upstream application, not reverse proxy

**Scalability:**
- **Current:** 10 concurrent subdomains (ports 9443-9452)
- **Expandable:** Add more ports (9453-9962 = 100 slots total)
- **Horizontal Scaling:** Deploy multiple Nginx containers with load balancing

---

## Security Considerations

**TLS Security:**
- ✅ TLS 1.3 enforced (HAProxy passthrough + Nginx termination)
- ✅ Let's Encrypt trusted certificates
- ✅ HSTS headers for all subdomains
- ✅ Perfect Forward Secrecy (PFS)

**SNI Inspection Privacy:**
- ⚠️ SNI is sent in **cleartext** during TLS handshake
- ⚠️ Passive observers can see domain names (app.example.com)
- ⚠️ NOT DPI-resistant (unlike VLESS Reality)
- ✅ Encrypted SNI (ESNI) support planned (future TLS 1.4)

**Attack Surface:**
- ✅ HAProxy does NOT decrypt TLS (cannot inspect content)
- ✅ Nginx terminates TLS (can add security headers)
- ⚠️ Upstream application must be trusted (Nginx forwards all traffic)

---

## Comparison: Reverse Proxy vs VLESS

| Feature | Reverse Proxy (Subdomains) | VLESS Reality (Port 443) |
|---------|---------------------------|-------------------------|
| **URL Format** | https://app.example.com | vless://uuid@vless.example.com:443 |
| **Port Visibility** | NO port (clean URLs) | NO port (standard HTTPS) |
| **TLS Decryption** | Yes (at Nginx) | No (passthrough) |
| **Use Case** | Web apps, APIs, services | VPN tunnel |
| **DPI Resistance** | Low (SNI visible) | High (Reality masquerading) |
| **Client Support** | Any web browser | VLESS clients only |
| **Authentication** | OAuth2, HTTP Basic, etc. | UUID only |

---

## Troubleshooting

### Common Issues

**Issue 1: 503 Service Unavailable**
- **Cause:** Nginx backend not responding, or HAProxy cannot route
- **Debug:**
  ```bash
  # Check Nginx backend status
  docker logs vless_nginx_reverseproxy --tail 50

  # Check HAProxy stats
  curl http://127.0.0.1:9000/stats | grep nginx_app

  # Test Nginx config
  docker exec vless_nginx_reverseproxy nginx -t
  ```

**Issue 2: SNI routing not working**
- **Cause:** HAProxy dynamic ACL section missing or malformed
- **Debug:**
  ```bash
  # Check HAProxy config for dynamic section
  grep -A 10 "DYNAMIC_REVERSE_PROXY_ROUTES" /opt/vless/config/haproxy.cfg

  # Test HAProxy config
  haproxy -c -f /opt/vless/config/haproxy.cfg
  ```

**Issue 3: Certificate errors (NET::ERR_CERT_COMMON_NAME_INVALID)**
- **Cause:** Nginx using wrong certificate, or certificate missing subdomain
- **Debug:**
  ```bash
  # Check certificate subject
  openssl x509 -in /etc/letsencrypt/live/example.com/fullchain.pem -text | grep "Subject Alternative Name"

  # Verify Nginx SSL config
  docker exec vless_nginx_reverseproxy nginx -T | grep ssl_certificate
  ```

**Issue 4: WebSocket connection fails**
- **Cause:** Missing `Upgrade` and `Connection` headers in Nginx config
- **Fix:** Add WebSocket headers to `proxy_set_header` directives (see Feature 2 above)

---

## Related Documentation

- [data-flows.yaml](../../yaml/data-flows.yaml) - Complete reverse proxy flow specification
- [docker.yaml](../../yaml/docker.yaml) - HAProxy and Nginx container configurations
- [config.yaml](../../yaml/config.yaml) - HAProxy ACL and Nginx config relationships
- [cli.yaml](../../yaml/cli.yaml) - vless-proxy CLI commands
- [VLESS Reality Flow](vless-reality-flow.md) - VPN protocol flow
- [SOCKS5 Proxy Flow](socks5-proxy-flow.md) - SOCKS5 proxy flow
- [HTTP Proxy Flow](http-proxy-flow.md) - HTTP proxy flow

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v4.3+ HAProxy unified architecture)

# Port Mapping and Allocation Diagram

**Purpose:** Visualize complete port allocation strategy across all services

**Scope:** Public ports, internal ports

**Version:** v5.33 (single-container architecture)

> **Note:** In v5.33, HAProxy was removed. nginx (inside the `familytraffic` container with `network_mode: host`) handles all port binding. Ports 9000 (HAProxy stats), 9443-9452 (HAProxy/Nginx RP backends) no longer exist.

---

## Complete Port Mapping Overview

### Public to Internal Port Flow

```mermaid
graph TB
    subgraph "Public Internet"
        Client[Client Connections]
    end

    subgraph "Host Ports (Public) — all handled by nginx inside familytraffic"
        Port443[":443<br/>HTTPS/TLS<br/>nginx ssl_preread"]
        Port1080[":1080<br/>SOCKS5 TLS<br/>nginx TLS termination"]
        Port8118[":8118<br/>HTTP Proxy TLS<br/>nginx TLS termination"]
        Port80[":80<br/>HTTP<br/>certbot webroot"]
        Port8443[":8443<br/>MTProxy<br/>optional, familytraffic-mtproxy"]
    end

    subgraph "familytraffic container (network_mode: host)"
        subgraph "nginx (stream block)"
            NginxSNI[ssl_preread SNI router]
        end
        subgraph "nginx (http block)"
            NginxTLS1080[TLS terminator :1080]
            NginxTLS8118[TLS terminator :8118]
            NginxTier2[Tier 2 handler :8448]
            NginxWebroot[Webroot :80]
        end
        subgraph "xray (loopback only)"
            Xray8443[":8443<br/>VLESS Reality<br/>127.0.0.1"]
            Xray8448[":8448<br/>Tier 2 WS/XHTTP/gRPC<br/>127.0.0.1"]
            Xray10800[":10800<br/>SOCKS5 Plaintext<br/>127.0.0.1"]
            Xray18118[":18118<br/>HTTP Plaintext<br/>127.0.0.1"]
        end
    end

    subgraph "familytraffic-mtproxy (optional)"
        MTProxy8443[":8443<br/>MTProxy<br/>0.0.0.0"]
    end

    Client --> Port443
    Client --> Port1080
    Client --> Port8118
    Client -.-> Port80
    Client --> Port8443

    Port443 --> NginxSNI
    Port1080 --> NginxTLS1080
    Port8118 --> NginxTLS8118
    Port80 --> NginxWebroot
    Port8443 --> MTProxy8443

    NginxSNI -->|TLS Passthrough<br/>SNI match: VLESS domain| Xray8443
    NginxSNI -->|SNI match: Tier 2 subdomain| NginxTier2
    NginxTLS1080 -->|Plaintext| Xray10800
    NginxTLS8118 -->|Plaintext| Xray18118
    NginxTier2 -->|Plaintext WS/XHTTP/gRPC| Xray8448

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style NginxSNI fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Xray8443 fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Xray8448 fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style MTProxy8443 fill:#fff9e1,stroke:#cc9900,stroke-width:3px
```

---

## Detailed Port Allocation Table

### Public Ports (Exposed to Internet)

| Port | Protocol | Service | Handler | Purpose | Status |
|------|----------|---------|---------|---------|--------|
| **443** | TCP | HTTPS/TLS | nginx (stream block, inside `familytraffic`) | SNI routing: VLESS Reality + Tier 2 transports | Active |
| **1080** | TCP | SOCKS5s | nginx (http block, inside `familytraffic`) | SOCKS5 over TLS endpoint | Active |
| **8118** | TCP | HTTPS | nginx (http block, inside `familytraffic`) | HTTP proxy over TLS endpoint | Active |
| **80** | TCP | HTTP | nginx (http block, inside `familytraffic`) | certbot webroot for HTTP-01 ACME challenge | Active |
| **8443** | TCP | MTProxy | `familytraffic-mtproxy` container | Telegram MTProxy | Optional (v6.0+) |

**Removed ports (no longer exist in v5.33):**
- ~~Port 9000~~ — HAProxy stats, removed with HAProxy
- ~~Ports 9443-9452~~ — Nginx reverse proxy backends, removed with reverse proxy feature

---

### Internal Ports (loopback only, inside familytraffic container)

| Port | Protocol | Process | Binding | Purpose | Accessed By |
|------|----------|---------|---------|---------|-------------|
| **8443** | TCP | xray | 127.0.0.1:8443 | VLESS Reality inbound | nginx ssl_preread passthrough |
| **8448** | TCP | xray | 127.0.0.1:8448 | Tier 2 (WS/XHTTP/gRPC) inbound | nginx http block (port 443 → 8448) |
| **10800** | TCP | xray | 127.0.0.1:10800 | SOCKS5 plaintext inbound | nginx after TLS termination on :1080 |
| **18118** | TCP | xray | 127.0.0.1:18118 | HTTP plaintext inbound | nginx after TLS termination on :8118 |

---

## Port Binding Strategy

### Port 443: SNI-Based Routing (nginx ssl_preread, NO TLS Decryption)

```mermaid
graph TB
    Client[Client<br/>TLS 1.3 ClientHello<br/>SNI: vless.example.com]
    NginxStream[nginx Port 443<br/>stream block / ssl_preread]

    Decision{SNI Value}

    VLESS[SNI: vless.example.com<br/>VLESS domain]
    Tier2[SNI: ws.example.com<br/>Tier 2 subdomain]
    Unknown[SNI: anything else]

    RouteXray[TLS Passthrough<br/>→ 127.0.0.1:8443 Xray]
    RouteTier2[→ 127.0.0.1:8448<br/>nginx Tier 2 handler]
    RouteDrop[Dropped / 444]

    Client --> NginxStream
    NginxStream --> Decision

    Decision --> VLESS
    Decision --> Tier2
    Decision --> Unknown

    VLESS --> RouteXray
    Tier2 --> RouteTier2
    Unknown --> RouteDrop

    style Client fill:#e1f5ff
    style NginxStream fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Decision fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style RouteXray fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style RouteTier2 fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
```

**nginx stream configuration (ssl_preread map):**
```nginx
stream {
    map $ssl_preread_server_name $backend {
        vless.example.com     127.0.0.1:8443;
        ws.example.com        127.0.0.1:8448;
        xhttp.example.com     127.0.0.1:8448;
        grpc.example.com      127.0.0.1:8448;
        default               "";
    }

    server {
        listen 443;
        ssl_preread on;
        proxy_pass $backend;
    }
}
```

---

### Port 1080: SOCKS5 TLS Termination

```mermaid
sequenceDiagram
    participant Client
    participant Nginx1080 as nginx:1080 (http block)
    participant Xray10800 as xray:10800

    Client->>Nginx1080: TLS 1.3 Handshake
    Nginx1080->>Client: TLS ServerHello (Let's Encrypt cert)
    Client->>Nginx1080: Encrypted SOCKS5 request
    Nginx1080->>Nginx1080: Decrypt TLS 1.3
    Nginx1080->>Xray10800: Forward plaintext SOCKS5 to 127.0.0.1:10800
    Xray10800->>Xray10800: Authenticate & route
    Xray10800->>Nginx1080: SOCKS5 response
    Nginx1080->>Nginx1080: Encrypt with TLS 1.3
    Nginx1080->>Client: Encrypted response
```

**nginx configuration (port 1080):**
```nginx
server {
    listen 1080 ssl;
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:10800;
    }
}
```

---

### Port 8118: HTTP Proxy TLS Termination

```mermaid
sequenceDiagram
    participant Client
    participant Nginx8118 as nginx:8118 (http block)
    participant Xray18118 as xray:18118

    Client->>Nginx8118: TLS 1.3 Handshake
    Nginx8118->>Client: TLS ServerHello (Let's Encrypt cert)
    Client->>Nginx8118: Encrypted HTTP CONNECT request
    Nginx8118->>Nginx8118: Decrypt TLS 1.3
    Nginx8118->>Xray18118: Forward plaintext HTTP to 127.0.0.1:18118
    Xray18118->>Xray18118: Authenticate & establish tunnel
    Xray18118->>Nginx8118: HTTP response
    Nginx8118->>Nginx8118: Encrypt with TLS 1.3
    Nginx8118->>Client: Encrypted response
```

**nginx configuration (port 8118):**
```nginx
server {
    listen 8118 ssl;
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:18118;
    }
}
```

---

## Port Conflict: xray :8443 vs MTProxy :8443

**No conflict** — different binding interfaces:
- xray: `127.0.0.1:8443` (loopback only, inside `familytraffic` container which uses `network_mode: host`)
- MTProxy: `0.0.0.0:8443` (public, in separate `familytraffic-mtproxy` container)

```mermaid
graph TB
    subgraph "Port 8443 Bindings"
        XrayBind[xray VLESS<br/>Binds to: 127.0.0.1:8443<br/>Accessible: loopback only<br/>Reached via: nginx ssl_preread on :443]
        MTProxyBind[MTProxy<br/>Binds to: 0.0.0.0:8443<br/>Scope: Public internet<br/>Separate container]
    end

    subgraph "Traffic Flow"
        VLESSClient[VLESS Client] -->|Port 443| NginxStream[nginx stream :443]
        NginxStream -->|ssl_preread passthrough<br/>127.0.0.1:8443| XrayBind

        TelegramClient[Telegram Client] -->|Port 8443 direct| MTProxyBind
    end

    style XrayBind fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style MTProxyBind fill:#fff9e1,stroke:#cc9900,stroke-width:3px
```

---

## Firewall Rules (UFW)

### Required Port Openings

```bash
# Essential ports
sudo ufw allow 443/tcp comment "HTTPS/TLS (VLESS + Tier 2 transports)"
sudo ufw allow 1080/tcp comment "SOCKS5 over TLS"
sudo ufw allow 8118/tcp comment "HTTP Proxy over TLS"

# Certificate validation (webroot — nginx always running on port 80)
sudo ufw allow 80/tcp comment "HTTP (Let's Encrypt webroot)"

# MTProxy (optional v6.0+)
sudo ufw allow 8443/tcp comment "Telegram MTProxy"

# No firewall rules needed for internal loopback ports:
# 8443 (xray VLESS), 8448 (xray Tier 2), 10800 (xray SOCKS5), 18118 (xray HTTP)
# These are on 127.0.0.1 only and are NOT exposed to the network.
```

---

## Port Usage Matrix

### Summary Table

| Port | Public? | Handler | Binding | Protocol | TLS | Purpose |
|------|---------|---------|---------|----------|-----|---------|
| 443 | Yes | nginx stream (inside `familytraffic`) | 0.0.0.0:443 | TCP | Passthrough (ssl_preread) | VLESS + Tier 2 SNI routing |
| 1080 | Yes | nginx http (inside `familytraffic`) | 0.0.0.0:1080 | TCP | Termination | SOCKS5 over TLS |
| 8118 | Yes | nginx http (inside `familytraffic`) | 0.0.0.0:8118 | TCP | Termination | HTTP Proxy over TLS |
| 80 | Yes | nginx http (inside `familytraffic`) | 0.0.0.0:80 | HTTP | None | certbot webroot ACME |
| 8443 | Yes (optional) | `familytraffic-mtproxy` | 0.0.0.0:8443 | TCP | Fake-TLS | Telegram MTProxy |
| 8443 | No | xray (inside `familytraffic`) | 127.0.0.1:8443 | TCP | Passthrough | VLESS Reality (loopback) |
| 8448 | No | xray (inside `familytraffic`) | 127.0.0.1:8448 | TCP | None | Tier 2 WS/XHTTP/gRPC (loopback) |
| 10800 | No | xray (inside `familytraffic`) | 127.0.0.1:10800 | TCP | None | SOCKS5 plaintext (loopback) |
| 18118 | No | xray (inside `familytraffic`) | 127.0.0.1:18118 | TCP | None | HTTP plaintext (loopback) |

**Removed (no longer exist in v5.33):**
- ~~9000~~ — HAProxy stats
- ~~9443-9452~~ — Nginx reverse proxy backends

---

## Related Documentation

- [Docker Topology](docker-topology.md) - Complete container architecture
- [docker.yaml](../../yaml/docker.yaml) - Full port specifications
- [data-flows diagrams](../data-flows/) - Traffic flow through ports
- [Filesystem Layout](filesystem-layout.md) - Configuration file locations

---

**Created:** 2026-01-07
**Updated:** 2026-02-26
**Version:** v5.33
**Status:** UPDATED — reflects single-container architecture, HAProxy removed

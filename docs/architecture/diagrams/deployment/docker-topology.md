# Docker Network Topology Diagram

**Purpose:** Visualize the complete Docker container architecture, network layout, and volume mounts

**Components:** 6 Docker containers, 1 bridge network, multiple volumes

**Version:** v5.26 (includes MTProxy v6.0+ planned container)

---

## Complete Docker Topology

### Full System Architecture

```mermaid
graph TB
    subgraph "Host Server (Ubuntu/Debian)"
        subgraph "Docker Network: familytraffic_net (172.20.0.0/16)"
            HAProxy[familytraffic-haproxy<br/>HAProxy 2.8-alpine<br/>IP: 172.20.0.2]
            Xray[familytraffic<br/>Xray 24.11.30<br/>IP: 172.20.0.3]
            NginxRP[familytraffic-nginx<br/>Nginx Alpine<br/>IP: 172.20.0.4]
            Certbot[familytraffic-certbot<br/>Nginx Alpine<br/>IP: 172.20.0.5<br/>On-demand only]
            FakeSite[familytraffic-fake-site<br/>Nginx Alpine<br/>IP: 172.20.0.6]
            MTProxy[familytraffic-mtproxy<br/>MTProxy Alpine<br/>IP: 172.20.0.7<br/>v6.0+ planned]
        end

        subgraph "Host Filesystem"
            OptVless[/opt/familytraffic/]
            LetsEncrypt[/etc/letsencrypt/]
        end

        subgraph "Host Ports (Public)"
            Port443[Port 443<br/>HTTPS/TLS]
            Port1080[Port 1080<br/>SOCKS5 TLS]
            Port8118[Port 8118<br/>HTTP Proxy TLS]
            Port80[Port 80<br/>HTTP<br/>On-demand]
            Port9000[Port 9000<br/>HAProxy Stats<br/>Localhost only]
            Port8443MT[Port 8443<br/>MTProxy<br/>v6.0+]
        end

        Internet[Internet]
    end

    Internet --> Port443
    Internet --> Port1080
    Internet --> Port8118
    Internet -.-> Port80
    Internet --> Port8443MT

    Port443 --> HAProxy
    Port1080 --> HAProxy
    Port8118 --> HAProxy
    Port80 -.-> Certbot
    Port9000 --> HAProxy
    Port8443MT --> MTProxy

    HAProxy -->|TLS Passthrough<br/>Port 8443| Xray
    HAProxy -->|TLS Passthrough<br/>Ports 9443-9452| NginxRP
    HAProxy -.->|HTTP Fallback<br/>Port 80| FakeSite

    Xray -.->|Fallback<br/>Invalid UUID| FakeSite

    OptVless --> HAProxy
    OptVless --> Xray
    OptVless --> NginxRP
    OptVless --> MTProxy
    LetsEncrypt --> HAProxy
    LetsEncrypt --> NginxRP

    style Internet fill:#e1f5ff,stroke:#0066cc,stroke-width:3px
    style HAProxy fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Xray fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style NginxRP fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style Certbot fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style FakeSite fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
    style MTProxy fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style OptVless fill:#e1f5ff
    style LetsEncrypt fill:#ffe1f5
```

---

## Detailed Container Specifications

### Container 1: familytraffic-haproxy (Unified TLS Termination & SNI Router)

```mermaid
graph TB
    HAProxyContainer[familytraffic-haproxy Container]

    subgraph "HAProxy Container Details"
        Image[Image: haproxy:2.8-alpine]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.2]

        PublicPorts[Public Ports:<br/>443 → 443<br/>1080 → 1080<br/>8118 → 8118]
        LocalhostPort[Localhost Port:<br/>9000 → 9000<br/>HAProxy Stats]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/config/haproxy.cfg → /etc/haproxy/haproxy.cfg<br/>/etc/letsencrypt/ → /etc/letsencrypt/<br/>/opt/familytraffic/logs/haproxy/ → /var/log/haproxy/]

        HealthCheck[Health Check:<br/>haproxy -c -f /etc/haproxy/haproxy.cfg]

        Restart[Restart: unless-stopped]
    end

    HAProxyContainer --> Image
    HAProxyContainer --> NetworkMode
    HAProxyContainer --> IP
    HAProxyContainer --> PublicPorts
    HAProxyContainer --> LocalhostPort
    HAProxyContainer --> Volumes
    HAProxyContainer --> HealthCheck
    HAProxyContainer --> Restart

    style HAProxyContainer fill:#fff4e1,stroke:#ff9900,stroke-width:3px
```

**Key Responsibilities:**
- Unified TLS termination for ports 1080 (SOCKS5) and 8118 (HTTP)
- SNI-based routing for port 443 (VLESS and reverse proxy)
- TLS passthrough to Xray (no decryption for VLESS)
- TLS passthrough to Nginx reverse proxy backends
- HAProxy stats dashboard on localhost:9000

---

### Container 2: familytraffic (VLESS Reality + SOCKS5 + HTTP Handler)

```mermaid
graph TB
    XrayContainer[familytraffic Container]

    subgraph "Xray Container Details"
        Image[Image: teddysun/xray:24.11.30]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.3]

        ExposedPorts[Exposed Ports<br/>Docker network only:<br/>8443 - VLESS Reality<br/>10800 - SOCKS5 plaintext<br/>18118 - HTTP plaintext]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/config/xray_config.json → /etc/xray/config.json<br/>/opt/familytraffic/logs/xray/ → /var/log/xray/]

        Environment[Environment:<br/>XRAY_VMESS_AEAD_FORCED=false]

        HealthCheck[Health Check:<br/>xray -test -config /etc/xray/config.json]

        Restart[Restart: unless-stopped]

        DependsOn[Depends On:<br/>familytraffic-haproxy]
    end

    XrayContainer --> Image
    XrayContainer --> NetworkMode
    XrayContainer --> IP
    XrayContainer --> ExposedPorts
    XrayContainer --> Volumes
    XrayContainer --> Environment
    XrayContainer --> HealthCheck
    XrayContainer --> Restart
    XrayContainer --> DependsOn

    style XrayContainer fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
```

**Key Responsibilities:**
- VLESS Reality protocol handler (port 8443, TLS passthrough from HAProxy)
- SOCKS5 handler (port 10800, plaintext from HAProxy TLS termination)
- HTTP proxy handler (port 18118, plaintext from HAProxy TLS termination)
- Per-user routing to external proxies (v5.24+)
- Fallback to fake site for invalid UUIDs

**Important:** Xray binds to `127.0.0.1:8443` (Docker network only), NOT public `0.0.0.0:8443`

---

### Container 3: familytraffic-nginx (Subdomain Reverse Proxy)

```mermaid
graph TB
    NginxRPContainer[familytraffic-nginx Container]

    subgraph "Nginx Reverse Proxy Container Details"
        Image[Image: nginx:alpine]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.4]

        ExposedPorts[Exposed Ports<br/>Localhost only:<br/>9443-9452 - Reverse proxy backends<br/>10 slots total]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/config/reverse-proxy/ → /etc/nginx/conf.d/<br/>/etc/letsencrypt/ → /etc/letsencrypt/<br/>/opt/familytraffic/logs/nginx-rp/ → /var/log/nginx/]

        HealthCheck[Health Check:<br/>nginx -t]

        Restart[Restart: unless-stopped]

        DependsOn[Depends On:<br/>familytraffic-haproxy]
    end

    NginxRPContainer --> Image
    NginxRPContainer --> NetworkMode
    NginxRPContainer --> IP
    NginxRPContainer --> ExposedPorts
    NginxRPContainer --> Volumes
    NginxRPContainer --> HealthCheck
    NginxRPContainer --> Restart
    NginxRPContainer --> DependsOn

    style NginxRPContainer fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
```

**Key Responsibilities:**
- Host subdomain-based reverse proxy server blocks
- TLS termination for reverse proxy domains
- Proxy requests to upstream application backends
- Support OAuth2, WebSocket, custom headers, rate limiting

---

### Container 4: familytraffic-certbot (Certificate Validation - On-Demand)

```mermaid
graph TB
    CertbotContainer[familytraffic-certbot Container]

    subgraph "Certbot Nginx Container Details"
        Image[Image: nginx:alpine]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.5]

        PublicPort[Public Port:<br/>80 → 80<br/>On-demand only]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/certbot-webroot/ → /var/www/html/<br/>/etc/letsencrypt/ → /etc/letsencrypt/]

        Purpose[Purpose:<br/>HTTP-01 challenge validation<br/>Serves /.well-known/acme-challenge/]

        Lifecycle[Lifecycle:<br/>Stopped by default<br/>Started during cert renewal<br/>Stopped after validation]
    end

    CertbotContainer --> Image
    CertbotContainer --> NetworkMode
    CertbotContainer --> IP
    CertbotContainer --> PublicPort
    CertbotContainer --> Volumes
    CertbotContainer --> Purpose
    CertbotContainer --> Lifecycle

    style CertbotContainer fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
```

**Key Responsibilities:**
- Serve HTTP-01 challenge files for Let's Encrypt validation
- Only runs during certificate renewal (on-demand)
- Automatically started/stopped by certbot

---

### Container 5: familytraffic-fake-site (Camouflage/Anti-Detection)

```mermaid
graph TB
    FakeSiteContainer[familytraffic-fake-site Container]

    subgraph "Fake Site Container Details"
        Image[Image: nginx:alpine]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.6]

        ExposedPort[Exposed Port<br/>Internal only:<br/>80]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/fake-site/ → /usr/share/nginx/html/]

        Purpose[Purpose:<br/>Fallback for invalid traffic<br/>SNI mismatch → serve generic site<br/>Invalid UUID → serve generic site]

        Restart[Restart: unless-stopped]
    end

    FakeSiteContainer --> Image
    FakeSiteContainer --> NetworkMode
    FakeSiteContainer --> IP
    FakeSiteContainer --> ExposedPort
    FakeSiteContainer --> Volumes
    FakeSiteContainer --> Purpose
    FakeSiteContainer --> Restart

    style FakeSiteContainer fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
```

**Key Responsibilities:**
- Serve generic website for unknown SNI (anti-probing)
- Serve generic website for invalid VLESS UUID (anti-probing)
- Make VPN server appear as normal website to scanners

---

### Container 6: familytraffic-mtproxy (Telegram MTProxy - v6.0+ Planned)

```mermaid
graph TB
    MTProxyContainer[familytraffic-mtproxy Container]

    subgraph "MTProxy Container Details"
        Image[Image: Custom Build<br/>docker/mtproxy/Dockerfile]
        NetworkMode[Network: familytraffic_net]
        IP[IP: 172.20.0.7]

        PublicPort[Public Port:<br/>8443 → 8443<br/>Binds to 0.0.0.0:8443]

        PortNote[Port Binding Note:<br/>MTProxy: 0.0.0.0:8443 public<br/>Xray: 127.0.0.1:8443 Docker network<br/>NO conflict different interfaces]

        Volumes[Volume Mounts:<br/>/opt/familytraffic/config/mtproxy/ → /etc/mtproxy/<br/>/opt/familytraffic/logs/mtproxy/ → /var/log/mtproxy/]

        Environment[Environment:<br/>MTPROXY_PORT=8443<br/>MTPROXY_WORKERS=2]

        HealthCheck[Health Check:<br/>curl http://localhost:8443/stats]

        Restart[Restart: unless-stopped]

        Status[Status:<br/>v6.0: Planned<br/>v6.1: Multi-user future]
    end

    MTProxyContainer --> Image
    MTProxyContainer --> NetworkMode
    MTProxyContainer --> IP
    MTProxyContainer --> PublicPort
    MTProxyContainer --> PortNote
    MTProxyContainer --> Volumes
    MTProxyContainer --> Environment
    MTProxyContainer --> HealthCheck
    MTProxyContainer --> Restart
    MTProxyContainer --> Status

    style MTProxyContainer fill:#fff9e1,stroke:#cc9900,stroke-width:2px
```

**Key Responsibilities:**
- Telegram MTProto proxy (v6.0+)
- Direct public port 8443 (separate from Xray)
- Single-user mode (v6.0), multi-user mode (v6.1 future)
- Fake-TLS support for additional stealth

**Important:** MTProxy and Xray both use port 8443 but with different binding interfaces:
- Xray: `127.0.0.1:8443` (Docker network only, accessed via HAProxy)
- MTProxy: `0.0.0.0:8443` (public, direct access)

---

## Docker Network Configuration

### familytraffic_net Bridge Network

```mermaid
graph LR
    subgraph "familytraffic_net (172.20.0.0/16)"
        Gateway[Gateway<br/>172.20.0.1]
        HAProxy[familytraffic-haproxy<br/>172.20.0.2]
        Xray[familytraffic<br/>172.20.0.3]
        NginxRP[familytraffic-nginx<br/>172.20.0.4]
        Certbot[familytraffic-certbot<br/>172.20.0.5]
        FakeSite[familytraffic-fake-site<br/>172.20.0.6]
        MTProxy[familytraffic-mtproxy<br/>172.20.0.7]
    end

    Gateway --> HAProxy
    Gateway --> Xray
    Gateway --> NginxRP
    Gateway --> Certbot
    Gateway --> FakeSite
    Gateway --> MTProxy

    style Gateway fill:#e1f5ff
```

**Network Configuration:**
```yaml
networks:
  familytraffic_net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**IP Allocation:**
| Container | IP Address | Purpose |
|-----------|------------|---------|
| Gateway | 172.20.0.1 | Docker bridge gateway |
| familytraffic-haproxy | 172.20.0.2 | HAProxy SNI router |
| familytraffic | 172.20.0.3 | Xray VLESS/SOCKS5/HTTP |
| familytraffic-nginx | 172.20.0.4 | Nginx reverse proxy |
| familytraffic-certbot | 172.20.0.5 | Certbot validation |
| familytraffic-fake-site | 172.20.0.6 | Fake site fallback |
| familytraffic-mtproxy | 172.20.0.7 | MTProxy (v6.0+) |

---

## Volume Mounts

### Persistent Storage Layout

```mermaid
graph TB
    HostFS[Host Filesystem]

    subgraph "/opt/familytraffic/"
        Config[config/]
        Data[data/]
        Logs[logs/]
        Scripts[scripts/]
        Lib[lib/]
        CertbotWebroot[certbot-webroot/]
        FakeSiteHTML[fake-site/]
    end

    subgraph "/etc/letsencrypt/"
        Live[live/]
        Archive[archive/]
        Renewal[renewal/]
    end

    HostFS --> Config
    HostFS --> Data
    HostFS --> Logs
    HostFS --> Scripts
    HostFS --> Lib
    HostFS --> CertbotWebroot
    HostFS --> FakeSiteHTML
    HostFS --> Live
    HostFS --> Archive
    HostFS --> Renewal

    style HostFS fill:#e1f5ff
    style Config fill:#ffe1f5
    style Data fill:#e1ffe1
    style Logs fill:#fff9e1
```

**Detailed Volume Mappings:**

| Host Path | Container Mount | Container(s) | Purpose |
|-----------|-----------------|--------------|---------|
| `/opt/familytraffic/config/haproxy.cfg` | `/etc/haproxy/haproxy.cfg` | HAProxy | HAProxy configuration |
| `/opt/familytraffic/config/xray_config.json` | `/etc/xray/config.json` | Xray | Xray configuration |
| `/opt/familytraffic/config/reverse-proxy/` | `/etc/nginx/conf.d/` | Nginx RP | Nginx reverse proxy configs |
| `/opt/familytraffic/config/mtproxy/` | `/etc/mtproxy/` | MTProxy | MTProxy configuration (v6.0+) |
| `/opt/familytraffic/data/` | (not mounted) | None | User database, client configs |
| `/opt/familytraffic/logs/haproxy/` | `/var/log/haproxy/` | HAProxy | HAProxy logs |
| `/opt/familytraffic/logs/xray/` | `/var/log/xray/` | Xray | Xray logs |
| `/opt/familytraffic/logs/nginx-rp/` | `/var/log/nginx/` | Nginx RP | Nginx reverse proxy logs |
| `/opt/familytraffic/logs/mtproxy/` | `/var/log/mtproxy/` | MTProxy | MTProxy logs (v6.0+) |
| `/opt/familytraffic/certbot-webroot/` | `/var/www/html/` | Certbot | ACME challenge files |
| `/opt/familytraffic/fake-site/` | `/usr/share/nginx/html/` | Fake Site | Generic website HTML |
| `/etc/letsencrypt/` | `/etc/letsencrypt/` | HAProxy, Nginx RP | TLS certificates |

---

## Container Dependencies

### Startup Order and Dependencies

```mermaid
graph TB
    Start[Docker Compose Start]

    HAProxyStart[Start familytraffic-haproxy]
    XrayStart[Start familytraffic]
    NginxRPStart[Start familytraffic-nginx]
    CertbotStart[Start familytraffic-certbot<br/>On-demand only]
    FakeSiteStart[Start familytraffic-fake-site]
    MTProxyStart[Start familytraffic-mtproxy<br/>v6.0+]

    Start --> HAProxyStart
    Start --> FakeSiteStart
    Start --> MTProxyStart

    HAProxyStart --> XrayStart
    HAProxyStart --> NginxRPStart
    HAProxyStart -.-> CertbotStart

    style Start fill:#e1f5ff
    style HAProxyStart fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style XrayStart fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style NginxRPStart fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style MTProxyStart fill:#fff9e1,stroke:#cc9900,stroke-width:2px
```

**Dependency Chain:**
1. **Independent:** HAProxy, Fake Site, MTProxy (can start in parallel)
2. **Depends on HAProxy:** Xray, Nginx Reverse Proxy
3. **On-Demand:** Certbot (only during certificate renewal)

---

## Health Checks

| Container | Health Check Command | Interval | Timeout | Retries |
|-----------|---------------------|----------|---------|---------|
| familytraffic-haproxy | `haproxy -c -f /etc/haproxy/haproxy.cfg` | 30s | 10s | 3 |
| familytraffic | `xray -test -config /etc/xray/config.json` | 30s | 10s | 3 |
| familytraffic-nginx | `nginx -t` | 30s | 10s | 3 |
| familytraffic-fake-site | `curl -f http://localhost` | 30s | 5s | 3 |
| familytraffic-mtproxy | `curl http://localhost:8443/stats` | 30s | 10s | 3 |

---

## Resource Limits (Recommended)

| Container | CPU Limit | Memory Limit | Notes |
|-----------|-----------|--------------|-------|
| familytraffic-haproxy | 1.0 | 512MB | High traffic handling |
| familytraffic | 2.0 | 1GB | Encryption/decryption intensive |
| familytraffic-nginx | 1.0 | 512MB | Moderate traffic |
| familytraffic-certbot | 0.5 | 256MB | On-demand only |
| familytraffic-fake-site | 0.5 | 256MB | Low traffic |
| familytraffic-mtproxy | 1.0 | 512MB | MTProto protocol handling (v6.0+) |

---

## Related Documentation

- [docker.yaml](../../yaml/docker.yaml) - Complete Docker specifications
- [Port Mapping Diagram](port-mapping.md) - Detailed port allocation
- [Filesystem Layout](filesystem-layout.md) - /opt/familytraffic/ structure
- [data-flows diagrams](../data-flows/) - Traffic flow through containers

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (includes MTProxy v6.0+ container)

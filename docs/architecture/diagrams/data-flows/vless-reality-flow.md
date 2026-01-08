# VLESS Reality Protocol Traffic Flow

**Purpose:** Visualize the complete VLESS Reality connection flow from client to internet destination

**Protocol:** VLESS over Reality (TLS 1.3 masquerading)

**Features:**
- DPI-resistant (mimics legitimate HTTPS traffic)
- TLS 1.3 passthrough at HAProxy (no decryption)
- UUID-based authentication
- Optional external proxy routing (v5.24+)

---

## Main Flow Diagram

```mermaid
graph TB
    Client[Client Device<br/>VLESS Reality Client]
    HAProxy[HAProxy<br/>Port 443 SNI Router]
    Xray[Xray<br/>Port 8443 VLESS]
    RoutingDecision{Routing<br/>Decision}
    ExtProxy[External Proxy<br/>SOCKS5s/HTTPS]
    Internet[Internet<br/>Target Site]
    FakeSite[Fake Site<br/>Fallback Nginx]

    Client -->|TLS 1.3 ClientHello<br/>SNI: vless.example.com<br/>Reality Protocol| HAProxy

    HAProxy -->|SNI Match<br/>TLS Passthrough<br/>NO decryption| Xray
    HAProxy -.->|SNI Mismatch<br/>Unknown Domain| FakeSite

    Xray -->|UUID Validation<br/>Reality Handshake<br/>Success| RoutingDecision
    Xray -.->|UUID Invalid OR<br/>Handshake Fail| FakeSite

    RoutingDecision -->|external_proxy_id SET<br/>v5.24+ Feature| ExtProxy
    RoutingDecision -->|external_proxy_id NULL<br/>Default Route| Internet

    ExtProxy -->|SOCKS5s/HTTPS<br/>Upstream Proxy| Internet

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style HAProxy fill:#fff4e1,stroke:#ff9900,stroke-width:2px
    style Xray fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style FakeSite fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
    style Internet fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style RoutingDecision fill:#fff9e1,stroke:#cc9900,stroke-width:2px
```

---

## Detailed Step-by-Step Flow

### Step 1: Client Initiation
```mermaid
sequenceDiagram
    participant Client
    participant HAProxy

    Note over Client: User connects via<br/>VLESS Reality client
    Client->>HAProxy: TLS 1.3 ClientHello<br/>SNI: vless.example.com<br/>Fingerprint: Chrome/Firefox
    Note over Client,HAProxy: Reality protocol mimics<br/>legitimate browser TLS
```

### Step 2: HAProxy SNI Inspection (NO TLS Decryption)
```mermaid
graph LR
    HAProxy[HAProxy SNI Router]
    CheckSNI{SNI Inspection}
    VLESS[vless.example.com?]
    ReverseProxy[Reverse Proxy<br/>subdomain?]
    Unknown[Unknown SNI?]

    ToXray[Route to Xray:8443<br/>TLS PASSTHROUGH]
    ToNginx[Route to Nginx:9443-9452<br/>TLS PASSTHROUGH]
    ToFake[Route to Fake Site:80]

    HAProxy --> CheckSNI
    CheckSNI --> VLESS
    CheckSNI --> ReverseProxy
    CheckSNI --> Unknown

    VLESS -->|Match| ToXray
    ReverseProxy -->|Match| ToNginx
    Unknown -->|No Match| ToFake

    style HAProxy fill:#fff4e1
    style ToXray fill:#e1ffe1
    style ToNginx fill:#e1f5ff
    style ToFake fill:#f5e1e1
```

### Step 3: Xray Reality Processing & Authentication
```mermaid
graph TB
    XrayIn[Xray Port 8443<br/>127.0.0.1]
    RealityHandshake{Reality Protocol<br/>Handshake}
    UUIDCheck{UUID<br/>Validation}

    Success[Authentication<br/>SUCCESS]
    Failure[Authentication<br/>FAILURE]
    Fallback[Fallback to<br/>Fake Site:80]

    XrayIn --> RealityHandshake
    RealityHandshake -->|TLS Fingerprint<br/>Valid| UUIDCheck
    RealityHandshake -.->|Fingerprint<br/>Invalid| Failure

    UUIDCheck -->|UUID in<br/>clients[] list| Success
    UUIDCheck -.->|UUID NOT<br/>in list| Failure

    Failure --> Fallback

    style Success fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Failure fill:#f5e1e1,stroke:#cc0000,stroke-width:3px
```

**Reality Protocol Details:**
- Mimics TLS connection to `www.microsoft.com:443`
- Server Name: `www.microsoft.com`
- Validates client TLS fingerprint (browser-like)
- On success: Decrypts inner VLESS payload
- On failure: Appears as failed HTTPS connection, redirects to fake site

### Step 4: Routing Decision (v5.24+ Per-User External Proxy)
```mermaid
graph TB
    Routing[Xray Routing Engine]
    CheckUser{User has<br/>external_proxy_id?}

    Rule1[Routing Rule 1:<br/>Per-User External Proxy]
    Rule2[Routing Rule 2:<br/>Default Direct]

    ExtProxyOut[Outbound:<br/>external-proxy<br/>SOCKS5s/HTTPS]
    DirectOut[Outbound:<br/>direct<br/>Freedom Protocol]

    Routing --> CheckUser

    CheckUser -->|external_proxy_id<br/>!= null| Rule1
    CheckUser -->|external_proxy_id<br/>== null| Rule2

    Rule1 --> ExtProxyOut
    Rule2 --> DirectOut

    style Rule1 fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style ExtProxyOut fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style DirectOut fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
```

**Routing Logic (from `xray_config.json`):**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["vless-in", "socks-in", "http-in"],
        "user": ["alice@vless.local", "bob@vless.local"],
        "outboundTag": "external-proxy"
      },
      {
        "type": "field",
        "outboundTag": "direct"
      }
    ]
  }
}
```

### Step 5: External Proxy Chain (Optional, v5.24+)
```mermaid
graph LR
    Xray[Xray<br/>external-proxy outbound]
    ProxyServer[External Proxy Server<br/>SOCKS5s or HTTPS]
    Internet[Internet Destination]

    Xray -->|Encrypted Connection<br/>SOCKS5s: TLS<br/>HTTPS: TLS| ProxyServer
    ProxyServer -->|Proxy Authentication<br/>username + password| ProxyServer
    ProxyServer -->|Forward to<br/>Destination| Internet

    Note1[Source IP visible<br/>to destination:<br/>PROXY IP]

    Internet -.-> Note1

    style Xray fill:#e1ffe1
    style ProxyServer fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style Internet fill:#e1e1f5
```

**Retry Logic:**
- Max attempts: 3
- Backoff: Exponential (1s, 2s, 4s)
- On all failures: Fallback to `direct` outbound (warn user)

### Step 6: Internet Destination
```mermaid
graph TB
    Destination[Target Website/Service]

    CheckRoute{Traffic Route?}

    ViaProxy[Via External Proxy<br/>Visible IP: Proxy Server]
    Direct[Direct from VPN<br/>Visible IP: VPN Server]

    Destination --> CheckRoute
    CheckRoute -->|external_proxy_id<br/>SET| ViaProxy
    CheckRoute -->|external_proxy_id<br/>NULL| Direct

    style ViaProxy fill:#ffe1f5
    style Direct fill:#e1ffe1
```

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Client Side"
        Client[VLESS Reality Client<br/>vless://uuid@domain:443]
    end

    subgraph "VPN Server - HAProxy Layer"
        HAProxy443[HAProxy Port 443<br/>SNI Router]
    end

    subgraph "VPN Server - Xray Layer"
        Xray8443[Xray Port 8443<br/>VLESS Reality Handler]
        Routing[Routing Rules<br/>Per-User Logic]
    end

    subgraph "Optional External Proxy"
        ExtProxy[External SOCKS5s/HTTPS<br/>Upstream Proxy]
    end

    subgraph "Internet"
        Target[Target Website<br/>example.com]
    end

    subgraph "Fallback Anti-Detection"
        Fake[Fake Nginx Site<br/>Camouflage Layer]
    end

    Client -->|1. TLS 1.3<br/>SNI: vless.example.com| HAProxy443
    HAProxy443 -->|2. Passthrough<br/>NO Decrypt| Xray8443
    Xray8443 -->|3. UUID Valid| Routing
    Xray8443 -.->|3. UUID Invalid| Fake

    Routing -->|4a. Direct Route| Target
    Routing -->|4b. Via Proxy| ExtProxy
    ExtProxy -->|5. Forward| Target

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:3px
    style HAProxy443 fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Xray8443 fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Routing fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style Target fill:#e1e1f5,stroke:#0000cc,stroke-width:3px
    style Fake fill:#f5e1e1,stroke:#cc0000,stroke-width:2px
```

---

## Performance Characteristics

**Latency Overhead:**
- HAProxy SNI routing: < 1ms
- Xray Reality handshake: 3-5ms
- Xray routing decision: < 1ms
- External proxy connection: 0ms (direct) or 50-200ms (with proxy)
- **Total:** < 10ms (direct) or 50-210ms (with external proxy)

**Throughput:**
- Limited by: VPN server bandwidth, external proxy bandwidth (if used)
- HAProxy: Hardware TLS acceleration (minimal overhead)
- Xray: Efficient protocol (minimal overhead)

---

## Security Features

**DPI Resistance:**
- ✅ Reality protocol mimics legitimate TLS to `www.microsoft.com`
- ✅ TLS 1.3 fingerprint matches real browsers (Chrome/Firefox)
- ✅ Traffic analysis shows HTTPS to Microsoft (not VPN)

**Authentication:**
- ✅ UUID-based (strong, unique per user)
- ✅ No password transmission (UUID embedded in protocol)
- ✅ Invalid UUID → Fallback to fake site (anti-probing)

**Encryption:**
- ✅ TLS 1.3 end-to-end
- ✅ No TLS decryption at HAProxy (preserves Reality protocol)
- ✅ Optional additional layer with external proxy TLS

---

## Key Configuration Files

**users.json** (User Database):
```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
      "email": "alice@vless.local",
      "flow": "xtls-rprx-vision",
      "external_proxy_id": null
    }
  ]
}
```

**xray_config.json** (VLESS Inbound):
```json
{
  "inbounds": [
    {
      "protocol": "vless",
      "port": 8443,
      "listen": "127.0.0.1",
      "settings": {
        "clients": [
          {
            "id": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
            "email": "alice@vless.local",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "vless_fake_site:80",
            "xver": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "<REALITY_PRIVATE_KEY>",
          "shortIds": ["", "0123456789abcdef"]
        }
      }
    }
  ]
}
```

**haproxy.cfg** (SNI Routing):
```
frontend https_sni_router
    bind *:443
    mode tcp
    tcp-request content accept if { req_ssl_hello_type 1 }

    acl is_vless req_ssl_sni -i vless.example.com
    use_backend xray_vless if is_vless

    default_backend fake_site_fallback

backend xray_vless
    mode tcp
    server xray 127.0.0.1:8443 check
```

---

## Related Documentation

- [data-flows.yaml](../../yaml/data-flows.yaml) - Complete VLESS Reality flow specification
- [docker.yaml](../../yaml/docker.yaml) - HAProxy and Xray container configurations
- [config.yaml](../../yaml/config.yaml) - Configuration file relationships
- [SOCKS5 Proxy Flow](socks5-proxy-flow.md) - Alternative protocol flow
- [HTTP Proxy Flow](http-proxy-flow.md) - HTTP proxy traffic flow

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v5.24+ per-user external proxy supported)

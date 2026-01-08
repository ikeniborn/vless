# SOCKS5 over TLS Proxy Traffic Flow

**Purpose:** Visualize the complete SOCKS5 proxy connection flow from client to internet destination

**Protocol:** SOCKS5 over TLS 1.3 (socks5s://)

**Features:**
- TLS termination at HAProxy (Let's Encrypt certificate)
- Username/password authentication
- Port 1080 unified endpoint
- Optional external proxy routing (v5.24+)

---

## Main Flow Diagram

```mermaid
graph TB
    Client[Client Device<br/>SOCKS5 Client]
    HAProxy[HAProxy<br/>Port 1080 TLS Terminator]
    Xray[Xray<br/>Port 10800 SOCKS5]
    RoutingDecision{Routing<br/>Decision}
    ExtProxy[External Proxy<br/>SOCKS5s/HTTPS]
    Internet[Internet<br/>Target Site]

    Client -->|TLS 1.3 Handshake<br/>socks5s://user:pass@server:1080| HAProxy

    HAProxy -->|TLS Decryption<br/>Let's Encrypt Cert<br/>Extract SOCKS5 Request| HAProxy
    HAProxy -->|Forward Plaintext SOCKS5<br/>to Internal Port| Xray

    Xray -->|Username/Password<br/>Authentication<br/>Success| RoutingDecision
    Xray -.->|Auth Failed| Client

    RoutingDecision -->|external_proxy_id SET<br/>v5.24+ Feature| ExtProxy
    RoutingDecision -->|external_proxy_id NULL<br/>Default Route| Internet

    ExtProxy -->|SOCKS5s/HTTPS<br/>Upstream Proxy| Internet

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style HAProxy fill:#fff4e1,stroke:#ff9900,stroke-width:2px
    style Xray fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style Internet fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
    style RoutingDecision fill:#fff9e1,stroke:#cc9900,stroke-width:2px
```

---

## Detailed Step-by-Step Flow

### Step 1: Client TLS Connection

```mermaid
sequenceDiagram
    participant Client
    participant HAProxy

    Note over Client: Configure SOCKS5 proxy<br/>socks5s://user:pass@server:1080
    Client->>HAProxy: TLS 1.3 ClientHello<br/>Port 1080
    HAProxy->>Client: ServerHello + Certificate<br/>(Let's Encrypt wildcard)
    Client->>HAProxy: TLS Handshake Complete<br/>Encrypted Channel Established
    Note over Client,HAProxy: All SOCKS5 traffic now<br/>encrypted with TLS 1.3
```

### Step 2: HAProxy TLS Termination

```mermaid
graph TB
    HAProxyIn[HAProxy Port 1080<br/>TLS Listener]
    TLSDecrypt[TLS Decryption Layer]
    CertValidation{Certificate<br/>Validation}
    ExtractSOCKS5[Extract SOCKS5<br/>Request]
    ForwardXray[Forward to Xray<br/>Port 10800 Plaintext]

    HAProxyIn --> TLSDecrypt
    TLSDecrypt --> CertValidation
    CertValidation -->|Valid Cert| ExtractSOCKS5
    CertValidation -.->|Invalid Cert| Reject[Reject Connection]

    ExtractSOCKS5 --> ForwardXray

    style HAProxyIn fill:#fff4e1
    style TLSDecrypt fill:#ffe1f5
    style ExtractSOCKS5 fill:#e1ffe1
    style ForwardXray fill:#e1f5ff
    style Reject fill:#f5e1e1
```

**Key Details:**
- HAProxy listens on `0.0.0.0:1080` (public port)
- Uses Let's Encrypt wildcard certificate for TLS
- Decrypts TLS 1.3 traffic
- Extracts plaintext SOCKS5 request
- Forwards to Xray at `127.0.0.1:10800` (no TLS)

### Step 3: Xray SOCKS5 Authentication

```mermaid
graph TB
    XrayIn[Xray Port 10800<br/>SOCKS5 Inbound<br/>Plaintext]
    ParseRequest[Parse SOCKS5<br/>Auth Request]
    AuthCheck{Username/Password<br/>Validation}
    UserLookup[Lookup in<br/>xray_config.json<br/>clients[]]

    Success[Authentication<br/>SUCCESS]
    Failure[Authentication<br/>FAILURE]

    XrayIn --> ParseRequest
    ParseRequest --> AuthCheck
    AuthCheck --> UserLookup

    UserLookup -->|Credentials Match<br/>email field| Success
    UserLookup -.->|No Match| Failure

    Failure -.-> SendError[Send SOCKS5<br/>Auth Error]

    style Success fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Failure fill:#f5e1e1,stroke:#cc0000,stroke-width:3px
```

**SOCKS5 Authentication Details:**
- Method: Username/Password (SOCKS5 method 0x02)
- Username/Password stored in `xray_config.json`:
  ```json
  {
    "inbounds": [{
      "protocol": "socks",
      "port": 10800,
      "listen": "127.0.0.1",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "alice",
            "pass": "<PASSWORD_HASH>"
          }
        ]
      }
    }]
  }
  ```
- On success: Proceed to routing
- On failure: Return SOCKS5 error code 0x01 (general failure)

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

**Routing Configuration (from `xray_config.json`):**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks-in"],
        "user": ["alice@vless.local"],
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

### Step 5: SOCKS5 Request Handling

```mermaid
sequenceDiagram
    participant Client
    participant Xray
    participant Target

    Note over Client: Client sends SOCKS5 request<br/>CONNECT example.com:443

    Client->>Xray: SOCKS5 CONNECT Request<br/>Target: example.com:443
    Xray->>Xray: Route based on user rules

    alt Direct Route
        Xray->>Target: TCP Connection to<br/>example.com:443
        Target->>Xray: Connection Established
        Xray->>Client: SOCKS5 Reply: Success
        Note over Client,Target: Bidirectional data tunnel
    else External Proxy Route
        Xray->>ExtProxy: Forward via external proxy
        ExtProxy->>Target: TCP Connection
        Target->>ExtProxy: Connection Established
        ExtProxy->>Xray: Success
        Xray->>Client: SOCKS5 Reply: Success
        Note over Client,Target: Bidirectional tunnel via proxy
    end
```

**SOCKS5 Commands Supported:**
- `CONNECT` (0x01) - TCP connection (most common)
- `BIND` (0x02) - Incoming connections
- `UDP ASSOCIATE` (0x03) - UDP relay

### Step 6: Data Transfer

```mermaid
graph LR
    ClientApp[Client Application]
    SOCKS5Client[SOCKS5 Client]
    TLSTunnel[TLS 1.3 Tunnel<br/>HAProxy Port 1080]
    XraySOCKS[Xray SOCKS5<br/>Port 10800]
    Destination[Internet Destination]

    ClientApp -->|HTTP/HTTPS/Any TCP| SOCKS5Client
    SOCKS5Client -->|Encrypted<br/>TLS 1.3| TLSTunnel
    TLSTunnel -->|Decrypted<br/>Plaintext SOCKS5| XraySOCKS
    XraySOCKS -->|Direct or<br/>via External Proxy| Destination

    style ClientApp fill:#e1f5ff
    style SOCKS5Client fill:#e1f5ff
    style TLSTunnel fill:#fff4e1
    style XraySOCKS fill:#e1ffe1
    style Destination fill:#e1e1f5
```

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Client Side"
        Client[SOCKS5 Client<br/>socks5s://user:pass@server:1080]
    end

    subgraph "VPN Server - HAProxy Layer"
        HAProxy1080[HAProxy Port 1080<br/>TLS Terminator]
    end

    subgraph "VPN Server - Xray Layer"
        Xray10800[Xray Port 10800<br/>SOCKS5 Handler<br/>Plaintext]
        Routing[Routing Rules<br/>Per-User Logic]
    end

    subgraph "Optional External Proxy"
        ExtProxy[External SOCKS5s/HTTPS<br/>Upstream Proxy]
    end

    subgraph "Internet"
        Target[Target Website<br/>example.com]
    end

    Client -->|1. TLS 1.3<br/>Encrypted SOCKS5| HAProxy1080
    HAProxy1080 -->|2. Decrypt TLS<br/>Forward Plaintext| Xray10800
    Xray10800 -->|3. Auth Success| Routing

    Routing -->|4a. Direct Route| Target
    Routing -->|4b. Via Proxy| ExtProxy
    ExtProxy -->|5. Forward| Target

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:3px
    style HAProxy1080 fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Xray10800 fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Routing fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style Target fill:#e1e1f5,stroke:#0000cc,stroke-width:3px
```

---

## Performance Characteristics

**Latency Overhead:**
- HAProxy TLS termination: ~2-3ms
- Xray SOCKS5 processing: ~1ms
- Xray routing decision: < 1ms
- External proxy connection: 0ms (direct) or 50-200ms (with proxy)
- **Total:** ~5ms (direct) or 55-205ms (with external proxy)

**Throughput:**
- Limited by: TLS encryption/decryption speed, upstream bandwidth
- HAProxy TLS: Hardware acceleration support (minimal overhead)
- Xray SOCKS5: Efficient protocol (minimal overhead)

---

## Security Features

**TLS Security:**
- ✅ TLS 1.3 only (enforced at HAProxy)
- ✅ Let's Encrypt wildcard certificate (valid, trusted)
- ✅ Perfect Forward Secrecy (PFS)
- ✅ Strong cipher suites only

**Authentication:**
- ✅ Username/password required (SOCKS5 method 0x02)
- ✅ Credentials stored in Xray config (hashed)
- ✅ No anonymous access

**Encryption:**
- ✅ Client to HAProxy: TLS 1.3 encrypted
- ⚠️ HAProxy to Xray: Plaintext (internal Docker network only)
- ✅ Xray to External Proxy: TLS encrypted (SOCKS5s/HTTPS)

---

## Key Configuration Files

**HAProxy Configuration** (`/opt/vless/config/haproxy.cfg`):
```haproxy
frontend socks5_tls_frontend
    bind *:1080 ssl crt /etc/letsencrypt/live/${DOMAIN}/combined.pem alpn h2,http/1.1
    mode tcp
    default_backend xray_socks5_plaintext

backend xray_socks5_plaintext
    mode tcp
    server xray 127.0.0.1:10800 check
```

**Xray Configuration** (`/opt/vless/config/xray_config.json`):
```json
{
  "inbounds": [
    {
      "tag": "socks-in",
      "protocol": "socks",
      "port": 10800,
      "listen": "127.0.0.1",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "alice",
            "pass": "hashed_password_here"
          }
        ],
        "udp": true,
        "ip": "127.0.0.1"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks-in"],
        "user": ["alice@vless.local"],
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

**Users Database** (`/opt/vless/data/users.json`):
```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
      "email": "alice@vless.local",
      "socks_password": "hashed_password",
      "external_proxy_id": null
    }
  ]
}
```

---

## Client Configuration

**Generic SOCKS5 Client:**
```
Protocol: SOCKS5 over TLS (socks5s://)
Server: vless.example.com
Port: 1080
Username: alice
Password: ********
TLS: Enabled (verify certificate)
```

**Common SOCKS5 Clients:**
- **Firefox:** Settings → Network → Connection Settings → Manual proxy → SOCKS5 with TLS
- **cURL:** `curl --socks5 socks5s://alice:pass@vless.example.com:1080 https://example.com`
- **proxychains:** Configure `/etc/proxychains.conf` with `socks5 vless.example.com 1080 alice pass`
- **SSH:** `ssh -o ProxyCommand="nc -X 5 -x vless.example.com:1080 %h %p" user@target`

---

## Comparison: SOCKS5 vs VLESS Reality

| Feature | SOCKS5 (Port 1080) | VLESS Reality (Port 443) |
|---------|-------------------|-------------------------|
| **TLS Termination** | HAProxy (decrypts) | Xray (passthrough) |
| **Authentication** | Username/Password | UUID only |
| **DPI Resistance** | Standard TLS | Reality masquerading |
| **Port** | 1080 (custom) | 443 (HTTPS standard) |
| **Protocol Overhead** | Medium | Low |
| **Use Case** | Applications with SOCKS5 support | VPN clients, high stealth |

---

## Related Documentation

- [data-flows.yaml](../../yaml/data-flows.yaml) - Complete SOCKS5 flow specification
- [docker.yaml](../../yaml/docker.yaml) - HAProxy and Xray container configurations
- [config.yaml](../../yaml/config.yaml) - Configuration file relationships
- [VLESS Reality Flow](vless-reality-flow.md) - Alternative protocol flow
- [HTTP Proxy Flow](http-proxy-flow.md) - HTTP proxy traffic flow

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v5.24+ per-user external proxy supported)

# HTTP Proxy over TLS Traffic Flow

**Purpose:** Visualize the complete HTTP proxy connection flow from client to internet destination

**Protocol:** HTTP CONNECT over TLS 1.3 (https://)

**Features:**
- TLS termination at HAProxy (Let's Encrypt certificate)
- HTTP CONNECT tunneling method
- Port 8118 unified endpoint
- Basic authentication (username:password)
- Optional external proxy routing (v5.24+)

---

## Main Flow Diagram

```mermaid
graph TB
    Client[Client Device<br/>HTTP Proxy Client]
    HAProxy[HAProxy<br/>Port 8118 TLS Terminator]
    Xray[Xray<br/>Port 18118 HTTP Proxy]
    RoutingDecision{Routing<br/>Decision}
    ExtProxy[External Proxy<br/>SOCKS5s/HTTPS]
    Internet[Internet<br/>Target Site]

    Client -->|TLS 1.3 Handshake<br/>https://user:pass@server:8118| HAProxy

    HAProxy -->|TLS Decryption<br/>Let's Encrypt Cert<br/>Extract HTTP CONNECT| HAProxy
    HAProxy -->|Forward Plaintext HTTP<br/>to Internal Port| Xray

    Xray -->|Basic Auth<br/>Validation<br/>Success| RoutingDecision
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

    Note over Client: Configure HTTP proxy<br/>https://user:pass@server:8118
    Client->>HAProxy: TLS 1.3 ClientHello<br/>Port 8118
    HAProxy->>Client: ServerHello + Certificate<br/>(Let's Encrypt wildcard)
    Client->>HAProxy: TLS Handshake Complete<br/>Encrypted Channel Established
    Note over Client,HAProxy: All HTTP proxy traffic now<br/>encrypted with TLS 1.3
```

### Step 2: HAProxy TLS Termination

```mermaid
graph TB
    HAProxyIn[HAProxy Port 8118<br/>TLS Listener]
    TLSDecrypt[TLS Decryption Layer]
    CertValidation{Certificate<br/>Validation}
    ExtractHTTP[Extract HTTP<br/>CONNECT Request]
    ForwardXray[Forward to Xray<br/>Port 18118 Plaintext]

    HAProxyIn --> TLSDecrypt
    TLSDecrypt --> CertValidation
    CertValidation -->|Valid Cert| ExtractHTTP
    CertValidation -.->|Invalid Cert| Reject[Reject Connection]

    ExtractHTTP --> ForwardXray

    style HAProxyIn fill:#fff4e1
    style TLSDecrypt fill:#ffe1f5
    style ExtractHTTP fill:#e1ffe1
    style ForwardXray fill:#e1f5ff
    style Reject fill:#f5e1e1
```

**Key Details:**
- HAProxy listens on `0.0.0.0:8118` (public port)
- Uses Let's Encrypt wildcard certificate for TLS
- Decrypts TLS 1.3 traffic
- Extracts plaintext HTTP CONNECT request
- Forwards to Xray at `127.0.0.1:18118` (no TLS)

### Step 3: Xray HTTP Proxy Authentication

```mermaid
graph TB
    XrayIn[Xray Port 18118<br/>HTTP Inbound<br/>Plaintext]
    ParseRequest[Parse HTTP<br/>CONNECT Request]
    AuthCheck{Basic Auth<br/>Validation}
    UserLookup[Lookup in<br/>xray_config.json<br/>accounts[]]

    Success[Authentication<br/>SUCCESS]
    Failure[Authentication<br/>FAILURE]

    XrayIn --> ParseRequest
    ParseRequest --> AuthCheck
    AuthCheck --> UserLookup

    UserLookup -->|Credentials Match<br/>user + pass| Success
    UserLookup -.->|No Match| Failure

    Failure -.-> SendError[Send HTTP 407<br/>Proxy Auth Required]

    style Success fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Failure fill:#f5e1e1,stroke:#cc0000,stroke-width:3px
```

**HTTP Proxy Authentication Details:**
- Method: HTTP Basic Authentication (Proxy-Authorization header)
- Credentials stored in `xray_config.json`:
  ```json
  {
    "inbounds": [{
      "protocol": "http",
      "port": 18118,
      "listen": "127.0.0.1",
      "settings": {
        "accounts": [
          {
            "user": "alice",
            "pass": "<PASSWORD_HASH>"
          }
        ],
        "allowTransparent": false
      }
    }]
  }
  ```
- On success: Proceed to establish CONNECT tunnel
- On failure: Return HTTP 407 Proxy Authentication Required

### Step 4: HTTP CONNECT Tunneling

```mermaid
sequenceDiagram
    participant Client
    participant Xray
    participant Target

    Note over Client: Client sends HTTP CONNECT<br/>to establish tunnel

    Client->>Xray: CONNECT example.com:443 HTTP/1.1<br/>Proxy-Authorization: Basic base64(user:pass)
    Xray->>Xray: Validate credentials
    Xray->>Xray: Route based on user rules

    alt Direct Route
        Xray->>Target: TCP Connection to<br/>example.com:443
        Target->>Xray: Connection Established
        Xray->>Client: HTTP/1.1 200 Connection Established
        Note over Client,Target: Bidirectional data tunnel<br/>(Client encrypts with TLS)
        Client->>Target: TLS Handshake (end-to-end)
        Client->>Target: HTTPS Request
        Target->>Client: HTTPS Response
    else External Proxy Route
        Xray->>ExtProxy: Forward via external proxy
        ExtProxy->>Target: TCP Connection
        Target->>ExtProxy: Connection Established
        ExtProxy->>Xray: Success
        Xray->>Client: HTTP/1.1 200 Connection Established
        Note over Client,Target: Bidirectional tunnel via proxy
    end
```

**CONNECT Method Details:**
- HTTP CONNECT establishes a TCP tunnel
- After `200 Connection Established`, proxy becomes transparent
- Client encrypts traffic end-to-end (e.g., TLS for HTTPS)
- Proxy only sees encrypted bytes (no visibility into HTTPS content)

### Step 5: Routing Decision (v5.24+ Per-User External Proxy)

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
        "inboundTag": ["http-in"],
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

### Step 6: Data Transfer

```mermaid
graph LR
    ClientApp[Client Application<br/>Web Browser]
    HTTPProxyClient[HTTP Proxy Client]
    TLSTunnel[TLS 1.3 Tunnel<br/>HAProxy Port 8118]
    XrayHTTP[Xray HTTP Proxy<br/>Port 18118]
    TCPTunnel[TCP Tunnel<br/>via CONNECT]
    Destination[Internet Destination<br/>HTTPS Site]

    ClientApp -->|HTTP/HTTPS Request| HTTPProxyClient
    HTTPProxyClient -->|Encrypted TLS 1.3<br/>CONNECT Request| TLSTunnel
    TLSTunnel -->|Decrypted<br/>Plaintext HTTP| XrayHTTP
    XrayHTTP -->|TCP Tunnel<br/>Established| TCPTunnel
    TCPTunnel -->|Direct or<br/>via External Proxy| Destination

    style ClientApp fill:#e1f5ff
    style HTTPProxyClient fill:#e1f5ff
    style TLSTunnel fill:#fff4e1
    style XrayHTTP fill:#e1ffe1
    style TCPTunnel fill:#fff9e1
    style Destination fill:#e1e1f5
```

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Client Side"
        Client[HTTP Proxy Client<br/>https://user:pass@server:8118]
    end

    subgraph "VPN Server - HAProxy Layer"
        HAProxy8118[HAProxy Port 8118<br/>TLS Terminator]
    end

    subgraph "VPN Server - Xray Layer"
        Xray18118[Xray Port 18118<br/>HTTP Proxy Handler<br/>Plaintext]
        Routing[Routing Rules<br/>Per-User Logic]
    end

    subgraph "Optional External Proxy"
        ExtProxy[External SOCKS5s/HTTPS<br/>Upstream Proxy]
    end

    subgraph "Internet"
        Target[Target Website<br/>example.com]
    end

    Client -->|1. TLS 1.3<br/>Encrypted HTTP CONNECT| HAProxy8118
    HAProxy8118 -->|2. Decrypt TLS<br/>Forward Plaintext| Xray18118
    Xray18118 -->|3. Auth Success<br/>Establish Tunnel| Routing

    Routing -->|4a. Direct Route| Target
    Routing -->|4b. Via Proxy| ExtProxy
    ExtProxy -->|5. Forward| Target

    style Client fill:#e1f5ff,stroke:#0066cc,stroke-width:3px
    style HAProxy8118 fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style Xray18118 fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style Routing fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style Target fill:#e1e1f5,stroke:#0000cc,stroke-width:3px
```

---

## Performance Characteristics

**Latency Overhead:**
- HAProxy TLS termination: ~2-3ms
- Xray HTTP proxy processing: ~1ms
- HTTP CONNECT establishment: ~1-2ms
- Xray routing decision: < 1ms
- External proxy connection: 0ms (direct) or 50-200ms (with proxy)
- **Total:** ~5-7ms (direct) or 55-210ms (with external proxy)

**Throughput:**
- Limited by: TLS encryption/decryption speed, upstream bandwidth
- HAProxy TLS: Hardware acceleration support (minimal overhead)
- Xray HTTP: Efficient CONNECT tunneling (minimal overhead after tunnel establishment)

---

## Security Features

**TLS Security:**
- ✅ TLS 1.3 only (enforced at HAProxy)
- ✅ Let's Encrypt wildcard certificate (valid, trusted)
- ✅ Perfect Forward Secrecy (PFS)
- ✅ Strong cipher suites only

**Authentication:**
- ✅ HTTP Basic Authentication required (Proxy-Authorization header)
- ✅ Credentials stored in Xray config (hashed)
- ✅ No anonymous access

**Encryption Layers:**
- ✅ **Layer 1:** Client to HAProxy - TLS 1.3 encrypted
- ⚠️ **Layer 2:** HAProxy to Xray - Plaintext (internal Docker network only)
- ✅ **Layer 3:** Client to Target - End-to-end TLS (for HTTPS)
- ✅ **Layer 4:** Xray to External Proxy - TLS encrypted (SOCKS5s/HTTPS)

**Important:** HTTP proxy with CONNECT method provides end-to-end encryption for HTTPS traffic, but HTTP traffic is NOT encrypted beyond the HAProxy-Xray segment.

---

## Key Configuration Files

**HAProxy Configuration** (`/opt/familytraffic/config/haproxy.cfg`):
```haproxy
frontend http_proxy_tls_frontend
    bind *:8118 ssl crt /etc/letsencrypt/live/${DOMAIN}/combined.pem alpn h2,http/1.1
    mode tcp
    default_backend xray_http_plaintext

backend xray_http_plaintext
    mode tcp
    server xray 127.0.0.1:18118 check
```

**Xray Configuration** (`/opt/familytraffic/config/xray_config.json`):
```json
{
  "inbounds": [
    {
      "tag": "http-in",
      "protocol": "http",
      "port": 18118,
      "listen": "127.0.0.1",
      "settings": {
        "accounts": [
          {
            "user": "alice",
            "pass": "hashed_password_here"
          }
        ],
        "allowTransparent": false,
        "timeout": 300
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["http-in"],
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

**Users Database** (`/opt/familytraffic/data/users.json`):
```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
      "email": "alice@vless.local",
      "http_password": "hashed_password",
      "external_proxy_id": null
    }
  ]
}
```

---

## Client Configuration

**Generic HTTP Proxy Client:**
```
Protocol: HTTP CONNECT over TLS (https://)
Server: vless.example.com
Port: 8118
Username: alice
Password: ********
TLS: Enabled (verify certificate)
```

**Common HTTP Proxy Clients:**

**1. Web Browsers:**

**Firefox:**
```
Settings → Network Settings → Manual proxy configuration
→ HTTP Proxy: vless.example.com
→ Port: 8118
→ Use this proxy server for all protocols: ✓
→ Also use this proxy for HTTPS: ✓
```

**Chrome/Chromium (via command line):**
```bash
chromium --proxy-server="https://vless.example.com:8118" \
         --proxy-auth="alice:password"
```

**2. Command Line Tools:**

**cURL:**
```bash
# With authentication in URL
curl --proxy https://alice:password@vless.example.com:8118 \
     https://example.com

# With separate proxy-user flag
curl --proxy https://vless.example.com:8118 \
     --proxy-user alice:password \
     https://example.com
```

**wget:**
```bash
# Set via environment
export https_proxy="https://alice:password@vless.example.com:8118"
wget https://example.com
```

**3. System-Wide Configuration:**

**Linux (environment variables):**
```bash
export HTTP_PROXY="https://alice:password@vless.example.com:8118"
export HTTPS_PROXY="https://alice:password@vless.example.com:8118"
export NO_PROXY="localhost,127.0.0.1"
```

**macOS (System Preferences):**
```
System Preferences → Network → Advanced → Proxies
→ Secure Web Proxy (HTTPS): vless.example.com:8118
→ Proxy authentication: alice / password
```

**Windows (Internet Options):**
```
Internet Options → Connections → LAN settings → Proxy server
→ Address: vless.example.com:8118
→ Use the same proxy for all protocols: ✓
```

---

## HTTP vs HTTPS Proxying

### HTTP Proxying (Plaintext Content Visibility)

```mermaid
sequenceDiagram
    participant Client
    participant Xray
    participant Target

    Client->>Xray: GET http://example.com/ HTTP/1.1<br/>Proxy-Authorization: Basic ...
    Note over Xray: Proxy can see full HTTP request<br/>(method, URL, headers, body)
    Xray->>Target: GET / HTTP/1.1<br/>Host: example.com
    Target->>Xray: HTTP/1.1 200 OK<br/>Content: ...
    Note over Xray: Proxy can see full HTTP response
    Xray->>Client: HTTP/1.1 200 OK<br/>Content: ...
```

**Security:** ⚠️ Proxy can inspect all HTTP traffic (NO privacy)

### HTTPS Proxying (End-to-End Encryption)

```mermaid
sequenceDiagram
    participant Client
    participant Xray
    participant Target

    Client->>Xray: CONNECT example.com:443 HTTP/1.1<br/>Proxy-Authorization: Basic ...
    Xray->>Target: TCP Connection
    Target->>Xray: TCP Connected
    Xray->>Client: HTTP/1.1 200 Connection Established

    Note over Client,Target: TCP tunnel established,<br/>proxy is now transparent

    Client->>Target: TLS Handshake (end-to-end)
    Client->>Target: Encrypted HTTPS Request
    Target->>Client: Encrypted HTTPS Response

    Note over Xray: Proxy sees ONLY encrypted bytes<br/>(NO visibility into content)
```

**Security:** ✅ End-to-end encryption (proxy cannot inspect HTTPS content)

---

## Comparison: HTTP Proxy vs SOCKS5 vs VLESS

| Feature | HTTP Proxy (Port 8118) | SOCKS5 (Port 1080) | VLESS Reality (Port 443) |
|---------|------------------------|-------------------|-------------------------|
| **TLS Termination** | HAProxy (decrypts) | HAProxy (decrypts) | Xray (passthrough) |
| **Authentication** | HTTP Basic Auth | Username/Password | UUID only |
| **Protocol** | HTTP CONNECT | SOCKS5 | VLESS Reality |
| **Application Support** | HTTP-aware apps | Any TCP app | VPN clients |
| **HTTPS Visibility** | End-to-end encrypted | End-to-end encrypted | N/A (VPN tunnel) |
| **DPI Resistance** | Standard TLS | Standard TLS | Reality masquerading |
| **Port** | 8118 (custom) | 1080 (custom) | 443 (HTTPS standard) |
| **Use Case** | Web browsers, cURL | Any TCP application | VPN clients, high stealth |

---

## Troubleshooting

### Common Issues

**Issue 1: 407 Proxy Authentication Required**
- **Cause:** Invalid credentials or missing Proxy-Authorization header
- **Fix:** Verify username/password in `xray_config.json` and client config

**Issue 2: Connection timeout**
- **Cause:** HAProxy not forwarding to Xray, or Xray not listening on 18118
- **Debug:**
  ```bash
  docker logs familytraffic-haproxy --tail 50 | grep 8118
  docker exec familytraffic ss -tulnp | grep 18118
  ```

**Issue 3: HTTPS sites work, HTTP sites don't**
- **Cause:** Client not configured to use proxy for HTTP (only HTTPS)
- **Fix:** Enable "Use this proxy for all protocols" in client settings

**Issue 4: Proxy works for some users, not others (v5.24+)**
- **Cause:** External proxy routing misconfigured
- **Debug:**
  ```bash
  sudo familytraffic show-proxy <username>
  jq '.routing.rules[] | select(.inboundTag[] == "http-in")' /opt/familytraffic/config/xray_config.json
  ```

---

## Related Documentation

- [data-flows.yaml](../../yaml/data-flows.yaml) - Complete HTTP proxy flow specification
- [docker.yaml](../../yaml/docker.yaml) - HAProxy and Xray container configurations
- [config.yaml](../../yaml/config.yaml) - Configuration file relationships
- [VLESS Reality Flow](vless-reality-flow.md) - VPN protocol flow
- [SOCKS5 Proxy Flow](socks5-proxy-flow.md) - SOCKS5 proxy traffic flow
- [Reverse Proxy Flow](reverse-proxy-flow.md) - Subdomain-based reverse proxy

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v5.24+ per-user external proxy supported)

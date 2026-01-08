# Per-User External Proxy Routing Flow (v5.24+)

**Purpose:** Visualize the per-user external proxy routing feature introduced in v5.24

**Feature:** Route specific users through upstream SOCKS5s/HTTPS proxies while other users use direct routing

**Use Cases:**
- Geo-specific routing (route users to different regions)
- Load distribution across multiple upstream proxies
- Privacy enhancement (additional encryption layer)
- Bypass restrictive networks for specific users

---

## Main Flow Diagram

```mermaid
graph TB
    Client1[Client: Alice<br/>UUID: abc123]
    Client2[Client: Bob<br/>UUID: def456]
    Client3[Client: Charlie<br/>UUID: ghi789]

    VPNServer[VLESS VPN Server<br/>Xray Routing Engine]

    RoutingRules{Per-User<br/>Routing Rules}

    ExtProxy1[External Proxy 1<br/>proxy-us-east<br/>SOCKS5s]
    ExtProxy2[External Proxy 2<br/>proxy-eu-west<br/>HTTPS]
    DirectRoute[Direct Internet<br/>No External Proxy]

    Internet[Internet Destinations]

    Client1 -->|VLESS Connection| VPNServer
    Client2 -->|VLESS Connection| VPNServer
    Client3 -->|VLESS Connection| VPNServer

    VPNServer --> RoutingRules

    RoutingRules -->|Alice:<br/>external_proxy_id = proxy-us-east| ExtProxy1
    RoutingRules -->|Bob:<br/>external_proxy_id = proxy-eu-west| ExtProxy2
    RoutingRules -->|Charlie:<br/>external_proxy_id = null| DirectRoute

    ExtProxy1 --> Internet
    ExtProxy2 --> Internet
    DirectRoute --> Internet

    style Client1 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Client2 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Client3 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style VPNServer fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style RoutingRules fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style ExtProxy1 fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style ExtProxy2 fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style DirectRoute fill:#e1e1f5,stroke:#0000cc,stroke-width:2px
```

---

## Detailed Step-by-Step Flow

### Step 1: User Configuration (Data Model)

```mermaid
graph TB
    UsersJSON[users.json<br/>User Database]
    ExtProxyJSON[external_proxy.json<br/>Proxy Database]
    XrayConfig[xray_config.json<br/>Routing Configuration]

    UsersJSON -->|users[].external_proxy_id| Mapping[User-to-Proxy<br/>Mapping]
    ExtProxyJSON -->|proxies[].id| Mapping

    Mapping -->|Generate routing rules| XrayConfig

    style UsersJSON fill:#e1f5ff
    style ExtProxyJSON fill:#ffe1f5
    style XrayConfig fill:#e1ffe1
```

**users.json** (User Database):
```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
      "email": "alice@vless.local",
      "external_proxy_id": "proxy-us-east"
    },
    {
      "username": "bob",
      "uuid": "b1c2d3e4-f5a6-7891-2345-678901bcdefg",
      "email": "bob@vless.local",
      "external_proxy_id": "proxy-eu-west"
    },
    {
      "username": "charlie",
      "uuid": "c1d2e3f4-a5b6-7892-3456-789012cdefgh",
      "email": "charlie@vless.local",
      "external_proxy_id": null
    }
  ]
}
```

**external_proxy.json** (Proxy Database):
```json
{
  "proxies": [
    {
      "id": "proxy-us-east",
      "name": "US East Proxy",
      "type": "socks5s",
      "address": "proxy-us.example.com",
      "port": 1080,
      "username": "proxyuser",
      "password": "encrypted_password_hash",
      "enabled": true
    },
    {
      "id": "proxy-eu-west",
      "name": "EU West Proxy",
      "type": "https",
      "address": "proxy-eu.example.com",
      "port": 8443,
      "username": "proxyuser",
      "password": "encrypted_password_hash",
      "enabled": true
    }
  ]
}
```

### Step 2: Configuration Generation

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless set-proxy
    participant UserMgmt as user_management.sh
    participant XrayMgr as xray_routing_manager.sh
    participant UsersDB as users.json
    participant XrayConfig as xray_config.json
    participant Xray

    Admin->>CLI: sudo vless set-proxy alice proxy-us-east

    CLI->>UserMgmt: cmd_set_user_proxy("alice", "proxy-us-east")
    UserMgmt->>UserMgmt: Validate user exists
    UserMgmt->>UserMgmt: Validate proxy-id exists in external_proxy.json

    UserMgmt->>UsersDB: Update users[alice].external_proxy_id = "proxy-us-east"
    UsersDB-->>UserMgmt: ✓ Updated

    UserMgmt->>XrayMgr: update_xray_routing_for_user("alice")
    XrayMgr->>XrayConfig: Regenerate routing rules

    Note over XrayConfig: Routing rules now include:<br/>- Users with external_proxy_id → external-proxy outbound<br/>- Users without → direct outbound

    XrayMgr->>Xray: Reload Xray config (SIGHUP)
    Xray-->>Admin: ✓ Routing updated for alice
```

**Generated xray_config.json** (Routing Section):
```json
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["vless-in", "socks-in", "http-in"],
        "user": [
          "alice@vless.local"
        ],
        "outboundTag": "external-proxy-us-east"
      },
      {
        "type": "field",
        "inboundTag": ["vless-in", "socks-in", "http-in"],
        "user": [
          "bob@vless.local"
        ],
        "outboundTag": "external-proxy-eu-west"
      },
      {
        "type": "field",
        "outboundTag": "direct"
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
      "tag": "external-proxy-us-east",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "proxy-us.example.com",
            "port": 1080,
            "users": [
              {
                "user": "proxyuser",
                "pass": "encrypted_password_hash"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false,
          "serverName": "proxy-us.example.com"
        }
      }
    },
    {
      "tag": "external-proxy-eu-west",
      "protocol": "http",
      "settings": {
        "servers": [
          {
            "address": "proxy-eu.example.com",
            "port": 8443,
            "users": [
              {
                "user": "proxyuser",
                "pass": "encrypted_password_hash"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false,
          "serverName": "proxy-eu.example.com"
        }
      }
    }
  ]
}
```

### Step 3: Runtime Routing Decision

```mermaid
graph TB
    InboundTraffic[Incoming Traffic<br/>from Client]
    ExtractEmail[Extract User Email<br/>from Authentication]
    LookupRouting{Lookup Routing Rules}

    RuleMatch1[Rule Match:<br/>alice@vless.local]
    RuleMatch2[Rule Match:<br/>bob@vless.local]
    DefaultRule[Default Rule:<br/>No Match]

    OutboundUSEast[Outbound:<br/>external-proxy-us-east]
    OutboundEUWest[Outbound:<br/>external-proxy-eu-west]
    OutboundDirect[Outbound:<br/>direct]

    InboundTraffic --> ExtractEmail
    ExtractEmail --> LookupRouting

    LookupRouting --> RuleMatch1
    LookupRouting --> RuleMatch2
    LookupRouting --> DefaultRule

    RuleMatch1 --> OutboundUSEast
    RuleMatch2 --> OutboundEUWest
    DefaultRule --> OutboundDirect

    style InboundTraffic fill:#e1f5ff
    style LookupRouting fill:#fff9e1,stroke:#cc9900,stroke-width:2px
    style OutboundUSEast fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style OutboundEUWest fill:#ffe1f5,stroke:#cc0099,stroke-width:3px
    style OutboundDirect fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
```

**Routing Logic:**
1. Xray receives traffic from client (VLESS, SOCKS5, or HTTP inbound)
2. Xray identifies user by email (extracted from UUID mapping or authentication)
3. Xray matches user against routing rules in order
4. First matching rule determines outbound tag
5. Xray forwards traffic to selected outbound (external proxy or direct)

### Step 4: External Proxy Connection (SOCKS5s Example)

```mermaid
sequenceDiagram
    participant Xray
    participant ExtProxy as External Proxy<br/>proxy-us.example.com:1080
    participant Internet

    Note over Xray: User alice's traffic<br/>routed to external-proxy-us-east

    Xray->>ExtProxy: TLS Handshake<br/>SNI: proxy-us.example.com
    ExtProxy->>Xray: TLS ServerHello

    Xray->>ExtProxy: SOCKS5 Auth Request<br/>Username: proxyuser<br/>Password: ***
    ExtProxy->>Xray: SOCKS5 Auth Success

    Xray->>ExtProxy: SOCKS5 CONNECT<br/>Target: example.com:443
    ExtProxy->>Internet: TCP Connection to example.com:443
    Internet->>ExtProxy: Connection Established
    ExtProxy->>Xray: SOCKS5 Reply: Success

    Note over Xray,Internet: Bidirectional tunnel established<br/>via external proxy

    Xray->>ExtProxy: Client data
    ExtProxy->>Internet: Forward to example.com
    Internet->>ExtProxy: Response from example.com
    ExtProxy->>Xray: Forward to client
```

**SOCKS5s Connection Details:**
- **Protocol:** SOCKS5 over TLS (socks5s://)
- **TLS Encryption:** Enabled (verify certificate)
- **Authentication:** Username + Password
- **Retry Logic:** 3 attempts with exponential backoff (1s, 2s, 4s)
- **Fallback:** On all failures, fallback to direct outbound (log warning)

### Step 5: External Proxy Connection (HTTPS Example)

```mermaid
sequenceDiagram
    participant Xray
    participant ExtProxy as External Proxy<br/>proxy-eu.example.com:8443
    participant Internet

    Note over Xray: User bob's traffic<br/>routed to external-proxy-eu-west

    Xray->>ExtProxy: TLS Handshake<br/>SNI: proxy-eu.example.com
    ExtProxy->>Xray: TLS ServerHello

    Xray->>ExtProxy: HTTP CONNECT example.com:443<br/>Proxy-Authorization: Basic base64(user:pass)
    ExtProxy->>Internet: TCP Connection to example.com:443
    Internet->>ExtProxy: Connection Established
    ExtProxy->>Xray: HTTP/1.1 200 Connection Established

    Note over Xray,Internet: TCP tunnel established<br/>via HTTPS proxy

    Xray->>ExtProxy: Client data (encrypted TLS)
    ExtProxy->>Internet: Forward to example.com
    Internet->>ExtProxy: Response from example.com
    ExtProxy->>Xray: Forward to client
```

**HTTPS Proxy Connection Details:**
- **Protocol:** HTTP CONNECT over TLS
- **TLS Encryption:** Enabled (verify certificate)
- **Authentication:** HTTP Basic Auth (Proxy-Authorization header)
- **Retry Logic:** Same as SOCKS5s (3 attempts, exponential backoff)
- **Fallback:** Same as SOCKS5s (direct outbound on failure)

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Client Side"
        Alice[Alice<br/>VLESS Client<br/>UUID: abc123]
        Bob[Bob<br/>SOCKS5 Client<br/>UUID: def456]
        Charlie[Charlie<br/>HTTP Proxy Client<br/>UUID: ghi789]
    end

    subgraph "VPN Server - Xray Routing"
        VLESSIn[VLESS Inbound<br/>Port 8443]
        SOCKS5In[SOCKS5 Inbound<br/>Port 10800]
        HTTPIn[HTTP Inbound<br/>Port 18118]
        RoutingEngine[Routing Engine<br/>Per-User Rules]
    end

    subgraph "Outbound Paths"
        ExtProxyUS[External Proxy US<br/>SOCKS5s]
        ExtProxyEU[External Proxy EU<br/>HTTPS]
        DirectOut[Direct Internet]
    end

    subgraph "Internet"
        TargetSites[Target Websites]
    end

    Alice -->|VLESS Connection| VLESSIn
    Bob -->|SOCKS5 Connection| SOCKS5In
    Charlie -->|HTTP Proxy Connection| HTTPIn

    VLESSIn --> RoutingEngine
    SOCKS5In --> RoutingEngine
    HTTPIn --> RoutingEngine

    RoutingEngine -->|Alice:<br/>proxy-us-east| ExtProxyUS
    RoutingEngine -->|Bob:<br/>proxy-eu-west| ExtProxyEU
    RoutingEngine -->|Charlie:<br/>null| DirectOut

    ExtProxyUS --> TargetSites
    ExtProxyEU --> TargetSites
    DirectOut --> TargetSites

    style Alice fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Bob fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Charlie fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style RoutingEngine fill:#fff9e1,stroke:#cc9900,stroke-width:3px
    style ExtProxyUS fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style ExtProxyEU fill:#ffe1f5,stroke:#cc0099,stroke-width:2px
    style DirectOut fill:#e1ffe1,stroke:#00cc00,stroke-width:2px
```

---

## CLI Management Workflow

### Adding External Proxy

```bash
# Step 1: Add external proxy to database
sudo vless-external-proxy add

# Interactive wizard:
# → Proxy type: socks5s
# → Address: proxy-us.example.com
# → Port: 1080
# → Username: proxyuser
# → Password: ********
# → Test connectivity: [Y/n] y

# Output:
# ✓ Proxy connectivity test passed
# ✓ Proxy added with ID: proxy-us-east
```

### Assigning Proxy to User

```bash
# Step 2: Assign proxy to user
sudo vless set-proxy alice proxy-us-east

# Output:
# ✓ Updated user alice: external_proxy_id = proxy-us-east
# ✓ Regenerated Xray routing rules
# ✓ Reloaded Xray configuration
# ✓ User alice will now route through proxy-us-east
```

### Viewing User Proxy Assignment

```bash
# Check specific user
sudo vless show-proxy alice

# Output:
# User: alice (alice@vless.local)
# External Proxy: proxy-us-east (US East Proxy)
# Proxy Type: socks5s
# Proxy Address: proxy-us.example.com:1080
# Proxy Status: ✓ Enabled

# List all assignments
sudo vless list-proxy-assignments

# Output:
# USER       PROXY ID         PROXY NAME        TYPE      STATUS
# alice      proxy-us-east    US East Proxy     socks5s   ✓ Enabled
# bob        proxy-eu-west    EU West Proxy     https     ✓ Enabled
# charlie    (none)           Direct routing    -         -
```

### Removing Proxy Assignment

```bash
# Remove proxy from user (revert to direct routing)
sudo vless set-proxy alice none

# Output:
# ✓ Updated user alice: external_proxy_id = null
# ✓ Regenerated Xray routing rules
# ✓ Reloaded Xray configuration
# ✓ User alice will now use direct routing
```

---

## Advanced Use Cases

### Use Case 1: Geo-Specific Routing

**Scenario:** Route US users through US proxy, EU users through EU proxy

```bash
# Add proxies
sudo vless-external-proxy add  # proxy-us
sudo vless-external-proxy add  # proxy-eu

# Assign to users
sudo vless set-proxy alice proxy-us    # Alice in US
sudo vless set-proxy bob proxy-eu      # Bob in EU
sudo vless set-proxy charlie none      # Charlie direct
```

**Result:**
- Alice's traffic exits via US proxy (low latency for US sites)
- Bob's traffic exits via EU proxy (low latency for EU sites)
- Charlie's traffic exits directly from VPN server

### Use Case 2: Load Distribution

**Scenario:** Distribute users across multiple upstream proxies to avoid overloading single proxy

```bash
# Add multiple proxies
sudo vless-external-proxy add  # proxy-1
sudo vless-external-proxy add  # proxy-2
sudo vless-external-proxy add  # proxy-3

# Distribute users
sudo vless set-proxy alice proxy-1
sudo vless set-proxy bob proxy-2
sudo vless set-proxy charlie proxy-3
```

**Result:** Traffic load distributed across 3 upstream proxies

### Use Case 3: Privacy Enhancement (Double Proxy Chain)

**Scenario:** Add extra encryption layer by routing through external proxy

```
Client → VLESS VPN (encrypted) → External Proxy (encrypted) → Internet
```

**Benefits:**
- Two separate encryption layers
- VPN server cannot see final destination (external proxy sees it)
- External proxy cannot see VPN client identity (VPN server sees it)

**Limitations:**
- Higher latency (~2x)
- Requires trust in external proxy provider

---

## Performance Characteristics

**Latency Impact:**
- **Direct Routing:** ~10ms (baseline VLESS Reality)
- **External Proxy (SOCKS5s):** +50-200ms (proxy connection + geo distance)
- **External Proxy (HTTPS):** +50-200ms (similar to SOCKS5s)

**Throughput:**
- **Bottleneck:** External proxy bandwidth (typically 10-100 Mbps)
- **VPN Server:** Can handle 1 Gbps+ with multiple users
- **Recommendation:** Monitor external proxy bandwidth usage

**Retry Behavior:**
- **Max Attempts:** 3 (configurable in xray_config.json)
- **Backoff:** Exponential (1s, 2s, 4s)
- **Total Retry Duration:** ~7 seconds maximum
- **Fallback:** Direct routing on all failures (logs warning)

---

## Security Considerations

**Encryption Layers:**
- ✅ **Layer 1:** Client to VPN server (VLESS Reality TLS 1.3)
- ✅ **Layer 2:** VPN server to external proxy (SOCKS5s/HTTPS TLS)
- ✅ **Layer 3:** Client to target website (HTTPS end-to-end)

**Privacy:**
- ⚠️ **VPN Server:** Knows client identity, but NOT final destination (external proxy sees it)
- ⚠️ **External Proxy:** Knows final destination, but NOT client identity (VPN server knows it)
- ✅ **Result:** Split trust model (no single entity knows both client and destination)

**Credential Storage:**
- ✅ External proxy credentials stored in `external_proxy.json` (chmod 600)
- ✅ Passwords encrypted with bcrypt or similar
- ✅ Credentials never logged

**Failure Modes:**
- ⚠️ **External proxy down:** Fallback to direct (logs warning, user exposed)
- ✅ **Mitigation:** Health check external proxy before fallback
- ✅ **Alternative:** Retry with different proxy (future enhancement)

---

## Comparison: Per-User vs Server-Level External Proxy

| Feature | Per-User (v5.24+) | Server-Level (v5.23) |
|---------|-------------------|----------------------|
| **Granularity** | Per user | All users |
| **Configuration** | users.json + routing rules | Single outbound |
| **Use Case** | Geo-routing, selective privacy | Global proxy requirement |
| **Complexity** | Higher (multiple routing rules) | Lower (single outbound) |
| **Performance** | Dynamic (depends on proxy assignment) | Consistent (all users same latency) |
| **Management** | `vless set-proxy <user> <proxy-id>` | `vless-external-proxy enable` |

---

## Troubleshooting

### Common Issues

**Issue 1: User traffic not routed through external proxy**
- **Cause:** Routing rule not generated correctly
- **Debug:**
  ```bash
  # Check user's external_proxy_id
  jq '.users[] | select(.username == "alice") | .external_proxy_id' /opt/vless/data/users.json

  # Check routing rules
  jq '.routing.rules[] | select(.user[] == "alice@vless.local")' /opt/vless/config/xray_config.json
  ```

**Issue 2: External proxy connection fails**
- **Cause:** Invalid credentials, network issues, or proxy down
- **Debug:**
  ```bash
  # Check Xray logs for proxy connection errors
  docker logs vless_xray --tail 100 | grep "external-proxy"

  # Test proxy connectivity manually
  curl --socks5 socks5://proxyuser:pass@proxy-us.example.com:1080 https://www.google.com
  ```

**Issue 3: Fallback to direct routing not working**
- **Cause:** Fallback not configured in xray_config.json
- **Fix:** Ensure last routing rule is catch-all to "direct" outbound

**Issue 4: User sees IP of external proxy instead of VPN server**
- **Status:** ✅ **This is expected behavior!**
- **Explanation:** Traffic exits via external proxy, so target websites see proxy IP (not VPN IP)

---

## Related Documentation

- [data-flows.yaml](../../yaml/data-flows.yaml) - Complete external proxy flow specification
- [docker.yaml](../../yaml/docker.yaml) - Xray container configuration
- [config.yaml](../../yaml/config.yaml) - users.json and external_proxy.json relationships
- [cli.yaml](../../yaml/cli.yaml) - vless-external-proxy and vless set-proxy commands
- [VLESS Reality Flow](vless-reality-flow.md) - Base VPN protocol flow
- [SOCKS5 Proxy Flow](socks5-proxy-flow.md) - SOCKS5 protocol details
- [HTTP Proxy Flow](http-proxy-flow.md) - HTTP proxy protocol details

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v5.24+ per-user external proxy fully supported)

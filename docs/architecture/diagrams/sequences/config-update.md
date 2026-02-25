# Configuration Update Propagation Sequence Diagram

**Purpose:** Visualize how configuration changes propagate through the system

**Scope:** Configuration update flows for major operations

**Operations Covered:**
- User database changes → Xray configuration
- External proxy changes → Xray configuration
- Reverse proxy domain addition → HAProxy + Nginx configuration
- Direct configuration file edits → Service reloads

---

## User Change Propagation Flow

### User Added → Full Configuration Update

```mermaid
sequenceDiagram
    participant UserAction as Admin Action<br/>(add-user alice)
    participant UsersDB as users.json
    participant XrayConfig as xray_config.json
    participant HAProxyConfig as haproxy.cfg
    participant Xray as Xray Container
    participant HAProxy as HAProxy Container

    Note over UserAction: Trigger: sudo familytraffic add-user alice

    UserAction->>UsersDB: Append user:<br/>{username: "alice", uuid: "...", external_proxy_id: null}

    Note over UsersDB,XrayConfig: Propagation Step 1: Xray Inbound Configuration

    UsersDB->>XrayConfig: Generate xray_config.json
    XrayConfig->>XrayConfig: Update inbounds[vless].clients[]:<br/>Add {id: "alice_uuid", email: "alice@vless.local"}
    XrayConfig->>XrayConfig: Update inbounds[socks].accounts[]:<br/>Add {user: "alice", pass: "..."}
    XrayConfig->>XrayConfig: Update inbounds[http].accounts[]:<br/>Add {user: "alice", pass: "..."}

    Note over XrayConfig,Xray: Propagation Step 2: Xray Reload

    XrayConfig->>XrayConfig: Validate JSON syntax<br/>(jq . xray_config.json)
    XrayConfig->>Xray: docker exec familytraffic kill -HUP $(pgrep xray)
    Xray->>Xray: Graceful reload<br/>(read new config, no downtime)
    Xray-->>XrayConfig: ✓ Config reloaded

    Note over UsersDB: HAProxy NOT affected<br/>(user addition doesn't change HAProxy)

    HAProxyConfig->>HAProxyConfig: No changes needed

    Note over UserAction: Result: Alice can now connect via<br/>VLESS, SOCKS5, and HTTP
```

---

## External Proxy Change Propagation

### Set Proxy → Routing Rule Update

```mermaid
sequenceDiagram
    participant UserAction as Admin Action<br/>(set-proxy alice proxy-us)
    participant UsersDB as users.json
    participant ProxyDB as external_proxy.json
    participant XrayConfig as xray_config.json
    participant Xray as Xray Container

    Note over UserAction: Trigger: sudo familytraffic set-proxy alice proxy-us

    UserAction->>UsersDB: Update users[alice].external_proxy_id = "proxy-us"

    Note over UsersDB,XrayConfig: Propagation Step 1: Routing Rules

    UsersDB->>ProxyDB: Read proxy details (proxy-us)
    ProxyDB-->>UsersDB: {type: "socks5s", address: "proxy-us.example.com", port: 1080, ...}

    UsersDB->>XrayConfig: Generate routing rules
    XrayConfig->>XrayConfig: Add routing.rules[]:<br/>{<br/> type: "field",<br/> inboundTag: ["vless-in", "socks-in", "http-in"],<br/> user: ["alice@vless.local"],<br/> outboundTag: "external-proxy-us"<br/>}

    Note over XrayConfig: Propagation Step 2: Outbound Configuration

    XrayConfig->>XrayConfig: Add/Update outbounds[]:<br/>{<br/> tag: "external-proxy-us",<br/> protocol: "socks",<br/> settings: {...},<br/> streamSettings: {security: "tls", ...}<br/>}

    Note over XrayConfig,Xray: Propagation Step 3: Xray Reload

    XrayConfig->>XrayConfig: Validate JSON
    XrayConfig->>Xray: Reload Xray (SIGHUP)
    Xray->>Xray: Apply new routing rules
    Xray-->>XrayConfig: ✓ Routing updated

    Note over UserAction: Result: Alice's traffic now routes<br/>through proxy-us.example.com
```

---

## Reverse Proxy Domain Addition Propagation

### Add Domain → Multi-Service Configuration Update

```mermaid
sequenceDiagram
    participant UserAction as Admin Action<br/>(familytraffic-proxy add)
    participant ReverseProxyDB as Reverse Proxy Database<br/>(in-memory)
    participant NginxConfig as Nginx Config<br/>app.example.com.conf
    participant HTTPContext as http_context.conf
    participant HAProxyConfig as haproxy.cfg
    participant Nginx as Nginx Container
    participant HAProxy as HAProxy Container

    Note over UserAction: Trigger: sudo familytraffic-proxy add

    UserAction->>UserAction: Interactive wizard:<br/>- Domain: app.example.com<br/>- Target: https://backend:8443<br/>- OAuth2: No<br/>- WebSocket: No

    Note over ReverseProxyDB,NginxConfig: Propagation Step 1: Nginx Configuration

    UserAction->>ReverseProxyDB: Allocate port: 9443
    ReverseProxyDB->>NginxConfig: Generate app.example.com.conf:<br/>server {<br/> listen 9443 ssl http2;<br/> server_name app.example.com;<br/> ssl_certificate ...;<br/> ssl_certificate_key ...;<br/> location / {<br/>   proxy_pass https://backend:8443;<br/>   ...<br/> }<br/>}

    ReverseProxyDB->>HTTPContext: Add rate limit zone:<br/>limit_req_zone $binary_remote_addr<br/> zone=reverseproxy_app_example_com:10m<br/> rate=100r/s;

    Note over NginxConfig,Nginx: Propagation Step 2: Nginx Reload

    NginxConfig->>Nginx: docker exec familytraffic-nginx nginx -t
    Nginx->>Nginx: Test configuration syntax
    Nginx-->>NginxConfig: ✓ Syntax OK

    NginxConfig->>Nginx: docker exec familytraffic-nginx nginx -s reload
    Nginx->>Nginx: Graceful reload<br/>(load new server block)
    Nginx-->>NginxConfig: ✓ Config reloaded

    Note over HAProxyConfig,HAProxy: Propagation Step 3: HAProxy ACL Update

    UserAction->>HAProxyConfig: Update dynamic ACL section:<br/>Add between markers:<br/># DYNAMIC_REVERSE_PROXY_ROUTES<br/>acl is_app req_ssl_sni -i app.example.com<br/>use_backend nginx_app if is_app<br/># END_DYNAMIC_REVERSE_PROXY_ROUTES

    HAProxyConfig->>HAProxyConfig: Add backend:<br/>backend nginx_app<br/> mode tcp<br/> server nginx 127.0.0.1:9443 check

    HAProxyConfig->>HAProxy: Validate config:<br/>haproxy -c -f /etc/haproxy/haproxy.cfg
    HAProxy-->>HAProxyConfig: ✓ Config valid

    HAProxyConfig->>HAProxy: Graceful reload:<br/>haproxy -sf $(cat /var/run/haproxy.pid)
    HAProxy->>HAProxy: Start new process<br/>Stop old process
    HAProxy-->>HAProxyConfig: ✓ Reloaded

    Note over UserAction: Result: https://app.example.com<br/>now routes to backend:8443
```

---

## Direct Configuration File Edit Propagation

### Manual Edit → Service Reload

```mermaid
sequenceDiagram
    participant Admin
    participant ConfigFile as Configuration File<br/>(edited manually)
    participant ValidationScript as Validation Script
    participant Service as Service Container

    Admin->>ConfigFile: Edit file directly:<br/>vi /opt/familytraffic/config/xray_config.json

    Note over ConfigFile: Changes made:<br/>- Modified inbound port<br/>- Added new outbound

    Admin->>ValidationScript: Validate changes:<br/>jq . /opt/familytraffic/config/xray_config.json

    alt Validation Success
        ValidationScript-->>Admin: ✓ Valid JSON

        Admin->>Service: Reload service:<br/>docker exec familytraffic kill -HUP $(pgrep xray)
        Service->>Service: Read configuration file
        Service->>Service: Apply changes

        alt Service Reload Success
            Service-->>Admin: ✓ Configuration applied
        else Service Reload Failure
            Service-->>Admin: ✗ Invalid configuration<br/>Service still running with old config
            Admin->>ConfigFile: Rollback changes
        end

    else Validation Failure
        ValidationScript-->>Admin: ✗ Invalid JSON syntax
        Admin->>ConfigFile: Fix syntax errors
    end
```

---

## Configuration Propagation Matrix

### Which Changes Affect Which Services

```mermaid
graph TB
    subgraph "Configuration Sources"
        UsersJSON[users.json]
        ProxyJSON[external_proxy.json]
        ReverseProxyConf[Reverse Proxy Configs]
    end

    subgraph "Generated Configurations"
        XrayConf[xray_config.json]
        HAProxyConf[haproxy.cfg]
        NginxConf[Nginx Configs]
    end

    subgraph "Service Reloads"
        XrayReload[Xray Reload<br/>SIGHUP]
        HAProxyReload[HAProxy Reload<br/>-sf]
        NginxReload[Nginx Reload<br/>-s reload]
    end

    UsersJSON -->|Generate inbounds,<br/>routing rules| XrayConf
    ProxyJSON -->|Generate outbounds,<br/>routing rules| XrayConf
    ReverseProxyConf -->|Generate server blocks| NginxConf
    ReverseProxyConf -->|Generate ACLs,<br/>backends| HAProxyConf

    XrayConf --> XrayReload
    HAProxyConf --> HAProxyReload
    NginxConf --> NginxReload

    style UsersJSON fill:#e1f5ff
    style ProxyJSON fill:#ffe1f5
    style ReverseProxyConf fill:#fff9e1
    style XrayConf fill:#e1ffe1
    style HAProxyConf fill:#fff4e1
    style NginxConf fill:#e1e1f5
```

| Change Type | Affects | Service Reload Required |
|-------------|---------|-------------------------|
| Add user | `xray_config.json` | Xray (SIGHUP) |
| Remove user | `xray_config.json` | Xray (SIGHUP) |
| Set user proxy | `xray_config.json` (routing) | Xray (SIGHUP) |
| Add external proxy | `external_proxy.json` | None (until assigned to user) |
| Assign proxy to user | `xray_config.json` (outbounds + routing) | Xray (SIGHUP) |
| Add reverse proxy domain | `haproxy.cfg` + Nginx `*.conf` | HAProxy (-sf) + Nginx (-s reload) |
| Remove reverse proxy domain | `haproxy.cfg` + Nginx `*.conf` | HAProxy (-sf) + Nginx (-s reload) |
| Edit HAProxy config | `haproxy.cfg` | HAProxy (-sf) |
| Edit Nginx config | Nginx `*.conf` | Nginx (-s reload) |
| Edit Xray config | `xray_config.json` | Xray (SIGHUP) |

---

## Configuration Atomicity and Locking

### File Lock Mechanism for Concurrent Updates

```mermaid
sequenceDiagram
    participant Admin1 as Admin #1<br/>(add-user alice)
    participant Admin2 as Admin #2<br/>(set-proxy bob proxy-us)
    participant Lock as /var/lock/familytraffic_users.lock
    participant UsersJSON as users.json
    participant XrayConfig as xray_config.json

    Note over Admin1,Admin2: Both operations modify users.json

    Admin1->>Lock: flock -w 10
    Lock-->>Admin1: ✓ Lock acquired

    Admin2->>Lock: flock -w 10
    Note over Lock: Wait... Admin1 holds lock

    Admin1->>UsersJSON: Read users.json
    Admin1->>UsersJSON: Add alice
    Admin1->>UsersJSON: Atomic write (temp → rename)

    Admin1->>XrayConfig: Update Xray config
    Admin1->>XrayConfig: Reload Xray

    Admin1->>Lock: Release lock

    Note over Lock: Lock now available

    Lock-->>Admin2: ✓ Lock acquired (after waiting)

    Admin2->>UsersJSON: Read users.json (now includes alice)
    Admin2->>UsersJSON: Update bob's external_proxy_id
    Admin2->>UsersJSON: Atomic write (temp → rename)

    Admin2->>XrayConfig: Update Xray config (routing)
    Admin2->>XrayConfig: Reload Xray

    Admin2->>Lock: Release lock

    Note over Admin1,Admin2: Both operations succeeded<br/>No race condition
```

---

## Configuration Rollback on Error

### Error Handling with Backup Restoration

```mermaid
sequenceDiagram
    participant Operation as Configuration Update
    participant Backup as Backup Files
    participant ConfigFile as Configuration File
    participant Validation as Validation
    participant Service as Service Container

    Note over Operation: Before making changes

    Operation->>Backup: Create backup:<br/>cp xray_config.json xray_config.json.backup

    Operation->>ConfigFile: Apply changes

    Operation->>Validation: Validate new config:<br/>jq . xray_config.json

    alt Validation Failed
        Validation-->>Operation: ✗ Invalid JSON

        Note over Operation: Rollback triggered

        Operation->>Backup: Restore from backup:<br/>mv xray_config.json.backup xray_config.json
        Operation->>Operation: Error: Config update failed<br/>Rollback complete

    else Validation Passed
        Validation-->>Operation: ✓ Valid JSON

        Operation->>Service: Reload service

        alt Service Reload Failed
            Service-->>Operation: ✗ Reload failed

            Note over Operation: Rollback triggered

            Operation->>Backup: Restore from backup
            Operation->>Service: Reload with old config
            Operation->>Operation: Error: Reload failed<br/>Rollback complete

        else Service Reload Success
            Service-->>Operation: ✓ Reloaded

            Operation->>Backup: Remove backup:<br/>rm xray_config.json.backup
            Operation->>Operation: ✓ Update successful
        end
    end
```

---

## Configuration Dependencies

### Dependency Graph for Configuration Files

```mermaid
graph TB
    subgraph "Source Data"
        UsersJSON[users.json]
        ProxyJSON[external_proxy.json]
        ReverseProxyDB[(Reverse Proxy<br/>Database)]
    end

    subgraph "Generated Configs"
        XrayInbounds[Xray Inbounds<br/>clients[] sections]
        XrayRouting[Xray Routing<br/>rules[] sections]
        XrayOutbounds[Xray Outbounds<br/>external proxies]
        XrayFull[xray_config.json<br/>Complete]

        HAProxyACLs[HAProxy ACLs<br/>Dynamic section]
        HAProxyBackends[HAProxy Backends<br/>Nginx backends]
        HAProxyFull[haproxy.cfg<br/>Complete]

        NginxServers[Nginx Server Blocks<br/>domain.conf files]
        NginxHTTPContext[http_context.conf<br/>Rate limit zones]
    end

    UsersJSON --> XrayInbounds
    UsersJSON --> XrayRouting
    ProxyJSON --> XrayOutbounds
    ProxyJSON --> XrayRouting

    XrayInbounds --> XrayFull
    XrayRouting --> XrayFull
    XrayOutbounds --> XrayFull

    ReverseProxyDB --> HAProxyACLs
    ReverseProxyDB --> HAProxyBackends
    ReverseProxyDB --> NginxServers
    ReverseProxyDB --> NginxHTTPContext

    HAProxyACLs --> HAProxyFull
    HAProxyBackends --> HAProxyFull

    style UsersJSON fill:#e1f5ff
    style ProxyJSON fill:#ffe1f5
    style ReverseProxyDB fill:#fff9e1
    style XrayFull fill:#e1ffe1
    style HAProxyFull fill:#fff4e1
    style NginxServers fill:#e1e1f5
```

---

## Performance Metrics

**Configuration Update Operations:**
- **File Lock Acquisition:** < 10ms (or wait up to 10s)
- **JSON Validation:** < 10ms
- **File Write (atomic):** < 10ms
- **Xray Reload (SIGHUP):** ~100-200ms
- **HAProxy Reload (-sf):** ~50-100ms
- **Nginx Reload (-s reload):** ~50-100ms

**Typical Update Durations:**
- **Add User:** ~300ms total (mostly Xray reload)
- **Set Proxy:** ~300ms total (Xray reload + routing update)
- **Add Reverse Proxy:** ~200ms total (HAProxy + Nginx reload)
- **Direct Config Edit:** Depends on validation + reload (~100-500ms)

**Downtime:**
- **Xray Reload:** 0 seconds (graceful)
- **HAProxy Reload:** 0 seconds (graceful)
- **Nginx Reload:** 0 seconds (graceful)

---

## Troubleshooting

### Common Issues

**Issue 1: Configuration update fails with "Lock timeout"**
- **Cause:** Another process holds the lock for > 10 seconds
- **Fix:**
  ```bash
  # Check if lock file exists
  ls -l /var/lock/familytraffic_users.lock

  # Check which process holds lock (if any)
  lsof /var/lock/familytraffic_users.lock

  # Force remove lock (use with caution!)
  rm -f /var/lock/familytraffic_users.lock
  ```

**Issue 2: Service fails to reload after config update**
- **Cause:** Invalid configuration or syntax error
- **Debug:**
  ```bash
  # Xray
  docker exec familytraffic xray -test -config /etc/xray/config.json

  # HAProxy
  docker exec familytraffic-haproxy haproxy -c -f /etc/haproxy/haproxy.cfg

  # Nginx
  docker exec familytraffic-nginx nginx -t
  ```

**Issue 3: Changes not taking effect after reload**
- **Cause:** Wrong config file edited, or cache issue
- **Debug:**
  ```bash
  # Verify config file timestamp
  ls -l /opt/familytraffic/config/xray_config.json

  # Check if service read new config
  docker logs familytraffic --tail 20 | grep "config"

  # Force restart instead of reload
  docker restart familytraffic
  ```

---

## Related Documentation

- [config.yaml](../../yaml/config.yaml) - Complete configuration relationships
- [dependencies.yaml](../../yaml/dependencies.yaml) - Configuration update dependencies
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - Configuration generation functions
- [User Management Sequence](user-management.md) - User-specific config updates
- [Proxy Assignment Sequence](proxy-assignment.md) - Proxy-specific config updates
- [Reverse Proxy Setup](reverse-proxy-setup.md) - Reverse proxy config updates

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT

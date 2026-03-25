# Per-User Proxy Assignment Sequence Diagram (v5.24+)

**Purpose:** Visualize the workflow for assigning external proxies to individual users

**Feature:** v5.24+ Per-User External Proxy Support

**Operations Covered:**
- Add external proxy to database
- Assign proxy to user
- Remove proxy assignment
- Proxy connectivity testing
- Routing rule generation

---

## Add External Proxy Sequence

### Complete Add External Proxy Flow

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as familytraffic-external-proxy CLI
    participant ProxyMgr as external_proxy_manager.sh
    participant ProxyDB as external_proxy.json
    participant TestProxy as Connectivity Test

    Admin->>CLI: sudo familytraffic-external-proxy add

    Note over CLI,ProxyMgr: Phase 1: Interactive Wizard

    CLI->>Admin: Prompt: Select proxy type
    Admin->>CLI: socks5s
    CLI->>Admin: Prompt: Enter proxy address
    Admin->>CLI: proxy-us.example.com
    CLI->>Admin: Prompt: Enter proxy port
    Admin->>CLI: 1080
    CLI->>Admin: Prompt: Enter username
    Admin->>CLI: proxyuser
    CLI->>Admin: Prompt: Enter password
    Admin->>CLI: ******** (hidden)
    CLI->>Admin: Prompt: Test connectivity? [Y/n]
    Admin->>CLI: Y

    Note over ProxyMgr: Phase 2: Validation

    CLI->>ProxyMgr: cmd_add_external_proxy({<br/> type: "socks5s",<br/> address: "proxy-us.example.com",<br/> port: 1080,<br/> username: "proxyuser",<br/> password: "********"<br/>})

    ProxyMgr->>ProxyMgr: validate_proxy_address()<br/>✓ Valid hostname
    ProxyMgr->>ProxyMgr: validate_proxy_port()<br/>✓ 1-65535
    ProxyMgr->>ProxyMgr: validate_proxy_type()<br/>✓ socks5s or https

    Note over ProxyMgr,TestProxy: Phase 3: Connectivity Test

    ProxyMgr->>TestProxy: test_proxy_connectivity({<br/> type: "socks5s",<br/> address: "proxy-us.example.com:1080",<br/> credentials: "proxyuser:********"<br/>})

    TestProxy->>TestProxy: curl --socks5 socks5://proxyuser:pass@proxy-us.example.com:1080<br/>https://www.google.com

    alt Connectivity Test Success
        TestProxy-->>ProxyMgr: ✓ Status 200, response received
    else Connectivity Test Failure
        TestProxy-->>ProxyMgr: ✗ Connection timeout / Auth failed
        ProxyMgr->>Admin: Warning: Connectivity test failed<br/>Continue anyway? [y/N]
        Admin->>ProxyMgr: n
        ProxyMgr->>Admin: ✗ Proxy not added
        Note over Admin: Flow terminates
    end

    Note over ProxyMgr,ProxyDB: Phase 4: Generate Proxy ID

    ProxyMgr->>ProxyMgr: generate_proxy_id()<br/>→ "proxy-us-east"<br/>(auto-generated from address + port)

    ProxyMgr->>ProxyDB: Check ID uniqueness
    ProxyDB-->>ProxyMgr: ✓ Unique

    Note over ProxyMgr,ProxyDB: Phase 5: Save to Database

    ProxyMgr->>ProxyMgr: encrypt_password("********")<br/>→ bcrypt hash

    ProxyMgr->>ProxyDB: Append proxy object:<br/>{<br/> id: "proxy-us-east",<br/> name: "US East Proxy",<br/> type: "socks5s",<br/> address: "proxy-us.example.com",<br/> port: 1080,<br/> username: "proxyuser",<br/> password: "$2b$10$...",<br/> enabled: true,<br/> created_at: "2026-01-07T14:30:22Z"<br/>}

    ProxyDB-->>ProxyMgr: ✓ Proxy saved

    Note over ProxyMgr,Admin: Phase 6: Success Response

    ProxyMgr->>CLI: Success:<br/>- Proxy ID: proxy-us-east<br/>- Connectivity: ✓ Tested<br/>- Status: Enabled
    CLI->>Admin: ✓ External proxy added successfully<br/><br/>Proxy ID: proxy-us-east<br/>Type: socks5s<br/>Address: proxy-us.example.com:1080<br/>Status: ✓ Enabled<br/><br/>Use this proxy ID to assign to users:<br/> sudo familytraffic set-proxy <username> proxy-us-east
```

---

## Assign Proxy to User Sequence

### Complete Proxy Assignment Flow

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant XrayRouting as xray_routing_manager.sh
    participant Lock as File Lock
    participant UsersDB as users.json
    participant ProxyDB as external_proxy.json
    participant XrayConfig as xray_config.json
    participant Xray as Xray Container

    Admin->>CLI: sudo familytraffic set-proxy alice proxy-us-east

    Note over CLI,UserMgmt: Phase 1: Validation

    CLI->>UserMgmt: cmd_set_user_proxy("alice", "proxy-us-east")

    UserMgmt->>UsersDB: Check user exists
    UsersDB-->>UserMgmt: ✓ User alice found

    UserMgmt->>ProxyDB: Check proxy exists
    ProxyDB-->>UserMgmt: ✓ Proxy proxy-us-east found

    UserMgmt->>ProxyDB: Check proxy enabled
    ProxyDB-->>UserMgmt: ✓ Proxy enabled = true

    Note over UserMgmt,UsersDB: Phase 2: Acquire Lock

    UserMgmt->>Lock: flock -w 10 /var/lock/familytraffic_users.lock
    Lock-->>UserMgmt: ✓ Lock acquired

    Note over UserMgmt,UsersDB: Phase 3: Update User Database

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: Current users list

    UserMgmt->>UserMgmt: Update:<br/>users[alice].external_proxy_id = "proxy-us-east"<br/>(was: null)

    UserMgmt->>UsersDB: Atomic write (temp → rename)
    UsersDB-->>UserMgmt: ✓ User updated

    UserMgmt->>Lock: Release lock
    Lock-->>UserMgmt: ✓ Lock released

    Note over UserMgmt,XrayConfig: Phase 4: Update Xray Routing

    UserMgmt->>XrayRouting: update_xray_routing_for_user("alice")

    XrayRouting->>ProxyDB: Read proxy details (proxy-us-east)
    ProxyDB-->>XrayRouting: {type: "socks5s", address: "proxy-us.example.com", port: 1080, ...}

    XrayRouting->>XrayConfig: Generate routing rule:<br/>{<br/> type: "field",<br/> inboundTag: ["vless-in", "socks-in", "http-in"],<br/> user: ["alice@vless.local"],<br/> outboundTag: "external-proxy-us-east"<br/>}

    XrayRouting->>XrayConfig: Generate outbound:<br/>{<br/> tag: "external-proxy-us-east",<br/> protocol: "socks",<br/> settings: {<br/>   servers: [{<br/>     address: "proxy-us.example.com",<br/>     port: 1080,<br/>     users: [{user: "proxyuser", pass: "..."}]<br/>   }]<br/> },<br/> streamSettings: {security: "tls", ...}<br/>}

    XrayConfig-->>XrayRouting: ✓ Config updated

    XrayRouting->>XrayRouting: validate_xray_config()<br/>✓ JSON valid

    Note over XrayRouting,Xray: Phase 5: Reload Xray

    XrayRouting->>Xray: docker exec familytraffic kill -HUP $(pgrep xray)
    Xray->>Xray: Reload configuration<br/>(graceful, no downtime)
    Xray-->>XrayRouting: ✓ Config reloaded

    Note over UserMgmt,Admin: Phase 6: Success Response

    XrayRouting->>UserMgmt: Success:<br/>- User alice → proxy-us-east<br/>- Routing rule added<br/>- Xray reloaded
    UserMgmt->>CLI: ✓ Proxy assigned
    CLI->>Admin: ✓ Proxy assigned successfully<br/><br/>User: alice<br/>External Proxy: proxy-us-east (US East Proxy)<br/>Routing: All traffic from alice will now<br/> route through proxy-us.example.com
```

---

## Remove Proxy Assignment Sequence

### Complete Proxy Removal Flow

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant XrayRouting as xray_routing_manager.sh
    participant Lock as File Lock
    participant UsersDB as users.json
    participant XrayConfig as xray_config.json
    participant Xray as Xray Container

    Admin->>CLI: sudo familytraffic set-proxy alice none

    Note over CLI,UserMgmt: Phase 1: Validation

    CLI->>UserMgmt: cmd_set_user_proxy("alice", "none")

    UserMgmt->>UsersDB: Check user exists
    UsersDB-->>UserMgmt: ✓ User alice found<br/>(external_proxy_id: "proxy-us-east")

    Note over UserMgmt,UsersDB: Phase 2: Acquire Lock

    UserMgmt->>Lock: flock -w 10 /var/lock/familytraffic_users.lock
    Lock-->>UserMgmt: ✓ Lock acquired

    Note over UserMgmt,UsersDB: Phase 3: Update User Database

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: Current users list

    UserMgmt->>UserMgmt: Update:<br/>users[alice].external_proxy_id = null<br/>(was: "proxy-us-east")

    UserMgmt->>UsersDB: Atomic write (temp → rename)
    UsersDB-->>UserMgmt: ✓ User updated

    UserMgmt->>Lock: Release lock
    Lock-->>UserMgmt: ✓ Lock released

    Note over UserMgmt,XrayConfig: Phase 4: Remove Routing Rule

    UserMgmt->>XrayRouting: update_xray_routing_for_user("alice")

    XrayRouting->>XrayConfig: Remove routing rule:<br/>Filter out rules with user="alice@vless.local"

    XrayRouting->>XrayConfig: Remove or keep outbound:<br/>If proxy-us-east used by other users:<br/> → Keep outbound<br/>If NO other users:<br/> → Remove outbound

    XrayConfig-->>XrayRouting: ✓ Config updated

    XrayRouting->>XrayRouting: validate_xray_config()<br/>✓ JSON valid

    Note over XrayRouting,Xray: Phase 5: Reload Xray

    XrayRouting->>Xray: docker exec familytraffic kill -HUP $(pgrep xray)
    Xray->>Xray: Reload configuration
    Xray-->>XrayRouting: ✓ Config reloaded

    Note over UserMgmt,Admin: Phase 6: Success Response

    XrayRouting->>UserMgmt: Success:<br/>- User alice → direct routing<br/>- Routing rule removed<br/>- Xray reloaded
    UserMgmt->>CLI: ✓ Proxy assignment removed
    CLI->>Admin: ✓ Proxy assignment removed successfully<br/><br/>User: alice<br/>External Proxy: (none)<br/>Routing: Alice will now use direct routing<br/> (no external proxy)
```

---

## View User Proxy Assignments

### Show Single User Proxy

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant UsersDB as users.json
    participant ProxyDB as external_proxy.json

    Admin->>CLI: sudo familytraffic show-proxy alice

    CLI->>UserMgmt: cmd_show_user_proxy("alice")

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: User alice data:<br/>{external_proxy_id: "proxy-us-east"}

    alt User has proxy assigned
        UserMgmt->>ProxyDB: Read external_proxy.json
        ProxyDB-->>UserMgmt: Proxy details:<br/>{id: "proxy-us-east", name: "US East Proxy", type: "socks5s", address: "proxy-us.example.com", port: 1080, enabled: true}

        UserMgmt->>CLI: Success:<br/>- User: alice<br/>- Proxy ID: proxy-us-east<br/>- Proxy Name: US East Proxy<br/>- Type: socks5s<br/>- Address: proxy-us.example.com:1080<br/>- Status: Enabled
        CLI->>Admin: User: alice (alice@vless.local)<br/>External Proxy: proxy-us-east (US East Proxy)<br/>Proxy Type: socks5s<br/>Proxy Address: proxy-us.example.com:1080<br/>Proxy Status: ✓ Enabled
    else User has no proxy (external_proxy_id = null)
        UserMgmt->>CLI: Success:<br/>- User: alice<br/>- Proxy: (none)<br/>- Routing: Direct
        CLI->>Admin: User: alice (alice@vless.local)<br/>External Proxy: (none)<br/>Routing: Direct routing (no external proxy)
    end
```

### List All Proxy Assignments

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant UsersDB as users.json
    participant ProxyDB as external_proxy.json

    Admin->>CLI: sudo familytraffic list-proxy-assignments

    CLI->>UserMgmt: cmd_list_proxy_assignments()

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: All users:<br/>[{username: "alice", external_proxy_id: "proxy-us-east"},<br/> {username: "bob", external_proxy_id: "proxy-eu-west"},<br/> {username: "charlie", external_proxy_id: null}]

    UserMgmt->>ProxyDB: Read external_proxy.json
    ProxyDB-->>UserMgmt: All proxies:<br/>[{id: "proxy-us-east", name: "US East Proxy", ...},<br/> {id: "proxy-eu-west", name: "EU West Proxy", ...}]

    UserMgmt->>UserMgmt: Join users with proxies

    UserMgmt->>CLI: Table data:<br/>alice | proxy-us-east | US East Proxy | socks5s | Enabled<br/>bob | proxy-eu-west | EU West Proxy | https | Enabled<br/>charlie | (none) | Direct routing | - | -

    CLI->>Admin: USER       PROXY ID         PROXY NAME        TYPE      STATUS<br/>alice      proxy-us-east    US East Proxy     socks5s   ✓ Enabled<br/>bob        proxy-eu-west    EU West Proxy     https     ✓ Enabled<br/>charlie    (none)           Direct routing    -         -
```

---

## Error Handling Scenarios

### Scenario 1: Proxy ID Not Found

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant UserMgmt
    participant ProxyDB

    Admin->>CLI: sudo familytraffic set-proxy alice proxy-invalid
    CLI->>UserMgmt: cmd_set_user_proxy("alice", "proxy-invalid")

    UserMgmt->>ProxyDB: Check proxy exists (proxy-invalid)
    ProxyDB-->>UserMgmt: ✗ Not found in external_proxy.json

    UserMgmt->>CLI: Error: Proxy ID proxy-invalid not found
    CLI->>Admin: ✗ ERROR: Proxy ID proxy-invalid does not exist<br/><br/>Available proxies:<br/> - proxy-us-east (US East Proxy)<br/> - proxy-eu-west (EU West Proxy)<br/><br/>List all proxies with:<br/> sudo familytraffic-external-proxy list
```

### Scenario 2: Proxy Disabled

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant UserMgmt
    participant ProxyDB

    Admin->>CLI: sudo familytraffic set-proxy alice proxy-disabled
    CLI->>UserMgmt: cmd_set_user_proxy("alice", "proxy-disabled")

    UserMgmt->>ProxyDB: Check proxy enabled
    ProxyDB-->>UserMgmt: ✗ Proxy disabled (enabled: false)

    UserMgmt->>CLI: Error: Proxy proxy-disabled is disabled
    CLI->>Admin: ✗ ERROR: Proxy proxy-disabled is disabled<br/><br/>Enable proxy first with:<br/> sudo familytraffic-external-proxy enable proxy-disabled<br/><br/>Or assign different proxy
```

### Scenario 3: Connectivity Test Failed

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant ProxyMgr
    participant TestProxy

    Admin->>CLI: sudo familytraffic-external-proxy add
    CLI->>Admin: (Interactive wizard collects details)
    Admin->>CLI: Test connectivity: Y

    CLI->>ProxyMgr: cmd_add_external_proxy(...)
    ProxyMgr->>TestProxy: test_proxy_connectivity(...)

    TestProxy->>TestProxy: curl --socks5 socks5://user:pass@proxy:1080<br/>https://www.google.com

    TestProxy-->>ProxyMgr: ✗ Connection timeout (28)

    ProxyMgr->>CLI: Warning: Connectivity test failed<br/>Error: Connection timeout<br/>Continue anyway? [y/N]
    CLI->>Admin: ⚠️ WARNING: Connectivity test failed<br/><br/>Error: Connection timeout after 10 seconds<br/><br/>Possible causes:<br/> - Proxy server is down<br/> - Incorrect address or port<br/> - Firewall blocking connection<br/> - Invalid credentials<br/><br/>Add proxy anyway? [y/N]
    Admin->>CLI: n
    CLI->>ProxyMgr: User declined
    ProxyMgr->>CLI: Proxy not added
    CLI->>Admin: Proxy not added (user cancelled)
```

---

## State Transitions

### Proxy Assignment State Diagram

```mermaid
stateDiagram-v2
    [*] --> NoProxy : User created

    NoProxy --> PendingAssignment : vless set-proxy <user> <proxy-id>
    PendingAssignment --> Validating : Validate proxy exists
    Validating --> LockAcquired : Acquire file lock
    LockAcquired --> DatabaseUpdated : Update external_proxy_id
    DatabaseUpdated --> RoutingUpdated : Generate routing rules
    RoutingUpdated --> XrayReloaded : Reload Xray config
    XrayReloaded --> ProxyAssigned : Success

    ProxyAssigned --> PendingRemoval : vless set-proxy <user> none
    PendingRemoval --> LockAcquired2[Lock Acquired] : Acquire file lock
    LockAcquired2 --> DatabaseUpdated2[Database Updated] : Set external_proxy_id = null
    DatabaseUpdated2 --> RoutingUpdated2[Routing Updated] : Remove routing rules
    RoutingUpdated2 --> XrayReloaded2[Xray Reloaded] : Reload Xray config
    XrayReloaded2 --> NoProxy : Success

    ProxyAssigned --> Modified : vless set-proxy <user> <different-proxy-id>
    Modified --> RoutingUpdated3[Routing Updated] : Change routing rules
    RoutingUpdated3 --> XrayReloaded3[Xray Reloaded] : Reload Xray config
    XrayReloaded3 --> ProxyAssigned : Success

    Validating --> ErrorRollback : Proxy not found / disabled
    XrayReloaded --> ErrorRollback : Reload failed

    ErrorRollback --> Rollback : Restore backup
    Rollback --> NoProxy : Rollback complete
```

---

## Performance Metrics

**Assign Proxy Operation:**
- **Validation:** < 10ms
- **Lock Acquisition:** < 10ms (or wait up to 10s)
- **Database Update:** < 10ms
- **Routing Rule Generation:** ~20-30ms
- **Xray Config Update:** < 20ms
- **Xray Reload:** ~100-200ms
- **Total Duration:** ~200-300ms

**Remove Proxy Assignment:**
- **Validation:** < 10ms
- **Lock Acquisition:** < 10ms
- **Database Update:** < 10ms
- **Routing Rule Removal:** ~20-30ms
- **Xray Config Update:** < 20ms
- **Xray Reload:** ~100-200ms
- **Total Duration:** ~200-300ms

**Connectivity Test:**
- **SOCKS5s Test:** ~100-500ms (depends on proxy latency)
- **HTTPS Test:** ~100-500ms
- **Timeout:** 10 seconds (configurable)

---

## Related Documentation

- [dependencies.yaml](../../yaml/dependencies.yaml) - Runtime dependencies for proxy assignment
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - external_proxy_manager.sh and xray_routing_manager.sh functions
- [cli.yaml](../../yaml/cli.yaml) - CLI command specifications (vless set-proxy, familytraffic-external-proxy add)
- [config.yaml](../../yaml/config.yaml) - users.json and external_proxy.json relationships
- [data-flows.yaml](../../yaml/data-flows.yaml) - External proxy routing flow
- [External Proxy Flow](../data-flows/external-proxy-flow.md) - Visual traffic flow diagram
- [User Management Sequence](user-management.md) - User add/remove operations

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (v5.24+ per-user external proxy support)

# User Management Sequence Diagram

**Purpose:** Visualize the complete workflow for adding and removing users in the VLESS VPN system

**Operations Covered:**
- Add new user
- Remove existing user
- User configuration generation
- Xray configuration update
- Client configuration generation

---

## Add User Sequence

### Complete Add User Flow

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant Lock as File Lock<br/>/var/lock/familytraffic_users.lock
    participant UsersDB as users.json
    participant XrayConfig as xray_config.json
    participant Xray as Xray Container
    participant QRGen as qr_generator.sh
    participant ClientFiles as Client Config Files

    Admin->>CLI: sudo familytraffic add-user alice

    Note over CLI,UserMgmt: Phase 1: Validation

    CLI->>UserMgmt: cmd_add_user("alice")
    UserMgmt->>UserMgmt: validate_username("alice")<br/>✓ Format: [a-z][a-z0-9_-]{2,31}

    Note over UserMgmt,UsersDB: Phase 2: Acquire Lock

    UserMgmt->>Lock: flock -w 10 /var/lock/familytraffic_users.lock
    Lock-->>UserMgmt: ✓ Lock acquired

    Note over UserMgmt,UsersDB: Phase 3: Check Uniqueness

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: Current users list
    UserMgmt->>UserMgmt: check_username_unique("alice")<br/>✓ Not exists

    Note over UserMgmt: Phase 4: Generate Credentials

    UserMgmt->>UserMgmt: generate_uuid()<br/>→ a1b2c3d4-e5f6-7890-1234-567890abcdef
    UserMgmt->>UserMgmt: generate_passwords()<br/>→ SOCKS5 password<br/>→ HTTP password

    Note over UserMgmt,UsersDB: Phase 5: Update Database

    UserMgmt->>UsersDB: Append user object:<br/>{username: "alice",<br/> uuid: "a1b2...",<br/> email: "alice@vless.local",<br/> external_proxy_id: null}

    UserMgmt->>UsersDB: Atomic write<br/>(temp file → rename)
    UsersDB-->>UserMgmt: ✓ User added

    UserMgmt->>Lock: Release lock
    Lock-->>UserMgmt: ✓ Lock released

    Note over UserMgmt,XrayConfig: Phase 6: Update Xray Config

    UserMgmt->>XrayConfig: add_client_to_xray("alice")
    XrayConfig->>XrayConfig: Add to inbounds[vless].clients[]
    XrayConfig->>XrayConfig: Add to inbounds[socks].accounts[]
    XrayConfig->>XrayConfig: Add to inbounds[http].accounts[]
    XrayConfig-->>UserMgmt: ✓ Xray config updated

    UserMgmt->>UserMgmt: validate_xray_config()<br/>✓ JSON valid

    Note over UserMgmt,Xray: Phase 7: Reload Xray

    UserMgmt->>Xray: docker exec familytraffic kill -HUP $(pgrep xray)
    Xray->>Xray: Reload configuration<br/>(graceful, no downtime)
    Xray-->>UserMgmt: ✓ Config reloaded

    Note over UserMgmt,ClientFiles: Phase 8: Generate Client Configs

    UserMgmt->>UserMgmt: mkdir /opt/familytraffic/data/clients/alice
    UserMgmt->>QRGen: generate_qr_code("alice")

    QRGen->>QRGen: Generate VLESS URI:<br/>vless://a1b2...@vless.example.com:443
    QRGen->>ClientFiles: Write vless_uri.txt
    QRGen->>ClientFiles: Generate QR code PNG
    QRGen->>QRGen: Generate SOCKS5 URI:<br/>socks5s://alice:pass@server:1080
    QRGen->>ClientFiles: Write socks5_uri.txt
    QRGen->>QRGen: Generate HTTP URI:<br/>https://alice:pass@server:8118
    QRGen->>ClientFiles: Write http_uri.txt
    QRGen->>ClientFiles: Write client_config.json<br/>(Xray client format)

    QRGen-->>UserMgmt: ✓ 6 files generated

    Note over UserMgmt,Admin: Phase 9: Success Response

    UserMgmt->>CLI: Success:<br/>- User alice created<br/>- UUID: a1b2...<br/>- Config files: /opt/familytraffic/data/clients/alice/
    CLI->>Admin: ✓ User alice created successfully<br/><br/>Config files generated:<br/> - vless_uri.txt<br/> - vless_qr.png<br/> - socks5_uri.txt<br/> - http_uri.txt<br/> - client_config.json<br/> - subscription.json
```

---

## Remove User Sequence

### Complete Remove User Flow

```mermaid
sequenceDiagram
    participant Admin
    participant CLI as vless CLI
    participant UserMgmt as user_management.sh
    participant Lock as File Lock
    participant UsersDB as users.json
    participant XrayConfig as xray_config.json
    participant Xray as Xray Container
    participant ClientFiles as Client Files<br/>/opt/familytraffic/data/clients/alice/

    Admin->>CLI: sudo familytraffic remove-user alice

    Note over CLI,UserMgmt: Phase 1: Validation

    CLI->>UserMgmt: cmd_remove_user("alice")

    Note over UserMgmt,UsersDB: Phase 2: Acquire Lock

    UserMgmt->>Lock: flock -w 10 /var/lock/familytraffic_users.lock
    Lock-->>UserMgmt: ✓ Lock acquired

    Note over UserMgmt,UsersDB: Phase 3: Check Existence

    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: Current users list
    UserMgmt->>UserMgmt: check_username_exists("alice")<br/>✓ Exists

    alt User has external_proxy_id assigned
        UserMgmt->>UserMgmt: Warn: User has external proxy assigned<br/>(will be removed)
    end

    Note over UserMgmt,UsersDB: Phase 4: Remove from Database

    UserMgmt->>UsersDB: Filter out alice:<br/>users[] = users[].filter(u => u.username != "alice")

    UserMgmt->>UsersDB: Atomic write<br/>(temp file → rename)
    UsersDB-->>UserMgmt: ✓ User removed

    UserMgmt->>Lock: Release lock
    Lock-->>UserMgmt: ✓ Lock released

    Note over UserMgmt,XrayConfig: Phase 5: Update Xray Config

    UserMgmt->>XrayConfig: remove_client_from_xray("alice")
    XrayConfig->>XrayConfig: Remove from inbounds[vless].clients[]<br/>(filter by uuid)
    XrayConfig->>XrayConfig: Remove from inbounds[socks].accounts[]<br/>(filter by user="alice")
    XrayConfig->>XrayConfig: Remove from inbounds[http].accounts[]<br/>(filter by user="alice")
    XrayConfig->>XrayConfig: Remove from routing.rules[]<br/>(filter by user="alice@vless.local")
    XrayConfig-->>UserMgmt: ✓ Xray config updated

    UserMgmt->>UserMgmt: validate_xray_config()<br/>✓ JSON valid

    Note over UserMgmt,Xray: Phase 6: Reload Xray

    UserMgmt->>Xray: docker exec familytraffic kill -HUP $(pgrep xray)
    Xray->>Xray: Reload configuration<br/>(graceful, no downtime)
    Xray-->>UserMgmt: ✓ Config reloaded

    Note over UserMgmt,ClientFiles: Phase 7: Archive Client Files (Optional)

    UserMgmt->>ClientFiles: mv /opt/familytraffic/data/clients/alice<br/>/opt/familytraffic/data/clients/archived/alice_<timestamp>

    alt Archive Failed (not critical)
        ClientFiles-->>UserMgmt: ✗ Archive failed (warn, continue)
    else Archive Success
        ClientFiles-->>UserMgmt: ✓ Files archived
    end

    Note over UserMgmt,Admin: Phase 8: Success Response

    UserMgmt->>CLI: Success:<br/>- User alice removed<br/>- Config files archived
    CLI->>Admin: ✓ User alice removed successfully<br/><br/>Client files archived to:<br/> /opt/familytraffic/data/clients/archived/alice_20260107_143022/
```

---

## Error Handling Scenarios

### Scenario 1: Username Already Exists

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant UserMgmt
    participant UsersDB

    Admin->>CLI: sudo familytraffic add-user alice
    CLI->>UserMgmt: cmd_add_user("alice")
    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: users: [{username: "alice", ...}]
    UserMgmt->>UserMgmt: check_username_unique("alice")<br/>✗ Already exists

    UserMgmt->>CLI: Error: Username alice already exists
    CLI->>Admin: ✗ ERROR: User alice already exists<br/><br/>Suggestion: Use different username or remove existing user first
```

### Scenario 2: Invalid Username Format

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant UserMgmt

    Admin->>CLI: sudo familytraffic add-user Alice123!
    CLI->>UserMgmt: cmd_add_user("Alice123!")
    UserMgmt->>UserMgmt: validate_username("Alice123!")<br/>✗ Invalid format

    UserMgmt->>CLI: Error: Invalid username format
    CLI->>Admin: ✗ ERROR: Invalid username format<br/><br/>Username must:<br/> - Start with lowercase letter<br/> - Contain only: a-z, 0-9, _, -<br/> - Be 3-32 characters long<br/><br/>Examples: alice, user123, vpn-user
```

### Scenario 3: Remove Non-Existent User

```mermaid
sequenceDiagram
    participant Admin
    participant CLI
    participant UserMgmt
    participant UsersDB

    Admin->>CLI: sudo familytraffic remove-user bob
    CLI->>UserMgmt: cmd_remove_user("bob")
    UserMgmt->>UsersDB: Read users.json
    UsersDB-->>UserMgmt: users: [{username: "alice", ...}]
    UserMgmt->>UserMgmt: check_username_exists("bob")<br/>✗ Not found

    UserMgmt->>CLI: Error: User bob not found
    CLI->>Admin: ✗ ERROR: User bob does not exist<br/><br/>Suggestion: Check username spelling or list users with:<br/> sudo familytraffic list-users
```

### Scenario 4: Xray Config Invalid After Update

```mermaid
sequenceDiagram
    participant UserMgmt
    participant XrayConfig
    participant Xray

    UserMgmt->>XrayConfig: add_client_to_xray("alice")
    XrayConfig-->>UserMgmt: ✓ Config written

    UserMgmt->>UserMgmt: validate_xray_config()
    UserMgmt->>UserMgmt: jq . /opt/familytraffic/config/xray_config.json
    UserMgmt->>UserMgmt: ✗ JSON parse error

    Note over UserMgmt: Rollback triggered

    UserMgmt->>XrayConfig: Restore from backup:<br/>xray_config.json.backup
    XrayConfig-->>UserMgmt: ✓ Restored

    UserMgmt->>UserMgmt: Error: Config generation failed<br/>Rollback successful
```

---

## Concurrent Access Handling

### File Locking Mechanism

```mermaid
sequenceDiagram
    participant Admin1 as Admin #1
    participant Admin2 as Admin #2
    participant UserMgmt1 as user_mgmt #1
    participant UserMgmt2 as user_mgmt #2
    participant Lock as File Lock
    participant UsersDB as users.json

    Note over Admin1,Admin2: Both admins try to add users simultaneously

    Admin1->>UserMgmt1: add-user alice
    Admin2->>UserMgmt2: add-user bob

    UserMgmt1->>Lock: flock -w 10 (timeout 10s)
    Lock-->>UserMgmt1: ✓ Lock acquired

    UserMgmt2->>Lock: flock -w 10 (timeout 10s)
    Note over Lock: Lock already held by UserMgmt1<br/>UserMgmt2 waits...

    UserMgmt1->>UsersDB: Add alice
    UserMgmt1->>UsersDB: Write users.json
    UserMgmt1->>Lock: Release lock
    Lock-->>UserMgmt1: ✓ Released

    Note over Lock: Lock now available

    Lock-->>UserMgmt2: ✓ Lock acquired (after waiting)
    UserMgmt2->>UsersDB: Read users.json (includes alice now)
    UserMgmt2->>UsersDB: Add bob
    UserMgmt2->>UsersDB: Write users.json
    UserMgmt2->>Lock: Release lock
    Lock-->>UserMgmt2: ✓ Released

    UserMgmt1->>Admin1: ✓ User alice created
    UserMgmt2->>Admin2: ✓ User bob created

    Note over Admin1,Admin2: Both operations succeeded,<br/>no race condition!
```

---

## State Transitions

### User Lifecycle State Diagram

```mermaid
stateDiagram-v2
    [*] --> Nonexistent

    Nonexistent --> PendingCreation : vless add-user <username>
    PendingCreation --> LockAcquired : Acquire file lock
    LockAcquired --> Validating : Validate username
    Validating --> CredentialsGenerated : Generate UUID + passwords
    CredentialsGenerated --> DatabaseUpdated : Write to users.json
    DatabaseUpdated --> XrayConfigUpdated : Update xray_config.json
    XrayConfigUpdated --> XrayReloaded : Reload Xray container
    XrayReloaded --> ClientConfigsGenerated : Generate client files
    ClientConfigsGenerated --> Active : Success

    Active --> PendingRemoval : vless remove-user <username>
    PendingRemoval --> LockAcquired2[Lock Acquired] : Acquire file lock
    LockAcquired2 --> DatabaseUpdated2[Database Updated] : Remove from users.json
    DatabaseUpdated2 --> XrayConfigUpdated2[Xray Config Updated] : Remove from xray_config.json
    XrayConfigUpdated2 --> XrayReloaded2[Xray Reloaded] : Reload Xray container
    XrayReloaded2 --> Archived : Archive client files
    Archived --> [*]

    Validating --> ErrorRollback : Validation failed
    XrayConfigUpdated --> ErrorRollback : Config invalid
    XrayReloaded --> ErrorRollback : Reload failed

    ErrorRollback --> Rollback : Restore backup
    Rollback --> Nonexistent : Rollback complete (add)
    Rollback --> Active : Rollback complete (remove)

    Active --> Modified : vless set-proxy <username>
    Modified --> XrayReloaded3[Xray Reloaded] : Update routing rules
    XrayReloaded3 --> Active : Success
```

---

## Key Files Modified

### Add User Operation

| File | Modification | Atomicity |
|------|-------------|-----------|
| `/opt/familytraffic/data/users.json` | Append user object | ✓ Atomic write (temp → rename) |
| `/opt/familytraffic/config/xray_config.json` | Add to `inbounds[].clients[]` | ✓ Atomic write |
| `/opt/familytraffic/data/clients/<username>/vless_uri.txt` | Write VLESS URI | ✓ New file |
| `/opt/familytraffic/data/clients/<username>/vless_qr.png` | Write QR code | ✓ New file |
| `/opt/familytraffic/data/clients/<username>/socks5_uri.txt` | Write SOCKS5 URI | ✓ New file |
| `/opt/familytraffic/data/clients/<username>/http_uri.txt` | Write HTTP URI | ✓ New file |
| `/opt/familytraffic/data/clients/<username>/client_config.json` | Write Xray client config | ✓ New file |
| `/opt/familytraffic/data/clients/<username>/subscription.json` | Write subscription URL | ✓ New file |

### Remove User Operation

| File | Modification | Atomicity |
|------|-------------|-----------|
| `/opt/familytraffic/data/users.json` | Filter out user | ✓ Atomic write (temp → rename) |
| `/opt/familytraffic/config/xray_config.json` | Remove from `inbounds[].clients[]` | ✓ Atomic write |
| `/opt/familytraffic/data/clients/<username>/` | Move to archived/ | ⚠️ Non-atomic (not critical) |

---

## Performance Metrics

**Add User Operation:**
- **Lock Acquisition:** < 10ms (or wait up to 10s if locked)
- **UUID Generation:** < 1ms
- **Database Write:** < 10ms
- **Xray Config Update:** < 20ms
- **Xray Reload:** ~100-200ms (graceful reload)
- **QR Code Generation:** ~50-100ms
- **Total Duration:** ~300-500ms

**Remove User Operation:**
- **Lock Acquisition:** < 10ms (or wait up to 10s)
- **Database Write:** < 10ms
- **Xray Config Update:** < 20ms
- **Xray Reload:** ~100-200ms
- **Archive Files:** < 50ms (optional)
- **Total Duration:** ~200-300ms

---

## Related Documentation

- [dependencies.yaml](../../yaml/dependencies.yaml) - Initialization order and runtime dependencies
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - user_management.sh function details
- [cli.yaml](../../yaml/cli.yaml) - CLI command specifications
- [config.yaml](../../yaml/config.yaml) - Configuration file relationships
- [Proxy Assignment Sequence](proxy-assignment.md) - Per-user proxy assignment flow (v5.24+)

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT

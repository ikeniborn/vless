# Runtime Call Chains - Function Call Graphs

**Purpose:** Function call graphs for major runtime operations

**Version:** v5.26
**Status:** Production
**Related Files:**
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - Module specifications
- [dependencies.yaml](../../yaml/dependencies.yaml) - Static dependencies

---

## Overview

This diagram shows the actual function call chains during runtime operations in the familyTraffic VPN system. Each operation is traced from CLI entry point through all module functions to final state changes.

**Key Operations Documented:**
1. Add User Flow
2. Remove User Flow
3. Set Per-User Proxy Flow (v5.24+)
4. Add Reverse Proxy Domain Flow
5. Certificate Renewal Flow
6. External Proxy Management Flow (v5.24+)

**Color Coding:**
- 🟦 Blue: Entry points (CLI commands)
- 🟩 Green: Core business logic
- 🟨 Yellow: Configuration operations
- 🟧 Orange: File I/O operations
- 🟥 Red: Critical validation/reload operations

---

## 1. Add User Flow

**Entry Point:** `vless add-user <username>`
**Duration:** ~3-5 seconds
**Module:** lib/user_management.sh

```mermaid
graph TB
    CLI["🟦 CLI Entry<br/>vless add-user alice"]
    CMD["🟩 cmd_add_user()<br/>scripts/vless:156"]

    subgraph "Validation Layer"
        VAL1["🟥 validate_username()<br/>user_management.sh:234"]
        VAL2["🟥 check_user_exists()<br/>user_management.sh:278"]
        VAL3["🟩 generate_uuid()<br/>user_management.sh:312"]
    end

    subgraph "Database Operations (Atomic)"
        LOCK["🟧 flock_acquire()<br/>user_management.sh:389"]
        READ["🟧 read_users_json()<br/>user_management.sh:421"]
        ADD["🟨 add_user_to_json()<br/>user_management.sh:456"]
        WRITE["🟧 atomic_write_json()<br/>user_management.sh:523"]
        UNLOCK["🟧 flock_release()<br/>user_management.sh:567"]
    end

    subgraph "Xray Configuration"
        ADDCLIENT["🟨 add_client_to_xray()<br/>user_management.sh:678"]
        GENCONFIG["🟨 generate_xray_config()<br/>orchestrator.sh:1234"]
        VALIDATE["🟥 validate_xray_config()<br/>user_management.sh:789"]
    end

    subgraph "Service Management"
        RELOAD["🟥 reload_xray()<br/>user_management.sh:834"]
        DOCKEREXEC["🟧 docker exec familytraffic<br/>kill -HUP"]
        VERIFY["🟥 verify_xray_healthy()<br/>user_management.sh:891"]
    end

    subgraph "Client Configuration Generation"
        GENQR["🟩 generate_qr_code()<br/>qr_generator.sh:45"]
        GENURI["🟩 generate_vless_uri()<br/>qr_generator.sh:123"]
        GENFILES["🟧 create_client_files()<br/>qr_generator.sh:189"]
    end

    SUCCESS["✅ User Created<br/>Exit Code: 0"]
    FAIL["❌ Operation Failed<br/>Rollback"]

    CLI --> CMD
    CMD --> VAL1
    VAL1 --> VAL2
    VAL2 --> VAL3
    VAL3 --> LOCK

    LOCK --> READ
    READ --> ADD
    ADD --> WRITE
    WRITE --> UNLOCK

    UNLOCK --> ADDCLIENT
    ADDCLIENT --> GENCONFIG
    GENCONFIG --> VALIDATE

    VALIDATE -->|Valid| RELOAD
    VALIDATE -->|Invalid| FAIL

    RELOAD --> DOCKEREXEC
    DOCKEREXEC --> VERIFY

    VERIFY -->|Success| GENQR
    VERIFY -->|Failed| FAIL

    GENQR --> GENURI
    GENURI --> GENFILES
    GENFILES --> SUCCESS

    FAIL -.->|Rollback| UNLOCK

    style CLI fill:#5dade2
    style CMD fill:#58d68d
    style VAL1 fill:#ec7063
    style VAL2 fill:#ec7063
    style VAL3 fill:#58d68d
    style LOCK fill:#f39c12
    style RELOAD fill:#ec7063
    style SUCCESS fill:#58d68d
    style FAIL fill:#ec7063
```

**Critical Functions:**
- `validate_username()` - Regex: `^[a-z][a-z0-9_-]{2,31}$`
- `flock_acquire()` - File lock: `/var/lock/familytraffic_users.lock`, timeout: 10s
- `atomic_write_json()` - Pattern: write to temp → `mv -f temp users.json`
- `reload_xray()` - Method: `docker exec familytraffic kill -HUP $(pidof xray)`

**Error Handling:**
- Username validation failure → Exit code 1
- Lock timeout → Exit code 2
- Xray config invalid → Rollback users.json, Exit code 3
- Xray reload failed → Manual intervention required

---

## 2. Remove User Flow

**Entry Point:** `vless remove-user <username>`
**Duration:** ~2-4 seconds
**Module:** lib/user_management.sh

```mermaid
graph TB
    CLI["🟦 CLI Entry<br/>vless remove-user alice"]
    CMD["🟩 cmd_remove_user()<br/>scripts/vless:234"]

    subgraph "Validation"
        CHECK["🟥 check_user_exists()<br/>user_management.sh:278"]
        CONFIRM["🟩 prompt_confirmation()<br/>user_management.sh:1123"]
    end

    subgraph "Cleanup Operations"
        RMJSON["🟨 remove_user_from_json()<br/>user_management.sh:1178"]
        RMXRAY["🟨 remove_client_from_xray()<br/>user_management.sh:1234"]
        RMFILES["🟧 cleanup_client_files()<br/>user_management.sh:1289"]
    end

    RELOAD["🟥 reload_xray()<br/>user_management.sh:834"]
    SUCCESS["✅ User Removed"]

    CLI --> CMD
    CMD --> CHECK
    CHECK --> CONFIRM
    CONFIRM -->|Yes| RMJSON
    CONFIRM -->|No| SUCCESS
    RMJSON --> RMXRAY
    RMXRAY --> RMFILES
    RMFILES --> RELOAD
    RELOAD --> SUCCESS

    style CLI fill:#5dade2
    style CHECK fill:#ec7063
    style SUCCESS fill:#58d68d
```

**Critical Operations:**
- User confirmation prompt (prevents accidental deletion)
- Atomic JSON update with rollback capability
- Cleanup of `/opt/familytraffic/data/clients/<username>/` directory
- Xray graceful reload with zero downtime

---

## 3. Set Per-User Proxy Flow (v5.24+)

**Entry Point:** `vless set-proxy <username> <proxy-id|none>`
**Duration:** ~4-6 seconds
**Module:** lib/user_management.sh, lib/xray_routing_manager.sh

```mermaid
graph TB
    CLI["🟦 CLI Entry<br/>vless set-proxy alice proxy1"]
    CMD["🟩 cmd_set_user_proxy()<br/>scripts/vless:312"]

    subgraph "Validation Layer"
        VUSER["🟥 validate_user_exists()<br/>user_management.sh:278"]
        VPROXY["🟥 validate_proxy_exists()<br/>external_proxy_manager.sh:567"]
        VTEST["🟥 test_proxy_connectivity()<br/>external_proxy_manager.sh:623"]
    end

    subgraph "Database Update"
        UPDATE["🟨 update_user_proxy_id()<br/>user_management.sh:1456"]
        LOCK["🟧 flock /var/lock/familytraffic_users.lock"]
        WRITE["🟧 atomic_write_json()"]
    end

    subgraph "Xray Routing Configuration"
        ROUTE["🟨 update_xray_routing_for_user()<br/>xray_routing_manager.sh:234"]
        GENRULE["🟨 generate_routing_rule()<br/>xray_routing_manager.sh:345"]
        GENOUT["🟨 update_outbound_config()<br/>xray_routing_manager.sh:456"]
    end

    VALIDATE["🟥 validate_xray_config()<br/>user_management.sh:789"]
    RELOAD["🟥 reload_xray()<br/>user_management.sh:834"]
    VERIFY["🟥 verify_routing_active()<br/>xray_routing_manager.sh:678"]
    SUCCESS["✅ Proxy Assigned"]
    FAIL["❌ Rollback"]

    CLI --> CMD
    CMD --> VUSER
    VUSER --> VPROXY
    VPROXY --> VTEST

    VTEST -->|Pass| UPDATE
    VTEST -->|Fail| FAIL

    UPDATE --> LOCK
    LOCK --> WRITE
    WRITE --> ROUTE

    ROUTE --> GENRULE
    GENRULE --> GENOUT
    GENOUT --> VALIDATE

    VALIDATE -->|Valid| RELOAD
    VALIDATE -->|Invalid| FAIL

    RELOAD --> VERIFY
    VERIFY --> SUCCESS

    style CLI fill:#5dade2
    style VUSER fill:#ec7063
    style VPROXY fill:#ec7063
    style VTEST fill:#ec7063
    style RELOAD fill:#ec7063
    style SUCCESS fill:#58d68d
    style FAIL fill:#ec7063
```

**Critical Validations:**
- User existence in `/opt/familytraffic/data/users.json`
- Proxy existence in `/opt/familytraffic/config/external_proxy.json`
- Proxy connectivity test: `curl --proxy socks5h://... https://www.google.com`
- Xray routing rule syntax validation

**Routing Rule Generated:**
```json
{
  "type": "field",
  "user": ["alice@vless.example.com"],
  "outboundTag": "external-proxy"
}
```

**State Changes:**
- `users.json`: `users[alice].external_proxy_id = "proxy1"`
- `xray_config.json`: New routing rule in `routing.rules[]`
- Xray runtime: User traffic routed through external proxy

---

## 4. Add Reverse Proxy Domain Flow

**Entry Point:** `familytraffic-proxy add`
**Duration:** ~8-12 seconds (includes DNS validation)
**Modules:** lib/reverseproxy_db.sh, lib/haproxy_config_manager.sh

```mermaid
graph TB
    CLI["🟦 CLI Entry<br/>familytraffic-proxy add"]
    WIZARD["🟩 interactive_add_domain()<br/>scripts/familytraffic-proxy:123"]

    subgraph "Input Collection"
        DOMAIN["🟩 prompt_domain_name()"]
        TARGET["🟩 prompt_target_url()"]
        OPTIONS["🟩 prompt_advanced_options()"]
    end

    subgraph "Validation Layer"
        VDNS["🟥 validate_dns_for_domain()<br/>certificate_manager.sh:456"]
        VTARGET["🟥 test_target_connectivity()<br/>reverseproxy_db.sh:234"]
        VUNIQUE["🟥 check_domain_unique()<br/>reverseproxy_db.sh:289"]
    end

    subgraph "Certificate Management"
        CERTCHECK["🟨 check_certificate_exists()<br/>certificate_manager.sh:567"]
        CERTGEN["🟨 obtain_certificate()<br/>letsencrypt_integration.sh:234"]
        COMBINE["🟧 create_combined_pem()<br/>certificate_manager.sh:678"]
    end

    subgraph "Nginx Configuration"
        GENNGINX["🟨 generate_nginx_config()<br/>reverseproxy_db.sh:456"]
        ADDZONE["🟨 add_rate_limit_zone()<br/>reverseproxy_db.sh:523"]
        WRITENGINX["🟧 write_nginx_config_file()"]
        TESTNGINX["🟥 test_nginx_config()<br/>nginx -t"]
    end

    subgraph "HAProxy Configuration"
        GENACL["🟨 generate_haproxy_acl()<br/>haproxy_config_manager.sh:789"]
        UPDATECFG["🟧 update_haproxy_config()<br/>haproxy_config_manager.sh:845"]
        TESTHAPROXY["🟥 test_haproxy_config()<br/>haproxy -c"]
    end

    subgraph "Service Reloads"
        RLHAPROXY["🟥 reload_haproxy()<br/>haproxy_config_manager.sh:923"]
        RLNGINX["🟥 reload_nginx()<br/>docker restart familytraffic-nginx"]
    end

    VERIFY["🟥 verify_domain_accessible()<br/>curl https://domain"]
    SUCCESS["✅ Domain Added"]
    FAIL["❌ Rollback"]

    CLI --> WIZARD
    WIZARD --> DOMAIN
    DOMAIN --> TARGET
    TARGET --> OPTIONS

    OPTIONS --> VDNS
    VDNS --> VTARGET
    VTARGET --> VUNIQUE

    VUNIQUE --> CERTCHECK
    CERTCHECK -->|Exists| GENNGINX
    CERTCHECK -->|Missing| CERTGEN
    CERTGEN --> COMBINE
    COMBINE --> GENNGINX

    GENNGINX --> ADDZONE
    ADDZONE --> WRITENGINX
    WRITENGINX --> TESTNGINX

    TESTNGINX -->|Pass| GENACL
    TESTNGINX -->|Fail| FAIL

    GENACL --> UPDATECFG
    UPDATECFG --> TESTHAPROXY

    TESTHAPROXY -->|Pass| RLHAPROXY
    TESTHAPROXY -->|Fail| FAIL

    RLHAPROXY --> RLNGINX
    RLNGINX --> VERIFY
    VERIFY --> SUCCESS

    style CLI fill:#5dade2
    style VDNS fill:#ec7063
    style TESTNGINX fill:#ec7063
    style TESTHAPROXY fill:#ec7063
    style SUCCESS fill:#58d68d
    style FAIL fill:#ec7063
```

**Critical Operations:**
- DNS validation: Domain must point to server IP
- Certificate obtainment: Let's Encrypt HTTP-01 challenge
- Rate limit zone: `limit_req_zone $binary_remote_addr zone=...`
- HAProxy dynamic ACL injection: `### DYNAMIC_REVERSE_PROXY_ROUTES ###`

**Files Modified:**
1. `/opt/familytraffic/config/reverse-proxy/<domain>.conf` (created)
2. `/opt/familytraffic/config/reverse-proxy/http_context.conf` (rate limit zone added)
3. `/opt/familytraffic/config/haproxy.cfg` (ACL rule added)
4. `/etc/letsencrypt/live/<domain>/` (certificate)

**Rollback Strategy:**
- Nginx config validation failure → Remove generated files
- HAProxy config validation failure → Restore previous haproxy.cfg
- Service reload failure → Manual intervention required

---

## 5. Certificate Renewal Flow (Automated)

**Entry Point:** Certbot cron job (runs twice daily)
**Duration:** ~30-60 seconds
**Module:** lib/certificate_manager.sh

```mermaid
graph TB
    CRON["🟦 Cron Trigger<br/>certbot renew (twice daily)"]

    subgraph "Certbot Renewal"
        CHECK["🟩 certbot renew --dry-run<br/>Check expiration"]
        RENEW["🟨 certbot renew --quiet<br/>Obtain new certificate"]
    end

    subgraph "Post-Renewal Hook"
        HOOK["🟩 deploy_hook()<br/>certificate_manager.sh:1234"]
        DETECT["🟩 detect_renewed_domains()"]

        subgraph "For Each Renewed Domain"
            COMBINE["🟧 create_combined_pem()<br/>certificate_manager.sh:678"]
            PERMS["🟧 chmod 600 combined.pem"]
            BACKUP["🟧 backup_old_certificate()"]
        end
    end

    subgraph "Service Reloads"
        RLHAPROXY["🟥 reload_haproxy_graceful()<br/>haproxy -sf <old_pid>"]
        RLNGINX["🟥 reload_nginx_reverseproxy()"]
        VERIFY["🟥 verify_certificate_active()<br/>openssl s_client"]
    end

    NOTIFY["🟩 send_notification()<br/>Email/Log success"]
    SUCCESS["✅ Renewal Complete"]
    FAIL["❌ Renewal Failed<br/>Alert Admin"]

    CRON --> CHECK
    CHECK -->|Needs Renewal| RENEW
    CHECK -->|Up to Date| SUCCESS

    RENEW -->|Success| HOOK
    RENEW -->|Failed| FAIL

    HOOK --> DETECT
    DETECT --> COMBINE
    COMBINE --> PERMS
    PERMS --> BACKUP

    BACKUP --> RLHAPROXY
    RLHAPROXY --> RLNGINX
    RLNGINX --> VERIFY

    VERIFY -->|Success| NOTIFY
    VERIFY -->|Failed| FAIL

    NOTIFY --> SUCCESS

    style CRON fill:#5dade2
    style RENEW fill:#f4d03f
    style RLHAPROXY fill:#ec7063
    style SUCCESS fill:#58d68d
    style FAIL fill:#ec7063
```

**Critical Operations:**
- Certificate expiration check: 30 days before expiry
- Combined PEM creation: `cat fullchain.pem privkey.pem > combined.pem`
- HAProxy graceful reload: Zero downtime (`-sf` flag)
- Certificate verification: `openssl s_client -connect domain:443`

**Cron Schedule:**
```cron
0 */12 * * * /usr/bin/certbot renew --quiet --deploy-hook "/opt/familytraffic/lib/certificate_manager.sh deploy_hook"
```

**Error Handling:**
- Renewal failure → Email alert to LETSENCRYPT_EMAIL
- Hook failure → Log to `/opt/familytraffic/logs/certbot_errors.log`
- Service reload failure → Retry after 60 seconds (max 3 attempts)

---

## 6. External Proxy Management Flow (v5.24+)

**Entry Point:** `familytraffic-external-proxy add`
**Duration:** ~10-15 seconds (includes connectivity test)
**Module:** lib/external_proxy_manager.sh

```mermaid
graph TB
    CLI["🟦 CLI Entry<br/>familytraffic-external-proxy add"]
    WIZARD["🟩 interactive_add_proxy()<br/>scripts/familytraffic-external-proxy:89"]

    subgraph "Input Collection"
        TYPE["🟩 prompt_proxy_type()<br/>socks5/socks5s/http/https"]
        ADDR["🟩 prompt_proxy_address()"]
        CREDS["🟩 prompt_credentials()"]
    end

    subgraph "Validation & Testing"
        VFORMAT["🟥 validate_proxy_format()<br/>external_proxy_manager.sh:234"]
        TEST["🟥 test_proxy_connectivity()<br/>external_proxy_manager.sh:623"]

        subgraph "Connectivity Tests"
            TEST1["🟨 curl --proxy ... http://www.google.com"]
            TEST2["🟨 curl --proxy ... https://www.anthropic.com"]
            TEST3["🟨 Measure latency & bandwidth"]
        end
    end

    subgraph "Database Operations"
        GENID["🟩 generate_proxy_id()<br/>external_proxy_manager.sh:723"]
        ADD["🟨 add_proxy_to_json()<br/>external_proxy_manager.sh:789"]
        ENCRYPT["🟧 encrypt_credentials()<br/>base64 + chmod 600"]
    end

    subgraph "Xray Configuration Update"
        UPDATEOUT["🟨 update_xray_outbounds()<br/>external_proxy_manager.sh:856"]
        GENCONFIG["🟨 generate_xray_config()<br/>orchestrator.sh:1234"]
        VALIDATE["🟥 validate_xray_config()"]
    end

    RESTART["🟥 restart_xray_container()<br/>docker restart familytraffic"]
    VERIFY["🟥 verify_proxy_routing()<br/>Test with temp user"]
    SUCCESS["✅ Proxy Added<br/>Show proxy ID"]
    FAIL["❌ Operation Failed"]

    CLI --> WIZARD
    WIZARD --> TYPE
    TYPE --> ADDR
    ADDR --> CREDS

    CREDS --> VFORMAT
    VFORMAT --> TEST
    TEST --> TEST1
    TEST1 --> TEST2
    TEST2 --> TEST3

    TEST3 -->|Pass| GENID
    TEST3 -->|Fail| FAIL

    GENID --> ADD
    ADD --> ENCRYPT
    ENCRYPT --> UPDATEOUT

    UPDATEOUT --> GENCONFIG
    GENCONFIG --> VALIDATE

    VALIDATE -->|Valid| RESTART
    VALIDATE -->|Invalid| FAIL

    RESTART --> VERIFY
    VERIFY --> SUCCESS

    style CLI fill:#5dade2
    style VFORMAT fill:#ec7063
    style TEST fill:#ec7063
    style VALIDATE fill:#ec7063
    style SUCCESS fill:#58d68d
    style FAIL fill:#ec7063
```

**Critical Validations:**
- Proxy format: `protocol://[user:pass@]host:port`
- Connectivity test: Must complete within 10 seconds
- Latency test: Log latency for user reference
- Xray outbound configuration syntax

**External Proxy JSON Structure:**
```json
{
  "proxies": [
    {
      "id": "proxy1",
      "name": "US Proxy",
      "type": "socks5s",
      "address": "proxy.example.com",
      "port": 1080,
      "credentials": {
        "username": "user",
        "password": "base64_encrypted"
      },
      "enabled": true
    }
  ]
}
```

**Xray Outbound Configuration:**
```json
{
  "tag": "external-proxy",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "proxy.example.com",
        "port": 1080,
        "users": [
          {
            "user": "user",
            "pass": "password"
          }
        ]
      }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls"
  }
}
```

**Error Handling:**
- Proxy unreachable → Retry with exponential backoff (1s, 2s, 4s)
- Authentication failure → Prompt to re-enter credentials
- Xray restart failure → Rollback external_proxy.json

---

## Call Chain Summary Table

| Operation | Entry Point | Primary Module | Key Functions | Duration | Criticality |
|-----------|-------------|----------------|---------------|----------|-------------|
| **Add User** | `vless add-user` | user_management.sh | validate_username()<br/>add_user_to_json()<br/>reload_xray() | ~3-5s | HIGH |
| **Remove User** | `vless remove-user` | user_management.sh | check_user_exists()<br/>remove_user_from_json()<br/>cleanup_client_files() | ~2-4s | HIGH |
| **Set Proxy** | `vless set-proxy` | user_management.sh<br/>xray_routing_manager.sh | validate_proxy_exists()<br/>update_xray_routing_for_user()<br/>reload_xray() | ~4-6s | MEDIUM |
| **Add Domain** | `familytraffic-proxy add` | reverseproxy_db.sh<br/>haproxy_config_manager.sh | validate_dns_for_domain()<br/>generate_nginx_config()<br/>reload_haproxy() | ~8-12s | MEDIUM |
| **Cert Renewal** | certbot renew (cron) | certificate_manager.sh | create_combined_pem()<br/>reload_haproxy_graceful() | ~30-60s | CRITICAL |
| **Add Ext Proxy** | `familytraffic-external-proxy add` | external_proxy_manager.sh | test_proxy_connectivity()<br/>add_proxy_to_json()<br/>restart_xray_container() | ~10-15s | MEDIUM |

---

## Function Call Depth Analysis

**Maximum Call Stack Depth by Operation:**

```
add-user:
  vless CLI (depth 1)
  └─ cmd_add_user() (depth 2)
     ├─ validate_username() (depth 3)
     ├─ add_user_to_json() (depth 3)
     │  ├─ flock_acquire() (depth 4)
     │  └─ atomic_write_json() (depth 4)
     ├─ add_client_to_xray() (depth 3)
     │  └─ generate_xray_config() (depth 4)
     │     └─ jq operations (depth 5)
     └─ generate_qr_code() (depth 3)
        └─ qrencode (depth 4)

Maximum Depth: 5 levels
```

**set-proxy (v5.24):**

```
vless set-proxy (depth 1)
└─ cmd_set_user_proxy() (depth 2)
   ├─ validate_proxy_exists() (depth 3)
   │  └─ jq query external_proxy.json (depth 4)
   ├─ update_user_proxy_id() (depth 3)
   │  ├─ flock_acquire() (depth 4)
   │  └─ jq update users.json (depth 4)
   └─ update_xray_routing_for_user() (depth 3)
      ├─ generate_routing_rule() (depth 4)
      │  └─ jq construct rule (depth 5)
      └─ update_outbound_config() (depth 4)
         └─ jq merge config (depth 5)

Maximum Depth: 5 levels
```

**add-domain:**

```
familytraffic-proxy add (depth 1)
└─ interactive_add_domain() (depth 2)
   ├─ validate_dns_for_domain() (depth 3)
   │  └─ dig +short domain (depth 4)
   ├─ obtain_certificate() (depth 3)
   │  └─ certbot certonly (depth 4)
   │     └─ ACME challenge (depth 5)
   ├─ generate_nginx_config() (depth 3)
   │  └─ sed templating (depth 4)
   └─ update_haproxy_config() (depth 3)
      └─ sed ACL injection (depth 4)

Maximum Depth: 5 levels
```

---

## Critical Path Analysis

**Longest Critical Path:** Certificate Renewal Flow (automated)

```
certbot renew
└─ Check expiration (1-2s)
   └─ ACME HTTP-01 challenge (5-15s) ← NETWORK DEPENDENT
      └─ Download new certificate (1-3s)
         └─ create_combined_pem() (< 1s)
            └─ reload_haproxy() (< 1s)
               └─ reload_nginx() (< 1s)
                  └─ verify_certificate_active() (2-5s) ← NETWORK DEPENDENT

Total: 10-27 seconds (variable due to network)
```

**Fastest Critical Path:** Remove User Flow

```
vless remove-user
└─ check_user_exists() (< 0.1s)
   └─ remove_user_from_json() (< 0.5s)
      └─ remove_client_from_xray() (< 0.5s)
         └─ reload_xray() (< 1s)
            └─ cleanup_client_files() (< 0.5s)

Total: ~2-3 seconds
```

---

## Error Recovery Call Chains

### Rollback on User Add Failure

```mermaid
graph LR
    ERR["❌ Error Detected"]
    DETECT["🟥 detect_error_stage()"]

    subgraph "Rollback Decision Tree"
        STAGE1["Stage: After JSON write?"]
        STAGE2["Stage: After Xray config?"]
        STAGE3["Stage: After Xray reload?"]
    end

    RB1["🟧 Restore users.json from backup"]
    RB2["🟧 Restore xray_config.json from backup"]
    RB3["🟥 Manual intervention required"]

    UNLOCK["🟧 Release all locks"]
    CLEANUP["🟧 Remove partial client files"]
    LOG["🟧 Log error details"]
    EXIT["Exit code: 1"]

    ERR --> DETECT
    DETECT --> STAGE1
    STAGE1 -->|Yes| RB1
    STAGE1 -->|No| STAGE2
    STAGE2 -->|Yes| RB2
    STAGE2 -->|No| STAGE3
    STAGE3 --> RB3

    RB1 --> UNLOCK
    RB2 --> UNLOCK
    UNLOCK --> CLEANUP
    CLEANUP --> LOG
    LOG --> EXIT

    style ERR fill:#ec7063
    style RB3 fill:#ec7063
```

**Rollback Guarantees:**
- JSON operations: Atomic (temp file → rename)
- Config operations: Backup created before modification
- Service reloads: Non-destructive (config validation first)
- Locks: Always released (trap EXIT in bash)

---

## Performance Hotspots

**Identified bottlenecks from profiling:**

1. **JSON Parsing (jq operations)** - ~40% of execution time
   - `jq` operations in add_user_to_json(): ~1.5s
   - Optimization: Use jq streaming API for large users.json (>1000 users)

2. **Xray Config Regeneration** - ~25% of execution time
   - generate_xray_config(): ~0.8s
   - Optimization: Incremental updates instead of full regeneration

3. **Docker Exec Operations** - ~20% of execution time
   - docker exec familytraffic: ~0.6s overhead per call
   - Optimization: Batch operations where possible

4. **File I/O Operations** - ~10% of execution time
   - Multiple reads/writes to /opt/familytraffic/data/
   - Optimization: Use tmpfs for temporary operations

5. **Network Operations** - ~5% of execution time (variable)
   - DNS lookups, ACME challenges, proxy connectivity tests
   - Optimization: Caching DNS results, parallel testing

---

## Concurrency & Locking

**File Locks Used:**

| Lock File | Purpose | Scope | Timeout |
|-----------|---------|-------|---------|
| `/var/lock/familytraffic_users.lock` | Serialize users.json modifications | All user operations | 10s |
| `/var/lock/familytraffic_config.lock` | Serialize xray_config.json updates | Config regeneration | 15s |
| `/var/lock/familytraffic-haproxy.lock` | Serialize HAProxy reloads | HAProxy operations | 5s |
| `/var/lock/familytraffic_external_proxy.lock` | Serialize external_proxy.json updates | Proxy management (v5.24+) | 10s |

**Lock Acquisition Order (prevents deadlock):**
1. users.lock (if needed)
2. external_proxy.lock (if needed)
3. xray_config.lock (if needed)
4. haproxy.lock (if needed)

**CRITICAL:** Always acquire locks in this order to prevent deadlock.

---

## Module Interaction Summary

**Most Called Functions (by frequency):**

1. **validate_xray_config()** - Called by 8 different operations
2. **reload_xray()** - Called by 6 different operations
3. **flock_acquire()** - Called by 5 different operations
4. **atomic_write_json()** - Called by 4 different operations
5. **generate_xray_config()** - Called by 3 different operations

**Module Coupling Analysis:**

| Module | Depends On | Used By | Coupling Level |
|--------|------------|---------|----------------|
| user_management.sh | xray_routing_manager.sh, qr_generator.sh | scripts/vless | HIGH |
| xray_routing_manager.sh | orchestrator.sh | user_management.sh, external_proxy_manager.sh | HIGH |
| external_proxy_manager.sh | xray_routing_manager.sh | scripts/familytraffic-external-proxy, user_management.sh | MEDIUM |
| haproxy_config_manager.sh | orchestrator.sh | reverseproxy_db.sh, certificate_manager.sh | MEDIUM |
| certificate_manager.sh | haproxy_config_manager.sh | letsencrypt_integration.sh, certbot hooks | LOW |

---

## Testing Call Chains

**Test Suite Execution Flow (v4.3+):**

```mermaid
graph TB
    TEST["🟦 vless test-security"]

    subgraph "Security Tests"
        T1["🟥 test_tls_versions()<br/>Verify TLS 1.3 only"]
        T2["🟥 test_weak_ciphers()<br/>Reject weak ciphers"]
        T3["🟥 test_certificate_validity()<br/>Check cert expiration"]
    end

    subgraph "Connectivity Tests"
        T4["🟨 test_vless_connectivity()<br/>VLESS Reality handshake"]
        T5["🟨 test_socks5_auth()<br/>SOCKS5 authentication"]
        T6["🟨 test_http_proxy()<br/>HTTP CONNECT method"]
    end

    subgraph "Routing Tests (v5.24+)"
        T7["🟨 test_external_proxy_routing()<br/>Per-user proxy routing"]
        T8["🟨 test_routing_fallback()<br/>Fallback to direct"]
    end

    REPORT["📊 Generate Test Report<br/>tests/security_test_report.log"]

    TEST --> T1
    T1 --> T2
    T2 --> T3
    T3 --> T4
    T4 --> T5
    T5 --> T6
    T6 --> T7
    T7 --> T8
    T8 --> REPORT

    style TEST fill:#5dade2
    style T1 fill:#ec7063
    style REPORT fill:#58d68d
```

**Test Execution Time:** ~45-60 seconds (full suite)

---

## Conclusion

This document provides complete traceability of function call chains during runtime operations. All major workflows are documented with:
- ✅ Entry points and CLI commands
- ✅ Complete function call graphs
- ✅ Module interactions
- ✅ Critical validations
- ✅ Error handling and rollback procedures
- ✅ Performance characteristics
- ✅ Concurrency and locking mechanisms

**For implementation details, see:**
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - Complete module specifications
- [dependencies.yaml](../../yaml/dependencies.yaml) - Static dependencies
- [Module Dependencies](module-dependencies.md) - Module relationship graph
- [Initialization Order](initialization-order.md) - Installation sequence

---

**Version:** v5.26
**Last Updated:** 2025-01-07
**Status:** Production Documentation

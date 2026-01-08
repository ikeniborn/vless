# Module Dependencies Graph

**Purpose:** Visualize the complete dependency graph for all 44 shell modules in lib/

**Scope:** Module-to-module dependencies, initialization order, call relationships

**Total Modules:** 44 modules, ~26,500 lines of shell code

---

## High-Level Module Categories

### Module Organization

```mermaid
graph TB
    subgraph "Core Orchestration (3 modules)"
        Orch[orchestrator.sh<br/>1881 lines]
        Install[installation_manager.sh<br/>~500 lines]
        Workflow[workflow_coordinator.sh<br/>~400 lines]
    end

    subgraph "User & Proxy Management (4 modules)"
        UserMgmt[user_management.sh<br/>3000 lines]
        ExtProxy[external_proxy_manager.sh<br/>1100 lines]
        ReverseProxy[reverseproxy_db.sh<br/>~600 lines]
        MTProxyMgr[mtproxy_manager.sh<br/>~400 lines]
    end

    subgraph "Configuration Generators (6 modules)"
        HAProxyGen[haproxy_config_manager.sh<br/>809 lines]
        XrayRouting[xray_routing_manager.sh<br/>~700 lines]
        DockerGen[docker_compose_generator.sh<br/>~550 lines]
        NginxGen[nginx_config_generator.sh<br/>~450 lines]
        MTProxySecrets[mtproxy_secret_manager.sh<br/>~400 lines]
        ConfigValidator[config_validator.sh<br/>~300 lines]
    end

    subgraph "Infrastructure & Security (7 modules)"
        CertMgr[certificate_manager.sh<br/>~500 lines]
        LetsEncrypt[letsencrypt_integration.sh<br/>~450 lines]
        Security[security_hardening.sh<br/>~600 lines]
        Firewall[firewall_manager.sh<br/>~400 lines]
        Fail2ban[fail2ban_integration.sh<br/>~350 lines]
        DockerMgr[docker_manager.sh<br/>~500 lines]
        NetworkMgr[network_manager.sh<br/>~300 lines]
    end

    subgraph "Utilities & Helpers (24 modules)"
        QRGen[qr_generator.sh<br/>~200 lines]
        Logger[logger.sh<br/>~250 lines]
        Validator[validator.sh<br/>~300 lines]
        Interactive[interactive_params.sh<br/>~800 lines]
        Others[... 20 more utility modules<br/>~12,000 lines total]
    end

    Orch --> UserMgmt
    Orch --> HAProxyGen
    Orch --> DockerGen
    Orch --> CertMgr
    Orch --> Security

    UserMgmt --> XrayRouting
    ExtProxy --> XrayRouting
    ReverseProxy --> HAProxyGen
    ReverseProxy --> NginxGen

    MTProxyMgr --> MTProxySecrets

    style Orch fill:#fff4e1,stroke:#ff9900,stroke-width:3px
    style UserMgmt fill:#e1ffe1,stroke:#00cc00,stroke-width:3px
    style HAProxyGen fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
```

---

## Core Module Dependencies

### orchestrator.sh - Main Installation Coordinator

```mermaid
graph TB
    Orch[orchestrator.sh<br/>Main Entry Point]

    subgraph "Phase 1: Initialization"
        OSDetect[os_detection.sh]
        Deps[dependencies.sh]
        Prereq[prerequisite_checker.sh]
    end

    subgraph "Phase 2: Interactive Input"
        Interactive[interactive_params.sh]
        DomainValidator[domain_validator.sh]
        DNSValidator[dns_validator.sh]
    end

    subgraph "Phase 3: Certificate Management"
        CertMgr[certificate_manager.sh]
        LetsEncrypt[letsencrypt_integration.sh]
    end

    subgraph "Phase 4: Configuration Generation"
        DockerGen[docker_compose_generator.sh]
        HAProxyGen[haproxy_config_manager.sh]
        XrayGen[xray_config_generator.sh]
        NginxGen[nginx_config_generator.sh]
    end

    subgraph "Phase 5: Security Hardening"
        Security[security_hardening.sh]
        Firewall[firewall_manager.sh]
        Fail2ban[fail2ban_integration.sh]
    end

    subgraph "Phase 6: Service Startup"
        DockerMgr[docker_manager.sh]
        HealthCheck[health_checker.sh]
        PostInstall[post_install_tasks.sh]
    end

    Orch --> OSDetect
    Orch --> Deps
    Orch --> Prereq

    Prereq --> Interactive
    Interactive --> DomainValidator
    Interactive --> DNSValidator

    DNSValidator --> CertMgr
    CertMgr --> LetsEncrypt

    LetsEncrypt --> DockerGen
    DockerGen --> HAProxyGen
    DockerGen --> XrayGen
    DockerGen --> NginxGen

    XrayGen --> Security
    Security --> Firewall
    Security --> Fail2ban

    Fail2ban --> DockerMgr
    DockerMgr --> HealthCheck
    HealthCheck --> PostInstall

    style Orch fill:#fff4e1,stroke:#ff9900,stroke-width:4px
```

---

## User Management Dependencies

### user_management.sh - User CRUD Operations

```mermaid
graph TB
    UserMgmt[user_management.sh<br/>User Management]

    subgraph "Direct Dependencies"
        XrayRouting[xray_routing_manager.sh<br/>Routing Rules]
        QRGen[qr_generator.sh<br/>QR Code Generation]
        UUID[uuid_generator.sh<br/>UUID Generation]
        PasswordHash[password_hasher.sh<br/>Password Hashing]
        ConfigValidator[config_validator.sh<br/>Config Validation]
    end

    subgraph "Data Files"
        UsersJSON[users.json<br/>User Database]
        XrayConfig[xray_config.json<br/>Xray Configuration]
        ClientConfigs[Client Config Files<br/>/data/clients/]
    end

    subgraph "Service Interactions"
        XrayReload[Xray Container<br/>SIGHUP Reload]
        FileLock[File Lock<br/>/var/lock/vless_users.lock]
    end

    UserMgmt --> UUID
    UserMgmt --> PasswordHash
    UserMgmt --> XrayRouting
    UserMgmt --> QRGen
    UserMgmt --> ConfigValidator

    UserMgmt --> UsersJSON
    UserMgmt --> XrayConfig
    UserMgmt --> ClientConfigs

    UserMgmt --> FileLock
    UserMgmt --> XrayReload

    XrayRouting --> XrayConfig

    style UserMgmt fill:#e1ffe1,stroke:#00cc00,stroke-width:4px
```

**Key Functions and Their Dependencies:**

| Function | Depends On | Purpose |
|----------|------------|---------|
| `cmd_add_user()` | uuid_generator.sh, password_hasher.sh | Generate credentials |
| `add_user_to_json()` | File locking, JSON validation | Atomic database update |
| `add_client_to_xray()` | xray_routing_manager.sh | Update Xray inbounds |
| `generate_client_configs()` | qr_generator.sh | Create client files |
| `reload_xray()` | Docker exec, health_checker.sh | Graceful reload |

---

## External Proxy Dependencies

### external_proxy_manager.sh - Upstream Proxy Management (v5.24+)

```mermaid
graph TB
    ExtProxy[external_proxy_manager.sh<br/>External Proxy Management]

    subgraph "Direct Dependencies"
        ProxyTester[proxy_tester.sh<br/>Connectivity Test]
        XrayRouting[xray_routing_manager.sh<br/>Routing Rules]
        PasswordEncrypt[password_encryptor.sh<br/>Credential Encryption]
        URLParser[url_parser.sh<br/>URL Validation]
    end

    subgraph "Data Files"
        ProxyJSON[external_proxy.json<br/>Proxy Database]
        UsersJSON[users.json<br/>User Database]
        XrayConfig[xray_config.json<br/>Xray Config]
    end

    subgraph "Service Interactions"
        XrayReload[Xray Container<br/>Reload for Routing]
        CurlTest[curl Test<br/>Connectivity Validation]
    end

    ExtProxy --> ProxyTester
    ExtProxy --> XrayRouting
    ExtProxy --> PasswordEncrypt
    ExtProxy --> URLParser

    ExtProxy --> ProxyJSON
    ExtProxy --> UsersJSON
    ExtProxy --> XrayConfig

    ProxyTester --> CurlTest
    XrayRouting --> XrayReload

    style ExtProxy fill:#ffe1f5,stroke:#cc0099,stroke-width:4px
```

---

## Configuration Generator Dependencies

### haproxy_config_manager.sh - HAProxy Configuration

```mermaid
graph TB
    HAProxyGen[haproxy_config_manager.sh<br/>HAProxy Config Generator]

    subgraph "Input Data"
        Domain[Domain Name<br/>From installer]
        RPDatabase[Reverse Proxy DB<br/>Dynamic domains]
        CertPath[Certificate Path<br/>/etc/letsencrypt/]
    end

    subgraph "Template System"
        BaseTemplate[haproxy_base.cfg.template<br/>Static Configuration]
        DynamicMarkers[Dynamic Markers<br/>DYNAMIC_REVERSE_PROXY_ROUTES]
    end

    subgraph "Output"
        HAProxyConfig[haproxy.cfg<br/>Final Configuration]
    end

    subgraph "Validation"
        HAProxyValidate[HAProxy Syntax Check<br/>haproxy -c -f]
        HAProxyReload[HAProxy Reload<br/>haproxy -sf]
    end

    HAProxyGen --> Domain
    HAProxyGen --> RPDatabase
    HAProxyGen --> CertPath

    HAProxyGen --> BaseTemplate
    HAProxyGen --> DynamicMarkers

    BaseTemplate --> HAProxyConfig
    DynamicMarkers --> HAProxyConfig

    HAProxyConfig --> HAProxyValidate
    HAProxyValidate --> HAProxyReload

    style HAProxyGen fill:#e1f5ff,stroke:#0066cc,stroke-width:4px
```

**Template Structure:**
```haproxy
# Static section (from template)
frontend https_sni_router
    bind *:443
    mode tcp

    # Static VLESS ACL
    acl is_vless req_ssl_sni -i ${VLESS_DOMAIN}
    use_backend xray_vless if is_vless

    # DYNAMIC_REVERSE_PROXY_ROUTES
    # (Dynamically injected ACLs)
    # END_DYNAMIC_REVERSE_PROXY_ROUTES

    default_backend fake_site_fallback
```

---

## Xray Routing Dependencies

### xray_routing_manager.sh - Per-User Routing Rules

```mermaid
graph TB
    XrayRouting[xray_routing_manager.sh<br/>Routing Manager]

    subgraph "Input Data"
        UsersJSON[users.json<br/>User Assignments]
        ProxyJSON[external_proxy.json<br/>Proxy Definitions]
    end

    subgraph "Routing Logic"
        UserMapping[User-to-Proxy Mapping<br/>external_proxy_id field]
        RuleGenerator[Routing Rule Generator<br/>Per-user rules]
        OutboundGenerator[Outbound Generator<br/>Proxy configurations]
    end

    subgraph "Output"
        XrayConfig[xray_config.json<br/>routing.rules[] section]
    end

    subgraph "Validation"
        JSONValidate[JSON Syntax Check<br/>jq validation]
        XrayTest[Xray Config Test<br/>xray -test]
        XrayReload[Xray Reload<br/>SIGHUP]
    end

    XrayRouting --> UsersJSON
    XrayRouting --> ProxyJSON

    UsersJSON --> UserMapping
    ProxyJSON --> UserMapping

    UserMapping --> RuleGenerator
    UserMapping --> OutboundGenerator

    RuleGenerator --> XrayConfig
    OutboundGenerator --> XrayConfig

    XrayConfig --> JSONValidate
    JSONValidate --> XrayTest
    XrayTest --> XrayReload

    style XrayRouting fill:#fff9e1,stroke:#cc9900,stroke-width:4px
```

**Routing Rule Generation Logic:**
```javascript
// For each user with external_proxy_id != null
for (user in users) {
    if (user.external_proxy_id) {
        routing.rules.push({
            type: "field",
            inboundTag: ["vless-in", "socks-in", "http-in"],
            user: [user.email],
            outboundTag: `external-proxy-${user.external_proxy_id}`
        });

        // Generate outbound if not exists
        if (!outboundExists(user.external_proxy_id)) {
            outbounds.push(generateProxyOutbound(user.external_proxy_id));
        }
    }
}

// Default rule (must be last)
routing.rules.push({
    type: "field",
    outboundTag: "direct"
});
```

---

## MTProxy Dependencies (v6.0+)

### mtproxy_manager.sh - MTProxy Management

```mermaid
graph TB
    MTProxyMgr[mtproxy_manager.sh<br/>MTProxy Manager]

    subgraph "Direct Dependencies"
        SecretMgr[mtproxy_secret_manager.sh<br/>Secret Generation]
        ConfigGen[mtproxy_config_generator.sh<br/>Config Generation]
    end

    subgraph "Data Files"
        MTProxyConfig[mtproxy_config.json<br/>MTProxy Settings]
        ProxySecret[proxy-secret<br/>Multi-user Secrets]
        ProxyMulti[proxy-multi.conf<br/>Telegram DCs]
        UsersJSON[users.json<br/>User DB v6.1+]
    end

    subgraph "Service Interactions"
        MTProxyContainer[MTProxy Container<br/>Restart Required]
        StatsEndpoint[Stats Endpoint<br/>:8443/stats]
    end

    MTProxyMgr --> SecretMgr
    MTProxyMgr --> ConfigGen

    MTProxyMgr --> MTProxyConfig
    MTProxyMgr --> ProxySecret
    MTProxyMgr --> ProxyMulti
    MTProxyMgr -.-> UsersJSON

    SecretMgr --> ProxySecret
    ConfigGen --> MTProxyConfig

    MTProxyConfig --> MTProxyContainer
    MTProxyContainer --> StatsEndpoint

    style MTProxyMgr fill:#fff9e1,stroke:#cc9900,stroke-width:4px
```

**Note:** MTProxy v6.1 multi-user mode extends users.json with `mtproxy_secret` field

---

## Complete Dependency Matrix

### Module-to-Module Dependency Table

| Module | Direct Dependencies | Indirect Dependencies | Complexity |
|--------|-------------------|----------------------|------------|
| orchestrator.sh | 12 modules | 30+ modules | ★★★★★ |
| user_management.sh | 5 modules | 8 modules | ★★★★☆ |
| external_proxy_manager.sh | 4 modules | 6 modules | ★★★☆☆ |
| haproxy_config_manager.sh | 2 modules | 4 modules | ★★★☆☆ |
| xray_routing_manager.sh | 3 modules | 5 modules | ★★★☆☆ |
| certificate_manager.sh | 3 modules | 7 modules | ★★★☆☆ |
| docker_compose_generator.sh | 4 modules | 6 modules | ★★☆☆☆ |
| reverseproxy_db.sh | 3 modules | 5 modules | ★★☆☆☆ |
| mtproxy_manager.sh | 2 modules | 3 modules | ★★☆☆☆ |
| qr_generator.sh | 0 modules | 0 modules | ★☆☆☆☆ |
| logger.sh | 0 modules | 0 modules | ★☆☆☆☆ |
| validator.sh | 1 module | 1 module | ★☆☆☆☆ |

**Complexity Legend:**
- ★★★★★ Very High (orchestrator)
- ★★★★☆ High (user management)
- ★★★☆☆ Medium (config generators)
- ★★☆☆☆ Low (utilities)
- ★☆☆☆☆ Very Low (leaf modules)

---

## Circular Dependency Prevention

### No Circular Dependencies Detected

```mermaid
graph TB
    Layer1[Layer 1: Leaf Utilities<br/>logger.sh, validator.sh, uuid_generator.sh<br/>NO dependencies]

    Layer2[Layer 2: Basic Utilities<br/>qr_generator.sh, password_hasher.sh<br/>Depend only on Layer 1]

    Layer3[Layer 3: Specialized Utilities<br/>proxy_tester.sh, dns_validator.sh<br/>Depend on Layers 1-2]

    Layer4[Layer 4: Configuration Generators<br/>haproxy_config_manager.sh, xray_routing_manager.sh<br/>Depend on Layers 1-3]

    Layer5[Layer 5: Management Modules<br/>user_management.sh, external_proxy_manager.sh<br/>Depend on Layers 1-4]

    Layer6[Layer 6: Orchestration<br/>orchestrator.sh<br/>Depends on Layers 1-5]

    Layer1 --> Layer2
    Layer2 --> Layer3
    Layer3 --> Layer4
    Layer4 --> Layer5
    Layer5 --> Layer6

    style Layer1 fill:#e1ffe1
    style Layer2 fill:#e1f5ff
    style Layer3 fill:#ffe1f5
    style Layer4 fill:#fff9e1
    style Layer5 fill:#fff4e1
    style Layer6 fill:#f5e1e1
```

**Dependency Architecture:**
- **Layered Design:** Modules organized in 6 dependency layers
- **No Circular Dependencies:** Strict top-down dependency flow
- **Clear Separation:** Each layer has well-defined responsibilities
- **Testability:** Leaf modules can be tested independently

---

## Critical Path Analysis

### Installation Critical Path (Sequential Dependencies)

```mermaid
graph LR
    Start[Installation Start]
    OS[OS Detection]
    Deps[Install Dependencies]
    Params[Collect Parameters]
    DNS[Validate DNS]
    Cert[Obtain Certificate]
    Docker[Generate Docker Compose]
    HAProxy[Generate HAProxy Config]
    Xray[Generate Xray Config]
    Security[Security Hardening]
    Launch[Launch Containers]
    Health[Health Check]
    Done[Installation Complete]

    Start --> OS
    OS --> Deps
    Deps --> Params
    Params --> DNS
    DNS --> Cert
    Cert --> Docker
    Docker --> HAProxy
    HAProxy --> Xray
    Xray --> Security
    Security --> Launch
    Launch --> Health
    Health --> Done

    style Start fill:#e1f5ff
    style Done fill:#e1ffe1
```

**Duration:** ~5-7 minutes on fresh Ubuntu 22.04
**Critical Modules:** orchestrator.sh → dependencies.sh → certificate_manager.sh → docker_compose_generator.sh

---

## Module Source Lines of Code (SLOC)

### Top 10 Largest Modules

| Rank | Module | Lines | Percentage | Category |
|------|--------|-------|------------|----------|
| 1 | user_management.sh | 3,000 | 11.3% | User Management |
| 2 | orchestrator.sh | 1,881 | 7.1% | Orchestration |
| 3 | external_proxy_manager.sh | 1,100 | 4.2% | Proxy Management |
| 4 | haproxy_config_manager.sh | 809 | 3.1% | Config Generator |
| 5 | interactive_params.sh | 800 | 3.0% | Utility |
| 6 | xray_routing_manager.sh | 700 | 2.6% | Config Generator |
| 7 | reverseproxy_db.sh | 600 | 2.3% | Proxy Management |
| 8 | security_hardening.sh | 600 | 2.3% | Security |
| 9 | docker_compose_generator.sh | 550 | 2.1% | Config Generator |
| 10 | certificate_manager.sh | 500 | 1.9% | Infrastructure |
| ... | 34 other modules | ~16,460 | 62.1% | Various |
| **Total** | **44 modules** | **~26,500** | **100%** | **All** |

---

## Related Documentation

- [dependencies.yaml](../../yaml/dependencies.yaml) - Complete dependency specifications
- [lib-modules.yaml](../../yaml/lib-modules.yaml) - Module function documentation
- [Initialization Order](initialization-order.md) - Installation sequence
- [Runtime Call Chains](runtime-call-chains.md) - Function call graphs

---

**Created:** 2026-01-07
**Version:** v5.26
**Status:** ✅ CURRENT (44 modules analyzed)

---
name: Validate Deployment
description: Comprehensive deployment validation checklist - containers, ports, certificates, data flows
version: 1.0.0
tags: [testing, validation, deployment, vless]
dependencies: []
files:
  checklists: ./checklists/*.md
  shared: ../../_shared/*.json
---

# Validate Deployment v1.0

Полная валидация deployment после установки или upgrade.

## Когда использовать

- После fresh installation
- После major upgrade
- После infrastructure changes
- Periodic health checks

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/docker.yaml  # Expected container state
Read .claude/skills/_shared/container-names.json
Read .claude/skills/_shared/vless-constants.json
```

### Phase 2: Validate Containers (AUTO)

```bash
# Check all 6 containers running
Bash: docker ps --filter 'name=vless' --format 'table {{.Names}}\t{{.Status}}'

# Expected containers:
# vless_haproxy (healthy)
# vless_xray (healthy)
# vless_nginx_reverseproxy (healthy)
# vless_certbot_nginx (healthy or exited - on-demand)
# vless_fake_site (healthy)
# vless_mtproxy (healthy or not running - optional)
```

**Checklist:**
- [ ] HAProxy running and healthy
- [ ] Xray running and healthy
- [ ] Nginx reverse proxy healthy
- [ ] Fake site healthy
- [ ] No containers in restart loop

### Phase 3: Validate Port Bindings

```bash
Bash: sudo ss -tulnp | grep -E ':(443|1080|8118|8443|9000)'
```

**Checklist:**
- [ ] Port 443 bound (HAProxy HTTPS)
- [ ] Port 1080 bound (HAProxy SOCKS5)
- [ ] Port 8118 bound (HAProxy HTTP proxy)
- [ ] Port 9000 bound (HAProxy stats, localhost only)
- [ ] Port 8443 bound if MTProxy enabled

### Phase 4: Validate Certificates

```bash
DOMAIN="your-domain.com"
Bash: ls -lh /etc/letsencrypt/live/$DOMAIN/
Bash: openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -dates
```

**Checklist:**
- [ ] Certificate exists
- [ ] Not expired (notAfter > today + 30 days)
- [ ] combined.pem exists (for HAProxy)

### Phase 5: Validate Data Flows

**Test each flow:**

**VLESS Reality:**
```bash
# Requires VLESS client configured
# Manual: Connect with client, verify connection
```

**SOCKS5 over TLS:**
```bash
# Test SOCKS5 endpoint
curl --socks5 localhost:1080 --socks5-user username:password http://ifconfig.me
```

**HTTP Proxy over TLS:**
```bash
# Test HTTP proxy
curl --proxy https://username:password@localhost:8118 http://ifconfig.me
```

**Checklist:**
- [ ] VLESS Reality works (if client available)
- [ ] SOCKS5 accepts connections
- [ ] HTTP proxy accepts connections

### Phase 6: Validate Configurations

**Используй:** `@skill:validate-config`

Run full config validation.

### Phase 7: Generate Compliance Report

```markdown
## Deployment Validation Report

**Date:** {timestamp}
**Version:** {vless_version}

### Container Health: ✅ PASSED
- vless_haproxy: healthy
- vless_xray: healthy
- vless_nginx_reverseproxy: healthy
- vless_fake_site: healthy

### Port Bindings: ✅ PASSED
- 443: HAProxy (0.0.0.0)
- 1080: HAProxy (0.0.0.0)
- 8118: HAProxy (0.0.0.0)

### Certificates: ✅ PASSED
- Certificate valid until: {date}
- Days remaining: {count}

### Data Flows: ⚠️ PARTIAL
- VLESS Reality: Not tested (no client)
- SOCKS5: ✅ Works
- HTTP Proxy: ✅ Works

### Configuration: ✅ PASSED
- Xray config: Valid
- HAProxy config: Valid
- Nginx config: Valid

### Overall Status: ✅ DEPLOYMENT VALID

Deployment is production-ready.
```

## Safety Rules

```yaml
ALWAYS:
  - Check ALL containers
  - Validate ALL ports
  - Test connectivity where possible
  - Generate comprehensive report

NEVER:
  - Skip checks because "it looks fine"
  - Mark as valid with failing checks
```

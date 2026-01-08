---
name: Validate Config
description: Validate Xray, HAProxy, Nginx configurations before applying changes
version: 1.0.0
tags: [troubleshooting, validation, config, vless]
dependencies: []
files:
  shared: ../../_shared/*.json
---

# Validate Config v1.0

Автоматическая валидация конфигураций перед применением изменений.

## Когда использовать

- Перед рестартом контейнеров
- После редактирования config files
- Перед деплоем изменений
- Troubleshooting конфигурационных проблем

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/config.yaml  # Configuration relationships
Read .claude/skills/_shared/vless-constants.json  # Validation commands
```

### Phase 2: Run Validations (AUTO)

**1. Xray Config:**
```bash
# Validate xray_config.json syntax
Bash: xray test -c /opt/vless/config/xray_config.json

# Validate JSON syntax
Bash: jq empty /opt/vless/config/xray_config.json

# Check required fields
Bash: jq '.inbounds[] | select(.protocol=="vless") | .port' /opt/vless/config/xray_config.json
```

**Expected:** `Configuration OK`

**2. HAProxy Config:**
```bash
# Validate haproxy.cfg syntax
Bash: haproxy -c -f /opt/vless/config/haproxy.cfg

# Check ACL sections exist
Bash: grep -E 'frontend|backend|DYNAMIC_REVERSE_PROXY_ROUTES' /opt/vless/config/haproxy.cfg
```

**Expected:** `Configuration file is valid`

**3. Nginx Config:**
```bash
# Validate nginx config
Bash: docker exec vless_nginx_reverseproxy nginx -t

# Check rate limit zones
Bash: grep 'limit_req_zone' /opt/vless/config/reverse-proxy/http_context.conf
```

**Expected:** `syntax is ok` and `test is successful`

**4. JSON Files:**
```bash
# Validate users.json
Bash: jq empty /opt/vless/data/users.json

# Validate external_proxy.json (if exists)
Bash: jq empty /opt/vless/config/external_proxy.json 2>/dev/null || echo "Not configured"
```

### Phase 3: Report Results

**Format:**

```markdown
## Configuration Validation Report

**✅ PASSED:**
- Xray config: Valid (port 8443, 3 users)
- HAProxy config: Valid (frontends: 4, backends: 3)
- Nginx config: Valid (rate limit zones: 2)
- Users JSON: Valid (3 users)

**❌ FAILED:**
- {config_file}: {error_message}

**⚠️ WARNINGS:**
- {warning_message}

**Safe to restart:** {YES/NO}
```

## Safety Rules

```yaml
ALWAYS:
  - Run ALL validations
  - Report FAILED configs clearly
  - Suggest fixes for failed validations

NEVER:
  - НЕ restart containers if validation fails
  - НЕ пропускай JSON syntax check
```

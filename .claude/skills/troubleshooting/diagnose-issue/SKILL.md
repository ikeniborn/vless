---
name: Diagnose Issue
description: Систематическая диагностика проблем VLESS + Reality VPN с использованием playbooks
version: 1.0.0
tags: [troubleshooting, diagnostics, vless, docker, networking]
dependencies: []
files:
  playbooks: ./playbooks/*.md
  templates: ./templates/*.json
  shared: ../../_shared/*.json
---

# Diagnose Issue v1.0

Автоматическая диагностика проблем VLESS + Reality VPN server с использованием playbooks для типичных сценариев.

## Когда использовать

- Container показывает (unhealthy)
- Порт заблокирован или занят
- Certificate renewal failed
- Routing не работает (503 ошибки)
- Любая другая проблема с работой VPN

## Workflow

### Phase 1: Load Context & Identify Issue

**ОБЯЗАТЕЛЬНО:** Загрузи контекст перед диагностикой:

```bash
# Используй Read tool
Read docs/architecture/yaml/docker.yaml        # Контейнеры и порты
Read docs/architecture/yaml/data-flows.yaml    # Traffic flows
Read .claude/skills/_shared/common-issues.json # База знаний
Read .claude/skills/_shared/container-names.json  # Container registry
```

**Определи тип проблемы:**
1. Спроси пользователя: "Опишите проблему (симптомы, сообщения об ошибках)"
2. Категоризируй проблему:
   - **Container unhealthy** → playbook: container-unhealthy.md
   - **Port conflict** → playbook: port-conflict.md
   - **Certificate issues** → playbook: cert-renewal-failed.md
   - **Routing broken** → playbook: routing-broken.md
   - **Other** → general diagnostic workflow

### Phase 2: Run Diagnostics (AUTO)

**Для каждого типа проблемы запусти диагностические команды:**

#### Standard Diagnostic Commands (выполняются автоматически):

```bash
# 1. System Status
Bash: sudo vless status

# 2. Container Health
Bash: docker ps

# 3. Port Bindings
Bash: sudo ss -tulnp | grep -E ':(443|1080|8118|8443|9000)'

# 4. Container Logs (last 50 lines)
Bash: docker logs vless_xray --tail 50
Bash: docker logs vless_haproxy --tail 50
Bash: docker logs vless_nginx_reverseproxy --tail 50

# 5. Network Connectivity
Bash: docker network inspect vless_reality_net
```

**Собери результаты:**
- Запиши все output в structured format
- Определи какие команды failed/succeeded
- Сопоставь errors с common-issues.json

### Phase 3: Match Against Known Issues

**Используй common-issues.json:**

1. Read `.claude/skills/_shared/common-issues.json`
2. Для каждого issue в базе:
   - Сопоставь симптомы с тем что нашел
   - Если match >= 70%:
     - Загрузи соответствующий playbook
     - Запусти специфичные diagnostic commands из playbook
     - Определи common_cause

3. Если нет match:
   - Используй general diagnostic workflow
   - Создай новый issue report

### Phase 4: Generate Diagnostic Report

**Template:** `@template:diagnostic-report` → `./templates/diagnostic-report.json`

**Формат отчета:**

```markdown
# 🔍 DIAGNOSTIC REPORT

**Issue ID:** {issue_id или "unknown"}
**Category:** {category}
**Severity:** {severity}

## Symptoms Detected

- {symptom 1}
- {symptom 2}
...

## Diagnostic Results

### System Status
{vless status output}

### Container Health
{docker ps output - только vless_* контейнеры}

### Port Bindings
{ss -tulnp output - только VLESS ports}

### Log Analysis
**vless_xray:**
{последние errors из xray logs}

**vless_haproxy:**
{последние errors из haproxy logs}

## Identified Issue

**Most Likely Cause:** {cause from common-issues.json}

**Explanation:** {explanation}

## Recommended Fix

{commands from fix section}

**Validation:**
{validation steps}

## Prevention

{prevention steps from common-issues.json}
```

### Phase 5: Present Findings

**Output:** Diagnostic report в markdown

**Спроси пользователя:**
```
Диагностика завершена. Хотите:
1. Применить recommended fix автоматически?
2. Посмотреть detailed playbook?
3. Попробовать альтернативные решения?
```

## Playbooks

### container-unhealthy.md
**Triggers:** docker ps shows (unhealthy), health check failing

**Playbook:** `@playbook:container-unhealthy`

**Common Issues:**
- Xray wrong port (443 instead of 8443)
- Wrong fallback destination
- Missing health check endpoint

### port-conflict.md
**Triggers:** "port is already allocated", "address already in use"

**Playbook:** `@playbook:port-conflict`

**Common Issues:**
- Existing web server on 443
- Old VLESS containers not cleaned up
- UFW blocking Docker

### cert-renewal-failed.md
**Triggers:** Certbot cron job failing, expired certificate

**Playbook:** `@playbook:cert-renewal-failed`

**Common Issues:**
- Port 80 blocked
- DNS changed
- Certbot rate limit

### routing-broken.md
**Triggers:** 503 Service Unavailable, HAProxy backend down

**Playbook:** `@playbook:routing-broken`

**Common Issues:**
- HAProxy config not reloaded
- Nginx backend crash
- Missing dynamic ACL

## Safety Rules

```yaml
ALWAYS:
  - Запускай diagnostic commands через Bash tool (read-only)
  - Собирай ВСЕ outputs перед анализом
  - Сопоставляй с common-issues.json перед выводами
  - Предлагай validation steps для каждого fix

NEVER:
  - НЕ применяй fixes без подтверждения пользователя
  - НЕ выполняй деструктивные команды (rm, docker rm) без approval
  - НЕ пропускай Phase 1 (YAML context loading)
```

## Examples

### Example 1: Container Unhealthy

**User:** "vless_xray shows unhealthy in docker ps"

**Workflow:**
1. Load YAML context (docker.yaml, common-issues.json)
2. Run diagnostics:
   - `docker inspect vless_xray | jq '.[0].State.Health'`
   - `docker logs vless_xray --tail 50`
   - `jq '.inbounds[].port' /opt/vless/config/xray_config.json`
3. Match symptoms → issue: "container_unhealthy"
4. Load playbook: `container-unhealthy.md`
5. Identify cause: "Xray listening on port 443 instead of 8443"
6. Present fix:
   ```bash
   sudo sed -i 's/"port": 443,/"port": 8443,/' /opt/vless/config/xray_config.json
   docker restart vless_xray
   ```
7. Ask user: "Применить этот fix?"

### Example 2: Port Conflict

**User:** "Installation fails with 'port is already allocated'"

**Workflow:**
1. Load context
2. Run `sudo ss -tulnp | grep :443`
3. Identify: nginx running on port 443
4. Present fix:
   ```bash
   sudo systemctl stop nginx
   sudo systemctl disable nginx
   ```
5. Validate: `sudo ss -tulnp | grep :443` returns empty

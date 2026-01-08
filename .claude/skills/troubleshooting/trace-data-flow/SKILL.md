---
name: Trace Data Flow
description: Trace traffic path through VLESS system using data-flows.yaml
version: 1.0.0
tags: [troubleshooting, routing, dataflow, vless, visualization]
dependencies: []
files:
  shared: ../../_shared/*.json
---

# Trace Data Flow v1.0

Визуализация пути трафика через VLESS систему для debugging routing issues.

## Когда использовать

- Debug routing problems
- Understand traffic path
- Verify proxy chain
- Explain system architecture
- Troubleshoot connection issues

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/data-flows.yaml  # Traffic flows
Read docs/architecture/yaml/docker.yaml      # Container topology
Read .claude/skills/_shared/vless-constants.json  # Ports
```

### Phase 2: Identify Flow Type

**Спроси пользователя:** "Какой тип трафика трассировать?"

1. **VLESS Reality** - DPI-resistant VPN
2. **SOCKS5 over TLS** - SOCKS5 proxy
3. **HTTP Proxy over TLS** - HTTP CONNECT proxy
4. **Reverse Proxy** - Subdomain-based reverse proxy
5. **External Proxy** - Per-user upstream routing (v5.24+)
6. **MTProxy** - Telegram proxy

### Phase 3: Visualize Traffic Path

**Для каждого flow type - output диаграмму:**

**Example (VLESS Reality):**

```
Client
  ↓ [TLS 1.3 connection to port 443]
  ↓
HAProxy (vless_haproxy)
  ↓ [SNI passthrough - NO TLS termination]
  ↓ [Forward to backend based on SNI]
  ↓
Xray (vless_xray:8443)
  ↓ [VLESS protocol decryption]
  ↓ [Reality protocol validation]
  ↓ [Routing decision based on user/rules]
  ↓
  ├─→ [Direct] → Internet
  ├─→ [External Proxy] → Upstream SOCKS5 → Internet (if configured)
  └─→ [Fallback] → Fake Site (if invalid client)
```

**Example (SOCKS5 over TLS):**

```
Client
  ↓ [TLS connection to port 1080]
  ↓
HAProxy (vless_haproxy)
  ↓ [TLS termination - decrypt]
  ↓ [Forward plaintext to backend]
  ↓
Xray (vless_xray:10800)
  ↓ [SOCKS5 protocol handling]
  ↓ [Username/password validation]
  ↓ [Create connection to target]
  ↓
Internet
```

### Phase 4: Highlight Potential Issues

**Check каждый hop:**
- Is container healthy?
- Is port correct?
- Is routing rule configured?
- Are logs showing errors?

**Output:**

```markdown
## Traffic Flow Trace: {flow_type}

### Path Visualization
{ASCII diagram}

### Component Status
✅ HAProxy (vless_haproxy) - Healthy, listening on port 443
✅ Xray (vless_xray) - Healthy, listening on port 8443
⚠️ {component} - {issue}

### Routing Decision Points
1. HAProxy SNI routing: {routing_rule}
2. Xray inbound: {inbound_config}
3. Xray outbound: {outbound_config}

### Potential Bottlenecks
- {bottleneck_1}
- {bottleneck_2}
```

## Flow Templates

См. `docs/architecture/diagrams/data-flows/` для полных диаграмм.

## Safety Rules

```yaml
ALWAYS:
  - Загружай data-flows.yaml перед трассировкой
  - Показывай ПОЛНЫЙ path от client до Internet
  - Проверяй health каждого компонента

NEVER:
  - НЕ guess routing - используй actual config
  - НЕ пропускай промежуточные hops
```

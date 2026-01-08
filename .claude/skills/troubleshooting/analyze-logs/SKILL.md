---
name: Analyze Logs
description: Parse and analyze container logs with pattern matching for known errors
version: 1.0.0
tags: [troubleshooting, logs, vless, xray, haproxy, analysis]
dependencies: []
files:
  patterns: ./patterns/*.json
  shared: ../../_shared/*.json
---

# Analyze Logs v1.0

Автоматический анализ логов контейнеров VLESS с pattern matching для известных ошибок.

## Когда использовать

- Нужно быстро найти ошибки в логах
- Подозрение на проблему но неясно где искать
- После изменения конфигурации (проверка ошибок)
- Периодический мониторинг здоровья системы

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/docker.yaml  # Container names and logs paths
Read .claude/skills/troubleshooting/analyze-logs/patterns/xray-errors.json
Read .claude/skills/troubleshooting/analyze-logs/patterns/haproxy-errors.json
```

### Phase 2: Collect Logs (AUTO)

```bash
# Xray logs
Bash: docker logs vless_xray --tail 100

# HAProxy logs
Bash: docker logs vless_haproxy --tail 100

# Nginx reverse proxy logs
Bash: docker logs vless_nginx_reverseproxy --tail 100

# MTProxy logs (if enabled)
Bash: docker logs vless_mtproxy --tail 100 2>/dev/null || echo "MTProxy not running"
```

### Phase 3: Pattern Matching (AUTO)

**Для каждого лога:**
1. Сопоставь с patterns из xray-errors.json / haproxy-errors.json
2. Определи severity (CRITICAL / HIGH / MEDIUM / LOW)
3. Группируй по error types

**Output format:**

```markdown
## Log Analysis Report

### vless_xray
- **CRITICAL**: {count} errors
  - {error_pattern_1}: {count} occurrences
- **HIGH**: {count} errors
- **MEDIUM**: {count} errors

### vless_haproxy
- **CRITICAL**: {count} errors
- **HIGH**: {count} errors

### Summary
Total errors: {count}
Critical issues requiring immediate attention: {count}
```

### Phase 4: Present Findings

**Output:**
- Aggregated error report
- Top 5 most frequent errors
- Recommended actions for each error type

**Спроси:** "Show detailed log excerpts for specific error?"

## Error Patterns

См. patterns/xray-errors.json и patterns/haproxy-errors.json для полного списка.

## Safety Rules

```yaml
ALWAYS:
  - Read-only операции (никогда не изменяй логи)
  - Группируй errors по severity
  - Предлагай actionable recommendations

NEVER:
  - НЕ удаляй логи
  - НЕ модифицируй log files
```

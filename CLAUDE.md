# CLAUDE.md - Project Memory

**Project:** familyTraffic VPN Server
**Version:** 5.24 (Per-User External Proxy Support)
**Last Updated:** 2025-10-26
**Purpose:** Unified project memory combining workflow execution rules and project-specific quick reference

---

## TABLE OF CONTENTS

### UNIVERSAL WORKFLOW EXECUTION RULES
1. [Critical Principles (P1-P5)](#part-i-universal-workflow-execution-rules)
2. [High Priority Rules (P6-P10)](#2-high-priority-rules-p6-p10)
3. [Medium Priority Rules (P11-P13)](#3-medium-priority-rules-p11-p13)
4. [Prohibited & Mandatory Actions](#4-prohibited--mandatory-actions)
5. [Standard Formats](#5-standard-formats)

### PROJECT-SPECIFIC QUICK REFERENCE
6. [Project Overview](#6-project-overview)
7. [Quick Reference](#7-quick-reference)
8. [Documentation Navigation](#8-documentation-navigation)

---

# PART I: UNIVERSAL WORKFLOW EXECUTION RULES

## 1. CRITICAL PRINCIPLES (P1-P5)

### P1: Sequential Execution (CRITICAL)
**Правило:** Выполняйте фазы и actions СТРОГО последовательно.

**Обязательно:**
- ✓ Выполняйте фазы в указанном порядке
- ✓ Выполняйте все actions внутри фазы по порядку
- ✓ НЕ пропускайте фазы
- ✓ НЕ пропускайте actions
- ✓ НЕ меняйте порядок выполнения

**Нарушение:** FATAL - немедленная остановка

---

### P2: Thinking Requirement (CRITICAL)
**Правило:** ОБЯЗАТЕЛЬНО используйте `<thinking>` перед критическими решениями.

**Когда обязателен thinking:**
- Перед началом каждой фазы
- Перед actions помеченными `requires_thinking="true"`
- Перед actions с `validation="critical"`
- Перед принятием важных технических решений
- При выборе между альтернативными подходами

**Что должен содержать thinking:**
- Анализ текущей ситуации
- Оценка рисков
- Обоснование выбранного решения
- Рассмотрение альтернатив
- План проверки результата

**Формат thinking:**
```xml
<thinking>
1. АНАЛИЗ: [что имеем]
2. ОПЦИИ: [какие варианты]
3. ВЫБОР: [что выбираем и почему]
4. РИСКИ: [что может пойти не так]
5. ВАЛИДАЦИЯ: [как проверим]
</thinking>
```

**Нарушение:** FATAL - действие НЕ ВЫПОЛНЯЕТСЯ без thinking

---

### P3: Mandatory Output Enforcement (CRITICAL)
**Правило:** Выводите ВСЕ обязательные outputs в указанных форматах.

**Когда output обязателен:**
- Action помечен `output="required"`
- Action имеет `mandatory_output` секцию
- Action имеет `mandatory_format` секцию
- Checkpoint требует verification_instruction

**Обязательно:**
- ✓ Используйте ТОЧНО указанный формат
- ✓ Заполните ВСЕ секции mandatory_format
- ✓ НЕ сокращайте форматы
- ✓ НЕ пропускайте секции
- ✓ НЕ заменяйте формат на "свой"

**Нарушение:** BLOCKING - нельзя продолжить без output

---

### P4: Exit Conditions Verification (CRITICAL)
**Правило:** Проверяйте exit_conditions перед продолжением.

**Обязательно:**
- ✓ Проверьте ВСЕ conditions в exit_conditions
- ✓ НЕ продолжайте если хотя бы одно condition не выполнено
- ✓ Выведите статус каждого condition явно
- ✓ При невыполнении - выполните violation_action

**Типичные exit_conditions:**
- Все обязательные actions выполнены
- Все mandatory_outputs выведены
- Validation passed
- Checkpoint пройден

**Нарушение:** FATAL - блокировка перехода к следующему шагу

---

### P5: Checkpoint Verification (HIGH)
**Правило:** Проходите checkpoints с явной верификацией перед переходом между фазами.

**Обязательно:**
- ✓ Проверьте ВСЕ checks в checkpoint
- ✓ Выведите verification_instruction если указана
- ✓ НЕ переходите к следующей фазе пока ВСЕ checks != ✓
- ✓ Выводите статус checkpoint явно

**Формат checkpoint verification:**
```
PHASE N CHECKPOINT:
[✓/✗] Check 1: [статус и детали]
[✓/✗] Check 2: [статус и детали]
[✓/✗] Check N: [статус и детали]

РЕЗУЛЬТАТ: ✓ PASSED / ✗ FAILED
Переход к Phase N+1: [ALLOWED/BLOCKED]
```

**Нарушение:** BLOCKING - нельзя перейти к следующей фазе

---

## 2. HIGH-PRIORITY RULES (P6-P10)

### P6: Entry Conditions Check (HIGH)
**Правило:** Проверяйте entry_conditions перед входом в фазу.

**Обязательно:**
- ✓ Проверьте все entry conditions
- ✓ При невыполнении - выполните violation_action
- ✓ НЕ начинайте фазу без выполнения conditions

---

### P7: Blocking Actions Enforcement (HIGH)
**Правило:** Для actions с `blocking="true"` - строго следуйте ограничениям.

**Обязательно:**
- ✓ Завершите action полностью
- ✓ Выведите mandatory_output
- ✓ Проверьте exit_condition
- ✓ НЕ продолжайте до выполнения всех требований

---

### P8: Validation Level Respect (HIGH)
**Правило:** Выполняйте validation в соответствии с уровнем.

**Уровни validation:**
- `critical`: ОБЯЗАТЕЛЬНАЯ проверка, STOP при failure
- `standard`: Обычная проверка, retry при failure
- `micro`: Быстрая проверка, log при failure

**Для validation="critical":**
- ОБЯЗАТЕЛЬНО thinking перед action
- ОБЯЗАТЕЛЬНО вывод результата проверки
- STOP немедленно при failure
- НЕ продолжать до исправления

---

### P9: Error Handling Compliance (HIGH)
**Правило:** Следуйте error_handling правилам при ошибках.

**Обязательно:**
- ✓ Определите тип ошибки
- ✓ Выполните указанный action (STOP/RETRY/ASK)
- ✓ Выведите указанное error message
- ✓ НЕ игнорируйте ошибки
- ✓ НЕ продолжайте при STOP errors

---

### P10: Approval Gates Respect (HIGH)
**Правило:** Для approval_gate с `required="true"` - ждите подтверждения.

**Обязательно:**
- ✓ Выведите approval gate message
- ✓ ЖДИТЕ подтверждения пользователя
- ✓ НЕ продолжайте автоматически
- ✓ Предложите опции (yes/no/review)

---

## 3. MEDIUM-PRIORITY RULES (P11-P13)

### P11: Ask When Unclear (MEDIUM)
**Правило:** При неясности - ОСТАНОВИТЕСЬ и спросите.

**Когда спрашивать:**
- Требования неоднозначны
- Несколько возможных интерпретаций
- Отсутствует критичная информация
- Неясен ожидаемый результат

**Формат вопроса:**
```
❓ ТРЕБУЕТСЯ УТОЧНЕНИЕ
Неясно: [что конкретно]
Варианты: [опции]
Вопрос: [конкретный вопрос]
```

---

### P12: Decision Documentation (MEDIUM)
**Правило:** Документируйте важные технические решения.

**Что документировать:**
- Выбор между альтернативными подходами
- Отклонение очевидных вариантов
- Trade-offs и компромиссы

---

### P13: Conditional Execution (MEDIUM)
**Правило:** Выполняйте conditional actions только при выполнении condition.

---

## 4. PROHIBITED & MANDATORY ACTIONS

### НИКОГДА НЕ ДЕЛАЙТЕ:
❌ НЕ пропускайте фазы / actions / thinking / mandatory_output
❌ НЕ сокращайте форматы
❌ НЕ продолжайте при critical failures
❌ НЕ игнорируйте blocking conditions / exit_conditions / checkpoints
❌ НЕ делайте assumptions - ASK при неясности

### ВСЕГДА ДЕЛАЙТЕ:
✓ ВСЕГДА используйте thinking для requires_thinking="true"
✓ ВСЕГДА выводите mandatory_output для output="required"
✓ ВСЕГДА проверяйте exit_conditions / checkpoints / conditions
✓ ВСЕГДА останавливайтесь при critical failures
✓ ВСЕГДА спрашивайте при неясности
✓ ВСЕГДА выполняйте последовательно
✓ ВСЕГДА обрабатывайте ошибки

---

## 5. STANDARD FORMATS

### Формат Thinking:
```xml
<thinking>
КОНТЕКСТ: [текущая ситуация]
ЗАДАЧА: [что нужно сделать]
ОПЦИИ: [варианты с плюсами/минусами]
ВЫБОР: [вариант N] потому что [обоснование]
РИСКИ: [что может пойти не так]
ПРОВЕРКА: [как валидируем результат]
</thinking>
```

### Формат Error Message:
```
[ICON] ОШИБКА: [Тип]
Проблема: [описание]
Контекст: [где произошло]
Действие: [STOP/RETRY/ASK]
```

### Формат Checkpoint:
```
PHASE N CHECKPOINT:
[✓/✗] Check 1: [детали]
РЕЗУЛЬТАТ: ✓ PASSED / ✗ FAILED
Переход: [ALLOWED/BLOCKED]
```

---

# PART II: PROJECT-SPECIFIC QUICK REFERENCE

## 6. PROJECT OVERVIEW

**Project Name:** familyTraffic VPN Server
**Version:** 5.33
**Target Scale:** 10-50 concurrent users
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, SOCKS5, HTTP, Nginx, supervisord

**Core Features:**
- Deploy production-ready VPN in < 5 minutes
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- Dual proxy support (SOCKS5 + HTTP) with TLS termination via Nginx
- Single Docker container: nginx + xray + certbot + supervisord
- Per-user external proxy support (route specific users through upstream proxies)
- Tier 2 transports: WebSocket / XHTTP / gRPC via CDN

**Architecture v5.33:**
```
Client
  ├─ TCP:443 ──► familytraffic (ssl_preread SNI) ──► 127.0.0.1:8443 (VLESS Reality)
  │                                               └─► port 8448 → Tier 2 (WS/XHTTP/gRPC)
  ├─ TCP:1080 ─► familytraffic (TLS termination) ──► 127.0.0.1:10800 (SOCKS5)
  └─ TCP:8118 ─► familytraffic (TLS termination) ──► 127.0.0.1:18118 (HTTP proxy)
```

**Key Paths:**
- Installation: `/opt/familytraffic/` (HARDCODED, cannot be changed)
- Config: `/opt/familytraffic/config/`
- Data: `/opt/familytraffic/data/`
- Users DB: `/opt/familytraffic/data/users.json` (v5.24: includes `external_proxy_id` field)

**CLI Commands (v5.33):**
```bash
# User Management
sudo familytraffic add-user <username>
sudo familytraffic remove-user <username>
sudo familytraffic list-users

# Per-User External Proxy
sudo familytraffic set-proxy <username> <proxy-id|none>
sudo familytraffic show-proxy <username>
sudo familytraffic list-proxy-assignments

# External Proxy Management
sudo familytraffic-external-proxy add
sudo familytraffic-external-proxy list
sudo familytraffic-external-proxy status

# Tier 2 Transports
sudo familytraffic add-transport <ws|xhttp|grpc> <subdomain>
sudo familytraffic list-transports
sudo familytraffic remove-transport <type>

# Status & Logs
sudo familytraffic status
sudo familytraffic logs xray
sudo familytraffic logs nginx
```

🔗 **Полная документация:** `docs/prd/` (7 модулей, 171 KB)

---

## 7. QUICK REFERENCE

### Top-5 NFR (Non-Functional Requirements)

| ID | Название | Target | Acceptance |
|----|----------|--------|------------|
| **NFR-SEC-001** | Mandatory TLS Policy | TLS 1.3 only | Nginx TLS termination for ports 1080/8118 |
| **NFR-OPS-001** | Zero Manual Intervention | 100% automated | Let's Encrypt auto-renewal via certbot |
| **NFR-PERF-001** | TLS Performance Overhead | < 10% latency | Nginx graceful reload < 1 second |
| **NFR-USABILITY-001** | Installation Simplicity | < 5 minutes | Interactive installer with validation |
| **NFR-RELIABILITY-001** | Cert Renewal Reliability | 99.9% success | Certbot renewal + Nginx reload cron job |

🔗 **Полный список:** docs/prd/03_nfr.md

---

### Top-5 Common Issues

#### Issue 1: UFW Blocks Docker Traffic
**Symptoms:** Containers run, but no Internet access inside

**Detection:**
```bash
docker exec familytraffic ping -c 1 8.8.8.8  # Fails
grep "DOCKER-USER" /etc/ufw/after.rules  # Check chains
```

**Solution:** Add Docker chains to /etc/ufw/after.rules, then `sudo ufw reload`

---

#### Issue 2: Port 443 Already Occupied
**Symptoms:** Installation fails, "port is already allocated"

**Detection:**
```bash
sudo ss -tulnp | grep :443
```

**Solution:** Offer alternative ports (8443, 2053) or ask user to resolve

---

#### Issue 3: Nginx Not Routing Reverse Proxy
**Symptoms:** 503 Service Unavailable for subdomain

**Detection:**
```bash
docker exec familytraffic-nginx nginx -t      # Check nginx config
docker logs familytraffic-nginx --tail 50
```

**Solution:**
```bash
# Verify SNI map includes the subdomain
grep "your.subdomain.com" /opt/familytraffic/config/nginx/nginx.conf

# Manual Nginx reload (zero-downtime)
docker exec familytraffic-nginx nginx -s reload
```

---

#### Issue 4: Xray Container Unhealthy - Wrong Port Configuration
**Symptoms:** familytraffic shows (unhealthy), familytraffic-nginx logs "Connection refused"

**Root Cause:** Xray configured to listen on port 443 instead of 8443 (requires Xray on internal port 8443)

**Solution:**
```bash
# Fix Xray port configuration
sudo sed -i 's/"port": 443,/"port": 8443,/' /opt/familytraffic/config/xray_config.json

# Fix fallback container name
sudo sed -i 's/"dest": "familytraffic-nginx:80"/"dest": "familytraffic-fake-site:80"/' /opt/familytraffic/config/xray_config.json

# Restart Xray container
docker restart familytraffic
```

---

#### Issue 5: Nginx Reverse Proxy Container Crash Loop
**Symptoms:** familytraffic-nginx shows "Restarting"

**Root Cause:** Missing `limit_req_zone` directive in `/opt/familytraffic/config/reverse-proxy/http_context.conf`

**Solution:**
```bash
DOMAIN="your-domain.com"
ZONE_NAME="reverseproxy_${DOMAIN//[.-]/_}"

# Add to http_context.conf
sudo bash -c "cat >> /opt/familytraffic/config/reverse-proxy/http_context.conf << EOF

# Rate limit zone for: ${DOMAIN}
limit_req_zone \\\$binary_remote_addr zone=${ZONE_NAME}:10m rate=100r/s;
EOF"

# Restart nginx container
docker restart familytraffic-nginx
```

🔗 **Полный список:** docs/prd/06_appendix.md (Common Failure Points)

---

### Quick Debug Commands

**System Status:**
```bash
sudo familytraffic status
docker ps
sudo ss -tulnp | grep -E '443|1080|8118'
```

**Logs:**
```bash
sudo familytraffic logs xray
docker logs familytraffic --tail 50
docker exec familytraffic supervisorctl status
```

**Config Validation:**
```bash
jq . /opt/familytraffic/config/xray_config.json
docker exec familytraffic nginx -t
```

**Per-User Proxy Debug (v5.24):**
```bash
# Show per-user assignments
sudo familytraffic list-proxy-assignments

# Check specific user
sudo familytraffic show-proxy alice

# Verify routing rules in Xray config
jq '.routing.rules' /opt/familytraffic/config/xray_config.json
```

**Security Testing:**
```bash
# Run comprehensive security test suite
sudo familytraffic test-security

# Quick mode (skip long-running tests)
sudo familytraffic test-security --quick
```

🔗 **Полный список:** docs/prd/06_appendix.md (Debug & Troubleshooting)

---

### Skills System Overview

**Location:** `.claude/skills/`
**Purpose:** Автоматизация development, troubleshooting, documentation, и testing workflows

#### Available Skills (12 total)

**Troubleshooting (4 skills):**
- **diagnose-issue** - Систематическая диагностика с playbooks (container unhealthy, port conflict, cert renewal, routing)
- **analyze-logs** - Pattern matching в логах (Xray, Nginx errors)
- **validate-config** - Валидация конфигураций перед применением
- **trace-data-flow** - Визуализация traffic path через систему

**Development (4 skills):**
- **add-feature** - Полный lifecycle добавления функции (planning → code → test → docs → git)
- **refactor-module** - Безопасный рефакторинг с проверкой call chains
- **add-cli-command** - Добавление новой CLI команды
- **update-architecture-docs** - Синхронизация YAML документации с кодом

**Documentation (2 skills):**
- **sync-yaml-with-code** - Автоматический sync YAML с code changes
- **generate-mermaid-diagram** - Генерация Mermaid диаграмм из YAML

**Testing (2 skills):**
- **run-test-suite** - Запуск unit/integration/security/performance tests
- **validate-deployment** - Comprehensive deployment validation checklist

#### How to Use Skills

**Natural language invocation:**
```
"Diagnose why familytraffic container is unhealthy"
→ Uses diagnose-issue skill with container-unhealthy playbook

"Add user quota feature to user management"
→ Uses add-feature skill with full lifecycle

"Sync YAML documentation with recent code changes"
→ Uses sync-yaml-with-code skill
```

**Key Features:**
- ✅ **YAML-aware:** Skills auto-load `docs/architecture/yaml/` для контекста
- ✅ **Hybrid automation:** Read-only операции автоматически, write operations с approval gates
- ✅ **Safety enforced:** Обязательное логирование, YAML updates, validation перед changes
- ✅ **Integrated:** Используют существующие CLI tools (`familytraffic`, `familytraffic-mtproxy`, etc.)

#### Skill Structure

Each skill includes:
- **SKILL.md** - Workflow definition с phases и approval gates
- **Templates** - JSON/markdown шаблоны для structured output
- **Playbooks** - Step-by-step руководства для типичных сценариев (troubleshooting)
- **Patterns** - Error patterns для автоматического matching (log analysis)

**Shared resources:**
- `_shared/vless-constants.json` - System constants (paths, ports, containers)
- `_shared/container-names.json` - Container registry с health check URLs
- `_shared/common-issues.json` - База знаний (6 issues с fixes)

🔗 **Подробности:** `.claude/skills/README.md` (если создан)

---

## 8. DOCUMENTATION NAVIGATION

### Navigation Map by Use Case

**Для быстрого ознакомления:**
- **docs/prd/00_summary.md** - Executive summary, quick start guide (читать ПЕРВЫМ)

**Для разработки новых features:**
- **docs/prd/02_functional_requirements.md** - All FR-* requirements (14 requirements, включая v5.24 per-user proxy)
- **docs/prd/04_architecture.md** - Nginx stream+http architecture, network diagrams, routing logic
- **docs/prd/03_nfr.md** - Non-functional requirements (Security, Performance, Reliability)

**Для тестирования:**
- **docs/prd/05_testing.md** - v4.3+ automated test suite (3 test cases, DEV_MODE support)
- **docs/prd/03_nfr.md** - Performance targets и acceptance criteria

**Для troubleshooting ошибок:**
- **docs/prd/06_appendix.md** - Implementation details, rollback procedures, security risk matrix, common failures

**Для миграции между версиями:**
- **CHANGELOG.md** - Version history v3.0-v5.24, migration guides, breaking changes

### Version History (Recent)

| Версия | Дата | Ключевые изменения |
|--------|------|--------------------|
| **v5.24** | 2025-10-26 | **Per-User External Proxy Support** - route specific users through upstream proxies (13 new functions, 3 CLI commands) |
| **v5.23** | 2025-10-25 | External Proxy Support (server-level) - upstream proxy chaining for all users |
| **v5.22** | 2025-10-21 | Robust Container Management & Validation System (auto-recovery, health checks) |
| **v5.21** | 2025-10-21 | Port Cleanup & HAProxy UX (CRITICAL BUGFIX + silent mode) |
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture - subdomain-based reverse proxy (NO port!) |

🔗 **Полная история:** CHANGELOG.md

### Key Files Reference

| Файл | Назначение | Размер | Аудитория |
|------|-----------|--------|-----------|
| **README.md** | User guide, installation instructions | ~15 KB | End users, administrators |
| **CHANGELOG.md** | Version history v3.0-v5.24, migration guides | ~30 KB | Developers, administrators |
| **CLAUDE.md** | Project memory (this file) | ~25 KB | Developers, AI assistant |
| **CLAUDE_FULL.md** | Full project memory backup (before optimization) | ~35 KB | Reference only |
| **docs/prd/** | Product Requirements Document (7 modules) | ~171 KB | Product managers, developers |

---



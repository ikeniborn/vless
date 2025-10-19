# CLAUDE.md - Project Memory

**Project:** VLESS + Reality VPN Server
**Version:** 5.1 (HAProxy Port Fix)
**Last Updated:** 2025-10-20
**Purpose:** Unified project memory combining workflow execution rules and project-specific technical documentation

**Рекомендации по использованию:**
- Для быстрого ознакомления: docs/prd/00_summary.md
- Для разработки: docs/prd/02_functional_requirements.md + docs/prd/04_architecture.md
- Для тестирования: docs/prd/05_testing.md + docs/prd/03_nfr.md
- Для troubleshooting: docs/prd/06_appendix.md

---

## TABLE OF CONTENTS

### UNIVERSAL WORKFLOW EXECUTION RULES
1. [Critical Principles (P1-P5)](#part-i-universal-workflow-execution-rules)
2. [High Priority Rules (P6-P10)](#2-high-priority-rules-p6-p10)
3. [Medium Priority Rules (P11-P13)](#3-medium-priority-rules-p11-p13)
4. [Prohibited & Mandatory Actions](#4-prohibited--mandatory-actions)
5. [Standard Formats](#5-standard-formats)

### PROJECT-SPECIFIC DOCUMENTATION
6. [Project Overview](#6-project-overview)
7. [Critical Parameters](#7-critical-parameters)
8. [Project Structure](#8-project-structure)
9. [Critical Requirements](#9-critical-requirements-top-5)
10. [Quick Reference](#10-quick-reference)
11. [Documentation Map](#11-documentation-map)

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

# PART II: PROJECT-SPECIFIC DOCUMENTATION

## 6. PROJECT OVERVIEW

**Project Name:** VLESS + Reality VPN Server
**Version:** 4.3 (HAProxy Unified Architecture)
**Target Scale:** 10-50 concurrent users
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, SOCKS5, HTTP, HAProxy, Nginx

**Core Value Proposition:**
- Deploy production-ready VPN in < 5 minutes
- Zero manual configuration through intelligent automation
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- Dual proxy support (SOCKS5 + HTTP) with unified credentials
- Multi-format config export (5 formats: SOCKS5, HTTP, VSCode, Docker, Bash)
- **Unified TLS and routing via HAProxy (v4.3)** - single container architecture
- **Subdomain-based reverse proxy (https://domain, NO port!)**
- Coexists with Outline, Wireguard, other VPN services

**Key Innovation:**
Reality protocol "steals" TLS handshake from legitimate websites (google.com, microsoft.com), making VPN traffic mathematically indistinguishable from normal HTTPS. Deep Packet Inspection systems cannot detect the VPN.

**HAProxy Architecture (v4.3 - Current):**
HAProxy handles ALL TLS termination and routing in single container. **stunnel removed completely**. Port 443 (external): SNI routing to Xray:8443 (internal) for VLESS Reality + Reverse Proxy subdomain routing. Ports 1080/8118: TLS termination for proxies → Xray:10800/18118 plaintext. Nginx reverse proxy backends on localhost:9443-9452 (NOT exposed). Subdomain-based reverse proxy access (https://domain, NO port!). Graceful reload for zero-downtime updates.

🔗 **Детали:** docs/prd/00_summary.md, docs/prd/04_architecture.md

---

## 7. CRITICAL PARAMETERS

### Technology Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **Docker Engine** | 20.10+ | Minimum version |
| **Docker Compose** | v2.0+ | v2 syntax required, use `docker compose` NOT `docker-compose` |
| **Xray** | teddysun/xray:24.11.30 | DO NOT change without testing |
| **HAProxy** | haproxy:latest | NEW v4.3: Unified TLS & routing (REPLACES stunnel) |
| **Nginx** | nginx:alpine | Latest alpine |
| **OS** | Ubuntu 20.04+, 22.04, 24.04, Debian 10+ | CentOS/RHEL/Fedora NOT supported (firewalld vs UFW) |
| **Bash** | 4.0+ | Required |
| **jq** | 1.5+ | JSON processing |
| **openssl** | system default | Key generation, SNI |

### Key Ports

| Port | Service | Protocol | Notes |
|------|---------|----------|-------|
| 443 | HAProxy SNI Routing | TCP | VLESS Reality + Reverse Proxy subdomains (v4.3) |
| 8443 | Xray VLESS Internal | TCP | Backend for HAProxy, NOT publicly exposed |
| 1080 | HAProxy SOCKS5 TLS | TCP | TLS termination → Xray:10800 plaintext |
| 8118 | HAProxy HTTP TLS | TCP | TLS termination → Xray:18118 plaintext |
| 10800 | Xray SOCKS5 Internal | TCP | Localhost-only, plaintext |
| 18118 | Xray HTTP Internal | TCP | Localhost-only, plaintext |
| 9443-9452 | Nginx Reverse Proxy | TCP | Localhost-only backends (v4.3) |
| 9000 | HAProxy Stats | HTTP | Localhost-only (http://127.0.0.1:9000/stats) |

### Installation Paths (HARDCODED)

| Path | Permission | Purpose |
|------|-----------|---------|
| /opt/vless/ | 755 | Base directory (CANNOT be changed) |
| /opt/vless/config/ | 700 | Sensitive configs |
| /opt/vless/data/ | 700 | User data, backups |
| /opt/vless/logs/ | 755 | Access/error logs |
| /opt/vless/certs/ | 700 | HAProxy certificates (v4.3) |
| /usr/local/bin/vless-* | 755 | CLI symlinks (sudo-accessible) |

🔗 **Полные детали:** docs/prd/04_architecture.md

---

## 8. PROJECT STRUCTURE

### Development Structure
```
/home/ikeniborn/Documents/Project/vless/
├── install.sh                  # Main installer
├── CLAUDE.md                   # This file - project memory
├── README.md                   # User guide
├── CHANGELOG.md                # Version history v3.0-v4.3
├── lib/                        # Installation modules
│   ├── haproxy_config_manager.sh   # v4.3: HAProxy config generation
│   └── certificate_manager.sh      # v4.3: combined.pem management
├── docs/prd/                   # PRD modular structure (7 modules, 171 KB)
└── tests/                      # Test suite
```

### Production Structure
```
/opt/vless/
├── config/
│   ├── config.json             # 600 - Xray config (3 inbounds)
│   ├── haproxy.cfg             # 600 - HAProxy unified config (v4.3)
│   ├── users.json              # 600 - User database (v1.1)
│   ├── reality_keys.json       # 600 - X25519 key pair
│   ├── reverse_proxies.json    # 600 - Reverse proxy database (v4.3)
│   └── nginx/                  # Nginx configs
├── certs/
│   └── combined.pem            # 600 - fullchain + privkey (v4.3)
├── data/clients/<username>/    # 8 files per user:
│   ├── vless_config.json       # VLESS client config
│   ├── vless_uri.txt           # VLESS connection string
│   ├── qrcode.png              # QR code
│   ├── socks5_config.txt       # socks5s:// URI (TLS via HAProxy)
│   ├── http_config.txt         # https:// URI (TLS via HAProxy)
│   ├── vscode_settings.json    # VSCode proxy settings
│   ├── docker_daemon.json      # Docker daemon config
│   └── bash_exports.sh         # Bash environment variables
└── logs/
    ├── haproxy/haproxy.log     # v4.3: Unified log stream
    ├── xray/error.log
    └── nginx/
```

🔗 **Полные детали:** docs/prd/04_architecture.md (Section 4.7)

---

## 9. CRITICAL REQUIREMENTS (TOP-5)

### FR-001: Interactive Installation
**Target:** < 5 minutes на чистой Ubuntu 22.04

**Validation:**
- Все параметры validated before use
- Clear error messages with fix suggestions
- Progress indicators for long operations

**Acceptance Criteria:**
- ✓ All parameters prompted with intelligent defaults
- ✓ Each parameter validated immediately after input
- ✓ Total time < 5 minutes on clean Ubuntu 22.04 (10 Mbps)

---

### FR-004: Dest Site Validation
**Requirement:** Validate destination site for Reality masquerading

**Default Options:** google.com:443, microsoft.com:443, apple.com:443, cloudflare.com:443

**Validation Steps:**
1. TLS 1.3 Support (REQUIRED)
2. SNI Extraction (REQUIRED)
3. Reachability (REQUIRED, < 10 seconds)

**Acceptance Criteria:**
- ✓ All validation steps execute in < 10 seconds
- ✓ Clear feedback on failures with alternatives
- ✓ Cannot proceed with invalid dest

---

### FR-011: UFW Integration
**Requirement:** Configure UFW firewall with Docker forwarding support

**Critical Files:**
- /etc/ufw/ufw.conf
- /etc/ufw/after.rules (Docker chains added here)

**Acceptance Criteria:**
- ✓ UFW detected (install if missing)
- ✓ Port rule added without duplication
- ✓ Docker chains added to after.rules
- ✓ Containers can access Internet

---

### FR-012: Proxy Server Integration (v4.3)
**Requirement:** Dual proxy support (SOCKS5 + HTTP) with TLS termination via HAProxy

**Implementation:**
- SOCKS5: HAProxy port 1080 (TLS) → Xray port 10800 (plaintext, localhost)
- HTTP: HAProxy port 8118 (TLS) → Xray port 18118 (plaintext, localhost)
- Single password for both proxies
- 5 config file formats per user

**Acceptance Criteria:**
- ✓ Proxies bind to 127.0.0.1 ONLY (not 0.0.0.0)
- ✓ HAProxy handles TLS termination (ports 1080/8118)
- ✓ 5 config formats generated per user
- ✓ Auto-generation on user creation
- ✓ Service status shows proxy info

---

### FR-014: Subdomain-Based Reverse Proxy (v4.3)
**Requirement:** Support up to 10 reverse proxies with subdomain-based access (NO port!)

**Access Format:** `https://domain` (NO port number!)

**Architecture:**
```
Client → HAProxy Frontend 443 (SNI routing, NO TLS decryption)
       → Nginx Backend:9443-9452 (localhost)
       → Xray Outbound → Target Site
```

**CLI Commands:**
- `sudo vless-proxy add` - Add reverse proxy (interactive, subdomain-based)
- `sudo vless-proxy list` - List all reverse proxies
- `sudo vless-proxy show <domain>` - Show details
- `sudo vless-proxy remove <domain>` - Remove

**Acceptance Criteria:**
- ✓ Subdomain-based access (NO port!)
- ✓ SNI routing without TLS decryption (HAProxy passthrough)
- ✓ Graceful HAProxy reload (0 downtime)
- ✓ Max 10 domains per server

🔗 **Полный список:** docs/prd/02_functional_requirements.md (FR-001 through FR-014)

---

## 10. QUICK REFERENCE

### Top-5 NFR (Non-Functional Requirements)

| ID | Название | Target | Acceptance |
|----|----------|--------|------------|
| **NFR-SEC-001** | Mandatory TLS Policy | TLS 1.3 only | HAProxy TLS termination for ports 1080/8118 |
| **NFR-OPS-001** | Zero Manual Intervention | 100% automated | Let's Encrypt auto-renewal via certbot |
| **NFR-PERF-001** | TLS Performance Overhead | < 10% latency | HAProxy graceful reload < 1 second |
| **NFR-USABILITY-001** | Installation Simplicity | < 5 minutes | Interactive installer with validation |
| **NFR-RELIABILITY-001** | Cert Renewal Reliability | 99.9% success | Certbot renewal + HAProxy reload cron job |

🔗 **Полный список:** docs/prd/03_nfr.md

---

### Top-4 Common Issues

#### Issue 1: UFW Blocks Docker Traffic
**Symptoms:** Containers run, but no Internet access inside

**Detection:**
```bash
docker exec vless_xray ping -c 1 8.8.8.8  # Fails
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

#### Issue 3: HAProxy Not Routing Reverse Proxy (v4.3)
**Symptoms:** 503 Service Unavailable for subdomain

**Detection:**
```bash
curl http://127.0.0.1:9000/stats  # Check HAProxy stats
docker logs vless_haproxy --tail 50
grep "subdomain.example.com" /opt/vless/config/haproxy.cfg
```

**Solution:**
```bash
# Verify dynamic ACL section
grep "DYNAMIC_REVERSE_PROXY_ROUTES" /opt/vless/config/haproxy.cfg

# Manual HAProxy reload
docker exec vless_haproxy haproxy -sf $(docker exec vless_haproxy cat /var/run/haproxy.pid)
```

---

#### Issue 4: Xray Container Unhealthy - Wrong Port Configuration
**Symptoms:** vless_xray shows (unhealthy), HAProxy logs "Connection refused"

**Detection:**
```bash
docker ps --filter "name=vless_xray" --format "{{.Status}}"
docker logs vless_haproxy | grep "xray_vless"
jq -r '.inbounds[0].port' /opt/vless/config/xray_config.json
```

**Root Cause:**
Xray configured to listen on port 443 instead of 8443 (v4.3 HAProxy architecture requires Xray on internal port 8443)

**Solution:**
```bash
# Fix Xray port configuration
sudo sed -i 's/"port": 443,/"port": 8443,/' /opt/vless/config/xray_config.json

# Fix fallback container name
sudo sed -i 's/"dest": "vless_nginx:80"/"dest": "vless_fake_site:80"/' /opt/vless/config/xray_config.json

# Restart Xray container
docker restart vless_xray

# Verify fix
docker ps --filter "name=vless_xray" --format "{{.Status}}"
docker logs vless_haproxy --tail 5 | grep "UP"
```

**Permanent Fix (for future installations):**
Update installation scripts:
- `lib/interactive_params.sh`: DEFAULT_VLESS_PORT=8443
- `lib/orchestrator.sh`: fallback → vless_fake_site:80

🔗 **Полный список:** docs/prd/06_appendix.md (Common Failure Points)

---

### Quick Debug Commands

**System Status:**
```bash
sudo vless-status
docker ps
docker network inspect vless_reality_net
sudo ss -tulnp | grep -E '443|1080|8118'
sudo ufw status numbered
```

**Logs:**
```bash
sudo vless-logs -f
docker logs vless_xray --tail 50
docker logs vless_haproxy --tail 50  # v4.3
docker logs vless_reverse_proxy_nginx --tail 50
```

**Config Validation:**
```bash
jq . /opt/vless/config/config.json
haproxy -c -f /opt/vless/config/haproxy.cfg  # v4.3
docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 xray run -test -c /etc/xray/config.json
```

**HAProxy Tests (v4.3):**
```bash
curl http://127.0.0.1:9000/stats  # Stats page
openssl s_client -connect localhost:1080  # SOCKS5 TLS test
openssl s_client -connect localhost:8118  # HTTP TLS test
```

**Security Testing:**
```bash
# Run comprehensive security test suite
sudo vless test-security

# Quick mode (skip long-running tests)
sudo vless test-security --quick

# Development mode (run without installation)
sudo vless test-security --dev-mode
```

🔗 **Полный список:** docs/prd/06_appendix.md (Debug & Troubleshooting)

---

## 11. DOCUMENTATION MAP

### Navigation Guide

| Документ | Назначение | Размер | Аудитория |
|----------|-----------|--------|-----------|
| **README.md** | User guide, installation instructions | ~15 KB | End users, administrators |
| **CHANGELOG.md** | Version history v3.0-v4.3, migration guides | ~25 KB | Developers, administrators |
| **CLAUDE.md** | Project memory (this file) | ~35 KB | Developers, AI assistant |
| **docs/prd/** | Product Requirements Document (7 модулей) | ~171 KB | Product managers, developers |

### PRD Quick Navigation

**Для быстрого ознакомления:**
- **00_summary.md** - Executive summary, v4.3 overview, quick start guide

**Для разработки:**
- **02_functional_requirements.md** - All FR-* requirements (HAProxy, TLS, Certificates)
- **04_architecture.md** - Section 4.7 HAProxy Unified Architecture, network diagrams
- **03_nfr.md** - Non-functional requirements (Security, Performance, Reliability)

**Для тестирования:**
- **05_testing.md** - v4.3 automated test suite (3 test cases, DEV_MODE support)
- **03_nfr.md** - Performance targets и acceptance criteria

**Для troubleshooting:**
- **06_appendix.md** - Implementation details, rollback procedures, security risk matrix

### Version History Summary

| Версия | Дата | Ключевые изменения |
|--------|------|--------------------|
| **v5.1** | 2025-10-20 | HAProxy Port Fix: Xray 8443 (internal), HAProxy 443 (external) |
| **v5.0** | 2025-10-19 | Optimized CLAUDE.md (-42% размер, -51% строки) |
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture, subdomain-based reverse proxy |
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix |
| **v4.0** | 2025-10-06 | stunnel TLS termination (deprecated in v4.3) |
| **v3.3** | 2025-10-05 | CRITICAL: Mandatory TLS for public proxies |
| **v3.1** | 2025-10-03 | Dual proxy support (SOCKS5 + HTTP) |

🔗 **Полная история:** CHANGELOG.md

---

**END OF OPTIMIZED PROJECT MEMORY**

**Optimization Results:**
```
v5.1 - 2025-10-20: HAProxy Port Configuration Fix
  - Fixed: Xray port 443 → 8443 (internal backend for HAProxy)
  - Fixed: Fallback container vless_nginx → vless_fake_site
  - Updated: Installation scripts (lib/interactive_params.sh, lib/orchestrator.sh)
  - Added: Issue 4 to Common Issues (Xray Unhealthy troubleshooting)

v5.0 - 2025-10-19: Optimized version
  - Size: 60 KB → ~35 KB (↓ 42%)
  - Lines: 1719 → ~850 (↓ 51%)
  - Removed: ~800 lines of duplication with docs/prd/
  - Improved: Navigation, readability, maintainability

v4.3 - 2025-10-18: HAProxy Unified Architecture
v2.1 - 2025-10-03: First optimized version (-33% size)
v2.0 - 2025-10-02: Unified document (workflow + project)
v1.0 - 2025-10-01: Initial project memory
```

This document serves as the single source of truth for both workflow execution rules and project-specific technical documentation for the VLESS + Reality VPN Server project.

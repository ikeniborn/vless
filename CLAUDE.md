# CLAUDE.md - Project Memory & Workflow Rules

**Project:** VLESS + Reality VPN Server  
**Version:** 2.0  
**Last Updated:** 2025-10-02  
**Purpose:** Unified project memory combining workflow execution rules and project-specific technical documentation

---

## TABLE OF CONTENTS

### PART I: UNIVERSAL WORKFLOW EXECUTION RULES
1. [Critical Principles (P1-P5)](#part-i-universal-workflow-execution-rules)
2. [High Priority Rules (P6-P10)](#2-high-priority-rules-p6-p10)
3. [Medium Priority Rules (P11-P13)](#3-medium-priority-rules-p11-p13)
4. [Prohibited Actions](#4-prohibited-actions)
5. [Mandatory Actions](#5-mandatory-actions)
6. [Standard Formats](#6-standard-formats)
7. [Violation Levels](#7-violation-levels)
8. [Rule Application](#8-rule-application)
9. [Control Checklist](#9-control-checklist)

### PART II: PROJECT-SPECIFIC DOCUMENTATION
10. [Project Overview](#part-ii-project-specific-documentation)
11. [Critical System Parameters](#11-critical-system-parameters)
12. [Project Structure](#12-project-structure)
13. [Critical Requirements](#13-critical-requirements-for-validation)
14. [Non-Functional Requirements](#14-non-functional-requirements-nfr)
15. [Common Failure Points & Solutions](#15-common-failure-points--solutions)
16. [Testing Checklist](#16-testing-checklist)
17. [Technical Details](#17-technical-details)
18. [Scalability & Constraints](#18-scalability--constraints)
19. [Security Threat Model](#19-security-threat-model)
20. [Debug Commands](#20-quick-debug-commands)
21. [Success Metrics](#21-success-metrics)
22. [Usage Guidelines](#22-usage-guidelines)

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

**НЕ ДЕЛАЙТЕ:**
- ❌ Не угадывайте намерения пользователя
- ❌ Не делайте assumptions
- ❌ Не выбирайте произвольно между вариантами
- ❌ Не продолжайте при критичной неясности

**Формат вопроса:**
```
❓ ТРЕБУЕТСЯ УТОЧНЕНИЕ

Неясно: [что конкретно]

Варианты:
1. [вариант 1]: [что это означает]
2. [вариант 2]: [что это означает]

Вопрос: [конкретный вопрос]

Пожалуйста, уточните для продолжения.
```

---

### P12: Decision Documentation (MEDIUM)
**Правило:** Документируйте важные технические решения.

**Что документировать:**
- Выбор между альтернативными подходами
- Отклонение очевидных вариантов
- Trade-offs и компромиссы
- Assumptions и ограничения
- Риски и митигация

**Формат документации:**
```
РЕШЕНИЕ: [что решили]
ОБОСНОВАНИЕ: [почему]
АЛЬТЕРНАТИВЫ: [что рассматривалось и почему отклонено]
TRADE-OFFS: [что жертвуем / что получаем]
РИСКИ: [какие риски и как минимизируем]
```

---

### P13: Conditional Execution (MEDIUM)
**Правило:** Выполняйте conditional actions только при выполнении condition.

**Для `conditional="true"` actions:**
- ✓ Проверьте condition явно
- ✓ Выполните action только если condition = true
- ✓ Если condition = false - пропустите action
- ✓ Документируйте почему пропущен

---

## 4. PROHIBITED ACTIONS

### НИКОГДА НЕ ДЕЛАЙТЕ:

❌ **НЕ пропускайте фазы** - все фазы обязательны и последовательны

❌ **НЕ пропускайте actions** - все actions внутри фазы обязательны

❌ **НЕ пропускайте thinking** - для requires_thinking="true" actions

❌ **НЕ пропускайте mandatory_output** - все output="required" actions

❌ **НЕ сокращайте форматы** - используйте полные mandatory_format

❌ **НЕ продолжайте при critical failures** - STOP немедленно

❌ **НЕ игнорируйте blocking conditions** - они блокируют продолжение

❌ **НЕ игнорируйте exit_conditions** - проверяйте перед продолжением

❌ **НЕ переходите без checkpoint** - проверка обязательна

❌ **НЕ делайте assumptions** - ASK при неясности

❌ **НЕ пропускайте approval gates** - ждите подтверждения

❌ **НЕ игнорируйте ошибки** - обрабатывайте явно

---

## 5. MANDATORY ACTIONS

### ВСЕГДА ДЕЛАЙТЕ:

✓ **ВСЕГДА используйте thinking** для requires_thinking="true" actions

✓ **ВСЕГДА выводите mandatory_output** для output="required" actions

✓ **ВСЕГДА проверяйте exit_conditions** перед продолжением

✓ **ВСЕГДА проходите checkpoints** с verification перед переходом

✓ **ВСЕГДА ждите approval** для required approval gates

✓ **ВСЕГДА останавливайтесь** при critical failures

✓ **ВСЕГДА спрашивайте** при неясности

✓ **ВСЕГДА документируйте** важные решения

✓ **ВСЕГДА следуйте форматам** - используйте полные mandatory_format

✓ **ВСЕГДА выполняйте последовательно** - фазы и actions по порядку

✓ **ВСЕГДА обрабатывайте ошибки** - следуйте error_handling правилам

✓ **ВСЕГДА проверяйте conditions** - entry, exit, blocking

---

## 6. STANDARD FORMATS

### Формат Thinking (для критических действий):
```xml
<thinking>
КОНТЕКСТ: [текущая ситуация]
ЗАДАЧА: [что нужно сделать]
ОПЦИИ: 
  1. [вариант 1]: [плюсы/минусы]
  2. [вариант 2]: [плюсы/минусы]
ВЫБОР: [вариант N] потому что [обоснование]
РИСКИ: [что может пойти не так]
МИТИГАЦИЯ: [как минимизируем риски]
ПРОВЕРКА: [как валидируем результат]
</thinking>
```

### Формат Error Message:
```
[ICON] ОШИБКА: [Тип]

Проблема: [описание]
Контекст: [где произошло]
Причина: [почему произошло]

Действие: [что делаем - STOP/RETRY/ASK]

[Дополнительная информация]
```

### Формат Checkpoint Verification:
```
PHASE N CHECKPOINT:
═══════════════════════════════════════
[✓/✗] Check 1 (priority): [детали]
[✓/✗] Check 2 (priority): [детали]
[✓/✗] Check N (priority): [детали]

РЕЗУЛЬТАТ: ✓ ALL PASSED / ✗ FAILED
[Если FAILED: список проблем]

Переход к Phase N+1: [ALLOWED/BLOCKED]
═══════════════════════════════════════
```

### Формат Validation Result:
```
VALIDATION: [название]
═══════════════════════════════════════
Item 1: [что проверяли]
[✓/✗] Статус: [PASSED/FAILED]
Проверка: [как проверили]
Результат: [что получили]

[... для каждого item ...]

ОБЩИЙ РЕЗУЛЬТАТ: ✓ PASSED / ✗ FAILED

[Если FAILED: детали проблем и необходимые действия]
═══════════════════════════════════════
```

---

## 7. VIOLATION LEVELS

### FATAL (Критическая ошибка)
- **Последствие:** Немедленная остановка выполнения
- **Примеры:** 
  - Пропуск фазы
  - Пропуск critical action
  - Отсутствие thinking для requires_thinking="true"
  - Игнорирование blocking condition

### BLOCKING (Блокирующая ошибка)
- **Последствие:** Нельзя продолжить до исправления
- **Примеры:**
  - Отсутствие mandatory_output
  - Failed exit_condition
  - Failed checkpoint
  - Невыполнение entry_condition

### WARNING (Предупреждение)
- **Последствие:** Продолжение возможно, но нежелательно
- **Примеры:**
  - Отсутствие документации решения
  - Неполное описание в non-critical outputs
  - Assumptions при низкой критичности

---

## 8. RULE APPLICATION

### Как использовать эти правила:

1. **При получении structured workflow промпта:**
   - Прочитайте эти универсальные правила
   - Прочитайте специфичные правила промпта
   - Применяйте ОБА набора правил

2. **Приоритет при конфликте:**
   - Универсальные правила (этот документ) - БАЗОВЫЕ
   - Специфичные правила промпта - могут ДОПОЛНЯТЬ
   - При конфликте - специфичные правила важнее

3. **Проверка соответствия:**
   - Перед каждой фазой - проверьте entry_conditions
   - Перед каждым action - проверьте requires_thinking
   - После каждого action - проверьте exit_condition
   - После каждой фазы - проверьте checkpoint

4. **При сомнении:**
   - STOP и ASK
   - Не делайте assumptions
   - Лучше спросить, чем ошибиться

---

## 9. CONTROL CHECKLIST

Используйте этот чеклист для КАЖДОЙ фазы:

### Перед началом фазы:
- [ ] Entry conditions проверены
- [ ] Все conditions выполнены
- [ ] Thinking выполнен (если требуется)

### Во время выполнения фазы:
- [ ] Actions выполняются последовательно
- [ ] Thinking перед requires_thinking="true" actions
- [ ] Mandatory outputs выведены
- [ ] Exit conditions проверены для каждого action
- [ ] Blocking conditions соблюдены

### После завершения фазы:
- [ ] Все actions выполнены
- [ ] Checkpoint пройден
- [ ] Verification instruction выведена
- [ ] Approval получен (если required)
- [ ] Exit conditions выполнены

### При ошибке:
- [ ] Тип ошибки определен
- [ ] Error message выведено
- [ ] Error action выполнен (STOP/RETRY/ASK)
- [ ] Проблема не игнорируется

---

# PART II: PROJECT-SPECIFIC DOCUMENTATION

## 10. PROJECT OVERVIEW

**Project Name:** VLESS + Reality VPN Server  
**Version:** 1.4  
**Target Scale:** 10-50 concurrent users  
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)  
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, Nginx

**Core Value Proposition:**
- Deploy production-ready VPN in < 5 minutes
- Zero manual configuration through intelligent automation
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- No domain/certificate management required
- Coexists with Outline, Wireguard, other VPN services

**Key Innovation:**
Reality protocol "steals" TLS handshake from legitimate websites (google.com, microsoft.com), making VPN traffic mathematically indistinguishable from normal HTTPS. Deep Packet Inspection systems cannot detect the VPN.

---

## 11. CRITICAL SYSTEM PARAMETERS

### Technology Stack (MUST FOLLOW EXACTLY)

```yaml
Docker & Orchestration:
  docker_engine: "20.10+"          # Minimum version
  docker_compose: "v2.0+"          # v2 syntax required
  compose_command: "docker compose" # NOT docker-compose

Container Images (FIXED VERSIONS):
  xray: "teddysun/xray:24.11.30"   # DO NOT change without testing
  nginx: "nginx:alpine"             # Latest alpine

Operating System:
  primary: "Ubuntu 20.04+, 22.04 LTS, 24.04 LTS"
  secondary: "Debian 10+, 11, 12"
  not_supported: "CentOS, RHEL, Fedora" # firewalld vs UFW

Shell & Tools:
  bash: "4.0+"
  jq: "1.5+"                        # JSON processing
  qrencode: "latest"                # QR code generation
  openssl: "system default"         # Key generation, SNI
  uuidgen: "system default"         # UUID generation
```

### Protocol Configuration

```yaml
VPN Protocol:
  protocol: "VLESS"                 # VMess-Less, no encryption
  security: "Reality"               # TLS 1.3 masquerading
  flow: "xtls-rprx-vision"         # Performance optimization
  transport: "TCP"                  # Base transport

Reality Settings:
  key_algorithm: "X25519"           # Elliptic curve DH
  tls_version: "1.3"                # Required for Reality
  dest_default: "google.com:443"    # Masquerading target
  sni_extraction: "required"        # Must succeed
  validation_timeout: "10s"         # Max time for dest check
```

### Network Architecture

```yaml
Docker Network:
  name: "vless_reality_net"
  driver: "bridge"
  subnet_default: "172.20.0.0/16"
  subnet_detection: "automatic"     # Scans existing networks
  isolation: "complete"             # Separate from other VPNs

Ports:
  vless_default: 443
  vless_alternatives: [8443, 2053, 2083, 2087]
  nginx_internal: 8080              # Not exposed to host
  port_detection: "automatic"       # ss -tulnp check

Firewall (UFW):
  status_required: "active"
  docker_integration: "/etc/ufw/after.rules"
  rule_format: "allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'"
```

### Installation Path (HARDCODED)

```yaml
Base Path: "/opt/vless/"            # CANNOT be changed

Directory Structure:
  config/:     "700"                # Sensitive configs
  data/:       "700"                # User data, backups
  logs/:       "755"                # Access/error logs
  fake-site/:  "755"                # Nginx configs
  scripts/:    "755"                # Management scripts

File Permissions:
  config.json:         "600"
  users.json:          "600"
  reality_keys.json:   "600"
  .env:                "600"
  docker-compose.yml:  "644"
  scripts/*.sh:        "755"

Symlinks:
  location: "/usr/local/bin/"
  pattern: "vless-*"
  permissions: "755"                # Sudo-accessible
```

---

## 12. PROJECT STRUCTURE

### Development Structure (Before Installation)

```
/home/ikeniborn/Documents/Project/vless/
├── install.sh                      # Main installer entry point
├── PLAN.md                         # Implementation roadmap
├── PRD.md                          # Product requirements (this expanded)
├── CLAUDE.md                       # This file - project memory
├── lib/                            # Installation modules
│   ├── os_detection.sh             # Detect OS, version, arch
│   ├── dependencies.sh             # Install Docker, compose, tools
│   ├── old_install_detect.sh       # Find existing installations
│   ├── interactive_params.sh       # Collect user inputs
│   ├── sudoers_info.sh             # Configure sudo access
│   ├── orchestrator.sh             # Main installation flow
│   └── verification.sh             # Post-install checks
├── docs/                           # Additional documentation
│   ├── OLD_INSTALL_DETECT_REPORT.md
│   ├── INTERACTIVE_PARAMS_REPORT.md
│   └── SUDOERS_INFO_REPORT.md
├── tests/                          # Test suite
│   ├── unit/                       # Unit tests (bats framework)
│   │   ├── test_os_detection.bats
│   │   ├── test_port_check.bats
│   │   └── test_subnet_detection.bats
│   └── integration/                # Integration tests
│       ├── test_fresh_install.bats
│       ├── test_user_management.bats
│       └── test_multi_vpn.bats
├── scripts/                        # Dev utilities
│   ├── dev-helpers/
│   │   ├── reset_test_env.sh
│   │   └── validate_configs.sh
│   └── ci/                         # CI/CD scripts
│       └── run_tests.sh
└── requests/                       # Workflow templates
    ├── request_implement.xml
    ├── request_debug.xml
    └── request_review.xml
```

### Production Structure (After Installation)

```
/opt/vless/                         # Created by installer
├── config/                         # 700, owner: root
│   ├── config.json                 # 600 - Xray main config
│   ├── users.json                  # 600 - User database
│   └── reality_keys.json           # 600 - X25519 key pair
│
├── data/                           # 700, user data
│   ├── clients/                    # Per-user configs
│   │   └── {username}/
│   │       ├── config.json         # v2rayN/NG format
│   │       ├── uri.txt             # VLESS URI
│   │       └── qrcode.png          # QR code image
│   └── backups/                    # Automatic backups
│       ├── users.json.backup.{timestamp}
│       └── reality_keys.json.backup.{timestamp}
│
├── logs/                           # 755, log files
│   ├── access.log                  # 644 - Xray access log
│   └── error.log                   # 644 - Xray error log
│
├── fake-site/                      # 755, Nginx configs
│   └── default.conf                # 644 - Reverse proxy
│
├── scripts/                        # 755, management tools
│   ├── user-manager.sh             # 755 - CRUD operations
│   ├── service-manager.sh          # 755 - Service control
│   └── common-functions.sh         # 755 - Shared utilities
│
├── .env                            # 600 - Environment variables
└── docker-compose.yml              # 644 - Container orchestration

/usr/local/bin/                     # Symlinks (sudo-accessible)
├── vless-install -> /opt/vless/scripts/install.sh
├── vless-user -> /opt/vless/scripts/user-manager.sh
├── vless-start -> /opt/vless/scripts/service-manager.sh
├── vless-stop -> /opt/vless/scripts/service-manager.sh
├── vless-restart -> /opt/vless/scripts/service-manager.sh
├── vless-status -> /opt/vless/scripts/service-manager.sh
├── vless-logs -> /opt/vless/scripts/service-manager.sh
├── vless-update -> /opt/vless/scripts/update.sh
└── vless-uninstall -> /opt/vless/scripts/uninstall.sh
```

---

## 13. CRITICAL REQUIREMENTS FOR VALIDATION

### FR-001: Interactive Installation (CRITICAL - Priority 1)

**Target:** Installation completes in < 5 minutes

**Requirements:**
```yaml
Validation BEFORE Application:
  - All parameters validated before use
  - Clear error messages with fix suggestions
  - Cancel and retry capability at any step
  - Progress indicators for long operations

Environment Detection:
  - OS version and architecture
  - Docker and compose versions (install if missing)
  - UFW status (install/enable if needed)
  - Existing VPN services (Outline, Wireguard)
  - Occupied ports and Docker subnets
  - Old VLESS installations
```

**Acceptance Criteria:**
```
✓ All parameters prompted with intelligent defaults
✓ Each parameter validated immediately after input
✓ Errors include actionable guidance (not just "failed")
✓ Can cancel at any point without leaving partial state
✓ Total time < 5 minutes on clean Ubuntu 22.04 (10 Mbps)
```

**Testing Command:**
```bash
time sudo ./install.sh
# Should output: "Installation complete" in < 5 minutes
```

---

### FR-002: Old Installation Detection (CRITICAL - Priority 1)

**Requirement:** Detect existing installations and offer safe options

**Detection Checks:**
```bash
# 1. Check directory
if [ -d "/opt/vless/" ]; then
  echo "Old installation found in /opt/vless/"
fi

# 2. Check containers
docker ps -a --format '{{.Names}}' | grep -E '^vless-'

# 3. Check networks
docker network ls --format '{{.Name}}' | grep -E '^vless_'

# 4. Check symlinks
ls -la /usr/local/bin/vless-* 2>/dev/null
```

**User Options:**
```yaml
1. DELETE:
  - Backup users.json to /tmp/vless_backup_{timestamp}/
  - Backup reality_keys.json to same location
  - docker-compose down (remove containers)
  - docker network rm vless_reality_net
  - rm -rf /opt/vless/
  - rm /usr/local/bin/vless-*
  - Proceed with fresh installation

2. UPDATE:
  - Backup users.json and reality_keys.json
  - Preserve existing users and keys
  - Update Docker images (docker-compose pull)
  - Regenerate configs with new parameters
  - Merge old users into new config
  - docker-compose up -d --force-recreate

3. CANCEL:
  - Exit without making any changes
  - Display backup recommendation
```

**Acceptance Criteria:**
```
✓ All three detection checks work correctly
✓ User presented with clear options
✓ DELETE: Complete removal + backup to /tmp/
✓ UPDATE: Users and keys preserved, containers updated
✓ CANCEL: No changes made, safe exit
✓ Backup created BEFORE any destructive operations
```

---

### FR-004: Dest Site Validation (CRITICAL - Priority 1)

**Requirement:** Validate destination site for Reality masquerading

**Default Options:**
```yaml
1: "google.com:443"          # Default, most reliable
2: "www.microsoft.com:443"   # Alternative
3: "www.apple.com:443"       # Alternative
4: "www.cloudflare.com:443"  # Alternative
5: "Custom"                  # User-provided
```

**Validation Steps:**
```bash
# 1. TLS 1.3 Support
curl -vI https://${dest} 2>&1 | grep -i "TLSv1.3"

# 2. HTTP/2 Support (preferred)
curl -vI https://${dest} 2>&1 | grep -i "HTTP/2"

# 3. SNI Extraction
openssl s_client -servername ${dest} \
  -connect ${dest}:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -text \
  | grep -A1 "Subject Alternative Name"

# 4. Reachability
curl -s -o /dev/null -w "%{http_code}" https://${dest}
# Should return 200, 301, 302, etc. (not timeout)

# 5. Response time
time curl -s -o /dev/null https://${dest}
# Should complete in < 3 seconds
```

**Validation Criteria:**
```yaml
TLS 1.3:      REQUIRED     # Reality needs TLS 1.3
HTTP/2:       PREFERRED    # Better performance, not required
SNI Extract:  REQUIRED     # Must successfully extract serverNames
Reachability: REQUIRED     # Must respond (any HTTP code)
Latency:      < 10 seconds # Total validation time
```

**Fallback Strategy:**
```
If selected dest fails validation:
  1. Display specific failure reason
  2. Offer alternative destinations
  3. Allow retry with same dest (transient network issue)
  4. Allow custom dest input
  5. Do NOT proceed with invalid dest
```

**Acceptance Criteria:**
```
✓ All 5 validation steps execute
✓ Validation completes in < 10 seconds
✓ Clear feedback on which check failed
✓ Alternatives offered on failure
✓ Can retry or change dest
✓ Cannot proceed with failed validation
```

---

### FR-005: User Creation (CRITICAL - Priority 1)

**Requirement:** Create user in < 5 seconds with automatic config generation

**Command:**
```bash
sudo vless-user add <username>
```

**Workflow:**
```yaml
1. Validate username:
   - Alphanumeric only (no spaces, special chars)
   - Length: 3-32 characters
   - Not already exists in users.json

2. Generate UUID:
   - Command: uuidgen
   - Format: 12345678-1234-1234-1234-123456789012
   - Validate: Check UUID v4 format

3. Generate shortId:
   - Command: openssl rand -hex 8
   - Format: 8-16 hex characters (e.g., a1b2c3d4e5f67890)
   - Validate: Unique among existing users

4. Update users.json:
   - Read with file lock
   - Append new user object
   - Write atomically (tmp file + mv)
   - Validate JSON syntax after write

5. Update config.json:
   - Add to inbounds[0].settings.clients[]
   - Include: id (UUID), flow, email (username)
   - Validate config: jq . config.json

6. Reload Xray:
   - Command: docker-compose restart xray
   - Wait for health check
   - Verify: docker ps shows "healthy"

7. Generate client configs:
   - JSON (v2rayN/v2rayNG format)
   - VLESS URI (vless://...)
   - QR code (PNG + ASCII art)

8. Save to data/clients/{username}/
   - config.json
   - uri.txt
   - qrcode.png

9. Display to user:
   - Print VLESS URI
   - Show QR code in terminal (if supported)
   - Print file locations
```

**Atomic File Operations:**
```bash
# Example: Update users.json with file locking
(
  flock -x 200  # Exclusive lock
  
  # Read current users
  users=$(cat users.json)
  
  # Add new user
  echo "$users" | jq '.users += [{
    "username": "'"$username"'",
    "uuid": "'"$uuid"'",
    "shortId": "'"$shortId"'",
    "created": "'"$(date -Iseconds)"'",
    "enabled": true
  }]' > users.json.tmp
  
  # Atomic move
  mv users.json.tmp users.json
  
) 200>/var/lock/vless-users.lock
```

**Acceptance Criteria:**
```
✓ Total time < 5 seconds (average across 50 users)
✓ UUID is unique (verified via grep)
✓ shortId is unique (verified in users.json)
✓ users.json and config.json updated correctly
✓ Xray reloads without errors (< 3 seconds)
✓ Client configs generated in all 3 formats
✓ Files saved with correct permissions (600)
✓ QR code displays in terminal
✓ No data corruption (JSON remains valid)
```

**Error Handling:**
```yaml
Username exists:
  - Error: "User '{username}' already exists"
  - Action: Suggest vless-user show {username}

UUID collision (unlikely):
  - Regenerate UUID
  - Retry up to 3 times
  - Fatal error if still collides

Xray reload fails:
  - Rollback: Restore previous config.json
  - Error: "Config validation failed"
  - Display: docker logs vless-reality (last 20 lines)

File lock timeout:
  - Wait up to 10 seconds
  - Error: "Another operation in progress"
  - Suggest: "Retry in a moment"
```

---

### FR-011: UFW Integration (CRITICAL - Priority 1)

**Requirement:** Configure UFW firewall with Docker forwarding support

**Critical Files:**
```
/etc/ufw/ufw.conf           # UFW main config
/etc/ufw/after.rules        # Custom rules (Docker chains)
/etc/ufw/before.rules       # Pre-routing rules
/var/lib/ufw/user.rules     # User-added rules
```

**Detection & Configuration:**
```bash
# 1. Check UFW Status
ufw_status=$(ufw status | grep "Status:" | awk '{print $2}')

if [ "$ufw_status" = "inactive" ]; then
  echo "UFW is inactive. Enable? [Y/n]"
  read response
  if [ "$response" != "n" ]; then
    ufw --force enable
  fi
fi

# 2. Check for VLESS port rule
if ! ufw status numbered | grep -q "${VLESS_PORT}/tcp"; then
  ufw allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'
fi

# 3. Check Docker forwarding in /etc/ufw/after.rules
if ! grep -q "DOCKER-USER" /etc/ufw/after.rules; then
  echo "Adding Docker forwarding chains..."
  
  cat >> /etc/ufw/after.rules << 'EOF'

# Docker forwarding rules for VLESS Reality
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
COMMIT
EOF

  ufw reload
fi
```

**Required Rules in /etc/ufw/after.rules:**
```iptables
# BEGIN VLESS Reality Docker Integration
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
COMMIT
# END VLESS Reality Docker Integration
```

**Validation:**
```bash
# 1. UFW is active
ufw status | grep -q "Status: active"

# 2. Port rule exists
ufw status numbered | grep "${VLESS_PORT}/tcp"

# 3. Docker chains exist
grep -q "DOCKER-USER" /etc/ufw/after.rules

# 4. Test connectivity
docker exec vless-reality ping -c 1 8.8.8.8
docker exec vless-reality curl -s https://www.google.com >/dev/null
```

**Acceptance Criteria:**
```
✓ UFW detected (install if missing)
✓ UFW enabled (prompt user if inactive)
✓ Port rule added without duplication
✓ Docker chains added to /etc/ufw/after.rules
✓ No duplicate chain entries
✓ ufw reload succeeds without errors
✓ Containers can access Internet
✓ External connections to ${VLESS_PORT} work
✓ No breaking of existing UFW rules
```

**Common Issues & Fixes:**
```yaml
Issue: Containers can't access Internet
Fix:
  - Verify MASQUERADE rule for subnet
  - Check: iptables -t nat -L POSTROUTING
  - Ensure subnet matches docker-compose.yml

Issue: Duplicate DOCKER-USER chains
Fix:
  - Check /etc/ufw/after.rules for duplicates
  - Remove old entries, keep one set
  - ufw reload

Issue: Port still blocked
Fix:
  - Check ufw status numbered
  - Verify rule: ALLOW ${VLESS_PORT}/tcp
  - Check: ss -tulnp | grep ${VLESS_PORT}
  - Ensure Docker port mapping in compose file
```

---

## 14. NON-FUNCTIONAL REQUIREMENTS (NFR)

### Performance Targets

```yaml
Installation:
  target: "< 5 minutes"
  baseline: "Clean Ubuntu 22.04, 10 Mbps internet"
  excludes: "Docker installation time if not present (add 2-3 min)"
  measurement: "Time from ./install.sh to 'Installation complete'"

User Creation:
  target: "< 5 seconds"
  includes: "UUID gen, config update, Xray reload, QR generation"
  scalability: "Consistent up to 50 users"
  measurement: "Time from 'vless-user add' to QR display"

Container Startup:
  target: "< 10 seconds"
  includes: "docker-compose up -d, health checks pass"
  verification: "docker ps shows both containers 'healthy'"

Config Reload:
  target: "< 3 seconds"
  command: "docker-compose restart xray"
  impact: "Brief interruption to active connections"
  verification: "New clients can connect immediately"

Operations (50 users):
  user_list: "< 1 second"
  user_show: "< 1 second"
  json_read: "< 100 ms"
  json_write: "< 200 ms"
```

### Reliability Requirements

```yaml
Uptime:
  target: "99.9%"
  allowance: "~8.76 hours/year, 43.8 minutes/month"
  excludes: "Planned maintenance windows"
  measurement: "Container uptime tracking"

Restart Policy:
  docker_compose: "restart: unless-stopped"
  behavior: "Auto-restart after crashes, NOT after manual stop"
  verification: "docker inspect vless-reality | grep RestartPolicy"

Failure Modes:
  container_crash:
    - Docker auto-restarts (unless-stopped policy)
    - Logs preserved in /opt/vless/logs/
    - Alert: Check logs for crash reason
  
  host_reboot:
    - Containers start automatically
    - Network recreated if external: true
    - Verify: All services running post-reboot
  
  config_error:
    - Validation BEFORE application
    - Rollback to previous working config
    - No service disruption

Config Validation:
  before_apply: "100% of changes"
  methods:
    - JSON syntax: jq . config.json
    - Xray test: xray run -test -c config.json
    - Schema: Validate users.json structure
    - Port check: ss -tulnp before binding
  rollback: "Keep previous config for auto-restore"
```

### Security Requirements

```yaml
File Permissions (ENFORCED):
  /opt/vless/config/:                 "700"  # root only
  /opt/vless/config/config.json:      "600"  # sensitive
  /opt/vless/config/users.json:       "600"  # sensitive
  /opt/vless/config/reality_keys.json: "600"  # CRITICAL
  /opt/vless/scripts/:                "755"  # executable
  /usr/local/bin/vless-*:             "755"  # sudo access

Container Security:
  xray_user: "nobody (UID 65534)"     # Non-root
  nginx_user: "nginx"                  # Non-root
  capabilities:
    drop: "ALL"
    add: "NET_BIND_SERVICE"            # Only for port < 1024
  verification: "docker exec vless-reality whoami"

Key Management:
  algorithm: "X25519"
  private_key:
    - Permissions: 600
    - Owner: root
    - NEVER transmitted over network
    - NEVER in client configs
  public_key:
    - Freely distributable
    - Included in all client configs
  rotation:
    - Supported via CLI command
    - All clients must update configs

Network Security:
  ufw_status: "active (required)"
  default_policy:
    - incoming: "deny"
    - outgoing: "allow"
  exposed_ports:
    - ${VLESS_PORT}/tcp only
  docker_isolation:
    - Separate network: vless_reality_net
    - No cross-network communication
    - Internet access via MASQUERADE

Input Validation:
  all_scripts: "Quote all variables"
  user_input: "Sanitize before use"
  command_injection: "Never eval user input"
  sql_injection: "N/A (no database)"
```

### Usability Requirements

```yaml
CLI Design:
  command_prefix: "vless-*"           # Consistent naming
  help_text: "Available for all commands"
  examples: "Included in --help output"
  success_metric: "80% tasks without docs lookup"

Error Messages (MUST INCLUDE):
  description: "Clear problem description"
  context: "Where/when error occurred"
  cause: "Root cause (if determinable)"
  suggestions: "Actionable fix steps with commands"
  example: "Try: ufw status OR Check: docker logs vless-reality"

Example Error Message:
  bad: "Error: Port unavailable"
  good: |
    ERROR: Port 443 is occupied
    
    Detected Process: nginx (PID 1234)
    Reason: Another service is using port 443
    
    Options:
      1. Use alternative port:
         sudo vless-install --port 8443
      
      2. Stop conflicting service:
         sudo systemctl stop nginx
      
      3. Cancel installation:
         Press Ctrl+C

Installation UX:
  progress_indicator: "Step X/Y: Current action"
  status_messages: "What's happening now"
  next_step_preview: "What will happen next"
  validation_feedback: "Immediate input validation"
  time_estimates: "Installing Docker (2-3 minutes)..."
```

---

## 15. COMMON FAILURE POINTS & SOLUTIONS

### Issue 1: UFW Blocks Docker Traffic

**Symptoms:**
- Containers start successfully
- `docker ps` shows containers running
- VPN clients can't connect
- Inside container: no Internet access

**Detection:**
```bash
# Test from inside container
docker exec vless-reality ping -c 1 8.8.8.8
# If fails: UFW blocking

# Check UFW rules
ufw status numbered
# Should see: ${VLESS_PORT}/tcp ALLOW

# Check Docker chains
grep -A10 "DOCKER-USER" /etc/ufw/after.rules
```

**Root Cause:**
UFW blocks Docker forwarding by default. Docker creates its own iptables chains, but UFW's rules take precedence.

**Solution:**
```bash
# 1. Add Docker chains to /etc/ufw/after.rules
sudo tee -a /etc/ufw/after.rules > /dev/null << 'EOF'

# Docker VLESS Reality Integration
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN
COMMIT

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
COMMIT
EOF

# 2. Reload UFW
sudo ufw reload

# 3. Verify
docker exec vless-reality ping -c 1 8.8.8.8
# Should succeed now
```

**Prevention:**
Installation script must check and configure UFW during setup (FR-011).

---

### Issue 2: Port 443 Already Occupied

**Symptoms:**
- Installation fails at Docker deployment
- Error: "port is already allocated"
- Cannot bind to 443

**Detection:**
```bash
# Check what's using port 443
sudo ss -tulnp | grep :443
# OR
sudo lsof -i :443

# Example output:
# nginx  1234  root  ... *:443 (LISTEN)
```

**Root Cause:**
Another service (nginx, Apache, Caddy, old VLESS) is using port 443.

**Solution Matrix:**

| Occupying Service | Action |
|-------------------|--------|
| Old VLESS installation | Offer UPDATE option (preserve users) |
| Nginx/Apache (production) | Offer alternative ports: 8443, 2053 |
| Outline VPN | Use different port (e.g., 8443) |
| Unknown process | Display PID, ask user to resolve |

**Implementation:**
```bash
# Interactive prompt
echo "Port 443 is occupied by: $process_name (PID $pid)"
echo ""
echo "Options:"
echo "  1) Use alternative port 8443"
echo "  2) Use custom port"
echo "  3) Stop conflicting service"
echo "  4) Cancel installation"
echo ""
read -p "Your choice [1-4]: " choice
```

**Prevention:**
Installation script must detect port conflicts (FR-010) and offer alternatives.

---

### Issue 3: Docker Subnet Conflicts

**Symptoms:**
- `docker network create` fails
- Error: "Pool overlaps with other one"
- Network creation hangs

**Detection:**
```bash
# List all Docker networks and subnets
docker network ls --format '{{.Name}}'

for net in $(docker network ls --format '{{.Name}}'); do
  echo "Network: $net"
  docker network inspect $net | jq -r '.[0].IPAM.Config[0].Subnet'
done

# Example output:
# Network: bridge -> 172.17.0.0/16
# Network: outline_net -> 172.18.0.0/16
# Network: wireguard_net -> 172.19.0.0/16
```

**Root Cause:**
Trying to create `vless_reality_net` with subnet that overlaps existing network.

**Solution:**
```bash
# Find free subnet in 172.16-31.0.0/16 range
occupied_subnets=$(docker network ls -q | xargs docker network inspect | jq -r '.[].IPAM.Config[].Subnet')

for i in {16..31}; do
  subnet="172.$i.0.0/16"
  if ! echo "$occupied_subnets" | grep -q "$subnet"; then
    echo "Free subnet found: $subnet"
    FREE_SUBNET="$subnet"
    break
  fi
done

# Create network with free subnet
docker network create vless_reality_net \
  --driver bridge \
  --subnet $FREE_SUBNET
```

**Prevention:**
Installation script must scan existing subnets (FR-009) and auto-select free one.

---

### Issue 4: Dest Validation Fails

**Symptoms:**
- Installation fails at dest validation step
- Error: "Unable to extract SNI"
- Error: "TLS 1.3 not supported"

**Detection:**
```bash
# Manual validation
dest="google.com:443"

# Check TLS 1.3
curl -vI https://${dest} 2>&1 | grep -i "TLSv1.3"

# Check SNI extraction
openssl s_client -servername ${dest} -connect ${dest}:443 \
  < /dev/null 2>/dev/null \
  | openssl x509 -noout -text \
  | grep -A1 "Subject Alternative Name"
```

**Root Causes:**
1. DNS resolution failure (can't resolve google.com)
2. Firewall blocking outbound HTTPS
3. Dest site temporarily unavailable
4. Network routing issues

**Solution Matrix:**

| Issue | Detection | Fix |
|-------|-----------|-----|
| DNS failure | `dig google.com` returns NXDOMAIN | Try alternative dest OR fix DNS |
| Firewall block | `curl -vI https://google.com` times out | Configure firewall OR use different dest |
| Site down | HTTP error 5xx | Wait and retry OR use alternative dest |
| TLS < 1.3 | curl shows TLSv1.2 | Use different dest (google.com supports 1.3) |

**Interactive Fallback:**
```bash
echo "Dest validation failed: $reason"
echo ""
echo "Alternatives:"
echo "  1) microsoft.com (try alternative)"
echo "  2) apple.com"
echo "  3) cloudflare.com"
echo "  4) Custom dest"
echo "  5) Retry $dest (transient issue)"
echo ""
read -p "Your choice [1-5]: " choice
```

**Prevention:**
- Offer multiple reliable defaults (FR-004)
- Validate each dest before accepting
- Allow retry for transient failures

---

### Issue 5: Containers Won't Start

**Symptoms:**
- `docker-compose up -d` completes but containers exit
- `docker ps` shows no running containers
- `docker ps -a` shows containers with "Exited (1)"

**Detection:**
```bash
# Check container status
docker ps -a | grep vless

# Check logs
docker logs vless-reality
docker logs vless-fake-site

# Common errors in logs:
# - "config.json: no such file or directory"
# - "invalid config: ..."
# - "bind: address already in use"
```

**Root Causes & Fixes:**

**1. Invalid config.json:**
```bash
# Validate JSON syntax
jq . /opt/vless/config/config.json
# If fails: Fix JSON syntax errors

# Test Xray config
docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 \
  xray run -test -c /etc/xray/config.json
```

**2. Missing volume mounts:**
```bash
# Check docker-compose.yml
cat /opt/vless/docker-compose.yml | grep -A5 volumes

# Should have:
# volumes:
#   - ./config:/etc/xray:ro
#   - ./logs:/var/log/xray:rw
```

**3. Port already bound:**
```bash
# Check host port
sudo ss -tulnp | grep :${VLESS_PORT}

# If occupied: Stop conflicting service or use different port
```

**4. Network doesn't exist:**
```bash
# Check network
docker network ls | grep vless_reality_net

# If missing: Create it
docker network create vless_reality_net --subnet 172.20.0.0/16
```

**Debug Workflow:**
```bash
# Step-by-step debugging
1. Validate config: jq . /opt/vless/config/config.json
2. Test Xray: xray run -test -c /opt/vless/config/config.json
3. Check network: docker network inspect vless_reality_net
4. Check port: ss -tulnp | grep ${VLESS_PORT}
5. Check logs: docker logs vless-reality
6. Try manual start: docker-compose up (no -d, see live errors)
```

---

## 16. TESTING CHECKLIST

### Fresh Installation Test

**Environment:** Clean Ubuntu 22.04 LTS, no Docker, no UFW

```yaml
Pre-conditions:
  - [ ] Fresh OS installation
  - [ ] Root/sudo access
  - [ ] Internet connectivity
  - [ ] No previous VLESS installation

Test Steps:
  1. [ ] Clone repository
  2. [ ] Run: sudo ./install.sh
  3. [ ] Select dest: google.com (default)
  4. [ ] Select port: 443 (default)
  5. [ ] Select subnet: 172.20.0.0/16 (default)
  6. [ ] Wait for completion

Success Criteria:
  - [ ] Installation completes in < 5 minutes
  - [ ] Docker and Docker Compose installed automatically
  - [ ] UFW installed, enabled, configured
  - [ ] Both containers running: docker ps
  - [ ] Admin user created with QR code
  - [ ] Port accessible: ss -tulnp | grep 443
  - [ ] Containers have Internet: docker exec vless-reality ping -c 1 8.8.8.8

Verification Commands:
  - docker ps
  - docker network ls | grep vless
  - ufw status
  - sudo vless-status
  - ls -la /opt/vless/
  - cat /opt/vless/config/users.json
```

### User Management Test

**Environment:** Existing VLESS installation

```yaml
Test: Create User
  - [ ] Run: sudo vless-user add testuser1
  - [ ] Verify: Completes in < 5 seconds
  - [ ] Check: QR code displayed
  - [ ] Verify files exist:
    - /opt/vless/data/clients/testuser1/config.json
    - /opt/vless/data/clients/testuser1/uri.txt
    - /opt/vless/data/clients/testuser1/qrcode.png

Test: List Users
  - [ ] Run: sudo vless-user list
  - [ ] Verify: Table format with columns
  - [ ] Check: testuser1 appears in list

Test: Show User
  - [ ] Run: sudo vless-user show testuser1
  - [ ] Verify: Full config displayed
  - [ ] Check: QR code rendered in terminal

Test: Remove User
  - [ ] Run: sudo vless-user remove testuser1
  - [ ] Confirm: "Remove testuser1? [y/N]"
  - [ ] Enter: y
  - [ ] Verify: User removed from list
  - [ ] Check: Config archived to data/clients/archived/

Success Criteria:
  - [ ] All operations < 5 seconds
  - [ ] UUIDs are unique
  - [ ] shortIds are unique
  - [ ] Xray reloads without errors
  - [ ] Client configs valid
```

### Multi-VPN Coexistence Test

**Environment:** Server with Outline VPN already installed

```yaml
Pre-conditions:
  - [ ] Outline VPN running (port 8080, subnet 172.18.0.0/16)
  - [ ] Outline clients can connect successfully

Test Steps:
  1. [ ] Install VLESS Reality:
     - Select port: 443 (different from Outline)
     - Select subnet: Should auto-detect 172.20.0.0/16
  2. [ ] Verify both VPNs running:
     - docker ps (both Outline and VLESS containers)
  3. [ ] Test Outline client:
     - Connect via Outline
     - Verify Internet access works
  4. [ ] Test VLESS client:
     - Connect via VLESS
     - Verify Internet access works
  5. [ ] Simultaneous connections:
     - Connect both clients from different devices
     - Both should work without interference

Success Criteria:
  - [ ] VLESS detects Outline subnet
  - [ ] VLESS uses different subnet
  - [ ] No port conflicts
  - [ ] Both VPNs function simultaneously
  - [ ] No network routing conflicts
  - [ ] Both containers can access Internet

Verification:
  - docker network ls (should show outline_net and vless_reality_net)
  - docker network inspect outline_net (check subnet)
  - docker network inspect vless_reality_net (check subnet)
  - ss -tulnp | grep -E '(8080|443)' (both ports listening)
```

### DPI Resistance Test

**Environment:** VLESS installed, client connected

```yaml
Test: Traffic Analysis
  Tools:
    - Wireshark
    - nmap
    - curl
    - VPN client (v2rayN/v2rayNG)

  1. [ ] Capture VPN traffic with Wireshark:
     - Filter: tcp.port == 443
     - Connect VPN client
     - Analyze: Should look like HTTPS to google.com
     - Check: No VLESS-specific signatures

  2. [ ] Port scan from external host:
     - nmap -p 443 -sV <server-ip>
     - Should report: HTTPS service
     - Should NOT report: VPN or proxy

  3. [ ] Direct browser access:
     - Open: https://<server-ip>:443
     - Should see: Google homepage (proxied)
     - Behavior: Like accessing google.com

  4. [ ] Invalid VPN connection:
     - Use wrong UUID
     - Should fallback: Nginx shows dest site
     - Should NOT: Show error page or rejection

Success Criteria:
  - [ ] Traffic indistinguishable from HTTPS
  - [ ] Port scan shows generic HTTPS
  - [ ] Browser shows fake-site (dest proxied)
  - [ ] Invalid auth → fake-site (not rejected)
  - [ ] No protocol fingerprints detectable
```

### Update & Data Preservation Test

**Environment:** VLESS with 10 users

```yaml
Pre-conditions:
  - [ ] VLESS installed and running
  - [ ] 10 users created (user1 through user10)
  - [ ] All users have active client configs
  - [ ] Note: Current Docker image version

Test Steps:
  1. [ ] Create test users:
     for i in {1..10}; do
       sudo vless-user add testuser$i
     done

  2. [ ] Backup users manually:
     cp /opt/vless/config/users.json ~/users_before.json

  3. [ ] Run update:
     sudo vless-update

  4. [ ] Wait for completion

  5. [ ] Verify users preserved:
     diff ~/users_before.json /opt/vless/config/users.json

  6. [ ] Test client connections:
     - Pick 3 random users
     - Test their client configs still work

  7. [ ] Check Docker image:
     docker images | grep xray
     - Should show: New image pulled
     - Old image may still exist (not auto-removed)

Success Criteria:
  - [ ] All 10 users present in users.json
  - [ ] Reality keys unchanged
  - [ ] Client configs still valid
  - [ ] VPN connections work
  - [ ] No data loss
  - [ ] Containers running with new image
  - [ ] Total downtime < 30 seconds
```

### Stress Test (50 Users)

**Environment:** VLESS installation

```yaml
Test: Create 50 Users
  Script:
    #!/bin/bash
    for i in {1..50}; do
      time sudo vless-user add user$i
    done

Success Criteria:
  - [ ] All 50 users created successfully
  - [ ] Average creation time < 5 seconds
  - [ ] No UUID collisions
  - [ ] No shortId collisions
  - [ ] users.json remains valid JSON
  - [ ] All client configs generated
  - [ ] File operations remain fast:
    - vless-user list < 1 second
    - vless-user show user25 < 1 second

Performance Metrics:
  - users.json size: ~10-15 KB (reasonable)
  - config.json size: ~30-40 KB (reasonable)
  - Xray memory: ~80-100 MB (acceptable)
  - File read/write: < 200ms (acceptable)
```

---

## 17. TECHNICAL DETAILS

### Reality Key Management

**Generation:**
```bash
# Using xray binary
xray x25519

# Output format:
Private key: SChVrmR2cGp3SnBRNTVMOHk4RUVzK2h6...
Public key: kLWZczP8AD9qK7c0dVxQjP7UJlCr3rKmhq...
```

**Storage Structure:**
```json
{
  "private_key": "SChVrmR2cGp3SnBRNTVMOHk4RUVzK2h6...",
  "public_key": "kLWZczP8AD9qK7c0dVxQjP7UJlCr3rKmhq...",
  "generated_at": "2025-10-01T12:00:00Z",
  "algorithm": "X25519"
}
```

**File:** `/opt/vless/config/reality_keys.json`  
**Permissions:** 600 (root only)  
**Backup:** Automatic during updates to `data/backups/`

**Security:**
- Private key: NEVER leave server, NEVER in client configs
- Public key: Distributed in all client configs
- Keys can be rotated (requires client config updates)

---

### User Data Structure

**File:** `/opt/vless/config/users.json`  
**Permissions:** 600  
**Format:** JSON

```json
{
  "version": "1.0",
  "users": [
    {
      "username": "admin",
      "uuid": "12345678-1234-1234-1234-123456789012",
      "shortId": "a1b2c3d4e5f67890",
      "email": "admin@local",
      "created_at": "2025-10-01T12:00:00Z",
      "enabled": true,
      "notes": "First admin user"
    },
    {
      "username": "user1",
      "uuid": "abcdef12-3456-7890-abcd-ef1234567890",
      "shortId": "1234567890abcdef",
      "email": "user1@local",
      "created_at": "2025-10-01T13:00:00Z",
      "enabled": true,
      "notes": ""
    }
  ],
  "metadata": {
    "total_users": 2,
    "last_modified": "2025-10-01T13:00:00Z",
    "format_version": "1.0"
  }
}
```

**Operations:**

1. **Add User (Atomic):**
```bash
(
  flock -x 200
  
  # Generate credentials
  uuid=$(uuidgen)
  shortId=$(openssl rand -hex 8)
  timestamp=$(date -Iseconds)
  
  # Read, update, write
  jq --arg user "$username" \
     --arg uuid "$uuid" \
     --arg sid "$shortId" \
     --arg ts "$timestamp" \
     '.users += [{
        "username": $user,
        "uuid": $uuid,
        "shortId": $sid,
        "created_at": $ts,
        "enabled": true
      }] | .metadata.last_modified = $ts' \
     users.json > users.json.tmp
  
  mv users.json.tmp users.json
  
) 200>/var/lock/vless-users.lock
```

2. **Remove User:**
```bash
jq --arg user "$username" \
   'del(.users[] | select(.username == $user))' \
   users.json > users.json.tmp && mv users.json.tmp users.json
```

3. **List Users:**
```bash
jq -r '.users[] | "\(.username)\t\(.uuid)\t\(.shortId)\t\(.created_at)"' \
   users.json
```

---

### Client Configuration Formats

**1. JSON (v2rayN/v2rayNG):**
```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "SERVER_IP",
            "port": 443,
            "users": [
              {
                "id": "UUID",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "google.com",
          "publicKey": "PUBLIC_KEY",
          "shortId": "SHORT_ID",
          "spiderX": "/"
        }
      },
      "tag": "proxy"
    }
  ]
}
```

**2. VLESS URI:**
```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#USERNAME
```

**Parameters Explanation:**
- `UUID`: User identifier
- `SERVER_IP`: Your VPS IP address
- `443`: VLESS port
- `encryption=none`: VLESS doesn't use built-in encryption
- `flow=xtls-rprx-vision`: XTLS flow control
- `security=reality`: Use Reality protocol
- `sni=google.com`: Server Name Indication (dest site)
- `fp=chrome`: TLS fingerprint (Chrome browser)
- `pbk=PUBLIC_KEY`: Reality public key
- `sid=SHORT_ID`: Additional authentication
- `type=tcp`: TCP transport
- `#USERNAME`: User-friendly label

**3. QR Code Generation:**
```bash
# PNG image
qrencode -o qrcode.png -t PNG -s 10 "vless://..."

# Terminal ASCII art
qrencode -t ANSIUTF8 "vless://..."

# UTF8 text
qrencode -t UTF8 "vless://..."
```

---

### Xray Configuration (config.json)

**Full Structure:**
```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID",
            "flow": "xtls-rprx-vision",
            "email": "username@local"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "nginx:8080",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "google.com:443",
          "xver": 0,
          "serverNames": [
            "google.com",
            "www.google.com"
          ],
          "privateKey": "PRIVATE_KEY",
          "shortIds": [
            "",
            "0123456789abcdef"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
```

**Key Sections:**

- **log**: Access and error logging
- **inbounds**: VLESS listening configuration
- **clients[]**: Array of authorized users
- **fallbacks**: Redirect invalid connections to Nginx
- **realitySettings**: Reality protocol parameters
- **serverNames**: SNI values (must match dest site)
- **shortIds**: Additional authentication layer
- **outbounds**: Traffic routing (freedom = direct, blackhole = blocked)

---

### Nginx Configuration (fake-site)

**File:** `/opt/vless/fake-site/default.conf`

```nginx
server {
    listen 8080;
    server_name _;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    location / {
        # Reverse proxy to destination site
        proxy_pass https://google.com;
        
        # SSL settings
        proxy_ssl_server_name on;
        proxy_ssl_name google.com;
        proxy_ssl_verify off;
        
        # Headers
        proxy_set_header Host google.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # Timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # Cache (optional)
        proxy_cache_valid 200 1h;
        proxy_cache_valid 404 1m;
    }
}
```

**Purpose:**
- Receives fallback traffic from Xray
- Proxies requests to destination site (google.com)
- Makes server appear as normal HTTPS website
- Enhances DPI resistance

---

## 18. SCALABILITY & CONSTRAINTS

### Current Design (10-50 Users)

**Architecture:**
```yaml
User Storage: JSON files (users.json)
Locking: File-based (flock)
Orchestration: Docker Compose
Management: Bash scripts
Database: None (JSON sufficient)
```

**Performance Characteristics:**
```yaml
User Operations (50 users):
  add: "< 5 seconds"
  remove: "< 3 seconds"
  list: "< 1 second"
  show: "< 1 second"

File Sizes:
  users.json: "~10 KB (50 users)"
  config.json: "~30 KB (50 users)"
  
Memory Usage:
  Xray container: "~80 MB (50 concurrent connections)"
  Nginx container: "~20 MB"
  
Disk Usage:
  Base installation: "~200 MB"
  Per user (configs): "~50 KB"
  Logs (daily): "~10-50 MB"
```

**Design Strengths:**
- Simple architecture (easy to understand, debug)
- No database overhead
- JSON files easily backed up, restored, edited
- Atomic operations via file locking
- Fast for target scale (10-50 users)

**Design Limitations:**
- JSON parsing slowdown beyond 100 users
- File locking contention with high concurrent ops
- No query optimization (always full file read)
- No connection pooling
- No horizontal scaling

---

### Beyond 50 Users (Out of Scope v1.0)

**Required Changes:**

```yaml
User Storage:
  current: "JSON files"
  future: "Database (SQLite or PostgreSQL)"
  reason: "Better performance, ACID guarantees, queries"

Locking:
  current: "File-based (flock)"
  future: "Database transactions"
  reason: "Proper concurrency, no file contention"

Management:
  current: "Bash scripts"
  future: "API server (Python FastAPI or Go)"
  reason: "RESTful API, better error handling, auth"

Orchestration:
  current: "Docker Compose"
  future: "Kubernetes (for multi-server)"
  reason: "Horizontal scaling, load balancing"

Monitoring:
  current: "Docker logs only"
  future: "Prometheus + Grafana"
  reason: "Metrics, alerting, dashboards"
```

**Estimated Effort:**
- 50-100 users: 2-3 weeks (SQLite + refactor scripts)
- 100-500 users: 1-2 months (PostgreSQL + API server)
- 500+ users: 3-6 months (Kubernetes + full rewrite)

**Recommendation:**
For deployments > 50 users, consider multiple independent instances (e.g., server1 for users 1-50, server2 for users 51-100). This avoids architectural redesign while maintaining simplicity.

---

## 19. SECURITY THREAT MODEL

### Threat Matrix

| Threat | Likelihood | Impact | Severity | Mitigation |
|--------|-----------|--------|----------|------------|
| **DPI Detection** | Low | High | HIGH | Reality protocol TLS masquerading |
| **Private Key Compromise** | Low | Critical | CRITICAL | 600 perms, root-only, never transmitted |
| **Brute Force UUID** | Low | Medium | MEDIUM | UUID + shortId required (2^128 space) |
| **Container Escape** | Very Low | High | HIGH | Non-root user, minimal capabilities |
| **Port Scanning** | High | Low | LOW | Fake-site shows legitimate HTTPS |
| **Man-in-the-Middle** | Medium | High | HIGH | Reality forward secrecy (X25519) |
| **DoS Attack** | Medium | Medium | MEDIUM | Rate limiting (future), UFW rules |
| **Config File Tampering** | Low | High | HIGH | 600 perms, root-only access |
| **Replay Attack** | Low | Medium | MEDIUM | Reality nonce, forward secrecy |
| **Side-Channel Timing** | Very Low | Low | LOW | Constant-time operations in Xray |

### Attack Scenarios & Defenses

**Scenario 1: Adversary Scanning Network**
```
Attack: Port scan to identify VPN servers
Detection: nmap -p 443 -sV <server-ip>
Defense:
  ✓ Fake-site (Nginx) responds as HTTPS website
  ✓ No VPN-specific signatures in response
  ✓ Appears as google.com (proxied)
  ✓ Deep inspection shows TLS 1.3 to google.com
Result: Undetectable as VPN
```

**Scenario 2: DPI Analysis of Traffic**
```
Attack: Packet capture and protocol analysis
Detection: Wireshark, deep packet inspection
Defense:
  ✓ Reality protocol steals TLS handshake from dest
  ✓ Traffic identical to HTTPS to google.com
  ✓ No protocol fingerprints (GFW tested)
  ✓ Randomized timing, padding (in Xray)
Result: Indistinguishable from normal HTTPS
```

**Scenario 3: Brute Force UUID**
```
Attack: Try random UUIDs to gain access
Complexity: 2^128 UUID space × 2^64 shortId space
Defense:
  ✓ UUID: 128-bit random (2^128 combinations)
  ✓ shortId: 64-bit random (2^64 combinations)
  ✓ Both required for authentication
  ✓ Invalid attempts → fallback to fake-site
  ✓ No indication of valid vs invalid
Result: Computationally infeasible
```

**Scenario 4: Compromise Server (Root Access)**
```
Attack: Attacker gains root access to server
Impact:
  ✓ Can read private key (game over for Reality)
  ✓ Can read users.json (all UUIDs exposed)
  ✓ Can modify configs (backdoor users)
Defense:
  ✓ Keep server patched (unattended-upgrades)
  ✓ SSH key-only auth (no passwords)
  ✓ UFW restrictive rules (only 443 + SSH)
  ✓ Regular backups (restore if compromised)
  ✓ Monitoring (detect anomalies)
Mitigation:
  - If compromised: Assume all keys/UUIDs leaked
  - Action: Rotate keys, regenerate all user UUIDs
  - Notify: All users to update configs
```

**Scenario 5: Insider Threat (Admin User)**
```
Attack: Admin with sudo access goes rogue
Capability:
  ✓ Can read all configs (users.json, keys)
  ✓ Can create backdoor users
  ✓ Can export all client configs
Defense:
  ✓ Limit sudo access (principle of least privilege)
  ✓ Audit logs: /var/log/auth.log (sudo usage)
  ✓ Two-person rule for key operations (future)
Mitigation:
  - Regular audit: Review users.json for unknown users
  - Monitor: Unusual vless-user commands
  - Revoke: Remove rogue admin, change all secrets
```

---

### Security Best Practices

**1. Key Rotation:**
```bash
# When to rotate:
# - Suspected key compromise
# - Every 6-12 months (proactive)
# - After admin turnover

# Process:
1. Generate new keys: xray x25519
2. Update config.json with new private key
3. Regenerate all client configs with new public key
4. Distribute new configs to all users
5. Restart Xray: docker-compose restart xray
6. Archive old keys securely
```

**2. User Audit:**
```bash
# Regular review of users.json
sudo vless-user list

# Check for:
# - Unknown usernames
# - Suspicious creation dates
# - Disabled users that should be removed
```

**3. Log Monitoring:**
```bash
# Check access logs for anomalies
tail -f /opt/vless/logs/access.log

# Look for:
# - Unusual connection patterns
# - Failed authentication attempts (shouldn't happen)
# - Connections from unexpected IPs
```

**4. System Hardening:**
```bash
# Keep system updated
sudo apt update && sudo apt upgrade -y

# Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# SSH hardening
# /etc/ssh/sshd_config:
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes

# Fail2ban (optional)
sudo apt install fail2ban
```

---

## 20. QUICK DEBUG COMMANDS

### System Status Checks

```bash
# Overall status
sudo vless-status

# Container status
docker ps
docker ps -a  # Include stopped containers

# Network status
docker network ls
docker network inspect vless_reality_net

# Port status
sudo ss -tulnp | grep 443
sudo lsof -i :443

# UFW status
sudo ufw status numbered
cat /etc/ufw/after.rules | grep -A10 DOCKER
```

### Log Inspection

```bash
# Xray logs (live)
sudo vless-logs -f

# Xray logs (last 50 lines)
sudo vless-logs -n 50

# Nginx logs
sudo docker logs vless-fake-site

# Specific time range
sudo docker logs --since 1h vless-reality

# Error logs only
sudo docker logs vless-reality 2>&1 | grep -i error
```

### Configuration Validation

```bash
# Validate JSON syntax
jq . /opt/vless/config/config.json
jq . /opt/vless/config/users.json

# Test Xray config
docker run --rm \
  -v /opt/vless/config:/etc/xray \
  teddysun/xray:24.11.30 \
  xray run -test -c /etc/xray/config.json

# Check permissions
ls -la /opt/vless/config/
stat -c '%a %n' /opt/vless/config/*.json
```

### Network Connectivity Tests

```bash
# From host to Internet
curl -I https://www.google.com

# From container to Internet
docker exec vless-reality ping -c 3 8.8.8.8
docker exec vless-reality curl -I https://www.google.com

# Port accessibility from external
# (Run from another machine)
telnet <server-ip> 443
curl -Ik https://<server-ip>:443
```

### Container Inspection

```bash
# Detailed container info
docker inspect vless-reality | jq .

# Container resources
docker stats vless-reality vless-fake-site

# Container processes
docker top vless-reality

# Container user
docker exec vless-reality whoami
docker exec vless-reality id

# Container environment
docker exec vless-reality env
```

### Debugging Failed Containers

```bash
# Why did container stop?
docker ps -a | grep vless
docker logs vless-reality --tail 50

# Manual container start (see live errors)
cd /opt/vless
docker-compose up  # No -d flag

# Restart with clean state
docker-compose down
docker-compose up -d

# Force recreate
docker-compose up -d --force-recreate
```

### User Management Debug

```bash
# Show raw users.json
cat /opt/vless/config/users.json | jq .

# Count users
jq '.users | length' /opt/vless/config/users.json

# Find user by name
jq -r '.users[] | select(.username=="admin")' \
  /opt/vless/config/users.json

# Check UUID uniqueness
jq -r '.users[].uuid' /opt/vless/config/users.json | sort | uniq -d

# Check shortId uniqueness
jq -r '.users[].shortId' /opt/vless/config/users.json | sort | uniq -d
```

### Firewall Debug

```bash
# UFW status
sudo ufw status verbose

# Check Docker chains in iptables
sudo iptables -t filter -L DOCKER-USER -n
sudo iptables -t nat -L POSTROUTING -n

# Test port access
sudo nc -zv localhost 443

# Check which process uses port
sudo lsof -i :443
sudo ss -tulnp | grep :443
```

### Performance Monitoring

```bash
# Container resource usage
docker stats --no-stream vless-reality vless-fake-site

# Disk usage
du -sh /opt/vless/
du -sh /opt/vless/logs/
du -sh /opt/vless/data/

# Check file sizes
ls -lh /opt/vless/config/
ls -lh /opt/vless/logs/

# Count client configs
find /opt/vless/data/clients/ -mindepth 1 -maxdepth 1 -type d | wc -l
```

---

## 21. SUCCESS METRICS

### Installation Performance

```yaml
Target: Installation completes in < 5 minutes

Measurement:
  start: "Time of: sudo ./install.sh"
  end: "Time of: Installation complete message"
  baseline: "Clean Ubuntu 22.04, 10 Mbps internet"
  
Success Criteria:
  excellent: "< 3 minutes"
  good: "3-5 minutes"
  acceptable: "5-7 minutes (slow network)"
  fail: "> 7 minutes (investigate bottleneck)"

Breakdown:
  env_detection: "10-30 seconds"
  docker_install: "1-2 minutes (if not present)"
  parameter_input: "30-60 seconds"
  config_generation: "5-10 seconds"
  container_deploy: "30-60 seconds"
  first_user: "5 seconds"
  total: "< 5 minutes"
```

### User Operations Performance

```yaml
User Creation:
  target: "< 5 seconds"
  measurement: "Time from command to QR display"
  scalability: "Consistent up to 50 users"
  
  Breakdown:
    uuid_generation: "< 0.1 sec"
    json_update: "< 0.5 sec"
    config_update: "< 0.5 sec"
    xray_reload: "< 3 sec"
    qr_generation: "< 1 sec"
  
  Success:
    excellent: "< 3 seconds"
    good: "3-5 seconds"
    acceptable: "5-7 seconds"
    fail: "> 7 seconds"

User Listing:
  target: "< 1 second (50 users)"
  measurement: "Time to display table"
  
User Removal:
  target: "< 3 seconds"
  includes: "Confirmation prompt time excluded"
```

### DPI Resistance

```yaml
Masquerading Effectiveness:
  target: "100% undetectable"
  
  Tests:
    1. Wireshark Analysis:
       - Capture VPN traffic
       - Analyze TLS handshake
       - Verify: Identical to HTTPS to dest
       - Pass: No VLESS-specific signatures
    
    2. Port Scanning:
       - nmap -p 443 -sV <server-ip>
       - Expected: HTTPS service detected
       - Pass: No VPN/proxy indication
    
    3. Browser Access:
       - Open: https://<server-ip>:443
       - Expected: Dest site displayed (proxied)
       - Pass: Looks like normal website
    
    4. Invalid Authentication:
       - Connect with wrong UUID
       - Expected: Fallback to fake-site
       - Pass: No error page, shows dest
  
  Success: All 4 tests pass
```

### Multi-VPN Compatibility

```yaml
Coexistence Test:
  target: "Zero conflicts with other VPNs"
  
  Test Setup:
    - Outline VPN installed (port 8080, subnet 172.18.0.0/16)
    - Install VLESS Reality
  
  Success Criteria:
    - ✓ Different subnets detected
    - ✓ Different ports used
    - ✓ Both VPNs function simultaneously
    - ✓ No network routing conflicts
    - ✓ Both containers access Internet
    - ✓ Clients connect to both VPNs
  
  Weight: 15% of overall success score
```

### Update Data Preservation

```yaml
Target: 100% user data retention

Test Procedure:
  1. Create 10 test users
  2. Note: All UUIDs and shortIds
  3. Run: sudo vless-update
  4. Verify: All 10 users still in users.json
  5. Test: 3 random client configs still work

Success Criteria:
  - ✓ All users present in users.json
  - ✓ UUIDs unchanged
  - ✓ shortIds unchanged
  - ✓ Reality keys unchanged
  - ✓ Client configs valid
  - ✓ VPN connections work
  - ✓ No data loss or corruption

Weight: 10% of overall success score
```

### CLI Intuitiveness

```yaml
Target: 8/10 user rating

Measurement:
  method: "User survey, first-time admin feedback"
  sample: "5 system administrators (varied experience)"
  
  Criteria:
    - Commands self-explanatory
    - Help text useful
    - Error messages actionable
    - Tasks completed without docs
  
  Test Tasks:
    1. Install VLESS from scratch
    2. Add 3 users
    3. Export user config
    4. Remove a user
    5. Check system status
    6. View logs
  
  Rating Scale:
    10: All tasks trivial, zero docs needed
    8-9: Most tasks easy, 1-2 docs lookups
    6-7: Moderate difficulty, several lookups
    < 6: Frustrating, frequent docs needed

Weight: 10% of overall success score
```

### Overall Success Formula

```yaml
Weighted Success Score:
  installation_time: 20%  (< 5 min = 100%)
  user_creation: 25%      (< 5 sec = 100%)
  dpi_resistance: 20%     (all tests = 100%)
  multi_vpn: 15%          (zero conflicts = 100%)
  data_preservation: 10%  (100% retention = 100%)
  cli_usability: 10%      (8/10 rating = 100%)

Overall Target: ≥ 85% weighted score

Calculation Example:
  installation: 4 min = 100% × 0.20 = 20%
  user_ops: 4 sec = 100% × 0.25 = 25%
  dpi: all pass = 100% × 0.20 = 20%
  multi: works = 100% × 0.15 = 15%
  preserve: 100% = 100% × 0.10 = 10%
  cli: 8/10 = 80% × 0.10 = 8%
  
  Total: 20+25+20+15+10+8 = 98%
  Result: EXCEEDS target (85%)
```

---

## 22. USAGE GUIDELINES

### When to Use This Document

**During Development:**
- Check critical requirements (Section 13) before implementation
- Follow file structure (Section 12) for consistency
- Use standard formats (Section 6) for outputs
- Validate against NFRs (Section 14)

**During Testing:**
- Use testing checklist (Section 16) for comprehensive coverage
- Measure against success metrics (Section 21)
- Follow debug commands (Section 20) for troubleshooting

**During Deployment:**
- Verify system parameters (Section 11) match target environment
- Check common failure points (Section 15) if issues arise
- Review security threat model (Section 19) for hardening

**During Maintenance:**
- Reference technical details (Section 17) for operations
- Use quick debug commands (Section 20) for diagnostics
- Follow update procedures (Section 16) for data preservation

### How to Apply Workflow Rules

**1. When Starting Any Task:**
```
Read: Part I (Universal Workflow Rules)
Check: Which rules apply to current task
Plan: Entry conditions, thinking requirements, checkpoints
Execute: Follow sequential order, use thinking blocks
Validate: Check exit conditions, verify outputs
```

**2. Before Each Phase:**
```
1. Check entry_conditions (P6)
2. Write thinking block (P2)
3. Plan actions in order
4. Identify blocking actions (P7)
5. Note required outputs (P3)
```

**3. After Each Action:**
```
1. Verify mandatory_output produced (P3)
2. Check exit_conditions (P4)
3. Document decisions (P12)
4. Handle errors properly (P9)
```

**4. At Phase Boundaries:**
```
1. Complete checkpoint verification (P5)
2. Output checkpoint status
3. Wait for approval if required (P10)
4. Do not proceed if checkpoint fails
```

**5. When Uncertain:**
```
1. STOP immediately
2. Use ASK template (P11)
3. Do not make assumptions
4. Wait for clarification
```

### Document Maintenance

**When to Update:**
- New requirements discovered during implementation
- Performance metrics change based on real usage
- Security threats identified through testing
- User feedback reveals usability issues
- Technology versions updated (Docker, Xray, etc.)

**How to Update:**
```
1. Locate relevant section
2. Update content
3. Increment version number
4. Update "Last Updated" date
5. Add entry to version history
6. Notify team of changes
```

**Version History:**
```
v2.0 - 2025-10-02: Unified document (workflow + project)
v1.1 - 2025-10-02: Added sudo accessibility
v1.0 - 2025-10-01: Initial project memory
```

---

**END OF UNIFIED PROJECT MEMORY**

This document serves as the single source of truth for both workflow execution rules and project-specific technical documentation for the VLESS + Reality VPN Server project.
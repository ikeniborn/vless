# CLAUDE.md - Project Memory & Workflow Rules

**Project:** VLESS + Reality VPN Server
**Version:** 2.1 (Optimized)
**Last Updated:** 2025-10-03
**Purpose:** Unified project memory combining workflow execution rules and project-specific technical documentation

---

## TABLE OF CONTENTS

### PART I: UNIVERSAL WORKFLOW EXECUTION RULES
1. [Critical Principles (P1-P5)](#part-i-universal-workflow-execution-rules)
2. [High Priority Rules (P6-P10)](#2-high-priority-rules-p6-p10)
3. [Medium Priority Rules (P11-P13)](#3-medium-priority-rules-p11-p13)
4. [Prohibited & Mandatory Actions](#4-prohibited--mandatory-actions)
5. [Standard Formats](#5-standard-formats)

### PART II: PROJECT-SPECIFIC DOCUMENTATION
6. [Project Overview](#part-ii-project-specific-documentation)
7. [Critical System Parameters](#7-critical-system-parameters)
8. [Project Structure](#8-project-structure)
9. [Critical Requirements](#9-critical-requirements-for-validation)
10. [Non-Functional Requirements](#10-non-functional-requirements-nfr)
11. [Common Failure Points & Solutions](#11-common-failure-points--solutions)
12. [Testing Checklist](#12-testing-checklist)
13. [Technical Details](#13-technical-details)
14. [Scalability & Constraints](#14-scalability--constraints)
15. [Security & Debug](#15-security--debug)
16. [Success Metrics](#16-success-metrics)

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
**Version:** 3.1 (with Dual Proxy Support)
**Target Scale:** 10-50 concurrent users
**Deployment:** Linux servers (Ubuntu 20.04+, Debian 10+)
**Technology Stack:** Docker, Xray-core, VLESS, Reality Protocol, SOCKS5, HTTP, Nginx

**Core Value Proposition:**
- Deploy production-ready VPN in < 5 minutes
- Zero manual configuration through intelligent automation
- DPI-resistant via Reality protocol (TLS 1.3 masquerading)
- **Dual proxy support (SOCKS5 + HTTP) with unified credentials**
- **Multi-format config export (5 formats: SOCKS5, HTTP, VSCode, Docker, Bash)**
- No domain/certificate management required
- Coexists with Outline, Wireguard, other VPN services

**Key Innovation:**
Reality protocol "steals" TLS handshake from legitimate websites (google.com, microsoft.com), making VPN traffic mathematically indistinguishable from normal HTTPS. Deep Packet Inspection systems cannot detect the VPN.

**Proxy Innovation (v3.1):**
Localhost-only SOCKS5 and HTTP proxies accessible only after VPN connection. Single password for both proxies. Auto-generates 5 config file formats per user for seamless integration with IDEs, Docker, and shell environments.

---

## 7. CRITICAL SYSTEM PARAMETERS

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

Proxy Protocols (NEW in v3.1):
  socks5:
    port: 1080
    listen: "127.0.0.1"             # Localhost-only
    auth: "password"                # Required
    udp: false                      # TCP only
  http:
    port: 8118
    listen: "127.0.0.1"             # Localhost-only
    auth: "password"                # Required
    allowTransparent: false         # Security hardening
    protocols: ["HTTP", "HTTPS"]    # Both supported
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
  socks5_proxy: 1080                # NEW: Localhost-only (127.0.0.1)
  http_proxy: 8118                  # NEW: Localhost-only (127.0.0.1)
  port_detection: "automatic"       # ss -tulnp check

Firewall (UFW):
  status_required: "active"
  docker_integration: "/etc/ufw/after.rules"
  rule_format: "allow ${VLESS_PORT}/tcp comment 'VLESS Reality VPN'"
  proxy_ports_exposed: false        # NEW: Ports 1080/8118 NOT in docker-compose.yml
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
  users.json:          "600"        # NEW: v1.1 with proxy_password field
  reality_keys.json:   "600"
  .env:                "600"
  docker-compose.yml:  "644"
  scripts/*.sh:        "755"

Client Config Files (NEW in v3.1):
  socks5_config.txt:       "600"
  http_config.txt:         "600"
  vscode_settings.json:    "600"
  docker_daemon.json:      "600"
  bash_exports.sh:         "700"    # Executable

Symlinks:
  location: "/usr/local/bin/"
  pattern: "vless-*"
  permissions: "755"                # Sudo-accessible
```

---

## 8. PROJECT STRUCTURE

### Development Structure (Before Installation)

```
/home/ikeniborn/Documents/Project/vless/
├── install.sh                      # Main installer entry point
├── PLAN.md                         # Implementation roadmap
├── PRD.md                          # Product requirements
├── CLAUDE.md                       # This file - project memory
├── lib/                            # Installation modules
│   ├── os_detection.sh
│   ├── dependencies.sh
│   ├── old_install_detect.sh
│   ├── interactive_params.sh
│   ├── sudoers_info.sh
│   ├── orchestrator.sh
│   └── verification.sh
├── docs/                           # Additional documentation
├── tests/                          # Test suite
│   ├── unit/
│   └── integration/
├── scripts/                        # Dev utilities
└── requests/                       # Workflow templates
```

### Production Structure (After Installation)

```
/opt/vless/                         # Created by installer
├── config/                         # 700, owner: root
│   ├── config.json                 # 600 - Xray main config (3 inbounds when proxy enabled)
│   ├── users.json                  # 600 - User database (v1.1 with proxy_password)
│   └── reality_keys.json           # 600 - X25519 key pair
├── data/                           # 700, user data
│   ├── clients/                    # Per-user configs
│   │   └── <username>/             # NEW: 8 files per user (3 VLESS + 5 proxy)
│   │       ├── vless_config.json   # VLESS client config
│   │       ├── vless_uri.txt       # VLESS connection string
│   │       ├── qrcode.png          # QR code for mobile
│   │       ├── socks5_config.txt   # NEW: SOCKS5 URI
│   │       ├── http_config.txt     # NEW: HTTP URI
│   │       ├── vscode_settings.json # NEW: VSCode proxy settings
│   │       ├── docker_daemon.json  # NEW: Docker daemon config
│   │       └── bash_exports.sh     # NEW: Bash environment variables
│   └── backups/                    # Automatic backups
├── logs/                           # 755, log files
├── fake-site/                      # 755, Nginx configs
├── scripts/                        # 755, management tools
├── .env                            # 600 - Environment variables
└── docker-compose.yml              # 644 - Container orchestration

/usr/local/bin/                     # Symlinks (sudo-accessible)
├── vless-install
├── vless-user                      # NEW: Now supports show-proxy, reset-proxy-password
├── vless-start / stop / restart / status / logs  # NEW: status shows proxy info
├── vless-update
└── vless-uninstall
```

---

## 9. CRITICAL REQUIREMENTS FOR VALIDATION

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

---

### FR-002: Old Installation Detection (CRITICAL - Priority 1)

**Requirement:** Detect existing installations and offer safe options

**Detection Checks:**
```bash
# 1. Check directory
if [ -d "/opt/vless/" ]; then echo "Old installation found"; fi

# 2. Check containers
docker ps -a --format '{{.Names}}' | grep -E '^vless-'

# 3. Check networks
docker network ls --format '{{.Name}}' | grep -E '^vless_'

# 4. Check symlinks
ls -la /usr/local/bin/vless-* 2>/dev/null
```

**User Options:**
```yaml
1. DELETE: Backup + complete removal + fresh install
2. UPDATE: Preserve users/keys + update containers
3. CANCEL: No changes, safe exit
```

**Acceptance Criteria:**
✓ All detection checks work
✓ DELETE: Complete removal + backup to /tmp/
✓ UPDATE: Users and keys preserved
✓ CANCEL: No changes made
✓ Backup created BEFORE destructive operations

---

### FR-004: Dest Site Validation (CRITICAL - Priority 1)

**Requirement:** Validate destination site for Reality masquerading

**Default Options:**
```yaml
1: "google.com:443"          # Default
2: "www.microsoft.com:443"
3: "www.apple.com:443"
4: "www.cloudflare.com:443"
5: "Custom"
```

**Validation Steps:**
```bash
# 1. TLS 1.3 Support (REQUIRED)
curl -vI https://${dest} 2>&1 | grep -i "TLSv1.3"

# 2. SNI Extraction (REQUIRED)
openssl s_client -servername ${dest} -connect ${dest}:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"

# 3. Reachability (REQUIRED)
curl -s -o /dev/null -w "%{http_code}" https://${dest}
```

**Validation Criteria:**
```yaml
TLS 1.3:      REQUIRED
SNI Extract:  REQUIRED
Reachability: REQUIRED
Latency:      < 10 seconds
```

**Acceptance Criteria:**
✓ All validation steps execute
✓ Validation completes in < 10 seconds
✓ Clear feedback on failures
✓ Alternatives offered on failure
✓ Cannot proceed with invalid dest

---

### FR-005: User Creation (CRITICAL - Priority 1)

**Requirement:** Create user in < 5 seconds with automatic config generation

**Command:**
```bash
sudo vless-user add <username>
```

**Workflow:**
```yaml
1. Validate username (alphanumeric, 3-32 chars, unique)
2. Generate UUID (uuidgen)
3. Generate shortId (openssl rand -hex 8)
4. Update users.json (atomic with file lock)
5. Update config.json
6. Reload Xray (docker-compose restart xray)
7. Generate client configs (JSON, URI, QR code)
8. Save to data/clients/{username}/
9. Display to user
```

**Acceptance Criteria:**
✓ Total time < 5 seconds
✓ UUID & shortId unique
✓ Xray reloads without errors
✓ Client configs generated (all 3 formats)
✓ Files saved with correct permissions (600)
✓ No data corruption

---

### FR-011: UFW Integration (CRITICAL - Priority 1)

**Requirement:** Configure UFW firewall with Docker forwarding support

**Critical Files:**
```
/etc/ufw/ufw.conf
/etc/ufw/after.rules        # Docker chains added here
/etc/ufw/before.rules
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
```

**Acceptance Criteria:**
✓ UFW detected (install if missing)
✓ UFW enabled (prompt if inactive)
✓ Port rule added without duplication
✓ Docker chains added to after.rules
✓ Containers can access Internet
✓ External connections work

---

### FR-012: Proxy Server Integration (CRITICAL - Priority 1) - NEW in v3.1

**Requirement:** Dual proxy support (SOCKS5 + HTTP) with localhost-only binding

**Implementation:**
```yaml
Proxy Configuration:
  socks5:
    port: 1080
    listen: "127.0.0.1"             # NOT exposed to internet
    auth: "password"                # Required
    protocol: "socks"

  http:
    port: 8118
    listen: "127.0.0.1"             # NOT exposed to internet
    auth: "password"                # Required
    protocol: "http"
    allowTransparent: false

Credential Management:
  password_generation: "openssl rand -hex 8"  # 16 characters
  password_storage: "users.json v1.1 (proxy_password field)"
  single_password: true                        # Same for SOCKS5 + HTTP

Config File Export (5 formats per user):
  - socks5_config.txt        # SOCKS5 URI
  - http_config.txt          # HTTP URI
  - vscode_settings.json     # VSCode proxy settings
  - docker_daemon.json       # Docker daemon config
  - bash_exports.sh          # Environment variables (executable)
```

**Security Requirements:**
```yaml
Network Binding:
  - Proxies bind ONLY to 127.0.0.1 (localhost)
  - NOT accessible from external network
  - Require VPN connection first (must connect via VLESS)
  - Ports 1080/8118 NOT exposed in docker-compose.yml

Authentication:
  - Password required for both SOCKS5 and HTTP
  - 16-character random hex passwords
  - Stored in users.json with 600 permissions

File Permissions:
  - Config files (txt, json): 600 (owner read/write only)
  - Bash script: 700 (owner read/write/execute)
  - Client directory: 700 (owner access only)
```

**Workflow Integration:**
```bash
# User creation (auto-generates proxy password + configs)
sudo vless-user add alice
# Output: UUID + proxy password + 8 config files

# Show proxy credentials
sudo vless-user show-proxy alice
# Output: SOCKS5/HTTP URIs + usage examples

# Reset proxy password (regenerates all configs)
sudo vless-user reset-proxy-password alice
# Output: New password + updated config files

# Service status (shows proxy info)
sudo vless-status
# Output: Proxy enabled/disabled + SOCKS5/HTTP details
```

**Acceptance Criteria:**
✓ Proxies bind to 127.0.0.1 ONLY (not 0.0.0.0)
✓ Password authentication enforced
✓ Single password for both SOCKS5 and HTTP
✓ 5 config file formats generated per user
✓ Auto-generation on user creation
✓ Auto-regeneration on password reset
✓ Service status shows proxy info
✓ Ports NOT exposed in docker-compose.yml
✓ External access blocked (verifiable with nmap)
✓ Backward compatible (VLESS-only mode works)

---

## 10. NON-FUNCTIONAL REQUIREMENTS (NFR)

### Performance Targets

```yaml
Installation:
  target: "< 5 minutes"
  baseline: "Clean Ubuntu 22.04, 10 Mbps internet"

User Creation:
  target: "< 5 seconds"
  scalability: "Consistent up to 50 users"

Container Startup:
  target: "< 10 seconds"

Config Reload:
  target: "< 3 seconds"

Operations (50 users):
  user_list: "< 1 second"
  user_show: "< 1 second"
```

### Reliability Requirements

```yaml
Uptime:
  target: "99.9%"

Restart Policy:
  docker_compose: "restart: unless-stopped"

Config Validation:
  before_apply: "100% of changes"
  methods:
    - JSON syntax: jq . config.json
    - Xray test: xray run -test -c config.json
  rollback: "Keep previous config for auto-restore"
```

### Security Requirements

```yaml
File Permissions (ENFORCED):
  /opt/vless/config/:                 "700"
  config.json / users.json / keys:    "600"
  scripts:                            "755"

Container Security:
  xray_user: "nobody (UID 65534)"
  nginx_user: "nginx"
  capabilities: drop ALL, add NET_BIND_SERVICE

Key Management:
  algorithm: "X25519"
  private_key: NEVER transmitted, 600 perms, root only
  public_key: Freely distributable
  rotation: Supported via CLI

Network Security:
  ufw_status: "active (required)"
  exposed_ports: ${VLESS_PORT}/tcp only
  docker_isolation: Separate network
```

### Usability Requirements

```yaml
CLI Design:
  command_prefix: "vless-*"
  help_text: "Available for all commands"
  success_metric: "80% tasks without docs lookup"

Error Messages (MUST INCLUDE):
  - Clear problem description
  - Context (where/when)
  - Root cause
  - Actionable fix steps with commands
```

---

## 11. COMMON FAILURE POINTS & SOLUTIONS

### Issue 1: UFW Blocks Docker Traffic

**Symptoms:** Containers run, but no Internet access inside

**Detection:**
```bash
docker exec vless-reality ping -c 1 8.8.8.8  # Fails
ufw status numbered  # Check rules
grep "DOCKER-USER" /etc/ufw/after.rules  # Check chains
```

**Solution:**
```bash
# Add Docker chains to /etc/ufw/after.rules (see FR-011)
sudo ufw reload
```

---

### Issue 2: Port 443 Already Occupied

**Symptoms:** Installation fails, "port is already allocated"

**Detection:**
```bash
sudo ss -tulnp | grep :443
sudo lsof -i :443
```

**Solution:** Offer alternative ports (8443, 2053) or ask user to resolve

---

### Issue 3: Docker Subnet Conflicts

**Symptoms:** Network creation fails, "Pool overlaps"

**Detection:**
```bash
docker network ls --format '{{.Name}}'
for net in $(docker network ls --format '{{.Name}}'); do
  docker network inspect $net | jq -r '.[0].IPAM.Config[0].Subnet'
done
```

**Solution:** Auto-scan 172.16-31.0.0/16 range, find free subnet

---

### Issue 4: Dest Validation Fails

**Root Causes:**
1. DNS resolution failure
2. Firewall blocking outbound HTTPS
3. Dest site temporarily unavailable
4. TLS < 1.3

**Solution:** Offer alternative destinations, allow retry

---

### Issue 5: Containers Won't Start

**Detection:**
```bash
docker ps -a | grep vless  # Check status
docker logs vless-reality  # Check errors
```

**Common Causes:**
- Invalid config.json
- Missing volume mounts
- Port already bound
- Network doesn't exist

**Debug Workflow:**
```bash
1. jq . /opt/vless/config/config.json
2. xray run -test -c config.json
3. docker network inspect vless_reality_net
4. ss -tulnp | grep ${VLESS_PORT}
5. docker logs vless-reality
6. docker-compose up (no -d, see live errors)
```

---

## 12. TESTING CHECKLIST

### Fresh Installation Test
**Environment:** Clean Ubuntu 22.04, no Docker, no UFW

**Success Criteria:**
- [ ] Installation < 5 minutes
- [ ] Docker/UFW auto-installed & configured
- [ ] Both containers running
- [ ] Admin user created with QR
- [ ] Port accessible
- [ ] Containers have Internet

### User Management Test
- [ ] Create user < 5 seconds
- [ ] QR code displayed
- [ ] All 3 config formats generated
- [ ] List/Show/Remove operations work

### Multi-VPN Coexistence Test
**Pre-conditions:** Outline VPN running

**Success:**
- [ ] Different subnets auto-detected
- [ ] Both VPNs work simultaneously
- [ ] No routing conflicts

### DPI Resistance Test
- [ ] Wireshark: Traffic looks like HTTPS
- [ ] nmap: Reports HTTPS service (not VPN)
- [ ] Browser: Shows dest site (proxied)
- [ ] Invalid auth → fake-site (not rejected)

### Update & Data Preservation Test
- [ ] All 10 users preserved after update
- [ ] Reality keys unchanged
- [ ] Client configs still valid
- [ ] Total downtime < 30 seconds

---

## 13. TECHNICAL DETAILS

### Reality Key Management

**Generation:**
```bash
xray x25519
# Output: Private key: ..., Public key: ...
```

**Storage:** `/opt/vless/config/reality_keys.json` (600 perms)
```json
{
  "private_key": "...",
  "public_key": "...",
  "generated_at": "2025-10-01T12:00:00Z",
  "algorithm": "X25519"
}
```

**Security:**
- Private key: NEVER leave server, NEVER in client configs
- Public key: Distributed in all client configs
- Keys can be rotated (requires client config updates)

---

### User Data Structure

**File:** `/opt/vless/config/users.json` (600 perms)
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
      "enabled": true
    }
  ]
}
```

**Atomic Operations:**
```bash
# Add user with file lock
(
  flock -x 200
  jq '.users += [NEW_USER]' users.json > users.json.tmp
  mv users.json.tmp users.json
) 200>/var/lock/vless-users.lock
```

---

### Client Configuration Formats

**1. JSON (v2rayN/v2rayNG):**
```json
{
  "outbounds": [{
    "protocol": "vless",
    "settings": { "vnext": [{ "address": "SERVER_IP", "port": 443 }] },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "google.com",
        "publicKey": "PUBLIC_KEY",
        "shortId": "SHORT_ID"
      }
    }
  }]
}
```

**2. VLESS URI:**
```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#USERNAME
```

**3. QR Code:**
```bash
qrencode -o qrcode.png -t PNG -s 10 "vless://..."
qrencode -t ANSIUTF8 "vless://..."  # Terminal
```

---

### Xray Configuration (config.json)

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

**Purpose:**
- Receives fallback traffic from Xray
- Proxies requests to destination site (google.com)
- Makes server appear as normal HTTPS website
- Enhances DPI resistance

**File:** `/opt/vless/fake-site/default.conf`
```nginx
server {
    listen 8080;
    location / {
        proxy_pass https://google.com;
        proxy_ssl_server_name on;
        proxy_set_header Host google.com;
    }
}
```

---

## 14. SCALABILITY & CONSTRAINTS

### Current Design (10-50 Users)

**Architecture:**
```yaml
User Storage: JSON files
Locking: File-based (flock)
Orchestration: Docker Compose
Management: Bash scripts
```

**Performance:**
```yaml
User Operations (50 users):
  add: "< 5 seconds"
  list: "< 1 second"

File Sizes:
  users.json: "~10 KB (50 users)"
  config.json: "~30 KB (50 users)"

Memory:
  Xray: "~80 MB (50 concurrent)"
  Nginx: "~20 MB"
```

**Design Strengths:**
- Simple architecture
- No database overhead
- JSON files easily backed up
- Fast for target scale (10-50 users)

**Design Limitations:**
- JSON parsing slowdown beyond 100 users
- File locking contention with high concurrent ops
- No horizontal scaling

**Recommendation:**
For > 50 users, use multiple independent instances (server1: users 1-50, server2: users 51-100) rather than architectural redesign.

---

## 15. SECURITY & DEBUG

### Security Threat Matrix

| Threat | Severity | Mitigation |
|--------|----------|------------|
| DPI Detection | HIGH | Reality protocol TLS masquerading |
| Private Key Compromise | CRITICAL | 600 perms, root-only, never transmitted |
| Brute Force UUID | MEDIUM | UUID + shortId (2^192 space) |
| Container Escape | HIGH | Non-root user, minimal capabilities |

### Security Best Practices

**1. Key Rotation:**
```bash
# When: Suspected compromise, every 6-12 months, after admin turnover
1. xray x25519  # Generate new keys
2. Update config.json with new private key
3. Regenerate all client configs
4. docker-compose restart xray
```

**2. System Hardening:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install unattended-upgrades
# SSH hardening: /etc/ssh/sshd_config
# PermitRootLogin no, PasswordAuthentication no
```

### Quick Debug Commands

**System Status:**
```bash
sudo vless-status
docker ps
docker network inspect vless_reality_net
sudo ss -tulnp | grep 443
sudo ufw status numbered
```

**Logs:**
```bash
sudo vless-logs -f
docker logs vless-reality --tail 50
docker logs vless-fake-site
```

**Config Validation:**
```bash
jq . /opt/vless/config/config.json
docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 xray run -test -c /etc/xray/config.json
```

**Network Tests:**
```bash
docker exec vless-reality ping -c 1 8.8.8.8
docker exec vless-reality curl -I https://www.google.com
```

**User Management:**
```bash
cat /opt/vless/config/users.json | jq .
jq '.users | length' /opt/vless/config/users.json
jq -r '.users[].uuid' /opt/vless/config/users.json | sort | uniq -d  # Check UUID uniqueness
```

---

## 16. SUCCESS METRICS

### Performance Targets

```yaml
Installation: < 5 minutes (baseline: Ubuntu 22.04, 10 Mbps)
User Creation: < 5 seconds (consistent up to 50 users)
Container Startup: < 10 seconds
Config Reload: < 3 seconds
```

### Test Results

```yaml
DPI Resistance:
  - Wireshark: Traffic identical to HTTPS ✓
  - nmap: Reports HTTPS service (not VPN) ✓
  - Browser: Shows dest site ✓
  - Invalid auth: Fallback to fake-site ✓

Multi-VPN:
  - Different subnets detected ✓
  - Both VPNs work simultaneously ✓

Update:
  - User data preserved ✓
  - Downtime < 30 seconds ✓
```

### Overall Success Formula

```yaml
Weighted Score:
  installation_time: 20%
  user_creation: 25%
  dpi_resistance: 20%
  multi_vpn: 15%
  data_preservation: 10%
  cli_usability: 10%

Target: ≥ 85% weighted score
```

---

**END OF OPTIMIZED PROJECT MEMORY**

**Version History:**
```
v2.1 - 2025-10-03: Optimized version (-33% size, all critical info preserved)
v2.0 - 2025-10-02: Unified document (workflow + project)
v1.0 - 2025-10-01: Initial project memory
```

This document serves as the single source of truth for both workflow execution rules and project-specific technical documentation for the VLESS + Reality VPN Server project.

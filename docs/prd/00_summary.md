# PRD v4.3 - Executive Summary & Navigation

**VLESS + Reality VPN Server: Product Requirements Document**

**Version:** 4.3 (HAProxy Unified Architecture)
**Status:** ✅ 100% Implemented
**Last Updated:** 2025-10-18

---

## Быстрая навигация

| Раздел | Описание | Ссылка |
|--------|----------|--------|
| **01. Обзор** | Document Control, Executive Summary, Product Overview | [→ Открыть](01_overview.md) |
| **02. Функциональные требования** | FR-HAPROXY-001 (v4.3), FR-REVERSE-PROXY-001 (v4.3), FR-TLS-002, FR-CERT-001/002, FR-IP-001, FR-CONFIG-001, FR-VSCODE-001, FR-GIT-001, FR-PUBLIC-001, FR-PASSWORD-001, FR-FAIL2BAN-001, FR-UFW-001, FR-MIGRATION-001 | [→ Открыть](02_functional_requirements.md) |
| **03. NFR** | NFR-SEC-001, NFR-OPS-001, NFR-PERF-001, NFR-COMPAT-001, NFR-USABILITY-001, NFR-RELIABILITY-001, NFR-RPROXY-002 (v4.3) | [→ Открыть](03_nfr.md) |
| **04. Архитектура** | Section 4.7 HAProxy Unified Architecture (v4.3), Network Architecture, Data Flow, Certificate Lifecycle, File Structure | [→ Открыть](04_architecture.md) |
| **05. Тестирование** | v4.3 Test Suite (automated), TLS Integration Tests, Client Integration Tests, Security Tests, HAProxy Tests | [→ Открыть](05_testing.md) |
| **06. Приложения** | Implementation Details, Security Risk, Success Metrics, Dependencies, Rollback, References | [→ Открыть](06_appendix.md) |

---

## Ключевые характеристики v4.3

### Текущая версия (Production-Ready)

**Статус реализации:** ✅ **100% COMPLETE**

| Компонент | Версия | Статус |
|-----------|--------|--------|
| **VLESS Reality VPN** | v4.3 | ✅ Stable |
| **HAProxy Unified Architecture** | v4.3 | ✅ Production (replaces stunnel) |
| **Subdomain-Based Reverse Proxy** | v4.3 | ✅ https://domain (NO port!) |
| **SNI Routing (HAProxy)** | v4.3 | ✅ TLS passthrough |
| **Dual Proxy (SOCKS5 + HTTP)** | v4.1+ | ✅ Complete |
| **Heredoc Config Generation** | v4.1+ | ✅ Implemented |
| **Port Range 9443-9452 (localhost)** | v4.3 | ✅ Nginx reverse proxy backends |
| **fail2ban Integration (HAProxy)** | v4.3 | ✅ Multi-layer protection |
| **IP Whitelisting** | v3.6+ | ✅ Server-level + UFW |
| **Let's Encrypt Auto-Renewal** | v3.3+ | ✅ Automated |
| **v4.3 Test Suite (automated)** | v4.3 | ✅ 3 test cases, DEV_MODE support |

---

## Архитектура (v4.3)

### Компоненты системы

```
┌─────────────────────────────────────────────────────────┐
│                        CLIENT                           │
│  VLESS Reality VPN (port 443)                          │
│  Encrypted Proxy: socks5s://1080, https://8118        │
│  Reverse Proxy: https://subdomain.example.com (NO port!)│
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ TLS 1.3 Encrypted
                      ↓
┌─────────────────────────────────────────────────────────┐
│                   UFW FIREWALL                          │
│  - Port 443 (ALLOW) - VLESS + Reverse Proxy            │
│  - Ports 1080/8118 (LIMIT: 10 conn/min) - Proxies      │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────┐
│               DOCKER CONTAINERS                         │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ HAProxy (v4.3 UNIFIED)                           │ │
│  │  - Frontend 443: SNI routing (TLS passthrough)   │ │
│  │    • VLESS Reality → Xray:8443                  │ │
│  │    • Subdomain routing → Nginx:9443-9452        │ │
│  │  - Frontend 1080: SOCKS5 TLS termination        │ │
│  │    • Forwards to: Xray:10800 (plaintext)        │ │
│  │  - Frontend 8118: HTTP TLS termination          │ │
│  │    • Forwards to: Xray:18118 (plaintext)        │ │
│  │  - Uses combined.pem (fullchain + privkey)      │ │
│  │  - fail2ban protection (HAProxy filter)         │ │
│  └──────────────────┬───────────────────────────────┘ │
│                     │                                  │
│  ┌──────────────────▼───────────────────────────────┐ │
│  │ Xray-core                                        │ │
│  │  - VLESS Reality (port 8443, internal)          │ │
│  │  - SOCKS5 plaintext (localhost:10800)           │ │
│  │  - HTTP plaintext (localhost:18118)             │ │
│  │  - Password authentication (32-char)            │ │
│  │  - IP whitelisting via routing rules            │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Nginx Reverse Proxy (v4.3)                       │ │
│  │  - Binds to localhost:9443-9452 (10 ports)      │ │
│  │  - Proxies to target sites via Xray             │ │
│  │  - fail2ban protection (nginx filter)           │ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Ключевые изменения по версиям

| Версия | Дата | Основное изменение | Impact |
|--------|------|-------------------|--------|
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture | 1 контейнер вместо 2 (stunnel REMOVED), subdomain-based reverse proxy (https://domain, NO port!), ports 9443-9452 |
| **v4.2** | 2025-10-17 | Reverse proxy planning | Промежуточная версия (см. v4.3 для реализации) |
| **v4.1** | 2025-10-07 | Heredoc config generation + URI fix | Упрощение (удален envsubst), исправлен баг URI |
| **v4.0** | 2025-10-06 | stunnel TLS termination | Разделение TLS и proxy логики (deprecated в v4.3) |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | Миграция с per-user (протокольное ограничение) |
| **v3.3** | 2025-10-05 | Mandatory TLS (Let's Encrypt) | Устранена критическая уязвимость v3.2 |
| **v3.1** | 2025-10-03 | Dual proxy (localhost-only) | Базовая proxy функциональность |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | Исходная VPN система |

---

## Функциональные требования (краткий обзор)

### Критические (CRITICAL)

1. **FR-HAPROXY-001** (v4.3) - HAProxy Unified Architecture
   - Единый HAProxy контейнер для ALL TLS и routing
   - 3 frontends: SNI routing (443), SOCKS5 TLS (1080), HTTP TLS (8118)
   - SNI routing без TLS decryption (TLS passthrough)
   - combined.pem certificates (fullchain + privkey)
   - Graceful reload (haproxy -sf) для zero-downtime

2. **FR-REVERSE-PROXY-001** (v4.3) - Subdomain-Based Reverse Proxy
   - HAProxy SNI routing → Nginx backends (ports 9443-9452, localhost-only)
   - Subdomain access: https://subdomain.example.com (NO port number!)
   - Xray routing для proxy traffic to target sites
   - Let's Encrypt сертификаты (combined.pem format)
   - Поддержка до 10 доменов (ports 9443-9452)
   - fail2ban protection (nginx + HAProxy filters)
   - Dynamic ACL management (sed-based config updates)

3. **FR-CERT-001** - Автоматическое получение Let's Encrypt сертификатов
   - Интеграция с certbot
   - ACME HTTP-01 challenge (временное открытие порта 80)
   - DNS валидация перед получением
   - combined.pem generation (для HAProxy v4.3)

4. **FR-CERT-002** - Автоматическое обновление сертификатов
   - Cron job (запуск 2 раза в день)
   - Deploy hook для перезапуска HAProxy (graceful reload)
   - Downtime < 5 секунд

5. **FR-IP-001** (v3.6) - Server-Level IP-Based Access Control
   - proxy_allowed_ips.json (server-level whitelist)
   - Xray routing rules без поля `user` (протокольное ограничение)
   - 5 CLI команд для управления

6. **FR-CONFIG-001** (v4.1) - Генерация клиентских конфигураций с TLS URIs
   - ✅ Исправлено: `socks5s://` (TLS-enabled SOCKS5)
   - ✅ Исправлено: `https://` (TLS-enabled HTTP)
   - 6 форматов файлов на пользователя

### Высокий приоритет (HIGH)

7. **FR-VSCODE-001** - VSCode Integration через HTTPS Proxy
8. **FR-GIT-001** - Git Integration через SOCKS5s Proxy
9. **FR-TLS-002** - TLS Encryption для HTTP Inbound
10. **FR-PUBLIC-001** - Public Proxy Binding (0.0.0.0)
11. **FR-PASSWORD-001** - 32-character passwords (brute-force protection)
12. **FR-FAIL2BAN-001** - Fail2ban Integration (5 retries → ban, HAProxy + Nginx filters в v4.3)
13. **FR-UFW-001** - UFW Firewall Rules с rate limiting
14. **FR-MIGRATION-001** - Migration Path v3.2 → v3.3+ → v4.3

**Детали:** [→ Функциональные требования](02_functional_requirements.md)

---

## Non-Functional Requirements (NFR)

| Требование | Метрика | Статус |
|------------|---------|--------|
| **NFR-SEC-001** | 100% публичных прокси с TLS | ✅ Enforced |
| **NFR-OPS-001** | 0 manual steps для cert renewal | ✅ Automated |
| **NFR-PERF-001** | TLS overhead < 2ms | ✅ Acceptable |
| **NFR-COMPAT-001** | VSCode 1.60+, Git 2.0+ | ✅ Verified |
| **NFR-USABILITY-001** | Installation < 7 минут | ✅ Tested |
| **NFR-RELIABILITY-001** | Cert renewal success > 99% | ✅ Monitored |

**Детали:** [→ Non-Functional Requirements](03_nfr.md)

---

## Технические характеристики

### Performance Targets (v4.3)

- **Installation Time:** < 7 минут (clean Ubuntu 22.04, 10 Mbps)
- **User Creation:** < 5 секунд (consistent up to 50 users)
- **Container Startup:** < 10 секунд
- **Config Reload:** < 3 секунд (HAProxy graceful reload)
- **Cert Renewal Downtime:** < 5 секунд
- **Reverse Proxy Setup:** < 2 минуты (subdomain-based, NO port!)

### Security Posture (v4.3)

- ✅ **TLS 1.3 Encryption** (HAProxy termination, v4.3)
- ✅ **Let's Encrypt Certificates** (auto-renewal, combined.pem format)
- ✅ **32-Character Passwords** (brute-force resistant)
- ✅ **fail2ban Protection** (HAProxy + Nginx filters, 5 attempts → 1 hour ban)
- ✅ **UFW Rate Limiting** (10 conn/min per IP)
- ✅ **DPI Resistance** (Reality protocol + SNI routing)
- ✅ **IP Whitelisting** (server-level + optional UFW)
- ✅ **SNI Routing Security** (NO TLS decryption for reverse proxy)

### Scalability

- **Target Scale:** 10-50 concurrent users
- **User Storage:** JSON files (fast for target scale)
- **File Locking:** flock-based (sufficient for < 100 users)
- **Horizontal Scaling:** Multiple independent instances for > 50 users

**Детали:** [→ Архитектура](04_architecture.md)

---

## Testing Coverage

### Категории тестов

1. **TLS Integration Tests** (5 тестов)
   - TLS handshake validation (SOCKS5, HTTP)
   - Certificate validity check
   - Auto-renewal dry-run
   - Deploy hook execution

2. **Client Integration Tests** (2 теста)
   - VSCode extension via HTTPS proxy
   - Git clone via SOCKS5s proxy

3. **Security Tests** (3 теста)
   - Wireshark traffic capture (encrypted stream verification)
   - Nmap service detection (TLS on ports 1080/8118)
   - Config validation (no plain proxy endpoints)

4. **Backward Compatibility Tests** (2 теста)
   - Old v3.2 configs must fail (plain proxy rejected)
   - New v3.3+ configs must work (TLS accepted)

**Детали:** [→ Тестирование](05_testing.md)

---

## Зависимости

### Core Stack (v4.3)

**Container Images:**
- `teddysun/xray:24.11.30` - Xray-core VPN/Proxy
- `haproxy:latest` - Unified TLS termination & routing (NEW v4.3, replaces stunnel)
- `nginx:alpine` - Reverse proxy backends (ports 9443-9452, localhost)

**System:**
- Ubuntu 20.04+ / Debian 10+ (primary support)
- Docker 20.10+, Docker Compose v2.0+
- UFW firewall (auto-installed)

**Tools:**
- bash 4.0+, jq 1.5+, openssl, certbot, fail2ban

**Детали:** [→ Dependencies](06_appendix.md#11-dependencies)

---

## Быстрый старт

### Для администраторов

```bash
# 1. Установка (< 7 минут)
git clone https://github.com/user/vless-reality-vpn.git
cd vless-reality-vpn
sudo bash install.sh

# 2. Управление пользователями
sudo vless-user add alice           # Создать пользователя
sudo vless-user list                # Список пользователей
sudo vless-user show alice          # Показать конфиги
sudo vless-user show-proxy alice    # Показать proxy credentials

# 3. Reverse Proxy (v4.3 - subdomain-based, NO port!)
sudo vless-proxy add                # Interactive setup
# URL: https://subdomain.example.com (NO :9443!)
sudo vless-proxy list               # Список reverse proxies
sudo vless-proxy remove subdomain.example.com

# 4. IP whitelisting
sudo vless show-proxy-ips           # Показать server-level whitelist
sudo vless add-proxy-ip 203.0.113.45  # Добавить IP
sudo vless add-ufw-ip 203.0.113.45    # Добавить UFW правило (опционально)

# 5. Мониторинг
sudo vless-status                   # Статус системы (включая HAProxy info)
sudo vless-logs -f                  # Live логи
sudo vless test-security            # Security test suite
```

### Для пользователей

**VLESS Reality VPN (mobile):**
1. Установить v2rayNG (Android) или Shadowrocket (iOS)
2. Отсканировать QR code или импортировать URI

**Encrypted Proxy (desktop):**
1. Получить конфиги от администратора (6 файлов)
2. VSCode: скопировать `vscode_settings.json` → Settings
3. Git: `git config --global http.proxy socks5s://user:pass@server:1080`
4. Docker: скопировать `docker_daemon.json` → `/etc/docker/daemon.json`

---

## Ссылки на документацию

### Внутренняя документация

- **[README.md](../../README.md)** - User guide, installation instructions
- **[CHANGELOG.md](../../CHANGELOG.md)** - Version history, breaking changes, migration guides
- **[CLAUDE.md](../../CLAUDE.md)** - Project memory, technical details, troubleshooting
- **[PRD.md](../../PRD.md)** - Original consolidated PRD (source for this split)

### Разделы PRD

- **[01. Обзор](01_overview.md)** - Document Control, Executive Summary
- **[02. Функциональные требования](02_functional_requirements.md)** - All FR-* requirements
- **[03. NFR](03_nfr.md)** - Non-Functional Requirements
- **[04. Архитектура](04_architecture.md)** - Technical Architecture
- **[05. Тестирование](05_testing.md)** - Testing Requirements
- **[06. Приложения](06_appendix.md)** - Implementation, Security, References

---

## Статус проекта

**Version:** v4.3 (2025-10-18)
**Implementation Status:** ✅ **100% COMPLETE**
**Production Ready:** ✅ **YES**
**Security Status:** ✅ **APPROVED** (TLS 1.3 HAProxy, Let's Encrypt, fail2ban HAProxy+Nginx, UFW, SNI routing)

**Ключевые достижения v4.3:**
1. ✅ HAProxy Unified Architecture (1 контейнер вместо 2)
2. ✅ Subdomain-based reverse proxy (https://domain, NO port!)
3. ✅ SNI routing без TLS decryption
4. ✅ Port range 9443-9452 (localhost-only backends)
5. ✅ fail2ban HAProxy integration
6. ✅ Automated test suite (3 test cases, DEV_MODE)

**Следующие шаги:**
1. Production deployment monitoring
2. Performance metrics collection
3. Security auditing (ongoing)

---

**Создано:** 2025-10-16
**Обновлено:** 2025-10-18 (v4.3 HAProxy Unified)
**Источник:** [PRD.md](../../PRD.md) (consolidated version)
**Разделение:** Логические модули для удобной навигации

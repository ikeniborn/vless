# PRD v4.1 - Executive Summary & Navigation

**VLESS + Reality VPN Server: Product Requirements Document**

**Version:** 4.1 (Heredoc Config Generation + Proxy URI Fix)
**Status:** ✅ 100% Implemented
**Last Updated:** 2025-10-07

---

## Быстрая навигация

| Раздел | Описание | Ссылка |
|--------|----------|--------|
| **01. Обзор** | Document Control, Executive Summary, Product Overview | [→ Открыть](01_overview.md) |
| **02. Функциональные требования** | FR-STUNNEL-001, FR-TLS-002, FR-CERT-001/002, FR-IP-001, FR-CONFIG-001, FR-VSCODE-001, FR-GIT-001, FR-PUBLIC-001, FR-PASSWORD-001, FR-FAIL2BAN-001, FR-UFW-001, FR-MIGRATION-001, **FR-REVERSE-PROXY-001** (NEW v4.2 DRAFT) | [→ Открыть](02_functional_requirements.md) |
| **03. NFR** | NFR-SEC-001, NFR-OPS-001, NFR-PERF-001, NFR-COMPAT-001, NFR-USABILITY-001, NFR-RELIABILITY-001 | [→ Открыть](03_nfr.md) |
| **04. Архитектура** | Network Architecture, Data Flow, Certificate Lifecycle, File Structure, Docker Compose | [→ Открыть](04_architecture.md) |
| **05. Тестирование** | TLS Integration Tests, Client Integration Tests, Security Tests, Backward Compatibility | [→ Открыть](05_testing.md) |
| **06. Приложения** | Implementation Details, Security Risk, Success Metrics, Dependencies, Rollback, References | [→ Открыть](06_appendix.md) |

---

## Ключевые характеристики v4.1

### Текущая версия (Production-Ready)

**Статус реализации:** ✅ **100% COMPLETE**

| Компонент | Версия | Статус |
|-----------|--------|--------|
| **VLESS Reality VPN** | v4.1 | ✅ Stable |
| **stunnel TLS Termination** | v4.0+ | ✅ Production |
| **Dual Proxy (SOCKS5 + HTTP)** | v4.1 | ✅ Complete |
| **Heredoc Config Generation** | v4.1 | ✅ Implemented |
| **Proxy URI Fix** | v4.1 | ✅ Bugfix (https://, socks5s://) |
| **IP Whitelisting** | v3.6/v4.0 | ✅ Server-level + UFW |
| **Let's Encrypt Auto-Renewal** | v3.3+ | ✅ Automated |

---

## Архитектура (v4.1)

### Компоненты системы

```
┌─────────────────────────────────────────────────────────┐
│                        CLIENT                           │
│  VLESS Reality VPN (port 443)                          │
│  OR                                                     │
│  Encrypted Proxy: socks5s://1080, https://8118        │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ TLS 1.3 Encrypted
                      ↓
┌─────────────────────────────────────────────────────────┐
│                   UFW FIREWALL                          │
│  - VLESS: 443 (ALLOW)                                  │
│  - Proxy: 1080/8118 (LIMIT: 10 conn/min)              │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────┐
│               DOCKER CONTAINERS                         │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ stunnel (v4.0+)                                  │ │
│  │  - TLS 1.3 termination for proxy ports          │ │
│  │  - Listens: 0.0.0.0:1080, 0.0.0.0:8118         │ │
│  │  - Forwards to: vless_xray:10800, :18118       │ │
│  │  - Uses Let's Encrypt certificates             │ │
│  └──────────────────┬───────────────────────────────┘ │
│                     │                                  │
│  ┌──────────────────▼───────────────────────────────┐ │
│  │ Xray-core                                        │ │
│  │  - VLESS Reality (port 443)                     │ │
│  │  - SOCKS5 plaintext (localhost:10800)           │ │
│  │  - HTTP plaintext (localhost:18118)             │ │
│  │  - Password authentication (32-char)            │ │
│  │  - IP whitelisting via routing rules            │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Nginx (fake-site)                                │ │
│  │  - Fallback for invalid VLESS connections       │ │
│  │  - Proxies to destination site (DPI resistance) │ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Ключевые изменения по версиям

| Версия | Дата | Основное изменение | Impact |
|--------|------|-------------------|--------|
| **v4.1** | 2025-10-07 | Heredoc config generation + URI fix | Упрощение (удален envsubst), исправлен баг URI |
| **v4.0** | 2025-10-06 | stunnel TLS termination | Разделение TLS и proxy логики |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | Миграция с per-user (протокольное ограничение) |
| **v3.3** | 2025-10-05 | Mandatory TLS (Let's Encrypt) | Устранена критическая уязвимость v3.2 |
| **v3.2** | 2025-10-04 | Public proxy (no encryption) | ❌ **CRITICAL SECURITY ISSUE** (deprecated) |
| **v3.1** | 2025-10-03 | Dual proxy (localhost-only) | Базовая proxy функциональность |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | Исходная VPN система |

---

## Функциональные требования (краткий обзор)

### Критические (CRITICAL)

1. **FR-STUNNEL-001** (v4.0) - stunnel TLS Termination
   - TLS 1.3 в отдельном контейнере
   - Упрощенная конфигурация Xray (plaintext inbounds)
   - Лучшая отладка (раздельные логи)

2. **FR-CERT-001** - Автоматическое получение Let's Encrypt сертификатов
   - Интеграция с certbot
   - ACME HTTP-01 challenge (временное открытие порта 80)
   - DNS валидация перед получением

3. **FR-CERT-002** - Автоматическое обновление сертификатов
   - Cron job (запуск 2 раза в день)
   - Deploy hook для перезапуска Xray
   - Downtime < 5 секунд

4. **FR-IP-001** (v3.6) - Server-Level IP-Based Access Control
   - proxy_allowed_ips.json (server-level whitelist)
   - Xray routing rules без поля `user` (протокольное ограничение)
   - 5 CLI команд для управления

5. **FR-CONFIG-001** (v4.1 BUGFIX) - Генерация клиентских конфигураций с TLS URIs
   - ✅ Исправлено: `socks5s://` (было `socks5://`)
   - ✅ Исправлено: `https://` (было `http://`)
   - 6 форматов файлов на пользователя

### Высокий приоритет (HIGH)

6. **FR-VSCODE-001** - VSCode Integration через HTTPS Proxy
7. **FR-GIT-001** - Git Integration через SOCKS5s Proxy
8. **FR-TLS-002** - TLS Encryption для HTTP Inbound
9. **FR-PUBLIC-001** - Public Proxy Binding (0.0.0.0)
10. **FR-PASSWORD-001** - 32-character passwords (brute-force protection)
11. **FR-FAIL2BAN-001** - Fail2ban Integration (5 retries → ban)
12. **FR-UFW-001** - UFW Firewall Rules с rate limiting
13. **FR-MIGRATION-001** - Migration Path v3.2 → v3.3

### Запланировано (v4.2 DRAFT)

14. **FR-REVERSE-PROXY-001** - Site-Specific Reverse Proxy (NEW v4.2)
   - Nginx reverse proxy с TLS termination
   - Xray для domain-based routing
   - HTTP Basic Auth (bcrypt)
   - Let's Encrypt сертификаты
   - Поддержка до 10 доменов на сервер
   - Обязательная fail2ban защита
   - Configurable port (default 8443)
   - **Status:** 📝 DRAFT v2 (ожидает security review)
   - **Ссылка:** [→ FR-REVERSE-PROXY-001.md](FR-REVERSE-PROXY-001.md)

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

### Performance Targets (v4.1)

- **Installation Time:** < 7 минут (clean Ubuntu 22.04, 10 Mbps)
- **User Creation:** < 5 секунд (consistent up to 50 users)
- **Container Startup:** < 10 секунд
- **Config Reload:** < 3 секунд
- **Cert Renewal Downtime:** < 5 секунд

### Security Posture (v4.1)

- ✅ **TLS 1.3 Encryption** (stunnel termination, v4.0+)
- ✅ **Let's Encrypt Certificates** (auto-renewal)
- ✅ **32-Character Passwords** (brute-force resistant)
- ✅ **fail2ban Protection** (5 attempts → 1 hour ban)
- ✅ **UFW Rate Limiting** (10 conn/min per IP)
- ✅ **DPI Resistance** (Reality protocol)
- ✅ **IP Whitelisting** (server-level + optional UFW, v4.0+)

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

### Core Stack (v4.1)

**Container Images:**
- `teddysun/xray:24.11.30` - Xray-core VPN/Proxy
- `dweomer/stunnel:latest` - TLS termination (NEW v4.0)
- `nginx:alpine` - Fake-site для DPI resistance

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

# 3. IP whitelisting (v4.0+)
sudo vless show-proxy-ips           # Показать server-level whitelist
sudo vless add-proxy-ip 203.0.113.45  # Добавить IP
sudo vless add-ufw-ip 203.0.113.45    # Добавить UFW правило (опционально)

# 4. Мониторинг
sudo vless-status                   # Статус системы
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

**Version:** v4.1 (2025-10-07)
**Implementation Status:** ✅ **100% COMPLETE**
**Production Ready:** ✅ **YES**
**Security Status:** ✅ **APPROVED** (TLS 1.3, Let's Encrypt, fail2ban, UFW)

**Следующие шаги:**
1. ✅ Все фичи реализованы
2. Мониторинг production performance
3. Планирование v4.2 (по необходимости)

---

**Создано:** 2025-10-16
**Источник:** [PRD.md](../../PRD.md) (consolidated version)
**Разделение:** Логические модули для удобной навигации

# PRD v1.1.5 - Executive Summary & Navigation

**familyTraffic VPN Server: Product Requirements Document**

**Version:** 1.1.5 (Per-user SOCKS5/HTTP proxy auth; MTProxy integrated)
**Status:** Production-Ready
**Last Updated:** 2026-03-25

---

## Быстрая навигация

| Раздел | Описание | Ссылка |
|--------|----------|--------|
| **01. Обзор** | Document Control, Executive Summary, Product Overview | [→ Открыть](01_overview.md) |
| **02. Функциональные требования** | FR-NGINX-001 (v1.1.0), FR-REVERSE-PROXY-001, FR-TLS-002, FR-CERT-001/002, FR-IP-001, FR-CONFIG-001, FR-VSCODE-001, FR-GIT-001, FR-PUBLIC-001, FR-PASSWORD-001, FR-FAIL2BAN-001, FR-UFW-001, FR-MTPROXY-001 | [→ Открыть](02_functional_requirements.md) |
| **03. NFR** | NFR-SEC-001, NFR-OPS-001, NFR-PERF-001, NFR-COMPAT-001, NFR-USABILITY-001, NFR-RELIABILITY-001 | [→ Открыть](03_nfr.md) |
| **04. Архитектура** | Section 4.8 Single-Container Architecture (v1.1.0+), Network Architecture, Data Flow, Certificate Lifecycle, File Structure | [→ Открыть](04_architecture.md) |
| **05. Тестирование** | Unit Tests (BATS), Integration Tests, Security Tests | [→ Открыть](05_testing.md) |
| **06. Приложения** | Implementation Details, Security Risk, Success Metrics, Dependencies, Rollback, References | [→ Открыть](06_appendix.md) |

---

## Ключевые характеристики v1.1.5

### Текущая версия (Production-Ready)

**Статус реализации:** Production-Ready

| Компонент | Версия | Статус |
|-----------|--------|--------|
| **VLESS Reality VPN** | Xray-core 24.11.30 | Stable + Hardened |
| **nginx SNI Routing** | nginx:alpine (single container) | Production (replaces HAProxy) |
| **MTProxy (mtg v2.2.3)** | v2.2.3 | Integrated (optional, supervisord-managed) |
| **Per-user SOCKS5/HTTP proxy auth** | v1.1.5 | Unique credentials per user |
| **Tier 2 transports (WS/gRPC/XHTTP)** | v1.1.0+ | Implemented (ports 8444-8446) |
| **Subdomain-Based Reverse Proxy** | v1.1.0+ | https://domain (NO port!) |
| **External Proxy Support** | v5.23 legacy | Server-level upstream proxy chaining |
| **XTLS Vision** | v5.24+ | flow=xtls-rprx-vision (all users) |
| **Enhanced Reverse Proxy Validation** | v5.23 | 10s delay + 6 retries |
| **fail2ban Integration** | v4.3+ | nginx + Xray filters |
| **IP Whitelisting** | v3.6+ | Server-level + UFW |
| **Let's Encrypt Auto-Renewal** | v3.3+ | certbot-cron every 12h |
| **Advanced Reverse Proxy Features** | v5.8-v5.11 | OAuth2, CSRF, WebSocket, CSP, Security Headers |

---

## Архитектура (v1.1.0+)

### Компоненты системы

```
+-----------------------------------------------------------+
|                        CLIENT                             |
|  VLESS Reality VPN (port 443)                             |
|  Tier 2 transports: WS/gRPC/XHTTP (8444-8446 via SNI)   |
|  MTProxy (port 2053, Fake TLS)                           |
|  Encrypted Proxy: socks5s://1080, https://8118           |
|  Reverse Proxy: https://subdomain.example.com (NO port!) |
+-------------------------+---------------------------------+
                          |
                          | TLS 1.3 Encrypted
                          v
+-----------------------------------------------------------+
|                   UFW FIREWALL                            |
|  - Port 443 (ALLOW) - VLESS + Tier 2 + Reverse Proxy     |
|  - Ports 1080/8118 (LIMIT) - Encrypted Proxies           |
|  - Port 2053 (ALLOW) - MTProxy (if enabled)              |
+-------------------------+---------------------------------+
                          |
                          v
+-----------------------------------------------------------+
|         DOCKER CONTAINER: familytraffic                   |
|         (network_mode: host, supervisord PID 1)           |
|                                                           |
|  +-----------------------------------------------------+  |
|  | nginx (SNI routing)                                 |  |
|  |  - Port 443: ssl_preread SNI routing                |  |
|  |    * Reality SNI  -> 127.0.0.1:8443 (xray VLESS)   |  |
|  |    * Tier 2 SNI   -> port 8448 (WS/gRPC/XHTTP)     |  |
|  |  - Port 1080: TLS termination -> 127.0.0.1:10800    |  |
|  |  - Port 8118: TLS termination -> 127.0.0.1:18118    |  |
|  |  - Port 4443: cloak-port (loopback-only, LE cert)   |  |
|  +-----------------------------------------------------+  |
|                          |                                 |
|  +-----------------------------------------------------+  |
|  | xray-core                                           |  |
|  |  - VLESS Reality (port 8443, internal)              |  |
|  |  - Tier 2 WS (port 8444, internal)                  |  |
|  |  - Tier 2 XHTTP (port 8445, internal)               |  |
|  |  - Tier 2 gRPC (port 8446, internal)                |  |
|  |  - SOCKS5 plaintext (127.0.0.1:10800)               |  |
|  |  - HTTP plaintext (127.0.0.1:18118)                 |  |
|  |  - Per-user credentials (v1.1.5)                    |  |
|  +-----------------------------------------------------+  |
|                                                           |
|  +-----------------------------------------------------+  |
|  | certbot-cron                                        |  |
|  |  - Auto-renews Let's Encrypt every 12h              |  |
|  +-----------------------------------------------------+  |
|                                                           |
|  +-----------------------------------------------------+  |
|  | mtg (MTProxy, optional)                             |  |
|  |  - Port 2053 (MTProxy Fake TLS -> Telegram DCs)     |  |
|  |  - Enabled via supervisord.d/mtg.conf               |  |
|  |  - Managed via familytraffic-mtproxy CLI            |  |
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
```

### Трафик-флоу

```
Client:443  -> nginx (ssl_preread SNI)
               +- Reality SNI  -> 127.0.0.1:8443 (xray VLESS Reality)
               +- Tier 2 SNI   -> port 8448 -> WS/XHTTP/gRPC inbounds
Client:1080 -> nginx TLS termination -> 127.0.0.1:10800 (SOCKS5)
Client:8118 -> nginx TLS termination -> 127.0.0.1:18118 (HTTP proxy)
Client:2053 -> mtg (MTProxy Fake TLS) -> Telegram DCs
Client:4443 -> nginx (LE-cert, active probing protection, loopback-only)
```

### Ключевые изменения по версиям

| Версия | Дата | Основное изменение | Impact |
|--------|------|-------------------|--------|
| **v1.1.5** | 2026-03-25 | Per-user SOCKS5/HTTP proxy auth; cert renewal improvements | Уникальные credentials на пользователя, улучшена надёжность обновления сертификатов |
| **v1.1.0** | 2026-02 | Single-container architecture; nginx replaces HAProxy; MTProxy (mtg v2.2.3) | Упрощённая архитектура, 1 контейнер вместо нескольких, supervisord, nginx ssl_preread |
| **v5.33** | 2025-10-30 | External Proxy TLS Server Name Validation & UX (CRITICAL) | FQDN/IP format validation, auto-activation workflow |
| **v5.24** | 2025-10-22 | HTTP Basic Auth + XTLS Vision | Nginx auth_basic fix, flow=xtls-rprx-vision для всех пользователей |
| **v5.23** | 2025-10-22 | Enhanced Validation + 3 CRITICAL BUGFIXES | False negatives -> 0%, fail2ban fix, race condition fix |
| **v5.11** | 2025-10-20 | Enhanced Security Headers | COOP, COEP, CORP, Expect-CT |
| **v5.10** | 2025-10-20 | Advanced Wizard + CSP | Интерактивные опции OAuth2/WebSocket/CSP |
| **v5.8** | 2025-10-20 | Cookie/URL Rewriting | Foundation для session-based auth, OAuth2 |
| **v4.3 (legacy)** | 2025-10-18 | HAProxy Unified Architecture | Удалён в v1.1.0, заменён nginx |
| **v3.3** | 2025-10-05 | Mandatory TLS (Let's Encrypt) | Устранена критическая уязвимость |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | Исходная VPN система |

---

## Функциональные требования (краткий обзор)

### Критические (CRITICAL)

1. **FR-NGINX-001** (v1.1.0) - nginx SNI Routing Architecture
   - Единый контейнер `familytraffic` с supervisord
   - nginx ssl_preread: SNI routing на порту 443 (без TLS decryption для Reality)
   - TLS termination для SOCKS5 (1080) и HTTP (8118)
   - cloak-port 4443 (loopback-only, active probing protection)
   - nginx reload для zero-downtime конфигурации

2. **FR-REVERSE-PROXY-001** (v1.1.0) - Subdomain-Based Reverse Proxy
   - nginx SNI routing -> Nginx backends (localhost-only)
   - Subdomain access: https://subdomain.example.com (NO port number!)
   - Xray routing для proxy traffic to target sites
   - Let's Encrypt сертификаты (стандартные fullchain.pem + privkey.pem)

3. **FR-CERT-001** - Автоматическое получение Let's Encrypt сертификатов
   - Интеграция с certbot
   - ACME HTTP-01 challenge (временное открытие порта 80)
   - DNS валидация перед получением

4. **FR-CERT-002** - Автоматическое обновление сертификатов
   - certbot-cron (запуск каждые 12 часов внутри контейнера)
   - Deploy hook для перезапуска nginx (graceful reload)
   - Downtime < 5 секунд

5. **FR-IP-001** (v3.6) - Server-Level IP-Based Access Control
   - proxy_allowed_ips.json (server-level whitelist)
   - Xray routing rules
   - 5 CLI команд для управления

6. **FR-CONFIG-001** (v4.1) - Генерация клиентских конфигураций с TLS URIs
   - `socks5s://` (TLS-enabled SOCKS5)
   - `https://` (TLS-enabled HTTP)
   - 6 форматов файлов на пользователя

7. **FR-MTPROXY-001** (v1.1.0) - MTProxy (mtg v2.2.3) Integration
   - Optional, opt-in через `familytraffic-mtproxy setup`
   - Управление через supervisord.d/mtg.conf
   - Fake TLS, порт 2053, ee-формат секретов

### Высокий приоритет (HIGH)

8. **FR-VSCODE-001** - VSCode Integration через HTTPS Proxy
9. **FR-GIT-001** - Git Integration через SOCKS5s Proxy
10. **FR-TLS-002** - TLS Encryption для HTTP Inbound
11. **FR-PUBLIC-001** - Public Proxy Binding (0.0.0.0)
12. **FR-PASSWORD-001** - Per-user proxy credentials (v1.1.5)
13. **FR-FAIL2BAN-001** - Fail2ban Integration (5 retries -> ban, nginx + Xray filters)
14. **FR-UFW-001** - UFW Firewall Rules с rate limiting

**Детали:** [→ Функциональные требования](02_functional_requirements.md)

---

## Non-Functional Requirements (NFR)

| Требование | Метрика | Статус |
|------------|---------|--------|
| **NFR-SEC-001** | 100% публичных прокси с TLS | Enforced |
| **NFR-OPS-001** | 0 manual steps для cert renewal | Automated |
| **NFR-PERF-001** | TLS overhead < 2ms | Acceptable |
| **NFR-COMPAT-001** | VSCode 1.60+, Git 2.0+ | Verified |
| **NFR-USABILITY-001** | Installation < 7 минут | Tested |
| **NFR-RELIABILITY-001** | Cert renewal success > 99% | Monitored |

**Детали:** [→ Non-Functional Requirements](03_nfr.md)

---

## Reverse Proxy Advanced Features (v5.8-v5.11)

### Feature Evolution

**v5.8 - Cookie/URL Rewriting Foundation**
- **Cookie Domain Rewriting**: `proxy_cookie_domain` for session persistence
- **URL Rewriting**: `sub_filter` for HTML/JS/CSS links
- **Origin Header**: CORS compatibility for target site
- **Use Case**: Session-based auth, form-based login

**v5.9 - Complex Authentication Support**
- **Enhanced Cookie Handling**: Multiple Set-Cookie headers (OAuth2/Google Auth)
- **Large Cookie Support**: Increased buffers (32k/16x32k/64k) for OAuth2 state >4kb
- **CSRF Protection**: Referer header rewriting from proxy domain -> target domain
- **WebSocket Support**: Long-lived connections (3600s timeout), connection upgrade map
- **Use Case**: OAuth2, Google Auth, CSRF-protected APIs, real-time apps

**v5.10 - CSP & Intelligent Rewriting**
- **CSP Header Handling**: Configurable strip/keep (default: strip for compatibility)
- **Intelligent Sub-filter**: 5 URL patterns (protocol-relative, JSON, JS strings)
- **Advanced Wizard**: Interactive options (OAuth2/WebSocket/CSP)
- **JSON Content Type**: API responses properly rewritten
- **Use Case**: Modern SPAs (React, Vue, Angular), API-heavy sites

**v5.11 - Enhanced Security Headers**
- **Modern Isolation Headers**: COOP, COEP, CORP, Expect-CT (opt-in)
- **Browser Isolation**: Protects against Spectre-like attacks
- **Certificate Transparency**: Enforced CT validation
- **Configurable**: Default OFF (compatibility first), opt-in via wizard
- **Use Case**: High-security internal apps, compliance requirements

### Supported Authentication Scenarios

| Scenario | Status | Version | Notes |
|----------|--------|---------|-------|
| **Session Cookies** | Working | v5.8+ | Cookie domain rewriting |
| **Form-based Login** | Working | v5.8+ | POST/PUT/DELETE with CSRF |
| **OAuth2 / OIDC** | Working | v5.9+ | Multiple cookies, large buffers |
| **Google Auth** | Working | v5.9+ | OAuth2 state cookies >4kb |
| **CSRF-protected APIs** | Working | v5.9+ | Referer rewriting |
| **WebSocket Auth** | Working | v5.9+ | Long-lived connections |
| **Modern SPAs** | Working | v5.10+ | CSP stripping, intelligent rewriting |
| **HTTP Basic Auth** | Working | v4.3+ | Native nginx support |
| **JWT (cookie-based)** | Working | v5.9+ | Large cookie support |

**Not Supported:**
- Client-side certificates (mTLS)
- Kerberos / NTLM
- SAML (requires XML rewriting)

---

## Технические характеристики

### Performance Targets

- **Installation Time:** < 7 минут (clean Ubuntu 22.04, 10 Mbps)
- **User Creation:** < 5 секунд
- **Container Startup:** < 10 секунд
- **Config Reload:** < 3 секунд (nginx graceful reload)
- **Cert Renewal Downtime:** < 5 секунд
- **Reverse Proxy Setup:** < 2 минуты

### Security Posture (v1.1.5)

- **TLS 1.3 Encryption** (nginx termination)
- **Let's Encrypt Certificates** (auto-renewal via certbot-cron every 12h)
- **Per-user Proxy Credentials** (v1.1.5, brute-force resistant)
- **fail2ban Protection** (nginx + Xray filters, 5 attempts -> 1 hour ban)
- **UFW Rate Limiting** (10 conn/min per IP)
- **DPI Resistance** (Reality protocol + XTLS Vision + SNI routing)
- **IP Whitelisting** (server-level + optional UFW)
- **SNI Routing Security** (NO TLS decryption for VLESS Reality)
- **Active Probing Protection** (cloak-port 4443, loopback-only)

### Scalability

- **Target Scale:** 10-50 concurrent users
- **User Storage:** JSON files (fast for target scale)
- **File Locking:** flock-based (sufficient for < 100 users)
- **Horizontal Scaling:** Multiple independent instances for > 50 users

**Детали:** [→ Архитектура](04_architecture.md)

---

## Testing Coverage

### Категории тестов

1. **Unit Tests (BATS)** — запускаются без Docker
   - test_validation.bats
   - test_logger.bats
   - test_os_detection.bats

2. **Integration Tests** — требуют работающий контейнер
   - test_user_workflow.bats

3. **Security Tests**
   - TLS handshake validation (SOCKS5, HTTP)
   - Certificate validity check
   - Auto-renewal dry-run

**Детали:** [→ Тестирование](05_testing.md)

---

## Зависимости

### Core Stack (v1.1.0+)

**Единый Docker образ:** `ghcr.io/…/familytraffic:latest`

Компоненты внутри образа:
- `nginx:alpine` — SNI routing, TLS termination, reverse proxy
- `xray-core (teddysun/xray:24.11.30)` — VPN/Proxy engine
- `certbot` — Let's Encrypt certificate management
- `supervisord` — PID 1, process manager
- `mtg v2.2.3` — MTProxy (optional, opt-in)

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
git clone https://github.com/user/familytraffic.git
cd familytraffic
sudo bash install.sh

# 2. Управление пользователями
sudo familytraffic user add alice           # Создать пользователя
sudo familytraffic user list               # Список пользователей
sudo familytraffic user show alice         # Показать конфиги
sudo familytraffic user show-proxy alice   # Показать proxy credentials

# 3. Управление MTProxy (опционально)
sudo familytraffic-mtproxy setup --fake-domain www.google.com
sudo familytraffic-mtproxy status
sudo familytraffic-mtproxy start/stop/restart/logs

# 4. Управление транспортами Tier 2
sudo familytraffic add-transport ws subdomain.example.com
sudo familytraffic add-transport xhttp subdomain.example.com
sudo familytraffic add-transport grpc subdomain.example.com
sudo familytraffic list-transports

# 5. Управление upstream proxy
sudo familytraffic-external-proxy add
sudo familytraffic-external-proxy list
sudo familytraffic-external-proxy enable

# 6. IP whitelisting
sudo familytraffic show-proxy-ips
sudo familytraffic add-proxy-ip 203.0.113.45
sudo familytraffic add-ufw-ip 203.0.113.45

# 7. Сертификаты
sudo familytraffic-cert-renew

# 8. Мониторинг
sudo familytraffic status
sudo familytraffic logs -f
```

### Для пользователей

**VLESS Reality VPN (mobile):**
1. Установить v2rayNG (Android) или v2rayTun / Shadowrocket (iOS)
2. Отсканировать QR code или импортировать URI

**Encrypted Proxy (desktop):**
1. Получить конфиги от администратора (6 файлов)
2. VSCode: скопировать `vscode_settings.json` -> Settings
3. Git: `git config --global http.proxy socks5s://[CREDENTIALS]@server:1080`
4. Docker: скопировать `docker_daemon.json` -> `/etc/docker/daemon.json`

**MTProxy (Telegram):**
1. Получить mtproto:// ссылку от администратора
2. Добавить в Telegram -> Settings -> Data and Storage -> Proxy

---

## Ссылки на документацию

### Внутренняя документация

- **[README.md](../../README.md)** - User guide, installation instructions
- **[CHANGELOG.md](../../CHANGELOG.md)** - Version history, breaking changes, migration guides
- **[CLAUDE.md](../../CLAUDE.md)** - Project memory, technical details, troubleshooting

### Разделы PRD

- **[01. Обзор](01_overview.md)** - Document Control, Executive Summary
- **[02. Функциональные требования](02_functional_requirements.md)** - All FR-* requirements
- **[03. NFR](03_nfr.md)** - Non-Functional Requirements
- **[04. Архитектура](04_architecture.md)** - Technical Architecture
- **[05. Тестирование](05_testing.md)** - Testing Requirements
- **[06. Приложения](06_appendix.md)** - Implementation, Security, References

---

## Статус проекта

**Version:** v1.1.5 (2026-03-25)
**Implementation Status:** Production-Ready
**Production Ready:** YES
**Security Status:** APPROVED (TLS 1.3 nginx, Let's Encrypt, fail2ban, UFW, SNI routing, per-user proxy auth)

**Ключевые достижения v1.1.5:**
1. Per-user SOCKS5/HTTP proxy auth (unique credentials per user)
2. Cert renewal improvements

**Ключевые достижения v1.1.0:**
1. Single-container architecture (nginx + xray + certbot + supervisord)
2. nginx ssl_preread SNI routing (replaces HAProxy)
3. MTProxy (mtg v2.2.3) integrated as optional process
4. Tier 2 transports (WS/gRPC/XHTTP) implemented

**Следующие шаги:**
1. Production deployment monitoring
2. Performance metrics collection
3. Security auditing (ongoing)

---

**Создано:** 2025-10-16
**Обновлено:** 2026-03-25 (v1.1.5 — per-user proxy auth; nginx replaces HAProxy; MTProxy integrated)
**Разделение:** Логические модули для удобной навигации

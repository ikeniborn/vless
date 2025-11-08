# MTProxy Integration Plan for VLESS Reality VPN Project

**Version:** 6.0-draft (MTProxy Support)
**Status:** 📝 PLANNING (Documentation Phase)
**Priority:** HIGH
**Created:** 2025-11-07
**Last Updated:** 2025-11-07

---

## TABLE OF CONTENTS

1. [Executive Summary](#1-executive-summary)
2. [Background & Motivation](#2-background--motivation)
3. [Integration Scope](#3-integration-scope)
4. [High-Level Architecture](#4-high-level-architecture)
5. [Functional Requirements](#5-functional-requirements)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [Technical Architecture](#7-technical-architecture)
8. [Implementation Phases](#8-implementation-phases)
9. [Testing Strategy](#9-testing-strategy)
10. [Risk Assessment](#10-risk-assessment)
11. [Migration & Rollback](#11-migration--rollback)
12. [References](#12-references)

---

## 1. EXECUTIVE SUMMARY

### Цель проекта

Добавить поддержку **MTProxy** (Telegram-специализированный прокси протокол) в существующую инфраструктуру VLESS Reality VPN (v5.33) в качестве дополнительного opt-in сервиса.

### Ключевые решения

| Аспект | Решение | Обоснование |
|--------|---------|-------------|
| **Назначение** | Специализированный Telegram-прокси | Фокус на Telegram клиентах, не замена VLESS |
| **Архитектура** | Отдельный Docker контейнер (vless_mtproxy) | Изоляция, независимое управление, opt-in установка |
| **Функциональность** | Базовая + официальные best practices | Минимальная viable implementation, расширение в будущем |
| **Интеграция** | fail2ban + клиентские конфиги | Совместимость с существующей инфраструктурой |
| **Приоритет** | HIGH | Ценная фича для пользователей Telegram, популярный протокол |

### Scope граница

**В scope (v6.0):**
- ✅ MTProxy Docker контейнер с официальным бинарником
- ✅ Opt-in установка (отдельный wizard)
- ✅ Генерация клиентских конфигураций (deep links, QR codes)
- ✅ fail2ban интеграция
- ✅ UFW firewall rules
- ✅ CLI управление секретами
- ✅ Базовый мониторинг (/stats endpoint)

**Не в scope (future versions):**
- ❌ Multi-user support с уникальными секретами на пользователя
- ❌ Promoted channel интеграция
- ❌ Advanced statistics/analytics
- ❌ HAProxy routing для MTProxy
- ❌ Let's Encrypt TLS для MTProxy (использует transport obfuscation)

---

## 2. BACKGROUND & MOTIVATION

### Что такое MTProxy?

**MTProxy** - официальный прокси-сервер Telegram для туннелирования MTProto трафика.

**Ключевые характеристики:**
- **Протокол:** MTProto (мобильный протокол Telegram)
- **Транспортные режимы:** 4 варианта (Abridged, Intermediate, Padded Intermediate, Full)
- **Transport Obfuscation:** AES-256-CTR шифрование для обхода DPI (Deep Packet Inspection)
- **Random Padding:** Случайные данные в пакетах для маскировки размеров
- **Секреты:** 16-byte ключи (32 hex symbols), опционально 17-byte с префиксом `dd` для padding

### Почему MTProxy для VLESS проекта?

**Проблемы, которые решает:**

1. **Telegram-специфичность**
   - VLESS/SOCKS5/HTTP - универсальные протоколы
   - MTProxy - оптимизирован для Telegram (нативная интеграция в клиентах)

2. **Обход блокировок Telegram**
   - В странах с блокировкой Telegram MTProxy наиболее эффективен
   - Transport obfuscation маскирует трафик как обычный HTTPS

3. **Простота для пользователей**
   - One-tap подключение в Telegram (tg://proxy?... deep links)
   - Нет необходимости в отдельных VPN приложениях
   - Встроенная поддержка в официальных клиентах Telegram

4. **Дополнительная опция**
   - Пользователи могут выбрать VLESS для всего трафика ИЛИ MTProxy только для Telegram
   - Диверсификация протоколов (снижает риск блокировок)

### Существующая архитектура (v5.33)

```
Client → HAProxy (443/1080/8118) → Xray → (External Proxy optional) → Internet
         5 контейнеров: vless_haproxy, vless_xray, vless_nginx_reverseproxy,
                        vless_certbot_nginx, vless_fake_site
```

**Проблема:** нет поддержки MTProto протокола

**Решение:** добавить 6-й контейнер **vless_mtproxy**

---

## 3. INTEGRATION SCOPE

### 3.1 Functional Scope (v6.0)

#### Базовая функциональность

**FR-MTPROXY-001: MTProxy Docker Container**
- **Описание:** Отдельный контейнер с официальным MTProxy бинарником
- **Детали:**
  - Image: собственный Dockerfile на базе `alpine:latest`
  - Компиляция из официального GitHub репозитория
  - Зависимости: `openssl`, `zlib`, `build-base`
  - Бинарник: `/opt/mtproxy/mtproto-proxy`
  - Конфигурация: `/opt/mtproxy/config/`

**FR-MTPROXY-002: Opt-in Installation**
- **Описание:** Установка MTProxy опциональна (как reverse proxy wizard)
- **Детали:**
  - Отдельный wizard: `vless-mtproxy-setup`
  - Вопросы: порт (по умолчанию 8443), workers, секреты
  - Не устанавливается по умолчанию при `vless-install`

**FR-MTPROXY-003: Secret Management**
- **Описание:** CLI для управления MTProxy секретами
- **Детали:**
  - Генерация: `head -c 16 /dev/urandom | xxd -ps`
  - Префикс `dd` для random padding (опционально)
  - Формат хранения: `/opt/vless/config/mtproxy_secrets.json`
  - CLI команды:
    - `vless-mtproxy add-secret [--with-padding]`
    - `vless-mtproxy list-secrets`
    - `vless-mtproxy remove-secret <secret>`
    - `vless-mtproxy regenerate-secret <old-secret>`

**FR-MTPROXY-004: Client Configuration Generation**
- **Описание:** Автоматическая генерация клиентских конфигураций
- **Детали:**
  - Deep link: `tg://proxy?server=IP&port=8443&secret=<HEX>`
  - HTTP link: `https://t.me/proxy?server=IP&port=8443&secret=<HEX>`
  - QR code генерация (PNG, SVG)
  - Файлы на пользователя:
    - `mtproxy_link.txt` (deep link)
    - `mtproxy_qr.png` (QR code)

**FR-MTPROXY-005: fail2ban Integration**
- **Описание:** Защита MTProxy от brute-force атак
- **Детали:**
  - Jail: `/etc/fail2ban/jail.d/vless-mtproxy.conf`
  - Filter: `/etc/fail2ban/filter.d/vless-mtproxy.conf`
  - Log source: `/opt/vless/logs/mtproxy/error.log`
  - Ban threshold: 5 failures → 1 hour ban
  - Pattern matching: MTProxy authentication errors

**FR-MTPROXY-006: UFW Firewall Rules**
- **Описание:** Автоматическое добавление UFW правил для MTProxy порта
- **Детали:**
  - Порт: 8443 (configurable)
  - Rule: `sudo ufw allow 8443/tcp`
  - Rate limiting: `sudo ufw limit 8443/tcp` (опционально)
  - Удаление при uninstall

**FR-MTPROXY-007: Basic Monitoring**
- **Описание:** Мониторинг состояния MTProxy через /stats endpoint
- **Детали:**
  - Stats port: 8888 (localhost only)
  - Endpoint: `curl localhost:8888/stats`
  - Метрики: active connections, total connections, uptime
  - Интеграция с `vless status` команд ой

#### Ограничения базовой функциональности

**Не включено в v6.0:**
- Multi-user support (один секрет для всех пользователей)
- Promoted channel интеграция (требует регистрацию через @MTProxybot)
- Advanced statistics (real-time graphs, history)
- TLS сертификаты (MTProxy использует transport obfuscation вместо TLS)

### 3.2 Non-Functional Scope

**NFR-MTPROXY-001: Performance**
- **Target:** < 10ms latency overhead vs direct Telegram connection
- **Acceptance:** Benchmark с официальным Telegram клиентом

**NFR-MTPROXY-002: Reliability**
- **Target:** 99.5% uptime (аналогично Xray)
- **Acceptance:** Auto-restart при сбоях, healthcheck в Docker

**NFR-MTPROXY-003: Security**
- **Target:** Защита от известных DPI методов обнаружения
- **Acceptance:** Transport obfuscation enabled, random padding available

**NFR-MTPROXY-004: Usability**
- **Target:** < 3 минуты на установку MTProxy (после vless-install)
- **Acceptance:** Interactive wizard с валидацией

**NFR-MTPROXY-005: Compatibility**
- **Target:** Работа со всеми официальными Telegram клиентами
- **Acceptance:** Тестирование Android, iOS, Desktop, Web

---

## 4. HIGH-LEVEL ARCHITECTURE

### 4.1 Новая архитектура (v6.0)

```
┌──────────────────────────────────────────────────────────────────┐
│                         INTERNET                                 │
└────────────────┬─────────────────────┬───────────────────────────┘
                 │                     │
                 │ Port 443           │ Port 8443
                 │ (VLESS/Reverse)    │ (MTProxy)
                 │                     │
       ┌─────────▼─────────────────────▼──────────────────────────┐
       │               UFW FIREWALL                                │
       │  - 443 ALLOW (VLESS Reality + Reverse Proxy)            │
       │  - 1080 LIMIT (SOCKS5 TLS)                              │
       │  - 8118 LIMIT (HTTP TLS)                                │
       │  - 8443 LIMIT (MTProxy) ← NEW                           │
       └─────────┬─────────────────────┬──────────────────────────┘
                 │                     │
                 │                     │
       ┌─────────▼─────────────────┐   │
       │   EXISTING CONTAINERS     │   │
       │  - vless_haproxy          │   │
       │  - vless_xray             │   │
       │  - vless_nginx_reverse    │   │
       │  - vless_certbot_nginx    │   │
       │  - vless_fake_site        │   │
       └───────────────────────────┘   │
                                        │
                              ┌─────────▼──────────────────────────┐
                              │   vless_mtproxy (NEW)              │
                              │  - Port 8443 (public)              │
                              │  - Port 8888 (stats, localhost)    │
                              │  - MTProto protocol                │
                              │  - Transport obfuscation           │
                              │  - Random padding (optional)       │
                              └────────────────────────────────────┘
```

### 4.2 Container Networking

**Docker Network:** `vless_reality_net` (existing)

**Port Mapping:**
- `8443:8443` - MTProxy публичный порт
- `127.0.0.1:8888:8888` - Stats endpoint (localhost only)

**Volume Mounts:**
- `/opt/vless/config/mtproxy/` → `/etc/mtproxy/` (ro) - Конфигурация
- `/opt/vless/logs/mtproxy/` → `/var/log/mtproxy/` (rw) - Логи
- `/opt/vless/data/mtproxy-stats/` → `/var/lib/mtproxy/` (rw) - Статистика

### 4.3 Traffic Flow

```
Telegram Client
    ↓
    │ 1. Connect to tg://proxy?server=IP&port=8443&secret=...
    ↓
UFW Firewall (port 8443 allowed)
    ↓
    │ 2. TCP connection to MTProxy container
    ↓
vless_mtproxy Container
    ↓
    │ 3. Transport obfuscation decryption (AES-256-CTR)
    │ 4. MTProto protocol processing
    │ 5. Authentication via secret
    ↓
    │ 6. Forward to Telegram servers
    ↓
Internet (Telegram DC - datacenter)
```

**Key Points:**
- MTProxy НЕ проходит через HAProxy (независимый путь)
- MTProxy НЕ использует Xray (прямое подключение к Telegram DC)
- MTProxy НЕ использует Let's Encrypt сертификаты (transport obfuscation вместо TLS)

---

## 5. FUNCTIONAL REQUIREMENTS

### FR-MTPROXY-001: MTProxy Docker Container

**Priority:** CRITICAL
**Status:** Planned

**Description:**
Создать отдельный Docker контейнер с официальным MTProxy бинарником из GitHub репозитория TelegramMessenger/MTProxy.

**Acceptance Criteria:**
- ✅ Dockerfile собирает MTProxy из официального репозитория
- ✅ Базовый image: `alpine:latest`
- ✅ Установлены зависимости: `openssl-dev`, `zlib-dev`, `build-base`
- ✅ Бинарник скомпилирован и доступен в `/usr/local/bin/mtproto-proxy`
- ✅ Контейнер стартует с параметрами: `-u nobody -p 8888 -H 8443 -S <secret>`
- ✅ Healthcheck: проверка TCP порта 8443
- ✅ Auto-restart policy: `unless-stopped`

**Implementation Notes:**
```dockerfile
FROM alpine:latest
RUN apk add --no-cache openssl-dev zlib-dev build-base git
RUN git clone https://github.com/TelegramMessenger/MTProxy.git /tmp/MTProxy
WORKDIR /tmp/MTProxy
RUN make && cp objs/bin/mtproto-proxy /usr/local/bin/
RUN adduser -D -s /sbin/nologin nobody
CMD ["/usr/local/bin/mtproto-proxy", "-u", "nobody", "-p", "8888", "-H", "8443", "-S", "${SECRET}", "--aes-pwd", "/etc/mtproxy/proxy-secret", "/etc/mtproxy/proxy-multi.conf", "-M", "1"]
```

---

### FR-MTPROXY-002: Opt-in Installation Wizard

**Priority:** HIGH
**Status:** Planned

**Description:**
Отдельный wizard для установки MTProxy (не включен в основной `vless-install`).

**Acceptance Criteria:**
- ✅ Скрипт: `/opt/vless/scripts/vless-mtproxy-setup`
- ✅ Symlink: `/usr/local/bin/vless-mtproxy-setup`
- ✅ Interactive prompts:
  1. "Install MTProxy? [y/N]"
  2. "MTProxy port [8443]:"
  3. "Number of workers [1]:"
  4. "Enable random padding? [Y/n]"
- ✅ Генерация секрета автоматически
- ✅ Добавление UFW правила
- ✅ fail2ban jail создание
- ✅ Docker контейнер запуск
- ✅ Валидация установки (проверка порта TCP 8443)
- ✅ Output: deep link и путь к QR code

**User Flow:**
```bash
$ sudo vless-mtproxy-setup

=== MTProxy Setup Wizard ===

MTProxy is a Telegram-specific proxy server.
Would you like to install it? [y/N]: y

Enter MTProxy port [8443]: 8443
Enter number of workers [1]: 2
Enable random padding (recommended)? [Y/n]: y

Generating secret...
✓ Secret generated: dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c
✓ UFW rule added: 8443/tcp LIMIT
✓ fail2ban jail created: vless-mtproxy
✓ Docker container started: vless_mtproxy
✓ MTProxy running on port 8443

Client configuration:
  Deep link: tg://proxy?server=1.2.3.4&port=8443&secret=dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c
  QR code: /opt/vless/data/mtproxy/mtproxy_qr.png

Next steps:
  1. Share the deep link or QR code with users
  2. Users tap link in Telegram to connect
  3. Monitor: sudo vless status
```

---

### FR-MTPROXY-003: Secret Management CLI

**Priority:** HIGH
**Status:** Planned

**Description:**
CLI команды для управления MTProxy секретами.

**Acceptance Criteria:**
- ✅ Команда: `vless-mtproxy add-secret [--with-padding]`
  - Генерирует 16-byte секрет: `head -c 16 /dev/urandom | xxd -ps`
  - Опционально добавляет префикс `dd` для padding
  - Сохраняет в `/opt/vless/config/mtproxy_secrets.json`
  - Обновляет Docker контейнер с новым секретом
  - Output: новый secret в hex формате

- ✅ Команда: `vless-mtproxy list-secrets`
  - Показывает все активные секреты
  - Формат: таблица (Secret, Padding, Created, Active)
  - Маскирует часть секрета: `dd1a2b...4b5c`

- ✅ Команда: `vless-mtproxy remove-secret <secret>`
  - Удаляет секрет из конфигурации
  - Перезапускает MTProxy контейнер
  - Предупреждает если это последний секрет

- ✅ Команда: `vless-mtproxy regenerate-secret <old-secret>`
  - Генерирует новый секрет
  - Заменяет старый
  - Перезапускает контейнер
  - Output: новый secret + deep link

**JSON Schema (mtproxy_secrets.json):**
```json
{
  "secrets": [
    {
      "value": "dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c",
      "padding_enabled": true,
      "created_at": "2025-11-07T12:00:00Z",
      "active": true
    }
  ],
  "metadata": {
    "last_modified": "2025-11-07T12:00:00Z",
    "version": "6.0.0"
  }
}
```

---

### FR-MTPROXY-004: Client Configuration Generation

**Priority:** HIGH
**Status:** Planned

**Description:**
Автоматическая генерация клиентских конфигураций при добавлении секрета.

**Acceptance Criteria:**
- ✅ Deep link генерация:
  - Format: `tg://proxy?server={IP}&port={PORT}&secret={SECRET}`
  - Alternative: `https://t.me/proxy?server={IP}&port={PORT}&secret={SECRET}`
  - Сохранение в `/opt/vless/data/mtproxy/mtproxy_link.txt`

- ✅ QR code генерация:
  - Library: `qrencode` (system package)
  - Output: PNG изображение 300x300px
  - Path: `/opt/vless/data/mtproxy/mtproxy_qr.png`
  - Кодирует deep link

- ✅ Команда: `vless-mtproxy show-config [<secret>]`
  - Показывает deep link для секрета
  - Показывает путь к QR code
  - Если secret не указан - показывает для активного

**User Flow:**
```bash
$ sudo vless-mtproxy add-secret --with-padding

✓ Secret generated: dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c

Client configuration saved:
  Deep link: /opt/vless/data/mtproxy/mtproxy_link.txt
  QR code: /opt/vless/data/mtproxy/mtproxy_qr.png

To view configuration:
  sudo vless-mtproxy show-config
```

---

### FR-MTPROXY-005: fail2ban Integration

**Priority:** MEDIUM
**Status:** Planned

**Description:**
Защита MTProxy от brute-force атак через fail2ban.

**Acceptance Criteria:**
- ✅ Jail file: `/etc/fail2ban/jail.d/vless-mtproxy.conf`
  ```ini
  [vless-mtproxy]
  enabled = true
  port = 8443
  protocol = tcp
  filter = vless-mtproxy
  logpath = /opt/vless/logs/mtproxy/error.log
  maxretry = 5
  bantime = 3600
  findtime = 600
  ```

- ✅ Filter file: `/etc/fail2ban/filter.d/vless-mtproxy.conf`
  ```ini
  [Definition]
  failregex = ^.*authentication failed.*from.*<HOST>.*$
  ignoreregex =
  ```

- ✅ Log rotation: `/etc/logrotate.d/vless-mtproxy`
- ✅ Автоматическое создание при `vless-mtproxy-setup`
- ✅ Тестирование: `fail2ban-regex /opt/vless/logs/mtproxy/error.log /etc/fail2ban/filter.d/vless-mtproxy.conf`

---

### FR-MTPROXY-006: UFW Firewall Rules

**Priority:** MEDIUM
**Status:** Planned

**Description:**
Автоматическое управление UFW правилами для MTProxy.

**Acceptance Criteria:**
- ✅ Добавление правила при установке:
  ```bash
  sudo ufw limit 8443/tcp comment 'MTProxy'
  ```

- ✅ Удаление правила при uninstall:
  ```bash
  sudo ufw delete limit 8443/tcp
  ```

- ✅ Валидация конфликтов портов перед установкой
- ✅ Проверка UFW статуса (active/inactive)
- ✅ Rate limiting по умолчанию (10 conn/min per IP)

---

### FR-MTPROXY-007: Basic Monitoring

**Priority:** LOW
**Status:** Planned

**Description:**
Базовый мониторинг MTProxy через /stats endpoint.

**Acceptance Criteria:**
- ✅ Stats endpoint: `http://localhost:8888/stats`
- ✅ Метрики:
  - Active connections
  - Total connections (since start)
  - Uptime
  - Bytes sent/received
- ✅ Интеграция с `vless status`:
  ```bash
  $ sudo vless status

  MTProxy Status (v6.0):
    ✓ Container: vless_mtproxy (running)
    Active connections: 5
    Total connections: 142
    Uptime: 2d 5h 32m
    Port: 8443
  ```

- ✅ Команда: `vless-mtproxy stats`
  - Показывает детальные метрики
  - Обновление каждые 5 секунд (live mode: `--live`)

---

## 6. NON-FUNCTIONAL REQUIREMENTS

### NFR-MTPROXY-001: Performance

**Priority:** HIGH
**Status:** Planned

**Target:**
- Latency overhead: < 10ms vs direct Telegram connection
- Throughput: ≥ 100 Mbps per worker
- CPU usage: < 5% при 50 concurrent connections

**Acceptance Criteria:**
- ✅ Benchmark с `iperf3` через MTProxy
- ✅ Сравнение с direct Telegram connection (измерение через Telegram Desktop logs)
- ✅ Load testing: 100 concurrent connections, измерение latency percentiles (p50, p95, p99)

**Testing Plan:**
```bash
# Benchmark script
#!/bin/bash
# 1. Direct connection latency baseline
curl -w "%{time_total}\n" https://api.telegram.org/bot<TOKEN>/getMe

# 2. MTProxy connection latency
# (измерение через Telegram Desktop debug logs)

# 3. Load test
for i in {1..100}; do
  curl -s tg://proxy?server=IP&port=8443&secret=... &
done
wait
```

---

### NFR-MTPROXY-002: Reliability

**Priority:** HIGH
**Status:** Planned

**Target:**
- Uptime: 99.5% (аналогично Xray)
- Recovery time: < 30 секунд после сбоя
- Auto-restart: ДА (Docker `unless-stopped`)

**Acceptance Criteria:**
- ✅ Docker healthcheck: TCP check на порту 8443 каждые 30 секунд
- ✅ Auto-restart при crash
- ✅ Graceful shutdown при `docker stop`
- ✅ Логирование всех crashes в `/opt/vless/logs/mtproxy/error.log`

**Healthcheck Configuration:**
```yaml
healthcheck:
  test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

---

### NFR-MTPROXY-003: Security

**Priority:** CRITICAL
**Status:** Planned

**Target:**
- Transport obfuscation: ENABLED по умолчанию
- Random padding: AVAILABLE (opt-in при установке)
- DPI resistance: Telegram трафик не обнаруживается как MTProto

**Acceptance Criteria:**
- ✅ All secrets generated with `dd` prefix (random padding)
- ✅ Transport obfuscation active (AES-256-CTR)
- ✅ Wireshark capture: трафик выглядит как случайный (не MTProto)
- ✅ fail2ban защита от brute-force
- ✅ Rate limiting через UFW (10 conn/min per IP)

**Security Testing:**
```bash
# 1. Wireshark packet capture
sudo tcpdump -i any port 8443 -w mtproxy_traffic.pcap

# 2. Analyze with Wireshark
# Verify: NO "MTProto" protocol detection, random-looking bytes

# 3. DPI simulation
# (use tools like nDPI to check protocol detection)
```

---

### NFR-MTPROXY-004: Usability

**Priority:** MEDIUM
**Status:** Planned

**Target:**
- Installation time: < 3 минуты (после `vless-install`)
- Client setup: < 1 минута (one-tap в Telegram)
- Documentation: COMPREHENSIVE (включая screenshots)

**Acceptance Criteria:**
- ✅ Interactive wizard с валидацией ввода
- ✅ Clear error messages при ошибках
- ✅ QR code генерация для простого подключения
- ✅ Help text в CLI: `vless-mtproxy --help`
- ✅ User guide в `/docs/mtproxy/user_guide.md`

**User Guide Structure:**
1. What is MTProxy?
2. Installation (with screenshots)
3. Client setup (Android, iOS, Desktop)
4. Troubleshooting (common issues)
5. FAQ

---

### NFR-MTPROXY-005: Compatibility

**Priority:** HIGH
**Status:** Planned

**Target:**
- Telegram clients: ALL official (Android, iOS, Desktop, Web)
- OS: Ubuntu 20.04+, Debian 10+ (аналогично VLESS)
- Docker: 20.10+

**Acceptance Criteria:**
- ✅ Testing matrix:
  | Client | Version | Status |
  |--------|---------|--------|
  | Telegram Android | 10.x+ | ✅ |
  | Telegram iOS | 10.x+ | ✅ |
  | Telegram Desktop | 4.x+ | ✅ |
  | Telegram Web | Latest | ✅ |

- ✅ All clients connect successfully via deep link
- ✅ Messages send/receive without errors
- ✅ Voice/video calls work через MTProxy (если поддерживается)

---

## 7. TECHNICAL ARCHITECTURE

### 7.1 Container Architecture

**Container Name:** `vless_mtproxy`

**Base Image:** Custom Dockerfile (alpine:latest + compiled MTProxy)

**Dockerfile:**
```dockerfile
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    openssl-dev \
    zlib-dev

# Clone and build MTProxy
WORKDIR /tmp
RUN git clone https://github.com/TelegramMessenger/MTProxy.git
WORKDIR /tmp/MTProxy
RUN make

# Final image
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    zlib \
    curl

# Copy compiled binary
COPY --from=builder /tmp/MTProxy/objs/bin/mtproto-proxy /usr/local/bin/

# Create non-root user
RUN adduser -D -s /sbin/nologin mtproxy

# Prepare directories
RUN mkdir -p /etc/mtproxy /var/log/mtproxy /var/lib/mtproxy

# Download Telegram proxy config (proxy-multi.conf and proxy-secret)
WORKDIR /etc/mtproxy
RUN curl -s https://core.telegram.org/getProxySecret -o proxy-secret && \
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# Expose ports
EXPOSE 8443 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD nc -z 127.0.0.1 8443 || exit 1

# Run as non-root user
USER mtproxy

# Default command (secret passed via environment variable)
CMD ["/usr/local/bin/mtproto-proxy", \
     "-u", "mtproxy", \
     "-p", "8888", \
     "-H", "8443", \
     "-S", "${MTPROXY_SECRET}", \
     "--aes-pwd", "/etc/mtproxy/proxy-secret", \
     "/etc/mtproxy/proxy-multi.conf", \
     "-M", "${MTPROXY_WORKERS:-1}"]
```

**Docker Compose Entry:**
```yaml
services:
  mtproxy:
    build:
      context: ./docker/mtproxy
      dockerfile: Dockerfile
    container_name: vless_mtproxy
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "8443:8443"                     # Public MTProxy port
      - "127.0.0.1:8888:8888"           # Stats endpoint (localhost only)
    volumes:
      - /opt/vless/config/mtproxy:/etc/mtproxy:ro
      - /opt/vless/logs/mtproxy:/var/log/mtproxy
      - /opt/vless/data/mtproxy-stats:/var/lib/mtproxy
    environment:
      - MTPROXY_SECRET=${MTPROXY_SECRET}
      - MTPROXY_WORKERS=${MTPROXY_WORKERS:-1}
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
```

### 7.2 File Structure

```
/opt/vless/
├── config/
│   └── mtproxy/
│       ├── mtproxy_secrets.json    # Secrets database
│       ├── proxy-secret            # Telegram AES secret (downloaded)
│       └── proxy-multi.conf        # Telegram DC config (downloaded)
│
├── data/
│   ├── mtproxy/
│   │   ├── mtproxy_link.txt        # Deep link
│   │   └── mtproxy_qr.png          # QR code
│   └── mtproxy-stats/              # MTProxy statistics
│
├── logs/
│   └── mtproxy/
│       ├── access.log              # Access logs (optional)
│       └── error.log               # Error logs (for fail2ban)
│
└── scripts/
    ├── vless-mtproxy-setup         # Setup wizard
    └── vless-mtproxy               # Management CLI

/etc/fail2ban/
├── jail.d/
│   └── vless-mtproxy.conf          # MTProxy jail
└── filter.d/
    └── vless-mtproxy.conf          # MTProxy filter
```

### 7.3 Network Configuration

**Port Allocation:**

| Service | Port | Protocol | Binding | Purpose |
|---------|------|----------|---------|---------|
| **Existing Services** | | | | |
| HAProxy (VLESS/Reverse) | 443 | TCP | 0.0.0.0 | VLESS Reality + Reverse Proxy SNI routing |
| HAProxy (SOCKS5) | 1080 | TCP | 0.0.0.0 | SOCKS5 TLS termination |
| HAProxy (HTTP) | 8118 | TCP | 0.0.0.0 | HTTP TLS termination |
| HAProxy Stats | 9000 | HTTP | 127.0.0.1 | HAProxy statistics |
| Xray VLESS | 8443 | TCP | 127.0.0.1 | VLESS Reality inbound (internal) |
| Xray SOCKS5 | 10800 | TCP | 127.0.0.1 | SOCKS5 plaintext (internal) |
| Xray HTTP | 18118 | TCP | 127.0.0.1 | HTTP plaintext (internal) |
| Nginx Reverse Proxy | 9443-9452 | HTTPS | 127.0.0.1 | Reverse proxy backends |
| **NEW: MTProxy** | | | | |
| MTProxy Public | 8443 | TCP | 0.0.0.0 | MTProto proxy ← NEW |
| MTProxy Stats | 8888 | HTTP | 127.0.0.1 | Statistics endpoint ← NEW |

**Port Conflict Resolution:**
- MTProxy default: 8443
- Xray VLESS internal: 8443 (localhost only - NO CONFLICT)
- Reason: Different bindings (0.0.0.0 vs 127.0.0.1)
- Alternative MTProxy ports if needed: 8444, 8445, 2053

**UFW Rules (after installation):**
```bash
# Existing rules
sudo ufw allow 443/tcp comment 'VLESS Reality + Reverse Proxy'
sudo ufw limit 1080/tcp comment 'SOCKS5 TLS'
sudo ufw limit 8118/tcp comment 'HTTP TLS'

# NEW: MTProxy rule
sudo ufw limit 8443/tcp comment 'MTProxy (Telegram)'
```

### 7.4 Security Architecture

**Secret Management:**

```json
// /opt/vless/config/mtproxy/mtproxy_secrets.json
{
  "secrets": [
    {
      "id": "secret-abc123",
      "value": "dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c",
      "padding_enabled": true,
      "created_at": "2025-11-07T12:00:00Z",
      "created_by": "admin",
      "active": true,
      "description": "Default secret with padding"
    }
  ],
  "metadata": {
    "last_modified": "2025-11-07T12:00:00Z",
    "version": "6.0.0"
  }
}
```

**File Permissions:**
- `mtproxy_secrets.json`: 600 (root:root)
- `proxy-secret`: 600 (root:root)
- `proxy-multi.conf`: 644 (root:root)
- Log files: 640 (root:adm)

**fail2ban Configuration:**

```ini
# /etc/fail2ban/jail.d/vless-mtproxy.conf
[vless-mtproxy]
enabled = true
port = 8443
protocol = tcp
filter = vless-mtproxy
logpath = /opt/vless/logs/mtproxy/error.log
maxretry = 5
bantime = 3600
findtime = 600
action = iptables-multiport[name=MTProxy, port="8443", protocol=tcp]
```

```ini
# /etc/fail2ban/filter.d/vless-mtproxy.conf
[Definition]
# Match MTProxy authentication failures
failregex = ^.*authentication.*failed.*<HOST>.*$
            ^.*invalid.*secret.*<HOST>.*$
            ^.*connection.*rejected.*<HOST>.*$

ignoreregex =
```

---

## 8. IMPLEMENTATION PHASES

### Phase 1: Core Infrastructure (Week 1)

**Goal:** Создать базовую инфраструктуру MTProxy

**Tasks:**
1. ✅ Создать Dockerfile для MTProxy
   - Базовый image: alpine:latest
   - Компиляция из GitHub
   - Healthcheck

2. ✅ Создать docker-compose.yml entry
   - Port mapping: 8443, 8888
   - Volume mounts
   - Environment variables

3. ✅ Создать структуру файлов
   - `/opt/vless/config/mtproxy/`
   - `/opt/vless/logs/mtproxy/`
   - `/opt/vless/data/mtproxy/`

4. ✅ Создать базовую библиотеку
   - `lib/mtproxy_manager.sh`
   - Functions: `init_mtproxy()`, `start_mtproxy()`, `stop_mtproxy()`

**Deliverable:** Работающий MTProxy контейнер (manual start)

**Testing:**
```bash
# Test manual start
docker-compose up -d mtproxy

# Test connectivity
nc -zv localhost 8443

# Test stats endpoint
curl http://localhost:8888/stats
```

---

### Phase 2: Secret Management (Week 2)

**Goal:** Реализовать управление секретами

**Tasks:**
1. ✅ Создать `lib/mtproxy_secret_manager.sh`
   - `generate_secret()`
   - `add_secret()`
   - `list_secrets()`
   - `remove_secret()`
   - `regenerate_secret()`

2. ✅ Создать JSON schema для `mtproxy_secrets.json`
   - Валидация через `jq`
   - Atomic writes (temp file + mv)

3. ✅ Создать CLI: `scripts/vless-mtproxy`
   - Subcommands: add-secret, list-secrets, remove-secret, regenerate-secret
   - Symlink в `/usr/local/bin/`

4. ✅ Интеграция с Docker
   - Передача секрета через environment variable
   - Auto-restart контейнера при изменении секрета

**Deliverable:** CLI для управления секретами

**Testing:**
```bash
# Test secret generation
sudo vless-mtproxy add-secret --with-padding

# Test list
sudo vless-mtproxy list-secrets

# Test remove
sudo vless-mtproxy remove-secret <secret>

# Verify container restart
docker logs vless_mtproxy | grep "secret"
```

---

### Phase 3: Client Configuration (Week 2)

**Goal:** Генерация клиентских конфигураций

**Tasks:**
1. ✅ Реализовать `generate_deep_link()`
   - Format: `tg://proxy?server=IP&port=PORT&secret=SECRET`
   - Сохранение в `mtproxy_link.txt`

2. ✅ Реализовать `generate_qr_code()`
   - Dependency: `qrencode` package
   - Output: PNG 300x300px
   - Encoding: deep link

3. ✅ Создать CLI subcommand: `show-config`
   - Display deep link
   - Display QR code path
   - Optional: display QR in terminal (ASCII art)

4. ✅ Интеграция с `add-secret`
   - Автоматическая генерация конфигов при создании секрета
   - Output в stdout

**Deliverable:** Автоматическая генерация клиентских конфигов

**Testing:**
```bash
# Test config generation
sudo vless-mtproxy add-secret --with-padding

# Verify files created
ls -la /opt/vless/data/mtproxy/
# Should see: mtproxy_link.txt, mtproxy_qr.png

# Test show-config
sudo vless-mtproxy show-config
```

---

### Phase 4: Installation Wizard (Week 3)

**Goal:** Opt-in установка через wizard

**Tasks:**
1. ✅ Создать `scripts/vless-mtproxy-setup`
   - Interactive prompts
   - Валидация ввода
   - Port conflict check

2. ✅ Реализовать setup flow:
   - Prompt: Install MTProxy? [y/N]
   - Prompt: Port [8443]
   - Prompt: Workers [1]
   - Prompt: Enable padding? [Y/n]
   - Generate secret
   - Add UFW rule
   - Create fail2ban jail
   - Start Docker container
   - Generate client configs
   - Display results

3. ✅ Создать `scripts/vless-mtproxy-uninstall`
   - Stop container
   - Remove UFW rule
   - Remove fail2ban jail
   - Cleanup files (optional)
   - Confirmation prompt

4. ✅ Интеграция с `vless-install` (опционально)
   - Добавить prompt в конце основной установки
   - "Would you like to install MTProxy? [y/N]"

**Deliverable:** Полностью автоматизированная установка

**Testing:**
```bash
# Test installation
sudo vless-mtproxy-setup
# Follow prompts, verify all steps complete

# Test uninstallation
sudo vless-mtproxy-uninstall
# Verify container stopped, UFW rule removed
```

---

### Phase 5: fail2ban & UFW (Week 3)

**Goal:** Интеграция с fail2ban и UFW

**Tasks:**
1. ✅ Создать fail2ban jail
   - File: `/etc/fail2ban/jail.d/vless-mtproxy.conf`
   - Port: 8443
   - Maxretry: 5
   - Bantime: 3600

2. ✅ Создать fail2ban filter
   - File: `/etc/fail2ban/filter.d/vless-mtproxy.conf`
   - Regex: MTProxy authentication errors

3. ✅ Добавить UFW rule management
   - Function: `add_mtproxy_ufw_rule()`
   - Function: `remove_mtproxy_ufw_rule()`
   - Rate limiting: 10 conn/min per IP

4. ✅ Тестирование fail2ban
   - Симуляция brute-force атаки
   - Проверка бана IP
   - Проверка unban через fail2ban-client

**Deliverable:** fail2ban защита MTProxy

**Testing:**
```bash
# Test fail2ban filter
fail2ban-regex /opt/vless/logs/mtproxy/error.log \
  /etc/fail2ban/filter.d/vless-mtproxy.conf

# Simulate attack (5 failed connections)
for i in {1..6}; do
  telnet localhost 8443 <<< "INVALID_DATA"
done

# Check ban
sudo fail2ban-client status vless-mtproxy
# Should show banned IP

# Test UFW rule
sudo ufw status | grep 8443
# Should show: 8443/tcp LIMIT Anywhere
```

---

### Phase 6: Monitoring & Status (Week 4)

**Goal:** Интеграция мониторинга в `vless status`

**Tasks:**
1. ✅ Реализовать `get_mtproxy_stats()`
   - Curl: `curl -s http://localhost:8888/stats`
   - Parse: active connections, uptime, total connections

2. ✅ Интеграция с `vless status`
   - Добавить секцию "MTProxy Status (v6.0)"
   - Display: container status, port, active connections, uptime

3. ✅ Создать CLI subcommand: `stats`
   - Display detailed metrics
   - Optional: live mode (`--live`, refresh every 5s)

4. ✅ Логирование
   - Rotate logs: `/etc/logrotate.d/vless-mtproxy`
   - Error log для fail2ban
   - Optional: access log (privacy consideration)

**Deliverable:** Полная интеграция мониторинга

**Testing:**
```bash
# Test status display
sudo vless status
# Should show MTProxy section with metrics

# Test stats command
sudo vless-mtproxy stats

# Test live mode
sudo vless-mtproxy stats --live
# Should refresh every 5 seconds
```

---

### Phase 7: Documentation & Testing (Week 4)

**Goal:** Comprehensive документация и тестирование

**Tasks:**
1. ✅ Написать user guide
   - File: `docs/mtproxy/user_guide.md`
   - Sections: Installation, Client Setup, Troubleshooting

2. ✅ Написать developer docs
   - File: `docs/mtproxy/developer_guide.md`
   - Sections: Architecture, API, Testing

3. ✅ Обновить основной README.md
   - Добавить секцию "MTProxy Support (v6.0)"
   - Quick start guide

4. ✅ Создать test suite
   - Unit tests: secret generation, config generation
   - Integration tests: Docker container, fail2ban, UFW
   - E2E test: Telegram client connection

5. ✅ Обновить CHANGELOG.md
   - Секция v6.0: MTProxy Support

**Deliverable:** Полная документация + тесты

**Testing:**
```bash
# Run test suite
sudo bash tests/test_mtproxy.sh

# E2E test (manual)
# 1. Install MTProxy: sudo vless-mtproxy-setup
# 2. Open Telegram app
# 3. Tap deep link: tg://proxy?server=...
# 4. Verify connection: send test message
```

---

## 9. TESTING STRATEGY

### 9.1 Unit Tests

**Scope:** Отдельные функции без внешних зависимостей

**Test Cases:**

| Test ID | Function | Test Case | Expected Result |
|---------|----------|-----------|-----------------|
| UT-001 | `generate_secret()` | Generate secret without padding | 32-char hex string |
| UT-002 | `generate_secret()` | Generate secret with padding | 34-char hex string (dd prefix) |
| UT-003 | `validate_secret()` | Valid secret (32 chars) | Return 0 (success) |
| UT-004 | `validate_secret()` | Invalid secret (30 chars) | Return 1 (error) |
| UT-005 | `generate_deep_link()` | Valid IP, port, secret | tg://proxy?server=... |
| UT-006 | `parse_mtproxy_stats()` | Valid stats JSON | Parsed metrics object |

**Test Script:** `tests/unit/test_mtproxy_functions.sh`

```bash
#!/bin/bash
source /opt/vless/lib/mtproxy_secret_manager.sh

# UT-001: Generate secret without padding
test_generate_secret_no_padding() {
    local secret=$(generate_secret false)
    [[ ${#secret} -eq 32 ]] || { echo "FAIL: UT-001"; return 1; }
    echo "PASS: UT-001"
}

# UT-002: Generate secret with padding
test_generate_secret_with_padding() {
    local secret=$(generate_secret true)
    [[ ${#secret} -eq 34 ]] || { echo "FAIL: UT-002"; return 1; }
    [[ $secret == dd* ]] || { echo "FAIL: UT-002 (no dd prefix)"; return 1; }
    echo "PASS: UT-002"
}

# Run all tests
test_generate_secret_no_padding
test_generate_secret_with_padding
```

---

### 9.2 Integration Tests

**Scope:** Взаимодействие между компонентами (Docker, UFW, fail2ban)

**Test Cases:**

| Test ID | Component | Test Case | Expected Result |
|---------|-----------|-----------|-----------------|
| IT-001 | Docker | Start MTProxy container | Container status: running |
| IT-002 | Docker | Healthcheck passes | Health: healthy (after 10s) |
| IT-003 | UFW | Add MTProxy rule | Rule visible in `ufw status` |
| IT-004 | fail2ban | Jail created | Jail listed in `fail2ban-client status` |
| IT-005 | fail2ban | Ban after 5 failures | IP banned (check `iptables`) |
| IT-006 | Stats API | Fetch stats | HTTP 200, valid JSON |

**Test Script:** `tests/integration/test_mtproxy_integration.sh`

```bash
#!/bin/bash

# IT-001: Start MTProxy container
test_docker_start() {
    docker-compose up -d mtproxy
    sleep 5
    local status=$(docker inspect -f '{{.State.Status}}' vless_mtproxy)
    [[ $status == "running" ]] || { echo "FAIL: IT-001"; return 1; }
    echo "PASS: IT-001"
}

# IT-002: Healthcheck passes
test_docker_healthcheck() {
    sleep 15  # Wait for healthcheck
    local health=$(docker inspect -f '{{.State.Health.Status}}' vless_mtproxy)
    [[ $health == "healthy" ]] || { echo "FAIL: IT-002"; return 1; }
    echo "PASS: IT-002"
}

# IT-003: UFW rule added
test_ufw_rule() {
    sudo ufw status | grep -q "8443/tcp" || { echo "FAIL: IT-003"; return 1; }
    echo "PASS: IT-003"
}

# IT-006: Stats API
test_stats_api() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/stats)
    [[ $response == "200" ]] || { echo "FAIL: IT-006"; return 1; }
    echo "PASS: IT-006"
}

# Run all tests
test_docker_start
test_docker_healthcheck
test_ufw_rule
test_stats_api
```

---

### 9.3 End-to-End Tests

**Scope:** Полный цикл от установки до подключения Telegram клиента

**Test Cases:**

| Test ID | Scenario | Steps | Expected Result |
|---------|----------|-------|-----------------|
| E2E-001 | Fresh install | 1. Run vless-mtproxy-setup<br>2. Follow prompts<br>3. Verify container | MTProxy running, secret generated |
| E2E-002 | Client connection (Android) | 1. Copy deep link<br>2. Open in Telegram<br>3. Tap "Connect" | Proxy connected, green checkmark |
| E2E-003 | Message send | 1. Send test message<br>2. Check delivery | Message sent successfully |
| E2E-004 | fail2ban ban | 1. 6 failed connections<br>2. Check ban status | IP banned for 1 hour |
| E2E-005 | Secret regeneration | 1. Regenerate secret<br>2. Old link fails<br>3. New link works | Old secret invalid, new secret works |

**Test Script:** `tests/e2e/test_mtproxy_e2e.sh`

```bash
#!/bin/bash

# E2E-001: Fresh install
test_fresh_install() {
    echo "=== E2E-001: Fresh Install ==="

    # Run installation wizard (non-interactive)
    MTPROXY_PORT=8443 \
    MTPROXY_WORKERS=1 \
    MTPROXY_PADDING=yes \
    sudo vless-mtproxy-setup --non-interactive

    # Verify container running
    docker ps | grep -q vless_mtproxy || { echo "FAIL: Container not running"; return 1; }

    # Verify secret generated
    [[ -f /opt/vless/config/mtproxy/mtproxy_secrets.json ]] || { echo "FAIL: Secrets file missing"; return 1; }

    echo "PASS: E2E-001"
}

# E2E-002: Client connection (manual test)
test_client_connection() {
    echo "=== E2E-002: Client Connection (MANUAL) ==="
    echo "Steps:"
    echo "1. Copy deep link: $(cat /opt/vless/data/mtproxy/mtproxy_link.txt)"
    echo "2. Open Telegram app on Android/iOS"
    echo "3. Tap the deep link"
    echo "4. Tap 'Connect' button"
    echo "5. Verify green checkmark appears"
    echo ""
    read -p "Did the proxy connect successfully? (y/n): " result
    [[ $result == "y" ]] || { echo "FAIL: E2E-002"; return 1; }
    echo "PASS: E2E-002"
}

# E2E-003: Message send (manual test)
test_message_send() {
    echo "=== E2E-003: Message Send (MANUAL) ==="
    echo "Steps:"
    echo "1. Send a test message in Telegram"
    echo "2. Verify message is delivered (check marks)"
    echo ""
    read -p "Was the message sent successfully? (y/n): " result
    [[ $result == "y" ]] || { echo "FAIL: E2E-003"; return 1; }
    echo "PASS: E2E-003"
}

# Run all E2E tests
test_fresh_install
test_client_connection
test_message_send
```

**Note:** E2E-002 и E2E-003 требуют manual testing, так как автоматизация Telegram клиента сложна.

---

### 9.4 Compatibility Testing

**Scope:** Проверка совместимости с разными Telegram клиентами

**Test Matrix:**

| Client | Platform | Version | Status | Notes |
|--------|----------|---------|--------|-------|
| Telegram Android | Android 10+ | 10.x+ | ⏳ TO TEST | Official app |
| Telegram iOS | iOS 14+ | 10.x+ | ⏳ TO TEST | Official app |
| Telegram Desktop | Windows 10+ | 4.x+ | ⏳ TO TEST | Qt-based |
| Telegram Desktop | macOS 11+ | 4.x+ | ⏳ TO TEST | Qt-based |
| Telegram Desktop | Ubuntu 20.04+ | 4.x+ | ⏳ TO TEST | AppImage |
| Telegram Web | Chrome 90+ | Latest | ⏳ TO TEST | Browser-based |
| Telegram Web | Firefox 88+ | Latest | ⏳ TO TEST | Browser-based |

**Test Procedure (per client):**
1. Install/open client
2. Tap deep link OR scan QR code
3. Verify proxy added to settings
4. Enable proxy
5. Send test message
6. Make voice call (if supported)
7. Verify connection stable for 5 minutes

**Success Criteria:**
- ✅ Proxy connects without errors
- ✅ Messages send/receive correctly
- ✅ Voice calls work (if applicable)
- ✅ Stable connection for 5+ minutes

---

### 9.5 Performance Testing

**Scope:** Измерение latency, throughput, resource usage

**Test Cases:**

| Test ID | Metric | Method | Target | Acceptance |
|---------|--------|--------|--------|------------|
| PERF-001 | Latency | Ping через MTProxy | < 10ms overhead | Измерить p50, p95, p99 |
| PERF-002 | Throughput | iperf3 через MTProxy | ≥ 100 Mbps | Single worker |
| PERF-003 | CPU usage | top/htop при 50 conn | < 5% | Monitor for 5 min |
| PERF-004 | Memory | docker stats | < 100 MB | Resident memory |
| PERF-005 | Concurrent | 100 clients | All connect | No errors |

**Performance Test Script:** `tests/performance/test_mtproxy_performance.sh`

```bash
#!/bin/bash

# PERF-001: Latency measurement
test_latency() {
    echo "=== PERF-001: Latency Measurement ==="

    # Baseline: direct Telegram connection
    echo "Baseline (direct):"
    for i in {1..10}; do
        curl -s -w "%{time_total}s\n" https://api.telegram.org/bot<TOKEN>/getMe -o /dev/null
    done | awk '{sum+=$1} END {print "Average:", sum/NR, "s"}'

    # MTProxy connection (manual test via Telegram client logs)
    echo "MTProxy (manual measurement required via client logs)"
}

# PERF-002: Throughput test
test_throughput() {
    echo "=== PERF-002: Throughput Test ==="

    # Run iperf3 server inside MTProxy container
    docker exec vless_mtproxy iperf3 -s -D

    # Run iperf3 client from host
    iperf3 -c localhost -p 8443 -t 30

    # Cleanup
    docker exec vless_mtproxy pkill iperf3
}

# PERF-003: CPU usage
test_cpu_usage() {
    echo "=== PERF-003: CPU Usage ==="

    # Monitor for 5 minutes
    docker stats vless_mtproxy --no-stream --format "table {{.Name}}\t{{.CPUPerc}}" &
    sleep 300

    # Get average
    echo "Check average CPU usage from logs above"
}

# PERF-004: Memory usage
test_memory_usage() {
    echo "=== PERF-004: Memory Usage ==="

    docker stats vless_mtproxy --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
}

# Run performance tests
test_latency
test_throughput
test_cpu_usage
test_memory_usage
```

---

### 9.6 Security Testing

**Scope:** Проверка transport obfuscation, fail2ban, DPI resistance

**Test Cases:**

| Test ID | Security Aspect | Method | Expected Result |
|---------|----------------|--------|-----------------|
| SEC-001 | Transport obfuscation | Wireshark capture | No MTProto detection |
| SEC-002 | DPI resistance | nDPI analysis | Protocol: "Unknown" |
| SEC-003 | fail2ban ban | Brute-force simulation | IP banned after 5 failures |
| SEC-004 | UFW rate limit | Connection flood | Connections limited to 10/min |
| SEC-005 | Secret validation | Invalid secret test | Connection rejected |

**Security Test Script:** `tests/security/test_mtproxy_security.sh`

```bash
#!/bin/bash

# SEC-001: Wireshark capture
test_wireshark_capture() {
    echo "=== SEC-001: Wireshark Capture ==="

    # Start packet capture
    sudo tcpdump -i any port 8443 -w /tmp/mtproxy_traffic.pcap &
    TCPDUMP_PID=$!

    # Connect Telegram client (manual)
    echo "Connect Telegram client now..."
    read -p "Press Enter after sending a few messages: "

    # Stop capture
    sudo kill $TCPDUMP_PID

    # Analyze with tshark
    echo "Analyzing capture..."
    tshark -r /tmp/mtproxy_traffic.pcap -Y "mtproto" | wc -l
    # Should be 0 (no MTProto detected)

    echo "Manual verification: Open /tmp/mtproxy_traffic.pcap in Wireshark"
    echo "Verify: NO 'MTProto' protocol in packets"
}

# SEC-002: DPI resistance
test_dpi_resistance() {
    echo "=== SEC-002: DPI Resistance ==="

    # Use nDPI for protocol detection
    sudo ndpiReader -i any -f "port 8443" -s 60
    # Should show: "Unknown" protocol
}

# SEC-003: fail2ban test
test_fail2ban() {
    echo "=== SEC-003: fail2ban Test ==="

    # Simulate 6 failed connections
    for i in {1..6}; do
        echo "INVALID_SECRET" | nc localhost 8443
        sleep 1
    done

    # Check ban status
    sudo fail2ban-client status vless-mtproxy
    # Should show 1 banned IP
}

# SEC-004: UFW rate limit
test_ufw_rate_limit() {
    echo "=== SEC-004: UFW Rate Limit ==="

    # Flood connections (20 in 1 minute)
    for i in {1..20}; do
        nc -zv localhost 8443
        sleep 3
    done

    # Check UFW logs
    sudo tail -n 50 /var/log/ufw.log | grep "8443" | grep "LIMIT"
    # Should show blocked connections after 10th
}

# Run security tests
test_wireshark_capture
test_dpi_resistance
test_fail2ban
test_ufw_rate_limit
```

---

## 10. RISK ASSESSMENT

### 10.1 Technical Risks

| Risk ID | Risk | Probability | Impact | Mitigation |
|---------|------|------------|--------|------------|
| RISK-001 | MTProxy Docker build fails | LOW | HIGH | Test on multiple platforms (Ubuntu 20.04/22.04, Debian 10/11) |
| RISK-002 | Port 8443 conflict with existing services | MEDIUM | MEDIUM | Port validation before installation, allow custom port selection |
| RISK-003 | Telegram blocks MTProxy IP | MEDIUM | HIGH | Use promoted channel feature (future), rotate IPs if needed |
| RISK-004 | Transport obfuscation bypassed by DPI | LOW | HIGH | Monitor DPI detection tools (nDPI, etc.), update obfuscation if needed |
| RISK-005 | fail2ban false positives | LOW | MEDIUM | Tuning: increase maxretry to 10, review filter regex |
| RISK-006 | Performance degradation | LOW | MEDIUM | Benchmark before release, optimize workers setting |

### 10.2 Operational Risks

| Risk ID | Risk | Probability | Impact | Mitigation |
|---------|------|------------|--------|------------|
| RISK-007 | Users don't understand MTProxy setup | MEDIUM | MEDIUM | Clear user guide with screenshots, QR code for simplicity |
| RISK-008 | Telegram client version incompatibility | LOW | MEDIUM | Test with latest client versions, document minimum versions |
| RISK-009 | MTProxy config updates break compatibility | LOW | HIGH | Pin MTProxy version in Dockerfile, test before updating |
| RISK-010 | Log files fill disk space | MEDIUM | LOW | Implement log rotation, set max log size |

### 10.3 Security Risks

| Risk ID | Risk | Probability | Impact | Mitigation |
|---------|------|------------|--------|------------|
| RISK-011 | Secret leaked via logs/configs | LOW | HIGH | Mask secrets in CLI output, 600 permissions on config files |
| RISK-012 | DDoS attack on MTProxy port | MEDIUM | MEDIUM | UFW rate limiting (10 conn/min), fail2ban protection |
| RISK-013 | MTProxy vulnerability in upstream | LOW | CRITICAL | Monitor GitHub releases, subscribe to security advisories |
| RISK-014 | Unauthorized access via brute-force | MEDIUM | MEDIUM | fail2ban after 5 failures, strong secret generation (16 bytes) |

### 10.4 Risk Summary

**HIGH Priority Risks (require immediate attention):**
- RISK-001: Docker build failures (TEST extensively)
- RISK-003: Telegram IP blocks (MONITOR, prepare rotation strategy)
- RISK-004: DPI bypass failures (MONITOR detection tools)
- RISK-013: Upstream vulnerabilities (SUBSCRIBE to advisories)

**Action Plan:**
1. Week 1: Test Docker build on 4 platforms (Ubuntu 20.04/22.04, Debian 10/11)
2. Week 2: Setup monitoring for Telegram IP blocks (check connectivity daily)
3. Week 3: DPI testing with nDPI, Wireshark, verify obfuscation
4. Ongoing: Subscribe to GitHub notifications for MTProxy releases

---

## 11. MIGRATION & ROLLBACK

### 11.1 Migration Plan (Existing Installations)

**Scenario:** User has VLESS v5.33 installed, wants to add MTProxy

**Migration Steps:**

1. **Pre-migration Checks**
   ```bash
   # Check current version
   vless --version
   # Should be v5.33 or later

   # Check port 8443 availability
   sudo ss -tulnp | grep 8443
   # Should be empty (no conflict)

   # Check Docker version
   docker --version
   # Should be 20.10+
   ```

2. **Backup Current Configuration**
   ```bash
   sudo tar -czf /tmp/vless_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
     /opt/vless/config/ \
     /opt/vless/data/
   ```

3. **Update Codebase**
   ```bash
   cd /opt/vless
   git fetch origin
   git checkout feature/mtproxy-integration
   git pull
   ```

4. **Run MTProxy Setup**
   ```bash
   sudo vless-mtproxy-setup
   # Follow interactive prompts
   ```

5. **Verification**
   ```bash
   # Check container status
   docker ps | grep mtproxy

   # Check stats
   curl http://localhost:8888/stats

   # Check UFW rule
   sudo ufw status | grep 8443
   ```

6. **Post-migration Testing**
   ```bash
   # Test client connection
   # 1. Copy deep link
   cat /opt/vless/data/mtproxy/mtproxy_link.txt

   # 2. Open in Telegram app, verify connection
   ```

**Rollback if Migration Fails:**
```bash
# Stop MTProxy container
docker-compose stop mtproxy

# Remove UFW rule
sudo ufw delete limit 8443/tcp

# Remove fail2ban jail
sudo rm /etc/fail2ban/jail.d/vless-mtproxy.conf
sudo fail2ban-client reload

# Restore backup
sudo tar -xzf /tmp/vless_backup_*.tar.gz -C /

# Restart existing services
docker-compose restart
```

### 11.2 Rollback Plan (v6.0 → v5.33)

**Scenario:** MTProxy causes issues, need to revert to v5.33

**Rollback Steps:**

1. **Stop MTProxy Services**
   ```bash
   # Stop container
   docker-compose stop mtproxy

   # Remove from docker-compose.yml
   sudo sed -i '/mtproxy:/,/^$/d' /opt/vless/docker-compose.yml
   ```

2. **Remove MTProxy Configurations**
   ```bash
   # Remove UFW rule
   sudo ufw delete limit 8443/tcp

   # Remove fail2ban jail
   sudo rm /etc/fail2ban/jail.d/vless-mtproxy.conf
   sudo rm /etc/fail2ban/filter.d/vless-mtproxy.conf
   sudo fail2ban-client reload

   # Remove MTProxy files (optional - keep for future)
   # sudo rm -rf /opt/vless/config/mtproxy/
   # sudo rm -rf /opt/vless/logs/mtproxy/
   # sudo rm -rf /opt/vless/data/mtproxy/
   ```

3. **Revert Codebase**
   ```bash
   cd /opt/vless
   git checkout master
   git pull
   ```

4. **Restart Existing Services**
   ```bash
   docker-compose restart
   ```

5. **Verification**
   ```bash
   # Check VLESS still works
   sudo vless status

   # Verify no MTProxy references
   docker ps | grep mtproxy
   # Should be empty
   ```

**Data Preservation:**
- MTProxy secrets preserved in `/opt/vless/config/mtproxy/mtproxy_secrets.json`
- Client configs preserved in `/opt/vless/data/mtproxy/`
- Can re-enable MTProxy later without re-generating secrets

### 11.3 Uninstallation (Complete MTProxy Removal)

**Scenario:** User wants to completely remove MTProxy

**Uninstall Script:** `vless-mtproxy-uninstall`

```bash
#!/bin/bash

echo "=== MTProxy Uninstallation ==="
echo "This will:"
echo "  1. Stop MTProxy container"
echo "  2. Remove Docker image"
echo "  3. Remove UFW rule"
echo "  4. Remove fail2ban jail"
echo "  5. Optionally delete configuration files"
echo ""
read -p "Continue? [y/N]: " confirm
[[ $confirm == "y" ]] || exit 0

# 1. Stop container
echo "Stopping MTProxy container..."
docker-compose stop mtproxy
docker-compose rm -f mtproxy

# 2. Remove image
echo "Removing Docker image..."
docker rmi vless_mtproxy

# 3. Remove UFW rule
echo "Removing UFW rule..."
sudo ufw delete limit 8443/tcp

# 4. Remove fail2ban jail
echo "Removing fail2ban jail..."
sudo rm /etc/fail2ban/jail.d/vless-mtproxy.conf
sudo rm /etc/fail2ban/filter.d/vless-mtproxy.conf
sudo fail2ban-client reload

# 5. Remove configs (optional)
read -p "Delete configuration files? (secrets will be lost) [y/N]: " delete_config
if [[ $delete_config == "y" ]]; then
    echo "Deleting configuration files..."
    sudo rm -rf /opt/vless/config/mtproxy/
    sudo rm -rf /opt/vless/logs/mtproxy/
    sudo rm -rf /opt/vless/data/mtproxy/
fi

echo "MTProxy uninstalled successfully!"
```

---

## 12. REFERENCES

### 12.1 Official Documentation

**MTProto Protocol:**
- Homepage: https://core.telegram.org/mtproto
- Transports: https://core.telegram.org/mtproto/mtproto-transports
- Security Guidelines: https://core.telegram.org/mtproto/security_guidelines

**MTProxy:**
- GitHub Repository: https://github.com/TelegramMessenger/MTProxy
- README: https://github.com/TelegramMessenger/MTProxy/blob/master/README.md

**Telegram API:**
- Bot API: https://core.telegram.org/bots/api
- Deep Links: https://core.telegram.org/api/links

### 12.2 Community Resources

**Tutorials:**
- MTProxy Setup Guide: https://gist.github.com/rameerez/8debfc790e965009ca2949c3b4580b91
- Systemd Service: https://github.com/aquigni/MTProxySystemd

**Tools:**
- MTProxybot Registration: https://t.me/MTProxybot
- QR Code Generator: https://github.com/fukuchi/libqrencode

### 12.3 Related VLESS Project Documents

**PRD (Product Requirements Document):**
- Summary: `docs/prd/00_summary.md`
- Architecture: `docs/prd/04_architecture.md`
- Testing: `docs/prd/05_testing.md`

**VLESS Core:**
- CHANGELOG: `CHANGELOG.md`
- README: `README.md`
- CLAUDE: `CLAUDE.md` (Project Memory)

**External Proxy (similar feature):**
- Integration Plan: `docs/prd/04_architecture.md` (Section 4.8)

### 12.4 Technical Dependencies

**Docker Images:**
- alpine:latest (base image)
- TelegramMessenger/MTProxy (source code)

**System Packages:**
- openssl-dev
- zlib-dev
- build-base
- qrencode (QR code generation)

**Existing VLESS Components:**
- lib/orchestrator.sh (installation orchestration)
- lib/ufw_manager.sh (firewall management)
- lib/fail2ban_manager.sh (fail2ban configuration)
- lib/docker_compose_manager.sh (Docker management)

---

## APPENDICES

### Appendix A: Glossary

| Term | Definition |
|------|------------|
| **MTProto** | Mobile Protocol - Telegram's proprietary protocol для клиент-сервер коммуникации |
| **MTProxy** | Официальный прокси-сервер Telegram для туннелирования MTProto трафика |
| **Transport Obfuscation** | AES-256-CTR шифрование для маскировки MTProto трафика под случайные данные |
| **Random Padding** | Добавление случайных байтов в пакеты для изменения размеров (анти-DPI) |
| **Deep Link** | URL формат для автоматического подключения к прокси: `tg://proxy?...` |
| **DPI** | Deep Packet Inspection - анализ содержимого пакетов провайдером |
| **Secret** | 16-byte ключ для аутентификации клиента в MTProxy |
| **Promoted Channel** | Канал Telegram, который отображается у пользователей прокси (опция) |

### Appendix B: CLI Commands Reference

```bash
# MTProxy Setup
vless-mtproxy-setup              # Interactive installation wizard
vless-mtproxy-uninstall          # Remove MTProxy completely

# Secret Management
vless-mtproxy add-secret [--with-padding]
vless-mtproxy list-secrets
vless-mtproxy remove-secret <secret>
vless-mtproxy regenerate-secret <old-secret>

# Configuration
vless-mtproxy show-config [<secret>]
vless-mtproxy set-port <port>
vless-mtproxy set-workers <count>

# Monitoring
vless-mtproxy stats [--live]
vless status  # Shows MTProxy section

# Docker Operations
docker-compose up -d mtproxy
docker-compose stop mtproxy
docker-compose restart mtproxy
docker logs vless_mtproxy

# fail2ban
sudo fail2ban-client status vless-mtproxy
sudo fail2ban-client unban <IP>

# UFW
sudo ufw status | grep 8443
sudo ufw delete limit 8443/tcp
```

### Appendix C: File Locations

```
/opt/vless/
├── config/mtproxy/
│   ├── mtproxy_secrets.json
│   ├── proxy-secret
│   └── proxy-multi.conf
├── data/mtproxy/
│   ├── mtproxy_link.txt
│   └── mtproxy_qr.png
├── logs/mtproxy/
│   └── error.log
├── scripts/
│   ├── vless-mtproxy-setup
│   ├── vless-mtproxy-uninstall
│   └── vless-mtproxy
└── lib/
    ├── mtproxy_manager.sh
    └── mtproxy_secret_manager.sh

/etc/fail2ban/
├── jail.d/vless-mtproxy.conf
└── filter.d/vless-mtproxy.conf

/usr/local/bin/
├── vless-mtproxy-setup -> /opt/vless/scripts/vless-mtproxy-setup
└── vless-mtproxy -> /opt/vless/scripts/vless-mtproxy
```

---

**Document Status:** ✅ COMPLETE (Ready for Review)
**Next Steps:**
1. Review by stakeholders
2. Approval for implementation
3. Begin Phase 1: Core Infrastructure
4. Update CHANGELOG.md with v6.0 plans

---

**END OF DOCUMENT**

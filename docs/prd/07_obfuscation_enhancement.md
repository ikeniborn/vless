# PRD v5.24 — Obfuscation Enhancement: Traffic Availability Analysis

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [Обфускация](07_obfuscation_enhancement.md)

---

## ОГЛАВЛЕНИЕ

1. [Executive Summary](#1-executive-summary)
2. [Текущая архитектура: VLESS + Reality](#2-текущая-архитектура-vless--reality)
3. [Анализ обфускационных технологий](#3-анализ-обфускационных-технологий)
   - 3.1 [XTLS Vision (улучшение Reality)](#31-xtls-vision-улучшение-reality)
   - 3.2 [WebSocket + TLS](#32-websocket--tls)
   - 3.3 [gRPC Transport](#33-grpc-transport)
   - 3.4 [XHTTP / SplitHTTP](#34-xhttp--splithttp)
   - 3.5 [Hysteria2 (QUIC-based)](#35-hysteria2-quic-based)
   - 3.6 [TUIC v5](#36-tuic-v5)
   - 3.7 [SingBox Runtime](#37-singbox-runtime)
   - 3.8 [Trojan Protocol](#38-trojan-protocol)
   - 3.9 [Shadowsocks 2022](#39-shadowsocks-2022)
4. [Сравнительный анализ](#4-сравнительный-анализ)
5. [Gap-анализ текущей архитектуры](#5-gap-анализ-текущей-архитектуры)
6. [Риски и ограничения](#6-риски-и-ограничения)
7. [Четырёхуровневый план доработки](#7-четырёхуровневый-план-доработки)
   - 7.1 [Tier 1: Немедленные улучшения (XTLS Vision)](#71-tier-1-немедленные-улучшения-xtls-vision)
   - 7.2 [Tier 2: Расширение транспортов (WS, gRPC, XHTTP)](#72-tier-2-расширение-транспортов-ws-grpc-xhttp)
   - 7.3 [Tier 3: UDP-протоколы как opt-in (Hysteria2, TUIC)](#73-tier-3-udp-протоколы-как-opt-in-hysteria2-tuic)
   - 7.4 [Tier 4: SingBox интеграция](#74-tier-4-singbox-интеграция)
8. [Технические спецификации Tier 1-2](#8-технические-спецификации-tier-1-2)
9. [Тестирование и валидация](#9-тестирование-и-валидация)
10. [Roadmap и приоритизация](#10-roadmap-и-приоритизация)

---

## 1. Executive Summary

### Цель документа

Данный документ описывает результаты исследования текущей архитектуры VLESS+Reality VPN (v5.24) с точки зрения устойчивости к DPI (Deep Packet Inspection) и методам блокировки трафика, а также предлагает структурированный план расширения системы поддержкой дополнительных обфускационных технологий.

### Контекст

Системы цензуры в ряде стран (Китай — GFW, Иран, Россия — ТСПУ) активно эволюционируют. Современные DPI-системы способны идентифицировать VPN-трафик по статистическим признакам, паттернам рукопожатия (handshake timing), и энтропии пакетов. Единственный транспорт (TCP + Reality) создаёт единую точку отказа при избирательной блокировке.

### Ключевые выводы

| Приоритет | Технология | Усилия | DPI-стойкость | Статус |
|-----------|-----------|--------|---------------|--------|
| ~~**Немедленно**~~ | ~~XTLS Vision~~ | ~~Низкие~~ | ~~Высокая~~ | ✅ **РЕАЛИЗОВАНО** — все 7 пользователей, v5.24+ (подтверждено SSH 2026-02-23) |
| **Следующий приоритет** | XHTTP/SplitHTTP | Средние | Высокая (CDN) | Не реализован (Tier 2, v5.3x) |
| **Следующий приоритет** | WebSocket + TLS | Средние | Средняя | Не реализован (Tier 2, v5.3x) |
| **Среднесрочно** | gRPC Transport | Средние | Средняя | Не реализован (Tier 2, v5.3x) |
| **Долгосрочно** | Hysteria2 | Высокие | Высокая | UDP, отдельный контейнер (Tier 3) |
| **Долгосрочно** | TUIC v5 | Высокие | Высокая | UDP, отдельный контейнер (Tier 3) |
| **Стратегически** | SingBox | Высокие | Протокол-зависимо | Параллельный рантайм (Tier 4) |

### Рекомендация

Реализовать **четырёхуровневый подход**:
1. ✅ **Tier 1 (v5.25): XTLS Vision** — РЕАЛИЗОВАНО. `flow: "xtls-rprx-vision"` активен у всех пользователей (подтверждено SSH на ikenibornvpn, 2026-02-23)
2. **Tier 2 (v5.3x):** WebSocket+TLS, gRPC, XHTTP как дополнительные inbound-ы — **ТЕКУЩИЙ ПРИОРИТЕТ**
3. **Tier 3 (v6.x):** Hysteria2 + TUIC как opt-in контейнеры (по образцу MTProxy)
4. **Tier 4 (v7.x):** SingBox как параллельный рантайм

---

## 2. Текущая архитектура: VLESS + Reality

### 2.1 Обзор текущей реализации

**Версия:** v5.24
**Протокол:** VLESS + Reality (Xray-core 24.11.30)
**Транспорт:** TCP only
**Порт:** 443 (через nginx ssl_preread SNI passthrough)

```
Клиент (Reality Client)
    │
    │ TCP:443 → ClientHello (маскировка под HTTPS к dest-домену)
    ▼
nginx (familytraffic, ssl_preread)
    │ SNI passthrough (NO TLS termination для Reality)
    │ ssl_preread_server_name = vless.example.com → 127.0.0.1:8443
    ▼
Xray (familytraffic, port 8443)
    │ Reality handshake: X25519 ECDH + uTLS fingerprint
    │ Decrypts VLESS payload
    ▼
Internet
```

### 2.2 Reality Protocol: текущая конфигурация

Конфигурация генерируется функцией `generate_xray_config_json()` в `lib/orchestrator.sh`:

```json
{
  "inbounds": [{
    "port": 8443,
    "protocol": "vless",
    "tag": "vless-reality",
    "settings": {
      "clients": [],
      "decryption": "none",
      "fallbacks": [{ "dest": "familytraffic:80" }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${REALITY_DEST}:${REALITY_DEST_PORT}",
        "xver": 0,
        "serverNames": [
          "${REALITY_DEST}",
          "www.google.com",
          "www.microsoft.com",
          "www.apple.com"
        ],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}", ""]
      }
    }
  }]
}
```

### 2.3 Что делает Reality DPI-стойким

Reality — это эволюция TLS-камуфляжа, разработанная специально против GFW:

1. **Подлинный TLS 1.3 рукопожатие**: Reality не эмулирует TLS — он использует его целиком. Сервер работает как настоящий TLS-endpoint для реального домена (`dest`), и только клиенты, знающие приватный ключ X25519 и shortId, получают VPN-трафик.

2. **uTLS Fingerprinting**: Клиент имитирует TLS fingerprint конкретных браузеров (Chrome, Firefox, Safari). DPI видит `ClientHello` неотличимый от браузерного.

3. **Active Probing Defense**: Любой сканер/зонд получает легитимный HTTPS-ответ от `dest` (например, google.com). Impossible to distinguish from real HTTPS traffic by external observation.

4. **X25519 ECDH + shortId**: Только клиент с правильными `publicKey` и `shortId` может установить VPN-сессию.

### 2.4 Текущие ограничения

> **Актуальность:** Проверено SSH на живом сервере `ikenibornvpn` 2026-02-23. Xray `teddysun/xray:24.11.30`. Обновлено 2026-03-25 с учётом v1.1.0 (nginx single-container architecture, Tier 2 implemented).

| Ограничение | Описание | Критичность | Статус |
|-------------|---------|-------------|--------|
| ~~TCP-only transport~~ | ~~`streamSettings.network` = "tcp" — единственный транспорт Reality~~ | ~~Средняя~~ | ✅ **ЗАКРЫТО** — Tier 2 (WS/XHTTP/gRPC) реализован в v1.1.0 (порты 8444-8446) |
| ~~XTLS Vision не включён~~ | ~~`flow: "xtls-rprx-vision"` отсутствует у клиентов~~ | ~~Низкая~~ | ✅ **ЗАКРЫТО** — `flow: "xtls-rprx-vision"` активен у ВСЕХ пользователей (v5.24+) |
| Нет CDN-совместимости | Reality не работает через Cloudflare и большинство CDN | Средняя | Частично закрыто — Tier 2 (WS/XHTTP/gRPC) добавляет CDN-совместимость (v1.1.0) |
| UDP не поддерживается | nginx stream module и текущая архитектура — TCP only | Высокая | 🔴 Актуально (Tier 3) |
| ~~Единственный inbound~~ | ~~Один режим подключения — точка отказа при блокировке Reality~~ | ~~Средняя~~ | ✅ **ЗАКРЫТО** — Tier 2 транспорты добавлены в v1.1.0 (WS/XHTTP/gRPC) |
| ~~Нет Nginx-контейнера~~ | ~~`familytraffic-nginx` не задеплоен~~ | ~~Средняя~~ | ✅ **ЗАКРЫТО** — nginx интегрирован в единый контейнер `familytraffic` (v1.1.0) |

---

## 3. Анализ обфускационных технологий

### 3.1 XTLS Vision (улучшение Reality)

**Что это:** XTLS Vision — это расширение протокола, реализованное в Xray-core, которое уменьшает энтропийные аномалии в первых пакетах TLS-сессии. Без Vision: первые байты после TLS handshake содержат зашифрованный VLESS-заголовок с характерной энтропией. С Vision: эти байты буферизируются и передаются вместе с первым данными приложения, устраняя паттерн.

**Как работает:**
```
Без Vision:
  TLS handshake → VLESS header (зашифрован, entropy ~= random) → данные

С Vision:
  TLS handshake → [VLESS header + первые данные] → остальные данные
                   (склеены, неотличимы статистически)
```

**Поддержка:** Xray-core 1.8.0+, текущий образ `teddysun/xray:24.11.30` поддерживает.

**DPI-стойкость:** Высокая. Устраняет статистический паттерн, специфичный для VLESS-трафика. Особенно эффективен против GFW Machine Learning классификаторов.

**CDN-совместимость:** Нет (Reality не работает через CDN).

**Реализация:** Минимальные изменения в `xray_config.json` — добавление поля `flow` в настройки клиентов.

---

### 3.2 WebSocket + TLS

**Что это:** VLESS или VMess через WebSocket + TLS. Клиент устанавливает HTTP/1.1 соединение, выполняет `Upgrade: websocket`, и туннелирует трафик через постоянное WebSocket-соединение поверх TLS.

**Схема трафика:**
```
Клиент
    │ TLS ClientHello (SNI = domain.com)
    ▼
HAProxy / Nginx (TLS termination)
    │ HTTP GET /ws-path
    │ Upgrade: websocket
    ▼
Xray WebSocket inbound
    │ WS → VLESS payload
    ▼
Internet
```

**DPI-стойкость:** Средняя. Трафик выглядит как HTTPS WebSocket (используется в video streaming, gaming, real-time apps). Но тайминг и объём пакетов могут выдавать VPN.

**CDN-совместимость:** Высокая. Работает через Cloudflare, AWS CloudFront, и большинство CDN. Это ключевое преимущество перед Reality.

**Применимость к текущей архитектуре:**
- HAProxy нужен новый frontend/backend для WebSocket inbound
- WebSocket inbound на отдельном порте (например, 8444) или через SNI на том же 443
- Nginx reverse proxy может проксировать WebSocket без HAProxy изменений (через `proxy_pass` с `Upgrade`)

**Ограничения:**
- WS через CDN раскрывает CDN IP (не сервер), но CDN знает реальный IP сервера
- WebSocket keepalive генерирует характерный паттерн (ping/pong каждые ~30с)

---

### 3.3 gRPC Transport

**Что это:** VLESS через gRPC (HTTP/2 binary framing). gRPC — это легитимный протокол для API-вызовов между сервисами Google, AWS и т.д. VPN-трафик замаскирован под gRPC API-вызовы.

**Схема трафика:**
```
Клиент
    │ HTTP/2 POST /GunService/Gun (gRPC)
    │ Content-Type: application/grpc
    ▼
HAProxy (TLS termination, h2 mode)
    ▼
Xray gRPC inbound
    │ gRPC framing → VLESS payload
    ▼
Internet
```

**DPI-стойкость:** Средняя. gRPC трафик широко распространён в корпоративных сетях. Сложнее блокировать, чем WebSocket.

**CDN-совместимость:** Высокая (через Cloudflare gRPC proxy). Cloudflare поддерживает gRPC с 2020 года.

**Требования к архитектуре:**
- HAProxy должен работать в `mode http` (не `mode tcp`) для gRPC frontend
- Или: TLS termination Nginx → plaintext gRPC → Xray
- Требуется HTTP/2 (`h2` в ALPN)
- Конфликт с текущим Reality SNI passthrough на порту 443 (разные режимы HAProxy)

**Xray конфигурация:**
```json
{
  "streamSettings": {
    "network": "grpc",
    "grpcSettings": {
      "serviceName": "GunService",
      "multiMode": false
    },
    "security": "tls",
    "tlsSettings": {
      "alpn": ["h2"]
    }
  }
}
```

---

### 3.4 XHTTP / SplitHTTP

**Что это:** Новый transport от Xray-core (>= 24.9), разработанный специально для CDN-совместимости. Разделяет upload и download потоки на отдельные HTTP-запросы:
- **Upload:** HTTP POST с фрагментированным body (chunked transfer)
- **Download:** HTTP GET с `Transfer-Encoding: chunked` (long-polling)

**Зачем нужен:** Некоторые CDN блокируют WebSocket и gRPC, но пропускают стандартные HTTP POST/GET. XHTTP работает там, где WS/gRPC не проходят.

**DPI-стойкость:** Высокая для CDN-среды. Трафик неотличим от стандартных HTTP API-вызовов (HTTP chunked upload/download используется в файловых хранилищах, стриминге).

**CDN-совместимость:** Наивысшая среди всех транспортов. Работает через Cloudflare Workers, любые HTTP-прокси.

**Xray конфигурация:**
```json
{
  "streamSettings": {
    "network": "splithttp",
    "splithttpSettings": {
      "path": "/api/v1/data",
      "host": "cdn-host.example.com",
      "maxUploadSize": 1000000,
      "maxConcurrentUploads": 10
    }
  }
}
```

**Ограничения:** Выше latency (HTTP round-trip на каждый upload chunk). Не рекомендуется для real-time приложений.

---

### 3.5 Hysteria2 (QUIC-based)

**Что это:** Транспортный протокол на базе QUIC (HTTP/3), оптимизированный для высоких задержек и потерь пакетов. Hysteria2 маскирует трафик под HTTPS/3.

**Ключевые характеристики:**

| Параметр | Значение |
|----------|---------|
| Транспорт | QUIC (UDP) |
| Шифрование | TLS 1.3 |
| Congestion control | BBR (оптимизировано для потерь) |
| Маскировка | HTTPS/3 масquerading |
| Latency | Ниже чем TCP (0-RTT reconnect) |
| Packet loss tolerance | До 50% (BBR) |

**DPI-стойкость:** Высокая. QUIC/HTTPS/3 является легитимным протоколом (YouTube, Google, Cloudflare используют HTTPS/3). Entropy трафика близка к легитимному QUIC.

**Архитектурные ограничения для текущего проекта:**
- **HAProxy не поддерживает UDP** — Hysteria2 не может использовать текущую HAProxy-архитектуру
- Требуется **прямой UDP port** в `docker-compose.yml`: `- "443:443/udp"`
- UFW правило: `ufw allow 443/udp`
- Hysteria2 сервер запускается в **отдельном контейнере** (не через Xray)
- Конфигурация существенно отличается от Xray JSON

**Рекомендуемая архитектура (opt-in, по образцу MTProxy):**
```
Клиент (Hysteria2 client)
    │ UDP:443
    │ QUIC + TLS 1.3
    ▼
familytraffic (отдельный контейнер)
    │ Декодирует Hysteria2
    ▼
Internet
```

---

### 3.6 TUIC v5

**Что это:** TLS-over-QUIC Intra Connectivity — протокол 5-го поколения с улучшенным мультиплексированием и 0-RTT рукопожатием. Разработан как более эффективная альтернатива Hysteria2.

**Сравнение с Hysteria2:**

| Параметр | Hysteria2 | TUIC v5 |
|----------|-----------|---------|
| Congestion control | BBR | Cubic/BBR |
| Multiplexing | Ограниченное | Полное (QUIC streams) |
| 0-RTT | Нет | Да |
| UDP relay | Нет | Да (UDP over QUIC) |
| Реализация | Отдельный binary | SingBox или tuic-server |
| CPU usage | Средний | Низкий |

**DPI-стойкость:** Высокая — подлинный QUIC трафик с TLS 1.3.

**Архитектурные ограничения:** Идентичны Hysteria2 (UDP, отдельный контейнер, bypass HAProxy).

**Рекомендация:** Реализовывать вместе с Hysteria2 или через SingBox (который поддерживает оба протокола).

---

### 3.7 SingBox Runtime

**Что это:** SingBox — универсальная прокси-платформа, поддерживающая 15+ протоколов в одном рантайме: VLESS, VMess, Trojan, Hysteria2, TUIC, Shadowsocks, NaïveProxy, и другие.

**Ключевые преимущества:**
- Единый контейнер заменяет несколько специализированных (Hysteria2 + TUIC + и т.д.)
- Активно развивается (релизы каждые 1-2 недели)
- Поддерживает все актуальные транспорты: WebSocket, gRPC, XHTTP, HTTP/3
- Единый формат конфигурации для всех протоколов

**Ограничения для интеграции:**
- Формат конфигурации **принципиально отличается** от Xray JSON — нельзя переиспользовать существующие функции `generate_xray_config_json()`
- Потребует **новой системы генерации конфигурации** (отдельный модуль `lib/singbox_config_generator.sh`)
- Не замена Xray — параллельный runtime для дополнительных протоколов

**Архитектура (параллельный контейнер):**
```
HAProxy (familytraffic)
    ├─ SNI: vless.domain → Xray (Reality)
    ├─ SNI: singbox.domain → SingBox VLESS/Trojan/etc.
    └─ SNI: *.domain → Nginx (reverse proxy)

familytraffic (новый контейнер)
    ├─ VLESS over WebSocket (port 8444)
    ├─ Trojan (port 8445)
    └─ Hysteria2 (UDP:8443 — прямой exposure)
```

---

### 3.8 Trojan Protocol

**Что это:** Trojan маскирует трафик под HTTPS путём отправки пароля как первых байт TLS-сессии. С точки зрения DPI — обычный HTTPS-трафик на порту 443.

**Схема:**
```
Клиент → TLS:443 → первые байты: sha256(password) + CRLF + CONNECT payload
```

**Поддержка в Xray:** Нативная (`protocol: "trojan"`). Можно добавить как дополнительный inbound.

**DPI-стойкость:** Средне-высокая. Подлинный TLS, но более слабая защита от active probing чем Reality (нет uTLS fingerprinting).

**CDN-совместимость:** Средняя. Через CDN требует WebSocket transport (Trojan over WS+TLS).

**Реализация:** Низкие усилия — новый `protocol: "trojan"` inbound в Xray, SNI routing через HAProxy.

---

### 3.9 Shadowsocks 2022

**Что это:** Современный Shadowsocks с AEAD-2022 шифрованием (AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305). Простой протокол шифрования без камуфляжа.

**DPI-стойкость:** Низкая. В Китае Shadowsocks активно блокируется начиная с 2019 года через replay detection и entropy analysis. В России и Иране — менее агрессивная блокировка.

**Применимость:** Ограничена. Рекомендуется только как фолбэк для регионов без агрессивного DPI. Не рекомендуется как основной протокол для регионов с высоким уровнем цензуры.

**Поддержка в Xray:** Нативная (`protocol: "shadowsocks"`).

---

## 4. Сравнительный анализ

### 4.1 Матрица характеристик

| Протокол/Transport | DPI-стойкость | CDN-совместимость | UDP | Усилия интеграции | Статус в проекте |
|-------------------|--------------|------------------|-----|------------------|-----------------|
| **VLESS+Reality (текущий)** | ★★★★★ | ✗ | ✗ | — | РЕАЛИЗОВАН |
| **XTLS Vision** | ★★★★★ | ✗ | ✗ | — | ✅ **РЕАЛИЗОВАН** (все 7 пользователей, v5.24+) |
| **VLESS+WebSocket+TLS** | ★★★ | ✓ | ✗ | Средние | Не реализован |
| **VLESS+gRPC** | ★★★★ | ✓ | ✗ | Средние | Не реализован |
| **VLESS+XHTTP/SplitHTTP** | ★★★★ | ✓✓ | ✗ | Средние | Не реализован |
| **Hysteria2** | ★★★★★ | ✗ | ✓ | Высокие | Не реализован |
| **TUIC v5** | ★★★★★ | ✗ | ✓ | Высокие | Не реализован |
| **Trojan** | ★★★ | Частично | ✗ | Низкие | Не реализован |
| **Shadowsocks 2022** | ★★ | ✗ | ✗ | Низкие | Не реализован |
| **SingBox (платформа)** | Зависит | ✓ | ✓ | Очень высокие | Не реализован |

### 4.2 Применимость по сценариям

| Сценарий использования | Рекомендованный протокол | Альтернатива |
|------------------------|-------------------------|-------------|
| Максимальная DPI-стойкость (Китай, GFW) | VLESS+Reality+XTLS Vision | Hysteria2 |
| CDN за Cloudflare | VLESS+XHTTP/SplitHTTP | VLESS+WebSocket+TLS |
| Нестабильная сеть (мобильный, Wi-Fi) | Hysteria2 (BBR) | TUIC v5 |
| Корпоративная среда (gRPC разрешён) | VLESS+gRPC | VLESS+WebSocket |
| Низкая задержка, 0-RTT reconnect | TUIC v5 | Hysteria2 |
| Простота развёртывания | VLESS+Reality (текущий) | Trojan |
| Устаревшие клиенты/регионы | Shadowsocks 2022 | VLESS+WebSocket |

### 4.3 Позиционирование текущего решения

Текущая реализация VLESS+Reality является **лучшим решением для противодействия GFW** при прямом подключении без CDN. Слабые стороны:
1. Нет CDN-пути (для случаев, когда прямое подключение заблокировано)
2. Нет UDP-оптимизации для плохих сетей
3. Единственный транспорт создаёт риск при точечной блокировке Reality

---

## 5. Gap-анализ текущей архитектуры

### 5.1 Транспортный gap

**Текущее состояние:** В функции `generate_xray_config_json()` (файл `lib/orchestrator.sh:627`):

```json
"streamSettings": {
  "network": "tcp",   // ← жёстко закодировано, единственный транспорт
  "security": "reality"
}
```

**Что отсутствует:**
- WebSocket transport (`network: "ws"`)
- gRPC transport (`network: "grpc"`)
- XHTTP transport (`network: "splithttp"`)
- Механизм выбора транспорта пользователем

### 5.2 XTLS Vision gap — ✅ ЗАКРЫТ

> **Статус на 2026-02-23:** Подтверждено SSH. Все 7 пользователей в `xray_config.json` имеют `flow: "xtls-rprx-vision"`. GAP УСТРАНЁН.

**Текущее состояние** (подтверждено SSH ikenibornvpn, 2026-02-23):
```json
"clients": [
  { "id": "uuid-1", "email": "ikeniborn@vless.local",  "flow": "xtls-rprx-vision" },
  { "id": "uuid-2", "email": "feanor666@vless.local",  "flow": "xtls-rprx-vision" },
  { "id": "uuid-3", "email": "oksigen86@vless.local",  "flow": "xtls-rprx-vision" },
  { "id": "uuid-4", "email": "sevruka@vless.local",    "flow": "xtls-rprx-vision" },
  { "id": "uuid-5", "email": "sevrukn@vless.local",    "flow": "xtls-rprx-vision" },
  { "id": "uuid-6", "email": "sevrukm@vless.local",    "flow": "xtls-rprx-vision" },
  { "id": "uuid-7", "email": "torrih@vless.local",     "flow": "xtls-rprx-vision" }
]
```

**Как реализовано в коде (`lib/user_management.sh`):**
```bash
# add_user_to_json() строка 521-525 — новые пользователи:
jq ".inbounds[0].settings.clients += [{
    \"id\": \"$uuid\",
    \"email\": \"${username}@vless.local\",
    \"flow\": \"xtls-rprx-vision\"   # ← добавляется автоматически
}]" "$XRAY_CONFIG" > "$temp_file"

# generate_vless_uri() строка 834 — URI включает flow:
uri+="&flow=xtls-rprx-vision"
```

**Остаток:**  `validate_vless_uri()` в `lib/qr_generator.sh` (строка 95) по-прежнему требует `flow` как обязательный параметр для ВСЕХ URI — это нужно исправить перед Tier 2 (Tier 2 URI не имеют `flow`).

### 5.3 UDP/QUIC gap

**Текущее состояние:** Все контейнеры используют TCP. `docker-compose.yml` не содержит UDP port mapping. HAProxy работает только в `mode tcp` (TCP-level LB).

**Что требуется для Hysteria2/TUIC:**
1. Новый контейнер `familytraffic` (или `familytraffic`)
2. UDP port mapping: `"443:443/udp"` или `"8443:8443/udp"`
3. UFW правила: `ufw allow 8443/udp`
4. Отдельный Docker network или прямой host binding
5. HAProxy не участвует в UDP routing

### 5.4 CDN-доступности gap

**Текущее состояние:** Reality не работает через CDN (Cloudflare, etc.) потому что CDN терминирует TLS и не пропускает RAW TLS traffic.

**Что нужно:** Хотя бы один CDN-совместимый transport (WebSocket, gRPC или XHTTP) за Nginx/HAProxy, который сможет работать через Cloudflare proxied DNS.

### 5.5 Архитектурные ограничения

```
ТЕКУЩАЯ АРХИТЕКТУРА (v1.1.0+):
┌─────────────────────────────────────────────────────────┐
│ nginx (ssl_preread, stream module)                      │
│  Port 443: SNI passthrough → Xray Reality (TCP:8443)   │
│            SNI routing → Tier 2 nginx proxy (8448)     │
│  Port 1080: TLS term → Xray SOCKS5 (TCP:10800)         │
│  Port 8118: TLS term → Xray HTTP (TCP:18118)           │
└─────────────────────────────────────────────────────────┘

ОГРАНИЧЕНИЯ:
  ✗ nginx stream module не маршрутизирует UDP → Hysteria2/TUIC невозможен без bypass
  ✗ Все инбаунды share порт 443 через SNI → новые транспорты нужны на новых портах
     (или отдельные subdomains через SNI)
  ✓ Tier 2 (WS/XHTTP/gRPC) — реализовано через nginx ssl_preread → Tier 2 nginx proxy
```

---

## 6. Риски и ограничения

### 6.1 Архитектурные риски

| ID | Риск | Severity | Mitigation |
|----|------|----------|-----------|
| **R1** | Новые инбаунды (WS, gRPC) требуют nginx конфигурационных изменений | Medium | Использовать SNI-subdomain routing: `ws.domain → Xray WebSocket backend`. nginx ssl_preread на порту 443 маршрутизирует по SNI к разным backends. Реализовано в v1.1.0 через nginx Tier 2 proxy. |
| **R2** | Hysteria2/TUIC требуют UDP — несовместимы с nginx stream (TCP-only) | High | Отдельный процесс/контейнер с прямым UDP port exposure (bypass nginx). Аналогично MTProxy pattern (`lib/mtproxy_manager.sh`) — **MTProxy уже реализован** как opt-in в v1.1.0. |
| **R3** | SingBox как замена Xray потребует полной переработки конфигурационных модулей | High | Реализовывать SingBox как **параллельный** контейнер, не замену. Пользователь выбирает: Xray (Reality) ИЛИ SingBox (multi-protocol). |
| **R4** | WebSocket на порту 443 конфликтует с Reality SNI passthrough | Medium | Subdomain routing: `vless.domain → Reality/Xray`, `ws.domain → WebSocket/Xray`. Оба через nginx ssl_preread SNI. Реализовано в v1.1.0. |
| **R5** | gRPC требует HTTP/2, несовместимо с режимом ssl_preread на порту 443 | Medium | gRPC inbound на отдельном порту (8446), nginx Tier 2 proxy терминирует TLS и передаёт plaintext gRPC в xray. Реализовано в v1.1.0. |
| ~~**R6**~~ | ~~GFW детектирует VLESS+Reality по timing analysis (без XTLS Vision)~~ | ~~Low~~ | ✅ **ЗАКРЫТ** — `flow: "xtls-rprx-vision"` активен у всех пользователей (подтверждено SSH 2026-02-23) |

### 6.2 Операционные риски

| Риск | Severity | Mitigation |
|------|----------|-----------|
| Сложность управления несколькими транспортами | Medium | CLI-команда `vless transport` для переключения и статуса |
| Увеличение attack surface при добавлении портов | Medium | UFW rate-limiting + fail2ban на все новые порты |
| Различные client apps для разных протоколов | Low | Документировать рекомендуемые клиенты для каждого транспорта |
| Performance degradation при HTTP-транспортах | Low | Benchmark тесты перед production. Hysteria2/BBR — наоборот, лучше при packet loss |

### 6.3 Совместимость клиентов

| Протокол | iOS | Android | Windows | macOS | Linux |
|----------|-----|---------|---------|-------|-------|
| VLESS+Reality+Vision | **v2rayTun** ✅, Shadowrocket, Sing-Box | v2rayNG, Sing-Box | v2rayN, Xray | ClashX, Sing-Box | Xray CLI |
| VLESS+WebSocket | **v2rayTun** ✅, Shadowrocket, Sing-Box | v2rayNG, Sing-Box | v2rayN, Xray | ClashX, Sing-Box | Xray CLI |
| VLESS+gRPC | **v2rayTun** ✅, Shadowrocket, Sing-Box | v2rayNG, Sing-Box | v2rayN, Xray | ClashX, Sing-Box | Xray CLI |
| VLESS+XHTTP | **v2rayTun** ⚠️ (вероятно), Sing-Box | v2rayNG, Sing-Box | v2rayN, Xray | Sing-Box | Xray CLI |
| Hysteria2 | Sing-Box | Sing-Box, NekoBox | v2rayN, Hysteria | Sing-Box | Hysteria CLI |
| TUIC v5 | Sing-Box | Sing-Box | Sing-Box | Sing-Box | tuic-client |

> **Примечание:** Фактические iOS-пользователи проекта используют **v2rayTun** (v2.4.4, февраль 2026). Анализ совместимости v2rayTun с конкретными транспортами см. в разделе **6.4**.

### 6.4 iOS v2rayTun — детальный анализ совместимости

> **Исследование:** App Store changelog + GitHub releases (DigneZzZ/v2raytun) + docs.v2raytun.com. Дата: 2026-02-22.

| Параметр | Значение |
|---|---|
| Текущая iOS версия | **2.4.4** (4 февраля 2026) |
| Bundled Xray-core | **25.10.15** (v2.4.1, декабрь 2025; v2.4.4 вероятно новее) |
| Разработчик | DATABRIDGES TECHNOLOGIES LTD |
| App Store ID | 6476628951 |
| Минимальная iOS | 16.0+ |

**Совместимость с планируемыми изменениями:**

| Функция | Поддержка | Уверенность | Источник |
|---------|-----------|-------------|---------|
| XTLS Vision (`flow=xtls-rprx-vision`) | ✅ **Да** | Высокая | Официальный пример URI в docs.v2raytun.com |
| VLESS URI импорт (`flow=`, `fp=`, `pbk=`, `sid=`) | ✅ **Да** | Высокая | Официальный URI пример + user guides |
| uTLS fingerprint: chrome, firefox, safari, ios, android, edge, 360, qq | ✅ **Полный набор** | Высокая | Наследуется от Xray-core |
| uTLS fingerprint: random, randomized | ✅ **Да** | Высокая | Xray-core uTLS |
| WebSocket transport | ✅ **Да** | Высокая | App Store changelog v1.8.9 (явное упоминание) |
| gRPC transport | ✅ **Да** | Высокая | App Store changelog v1.8.9 (явное упоминание) |
| XHTTP/SplitHTTP transport | ⚠️ **Вероятно** | Средняя | Android v3.9.34 (август 2024) подтверждён; iOS — не задокументирован явно |
| HAProxy → Nginx migration | ✅ **Нулевой impact** | Высокая | Прозрачное изменение на L4; порт/хост/cert не меняются |

**XTLS Vision — как работает с v2rayTun:**

Официальная документация (docs.v2raytun.com) содержит пример URI именно с XTLS Vision:
```
vless://<uuid>@<server>:443?type=tcp&security=reality&fp=chrome&pbk=<key>&sni=google.com&flow=xtls-rprx-vision#name
```
v2rayTun парсит параметр `flow=xtls-rprx-vision` из URI при импорте и передаёт его в Xray-core. Поскольку Xray-core >= 1.8.0 поддерживает XTLS Vision, функция работает полностью.

**uTLS fingerprints в v2rayTun:**

v2rayTun использует Xray-core uTLS — полный набор fingerprints идентичен эталонному:

| Значение | Что эмулирует |
|---|---|
| `chrome` | Chrome (актуальный) |
| `firefox` | Firefox |
| `safari` | Safari desktop |
| `ios` | iOS Safari |
| `android` | Android Chrome |
| `edge` | Microsoft Edge |
| `360` | 360 Browser (Китай) |
| `qq` | QQ Browser (Китай) |
| `random` | Случайный из именованных |
| `randomized` | Уникальный сгенерированный (100% TLS 1.3 + X25519) |

**XHTTP на iOS — риск и митигация:**

XHTTP подтверждён на Android с августа 2024 (v3.9.34). iOS-версия обычно выходит с задержкой в 1-4 недели. При Tier 2 реализации (v5.31):
- **Обязательное ручное тестирование** XHTTP на реальном iOS-устройстве с v2rayTun
- Если XHTTP не поддерживается — пользователи iOS переходят на WebSocket (полная поддержка)
- Reality (основной транспорт) не затрагивается в любом случае

---

## 7. Четырёхуровневый план доработки

### 7.1 Tier 1: Немедленные улучшения (XTLS Vision) — ✅ РЕАЛИЗОВАНО

**Версия:** v5.25 (фактически реализовано в v5.24+)
**Усилия:** ~~Низкие (1-2 дня)~~ → ВЫПОЛНЕНО
**Риск:** Низкий → ЗАКРЫТ
**Влияние:** Высокое (улучшение DPI-стойкости для всех пользователей Reality) → ДОСТИГНУТО

> **SSH-подтверждение (ikenibornvpn, 2026-02-23):** Все 7 пользователей в xray_config.json имеют `flow: "xtls-rprx-vision"`. Xray образ `teddysun/xray:24.11.30` подтверждён.

**Статус изменений:**

| # | Изменение | Статус |
|---|-----------|--------|
| 1 | `lib/orchestrator.sh` (create_xray_config): начальный `clients: []` — flow добавляется при create_user | ✅ OK (flow добавляется через add_user_to_json, не через шаблон) |
| 2 | `lib/user_management.sh` (add_user_to_json, строка 524): `"flow": "xtls-rprx-vision"` | ✅ РЕАЛИЗОВАНО |
| 3 | `lib/user_management.sh` (generate_vless_uri, строка 834): `uri+="&flow=xtls-rprx-vision"` | ✅ РЕАЛИЗОВАНО |
| 4 | Xray `teddysun/xray:24.11.30` поддерживает XTLS Vision | ✅ ПОДТВЕРЖДЕНО (Xray-core >= 1.8.0) |

**Остаток Tier 1 (единственное незакрытое):**
- `lib/qr_generator.sh` строка 95: `validate_vless_uri()` требует `flow` как обязательный параметр у ВСЕХ URI → нужно исправить до Tier 2 (WS/XHTTP/gRPC URI не имеют `flow`)

---

### 7.2 Tier 2: Расширение транспортов (WS, gRPC, XHTTP)

**Версия:** v5.3x
**Усилия:** Средние (2-4 недели)
**Риск:** Средний (архитектурные изменения HAProxy)
**Влияние:** Высокое (CDN-совместимость)

> **Архитектурное уточнение (на основе анализа живого сервера):**
> HAProxy на порту 443 работает в `mode tcp` (SNI passthrough). TLS-терминация для Tier 2 транспортов **невозможна в HAProxy на порту 443** без нарушения Reality. Решение: отдельный контейнер **`familytraffic-nginx_tier2`** принимает трафик от HAProxy и терминирует TLS для WS/XHTTP/gRPC.
>
> На живом сервере **нет ни одного Nginx-контейнера** (reverse proxy был отключён при установке) — `familytraffic-nginx_tier2` нужно создать с нуля.

**Правильная архитектура Tier 2:**
```
HAProxy :443 (mode tcp, SNI routing)
  ├── SNI ws.domain    → backend nginx_tier2:8448
  ├── SNI xhttp.domain → backend nginx_tier2:8448
  ├── SNI grpc.domain  → backend nginx_tier2:8448
  └── (default)        → backend xray_vless:8443 (Reality — без изменений)

familytraffic-nginx_tier2 (НОВЫЙ контейнер, listen 8448 ssl http2)
  ├── server_name ws.domain    → proxy_pass http://familytraffic:8444
  ├── server_name xhttp.domain → proxy_pass http://familytraffic:8445
  └── server_name grpc.domain  → grpc_pass grpc://familytraffic:8446

familytraffic (plaintext inbounds — без TLS, Nginx терминирует)
  ├── :8443 Reality (существующий)
  ├── :8444 VLESS WS plaintext (новый)
  ├── :8445 VLESS XHTTP plaintext (новый)
  └── :8446 VLESS gRPC plaintext (новый)
```

**Подэтап 2a: WebSocket + TLS (приоритет)**

1. Новый Xray inbound на порту 8444 с `network: "ws"`, **без TLS** (Nginx терминирует)
2. HAProxy SNI routing: `ws.example.com → nginx_tier2 backend (:8448)`
3. Nginx `server_name ws.example.com` → `proxy_pass http://familytraffic:8444` + WebSocket upgrade headers
4. Генератор клиентских конфигов для WS transport (`generate_transport_uri ws`)
5. CLI команда: `vless add-transport ws <subdomain>`

**Подэтап 2b: XHTTP/SplitHTTP (высокий приоритет)**

1. Новый Xray inbound на порту 8445 с `network: "splithttp"` (Xray >= 24.9 — уже используется 24.11.30 ✓)
2. HAProxy SNI routing: `xhttp.example.com → nginx_tier2 backend`
3. Nginx `server_name xhttp.example.com` → `proxy_pass http://familytraffic:8445` + chunked streaming
4. CDN-инструкция: как настроить Cloudflare для XHTTP

**Подэтап 2c: gRPC (средний приоритет)**

1. Новый Xray inbound на порту 8446 с `network: "grpc"`, **без TLS** (Nginx терминирует)
2. HAProxy SNI routing: `grpc.example.com → nginx_tier2 backend`
3. Nginx `server_name grpc.example.com` → `grpc_pass grpc://familytraffic:8446` (http2 required)

**Новые CLI-команды:**
```bash
sudo familytraffic add-transport ws subdomain.example.com
sudo familytraffic add-transport xhttp subdomain.example.com
sudo familytraffic add-transport grpc subdomain.example.com
sudo familytraffic list-transports
sudo familytraffic remove-transport ws
```

---

### 7.3 Tier 3: UDP-протоколы как opt-in (Hysteria2, TUIC)

**Версия:** v6.x
**Усилия:** Высокие (4-6 недель)
**Риск:** Высокий (новая архитектура, UDP exposure)
**Влияние:** Очень высокое (плохие сети, Китай)

**Архитектура:** По образцу MTProxy — ✅ **РЕАЛИЗОВАН** в v1.1.0 как opt-in supervisord процесс (`lib/mtproxy_manager.sh`, mtg v2.2.3, порт 2053).
Hysteria2/TUIC реализовать аналогично: opt-in supervisord процесс с прямым UDP exposure (bypass nginx stream).

```
Новые файлы:
  lib/hysteria2_manager.sh        # Управление Hysteria2 процессом (как mtproxy_manager.sh)
  lib/tuic_manager.sh             # Управление TUIC процессом
  scripts/familytraffic-hysteria2 # CLI для Hysteria2 (как familytraffic-mtproxy)
  scripts/familytraffic-tuic      # CLI для TUIC

Интеграция через supervisord (аналогично MTProxy):
  /opt/familytraffic/config/supervisord.d/hysteria2.conf  # создаётся при установке
  # UDP port — прямой exposure, bypass nginx

UFW правила:
  ufw allow 8443/udp comment 'Hysteria2'
```

**Установка (opt-in wizard):**
```bash
sudo familytraffic install-hysteria2
# Wizard: выбор порта, SSL cert, bandwidth limits
# Генерация клиентских конфигов (Sing-Box format)
```

---

### 7.4 Tier 4: SingBox интеграция

**Версия:** v7.x
**Усилия:** Очень высокие (2-3 месяца)
**Риск:** Высокий (параллельная кодовая база)
**Влияние:** Максимальное (все протоколы в одном контейнере)

**Принцип:** SingBox как **параллельный рантайм**, не замена Xray.

```
Новые файлы:
  lib/singbox_config_generator.sh  # Генерация SingBox JSON (отдельный формат)
  lib/singbox_manager.sh           # Управление SingBox контейнером
  scripts/vless-singbox            # CLI

Контейнер familytraffic:
  - VLESS+Reality (дублирует Xray, для A/B тестирования)
  - Hysteria2 (заменяет отдельный familytraffic)
  - TUIC v5 (заменяет отдельный familytraffic)
  - Trojan+WebSocket+TLS
```

**Обоснование стратегического значения:** SingBox активно развивается и в перспективе станет основной платформой для обхода блокировок. Ранняя интеграция как opt-in обеспечит плавный переход.

---

## 8. Технические спецификации Tier 1-2

### 8.1 XTLS Vision: изменения конфигурации — ✅ РЕАЛИЗОВАНО

> **Статус:** Подтверждено SSH на ikenibornvpn. Все 7 пользователей имеют `flow: "xtls-rprx-vision"`.

**Текущая конфигурация Xray inbound** (реальное состояние сервера, 2026-02-23):

```json
{
  "inbounds": [{
    "port": 8443,
    "protocol": "vless",
    "tag": "vless-reality",
    "settings": {
      "clients": [
        { "id": "...", "email": "ikeniborn@vless.local",  "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "feanor666@vless.local",  "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "oksigen86@vless.local",  "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "sevruka@vless.local",    "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "sevrukn@vless.local",    "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "sevrukm@vless.local",    "flow": "xtls-rprx-vision" },
        { "id": "...", "email": "torrih@vless.local",     "flow": "xtls-rprx-vision" }
      ],
      "decryption": "none",
      "fallbacks": [{ "dest": "familytraffic:80" }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": { "show": false, "...": "..." }
    }
  }]
}
```

**Текущий client URI** (`generate_vless_uri()` строка 834 — уже реализовано):

```
# Формат с Vision (АКТИВНЫЙ — подтверждён на сервере):
vless://${UUID}@${SERVER}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=...&fp=chrome&pbk=...&sid=...&type=tcp#username
```

### 8.2 WebSocket Transport: конфигурация Xray

**Новый inbound для WebSocket** (добавляется в массив inbounds):

```json
{
  "port": 8444,
  "protocol": "vless",
  "tag": "vless-websocket",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "/vless-ws",
      "headers": {}
    }
  }
}
```

**HAProxy конфигурация** (SNI routing → `familytraffic-nginx_tier2`, НЕ напрямую на Xray):

> **Уточнение:** HAProxy на порту 443 работает в `mode tcp`. TLS-терминацию для WebSocket выполняет `familytraffic-nginx_tier2` (новый контейнер). HAProxy только маршрутизирует по SNI.

```haproxy
# В frontend https_sni_router, ПЕРЕД default_backend (R4 mitigation):
acl is_tier2_ws req_ssl_sni -i ws.example.com
use_backend nginx_tier2 if is_tier2_ws

# Единый backend для всех Tier 2 транспортов:
backend nginx_tier2
    mode tcp
    server nginx familytraffic-nginx_tier2:8448 check inter 10s fall 3 rise 2
```

**Nginx конфигурация** (TLS termination → plaintext WebSocket к Xray):
```nginx
server {
    listen 8448 ssl;
    http2 on;
    server_name ws.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location /vless-ws {
        proxy_pass http://familytraffic:8444;   # plaintext к Xray
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
```

**Клиентский URI для WebSocket:**
```
vless://${UUID}@ws.example.com:443?encryption=none&security=tls&sni=ws.example.com&fp=chrome&type=ws&path=%2Fvless-ws#username-ws
```

### 8.3 XHTTP/SplitHTTP Transport: конфигурация Xray

**Новый inbound для SplitHTTP:**

```json
{
  "port": 8445,
  "protocol": "vless",
  "tag": "vless-xhttp",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "splithttp",
    "splithttpSettings": {
      "path": "/api/v2",
      "maxUploadSize": 1000000,
      "maxConcurrentUploads": 10,
      "minUploadIntervalMs": 0
    }
  }
}
```

**HAProxy конфигурация** (к тому же единому `nginx_tier2` backend):

```haproxy
acl is_tier2_xhttp req_ssl_sni -i xhttp.example.com
use_backend nginx_tier2 if is_tier2_xhttp
# backend nginx_tier2 уже определён в секции 8.2 (shared с WS и gRPC)
```

**Nginx конфигурация** (TLS termination → plaintext XHTTP к Xray):
```nginx
server {
    listen 8448 ssl;
    http2 on;
    server_name xhttp.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location /api/v2 {
        proxy_pass http://familytraffic:8445;   # plaintext к Xray
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 300s;
    }
}
```

### 8.4 gRPC Transport: конфигурация

**Новый inbound для gRPC:**

```json
{
  "port": 8446,
  "protocol": "vless",
  "tag": "vless-grpc",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "grpc",
    "grpcSettings": {
      "serviceName": "GunService",
      "multiMode": false,
      "idle_timeout": 60,
      "health_check_timeout": 20
    },
    "security": "none"
  }
}
```

**HAProxy конфигурация** (к тому же `nginx_tier2` backend):

```haproxy
acl is_tier2_grpc req_ssl_sni -i grpc.example.com
use_backend nginx_tier2 if is_tier2_grpc
# backend nginx_tier2 уже определён в секции 8.2 (shared с WS и XHTTP)
```

**Nginx конфигурация** (TLS termination + gRPC proxy → plaintext к Xray):

> **Важно:** Nginx работает на порту 8448 (общем для всех Tier 2), различает транспорты по `server_name`.

```nginx
server {
    listen 8448 ssl;
    http2 on;
    server_name grpc.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location /GunService/ {
        grpc_pass grpc://familytraffic:8446;   # plaintext gRPC к Xray
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
        grpc_buffer_size 4k;
    }
}
```

---

## 9. Тестирование и валидация

### 9.1 Тест-матрица по транспортам

| Тест-кейс | Reality+Vision | WebSocket | XHTTP | gRPC | Hysteria2 |
|-----------|---------------|-----------|-------|------|-----------|
| Базовое подключение | TC-01 | TC-10 | TC-20 | TC-30 | TC-40 |
| DPI-bypass (GFW simulation) | TC-02 | TC-11 | TC-21 | TC-31 | TC-41 |
| CDN routing | N/A | TC-12 | TC-22 | TC-32 | N/A |
| Fallback при потере пакетов | TC-03 | TC-13 | TC-23 | TC-33 | TC-42 |
| Multi-user concurrency | TC-04 | TC-14 | TC-24 | TC-34 | TC-43 |
| Cert renewal без downtime | TC-05 | TC-15 | TC-25 | TC-35 | TC-44 |
| fail2ban integration | TC-06 | TC-16 | TC-26 | TC-36 | TC-45 |

### 9.2 DPI-bypass тестирование

Для проверки устойчивости к DPI использовать:

```bash
# 1. Проверка entropy первых пакетов (XTLS Vision)
sudo tcpdump -i any -w /tmp/vless.pcap port 443 &
# Подключиться клиентом
kill %1
tshark -r /tmp/vless.pcap -Y "tls.handshake" -T fields -e tls.handshake.type

# 2. Проверка TLS fingerprint (uTLS)
# Сравнить JA3 hash с эталонным браузерным fingerprint
tshark -r /tmp/vless.pcap -Y "tls.handshake.type==1" -T fields -e tls.handshake.ciphersuite

# 3. Active probing test (проверка fallback)
curl -v https://vless.example.com  # должен вернуть fake-site контент
```

### 9.3 Интеграция с существующим тест-сюитом

Расширить `tests/integration/test_security.sh`:

```bash
# Новые тест-кейсы для обфускации:
test_xtls_vision_enabled()        # Проверить наличие flow field в config
test_websocket_connectivity()     # WebSocket handshake через сервер
test_xhttp_split_pattern()        # Проверить chunked upload/download
test_fallback_to_tcp()            # При недоступности WebSocket → fallback на Reality
```

### 9.4 Performance benchmarks

```bash
# Latency тест по транспортам
for transport in reality websocket xhttp grpc hysteria2; do
  echo "=== $transport ==="
  ping -c 10 -I proxy-$transport.example.com 8.8.8.8 2>/dev/null | tail -1
done

# Throughput тест
curl -o /dev/null -s -w "%{speed_download}" \
  --proxy "socks5://user:pass@server:1080" \
  https://speed.cloudflare.com/__down?bytes=10000000
```

---

## 10. Roadmap и приоритизация

### 10.1 Временная шкала

```
2026 Q1: Tier 1 — XTLS Vision [✅ ВЫПОЛНЕНО раньше срока]
├── ✅ v5.24+: flow=xtls-rprx-vision добавлен в add_user_to_json() и generate_vless_uri()
├── ✅ v5.24+: Все 7 существующих пользователей уже имеют flow (миграция не потребовалась)
├── ⏳ v5.25: Исправить validate_vless_uri() — убрать flow из обязательных (блокирует Tier 2)
└── ⏳ v5.25: Добавить test_xtls_vision_enabled() (TC-01) в security_tests.sh

2026 Q2: Tier 2 — WebSocket + XHTTP + gRPC [✅ РЕАЛИЗОВАНО в v1.1.0]
├── ✅ v1.1.0: nginx Tier 2 proxy + WebSocket transport (port 8444)
│             (lib/nginx_stream_generator.sh + lib/transport_manager.sh)
├── ✅ v1.1.0: XHTTP/SplitHTTP transport (port 8445)
├── ✅ v1.1.0: gRPC transport (port 8446)
└── ✅ v1.1.0: CLI управление транспортами (familytraffic add-transport/list-transports)

2026 Q2 MTProxy: ✅ РЕАЛИЗОВАНО в v1.1.0
└── ✅ v1.1.0: MTProxy (mtg v2.2.3) как opt-in supervisord процесс (familytraffic-mtproxy CLI)

2026 Q3-Q4: Tier 3 — UDP Protocols
├── v6.0: Hysteria2 opt-in supervisord процесс (по образцу MTProxy)
├── v6.1: TUIC v5 opt-in supervisord процесс
└── v6.2: Единый CLI для transport selection

2027: Tier 4 — SingBox
├── v7.0: SingBox parallel container (opt-in)
├── v7.1: SingBox config generator (lib/singbox_config_generator.sh)
└── v7.2: Унифицированный multi-transport management
```

### 10.2 Приоритизация по impact/effort

```
                    HIGH IMPACT
                         │
  Hysteria2 ─────────────┼──────────── XTLS Vision ← НАЧАТЬ ЗДЕСЬ
  TUIC v5                │            XHTTP/SplitHTTP
                         │
ВЫСОКИЕ ─────────────────┼───────────────────────── НИЗКИЕ
УСИЛИЯ                   │                           УСИЛИЯ
                         │
  SingBox                │            WebSocket+TLS
                         │            gRPC
                         │            Trojan
                    LOW IMPACT
```

### 10.3 Критерии готовности каждого Tier

**Tier 1 (XTLS Vision) — Definition of Done:**
- [x] ~~`flow: "xtls-rprx-vision"` добавлен в `generate_xray_config_json()`~~ → **ВЫПОЛНЕНО** (`add_user_to_json()` строка 524)
- [x] ~~`flow` добавлен в user management (`add_user()`)~~ → **ВЫПОЛНЕНО** (строка 524)
- [x] ~~VLESS URI обновлён с параметром `flow=xtls-rprx-vision`~~ → **ВЫПОЛНЕНО** (`generate_vless_uri()` строка 834)
- [x] ~~Все существующие пользователи мигрированы~~ → **ВЫПОЛНЕНО** (7/7 пользователей подтверждены SSH)
- [ ] `validate_vless_uri()` исправлен — `flow` conditional (только для `security=reality`) ← **ОСТАЛОСЬ**
- [ ] Клиентская документация обновлена: **v2rayTun** (iOS, основной клиент), Shadowrocket, v2rayNG ← **ОСТАЛОСЬ**
- [ ] Тест TC-01 (`test_xtls_vision_enabled`) добавлен ← **ОСТАЛОСЬ**

**Tier 2 (Транспорты) — Definition of Done: ✅ РЕАЛИЗОВАНО в v1.1.0**
- [x] ~~`familytraffic-nginx_tier2` контейнер~~ → nginx Tier 2 proxy внутри единого контейнера `familytraffic` (nginx_stream_generator.sh)
- [x] Новые inbound-ы добавлены в xray_config (WS :8444, XHTTP :8445, gRPC :8446, plaintext, без TLS)
- [x] nginx SNI routing (ssl_preread) → Tier 2 nginx proxy (TLS termination → plaintext к xray)
- [x] `lib/nginx_stream_generator.sh` генерирует конфиг для Tier 2 транспортов
- [x] `lib/transport_manager.sh` управляет транспортами
- [x] CLI `familytraffic add-transport` / `list-transports` / `remove-transport` работают
- [x] Reality трафик не нарушен (nginx ssl_preread пассирует Reality без изменений)
- [ ] Тест TC-10 (WS), TC-20 (XHTTP), TC-30 (gRPC) пройдены ← **ОСТАЛОСЬ**
- [ ] **iOS v2rayTun**: тесты iOS-10 (WS) и iOS-30 (gRPC) пройдены ← **ОСТАЛОСЬ**
- [ ] Документация обновлена: README.md, CHANGELOG.md + инструкции для v2rayTun ← **ОСТАЛОСЬ**

**Tier 3 (UDP) — Definition of Done:**
- [ ] `familytraffic install-hysteria2` wizard работает (opt-in, supervisord process)
- [ ] UDP ports безопасно изолированы (fail2ban, UFW)
- [ ] Клиентские конфигурации SingBox format генерируются автоматически
- [ ] Тест TC-40 до TC-45 пройдены

---

## Приложение А: Клиентские приложения

| Платформа | Приложение | Reality+Vision | WS | gRPC | XHTTP | Hysteria2 | TUIC | Примечание |
|-----------|-----------|:-:|:-:|:-:|:-:|:-:|:-:|---|
| **iOS** | **v2rayTun 2.4.4** | ✅ | ✅ | ✅ | ⚠️ | ✗ | ✗ | **Фактический клиент пользователей проекта**; Xray-core 25.10.15; XHTTP требует проверки |
| iOS | Shadowrocket | ✅ | ✅ | ✅ | ⚠️ | ✗ | ✗ | Платный ($2.99) |
| iOS | Sing-Box | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Бесплатный, все протоколы |
| Android | v2rayNG | ✅ | ✅ | ✅ | ✅ | ✗ | ✗ | |
| Android | Sing-Box / NekoBox | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Windows | v2rayN | ✅ | ✅ | ✅ | ✅ | ✅ | ✗ | |
| macOS | ClashX Pro | ✅ | ✅ | ✅ | ✗ | ✗ | ✗ | |
| macOS/Linux | Sing-Box CLI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Linux | Xray CLI | ✅ | ✅ | ✅ | ✅ | ✗ | ✗ | |

> ⚠️ **XHTTP на iOS (v2rayTun):** Подтверждён на Android v3.9.34 (август 2024). iOS-поддержка не задокументирована явно — требует ручного тестирования при реализации Tier 2.

## Приложение Б: Полезные ресурсы

- **Xray-core документация:** https://xtls.github.io/
- **SingBox документация:** https://sing-box.sagernet.org/
- **Hysteria2 документация:** https://v2.hysteria.network/
- **TUIC v5 репозиторий:** https://github.com/EAimTY/tuic
- **Reality Protocol:** https://github.com/XTLS/REALITY
- **GFW Report (исследования):** https://gfw.report/

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [Обфускация](07_obfuscation_enhancement.md)

---

*Документ создан: 2026-02-20. Версия проекта: v5.24.*
*Обновлён: 2026-02-23 — SSH-верификация на ikenibornvpn. Исправлены: статус Tier 1 (→ РЕАЛИЗОВАНО), архитектура Tier 2 (Nginx tier2 вместо HAProxy TLS termination), gap-анализ секции 5.2, риск R6 (→ закрыт), timeline 10.1.*
*Обновлён: 2026-02-22 — Добавлен анализ совместимости iOS клиента v2rayTun (раздел 6.4 + Приложение А). v2rayTun v2.4.4, Xray-core 25.10.15. XTLS Vision ✅, WS ✅, gRPC ✅, XHTTP ⚠️.*
*Автор: Agent-Orchestrator Pipeline + live-server SSH verification.*

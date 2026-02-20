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
| **Немедленно** | XTLS Vision | Низкие | Высокая | Доступно в Xray, не включено |
| **Краткосрочно** | XHTTP/SplitHTTP | Средние | Высокая (CDN) | Новый транспорт Xray >= 24.9 |
| **Краткосрочно** | WebSocket + TLS | Средние | Средняя | CDN-совместимо |
| **Среднесрочно** | gRPC Transport | Средние | Средняя | HTTP/2 требует TLS termination |
| **Долгосрочно** | Hysteria2 | Высокие | Высокая | UDP, отдельный контейнер |
| **Долгосрочно** | TUIC v5 | Высокие | Высокая | UDP, отдельный контейнер |
| **Стратегически** | SingBox | Высокие | Протокол-зависимо | Параллельный рантайм |

### Рекомендация

Реализовать **четырёхуровневый подход**:
1. **Tier 1 (v5.25):** XTLS Vision — одно JSON-поле, максимальная отдача
2. **Tier 2 (v5.3x):** WebSocket+TLS, gRPC, XHTTP как дополнительные inbound-ы
3. **Tier 3 (v6.x):** Hysteria2 + TUIC как opt-in контейнеры (по образцу MTProxy)
4. **Tier 4 (v7.x):** SingBox как параллельный рантайм

---

## 2. Текущая архитектура: VLESS + Reality

### 2.1 Обзор текущей реализации

**Версия:** v5.24
**Протокол:** VLESS + Reality (Xray-core 24.11.30)
**Транспорт:** TCP only
**Порт:** 443 (через HAProxy SNI passthrough)

```
Клиент (Reality Client)
    │
    │ TCP:443 → ClientHello (маскировка под HTTPS к dest-домену)
    ▼
HAProxy (vless_haproxy)
    │ SNI passthrough (NO TLS termination для Reality)
    │ ACL: req_ssl_sni -i vless.example.com → backend xray_vless
    ▼
Xray (vless_xray, port 8443)
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
      "fallbacks": [{ "dest": "vless_fake_site:80" }]
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

| Ограничение | Описание | Критичность |
|-------------|---------|-------------|
| TCP-only transport | `streamSettings.network` = "tcp" жёстко задан | Средняя |
| XTLS Vision не включён | `flow: "xtls-rprx-vision"` отсутствует у клиентов | Низкая |
| Нет CDN-совместимости | Reality не работает через Cloudflare и большинство CDN | Средняя |
| UDP не поддерживается | HAProxy и текущая архитектура — TCP only | Высокая |
| Единственный inbound | Один режим подключения — точка отказа | Средняя |

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
vless_hysteria2 (отдельный контейнер)
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
HAProxy (vless_haproxy)
    ├─ SNI: vless.domain → Xray (Reality)
    ├─ SNI: singbox.domain → SingBox VLESS/Trojan/etc.
    └─ SNI: *.domain → Nginx (reverse proxy)

vless_singbox (новый контейнер)
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
| **XTLS Vision** | ★★★★★ | ✗ | ✗ | Низкие | Доступен, не включён |
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

### 5.2 XTLS Vision gap

**Текущее состояние:** Clients в `xray_config.json`:
```json
"clients": [{
  "id": "uuid",
  "level": 0
  // ← отсутствует поле "flow"
}]
```

**Что нужно добавить:**
```json
"clients": [{
  "id": "uuid",
  "flow": "xtls-rprx-vision",  // ← единственное изменение
  "level": 0
}]
```

### 5.3 UDP/QUIC gap

**Текущее состояние:** Все контейнеры используют TCP. `docker-compose.yml` не содержит UDP port mapping. HAProxy работает только в `mode tcp` (TCP-level LB).

**Что требуется для Hysteria2/TUIC:**
1. Новый контейнер `vless_hysteria2` (или `vless_singbox`)
2. UDP port mapping: `"443:443/udp"` или `"8443:8443/udp"`
3. UFW правила: `ufw allow 8443/udp`
4. Отдельный Docker network или прямой host binding
5. HAProxy не участвует в UDP routing

### 5.4 CDN-доступности gap

**Текущее состояние:** Reality не работает через CDN (Cloudflare, etc.) потому что CDN терминирует TLS и не пропускает RAW TLS traffic.

**Что нужно:** Хотя бы один CDN-совместимый transport (WebSocket, gRPC или XHTTP) за Nginx/HAProxy, который сможет работать через Cloudflare proxied DNS.

### 5.5 Архитектурные ограничения

```
ТЕКУЩАЯ АРХИТЕКТУРА:
┌─────────────────────────────────────────────────────────┐
│ HAProxy (TCP only, mode tcp)                            │
│  Port 443: SNI passthrough → Xray Reality (TCP:8443)   │
│  Port 1080: TLS term → Xray SOCKS5 (TCP:10800)         │
│  Port 8118: TLS term → Xray HTTP (TCP:18118)           │
└─────────────────────────────────────────────────────────┘

ОГРАНИЧЕНИЯ:
  ✗ HAProxy не маршрутизирует UDP → Hysteria2/TUIC невозможен без bypass
  ✗ mode tcp на порту 443 конфликтует с mode http (нужен для gRPC)
  ✗ Все инбаунды share порт 443 через SNI → новые транспорты нужны на новых портах
     (или отдельные subdomains через SNI)
```

---

## 6. Риски и ограничения

### 6.1 Архитектурные риски

| ID | Риск | Severity | Mitigation |
|----|------|----------|-----------|
| **R1** | Новые инбаунды (WS, gRPC) требуют новых Docker-портов и HAProxy изменений | Medium | Использовать SNI-subdomain routing: `ws.domain → Xray WebSocket backend`. Один HAProxy frontend на порту 443 маршрутизирует по SNI к разным backends. |
| **R2** | Hysteria2/TUIC требуют UDP — несовместимы с HAProxy TCP-архитектурой | High | Отдельный контейнер с прямым UDP port exposure (bypass HAProxy). Аналогично MTProxy pattern (`lib/mtproxy_manager.sh`). |
| **R3** | SingBox как замена Xray потребует полной переработки конфигурационных модулей | High | Реализовывать SingBox как **параллельный** контейнер, не замену. Пользователь выбирает: Xray (Reality) ИЛИ SingBox (multi-protocol). |
| **R4** | WebSocket на порту 443 конфликтует с Reality SNI passthrough | Medium | Subdomain routing: `vless.domain → Reality/Xray`, `ws.domain → WebSocket/Xray`. Оба через HAProxy SNI ACL. |
| **R5** | gRPC требует HTTP/2 и HAProxy `mode http`, несовместимо с текущим `mode tcp` на порту 443 | Medium | gRPC inbound на отдельном порту (8444) с отдельным HAProxy frontend в `mode http`. ИЛИ gRPC через Nginx reverse proxy (добавить backend в `vless_nginx_reverseproxy`). |
| **R6** | GFW детектирует VLESS+Reality по timing analysis (без XTLS Vision) | Low | Включить `flow: "xtls-rprx-vision"` в server и client конфигурациях — минимальные изменения, максимальный эффект. |

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
| VLESS+Reality | Shadowrocket, Sing-Box | v2rayNG, Sing-Box | v2rayN, Xray | ClashX, Sing-Box | Xray CLI |
| VLESS+WebSocket | То же | То же | То же | То же | То же |
| VLESS+gRPC | То же | То же | То же | То же | То же |
| Hysteria2 | Sing-Box | Sing-Box, NekoBox | v2rayN, Hysteria | Sing-Box | Hysteria CLI |
| TUIC v5 | Sing-Box | Sing-Box | Sing-Box | Sing-Box | tuic-client |

---

## 7. Четырёхуровневый план доработки

### 7.1 Tier 1: Немедленные улучшения (XTLS Vision)

**Версия:** v5.25
**Усилия:** Низкие (1-2 дня)
**Риск:** Низкий
**Влияние:** Высокое (улучшение DPI-стойкости для всех пользователей Reality)

**Изменения:**

1. **`lib/orchestrator.sh` (generate_xray_config_json):** Добавить `"flow": "xtls-rprx-vision"` в client объекты внутри inbound settings.

2. **`lib/user_management.sh` (add_user):** Добавить `"flow"` в пользовательский объект при создании.

3. **Клиентские конфигурации:** Обновить шаблоны VLESS-ссылок — добавить параметр `flow=xtls-rprx-vision` в URI.

4. **Проверка:** Убедиться что Xray образ `teddysun/xray:24.11.30` поддерживает XTLS Vision (поддерживает начиная с Xray-core 1.8.0).

**Ожидаемый результат:** Уменьшение энтропийных аномалий в первых пакетах сессии → лучшее прохождение через ML-classifiers GFW.

---

### 7.2 Tier 2: Расширение транспортов (WS, gRPC, XHTTP)

**Версия:** v5.3x
**Усилия:** Средние (2-4 недели)
**Риск:** Средний (архитектурные изменения HAProxy)
**Влияние:** Высокое (CDN-совместимость)

**Подэтап 2a: WebSocket + TLS (приоритет)**

1. Новый Xray inbound на внутреннем порту (8444) с `network: "ws"`
2. HAProxy SNI routing: `ws.example.com → xray_websocket backend (8444)`
3. HAProxy TLS termination для WS inbound (не passthrough как Reality)
4. Генератор клиентских конфигов для WS transport
5. CLI команда: `vless add-transport ws <subdomain>`

**Подэтап 2b: XHTTP/SplitHTTP (высокий приоритет)**

1. Новый Xray inbound с `network: "splithttp"` (требует Xray >= 24.9 — уже используется 24.11.30)
2. Nginx конфигурация для проксирования XHTTP (или HAProxy в http mode)
3. CDN-инструкция: как настроить Cloudflare для XHTTP

**Подэтап 2c: gRPC (средний приоритет)**

1. Новый Xray inbound с `network: "grpc"` на внутреннем порту (8445)
2. HAProxy frontend в `mode http` с `h2` ALPN support
3. Или: Nginx с gRPC proxy (`grpc_pass`)

**Новые CLI-команды:**
```bash
sudo vless add-transport ws subdomain.example.com
sudo vless add-transport xhttp subdomain.example.com
sudo vless add-transport grpc subdomain.example.com
sudo vless list-transports
sudo vless remove-transport ws
```

---

### 7.3 Tier 3: UDP-протоколы как opt-in (Hysteria2, TUIC)

**Версия:** v6.x
**Усилия:** Высокие (4-6 недель)
**Риск:** Высокий (новая архитектура, UDP exposure)
**Влияние:** Очень высокое (плохие сети, Китай)

**Архитектура:** По образцу MTProxy (`lib/mtproxy_manager.sh` + `docker/mtproxy/`):

```
Новые файлы:
  lib/hysteria2_manager.sh        # Управление Hysteria2 контейнером
  lib/tuic_manager.sh             # Управление TUIC контейнером
  docker/hysteria2/               # Dockerfile + entrypoint
  docker/tuic/                    # Dockerfile + entrypoint
  scripts/vless-hysteria2         # CLI для Hysteria2
  scripts/vless-tuic              # CLI для TUIC

Изменения docker-compose.yml:
  vless_hysteria2:
    image: tobyxdd/hysteria:latest
    ports:
      - "8443:8443/udp"  # Прямой UDP, bypass HAProxy
    profiles: ["hysteria2"]  # Opt-in, не стартует по умолчанию

UFW правила:
  ufw allow 8443/udp comment 'Hysteria2'
```

**Установка (opt-in wizard):**
```bash
sudo vless install-hysteria2
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

Контейнер vless_singbox:
  - VLESS+Reality (дублирует Xray, для A/B тестирования)
  - Hysteria2 (заменяет отдельный vless_hysteria2)
  - TUIC v5 (заменяет отдельный vless_tuic)
  - Trojan+WebSocket+TLS
```

**Обоснование стратегического значения:** SingBox активно развивается и в перспективе станет основной платформой для обхода блокировок. Ранняя интеграция как opt-in обеспечит плавный переход.

---

## 8. Технические спецификации Tier 1-2

### 8.1 XTLS Vision: изменения конфигурации

**Изменение в Xray inbound** (функция `generate_xray_config_json()` в `lib/orchestrator.sh`):

```json
{
  "inbounds": [{
    "port": 8443,
    "protocol": "vless",
    "tag": "vless-reality",
    "settings": {
      "clients": [{
        "id": "${USER_UUID}",
        "flow": "xtls-rprx-vision",
        "level": 0
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": { ... }
    }
  }]
}
```

**Изменение в client URI** (функция генерации VLESS-ссылки в `lib/user_management.sh`):

```
# Формат VLESS URI без Vision:
vless://${UUID}@${SERVER}:443?type=tcp&security=reality&...

# Формат VLESS URI с Vision:
vless://${UUID}@${SERVER}:443?type=tcp&security=reality&flow=xtls-rprx-vision&...
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

**HAProxy конфигурация для WebSocket** (добавить в `haproxy.cfg`):

```haproxy
# Frontend для WebSocket subdomain (SNI routing)
# Добавляется в секцию DYNAMIC_REVERSE_PROXY_ROUTES

acl is_vless_ws req_ssl_sni -i ws.example.com
use_backend xray_websocket if is_vless_ws

# Backend
backend xray_websocket
    mode tcp
    server xray vless_xray:8444 check inter 10s fall 3 rise 2
```

**Клиентский URI для WebSocket:**
```
vless://${UUID}@ws.example.com:443?type=ws&path=/vless-ws&security=tls&sni=ws.example.com
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

**HAProxy конфигурация:**

```haproxy
acl is_vless_xhttp req_ssl_sni -i xhttp.example.com
use_backend xray_xhttp if is_vless_xhttp

backend xray_xhttp
    mode tcp
    server xray vless_xray:8445 check inter 10s fall 3 rise 2
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

**Nginx конфигурация для gRPC proxy** (альтернатива HAProxy `mode http`):

```nginx
server {
    listen 8446 ssl http2;
    server_name grpc.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location /GunService/ {
        grpc_pass grpc://vless_xray:8446;
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
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
2026 Q1: Tier 1 — XTLS Vision
├── v5.25: Enable flow=xtls-rprx-vision для всех новых пользователей
├── v5.26: Миграция существующих пользователей (CLI команда)
└── v5.27: Документация и клиентские инструкции

2026 Q2: Tier 2 — WebSocket + XHTTP
├── v5.30: WebSocket transport (lib/orchestrator.sh + HAProxy)
├── v5.31: XHTTP/SplitHTTP transport
├── v5.32: gRPC transport
└── v5.33: CLI управление транспортами + документация

2026 Q3-Q4: Tier 3 — UDP Protocols
├── v6.0: Hysteria2 opt-in контейнер
├── v6.1: TUIC v5 opt-in контейнер
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
- [ ] `flow: "xtls-rprx-vision"` добавлен в `generate_xray_config_json()` для новых inbound-ов
- [ ] `flow` добавлен в user management (`add_user()`)
- [ ] VLESS URI обновлён с параметром `flow=xtls-rprx-vision`
- [ ] Клиентская документация обновлена (рекомендуемые настройки Shadowrocket, v2rayNG)
- [ ] Тест TC-01 и TC-02 пройдены

**Tier 2 (Транспорты) — Definition of Done:**
- [ ] Новые inbound-ы добавлены в `generate_xray_config_json()` с флагом включения
- [ ] HAProxy ACL/backend добавляются автоматически при `vless add-transport`
- [ ] Клиентские конфигурации генерируются для каждого транспорта
- [ ] Тест TC-10 до TC-36 пройдены
- [ ] Документация обновлена

**Tier 3 (UDP) — Definition of Done:**
- [ ] `vless install-hysteria2` wizard работает
- [ ] UDP ports безопасно изолированы (fail2ban, UFW)
- [ ] Клиентские конфигурации SingBox format генерируются автоматически
- [ ] Тест TC-40 до TC-45 пройдены

---

## Приложение А: Клиентские приложения

| Платформа | Приложение | Поддерживаемые протоколы |
|-----------|-----------|--------------------------|
| iOS | Shadowrocket | Reality, WebSocket, gRPC |
| iOS | Sing-Box | Все, включая Hysteria2, TUIC |
| Android | v2rayNG | Reality, WebSocket, gRPC |
| Android | Sing-Box / NekoBox | Все, включая Hysteria2, TUIC |
| Windows | v2rayN | Reality, WebSocket, gRPC, Hysteria2 |
| macOS | ClashX Pro | Reality, WebSocket, gRPC |
| macOS/Linux | Sing-Box CLI | Все протоколы |
| Linux | Xray CLI | Reality, WebSocket, gRPC, XHTTP |

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

*Документ создан: 2026-02-20. Версия проекта: v5.24. Автор: Agent-Orchestrator Pipeline (Researcher → Critic → Planner → Executor).*

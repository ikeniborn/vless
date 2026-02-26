# Implementation Plan: XTLS Vision (Tier 1 v5.25) + WebSocket/XHTTP/gRPC (Tier 2 v5.3x)

**Создан:** 2026-02-23
**Версия проекта:** v5.24 → v5.25 (Tier 1), v5.25 → v5.33 (Tier 2)
**Источник:** Agent Orchestrator Pipeline (Researcher → Critic → Planner)
**Рабочий workspace:** `.claude/workspace/2026-02-23T0032/`
**Статус:** PLAN ONLY — не выполнять без явного подтверждения

---

## ОГЛАВЛЕНИЕ

1. [Краткое резюме](#1-краткое-резюме)
2. [Результаты верификации (Tier 1)](#2-результаты-верификации-tier-1)
3. [Архитектурный анализ](#3-архитектурный-анализ)
4. [Риски и митигации](#4-риски-и-митигации)
5. [**Phase 0: Миграция HAProxy → единый Nginx (v5.30)**](#5-phase-0-миграция-haproxy--единый-nginx-v530)
6. [Phase 1: Tier 1 — Завершение XTLS Vision (v5.25)](#6-phase-1-tier-1--завершение-xtls-vision-v525)
7. [Phase 2: Tier 2 — Транспортная инфраструктура (v5.30-v5.32)](#7-phase-2-tier-2--транспортная-инфраструктура-v530-v532)
8. [Phase 3: Tier 2 — Transport Management CLI (v5.33)](#8-phase-3-tier-2--transport-management-cli-v533)
9. [Тестирование и валидация](#9-тестирование-и-валидация)
10. [Процедура отката](#10-процедура-отката)
11. [Definition of Done](#11-definition-of-done)

---

## СТАТУС ВЕРИФИКАЦИИ (SSH ikenibornvpn, 2026-02-23)

**Live Server:** `ikenibornvpn` | Docker: `familytraffic`, `familytraffic`, `familytraffic (healthy)`, `watchtower`, `shadowbox`

| Проверка | Результат |
|----------|-----------|
| Контейнеры запущены | ✓ `familytraffic`, `familytraffic` (healthy), `familytraffic` — 3 недели uptime |
| `familytraffic-nginx` | ✗ **НЕ ЗАПУЩЕН** — reverse proxy отключён при установке |
| xray inbounds count | 3 (reality:8443, socks5:10800, http:18118) |
| Users in xray_config | 7 клиентов |
| **flow: xtls-rprx-vision** | **✅ ВСЕ 7 ПОЛЬЗОВАТЕЛЕЙ УЖЕ ИМЕЮТ flow** |
| users.json schema fields | `connection_type, created, fingerprint, shortId, username, uuid, external_proxy_id` (без поля flow — это норма) |
| HAProxy frontend 443 | `mode tcp`, SNI passthrough, **нет ACLs для субдоменов**, только `default_backend xray_vless` |
| HAProxy backends | `xray_vless:8443`, `xray_socks5_plaintext:10800`, `xray_http_plaintext:18118` |
| Docker expose Xray | `8443, 10800, 18118` (без 8444/8445/8446) |

### Критические исправления к исходному плану

| # | Уровень | Проблема | Влияние |
|---|---------|----------|---------|
| **P1** | 🔴 КРИТИЧЕСКАЯ | WS/XHTTP inbounds не имеют `tlsSettings` — HAProxy делает `mode tcp` passthrough, Xray не сможет декодировать TLS | WS/XHTTP клиенты не подключатся |
| **P2** | 🔴 КРИТИЧЕСКАЯ | `familytraffic-nginx` не существует на сервере — нужен новый контейнер для TLS-терминации Tier 2 | gRPC не запустится |
| **P3** | 🔴 КРИТИЧЕСКАЯ | `generate_haproxy_config()` параметр $5 занят `enable_reverse_proxy` — план предлагает ws_subdomain как $5, что ломает существующий код | Коллизия параметров |
| **P4** | 🟡 СРЕДНЯЯ | `generate_transport_uri()` в case `reality` обращается к `$username` — переменная не определена в scope функции | Runtime ошибка |
| **P5** | 🟡 СРЕДНЯЯ | HAProxy backend для WS/XHTTP указывает на Xray (8444/8445) напрямую, но TLS терминируется в Nginx → бэкенд должен указывать на Nginx | Неправильная архитектура |
| **P6** | 🟡 СРЕДНЯЯ | Tier 1 на живом сервере **полностью реализован** — все 7 пользователей уже имеют flow. Migrate функция полезна только для edge cases | Переоценён объём работ Tier 1 |
| **P7** | 🟡 СРЕДНЯЯ | Nginx конфиг в Step 2.6 только для gRPC — нужен общий Tier 2 Nginx, обслуживающий WS + XHTTP + gRPC | Неполная архитектура |
| **P8** | 🟢 МАЛАЯ | `migrate_users_schema_v525()` находится на строке 1797, а не ~1851 как указано в плане | Неточная ссылка |

---

## 1. Краткое резюме

### Что реализуется

| Phase | Версия | Изменения | Файлы | Примечание |
|-------|--------|-----------|-------|------------|
| **Phase 0** | v5.30 | **Миграция HAProxy → единый Nginx.** `familytraffic-nginx` (stream+http) заменяет `familytraffic` + `familytraffic-nginx_tier2`. Cert renewal hook упрощается. | 4 файла | Предпосылка для Phase 2 |
| **Phase 1** | v5.25 | ~~XTLS Vision~~ уже реализован. Остаток: исправить `validate_vless_uri()` (flow conditional), добавить `test_xtls_vision_enabled()` (TC-01), safety-net `migrate_xtls_vision()` | 2 файла | 95% выполнено на сервере |
| **Phase 2** | v5.30-v5.33 | WS/XHTTP/gRPC inbounds в Xray + extend `familytraffic-nginx` (Phase 0) Tier 2 http-блоком + CLI управление. **`familytraffic-nginx_tier2` НЕ нужен** — всё в одном контейнере | 5 новых/изменённых файлов | Строится на Phase 0 |

### Ключевое открытие верификации

**Tier 1 ПОЛНОСТЬЮ РЕАЛИЗОВАН** (подтверждено SSH на живом сервере):
- `lib/user_management.sh` строка 524: `"flow": "xtls-rprx-vision"` добавляется в `add_user_to_json()` ✓
- `lib/user_management.sh` строка 834: `flow=xtls-rprx-vision` добавляется в `generate_vless_uri()` ✓
- **Все 7 пользователей на сервере уже имеют `flow: "xtls-rprx-vision"` в xray_config.json** ✓

**Что ещё нужно для Tier 1:**
1. ~~Инструмент миграции~~ — не критично для текущего сервера (все юзеры уже мигрированы), добавляется как safety-net
2. Исправление `validate_vless_uri()` — убрать `flow` из обязательных params (сломает Tier 2)
3. Тест-покрытие (TC-01, TC-02)

---

## 2. Результаты верификации (Tier 1)

### Проверка текущего состояния кода

#### `lib/user_management.sh` — add_user_to_json()
```bash
# Строки 521-525: flow уже добавляется к новым пользователям
jq ".inbounds[0].settings.clients += [{
    \"id\": \"$uuid\",
    \"email\": \"${username}@vless.local\",
    \"flow\": \"xtls-rprx-vision\"   # ← УЖЕ ЕСТЬ
}]" "$XRAY_CONFIG" > "$temp_file"
```
**Статус: РЕАЛИЗОВАНО для новых пользователей**

#### `lib/user_management.sh` — generate_vless_uri()
```bash
# Строки 832-834: flow добавляется в URI
local uri="vless://${uuid}@${server_ip}:${server_port}?"
uri+="encryption=none"
uri+="&flow=xtls-rprx-vision"   # ← УЖЕ ЕСТЬ
```
**Статус: РЕАЛИЗОВАНО для новых URI**

#### `lib/qr_generator.sh` — validate_vless_uri()
```bash
# Строка 95: flow является обязательным параметром
local required_params=("encryption" "flow" "security" "sni" "fp" "pbk" "sid" "type")
#                                     ↑ Это сломает Tier 2 транспорты (WS, gRPC, XHTTP не используют flow)
```
**Статус: ТРЕБУЕТ ИСПРАВЛЕНИЯ**

#### `lib/orchestrator.sh` — create_xray_config()
```bash
# Строки 617-624: начальный clients массив пустой — flow не нужен в шаблоне
"settings": {
    "clients": [],   # ← add_user_to_json() добавит flow при создании пользователя
```
**Статус: OK — изменений не требуется для Tier 1**

---

## 3. Архитектурный анализ

### Текущая архитектура (v5.24)

```
Client (VLESS Reality)
    │ TCP:443 (с flow=xtls-rprx-vision в новых версиях)
    ▼
HAProxy familytraffic (SNI passthrough, mode tcp)
    │ default_backend → xray_vless (Reality не имеет server SNI)
    ▼
Xray familytraffic:8443 (VLESS + Reality)
    │ flow: xtls-rprx-vision (новые пользователи)
    ▼
Internet
```

### Целевая архитектура (Phase 0 + Tier 2) — Вариант A: единый Nginx

> **Изменение vs. исходного плана:** Phase 0 вводит `familytraffic-nginx` (nginx stream+http), который полностью заменяет `familytraffic`. Phase 2 расширяет его Tier 2 http-блоком. `familytraffic-nginx_tier2` как отдельный контейнер НЕ нужен.

```
Client → TCP:443 / TCP:1080 / TCP:8118
    │
    ▼
familytraffic-nginx [Phase 0 — заменяет familytraffic]
    │
    ├─ stream: listen 443 (ssl_preread, NO TLS termination)
    │    ├─ SNI: ws.domain, xhttp.domain, grpc.domain → loopback 127.0.0.1:8448
    │    └─ SNI: (default / Reality clients)          → familytraffic:8443 (passthrough)
    │
    ├─ stream: listen 1080 ssl (TLS termination)      → familytraffic:10800 (SOCKS5 plaintext)
    ├─ stream: listen 8118 ssl (TLS termination)      → familytraffic:18118 (HTTP proxy plaintext)
    │
    └─ http: listen 8448 ssl http2 (Phase 2 — Tier 2 TLS termination, loopback target)
         ├─ server_name ws.domain    → proxy_pass http://familytraffic:8444 (WebSocket)
         ├─ server_name xhttp.domain → proxy_pass http://familytraffic:8445 (XHTTP)
         └─ server_name grpc.domain  → grpc_pass grpc://familytraffic:8446  (gRPC)
    │
    ▼
familytraffic (внутренние порты — только plaintext, без TLS)
    ├─ Port 8443: VLESS Reality (existing, TLS через Reality)
    ├─ Port 8444: VLESS WebSocket plaintext (Phase 2, new)
    ├─ Port 8445: VLESS XHTTP/SplitHTTP plaintext (Phase 2, new)
    └─ Port 8446: VLESS gRPC plaintext (Phase 2, new)

familytraffic — ОСТАЁТСЯ отдельным (fallback для Reality, нельзя объединять)
```

**Ключевые отличия от исходного плана:**
- `familytraffic` **удалён**, `familytraffic-nginx` его полностью заменяет
- `familytraffic-nginx_tier2` **не создаётся** — Tier 2 http-блок живёт в том же `familytraffic-nginx`
- Loopback 127.0.0.1:8448 внутри контейнера маршрутизирует Tier 2 из stream в http
- `combined.pem` (HAProxy-формат) **не нужен** — Nginx использует fullchain.pem + privkey.pem отдельно

### Зависимости между файлами

```
scripts/vless
    ├── lib/user_management.sh (create_user, migrate_xtls_vision, generate_transport_uri)
    ├── lib/transport_manager.sh [NEW] (add_transport, list_transports, remove_transport)
    └── lib/haproxy_config_manager.sh (reload HAProxy after transport change)

lib/orchestrator.sh (create_xray_config)
    ├── lib/orchestrator.sh (generate_websocket_inbound_json) [NEW FUNCTION]
    ├── lib/orchestrator.sh (generate_xhttp_inbound_json) [NEW FUNCTION]
    └── lib/orchestrator.sh (generate_grpc_inbound_json) [NEW FUNCTION]

lib/haproxy_config_manager.sh (generate_haproxy_config)
    └── Reads: VLESS_DOMAIN, WS_SUBDOMAIN, XHTTP_SUBDOMAIN env vars

lib/docker_compose_generator.sh (generate_docker_compose)
    └── Reads: ENABLE_TIER2_TRANSPORTS flag
```

---

## 4. Риски и митигации

| ID | Риск | Severity | Фаза | Митигация |
|----|------|----------|------|-----------|
| **R1** | `validate_vless_uri()` требует `flow` для всех транспортов — сломает WS/gRPC/XHTTP URI | Medium | Phase 1 Step 2 | Сделать `flow` условным: проверять только если `security=reality` в URI |
| **R2** | Порты 8444/8445/8446 нужны в `expose` docker-compose для Xray — Nginx должен до них добраться | **High** | Phase 2 Step 7 | Добавить expose 8444/8445/8446 условно при `ENABLE_TIER2_TRANSPORTS=true` |
| ~~**R3**~~ | ~~gRPC требует HAProxy `mode http` — конфликт с текущим `mode tcp` на порту 443~~ | ~~High~~ | — | ✅ **ЗАКРЫТ Phase 0** — HAProxy удалён. Nginx `grpc_pass` в http-блоке работает без конфликтов |
| ~~**R4**~~ | ~~WebSocket SNI ACL может конфликтовать с Reality default_backend~~ | ~~Medium~~ | — | ✅ **ЗАКРЫТ Phase 0** — Nginx stream `map` не имеет проблемы порядка ACL; `default familytraffic:8443` срабатывает только если нет совпадений |
| **R5** | Существующие пользователи без `flow` поля в `xray_config.json` | Low | Phase 1 Steps 3+5 | Функция `migrate_xtls_vision()` + команда `vless migrate-vision` (на текущем сервере — уже не нужна) |
| **R6** | QR-код для Tier 2 генерирует неправильный URI формат | Medium | Phase 1 Step 4 | Функция `generate_transport_uri(transport_type)` — transport-aware URI |
| ~~**R7**~~ | ~~WS/XHTTP inbounds без TLS — если HAProxy делает mode-tcp passthrough, Xray на 8444/8445 получит raw TLS~~ | ~~CRITICAL~~ | — | ✅ **ЗАКРЫТ Phase 0** — HAProxy удалён. Nginx stream `ssl_preread` пробрасывает Reality TLS на `familytraffic:8443` без разрыва; Tier 2 http-блок (порт 8448) терминирует TLS для WS/XHTTP/gRPC |
| ~~**R8**~~ | ~~`familytraffic-nginx` не существует на живом сервере — reverse proxy был отключён при установке~~ | ~~CRITICAL~~ | — | ✅ **ЗАКРЫТ Phase 0** — Отдельный контейнер не нужен. Tier 2 http-блок встроен в основной `familytraffic-nginx` (loopback route: stream port 443 → 127.0.0.1:8448 → http block) |
| ~~**R9**~~ | ~~`generate_haproxy_config()` $5 = `enable_reverse_proxy` — добавление ws_subdomain как $5 сломает существующий функционал~~ | ~~HIGH~~ | — | ✅ **ЗАКРЫТ Phase 0** — `generate_haproxy_config()` больше не используется; `generate_nginx_config()` ($1=cert_domain, $2=enable_tier2, $3=ws_sub, $4=xhttp_sub, $5=grpc_sub) — чистая сигнатура без конфликтов |
| **R10** | 🆕 **`generate_transport_uri()` — undefined `$username`** в case `reality`: вызов `generate_vless_uri "$username" "$uuid"` — $username не в scope функции | Medium | Phase 1 Step 4 | Добавить параметр `$6=username` в сигнатуру функции |
| **R11** | 🆕 **XHTTP на iOS (v2rayTun)** — XHTTP подтверждён на Android v3.9.34 (август 2024), но на iOS не задокументирован явно (App Store changelog не упоминает явно) | Medium | Phase 2 Step 2 (v5.31) | Обязательное ручное тестирование XHTTP с реальным устройством iOS + v2rayTun перед release v5.31; при необходимости — WebSocket как fallback для iOS |

---

## 5. Phase 0: Миграция HAProxy → единый Nginx (v5.30)

**Версия:** v5.30
**Риск:** Medium (замена работающего компонента)
**Файлы:**
- `lib/nginx_stream_generator.sh` **[NEW]** — заменяет `lib/haproxy_config_manager.sh`
- `lib/docker_compose_generator.sh` **[MODIFY]** — haproxy → familytraffic-nginx сервис
- `lib/orchestrator.sh` **[MODIFY]** — вызовы haproxy → nginx
- `scripts/certbot-renewal-hook.sh` **[MODIFY]** — убрать combined.pem, nginx -s reload

> **Почему Phase 0 раньше Phase 1:** Phase 0 (v5.30) — архитектурная предпосылка для Phase 2 Tier 2 транспортов. Phase 1 (v5.25) — небольшой исправляющий патч, который можно сделать в любом порядке. Оба должны быть выполнены до Phase 2.

---

### Step 0.1: Создать lib/nginx_stream_generator.sh

**Новый файл:** `lib/nginx_stream_generator.sh`
**Назначение:** Генерирует `/opt/familytraffic/config/nginx/nginx.conf` — полный конфиг с stream + http блоками.

```bash
# ============================================================================
# FUNCTION: generate_nginx_config (v5.30)
# ============================================================================
# Description: Generate complete nginx.conf replacing haproxy.cfg
#   stream block: SNI routing (port 443), TLS termination (1080, 8118)
#   http block:   Tier 2 transports (port 8448, populated by Phase 2)
# Arguments:
#   $1 - cert_domain: domain for LE cert (e.g., proxy.ikeniborn.ru)
#   $2 - enable_tier2: "true"/"false" — include http block placeholder
#   $3 - ws_subdomain: WebSocket subdomain (optional, Phase 2)
#   $4 - xhttp_subdomain: XHTTP subdomain (optional, Phase 2)
#   $5 - grpc_subdomain: gRPC subdomain (optional, Phase 2)
# ============================================================================
generate_nginx_config() {
    local cert_domain="${1}"
    local enable_tier2="${2:-false}"
    local ws_subdomain="${3:-}"
    local xhttp_subdomain="${4:-}"
    local grpc_subdomain="${5:-}"

    local cert_path="/etc/letsencrypt/live/${cert_domain}"

    cat <<EOF
# nginx.conf — familytraffic-nginx (v5.30, replaces haproxy.cfg)
# Generated by lib/nginx_stream_generator.sh

user nginx;
worker_processes auto;

events {
    worker_connections 65536;
    use epoll;
    multi_accept on;
}

# =============================================================================
# Stream block: L4 routing (replaces HAProxy mode tcp)
# =============================================================================
stream {
    # Log format for stream (no access_log by default in stream module)
    error_log /var/log/nginx/stream_error.log warn;

    # SNI map: Tier 2 subdomains → loopback http block; Reality → Xray passthrough
    map \$ssl_preread_server_name \$backend_addr {
$(if [[ -n "$ws_subdomain" ]]; then
    echo "        ${ws_subdomain}    127.0.0.1:8448;"
fi)
$(if [[ -n "$xhttp_subdomain" ]]; then
    echo "        ${xhttp_subdomain} 127.0.0.1:8448;"
fi)
$(if [[ -n "$grpc_subdomain" ]]; then
    echo "        ${grpc_subdomain}  127.0.0.1:8448;"
fi)
        default                 familytraffic:8443;  # Reality passthrough (no TLS termination)
    }

    # -------------------------------------------------------------------------
    # Port 443: SNI routing (NO TLS termination — Reality requires passthrough)
    # -------------------------------------------------------------------------
    server {
        listen 443;
        ssl_preread on;
        proxy_pass \$backend_addr;
        proxy_connect_timeout 10s;
        proxy_timeout 300s;
    }

    # -------------------------------------------------------------------------
    # Port 1080: SOCKS5 with TLS termination (replaces HAProxy frontend socks5_tls)
    # -------------------------------------------------------------------------
    server {
        listen 1080 ssl;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        ssl_ciphers         TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384;
        proxy_pass          familytraffic:10800;   # plaintext SOCKS5 to Xray
        proxy_connect_timeout 10s;
        proxy_timeout        300s;
    }

    # -------------------------------------------------------------------------
    # Port 8118: HTTP proxy with TLS termination (replaces HAProxy frontend http_tls)
    # -------------------------------------------------------------------------
    server {
        listen 8118 ssl;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        ssl_ciphers         TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384;
        proxy_pass          familytraffic:18118;   # plaintext HTTP proxy to Xray
        proxy_connect_timeout 10s;
        proxy_timeout        300s;
    }
}

# =============================================================================
# HTTP block: Tier 2 transports (Phase 2 populates this)
# Port 8448: loopback target from stream SNI map (Tier 2 subdomains)
# =============================================================================
http {
    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    # Default server — reject unknown hosts (active probing protection)
    server {
        listen 8448 ssl default_server;
        http2 on;
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        server_name         _;
        return 444;
    }
$(if [[ -n "$ws_subdomain" ]]; then
cat <<WS_BLOCK
    # WebSocket Transport (Phase 2 / v5.30)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${ws_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /vless-ws {
            proxy_pass http://familytraffic:8444;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_read_timeout 300s;
        }
    }
WS_BLOCK
fi)
$(if [[ -n "$xhttp_subdomain" ]]; then
cat <<XHTTP_BLOCK
    # XHTTP/SplitHTTP Transport (Phase 2 / v5.31)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${xhttp_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /api/v2 {
            proxy_pass http://familytraffic:8445;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header Connection "";
            proxy_buffering off;
            client_max_body_size 0;
            proxy_read_timeout 300s;
        }
    }
XHTTP_BLOCK
fi)
$(if [[ -n "$grpc_subdomain" ]]; then
cat <<GRPC_BLOCK
    # gRPC Transport (Phase 2 / v5.32)
    server {
        listen 8448 ssl;
        http2 on;
        server_name ${grpc_subdomain};
        ssl_certificate     ${cert_path}/fullchain.pem;
        ssl_certificate_key ${cert_path}/privkey.pem;
        ssl_protocols       TLSv1.3;
        location /GunService/ {
            grpc_pass grpc://familytraffic:8446;
            grpc_read_timeout 300s;
            grpc_send_timeout 300s;
        }
    }
GRPC_BLOCK
fi)
}
EOF
}
```

**Ключевые архитектурные моменты:**
- `ssl_preread on` на порту 443 читает SNI **без расшифровки** TLS → Reality passthrough сохранён
- Tier 2 субдомены маршрутизируются на `127.0.0.1:8448` (loopback внутри контейнера) → http-блок терминирует TLS
- Порты 1080/8118: `listen ssl` — TLS-терминация в stream-блоке, plaintext к Xray
- `combined.pem` (HAProxy-формат) **не нужен** — используются раздельные `fullchain.pem` и `privkey.pem`

---

### Step 0.2: Обновить docker_compose_generator.sh — заменить haproxy на familytraffic-nginx

**Файл:** `lib/docker_compose_generator.sh`
**Изменение:** Заменить весь блок сервиса `haproxy:` на `familytraffic-nginx:` в heredoc `generate_docker_compose()`

```yaml
# УДАЛИТЬ (haproxy сервис):
  haproxy:
    image: haproxy:2.8-alpine
    container_name: familytraffic
    ...
    volumes:
      - ${VLESS_DIR}/config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ${VLESS_DIR}/logs/haproxy/:/var/log/haproxy/

# ДОБАВИТЬ (familytraffic-nginx сервис):
  familytraffic-nginx:
    image: nginx:1.27-alpine       # contains ngx_stream_module by default
    container_name: familytraffic-nginx
    restart: unless-stopped
    networks:
      - familytraffic_net
    cap_add:
      - NET_BIND_SERVICE            # bind ports < 1024 (443, 1080, 8118)
    ports:
      - "443:443"     # SNI routing (stream, ssl_preread)
      - "1080:1080"   # SOCKS5 with TLS
      - "8118:8118"   # HTTP proxy with TLS
    volumes:
      - ${VLESS_DIR}/config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ${VLESS_DIR}/logs/nginx/:/var/log/nginx/
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    depends_on:
      - xray
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

> **Примечание:** Порт 9000 (HAProxy stats) исчезает. Статистика через `nginx -V` и `docker stats`.

---

### Step 0.3: Обновить orchestrator.sh — haproxy → nginx вызовы

**Файл:** `lib/orchestrator.sh`
**Изменение:** Найти все вызовы `generate_haproxy_config()` и заменить на `generate_nginx_config()`:

```bash
# БЫЛО:
source "${LIB_DIR}/haproxy_config_manager.sh"
generate_haproxy_config "$VLESS_DOMAIN" "$BASE_DOMAIN" "$STATS_PASSWORD" \
    "$ENABLE_PUBLIC_PROXY" "$ENABLE_REVERSE_PROXY"

# СТАЛО:
source "${LIB_DIR}/nginx_stream_generator.sh"
generate_nginx_config "$CERT_DOMAIN" "false"
# Записать в /opt/familytraffic/config/nginx/nginx.conf
mkdir -p "${VLESS_DIR}/config/nginx"
generate_nginx_config "$CERT_DOMAIN" > "${VLESS_DIR}/config/nginx/nginx.conf"
```

---

### Step 0.4: Обновить certbot-renewal-hook — убрать combined.pem

**Файл:** `scripts/certbot-renewal-hook.sh` (или аналог)

```bash
# УДАЛИТЬ (HAProxy требовал combined.pem):
cat /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
    /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
    > /etc/letsencrypt/live/${DOMAIN}/combined.pem
docker exec familytraffic haproxy -sf $(...)  # graceful reload

# ЗАМЕНИТЬ на:
docker exec familytraffic nginx -s reload       # nginx graceful reload (0-downtime)
```

> Nginx поддерживает zero-downtime reload через `nginx -s reload` — рабочие процессы заменяются graceful образом.

---

### Step 0.5: Регрессионные тесты Phase 0

```bash
# 1. Синтаксис nginx конфига
docker exec familytraffic nginx -t

# 2. Reality по-прежнему работает (SNI passthrough)
# Подключиться клиентом через порт 443 — VLESS Reality должен работать

# 3. SOCKS5 TLS-терминация
curl -x socks5h://proxy:PASSWORD@SERVER:1080 https://ipinfo.io

# 4. HTTP proxy TLS-терминация
curl -x https://proxy:PASSWORD@SERVER:8118 https://ipinfo.io

# 5. fake-site fallback
curl -v --resolve "proxy.ikeniborn.ru:443:SERVER_IP" https://proxy.ikeniborn.ru
# Должен вернуть yandex.ru контент (из familytraffic через Xray fallback)

# 6. iOS-00: подключить v2rayTun с прежним URI — нулевой impact
```

---

**Commit message для Phase 0:**
```
feat(infra): replace HAProxy with unified Nginx (stream+http) — v5.30

- Add lib/nginx_stream_generator.sh: generate nginx.conf with stream block
  (port 443 ssl_preread SNI routing, ports 1080/8118 TLS termination)
  and http block placeholder for Tier 2 transports (port 8448)
- Update docker_compose_generator.sh: familytraffic-nginx replaces familytraffic
- Update orchestrator.sh: generate_nginx_config() replaces generate_haproxy_config()
- Update certbot-renewal-hook: nginx -s reload, remove combined.pem generation
- Eliminates need for separate familytraffic-nginx_tier2 container (Phase 2 reuses http block)
```

---

## 6. Phase 1: Tier 1 — Завершение XTLS Vision

**Версия:** v5.25
**Риск:** Low
**Файлы:** lib/user_management.sh, lib/qr_generator.sh, scripts/vless, lib/security_tests.sh

### Step 1.1: Верификация существующей реализации

Подтвердить наличие `flow: "xtls-rprx-vision"` в `add_user_to_json()` (строка 524) и `generate_vless_uri()` (строка 834). **Код изменять не нужно** — уже реализован.

```bash
# Проверка:
grep -n '"flow": "xtls-rprx-vision"' lib/user_management.sh
grep -n 'flow=xtls-rprx-vision' lib/user_management.sh
```

### Step 1.2: Исправить validate_vless_uri() в qr_generator.sh

**Файл:** `lib/qr_generator.sh`
**Строка:** ~95

```bash
# ТЕКУЩИЙ КОД (сломает Tier 2):
local required_params=("encryption" "flow" "security" "sni" "fp" "pbk" "sid" "type")

# НОВЫЙ КОД:
local required_params=("encryption" "security" "sni" "fp" "pbk" "sid" "type")
# Conditional check for flow (only required for Reality):
if [[ "$uri" =~ security=reality ]]; then
    if ! [[ "$uri" =~ flow= ]]; then
        log_error "Invalid URI: Reality transport requires 'flow' parameter"
        return 1
    fi
fi
```

### Step 1.3: Добавить migrate_xtls_vision() в user_management.sh

> **⚠ Примечание (P6, P8):** На живом сервере `ikenibornvpn` все 7 пользователей УЖЕ имеют `flow: "xtls-rprx-vision"` в xray_config.json. Функция добавляется как safety-net для свежих установок или edge cases.

**Файл:** `lib/user_management.sh`
**Размещение:** После функции `migrate_users_schema_v525()` (строка **1797**, не ~1851)

```bash
# ============================================================================
# FUNCTION: migrate_xtls_vision (v5.25)
# ============================================================================
# Description: Add flow=xtls-rprx-vision to all existing Xray client objects
#              that were created before XTLS Vision was added to the code.
# Returns: 0 on success, 1 on failure
# ============================================================================
migrate_xtls_vision() {
    log_info "Checking XTLS Vision migration status..."

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log_error "Xray configuration not found: $XRAY_CONFIG"
        return 1
    fi

    # Count clients missing flow field
    local missing_count
    missing_count=$(jq '[.inbounds[0].settings.clients[] | select(.flow == null or .flow == "")] | length' \
        "$XRAY_CONFIG" 2>/dev/null || echo "0")

    if [[ "$missing_count" == "0" ]]; then
        log_success "XTLS Vision already configured for all users (no migration needed)"
        return 0
    fi

    log_info "Found $missing_count user(s) without flow field — migrating..."

    # Backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.migrate.$$"

    # Add flow field to all clients missing it
    local temp_file="${XRAY_CONFIG}.tmp.migrate.$$"
    jq '(.inbounds[0].settings.clients[] | select(.flow == null or .flow == "")) |= . + {"flow": "xtls-rprx-vision"}' \
        "$XRAY_CONFIG" > "$temp_file"

    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Migration produced invalid JSON"
        rm -f "$temp_file"
        return 1
    fi

    mv "$temp_file" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"
    rm -f "${XRAY_CONFIG}.bak.migrate.$$"

    log_success "XTLS Vision migration complete: $missing_count user(s) updated"
    log_warning "IMPORTANT: Existing clients must update their VLESS URI to include flow=xtls-rprx-vision"
    log_warning "Use 'vless list-users' to regenerate QR codes/URIs for affected users"

    # Reload Xray to apply changes
    docker restart familytraffic 2>/dev/null && log_success "Xray restarted to apply Vision migration"

    return 0
}
```

### Step 1.4: Добавить generate_transport_uri() в user_management.sh

**Файл:** `lib/user_management.sh`
**Размещение:** Перед `generate_vless_uri()` (строка ~790)

> **⚠ Исправление P4:** В исходном плане case `reality` обращается к `$username` который не определён в scope функции. Исправлено — добавлен параметр `$6=username`.

```bash
# ============================================================================
# FUNCTION: generate_transport_uri (v5.30)
# ============================================================================
# Description: Generate transport-specific VLESS URI
# Arguments:
#   $1 - transport_type: reality|ws|xhttp|grpc
#   $2 - uuid
#   $3 - server_ip
#   $4 - domain (for SNI and subdomain)
#   $5 - server_port (default: 443)
#   $6 - username (for URI fragment/remark)   ← ИСПРАВЛЕНИЕ P4
# Returns: VLESS URI string
# ============================================================================
generate_transport_uri() {
    local transport_type="$1"
    local uuid="$2"
    local server_ip="$3"
    local domain="$4"
    local server_port="${5:-443}"
    local username="${6:-user}"               # ← ИСПРАВЛЕНИЕ P4

    case "$transport_type" in
        reality)
            # Existing Reality URI format (handled by generate_vless_uri)
            generate_vless_uri "$username" "$uuid"
            ;;
        ws)
            # WebSocket + TLS URI
            local ws_subdomain="ws.${domain}"
            echo "vless://${uuid}@${ws_subdomain}:${server_port}?encryption=none&security=tls&sni=${ws_subdomain}&fp=chrome&type=ws&path=%2Fvless-ws#${username}-ws"
            ;;
        xhttp)
            # XHTTP/SplitHTTP + TLS URI
            local xhttp_subdomain="xhttp.${domain}"
            echo "vless://${uuid}@${xhttp_subdomain}:${server_port}?encryption=none&security=tls&sni=${xhttp_subdomain}&fp=chrome&type=splithttp&path=%2Fapi%2Fv2#${username}-xhttp"
            ;;
        grpc)
            # gRPC + TLS URI (via Nginx, standard HTTPS port)
            local grpc_subdomain="grpc.${domain}"
            echo "vless://${uuid}@${grpc_subdomain}:${server_port}?encryption=none&security=tls&sni=${grpc_subdomain}&fp=chrome&type=grpc&serviceName=GunService#${username}-grpc"
            ;;
        *)
            log_error "Unknown transport type: $transport_type"
            return 1
            ;;
    esac
}
```

### Step 1.5: Добавить 'vless migrate-vision' в scripts/vless

**Файл:** `scripts/vless`
**Размещение:** После существующих команд (строка ~267)

```bash
# В dispatch section:
migrate-vision|migrate_vision)
    source "${LIB_DIR}/user_management.sh"
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  XTLS Vision Migration (v5.25)"
    echo "═══════════════════════════════════════════════════════"
    migrate_xtls_vision
    ;;
```

### Step 1.6: Добавить test_xtls_vision_enabled() в security_tests.sh

**Файл:** `lib/security_tests.sh`
**Тест-кейс:** TC-01 из PRD section 9.1

```bash
# ============================================================================
# TEST: test_xtls_vision_enabled (TC-01)
# ============================================================================
test_xtls_vision_enabled() {
    print_test_header "XTLS Vision — flow field verification (TC-01)"

    local xray_config="/opt/familytraffic/config/xray_config.json"

    if [[ ! -f "$xray_config" ]]; then
        print_skip "Xray config not found (installation may not be complete)"
        return 0
    fi

    # Check all clients have flow=xtls-rprx-vision
    local clients_without_flow
    clients_without_flow=$(jq '[.inbounds[0].settings.clients[] | select(.flow != "xtls-rprx-vision")] | length' \
        "$xray_config" 2>/dev/null || echo "-1")

    if [[ "$clients_without_flow" == "0" ]]; then
        print_success "XTLS Vision: All client objects have flow=xtls-rprx-vision"
    elif [[ "$clients_without_flow" == "-1" ]]; then
        print_failure "XTLS Vision: Could not parse xray_config.json"
        return 1
    else
        print_failure "XTLS Vision: $clients_without_flow client(s) missing flow field — run 'vless migrate-vision'"
        return 1
    fi

    # Verify no clients have empty flow
    local clients_empty_flow
    clients_empty_flow=$(jq '[.inbounds[0].settings.clients[] | select(.flow == "" or .flow == null)] | length' \
        "$xray_config" 2>/dev/null || echo "0")

    if [[ "$clients_empty_flow" != "0" ]]; then
        print_failure "XTLS Vision: $clients_empty_flow client(s) have empty/null flow field"
        return 1
    fi

    print_success "XTLS Vision TC-01: PASSED"
    return 0
}
```

**Commit message для Phase 1:**
```
feat(obfuscation): complete Tier 1 XTLS Vision — migration, transport-aware URI validation, and test coverage (v5.25)
```

**Validation:**
```bash
bash -n lib/user_management.sh
bash -n lib/qr_generator.sh
bash -n scripts/vless
bash -n lib/security_tests.sh
```

---

## 7. Phase 2: Tier 2 — Транспортная инфраструктура (v5.30-v5.32)

> **Предусловие:** Phase 0 выполнена — `familytraffic-nginx` (stream+http) уже работает вместо HAProxy.

**Версия:** v5.30-v5.32
**Риск:** Medium (Nginx уже запущен после Phase 0, добавляем только новые inbounds и http-блоки)
**Файлы:** lib/orchestrator.sh, **lib/nginx_stream_generator.sh** (расширяем, не haproxy!), lib/docker_compose_generator.sh

### Step 2.1: Добавить generate_websocket_inbound_json() в orchestrator.sh

**Файл:** `lib/orchestrator.sh`
**Размещение:** После `generate_http_inbound_json()` (~строка 570)

```bash
# ============================================================================
# FUNCTION: generate_websocket_inbound_json (v5.30)
# ============================================================================
# Description: Returns JSON for VLESS WebSocket inbound (no TLS — Nginx terminates)
# Port: 8444 (internal Docker network only)
# ============================================================================
generate_websocket_inbound_json() {
    cat <<'EOF'
,{
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
EOF
}
```

### Step 2.2: Добавить generate_xhttp_inbound_json() в orchestrator.sh

```bash
# ============================================================================
# FUNCTION: generate_xhttp_inbound_json (v5.31)
# ============================================================================
# Description: Returns JSON for VLESS XHTTP/SplitHTTP inbound
# Port: 8445 (internal Docker network only)
# Requires: Xray-core >= 24.9 (using teddysun/xray:24.11.30 — satisfied)
# ============================================================================
generate_xhttp_inbound_json() {
    cat <<'EOF'
,{
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
EOF
}
```

### Step 2.3: Добавить generate_grpc_inbound_json() в orchestrator.sh

```bash
# ============================================================================
# FUNCTION: generate_grpc_inbound_json (v5.32)
# ============================================================================
# Description: Returns JSON for VLESS gRPC inbound (TLS terminated by Nginx)
# Port: 8446 (internal Docker network only)
# ============================================================================
generate_grpc_inbound_json() {
    cat <<'EOF'
,{
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
EOF
}
```

### Step 2.4: Расширить create_xray_config() в orchestrator.sh

**Файл:** `lib/orchestrator.sh`
**Изменение:** Добавить параметр `enable_tier2`

```bash
# ТЕКУЩАЯ СИГНАТУРА (строка 585):
create_xray_config() {
    local enable_proxy="${1:-false}"

# НОВАЯ СИГНАТУРА:
create_xray_config() {
    local enable_proxy="${1:-false}"
    local enable_tier2="${2:-false}"   # v5.30: Tier 2 transports flag

# В heredoc inbounds (строка ~650), ПОСЛЕ существующего proxy conditional:
$(if [[ "$enable_tier2" == "true" ]]; then
    generate_websocket_inbound_json
    generate_xhttp_inbound_json
    generate_grpc_inbound_json
fi)
```

### Step 2.5: Расширить generate_nginx_config() с Tier 2 субдоменами

**Файл:** `lib/nginx_stream_generator.sh`
**Изменение:** `generate_nginx_config()` уже принимает $3/$4/$5 (ws/xhttp/grpc subdomain) — добавить вызовы с новыми аргументами при активации транспорта.

> **Упрощение vs. исходного плана (Phase 0 эффект):**
> Вместо изменения `generate_haproxy_config()` ($6/$7/$8 параметры, коллизия $5 — P3/R9) — просто передаём субдомены в уже существующий `generate_nginx_config()`. Функция уже знает как добавить SNI route в stream-map и server-блок в http-секцию.

```bash
# При добавлении WebSocket транспорта (vless add-transport ws ws.example.com):
generate_nginx_config \
    "$CERT_DOMAIN" \
    "true" \
    "ws.example.com" \      # $3=ws_subdomain
    "" \                    # $4=xhttp_subdomain (пока пусто)
    "" \                    # $5=grpc_subdomain (пока пусто)
    > "${VLESS_DIR}/config/nginx/nginx.conf"

docker exec familytraffic nginx -s reload   # zero-downtime reload
```

**Что происходит внутри generate_nginx_config() при добавлении ws_subdomain:**
1. В stream-блок добавляется строка `ws.example.com  127.0.0.1:8448;` в map
2. В http-блок добавляется `server { server_name ws.example.com; ... proxy_pass http://familytraffic:8444; }`
3. Reality на порту 443 продолжает работать через `default familytraffic:8443` — без изменений

> **Сравнение с HAProxy подходом:** В исходном плане нужно было трогать `generate_haproxy_config()` (риски P3, R9 коллизии параметров) И создавать отдельный `familytraffic-nginx_tier2`. Сейчас — один вызов одной функции.

### ~~Step 2.6: Добавить generate_tier2_nginx_config() в nginx_config_generator.sh~~ — НЕ НУЖЕН (Phase 0 эффект)

> **Отменён Phase 0:** Функция `generate_tier2_nginx_config()` в `lib/nginx_config_generator.sh` не создаётся — она была спроектирована для `familytraffic-nginx_tier2` контейнера с HAProxy. После Phase 0 все Tier 2 server-блоки (WS/XHTTP/gRPC) генерируются внутри `generate_nginx_config()` в `lib/nginx_stream_generator.sh` (http-блок, порт 8448).
>
> **Что происходит вместо этого:** Step 2.5 вызывает `generate_nginx_config "$CERT_DOMAIN" "true" "$ws_sub" "$xhttp_sub" "$grpc_sub"` → перезаписывает `/opt/familytraffic/config/nginx/nginx.conf` → `docker exec familytraffic nginx -s reload`.

### Step 2.7: Расширить expose портов familytraffic в generate_docker_compose()

**Файл:** `lib/docker_compose_generator.sh`
**Изменение:** В heredoc familytraffic expose секция (~строка 262)

> **Подтверждено SSH:** Текущий expose — только `8443, 10800, 18118`. Нужно добавить 8444/8445/8446 для Tier 2.

```yaml
# ТЕКУЩИЙ КОД (строки 262-264, подтверждено SSH):
    expose:
      - "8443"   # VLESS Reality inbound
      - "10800"  # SOCKS5 proxy
      - "18118"  # HTTP proxy

# НОВЫЙ КОД (R2 mitigation — Nginx должен достучаться до Xray plaintext inbounds):
    expose:
      - "8443"   # VLESS Reality inbound
      - "10800"  # SOCKS5 proxy (Nginx terminates TLS on port 1080)
      - "18118"  # HTTP proxy (Nginx terminates TLS on port 8118)
$(if [[ "${ENABLE_TIER2_TRANSPORTS:-false}" == "true" ]]; then
cat <<TIER2_EXPOSE
      - "8444"   # VLESS WebSocket plaintext (Nginx→Xray, v5.30)
      - "8445"   # VLESS XHTTP/SplitHTTP plaintext (Nginx→Xray, v5.31)
      - "8446"   # VLESS gRPC plaintext (Nginx→Xray, v5.32)
TIER2_EXPOSE
fi)
```

### ~~Step 2.8: Добавить familytraffic-nginx_tier2 контейнер~~ — НЕ НУЖЕН (Phase 0 эффект)

> **Отменён Phase 0:** После миграции на единый `familytraffic-nginx` отдельный контейнер `familytraffic-nginx_tier2` не создаётся. Tier 2 http-блок (порт 8448) является частью основного `familytraffic-nginx`. Step 2.8 удалён из плана.
>
> **Что происходит вместо этого:** `add_transport()` (Step 3.1) вызывает `generate_nginx_config()` с новыми субдоменами → перезаписывает `/opt/familytraffic/config/nginx/nginx.conf` → `docker exec familytraffic nginx -s reload`.

---

**Commit message для Phase 2:**
```
feat(obfuscation): add Tier 2 transports — WS/XHTTP/gRPC Xray inbounds, extend familytraffic-nginx with Tier 2 SNI routing and http block (v5.30)
```

**Validation:**
```bash
bash -n lib/orchestrator.sh
bash -n lib/nginx_stream_generator.sh
bash -n lib/docker_compose_generator.sh
# После регенерации конфигов:
jq empty /opt/familytraffic/config/xray_config.json
docker exec familytraffic nginx -t        # проверить nginx.conf с новыми server-блоками
```

---

## 8. Phase 3: Tier 2 — Transport Management CLI

**Версия:** v5.33
**Риск:** Medium
**Файлы:** lib/transport_manager.sh (NEW), scripts/vless

### Step 3.1: Создать lib/transport_manager.sh

**Новый файл:** `lib/transport_manager.sh`

```bash
#!/usr/bin/env bash
# lib/transport_manager.sh
# Transport Management (v5.33)
# Manages Tier 2 transport configurations (WebSocket, XHTTP, gRPC)
#
# Functions:
#   1. add_transport()      - Add transport with subdomain routing
#   2. list_transports()    - List configured transports
#   3. remove_transport()   - Remove transport and cleanup
#   4. get_transport_uri()  - Get client URI for transport

TRANSPORTS_JSON="${VLESS_HOME}/data/transports.json"

# Initialize transports.json if not exists
_init_transports_json() {
    if [[ ! -f "$TRANSPORTS_JSON" ]]; then
        echo '{"transports":[]}' > "$TRANSPORTS_JSON"
        chmod 600 "$TRANSPORTS_JSON"
    fi
}

# ============================================================================
# FUNCTION: add_transport
# ============================================================================
add_transport() {
    local transport_type="$1"   # ws|xhttp|grpc
    local subdomain="$2"        # e.g., ws.example.com

    _init_transports_json

    # Validate type
    case "$transport_type" in
        ws|xhttp|grpc) ;;
        *) log_error "Unknown transport type: $transport_type (must be: ws, xhttp, grpc)"; return 1 ;;
    esac

    # Determine port
    local port
    case "$transport_type" in
        ws)    port=8444 ;;
        xhttp) port=8445 ;;
        grpc)  port=8446 ;;
    esac

    # Check if already configured
    local existing
    existing=$(jq -r --arg t "$transport_type" '.transports[] | select(.type == $t) | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null)
    if [[ -n "$existing" ]]; then
        log_error "Transport '$transport_type' already configured for $existing"
        log_info "Run 'vless remove-transport $transport_type' first to reconfigure"
        return 1
    fi

    # Add to transports.json
    local temp="${TRANSPORTS_JSON}.tmp.$$"
    jq --arg t "$transport_type" --arg s "$subdomain" --argjson p "$port" \
        '.transports += [{"type": $t, "subdomain": $s, "port": $p, "enabled": true}]' \
        "$TRANSPORTS_JSON" > "$temp" && mv "$temp" "$TRANSPORTS_JSON"

    log_success "Transport '$transport_type' added: $subdomain:443 → familytraffic:$port"

    # Regenerate configs
    ENABLE_TIER2_TRANSPORTS=true
    source "${LIB_DIR}/orchestrator.sh"
    source "${LIB_DIR}/nginx_stream_generator.sh"
    source "${LIB_DIR}/docker_compose_manager.sh"

    log_info "Regenerating Xray config with Tier 2 inbounds..."
    create_xray_config "${ENABLE_PUBLIC_PROXY:-false}" "true"

    log_info "Regenerating Nginx config with $transport_type routing..."
    # Re-read all transport subdomains for Nginx generation
    local ws_sub xhttp_sub grpc_sub
    ws_sub=$(jq -r '.transports[] | select(.type == "ws") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null)
    xhttp_sub=$(jq -r '.transports[] | select(.type == "xhttp") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null)
    grpc_sub=$(jq -r '.transports[] | select(.type == "grpc") | .subdomain' "$TRANSPORTS_JSON" 2>/dev/null)
    generate_nginx_config "$VLESS_DOMAIN" "true" "$ws_sub" "$xhttp_sub" "$grpc_sub" \
        > "${VLESS_DIR}/config/nginx/nginx.conf"

    log_info "Reloading containers..."
    docker restart familytraffic
    docker exec familytraffic nginx -s reload

    log_success "Transport '$transport_type' is now active on $subdomain"
    return 0
}

# ============================================================================
# FUNCTION: list_transports
# ============================================================================
list_transports() {
    _init_transports_json

    local count
    count=$(jq '.transports | length' "$TRANSPORTS_JSON" 2>/dev/null || echo "0")

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Tier 2 Transports"
    echo "═══════════════════════════════════════════════════════"

    if [[ "$count" == "0" ]]; then
        echo "  No transports configured."
        echo "  Use: sudo familytraffic add-transport ws subdomain.example.com"
    else
        printf "  %-8s %-30s %-6s %-8s\n" "TYPE" "SUBDOMAIN" "PORT" "STATUS"
        echo "  ──────────────────────────────────────────────────────"
        jq -r '.transports[] | [.type, .subdomain, (.port|tostring), (if .enabled then "active" else "disabled" end)] | @tsv' \
            "$TRANSPORTS_JSON" | while IFS=$'\t' read -r t s p e; do
            printf "  %-8s %-30s %-6s %-8s\n" "$t" "$s" "$p" "$e"
        done
    fi
    echo ""
}

# ============================================================================
# FUNCTION: remove_transport
# ============================================================================
remove_transport() {
    local transport_type="$1"

    _init_transports_json

    local existing
    existing=$(jq -r --arg t "$transport_type" '.transports[] | select(.type == $t) | .subdomain' "$TRANSPORTS_JSON")

    if [[ -z "$existing" ]]; then
        log_error "Transport '$transport_type' is not configured"
        return 1
    fi

    # Remove from transports.json
    local temp="${TRANSPORTS_JSON}.tmp.$$"
    jq --arg t "$transport_type" '.transports = [.transports[] | select(.type != $t)]' \
        "$TRANSPORTS_JSON" > "$temp" && mv "$temp" "$TRANSPORTS_JSON"

    # Remove inbound from xray_config.json
    local tag
    case "$transport_type" in
        ws)    tag="vless-websocket" ;;
        xhttp) tag="vless-xhttp" ;;
        grpc)  tag="vless-grpc" ;;
    esac

    local xray_temp="${XRAY_CONFIG}.tmp.$$"
    jq --arg tag "$tag" '.inbounds = [.inbounds[] | select(.tag != $tag)]' \
        "$XRAY_CONFIG" > "$xray_temp" && mv "$xray_temp" "$XRAY_CONFIG"

    log_success "Transport '$transport_type' removed"

    # Reload Xray
    docker restart familytraffic
    log_success "Xray restarted"

    return 0
}
```

### Step 3.2-3.4: Добавить CLI команды в scripts/vless

```bash
# В dispatch section scripts/vless:
add-transport|addtransport)
    if [[ $# -lt 2 ]]; then
        echo "Usage: vless add-transport <type> <subdomain>" >&2
        echo "Types: ws, xhttp, grpc" >&2
        echo "Example: vless add-transport ws ws.example.com" >&2
        exit 1
    fi
    source "${LIB_DIR}/transport_manager.sh"
    add_transport "$1" "$2"
    ;;

list-transports|listtransports)
    source "${LIB_DIR}/transport_manager.sh"
    list_transports
    ;;

remove-transport|removetransport)
    if [[ $# -lt 1 ]]; then
        echo "Usage: vless remove-transport <type>" >&2
        echo "Types: ws, xhttp, grpc" >&2
        exit 1
    fi
    source "${LIB_DIR}/transport_manager.sh"
    remove_transport "$1"
    ;;
```

**Commit message для Phase 3:**
```
feat(cli): add transport management commands — add-transport, list-transports, remove-transport (v5.33)
```

**Validation:**
```bash
bash -n lib/transport_manager.sh
bash -n scripts/vless
```

---

## 9. Тестирование и валидация

### Тест-матрица (из PRD section 9.1)

| Тест-кейс | Описание | Phase | Команда проверки |
|-----------|----------|-------|-----------------|
| **TC-01** | Проверка flow поля в xray_config.json | Phase 1 | `sudo familytraffic test-security` (добавить test_xtls_vision_enabled) |
| **TC-02** | DPI bypass — entropia первых пакетов | Phase 1 | `tcpdump + tshark` (см. PRD 9.2) |
| **TC-10** | WebSocket базовое подключение | Phase 2 | `curl -H "Upgrade: websocket" https://ws.domain/vless-ws` |
| **TC-20** | XHTTP chunked upload/download | Phase 2 | `curl -X POST https://xhttp.domain/api/v2` |
| **TC-30** | gRPC базовое подключение | Phase 2 | `grpcurl -d '{}' grpc.domain:443 GunService/Gun` |
| **TC-12** | WebSocket через Cloudflare CDN | Phase 2 | Настроить Cloudflare proxy → проверить подключение |
| **TC-22** | XHTTP через Cloudflare CDN | Phase 2 | Аналогично TC-12 |
| **TC-32** | gRPC через Cloudflare CDN | Phase 2 | Cloudflare поддерживает gRPC с 2020 |

### iOS v2rayTun — тест-план

> **Контекст:** Фактические iOS-пользователи проекта используют v2rayTun v2.4.4 (Xray-core 25.10.15). Исследование показало полную совместимость с Reality+Vision, WS, gRPC; XHTTP требует ручной проверки.

| ID | Транспорт | Тест | Ожидаемый результат | Приоритет |
|----|-----------|------|---------------------|-----------|
| **iOS-00** | HAProxy → Nginx (миграция) | После замены HAProxy на Nginx: подключиться по прежнему VLESS URI без изменений | Нулевой impact | Phase 2 / v5.30 (при миграции) |
| **iOS-01** | Reality + Vision | Подключиться через v2rayTun, импортировав VLESS URI с `flow=xtls-rprx-vision` | Успешное подключение | **Phase 1 — подтвердить уже сейчас** |
| **iOS-10** | WebSocket | Импортировать WS URI → подключиться | Успешное подключение | Phase 2 / v5.30 |
| **iOS-20** | XHTTP | Импортировать XHTTP URI → подключиться | Успешное / не поддерживается (R11) | **Phase 2 / v5.31 — ОБЯЗАТЕЛЬНО** |
| **iOS-30** | gRPC | Импортировать gRPC URI → подключиться | Успешное подключение | Phase 2 / v5.32 |

**Инструкция для iOS-01 (ручной, немедленно):**
```
1. Открыть v2rayTun → Profiles → Add via QR / Clipboard
2. Вставить URI: vless://UUID@SERVER:443?...&flow=xtls-rprx-vision&...
3. Подключиться → проверить IP (ipinfo.io)
4. Убедиться fingerprint fp=chrome применён (опционально: wireshark на сервере)
```

**Проверка XHTTP на iOS (iOS-20) — критический тест перед v5.31:**
```bash
# На сервере — логи Xray (смотреть входящие соединения на порту 8445):
docker logs familytraffic --follow | grep "8445\|splithttp\|XHTTP"

# Если v2rayTun успешно подключился → TC-20 iOS passed
# Если "connection refused" / нет записей → XHTTP не поддерживается в v2rayTun iOS
# → Документировать ограничение, рекомендовать WebSocket для iOS пользователей
```

### Проверка fallback (Reality не нарушается)

```bash
# Убедиться что Reality трафик по-прежнему идёт через default familytraffic:8443:
curl -v --resolve "www.google.com:443:${SERVER_IP}" \
    --cert-status \
    https://www.google.com:443  # должен вернуть fake-site контент

# Проверить Nginx stream map (после Phase 0):
grep -A 10 "map \$ssl_preread_server_name" /opt/familytraffic/config/nginx/nginx.conf
# Tier 2 subdomains → 127.0.0.1:8448; default → familytraffic:8443
```

---

## 10. Процедура отката

### Откат Phase 0 (HAProxy → Nginx migration)

```bash
# Если миграция на Nginx прошла неуспешно — вернуть HAProxy:

# 1. Остановить familytraffic-nginx
docker stop familytraffic-nginx || true

# 2. Восстановить docker-compose.yml из backup
cp /opt/familytraffic/docker-compose.yml.bak /opt/familytraffic/docker-compose.yml

# 3. Восстановить haproxy.cfg (должен быть до миграции)
#    Если backup не сохранён — регенерировать через старую версию orchestrator.sh из git
git -C /opt/familytraffic show HEAD:lib/haproxy_config_manager.sh > /tmp/haproxy_config_manager.sh
VLESS_DIR=/opt/familytraffic source /tmp/haproxy_config_manager.sh
generate_haproxy_config "$VLESS_DOMAIN" "$BASE_DOMAIN" "$PROXY_PASSWORD" "false"

# 4. Восстановить combined.pem для HAProxy
cat /etc/letsencrypt/live/${VLESS_DOMAIN}/fullchain.pem \
    /etc/letsencrypt/live/${VLESS_DOMAIN}/privkey.pem \
    > /etc/letsencrypt/live/${VLESS_DOMAIN}/combined.pem
chmod 600 /etc/letsencrypt/live/${VLESS_DOMAIN}/combined.pem

# 5. Запустить HAProxy
docker compose -f /opt/familytraffic/docker-compose.yml up -d haproxy

# Проверка:
docker ps | grep -E "familytraffic|familytraffic-nginx"
curl -sk https://localhost:443 -o /dev/null -w "%{http_code}"  # должен быть 400 (fake-site)
```

---

### Откат Tier 1 (XTLS Vision migration)

```bash
# Восстановить xray_config.json из backup:
cp /opt/familytraffic/config/xray_config.json.bak.migrate.* /opt/familytraffic/config/xray_config.json
docker restart familytraffic
```

### Откат Tier 2 (транспорты)

```bash
# Удалить транспорт через CLI:
sudo familytraffic remove-transport ws
sudo familytraffic remove-transport xhttp
sudo familytraffic remove-transport grpc

# Или вручную — удалить inbound из xray_config.json:
jq '.inbounds = [.inbounds[] | select(.tag | startswith("vless-") | not or . == "vless-reality")]' \
    /opt/familytraffic/config/xray_config.json > /tmp/xray_rollback.json \
    && mv /tmp/xray_rollback.json /opt/familytraffic/config/xray_config.json

docker restart familytraffic

# Восстановить docker-compose.yml без Tier 2 expose:
# Установить ENABLE_TIER2_TRANSPORTS=false и регенерировать
```

---

## 11. Definition of Done

### Phase 0 (v5.30) — Миграция HAProxy → Nginx — Definition of Done

- [ ] `lib/nginx_stream_generator.sh` создан с `generate_nginx_config()` (stream + http блоки)
- [ ] `docker_compose_generator.sh`: `familytraffic` заменён на `familytraffic-nginx` (nginx:1.27-alpine)
- [ ] `orchestrator.sh`: вызовы `generate_haproxy_config()` → `generate_nginx_config()`
- [ ] `certbot-renewal-hook.sh`: `combined.pem` удалён, `nginx -s reload` вместо haproxy reload
- [ ] Reality на порту 443 работает после миграции (регрессионный тест iOS-00)
- [ ] SOCKS5 :1080 и HTTP proxy :8118 работают через Nginx stream TLS
- [ ] `docker exec familytraffic nginx -t` без ошибок
- [ ] `familytraffic` контейнер удалён, `familytraffic-nginx` запущен и healthy

### Phase 1 (v5.25) — Завершение XTLS Vision — Definition of Done

- [ ] `flow: "xtls-rprx-vision"` подтверждён в `add_user_to_json()` (строка 524 — уже есть)
- [ ] `flow=xtls-rprx-vision` подтверждён в `generate_vless_uri()` (строка 834 — уже есть)
- [ ] `validate_vless_uri()` исправлен: `flow` проверяется только при `security=reality`
- [ ] `migrate_xtls_vision()` добавлен и работает для существующих пользователей
- [ ] `vless migrate-vision` команда добавлена в scripts/vless
- [ ] `test_xtls_vision_enabled()` добавлен и проходит (TC-01)
- [ ] Документация клиентских приложений обновлена (**v2rayTun iOS** — основной клиент пользователей, подтверждена совместимость с Reality+Vision; Shadowrocket, v2rayNG — добавить flow в настройки)

### Phase 2 (v5.30-v5.33) — Tier 2 транспорты — Definition of Done

- [ ] `generate_websocket_inbound_json()`, `generate_xhttp_inbound_json()`, `generate_grpc_inbound_json()` добавлены в orchestrator.sh (plaintext, без TLS — Nginx терминирует)
- [ ] `create_xray_config()` принимает флаг `enable_tier2` и условно добавляет inbounds
- [ ] Порты 8444/8445/8446 добавлены в docker-compose.yml expose для familytraffic (условно)
- [ ] ~~`familytraffic-nginx_tier2` контейнер~~ — **НЕ НУЖЕН** (Phase 0 заменил HAProxy единым familytraffic-nginx)
- [ ] `generate_nginx_config()` вызывается с ws/xhttp/grpc субдоменами → SNI map + http server блоки генерируются
- [ ] ~~`generate_haproxy_config()` параметры $6/$7/$8~~ — **НЕ НУЖЕН** (Phase 0 устранил HAProxy)
- [ ] `generate_transport_uri()` имеет параметр $6=username, без undefined $username в scope (P4 mitigation)
- [ ] `lib/transport_manager.sh` создан с функциями add/list/remove
- [ ] CLI команды `vless add-transport`, `vless list-transports`, `vless remove-transport` работают
- [ ] `docker exec familytraffic nginx -s reload` выполняется без ошибок после добавления транспорта
- [ ] Тесты TC-10 (WS), TC-20 (XHTTP), TC-30 (gRPC) пройдены
- [ ] **iOS v2rayTun тесты** iOS-10 (WS) и iOS-30 (gRPC) пройдены
- [ ] **iOS v2rayTun тест iOS-20 (XHTTP)** пройден или задокументировано ограничение (R11)
- [ ] Reality трафик продолжает работать (регрессионный тест — default в stream map)
- [ ] Документация обновлена: README.md, CHANGELOG.md, клиентские инструкции для v2rayTun

---

*План создан: 2026-02-23. Сессия: 2026-02-23T0032.*
*Верифицирован по SSH ikenibornvpn: 2026-02-23. Исправлено 8 проблем (P1-P8).*
*Обновлён: 2026-02-22 — Добавлен анализ совместимости iOS v2rayTun (R11, iOS тест-план, DoD). v2rayTun v2.4.4, Xray-core 25.10.15. Reality+Vision ✅ WS ✅ gRPC ✅ XHTTP ⚠️.*
*Источник: Agent Orchestrator Pipeline (research.toon + plan.toon в .claude/workspace/2026-02-23T0032/) + SSH live-server verification.*
*Обновлён: 2026-02-22 — Добавлена Phase 0: миграция HAProxy → единый Nginx (lib/nginx_stream_generator.sh, stream+http). Вариант A. Phase 2 упрощена: familytraffic-nginx_tier2 не нужен, generate_haproxy_config изменений не требует.*
*Следующий шаг: Получить подтверждение → Phase 0 (HAProxy→Nginx) → Phase 1 (validate_vless_uri) → Phase 2 (Tier 2 транспорты) → Phase 3 (CLI).*

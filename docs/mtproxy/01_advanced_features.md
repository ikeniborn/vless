# MTProxy Advanced Features Specification (v6.1+)

**Version:** v6.1 (Advanced Features - Released)
**Status:** ✅ COMPLETED (Multi-User + Fake-TLS Implemented)
**Priority:** MEDIUM-HIGH
**Created:** 2025-11-08
**Last Updated:** 2025-11-08

---

## TABLE OF CONTENTS

1. [Overview](#1-overview)
2. [Multi-User Support with Unique Secrets](#2-multi-user-support-with-unique-secrets)
3. [Promoted Channel Integration](#3-promoted-channel-integration)
4. [Advanced Statistics & Analytics](#4-advanced-statistics--analytics)
5. [HAProxy Routing for MTProxy](#5-haproxy-routing-for-mtproxy)
6. [Fake-TLS Support (ee secrets)](#6-fake-tls-support-ee-secrets)
7. [Implementation Roadmap](#7-implementation-roadmap)
8. [Protocol Limitations & Constraints](#8-protocol-limitations--constraints)

---

## 1. OVERVIEW

### Цель документа

Данный документ описывает **расширенные функции MTProxy** которые выходят за рамки базовой реализации v6.0. Эти функции повышают функциональность, usability и enterprise-готовность решения.

### Связь с базовой версией

**v6.0 (Базовая):**
- Один глобальный секрет для всех пользователей
- Базовая статистика (/stats endpoint)
- Standalone deployment (без HAProxy)
- Standard MTProto (dd prefix для padding)

**v6.1+ (Расширенная):**
- ✅ Уникальные секреты на пользователя (multi-user support)
- ✅ Promoted channel интеграция (монетизация)
- ✅ Advanced statistics (детальная аналитика)
- ✅ HAProxy routing (унифицированная архитектура)
- ✅ Fake-TLS support (ee secrets для DPI resistance)

### Приоритизация функций

| Функция | Priority | Complexity | Impact | Версия |
|---------|----------|------------|--------|--------|
| **Multi-User Secrets** | HIGH | MEDIUM | HIGH | v6.1 |
| **Promoted Channel** | MEDIUM | LOW | MEDIUM | v6.1 |
| **Advanced Statistics** | MEDIUM | MEDIUM | MEDIUM | v6.2 |
| **HAProxy Routing** | LOW | HIGH | LOW | v6.3 |
| **Fake-TLS (ee secrets)** | HIGH | HIGH | HIGH | v6.1 |

**Рекомендуемый порядок реализации:**
1. v6.1: Multi-User Secrets + Fake-TLS + Promoted Channel
2. v6.2: Advanced Statistics
3. v6.3: HAProxy Routing (optional, если требуется унификация)

---

## 2. MULTI-USER SUPPORT WITH UNIQUE SECRETS

### 2.1 Описание

**Проблема:** В базовой версии v6.0 все пользователи используют один глобальный секрет. Это создает риски:
- Невозможность отозвать доступ конкретного пользователя
- Нет per-user статистики (трафик, соединения)
- Сложность audit trail (кто подключался)

**Решение:** Уникальный секрет для каждого VLESS пользователя, интеграция с `users.json`.

### 2.2 Архитектурные решения

**Вариант A: Multiple Secrets в одном MTProxy процессе**

MTProxy поддерживает множественные `-S` параметры:
```bash
mtproto-proxy -S <secret1> -S <secret2> -S <secret3> ...
```

**Проблемы:**
- ❌ MTProxy нужно перезапустить для добавления/удаления секрета
- ❌ Все секреты передаются через командную строку (видны в `ps aux`)
- ❌ Нет встроенной per-secret статистики в официальном MTProxy

**Вердикт:** ❌ НЕ ПОДХОДИТ для production (security + перезапуски)

---

**Вариант B: Маппинг VLESS users → MTProxy secrets**

Структура:
```
VLESS User (alice) → MTProxy Secret (секрет_alice)
VLESS User (bob)   → MTProxy Secret (секрет_bob)
```

Хранение: `/opt/familytraffic/data/users.json` (расширение)
```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "...",
      "proxy_password": "...",
      "mtproxy_secret": "dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c",
      "mtproxy_enabled": true
    }
  ]
}
```

CLI команды:
```bash
# Автоматическая генерация секрета при создании пользователя
vless-user add alice --with-mtproxy

# Ручное управление
mtproxy enable-user alice
mtproxy disable-user alice
mtproxy regenerate-user-secret alice

# Показать конфиги
vless-user show alice  # включает MTProxy deep link
```

**Реализация:**
1. При `vless-user add alice --with-mtproxy`:
   - Генерируется уникальный секрет (16 bytes + dd prefix)
   - Секрет добавляется в MTProxy через `-S` параметр
   - MTProxy контейнер перезапускается
   - Генерируется deep link: `tg://proxy?server=IP&port=8443&secret=<секрет_alice>`

2. При `vless-user remove alice`:
   - Секрет удаляется из MTProxy
   - Контейнер перезапускается

3. Генерация клиентских конфигов:
   - `/opt/familytraffic/data/clients/alice/mtproxy_link.txt`
   - `/opt/familytraffic/data/clients/alice/mtproxy_qr.png`

**Проблемы:**
- ⚠️ Перезапуск контейнера при каждом add/remove (downtime ~2-3 секунды)
- ⚠️ Командная строка может стать очень длинной (50+ пользователей = 50 `-S` параметров)

**Mitigation:**
- Graceful restart (active connections сохраняются)
- Config file для секретов (если MTProxy поддерживает) - **требуется проверка**

**Вердикт:** ✅ ПОДХОДИТ для < 50 пользователей (с mitigation)

---

**Вариант C: Множественные MTProxy процессы (per-user containers)**

Архитектура:
```
VLESS User (alice) → familytraffic-mtproxy_alice (отдельный контейнер, порт 8444)
VLESS User (bob)   → familytraffic-mtproxy_bob (отдельный контейнер, порт 8445)
```

**Проблемы:**
- ❌ Масштабируемость: 50 пользователей = 50 Docker контейнеров
- ❌ Port exhaustion: каждому нужен уникальный порт
- ❌ Resource overhead: каждый MTProxy процесс ~20-30 MB RAM

**Вердикт:** ❌ НЕ ПОДХОДИТ (избыточная complexity)

---

### 2.3 Рекомендуемое решение

**Выбор:** Вариант B (Маппинг users → secrets)

**Ограничения:**
- Max users: 50 (после этого рассмотреть config file approach)
- Downtime при add/remove: 2-3 секунды (acceptable)

### 2.4 Functional Requirements

**FR-MTPROXY-101: Per-User Secret Generation**

**Priority:** HIGH
**Status:** Planned (v6.1)

**Description:**
Автоматическая генерация уникального MTProxy секрета для каждого VLESS пользователя.

**Acceptance Criteria:**
- ✅ CLI: `vless-user add alice --with-mtproxy` генерирует секрет
- ✅ Секрет сохраняется в `users.json` (поле `mtproxy_secret`)
- ✅ Секрет добавляется в MTProxy контейнер через `-S` параметр
- ✅ MTProxy контейнер перезапускается (graceful restart)
- ✅ Deep link генерируется с user-specific секретом
- ✅ QR code генерируется с user-specific секретом

**Implementation Notes:**
```bash
# Функция в lib/user_manager.sh
add_user_with_mtproxy() {
    local username="$1"

    # 1. Создать VLESS пользователя (existing logic)
    create_user "$username"

    # 2. Генерировать MTProxy секрет
    local mtproxy_secret=$(generate_mtproxy_secret true)  # with dd prefix

    # 3. Сохранить в users.json
    jq --arg user "$username" --arg secret "$mtproxy_secret" \
       '.users[] | select(.username == $user) | .mtproxy_secret = $secret | .mtproxy_enabled = true' \
       /opt/familytraffic/data/users.json > /tmp/users.json && mv /tmp/users.json /opt/familytraffic/data/users.json

    # 4. Обновить MTProxy контейнер
    add_mtproxy_secret "$mtproxy_secret"
    restart_mtproxy_container

    # 5. Генерировать клиентские конфиги
    generate_mtproxy_client_config "$username" "$mtproxy_secret"
}
```

---

**FR-MTPROXY-102: Per-User Secret Management**

**Priority:** HIGH
**Status:** Planned (v6.1)

**Description:**
CLI для управления MTProxy секретами пользователей.

**Acceptance Criteria:**
- ✅ `mtproxy enable-user <username>` - включить MTProxy для пользователя
- ✅ `mtproxy disable-user <username>` - отключить (удалить секрет)
- ✅ `mtproxy regenerate-user-secret <username>` - сгенерировать новый секрет
- ✅ `mtproxy list-user-secrets` - показать все секреты (маскированные)
- ✅ `vless-user show <username>` - показывает MTProxy конфигурацию в output

**CLI Output Example:**
```bash
$ mtproxy list-user-secrets

MTProxy User Secrets:
┌──────────┬────────────────────────┬─────────┬───────────────┐
│ Username │ Secret (masked)        │ Enabled │ Created       │
├──────────┼────────────────────────┼─────────┼───────────────┤
│ alice    │ dd1a2b...4b5c (32)    │ ✓       │ 2025-11-08    │
│ bob      │ dd3c4d...6e7f (32)    │ ✓       │ 2025-11-08    │
│ charlie  │ -                      │ ✗       │ -             │
└──────────┴────────────────────────┴─────────┴───────────────┘

Total: 2 enabled, 1 disabled
```

---

**FR-MTPROXY-103: Integration with vless-user Commands**

**Priority:** MEDIUM
**Status:** Planned (v6.1)

**Description:**
Интеграция MTProxy в существующие `vless-user` команды.

**Acceptance Criteria:**
- ✅ `vless-user show alice` показывает MTProxy секцию:
  ```
  MTProxy Configuration:
    Status: Enabled
    Secret: dd1a2b...4b5c (masked)
    Deep Link: tg://proxy?server=1.2.3.4&port=8443&secret=...
    QR Code: /opt/familytraffic/data/clients/alice/mtproxy_qr.png
  ```

- ✅ `vless-user remove alice` удаляет MTProxy секрет автоматически
  - Prompt: "User has MTProxy enabled. Remove secret? [Y/n]"
  - Действие: удалить секрет, перезапустить контейнер

- ✅ `vless-user list` показывает MTProxy status:
  ```
  Users (3 total):
  ┌──────────┬─────────────┬───────────┬──────────┐
  │ Username │ VLESS       │ SOCKS5/HTTP│ MTProxy  │
  ├──────────┼─────────────┼───────────┼──────────┤
  │ alice    │ ✓           │ ✓          │ ✓        │
  │ bob      │ ✓           │ ✓          │ ✗        │
  └──────────┴─────────────┴───────────┴──────────┘
  ```

---

### 2.5 Technical Implementation

**Docker Compose Changes:**

Передача множественных секретов через environment variable:
```yaml
services:
  mtproxy:
    environment:
      - MTPROXY_SECRETS=${MTPROXY_SECRETS}  # Comma-separated secrets
    command: >
      sh -c "
      IFS=',' read -ra SECRETS <<< \"$MTPROXY_SECRETS\";
      ARGS=\"\";
      for secret in \"\${SECRETS[@]}\"; do
        ARGS=\"\$ARGS -S \$secret\";
      done;
      /usr/local/bin/mtproto-proxy -u mtproxy -p 8888 -H 8443 \$ARGS --aes-pwd /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf -M 1
      "
```

**Environment Variable Generation:**
```bash
# lib/mtproxy_manager.sh
generate_mtproxy_secrets_env() {
    local secrets=$(jq -r '.users[] | select(.mtproxy_enabled == true) | .mtproxy_secret' /opt/familytraffic/data/users.json | tr '\n' ',')
    # Remove trailing comma
    secrets="${secrets%,}"

    # Update .env file
    sed -i "s/^MTPROXY_SECRETS=.*/MTPROXY_SECRETS=$secrets/" /opt/familytraffic/.env
}
```

**Restart Strategy:**
```bash
restart_mtproxy_container() {
    echo "Restarting MTProxy container (graceful)..."

    # Regenerate secrets environment variable
    generate_mtproxy_secrets_env

    # Graceful restart (preserves active connections)
    docker-compose up -d --no-deps mtproxy

    # Wait for healthcheck
    sleep 5

    # Verify
    if docker ps | grep -q "familytraffic-mtproxy.*healthy"; then
        echo "✓ MTProxy container restarted successfully"
    else
        echo "✗ MTProxy container failed to start"
        return 1
    fi
}
```

---

### 2.6 Protocol Limitations

**MTProxy Official Implementation:**
- ✅ **Поддерживает:** Множественные `-S` параметры
- ⚠️ **Ограничение:** Нет config file support (все секреты через CLI args)
- ⚠️ **Ограничение:** Перезапуск процесса для изменения секретов
- ⚠️ **Ограничение:** Нет per-secret статистики (все секреты одинаковы для MTProxy)

**Impact:**
- Per-user statistics НЕВОЗМОЖНЫ через стандартный /stats API
- Для per-user stats нужен external tracking (HAProxy logs или custom wrapper)

**Workaround для per-user stats:**
- Парсинг MTProxy logs (если доступны connection logs)
- HAProxy routing с разными backend портами (см. Section 5)
- External analytics tool (Prometheus + Grafana)

---

### 2.7 Testing Plan

**Unit Tests:**
```bash
# Test secret generation
test_generate_user_secret() {
    local username="test_user"
    local secret=$(generate_mtproxy_secret true)

    # Verify format
    [[ $secret =~ ^dd[0-9a-f]{32}$ ]] || fail "Invalid secret format"

    # Verify uniqueness
    local secret2=$(generate_mtproxy_secret true)
    [[ $secret != $secret2 ]] || fail "Secrets not unique"
}

# Test user add with MTProxy
test_add_user_with_mtproxy() {
    add_user_with_mtproxy "alice"

    # Verify secret in users.json
    local secret=$(jq -r '.users[] | select(.username == "alice") | .mtproxy_secret' /opt/familytraffic/data/users.json)
    [[ -n $secret ]] || fail "Secret not saved"

    # Verify MTProxy container has secret
    docker exec familytraffic-mtproxy cat /proc/$PID/cmdline | grep -q "$secret" || fail "Secret not in container"
}
```

**Integration Tests:**
```bash
# Test add 10 users
test_multi_user_scalability() {
    for i in {1..10}; do
        add_user_with_mtproxy "user$i"
    done

    # Verify all secrets in container
    local cmdline=$(docker exec familytraffic-mtproxy cat /proc/1/cmdline)
    for i in {1..10}; do
        local secret=$(jq -r '.users[] | select(.username == "user'$i'") | .mtproxy_secret' /opt/familytraffic/data/users.json)
        echo "$cmdline" | grep -q "$secret" || fail "Secret for user$i not found"
    done
}
```

---

## 3. PROMOTED CHANNEL INTEGRATION

### 3.1 Описание

**Promoted Channel** - функция Telegram, позволяющая владельцу MTProxy отображать канал в списке чатов пользователей, подключенных через прокси.

**Benefits:**
- ✅ Монетизация: канал показывается всем пользователям прокси
- ✅ Статистика: доступ к официальной статистике Telegram через @MTProxybot
- ✅ Доверие: прокси зарегистрирован в официальной системе Telegram

**Официальная документация:**
- Bot: https://t.me/MTProxybot
- Команда: `/newproxy`

### 3.2 Регистрация процесс

**Шаги:**

1. **Открыть @MTProxybot в Telegram**
2. **Отправить `/newproxy`**
3. **Указать IP адрес сервера**
4. **Указать порт (8443)**
5. **Указать секрет (один из секретов MTProxy)**
6. **Выбрать promoted channel (опционально)**
7. **Получить proxy tag** (например: `7F0000000000000000000000000000007F`)

**Результат:**
- Proxy tag для использования в `-P` параметре
- Доступ к статистике в боте
- Канал отображается у пользователей (если указан)

### 3.3 Архитектурные решения

**Вариант A: Глобальный Promoted Channel (один для всех пользователей)**

MTProxy запускается с одним `-P` параметром:
```bash
mtproto-proxy -u mtproxy -p 8888 -H 8443 \
  -S <secret1> -S <secret2> \
  -P 7F0000000000000000000000000000007F \
  --aes-pwd /etc/mtproxy/proxy-secret \
  /etc/mtproxy/proxy-multi.conf -M 1
```

**Плюсы:**
- ✅ Простая реализация
- ✅ Один канал для всех пользователей

**Минусы:**
- ❌ Невозможно иметь разные каналы для разных пользователей
- ❌ Все секреты должны быть зарегистрированы с одним тэгом

**Вердикт:** ✅ ПОДХОДИТ для большинства use cases

---

**Вариант B: Per-User Promoted Channels**

**Проблема:** MTProxy не поддерживает множественные `-P` параметры для разных секретов.

**Официальное ограничение:**
```
MTProxy supports only ONE -P parameter globally for ALL secrets.
```

**Вердикт:** ❌ НЕ ПОДДЕРЖИВАЕТСЯ протоколом

---

### 3.4 Рекомендуемое решение

**Выбор:** Вариант A (Глобальный Promoted Channel)

**Implementation:**
- Один промо-канал для всех пользователей MTProxy
- Администратор регистрирует прокси через @MTProxybot
- Proxy tag сохраняется в конфигурации
- CLI для управления promoted channel

### 3.5 Functional Requirements

**FR-MTPROXY-201: Promoted Channel Configuration**

**Priority:** MEDIUM
**Status:** Planned (v6.1)

**Description:**
CLI для регистрации и управления promoted channel через @MTProxybot.

**Acceptance Criteria:**
- ✅ CLI: `mtproxy setup-promoted-channel`
  - Interactive wizard
  - Prompt для proxy tag (получен через @MTProxybot)
  - Prompt для channel username (опционально)
  - Сохранение в `/opt/familytraffic/config/mtproxy/promoted_channel.json`

- ✅ CLI: `mtproxy show-promoted-channel`
  - Показывает текущий proxy tag
  - Показывает channel username (если есть)
  - Показывает статус (active/inactive)

- ✅ CLI: `mtproxy remove-promoted-channel`
  - Удаляет `-P` параметр из MTProxy
  - Перезапускает контейнер

**CLI Flow:**
```bash
$ sudo mtproxy setup-promoted-channel

=== Promoted Channel Setup ===

This wizard will help you register your MTProxy with Telegram
and optionally promote a channel to users.

Steps:
1. Open @MTProxybot in Telegram
2. Send /newproxy command
3. Provide server IP: <your-server-ip>
4. Provide port: 8443
5. Provide secret: <one-of-your-secrets>
6. Optionally select a channel to promote
7. Copy the proxy tag from the bot

Enter proxy tag (received from @MTProxybot): 7F0000000000000000000000000000007F
Enter promoted channel username (optional, e.g., @yourchannel): @mytechchannel

Saving configuration...
✓ Promoted channel configured
✓ Restarting MTProxy container...
✓ MTProxy now running with promoted channel

View statistics: https://t.me/MTProxybot
```

---

**FR-MTPROXY-202: Promoted Channel Auto-Configuration**

**Priority:** LOW
**Status:** Planned (v6.2)

**Description:**
Автоматическая интеграция с @MTProxybot API (если доступен).

**Note:** @MTProxybot не предоставляет публичный API, только интерактивный бот.

**Вердикт:** ❌ НЕ РЕАЛИЗУЕМО (API отсутствует)

---

### 3.6 Technical Implementation

**Configuration File:**
```json
// /opt/familytraffic/config/mtproxy/promoted_channel.json
{
  "enabled": true,
  "proxy_tag": "7F0000000000000000000000000000007F",
  "channel_username": "@mytechchannel",
  "registered_at": "2025-11-08T10:00:00Z",
  "registered_secret": "dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c",
  "statistics_url": "https://t.me/MTProxybot"
}
```

**Docker Compose Update:**
```yaml
services:
  mtproxy:
    environment:
      - MTPROXY_SECRETS=${MTPROXY_SECRETS}
      - MTPROXY_PROXY_TAG=${MTPROXY_PROXY_TAG}  # NEW
    command: >
      sh -c "
      ARGS=\"-u mtproxy -p 8888 -H 8443\";

      # Add secrets
      IFS=',' read -ra SECRETS <<< \"$MTPROXY_SECRETS\";
      for secret in \"\${SECRETS[@]}\"; do
        ARGS=\"\$ARGS -S \$secret\";
      done;

      # Add promoted channel tag (if set)
      if [ -n \"\$MTPROXY_PROXY_TAG\" ]; then
        ARGS=\"\$ARGS -P \$MTPROXY_PROXY_TAG\";
      fi;

      # Execute
      /usr/local/bin/mtproto-proxy \$ARGS --aes-pwd /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf -M 1
      "
```

---

### 3.7 Statistics Access

**@MTProxybot предоставляет:**
- Total connections (all time)
- Active connections (current)
- Traffic statistics (bandwidth)
- Geographic distribution (countries)

**Доступ:**
1. Открыть @MTProxybot
2. Отправить `/stats`
3. Выбрать зарегистрированный прокси
4. Просмотреть статистику

**Ограничения:**
- ❌ Нет API для автоматического получения статистики
- ❌ Только через Telegram бота (manual)

**Workaround:**
- Использовать локальный `/stats` endpoint для real-time метрик
- @MTProxybot для historical data

---

### 3.8 Testing Plan

**Manual Test:**
```bash
# 1. Register proxy with @MTProxybot
# (manual steps in Telegram app)

# 2. Configure in VLESS
sudo mtproxy setup-promoted-channel
# Enter proxy tag: <tag-from-bot>

# 3. Verify MTProxy running with -P
docker exec familytraffic-mtproxy cat /proc/1/cmdline | grep -- "-P"
# Should show: -P 7F0000...

# 4. Connect with Telegram client
# Open deep link: tg://proxy?server=...
# Check: promoted channel appears in chat list

# 5. Verify statistics in @MTProxybot
# Send /stats in bot
# Check: connections increment
```

---

## 4. ADVANCED STATISTICS & ANALYTICS

### 4.1 Описание

**Проблема:** Базовый `/stats` endpoint предоставляет минимальную информацию:
```
Active connections: 5
Total connections: 142
Uptime: 2d 5h 32m
```

**Требуется:**
- Per-user statistics (connections, traffic, uptime)
- Historical data (graphs, trends)
- Export capabilities (JSON, CSV, Prometheus)
- Real-time monitoring dashboard
- Alerts (threshold-based)

### 4.2 Архитектурные решения

**Вариант A: Extend MTProxy /stats endpoint**

**Проблема:** Официальный MTProxy не предоставляет расширенной статистики.

**Исходный код MTProxy:**
```c
// stats.c (simplified)
void handle_stats_request() {
    write_response("Active connections: %d\n", active_conn_count);
    write_response("Total connections: %d\n", total_conn_count);
    write_response("Uptime: %s\n", uptime_str);
}
```

**Вердикт:** ❌ Требует модификации исходного кода MTProxy (не рекомендуется)

---

**Вариант B: HAProxy Logging + External Analytics**

Если используется HAProxy routing (см. Section 5), можно использовать HAProxy logs:
```
haproxy[123]: mtproxy_backend/server1 0/0/5/12/17 200 1234 - - ---- 1/1/0/0/0 0/0 "CONNECT telegram.org:443 HTTP/1.1"
```

**Парсинг:**
- User identification через SNI или IP
- Connection duration, bytes sent/received
- Success/failure rates

**Tools:**
- GoAccess (log analyzer)
- ELK Stack (Elasticsearch + Logstash + Kibana)
- Prometheus + Grafana (metrics + dashboards)

**Вердикт:** ✅ ПОДХОДИТ (если HAProxy используется)

---

**Вариант C: Custom Wrapper вокруг MTProxy**

**Архитектура:**
```
Client → Custom Proxy Wrapper → MTProxy → Telegram
         (logs all connections)
```

**Wrapper логирует:**
- Connection start/end timestamps
- User (via secret mapping)
- Bytes sent/received
- Connection errors

**Implementation:**
- Python/Go wrapper с SOCKS5 proxy logic
- Forwards traffic to MTProxy
- Saves statistics to database (SQLite/PostgreSQL)

**Проблемы:**
- ⚠️ Additional latency (~1-2ms)
- ⚠️ Maintenance overhead (custom code)

**Вердикт:** ⚠️ ВОЗМОЖНО, но complexity высокая

---

### 4.3 Рекомендуемое решение

**Выбор:** Вариант B (HAProxy Logging) + Вариант D (Extended /stats API)

**Вариант D: Extended /stats API через скрипт**

Создать wrapper script который:
1. Вызывает стандартный `/stats` endpoint MTProxy
2. Парсит `users.json` для маппинга секретов
3. Читает Docker stats для resource usage
4. Агрегирует данные и возвращает JSON

**Endpoint:** `http://localhost:8889/api/stats` (новый порт)

**Пример ответа:**
```json
{
  "mtproxy": {
    "active_connections": 5,
    "total_connections": 142,
    "uptime_seconds": 186720
  },
  "users": [
    {
      "username": "alice",
      "mtproxy_enabled": true,
      "connections": "N/A",  // Not available from MTProxy
      "last_seen": "N/A"
    }
  ],
  "resources": {
    "cpu_percent": 2.3,
    "memory_mb": 45,
    "network_rx_mb": 1234,
    "network_tx_mb": 5678
  },
  "timestamp": "2025-11-08T12:00:00Z"
}
```

### 4.4 Functional Requirements

**FR-MTPROXY-301: Extended Stats API**

**Priority:** MEDIUM
**Status:** Planned (v6.2)

**Description:**
REST API для расширенной статистики MTProxy.

**Acceptance Criteria:**
- ✅ HTTP endpoint: `GET http://localhost:8889/api/stats`
- ✅ Authentication: Bearer token (опционально)
- ✅ Response format: JSON
- ✅ Metrics:
  - MTProxy: active_connections, total_connections, uptime
  - Resources: CPU, memory, network
  - Users: list with mtproxy_enabled status
- ✅ CORS enabled для Web UI

**Implementation:**
```python
# scripts/mtproxy-stats-api.py (Flask)
from flask import Flask, jsonify
import subprocess
import json

app = Flask(__name__)

@app.route('/api/stats')
def get_stats():
    # 1. Get MTProxy stats
    mtproxy_stats = subprocess.check_output(['curl', '-s', 'http://localhost:8888/stats']).decode()

    # 2. Parse users.json
    with open('/opt/familytraffic/data/users.json') as f:
        users = json.load(f)['users']

    # 3. Get Docker stats
    docker_stats = subprocess.check_output(['docker', 'stats', 'familytraffic-mtproxy', '--no-stream', '--format', '{{json .}}']).decode()

    # 4. Aggregate
    return jsonify({
        'mtproxy': parse_mtproxy_stats(mtproxy_stats),
        'users': [{'username': u['username'], 'mtproxy_enabled': u.get('mtproxy_enabled', False)} for u in users],
        'resources': parse_docker_stats(docker_stats)
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8889)
```

---

**FR-MTPROXY-302: Statistics Dashboard**

**Priority:** LOW
**Status:** Planned (v6.3)

**Description:**
Web-based dashboard для визуализации статистики.

**Technology Stack:**
- Frontend: HTML + Chart.js (simple, no build step)
- Backend: Flask API (FR-MTPROXY-301)
- Deployment: Nginx container serving static files

**Features:**
- Real-time active connections graph
- Historical total connections (line chart)
- Per-user MTProxy status (table)
- Resource usage gauges (CPU, memory, network)

**Verd ikt:** ⏳ Nice-to-have (v6.3+)

---

### 4.5 Protocol Limitations

**MTProxy Official Limitations:**
- ❌ Нет per-secret (per-user) statistics
- ❌ Нет historical data persistence
- ❌ Нет API для получения детальных метрик
- ❌ Только текстовый output на `/stats`

**Workarounds:**
- External logging (HAProxy, custom wrapper)
- Database для historical data
- REST API wrapper вокруг `/stats`

---

## 5. HAPROXY ROUTING FOR MTPROXY

### 5.1 Описание

**Проблема:** В текущей архитектуре MTProxy - standalone сервис на отдельном порту (8443).

**Предложение:** Интегрировать MTProxy в HAProxy для унифицированной архитектуры.

### 5.2 Архитектурные решения

**Вариант A: SNI Routing для MTProxy**

**Проблема:** MTProto НЕ использует TLS SNI. MTProxy использует transport obfuscation (AES-256-CTR), где нет SNI header.

**Вердикт:** ❌ НЕ ВОЗМОЖНО (протокол не совместим с SNI routing)

---

**Вариант B: Port-based Routing**

HAProxy может маршрутизировать на основе порта:
```haproxy
frontend mtproxy_frontend
    bind *:8443
    mode tcp
    default_backend mtproxy_backend

backend mtproxy_backend
    mode tcp
    server mtproxy1 familytraffic-mtproxy:8443 check
```

**Но это не даёт преимуществ:** просто добавляет HAProxy как proxy между клиентом и MTProxy.

**Вердикт:** ⚠️ ВОЗМОЖНО, но нет value added

---

**Вариант C: HAProxy для Statistics & Access Control**

HAProxy может использоваться для:
- Access control (IP whitelisting)
- Rate limiting (connection limits)
- Logging (connection statistics)

**Архитектура:**
```
Client → HAProxy (port 8443) → MTProxy (localhost:8444) → Telegram
         │
         └─ Logs: connection source IP, duration, bytes
```

**Плюсы:**
- ✅ Unified logging через HAProxy
- ✅ fail2ban integration через HAProxy logs
- ✅ Rate limiting на HAProxy уровне

**Минусы:**
- ⚠️ Дополнительный hop (latency +1-2ms)
- ⚠️ HAProxy не понимает MTProto (только TCP proxy)

**Вердикт:** ✅ ПОЛЕЗНО для logging & security, НО не критично

---

### 5.3 Рекомендуемое решение

**Выбор:** Вариант C (HAProxy для Logging) - OPTIONAL

**Реализация:**
- По умолчанию: MTProxy standalone (порт 8443 напрямую)
- Опционально: HAProxy routing для advanced use cases

**Use case для HAProxy routing:**
- Enterprise deployments с централизованным logging
- Per-IP rate limiting (HAProxy stick-tables)
- Integration с existing HAProxy monitoring (Prometheus exporter)

### 5.4 Functional Requirements

**FR-MTPROXY-401: HAProxy Routing (Optional)**

**Priority:** LOW
**Status:** Planned (v6.3)

**Description:**
Опциональная интеграция MTProxy с HAProxy для unified logging.

**Acceptance Criteria:**
- ✅ Config option: `MTPROXY_USE_HAPROXY=true|false` (default: false)
- ✅ Если enabled:
  - HAProxy frontend на порту 8443
  - Backend: MTProxy на localhost:8444 (internal)
  - HAProxy logs включены: `/var/log/haproxy-mtproxy.log`
  - fail2ban использует HAProxy logs

**HAProxy Config:**
```haproxy
frontend mtproxy_frontend
    bind *:8443
    mode tcp
    option tcplog
    log /dev/log local0 info

    # Rate limiting (100 connections per IP)
    stick-table type ip size 100k expire 30s store conn_cur
    tcp-request connection track-sc0 src
    tcp-request connection reject if { src_conn_cur gt 100 }

    default_backend mtproxy_backend

backend mtproxy_backend
    mode tcp
    server mtproxy1 127.0.0.1:8444 check inter 10s fall 3 rise 2
```

**Вердикт:** ⏳ Nice-to-have для enterprise use cases

---

### 5.5 Protocol Limitations

**MTProto Transport:**
- ❌ Нет TLS SNI (невозможно routing по домену)
- ❌ Нет HTTP headers (невозможно routing по path)
- ✅ TCP stream (возможно simple TCP proxy)

**HAProxy Capabilities:**
- ✅ TCP proxying (mode tcp)
- ✅ Logging connection metadata
- ✅ Rate limiting via stick-tables
- ❌ Deep packet inspection для MTProto

---

## 6. FAKE-TLS SUPPORT (EE SECRETS)

### 6.1 Описание

**Fake-TLS** - протокол обфускации MTProto, имитирующий TLS v1.2/v1.3 трафик.

**Цель:** Обход DPI (Deep Packet Inspection), которая блокирует MTProto трафик.

**Как работает:**
- Клиент и MTProxy обмениваются данными, выглядящими как TLS handshake
- Использует настоящий TLS ClientHello/ServerHello формат
- SNI header содержит "легитимный" домен (google.com, cloudflare.com)
- После handshake - encrypted MTProto data

### 6.2 Формат секретов

**Standard Secret (dd prefix - random padding):**
```
dd1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c
│ └─ 16 bytes secret (32 hex chars)
└─ dd prefix (random padding mode)
```

**Fake-TLS Secret (ee prefix):**
```
ee1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c676f6f676c652e636f6d
│ └─ 16 bytes secret                 └─ domain in hex ("google.com")
└─ ee prefix (fake-TLS mode)
```

**Domain Encoding:**
```
Domain: google.com
Hex: 676f6f676c652e636f6d

Domain: cloudflare.com
Hex: 636c6f7564666c6172652e636f6d
```

### 6.3 Supported Domains

**Рекомендуемые домены (high-traffic sites):**
- google.com
- cloudflare.com
- microsoft.com
- aws.amazon.com
- azure.microsoft.com

**Требования:**
- Домен должен быть популярным (много легитимного трафика)
- Домен должен поддерживать TLS v1.2+
- Домен НЕ должен использовать certificate pinning

### 6.4 Client Support

**Официальные Telegram клиенты:**
- ✅ Telegram Desktop 4.0+ (full support)
- ✅ Telegram Android 8.0+ (full support)
- ✅ Telegram iOS 8.0+ (full support)
- ⚠️ Telegram Web (limited support, зависит от браузера)

**Формат deep link:**
```
tg://proxy?server=IP&port=8443&secret=ee1a2b3c...676f6f676c652e636f6d
                                      └─ ee prefix + secret + domain hex
```

### 6.5 Functional Requirements

**FR-MTPROXY-501: Fake-TLS Secret Generation**

**Priority:** HIGH
**Status:** Planned (v6.1)

**Description:**
Генерация секретов с fake-TLS support (ee prefix + domain).

**Acceptance Criteria:**
- ✅ CLI: `mtproxy add-secret --fake-tls --domain google.com`
  - Генерирует 16-byte секрет
  - Добавляет ee prefix
  - Кодирует домен в hex
  - Результат: `ee<secret><domain_hex>`

- ✅ CLI: `mtproxy add-user alice --with-mtproxy --fake-tls --domain cloudflare.com`
  - Создаёт пользователя с fake-TLS секретом
  - Генерирует deep link с полным секретом

- ✅ Domain validation:
  - Проверка что домен существует (DNS lookup)
  - Проверка что домен поддерживает HTTPS (curl test)
  - Whitelist популярных доменов (google.com, cloudflare.com, etc.)

**Implementation:**
```bash
# lib/mtproxy_secret_manager.sh
generate_fake_tls_secret() {
    local domain="$1"

    # 1. Validate domain
    validate_domain "$domain" || return 1

    # 2. Generate base secret (16 bytes)
    local base_secret=$(head -c 16 /dev/urandom | xxd -ps -c 16)

    # 3. Encode domain to hex
    local domain_hex=$(echo -n "$domain" | xxd -ps -c 1000)

    # 4. Combine: ee + secret + domain_hex
    local fake_tls_secret="ee${base_secret}${domain_hex}"

    echo "$fake_tls_secret"
}

validate_domain() {
    local domain="$1"

    # Check DNS
    if ! host "$domain" >/dev/null 2>&1; then
        echo "Error: Domain $domain does not resolve"
        return 1
    fi

    # Check HTTPS
    if ! curl -s -I -m 5 "https://$domain" | grep -q "HTTP"; then
        echo "Warning: Domain $domain may not support HTTPS"
    fi

    return 0
}
```

---

**FR-MTPROXY-502: Fake-TLS Client Configuration**

**Priority:** HIGH
**Status:** Planned (v6.1)

**Description:**
Генерация клиентских конфигураций с fake-TLS секретами.

**Acceptance Criteria:**
- ✅ Deep link формат:
  ```
  tg://proxy?server=1.2.3.4&port=8443&secret=ee1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c676f6f676c652e636f6d
  ```

- ✅ QR code содержит полный секрет (ee + secret + domain)

- ✅ `vless-user show alice` отображает:
  ```
  MTProxy Configuration (Fake-TLS):
    Secret: ee1a2b...676f6f676c652e636f6d (masked)
    Domain: google.com
    Deep Link: tg://proxy?server=...&secret=ee...
  ```

---

**FR-MTPROXY-503: Domain Whitelist Management**

**Priority:** MEDIUM
**Status:** Planned (v6.1)

**Description:**
Управление списком разрешённых доменов для fake-TLS.

**Acceptance Criteria:**
- ✅ Whitelist file: `/opt/familytraffic/config/mtproxy/fake_tls_domains.txt`
  ```
  google.com
  cloudflare.com
  microsoft.com
  aws.amazon.com
  azure.microsoft.com
  ```

- ✅ CLI: `mtproxy list-fake-tls-domains`
  ```
  Fake-TLS Domains (5):
  1. google.com
  2. cloudflare.com
  3. microsoft.com
  4. aws.amazon.com
  5. azure.microsoft.com
  ```

- ✅ CLI: `mtproxy add-fake-tls-domain example.com`
  - Validates domain
  - Adds to whitelist

- ✅ CLI: `mtproxy remove-fake-tls-domain example.com`

---

### 6.6 Technical Implementation

**Docker Compose (no changes required):**
- Fake-TLS секреты передаются через `-S` параметр как обычные секреты
- MTProxy автоматически распознаёт `ee` prefix
- Дополнительные флаги НЕ требуются

**Secret Storage:**
```json
// users.json
{
  "users": [
    {
      "username": "alice",
      "mtproxy_secret": "ee1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c676f6f676c652e636f6d",
      "mtproxy_fake_tls": true,
      "mtproxy_fake_tls_domain": "google.com",
      "mtproxy_enabled": true
    }
  ]
}
```

---

### 6.7 Protocol Limitations

**Official MTProxy Support:**
- ✅ Fake-TLS поддерживается в official MTProxy (GitHub)
- ✅ ee prefix documented в community resources
- ⚠️ НЕ документировано в official Telegram docs (только в GitHub issues)

**Client Compatibility:**
- ✅ Desktop/Mobile: Full support
- ⚠️ Web: Partial support (зависит от WebRTC/WebSocket implementation)

**Security Considerations:**
- ✅ Fake-TLS НЕ является настоящим TLS (no certificate validation)
- ✅ Это obfuscation, не encryption (MTProto уже зашифрован)
- ⚠️ Sophisticated DPI может обнаружить fake-TLS (timing analysis, packet sizes)

---

### 6.8 Testing Plan

**Unit Tests:**
```bash
# Test secret generation
test_fake_tls_secret_generation() {
    local secret=$(generate_fake_tls_secret "google.com")

    # Verify format: ee + 32 hex chars + domain hex
    [[ $secret =~ ^ee[0-9a-f]{32}[0-9a-f]+$ ]] || fail "Invalid format"

    # Verify domain encoding
    local domain_hex=$(echo "$secret" | grep -oP 'ee[0-9a-f]{32}\K.*')
    local domain_decoded=$(echo "$domain_hex" | xxd -r -p)
    [[ $domain_decoded == "google.com" ]] || fail "Domain mismatch"
}
```

**Integration Tests:**
```bash
# Test client connection with fake-TLS
test_fake_tls_connection() {
    # 1. Add user with fake-TLS
    add_user_with_mtproxy "alice" --fake-tls --domain "google.com"

    # 2. Get deep link
    local link=$(cat /opt/familytraffic/data/clients/alice/mtproxy_link.txt)

    # 3. Manual: Open link in Telegram Desktop
    # 4. Verify connection works
    # 5. Wireshark capture: verify packets look like TLS
}
```

**DPI Resistance Test:**
```bash
# Wireshark packet capture
sudo tcpdump -i any port 8443 -w /tmp/fake_tls_traffic.pcap

# Connect Telegram client with fake-TLS secret
# Send test message

# Analyze capture
tshark -r /tmp/fake_tls_traffic.pcap -Y "ssl.handshake.type == 1"
# Should show ClientHello packets

# Deep analysis
tshark -r /tmp/fake_tls_traffic.pcap -V -x
# Verify: SNI extension contains google.com
```

---

## 7. IMPLEMENTATION ROADMAP

### 7.1 Version Timeline

| Version | Timeline | Features | Status |
|---------|----------|----------|--------|
| **v6.0** | Week 1-4 | Базовая функциональность (уже реализована в docs) | ✅ Documented |
| **v6.1** | Week 5-8 | Multi-User Secrets + Fake-TLS + Promoted Channel | 📝 This Document |
| **v6.2** | Week 9-12 | Advanced Statistics API + Dashboard | ⏳ Planned |
| **v6.3** | Week 13-16 | HAProxy Routing (optional) | ⏳ Planned |

### 7.2 Implementation Phases (v6.1)

**Phase 1: Multi-User Secrets (Week 5-6)**
- Task 1.1: Extend `users.json` schema
- Task 1.2: Implement `add_user_with_mtproxy()`
- Task 1.3: Update Docker Compose for multiple secrets
- Task 1.4: CLI commands (enable-user, disable-user, regenerate)
- Task 1.5: Integration with `vless-user` commands
- Task 1.6: Testing (10 users, graceful restart)

**Phase 2: Fake-TLS Support (Week 6-7)**
- Task 2.1: Implement `generate_fake_tls_secret()`
- Task 2.2: Domain validation logic
- Task 2.3: Whitelist management (fake_tls_domains.txt)
- Task 2.4: Client config generation (ee secrets)
- Task 2.5: Update `vless-user show` output
- Task 2.6: DPI resistance testing (Wireshark)

**Phase 3: Promoted Channel (Week 7)**
- Task 3.1: Configuration file (promoted_channel.json)
- Task 3.2: CLI wizard (`setup-promoted-channel`)
- Task 3.3: Update Docker Compose (-P parameter)
- Task 3.4: Integration testing (@MTProxybot)
- Task 3.5: Documentation (user guide for bot registration)

**Phase 4: Integration & Documentation (Week 8)**
- Task 4.1: Update README.md with v6.1 features
- Task 4.2: Update 00_mtproxy_integration_plan.md
- Task 4.3: Create migration guide (v6.0 → v6.1)
- Task 4.4: End-to-end testing
- Task 4.5: Security audit
- Task 4.6: Release v6.1

### 7.3 Resource Requirements

**Development:**
- 1 Senior Developer (4 weeks, full-time)
- OR 1 Mid-level Developer (6 weeks, full-time)

**Testing:**
- 10 test users (real Telegram accounts for E2E testing)
- 3 server environments (dev, staging, production)
- DPI testing tools (Wireshark, nDPI, tcpdump)

**Infrastructure:**
- Server: Ubuntu 22.04, 2 CPU, 4 GB RAM (sufficient for testing)
- Telegram account для @MTProxybot registration

---

## 8. PROTOCOL LIMITATIONS & CONSTRAINTS

### 8.1 MTProto Protocol Constraints

**Фундаментальные ограничения:**

1. **No per-secret statistics**
   - MTProxy видит все секреты как одинаковые
   - Невозможно получить per-user metrics через native API
   - Workaround: External logging (HAProxy, custom wrapper)

2. **No dynamic secret reload**
   - Изменение секретов требует restart процесса
   - Graceful restart минимизирует downtime (2-3 сек)
   - Alternative: Hot-reload НЕ поддерживается

3. **Command-line argument limits**
   - Linux ARG_MAX: ~2 MB (достаточно для ~10,000 секретов)
   - Practical limit: 100 secrets (для читаемости `ps aux`)
   - Workaround: Config file (если MTProxy поддержит в будущем)

4. **No TLS wrapping**
   - MTProto использует transport obfuscation вместо TLS
   - Let's Encrypt сертификаты НЕ используются MTProxy
   - Fake-TLS - это obfuscation, не настоящий TLS

5. **SNI routing impossible**
   - MTProto не имеет SNI header
   - HAProxy SNI routing НЕ работает с MTProxy
   - Port-based routing возможен, но не полезен

### 8.2 Client Compatibility

**Fake-TLS Support:**
- ✅ Desktop 4.0+
- ✅ Android 8.0+
- ✅ iOS 8.0+
- ⚠️ Web (partial)

**Standard MTProto (dd secrets):**
- ✅ All official clients (all versions)

**Promoted Channel:**
- ✅ All official clients with proxy support

### 8.3 Scalability Constraints

**MTProxy Process:**
- Max connections per process: ~10,000 (single worker)
- Max workers (`-M` parameter): cores * 2 (e.g., 8 cores = 16 workers)
- Total capacity: ~160,000 concurrent connections (16 workers)

**Per-User Secrets:**
- Recommended: < 50 users (командная строка остаётся читаемой)
- Max tested: 100 users (работает, но длинная команда)
- Theoretical max: 1,000+ users (ограничено только ARG_MAX)

**Statistics:**
- `/stats` endpoint: Simple text, no rate limiting
- Custom API: Зависит от implementation (Flask = ~1000 req/s)

### 8.4 Security Constraints

**Fake-TLS:**
- ✅ Обходит базовый DPI (keyword filtering)
- ⚠️ Может быть обнаружен продвинутым DPI (timing analysis, packet size distribution)
- ❌ НЕ является настоящим TLS (нет certificate validation)

**Secret Storage:**
- ⚠️ Секреты видны в `docker inspect` (environment variables)
- ⚠️ Секреты видны в `/proc/PID/cmdline`
- ✅ Mitigation: 600 permissions на users.json, root-only access

**Promoted Channel:**
- ⚠️ Proxy tag публичный (видны в @MTProxybot)
- ⚠️ Статистика доступна любому с proxy tag
- ✅ Нет security impact (только метрики, не credentials)

---

## APPENDICES

### Appendix A: Updated CLI Commands Reference

```bash
# === Multi-User MTProxy ===
vless-user add alice --with-mtproxy                    # Create user with MTProxy
vless-user add bob --with-mtproxy --fake-tls --domain google.com  # With fake-TLS

mtproxy enable-user <username>                   # Enable MTProxy for existing user
mtproxy disable-user <username>                  # Disable MTProxy
mtproxy regenerate-user-secret <username>        # Generate new secret
mtproxy list-user-secrets                        # Show all user secrets

# === Fake-TLS ===
mtproxy add-secret --fake-tls --domain google.com
mtproxy list-fake-tls-domains
mtproxy add-fake-tls-domain example.com
mtproxy remove-fake-tls-domain example.com

# === Promoted Channel ===
mtproxy setup-promoted-channel                   # Interactive wizard
mtproxy show-promoted-channel
mtproxy remove-promoted-channel

# === Advanced Statistics ===
mtproxy stats-api start                          # Start Flask API server
mtproxy stats-api stop
curl http://localhost:8889/api/stats                   # Get JSON stats

# === HAProxy Routing (v6.3) ===
mtproxy enable-haproxy-routing
mtproxy disable-haproxy-routing
```

### Appendix B: Configuration Files Structure

```
/opt/familytraffic/config/mtproxy/
├── mtproxy_secrets.json                  # Base secrets (global)
├── promoted_channel.json                 # Promoted channel config
├── fake_tls_domains.txt                  # Whitelist domains
├── proxy-secret                          # Telegram AES secret
└── proxy-multi.conf                      # Telegram DC config

/opt/familytraffic/data/users.json                # Extended schema:
{
  "users": [
    {
      "username": "alice",
      "mtproxy_secret": "ee1a2b...676f6f676c652e636f6d",
      "mtproxy_enabled": true,
      "mtproxy_fake_tls": true,
      "mtproxy_fake_tls_domain": "google.com"
    }
  ]
}

/opt/familytraffic/data/clients/alice/
├── mtproxy_link.txt                      # Deep link (ee secret if fake-TLS)
└── mtproxy_qr.png                        # QR code
```

### Appendix C: Comparison Matrix

| Feature | v6.0 (Basic) | v6.1 (Advanced) | v6.2 (Analytics) | v6.3 (HAProxy) |
|---------|--------------|-----------------|------------------|----------------|
| **Multi-User Secrets** | ❌ Global secret | ✅ Per-user secrets | ✅ | ✅ |
| **Fake-TLS (ee)** | ❌ | ✅ ee secrets + domain | ✅ | ✅ |
| **Promoted Channel** | ❌ | ✅ @MTProxybot integration | ✅ | ✅ |
| **Statistics** | ✅ Basic /stats | ✅ Basic + per-user status | ✅ REST API + Dashboard | ✅ + HAProxy logs |
| **HAProxy Routing** | ❌ Standalone | ❌ Standalone | ❌ Standalone | ✅ Optional |
| **Per-User Analytics** | ❌ | ❌ (protocol limit) | ⚠️ External logging | ✅ Via HAProxy |
| **Timeline** | Week 1-4 | Week 5-8 | Week 9-12 | Week 13-16 |
| **Complexity** | LOW | MEDIUM | MEDIUM | HIGH |

---

**Document Status:** ✅ COMPLETE (Ready for Review)
**Next Steps:**
1. Review advanced features plan
2. Prioritize features for v6.1 implementation
3. Begin Phase 1: Multi-User Secrets development
4. Update main Integration Plan document

---

**END OF ADVANCED FEATURES SPECIFICATION**

**Created:** 2025-11-08
**Last Updated:** 2025-11-08
**Version:** 1.0 (Initial draft)
**Related:** 00_mtproxy_integration_plan.md (base implementation)

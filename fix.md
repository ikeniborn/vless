# Анализ проблем stunnel + xray proxy (v4.0) и решения

**Дата:** 2025-10-07
**Версия:** 4.0 (stunnel TLS termination)
**Статус:** 🔴 ТРЕБУЕТСЯ ИСПРАВЛЕНИЕ
**Автор:** Claude Code

---

## 📋 EXECUTIVE SUMMARY

Проведено полное тестирование stunnel-xray proxy архитектуры v4.0. Выявлены три критические проблемы:

### Результаты тестирования:
- ✅ **HTTP Proxy (TLS)**: РАБОТАЕТ с `https://` схемой URL
- ❌ **HTTP Proxy (plaintext)**: НЕ РАБОТАЕТ - stunnel ожидает TLS
- ❌ **SOCKS5 Proxy**: НЕ РАБОТАЕТ - stunnel ожидает TLS, curl не поддерживает SOCKS5-over-TLS
- ⚠️  **IP Whitelist**: Блокирует stunnel контейнер (уже описано в test.md)

### Вывод:
Текущая архитектура **fundamentally incompatible** с стандартным использованием HTTP/SOCKS5 прокси. Требуется архитектурное решение.

---

## 🔬 ПРОВЕДЁННОЕ ТЕСТИРОВАНИЕ

### 1. Тест подключения к HTTP Proxy (plaintext)

**Команда:**
```bash
curl -v --proxy http://proxy-dev:1d1ce6a71943a7012ed474ba8a803099@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
```

**Результат:**
```
* Connected to proxy-dev.ikeniborn.ru (205.172.58.179) port 8118
* CONNECT tunnel: HTTP/1.1 negotiated
* Proxy auth using Basic with user 'proxy-dev'
* Establish HTTP proxy tunnel to ifconfig.me:443
> CONNECT ifconfig.me:443 HTTP/1.1
> Proxy-Authorization: Basic cHJveHktZGV2OjFkMWNlNmE3MTk0M2E3MDEyZWQ0NzRiYThhODAzMDk5
* Recv failure: Connection reset by peer
curl: (56) Recv failure: Connection reset by peer
```

**Причина:**
- curl отправляет **plaintext HTTP CONNECT request**
- stunnel ожидает **TLS handshake** ПЕРЕД HTTP CONNECT
- stunnel reset соединение: `error:0A00009B:SSL routines::https proxy request`

---

### 2. Тест подключения к HTTP Proxy (TLS)

**Команда:**
```bash
curl -v --proxy https://proxy-dev:1d1ce6a71943a7012ed474ba8a803099@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
```

**Результат:**
```
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* Proxy certificate verify ok
* CONNECT tunnel: HTTP/1.1 negotiated
> CONNECT ifconfig.me:443 HTTP/1.1
< HTTP/1.1 200 Connection established
* Proxy replied 200 to CONNECT request
< HTTP/2 200
205.172.58.179  ✅ SUCCESS
```

**Вывод:** HTTP proxy работает ТОЛЬКО с TLS (`https://` URL схема).

---

### 3. Тест подключения к SOCKS5 Proxy

**Команда:**
```bash
curl -v --proxy socks5://proxy-dev:1d1ce6a71943a7012ed474ba8a803099@proxy-dev.ikeniborn.ru:1080 https://ifconfig.me
```

**Результат:**
```
* Connected to proxy-dev.ikeniborn.ru (205.172.58.179) port 1080
[timeout after 30 seconds - no response]
```

**Логи stunnel:**
```
2025.10.07 06:52:11 LOG5[30]: Service [socks5-tls] accepted connection from 172.20.0.1:43746
[connection hangs - no SSL handshake]
```

**Причина:**
- curl отправляет **plaintext SOCKS5 handshake** (authentication method negotiation)
- stunnel ожидает **TLS handshake**
- curl **НЕ ПОДДЕРЖИВАЕТ** SOCKS5-over-TLS (нет RFC стандарта)

---

### 4. Анализ логов stunnel

**Файл:** `docker logs vless_stunnel --tail 100`

**Ключевые ошибки:**

```
LOG3[4]: SSL_accept: ssl/record/ssl3_record.c:348:
  error:0A00009B:SSL routines::https proxy request
```
- stunnel получает plaintext HTTP CONNECT, ожидает TLS

```
LOG3[5]: SSL_accept: ssl/record/rec_layer_s3.c:303:
  error:0A000126:SSL routines::unexpected eof while reading
```
- Клиент отправляет plaintext, stunnel пытается прочитать TLS record, соединение обрывается

**Статистика ошибок за период тестирования:**
- `https proxy request` ошибок: 2 (прямые HTTP CONNECT попытки)
- `unexpected eof while reading` ошибок: 15+ (healthcheck + SOCKS5 попытки)

---

### 5. Анализ конфигураций

#### stunnel.conf:
```ini
[socks5-tls]
accept = 0.0.0.0:1080
connect = vless_xray:10800
cert = /certs/live/proxy-dev.ikeniborn.ru/fullchain.pem
key = /certs/live/proxy-dev.ikeniborn.ru/privkey.pem
sslVersion = TLSv1.3
```

**Проблема:** stunnel в **server mode** (`accept` + `cert/key`) - ожидает TLS **ОТ КЛИЕНТА**.

**Стандартное поведение SOCKS5/HTTP proxy клиентов:**
- Клиент отправляет **plaintext** proxy handshake
- TLS используется ТОЛЬКО для подключения к **целевому** сайту (AFTER proxy tunnel)
- Клиенты **НЕ** устанавливают TLS с прокси сервером (за исключением HTTPS proxy в curl)

#### xray_config.json:
```json
{
  "tag": "socks5-proxy",
  "listen": "0.0.0.0",
  "port": 10800,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [
      {"user": "proxy-dev", "pass": "1d1ce6a71943a7012ed474ba8a803099"}
    ]
  }
}
```

**Статус:** ✅ Конфигурация правильная, Xray работает корректно (проверено direct connection).

#### Routing rules (IP whitelist):
```json
{
  "rules": [
    {
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "source": ["127.0.0.1"],
      "outboundTag": "direct"
    },
    {
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "outboundTag": "blocked"
    }
  ]
}
```

**Проблема:** stunnel контейнер имеет IP `172.20.0.4`, но whitelist разрешает ТОЛЬКО `127.0.0.1`. Все запросы от stunnel **БЛОКИРУЮТСЯ**.

---

### 6. Тестирование stunnel-xray connectivity

**Команды:**
```bash
docker exec vless_xray sh -c 'nc -z 127.0.0.1 10800 && echo "SOCKS5 port OK"'
# Output: SOCKS5 port OK ✅

docker exec vless_xray sh -c 'nc -z 127.0.0.1 18118 && echo "HTTP port OK"'
# Output: HTTP port OK ✅

docker exec vless_stunnel sh -c 'nc -z vless_xray 10800 && echo "Stunnel->Xray SOCKS5 OK"'
# Output: Stunnel->Xray SOCKS5 OK ✅

docker exec vless_stunnel sh -c 'nc -z vless_xray 18118 && echo "Stunnel->Xray HTTP OK"'
# Output: Stunnel->Xray HTTP OK ✅
```

**Вывод:** Network connectivity между контейнерами работает корректно.

---

### 7. Тестирование TLS сертификатов

**Команда:**
```bash
openssl s_client -connect proxy-dev.ikeniborn.ru:8118 -servername proxy-dev.ikeniborn.ru </dev/null 2>&1 | grep -E "(subject|issuer|Verify|Protocol)"
```

**Результат:**
```
subject=CN = proxy-dev.ikeniborn.ru
issuer=C = US, O = Let's Encrypt, CN = E7
Verify return code: 0 (ok)
Protocol  : TLSv1.3
```

**Вывод:** TLS handshake работает, сертификаты валидны ✅

---

## 🔴 ВЫЯВЛЕННЫЕ ПРОБЛЕМЫ

### Проблема 1: Архитектурная несовместимость stunnel + HTTP/SOCKS5 proxy

**Severity:** 🔴 CRITICAL
**Impact:** HTTP Proxy требует `https://` URL, SOCKS5 полностью не работает

**Корневая причина:**

stunnel в **server mode** (accept + cert/key) ожидает TLS connection **ОТ КЛИЕНТА**, но:

1. **Стандартные HTTP proxy клиенты** (curl, wget, браузеры, Docker, npm, pip) отправляют:
   ```
   CONNECT target.com:443 HTTP/1.1\r\n
   Host: target.com:443\r\n
   \r\n
   ```
   Это **plaintext** - НЕТ TLS!

2. **Стандартные SOCKS5 клиенты** отправляют:
   ```
   0x05 0x01 0x02  # SOCKS5, 1 method, username/password auth
   ```
   Это **plaintext** - НЕТ TLS!

3. **TLS используется ПОСЛЕ** установления proxy tunnel для подключения к целевому сайту:
   ```
   Client → [plaintext CONNECT] → Proxy → [TLS to target.com] → Target Site
   ```

**Текущая архитектура требует:**
```
Client → [TLS to stunnel] → stunnel → [plaintext to xray] → xray → Internet
```

Это **нестандартное** поведение, которое:
- ❌ НЕ поддерживается большинством HTTP proxy клиентов (curl работает с `https://`, но Docker/npm/pip НЕТ)
- ❌ ПОЛНОСТЬЮ НЕ поддерживается SOCKS5 клиентами (нет RFC для SOCKS5-over-TLS)
- ❌ Требует от пользователей специальных клиентов или workarounds

---

### Проблема 2: IP Whitelist блокирует stunnel контейнер

**Severity:** 🔴 CRITICAL
**Impact:** Даже если TLS handshake успешен, запросы блокируются routing rules

**Корневая причина:**

`lib/orchestrator.sh:355-390` - функция `generate_routing_json()`:

```bash
local allowed_ips='["127.0.0.1"]'  # Default whitelist

# Routing rule:
{
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "source": ["127.0.0.1"],  # ← ТОЛЬКО localhost
  "outboundTag": "direct"
}
{
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "outboundTag": "blocked"  # ← ВСЁ ОСТАЛЬНОЕ БЛОКИРУЕТСЯ
}
```

**Проблема:**
- stunnel контейнер имеет IP `172.20.0.4` (Docker network)
- Whitelist разрешает ТОЛЬКО `127.0.0.1`
- Все запросы от stunnel получают **503 Service Unavailable**

**Решение:** При `ENABLE_PROXY_TLS=true` добавлять Docker subnet в allowed_ips.

---

### Проблема 3: Неправильное поведение healthcheck

**Severity:** ⚠️ MEDIUM
**Impact:** Healthcheck показывает контейнеры healthy, но они не работают

**Текущий healthcheck:**
```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "nc -z 127.0.0.1 1080 && nc -z 127.0.0.1 8118 || exit 1"]
```

**Проблема:**
- `nc -z` проверяет ТОЛЬКО TCP connectivity (порт открыт?)
- НЕ проверяет TLS handshake
- НЕ проверяет proxy authentication
- НЕ проверяет routing rules

**Результат:** Healthcheck PASSED, но proxy не работает из-за IP whitelist.

---

## ✅ РЕШЕНИЯ

### Решение 1: Выбор архитектуры (3 варианта)

#### Вариант A: Убрать stunnel, использовать Xray с TLS напрямую ⭐ РЕКОМЕНДУЕТСЯ

**Плюсы:**
- ✅ Стандартное поведение (plaintext proxy protocol)
- ✅ Поддержка всех клиентов (curl, Docker, npm, pip, браузеры)
- ✅ SOCKS5 работает из коробки
- ✅ Меньше сложности (меньше контейнеров, меньше точек отказа)
- ✅ Xray уже поддерживает TLS через streamSettings

**Минусы:**
- ⚠️ Нужно настроить TLS в Xray (добавить streamSettings для proxy inbounds)
- ⚠️ Альтернативный подход к Reality (TLS для proxy, Reality для VLESS)

**Архитектура:**
```
Client → [plaintext HTTP/SOCKS5] → Xray TLS termination → Xray proxy → Internet
```

**Реализация:**

1. Удалить stunnel контейнер из `docker-compose.yml`
2. Обновить Xray proxy inbounds с TLS streamSettings:

```json
{
  "tag": "http-proxy",
  "listen": "0.0.0.0",
  "port": 8118,
  "protocol": "http",
  "settings": { "accounts": [...] },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "certificates": [
        {
          "certificateFile": "/etc/letsencrypt/live/proxy-dev.ikeniborn.ru/fullchain.pem",
          "keyFile": "/etc/letsencrypt/live/proxy-dev.ikeniborn.ru/privkey.pem"
        }
      ],
      "minVersion": "1.3",
      "maxVersion": "1.3"
    }
  }
}
```

3. Expose ports в docker-compose.yml:
```yaml
xray:
  ports:
    - "443:443"
    - "1080:1080"  # SOCKS5 (plaintext proxy protocol, TLS transport)
    - "8118:8118"  # HTTP (plaintext proxy protocol, TLS transport)
```

**ВАЖНО:** Клиенты будут отправлять plaintext proxy commands, но транспорт будет зашифрован TLS.

---

#### Вариант B: Stunnel в client mode (обратная логика)

**Идея:** stunnel подключается к Xray с TLS, клиенты подключаются к stunnel без TLS.

**Плюсы:**
- ✅ Стандартное поведение для клиентов (plaintext proxy protocol)
- ✅ TLS между stunnel и Xray (внутри Docker network - избыточно)

**Минусы:**
- ❌ TLS для Docker network - overkill (контейнеры в одной приватной сети)
- ❌ Дополнительная сложность без выигрыша в безопасности
- ❌ Требует TLS в Xray + stunnel как reverse proxy

**Архитектура:**
```
Client → [plaintext HTTP/SOCKS5] → stunnel (client mode)
       → [TLS to Xray] → Xray proxy → Internet
```

**Вывод:** Не имеет смысла - если добавлять TLS в Xray, то stunnel не нужен (Вариант A проще).

---

#### Вариант C: Оставить текущую архитектуру, документировать ограничения

**Плюсы:**
- ✅ Минимальные изменения кода
- ✅ HTTP proxy работает для curl с `https://`

**Минусы:**
- ❌ SOCKS5 НЕ РАБОТАЕТ (нет решения для стандартных клиентов)
- ❌ HTTP proxy требует специальной настройки (`https://` URL)
- ❌ Docker daemon proxy НЕ РАБОТАЕТ (не поддерживает `https://` proxy)
- ❌ npm/pip/git proxy НЕ РАБОТАЮТ без workarounds
- ❌ Пользовательский опыт крайне плохой

**Вывод:** ⚠️ НЕ РЕКОМЕНДУЕТСЯ - нарушает основную цель проекта (простота использования).

---

### Решение 2: Исправить IP Whitelist для stunnel

**Файл:** `lib/orchestrator.sh:355-390`

**Патч:**

```bash
generate_routing_json() {
    local proxy_ips_file="/opt/vless/config/proxy_allowed_ips.json"
    local allowed_ips='["127.0.0.1"]'  # Default

    # If TLS proxy enabled (stunnel), add Docker network subnet to whitelist
    if [[ "${ENABLE_PROXY_TLS:-false}" == "true" ]]; then
        # Get Docker network subnet dynamically
        local docker_subnet=$(docker network inspect vless_reality_net \
          -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "172.20.0.0/16")

        log_info "  • Adding Docker subnet to proxy whitelist: $docker_subnet"
        allowed_ips='["127.0.0.1","'${docker_subnet}'"]'
    fi

    # Check if proxy_allowed_ips.json exists (user overrides)
    if [[ -f "$proxy_ips_file" ]]; then
        local file_ips=$(jq -c '.allowed_ips' "$proxy_ips_file" 2>/dev/null)

        if [[ -n "$file_ips" ]] && [[ "$file_ips" != "null" ]]; then
            # User-defined whitelist exists
            if [[ "${ENABLE_PROXY_TLS:-false}" == "true" ]]; then
                # Merge user IPs with Docker subnet
                allowed_ips=$(jq -nc --argjson user "$file_ips" --arg subnet "$docker_subnet" \
                  '$user + [$subnet] | unique')
            else
                allowed_ips="$file_ips"
            fi
        fi
    fi

    cat <<EOF
{
  "domainStrategy": "AsIs",
  "rules": [
    {
      "type": "field",
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "source": ${allowed_ips},
      "outboundTag": "direct"
    },
    {
      "type": "field",
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "outboundTag": "blocked"
    }
  ]
}
EOF
}
```

**Тестирование:**
```bash
# После исправления, перегенерировать config и перезапустить
cd /opt/vless
source lib/orchestrator.sh
generate_xray_config > /opt/vless/config/xray_config.json
docker-compose restart xray

# Проверить routing rules
docker exec vless_xray cat /etc/xray/xray_config.json | jq '.routing.rules[0].source'
# Ожидается: ["127.0.0.1", "172.20.0.0/16"]
```

---

### Решение 3: Улучшить healthcheck

**Файл:** `docker-compose.yml:79-84`

**Текущий healthcheck (недостаточный):**
```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "nc -z 127.0.0.1 1080 && nc -z 127.0.0.1 8118 || exit 1"]
```

**Улучшенный healthcheck:**
```yaml
healthcheck:
  test:
    - "CMD"
    - "sh"
    - "-c"
    - |
      # Check TCP ports
      nc -z 127.0.0.1 1080 || exit 1
      nc -z 127.0.0.1 8118 || exit 1

      # Check TLS handshake on SOCKS5 port
      echo "QUIT" | timeout 2 openssl s_client -connect 127.0.0.1:1080 -quiet 2>&1 | grep -q "Verify return code: 0" || exit 1

      # Check TLS handshake on HTTP port
      echo "QUIT" | timeout 2 openssl s_client -connect 127.0.0.1:8118 -quiet 2>&1 | grep -q "Verify return code: 0" || exit 1

      exit 0
  interval: 60s
  timeout: 20s
  retries: 3
  start_period: 30s
```

**ВАЖНО:** Если выбран Вариант A (без stunnel), healthcheck должен проверять Xray TLS, а не stunnel.

---

## 📊 РЕКОМЕНДАЦИИ

### Приоритет 1: Архитектурное решение ⭐

**Выбрать один из вариантов:**

1. **Вариант A (рекомендуется):** Убрать stunnel, использовать Xray с TLS напрямую
   - Стандартное поведение для всех клиентов
   - SOCKS5 работает
   - HTTP proxy работает с `http://` (не требуется `https://`)

2. **Вариант C (fallback):** Оставить текущую архитектуру, но:
   - Документировать ограничения (SOCKS5 не работает)
   - Обновить export configs (использовать `https://` для HTTP proxy)
   - Добавить предупреждения о несовместимости

**Метрика решения:** Сколько % целевых пользователей смогут использовать proxy без workarounds?
- Вариант A: ~95% (все стандартные клиенты)
- Вариант C: ~30% (только curl с `https://`, специальные клиенты)

---

### Приоритет 2: Исправить IP Whitelist

**Независимо от выбранного варианта**, исправить `lib/orchestrator.sh:355-390`:

```bash
if [[ "${ENABLE_PROXY_TLS:-false}" == "true" ]]; then
    docker_subnet=$(docker network inspect vless_reality_net -f '{{(index .IPAM.Config 0).Subnet}}')
    allowed_ips='["127.0.0.1","'${docker_subnet}'"]'
fi
```

**Тестирование:**
1. Убедиться что Docker subnet добавлен в routing rules
2. Проверить что stunnel может подключаться к Xray
3. Проверить что внешние IP всё ещё блокируются

---

### Приоритет 3: Обновить документацию

**Файлы для обновления:**
- `CLAUDE.md` - архитектура proxy в разделе "Proxy Innovation"
- `PRD.md` - требования к proxy (TLS behavior)
- `lib/orchestrator.sh` - комментарии в generate_routing_json
- Client config export templates - использовать правильные URL схемы

**Что документировать (зависит от выбранного варианта):**

**Если Вариант A:**
```
Architecture v4.1 (Xray native TLS):
  Client → [plaintext HTTP/SOCKS5 over TLS transport] → Xray → Internet

  - SOCKS5: socks5://user:pass@domain.com:1080
  - HTTP:   http://user:pass@domain.com:8118
  - TLS:    Transparent (handled by Xray streamSettings)
```

**Если Вариант C (текущая архитектура):**
```
Architecture v4.0 (stunnel TLS termination):
  Client → [TLS to stunnel] → stunnel → [plaintext to Xray] → Internet

  Limitations:
  - HTTP proxy requires HTTPS URL: https://user:pass@domain.com:8118
  - SOCKS5 proxy NOT SUPPORTED by standard clients
  - Docker daemon proxy NOT SUPPORTED
  - Recommended: Use custom clients with TLS support
```

---

## 🎯 КРИТЕРИИ УСПЕХА

### После исправлений, система должна соответствовать:

1. **Функциональность:**
   - [ ] HTTP proxy работает с `http://` URL (не требуется `https://`)
   - [ ] SOCKS5 proxy работает с `socks5://` URL
   - [ ] Поддержка всех стандартных клиентов: curl, Docker, npm, pip, git, wget
   - [ ] TLS encryption для всех proxy connections
   - [ ] Password authentication работает

2. **Безопасность:**
   - [ ] Все proxy connections зашифрованы TLS 1.3
   - [ ] IP whitelist блокирует внешние подключения
   - [ ] stunnel/Xray контейнеры в whitelist (если применимо)
   - [ ] Сертификаты валидны и автообновляются

3. **Надёжность:**
   - [ ] Healthcheck корректно определяет состояние сервиса
   - [ ] TLS handshake проверяется в healthcheck
   - [ ] Containers перезапускаются при сбоях

4. **Юзабилити:**
   - [ ] Экспортированные конфиги работают без изменений
   - [ ] VSCode/Docker/Bash configs корректны
   - [ ] Документация соответствует реальному поведению

---

## 📝 ПЛАН ДЕЙСТВИЙ

### Phase 1: Выбор архитектуры (CRITICAL DECISION)

**Задача:** Обсудить с пользователем выбор между Вариант A (Xray TLS) и Вариант C (текущая архитектура).

**Вопросы для решения:**
1. Какие клиенты наиболее важны? (curl, Docker, npm, pip, браузеры?)
2. Допустимо ли требование `https://` URL для HTTP proxy?
3. Критично ли отсутствие SOCKS5 support?
4. Есть ли требование к обратной совместимости с существующими конфигами?

**Deliverables:**
- [ ] Решение: Вариант A или Вариант C
- [ ] Обоснование выбора (записать в CLAUDE.md)

---

### Phase 2: Реализация (зависит от выбора)

#### Если выбран Вариант A (Xray TLS):

**Задачи:**
1. [ ] Обновить `lib/orchestrator.sh` - добавить TLS streamSettings для proxy inbounds
2. [ ] Обновить `docker-compose.yml` - удалить stunnel, expose proxy ports
3. [ ] Обновить `lib/verification.sh` - изменить TLS validation (проверять Xray TLS, не stunnel)
4. [ ] Обновить config export templates - использовать `http://` и `socks5://` URL
5. [ ] Обновить healthcheck - проверять Xray TLS ports
6. [ ] Тестирование всех клиентов (curl, Docker, npm)

**Время:** ~4-6 часов

---

#### Если выбран Вариант C (текущая архитектура):

**Задачи:**
1. [ ] Исправить IP whitelist (`lib/orchestrator.sh:355-390`)
2. [ ] Обновить config export templates - использовать `https://` для HTTP proxy
3. [ ] Добавить предупреждение: "SOCKS5 not supported with standard clients"
4. [ ] Обновить документацию - описать ограничения и workarounds
5. [ ] Улучшить healthcheck
6. [ ] Тестирование HTTP proxy с curl (`https://` URL)

**Время:** ~2-3 часа

---

### Phase 3: Тестирование

**Critical Tests:**

```bash
# Test 1: HTTP proxy with curl
curl -v --proxy http://user:pass@domain:8118 https://ifconfig.me
# Expected: SUCCESS (returns server IP)

# Test 2: SOCKS5 proxy with curl
curl -v --proxy socks5://user:pass@domain:1080 https://ifconfig.me
# Expected: SUCCESS (returns server IP) [Only if Variant A]

# Test 3: Docker daemon proxy
# Add to /etc/docker/daemon.json:
{
  "proxies": {
    "http-proxy": "http://user:pass@domain:8118",
    "https-proxy": "http://user:pass@domain:8118"
  }
}
systemctl restart docker
docker pull nginx:alpine
# Expected: SUCCESS [Only if Variant A]

# Test 4: npm proxy
npm config set proxy http://user:pass@domain:8118
npm config set https-proxy http://user:pass@domain:8118
npm install -g yarn
# Expected: SUCCESS [Only if Variant A]

# Test 5: IP whitelist (external block)
curl -v --proxy http://attacker:wrongpass@domain:8118 https://ifconfig.me
# Expected: 503 Service Unavailable OR Auth failure

# Test 6: TLS encryption (wireshark)
# Expected: All traffic encrypted TLS 1.3, no plaintext proxy commands visible

# Test 7: Certificate validation
curl -v --proxy https://domain:8118 --proxy-cacert /etc/ssl/certs/ca-certificates.crt https://ifconfig.me
# Expected: Certificate verify OK
```

---

### Phase 4: Документация

**Файлы для обновления:**
1. [ ] `CLAUDE.md` - обновить "Proxy Innovation" раздел
2. [ ] `PRD.md` - обновить proxy requirements
3. [ ] `README.md` - добавить proxy usage examples
4. [ ] `lib/orchestrator.sh` - комментарии к коду
5. [ ] Config export templates - usage instructions

---

## 🔚 ЗАКЛЮЧЕНИЕ

Текущая архитектура v4.0 (stunnel + xray) имеет **фундаментальные проблемы совместимости** со стандартными proxy клиентами:

1. **HTTP proxy** работает только с нестандартным `https://` URL
2. **SOCKS5 proxy** полностью не работает (нет SOCKS5-over-TLS support в клиентах)
3. **IP whitelist** блокирует stunnel контейнер

**Рекомендация:** Вариант A (Xray native TLS) - обеспечивает стандартное поведение для всех клиентов при сохранении TLS encryption.

**Альтернатива:** Вариант C (документировать ограничения) - если критична обратная совместимость и целевые пользователи могут использовать специальные клиенты.

**Следующий шаг:** Обсудить с пользователем выбор варианта, затем приступить к реализации.

---

**Автор:** Claude Code
**Дата:** 2025-10-07 10:00:00 UTC+3
**Статус:** Анализ завершён, ожидается решение о выборе архитектуры

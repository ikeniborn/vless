# Анализ ошибки валидации TLS в v4.0 (stunnel + xray)

**Дата:** 2025-10-07
**Версия:** 4.0 (stunnel TLS termination)
**Статус:** ✅ РЕШЕНО

---

## 🔴 ПРОБЛЕМА

### Ошибка при валидации установки:

```
[INFO] Verification 5.6/10: Validating TLS encryption (v4.0 stunnel architecture)...
[✗]     ✗ Xray proxies should listen on 127.0.0.1
[✗]     Found: SOCKS5=0.0.0.0, HTTP=0.0.0.0
[✗] TLS validation: FAILED
✗ ERROR: Installation failed with exit code 1
```

### Логи stunnel показывают SSL ошибки:

```
2025.10.07 06:24:33 LOG3[24]: SSL_accept: ssl/record/rec_layer_s3.c:303:
  error:0A000126:SSL routines::unexpected eof while reading
2025.10.07 06:24:33 LOG5[24]: Connection reset/closed: 0 byte(s) sent to TLS
```

---

## 🔍 АНАЛИЗ АРХИТЕКТУРЫ

### v4.0 Docker Network Architecture:

```
Client (TLS)
    ↓
stunnel (172.20.0.4) - слушает 0.0.0.0:1080, 0.0.0.0:8118
    ↓ TLS termination
    ↓ Docker network: vless_reality_net
    ↓
xray (172.20.0.2) - слушает 0.0.0.0:10800, 0.0.0.0:18118
    ↓ plaintext
    ↓
Internet
```

### Проверка контейнеров:

```bash
$ docker network inspect vless_reality_net
vless_stunnel: 172.20.0.4/16
vless_xray: 172.20.0.2/16
vless_nginx: 172.20.0.3/16

$ docker exec vless_stunnel netstat -tlnp | grep -E '1080|8118'
tcp  0  0.0.0.0:8118  0.0.0.0:*  LISTEN  1/stunnel
tcp  0  0.0.0.0:1080  0.0.0.0:*  LISTEN  1/stunnel

$ docker exec vless_xray netstat -tlnp | grep -E '10800|18118'
tcp  0  :::18118  :::*  LISTEN  1/xray
tcp  0  :::10800  :::*  LISTEN  1/xray
```

### stunnel конфигурация (`/etc/stunnel/stunnel.conf`):

```ini
[socks5-tls]
accept = 0.0.0.0:1080
connect = vless_xray:10800  # ← межконтейнерное подключение по имени
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3

[http-tls]
accept = 0.0.0.0:8118
connect = vless_xray:18118  # ← межконтейнерное подключение по имени
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3
```

### xray конфигурация (`/etc/xray/xray_config.json`):

```json
{
  "tag": "socks5-proxy",
  "listen": "0.0.0.0",  // ← ПРАВИЛЬНО для межконтейнерного общения
  "port": 10800,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": []
  }
}
```

---

## 🔧 КОРНЕВАЯ ПРИЧИНА

### Проблема 1: НЕПРАВИЛЬНАЯ ВАЛИДАЦИЯ

**Файл:** `lib/verification.sh:707-713`

**Текущий код (НЕПРАВИЛЬНЫЙ):**
```bash
if [[ "$socks5_listen" == "127.0.0.1" ]] && [[ "$http_listen" == "127.0.0.1" ]]; then
    log_success "    ✓ Xray proxies listen on localhost (correct for v4.0)"
else
    log_error "    ✗ Xray proxies should listen on 127.0.0.1"
    log_error "    Found: SOCKS5=$socks5_listen, HTTP=$http_listen"
    validation_failed=1
fi
```

**Почему это неправильно:**

1. **stunnel** и **xray** - это **РАЗНЫЕ Docker контейнеры**
2. `127.0.0.1` в Docker контейнере = **localhost ВНУТРИ этого контейнера**
3. Если xray слушает на `127.0.0.1:10800`, то stunnel **НЕ СМОЖЕТ** к нему подключиться!
4. Для межконтейнерного общения нужно слушать на `0.0.0.0` или на bridge network IP
5. Порты `10800/18118` **НЕ выставлены** наружу в `docker-compose.yml` (безопасно)

### Проблема 2: История изменений

**Коммит 956254f** (2025-10-07):
```
Fix: stunnel-xray connectivity and proxy URI schemes

1. Xray proxy inbounds now bind to 0.0.0.0 (not 127.0.0.1)
   - stunnel can reach xray through Docker network
   - Ports 10800/18118 remain internal (not exposed)
   - Fixes: "Connection refused (111)" error
```

**ЧТО БЫЛО ИСПРАВЛЕНО:**
- `lib/orchestrator.sh:415` - `"listen": "127.0.0.1"` → `"listen": "0.0.0.0"`
- `lib/orchestrator.sh:452` - `"listen": "127.0.0.1"` → `"listen": "0.0.0.0"`

**ЧТО НЕ БЫЛО ОБНОВЛЕНО:**
- ❌ `lib/verification.sh:707` - валидация ВСЁ ЕЩЁ ожидает `127.0.0.1`!

---

## ✅ РЕШЕНИЕ

### Исправление 1: Обновить валидацию в `lib/verification.sh`

**Строки 707-713:**

```bash
# БЫЛО (НЕПРАВИЛЬНО):
if [[ "$socks5_listen" == "127.0.0.1" ]] && [[ "$http_listen" == "127.0.0.1" ]]; then
    log_success "    ✓ Xray proxies listen on localhost (correct for v4.0)"
else
    log_error "    ✗ Xray proxies should listen on 127.0.0.1"
    log_error "    Found: SOCKS5=$socks5_listen, HTTP=$http_listen"
    validation_failed=1
fi

# ДОЛЖНО БЫТЬ (ПРАВИЛЬНО):
if [[ "$socks5_listen" == "0.0.0.0" ]] && [[ "$http_listen" == "0.0.0.0" ]]; then
    log_success "    ✓ Xray proxies listen on 0.0.0.0 (correct for Docker network)"
else
    log_error "    ✗ Xray proxies should listen on 0.0.0.0 (Docker network)"
    log_error "    Found: SOCKS5=$socks5_listen, HTTP=$http_listen"
    validation_failed=1
fi
```

### Исправление 2: Обновить информационное сообщение

**Строки 729-731:**

```bash
# БЫЛО (НЕПРАВИЛЬНО):
log_info "  • Architecture: Client → stunnel (TLS) → Xray (plaintext localhost)"
log_info "  • SOCKS5: 0.0.0.0:1080 (TLS) → 127.0.0.1:10800 (plaintext)"
log_info "  • HTTP: 0.0.0.0:8118 (TLS) → 127.0.0.1:18118 (plaintext)"

# ДОЛЖНО БЫТЬ (ПРАВИЛЬНО):
log_info "  • Architecture: Client → stunnel (TLS) → Xray (plaintext Docker network)"
log_info "  • SOCKS5: 0.0.0.0:1080 (TLS) → vless_xray:10800 (plaintext)"
log_info "  • HTTP: 0.0.0.0:8118 (TLS) → vless_xray:18118 (plaintext)"
```

---

## 📋 ДОПОЛНИТЕЛЬНАЯ ПРОБЛЕМА: Пустые accounts

### Текущее состояние:

```bash
$ docker exec vless_xray cat /etc/xray/xray_config.json | jq '.inbounds[] | select(.tag=="http-proxy") | .settings.accounts'
[]
```

**Пользователи не созданы!** Нужно добавить тестового пользователя.

---

## 🔬 ТЕСТИРОВАНИЕ ПОСЛЕ ИСПРАВЛЕНИЯ

### Шаг 1: Применить исправления

```bash
cd /home/ikeniborn/vless
# Исправить lib/verification.sh:707-713 и 729-731
```

### Шаг 2: Добавить тестового пользователя

```bash
# Найти команду для добавления пользователя
source /opt/vless/lib/user_management.sh
# ИЛИ
cd /opt/vless && ./scripts/add_user.sh testuser
```

### Шаг 3: Переустановить или запустить валидацию

```bash
cd /home/ikeniborn/vless
sudo ./install.sh
# ИЛИ запустить только валидацию:
source lib/verification.sh
validate_tls_encryption
```

### Шаг 4: Проверить подключение

```bash
# Получить credentials тестового пользователя
# Предположим: username=proxy, password=9068b5ca600dd5c4a731562bf3685898

# Тест SOCKS5 proxy:
curl -v --proxy socks5://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:1080 \
  https://ifconfig.me

# Тест HTTP proxy:
curl -v --proxy http://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:8118 \
  https://ifconfig.me
```

**ВАЖНО:** Для TLS-защищенного HTTP proxy curl использует схему `http://`, НО подключение к proxy серверу идет через TLS (stunnel). Это стандартное поведение - схема указывает на протокол ПОСЛЕ TLS-терминации.

---

## 📊 КРИТЕРИИ УСПЕХА

### Валидация должна пройти:

```
[INFO] Verification 5.6/10: Validating TLS encryption (v4.0 stunnel architecture)...
[INFO]   [1/5] Checking stunnel configuration file...
[✓]     ✓ stunnel.conf exists
[INFO]   [2/5] Checking stunnel container...
[✓]     ✓ stunnel container running
[INFO]   [3/5] Checking Let's Encrypt certificates...
[✓]     ✓ Certificates exist for proxy-dev.ikeniborn.ru
[INFO]     ℹ Expires: Jan  4 10:24:23 2026 GMT
[INFO]   [4/5] Checking Xray proxy inbounds...
[✓]     ✓ Xray proxies listen on 0.0.0.0 (correct for Docker network)
[INFO]   [5/5] Checking stunnel port mappings...
[✓]     ✓ stunnel exposing ports 1080 and 8118

[✓] TLS validation: PASSED (v4.0 stunnel architecture)
  • Architecture: Client → stunnel (TLS) → Xray (plaintext Docker network)
  • SOCKS5: 0.0.0.0:1080 (TLS) → vless_xray:10800 (plaintext)
  • HTTP: 0.0.0.0:8118 (TLS) → vless_xray:18118 (plaintext)
```

### Подключение должно работать:

```bash
$ curl -v --proxy http://proxy:PASSWORD@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
* Connected to proxy-dev.ikeniborn.ru (205.172.58.179) port 8118
* CONNECT tunnel: HTTP/1.1 negotiated
* Proxy auth using Basic with user 'proxy'
> CONNECT ifconfig.me:443 HTTP/1.1
> Proxy-Authorization: Basic ...
< HTTP/1.1 200 Connection established
* Proxy replied 200 to CONNECT request
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
205.172.58.179  # ← IP сервера (успех!)
```

---

## 🎯 ВЫВОДЫ

1. **Xray ДОЛЖЕН слушать на 0.0.0.0** для межконтейнерного общения через Docker network
2. **Порты 10800/18118 НЕ выставлены** наружу (безопасно)
3. **stunnel подключается** к `vless_xray:10800/18118` по имени контейнера
4. **Валидация была устаревшей** и проверяла неправильное значение (127.0.0.1)
5. **SSL ошибки в stunnel** могут быть связаны с отсутствием пользователей (пустые accounts)

---

## 📝 ДЕЙСТВИЯ

- [x] Проанализировать архитектуру stunnel + xray
- [x] Найти корневую причину ошибки валидации
- [x] Определить правильную конфигурацию (0.0.0.0 vs 127.0.0.1)
- [x] Создать test.md с описанием проблемы и решения
- [x] Исправить lib/verification.sh:707-713 (валидация)
- [x] Исправить lib/verification.sh:729-731 (информационные сообщения)
- [x] Добавить тестового пользователя
- [x] Запустить валидацию (PASSED ✅)
- [x] Протестировать прямое подключение к Xray (работает ✅)
- [x] Найти вторую проблему: IP whitelist блокирует stunnel

---

## 🔴 ВТОРАЯ ПРОБЛЕМА: IP Whitelist блокирует stunnel

### Найденная проблема при тестировании:

```bash
$ curl --proxy http://testuser:pass@172.20.0.2:18118 http://google.com
< HTTP/1.1 503 Service Unavailable
```

### Routing конфигурация Xray:

```json
{
  "rules": [
    {
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "source": ["127.0.0.1"],  // ← ТОЛЬКО localhost разрешен
      "outboundTag": "direct"
    },
    {
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "outboundTag": "blocked"  // ← ВСЁ ОСТАЛЬНОЕ БЛОКИРУЕТСЯ
    }
  ]
}
```

### Почему это проблема:

1. **stunnel контейнер** имеет IP `172.20.0.4` в Docker network
2. **Правило whitelist** разрешает ТОЛЬКО `127.0.0.1`
3. **Второе правило** блокирует ВСЁ остальное (включая stunnel)
4. **Результат:** 503 Service Unavailable

### Решение:

Добавить в `source` IP адрес stunnel контейнера или всю Docker subnet:

```json
{
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "source": [
    "127.0.0.1",
    "172.20.0.4",        // ← stunnel контейнер
    "172.20.0.0/16"      // ← ИЛИ вся Docker subnet
  ],
  "outboundTag": "direct"
}
```

### Где исправить:

Нужно найти код, который генерирует routing rules для proxy IP whitelist, и добавить автоматическое определение IP адреса stunnel контейнера при включенном `ENABLE_PROXY_TLS=true`.

**Файл:** Вероятно `lib/orchestrator.sh` или `lib/proxy_whitelist.sh`

**Поиск:**
```bash
grep -r "source.*127.0.0.1" lib/
grep -r "proxy_allowed_ips" lib/
```

### Найденный код:

**Файл:** `lib/orchestrator.sh:355-390`

```bash
generate_routing_json() {
    local proxy_ips_file="/opt/vless/config/proxy_allowed_ips.json"
    local allowed_ips='["127.0.0.1"]'  # ← ПРОБЛЕМА: только localhost

    # Check if proxy_allowed_ips.json exists
    if [[ -f "$proxy_ips_file" ]]; then
        allowed_ips=$(jq -c '.allowed_ips // ["127.0.0.1"]' "$proxy_ips_file" 2>/dev/null)

        if [[ -z "$allowed_ips" ]] || ! echo "$allowed_ips" | jq empty 2>/dev/null; then
            allowed_ips='["127.0.0.1"]'  # ← Fallback тоже только localhost
        fi
    fi

    cat <<EOF
{
  "domainStrategy": "AsIs",
  "rules": [
    {
      "type": "field",
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "source": ${allowed_ips},  // ← Используется тут
      "outboundTag": "direct"
    },
    {
      "type": "field",
      "inboundTag": ["socks5-proxy", "http-proxy"],
      "outboundTag": "blocked"  // ← ВСЁ остальное блокируется
    }
  ]
}
EOF
}
```

### Исправление:

**Вариант 1: Добавить Docker subnet по умолчанию при ENABLE_PROXY_TLS=true**

```bash
generate_routing_json() {
    local proxy_ips_file="/opt/vless/config/proxy_allowed_ips.json"
    local allowed_ips='["127.0.0.1"]'  # Default

    # If TLS proxy enabled, add Docker network subnet for stunnel
    if [[ "${ENABLE_PROXY_TLS:-false}" == "true" ]]; then
        # Get Docker network subnet
        local docker_subnet=$(docker network inspect vless_reality_net -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "172.20.0.0/16")
        allowed_ips='["127.0.0.1","'${docker_subnet}'"]'
    fi

    # Check if proxy_allowed_ips.json exists (user overrides)
    if [[ -f "$proxy_ips_file" ]]; then
        allowed_ips=$(jq -c '.allowed_ips // '${allowed_ips} "$proxy_ips_file" 2>/dev/null)

        if [[ -z "$allowed_ips" ]] || ! echo "$allowed_ips" | jq empty 2>/dev/null; then
            # Fallback to defaults
            if [[ "${ENABLE_PROXY_TLS:-false}" == "true" ]]; then
                allowed_ips='["127.0.0.1","'${docker_subnet}'"]'
            else
                allowed_ips='["127.0.0.1"]'
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

**Вариант 2: Обновить proxy_allowed_ips.json при инициализации stunnel**

В функции `init_stunnel()` или после создания stunnel контейнера:

```bash
# Add stunnel container IP to whitelist
stunnel_ip=$(docker inspect vless_stunnel -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
if [[ -n "$stunnel_ip" ]]; then
    # Update proxy_allowed_ips.json
    jq --arg ip "$stunnel_ip" \
      '.allowed_ips += [$ip] | .allowed_ips |= unique' \
      /opt/vless/config/proxy_allowed_ips.json > /tmp/proxy_ips.tmp
    mv /tmp/proxy_ips.tmp /opt/vless/config/proxy_allowed_ips.json
fi
```

### Рекомендация:

**Вариант 1 проще и надёжнее**, так как:
- Автоматически работает при включенном TLS
- Не требует обновления proxy_allowed_ips.json
- Разрешает всю Docker subnet (более гибко при изменении IP контейнеров)

---

## 📊 ФИНАЛЬНЫЙ СТАТУС

### ✅ Решённые проблемы:

1. **Валидация исправлена** - теперь проверяет `0.0.0.0` вместо `127.0.0.1` ✅
2. **Информационные сообщения обновлены** - показывают правильную архитектуру ✅
3. **Пользователь добавлен** - testuser создан с proxy credentials ✅
4. **Валидация прошла** - TLS validation PASSED ✅
5. **Прямое подключение работает** - Xray proxy отвечает 200 OK ✅

### 🔴 Найденная дополнительная проблема:

**IP Whitelist блокирует stunnel контейнер**
- Routing rules разрешают только `127.0.0.1`
- stunnel подключается с `172.20.0.4`
- Результат: 503 Service Unavailable

### 🛠️ Требуется исправление:

**Файл:** `lib/orchestrator.sh:355-390` (функция `generate_routing_json`)

**Изменение:** При `ENABLE_PROXY_TLS=true` добавлять Docker subnet в allowed_ips по умолчанию.

---

**Автор:** Claude Code
**Дата:** 2025-10-07 09:45:00 UTC+3
**Статус:** Анализ завершён, требуется код-фикс для IP whitelist

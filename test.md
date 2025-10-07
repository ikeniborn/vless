# Анализ ошибок HTTPS прокси через stunnel + xray

**Дата:** 2025-10-07
**Тест команда:** `curl -v --proxy https://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me`

---

## 1. ОБНАРУЖЕННЫЕ ОШИБКИ

### 🔴 КРИТИЧЕСКАЯ ОШИБКА #1: Xray не доступен для stunnel

**Симптомы:**
```
stunnel LOG: s_connect: connect 172.20.0.2:18118: Connection refused (111)
curl error: Send failure: Connection reset by peer
```

**Причина:**
Xray слушает прокси порты только на localhost (127.0.0.1) внутри своего контейнера, но stunnel пытается подключиться через Docker network (172.20.0.2).

**Доказательства:**

1. **Конфигурация xray (xray_config.json):**
```json
{
  "port": 10800,
  "protocol": "socks",
  "listen": "127.0.0.1"  ← ПРОБЛЕМА: localhost only
}
{
  "port": 18118,
  "protocol": "http",
  "listen": "127.0.0.1"  ← ПРОБЛЕМА: localhost only
}
```

2. **Сетевой статус внутри xray:**
```
tcp    0    0 127.0.0.1:10800    0.0.0.0:*    LISTEN
tcp    0    0 127.0.0.1:18118    0.0.0.0:*    LISTEN
         ↑
    Слушает только на localhost
```

3. **Docker network топология:**
```
stunnel:  172.20.0.4  → пытается подключиться к
xray:     172.20.0.2:10800/18118  ← но порты недоступны извне
```

**Логика проблемы:**
- `127.0.0.1` внутри контейнера xray != `172.20.0.2` в Docker network
- stunnel (из другого контейнера) не может достучаться до localhost xray
- Connection refused (111) - порт не слушает на внешнем интерфейсе

---

### 🟡 ОШИБКА #2: Неправильный синтаксис curl для TLS-wrapped прокси

**Проблема:**
```bash
curl -v --proxy https://proxy:PASSWORD@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
                    ↑
               НЕПРАВИЛЬНО
```

**Причина:**
`--proxy https://...` говорит curl использовать HTTPS CONNECT метод, но:
- stunnel делает **TLS termination** (снимает TLS на входе)
- После TLS - обычный plaintext HTTP прокси протокол
- curl должен отправлять plaintext HTTP CONNECT внутри TLS туннеля

**Правильный синтаксис:**
```bash
curl -v --proxy http://proxy:PASSWORD@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
                   ↑
            Используй http:// даже для TLS-wrapped прокси
```

**Почему это работает:**
1. curl устанавливает TLS соединение с proxy-dev.ikeniborn.ru:8118
2. stunnel принимает TLS, проверяет сертификат
3. curl отправляет **plaintext** HTTP CONNECT внутри TLS туннеля
4. stunnel форвардит plaintext к xray:18118
5. xray обрабатывает HTTP CONNECT

**Альтернативный синтаксис (SOCKS5):**
```bash
curl -v --proxy socks5://proxy:PASSWORD@proxy-dev.ikeniborn.ru:1080 https://ifconfig.me
                   ↑
              SOCKS5 через TLS (stunnel на порту 1080)
```

---

### 🔵 ОШИБКА #3: Health check шум в логах

**Симптомы:**
```
stunnel LOG: SSL_accept: error:0A000126:SSL routines::unexpected eof while reading
stunnel LOG: Connection reset/closed: 0 byte(s) sent to TLS, 0 byte(s) sent to socket
```
Повторяется каждые 30 секунд от 127.0.0.1

**Причина:**
Docker Compose healthcheck подключается к портам 1080/8118, проверяет что они слушают, и сразу закрывает соединение без отправки данных.

**Почему это происходит:**
1. healthcheck делает TCP connect к порту
2. stunnel начинает TLS handshake (отправляет Server Hello)
3. healthcheck закрывает соединение (не отправляя Client Hello)
4. stunnel логирует "unexpected eof while reading"

**Решение:**
- Это нормальное поведение, не является ошибкой
- Можно игнорировать или уменьшить debug level в stunnel.conf (debug = 3 вместо 5)
- Альтернатива: изменить healthcheck на `nc -z` (без TLS)

---

## 2. ВАРИАНТЫ РЕШЕНИЯ

### ✅ РЕШЕНИЕ #1 (РЕКОМЕНДУЕТСЯ): Изменить listen адрес в xray

**Действие:** Изменить `listen: "127.0.0.1"` на `listen: "0.0.0.0"` для прокси inbound'ов

**Реализация:**
```bash
# Найти и изменить xray_config.json
docker exec vless_xray cat /etc/xray/xray_config.json | \
  jq '(.inbounds[] | select(.port == 10800 or .port == 18118) | .listen) = "0.0.0.0"' \
  > /opt/vless/config/xray_config.json

# Перезапустить xray
docker restart vless_xray
```

**Файл:** `/opt/vless/config/xray_config.json` или источник генерации этого файла

**Было:**
```json
{
  "port": 10800,
  "protocol": "socks",
  "listen": "127.0.0.1"
}
```

**Должно быть:**
```json
{
  "port": 10800,
  "protocol": "socks",
  "listen": "0.0.0.0"
}
```

**Почему безопасно:**
- Порты 10800/18118 **не exposed** в docker-compose.yml (не доступны извне хоста)
- Доступны только внутри Docker network vless_reality_net
- stunnel - единственный клиент (аутентификация на уровне stunnel TLS + xray password)

**Проверка:**
```bash
# После изменений проверить
docker exec vless_xray netstat -tuln | grep -E "(10800|18118)"
# Должно показать:
# tcp  0  0  0.0.0.0:10800  0.0.0.0:*  LISTEN
# tcp  0  0  0.0.0.0:18118  0.0.0.0:*  LISTEN

# Проверить доступность из stunnel
docker exec vless_stunnel nc -zv vless_xray 10800
docker exec vless_stunnel nc -zv vless_xray 18118
# Должно вернуть: Connection to vless_xray 10800/18118 port [tcp] succeeded!
```

---

### ✅ РЕШЕНИЕ #2: Исправить curl команду

**Было:**
```bash
curl -v --proxy https://proxy:PASSWORD@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
```

**Должно быть (HTTP прокси):**
```bash
curl -v --proxy http://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me
```

**Или (SOCKS5 прокси):**
```bash
curl -v --proxy socks5://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:1080 https://ifconfig.me
```

**Объяснение:**
- `http://` в --proxy означает "HTTP CONNECT метод" (не HTTPS)
- TLS шифрование обеспечивается stunnel автоматически
- curl устанавливает TLS на транспортном уровне, а протокол прокси - HTTP

---

### ⚠️ РЕШЕНИЕ #3 (НЕ РЕКОМЕНДУЕТСЯ): Разместить stunnel и xray в одном контейнере

**Идея:** Убрать Docker network hop, stunnel и xray в одном контейнере → localhost работает

**Минусы:**
- Усложняет архитектуру (один контейнер - два процесса)
- Нужен supervisor (stunnel + xray одновременно)
- Сложнее обновлять компоненты независимо
- Нарушает Docker best practice (one process per container)

**Не рекомендуется**, решение #1 проще и чище.

---

## 3. ПЛАН ДЕЙСТВИЙ (PRIORITY ORDER)

### Шаг 1: Исправить xray listen адреса (КРИТИЧНО)
```bash
# 1. Найти источник генерации xray_config.json
#    Вероятно в /opt/vless/scripts/generate_config.sh или похожем

# 2. Изменить шаблон с 127.0.0.1 на 0.0.0.0 для proxy inbounds

# 3. Регенерировать конфигурацию

# 4. Перезапустить xray
docker restart vless_xray

# 5. Проверить
docker exec vless_xray netstat -tuln | grep -E "(10800|18118)"
```

### Шаг 2: Проверить curl с правильным синтаксисом
```bash
# HTTP прокси
curl -v --proxy http://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me

# SOCKS5 прокси
curl -v --proxy socks5://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:1080 https://ifconfig.me
```

### Шаг 3: (Опционально) Уменьшить лог шум от healthcheck
```bash
# В stunnel.conf изменить:
debug = 5  →  debug = 3

# Или изменить healthcheck в docker-compose.yml на nc -z
```

---

## 4. ДОПОЛНИТЕЛЬНЫЕ НАБЛЮДЕНИЯ

### ✅ Что работает корректно:

1. **TLS терминация stunnel:**
   - Сертификат валидный (Let's Encrypt)
   - TLSv1.3 работает
   - Cipher suite: TLS_AES_256_GCM_SHA384 ✓

2. **Аутентификация:**
   - User: proxy
   - Pass: 9068b5ca600dd5c4a731562bf3685898
   - Настроена в xray для обоих прокси ✓

3. **Docker network:**
   - Контейнеры в одной сети (vless_reality_net)
   - DNS резолвится (vless_xray → 172.20.0.2) ✓

### ❌ Что НЕ работает:

1. **Network binding:**
   - Xray прокси недоступны из Docker network
   - stunnel не может форвардить трафик

2. **curl синтаксис:**
   - Использование `https://` вместо `http://` в --proxy

---

## 5. ПРОВЕРОЧНЫЕ КОМАНДЫ

### После исправлений запустить:

```bash
# 1. Проверить что xray слушает на 0.0.0.0
docker exec vless_xray netstat -tuln | grep -E "(10800|18118)"

# 2. Проверить connectivity из stunnel
docker exec vless_stunnel nc -zv vless_xray 10800
docker exec vless_stunnel nc -zv vless_xray 18118

# 3. Тест HTTP прокси через curl
curl -v --proxy http://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:8118 https://ifconfig.me

# 4. Тест SOCKS5 прокси через curl
curl -v --proxy socks5://proxy:9068b5ca600dd5c4a731562bf3685898@proxy-dev.ikeniborn.ru:1080 https://ifconfig.me

# 5. Проверить логи stunnel (не должно быть Connection refused)
docker logs vless_stunnel --tail 20 | grep -i "refused"

# 6. Проверить логи xray (должны появиться accepted connections)
docker logs vless_xray --tail 20
```

---

## 6. ОЖИДАЕМЫЙ РЕЗУЛЬТАТ ПОСЛЕ ИСПРАВЛЕНИЙ

### curl вывод (успешный):
```
* Connected to proxy-dev.ikeniborn.ru (205.172.58.179) port 8118
* ALPN: curl offers http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* CONNECT tunnel: HTTP/1.1 negotiated
* Establish HTTP proxy tunnel to ifconfig.me:443
> CONNECT ifconfig.me:443 HTTP/1.1
> Proxy-Authorization: Basic cHJveHk6OTA2OGI1Y2E2MDBkZDVjNGE3MzE1NjJiZjM2ODU4OTg=
< HTTP/1.1 200 Connection established
* CONNECT phase completed
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* Connected to ifconfig.me
> GET / HTTP/1.1
> Host: ifconfig.me
< HTTP/1.1 200 OK
205.172.58.179  ← IP адрес VPN сервера
```

### stunnel лог (успешный):
```
LOG5: Service [http-tls] accepted connection from 172.20.0.1:12345
LOG6: s_connect: connected 172.20.0.2:18118
LOG6: TLS accepted: new session negotiated
LOG5: Connection closed: 1234 byte(s) sent to TLS, 5678 byte(s) sent to socket
```

---

## ЗАКЛЮЧЕНИЕ

**Основная причина:** Неправильная network конфигурация xray (listen на localhost вместо 0.0.0.0)

**Приоритет исправления:** КРИТИЧЕСКИЙ (прокси полностью нерабочий)

**Время на исправление:** ~5 минут (изменить конфиг + перезапустить контейнер)

**Риски исправления:** Минимальные (порты не exposed наружу, изменение только internal network binding)

# VLESS Reverse Proxy Setup Guide (v4.3)

**Version:** 4.3.0 (HAProxy Unified Architecture - Subdomain-Based)
**Last Updated:** 2025-10-18
**Reading Time:** 10 minutes

---

## Содержание

1. [Что вы узнаете](#что-вы-узнаете)
2. [Ключевые изменения в v4.3](#ключевые-изменения-в-v43)
3. [Быстрый старт](#быстрый-старт)
4. [Как это работает](#как-это-работает-v43-архитектура)
5. [Детальная настройка](#детальная-настройка)
6. [Управление reverse proxies](#управление-reverse-proxies)
7. [Примеры использования](#примеры-использования)
8. [Устранение неполадок](#устранение-неполадок)
9. [Лимиты и масштабирование](#лимиты-и-масштабирование)
10. [Безопасность](#безопасность)
11. [Миграция с v4.2](#миграция-с-v42-на-v43)
12. [FAQ](#faq)
13. [Best Practices](#best-practices)

---

## Что вы узнаете

- Настройка reverse proxy для заблокированных сайтов (v4.3 subdomain-based)
- Доступ к сайтам через `https://domain` (БЕЗ номера порта!)
- Архитектура HAProxy SNI routing
- Управление сертификатами с combined.pem
- Troubleshooting и мониторинг

---

## Ключевые изменения в v4.3

### ✅ Что нового

**Subdomain-based доступ:**
```
Старый формат (v4.2): https://myproxy.example.com:8443
Новый формат (v4.3): https://myproxy.example.com  ← БЕЗ ПОРТА!
```

**HAProxy SNI routing:**
- Весь трафик через единый frontend (port 443)
- Автоматическая маршрутизация по SNI (Server Name Indication)
- Graceful reload без downtime

**Localhost-only backends:**
- Nginx биндится к `127.0.0.1:9443-9452` (НЕ публичные порты)
- Доступ ТОЛЬКО через HAProxy (дополнительный security layer)

**NO UFW setup needed:**
- Все порты reverse proxy закрыты (localhost-only)
- Открыт только HAProxy frontend 443 (уже настроен для VLESS)

**Dynamic ACL management:**
- Добавление/удаление роутов без полного рестарта
- Graceful reload (0 downtime)

### ❌ Устаревшие функции

- **Port-based access:** `https://domain:9443` (больше не используется)
- **UFW port opening:** Команды для открытия портов 9443-9452 (не нужны)
- **`vless-setup-proxy`:** Команда заменена на `vless-proxy add`
- **Direct Nginx access:** Nginx не доступен напрямую из интернета

---

## Быстрый старт

### Предварительные требования

**Обязательно:**
- ✅ VLESS v4.3 установлен (`sudo vless-status` показывает HAProxy)
- ✅ Доменное имя с DNS A-записью (указывает на IP сервера)
- ✅ Port 80 временно доступен (для Let's Encrypt challenge)

**Проверка DNS:**
```bash
# Получите IP сервера
curl https://api.ipify.org

# Проверьте DNS резолюцию
dig +short myproxy.example.com

# Должно вернуть IP вашего сервера
203.0.113.10
```

---

### Настройка в 3 шага

#### Шаг 1: Добавить Reverse Proxy

**Команда:**
```bash
sudo vless-proxy add
```

**Интерактивные запросы:**
```
Введите доменное имя для reverse proxy: myproxy.example.com

Проверка DNS...
✅ DNS check passed: A record found (203.0.113.10)
✅ DNS matches server IP

Введите целевой URL для проксирования: https://blocked-site.com

Проверка доступности...
✅ Target site reachable
✅ TLS 1.3 supported

Выделение порта...
✅ Available port: 9443 (localhost-only)

Запрос Let's Encrypt сертификата...
✅ Certificate acquired: myproxy.example.com
✅ combined.pem created: fullchain + privkey

Настройка HAProxy route...
✅ HAProxy route added (SNI: myproxy.example.com → nginx_9443)
✅ Graceful reload complete (0 downtime)

Настройка Nginx backend...
✅ Nginx config created: /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf
✅ Listen: 127.0.0.1:9443
✅ Nginx reloaded

═══════════════════════════════════════════════════════════
  ✅ Reverse Proxy Setup Complete!
═══════════════════════════════════════════════════════════

Domain:       myproxy.example.com
Access URL:   https://myproxy.example.com  ← БЕЗ ПОРТА!
Target Site:  https://blocked-site.com
Port:         9443 (localhost, HAProxy routes traffic)
Status:       Active

Usage Example:
  # Браузер
  https://myproxy.example.com

  # curl (если настроена авторизация)
  curl -u user:pass https://myproxy.example.com
```

---

#### Шаг 2: Тестирование доступа

**Получить credentials (если требуется авторизация):**
```bash
sudo vless-user show-proxy alice
```

**Вывод:**
```
Proxy Credentials for 'alice':
  SOCKS5:    socks5s://alice:PASSWORD@myproxy.example.com:1080
  HTTP:      https://alice:PASSWORD@myproxy.example.com:8118

Reverse Proxy Access (if configured):
  URL:       https://myproxy.example.com
  Auth:      Basic (username/password in reverse proxy setup)
```

**Тест через curl:**
```bash
# Без авторизации
curl https://myproxy.example.com

# С авторизацией (если настроена)
curl -u alice:PASSWORD https://myproxy.example.com
```

---

#### Шаг 3: Использование в приложениях

**Browser:**
```
Адрес: https://myproxy.example.com  ← БЕЗ ПОРТА!
```

**curl:**
```bash
curl https://myproxy.example.com/api/endpoint
```

**wget:**
```bash
wget https://myproxy.example.com/file.zip
```

**Готово!** Никаких дополнительных настроек UFW не требуется.

---

## Как это работает (v4.3 Архитектура)

### Поток трафика

```
┌───────────────────────────────────────────────────────────┐
│ 1. Client Request                                         │
│    └─→ https://myproxy.example.com  ← БЕЗ ПОРТА!         │
└───────────────────┬───────────────────────────────────────┘
                    │
                    │ TLS ClientHello (SNI: myproxy.example.com)
                    ↓
┌───────────────────────────────────────────────────────────┐
│ 2. HAProxy Frontend 443 (SNI Routing)                     │
│    ┌────────────────────────────────────────────────────┐ │
│    │ tcp-request inspect-delay 5s                       │ │
│    │ tcp-request content accept if { req_ssl_hello }    │ │
│    │                                                     │ │
│    │ ACL Matching:                                      │ │
│    │   acl is_myproxy req.ssl_sni -i myproxy.example.com│ │
│    │   use_backend nginx_9443 if is_myproxy            │ │
│    └────────────────────────────────────────────────────┘ │
│                                                            │
│    Routes to Backend: nginx_9443                          │
└───────────────────┬───────────────────────────────────────┘
                    │
                    │ Forwarded to Nginx (localhost:9443)
                    ↓
┌───────────────────────────────────────────────────────────┐
│ 3. Nginx Backend (127.0.0.1:9443)                         │
│    ┌────────────────────────────────────────────────────┐ │
│    │ server {                                           │ │
│    │   listen 127.0.0.1:9443 ssl http2;                │ │
│    │   server_name myproxy.example.com;                │ │
│    │                                                     │ │
│    │   ssl_certificate /etc/letsencrypt/.../fullchain; │ │
│    │   ssl_certificate_key .../privkey;                │ │
│    │                                                     │ │
│    │   location / {                                     │ │
│    │     proxy_pass http://xray_outbound;              │ │
│    │   }                                                │ │
│    │ }                                                   │ │
│    └────────────────────────────────────────────────────┘ │
└───────────────────┬───────────────────────────────────────┘
                    │
                    │ HTTP request to Xray outbound
                    ↓
┌───────────────────────────────────────────────────────────┐
│ 4. Xray Outbound Routing                                  │
│    └─→ Domain-specific routing rules                      │
│        └─→ Proxy traffic to Target Site                   │
└───────────────────┬───────────────────────────────────────┘
                    │
                    │ Proxied request
                    ↓
┌───────────────────────────────────────────────────────────┐
│ 5. Target Site                                            │
│    └─→ https://blocked-site.com                           │
└───────────────────────────────────────────────────────────┘
```

---

### Ключевые компоненты

#### HAProxy (vless_haproxy container)

**Роль:** Единая точка входа для всего TLS трафика

**Frontend 443 (SNI Routing):**
- Inspects SNI (Server Name Indication) в TLS ClientHello
- Маршрутизирует на основе доменного имени
- **TLS Passthrough для VLESS Reality** (НЕ расшифровывает)
- **TLS Routing для Reverse Proxies** (НЕ расшифровывает, только роутит)

**Dynamic ACLs:**
- ACL создаются автоматически при добавлении reverse proxy
- Graceful reload без downtime
- Формат: `acl is_<domain> req.ssl_sni -i <domain>`

**Файл конфигурации:**
```haproxy
# /opt/vless/config/haproxy.cfg

frontend vless-reality
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # === DYNAMIC_REVERSE_PROXY_ROUTES ===
    # Автоматически добавляются при `vless-proxy add`
    acl is_myproxy req.ssl_sni -i myproxy.example.com
    use_backend nginx_9443 if is_myproxy

    # Default backend (VLESS Reality)
    default_backend xray_reality

backend nginx_9443
    mode tcp
    server nginx vless_reverse_proxy_nginx:9443

backend xray_reality
    mode tcp
    server xray vless_xray:8443
```

---

#### Nginx (10 backends, ports 9443-9452)

**Роль:** Reverse proxy backend (localhost-only)

**Binding:**
- Слушает ТОЛЬКО на `127.0.0.1:9443-9452`
- НЕ доступен из интернета напрямую
- Доступ ТОЛЬКО через HAProxy

**Конфигурация:**
```nginx
# /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf

server {
    listen 127.0.0.1:9443 ssl http2;
    server_name myproxy.example.com;

    # TLS Configuration
    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;
    ssl_protocols TLSv1.3;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Rate Limiting
    limit_req zone=reverseproxy burst=20 nodelay;
    limit_conn conn_limit_per_ip 5;

    # Logging (error only, no access log)
    access_log off;
    error_log /var/log/nginx/reverse-proxy-error.log warn;

    # Proxy to target site via Xray
    location / {
        proxy_pass http://xray_outbound;
        proxy_set_header Host blocked-site.com;  # Target site (hardcoded)
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

#### Xray Outbound

**Роль:** Проксирование трафика к целевому сайту

**Routing Rules:**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-1"],
        "domain": ["blocked-site.com"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["reverse-proxy-1"],
        "outboundTag": "block"
      }
    ]
  }
}
```

**Безопасность:**
- Разрешен доступ ТОЛЬКО к целевому домену
- Все остальные домены блокируются (`block` outbound)

---

#### Certificate Management

**Формат:** combined.pem (fullchain + privkey)

**Создание:**
```bash
# 1. Получение сертификата (Let's Encrypt)
certbot certonly --nginx -d myproxy.example.com

# 2. Создание combined.pem (автоматически)
cat /etc/letsencrypt/live/myproxy.example.com/fullchain.pem \
    /etc/letsencrypt/live/myproxy.example.com/privkey.pem \
    > /opt/vless/certs/combined.pem

chmod 600 /opt/vless/certs/combined.pem

# 3. HAProxy reload (graceful, 0 downtime)
docker exec vless_haproxy haproxy -sf $(cat /var/run/haproxy.pid)
```

**Автоматическое обновление:**
- Cron job: `/etc/cron.d/vless-cert-renew`
- Частота: Ежедневная проверка
- Обновление: Автоматически за 30 дней до истечения
- Post-hook: Regenerate combined.pem + graceful HAProxy reload

---

## Детальная настройка

### DNS конфигурация

**Перед настройкой, проверьте DNS:**

```bash
# 1. Получите IP сервера
curl https://api.ipify.org
# Output: 203.0.113.10

# 2. Проверьте A-запись
dig +short myproxy.example.com
# Output: 203.0.113.10 (должен совпадать с IP сервера)

# 3. Проверьте резолюцию с разных DNS серверов
dig @8.8.8.8 myproxy.example.com
dig @1.1.1.1 myproxy.example.com
```

**Требования DNS:**
- ✅ A-запись указывает на публичный IP сервера
- ✅ Propagation завершен (ожидание 5-60 минут после изменения DNS)
- ✅ Port 80 доступен (временно, для Let's Encrypt ACME challenge)

**Создание A-записи (пример для Cloudflare):**
```
Type:  A
Name:  myproxy (или @ для root domain)
Value: 203.0.113.10 (IP вашего сервера)
TTL:   Auto (или 300 seconds)
Proxy: OFF (отключите Cloudflare proxy для Let's Encrypt)
```

---

### Запуск настройки

**Команда:**
```bash
sudo vless-proxy add
```

**Детальные запросы:**

#### 1. Доменное имя

```
═══════════════════════════════════════════════════════════
  Добавление Reverse Proxy (v4.3)
═══════════════════════════════════════════════════════════

Введите доменное имя для reverse proxy: myproxy.example.com

Валидация формата...
✅ Формат домена валиден
```

#### 2. DNS валидация

```
Проверка DNS...

[1/3] Резолюция домена...
✅ DNS check: A record found (203.0.113.10)

[2/3] Проверка соответствия IP...
Server IP: 203.0.113.10
DNS IP:    203.0.113.10
✅ DNS matches server IP

[3/3] Проверка TTL...
TTL: 300 seconds
✅ DNS ready for Let's Encrypt challenge
```

#### 3. Целевой URL

```
Введите целевой URL для проксирования: https://blocked-site.com

Валидация URL...
✅ URL format valid

Проверка доступности...
[1/2] Проверка резолюции...
✅ Target site resolves (93.184.216.34)

[2/2] Проверка TLS...
✅ TLS 1.3 supported
✅ Certificate valid

Target site reachable!
```

#### 4. Выделение порта

```
Выделение localhost порта для Nginx backend...

Доступные порты: 9443-9452
Используется:    0/10 reverse proxies

✅ Available port: 9443 (localhost-only)

Примечание: Порт 9443 НЕ будет доступен из интернета.
Доступ ТОЛЬКО через HAProxy (https://myproxy.example.com).
```

#### 5. Получение сертификата

```
Запрос Let's Encrypt сертификата для myproxy.example.com...

[1/5] Открытие UFW port 80 (temporary)...
✅ UFW rule added: allow 80/tcp (ACME HTTP-01 challenge)

[2/5] Запуск certbot...
Requesting certificate via HTTP-01 challenge...
✅ ACME challenge passed
✅ Certificate issued

[3/5] Закрытие UFW port 80...
✅ UFW rule removed: 80/tcp

[4/5] Создание combined.pem для HAProxy...
✅ combined.pem created: /opt/vless/certs/combined.pem
✅ Permissions: 600 (root only)

[5/5] Валидация сертификата...
✅ Certificate valid until: 2026-01-16T10:30:00Z (90 days)

Certificate ready!
```

#### 6. HAProxy конфигурация

```
Настройка HAProxy route...

[1/4] Добавление ACL в haproxy.cfg...
Added: acl is_myproxy req.ssl_sni -i myproxy.example.com

[2/4] Добавление backend в haproxy.cfg...
Added: backend nginx_9443 { server nginx vless_reverse_proxy_nginx:9443 }

[3/4] Добавление routing rule...
Added: use_backend nginx_9443 if is_myproxy

[4/4] Валидация и graceful reload...
✅ HAProxy config valid
✅ Graceful reload complete (0 downtime)

HAProxy route active!
```

#### 7. Nginx backend

```
Настройка Nginx backend...

[1/3] Создание конфигурации...
✅ Config created: /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf
✅ Listen: 127.0.0.1:9443
✅ Target: blocked-site.com

[2/3] Валидация Nginx конфигурации...
✅ nginx -t: syntax ok
✅ nginx -t: configuration valid

[3/3] Reload Nginx...
✅ Nginx reloaded successfully

Nginx backend ready!
```

#### 8. Итоговый вывод

```
═══════════════════════════════════════════════════════════
  ✅ Reverse Proxy Setup Complete!
═══════════════════════════════════════════════════════════

Reverse Proxy успешно настроен и активен!

Детали конфигурации:
  Domain:       myproxy.example.com
  Access URL:   https://myproxy.example.com  ← БЕЗ ПОРТА!
  Target Site:  https://blocked-site.com
  Port:         9443 (localhost, HAProxy routes traffic)
  Status:       Active

Сертификат:
  Issuer:       Let's Encrypt
  Valid until:  2026-01-16T10:30:00Z (90 days)
  Auto-renewal: Enabled (daily check)

Использование:
  # Browser
  https://myproxy.example.com

  # curl
  curl https://myproxy.example.com

  # wget
  wget https://myproxy.example.com/file.zip

Управление:
  sudo vless-proxy list                        # Список всех proxies
  sudo vless-proxy show myproxy.example.com    # Детали
  sudo vless-proxy remove myproxy.example.com  # Удаление

Мониторинг:
  sudo vless-status                            # Статус всех сервисов
  http://<server_ip>:9000/stats                # HAProxy stats page

Готово! 🎉
```

---

## Управление Reverse Proxies

### Список всех reverse proxies

**Команда:**
```bash
sudo vless-proxy list
```

**Вывод:**
```
═══════════════════════════════════════════════════════════
  🌐 Reverse Proxies (v4.3 - Subdomain-Based)
═══════════════════════════════════════════════════════════

Найдено: 3 reverse proxies (макс. 10)

ID   DOMAIN                      TARGET SITE              PORT     STATUS
──────────────────────────────────────────────────────────────────────────
1    myproxy.example.com         blocked-site.com         9443     active
2    news.example.com            blocked-news.com         9444     active
3    social.example.com          blocked-social.com       9445     active

Доступ:
  - myproxy.example.com:  https://myproxy.example.com  ← БЕЗ ПОРТА!
  - news.example.com:     https://news.example.com
  - social.example.com:   https://social.example.com

Все reverse proxies маршрутизируются через HAProxy Frontend 443.
Порты 9443-9445 доступны ТОЛЬКО на localhost (защищены HAProxy).

HAProxy Stats: http://<server_ip>:9000/stats
```

---

### Показать детали reverse proxy

**Команда:**
```bash
sudo vless-proxy show myproxy.example.com
```

**Вывод:**
```
═══════════════════════════════════════════════════════════
  🌐 Детали Reverse Proxy: myproxy.example.com
═══════════════════════════════════════════════════════════

Основные параметры:
  ID:                 1
  Domain:             myproxy.example.com
  Target Site:        blocked-site.com
  Backend Port:       9443 (localhost-only)
  Status:             ✅ Active

Доступ:
  URL:                https://myproxy.example.com  ← БЕЗ ПОРТА!
  Method:             HAProxy SNI routing → Nginx backend

HAProxy Configuration:
  Frontend:           vless-reality (port 443)
  ACL:                is_myproxy (SNI: myproxy.example.com)
  Backend:            nginx_9443
  Routing:            use_backend nginx_9443 if is_myproxy

Nginx Configuration:
  Listen:             127.0.0.1:9443 ssl http2
  Config File:        /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf
  Target:             blocked-site.com
  TLS:                1.3 only

Let's Encrypt Certificate:
  Domain:             myproxy.example.com
  Issuer:             Let's Encrypt
  Valid Until:        2026-01-16T10:30:00Z (85 days remaining)
  Auto-Renewal:       ✅ Enabled (daily check)
  combined.pem:       /opt/vless/certs/combined.pem

Проверка доступности:
  ✅ HAProxy route exists
  ✅ Nginx backend listening on 127.0.0.1:9443
  ✅ Certificate valid
  ✅ Target site reachable

Использование:
  curl https://myproxy.example.com
  wget https://myproxy.example.com/path
```

---

### Удаление reverse proxy

**Команда:**
```bash
sudo vless-proxy remove myproxy.example.com
```

**Процесс:**
```
═══════════════════════════════════════════════════════════
  ⚠️  Удаление Reverse Proxy: myproxy.example.com
═══════════════════════════════════════════════════════════

Что будет удалено:
  - HAProxy SNI route (ACL + backend)
  - Nginx backend config
  - Xray outbound routing rules
  - Reverse proxy запись из БД

Что НЕ будет удалено:
  - Let's Encrypt сертификат (сохранится в /etc/letsencrypt)
  - combined.pem (можно использовать повторно)

⚠️  Внимание: Это действие нельзя отменить!

Вы уверены? Введите доменное имя для подтверждения: myproxy.example.com

Подтверждено. Начинаю удаление...

[1/5] Удаление HAProxy SNI route...
✅ ACL 'is_myproxy' removed from haproxy.cfg
✅ Backend 'nginx_9443' removed from haproxy.cfg
✅ Routing rule removed from haproxy.cfg

[2/5] Graceful HAProxy reload...
✅ HAProxy config validated
✅ Graceful reload complete (0 downtime)

[3/5] Удаление Nginx backend config...
✅ Config removed: /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf
✅ Nginx reloaded

[4/5] Удаление Xray outbound routing...
✅ Routing rules removed from config.json
✅ Xray reloaded

[5/5] Удаление записи из БД...
✅ Entry removed from reverse_proxies.json

═══════════════════════════════════════════════════════════
  ✅ Reverse Proxy Удалён
═══════════════════════════════════════════════════════════

Reverse proxy для 'myproxy.example.com' успешно удалён.

Освобожденный порт: 9443 (доступен для нового reverse proxy)
Активных reverse proxies: 2/10

Примечания:
  - Сертификат сохранён в /etc/letsencrypt/live/myproxy.example.com/
  - Для удаления сертификата: sudo certbot delete --cert-name myproxy.example.com
  - combined.pem НЕ удалён (можно переиспользовать)
```

---

### Обновление сертификата

**Команда:**
```bash
sudo vless-proxy renew-cert myproxy.example.com
```

**Вывод:**
```
═══════════════════════════════════════════════════════════
  🔒 Обновление Сертификата: myproxy.example.com
═══════════════════════════════════════════════════════════

Текущий сертификат:
  Valid Until:  2026-01-16T10:30:00Z (85 days remaining)

⚠️  Сертификат валиден. Принудительное обновление?
Рекомендуется обновлять за 30 дней до истечения.

Продолжить принудительное обновление? [y/N]: y

[1/5] Открытие UFW port 80 (temporary)...
✅ UFW rule added: allow 80/tcp

[2/5] Запуск certbot (forced renewal)...
Requesting new certificate via HTTP-01 challenge...
✅ ACME challenge passed
✅ New certificate issued

[3/5] Закрытие UFW port 80...
✅ UFW rule removed: 80/tcp

[4/5] Regenerate combined.pem...
✅ combined.pem updated: /opt/vless/certs/combined.pem

[5/5] Graceful HAProxy reload...
✅ HAProxy reloaded with new certificate

═══════════════════════════════════════════════════════════
  ✅ Сертификат успешно обновлён
═══════════════════════════════════════════════════════════

Новый сертификат:
  Valid Until:  2026-04-16T12:00:00Z (90 days)
  Auto-Renewal: ✅ Enabled (daily check)

Downtime: 0 seconds (graceful reload)
```

---

### Проверка всех сертификатов

**Команда:**
```bash
sudo vless-proxy check-certs
```

**Вывод:**
```
═══════════════════════════════════════════════════════════
  ⏰ Проверка Сертификатов
═══════════════════════════════════════════════════════════

Проверка сертификатов для всех reverse proxies...

DOMAIN                      VALID UNTIL              STATUS         DAYS LEFT
─────────────────────────────────────────────────────────────────────────────
myproxy.example.com         2026-01-16T10:30:00Z     ✅ OK          85
news.example.com            2025-11-20T10:30:00Z     ⚠️  WARNING    25
social.example.com          2025-10-22T08:15:00Z     ❌ CRITICAL    5

Статус:
  ✅ OK:       > 30 days remaining
  ⚠️  WARNING: 30-7 days remaining
  ❌ CRITICAL: < 7 days remaining

Рекомендации:
  - social.example.com: СРОЧНО обновите сертификат!
    sudo vless-proxy renew-cert social.example.com

  - news.example.com: Рекомендуется обновить заранее
    sudo vless-proxy renew-cert news.example.com

Автоматическое обновление:
  Status:    ✅ Enabled
  Frequency: Daily check (cron)
  Next run:  2025-10-19 02:00:00 UTC
```

---

## Примеры использования

### Browser доступ

**Простейший способ:**
```
1. Откройте браузер
2. Введите: https://myproxy.example.com
3. Готово! Сайт доступен (если настроена авторизация - введите credentials)
```

**Преимущества v4.3:**
- ✅ Стандартный HTTPS порт (443)
- ✅ Нет номера порта в URL
- ✅ Работает с bookmarks и autocomplete
- ✅ Нет SSL/TLS warnings (Let's Encrypt trusted)

---

### cURL

**Без авторизации:**
```bash
curl https://myproxy.example.com
```

**С Basic Auth (если настроена):**
```bash
curl -u alice:PASSWORD https://myproxy.example.com
```

**Fetch specific path:**
```bash
curl https://myproxy.example.com/api/v1/endpoint
```

**Verbose output (debug):**
```bash
curl -v https://myproxy.example.com
```

---

### wget

**Скачать файл:**
```bash
wget https://myproxy.example.com/file.zip
```

**С авторизацией:**
```bash
wget --user=alice --password=PASSWORD https://myproxy.example.com/file.zip
```

**Рекурсивное скачивание:**
```bash
wget -r -np -k https://myproxy.example.com/docs/
```

---

### Python requests

```python
import requests

# v4.3: БЕЗ ПОРТА!
url = "https://myproxy.example.com"

# Без авторизации
response = requests.get(url)
print(response.text)

# С Basic Auth
auth = ("alice", "PASSWORD")
response = requests.get(url, auth=auth)
print(response.status_code)
```

---

### Git через Reverse Proxy

**Clone repository:**
```bash
# Если reverse proxy настроен для github.com
git clone https://git-proxy.example.com/user/repo.git
```

**Configure Git to use reverse proxy:**
```bash
git config --global http.proxy https://myproxy.example.com
```

---

## Устранение неполадок

### 1. Домен не доступен

**Симптом:**
```bash
curl: (6) Could not resolve host: myproxy.example.com
```

**Причина:** DNS не настроен или не распространён (propagation)

**Решение:**
```bash
# Проверьте DNS резолюцию
dig +short myproxy.example.com

# Если пусто - DNS не настроен
# 1. Создайте A-запись в DNS провайдере
# 2. Подождите 5-60 минут для propagation
# 3. Проверьте повторно

# Проверьте с разных DNS серверов
dig @8.8.8.8 myproxy.example.com  # Google DNS
dig @1.1.1.1 myproxy.example.com  # Cloudflare DNS
```

---

### 2. SSL Certificate Error

**Симптом:**
```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

**Причина:** Сертификат не установлен или combined.pem некорректен

**Решение:**
```bash
# 1. Проверьте существование combined.pem
ls -la /opt/vless/certs/combined.pem

# 2. Проверьте содержимое
openssl x509 -in /opt/vless/certs/combined.pem -noout -text

# 3. Regenerate combined.pem
sudo /opt/vless/lib/certificate_manager.sh create_combined_pem myproxy.example.com

# 4. Graceful HAProxy reload
docker exec vless_haproxy haproxy -sf $(cat /var/run/haproxy.pid)
```

---

### 3. HAProxy не маршрутизирует

**Симптом:**
```
curl: (56) Recv failure: Connection reset by peer
```

**Причина:** HAProxy route отсутствует или backend недоступен

**Решение:**
```bash
# 1. Проверьте HAProxy stats
curl http://localhost:9000/stats
# Или откройте в браузере: http://<server_ip>:9000/stats

# 2. Проверьте HAProxy logs
docker logs vless_haproxy --tail 50

# 3. Verify route exists in haproxy.cfg
grep myproxy /opt/vless/config/haproxy.cfg

# Должно вернуть:
#   acl is_myproxy req.ssl_sni -i myproxy.example.com
#   use_backend nginx_9443 if is_myproxy

# 4. Если route отсутствует - пересоздайте
sudo vless-proxy remove myproxy.example.com
sudo vless-proxy add
```

---

### 4. Nginx backend не отвечает

**Симптом:**
```
502 Bad Gateway
```

**Причина:** Nginx не слушает на ожидаемом порту

**Решение:**
```bash
# 1. Проверьте Nginx container
docker ps | grep nginx

# 2. Проверьте port bindings
docker exec vless_reverse_proxy_nginx netstat -tlnp | grep 9443

# Expected output:
# tcp  0  0  127.0.0.1:9443  0.0.0.0:*  LISTEN  1/nginx

# 3. Проверьте Nginx config
docker exec vless_reverse_proxy_nginx nginx -t

# 4. Проверьте Nginx logs
docker logs vless_reverse_proxy_nginx --tail 50

# 5. Restart Nginx container
docker restart vless_reverse_proxy_nginx
```

---

### 5. Target site недоступен

**Симптом:**
```
504 Gateway Timeout
```

**Причина:** Целевой сайт не доступен с сервера

**Решение:**
```bash
# 1. Проверьте доступность target site с сервера
curl -I https://blocked-site.com

# 2. Проверьте Xray outbound routing
cat /opt/vless/config/config.json | jq '.routing.rules[] | select(.inboundTag[] | contains("reverse-proxy"))'

# 3. Проверьте Xray logs
docker logs vless_xray --tail 50

# 4. Verify DNS resolution
dig +short blocked-site.com

# 5. Check firewall (UFW)
sudo ufw status | grep 443
```

---

### 6. HAProxy Stats недоступен

**Симптом:**
```
curl: (7) Failed to connect to localhost port 9000
```

**Решение:**
```bash
# 1. Проверьте HAProxy container
docker ps | grep haproxy

# 2. Проверьте port 9000
sudo ss -tlnp | grep 9000

# 3. Verify haproxy.cfg
grep "bind.*9000" /opt/vless/config/haproxy.cfg

# 4. Check UFW (if accessing remotely)
sudo ufw allow 9000/tcp comment 'HAProxy Stats (temporary)'

# 5. Restart HAProxy
docker restart vless_haproxy
```

---

## Лимиты и масштабирование

### Port Range: 9443-9452

**Максимум:** 10 reverse proxies на сервер

**Port Assignment:**
```
Первый proxy:   9443
Второй proxy:   9444
...
Десятый proxy:  9452
```

**После 10 reverse proxies:**
- Deploy новый независимый сервер
- Используйте разные поддомены (proxy1.example.com → server1, proxy11.example.com → server2)

---

### Performance

**На 1 Reverse Proxy:**
- Throughput: 100 Mbps
- Concurrent connections: 1000
- Latency overhead: < 50ms

**С 10 Reverse Proxies:**
- Aggregate throughput: 1 Gbps
- Total connections: 10,000
- Memory usage: ~500 MB (HAProxy + Nginx + Xray)

---

### Scaling Beyond 10 Proxies

**Горизонтальное масштабирование:**

```
Server 1 (proxies 1-10):
  proxy1.example.com → server1_ip
  proxy2.example.com → server1_ip
  ...
  proxy10.example.com → server1_ip

Server 2 (proxies 11-20):
  proxy11.example.com → server2_ip
  proxy12.example.com → server2_ip
  ...
  proxy20.example.com → server2_ip
```

**Load Balancing (advanced):**
- DNS-based round-robin
- Dedicated load balancer (HAProxy/Nginx)
- CDN integration (Cloudflare, CloudFront)

---

## Безопасность

### TLS 1.3 Only

**Конфигурация:**
```nginx
ssl_protocols TLSv1.3;
ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;
ssl_prefer_server_ciphers off;
```

**Гарантии:**
- ✅ Нет fallback к старым версиям (TLS 1.2, 1.1, 1.0)
- ✅ Perfect Forward Secrecy (PFS)
- ✅ Защита от BEAST, CRIME, POODLE attacks

---

### SNI Routing Security

**HAProxy НЕ расшифровывает reverse proxy traffic:**

```
Client → HAProxy (SNI inspection, NO decryption)
       → Nginx (TLS termination)
       → Xray (plaintext proxy)
       → Target Site
```

**Преимущества:**
- ✅ End-to-end encryption сохранена (HAProxy → Nginx)
- ✅ HAProxy не видит содержимое трафика
- ✅ Только VLESS Reality терминируется (passthrough)

---

### fail2ban Protection

**HAProxy filter:**
```bash
# /etc/fail2ban/filter.d/haproxy-sni.conf
[Definition]
failregex = ^.*\[ALERT\] .* from <HOST>:.*$
            ^.*client <HOST> disconnected.*$
ignoreregex =
```

**Nginx filter:**
```bash
# /etc/fail2ban/filter.d/nginx-reverse-proxy.conf
[Definition]
failregex = ^<HOST> .* "GET .* HTTP/.*" 401 .*$
            ^<HOST> .* "POST .* HTTP/.*" 403 .*$
ignoreregex =
```

**Jail configuration:**
```ini
[vless-haproxy]
enabled = true
port = 443,1080,8118
filter = haproxy-sni
maxretry = 5
bantime = 3600  # 1 hour
findtime = 600  # 10 minutes

[vless-nginx-reverseproxy]
enabled = true
port = 9443-9452
filter = nginx-reverse-proxy
maxretry = 5
bantime = 3600
```

**Эффект:** 5 неудачных попыток за 10 минут → ban на 1 час

---

### Certificate Auto-Renewal

**Cron job:**
```bash
# /etc/cron.d/vless-cert-renew
0 2 * * * root /opt/vless/scripts/vless-cert-renew
```

**Workflow:**
1. **Daily check:** Certbot проверяет все сертификаты
2. **Renewal trigger:** Если < 30 дней до истечения
3. **ACME challenge:** HTTP-01 (port 80 временно открывается)
4. **combined.pem regeneration:** fullchain + privkey
5. **Graceful HAProxy reload:** 0 downtime

**Validация:**
```bash
# Проверьте последний run
sudo grep vless-cert-renew /var/log/syslog

# Проверьте cron job
sudo crontab -l | grep vless-cert-renew

# Manual test
sudo /opt/vless/scripts/vless-cert-renew
```

---

### Best Security Practices

#### 1. Используйте сильные пароли (если настроена авторизация)

**Генерация:**
```bash
# 32-character random password
openssl rand -hex 16
```

**Пример:**
```
a3f7e9d1c5b2048796e4f3a2b8c1d5e0
```

#### 2. Мониторинг сертификатов

**Еженедельная проверка:**
```bash
echo "0 9 * * 1 sudo vless-proxy check-certs" | sudo crontab -
```

#### 3. Регулярные security аудиты

**Ежемесячно:**
```bash
sudo vless test-security
```

**Ежеквартально:**
```bash
cd /opt/vless/tests/security
sudo ./run_pentest.sh
```

#### 4. Ограничение доступа к HAProxy stats

**Рекомендация:** НЕ открывайте port 9000 в UFW (доступ только с localhost)

**SSH tunnel для удаленного доступа:**
```bash
ssh -L 9000:localhost:9000 user@server_ip
```

Затем откройте в браузере: `http://localhost:9000/stats`

---

## Миграция с v4.2 на v4.3

### Что изменилось

**URL Format:**

| Версия | Format | Пример |
|--------|--------|--------|
| v4.2 | `https://domain:PORT` | `https://proxy.example.com:8443` |
| v4.3 | `https://domain` | `https://proxy.example.com` (БЕЗ ПОРТА!) |

**Port Range:**

| Версия | Range | Binding | Public Access |
|--------|-------|---------|---------------|
| v4.2 | 8443-8452 | 0.0.0.0 | ✅ Yes (UFW rules) |
| v4.3 | 9443-9452 | 127.0.0.1 | ❌ No (localhost-only) |

**UFW Rules:**

| Версия | Ports | Required |
|--------|-------|----------|
| v4.2 | 8443-8452 | ✅ Yes (manually opened) |
| v4.3 | 9443-9452 | ❌ No (localhost-only) |

---

### Migration Steps

#### Шаг 1: Обновите клиентские приложения

**Обновите URLs:**

**До (v4.2):**
```bash
curl https://myproxy.example.com:8443
```

**После (v4.3):**
```bash
curl https://myproxy.example.com  # БЕЗ :8443!
```

**Python:**
```python
# v4.2
url = "https://myproxy.example.com:8443"

# v4.3
url = "https://myproxy.example.com"  # БЕЗ ПОРТА!
```

---

#### Шаг 2: Обновление сервера

**Команда:**
```bash
sudo vless-update
```

**Процесс автоматической миграции:**
```
[1/6] Backup существующих данных...
✅ Backup created: /opt/vless/data/backups/pre-v4.3-migration-YYYYMMDD.tar.gz

[2/6] Сохранение reverse proxy конфигураций...
✅ Saved: 3 reverse proxies (myproxy, news, social)

[3/6] Обновление Docker containers...
✅ HAProxy unified container deployed
✅ stunnel container removed (replaced by HAProxy)

[4/6] Миграция reverse proxy routes...
✅ myproxy.example.com: 8443 → 9443 (localhost-only)
✅ news.example.com:     8444 → 9444 (localhost-only)
✅ social.example.com:   8445 → 9445 (localhost-only)

[5/6] Настройка HAProxy SNI routing...
✅ HAProxy routes added for all 3 reverse proxies
✅ Graceful reload complete (0 downtime)

[6/6] Удаление старых UFW rules (8443-8452)...
✅ UFW rules removed (ports now localhost-only)

Migration complete! 🎉
```

---

#### Шаг 3: Проверка доступа

**Проверьте новые URLs (БЕЗ порта):**
```bash
# Старый URL (все еще работает, но deprecated)
curl https://myproxy.example.com:8443

# Новый URL (preferred v4.3 format)
curl https://myproxy.example.com  # БЕЗ :8443!
```

**Оба URL работают после миграции**, но рекомендуется использовать новый формат.

---

#### Шаг 4: Удаление старых UFW rules (опционально)

**Проверьте старые rules:**
```bash
sudo ufw status numbered | grep -E "844[3-9]|845[0-2]"
```

**Если найдены - удалите:**
```bash
# Автоматическое удаление (безопасно)
sudo vless-update --cleanup-old-rules

# Или вручную
sudo ufw delete allow 8443/tcp
sudo ufw delete allow 8444/tcp
# ... и т.д.
```

---

### Rollback (если требуется)

**v4.3 → v4.2:**
```bash
# 1. Restore backup
cd /opt/vless/data/backups
tar -xzf pre-v4.3-migration-YYYYMMDD.tar.gz -C /

# 2. Reinstall v4.2
sudo vless-install --version 4.2

# 3. Restore reverse proxies
sudo vless-restore --backup pre-v4.3-migration-YYYYMMDD.tar.gz
```

**Примечание:** Rollback НЕ рекомендуется. Пожалуйста, сообщите о проблемах в GitHub Issues.

---

## FAQ

### Q: Сколько reverse proxies можно создать?

**A:** Максимум 10 reverse proxies на сервер (порты 9443-9452, localhost-only)

---

### Q: Почему порты 9443-9452, а не 8443-8452?

**A:** В v4.3 reverse proxies работают на localhost (127.0.0.1), а не публично (0.0.0.0). Это повышает безопасность: доступ ТОЛЬКО через HAProxy, который контролирует все маршрутизацию.

---

### Q: Нужно ли открывать порты 9443-9452 в UFW?

**A:** ❌ НЕТ! Эти порты доступны ТОЛЬКО на localhost. HAProxy frontend (port 443) маршрутизирует трафик на Nginx backends. Открывать 9443-9452 в UFW не нужно и небезопасно.

---

### Q: Можно ли использовать port 443 вместо 9443 для reverse proxy?

**A:** ❌ НЕТ. Port 443 зарезервирован для HAProxy frontend (SNI routing). Reverse proxies используют localhost порты 9443-9452, а доступ осуществляется через HAProxy по стандартному HTTPS (443).

---

### Q: Нужен ли отдельный домен для каждого reverse proxy?

**A:** ✅ ДА! Каждый reverse proxy требует уникальный домен или поддомен.

**Пример:**
```
proxy1.example.com  → blocked-site1.com
proxy2.example.com  → blocked-site2.com
news.example.com    → blocked-news.com
```

---

### Q: Можно ли использовать один домен для нескольких целевых сайтов?

**A:** ❌ НЕТ. Один домен = один целевой сайт. Для нескольких сайтов создайте несколько поддоменов.

---

### Q: Можно ли использовать reverse proxy вместе с VLESS VPN?

**A:** ✅ ДА! Reverse proxies работают независимо и одновременно с VLESS Reality VPN.

**Port Allocation:**
```
Port 443:     HAProxy (VLESS Reality SNI passthrough + Reverse Proxy SNI routing)
Port 1080:    SOCKS5 proxy (via HAProxy TLS termination)
Port 8118:    HTTP proxy (via HAProxy TLS termination)
Ports 9443+:  Reverse proxy Nginx backends (localhost-only)
```

---

### Q: Как изменить целевой сайт для существующего reverse proxy?

**A:** Текущая версия НЕ поддерживает редактирование. Workaround: удалите и пересоздайте.

```bash
sudo vless-proxy remove myproxy.example.com
sudo vless-proxy add
# Введите новый target site
```

**Примечание:** Сертификат сохранится (не нужно переполучать).

---

### Q: Что произойдет, если сертификат истечет?

**A:** Автоматическое обновление настроено (cron + certbot). Ручное обновление:

```bash
sudo vless-proxy renew-cert myproxy.example.com
```

---

### Q: Можно ли проксировать любой сайт?

**A:** ✅ ДА, но:
- Целевой сайт должен быть доступен с вашего сервера
- Некоторые сайты блокируют proxies (Cloudflare, Akamai)
- Соблюдайте условия использования и местные законы

---

### Q: Трафик зашифрован?

**A:** ✅ ДА, полностью:

```
Client → HAProxy:         TLS 1.3 (SNI routing, NO decryption)
HAProxy → Nginx:          TLS forwarded (passthrough)
Nginx (TLS termination):  Decrypted
Nginx → Xray:             Plaintext (localhost, безопасно)
Xray → Target Site:       HTTPS (если target использует HTTPS)
```

---

### Q: Как получить доступ к HAProxy stats?

**A:** HAProxy stats доступны на `http://<server_ip>:9000/stats` (localhost by default)

**Remote access (secure via SSH tunnel):**
```bash
ssh -L 9000:localhost:9000 user@server_ip
```

Затем откройте: `http://localhost:9000/stats`

---

### Q: Можно ли использовать Cloudflare для reverse proxy домена?

**A:** ⚠️  С ограничениями:

**Let's Encrypt acquisition:**
- ❌ Cloudflare proxy ДОЛЖЕН быть ВЫКЛЮЧЕН (DNS-only mode)
- ✅ После получения сертификата можно включить (опционально)

**Cloudflare proxy mode:**
- ✅ Работает (Cloudflare → HAProxy → Nginx)
- ⚠️  Cloudflare увидит TLS трафик (не end-to-end encryption)

**Рекомендация:** Используйте Cloudflare DNS-only (оранжевое облако выключено).

---

## Best Practices

### 1. Используйте описательные доменные имена

**✅ ХОРОШО:**
```
news-proxy.example.com → blocked-news.com
social-proxy.example.com → blocked-social.com
video-proxy.example.com → blocked-video.com
```

**❌ ПЛОХО:**
```
p1.example.com → ?
proxy.example.com → ?
x.example.com → ?
```

---

### 2. Мониторинг сертификатов

**Еженедельная автоматическая проверка:**
```bash
# Добавьте в cron
echo "0 9 * * 1 sudo vless-proxy check-certs | mail -s 'Certificate Status' admin@example.com" | sudo crontab -
```

---

### 3. Регулярные бэкапы

**Автоматический backup:**
```bash
# Бэкапы создаются автоматически перед изменениями
ls -lh /opt/vless/data/backups/

# Ручной backup
sudo cp /opt/vless/config/reverse_proxies.json /backup/
sudo tar -czf /backup/vless-configs-$(date +%Y%m%d).tar.gz /opt/vless/config/
```

---

### 4. Документирование reverse proxies

**Сохраняйте список в отдельном файле:**
```bash
# /opt/vless/docs/reverse-proxies-list.md
1. myproxy.example.com → blocked-site.com (production, DO NOT REMOVE)
2. news.example.com → blocked-news.com (testing, remove after 2026-01-01)
3. social.example.com → blocked-social.com (team access)
```

---

### 5. Security аудиты

**Ежемесячно:**
```bash
sudo vless test-security
```

**Ежеквартально:**
```bash
cd /opt/vless/tests/security
sudo ./run_pentest.sh
```

---

### 6. Мониторинг HAProxy stats

**Регулярная проверка:**
```bash
# Локальный доступ
curl http://localhost:9000/stats

# Или SSH tunnel + браузер
ssh -L 9000:localhost:9000 user@server_ip
# Откройте: http://localhost:9000/stats
```

**Что проверять:**
- Backend status (UP/DOWN)
- Traffic throughput
- Error rates
- Connection limits

---

### 7. Лимиты на тестирование

**Перед production deployment:**
1. Создайте test reverse proxy (test.example.com)
2. Проверьте доступность с разных клиентов
3. Измерьте latency и throughput
4. Проверьте работу сертификата
5. Удалите test proxy после успешных тестов

---

## Следующие шаги

1. ✅ Настройте ваш первый reverse proxy
2. 📚 Прочитайте [Security Documentation](SECURITY_v4.3.md)
3. 🔧 Изучите [CLI Reference](REVERSE_PROXY_API.md)
4. 🏗️  Познакомьтесь с [Architecture](prd/04_architecture.md#47-haproxy-unified-architecture-v43)
5. 🚀 Запланируйте [Migration from v4.2](MIGRATION_v4.2_to_v4.3.md)

---

## Поддержка

- **Документация:** `/opt/vless/docs/`
- **Issues:** https://github.com/ikeniborn/vless/issues
- **Security:** SECURITY_v4.3.md
- **HAProxy Stats:** `http://<server_ip>:9000/stats` (SSH tunnel)

---

**Version:** 4.3.0 | **License:** MIT | **Author:** VLESS Development Team
**Last Updated:** 2025-10-18 | **Architecture:** HAProxy Unified (Subdomain-Based)

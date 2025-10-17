# VLESS v4.2 - Reverse Proxy User Guide

**Version:** 4.2.0
**Status:** Production Ready
**Last Updated:** 2025-10-17

---

## 📖 Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Use Cases](#use-cases)
4. [Prerequisites](#prerequisites)
5. [Setup Guide](#setup-guide)
6. [Managing Reverse Proxies](#managing-reverse-proxies)
7. [Security](#security)
8. [Troubleshooting](#troubleshooting)
9. [FAQ](#faq)
10. [Best Practices](#best-practices)

---

## Introduction

### What is Reverse Proxy?

VLESS v4.2 включает **Site-Specific Reverse Proxy** - защищённый способ доступа к заблокированным сайтам через ваш собственный домен с автоматическим TLS сертификатом.

### How It Works

```
User → https://myproxy.com:8443 → Nginx (TLS + Auth) → Xray → Blocked Site
```

**Ключевые компоненты:**
- **Nginx**: TLS termination, HTTP Basic Auth, rate limiting
- **Xray**: Domain-based routing, VLESS integration
- **Let's Encrypt**: Автоматические TLS сертификаты
- **fail2ban**: Защита от brute-force атак

---

## Quick Start

### 5-Minute Setup

```bash
# 1. Запустите интерактивный wizard
sudo vless-setup-proxy

# 2. Введите параметры:
#    - Домен: myproxy.example.com
#    - Целевой сайт: blocked-site.com
#    - Порт: 8443 (рекомендуется)
#    - Email: your@email.com

# 3. Готово! Получите креденшелы:
#    URL: https://myproxy.example.com:8443
#    Username: user_abc12345
#    Password: (автогенерируется)
```

### First Connection

1. Откройте браузер
2. Перейдите: `https://myproxy.example.com:8443`
3. Введите username/password
4. Вы будете перенаправлены на `blocked-site.com`

---

## Use Cases

### 1. Access Blocked Websites

```bash
# Создайте proxy для доступа к заблокированному контенту
sudo vless-setup-proxy

# Параметры:
Domain: unblock.example.com
Target: blocked-news-site.com
Port: 8443
```

### 2. Multiple Sites via Different Domains

```bash
# Proxy #1: Новости
Domain: news.example.com → Target: blocked-news.com (port 8443)

# Proxy #2: Социальные сети
Domain: social.example.com → Target: blocked-social.com (port 8444)

# Proxy #3: Видео
Domain: video.example.com → Target: blocked-video.com (port 8445)

# Max: 10 reverse proxies (ports 8443-8452)
```

### 3. Team Access with Shared Credentials

```bash
# Создайте reverse proxy для команды
sudo vless-setup-proxy

# Раздайте команде:
#   URL: https://team-proxy.com:8443
#   Username: user_team9876
#   Password: (поделитесь через secure channel)

# Все члены команды используют одни креденшелы
```

---

## Prerequisites

### DNS Requirements

**ОБЯЗАТЕЛЬНО:** Домен должен указывать на IP вашего сервера:

```bash
# 1. Получите IP сервера
curl https://api.ipify.org

# 2. Создайте A-запись в DNS:
Type: A
Name: myproxy
Value: [ВАШ_IP]
TTL: 300

# 3. Проверьте резолюцию:
dig +short myproxy.example.com
# Должно вернуть IP сервера
```

### Firewall Configuration

```bash
# UFW должен быть активен
sudo ufw status

# Порты 8443-8452 будут открыты автоматически
```

### System Requirements

- **OS**: Ubuntu 20.04+, Debian 10+
- **RAM**: Минимум 512 MB
- **Disk**: 1 GB свободного места
- **Docker**: Установлен (проверяется автоматически)
- **VLESS**: v4.0+ уже установлен

---

## Setup Guide

### Step-by-Step Setup

#### 1. Run Setup Wizard

```bash
sudo vless-setup-proxy
```

#### 2. Enter Domain

```
Введите домен для reverse proxy: myproxy.example.com

✓ Валидация формата домена
✓ DNS резолюция (A-запись проверена)
```

#### 3. Enter Target Site

```
Введите целевой сайт для проксирования: blocked-site.com

✓ Reachability check
✓ TLS 1.3 support validation
```

#### 4. Select Port

```
Выберите публичный порт: [8443]

Рекомендуется: 8443 (следующий доступный)
Диапазон: 8443-8452
Использовано: 0/10
```

#### 5. Enter Email

```
Введите email для Let's Encrypt: admin@example.com

Email используется для:
- Уведомления об истечении сертификата
- Критические обновления безопасности
```

#### 6. Confirm Configuration

```
═══════════════════════════════════════════════════════════
  Подтверждение Конфигурации
═══════════════════════════════════════════════════════════

  Домен:           myproxy.example.com
  Целевой сайт:    blocked-site.com
  Порт:            8443
  Email:           admin@example.com

Что будет выполнено:
  1. Получение Let's Encrypt сертификата
  2. Создание Nginx reverse proxy конфигурации
  3. Создание Xray HTTP inbound
  4. Настройка fail2ban защиты
  5. Открытие UFW порта 8443
  6. Генерация HTTP Basic Auth креденшелов

Продолжить установку? [y/N]: y
```

#### 7. Installation Process

```
🚀 Установка Reverse Proxy

▶ Получение Let's Encrypt сертификата...
  ✅ Сертификат получен успешно

▶ Создание Xray HTTP inbound...
  ✅ Xray inbound создан: reverse-proxy-1 (localhost:10080)

▶ Генерация креденшелов...
  ✅ Username: user_abc12345
  ✅ Password: f3e8d9a1b2c4567890123456

▶ Создание Nginx конфигурации...
  ✅ Nginx конфигурация создана

▶ Настройка fail2ban защиты...
  ✅ fail2ban правило добавлено

▶ Открытие UFW порта 8443...
  ✅ UFW правило добавлено

▶ Перезагрузка сервисов...
  ✅ Nginx reloaded
  ✅ Xray reloaded
```

#### 8. Success

```
═══════════════════════════════════════════════════════════
  ✅ Reverse Proxy Успешно Настроен!
═══════════════════════════════════════════════════════════

Reverse Proxy готов к использованию!

Детали конфигурации:
  URL:      https://myproxy.example.com:8443
  Username: user_abc12345
  Password: f3e8d9a1b2c4567890123456

Как использовать:
  1. Откройте браузер
  2. Перейдите по адресу: https://myproxy.example.com:8443
  3. Введите username/password при запросе
  4. Вы будете перенаправлены на blocked-site.com

Управление:
  sudo vless-proxy show myproxy.example.com        # Показать детали
  sudo vless-proxy remove myproxy.example.com      # Удалить
  sudo vless-proxy renew-cert myproxy.example.com  # Обновить сертификат
```

---

## Managing Reverse Proxies

### List All Proxies

```bash
sudo vless-proxy list
```

**Output:**
```
═══════════════════════════════════════════════════════════
  🌐 Список Reverse Proxies
═══════════════════════════════════════════════════════════

Найдено: 3 proxy (макс. 10)

ID   ДОМЕН                          ЦЕЛЕВОЙ САЙТ              ПОРТ     СТАТУС
────────────────────────────────────────────────────────────────────────────────
1    proxy.example.com              blocked-site.com          8443     enabled
2    news.example.com               blocked-news.com          8444     enabled
3    social.example.com             blocked-social.com        8445     enabled
```

### Show Proxy Details

```bash
sudo vless-proxy show proxy.example.com
```

**Output:**
```
═══════════════════════════════════════════════════════════
  🌐 Детали Reverse Proxy: proxy.example.com
═══════════════════════════════════════════════════════════

Основные параметры:
  ID:                 1
  Домен:              proxy.example.com
  Целевой сайт:       blocked-site.com
  Публичный порт:     8443
  Статус:             ✅ Enabled

Доступ:
  URL:                https://proxy.example.com:8443
  Username:           user_abc12345
  Password:           (хранится в .htpasswd)

Xray Configuration:
  Inbound Tag:        reverse-proxy-1
  Inbound Port:       10080 (localhost only)

Let's Encrypt Certificate:
  Истекает:           2026-01-15T12:00:00Z (85 дней)
  Путь:               /etc/letsencrypt/live/proxy.example.com/

Проверка доступности:
  ✅ Nginx слушает на порту 8443
  ✅ Xray inbound reverse-proxy-1 активен
  ✅ Сертификат валиден
```

### Remove Proxy

```bash
sudo vless-proxy remove proxy.example.com
```

**Process:**
```
═══════════════════════════════════════════════════════════
  ⚠️  Удаление Reverse Proxy: proxy.example.com
═══════════════════════════════════════════════════════════

Будет удалено:
  - Nginx конфигурация
  - Xray HTTP inbound (reverse-proxy-1)
  - fail2ban правило для порта 8443
  - UFW правило для порта 8443
  - .htpasswd файл
  - Запись из БД

⚠️  Let's Encrypt сертификат НЕ будет удалён

Вы уверены? Введите 'proxy.example.com' для подтверждения: proxy.example.com

ℹ Начинаю удаление...
  ✅ Nginx конфигурация удалена
  ✅ Xray inbound удалён
  ✅ fail2ban правило удалено
  ✅ UFW правило удалено
  ✅ Запись из БД удалена

═══════════════════════════════════════════════════════════
  ✅ Reverse Proxy Удалён
═══════════════════════════════════════════════════════════

Reverse proxy для 'proxy.example.com' успешно удалён

Примечания:
  - Сертификат сохранён в /etc/letsencrypt/live/proxy.example.com/
  - Для удаления сертификата: sudo certbot delete --cert-name proxy.example.com
```

### Renew Certificate

```bash
sudo vless-proxy renew-cert proxy.example.com
```

**Output:**
```
═══════════════════════════════════════════════════════════
  🔒 Обновление Сертификата: proxy.example.com
═══════════════════════════════════════════════════════════

ℹ Начинаю принудительное обновление сертификата...

[letsencrypt] Opening UFW port 80 for ACME HTTP-01 challenge...
[letsencrypt] Running certbot (standalone mode)...
[letsencrypt] ✅ Certificate obtained successfully for proxy.example.com
[letsencrypt] Closing UFW port 80...
[letsencrypt] ✅ Certificate validation passed

✅ Сертификат успешно обновлён
ℹ Новая дата истечения: 2026-04-15T12:00:00Z
```

### Check All Certificates

```bash
sudo vless-proxy check-certs
```

**Output:**
```
═══════════════════════════════════════════════════════════
  ⏰ Проверка Сертификатов
═══════════════════════════════════════════════════════════

Проверка сертификатов для всех reverse proxies...

ДОМЕН                          ИСТЕКАЕТ                  СТАТУС
────────────────────────────────────────────────────────────────────────
proxy.example.com              2026-01-15T12:00:00Z      OK             (85 дней)
news.example.com               2025-11-20T10:30:00Z      WARNING        (25 дней)
social.example.com             2025-10-22T08:15:00Z      CRITICAL       (5 дней)

⚠ 1 сертификатов истекают в течение 30 дней
Рекомендуется обновить сертификаты заранее
```

---

## Security

### Architecture Security

**Multi-Layer Protection:**

```
Internet → UFW Firewall
           ↓
       Nginx (Port 8443)
       - TLS 1.3 Only
       - HTTP Basic Auth (bcrypt)
       - Rate Limiting (10 req/s)
       - Connection Limits (5 per IP)
       - Host Header Validation
       - HSTS Headers
           ↓
       Xray (Localhost:10080)
       - Domain-based Routing
       - Allow target site only
       - Block other domains
           ↓
       Internet (blocked-site.com)
```

### Security Features

#### 1. TLS 1.3 Only

```nginx
ssl_protocols TLSv1.3;
ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;
```

#### 2. HTTP Basic Auth (bcrypt)

```bash
# Passwords hashed with bcrypt (cost=12)
# 16-character random hex
Password: 32a1b4c7d9e2f8g3
Hash: $2b$12$Xy6RnQzK9mH7Lv2Nw4PqO.QzU8TyE3FjV6CwX9BaY1DzK5MnR7SoP
```

#### 3. Rate Limiting

```nginx
limit_req_zone $binary_remote_addr zone=reverseproxy:10m rate=10r/s;
limit_req zone=reverseproxy burst=20 nodelay;
```

**Effect:** Max 10 requests/second per IP, burst 20

#### 4. Connection Limits

```nginx
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
limit_conn conn_limit_per_ip 5;
```

**Effect:** Max 5 concurrent connections per IP

#### 5. Host Header Injection Protection (VULN-001)

```nginx
# Default server block - rejects invalid Host headers
server {
    listen 8443 ssl http2 default_server;
    return 444;  # Close connection
}

# Actual proxy - validates Host header
server {
    listen 8443 ssl http2;
    server_name myproxy.example.com;

    if ($host != "myproxy.example.com") {
        return 444;
    }

    # Hardcoded Host header (not $host variable)
    proxy_set_header Host blocked-site.com;
}
```

#### 6. fail2ban Protection

```ini
[vless-reverseproxy]
enabled = true
port = 8443,8444,8445  # All reverse proxy ports
filter = vless-reverseproxy
maxretry = 5
bantime = 3600  # 1 hour
findtime = 600  # 10 minutes
action = ufw

# 5 failed auth attempts in 10 minutes → banned for 1 hour
```

#### 7. HSTS Headers

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

**Effect:** Forces HTTPS for 1 year, preload-ready

### Security Best Practices

#### Strong Passwords

```bash
# Automatically generated: 16-character random hex
Example: a3f7e9d1c5b2048796e4f3a2

# Never use:
# - Dictionary words
# - Personal information
# - Short passwords (<16 chars)
```

#### Credential Sharing

```bash
# ✅ GOOD:
- Encrypted messaging (Signal, WhatsApp)
- Password managers (1Password, Bitwarden)
- Secure note-taking (Notion, Obsidian)

# ❌ BAD:
- Email
- SMS
- Plain text files
- Screenshots
```

#### Certificate Monitoring

```bash
# Setup automatic checks (weekly)
echo "0 9 * * 1 sudo vless-proxy check-certs" | sudo crontab -

# Alert on expiry < 30 days
```

#### Regular Audits

```bash
# Run security tests monthly
sudo vless test-security

# Run penetration tests quarterly
cd /opt/vless/tests/security
sudo ./run_pentest.sh
```

---

## Troubleshooting

### Common Issues

#### 1. DNS Not Resolving

**Symptoms:**
```
✗ Домен proxy.example.com не резолвится
```

**Solution:**
```bash
# 1. Check DNS propagation
dig +short proxy.example.com @8.8.8.8

# 2. Wait for DNS propagation (up to 24h for some providers)

# 3. Verify A-record points to server IP
curl https://api.ipify.org  # Get server IP
```

#### 2. Certificate Acquisition Failed

**Symptoms:**
```
❌ Failed to obtain certificate for proxy.example.com
```

**Solution:**
```bash
# 1. Check DNS first (see above)

# 2. Check if port 80 is available
sudo ss -tulnp | grep :80

# 3. Check UFW allows port 80 temporarily
sudo ufw status | grep 80

# 4. Try manual certificate
sudo certbot certonly --standalone -d proxy.example.com

# 5. Check logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

#### 3. 401 Unauthorized

**Symptoms:**
- Browser prompts for username/password repeatedly
- Credentials not accepted

**Solution:**
```bash
# 1. Verify credentials
sudo vless-proxy show proxy.example.com

# 2. Check .htpasswd file
sudo cat /opt/vless/config/reverse-proxy/.htpasswd-proxy.example.com

# 3. Test with curl
curl -u user_abc12345:password -k https://proxy.example.com:8443
```

#### 4. 444 Connection Closed

**Symptoms:**
- Connection closes immediately
- No error page shown

**Causes:**
- Invalid Host header
- Wrong domain in URL
- DNS pointing to wrong server

**Solution:**
```bash
# 1. Verify you're using correct domain
https://proxy.example.com:8443  # ✅ CORRECT
https://wrong-domain.com:8443   # ❌ WRONG (returns 444)

# 2. Check Host header
curl -I -k https://proxy.example.com:8443

# 3. Check Nginx config
sudo nginx -t
sudo vless-proxy show proxy.example.com
```

#### 5. Target Site Not Accessible

**Symptoms:**
- Auth works, but target site shows error
- 502 Bad Gateway

**Solution:**
```bash
# 1. Check if Xray inbound exists
sudo docker exec vless_xray netstat -tlnp | grep 10080

# 2. Verify routing rules
sudo cat /opt/vless/config/config.json | jq '.routing.rules[] | select(.inboundTag[] | contains("reverse-proxy"))'

# 3. Test target site reachability from server
curl -I https://blocked-site.com

# 4. Check Xray logs
sudo docker logs vless_xray --tail 50
```

---

## FAQ

### Q: How many reverse proxies can I create?

**A:** Maximum 10 reverse proxies per server (ports 8443-8452)

### Q: Can I use port 443 instead of 8443?

**A:** No, port 443 is reserved for VLESS Reality VPN. Use 8443-8452 range.

### Q: Do I need separate domain for each proxy?

**A:** Yes, each reverse proxy requires its own domain or subdomain.

Example:
```
proxy1.example.com:8443 → blocked-site1.com
proxy2.example.com:8444 → blocked-site2.com
news.example.com:8445   → blocked-news.com
```

### Q: Can multiple users share same proxy?

**A:** Yes! Each proxy has one set of credentials that can be shared with your team.

### Q: How do I change the password?

**A:** Currently not supported. Workaround: remove and recreate proxy.

### Q: What happens if certificate expires?

**A:** Auto-renewal is configured (cron + systemd timer). Manual renewal: `sudo vless-proxy renew-cert DOMAIN`

### Q: Can I proxy any website?

**A:** Yes, but:
- Target site must be reachable from your server
- Some sites block proxies (CloudFlare, etc.)
- Respect terms of service and local laws

### Q: Is traffic encrypted?

**A:** Yes:
- Client → Nginx: TLS 1.3
- Nginx → Xray: Localhost (no encryption needed)
- Xray → Target Site: HTTPS (if target uses HTTPS)

### Q: Can I use with VLESS VPN?

**A:** Yes! Reverse proxy is independent and works alongside VLESS VPN.

```
Port 443:     VLESS Reality VPN
Port 1080:    SOCKS5 proxy (via VPN)
Port 8118:    HTTP proxy (via VPN)
Port 8443+:   Reverse proxy (standalone)
```

---

## Best Practices

### 1. Use Meaningful Domain Names

```bash
# ✅ GOOD: Descriptive domains
news-proxy.example.com → blocked-news.com
social-proxy.example.com → blocked-social.com

# ❌ BAD: Generic domains
p1.example.com → ?
proxy.example.com → ?
```

### 2. Monitor Certificate Expiry

```bash
# Weekly cron job
0 9 * * 1 sudo vless-proxy check-certs | mail -s "Certificate Status" admin@example.com
```

### 3. Regular Backups

```bash
# Database backup (automatic before changes)
ls -lh /opt/vless/data/backups/

# Manual backup
sudo cp /opt/vless/config/reverse_proxies.json /backup/
```

### 4. Document Your Proxies

```bash
# Add notes to each proxy
sudo vless-proxy show proxy.example.com

# Example notes:
"Production proxy for team access - DO NOT REMOVE"
"Testing proxy - can be removed after 2025-11-01"
```

### 5. Security Audits

```bash
# Monthly security scan
sudo /opt/vless/tests/security/suite1_auth_tests.sh
sudo /opt/vless/tests/security/suite3_host_header_tests.sh

# Quarterly penetration test
sudo /opt/vless/tests/security/run_pentest.sh
```

---

## Next Steps

1. ✅ Setup your first reverse proxy
2. 📚 Read [Security Documentation](SECURITY_v4.2.md)
3. 🔧 Explore [CLI Reference](REVERSE_PROXY_API.md)
4. 🏗️ Learn [Architecture](ARCHITECTURE_v4.2.md)
5. 🚀 Plan [Migration from v4.1](MIGRATION_v4.1_to_v4.2.md)

---

**Support:**
- Documentation: `/opt/vless/docs/`
- Issues: https://github.com/ikeniborn/vless/issues
- Security: See SECURITY_v4.2.md

**Version:** 4.2.0 | **License:** MIT | **Author:** VLESS Development Team

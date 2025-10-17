# VLESS v4.2 - Reverse Proxy CLI Reference

**Version:** 4.2.0
**Last Updated:** 2025-10-17

---

## CLI Commands Overview

| Command | Description | Example |
|---------|-------------|---------|
| `vless-setup-proxy` | Interactive wizard for new proxy | `sudo vless-setup-proxy` |
| `vless-proxy add` | Alias to vless-setup-proxy | `sudo vless-proxy add` |
| `vless-proxy list` | List all reverse proxies | `sudo vless-proxy list` |
| `vless-proxy show <domain>` | Show proxy details | `sudo vless-proxy show proxy.com` |
| `vless-proxy remove <domain>` | Remove proxy | `sudo vless-proxy remove proxy.com` |
| `vless-proxy renew-cert <domain>` | Renew Let's Encrypt cert | `sudo vless-proxy renew-cert proxy.com` |
| `vless-proxy check-certs` | Check all certificate expiry | `sudo vless-proxy check-certs` |

---

## vless-setup-proxy

**Interactive wizard for creating new reverse proxy**

### Usage
```bash
sudo vless-setup-proxy
```

### Interactive Prompts
1. Domain (DNS validation required)
2. Target site (reachability + TLS 1.3 check)
3. Port (8443-8452, auto-suggestion)
4. Let's Encrypt email
5. Confirmation

### What It Does
- Obtains Let's Encrypt certificate
- Creates Nginx reverse proxy config
- Creates Xray HTTP inbound
- Generates HTTP Basic Auth credentials
- Sets up fail2ban protection
- Opens UFW firewall port

### Example Output
```
✅ Reverse Proxy Успешно Настроен!

URL:      https://proxy.example.com:8443
Username: user_abc12345
Password: a3f7e9d1c5b2048796
```

---

## vless-proxy list

**List all configured reverse proxies**

### Usage
```bash
sudo vless-proxy list
```

### Output Format
```
ID   ДОМЕН                    ЦЕЛЕВОЙ САЙТ         ПОРТ     СТАТУС
────────────────────────────────────────────────────────────────────
1    proxy.example.com        blocked-site.com     8443     enabled
2    news.example.com         blocked-news.com     8444     enabled
```

### Exit Codes
- `0`: Success
- `1`: Error

---

## vless-proxy show

**Show detailed information about reverse proxy**

### Usage
```bash
sudo vless-proxy show <domain>
```

### Parameters
- `<domain>`: Reverse proxy domain name (required)

### Example
```bash
sudo vless-proxy show proxy.example.com
```

### Output
```
Основные параметры:
  ID:                 1
  Домен:              proxy.example.com
  Целевой сайт:       blocked-site.com
  Публичный порт:     8443
  Статус:             ✅ Enabled

Доступ:
  URL:                https://proxy.example.com:8443
  Username:           user_abc12345

Xray Configuration:
  Inbound Tag:        reverse-proxy-1
  Inbound Port:       10080 (localhost only)

Let's Encrypt Certificate:
  Истекает:           2026-01-15T12:00:00Z (85 дней)

Проверка доступности:
  ✅ Nginx слушает на порту 8443
  ✅ Xray inbound reverse-proxy-1 активен
  ✅ Сертификат валиден
```

---

## vless-proxy remove

**Remove reverse proxy configuration**

### Usage
```bash
sudo vless-proxy remove <domain>
```

### Parameters
- `<domain>`: Domain to remove (required)

### What It Removes
- ✅ Nginx configuration
- ✅ Xray HTTP inbound
- ✅ fail2ban rule
- ✅ UFW firewall rule
- ✅ .htpasswd file
- ✅ Database entry
- ❌ Let's Encrypt certificate (preserved)

### Confirmation Required
```
Вы уверены? Введите 'proxy.example.com' для подтверждения:
```

### Example
```bash
sudo vless-proxy remove old-proxy.example.com
```

---

## vless-proxy renew-cert

**Manually renew Let's Encrypt certificate**

### Usage
```bash
sudo vless-proxy renew-cert <domain>
```

### Parameters
- `<domain>`: Domain to renew certificate for (required)

### What It Does
- Temporarily opens UFW port 80
- Runs `certbot renew --force-renewal`
- Closes UFW port 80
- Updates database with new expiry date
- Reloads Nginx

### Example
```bash
sudo vless-proxy renew-cert proxy.example.com
```

### Output
```
✅ Сертификат успешно обновлён
ℹ Новая дата истечения: 2026-04-15T12:00:00Z
```

---

## vless-proxy check-certs

**Check certificate expiry for all reverse proxies**

### Usage
```bash
sudo vless-proxy check-certs
```

### Output
```
ДОМЕН                    ИСТЕКАЕТ                  СТАТУС
──────────────────────────────────────────────────────────────
proxy.example.com        2026-01-15T12:00:00Z      OK (85 дней)
news.example.com         2025-11-20T10:30:00Z      WARNING (25 дней)
social.example.com       2025-10-22T08:15:00Z      CRITICAL (5 дней)
```

### Status Levels
- **OK**: > 30 days left
- **WARNING**: 7-30 days left
- **CRITICAL**: < 7 days left or expired

---

## Library Functions (Advanced)

### nginx_config_generator.sh

```bash
source /opt/vless/lib/nginx_config_generator.sh

# Generate secure Nginx config
generate_reverseproxy_nginx_config \
    "proxy.example.com" \
    "blocked-site.com" \
    8443 \
    10080 \
    "user_abc12345" \
    '$2b$12$hash...'
```

### xray_http_inbound.sh

```bash
source /opt/vless/lib/xray_http_inbound.sh

# Add HTTP inbound
add_reverseproxy_inbound "proxy.com" "blocked-site.com"
# Output: "1 10080" (inbound_id port)

# List inbounds
list_reverseproxy_inbounds

# Remove inbound
remove_reverseproxy_inbound "reverse-proxy-1"
```

### letsencrypt_integration.sh

```bash
source /opt/vless/lib/letsencrypt_integration.sh

# Obtain certificate
obtain_certificate "proxy.example.com" "admin@example.com"

# Renew certificate
renew_certificate "proxy.example.com"

# Validate certificate
validate_certificate "proxy.example.com"
```

### fail2ban_config.sh

```bash
source /opt/vless/lib/fail2ban_config.sh

# Setup fail2ban
setup_reverseproxy_fail2ban "8443,8444,8445"

# Add port dynamically
add_port_to_jail 8446
reload_fail2ban
```

### reverseproxy_db.sh

```bash
source /opt/vless/lib/reverseproxy_db.sh

# Initialize database
init_database

# Add proxy
add_proxy '{...json...}'

# Get proxy
get_proxy "proxy.example.com"

# List all
list_proxies

# Remove proxy
remove_proxy "proxy.example.com"
```

---

## Environment Variables

```bash
# Test domain for security tests
export TEST_DOMAIN=proxy.example.com
export TEST_PORT=8443
export TEST_USERNAME=user_test1234
export TEST_PASSWORD=testpassword123

# Installation path (DO NOT CHANGE)
export INSTALL_PATH=/opt/vless
```

---

## Exit Codes

All commands follow standard exit code conventions:

- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: Permission denied (not running as root)

---

## Logs

### Nginx Logs
```bash
# Error log
sudo tail -f /opt/vless/logs/nginx/reverse-proxy-error.log

# Access log
sudo tail -f /opt/vless/logs/nginx/reverse-proxy-access.log
```

### Xray Logs
```bash
# Container logs
sudo docker logs -f vless_xray

# Access log
sudo tail -f /opt/vless/logs/xray/access.log
```

### fail2ban Logs
```bash
# fail2ban log
sudo tail -f /var/log/fail2ban.log

# Check banned IPs
sudo fail2ban-client status vless-reverseproxy
```

---

**Next:** [Security Documentation](SECURITY_v4.2.md) | [User Guide](REVERSE_PROXY_GUIDE.md)

# VLESS Reverse Proxy CLI Reference (v4.3)

**Version:** 4.3.0 (HAProxy Unified Architecture)
**Last Updated:** 2025-10-18
**Architecture:** Subdomain-Based Access (https://domain, NO port!)
**Status:** Production Ready

---

## Обзор

Система reverse proxy в v4.3 использует **HAProxy SNI routing** для доступа к заблокированным сайтам через subdomain **БЕЗ указания порта в URL**.

### Ключевые изменения v4.3

- ✅ **Subdomain-based access:** `https://domain` (NO port number!)
- ✅ **HAProxy SNI routing:** Один порт 443 для всех reverse proxy доменов
- ✅ **Localhost-only backends:** Nginx слушает на 9443-9452 (НЕ публично)
- ✅ **Динамическое управление ACL:** Добавление/удаление маршрутов без полного перезапуска
- ✅ **Упрощённая архитектура:** Один HAProxy вместо stunnel + HAProxy

### Архитектура (v4.3)

```
Client → HAProxy Frontend 443 (SNI routing)
       ↓
       SNI: myproxy.example.com
       ↓
       HAProxy Backend → Nginx:9443 (localhost)
       ↓
       Nginx Reverse Proxy → Xray Outbound
       ↓
       Xray Routing → Target Site (https://blocked-site.com)
```

**Важно:**
- Public access: **ТОЛЬКО через HAProxy port 443**
- Nginx backends: **НЕ exposed** (localhost:9443-9452)
- URL format: `https://domain` (**NO** `:9443`!)

---

## CLI Commands Reference

### Таблица команд

| Command | Description | Example |
|---------|-------------|---------|
| `vless-proxy add` | Интерактивная настройка reverse proxy (subdomain-based) | `sudo vless-proxy add` |
| `vless-proxy list` | Показать все настроенные reverse proxies | `sudo vless-proxy list` |
| `vless-proxy show <domain>` | Показать детали конкретного reverse proxy | `sudo vless-proxy show myproxy.example.com` |
| `vless-proxy remove <domain>` | Удалить reverse proxy конфигурацию | `sudo vless-proxy remove myproxy.example.com` |
| `vless-status` | Показать статус системы (включая HAProxy info) | `sudo vless-status` |

**Удалённые команды (v4.2 → v4.3):**
- ❌ `vless-setup-proxy` (deprecated, теперь `vless-proxy add`)
- ❌ `vless add-ufw-port`, `vless remove-ufw-port` (НЕ нужны в v4.3, все через HAProxy port 443)

---

## Детальное описание команд

### `vless-proxy add` - Добавить Reverse Proxy (Interactive)

**Назначение:** Интерактивная настройка нового subdomain-based reverse proxy

**Использование:**
```bash
sudo vless-proxy add
```

**Интерактивные запросы:**

1. **Domain name:** Введите subdomain (например, myproxy.example.com)
   - Валидация DNS: `dig +short myproxy.example.com` должен вернуть IP сервера

2. **Target URL:** Введите сайт для проксирования (например, https://blocked-site.com)
   - Валидация доступности: `curl -I https://blocked-site.com`

3. **DNS validation:** Система проверяет, что DNS A record указывает на сервер

4. **Certificate:** Запрашивает Let's Encrypt certificate (HTTP-01 challenge)
   - Port 80 временно открывается для ACME challenge
   - После получения сертификата port 80 закрывается

5. **HAProxy route:** Добавляет SNI routing в haproxy.cfg (dynamic ACL)

6. **Nginx backend:** Создаёт localhost:9443-9452 reverse proxy config

7. **Xray outbound:** Настраивает Xray routing для target site

**Output:**
```
✅ Reverse Proxy Configuration Complete

Domain:       myproxy.example.com
Access URL:   https://myproxy.example.com  ← NO PORT!
Target Site:  https://blocked-site.com
Port:         9443 (localhost-only, HAProxy routes traffic)
Status:       Active

HAProxy Frontend: 443 (SNI routing)
Nginx Backend:    127.0.0.1:9443
Certificate:      /etc/letsencrypt/live/myproxy.example.com/fullchain.pem

Credentials:
  Username:       user_a3f9c2e1
  Password:       4fd0a3936e5a1e28b7c9d0f1e2a3b4c5

Usage:
  curl -u user_a3f9c2e1:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5 https://myproxy.example.com

  Browser:
    1. Open https://myproxy.example.com
    2. Enter credentials when prompted
    3. Access blocked-site.com through your domain
```

**Требования:**
- Domain DNS A record указывает на server IP
- Port 80 временно доступен для Let's Encrypt challenge
- Доступный порт в диапазоне 9443-9452
- HAProxy reload permission

**Exit Codes:**
- `0`: Success
- `1`: General error
- `2`: Invalid arguments (DNS, target URL validation failed)
- `3`: Permission denied (not running as root)

---

### `vless-proxy list` - List All Reverse Proxies

**Назначение:** Показать все настроенные reverse proxies

**Использование:**
```bash
sudo vless-proxy list
```

**Output:**
```
Reverse Proxies (v4.3 - Subdomain-Based):

1. myproxy.example.com
   URL:        https://myproxy.example.com  ← NO PORT!
   Target:     https://blocked-site.com
   Port:       9443 (localhost)
   Status:     Active
   Certificate: Valid (expires: 2026-01-15)
   Username:   user_a3f9c2e1

2. another.example.com
   URL:        https://another.example.com  ← NO PORT!
   Target:     https://another-site.com
   Port:       9444 (localhost)
   Status:     Active
   Certificate: Valid (expires: 2026-02-20)
   Username:   user_b2c1d3e4

Total: 2/10 reverse proxies
HAProxy Frontend: 443 (SNI routing to all)
Available Ports: 9445-9452 (8 remaining)
```

**Exit Codes:**
- `0`: Success
- `1`: Error reading configuration

---

### `vless-proxy show <domain>` - Show Reverse Proxy Details

**Назначение:** Показать детали конкретного reverse proxy

**Использование:**
```bash
sudo vless-proxy show myproxy.example.com
```

**Параметры:**
- `<domain>`: Reverse proxy domain name (обязательный)

**Output:**
```
Reverse Proxy Details: myproxy.example.com

Access Information:
  URL:                https://myproxy.example.com  ← NO PORT!
  Target Site:        https://blocked-site.com
  Status:             ✅ Active

Credentials:
  Username:           user_a3f9c2e1
  Password:           4fd0a3936e5a1e28b7c9d0f1e2a3b4c5

Architecture (v4.3):
  HAProxy Frontend:   443 (SNI routing)
  HAProxy ACL:        acl is_myproxy req.ssl_sni -i myproxy.example.com
  HAProxy Backend:    nginx_myproxy (vless_reverse_proxy_nginx:9443)
  Nginx Backend Port: 9443 (localhost-only, NOT exposed)
  Xray Inbound:       reverse-proxy-1 (localhost:10080)

Let's Encrypt Certificate:
  Path:               /etc/letsencrypt/live/myproxy.example.com/
  Expires:            2026-01-15T12:00:00Z (85 days remaining)
  Auto-Renewal:       Enabled (certbot cron)

Security:
  HTTP Basic Auth:    Enabled (bcrypt hashed)
  fail2ban:           Active (5 failures → 1 hour ban)
  Rate Limiting:      10 req/s per IP
  Connection Limit:   5 concurrent per IP

Health Checks:
  ✅ HAProxy routing active
  ✅ Nginx backend listening on 127.0.0.1:9443
  ✅ Xray inbound reverse-proxy-1 active
  ✅ Certificate valid
  ✅ DNS resolves to server IP

Usage Examples:
  curl -u user_a3f9c2e1:PASSWORD https://myproxy.example.com

  Browser:
    https://myproxy.example.com (NO :9443!)
```

**Exit Codes:**
- `0`: Success
- `1`: Domain not found
- `2`: Invalid domain format

---

### `vless-proxy remove <domain>` - Remove Reverse Proxy

**Назначение:** Удалить reverse proxy конфигурацию

**Использование:**
```bash
sudo vless-proxy remove myproxy.example.com
```

**Параметры:**
- `<domain>`: Domain для удаления (обязательный)

**Подтверждение:**
```
⚠️  WARNING: This will remove reverse proxy configuration

Domain:       myproxy.example.com
Target Site:  https://blocked-site.com
Port:         9443 (will be freed for reuse)

The following will be removed:
  - HAProxy SNI route (dynamic ACL)
  - Nginx backend config (9443)
  - Xray outbound routing
  - Database entry

The following will be KEPT:
  - Let's Encrypt certificate (manual deletion required)

Type 'myproxy.example.com' to confirm:
```

**Actions performed:**
1. Remove HAProxy SNI route (dynamic ACL update via `sed`)
2. Remove Nginx backend config (port 9443 freed for reuse)
3. Remove Xray outbound routing
4. Update `reverse-proxies.json` database
5. Graceful HAProxy reload (`haproxy -sf`)

**Output:**
```
✅ Reverse Proxy Removed

Domain:       myproxy.example.com
Port:         9443 (now available for reuse)
HAProxy:      Route removed, graceful reload complete

Note: Certificate kept at /etc/letsencrypt/live/myproxy.example.com/
      Delete manually if needed:
        sudo certbot delete --cert-name myproxy.example.com
```

**Важно:**
- ❌ **NO UFW rule removal** (все через HAProxy frontend 443)
- ✅ Port 9443 освобождается для повторного использования
- ✅ Graceful HAProxy reload (zero downtime)
- ✅ Certificate НЕ удаляется автоматически (можно переиспользовать)

**Exit Codes:**
- `0`: Success
- `1`: Domain not found
- `2`: Removal failed (validation error, rollback performed)

---

### `vless-status` - System Status

**Назначение:** Показать статус системы (включая HAProxy и reverse proxies)

**Использование:**
```bash
sudo vless-status
```

**Output (relevant section):**
```
============================================================
           VLESS Reality VPN Server Status (v4.3)
============================================================

HAProxy (Unified TLS Termination & Routing):
  Container:        vless_haproxy (RUNNING)
  Frontends:
    - vless-reality:  443 (SNI routing, passthrough)
    - socks5-tls:     1080 (TLS termination → Xray:10800)
    - http-tls:       8118 (TLS termination → Xray:18118)
  Stats Page:       http://127.0.0.1:9000/stats
  Active Routes:    2/10 reverse proxies configured

Reverse Proxies:
  1. myproxy.example.com    → https://blocked-site.com (Port 9443)
  2. another.example.com    → https://another-site.com (Port 9444)

Nginx Reverse Proxy:
  Container:        vless_reverse_proxy_nginx (RUNNING)
  Backend Ports:    9443, 9444 (localhost-only)
  Access:           Via HAProxy SNI routing on port 443

Xray:
  Container:        vless_xray (RUNNING)
  Inbounds:
    - VLESS Reality:   8443 (Reality TLS, from HAProxy)
    - SOCKS5:          10800 (plaintext, from HAProxy)
    - HTTP:            18118 (plaintext, from HAProxy)
    - Reverse Proxy 1: 10080 (plaintext, from Nginx:9443)
    - Reverse Proxy 2: 10081 (plaintext, from Nginx:9444)

fail2ban:
  Status:           ACTIVE
  Jails:
    - vless-haproxy:        5 failures → 1h ban (ports 443,1080,8118)
    - vless-reverseproxy:   5 failures → 1h ban (ports 9443-9452)
  Banned IPs:       0
```

---

## Configuration Files (v4.3)

### HAProxy Config

**Location:** `/opt/vless/config/haproxy.cfg`

**Structure:**
```haproxy
# Frontend 1: SNI Routing (port 443)
frontend vless-reality
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # === DYNAMIC_REVERSE_PROXY_ROUTES ===
    # ACLs and use_backend directives added dynamically
    # Example:
    #   acl is_myproxy req.ssl_sni -i myproxy.example.com
    #   use_backend nginx_myproxy if is_myproxy

    default_backend xray_reality

# Backends
backend xray_reality
    mode tcp
    server xray vless_xray:8443

backend nginx_myproxy
    mode tcp
    server nginx vless_reverse_proxy_nginx:9443

# (More backends added dynamically)
```

**Dynamic ACL Management:**
- Script: `lib/haproxy_config_manager.sh`
- Method: `sed`-based insertion/deletion
- Reload: `docker exec vless_haproxy haproxy -sf $(cat /var/run/haproxy.pid)`

---

### Nginx Reverse Proxy Configs

**Location:** `/opt/vless/config/nginx/reverse-proxy-<domain>.conf`

**Port Range:** 9443-9452 (localhost-only)

**Example Config:**
```nginx
upstream xray_reverseproxy_1 {
    server vless_xray:10080;
    keepalive 32;
}

server {
    listen 127.0.0.1:9443 ssl http2;
    server_name myproxy.example.com;

    # TLS Configuration
    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;
    ssl_protocols TLSv1.3;

    # HTTP Basic Auth
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/conf.d/reverse-proxy/.htpasswd-myproxy;

    # Host Header Validation (VULN-001 fix)
    if ($host != "myproxy.example.com") {
        return 444;
    }

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;

    # Proxy to Xray
    location / {
        proxy_pass http://xray_reverseproxy_1;
        proxy_http_version 1.1;
        proxy_set_header Host blocked-site.com;  # Hardcoded target (VULN-001 fix)
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Важно:**
- **Listen:** `127.0.0.1:9443` (localhost-only, НЕ 0.0.0.0)
- **Access:** Только через HAProxy SNI routing на port 443
- **Security:** Host header validation, HSTS, security headers

---

### Reverse Proxy Database

**Location:** `/opt/vless/data/reverse-proxies.json`

**Schema Version:** 2.0 (v4.3)

**Format:**
```json
{
  "version": "2.0",
  "reverse_proxies": [
    {
      "domain": "myproxy.example.com",
      "target_url": "https://blocked-site.com",
      "nginx_backend_port": 9443,
      "xray_inbound_port": 10080,
      "xray_inbound_tag": "reverse-proxy-1",
      "username": "user_a3f9c2e1",
      "password_hash": "$2y$10$...",
      "created_at": "2025-10-18T12:00:00Z",
      "certificate_path": "/etc/letsencrypt/live/myproxy.example.com/",
      "certificate_expires": "2026-01-15T12:00:00Z",
      "last_renewed": "2025-10-18T12:00:00Z",
      "enabled": true,
      "haproxy_acl_name": "is_myproxy",
      "haproxy_backend_name": "nginx_myproxy"
    }
  ]
}
```

**Key Changes from v4.2:**
- ✅ **NEW:** `nginx_backend_port` (replaces `port` field)
- ✅ **NEW:** `haproxy_acl_name`, `haproxy_backend_name`
- ❌ **REMOVED:** `public_port` (все через HAProxy 443)

---

## Troubleshooting (v4.3)

### HAProxy Debugging

**HAProxy stats page:**
```bash
# Access stats page (localhost only)
curl http://127.0.0.1:9000/stats

# Or open in browser (SSH tunnel required):
ssh -L 9000:localhost:9000 user@server
# Then open http://localhost:9000/stats in browser
```

**HAProxy logs:**
```bash
# Real-time logs
sudo docker logs -f vless_haproxy

# Last 50 lines
sudo docker logs vless_haproxy --tail 50

# SNI routing debug
sudo docker logs vless_haproxy | grep "ssl_sni"
```

**HAProxy reload errors:**
```bash
# Validate config
docker exec vless_haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Check running process
docker exec vless_haproxy ps aux | grep haproxy

# Manual graceful reload
docker exec vless_haproxy haproxy -sf $(cat /var/run/haproxy.pid)
```

---

### SNI Routing Debug

**Test SNI routing:**
```bash
# OpenSSL s_client to test SNI
openssl s_client -connect server_ip:443 -servername myproxy.example.com

# Expected output:
# - Certificate for myproxy.example.com shown
# - Connection routed to Nginx:9443

# Test with different SNI:
openssl s_client -connect server_ip:443 -servername invalid.domain.com

# Expected:
# - Default VLESS backend (Xray:8443)
```

**HAProxy SNI inspection:**
```bash
# Enable debug mode (haproxy.cfg):
# global
#     log stdout format raw local0 debug

# Then restart HAProxy and watch logs:
sudo docker logs -f vless_haproxy
```

---

### Certificate Validation

**Verify combined.pem (for HAProxy TLS termination):**
```bash
# Check certificate validity
openssl x509 -in /opt/vless/certs/combined.pem -text -noout

# Check private key
openssl rsa -in /opt/vless/certs/combined.pem -check

# Verify cert and key match
openssl x509 -modulus -noout -in /opt/vless/certs/combined.pem | openssl md5
openssl rsa -modulus -noout -in /opt/vless/certs/combined.pem | openssl md5
# Output hashes should match
```

**Verify Nginx certificates (for reverse proxy backends):**
```bash
# Check certificate
openssl x509 -in /etc/letsencrypt/live/myproxy.example.com/fullchain.pem -text -noout

# Check expiry date
openssl x509 -enddate -noout -in /etc/letsencrypt/live/myproxy.example.com/fullchain.pem
```

---

### Connection Testing

**Test reverse proxy access:**
```bash
# Without auth (should return 401)
curl -I https://myproxy.example.com

# With valid auth (should return 200)
curl -I -u user_a3f9c2e1:PASSWORD https://myproxy.example.com

# With invalid auth (should return 401)
curl -I -u wrong:credentials https://myproxy.example.com

# Full page fetch
curl -u user_a3f9c2e1:PASSWORD https://myproxy.example.com
```

**Test SNI routing from client:**
```bash
# Test with curl (specify SNI via Host header)
curl -I --resolve myproxy.example.com:443:SERVER_IP https://myproxy.example.com

# Test with browser (use Developer Tools → Network tab)
# Check Request Headers: Host should be myproxy.example.com
```

---

### Common Issues

#### Issue 1: "Connection refused" on https://domain

**Symptom:** `curl: (7) Failed to connect to domain port 443: Connection refused`

**Diagnosis:**
```bash
# Check HAProxy running
docker ps | grep vless_haproxy

# Check HAProxy listening on 443
sudo ss -tulnp | grep :443

# Check HAProxy logs
sudo docker logs vless_haproxy --tail 50
```

**Solutions:**
- HAProxy container not running: `docker compose up -d haproxy`
- Port 443 occupied by another service: `sudo ss -tulnp | grep :443`
- UFW blocking port 443: `sudo ufw allow 443/tcp`

---

#### Issue 2: "Certificate validation failed"

**Symptom:** Browser shows SSL certificate warning

**Diagnosis:**
```bash
# Check certificate for domain
openssl s_client -connect server_ip:443 -servername myproxy.example.com

# Verify Let's Encrypt certificate
certbot certificates | grep myproxy.example.com
```

**Solutions:**
- Certificate expired: `sudo certbot renew --force-renewal`
- Wrong certificate served: Check HAProxy ACL order (first match wins)
- Certificate path wrong: Verify paths in nginx config

---

#### Issue 3: "401 Unauthorized" with correct credentials

**Symptom:** Authentication fails with known-good credentials

**Diagnosis:**
```bash
# Check .htpasswd file
cat /opt/vless/config/reverse-proxy/.htpasswd-myproxy

# Verify password hash
htpasswd -v /opt/vless/config/reverse-proxy/.htpasswd-myproxy user_a3f9c2e1
# Enter password when prompted
```

**Solutions:**
- Password hash corrupted: Regenerate with `htpasswd -bc .htpasswd-myproxy user password`
- Wrong username/password in database: Check `reverse-proxies.json`
- Nginx not reading .htpasswd: Check nginx error log

---

#### Issue 4: HAProxy not routing to correct backend

**Symptom:** Wrong site content displayed

**Diagnosis:**
```bash
# Check HAProxy ACL configuration
cat /opt/vless/config/haproxy.cfg | grep -A 5 "DYNAMIC_REVERSE_PROXY_ROUTES"

# Test SNI routing manually
openssl s_client -connect server_ip:443 -servername myproxy.example.com
```

**Solutions:**
- ACL not added: Run `vless-proxy add` again or add manually
- ACL order wrong: First match wins, reorder if needed
- Nginx backend not running: `docker ps | grep vless_reverse_proxy_nginx`
- Port mismatch: Verify Nginx listening on correct port (9443-9452)

---

## Migration from v4.2 to v4.3

### Breaking Changes

**URL Format Changed:**

**Before (v4.2):**
```
https://myproxy.example.com:9443  ← WITH port
```

**After (v4.3):**
```
https://myproxy.example.com  ← NO port!
```

**Architecture Changes:**
- ❌ stunnel container removed (replaced by HAProxy)
- ✅ HAProxy handles all TLS termination and routing
- ✅ Port range changed: 8443-8452 → 9443-9452 (localhost-only)
- ✅ Subdomain-based access (no port numbers in URLs)

---

### Migration Steps

**1. Backup (CRITICAL):**
```bash
sudo vless-backup
# Backup saved to /tmp/vless_backup_<timestamp>
```

**2. Update system:**
```bash
sudo vless-update

# Warning shown:
⚠️  WARNING: v4.3 BREAKING CHANGES (HAProxy Unified Architecture)

v4.3 replaces stunnel with HAProxy for unified TLS and routing.

BREAKING CHANGES:
  1. stunnel container removed (replaced by HAProxy)
  2. Reverse proxy URLs changed: https://domain:9443 → https://domain (NO port!)
  3. combined.pem certificate format required
  4. Port range changed: 8443-8452 → 9443-9452 (localhost-only)

AUTOMATIC ACTIONS:
  1. stunnel container stopped and removed
  2. HAProxy container deployed
  3. combined.pem generated from existing certificates
  4. Reverse proxy URLs updated (if configured)
  5. UFW rules updated (port 443 for SNI routing)

Estimated downtime: 2-3 minutes (container transition)

Continue with update? [y/N]:
```

**3. Verify migration:**
```bash
# Check HAProxy running
sudo vless-status

# Test reverse proxy access (NEW URL format)
curl -I -u user:pass https://myproxy.example.com  # NO :9443!

# Check logs
sudo docker logs vless_haproxy --tail 50
```

**4. Update client applications:**
- Browser bookmarks: Remove `:9443` from URLs
- Documentation: Update to new URL format
- Firewall rules: NO manual changes needed (все через HAProxy 443)

---

### Rollback (if migration fails)

```bash
# Restore from backup
sudo vless-restore /tmp/vless_backup_<timestamp>

# Old v4.2 configs will work again
# stunnel container will be restored
```

---

## API для разработчиков (Library Functions)

### haproxy_config_manager.sh

**Location:** `/opt/vless/lib/haproxy_config_manager.sh`

**Functions:**

```bash
# Source library
source /opt/vless/lib/haproxy_config_manager.sh

# Add reverse proxy route
add_reverse_proxy_route "myproxy.example.com" 9443
# Returns: 0 (success), 1 (error)

# Remove reverse proxy route
remove_reverse_proxy_route "myproxy.example.com"
# Returns: 0 (success), 1 (error)

# List active routes
list_haproxy_routes
# Output: domain → port mappings

# Graceful reload
reload_haproxy
# Returns: 0 (success), 1 (error)

# Validate config
validate_haproxy_config
# Returns: 0 (valid), 1 (invalid)
```

---

### nginx_config_generator.sh

**Location:** `/opt/vless/lib/nginx_config_generator.sh`

**Functions:**

```bash
source /opt/vless/lib/nginx_config_generator.sh

# Generate Nginx reverse proxy config (heredoc-based)
generate_reverseproxy_nginx_config \
    "myproxy.example.com" \
    "blocked-site.com" \
    9443 \
    10080 \
    "user_a3f9c2e1" \
    '$2b$12$hash...'

# Output: Config written to /opt/vless/config/nginx/reverse-proxy-myproxy.example.com.conf
```

---

### reverseproxy_db.sh

**Location:** `/opt/vless/lib/reverseproxy_db.sh`

**Functions:**

```bash
source /opt/vless/lib/reverseproxy_db.sh

# Add proxy to database
add_reverse_proxy_to_db '{
  "domain": "myproxy.example.com",
  "target_url": "https://blocked-site.com",
  "nginx_backend_port": 9443,
  ...
}'

# Get proxy details
get_reverse_proxy "myproxy.example.com"
# Output: JSON object

# List all proxies
list_reverse_proxies
# Output: JSON array

# Remove proxy
remove_reverse_proxy "myproxy.example.com"
```

---

## Logs

### HAProxy Logs (v4.3)

```bash
# Real-time logs
sudo docker logs -f vless_haproxy

# Filter by frontend
sudo docker logs vless_haproxy | grep "vless-reality"
sudo docker logs vless_haproxy | grep "socks5-tls"

# SNI routing logs
sudo docker logs vless_haproxy | grep "ssl_sni"

# Backend selection logs
sudo docker logs vless_haproxy | grep "use_backend"
```

---

### Nginx Logs

```bash
# Error log (authentication failures)
sudo tail -f /opt/vless/logs/nginx/reverse-proxy-error.log

# No access log (privacy requirement)
# Access logging DISABLED in v4.3
```

---

### Xray Logs

```bash
# Container logs
sudo docker logs -f vless_xray

# Error log
sudo tail -f /opt/vless/logs/xray/error.log

# Access log (if enabled)
sudo tail -f /opt/vless/logs/xray/access.log
```

---

### fail2ban Logs

```bash
# fail2ban log
sudo tail -f /var/log/fail2ban.log

# Check banned IPs (HAProxy jail)
sudo fail2ban-client status vless-haproxy

# Check banned IPs (Reverse proxy jail)
sudo fail2ban-client status vless-reverseproxy

# Unban IP
sudo fail2ban-client set vless-haproxy unbanip IP_ADDRESS
```

---

## Примеры использования

### Пример 1: Настройка reverse proxy для заблокированного сайта

```bash
# 1. Настройте DNS A record (вне скрипта)
# myproxy.example.com → 203.0.113.42

# 2. Запустите интерактивную настройку
sudo vless-proxy add

# Prompts:
# Domain: myproxy.example.com
# Target URL: https://blocked-site.com
# Email: admin@example.com

# 3. Дождитесь завершения (1-2 минуты)
# Output: URL, credentials

# 4. Откройте в браузере
# https://myproxy.example.com  # NO :9443!

# 5. Введите credentials
# Username: user_a3f9c2e1
# Password: 4fd0a3936e5a1e28b7c9d0f1e2a3b4c5

# 6. Доступ к заблокированному сайту получен
```

---

### Пример 2: Просмотр статуса всех reverse proxies

```bash
# Список всех настроенных доменов
sudo vless-proxy list

# Output:
# 1. myproxy.example.com → blocked-site.com (Port 9443)
# 2. news.example.com → blocked-news.com (Port 9444)
# Total: 2/10
```

---

### Пример 3: Удаление reverse proxy

```bash
# Удалить домен
sudo vless-proxy remove old-proxy.example.com

# Подтверждение:
# Type 'old-proxy.example.com' to confirm:
old-proxy.example.com

# Output:
# ✅ Reverse Proxy Removed
# Port 9445 now available for reuse
```

---

### Пример 4: Отладка проблем с доступом

```bash
# 1. Проверка HAProxy
sudo docker logs vless_haproxy --tail 50

# 2. Проверка Nginx backend
sudo docker exec vless_reverse_proxy_nginx nginx -t

# 3. Проверка Xray routing
sudo docker logs vless_xray | grep "reverse-proxy"

# 4. Тест с curl
curl -I -u user:pass https://myproxy.example.com

# 5. Проверка fail2ban
sudo fail2ban-client status vless-reverseproxy
```

---

## Exit Codes

Все команды следуют стандартным exit code conventions:

- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: Permission denied (not running as root)

---

## Безопасность

### Уровни защиты (v4.3)

1. **TLS 1.3 Encryption** (HAProxy SNI routing, Nginx HTTPS)
2. **HTTP Basic Auth** (bcrypt hashed, 32-char passwords)
3. **fail2ban** (5 failures → 1 hour ban, HAProxy + Nginx filters)
4. **Rate Limiting** (10 req/s per IP, 5 concurrent connections)
5. **Domain Restriction** (Xray routing to target site only)
6. **Host Header Validation** (VULN-001 fix, hardcoded target)
7. **HSTS** (max-age=31536000, VULN-002 fix)
8. **Security Headers** (X-Frame-Options, X-Content-Type-Options, etc.)

### Рекомендации

- ✅ Используйте сильные пароли (auto-generated 32 chars)
- ✅ Регулярно обновляйте сертификаты (auto-renewal enabled)
- ✅ Мониторьте fail2ban logs (`/var/log/fail2ban.log`)
- ✅ Проверяйте HAProxy stats (`http://127.0.0.1:9000/stats`)
- ✅ Ограничивайте количество доменов (max 10 per server)

---

**Next:** [Security Documentation](SECURITY_v4.3.md) | [User Guide](REVERSE_PROXY_GUIDE_v4.3.md) | [Architecture](prd/04_architecture.md#47-haproxy-unified-architecture-v43)

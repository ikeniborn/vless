# VLESS Reverse Proxy - План Доработок v5.8+

**Дата:** 2025-10-20
**Версия:** v5.8
**Статус:** Research Complete → Implementation Planning

---

## Исполнительное Резюме

На основе исследования современных best practices для Nginx reverse proxy и сложных сценариев авторизации (OAuth2, Google Auth, session cookies, CSRF protection) разработан комплексный план доработок для обеспечения стабильной работы со всеми типами авторизации.

**Ключевые находки:**
- ✅ v5.8 базовая реализация (cookie/URL rewriting) покрывает ~70% сценариев
- ⚠️ Требуются доработки для OAuth2/OIDC, JWT, CSRF tokens, WebSocket
- ⚠️ Отсутствует поддержка больших cookies (>4kb), multi-domain auth
- ⚠️ CSP headers могут блокировать inline scripts на некоторых сайтах

---

## Часть 1: Критические Улучшения (v5.9)

### 1.1 Advanced Cookie Handling

**Проблема:**
Nginx по умолчанию копирует только первый `Set-Cookie` header. Сайты с OAuth2/Google Auth часто устанавливают 3-5+ cookies одновременно.

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# Multiple Set-Cookie headers support (OAuth2/Google Auth)
proxy_pass_header Set-Cookie;
proxy_set_header Cookie $http_cookie;

# Cookie size increase (large JWT tokens, OAuth2 state)
proxy_buffer_size 32k;  # Increased from 16k
proxy_buffers 16 32k;   # Increased from 8 16k
proxy_busy_buffers_size 64k;  # Increased from 32k

# Cookie flags (modern security standards)
proxy_cookie_flags ~ secure httponly samesite=lax;
# For cross-origin scenarios (Google Auth): samesite=none requires secure
# proxy_cookie_flags ~ secure httponly samesite=none;
```

**Приоритет:** 🔴 CRITICAL
**Сложность:** 🟢 LOW
**Влияние:** OAuth2, Google Auth, session-based auth

---

### 1.2 CSRF Protection Headers

**Проблема:**
Многие сайты проверяют Origin/Referer для CSRF protection. Текущая конфигурация может ломать POST/PUT/DELETE запросы.

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# CSRF Protection Headers (preserve for validation)
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Original-URL $scheme://$http_host$request_uri;

# Origin: set to target site (already implemented in v5.8) ✅
proxy_set_header Origin "https://${target_site}";

# Referer: rewrite from proxy domain to target domain (CRITICAL for CSRF)
set $new_referer $http_referer;
if ($http_referer ~* "^https?://${domain}(.*)$") {
    set $new_referer "https://${target_site}$1";
}
proxy_set_header Referer $new_referer;
```

**Приоритет:** 🔴 CRITICAL
**Сложность:** 🟡 MEDIUM
**Влияние:** Form-based auth, CSRF-protected APIs

---

### 1.3 Content Security Policy (CSP) Header Handling

**Проблема:**
CSP headers от целевого сайта могут блокировать загрузку ресурсов через прокси-домен.

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# CSP Header Rewriting (replace target domain with proxy domain)
proxy_hide_header Content-Security-Policy;
proxy_hide_header Content-Security-Policy-Report-Only;

# Option 1: Disable CSP (permissive, not recommended)
# add_header Content-Security-Policy "" always;

# Option 2: Rewrite CSP (advanced, requires lua-nginx-module)
# header_filter_by_lua_block {
#     local csp = ngx.header["Content-Security-Policy"]
#     if csp then
#         csp = string.gsub(csp, "${target_site}", "${domain}")
#         ngx.header["Content-Security-Policy"] = csp
#     end
# }
```

**Приоритет:** 🟡 HIGH
**Сложность:** 🔴 HIGH (requires Lua module)
**Влияние:** Modern web apps (React, Vue, Angular)

---

### 1.4 WebSocket Support

**Проблема:**
Многие современные приложения используют WebSocket (chat, real-time updates, OAuth2 flows).

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# WebSocket support (already has Upgrade headers in v5.8, add timeout) ✅
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;

# WebSocket timeout (prevent premature disconnection)
proxy_read_timeout 3600s;  # 1 hour for long-lived connections
proxy_send_timeout 3600s;

# Map upgrade header
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
```

**Приоритет:** 🟡 HIGH
**Сложность:** 🟢 LOW
**Влияние:** Real-time apps, OAuth2 callback flows

---

## Часть 2: Улучшения Безопасности (v5.10)

### 2.1 Enhanced Security Headers

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# Permissions-Policy (modern replacement for Feature-Policy)
add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;

# Cross-Origin-Embedder-Policy (COEP)
add_header Cross-Origin-Embedder-Policy "require-corp" always;

# Cross-Origin-Opener-Policy (COOP)
add_header Cross-Origin-Opener-Policy "same-origin" always;

# Cross-Origin-Resource-Policy (CORP)
add_header Cross-Origin-Resource-Policy "same-origin" always;

# Expect-CT (Certificate Transparency)
add_header Expect-CT "max-age=86400, enforce" always;
```

**Приоритет:** 🟢 MEDIUM
**Сложность:** 🟢 LOW
**Влияние:** Security posture, browser isolation

---

### 2.2 Rate Limiting Per Auth State

**Проблема:**
Текущий rate limiting одинаковый для authenticated и unauthenticated запросов.

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# Different rate limits based on auth status
map $http_authorization $limit_key {
    default $binary_remote_addr;
    ~.      "";  # Authenticated users bypass IP-based rate limit
}

limit_req_zone $limit_key zone=reverseproxy_${domain}_unauth:10m rate=10r/s;
limit_req_zone $remote_user zone=reverseproxy_${domain}_auth:10m rate=100r/s;

# In server block:
limit_req zone=reverseproxy_${domain}_unauth burst=20 nodelay;
limit_req zone=reverseproxy_${domain}_auth burst=200 nodelay;
```

**Приоритет:** 🟢 MEDIUM
**Сложность:** 🟡 MEDIUM
**Влияние:** DoS protection, user experience

---

## Часть 3: Продвинутые Функции (v6.0)

### 3.1 OAuth2 / OIDC Support (External Auth)

**Проблема:**
Требуется централизованная авторизация через OAuth2 Proxy для защиты множества сервисов.

**Решение:**
```nginx
# NEW: lib/oauth2_proxy_integration.sh

# OAuth2 Proxy integration (optional, advanced users)
location /oauth2/ {
    proxy_pass http://oauth2_proxy:4180;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Scheme $scheme;
    proxy_set_header X-Auth-Request-Redirect $request_uri;
}

location = /oauth2/auth {
    proxy_pass http://oauth2_proxy:4180;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header Content-Length "";
    proxy_pass_request_body off;
}

location / {
    # Auth subrequest
    auth_request /oauth2/auth;
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;

    # Pass user info to backend
    proxy_set_header X-User $user;
    proxy_set_header X-Email $email;

    # Proxy to target site
    proxy_pass https://${target_ipv4};
}
```

**Приоритет:** 🟢 LOW (advanced feature)
**Сложность:** 🔴 HIGH
**Влияние:** Enterprise deployments, multi-service auth

---

### 3.2 Session Persistence (Sticky Sessions)

**Проблема:**
Для load-balanced backends нужна привязка сессии к конкретному серверу.

**Решение:**
```nginx
# lib/nginx_config_generator.sh (if multiple backends)

upstream backend_${domain} {
    # IP hash for session persistence
    ip_hash;

    # Or cookie-based (more reliable)
    # hash $cookie_sessionid consistent;

    server ${target_ipv4}:443;
}

location / {
    proxy_pass https://backend_${domain};
}
```

**Приоритет:** 🟢 LOW (not needed for single backend)
**Сложность:** 🟡 MEDIUM
**Влияние:** Load-balanced deployments

---

### 3.3 Intelligent Sub-filter (Regex-based URL Rewriting)

**Проблема:**
Текущий `sub_filter` не покрывает JSON responses, dynamic JS, relative URLs.

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# Enhanced sub_filter (all content types)
sub_filter_types text/html text/css text/javascript application/javascript application/json;

# Multiple patterns (cover more cases)
sub_filter 'https://${target_site}' 'https://${domain}';
sub_filter 'http://${target_site}' 'https://${domain}';
sub_filter '//${target_site}' '//${domain}';  # Protocol-relative URLs

# Preserve API calls (optional, if target site has API on same domain)
# sub_filter_once off;
# sub_filter_last_modified on;

# Alternative: Use ngx_http_substitutions_filter_module for regex
# subs_filter 'https?://([^/]*\.)?${target_site}' 'https://$1${domain}' gir;
```

**Приоритет:** 🟡 HIGH
**Сложность:** 🟡 MEDIUM
**Влияние:** SPA apps, AJAX-heavy sites

---

## Часть 4: Диагностика и Мониторинг (v5.9)

### 4.1 Enhanced Logging (Conditional)

**Решение:**
```nginx
# lib/nginx_config_generator.sh

# Conditional access logging (errors only, privacy-preserving)
map $status $loggable {
    ~^[23]  0;  # 2xx, 3xx: don't log
    default 1;  # 4xx, 5xx: log
}

access_log /var/log/nginx/reverse-proxy-${domain}-access.log combined if=$loggable;

# Debug headers (enabled via query param ?debug=1)
map $arg_debug $debug_headers {
    1 "on";
    default "off";
}

add_header X-Debug-Backend $upstream_addr always if=$debug_headers;
add_header X-Debug-Response-Time $upstream_response_time always if=$debug_headers;
```

**Приоритет:** 🟢 MEDIUM
**Сложность:** 🟢 LOW
**Влияние:** Troubleshooting, compliance (privacy)

---

### 4.2 Health Checks for Target Sites

**Решение:**
```bash
# NEW: lib/reverse_proxy_health_check.sh

#!/bin/bash
# Periodic health check for reverse proxy backends
# Alerts when target site is down

check_backend_health() {
    local domain="$1"
    local target_ipv4="$2"

    if ! curl -sf --max-time 10 "https://${target_ipv4}" > /dev/null; then
        log_error "Backend DOWN: ${domain} → ${target_ipv4}"
        # TODO: Send alert (email, webhook, etc.)
        return 1
    fi

    log "Backend UP: ${domain} → ${target_ipv4}"
    return 0
}

# Cron job: */5 * * * * /opt/vless/lib/reverse_proxy_health_check.sh
```

**Приоритет:** 🟢 MEDIUM
**Сложность:** 🟢 LOW
**Влияние:** Availability monitoring

---

## Часть 5: Wizard Improvements (v5.9)

### 5.1 Advanced Configuration Wizard

**Новые опции в `vless-setup-proxy`:**

```bash
# scripts/vless-setup-proxy (enhanced)

prompt_advanced_options() {
    echo "Advanced options (optional):"
    echo ""

    # Cookie SameSite policy
    read -p "Cookie SameSite policy [lax/strict/none]: " samesite
    samesite=${samesite:-lax}

    # WebSocket support
    read -p "Enable WebSocket support? [y/N]: " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_websocket=true
    fi

    # Large cookie support
    read -p "Enable large cookie support (OAuth2)? [y/N]: " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_large_cookies=true
    fi

    # CSP handling
    echo ""
    echo "Content Security Policy (CSP) handling:"
    echo "  1) Strip CSP headers (permissive)"
    echo "  2) Keep CSP as-is (may break some features)"
    read -p "Choice [1]: " csp_mode
    csp_mode=${csp_mode:-1}
}
```

**Приоритет:** 🟡 HIGH
**Сложность:** 🟡 MEDIUM
**Влияние:** User experience, flexibility

---

### 5.2 Configuration Templates

**Предустановленные шаблоны для популярных сервисов:**

```bash
# NEW: lib/reverse_proxy_templates.sh

# Template: Google Workspace (Docs, Sheets, etc.)
template_google_workspace() {
    # Large cookies, WebSocket, strict CORS
    enable_large_cookies=true
    enable_websocket=true
    samesite_policy="none"
    csrf_strict=true
}

# Template: Jira / Confluence
template_atlassian() {
    # Session cookies, CSRF protection
    enable_large_cookies=true
    csrf_strict=true
    websocket_timeout=7200  # 2 hours
}

# Template: Generic OAuth2
template_oauth2() {
    # OAuth2 state cookies, redirects
    enable_large_cookies=true
    cookie_refresh=3600  # 1 hour
    csrf_strict=true
}

# Usage in wizard:
echo "Select template (optional):"
echo "  1) Generic (default)"
echo "  2) Google Workspace"
echo "  3) Atlassian (Jira/Confluence)"
echo "  4) OAuth2-protected app"
read -p "Template [1]: " template_choice
```

**Приоритет:** 🟢 MEDIUM
**Сложность:** 🟡 MEDIUM
**Влияние:** Ease of use, success rate

---

## Часть 6: Тестирование (v5.9)

### 6.1 Automated Test Suite

```bash
# NEW: tests/reverse_proxy_auth_test.sh

#!/bin/bash
# Comprehensive reverse proxy authentication testing

test_session_cookies() {
    # Test 1: Cookie persistence across requests
    local cookies=$(mktemp)
    curl -c $cookies -u "$username:$password" "https://$domain/login"

    # Test 2: Subsequent request uses stored cookies
    if curl -b $cookies "https://$domain/profile" | grep -q "authenticated"; then
        echo "✅ Session cookies working"
    else
        echo "❌ Session cookies NOT working"
    fi
}

test_csrf_protection() {
    # Test 1: GET request (should work)
    curl -X GET "https://$domain/api/data" -o /dev/null -w "%{http_code}"

    # Test 2: POST without CSRF token (should fail)
    curl -X POST "https://$domain/api/data" -d '{}' -w "%{http_code}"

    # Test 3: POST with CSRF token (should work)
    # ...
}

test_websocket() {
    # Test WebSocket connection
    wscat -c "wss://$domain/ws" --auth "$username:$password"
}
```

**Приоритет:** 🟡 HIGH
**Сложность:** 🟡 MEDIUM
**Влияние:** Quality assurance, regression prevention

---

## Часть 7: Документация (v5.9)

### 7.1 Troubleshooting Guide

**Новый документ:** `docs/REVERSE_PROXY_TROUBLESHOOTING.md`

Разделы:
1. **Common Auth Issues**
   - Login loop (cookie domain mismatch)
   - CSRF validation failures (Origin/Referer mismatch)
   - Session timeout (cookie expiration)

2. **OAuth2 / Google Auth Issues**
   - Redirect URI mismatch
   - Cookie size limits (>4kb)
   - State parameter validation

3. **WebSocket Issues**
   - Timeout configuration
   - Upgrade header missing
   - HAProxy passthrough

4. **Performance Issues**
   - Large file uploads/downloads
   - Buffering configuration
   - Rate limiting tuning

**Приоритет:** 🟡 HIGH
**Сложность:** 🟢 LOW
**Влияние:** User support, self-service troubleshooting

---

## Roadmap

### v5.9 (Immediate - 1-2 weeks)
- ✅ Enhanced cookie handling (1.1)
- ✅ CSRF protection headers (1.2)
- ✅ WebSocket support (1.4)
- ✅ Advanced wizard options (5.1)
- ✅ Enhanced logging (4.1)

### v5.10 (Short-term - 1 month)
- ✅ CSP header handling (1.3)
- ✅ Enhanced security headers (2.1)
- ✅ Rate limiting per auth state (2.2)
- ✅ Configuration templates (5.2)
- ✅ Health checks (4.2)

### v6.0 (Mid-term - 2-3 months)
- ✅ OAuth2/OIDC support (3.1)
- ✅ Intelligent sub-filter (3.3)
- ✅ Session persistence (3.2)
- ✅ Automated test suite (6.1)
- ✅ Troubleshooting guide (7.1)

---

## Приоритизация

### Критические (выполнить в v5.9):
1. **Enhanced cookie handling (1.1)** - блокирует OAuth2/Google Auth
2. **CSRF protection (1.2)** - ломает POST/PUT/DELETE на многих сайтах
3. **WebSocket support (1.4)** - критично для real-time apps

### Высокий приоритет (v5.9-5.10):
4. **CSP header handling (1.3)** - блокирует современные SPA
5. **Advanced wizard (5.1)** - улучшает UX
6. **Intelligent sub-filter (3.3)** - покрывает больше сценариев

### Средний приоритет (v5.10-6.0):
7. **Enhanced security headers (2.1)** - улучшает security posture
8. **Configuration templates (5.2)** - ease of use
9. **Health checks (4.2)** - availability monitoring

### Низкий приоритет (v6.0+):
10. **OAuth2/OIDC (3.1)** - advanced enterprise feature
11. **Session persistence (3.2)** - only for load-balanced setups

---

## Риски и Ограничения

### Технические Ограничения

1. **Nginx native limitations:**
   - Нет regex в `sub_filter` (нужен 3rd-party module)
   - Нет CSP rewriting (нужен Lua module)
   - Только первый `Set-Cookie` без `proxy_pass_header`

2. **Performance trade-offs:**
   - `sub_filter` on large files = high CPU usage
   - Large buffers = high memory usage
   - WebSocket long-lived connections = high fd count

3. **Security trade-offs:**
   - Stripping CSP = reduced security
   - SameSite=None = CSRF vulnerability (requires secure)
   - Proxy authentication bypass (если target site имеет свою auth)

### Совместимость

**Работает:**
- ✅ Session-based auth (cookies)
- ✅ Form-based login
- ✅ HTTP Basic Auth (над proxy auth)
- ✅ Cookie-based JWT

**Требует доработок:**
- ⚠️ OAuth2 / OIDC (нужен 1.1 + 1.2)
- ⚠️ Google Auth (нужен 1.1 + large cookies)
- ⚠️ WebSocket auth (нужен 1.4)

**Не работает:**
- ❌ Client-side certificates (mTLS)
- ❌ Kerberos / NTLM
- ❌ SAML (требует XML rewriting)

---

## Заключение

План доработок охватывает **все основные сценарии авторизации** в современных web-приложениях:
- Session cookies ✅ (текущий v5.8)
- OAuth2/OIDC ⚠️ (требует v5.9)
- Google Auth ⚠️ (требует v5.9)
- Form-based auth ✅ (текущий v5.8)
- CSRF protection ⚠️ (требует v5.9)
- WebSocket auth ⚠️ (требует v5.9)

**Рекомендация:** Начать с критических улучшений (1.1, 1.2, 1.4) в версии v5.9, что покроет ~95% use-cases.

**Следующий шаг:** Начать реализацию v5.9 критических улучшений.

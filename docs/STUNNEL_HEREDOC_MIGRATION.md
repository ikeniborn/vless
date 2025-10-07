# stunnel Configuration: Template vs Heredoc Migration

**Дата:** 2025-10-07
**Цель:** Сравнить template-based подход с heredoc для stunnel конфигурации
**Контекст:** Унификация кодовой базы (Xray и docker-compose используют heredoc)

---

## 📊 Текущая реализация (Template-based)

### Архитектура

```
templates/
└── stunnel.conf.template (111 строк)
    ↓ envsubst '${DOMAIN}'
lib/stunnel_setup.sh
└── create_stunnel_config() → ${CONFIG_DIR}/stunnel.conf
```

### Плюсы ✅

1. **Separation of Concerns** - конфиг отделен от логики
2. **Easier Review** - можно просмотреть stunnel.conf.template как standalone файл
3. **Version Control** - изменения конфига видны в git diff
4. **Documentation** - template самодокументируется (комментарии)
5. **No Escaping** - не нужно экранировать спецсимволы в heredoc

### Минусы ❌

1. **Extra Directory** - требует templates/ директорию
2. **Build Step** - требует envsubst (dependency)
3. **Two Files** - конфиг в 2 местах (template + generated)
4. **Inconsistency** - Xray/docker-compose используют heredoc

### Метрики

- **Переменных:** 1 (`${DOMAIN}`)
- **Строк:** 111
- **Зависимости:** envsubst (GNU gettext)
- **Сложность:** LOW (всего 1 переменная)

---

## 🔄 Предлагаемая реализация (Heredoc)

### Архитектура

```
lib/stunnel_setup.sh
└── create_stunnel_config()
    └── cat > stunnel.conf <<EOF ... EOF (inline heredoc)
```

### Плюсы ✅

1. **Consistency** - единый подход с Xray/docker-compose
2. **No External Files** - все в одном месте
3. **No Dependencies** - не требует envsubst
4. **Atomic** - генерация и логика в одной функции
5. **Easier Debugging** - меньше файлов для проверки

### Минусы ❌

1. **Code Mixing** - конфиг смешан с bash кодом
2. **Harder Review** - heredoc менее читабелен чем standalone файл
3. **Git Diff Noise** - изменения конфига показываются в bash файле
4. **Escaping** - нужно экранировать $ если нужен literal

### Метрики

- **Переменных:** 1 (`$domain` или `${DOMAIN}`)
- **Строк:** ~115 (111 конфиг + 4 heredoc wrapper)
- **Зависимости:** bash (встроенный)
- **Сложность:** LOW

---

## 🔍 Сравнительная таблица

| Критерий | Template | Heredoc | Победитель |
|----------|----------|---------|------------|
| **Consistency с проектом** | ❌ Xray/docker-compose используют heredoc | ✅ Единый подход | **Heredoc** |
| **Readability** | ✅ Standalone файл легче читать | ⚠️ Heredoc в bash коде | **Template** |
| **Maintainability** | ⚠️ 2 файла (template + script) | ✅ 1 файл | **Heredoc** |
| **Version Control** | ✅ Чистый git diff для конфига | ❌ Diff в bash файле | **Template** |
| **Dependencies** | ❌ Требует envsubst | ✅ Только bash | **Heredoc** |
| **Complexity** | ⚠️ Build step (envsubst) | ✅ Direct generation | **Heredoc** |
| **Self-documentation** | ✅ Комментарии в template | ⚠️ Комментарии в heredoc | **Равенство** |
| **Escaping issues** | ✅ Нет экранирования | ⚠️ Нужно экранировать $ | **Template** |

**Итог:** 4:4 (равенство, но с учетом consistency → **Heredoc побеждает**)

---

## 💻 Код обоих вариантов

### Вариант A: Template (текущий)

**templates/stunnel.conf.template:**
```conf
# stunnel Configuration Template
foreground = yes
output = /var/log/stunnel/stunnel.log
debug = 5
syslog = no

ciphersuites = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256

[socks5-tls]
accept = 0.0.0.0:1080
connect = vless_xray:10800
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
verify = 0
sslVersion = TLSv1.3

[http-tls]
accept = 0.0.0.0:8118
connect = vless_xray:18118
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
verify = 0
sslVersion = TLSv1.3
```

**lib/stunnel_setup.sh:**
```bash
create_stunnel_config() {
    local domain="$1"

    # Generate from template
    envsubst '${DOMAIN}' < "$STUNNEL_TEMPLATE" > "$STUNNEL_CONFIG"
    chmod 600 "$STUNNEL_CONFIG"
}
```

**Строк кода:** Template (111) + Bash (3) = **114 строк**
**Файлов:** 2

---

### Вариант B: Heredoc (предлагаемый)

**lib/stunnel_setup.sh:**
```bash
create_stunnel_config() {
    local domain="$1"

    log_stunnel_info "Generating stunnel configuration..."

    # Validate domain
    if [[ -z "$domain" ]]; then
        log_stunnel_error "Domain name required"
        return 1
    fi

    # Generate config via heredoc
    cat > "$STUNNEL_CONFIG" <<EOF
#
# stunnel Configuration for VLESS Reality VPN
# Version: 4.0
# Purpose: TLS termination for SOCKS5 and HTTP proxies
#
# Domain: $domain
# Generated: $(date -Iseconds)
#
# Architecture:
#   Client → stunnel (TLS termination, ports 1080/8118)
#          → Xray (plaintext proxy, localhost 10800/18118)
#          → Internet
#

# Global settings
foreground = yes
output = /var/log/stunnel/stunnel.log
debug = 5
syslog = no

# Security options (OpenSSL 3.x compatibility)
# Note: SSLv2, SSLv3, TLSv1.0, TLSv1.1, TLSv1.2 are disabled by default
# Only TLSv1.3 will be used

# TLS 1.3 only cipher suites (strongest)
ciphersuites = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256

# Connection limits
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# Timeouts (seconds)
TIMEOUTbusy = 300
TIMEOUTclose = 10
TIMEOUTconnect = 10
TIMEOUTidle = 3600

# ============================================================================
# SOCKS5 Proxy Service (TLS-encrypted)
# ============================================================================
[socks5-tls]
# Accept encrypted connections from internet
accept = 0.0.0.0:1080

# Forward plaintext to Xray SOCKS5 (localhost)
connect = vless_xray:10800

# Let's Encrypt certificates (shared with Xray VLESS)
cert = /certs/live/$domain/fullchain.pem
key = /certs/live/$domain/privkey.pem

# Client certificate validation (disabled - password auth in Xray)
verify = 0

# TLS protocol settings
sslVersion = TLSv1.3

# Session cache for performance
sessionCacheSize = 1000
sessionCacheTimeout = 300

# Connection options
TIMEOUTbusy = 300
TIMEOUTclose = 10
TIMEOUTconnect = 10
TIMEOUTidle = 3600

# ============================================================================
# HTTP Proxy Service (TLS-encrypted)
# ============================================================================
[http-tls]
# Accept encrypted connections from internet
accept = 0.0.0.0:8118

# Forward plaintext to Xray HTTP proxy (localhost)
connect = vless_xray:18118

# Let's Encrypt certificates (shared with Xray VLESS)
cert = /certs/live/$domain/fullchain.pem
key = /certs/live/$domain/privkey.pem

# Client certificate validation (disabled - password auth in Xray)
verify = 0

# TLS protocol settings
sslVersion = TLSv1.3

# Session cache for performance
sessionCacheSize = 1000
sessionCacheTimeout = 300

# Connection options
TIMEOUTbusy = 300
TIMEOUTclose = 10
TIMEOUTconnect = 10
TIMEOUTidle = 3600

# ============================================================================
# Notes:
# ============================================================================
# 1. stunnel runs in foreground mode for Docker compatibility
# 2. Certificates automatically renewed by Certbot (Let's Encrypt)
# 3. vless_xray hostname resolves via Docker network (vless_reality_net)
# 4. Xray handles authentication (password-based SOCKS5/HTTP)
# 5. No client certificates required (verify = 0)
# 6. TLS 1.3 only for maximum security
# 7. Session cache improves reconnection performance
# 8. TCP_NODELAY disables Nagle's algorithm (lower latency)
# 9. Port 1080 (SOCKS5) and 8118 (HTTP) exposed to internet
# 10. Ports 10800 (SOCKS5) and 18118 (HTTP) localhost-only in Xray
EOF

    # Set permissions
    chmod 600 "$STUNNEL_CONFIG"

    log_stunnel_success "stunnel configuration created: $STUNNEL_CONFIG"
    return 0
}
```

**Строк кода:** 135 строк в одном файле
**Файлов:** 1

---

## 🔧 План миграции (Template → Heredoc)

### Шаг 1: Обновить lib/stunnel_setup.sh

**Файл:** `lib/stunnel_setup.sh`
**Функция:** `create_stunnel_config()`
**Изменения:**
- Заменить `envsubst` вызов на heredoc
- Удалить проверку template file existence
- Заменить `${DOMAIN}` на `$domain` (bash variable)

**Diff:**
```diff
create_stunnel_config() {
    local domain="$1"

    log_stunnel_info "Generating stunnel configuration..."

-   # Check template exists
-   if [[ ! -f "$STUNNEL_TEMPLATE" ]]; then
-       log_stunnel_error "stunnel template not found: $STUNNEL_TEMPLATE"
-       return 1
-   fi
-
-   # Generate config from template
-   if ! envsubst '${DOMAIN}' < "$STUNNEL_TEMPLATE" > "$STUNNEL_CONFIG"; then
-       log_stunnel_error "Failed to generate stunnel configuration"
-       return 1
-   fi
+   # Generate config via heredoc
+   cat > "$STUNNEL_CONFIG" <<'EOF'
+   # ... full config here with $domain variable ...
+   cert = /certs/live/$domain/fullchain.pem
+   key = /certs/live/$domain/privkey.pem
+   EOF

    chmod 600 "$STUNNEL_CONFIG"
    log_stunnel_success "stunnel configuration created"
}
```

**Note:** Используем `<<'EOF'` (quoted) чтобы НЕ интерпретировать $ внутри конфига, кроме мест где нужна подстановка `$domain`.

**Альтернативный подход (если нужны подстановки):**
```bash
cat > "$STUNNEL_CONFIG" <<EOF
cert = /certs/live/${domain}/fullchain.pem
EOF
```

---

### Шаг 2: Удалить templates/ директорию

**Файлы для удаления:**
```
rm -rf templates/
```

**Обновить .gitignore (если есть):**
```diff
- templates/*.conf
```

---

### Шаг 3: Обновить переменные в lib/stunnel_setup.sh

**Удалить:**
```bash
readonly STUNNEL_TEMPLATE="${TEMPLATE_DIR}/stunnel.conf.template"
```

**Удалить проверку TEMPLATE_DIR:**
```bash
# В начале файла или в вызывающем коде
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    mkdir -p "$TEMPLATE_DIR"
fi
```

---

### Шаг 4: Тестирование

**Test 1: Generation**
```bash
source lib/stunnel_setup.sh
create_stunnel_config "vpn.example.com"

# Verify output
cat /opt/vless/config/stunnel.conf | grep "cert = /certs/live/vpn.example.com"
```

**Test 2: Docker container start**
```bash
docker compose up stunnel
docker logs vless_stunnel | grep "Configuration successful"
```

**Test 3: TLS handshake**
```bash
openssl s_client -connect server:1080 -showcerts
# Should show TLS 1.3 handshake
```

---

## 📋 Checklist миграции

### Pre-Migration
- [ ] Backup текущего templates/stunnel.conf.template
- [ ] Backup lib/stunnel_setup.sh
- [ ] Review heredoc escaping rules

### Migration
- [ ] Update create_stunnel_config() в lib/stunnel_setup.sh
- [ ] Replace envsubst with heredoc
- [ ] Update variable substitution (${DOMAIN} → $domain)
- [ ] Remove STUNNEL_TEMPLATE constant
- [ ] Test config generation locally

### Post-Migration
- [ ] Delete templates/stunnel.conf.template
- [ ] Delete templates/ directory (if empty)
- [ ] Update PRD.md (remove stunnel template mention)
- [ ] Update ROADMAP_v4.1.md (mark template migration as DONE)
- [ ] Run full installation test
- [ ] Commit changes with message: "refactor: migrate stunnel config from template to heredoc"

---

## ⚖️ Рекомендация

### ✅ **Мигрировать на heredoc**

**Причины:**

1. **Consistency** - единый подход с Xray/docker-compose конфигами
2. **Simplicity** - меньше файлов, меньше зависимостей (envsubst)
3. **Maintainability** - вся логика в одном месте
4. **Low Risk** - всего 1 переменная, простая миграция

**Против:**

- Теряется визуальная separation (конфиг в bash файле)
- Git diff будет показывать изменения конфига в bash файле

**Но:** Для stunnel конфига (всего 111 строк, 1 переменная) преимущества heredoc перевешивают.

---

## 🎯 Итоговое решение

**Рекомендация:** ✅ **Мигрировать stunnel на heredoc**

**Трудозатраты:** ~1 час (update code + testing)

**Риск:** LOW (простая замена, легко откатить)

**Benefit:** HIGH (consistency, simplicity, no external dependencies)

---

**Следующий шаг:** Если согласен - выполняю миграцию?

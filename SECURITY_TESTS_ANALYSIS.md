# SECURITY_TESTS_ANALYSIS.md - Анализ скрипта тестирования безопасности

**Date:** 2025-10-08
**Script:** lib/security_tests.sh
**PRD Version:** v4.1
**Status:** ANALYSIS COMPLETE

---

## Executive Summary

**Цель:** Тщательный анализ скрипта `lib/security_tests.sh` на соответствие текущей реализации сервиса VLESS Reality VPN v4.1.

**Основные находки:**
- ✅ **6/8 тестов** полностью соответствуют архитектуре PRD v4.1
- ⚠️ **2/8 тестов** требуют обновления для поддержки архитектуры stunnel TLS termination (v4.0+)
- 🔧 **4 критичных несоответствия** обнаружены, требуют исправления

**Общая оценка:** 75% соответствия - хорошо, но требуются улучшения

---

## Table of Contents

1. [Архитектура PRD v4.1 - Ключевые моменты](#1-архитектура-prd-v41---ключевые-моменты)
2. [Анализ тестов (TEST 1-8)](#2-анализ-тестов-test-1-8)
3. [Обнаруженные проблемы](#3-обнаруженные-проблемы)
4. [Рекомендации по исправлению](#4-рекомендации-по-исправлению)
5. [План улучшений](#5-план-улучшений)
6. [Приложение: Diff для исправлений](#6-приложение-diff-для-исправлений)

---

## 1. Архитектура PRD v4.1 - Ключевые моменты

### 1.1 stunnel TLS Termination Architecture (v4.0/v4.1)

**Архитектура:**
```
Client (TLS 1.3)
    ↓
stunnel Container (dweomer/stunnel:latest)
  - Listen: 0.0.0.0:1080 (SOCKS5 with TLS)
  - Listen: 0.0.0.0:8118 (HTTP with TLS)
  - Certificates: /etc/letsencrypt (mounted read-only)
    ↓
Xray Container (teddysun/xray:24.11.30)
  - Inbound SOCKS5: 127.0.0.1:10800 (plaintext, no TLS streamSettings)
  - Inbound HTTP: 127.0.0.1:18118 (plaintext, no TLS streamSettings)
    ↓
Internet
```

**Ключевые отличия от v3.x:**
- ❌ **v3.x:** Xray inbounds имели `streamSettings.security="tls"` на портах 1080/8118
- ✅ **v4.0+:** Xray inbounds plaintext на localhost, stunnel обрабатывает TLS

### 1.2 Proxy URI Schemes (v4.1 Bugfix)

**Правильные схемы:**
- SOCKS5: `socks5s://user:pass@domain:1080` (TLS via stunnel)
- HTTP: `https://user:pass@domain:8118` (TLS via stunnel)

**Неправильные схемы (legacy v3.x):**
- ❌ `socks5://` - plaintext, не используется
- ❌ `http://` - plaintext, не используется
- ⚠️ `socks5h://` - DNS via proxy, НЕ TLS! (часто путают)

**Примечание:** `socks5h://` обеспечивает только DNS privacy, но НЕ шифрование. Для TLS нужен `socks5s://`.

### 1.3 Docker Compose Architecture (v4.0/v4.1)

**Сервисы:**
1. **stunnel:**
   - Image: `dweomer/stunnel:latest`
   - Ports: `1080:1080`, `8118:8118`
   - Volumes:
     - `/opt/vless/config/stunnel.conf:/etc/stunnel/stunnel.conf:ro`
     - `/etc/letsencrypt:/certs:ro`
   - Depends on: `xray`

2. **xray:**
   - Image: `teddysun/xray:24.11.30`
   - Ports: `${VLESS_PORT}:${VLESS_PORT}` (default 443)
   - Volumes:
     - `/opt/vless/config:/etc/xray:ro`
   - **НЕ монтирует** `/etc/letsencrypt` (сертификаты только для stunnel)

3. **nginx:**
   - Image: `nginx:alpine`
   - Internal fallback site

### 1.4 Configuration Files (v4.1)

**stunnel.conf** (генерируется через heredoc в lib/stunnel_setup.sh):
```ini
# Global settings
foreground = yes
output = /var/log/stunnel/stunnel.log
syslog = no

# TLS 1.3 only
ciphersuites = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256

[socks5-tls]
accept = 0.0.0.0:1080
connect = vless_xray:10800
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3

[http-tls]
accept = 0.0.0.0:8118
connect = vless_xray:18118
cert = /certs/live/${DOMAIN}/fullchain.pem
key = /certs/live/${DOMAIN}/privkey.pem
sslVersion = TLSv1.3
```

**config.json (Xray)** - plaintext inbounds:
```json
{
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "protocol": "vless",
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": { ... }
      }
    },
    {
      "tag": "socks5-proxy",
      "listen": "127.0.0.1",
      "port": 10800,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [...]
      }
      // IMPORTANT: NO streamSettings section - plaintext inbound
    },
    {
      "tag": "http-proxy",
      "listen": "127.0.0.1",
      "port": 18118,
      "protocol": "http",
      "settings": {
        "accounts": [...]
      }
      // IMPORTANT: NO streamSettings section - plaintext inbound
    }
  ]
}
```

---

## 2. Анализ тестов (TEST 1-8)

### TEST 1: Reality Protocol TLS 1.3 Configuration

**Файл:** lib/security_tests.sh:428-493
**Функция:** `test_01_reality_tls_config()`

**Что проверяет:**
- Reality settings в Xray config (`.inbounds[0].streamSettings.realitySettings`)
- X25519 private key
- shortIds
- destination для TLS masquerading
- serverNames (SNI)
- Destination TLS 1.3 support

**Соответствие PRD v4.1:**
✅ **ПОЛНОСТЬЮ СООТВЕТСТВУЕТ**

**Обоснование:**
- Reality protocol используется ТОЛЬКО для VLESS inbound (порт 443)
- Не связан с proxy inbounds (SOCKS5/HTTP)
- Проверяет корректные параметры из PRD Section 2 (FR-001)
- Индекс `[0]` корректен (VLESS inbound обычно первый)

**Результат теста:** ✅ 5/5 checks PASSED (из логов)

---

### TEST 2: stunnel TLS Termination Configuration

**Файл:** lib/security_tests.sh:499-593
**Функция:** `test_02_stunnel_tls()`

**Что проверяет:**
- Существование stunnel container
- stunnel.conf configuration
- Let's Encrypt certificates
- Certificate validity and cipher support
- Ports 1080/8118 listening

**Соответствие PRD v4.1:**
✅ **СООТВЕТСТВУЕТ**, но с ⚠️ **1 проблемой**

#### ПРОБЛЕМА 1: Условие skip для stunnel tests

**Код (строки 502-505):**
```bash
if ! is_public_proxy_enabled; then
    print_skip "Public proxy not enabled - stunnel tests skipped"
    return 0
fi
```

**Функция is_public_proxy_enabled (строки 401-408):**
```bash
is_public_proxy_enabled() {
    if [[ -f "$ENV_FILE" ]]; then
        local enabled
        enabled=$(grep "^ENABLE_PUBLIC_PROXY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
        [[ "$enabled" == "true" ]] && return 0
    fi
    return 1
}
```

**Проблема:**
- Архитектура v4.0+ подразумевает, что stunnel используется ВСЕГДА когда proxy support включен
- `ENABLE_PUBLIC_PROXY` определяет режим listen для Xray inbounds (public vs localhost)
- Но stunnel TLS termination используется в ОБОИХ режимах (согласно архитектуре)

**Анализ из PRD:**
- PRD v4.0+ не содержит явного указания на то, что stunnel используется только в public mode
- Архитектура показывает stunnel как обязательный компонент для TLS termination
- Однако, PRD также упоминает "localhost-only mode" (v3.1) где proxy bind на 127.0.0.1 БЕЗ TLS

**Вывод:**
Нужно уточнить: используется ли stunnel ТОЛЬКО в public mode, или в ОБОИХ режимах?

**Рекомендация:**
Изменить условие на проверку наличия stunnel container вместо проверки ENABLE_PUBLIC_PROXY:
```bash
# Check if stunnel container exists (not necessarily running)
if ! docker ps -a --format '{{.Names}}' | grep -q "stunnel"; then
    print_skip "stunnel not configured - tests skipped"
    return 0
fi
```

**Результат теста:** ✅ 7/7 checks PASSED (из логов - stunnel работает)

---

### TEST 3: Traffic Encryption Validation

**Файл:** lib/security_tests.sh:599-732
**Функция:** `test_03_traffic_encryption()`

**Что проверяет:**
- Packet capture с tcpdump
- Отсутствие plaintext в трафике
- TLS handshakes с tshark
- Proxy connection test

**Соответствие PRD v4.1:**
⚠️ **ЧАСТИЧНО СООТВЕТСТВУЕТ** - найдены 2 проблемы

#### ПРОБЛЕМА 2: Неправильная схема подключения к localhost proxy

**Код (строки 657-664):**
```bash
else
    print_info "Public proxy not enabled, testing localhost proxy..."

    if [[ -n "$proxy_password" ]]; then
        # Test localhost proxy (should fail from remote, but we'll try)
        timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:1080" \
            -s -o /dev/null "$test_url" 2>/dev/null || true
    fi
fi
```

**Проблемы:**
1. Использует `--socks5` вместо `-x "socks5s://"` (неправильная схема)
2. Порт `127.0.0.1:1080` - это НЕ Xray порт в архитектуре v4.0+
   - stunnel слушает на `0.0.0.0:1080` (внешний интерфейс, может быть недоступен на localhost)
   - Xray слушает на `127.0.0.1:10800` (plaintext, без TLS)

**Анализ:**
- Если тест запускается НА сервере (localhost), то:
  - `127.0.0.1:1080` может работать ЕСЛИ stunnel bind на 0.0.0.0 (включая loopback)
  - Но это проверит stunnel TLS, а НЕ Xray plaintext inbound
- Если тест запускается УДАЛЕННО, то:
  - `127.0.0.1:1080` не работает (localhost удаленного клиента)
  - Нужно использовать `${domain}:1080` или `${server_ip}:1080`

**Правильный код:**
```bash
else
    print_info "Proxy support detected (localhost mode), testing local connection..."

    if [[ -n "$proxy_password" ]]; then
        # Option 1: Test Xray plaintext inbound directly (localhost only)
        print_verbose "Testing Xray plaintext SOCKS5 inbound (localhost:10800)..."
        timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:10800" \
            -s -o /dev/null "$test_url" 2>/dev/null || \
            print_warning "Xray plaintext inbound test failed (expected if test runs remotely)"

        # Option 2: Test stunnel TLS inbound (via server IP/domain)
        local server_ip
        server_ip=$(get_server_ip)
        print_verbose "Testing stunnel TLS SOCKS5 inbound (${server_ip}:1080)..."
        timeout 10 curl -x "socks5s://${test_user}:${proxy_password}@${server_ip}:1080" \
            -s -o /dev/null "$test_url" 2>/dev/null || \
            print_warning "stunnel TLS inbound test failed"
    fi
fi
```

**Результат теста:** ❌ FAIL "No test user available" (из логов - не может протестировать)

---

#### ПРОБЛЕМА 3: Public proxy test использует правильную схему, но нужна документация

**Код (строки 643-656):**
```bash
if is_public_proxy_enabled && [[ -n "$proxy_password" ]]; then
    local domain
    domain=$(get_domain)

    print_info "Testing proxy encrypted traffic via stunnel..."

    # Make request through HTTPS proxy
    if ! timeout 10 curl -x "https://${test_user}:${proxy_password}@${domain}:8118" \
        -s -o /dev/null "$test_url" 2>/dev/null; then
        print_warning "Proxy connection failed (expected if not accessible from test location)"
    else
        print_verbose "Proxy connection successful"
    fi
```

**Анализ:**
✅ **КОРРЕКТНО** - использует `https://` для HTTP proxy через stunnel (v4.1 URI scheme)

**Рекомендация:**
Добавить комментарий для ясности:
```bash
# Make request through HTTPS proxy (TLS via stunnel on port 8118)
# URI scheme: https:// indicates HTTP proxy WITH TLS encryption (stunnel v4.0+)
if ! timeout 10 curl -x "https://${test_user}:${proxy_password}@${domain}:8118" \
    -s -o /dev/null "$test_url" 2>/dev/null; then
```

**Результат теста:** ⊘ SKIP (из логов - tcpdump может отсутствовать)

---

### TEST 4: Certificate Security Validation

**Файл:** lib/security_tests.sh:738-825
**Функция:** `test_04_certificate_security()`

**Что проверяет:**
- File permissions (600 для privkey, 644/600 для fullchain)
- Certificate chain validity
- Certificate subject, issuer, SAN
- TLS connection к stunnel SOCKS5 port (1080)

**Соответствие PRD v4.1:**
✅ **ПОЛНОСТЬЮ СООТВЕТСТВУЕТ**

**Ключевые проверки:**
1. **Права доступа (строки 759-777):**
   ```bash
   local fullchain_perms
   fullchain_perms=$(stat -c "%a" "$fullchain" 2>/dev/null || echo "000")

   if [[ "$fullchain_perms" == "644" ]] || [[ "$fullchain_perms" == "600" ]]; then
       print_success "Certificate file permissions secure: $fullchain_perms"
   else
       print_warning "Certificate file permissions: $fullchain_perms (should be 644 or 600)"
   fi

   local privkey_perms
   privkey_perms=$(stat -c "%a" "$privkey" 2>/dev/null || echo "000")

   if [[ "$privkey_perms" == "600" ]]; then
       print_success "Private key file permissions secure: $privkey_perms"
   else
       print_critical "Private key file permissions insecure: $privkey_perms (MUST be 600)"
       return 1
   fi
   ```

   ✅ **СООТВЕТСТВУЕТ PRD:** Section 10 (NFR), CLAUDE.md Section 9 (File Permissions)

2. **TLS connection test (строки 815-821):**
   ```bash
   print_info "Testing TLS connection to stunnel SOCKS5 port (1080)..."

   if timeout 5 openssl s_client -connect "${domain}:1080" -tls1_3 </dev/null 2>&1 | grep -q "Verify return code: 0"; then
       print_success "TLS connection to SOCKS5 port successful (certificate valid)"
   else
       print_warning "TLS connection to SOCKS5 port failed (may not support direct TLS handshake)"
   fi
   ```

   ✅ **КОРРЕКТНО** - проверяет stunnel TLS termination на порту 1080

**Результат теста:** ⚠️ 1 WARNING + 🔥 1 CRITICAL ISSUE (из логов)
- ⚠️ Certificate file permissions: 777 (should be 644 or 600)
- 🔥 Private key file permissions insecure: 777 (MUST be 600)

**Примечание:** Тест РАБОТАЕТ КОРРЕКТНО - он ОБНАРУЖИЛ критичную проблему безопасности!

---

### TEST 5: DPI Resistance Validation

**Файл:** lib/security_tests.sh:831-910
**Функция:** `test_05_dpi_resistance()`

**Что проверяет:**
- Reality destination configuration
- SNI validation
- Port analysis с nmap
- TLS fingerprint

**Соответствие PRD v4.1:**
✅ **ПОЛНОСТЬЮ СООТВЕТСТВУЕТ**

**Обоснование:**
- Проверяет Reality protocol для VLESS inbound
- Не связан с proxy/stunnel
- Все проверки соответствуют PRD Section 2 (FR-001: Reality Configuration)

**Результат теста:** ❌ FAIL "Reality destination not configured" (из логов - config.json отсутствует)

---

### TEST 6: SSL/TLS Vulnerability Scanning

**Файл:** lib/security_tests.sh:916-1006
**Функция:** `test_06_tls_vulnerabilities()`

**Что проверяет:**
- Weak cipher suites
- Obsolete SSL/TLS versions (SSLv2, SSLv3, TLS 1.0)
- Perfect Forward Secrecy (PFS)
- Security headers

**Соответствие PRD v4.1:**
✅ **ПОЛНОСТЬЮ СООТВЕТСТВУЕТ**

**Все проверки используют:** `${domain}:8118` (HTTP proxy port через stunnel)

**Примеры:**
```bash
# Weak ciphers test (строки 936-944)
for cipher in "${weak_ciphers[@]}"; do
    if openssl s_client -connect "${domain}:8118" -cipher "$cipher" </dev/null 2>&1 | grep -q "Cipher.*$cipher"; then
        print_critical "Weak cipher supported: $cipher"
    fi
done

# SSLv2/SSLv3 test (строки 956-968)
if openssl s_client -connect "${domain}:8118" -ssl2 </dev/null 2>&1 | grep -q "SSLv2"; then
    print_critical "SSLv2 is enabled (CRITICAL VULNERABILITY)"
fi
```

✅ **КОРРЕКТНО** - проверяет stunnel TLS configuration согласно PRD Section 2 (FR-STUNNEL-001)

**Результат теста:** ✅ 6/6 checks PASSED (из логов)

---

### TEST 7: Proxy Protocol Security Validation

**Файл:** lib/security_tests.sh:1012-1111
**Функция:** `test_07_proxy_protocol_security()`

**Что проверяет:**
- Proxy authentication (password required)
- Listen addresses
- UDP disabled для SOCKS5
- Password strength

**Соответствие PRD v4.1:**
⚠️ **ЧАСТИЧНО СООТВЕТСТВУЕТ** - найдена 1 критичная проблема

#### ПРОБЛЕМА 4: Неправильная проверка listen addresses для v4.0+ архитектуры

**Код (строки 1046-1070):**
```bash
# Test 2: Check proxy listen addresses
print_info "Checking proxy listen addresses..."

if is_public_proxy_enabled; then
    # Public mode: should listen on 0.0.0.0 with stunnel in front
    print_info "Public proxy mode detected"

    # Verify stunnel is handling external connections
    if docker ps --format '{{.Names}}' | grep -q "stunnel"; then
        print_success "stunnel container running (TLS termination active)"
    else
        print_critical "stunnel container not running - PUBLIC PROXY UNPROTECTED"
        return 1
    fi

else
    # Localhost mode: should listen on 127.0.0.1 only
    local socks5_listen
    socks5_listen=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$socks5_listen" == "127.0.0.1" ]]; then
        print_success "SOCKS5 proxy bound to localhost only (secure)"
    else
        print_warning "SOCKS5 proxy listen address: $socks5_listen (should be 127.0.0.1 for localhost mode)"
    fi
fi
```

**Проблема:**
Архитектура v4.0+ изменилась! Согласно PRD:

**Public mode (v4.0+):**
- stunnel слушает на `0.0.0.0:1080/8118` (external, with TLS)
- Xray слушает на `127.0.0.1:10800/18118` (localhost, plaintext)

**Localhost mode (v3.1):**
- Xray слушает на `127.0.0.1:1080/8118` (localhost, БЕЗ TLS)
- stunnel НЕ используется (?)

**Тест проверяет:**
- Public mode: Только наличие stunnel container (НЕ проверяет что Xray на localhost!)
- Localhost mode: Что Xray слушает на 127.0.0.1 (корректно)

**Что ДОЛЖЕН проверять тест в v4.0+:**
- Public mode:
  1. ✅ stunnel container running
  2. ✅ stunnel слушает на 0.0.0.0:1080/8118
  3. ❌ **ОТСУТСТВУЕТ:** Xray inbounds БЕЗ streamSettings (plaintext)
  4. ❌ **ОТСУТСТВУЕТ:** Xray inbounds слушают на 127.0.0.1:10800/18118
- Localhost mode:
  1. ✅ Xray inbounds слушают на 127.0.0.1:1080/8118
  2. ❓ stunnel НЕ используется (нужно уточнить в PRD)

**Правильный код для public mode:**
```bash
if is_public_proxy_enabled; then
    print_info "Public proxy mode detected (v4.0+ stunnel architecture)"

    # Check 1: stunnel container running
    if ! docker ps --format '{{.Names}}' | grep -q "stunnel"; then
        print_critical "stunnel container not running - PUBLIC PROXY UNPROTECTED"
        return 1
    fi
    print_success "stunnel container running (TLS termination active)"

    # Check 2: stunnel listening on external ports
    if ss -tlnp | grep -q "0.0.0.0:1080"; then
        print_success "stunnel SOCKS5 port listening on external interface (0.0.0.0:1080)"
    else
        print_failure "stunnel SOCKS5 port not listening on 0.0.0.0:1080"
        return 1
    fi

    if ss -tlnp | grep -q "0.0.0.0:8118"; then
        print_success "stunnel HTTP port listening on external interface (0.0.0.0:8118)"
    else
        print_failure "stunnel HTTP port not listening on 0.0.0.0:8118"
        return 1
    fi

    # Check 3: Xray inbounds are plaintext (no TLS streamSettings)
    local socks5_security
    socks5_security=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .streamSettings.security // "none"' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$socks5_security" == "none" ]]; then
        print_success "Xray SOCKS5 inbound is plaintext (stunnel handles TLS)"
    else
        print_warning "Xray SOCKS5 inbound has TLS streamSettings: $socks5_security (should be none in v4.0+)"
    fi

    # Check 4: Xray inbounds listen on localhost
    local socks5_listen
    socks5_listen=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$socks5_listen" == "127.0.0.1" ]]; then
        print_success "Xray SOCKS5 inbound bound to localhost (secure, stunnel handles external)"
    else
        print_warning "Xray SOCKS5 inbound listen address: $socks5_listen (should be 127.0.0.1 in v4.0+)"
    fi

    # Check 5: Xray inbound ports are plaintext ports (10800/18118, not 1080/8118)
    local socks5_port
    socks5_port=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .port' "$XRAY_CONFIG" 2>/dev/null)

    if [[ "$socks5_port" == "10800" ]]; then
        print_success "Xray SOCKS5 inbound using plaintext port (10800)"
    elif [[ "$socks5_port" == "1080" ]]; then
        print_warning "Xray SOCKS5 inbound using stunnel port (1080) - may conflict with stunnel"
    else
        print_info "Xray SOCKS5 inbound port: $socks5_port"
    fi
```

**Результат теста:** ⊘ SKIP "Proxy support not enabled" (из логов - config.json отсутствует, не может проверить)

---

### TEST 8: Data Leak Detection

**Файл:** lib/security_tests.sh:1117-1211
**Функция:** `test_08_data_leak_detection()`

**Что проверяет:**
- Exposed configuration files
- Default/weak credentials
- Sensitive data in logs
- DNS configuration

**Соответствие PRD v4.1:**
✅ **ПОЛНОСТЬЮ СООТВЕТСТВУЕТ**

**Обоснование:**
- Общие проверки безопасности
- Не зависят от архитектуры proxy/stunnel
- Соответствуют NFR-SEC-001 (PRD Section 10)

**Результат теста:** ✅ 4/4 checks PASSED + ⚠️ 1 WARNING (из логов)
- ✅ No exposed configuration files detected
- ✅ No default/weak usernames detected
- ✅ No obvious data leaks in container logs
- ⚠️ No DNS configuration in Xray (may use system DNS - potential leak)

---

## 3. Обнаруженные проблемы

### Сводная таблица

| # | Проблема | Тест | Severity | Строки | Статус |
|---|----------|------|----------|--------|--------|
| 1 | Условие skip для stunnel tests может быть неправильным | TEST 2 | MEDIUM | 502-505 | Требует уточнения PRD |
| 2 | Неправильная схема подключения к localhost proxy | TEST 3 | HIGH | 657-664 | Требует исправления |
| 3 | Public proxy test корректен, но нужна документация | TEST 3 | LOW | 643-656 | Добавить комментарии |
| 4 | Неправильная проверка listen addresses для v4.0+ | TEST 7 | HIGH | 1046-1070 | Требует исправления |

---

### Детализация проблем

#### ПРОБЛЕМА 1: Условие skip для stunnel tests (MEDIUM)

**Локация:** lib/security_tests.sh:502-505

**Текущий код:**
```bash
if ! is_public_proxy_enabled; then
    print_skip "Public proxy not enabled - stunnel tests skipped"
    return 0
fi
```

**Вопрос:** Используется ли stunnel ТОЛЬКО в public mode?

**Анализ PRD:**
- v3.1: "Localhost-only mode" - proxy bind на 127.0.0.1, TLS НЕ упоминается
- v3.3: "Mandatory TLS encryption for public proxies" - TLS обязателен для PUBLIC mode
- v4.0: "stunnel TLS termination architecture" - stunnel как ОТДЕЛЬНЫЙ компонент

**Интерпретация:**
- **Вариант A:** stunnel используется ТОЛЬКО в public mode (TLS для внешних подключений)
- **Вариант B:** stunnel используется ВСЕГДА когда proxy enabled (TLS везде)

**Рекомендация:**
Уточнить в PRD. Временно - изменить условие на проверку наличия stunnel container:
```bash
if ! docker ps -a --format '{{.Names}}' | grep -q "stunnel"; then
    print_skip "stunnel not configured - tests skipped"
    return 0
fi
```

---

#### ПРОБЛЕМА 2: Неправильная схема подключения к localhost proxy (HIGH)

**Локация:** lib/security_tests.sh:657-664

**Текущий код:**
```bash
else
    print_info "Public proxy not enabled, testing localhost proxy..."

    if [[ -n "$proxy_password" ]]; then
        # Test localhost proxy (should fail from remote, but we'll try)
        timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:1080" \
            -s -o /dev/null "$test_url" 2>/dev/null || true
    fi
fi
```

**Проблемы:**
1. Использует `--socks5` вместо корректной схемы (`-x "socks5s://"` или `-x "socks5://"`)
2. Порт `127.0.0.1:1080` может быть недоступен (stunnel на 0.0.0.0 или Xray на 10800)

**Правильный подход:**
```bash
else
    print_info "Proxy support detected (localhost mode), testing connections..."

    if [[ -n "$proxy_password" ]]; then
        # Determine test location (local or remote)
        local server_ip
        server_ip=$(get_server_ip)
        local client_ip
        client_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")

        if [[ "$server_ip" == "$client_ip" ]] || [[ "$client_ip" == "unknown" ]]; then
            # Test is running ON the server - can test localhost
            print_verbose "Test running locally - testing Xray plaintext inbound"

            # Test Xray plaintext SOCKS5 (localhost:10800)
            timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:10800" \
                -s -o /dev/null "$test_url" 2>/dev/null && \
                print_success "Xray plaintext SOCKS5 inbound working" || \
                print_warning "Xray plaintext SOCKS5 inbound test failed"
        else
            # Test is running REMOTELY - cannot test localhost, test stunnel instead
            print_verbose "Test running remotely - testing stunnel TLS inbound"

            # Test stunnel TLS SOCKS5 (domain:1080 or server_ip:1080)
            local domain
            domain=$(get_domain)
            local test_host="${domain:-$server_ip}"

            timeout 10 curl -x "socks5s://${test_user}:${proxy_password}@${test_host}:1080" \
                -s -o /dev/null "$test_url" 2>/dev/null && \
                print_success "stunnel TLS SOCKS5 inbound working" || \
                print_warning "stunnel TLS SOCKS5 inbound test failed"
        fi
    fi
fi
```

**Impact:** HIGH - неправильный тест может давать false negative/positive результаты

---

#### ПРОБЛЕМА 3: Public proxy test корректен, но нужна документация (LOW)

**Локация:** lib/security_tests.sh:643-656

**Текущий код:**
```bash
# Make request through HTTPS proxy
if ! timeout 10 curl -x "https://${test_user}:${proxy_password}@${domain}:8118" \
    -s -o /dev/null "$test_url" 2>/dev/null; then
```

**Рекомендация:**
Добавить комментарий для ясности:
```bash
# Make request through HTTPS proxy (TLS via stunnel on port 8118)
# URI scheme: https:// indicates HTTP proxy WITH TLS encryption (stunnel v4.0+)
# Architecture: Client → stunnel:8118 (TLS) → Xray:18118 (plaintext) → Internet
if ! timeout 10 curl -x "https://${test_user}:${proxy_password}@${domain}:8118" \
    -s -o /dev/null "$test_url" 2>/dev/null; then
```

**Impact:** LOW - код работает корректно, нужна только документация

---

#### ПРОБЛЕМА 4: Неправильная проверка listen addresses для v4.0+ (HIGH)

**Локация:** lib/security_tests.sh:1046-1070

**Текущий код:**
```bash
if is_public_proxy_enabled; then
    # Public mode: should listen on 0.0.0.0 with stunnel in front
    print_info "Public proxy mode detected"

    # Verify stunnel is handling external connections
    if docker ps --format '{{.Names}}' | grep -q "stunnel"; then
        print_success "stunnel container running (TLS termination active)"
    else
        print_critical "stunnel container not running - PUBLIC PROXY UNPROTECTED"
        return 1
    fi
```

**Что НЕ проверяется:**
- ❌ Xray inbounds БЕЗ streamSettings (plaintext)
- ❌ Xray inbounds слушают на 127.0.0.1:10800/18118
- ❌ stunnel слушает на 0.0.0.0:1080/8118

**Почему это критично:**
Если Xray случайно настроен с TLS streamSettings и слушает на 0.0.0.0 (legacy v3.x конфигурация), то:
- Безопасность НЕ нарушена (TLS есть)
- Но архитектура неправильная (дубликат TLS: stunnel + Xray)
- Performance overhead (двойное TLS шифрование)

**Правильный тест (см. детализацию в TEST 7 выше):**
```bash
# Check 1: stunnel container running
# Check 2: stunnel listening on 0.0.0.0:1080/8118
# Check 3: Xray inbounds are plaintext (no TLS streamSettings)
# Check 4: Xray inbounds listen on 127.0.0.1
# Check 5: Xray inbound ports are plaintext ports (10800/18118)
```

**Impact:** HIGH - неправильная архитектура может остаться незамеченной

---

## 4. Рекомендации по исправлению

### 4.1 Приоритеты

| Приоритет | Проблемы | Action | Timeline |
|-----------|----------|--------|----------|
| **P0 (CRITICAL)** | ПРОБЛЕМА 4 | Исправить TEST 7 | Немедленно |
| **P1 (HIGH)** | ПРОБЛЕМА 2 | Исправить TEST 3 | В течение недели |
| **P2 (MEDIUM)** | ПРОБЛЕМА 1 | Уточнить PRD + исправить | В течение месяца |
| **P3 (LOW)** | ПРОБЛЕМА 3 | Добавить комментарии | По возможности |

### 4.2 Последовательность исправлений

**Шаг 1: Исправить ПРОБЛЕМУ 4 (TEST 7)**

**Файл:** lib/security_tests.sh
**Функция:** test_07_proxy_protocol_security()
**Строки:** 1046-1070

**Изменения:**
1. Добавить проверку stunnel listening ports (0.0.0.0:1080/8118)
2. Добавить проверку Xray plaintext inbounds (no streamSettings)
3. Добавить проверку Xray localhost binding (127.0.0.1)
4. Добавить проверку Xray plaintext ports (10800/18118)

**Детальный код:** См. раздел TEST 7 выше.

---

**Шаг 2: Исправить ПРОБЛЕМУ 2 (TEST 3)**

**Файл:** lib/security_tests.sh
**Функция:** test_03_traffic_encryption()
**Строки:** 657-664

**Изменения:**
1. Определить локацию теста (локально или удаленно)
2. Локально: тестировать Xray plaintext inbound (127.0.0.1:10800)
3. Удаленно: тестировать stunnel TLS inbound (domain:1080)

**Детальный код:** См. раздел TEST 3 выше.

---

**Шаг 3: Уточнить PRD + исправить ПРОБЛЕМУ 1 (TEST 2)**

**Действия:**
1. Уточнить в PRD: используется ли stunnel ТОЛЬКО в public mode?
2. Обновить TEST 2 в соответствии с уточненной архитектурой

**Варианты решения:**
- **Вариант A (stunnel ТОЛЬКО public):** Оставить текущую логику
- **Вариант B (stunnel ВСЕГДА):** Изменить на проверку наличия stunnel container

---

**Шаг 4: Добавить комментарии (ПРОБЛЕМА 3)**

**Файл:** lib/security_tests.sh
**Функция:** test_03_traffic_encryption()
**Строки:** 643-656

**Изменения:**
Добавить поясняющие комментарии к строке 650.

---

### 4.3 Валидация исправлений

**После каждого исправления:**

1. **Unit test:**
   ```bash
   # Проверить синтаксис bash
   bash -n lib/security_tests.sh

   # Проверить jq queries
   jq '.inbounds[] | select(.tag == "socks5-proxy")' config/config.json
   ```

2. **Integration test:**
   ```bash
   # Запустить полный тест на тестовом сервере
   sudo lib/security_tests.sh --verbose
   ```

3. **Manual review:**
   - Проверить логи тестов
   - Убедиться, что все новые проверки работают
   - Проверить false positive/negative

4. **Documentation:**
   - Обновить комментарии в коде
   - Обновить CHANGELOG.md
   - Обновить README.md (если требуется)

---

## 5. План улучшений

### 5.1 Краткосрочные улучшения (1-2 недели)

1. ✅ **Исправить ПРОБЛЕМУ 4** (TEST 7 - v4.0+ architecture validation)
2. ✅ **Исправить ПРОБЛЕМУ 2** (TEST 3 - localhost proxy test)
3. ✅ **Добавить комментарии** (ПРОБЛЕМА 3)

### 5.2 Среднесрочные улучшения (1 месяц)

1. ✅ **Уточнить PRD** (stunnel usage modes)
2. ✅ **Исправить ПРОБЛЕМУ 1** (TEST 2 - skip condition)
3. ✅ **Добавить новые тесты:**
   - Проверка heredoc config generation (v4.1)
   - Проверка proxy URI schemes (socks5s://, https://)
   - Проверка stunnel cipher suites (TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256)

### 5.3 Долгосрочные улучшения (3 месяца)

1. ✅ **Автоматизация тестов** в CI/CD pipeline
2. ✅ **Benchmark тесты** для performance validation
3. ✅ **Мониторинг** security metrics в production
4. ✅ **Регулярные security audits** (quarterly)

---

## 6. Приложение: Diff для исправлений

### 6.1 ПРОБЛЕМА 4: Исправление TEST 7

```diff
--- a/lib/security_tests.sh
+++ b/lib/security_tests.sh
@@ -1043,27 +1043,92 @@ test_07_proxy_protocol_security() {
     fi

     # Test 2: Check proxy listen addresses
     print_info "Checking proxy listen addresses..."

     if is_public_proxy_enabled; then
-        # Public mode: should listen on 0.0.0.0 with stunnel in front
-        print_info "Public proxy mode detected"
+        # Public mode (v4.0+): stunnel handles TLS on external ports, Xray uses plaintext localhost
+        print_info "Public proxy mode detected (v4.0+ stunnel architecture)"

-        # Verify stunnel is handling external connections
-        if docker ps --format '{{.Names}}' | grep -q "stunnel"; then
+        # Check 1: stunnel container running
+        if ! docker ps --format '{{.Names}}' | grep -q "stunnel"; then
+            print_critical "stunnel container not running - PUBLIC PROXY UNPROTECTED"
+            return 1
+        fi
+        print_success "stunnel container running (TLS termination active)"
+
+        # Check 2: stunnel listening on external ports
+        if ss -tlnp | grep -q "0.0.0.0:1080"; then
+            print_success "stunnel SOCKS5 port listening on external interface (0.0.0.0:1080)"
+        else
+            print_failure "stunnel SOCKS5 port not listening on 0.0.0.0:1080"
+            return 1
+        fi
+
+        if ss -tlnp | grep -q "0.0.0.0:8118"; then
+            print_success "stunnel HTTP port listening on external interface (0.0.0.0:8118)"
+        else
+            print_failure "stunnel HTTP port not listening on 0.0.0.0:8118"
+            return 1
+        fi
+
+        # Check 3: Xray inbounds are plaintext (no TLS streamSettings)
+        local socks5_security
+        socks5_security=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .streamSettings.security // "none"' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$socks5_security" == "none" ]]; then
+            print_success "Xray SOCKS5 inbound is plaintext (stunnel handles TLS)"
+        else
+            print_warning "Xray SOCKS5 inbound has TLS streamSettings: $socks5_security (should be none in v4.0+)"
+        fi
+
+        local http_security
+        http_security=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .streamSettings.security // "none"' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$http_security" == "none" ]]; then
+            print_success "Xray HTTP inbound is plaintext (stunnel handles TLS)"
+        else
+            print_warning "Xray HTTP inbound has TLS streamSettings: $http_security (should be none in v4.0+)"
+        fi
+
+        # Check 4: Xray inbounds listen on localhost
+        local socks5_listen
+        socks5_listen=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$socks5_listen" == "127.0.0.1" ]]; then
             print_success "stunnel container running (TLS termination active)"
         else
-            print_critical "stunnel container not running - PUBLIC PROXY UNPROTECTED"
+            print_warning "Xray SOCKS5 inbound listen address: $socks5_listen (should be 127.0.0.1 in v4.0+)"
+        fi
+
+        local http_listen
+        http_listen=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$http_listen" == "127.0.0.1" ]]; then
+            print_success "Xray HTTP inbound bound to localhost (secure, stunnel handles external)"
+        else
+            print_warning "Xray HTTP inbound listen address: $http_listen (should be 127.0.0.1 in v4.0+)"
+        fi
+
+        # Check 5: Xray inbound ports are plaintext ports (10800/18118, not 1080/8118)
+        local socks5_port
+        socks5_port=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .port' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$socks5_port" == "10800" ]]; then
+            print_success "Xray SOCKS5 inbound using plaintext port (10800)"
+        elif [[ "$socks5_port" == "1080" ]]; then
+            print_warning "Xray SOCKS5 inbound using stunnel port (1080) - may conflict with stunnel"
+        else
+            print_info "Xray SOCKS5 inbound port: $socks5_port"
+        fi
+
+        local http_port
+        http_port=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .port' "$XRAY_CONFIG" 2>/dev/null)
+
+        if [[ "$http_port" == "18118" ]]; then
+            print_success "Xray HTTP inbound using plaintext port (18118)"
+        elif [[ "$http_port" == "8118" ]]; then
+            print_warning "Xray HTTP inbound using stunnel port (8118) - may conflict with stunnel"
+        else
+            print_info "Xray HTTP inbound port: $http_port"
-            return 1
         fi

     else
```

### 6.2 ПРОБЛЕМА 2: Исправление TEST 3

```diff
--- a/lib/security_tests.sh
+++ b/lib/security_tests.sh
@@ -654,13 +654,44 @@ test_03_traffic_encryption() {
             print_verbose "Proxy connection successful"
         fi
     else
-        print_info "Public proxy not enabled, testing localhost proxy..."
+        print_info "Proxy support detected (localhost mode), testing connections..."

         if [[ -n "$proxy_password" ]]; then
-            # Test localhost proxy (should fail from remote, but we'll try)
-            timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:1080" \
-                -s -o /dev/null "$test_url" 2>/dev/null || true
+            # Determine test location (local or remote)
+            local server_ip
+            server_ip=$(get_server_ip)
+            local client_ip
+            client_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
+
+            if [[ "$server_ip" == "$client_ip" ]] || [[ "$client_ip" == "unknown" ]]; then
+                # Test is running ON the server - can test localhost
+                print_verbose "Test running locally - testing Xray plaintext inbound"
+
+                # Test Xray plaintext SOCKS5 (localhost:10800)
+                timeout 5 curl --socks5 "${test_user}:${proxy_password}@127.0.0.1:10800" \
+                    -s -o /dev/null "$test_url" 2>/dev/null && \
+                    print_success "Xray plaintext SOCKS5 inbound working" || \
+                    print_warning "Xray plaintext SOCKS5 inbound test failed"
+            else
+                # Test is running REMOTELY - cannot test localhost, test stunnel instead
+                print_verbose "Test running remotely - testing stunnel TLS inbound"
+
+                # Test stunnel TLS SOCKS5 (domain:1080 or server_ip:1080)
+                local domain
+                domain=$(get_domain)
+                local test_host="${domain:-$server_ip}"
+
+                # Note: Using socks5s:// scheme for TLS connection (v4.1)
+                timeout 10 curl -x "socks5s://${test_user}:${proxy_password}@${test_host}:1080" \
+                    -s -o /dev/null "$test_url" 2>/dev/null && \
+                    print_success "stunnel TLS SOCKS5 inbound working" || \
+                    print_warning "stunnel TLS SOCKS5 inbound test failed (expected if firewall blocks external access)"
+            fi
         fi
     fi
```

---

**END OF SECURITY_TESTS_ANALYSIS.md**

**Version:** 1.0
**Last Updated:** 2025-10-08
**Author:** Claude Code Analysis
**Status:** ✅ COMPLETE - Ready for review and implementation

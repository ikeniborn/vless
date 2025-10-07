# CLAUDE.md Update Plan: v3.1 → v4.1

**Дата:** 2025-10-07
**Цель:** Актуализировать PART II с учетом реальной реализации v4.1
**Принцип:** Только критически важные изменения, не раздувать контекст

---

## КРИТИЧЕСКИЕ ИЗМЕНЕНИЯ

### 1. Project Overview (Section 6)

**Текущее:**
```
**Version:** 3.1 (with Dual Proxy Support)
**Proxy Innovation (v3.1):**
Localhost-only SOCKS5 and HTTP proxies...
```

**Новое:**
```
**Version:** 4.1 (stunnel TLS Termination + Heredoc Config Generation)
**Architecture Evolution:**
- v3.1: Dual proxy support (SOCKS5 + HTTP) with localhost binding
- v4.0: stunnel TLS termination (separation of concerns)
- v4.1: Heredoc config generation (no templates/, simplified dependencies)

**Key Innovation (v4.0+):**
stunnel handles TLS termination for proxy connections:
- Client → stunnel (TLS 1.3, ports 1080/8118) → Xray (plaintext, ports 10800/18118) → Internet
- Separation of concerns: stunnel = TLS layer, Xray = proxy logic
- Simpler Xray config (no TLS streamSettings)
- Proxy URIs use `https://` and `socks5s://` for TLS connections
```

---

### 2. Critical System Parameters (Section 7)

**Добавить после "Container Images":**

```yaml
Container Images (FIXED VERSIONS):
  xray: "teddysun/xray:24.11.30"
  nginx: "nginx:alpine"
  stunnel: "dweomer/stunnel:latest"  # NEW in v4.0: TLS termination
```

**Добавить после "Protocol Configuration":**

```yaml
### stunnel TLS Termination (NEW in v4.0)

Architecture:
  client_connection: "TLS 1.3 encrypted (ports 1080/8118)"
  stunnel_to_xray: "Plaintext (localhost ports 10800/18118)"
  benefit: "Separation of concerns (stunnel=TLS, Xray=proxy)"

stunnel Configuration:
  tls_version: "TLSv1.3"                    # Only TLS 1.3 allowed
  ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
  certificates: "/etc/letsencrypt (shared with VLESS)"
  listen: "0.0.0.0:1080, 0.0.0.0:8118"
  forward_to: "vless_xray:10800, vless_xray:18118"
  config_generation: "heredoc in lib/stunnel_setup.sh (v4.1)"  # No templates/

Xray Inbound Changes (v4.0):
  socks5:
    old_v3: "listen: 0.0.0.0:1080, security: tls"
    new_v4: "listen: 127.0.0.1:10800, security: none"  # Plaintext, stunnel handles TLS
  http:
    old_v3: "listen: 0.0.0.0:8118, security: tls"
    new_v4: "listen: 127.0.0.1:18118, security: none"

Proxy URI Schemes (v4.1 fix):
  http_proxy: "https://user:pass@domain:8118"     # TLS via stunnel
  socks5_proxy: "socks5s://user:pass@domain:1080" # TLS via stunnel
  note: "Scheme 's' suffix = SSL/TLS (https, socks5s)"
```

---

### 3. Installation Path (Section 7)

**Обновить:**

```diff
File Permissions:
  config.json:         "600"
+ stunnel.conf:        "600"        # NEW in v4.0: stunnel TLS config
  users.json:          "600"
  reality_keys.json:   "600"
  .env:                "600"
  docker-compose.yml:  "644"
  scripts/*.sh:        "755"

- Client Config Files (NEW in v3.1):
+ Client Config Files (v3.1+, URI schemes fixed in v4.1):
  socks5_config.txt:       "600"
  http_config.txt:         "600"
+ # NOTE: Uses https:// and socks5s:// for TLS (v4.1 fix)
```

---

### 4. Project Structure (Section 8)

**Production Structure - добавить:**

```diff
/opt/vless/
├── config/                         # 700, owner: root
│   ├── config.json                 # 600 - Xray config (3 inbounds, plaintext proxy)
+│   ├── stunnel.conf                # 600 - stunnel TLS termination config (v4.0+)
│   ├── users.json                  # 600 - User database
│   └── reality_keys.json           # 600 - X25519 key pair
```

**Примечание:**
```
v4.0: stunnel.conf.template → envsubst → stunnel.conf
v4.1: heredoc in lib/stunnel_setup.sh → stunnel.conf (no templates/)
```

---

### 5. FR-012: Proxy Server Integration (Section 9)

**Обновить заголовок:**

```diff
- ### FR-012: Proxy Server Integration (CRITICAL - Priority 1) - NEW in v3.1
+ ### FR-012: Proxy Server Integration (CRITICAL - Priority 1) - v3.1, TLS via stunnel v4.0+
```

**Добавить в "Implementation":**

```yaml
TLS Termination (v4.0+):
  method: "stunnel separate container"
  architecture: "Client (TLS) → stunnel → Xray (plaintext) → Internet"
  benefits:
    - Xray config simplified (no TLS streamSettings)
    - Mature TLS stack (stunnel 20+ years production)
    - Separate logs for debugging
    - Certificate management centralized

Config Generation (v4.1):
  method: "heredoc in lib/stunnel_setup.sh"
  previous_v4.0: "templates/stunnel.conf.template + envsubst"
  change_rationale: "Unified with Xray/docker-compose generation (all heredoc)"
  dependencies_removed: "envsubst (GNU gettext)"
```

**Обновить URI schemes:**

```diff
Credential Management:
  password_generation: "openssl rand -hex 8"
  password_storage: "users.json v1.1 (proxy_password field)"
  single_password: true

- Config File Export (5 formats per user):
+ Config File Export (5 formats per user, v4.1 URI fix):
  - socks5_config.txt        # socks5s://user:pass@domain:1080 (TLS)
  - http_config.txt          # https://user:pass@domain:8118 (TLS)
  - vscode_settings.json
  - docker_daemon.json
  - bash_exports.sh

+ Proxy URI Schemes Explained:
+   http://   - Plaintext HTTP (NOT USED, localhost-only deprecated)
+   https://  - HTTP with TLS (v4.0+, stunnel termination) ✅
+   socks5:// - Plaintext SOCKS5 (NOT USED, localhost-only deprecated)
+   socks5s://- SOCKS5 with TLS (v4.0+, stunnel termination) ✅
+   socks5h://- SOCKS5 with DNS via proxy (NOT a TLS replacement!)
```

---

### 6. Workflow Integration (Section 9, FR-012)

**Обновить примеры команд:**

```diff
# User creation (auto-generates proxy password + configs)
sudo vless-user add alice
- # Output: UUID + proxy password + 8 config files
+ # Output: UUID + proxy password + 8 config files (VLESS + 5 proxy configs)
+ # Proxy configs use https:// and socks5s:// URIs (v4.1 fix)

# Show proxy credentials
sudo vless-user show-proxy alice
- # Output: SOCKS5/HTTP URIs + usage examples
+ # Output:
+ #   SOCKS5: socks5s://alice:PASSWORD@domain:1080
+ #   HTTP:   https://alice:PASSWORD@domain:8118
```

---

## УДАЛИТЬ / НЕ ДОБАВЛЯТЬ

**Не добавлять из PRD.md (неактуально):**

1. ❌ FR-TEMPLATE-001 (templates/ removed in v4.1)
2. ❌ FR-TLS-001 (DEPRECATED, TLS now in stunnel)
3. ❌ envsubst зависимость (removed in v4.1)
4. ❌ Подробности про template-based генерацию

**Причина:** v4.1 использует heredoc, templates/ удалена, это важная деталь.

---

## РАЗМЕР ИЗМЕНЕНИЙ

**Добавить:**
- ~80 строк в секцию 7 (stunnel architecture)
- ~30 строк в секцию 8 (project structure)
- ~40 строк в секцию 9 (FR-012 updates)

**Итого:** ~150 строк (компактно, только критическое)

**Принцип:** Каждое изменение критически важно для понимания v4.0/v4.1 архитектуры.

---

## ПРИОРИТЕТ ИЗМЕНЕНИЙ

**ВЫСОКИЙ (обязательно):**
1. ✅ Version: 3.1 → 4.1
2. ✅ stunnel architecture в секцию 7
3. ✅ Proxy URI schemes (https://, socks5s://)
4. ✅ Installation Path (stunnel.conf, no templates/)

**СРЕДНИЙ (желательно):**
5. ✅ FR-012 updates (TLS termination details)
6. ✅ Config generation method (heredoc v4.1)

**НИЗКИЙ (опционально):**
7. Project Structure примечание про v4.0 vs v4.1

---

**Следующий шаг:** Применить изменения к CLAUDE.md

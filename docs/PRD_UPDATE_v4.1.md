# PRD Update: v4.0 → v4.1
## Список расхождений между PRD и реальной реализацией

**Дата:** 2025-10-07
**Автор:** Analysis Report
**Цель:** Привести PRD в соответствие с текущей реализацией v4.0

---

## 🔴 КРИТИЧЕСКИЕ РАСХОЖДЕНИЯ (HIGH PRIORITY)

### 1. FR-TEMPLATE-001: Неполная реализация template-based конфигурации

**Расположение:** PRD строки 288-351

**Проблема:**
- PRD утверждает что ВСЕ конфиги генерируются из templates
- Реально реализован только `stunnel.conf.template`
- Xray config и docker-compose.yml генерируются inline (heredoc)

**Текущее состояние:**
```
templates/
└── stunnel.conf.template  ✅ (реализовано)
```

**Что в PRD (НЕВЕРНО):**
```
templates/
├── stunnel.conf.template     ✅
├── xray_config.json.template ❌ НЕТ
└── docker-compose.yml.template ❌ НЕТ
```

**Исправление:**
```diff
### FR-TEMPLATE-001: Template-Based Configuration

**Required Templates:**

| Template File | Purpose | Status |
|---------------|---------|--------|
- | `stunnel.conf.template` | stunnel TLS configuration | `${DOMAIN}` |
+ | `stunnel.conf.template` | stunnel TLS configuration | ✅ IMPLEMENTED |
- | `xray_config.json.template` | Xray full configuration | `${VLESS_PORT}`, `${DOMAIN}`, `${DEST_SITE}` |
+ | ~~`xray_config.json.template`~~ | ~~Xray configuration~~ | ❌ NOT IMPLEMENTED (inline heredoc in orchestrator.sh) |
- | `docker-compose.yml.template` | Container orchestration | `${VLESS_PORT}`, `${DOMAIN}`, `${ENABLE_PUBLIC_PROXY}` |
+ | ~~`docker-compose.yml.template`~~ | ~~Container orchestration~~ | ❌ NOT IMPLEMENTED (inline heredoc) |

**Rationale for partial implementation:**
- stunnel config simple and static (ideal for template)
- Xray config complex with dynamic user arrays (heredoc more maintainable)
- docker-compose has conditional logic (heredoc easier than template)
```

---

### 2. FR-TLS-001: DEPRECATED раздел не удален

**Расположение:** PRD строки 354-397

**Проблема:**
- Раздел помечен "DEPRECATED in v4.0 - See FR-STUNNEL-001"
- НО содержит примеры Xray config с TLS в streamSettings
- Может ввести в заблуждение читателей

**Устаревший пример:**
```json
"streamSettings": {
  "network": "tcp",
  "security": "tls",  // ❌ v4.0 НЕ использует это (stunnel handles TLS)
  "tlsSettings": {...}
}
```

**Исправление (OPTION A - удалить):**
```diff
- ### FR-TLS-001: TLS Encryption для SOCKS5 Inbound (DEPRECATED in v4.0 - See FR-STUNNEL-001)
- ...весь раздел...
```

**Исправление (OPTION B - переместить в Legacy):**
```diff
+ ## Appendix A: Legacy v3.x Configuration
+
+ ### A.1 v3.x TLS in Xray (Replaced by stunnel in v4.0)
+
+ **NOTE:** This configuration is DEPRECATED. v4.0 uses stunnel for TLS termination.
+ For current implementation, see FR-STUNNEL-001.
```

**Рекомендация:** OPTION A (удалить полностью)

---

### 3. File Structure: Неправильное описание xray_config.json

**Расположение:** PRD строки 1218-1264

**Проблема:**
```
/opt/vless/config/
├── xray_config.json        # 3 inbounds with TLS streamSettings ←MODIFIED
│                           # SOCKS5/HTTP: streamSettings.security="tls"
```

**Реальность v4.0:**
- Xray config НЕ содержит TLS streamSettings для proxy inbounds
- TLS обрабатывается stunnel контейнером
- Xray слушает на localhost:10800/18118 (plaintext)

**Исправление:**
```diff
/opt/vless/
├── config/
- │   ├── xray_config.json        # 3 inbounds with TLS streamSettings ←MODIFIED
- │   │                           # SOCKS5/HTTP: streamSettings.security="tls"
+ │   ├── xray_config.json        # 3 inbounds: VLESS (Reality), SOCKS5 (plaintext), HTTP (plaintext)
+ │   │                           # SOCKS5/HTTP listen on 127.0.0.1:10800/18118 (stunnel handles TLS)
+ │   ├── stunnel.conf            # NEW in v4.0: TLS termination config
  │   └── users.json              # v1.1 with proxy_password (32 chars)
```

---

### 4. Docker Compose: Отсутствует stunnel сервис

**Расположение:** PRD строки 1268-1313

**Проблема:**
- PRD показывает docker-compose БЕЗ stunnel сервиса
- Показывает монтирование `/etc/letsencrypt` в Xray (v3.x поведение)
- v4.0 монтирует сертификаты в stunnel, НЕ в Xray

**Устаревший пример:**
```yaml
xray:
  volumes:
    - /opt/vless/config:/etc/xray:ro
    - /etc/letsencrypt:/etc/xray/certs:ro  # ❌ v4.0 НЕ использует это
```

**Исправление:**
```diff
version: '3.8'

services:
+ stunnel:
+   image: dweomer/stunnel:latest
+   container_name: vless_stunnel
+   restart: unless-stopped
+   ports:
+     - "1080:1080"   # SOCKS5 with TLS
+     - "8118:8118"   # HTTP with TLS
+   volumes:
+     - /opt/vless/config/stunnel.conf:/etc/stunnel/stunnel.conf:ro
+     - /etc/letsencrypt:/certs:ro  # Let's Encrypt certificates
+   networks:
+     - vless_reality_net
+   depends_on:
+     - xray

  xray:
    image: teddysun/xray:24.11.30
    container_name: vless_xray
    restart: unless-stopped
-   network_mode: host
+   networks:
+     - vless_reality_net
    volumes:
      - /opt/vless/config:/etc/xray:ro
-     - /etc/letsencrypt:/etc/xray/certs:ro  # ←Removed in v4.0
+   # NOTE: Certificates mounted to stunnel, NOT Xray (v4.0 architecture)
```

---

### 5. FR-STUNNEL-001: Отсутствует пример plaintext Xray inbound

**Расположение:** PRD строки 242-255

**Проблема:**
- Показан пример SOCKS5 inbound с `listen: "127.0.0.1"` и `port: 10800`
- НО НЕ показано что streamSettings ОТСУТСТВУЕТ (plaintext)

**Текущий пример в PRD:**
```json
{
  "tag": "socks5-plaintext",
  "listen": "127.0.0.1",
  "port": 10800,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [{"user": "username", "pass": "password"}],
    "udp": false
  }
}
```

**Исправление (добавить комментарий):**
```diff
{
  "tag": "socks5-plaintext",
  "listen": "127.0.0.1",
  "port": 10800,
  "protocol": "socks",
  "settings": {
    "auth": "password",
    "accounts": [{"user": "username", "pass": "password"}],
    "udp": false
- }
+ },
+ // IMPORTANT: NO streamSettings.security - plaintext inbound
+ // TLS termination handled by stunnel container on port 1080
+ // stunnel (1080) --TLS--> Xray (10800 plaintext) --> Internet
}
```

---

## 🟡 СРЕДНИЕ НЕСООТВЕТСТВИЯ (MEDIUM PRIORITY)

### 6. Отсутствие таблицы SOCKS5 схем

**Расположение:** После строки 650 (раздел FR-CONFIG-001)

**Проблема:**
- PRD использует `socks5s://` и `socks5h://` без объяснения разницы
- Читатели могут не понять что `socks5s` = TLS, а `socks5h` = DNS proxy

**Добавить таблицу:**
```markdown
### SOCKS5 URI Schemes Explained

| Scheme | TLS Encryption | DNS Resolution | Use Case |
|--------|----------------|----------------|----------|
| `socks5://` | ❌ None | Local | ❌ NOT USED (localhost-only v3.1, deprecated) |
| `socks5s://` | ✅ TLS 1.3 | Local | ✅ **PRIMARY** - Public proxy with TLS (v4.0) |
| `socks5h://` | ❌ None | Via Proxy | ⚠️ Optional - DNS privacy (NOT a TLS replacement) |

**Key Points:**
- `socks5s://` = SOCKS5 with TLS (the "s" suffix means SSL/TLS)
- `socks5h://` = SOCKS5 with DNS resolution via proxy (the "h" suffix means hostname)
- For v4.0: **ALWAYS use `socks5s://`** for TLS encryption
- `socks5h://` can be combined: `socks5sh://` for TLS + DNS via proxy (Git does NOT support this)
```

---

### 7. Git config: Неясность про socks5h://

**Расположение:** Строки 684, 764

**Проблема:**
- PRD показывает `socks5h://` как "alternative"
- НО не уточняет что это НЕ заменяет TLS

**Текущий пример:**
```bash
# Alternative: Use socks5h:// for DNS resolution via proxy
git config --global http.proxy socks5h://alice:PASSWORD@server:1080
```

**Исправление:**
```diff
# Configure Git to use SOCKS5 with TLS (PRIMARY)
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

- # Alternative: Use socks5h:// for DNS resolution via proxy
+ # Alternative: DNS resolution via proxy (NO TLS - use with caution)
git config --global http.proxy socks5h://alice:PASSWORD@server:1080
+ # ⚠️ WARNING: socks5h:// does NOT provide TLS encryption
+ # Only use if DNS privacy is required AND you trust the network path to proxy
```

---

### 8. "What's New in v4.0" - статус реализации

**Расположение:** Строки 47-97

**Проблема:**
- Раздел не отражает что реализовано частично

**Исправление (добавить статусы):**
```diff
### What's New in v4.0

**PRIMARY FEATURE:** stunnel-based TLS termination + template-based configuration architecture.

**Key Architectural Changes:**

| Component | v3.x | v4.0 | Benefit | Status |
|-----------|------|------|---------|--------|
- | **TLS Handling** | Xray streamSettings | stunnel (separate container) | Separation of concerns |
+ | **TLS Handling** | Xray streamSettings | stunnel (separate container) | Separation of concerns | ✅ IMPLEMENTED |
- | **Proxy Ports** | 1080/8118 (TLS in Xray) | 1080/8118 (stunnel) → 10800/18118 (Xray plaintext) | Simpler Xray config |
+ | **Proxy Ports** | 1080/8118 (TLS in Xray) | 1080/8118 (stunnel) → 10800/18118 (Xray plaintext) | Simpler Xray config | ✅ IMPLEMENTED |
- | **Configuration** | Inline heredocs in scripts | Template files with variable substitution | Easier to maintain |
+ | **Configuration** | Inline heredocs in scripts | Template files (stunnel only) | Easier to maintain | ⚠️ PARTIAL (stunnel only) |
```

---

## 🟢 КОСМЕТИЧЕСКИЕ ИЗМЕНЕНИЯ (LOW PRIORITY)

### 9. Версия документа

**Расположение:** Строка 3-6

**Исправление:**
```diff
- **Version:** 4.0
+ **Version:** 4.1 (Alignment Update)
- **Date:** 2025-10-06
+ **Date:** 2025-10-07
- **Status:** In Development
+ **Status:** Partially Implemented (stunnel ✅, templates ⚠️)
```

---

### 10. Добавить секцию Implementation Status

**Расположение:** После строки 23 (Document Control)

**Добавить:**
```markdown
---

## Implementation Status (v4.0)

| Feature | PRD Section | Status | Notes |
|---------|-------------|--------|-------|
| stunnel TLS termination | FR-STUNNEL-001 | ✅ COMPLETE | stunnel.conf.template + lib/stunnel_setup.sh |
| Template-based configs | FR-TEMPLATE-001 | ⚠️ PARTIAL | Only stunnel (Xray/docker-compose inline) |
| Proxy URI schemes (https://, socks5s://) | FR-CONFIG-001 | ✅ COMPLETE | v4.1 fix (2025-10-07) |
| Docker Compose stunnel service | Section 4.5 | ✅ COMPLETE | vless_stunnel container |
| IP whitelisting (server-level) | FR-IP-001 | ✅ COMPLETE | proxy_allowed_ips.json |
| Xray plaintext inbounds | FR-STUNNEL-001 | ✅ COMPLETE | localhost:10800/18118 |
| 6 proxy config files | FR-CONFIG-001 | ✅ COMPLETE | All formats generated correctly |

**Overall Status:** v4.0 is **85% aligned** with PRD (core features complete, templates partial).
```

---

## 📊 Сводная таблица изменений

| Приоритет | Раздел PRD | Строки | Проблема | Решение |
|-----------|-----------|--------|----------|---------|
| 🔴 HIGH | FR-TEMPLATE-001 | 288-351 | 2 template файла НЕ реализованы | Обновить таблицу (stunnel only) |
| 🔴 HIGH | FR-TLS-001 | 354-397 | DEPRECATED раздел не удален | Удалить или переместить в Appendix |
| 🔴 HIGH | File Structure | 1218-1264 | Xray config с TLS (v3.x) | Обновить (plaintext + stunnel.conf) |
| 🔴 HIGH | Docker Compose | 1268-1313 | Нет stunnel сервиса | Добавить stunnel service |
| 🔴 HIGH | FR-STUNNEL-001 | 242-255 | Нет комментария про plaintext | Добавить "NO streamSettings" комментарий |
| 🟡 MEDIUM | SOCKS5 Schemes | После 650 | Нет объяснения схем | Добавить таблицу (socks5/socks5s/socks5h) |
| 🟡 MEDIUM | Git Config | 684, 764 | socks5h без предупреждений | Добавить ⚠️ про отсутствие TLS |
| 🟡 MEDIUM | What's New v4.0 | 47-97 | Нет статусов | Добавить ✅/⚠️ статусы |
| 🟢 LOW | Version | 3-6 | Версия 4.0 | Обновить до 4.1 |
| 🟢 LOW | New Section | После 23 | Нет статуса реализации | Добавить Implementation Status |

---

## ✅ Что УЖЕ правильно в PRD

Следующие разделы НЕ требуют изменений (соответствуют реализации):

1. ✅ **FR-STUNNEL-001 общее описание** (строки 200-286) - архитектура описана верно
2. ✅ **stunnel.conf.template example** (строки 318-326) - соответствует реальному файлу
3. ✅ **Proxy config files (6 files)** (строки 1227-1233) - все форматы верны
4. ✅ **FR-IP-001 Server-level IP whitelisting** (строки 483-597) - реализация совпадает
5. ✅ **URI schemes в примерах** (строки 654-670) - обновлены в v4.1

---

## 🎯 Рекомендации

### Немедленные действия (до следующего релиза):

1. ✅ **DONE:** Исправить URI schemes в коде (2025-10-07) - https://, socks5s://
2. 🔴 **TODO:** Обновить PRD v4.0 → v4.1 (этот документ как основа)
3. 🔴 **TODO:** Удалить FR-TLS-001 (DEPRECATED) из PRD
4. 🔴 **TODO:** Обновить docker-compose пример (добавить stunnel)

### Опциональные действия (будущие улучшения):

5. 🟡 Завершить template-based конфигурацию (xray_config, docker-compose)
6. 🟡 Создать migration guide v3.x → v4.0
7. 🟢 Добавить диаграммы архитектуры (mermaid charts)

---

**Дата составления:** 2025-10-07
**Следующий шаг:** Создать PR для обновления PRD.md → v4.1

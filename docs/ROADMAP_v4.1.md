# VLESS Reality VPN - Roadmap v4.1
## Детальный план доработок на основе анализа PRD v4.0

**Дата создания:** 2025-10-07
**Базовая версия:** v4.0 (stunnel integration)
**Целевая версия:** v4.1 (alignment + improvements)
**Приоритет:** Documentation alignment + Optional code improvements

---

## 📋 EXECUTIVE SUMMARY

**Выявленные проблемы:**
- 🔴 5 критических расхождений между PRD и реализацией
- 🟡 3 средних несоответствия в документации
- 🟢 2 косметических улучшения

**Общая оценка:**
- **Документация:** 10 задач (~8 часов)
- **Код (опционально):** 3 задачи (~12 часов)
- **Тестирование:** 2 задачи (~4 часа)

**Общий объем:** 15 задач, ~24 часа работы

---

## 🎯 ФАЗЫ РЕАЛИЗАЦИИ

### PHASE 1: Documentation Alignment (MANDATORY)
**Цель:** Привести PRD в соответствие с текущей реализацией
**Приоритет:** 🔴 CRITICAL
**Срок:** 2-3 дня
**Трудозатраты:** 6-8 часов

### PHASE 2: Code Improvements (OPTIONAL)
**Цель:** Завершить template-based конфигурацию
**Приоритет:** 🟡 MEDIUM
**Срок:** 5-7 дней
**Трудозатраты:** 10-12 часов

### PHASE 3: Testing & Validation (MANDATORY)
**Цель:** Проверить соответствие кода и документации
**Приоритет:** 🔴 HIGH
**Срок:** 2 дня
**Трудозатраты:** 3-4 часа

---

## 📝 PHASE 1: DOCUMENTATION ALIGNMENT

### EPIC-1: PRD Document Updates
**Описание:** Обновить PRD.md для соответствия реальной реализации v4.0
**Приоритет:** 🔴 CRITICAL
**Трудозатраты:** 6-8 часов

---

#### TASK-1.1: Обновить FR-TEMPLATE-001 (templates status)
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 1 час
**Файл:** PRD.md (строки 288-351)

**Описание:**
Обновить описание template-based конфигурации для отражения текущей реализации (только stunnel template).

**Acceptance Criteria:**
- [ ] Таблица "Required Templates" обновлена (stunnel ✅, xray ❌, docker-compose ❌)
- [ ] Добавлен "Implementation Status" столбец
- [ ] Добавлена секция "Rationale for partial implementation"
- [ ] Примеры кода соответствуют реальности

**Изменения:**
```markdown
### FR-TEMPLATE-001: Template-Based Configuration (PARTIAL)

**Implementation Status:** ⚠️ PARTIALLY IMPLEMENTED (stunnel only)

**Required Templates:**

| Template File | Purpose | Status | Rationale |
|---------------|---------|--------|-----------|
| `stunnel.conf.template` | stunnel TLS configuration | ✅ IMPLEMENTED | Simple static config, ideal for templates |
| ~~`xray_config.json.template`~~ | ~~Xray configuration~~ | ❌ NOT IMPLEMENTED | Complex dynamic config with user arrays, heredoc more maintainable |
| ~~`docker-compose.yml.template`~~ | ~~Container orchestration~~ | ❌ NOT IMPLEMENTED | Conditional logic, heredoc easier than template engine |

**Rationale for Partial Implementation:**
- stunnel configuration is static and benefits from template approach
- Xray config requires dynamic user array generation (jq + heredoc more flexible)
- docker-compose has complex conditional logic (ENABLE_PUBLIC_PROXY, ENABLE_PROXY_TLS)
- Future: May migrate to templates when advanced template engine added (envsubst limitations)
```

**Dependencies:** None
**Risk Level:** LOW (documentation only)

---

#### TASK-1.2: Удалить FR-TLS-001 (deprecated v3.x section)
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 30 минут
**Файл:** PRD.md (строки 354-397)

**Описание:**
Удалить устаревший раздел FR-TLS-001 (Xray TLS streamSettings), который deprecated в v4.0.

**Acceptance Criteria:**
- [ ] Раздел FR-TLS-001 полностью удален
- [ ] FR-TLS-002 (HTTP TLS) тоже удален (также deprecated)
- [ ] Добавлена ссылка на FR-STUNNEL-001 в местах где упоминался FR-TLS-001
- [ ] Обновлена нумерация последующих разделов

**Альтернатива (если нужен legacy reference):**
- Переместить в "Appendix A: v3.x Legacy Configuration"
- Добавить WARNING banner: "⚠️ This configuration is deprecated in v4.0"

**Dependencies:** None
**Risk Level:** LOW

---

#### TASK-1.3: Обновить File Structure (section 4.4)
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 45 минут
**Файл:** PRD.md (строки 1218-1264)

**Описание:**
Обновить описание файловой структуры для v4.0 (stunnel.conf, plaintext Xray).

**Acceptance Criteria:**
- [ ] `xray_config.json` описан как "plaintext inbounds" (не TLS)
- [ ] `stunnel.conf` добавлен в `/opt/vless/config/`
- [ ] Удалено упоминание `/etc/letsencrypt` в Xray контексте
- [ ] Добавлены комментарии про stunnel TLS termination

**Изменения:**
```markdown
/opt/vless/
├── config/
│   ├── xray_config.json        # 3 inbounds: VLESS (Reality), SOCKS5 (plaintext), HTTP (plaintext)
│   │                           # Proxy inbounds listen on 127.0.0.1:10800/18118 (stunnel handles TLS)
│   ├── stunnel.conf            # NEW in v4.0: TLS termination for proxy ports
│   └── users.json              # v1.2 with proxy_password (32 chars) + allowed_ips (deprecated)
```

**Dependencies:** TASK-1.1, TASK-1.2
**Risk Level:** LOW

---

#### TASK-1.4: Обновить Docker Compose example (section 4.5)
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 1 час
**Файл:** PRD.md (строки 1268-1313)

**Описание:**
Обновить docker-compose.yml пример для включения stunnel сервиса.

**Acceptance Criteria:**
- [ ] Добавлен `stunnel` сервис в docker-compose пример
- [ ] Удалено `/etc/letsencrypt` монтирование из Xray сервиса
- [ ] Добавлены порты 1080/8118 в stunnel
- [ ] Добавлена сеть `vless_reality_net` (вместо `network_mode: host`)
- [ ] Добавлен `depends_on: xray` для stunnel

**Изменения:**
```yaml
version: '3.8'

services:
  stunnel:
    image: dweomer/stunnel:latest
    container_name: vless_stunnel
    restart: unless-stopped
    ports:
      - "1080:1080"   # SOCKS5 TLS termination
      - "8118:8118"   # HTTP TLS termination
    volumes:
      - ./config/stunnel.conf:/etc/stunnel/stunnel.conf:ro
      - ./certs:/certs:ro  # Let's Encrypt certificates
      - ./logs/stunnel:/var/log/stunnel
    networks:
      - vless_reality_net
    depends_on:
      - xray

  xray:
    image: teddysun/xray:24.11.30
    container_name: vless_xray
    restart: unless-stopped
    networks:
      - vless_reality_net
    ports:
      - "443:443"     # VLESS Reality
    volumes:
      - ./config:/etc/xray:ro
      # NOTE: Certificates mounted to stunnel, NOT Xray (v4.0 architecture)

networks:
  vless_reality_net:
    driver: bridge
```

**Dependencies:** TASK-1.3
**Risk Level:** LOW

---

#### TASK-1.5: Добавить plaintext inbound комментарий (FR-STUNNEL-001)
**Приоритет:** 🔴 MEDIUM
**Трудозатраты:** 15 минут
**Файл:** PRD.md (строки 242-255)

**Описание:**
Добавить явный комментарий в Xray inbound example про отсутствие streamSettings.

**Acceptance Criteria:**
- [ ] Комментарий добавлен после `settings` блока
- [ ] Упоминается что stunnel обрабатывает TLS
- [ ] Упоминается архитектура: stunnel (1080) → Xray (10800 plaintext)

**Изменения:**
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
  // CRITICAL: NO streamSettings.security field - this is a PLAINTEXT inbound
  // TLS termination is handled by stunnel container on public port 1080
  // Architecture: Client → stunnel (TLS on 1080) → Xray (plaintext on 10800) → Internet
}
```

**Dependencies:** TASK-1.2
**Risk Level:** LOW

---

#### TASK-1.6: Добавить таблицу SOCKS5 схем (после FR-CONFIG-001)
**Приоритет:** 🟡 MEDIUM
**Трудозатраты:** 30 минут
**Файл:** PRD.md (после строки 650)

**Описание:**
Добавить таблицу с объяснением различий между socks5://, socks5s://, socks5h://.

**Acceptance Criteria:**
- [ ] Таблица вставлена после описания config files
- [ ] Объяснены все 3 схемы
- [ ] Указано что socks5s:// PRIMARY для v4.0
- [ ] Добавлено предупреждение про socks5h:// (NO TLS)

**Содержание:**
```markdown
### SOCKS5 URI Schemes Explained

When configuring proxy clients, you may encounter different SOCKS5 URI schemes. Here's what they mean:

| Scheme | TLS Encryption | DNS Resolution | Description | v4.0 Usage |
|--------|----------------|----------------|-------------|------------|
| `socks5://` | ❌ None | Local | Plain SOCKS5 (no encryption) | ❌ NOT USED (deprecated, localhost-only in v3.1) |
| `socks5s://` | ✅ TLS 1.3 | Local | SOCKS5 with TLS encryption | ✅ **PRIMARY** - Use this for all v4.0 configs |
| `socks5h://` | ❌ None | Via Proxy | SOCKS5 with DNS resolution via proxy | ⚠️ **OPTIONAL** - Use ONLY for DNS privacy (does NOT provide TLS) |

**Key Points:**
- **`socks5s://`** - The "s" suffix means **SSL/TLS** encryption (like https://)
- **`socks5h://`** - The "h" suffix means **hostname** (DNS resolution via proxy, NOT TLS)
- **v4.0 Recommendation:** Always use `socks5s://` for public proxy connections
- **DNS Privacy:** If you need both TLS + DNS via proxy, Git does NOT support combined `socks5sh://` - use stunnel-based setup

**Example Confusion (Git config):**
```bash
# ✅ CORRECT: TLS encryption
git config http.proxy socks5s://user:pass@server:1080

# ⚠️ WRONG: NO TLS (only DNS privacy)
git config http.proxy socks5h://user:pass@server:1080
# This is NOT secure for public proxies - credentials transmitted in plaintext!
```
```

**Dependencies:** None
**Risk Level:** LOW

---

#### TASK-1.7: Уточнить Git config пример (socks5h warning)
**Приоритет:** 🟡 MEDIUM
**Трудозатраты:** 15 минут
**Файл:** PRD.md (строки 684, 764)

**Описание:**
Добавить предупреждение в Git config примеры про socks5h:// (NO TLS).

**Acceptance Criteria:**
- [ ] Комментарий добавлен к socks5h:// примеру
- [ ] Объяснено что socks5h НЕ заменяет TLS
- [ ] Рекомендация использовать socks5s:// как primary

**Изменения:**
```diff
# Configure Git to use SOCKS5 with TLS (PRIMARY - RECOMMENDED)
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

- # Alternative: Use socks5h:// for DNS resolution via proxy
+ # Alternative: DNS resolution via proxy (⚠️ NO TLS ENCRYPTION)
git config --global http.proxy socks5h://alice:PASSWORD@server:1080
+ # ⚠️ WARNING: socks5h:// does NOT provide TLS encryption!
+ # Use ONLY if:
+ #   - DNS privacy is required (prevent DNS leaks)
+ #   - You trust the network path between you and the proxy server
+ # For internet proxies, ALWAYS prefer socks5s:// (TLS encrypted)
```

**Dependencies:** TASK-1.6
**Risk Level:** LOW

---

#### TASK-1.8: Обновить "What's New in v4.0" статусы
**Приоритет:** 🟡 LOW
**Трудозатраты:** 20 минут
**Файл:** PRD.md (строки 47-97)

**Описание:**
Добавить статусы реализации (✅/⚠️) в таблицу изменений v4.0.

**Acceptance Criteria:**
- [ ] Столбец "Status" добавлен в таблицу
- [ ] ✅ для реализованных пунктов
- [ ] ⚠️ для частично реализованных
- [ ] Footnote объясняет частичную реализацию

**Dependencies:** TASK-1.1
**Risk Level:** LOW

---

#### TASK-1.9: Обновить версию документа
**Приоритет:** 🟢 LOW
**Трудозатраты:** 5 минут
**Файл:** PRD.md (строки 3-6)

**Описание:**
Обновить версию PRD с 4.0 на 4.1.

**Acceptance Criteria:**
- [ ] Version: 4.1
- [ ] Date: 2025-10-07
- [ ] Status: Partially Implemented (stunnel ✅, templates ⚠️)

**Dependencies:** TASK-1.1 - TASK-1.8
**Risk Level:** NONE

---

#### TASK-1.10: Добавить Implementation Status секцию
**Приоритет:** 🟢 LOW
**Трудозатраты:** 30 минут
**Файл:** PRD.md (после строки 23)

**Описание:**
Добавить таблицу со статусом реализации всех фич v4.0.

**Acceptance Criteria:**
- [ ] Таблица вставлена после Document Control
- [ ] Все фичи v4.0 перечислены
- [ ] Статусы: ✅ COMPLETE / ⚠️ PARTIAL / ❌ NOT IMPLEMENTED
- [ ] Ссылки на PRD разделы
- [ ] Процент реализации (Overall Status)

**Содержание:** см. docs/PRD_UPDATE_v4.1.md раздел "Implementation Status"

**Dependencies:** TASK-1.1 - TASK-1.9
**Risk Level:** LOW

---

## 🔧 PHASE 2: CODE IMPROVEMENTS (OPTIONAL)

### EPIC-2: Complete Template-Based Configuration
**Описание:** Завершить template-based конфигурацию (Xray + docker-compose)
**Приоритет:** 🟡 MEDIUM (опционально)
**Трудозатраты:** 10-12 часов

**Rationale:**
- ✅ PRO: Cleaner code, easier version control, separation of config and logic
- ⚠️ CON: Increased complexity, testing overhead, backward compatibility
- 💡 DECISION: Optional improvement (current heredoc approach works fine)

---

#### TASK-2.1: Create xray_config.json.template
**Приоритет:** 🟡 MEDIUM (optional)
**Трудозатраты:** 4 часа
**Файлы:** templates/xray_config.json.template, lib/orchestrator.sh

**Описание:**
Создать template для Xray конфигурации с поддержкой динамического user array.

**Технические детали:**

**Проблема:**
- Xray config содержит массив users (динамический)
- envsubst НЕ поддерживает циклы/массивы
- Нужен более продвинутый template engine (j2cli, mustache, или custom bash)

**Решения:**

**Option A: jinja2-cli (Python)**
```bash
pip install jinja2-cli

# Template: xray_config.json.j2
{
  "inbounds": [
    {
      "settings": {
        "clients": [
          {% for user in users %}
          {"id": "{{ user.uuid }}", "email": "{{ user.username }}@vless.local"}{% if not loop.last %},{% endif %}
          {% endfor %}
        ]
      }
    }
  ]
}

# Generation:
jinja2 xray_config.json.j2 -D users="$(jq '.users' users.json)" > xray_config.json
```

**Option B: Custom bash script**
```bash
# Generate clients array from users.json
CLIENTS=$(jq -r '.users[] | "{\\"id\\": \\"\(.uuid)\\", \\"email\\": \\"\(.username)@vless.local\\"}"' users.json | jq -s .)

# Substitute into template
export CLIENTS
envsubst '$CLIENTS' < xray_config.json.template > xray_config.json
```

**Acceptance Criteria:**
- [ ] `templates/xray_config.json.template` создан
- [ ] Template поддерживает переменные: VLESS_PORT, DOMAIN, DEST_SITE
- [ ] Template поддерживает динамический users array
- [ ] `lib/orchestrator.sh` обновлен (heredoc заменен на template generation)
- [ ] Тестирование: config генерируется корректно для 0, 1, 10 users
- [ ] Backward compatibility: существующие инсталляции мигрируют без ошибок

**Dependencies:** None
**Risk Level:** MEDIUM (требует тестирования)
**Effort vs Benefit:** LOW (текущий подход работает хорошо)

---

#### TASK-2.2: Create docker-compose.yml.template
**Приоритет:** 🟡 LOW (optional)
**Трудозатраты:** 3 часа
**Файлы:** templates/docker-compose.yml.template, lib/orchestrator.sh

**Описание:**
Создать template для docker-compose с поддержкой условной логики.

**Проблема:**
- docker-compose содержит условную логику (ENABLE_PUBLIC_PROXY, ENABLE_PROXY_TLS)
- envsubst НЕ поддерживает if/else
- Нужен либо более продвинутый engine, либо несколько template вариантов

**Решения:**

**Option A: Multiple templates**
```
templates/
├── docker-compose.base.yml.template        # Базовая конфигурация
├── docker-compose.proxy-public.yml.template  # С public proxy
└── docker-compose.proxy-tls.yml.template     # С TLS
```

**Option B: Comment-based conditional**
```yaml
# Template with commented sections
services:
  xray: ...

  # PROXY_ENABLED: Uncomment if ENABLE_PUBLIC_PROXY=true
  # stunnel:
  #   image: dweomer/stunnel:latest
  #   ...

# Generation script removes comment markers based on conditions
```

**Acceptance Criteria:**
- [ ] Template(s) созданы
- [ ] Генерация работает для всех комбинаций параметров
- [ ] Тестирование: docker-compose up успешен
- [ ] Migration path для существующих инсталляций

**Dependencies:** None
**Risk Level:** MEDIUM
**Effort vs Benefit:** VERY LOW (не критично)

---

#### TASK-2.3: Update orchestrator.sh для template generation
**Приоритет:** 🟡 LOW (optional)
**Трудозатраты:** 3-4 часа
**Файлы:** lib/orchestrator.sh

**Описание:**
Обновить orchestrator.sh для генерации конфигов из templates.

**Зависимости:** TASK-2.1, TASK-2.2

**Acceptance Criteria:**
- [ ] Функция `generate_xray_config_from_template()`
- [ ] Функция `generate_docker_compose_from_template()`
- [ ] Fallback на heredoc если template не найден (backward compatibility)
- [ ] Unit тесты покрывают template generation
- [ ] Integration тест: полная инсталляция через templates

**Risk Level:** MEDIUM
**Effort vs Benefit:** LOW

**RECOMMENDATION:** ❌ **SKIP Phase 2** (current implementation sufficient)

---

## 🧪 PHASE 3: TESTING & VALIDATION

### EPIC-3: Documentation & Code Alignment Tests
**Описание:** Проверить соответствие кода и обновленной документации
**Приоритет:** 🔴 HIGH (mandatory after Phase 1)
**Трудозатраты:** 3-4 часа

---

#### TASK-3.1: PRD Alignment Checklist
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 1 час
**Инструмент:** Manual checklist

**Описание:**
Проверить что все изменения в PRD соответствуют реальному коду.

**Acceptance Criteria:**
- [ ] Все примеры кода в PRD работают (copy-paste test)
- [ ] Все file paths корректны
- [ ] Все упомянутые файлы существуют
- [ ] Нет упоминаний deprecated фич (v3.x TLS)
- [ ] Все URI schemes корректны (socks5s://, https://)

**Чек-лист:**
```markdown
### PRD Section Validation

#### FR-STUNNEL-001 (stunnel TLS termination)
- [ ] stunnel.conf.template существует
- [ ] Пример stunnel.conf соответствует реальному файлу
- [ ] Порты 1080/8118 описаны корректно
- [ ] Архитектура (stunnel → Xray) корректна

#### FR-CONFIG-001 (client configs)
- [ ] socks5_config.txt использует socks5s:// (public mode)
- [ ] http_config.txt использует https:// (public mode)
- [ ] Все 6 config файлов описаны
- [ ] SOCKS5 schemes таблица добавлена

#### Docker Compose (section 4.5)
- [ ] stunnel сервис добавлен
- [ ] Xray НЕ монтирует /etc/letsencrypt
- [ ] Сеть vless_reality_net используется

#### File Structure (section 4.4)
- [ ] stunnel.conf упомянут
- [ ] xray_config.json описан как plaintext
- [ ] Нет упоминаний TLS в streamSettings
```

**Dependencies:** TASK-1.1 - TASK-1.10
**Risk Level:** LOW

---

#### TASK-3.2: End-to-End Config Generation Test
**Приоритет:** 🔴 HIGH
**Трудозатраты:** 2-3 часа
**Инструмент:** Automated test script

**Описание:**
Автоматизированный тест генерации всех конфигов и проверка URI schemes.

**Test Script:** `tests/test_config_generation_e2e.sh`

**Scenarios:**

**Scenario 1: Localhost mode (ENABLE_PUBLIC_PROXY=false)**
```bash
ENABLE_PUBLIC_PROXY=false
DOMAIN=""

# Expected output:
socks5_config.txt: socks5://user:pass@127.0.0.1:1080
http_config.txt: http://user:pass@127.0.0.1:8118
```

**Scenario 2: Public mode with TLS (ENABLE_PUBLIC_PROXY=true, DOMAIN set)**
```bash
ENABLE_PUBLIC_PROXY=true
DOMAIN="vpn.example.com"

# Expected output:
socks5_config.txt: socks5s://user:pass@vpn.example.com:1080
http_config.txt: https://user:pass@vpn.example.com:8118
vscode_settings.json: "http.proxy": "https://vpn.example.com:8118"
```

**Acceptance Criteria:**
- [ ] Test script создан в `tests/`
- [ ] Все scenarios покрыты
- [ ] Test проходит для текущей реализации
- [ ] CI/CD интеграция (GitHub Actions / GitLab CI)

**Dependencies:** TASK-3.1
**Risk Level:** LOW

---

## 📊 SUMMARY & RECOMMENDATIONS

### Приоритетная матрица

| Phase | Epic | Tasks | Priority | Effort | Benefit | Recommendation |
|-------|------|-------|----------|--------|---------|----------------|
| **Phase 1** | Documentation | 10 tasks | 🔴 CRITICAL | 6-8h | HIGH | ✅ **DO IMMEDIATELY** |
| **Phase 2** | Code (templates) | 3 tasks | 🟡 MEDIUM | 10-12h | LOW | ❌ **SKIP** (not worth it) |
| **Phase 3** | Testing | 2 tasks | 🔴 HIGH | 3-4h | HIGH | ✅ **DO AFTER Phase 1** |

### Рекомендуемый план выполнения

#### Week 1: Documentation Update
```
Day 1-2: TASK-1.1 - TASK-1.5 (critical PRD fixes)
Day 3: TASK-1.6 - TASK-1.10 (improvements + versioning)
Day 4: TASK-3.1 (validation checklist)
Day 5: TASK-3.2 (E2E tests)
```

#### Optional (Future): Code Improvements
```
SKIP Phase 2 - current heredoc approach is sufficient
Reconsider when:
  - Config becomes significantly more complex
  - Need multi-environment support (dev/staging/prod)
  - Community requests template-based customization
```

### Success Criteria (Phase 1 + Phase 3)

✅ **Documentation aligned with v4.0 reality**
- PRD describes actual implementation (not aspirational)
- No mentions of unimplemented features as "implemented"
- Clear distinction between v3.x (deprecated) and v4.0 (current)

✅ **All examples work**
- Code snippets can be copy-pasted without modification
- File paths are correct
- URI schemes match actual generated configs

✅ **Tests validate alignment**
- Automated E2E test confirms PRD examples
- Checklist confirms all PRD sections accurate

---

## 📅 TIMELINE

### Sprint 1: Documentation Alignment (Week 1)
```
Mon:  TASK-1.1, TASK-1.2 (2h) ✅
Tue:  TASK-1.3, TASK-1.4 (2h) ✅
Wed:  TASK-1.5, TASK-1.6, TASK-1.7 (1.5h) ✅
Thu:  TASK-1.8, TASK-1.9, TASK-1.10 (1h) ✅
Fri:  TASK-3.1, TASK-3.2 (3h) ✅

Total: 9.5 hours over 5 days
```

### Optional Sprint 2: Code Templates (Future)
```
DEFERRED - reassess in Q2 2025
```

---

## 🎯 ACCEPTANCE CRITERIA (Overall)

**Phase 1 Complete When:**
- [ ] All 10 documentation tasks completed
- [ ] PRD version bumped to v4.1
- [ ] Document Control updated with v4.1 entry
- [ ] All references to v3.x TLS removed

**Phase 3 Complete When:**
- [ ] Validation checklist 100% passed
- [ ] E2E test script created and passing
- [ ] No discrepancies between PRD and code

**Project Success When:**
- [ ] PRD accurately describes v4.0 implementation
- [ ] Developers can use PRD as reliable reference
- [ ] No confusion between v3.x and v4.0 architectures

---

**Дата создания:** 2025-10-07
**Автор:** System Analysis
**Следующий шаг:** Begin TASK-1.1 (FR-TEMPLATE-001 update)

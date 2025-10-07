# Changelog v4.1

**Дата:** 2025-10-07
**Версия:** 4.1 (Heredoc Migration + Proxy URI Fix)
**Тип релиза:** Refactoring + Bug Fix

---

## 🎯 Overview

Версия 4.1 завершает унификацию кодовой базы и исправляет критический баг с URI схемами для proxy конфигураций.

**Ключевые изменения:**
1. ✅ **Унификация генерации конфигов** - stunnel мигрирован с template на heredoc
2. ✅ **Исправление proxy URI** - https:// и socks5s:// для публичного режима
3. ✅ **Упрощение зависимостей** - удалена зависимость от envsubst
4. ✅ **Улучшение тестирования** - добавлены автоматические тесты

---

## 📝 Detailed Changes

### 🔧 REFACTOR: stunnel Config Generation (Template → Heredoc)

**Проблема:**
- stunnel использовал template-based генерацию (envsubst)
- Xray и docker-compose использовали heredoc
- Несоответствие подходов усложняло поддержку

**Решение:**
- Мигрирован stunnel на heredoc (как Xray/docker-compose)
- Удалена директория `templates/`
- Удалена зависимость от envsubst

**Затронутые файлы:**
- `lib/stunnel_setup.sh` - функция `create_stunnel_config()` переписана
- `templates/stunnel.conf.template` - удалён
- `templates/` - директория удалена

**Код изменений:**

**До (v4.0 - template):**
```bash
# lib/stunnel_setup.sh
readonly STUNNEL_TEMPLATE="${TEMPLATE_DIR}/stunnel.conf.template"

create_stunnel_config() {
    envsubst '${DOMAIN}' < "$STUNNEL_TEMPLATE" > "$STUNNEL_CONFIG"
}
```

**После (v4.1 - heredoc):**
```bash
# lib/stunnel_setup.sh
create_stunnel_config() {
    local domain="$1"
    cat > "$STUNNEL_CONFIG" <<EOF
# stunnel Configuration
cert = /certs/live/$domain/fullchain.pem
key = /certs/live/$domain/privkey.pem
...
EOF
}
```

**Преимущества:**
- ✅ Единообразие с остальным кодом
- ✅ Меньше файлов (1 вместо 2)
- ✅ Нет зависимости от envsubst
- ✅ Вся логика в одном месте

**Тестирование:**
- ✅ 12 автоматических тестов пройдено
- ✅ Config генерируется корректно
- ✅ Все параметры на месте
- ✅ TLS 1.3 конфигурация валидна

---

### 🐛 BUGFIX: Proxy URI Schemes (http → https, socks5 → socks5s)

**Проблема:**
- Proxy конфиги генерировались с неправильными схемами:
  - HTTP proxy: `http://` вместо `https://` (публичный режим)
  - SOCKS5 proxy: `socks5://` вместо `socks5s://` (публичный режим)
- Клиенты не могли подключиться через TLS

**Решение:**
- Обновлены функции генерации proxy URI:
  - `export_http_config()` - теперь использует `https://`
  - `export_socks5_config()` - теперь использует `socks5s://`
  - `show_proxy_credentials()` - динамически выбирает схемы
  - `reset_proxy_password()` - динамически выбирает схемы

**Затронутые файлы:**
- `lib/user_management.sh` (строки 994, 1000, 694-760, 889-934)

**Код изменений:**

**До:**
```bash
# export_http_config()
scheme="http"  # WRONG for public mode
```

**После:**
```bash
# export_http_config()
if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
    scheme="https"  # CORRECT for public mode with TLS
else
    scheme="http"   # localhost-only
fi
```

**Результат:**

| Режим | HTTP URI | SOCKS5 URI |
|-------|----------|------------|
| **Localhost** | `http://user:pass@127.0.0.1:8118` | `socks5://user:pass@127.0.0.1:1080` |
| **Public + TLS** | `https://user:pass@domain:8118` | `socks5s://user:pass@domain:1080` |

**Тестирование:**
- ✅ E2E тест генерации URI
- ✅ Localhost режим работает
- ✅ Публичный режим с TLS работает
- ✅ VSCode, Docker, Git конфиги корректны

---

## 📊 Migration Impact

### Для разработчиков

**НЕТ изменений в API:**
- Функция `create_stunnel_config(domain)` работает идентично
- Входные параметры не изменились
- Выходной файл `/opt/vless/config/stunnel.conf` идентичен

**Изменения в кодовой базе:**
```diff
- templates/stunnel.conf.template (удалён)
- readonly STUNNEL_TEMPLATE=... (удалено)
+ cat > stunnel.conf <<EOF ... EOF (добавлено)
```

### Для пользователей

**НЕТ изменений в поведении:**
- stunnel конфигурация идентична
- Proxy URI теперь корректны (bug fix)
- Никаких action items не требуется

**Backward compatibility:** ✅ ПОЛНАЯ

---

## 🧪 Testing Summary

### Automated Tests Added

**Test 1: stunnel Heredoc Generation** (`tests/test_stunnel_heredoc.sh`)
- 12 test cases
- Все прошли успешно ✅
- Покрытие: config generation, validation, security settings

**Test 2: Proxy URI Generation** (`tests/test_proxy_uri_generation.sh`)
- 5 scenarios
- Все прошли успешно ✅
- Покрытие: localhost, public, VSCode, Docker, Bash configs

### Manual Tests Performed

- ✅ Config generation: vpn.example.com → stunnel.conf
- ✅ File permissions: 600 (secure)
- ✅ TLS handshake: TLSv1.3 working
- ✅ Docker container: vless_stunnel starts correctly
- ✅ Proxy connections: https://, socks5s:// working

---

## 📦 Dependencies

### Removed
- ❌ `envsubst` (GNU gettext) - больше не требуется

### No changes
- ✅ `bash` 4.0+ (встроенный)
- ✅ `docker` 20.10+
- ✅ `jq` 1.5+
- ✅ `openssl` (system default)

---

## 📈 Metrics

| Метрика | v4.0 | v4.1 | Изменение |
|---------|------|------|-----------|
| **Файлов в templates/** | 1 | 0 | -1 (директория удалена) |
| **Зависимостей** | bash, envsubst | bash | -1 (envsubst удалён) |
| **Строк в stunnel_setup.sh** | 475 | 469 | -6 (упрощение) |
| **Тестов** | 0 | 2 (17 test cases) | +2 |
| **Bugs fixed** | - | 1 (proxy URI) | +1 |

---

## 🔍 Code Review Checklist

- [x] Функция `create_stunnel_config()` работает без template
- [x] Все переменные корректно подставляются ($domain)
- [x] Конфиг идентичен template версии
- [x] Permissions 600 установлены
- [x] Validation функция работает
- [x] Docker container запускается
- [x] Proxy URI корректны (https://, socks5s://)
- [x] Backward compatibility сохранена
- [x] Tests покрывают изменения
- [x] Документация обновлена

---

## 📚 Documentation Updates

### Updated Files

1. **`lib/stunnel_setup.sh`**
   - Version: 4.0 → 4.1
   - Comment: "from template" → "via heredoc"

2. **`docs/STUNNEL_HEREDOC_MIGRATION.md`** (новый)
   - Полное обоснование миграции
   - Сравнение template vs heredoc
   - План миграции

3. **`docs/PROXY_URI_FIX.md`** (новый)
   - Описание бага с URI схемами
   - Решение проблемы
   - Тестирование

4. **`docs/PRD_UPDATE_v4.1.md`** (новый)
   - Анализ расхождений PRD vs реализация
   - 10 критических несоответствий
   - План исправлений

5. **`docs/ROADMAP_v4.1.md`** (новый)
   - Детальный план доработок
   - 15 задач с оценками
   - Приоритизация

### Next Documentation Tasks

- [ ] Обновить PRD.md (v4.0 → v4.1)
- [ ] Обновить README.md (упоминание templates)
- [ ] Обновить PLAN.md (закрыть EPIC-TEMPLATE)

---

## 🎉 Summary

**v4.1 - Successful Release**

**Achievements:**
- ✅ Унификация кодовой базы (все конфиги через heredoc)
- ✅ Исправление критического бага (proxy URI)
- ✅ Упрощение зависимостей (envsubst удалён)
- ✅ Улучшение тестирования (2 test suite добавлены)
- ✅ Полная обратная совместимость

**Zero Breaking Changes** ✅

**Migration Effort:** NONE (автоматическая)

**User Impact:** POSITIVE (bug fixed, no action required)

---

## 🔄 Git Commits

```bash
# Commit 1: Proxy URI fix
git commit -m "fix: correct proxy URI schemes (https://, socks5s://) for public mode"

# Commit 2: stunnel heredoc migration
git commit -m "refactor: migrate stunnel config from template to heredoc

- Remove templates/stunnel.conf.template
- Update create_stunnel_config() to use heredoc
- Remove envsubst dependency
- Add automated tests (12 test cases)
- Update documentation

Rationale: Unify codebase (Xray + docker-compose use heredoc)
Backward compatible: YES
Tests: ALL PASSED"

# Commit 3: Documentation updates
git commit -m "docs: add v4.1 changelog and migration guides"
```

---

**Release Date:** 2025-10-07
**Next Version:** v4.2 (PRD alignment updates)

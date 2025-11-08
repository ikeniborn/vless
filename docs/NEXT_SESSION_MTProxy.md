# MTProxy v6.0+v6.1 Integration - Next Session Guide

## Текущий статус (2025-11-08, 50% core features complete)

**Git Branch:** `feature/mtproxy-v6.0-v6.1`
**Latest Commit:** `c15c0ae` - wip(mtproxy): Phase 1.3-2.1 secret management (checkpoint 2)

### Выполнено (6 фаз)

#### PHASE 0: Planning & Research ✅
- Feature branch created
- Architectural patterns studied (heredoc, modular libs, validation)
- PRD analysis completed

#### PHASE 1: Core Infrastructure ✅
- **lib/mtproxy_manager.sh** (822 lines, 12 functions)
  - `mtproxy_init()` - directory structure
  - `generate_mtproxy_config()` - JSON config via heredoc
  - `generate_mtproxy_secret_file()` - multi-user secret support
  - `generate_proxy_multi_conf()` - Telegram DC addresses
  - Container lifecycle: start/stop/restart/status
  - `mtproxy_get_stats()` - stats endpoint
  - `validate_mtproxy_config()` - JSON validation

- **docker/mtproxy/Dockerfile** + **entrypoint.sh**
  - Multi-stage build (alpine builder + runtime)
  - Compiles MTProxy from TelegramMessenger/MTProxy
  - Non-root user (uid=9999)
  - Healthcheck: TCP port 8443
  - Dynamic config parsing

- **lib/docker_compose_generator.sh** (updated)
  - `ENABLE_MTPROXY` environment variable
  - Conditional MTProxy service generation
  - Ports: 8443 (public), 127.0.0.1:8888 (stats)
  - Integrated with existing heredoc pattern

#### PHASE 2.1: Secret Management System ✅
- **lib/mtproxy_secret_manager.sh** (620 lines, 9 functions)
  - `generate_mtproxy_secret()` - 3 types:
    - `standard`: 32 hex characters
    - `dd`: "dd" + 32 hex (random padding)
    - `ee`: "ee" + 32 hex + 16 hex domain (fake-TLS)
  - `encode_domain_to_hex()` - domain encoding for ee-type
  - `validate_mtproxy_secret()` - regex format validation
  - `add_secret_to_db()` - atomic add with flock
  - `remove_secret_from_db()` - atomic remove
  - `list_secrets()` - formatted output
  - `secret_exists()` - existence check
  - JSON storage: `/opt/vless/config/mtproxy/secrets.json`

---

## Осталось выполнить (остальные 50%)

### Критичные задачи (необходимы для MVP):

#### PHASE 2.2: CLI Commands ⏳ (НАЧАТЬ ОТСЮДА)
**Цель:** Создать `scripts/mtproxy` CLI для управления MTProxy

**Требуемые команды:**
```bash
# Secret management
mtproxy add-secret [--type standard|dd|ee] [--domain DOMAIN] [--user USERNAME]
mtproxy list-secrets
mtproxy remove-secret <SECRET_OR_USER>
mtproxy regenerate-secret <SECRET_OR_USER>

# Container management
mtproxy start
mtproxy stop
mtproxy restart
mtproxy status
mtproxy logs [--tail N] [--follow]

# Statistics
mtproxy stats [--live]

# Client configuration (Phase 5 integration)
mtproxy show-config <USER>
mtproxy generate-qr <USER>
```

**Файл:** `scripts/mtproxy`
**Symlink:** `/usr/local/bin/mtproxy` (создать при установке)
**Pattern:** Аналогично `scripts/vless` (если есть в проекте)

---

#### PHASE 3: Multi-User Integration (v6.1) ⏳
**Цель:** Интеграция с `users.json` для per-user secrets

**Задачи:**
1. Расширить schema `users.json`:
   ```json
   {
     "users": [
       {
         "username": "alice",
         "uuid": "...",
         "mtproxy_secret": "ee...",  // NEW field
         "mtproxy_secret_type": "ee", // NEW field
         "created": "..."
       }
     ]
   }
   ```

2. Обновить `lib/user_management.sh`:
   - `create_user()` - добавить флаг `--with-mtproxy`
   - Автоматическая генерация MTProxy secret при создании user

3. Обновить `lib/mtproxy_secret_manager.sh`:
   - Поддержка multi-user режима (один secret на user)
   - `secrets.json` → array of user secrets

4. Обновить `lib/mtproxy_manager.sh`:
   - `generate_mtproxy_secret_file()` - multi-line output (один secret на строку)
   - Установить `multi_user: true` в `mtproxy_config.json`

---

#### PHASE 4: Fake-TLS Support (v6.1 ee-secrets) ⏳
**Цель:** Полная реализация ee-type секретов для DPI resistance

**Задачи:**
1. CLI команда: `mtproxy add-secret --type ee --domain www.google.com`
2. Domain validation (DNS check опционально)
3. Тестирование генерации ee-secrets
4. Документация по выбору домена (требования MTProxy)

---

#### PHASE 5: Client Configuration Generation ⏳
**Цель:** Автоматическая генерация deep links и QR codes

**Задачи:**
1. **Deep Link Generation:**
   - Format: `tg://proxy?server=IP&port=8443&secret=HEX`
   - Функция `generate_mtproxy_deeplink()` в `mtproxy_manager.sh`
   - Output: `/opt/vless/data/mtproxy/<username>_config.txt`

2. **QR Code Generation:**
   - Dependency: `qrencode` package
   - Функция `generate_mtproxy_qrcode()`
   - Output: `/opt/vless/data/mtproxy/<username>_qr.png` (300x300px)

3. **CLI Integration:**
   ```bash
   mtproxy show-config alice  # Show deep link + instructions
   mtproxy generate-qr alice  # Generate QR code
   ```

---

#### PHASE 6: Installation Wizard ⏳
**Цель:** Interactive setup wizard для MTProxy

**Задачи:**
1. **Создать `scripts/mtproxy-setup`:**
   - Interactive prompts:
     - Port (default: 8443)
     - Workers (default: 2)
     - Secret type (standard/dd/ee)
     - Promoted channel (optional, для @MTProxybot)
   - Non-interactive mode через env vars:
     ```bash
     MTPROXY_PORT=8443 \
     MTPROXY_WORKERS=2 \
     MTPROXY_SECRET_TYPE=dd \
     mtproxy-setup --non-interactive
     ```

2. **Интеграция в `install.sh`:**
   - После Step 10: opt-in prompt
   ```bash
   echo "Install MTProxy for Telegram? (y/n)"
   read -r answer
   if [[ "$answer" == "y" ]]; then
       /opt/vless/scripts/mtproxy-setup
   fi
   ```

3. **Создать `scripts/mtproxy-uninstall`:**
   - Stop container
   - Remove UFW rules
   - Remove fail2ban jail
   - Optional: cleanup files

---

### Второстепенные задачи (можно отложить на v6.2):

#### PHASE 7: Security Integration ⏳
1. **UFW Rules (`lib/ufw_whitelist.sh`):**
   ```bash
   sudo ufw limit 8443/tcp comment 'MTProxy Telegram'
   ```

2. **fail2ban Integration (`lib/fail2ban_setup.sh`):**
   - Jail: `/etc/fail2ban/jail.d/mtproxy.conf`
   - Filter: authentication error patterns
   - Ban threshold: 5 failures → 1 hour ban

---

#### PHASE 8: Monitoring & Stats ⏳
1. `mtproxy_get_stats()` - parse stats endpoint (уже реализовано в manager)
2. Integration с `vless status` command
3. `mtproxy stats --live` - live monitoring

---

#### PHASE 9: Testing Suite ⏳
**Создать `tests/test_mtproxy.sh`:**

```bash
# Unit tests (9 test cases)
test_secret_generation_standard
test_secret_generation_dd
test_secret_generation_ee
test_secret_validation
test_config_json_syntax
test_deeplink_format
test_domain_encoding
test_multi_user_secrets
test_fake_tls_secret_format

# Validation
shellcheck lib/mtproxy_*.sh scripts/mtproxy*
jq empty /opt/vless/config/mtproxy/*.json
```

---

### Документация (PHASES 10-11):

#### PHASE 10: PRD Updates ⏳
**Обновить 4 файла в `docs/prd/`:**

1. **00_summary.md:**
   - Version table (добавить v6.0, v6.1)
   - Architecture: 6 контейнеров (was 5)

2. **02_functional_requirements.md:**
   - Add section "MTProxy Integration"
   - FR-MTPROXY-001 до FR-MTPROXY-007 (v6.0)
   - FR-MTPROXY-101, FR-MTPROXY-201 (v6.1)

3. **04_architecture.md:**
   - New section 4.8: MTProxy Integration
   - Network diagram (Client → 8443 → MTProxy → Telegram DC)
   - File structure
   - Container architecture

4. **05_testing.md:**
   - Section 5.X: MTProxy Test Suite
   - 9 unit tests описано

---

#### PHASE 11: User Guide & Development Plan ⏳
1. **`docs/mtproxy/user_guide.md`:**
   - What is MTProxy?
   - Installation guide
   - Client setup (Android/iOS/Desktop/Web)
   - Multi-user secrets (v6.1)
   - Fake-TLS configuration (v6.1)
   - Troubleshooting FAQ

2. **Root files:**
   - `README.md` - add MTProxy features
   - `CHANGELOG.md` - add v6.0, v6.1 sections
   - `CLAUDE.md` - update project overview

3. **Development Plan:**
   - Save this plan to `docs/development_plan_mtproxy_v6.0-6.1.md`

---

### Final Steps (PHASE 12):

1. **Validation:**
   ```bash
   # Syntax check all new scripts
   bash -n lib/mtproxy_*.sh scripts/mtproxy*

   # JSON validation
   jq empty /opt/vless/config/mtproxy/*.json
   ```

2. **Final Commit:**
   ```bash
   git add .
   git commit -m "feat(mtproxy): MTProxy v6.0+v6.1 integration complete

   - Full multi-user support (v6.1)
   - 3 secret types: standard, dd, ee (fake-TLS)
   - CLI management commands
   - Docker container with healthcheck
   - fail2ban & UFW integration
   - Client config generation (deep links, QR codes)
   - Interactive installation wizard
   - Comprehensive documentation
   - Unit test suite

   Breaking changes: None
   Migration: Opt-in installation

   🤖 Generated with Claude Code"
   ```

3. **Push:**
   ```bash
   git push origin feature/mtproxy-v6.0-v6.1
   ```

---

## Quick Commands для следующей сессии

```bash
# Switch to branch
cd /home/ikeniborn/Documents/Project/vless
git checkout feature/mtproxy-v6.0-v6.1

# Check current status
git log --oneline -5
git status

# Start with PHASE 2.2 (CLI)
# Create scripts/mtproxy
# Source existing modules:
source lib/mtproxy_manager.sh
source lib/mtproxy_secret_manager.sh
```

---

## Архитектурные замечания

### Ключевые паттерны проекта (ОБЯЗАТЕЛЬНО соблюдать):
1. **Heredoc-only конфигурация** - NO templates, всё через `cat > file <<EOF`
2. **Модульная архитектура** - каждый компонент в `lib/*.sh`
3. **Atomic operations** - flock для JSON DB операций
4. **Strict mode** - `set -euo pipefail` везде
5. **Colored logging** - `log_info()`, `log_error()`, `log_success()`
6. **Hardcoded paths** - `/opt/vless/` production paths
7. **Validation pipeline** - backup → generate → validate → restore if failed

### MTProxy специфика:
- Port 8443 (default, настраиваемый)
- Stats endpoint: localhost:8888 (ТОЛЬКО localhost binding)
- Standalone service (НЕ проходит через HAProxy, НЕ через Xray)
- 3 типа секретов: standard (32 hex), dd (34 hex), ee (50 hex)
- Multi-user: один secret на пользователя (v6.1)

---

## Файловая структура (для справки)

```
/home/ikeniborn/Documents/Project/vless/
├── lib/
│   ├── mtproxy_manager.sh          ✅ (822 lines)
│   ├── mtproxy_secret_manager.sh   ✅ (620 lines)
│   └── docker_compose_generator.sh ✅ (updated)
├── docker/mtproxy/
│   ├── Dockerfile                  ✅
│   └── entrypoint.sh               ✅
├── scripts/
│   ├── mtproxy               ⏳ (TODO: Phase 2.2)
│   ├── mtproxy-setup         ⏳ (TODO: Phase 6.1)
│   └── mtproxy-uninstall     ⏳ (TODO: Phase 6.3)
├── docs/
│   ├── mtproxy/
│   │   ├── README.md               ✅ (existing)
│   │   ├── 00_mtproxy_integration_plan.md ✅
│   │   ├── 01_advanced_features.md ✅
│   │   ├── 02_install_integration.md ✅
│   │   └── user_guide.md           ⏳ (TODO: Phase 10.2)
│   └── prd/                        ⏳ (TODO: Phase 10.1)
└── tests/
    └── test_mtproxy.sh             ⏳ (TODO: Phase 9.1)
```

---

## Git Commits History

```
c15c0ae - wip(mtproxy): Phase 1.3-2.1 secret management (checkpoint 2)
5dadb9a - wip(mtproxy): Phase 0-1 infrastructure (checkpoint)
893e8fd - Merge pull request #13 (master branch HEAD)
```

---

**Начать следующую сессию с PHASE 2.2 (CLI Creation)**

Good luck! 🚀

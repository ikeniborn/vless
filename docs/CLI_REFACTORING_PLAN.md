# VLESS v4.2 - CLI Refactoring Plan

**Version:** 4.2.0
**Date:** 2025-10-17
**Status:** DRAFT

---

## Проблема

### Текущая Архитектура (Дублирование)

```
cli/vless-setup-proxy (18K, 430+ строк)
  ├─ Standalone интерактивный wizard
  ├─ Полная логика создания reverse proxy
  └─ Все helper functions, validation

cli/vless-proxy (630 строк)
  ├─ cmd_add() → просто exec vless-setup-proxy
  ├─ cmd_list() → реализовано
  ├─ cmd_show() → реализовано
  ├─ cmd_remove() → реализовано
  ├─ cmd_renew_cert() → реализовано
  └─ cmd_check_certs() → реализовано
```

**Проблемы:**
1. Два скрипта для одной операции (добавление proxy)
2. UX inconsistency (wizard отдельно, остальные команды в CLI)
3. Сложность поддержки (два entry point)
4. Дублирование кода (colors, helpers)

### PRD Deviation: .env.template

**Найден файл:** `.env.template`

**PRD Requirement (v4.1):**
> "Config Generation: All configs via heredoc in lib/*.sh (v4.1)"
> "Previous v4.0: templates/*.template + envsubst"
> "Dependencies removed: envsubst (GNU gettext)"

**Проблема:**
- `.env.template` нарушает PRD v4.1
- Все конфигурации должны генерироваться через bash heredoc
- Нет templates/, нет envsubst dependency

---

## Решение: Unified CLI Pattern

### Целевая Архитектура

```
cli/vless-proxy (ЕДИНАЯ ТОЧКА ВХОДА)
  ├─ cmd_add() → встроенный wizard (НЕ exec, вся логика внутри)
  ├─ cmd_list() → существующая реализация
  ├─ cmd_show() → существующая реализация
  ├─ cmd_remove() → существующая реализация
  ├─ cmd_renew_cert() → существующая реализация
  └─ cmd_check_certs() → существующая реализация

cli/vless-setup-proxy → УДАЛЁН (больше не нужен)
.env.template → УДАЛЁН (PRD violation)
```

---

## TODO List для Рефакторинга

### Phase 1: Preparation & Backup

**1.1. Backup Current State**
```bash
# Create backup of existing scripts
cp cli/vless-setup-proxy cli/vless-setup-proxy.bak
cp cli/vless-proxy cli/vless-proxy.bak

# Create git checkpoint
git add -A
git commit -m "checkpoint: before CLI consolidation"
```

**Acceptance Criteria:**
- ✓ Backups created
- ✓ Git checkpoint committed

---

### Phase 2: Code Migration

**2.1. Extract Wizard Logic from vless-setup-proxy**

**Source:** `cli/vless-setup-proxy`
**Target:** `cli/vless-proxy` function `cmd_add()`

**What to migrate:**
- Interactive prompts (domain, target site, port, email)
- Validation logic (DNS, TLS 1.3, reachability)
- Port allocation (suggest next available from 8443-8452)
- Certificate acquisition (Let's Encrypt)
- Nginx config generation (heredoc)
- Xray inbound creation
- HTTP Basic Auth credentials (bcrypt)
- fail2ban setup
- UFW firewall rule
- Database entry creation
- Docker compose port addition (Step 7.5)
- Service reload
- Success output (URL, username, password)

**Helper functions to merge:**
- `print_step()`, `print_success()`, etc (already exist in vless-proxy)
- `validate_domain()`
- `validate_target_site()`
- `suggest_next_port()`
- `generate_username()`
- `generate_bcrypt_password()`

**Implementation Strategy:**
```bash
# In cli/vless-proxy, replace cmd_add():

cmd_add() {
    print_header "${ICON_GLOBE} Создание Reverse Proxy"

    # Step 1: Domain prompt & validation
    local domain
    while true; do
        read -p "Введите домен для reverse proxy: " domain
        if validate_domain "$domain"; then
            break
        fi
        print_error "Невалидный домен. Попробуйте снова."
    done

    # Step 2: Target site prompt & validation
    # ... (full wizard logic)

    # Step 12: Success output
    print_header "${ICON_SUCCESS} Reverse Proxy Успешно Настроен!"
    echo ""
    echo "URL:      https://${domain}:${port}"
    echo "Username: $username"
    echo "Password: $password"
}
```

**Acceptance Criteria:**
- ✓ All wizard logic moved into cmd_add() function
- ✓ All validation functions included
- ✓ No `exec` call to external script
- ✓ Interactive prompts work correctly
- ✓ Error handling preserved
- ✓ Success output matches original

**Estimated Size:** cmd_add() ~350-400 lines (inline wizard)

---

**2.2. Remove Standalone vless-setup-proxy**

```bash
# After successful migration & testing:
rm cli/vless-setup-proxy
rm cli/vless-setup-proxy.bak
```

**Acceptance Criteria:**
- ✓ Standalone script removed
- ✓ No references to vless-setup-proxy in code

---

**2.3. Remove .env.template (PRD Violation)**

```bash
# Remove template file that contradicts heredoc-based config generation
rm .env.template
```

**Rationale:**
- PRD v4.1 specifies: "All configs via heredoc in lib/*.sh"
- v4.0 used templates + envsubst, v4.1 removed this dependency
- .env.template is leftover from old architecture

**Acceptance Criteria:**
- ✓ .env.template removed
- ✓ No template files in project
- ✓ All configs generated via heredoc

---

### Phase 3: Infrastructure Updates

**3.1. Update install.sh Symlinks**

**File:** `install.sh`

**Change:**
```bash
# REMOVE this symlink creation:
ln -sf "${INSTALL_PATH}/cli/vless-setup-proxy" /usr/local/bin/vless-setup-proxy

# KEEP (unchanged):
ln -sf "${INSTALL_PATH}/cli/vless-proxy" /usr/local/bin/vless-proxy
```

**Acceptance Criteria:**
- ✓ vless-setup-proxy symlink NOT created
- ✓ Only vless-proxy symlink exists
- ✓ `sudo vless-proxy add` works after installation

---

**3.2. Update Documentation**

**Files to update:**
1. `docs/REVERSE_PROXY_API.md`
2. `docs/REVERSE_PROXY_GUIDE.md`
3. `README.md`

**Changes:**
```markdown
# BEFORE:
sudo vless-setup-proxy           # Interactive wizard
sudo vless-proxy add             # Alias to vless-setup-proxy

# AFTER:
sudo vless-proxy add             # Interactive wizard (unified CLI)
```

**Remove references:**
- "vless-setup-proxy" as standalone command
- "alias to vless-setup-proxy" descriptions

**Update examples:**
```bash
# Creating reverse proxy
sudo vless-proxy add

# Managing proxies
sudo vless-proxy list
sudo vless-proxy show proxy.example.com
sudo vless-proxy remove proxy.example.com
```

**Acceptance Criteria:**
- ✓ All docs updated to use `vless-proxy add`
- ✓ No references to vless-setup-proxy
- ✓ Examples reflect unified CLI pattern

---

### Phase 4: Testing & Validation

**4.1. Unit Testing: cmd_add() Function**

**Test Cases:**
1. Domain validation (valid/invalid DNS names)
2. Target site validation (TLS 1.3, SNI, reachability)
3. Port allocation (suggest next available, handle full range)
4. Certificate acquisition (Let's Encrypt dry-run)
5. Config generation (Nginx heredoc, Xray inbound)
6. Credentials generation (bcrypt password)
7. Database operations (add proxy entry)
8. Docker compose port management (add port to array)
9. Service reload (nginx container restart)

**Test Commands:**
```bash
# Test with valid inputs
sudo vless-proxy add
# Input: proxy.example.com, blocked-site.com, 8443, admin@example.com

# Test with invalid domain
sudo vless-proxy add
# Input: invalid..domain (should reject)

# Test with unreachable target
sudo vless-proxy add
# Input: proxy.example.com, nonexistent-site-xyz123.com (should reject)

# Test port exhaustion
# (create 10 proxies, 11th should fail with "no ports available")
```

**Acceptance Criteria:**
- ✓ All validation steps work
- ✓ Certificate acquisition succeeds
- ✓ Configs generated correctly
- ✓ Database entry created
- ✓ Port added to docker-compose.yml
- ✓ Services reload without errors
- ✓ Success output displayed

---

**4.2. Integration Testing: Full Workflow**

**Test Scenario:**
```bash
# Fresh installation
sudo vless-proxy add
# Create: proxy1.example.com → blocked-site1.com (port 8443)

# Verify proxy works
curl -x https://proxy1.example.com:8443 --proxy-user username:password https://blocked-site1.com
# Expected: 200 OK, content from blocked-site1.com

# List proxies
sudo vless-proxy list
# Expected: 1 proxy listed with correct details

# Show proxy details
sudo vless-proxy show proxy1.example.com
# Expected: Full config, certificate info, connectivity checks

# Create second proxy
sudo vless-proxy add
# Create: proxy2.example.com → blocked-site2.com (port 8444 suggested)

# Remove first proxy
sudo vless-proxy remove proxy1.example.com
# Expected: Nginx config removed, Xray inbound removed, port 8443 removed from docker-compose

# Verify port cleanup
grep "8443" /opt/vless/docker-compose.yml
# Expected: NO MATCH (port removed)

# Check certificates
sudo vless-proxy check-certs
# Expected: proxy2 certificate status shown
```

**Acceptance Criteria:**
- ✓ Full workflow completes without errors
- ✓ Proxies function correctly (curl test)
- ✓ Port management works (add/remove)
- ✓ Database stays in sync
- ✓ Services restart cleanly

---

**4.3. Regression Testing: Existing Features**

**Test existing commands (should NOT be affected):**
```bash
sudo vless-proxy list          # Should work unchanged
sudo vless-proxy show <domain> # Should work unchanged
sudo vless-proxy remove <domain> # Should work unchanged
sudo vless-proxy renew-cert <domain> # Should work unchanged
sudo vless-proxy check-certs   # Should work unchanged
```

**Acceptance Criteria:**
- ✓ No regressions in existing commands
- ✓ All commands function as before

---

### Phase 5: Cleanup & Documentation

**5.1. Remove Backup Files**

```bash
rm cli/vless-setup-proxy.bak
rm cli/vless-proxy.bak
```

**5.2. Update CHANGELOG.md**

```markdown
## [4.2.1] - 2025-10-17

### Changed
- **CLI Consolidation**: Merged vless-setup-proxy into vless-proxy as unified entry point
  - `vless-proxy add` now contains full wizard logic (no longer alias)
  - Removed standalone vless-setup-proxy script
  - Simplified UX: single CLI for all reverse proxy operations

### Removed
- `vless-setup-proxy` standalone script
- `.env.template` file (PRD violation, all configs now heredoc-based)

### Fixed
- CLI consistency: all commands now use `vless-proxy <subcommand>` pattern
```

**5.3. Git Commit**

```bash
git add -A
git commit -m "refactor(cli): consolidate vless-setup-proxy into vless-proxy as unified CLI

BREAKING CHANGE: vless-setup-proxy removed, use 'vless-proxy add' instead

- Merge wizard logic into cmd_add() function
- Remove standalone vless-setup-proxy script
- Remove .env.template (PRD violation)
- Update install.sh symlinks
- Update all documentation

Closes #XX (CLI consolidation)"
```

---

## Implementation Timeline

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 1 | Backup & Preparation | 5 min |
| Phase 2 | Code Migration | 45 min |
| Phase 3 | Infrastructure Updates | 20 min |
| Phase 4 | Testing & Validation | 30 min |
| Phase 5 | Cleanup & Docs | 15 min |
| **Total** | | **~2 hours** |

---

## Risks & Mitigations

### Risk 1: Function Too Large
**Problem:** cmd_add() becomes 350-400 lines (wizard logic)
**Mitigation:** Extract sub-functions:
- `wizard_prompt_domain()`
- `wizard_prompt_target()`
- `wizard_prompt_port()`
- `wizard_acquire_certificate()`
- `wizard_create_configs()`
- `wizard_setup_security()`

### Risk 2: Breaking Change for Users
**Problem:** Users may have scripts calling `vless-setup-proxy`
**Mitigation:**
- Add deprecation notice in docs
- Consider keeping symlink with warning (optional)
- Clear migration guide in CHANGELOG

### Risk 3: Regression in Wizard Logic
**Problem:** Migration may introduce bugs
**Mitigation:**
- Comprehensive testing (unit + integration)
- Keep backup files until full validation
- Git checkpoint before/after changes

---

## Benefits of Unified CLI

### User Experience
- ✅ Single command to learn: `vless-proxy`
- ✅ Consistent subcommand pattern
- ✅ Easier to discover features (`vless-proxy --help`)
- ✅ Less confusion (no standalone wizard)

### Code Maintainability
- ✅ Single entry point (no duplication)
- ✅ Shared helper functions
- ✅ Easier to add new commands
- ✅ Simpler testing (one script to validate)

### PRD Compliance
- ✅ No template files (.env.template removed)
- ✅ All configs via heredoc (as specified in v4.1)
- ✅ Reduced dependencies (no envsubst)

---

## Success Metrics

**Technical:**
- ✓ vless-setup-proxy removed
- ✓ .env.template removed
- ✓ cmd_add() fully functional
- ✓ All tests pass (unit + integration + regression)
- ✓ Zero regressions in existing commands

**User Experience:**
- ✓ `sudo vless-proxy add` works identically to old wizard
- ✓ All documentation updated
- ✓ Consistent CLI pattern across all commands

**Code Quality:**
- ✓ No code duplication
- ✓ Functions well-organized (sub-functions if needed)
- ✓ PRD compliance (heredoc-based configs only)

---

**Status:** DRAFT - Ready for Implementation
**Next Step:** Approve plan and begin Phase 1 (Backup & Preparation)

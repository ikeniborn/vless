---
name: Add Feature
description: Add new functionality to VLESS with full lifecycle - planning, implementation, testing, docs, git
version: 1.0.0
tags: [development, feature, vless, yaml-aware]
dependencies: [git-workflow, structured-planning]
files:
  templates: ./templates/*.json
  examples: ./examples/*.md
  shared: ../../_shared/*.json
---

# Add Feature v1.0

Полный lifecycle добавления новой функции в VLESS + Reality VPN.

## Когда использовать

- Добавление новой user management функции
- Добавление поддержки нового протокола
- Добавление новой CLI команды
- Любая значимая новая функциональность

## Workflow

### Phase 1: Load Context & Analysis

**ОБЯЗАТЕЛЬНО загрузи YAML документацию:**

```bash
Read docs/architecture/yaml/lib-modules.yaml  # Структура модулей, функции
Read docs/architecture/yaml/cli.yaml          # CLI команды
Read docs/architecture/yaml/docker.yaml       # Контейнеры
Read docs/architecture/yaml/dependencies.yaml # Dependency chains
```

**Затем:**
1. Спроси пользователя: "Опишите новую функцию (что делает, где добавить)"
2. Проанализируй lib-modules.yaml:
   - Какие модули затронуты?
   - Какие функции нужно добавить/изменить?
   - Где находятся эти модули (file paths, line numbers)?
3. Определи зависимости из dependencies.yaml
4. Создай dependency graph

### Phase 2: Planning (HYBRID)

**Используй:** `@skill:structured-planning`

**Создай план:**
1. Файлы для изменения (с номерами строк из lib-modules.yaml)
2. Новые функции для добавления
3. Изменения в существующих функциях
4. CLI команды (если нужны)
5. Тестовый план

**APPROVAL GATE:**
```
План реализации готов:

Затронутые модули:
- /opt/vless/lib/user_management.sh (add function at line ~1200)
- /opt/vless/lib/orchestrator.sh (modify function at line 856)

Новые функции:
- cmd_set_quota() - Set user bandwidth quota
- apply_quota_to_xray() - Apply quota to Xray config

Хотите приступить к реализации? (yes/no/review)
```

Жди подтверждения.

### Phase 3: Implementation (HYBRID)

**Для каждого файла:**

1. Read текущий код
2. Подготовь изменения
3. **КРИТИЧНО:** Добавь полное логирование:
   ```bash
   # Backend logging
   echo "[$(date)] cmd_set_quota: username=$username quota=$quota_gb" >> /opt/vless/logs/user_management.log

   # Console logging для debugging
   log_info "Setting quota for user $username: ${quota_gb}GB"
   ```

4. **APPROVAL GATE:**
   ```
   Изменения в /opt/vless/lib/user_management.sh:

   [показать diff]

   Применить? (yes/no/review)
   ```

5. Apply changes (Edit tool)

### Phase 4: Update YAML Documentation (HYBRID)

**ОБЯЗАТЕЛЬНО обнови docs/architecture/yaml/**

**Для новых функций в lib-modules.yaml:**

```yaml
- name: "cmd_set_quota"
  line: 1245  # Автоопределить из кода
  purpose: "Set user bandwidth quota in GB per month"
  parameters:
    - name: "username"
      type: "string"
      validation: "^[a-z][a-z0-9_-]{2,31}$"
    - name: "quota_gb"
      type: "integer"
      validation: "1-1000"
  calls:
    - "validate_username()"
    - "apply_quota_to_xray()"
    - "reload_xray()"
  returns: "exit_code (0=success, 1=failure)"
```

**Для новых CLI команд в cli.yaml:**

```yaml
- name: "quota"
  syntax: "vless quota <username> [quota_gb]"
  description: "Set or view user bandwidth quota"
  implementation:
    module: "user_management.sh"
    function: "cmd_set_quota"
    line: 1245
```

**APPROVAL GATE:**
```
YAML updates:

lib-modules.yaml:
[показать diff]

cli.yaml:
[показать diff]

Применить? (yes/no)
```

### Phase 5: Testing (AUTO)

```bash
# Syntax validation
Bash: bash -n /opt/vless/lib/user_management.sh

# Xray config validation (if modified)
Bash: xray test -c /opt/vless/config/xray_config.json

# Run unit tests (if available)
Bash: bash /opt/vless/lib/tests/test_user_management.sh 2>/dev/null || echo "No unit tests"
```

**Создай test report:**
```markdown
## Test Results

✅ Syntax validation: PASSED
✅ Xray config: VALID
⚠️ Unit tests: NOT AVAILABLE (create manual test plan)

Manual testing needed:
1. Add test user
2. Set quota
3. Verify quota applied in xray_config.json
4. Test with actual traffic
```

### Phase 6: Git Commit (HYBRID)

**Используй:** `@skill:git-workflow`

```bash
# Create branch
git checkout -b feature/user-quota

# Stage changes
git add lib/user_management.sh
git add docs/architecture/yaml/lib-modules.yaml
git add docs/architecture/yaml/cli.yaml

# Commit
git commit -m "feat: add user bandwidth quota management

Implement user quota feature with monthly GB limits.
- Add cmd_set_quota() function to user_management.sh
- Update Xray config generation with quota rules
- Update YAML documentation

🤖 Generated with Claude Code

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# Push
git push -u origin feature/user-quota
```

**APPROVAL GATE:**
```
Ready to push to remote? (yes/no)
```

## Safety Rules

```yaml
ALWAYS:
  - Загружай YAML context перед началом (Phase 1)
  - Добавляй полное логирование (console.log + backend)
  - Обновляй YAML documentation (lib-modules.yaml, cli.yaml)
  - Запрашивай approval перед Edit/Git push
  - Запускай syntax validation перед commit

NEVER:
  - Пропускай logging implementation
  - Пропускай YAML updates
  - Коммить без syntax validation
  - Force push to master
```

## Templates

**feature-plan.json:**
```json
{
  "feature_name": "User Quota Management",
  "affected_modules": [
    {
      "path": "/opt/vless/lib/user_management.sh",
      "changes": ["add cmd_set_quota()", "modify generate_xray_config()"]
    }
  ],
  "new_functions": [
    {
      "name": "cmd_set_quota",
      "parameters": ["username", "quota_gb"],
      "purpose": "Set user bandwidth quota"
    }
  ],
  "yaml_updates": ["lib-modules.yaml", "cli.yaml"],
  "test_plan": ["manual test with real user"]
}
```

## Example

См. `./examples/add-user-feature.md` для полного примера.

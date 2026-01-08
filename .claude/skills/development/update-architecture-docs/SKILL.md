---
name: Update Architecture Docs
description: Sync YAML documentation after code changes - detect stale entries and generate updates
version: 1.0.0
tags: [development, documentation, yaml, sync]
dependencies: []
files:
  templates: ./templates/*.md
  shared: ../../_shared/*.json
---

# Update Architecture Docs v1.0

Синхронизация YAML документации с кодом.

## Когда использовать

- После добавления новых функций
- После изменения модулей
- После добавления контейнеров
- Периодический sync check

## Workflow

### Phase 1: Load All YAML

```bash
Read docs/architecture/yaml/lib-modules.yaml
Read docs/architecture/yaml/cli.yaml
Read docs/architecture/yaml/docker.yaml
Read docs/architecture/yaml/dependencies.yaml
```

### Phase 2: Scan Code

**Scan lib/ modules:**

```bash
# Find all bash functions
Grep: "^[a-zA-Z_][a-zA-Z0-9_]*\(\)" /opt/vless/lib/ --output_mode content

# Count lines per module
Bash: wc -l /opt/vless/lib/*.sh
```

### Phase 3: Compare with YAML

**For each function in code:**
1. Есть ли в lib-modules.yaml?
2. Совпадает ли line number?
3. Совпадает ли signature?

**Identify:**
- ✅ In sync
- ⚠️ Stale (line numbers outdated)
- ❌ Missing (new functions not documented)
- 🗑️ Obsolete (documented but deleted from code)

### Phase 4: Generate Updates (HYBRID)

**Output:**

```markdown
## YAML Sync Report

**Missing in YAML (need to add):**
- user_management.sh:1245: set_user_quota()
- orchestrator.sh:920: apply_quota_rules()

**Stale entries (line numbers outdated):**
- user_management.sh:156: add_user_to_json() (actual: line 160)

**Obsolete entries (deleted from code):**
- utils.sh:200: deprecated_function()

**Proposed YAML updates:**

[show YAML additions/changes]

Apply updates? (yes/no)
```

### Phase 5: Apply Updates

Update YAML files with approved changes.

### Phase 6: Validate

```bash
# Validate YAML syntax
Bash: python3 docs/architecture/validate_architecture_docs.py

# Expected: All validations pass
```

## Safety Rules

```yaml
ALWAYS:
  - Scan ALL modules
  - Show diff before applying
  - Validate YAML after updates

NEVER:
  - Auto-delete obsolete entries без confirmation
  - Skip validation
```

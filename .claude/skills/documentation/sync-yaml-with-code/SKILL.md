---
name: Sync YAML with Code
description: Keep YAML documentation in sync with codebase - auto-detect changes
version: 1.0.0
tags: [documentation, yaml, sync, vless]
dependencies: [update-architecture-docs]
files:
  templates: ./templates/*.md
  shared: ../../_shared/*.json
---

# Sync YAML with Code v1.0

Автоматическая синхронизация YAML документации с кодом.

**Примечание:** Этот skill - wrapper для `update-architecture-docs` skill с фокусом на documentation workflow.

## Когда использовать

- После merge feature branch
- Перед release
- Периодический sync (раз в неделю)
- После major refactoring

## Workflow

### Phase 1: Run Full Scan

**Делегируй:** `@skill:update-architecture-docs`

Запусти полное сканирование кода и сравни с YAML.

### Phase 2: Review Sync Report

**Analyze:**
- Missing entries (новые функции/команды)
- Stale entries (outdated line numbers)
- Obsolete entries (deleted functions)

### Phase 3: Apply Updates (HYBRID)

**APPROVAL GATE:**
```
YAML Sync Updates Ready:

lib-modules.yaml:
+ 5 new functions
~ 12 stale line numbers
- 2 obsolete entries

cli.yaml:
+ 1 new command

Apply? (yes/no)
```

### Phase 4: Validate & Commit

```bash
# Validate YAML
Bash: python3 docs/architecture/validate_architecture_docs.py

# Git commit
git add docs/architecture/yaml/*.yaml
git commit -m "docs: sync YAML with code changes"
```

## Safety Rules

```yaml
ALWAYS:
  - Review all changes before applying
  - Validate YAML after sync
  - Commit sync separately from code changes
```

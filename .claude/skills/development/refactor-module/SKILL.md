---
name: Refactor Module
description: Refactor bash modules while maintaining functionality and validating call chains
version: 1.0.0
tags: [development, refactoring, vless, safety]
dependencies: [git-workflow]
files:
  templates: ./templates/*.json
  shared: ../../_shared/*.json
---

# Refactor Module v1.0

Безопасный рефакторинг bash модулей с проверкой dependency chains.

## Когда использовать

- Улучшение читаемости кода
- Извлечение дублированной логики
- Оптимизация производительности
- Реорганизация функций

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/lib-modules.yaml  # Module structure
Read docs/architecture/yaml/dependencies.yaml # Call chains
```

### Phase 2: Analyze Current State

1. Read модуль для рефакторинга
2. Найди в lib-modules.yaml:
   - Какие функции экспортирует модуль
   - Кто вызывает эти функции (call chains)
   - Внутренние зависимости

3. **КРИТИЧНО:** Определи breaking changes:
   - Меняются ли сигнатуры функций?
   - Меняются ли return values?
   - Удаляются ли функции?

### Phase 3: Refactor (HYBRID)

**Правила:**
- Сохраняй публичные API (function signatures)
- Добавляй логирование
- Улучшай читаемость

**APPROVAL GATE перед каждым изменением:**
```
Refactoring: extract_common_logic() from 3 functions

Changes:
[diff]

Safe to apply? (yes/no)
```

### Phase 4: Validate Call Chains

```bash
# Check all callers still work
grep -r "function_name" /opt/vless/lib/

# Syntax validation
bash -n /opt/vless/lib/module.sh
```

### Phase 5: Update YAML

Обнови lib-modules.yaml:
- Новые функции
- Измененные signatures
- Удаленные функции

### Phase 6: Git Commit

```
refactor: extract common validation logic in user_management

Extract validate_input() to reduce duplication.
No breaking changes to public API.
```

## Safety Rules

```yaml
ALWAYS:
  - Проверяй call chains before refactoring
  - Preserve public API
  - Update YAML documentation

NEVER:
  - Breaking changes без version bump
  - Удаляй функции без проверки зависимостей
```

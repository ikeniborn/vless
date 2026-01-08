---
name: Run Test Suite
description: Execute unit/integration/security/performance tests with intelligent filtering
version: 1.0.0
tags: [testing, vless, automation]
dependencies: []
files:
  shared: ../../_shared/*.json
---

# Run Test Suite v1.0

Запуск тестов с фильтрацией и reporting.

## Когда использовать

- Перед git commit
- После major changes
- Before release
- CI/CD pipeline

## Workflow

### Phase 1: Select Test Scope

Спроси: "Какие тесты запустить?"

1. **All** - Все тесты
2. **Unit** - Только unit tests
3. **Integration** - Integration tests (v4.3+)
4. **Security** - Security & DPI resistance tests
5. **Performance** - Performance benchmarks
6. **Module-specific** - Тесты для конкретного модуля

### Phase 2: Run Tests (AUTO)

**Unit Tests:**

```bash
Bash: bash /opt/vless/lib/tests/run_all_tests.sh
# OR module-specific:
Bash: bash /opt/vless/lib/tests/test_user_management.sh
```

**Integration Tests (v4.3+):**

```bash
Bash: bash /opt/vless/tests/integration/v4.3/run.sh
```

**Security Tests:**

```bash
Bash: sudo vless test-security
# OR quick mode:
Bash: sudo vless test-security --quick
```

### Phase 3: Collect Results

**Parse test output:**
- Total tests
- Passed
- Failed
- Skipped

**Capture failed test details:**
- Test name
- Error message
- Stack trace (if available)

### Phase 4: Generate Report

```markdown
## Test Suite Report

**Scope:** {All | Unit | Integration | Security}
**Date:** {timestamp}

### Summary
- Total: {count}
- ✅ Passed: {count}
- ❌ Failed: {count}
- ⏭️ Skipped: {count}

### Failed Tests
{test_name}: {error_message}

### Recommendations
{suggestions based on failures}
```

### Phase 5: Present Results

**If all passed:**
```
✅ All tests passed! Safe to commit.
```

**If failures:**
```
❌ {count} tests failed. Review failures before committing.

Failed tests:
- test_user_quota: AssertionError
- test_xray_reload: Container not responding

Fix these issues first.
```

## Safety Rules

```yaml
ALWAYS:
  - Run tests before suggesting commit
  - Show failed test details
  - Recommend fixes for failures

NEVER:
  - Skip tests because "it should work"
  - Commit with failing tests
```

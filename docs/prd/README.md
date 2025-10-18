# PRD v4.3 - Структурированная документация

Это структурированная версия Product Requirements Document (PRD) для проекта **VLESS + Reality VPN Server**.

## Структура документации

Исходный [PRD.md](../../PRD.md) (1545 строк) разделен на 7 логических модулей для удобной навигации:

| Файл | Содержание | Размер |
|------|-----------|--------|
| **[00_summary.md](00_summary.md)** | 📋 **Итоговое саммари** - точка входа, быстрая навигация, ключевые метрики | ~16 KB |
| **[01_overview.md](01_overview.md)** | 📖 Document Control, Executive Summary, Version History, Product Overview | ~12 KB |
| **[02_functional_requirements.md](02_functional_requirements.md)** | 🔧 Все функциональные требования (FR-*): HAProxy unified, TLS, certificates, IP whitelist, reverse proxy (v4.3) | ~35 KB |
| **[03_nfr.md](03_nfr.md)** | 📊 Non-Functional Requirements (NFR-*): Security, Performance, Compatibility, Usability | ~8 KB |
| **[04_architecture.md](04_architecture.md)** | 🏗️ Technical Architecture: Section 4.7 HAProxy Unified, Network diagrams, Data flow, File structure | ~28 KB |
| **[05_testing.md](05_testing.md)** | 🧪 Testing Requirements: TLS tests, HAProxy tests, Security tests, v4.3 test suite | ~10 KB |
| **[06_appendix.md](06_appendix.md)** | 📚 Implementation, Security Risk, Success Metrics, Dependencies, Rollback, References | ~8 KB |

**Общий размер:** ~117 KB

---

## Быстрый старт

### Для новых пользователей

Начните с **[00_summary.md](00_summary.md)** - это Executive Summary со всеми ключевыми моментами и навигацией.

### Для разработчиков

1. **Обзор системы:** [01_overview.md](01_overview.md)
2. **Требования:** [02_functional_requirements.md](02_functional_requirements.md) + [03_nfr.md](03_nfr.md)
3. **Архитектура:** [04_architecture.md](04_architecture.md)
4. **Тестирование:** [05_testing.md](05_testing.md)

### Для администраторов

- **Быстрый старт:** [00_summary.md](00_summary.md#быстрый-старт)
- **Troubleshooting:** [06_appendix.md](06_appendix.md#12-rollback--troubleshooting)
- **Security:** [03_nfr.md](03_nfr.md) + [06_appendix.md](06_appendix.md#6-security-risk-assessment)

---

## Навигация между разделами

Каждый файл содержит:
- **Навигационное меню вверху и внизу** - быстрые ссылки на все разделы
- **Перекрестные ссылки** на CLAUDE.md и CHANGELOG.md
- **Внутренние якоря** для навигации внутри больших разделов

Пример меню:
```
[Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) |
[NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) |
[Приложения](06_appendix.md) | [← Саммари](00_summary.md)
```

---

## Связь с другой документацией

### Основные документы проекта

- **[README.md](../../README.md)** - User guide, installation instructions
- **[CHANGELOG.md](../../CHANGELOG.md)** - Version history, breaking changes, migration guides
- **[CLAUDE.md](../../CLAUDE.md)** - Project memory, technical details, troubleshooting
- **[PRD.md](../../PRD.md)** - Исходный consolidated PRD (source for this split)

### Разделение ответственности

| Документ | Назначение | Целевая аудитория |
|----------|-----------|-------------------|
| **README.md** | User guide, quick start | End users, administrators |
| **CHANGELOG.md** | Version history, migrations | Developers, administrators |
| **CLAUDE.md** | Project memory, implementation | Developers, AI assistant |
| **PRD.md** (этот) | Product requirements, architecture | Product managers, developers |

---

## История версий PRD

| Версия | Дата | Ключевые изменения |
|--------|------|--------------------|
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture - subdomain-based reverse proxy (https://domain, NO port), ports 9443-9452, stunnel REMOVED |
| **v4.2** | 2025-10-17 | Reverse proxy planning (intermediate, see v4.3 for implementation) |
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix (https://, socks5s://) |
| **v4.0** | 2025-10-06 | stunnel TLS termination architecture (deprecated in v4.3) |
| **v3.6** | 2025-10-06 | Server-level IP whitelist |
| **v3.3** | 2025-10-05 | Mandatory TLS for public proxies (CRITICAL security fix) |
| **v3.1** | 2025-10-03 | Dual proxy (SOCKS5 + HTTP, localhost-only) |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN system |

**Полная история:** [CHANGELOG.md](../../CHANGELOG.md)

---

## Статус реализации

### v4.3 (Production)

✅ **100% COMPLETE** - все активные фичи реализованы

| Компонент | Статус |
|-----------|--------|
| VLESS Reality VPN | ✅ Production |
| HAProxy Unified Architecture | ✅ v4.3 |
| Subdomain-Based Reverse Proxy | ✅ v4.3 (https://domain, NO port) |
| SNI Routing (HAProxy) | ✅ v4.3 |
| Dual Proxy (SOCKS5 + HTTP) | ✅ v4.1+ |
| Heredoc Config Generation | ✅ v4.1+ |
| Port Range 9443-9452 (localhost) | ✅ v4.3 |
| fail2ban Integration (HAProxy) | ✅ v4.3 |
| IP Whitelisting (server-level) | ✅ v3.6+ |
| Let's Encrypt Auto-Renewal | ✅ v3.3+ |
| v4.3 Test Suite (automated) | ✅ v4.3 |

---

## Использование

### Чтение offline

Все файлы - обычный Markdown, читаются в любом редакторе или браузере.

### Поиск

```bash
# Поиск по всем файлам PRD
grep -r "stunnel" docs/prd/

# Поиск конкретного требования
grep -r "FR-STUNNEL-001" docs/prd/
```

### Генерация PDF (опционально)

```bash
# Установка pandoc (если не установлен)
sudo apt install pandoc

# Генерация PDF из всех разделов
cd docs/prd/
pandoc 00_summary.md 01_overview.md 02_functional_requirements.md \
       03_nfr.md 04_architecture.md 05_testing.md 06_appendix.md \
       -o PRD_v4.1_complete.pdf
```

---

## Поддержка и обратная связь

- **Issues:** https://github.com/user/vless-reality-vpn/issues (если проект опубликован)
- **Обновления:** Следите за [CHANGELOG.md](../../CHANGELOG.md)
- **Вопросы:** Проверьте [06_appendix.md](06_appendix.md#14-references) - Technical References

---

**Создано:** 2025-10-16
**Обновлено:** 2025-10-18
**Версия PRD:** v4.3
**Статус:** Production-Ready ✅

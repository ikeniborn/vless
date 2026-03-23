# MTProxy Integration Documentation

**Version:** v6.1 (Released)
**Status:** ✅ COMPLETED (Core Features Implemented)
**Priority:** HIGH
**Last Updated:** 2025-11-08

---

## Quick Navigation

| Document | Purpose | Audience |
|----------|---------|----------|
| **[00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md)** | Base implementation plan (v6.0) | Developers, Project Managers |
| **[01_advanced_features.md](01_advanced_features.md)** | Advanced features specification (v6.1+) | Developers, Architects |
| **[02_install_integration.md](02_install_integration.md)** | Integration with install.sh | Developers |
| **This README** | Quick reference and overview | All stakeholders |

---

## What is MTProxy?

**MTProxy** - официальный прокси-сервер Telegram для туннелирования MTProto трафика.

**Ключевые характеристики:**
- ✅ Специализирован для Telegram клиентов
- ✅ Transport obfuscation (AES-256-CTR) для обхода DPI
- ✅ Random padding для маскировки размеров пакетов
- ✅ One-tap подключение в Telegram (tg://proxy deep links)
- ✅ Поддержка всех официальных клиентов (Android, iOS, Desktop, Web)

---

## Integration Overview

### Цель интеграции

Добавить MTProxy в VLESS Reality VPN project (v5.33) как **opt-in сервис** для пользователей Telegram.

### Scope v6.0 (Base Implementation)

**В scope:**
- ✅ Отдельный Docker контейнер `familytraffic-mtproxy`
- ✅ Opt-in установка через install.sh wizard
- ✅ Генерация клиентских конфигураций (deep links, QR codes)
- ✅ fail2ban интеграция
- ✅ UFW firewall rules
- ✅ CLI управление секретами (single-user mode)
- ✅ Базовый мониторинг (/stats endpoint)
- ✅ Heredoc-based конфигурация (соответствие PRD v4.1+)

**Детали:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md)

---

### Scope v6.1 (Advanced Features)

**В scope:**
- ✅ Multi-user support с уникальными секретами (до 50 пользователей)
- ✅ Fake-TLS support (`ee` prefix secrets) для дополнительной маскировки
- ✅ Promoted channel интеграция (@MTProxybot)
- ✅ Advanced statistics & analytics (HAProxy logging + external analytics)
- ✅ Per-user secret management CLI
- ✅ Graceful secret rotation без остановки сервиса

**Ограничения протокола (Protocol Constraints):**
- ⚠️ HAProxy SNI routing - **невозможно** (MTProto не использует SNI)
- ⚠️ Per-secret statistics - **не поддерживается** MTProxy (только server-level stats)
- ⚠️ Live secret reload - **невозможно** (требуется graceful restart)
- ⚠️ Max 50 users - рекомендация для стабильности (технически до 100)

**Детали:** См. [01_advanced_features.md](01_advanced_features.md)

### Architecture Changes

**Before (v5.33):**
```
5 контейнеров: HAProxy, Xray, Nginx, Certbot, Fake Site
```

**After (v6.0):**
```
6 контейнеров: HAProxy, Xray, Nginx, Certbot, Fake Site, MTProxy (NEW)
```

**New Port:**
- `8443/tcp` - MTProxy public port (Telegram traffic)

---

## Key Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-MTPROXY-001 | MTProxy Docker Container | CRITICAL | Planned |
| FR-MTPROXY-002 | Opt-in Installation Wizard | HIGH | Planned |
| FR-MTPROXY-003 | Secret Management CLI | HIGH | Planned |
| FR-MTPROXY-004 | Client Configuration Generation | HIGH | Planned |
| FR-MTPROXY-005 | fail2ban Integration | MEDIUM | Planned |
| FR-MTPROXY-006 | UFW Firewall Rules | MEDIUM | Planned |
| FR-MTPROXY-007 | Basic Monitoring | LOW | Planned |

**Детали:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#5-functional-requirements)

---

## Non-Functional Requirements

| ID | Requirement | Target | Acceptance |
|----|-------------|--------|------------|
| NFR-MTPROXY-001 | Performance | < 10ms latency overhead | Benchmark test |
| NFR-MTPROXY-002 | Reliability | 99.5% uptime | Auto-restart enabled |
| NFR-MTPROXY-003 | Security | DPI-resistant | Transport obfuscation |
| NFR-MTPROXY-004 | Usability | < 3 min installation | Interactive wizard |
| NFR-MTPROXY-005 | Compatibility | All Telegram clients | Test matrix (7 clients) |

**Детали:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#6-non-functional-requirements)

---

## Implementation Phases (4 Weeks)

| Phase | Week | Goal | Deliverable |
|-------|------|------|-------------|
| **Phase 1** | 1 | Core Infrastructure | Работающий MTProxy контейнер |
| **Phase 2** | 2 | Secret Management | CLI для управления секретами |
| **Phase 3** | 2 | Client Configuration | Автоматическая генерация конфигов |
| **Phase 4** | 3 | Installation Wizard | Opt-in установка |
| **Phase 5** | 3 | fail2ban & UFW | Интеграция безопасности |
| **Phase 6** | 4 | Monitoring & Status | Интеграция мониторинга |
| **Phase 7** | 4 | Documentation & Testing | Документация + тесты |

**Детальный план:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#8-implementation-phases)

---

## CLI Commands (Planned)

**Installation:**
```bash
sudo mtproxy-setup              # Interactive wizard (called from install.sh)
sudo mtproxy-uninstall          # Complete removal
```

**Secret Management (v6.0 - Single-user mode):**
```bash
sudo familytraffic-mtproxy add-secret [--with-padding]
sudo familytraffic-mtproxy list-secrets
sudo familytraffic-mtproxy remove-secret <secret>
sudo familytraffic-mtproxy regenerate-secret <old-secret>
sudo familytraffic-mtproxy show-config [<secret>]
```

**Multi-User Support (v6.1 - Advanced):**
```bash
# User-based secret management
sudo familytraffic-mtproxy add-user <username> [--fake-tls <domain>]
sudo familytraffic-mtproxy remove-user <username>
sudo familytraffic-mtproxy list-users
sudo familytraffic-mtproxy show-user-config <username>

# Promoted channel integration
sudo familytraffic-mtproxy set-promoted-channel <channel_id>
sudo familytraffic-mtproxy remove-promoted-channel
```

**Configuration:**
```bash
sudo familytraffic-mtproxy set-port <port>
sudo familytraffic-mtproxy set-workers <count>
```

**Monitoring:**
```bash
sudo familytraffic-mtproxy stats [--live]
sudo familytraffic status                     # Shows MTProxy section
```

---

## Testing Strategy

### Test Categories

**1. Unit Tests** (20 test cases)
- Secret generation, validation
- Config generation (deep links, QR codes)
- Stats parsing

**2. Integration Tests** (6 test cases)
- Docker container lifecycle
- fail2ban jail creation and banning
- UFW rule management
- Stats API accessibility

**3. End-to-End Tests** (5 test cases)
- Fresh installation
- Client connection (Android, iOS, Desktop)
- Message send/receive
- Secret regeneration

**4. Compatibility Tests** (7 clients)
- Telegram Android, iOS, Desktop (Windows/macOS/Linux), Web (Chrome/Firefox)

**5. Performance Tests** (5 metrics)
- Latency (<10ms overhead)
- Throughput (≥100 Mbps)
- CPU usage (<5%)
- Memory (<100 MB)
- Concurrent connections (100 clients)

**6. Security Tests** (5 aspects)
- Transport obfuscation (Wireshark)
- DPI resistance (nDPI)
- fail2ban banning
- UFW rate limiting
- Secret validation

**Детали:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#9-testing-strategy)

---

## Risk Assessment

### High Priority Risks

| Risk ID | Risk | Mitigation |
|---------|------|------------|
| RISK-001 | Docker build fails | Test on 4 platforms (Ubuntu 20.04/22.04, Debian 10/11) |
| RISK-003 | Telegram blocks IP | Monitor connectivity, prepare rotation strategy |
| RISK-004 | DPI bypass fails | Monitor detection tools (nDPI), verify obfuscation |
| RISK-013 | Upstream vulnerability | Subscribe to GitHub security advisories |

**Детальный анализ:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#10-risk-assessment)

---

## Migration Plan

### For Existing Users (v5.33 → v6.0)

**Steps:**
1. Backup current configuration
2. Update codebase to v6.0
3. Run `mtproxy-setup`
4. Verify installation
5. Test client connection

**Rollback:** Доступен в любой момент (MTProxy независим от VLESS)

**Детали:** См. [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md#11-migration--rollback)

---

## References

### Official Telegram Documentation
- **MTProto Protocol:** https://core.telegram.org/mtproto
- **MTProto Transports:** https://core.telegram.org/mtproto/mtproto-transports
- **MTProxy GitHub:** https://github.com/TelegramMessenger/MTProxy

### VLESS Project Documents
- **PRD Summary:** [docs/prd/00_summary.md](../prd/00_summary.md)
- **Architecture:** [docs/prd/04_architecture.md](../prd/04_architecture.md)
- **CHANGELOG:** [CHANGELOG.md](../../CHANGELOG.md)
- **Project Memory:** [CLAUDE.md](../../CLAUDE.md)

---

## Document Structure

```
docs/mtproxy/
├── README.md                              ← You are here (Quick reference)
├── 00_mtproxy_integration_plan.md         ← Base implementation v6.0 (63KB, 2000+ lines)
├── 01_advanced_features.md                ← Advanced features v6.1+ (detailed specification)
└── 02_install_integration.md              ← Integration with install.sh (heredoc patterns)
```

**Рекомендуемый порядок чтения:**
1. README.md (этот файл) - общий обзор
2. 00_mtproxy_integration_plan.md - базовая реализация
3. 01_advanced_features.md - расширенные функции (опционально)
4. 02_install_integration.md - детали интеграции с install.sh

---

## Quick Start (For Readers)

### Для пользователей проекта:
1. **Читайте:** Этот README для понимания что такое MTProxy
2. **Ждите:** v6.0 release (базовая функциональность)
3. **После релиза v6.0:** Запустите `sudo ./install.sh` и выберите MTProxy при установке
4. **Для v6.1 features:** Дождитесь релиза v6.1 (multi-user support, promoted channels)

### Для разработчиков (v6.0 Base Implementation):
1. **Читайте:** [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md) (полный план v6.0)
2. **Изучите:** [02_install_integration.md](02_install_integration.md) (интеграция с install.sh)
3. **Начните:** Phase 1 - Core Infrastructure (Docker container)

### Для разработчиков (v6.1 Advanced Features):
1. **Читайте:** [01_advanced_features.md](01_advanced_features.md) (спецификация расширенных функций)
2. **Изучите:** Protocol Constraints секцию (ограничения MTProto)
3. **Начните:** После завершения v6.0 (multi-user требует базовой инфраструктуры)

### Для project managers:
1. **Executive Summary:** [00_mtproxy_integration_plan.md#1-executive-summary](00_mtproxy_integration_plan.md#1-executive-summary)
2. **v6.0 Timeline:** 4 weeks (7 phases, базовая функциональность)
3. **v6.1 Timeline:** +2-3 weeks (расширенные функции)
4. **Resources:** 1 developer, existing VLESS infrastructure
5. **Risk:** LOW-MEDIUM (см. Risk Assessment в 00_mtproxy_integration_plan.md)

---

## Status & Next Steps

**Current Status:** 📝 PLANNING PHASE (Documentation v6.0 + v6.1 Complete)

**Documentation Status:**
- ✅ **DONE:** Base implementation plan (v6.0) - 00_mtproxy_integration_plan.md
- ✅ **DONE:** Advanced features specification (v6.1) - 01_advanced_features.md
- ⏳ **IN PROGRESS:** Integration with install.sh - 02_install_integration.md (создаётся)
- ✅ **DONE:** Quick reference README (этот файл)

**Next Steps (v6.0 - Base Implementation):**
1. ✅ **DONE:** Comprehensive documentation created (v6.0 + v6.1)
2. ⏳ **TODO:** Complete 02_install_integration.md (install.sh + heredoc patterns)
3. ⏳ **TODO:** Review and approval by stakeholders
4. ⏳ **TODO:** Begin Phase 1 implementation (Core Infrastructure)
5. ⏳ **TODO:** Update CHANGELOG.md with v6.0 plans

**Next Steps (v6.1 - Advanced Features):**
1. ⏳ **TODO:** Complete v6.0 base implementation first
2. ⏳ **TODO:** Implement multi-user support (unique secrets per user)
3. ⏳ **TODO:** Implement promoted channel integration
4. ⏳ **TODO:** Implement advanced analytics (HAProxy logging)
5. ⏳ **TODO:** Document protocol limitations and workarounds

**Timeline:**
- **Planning:** Week 1 (CURRENT - документация v6.0 + v6.1)
- **v6.0 Implementation:** Weeks 2-5 (Phases 1-7, базовая функциональность)
- **v6.0 Testing & QA:** Week 6
- **v6.0 Release:** ETA: +6 weeks from approval
- **v6.1 Implementation:** +2-3 weeks after v6.0 (расширенные функции)
- **v6.1 Release:** ETA: +9 weeks from approval

---

## Contact & Feedback

**Questions:**
- Telegram: Create issue в GitHub репозитории
- Email: См. CLAUDE.md для контактов

**Feedback:**
- GitHub Issues: https://github.com/[your-repo]/vless/issues
- Pull Requests: Welcome (following contribution guidelines)

---

**Created:** 2025-11-07
**Last Updated:** 2025-11-08
**Version:** 1.1 (Updated with v6.1 advanced features + install.sh integration)
**Status:** ⏳ IN PROGRESS (Awaiting 02_install_integration.md completion)

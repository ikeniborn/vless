# MTProxy Integration Documentation

**Version:** 6.0-draft
**Status:** 📝 PLANNING PHASE
**Priority:** HIGH

---

## Quick Navigation

| Document | Purpose | Audience |
|----------|---------|----------|
| **[00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md)** | Comprehensive integration plan | Developers, Project Managers |
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

### Scope v6.0

**В scope:**
- ✅ Отдельный Docker контейнер `vless_mtproxy`
- ✅ Opt-in установка через wizard
- ✅ Генерация клиентских конфигураций (deep links, QR codes)
- ✅ fail2ban интеграция
- ✅ UFW firewall rules
- ✅ CLI управление секретами
- ✅ Базовый мониторинг (/stats endpoint)

**Не в scope (future):**
- ❌ Multi-user support (один секрет для всех)
- ❌ Promoted channel интеграция
- ❌ Advanced statistics
- ❌ HAProxy routing

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
sudo vless-mtproxy-setup              # Interactive wizard
sudo vless-mtproxy-uninstall          # Complete removal
```

**Secret Management:**
```bash
sudo vless-mtproxy add-secret [--with-padding]
sudo vless-mtproxy list-secrets
sudo vless-mtproxy remove-secret <secret>
sudo vless-mtproxy regenerate-secret <old-secret>
```

**Configuration:**
```bash
sudo vless-mtproxy show-config [<secret>]
sudo vless-mtproxy set-port <port>
sudo vless-mtproxy set-workers <count>
```

**Monitoring:**
```bash
sudo vless-mtproxy stats [--live]
sudo vless status                     # Shows MTProxy section
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
3. Run `vless-mtproxy-setup`
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
└── 00_mtproxy_integration_plan.md         ← Comprehensive plan (23KB, 1500+ lines)
```

---

## Quick Start (For Readers)

### Для пользователей проекта:
1. **Читайте:** Этот README для понимания что такое MTProxy
2. **Ждите:** v6.0 release (implementation в процессе)
3. **После релиза:** Запустите `sudo vless-mtproxy-setup`

### Для разработчиков:
1. **Читайте:** [00_mtproxy_integration_plan.md](00_mtproxy_integration_plan.md) (полный plan)
2. **Изучите:** Section 8 (Implementation Phases) для task breakdown
3. **Начните:** Phase 1 (Core Infrastructure)

### Для project managers:
1. **Executive Summary:** [00_mtproxy_integration_plan.md#1-executive-summary](00_mtproxy_integration_plan.md#1-executive-summary)
2. **Timeline:** 4 weeks (7 phases)
3. **Resources:** 1 developer, existing VLESS infrastructure
4. **Risk:** LOW-MEDIUM (см. Risk Assessment)

---

## Status & Next Steps

**Current Status:** 📝 PLANNING PHASE (Documentation Complete)

**Next Steps:**
1. ✅ **DONE:** Comprehensive documentation created
2. ⏳ **TODO:** Review and approval by stakeholders
3. ⏳ **TODO:** Begin Phase 1 implementation (Core Infrastructure)
4. ⏳ **TODO:** Update CHANGELOG.md with v6.0 plans

**Timeline:**
- Planning: Week 1 (CURRENT)
- Implementation: Weeks 2-5 (Phases 1-7)
- Testing & QA: Week 6
- Release: v6.0 (ETA: +6 weeks from approval)

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
**Last Updated:** 2025-11-07
**Version:** 1.0 (Initial draft)
**Status:** ✅ COMPLETE (Ready for review)

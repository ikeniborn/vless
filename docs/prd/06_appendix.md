# PRD v4.1 - Appendix

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 5. Implementation Details & Migration History

**For implementation specifics and historical migration guides, see:**
- **[CHANGELOG.md](../../CHANGELOG.md)** - Detailed version history, breaking changes, migration guides
- **[CLAUDE.md Section 8](../../CLAUDE.md#8-project-structure)** - Current implementation architecture (v4.1)

**Current v4.1 Implementation Summary:**
- **Config Generation:** Heredoc-based (lib/stunnel_setup.sh, lib/orchestrator.sh, lib/user_management.sh)
- **TLS Termination:** stunnel container (separate from Xray)
- **Proxy Ports:** stunnel:1080/8118 (TLS) → Xray:10800/18118 (plaintext)
- **IP Whitelisting:** server-level via proxy_allowed_ips.json + Xray routing + optional UFW
- **Client Configs:** 6 formats auto-generated with correct URI schemes (https://, socks5s://)

---

## 6. Security Risk Assessment

**For detailed security analysis, threat modeling, and mitigation strategies, see:**
- **[CLAUDE.md Section 15](../../CLAUDE.md#15-security--debug)** - Security Threat Matrix, Best Practices, Debug Commands
- **[CHANGELOG.md](../../CHANGELOG.md)** - Historical security improvements (v3.2 → v3.3 TLS migration)

**Current v4.1 Security Posture:**
- ✅ **TLS 1.3 Encryption:** stunnel termination for all proxy connections (v4.0+)
- ✅ **Let's Encrypt Certificates:** Automated certificate management with auto-renewal
- ✅ **32-Character Passwords:** Brute-force resistant credentials
- ✅ **fail2ban Protection:** Automated IP banning after 5 failed attempts
- ✅ **UFW Rate Limiting:** 10 connections/minute per IP on proxy ports
- ✅ **DPI Resistance:** Reality protocol makes VPN traffic indistinguishable from HTTPS

---

## 8. Acceptance Criteria

**For historical v3.x acceptance criteria and migration checklists, see:**
- **[CHANGELOG.md](../../CHANGELOG.md)** - Phase-by-phase acceptance criteria for v3.2 → v3.3, v3.5 → v3.6, v4.0, v4.1 releases

**v4.1 Implementation Status:** All features ✅ **COMPLETE** (see Implementation Status table in [Overview](01_overview.md))

---

## 9. Out of Scope (v3.3)

The following are explicitly NOT included:

- ❌ Self-signed certificates (Let's Encrypt only)
- ❌ Plain proxy fallback option (TLS mandatory)
- ❌ Manual certificate installation (certbot only)
- ❌ Alternative ACME challenges (DNS-01, TLS-ALPN-01)
- ❌ Reality protocol for proxy inbounds (TLS chosen for compatibility)
- ❌ Certificate monitoring dashboard (email alerts only)
- ❌ Traffic logging (privacy requirement, unchanged)
- ❌ Per-user bandwidth limits (unlimited, unchanged)

---

## 10. Success Metrics

**For detailed performance targets, test results, and success criteria, see:**
- **[CLAUDE.md Section 16](../../CLAUDE.md#16-success-metrics)** - Current v4.1 success metrics, performance targets, overall success formula

**Quick Summary:**

**Performance Targets:**
- Installation: < 7 minutes (v4.1 with certbot + stunnel setup)
- User Creation: < 5 seconds (consistent up to 50 users)
- Container Startup: < 10 seconds
- Config Reload: < 3 seconds

**Test Results (v4.1):**
- ✅ DPI Resistance: Traffic identical to HTTPS (Wireshark validated)
- ✅ stunnel TLS Termination: Separate logs, simpler Xray config
- ✅ Multi-VPN: Different subnets detected, both VPNs work simultaneously
- ✅ Update: User data preserved, downtime < 30 seconds

---

## 11. Dependencies

**For complete dependency list with versions and installation requirements, see:**
- **[CLAUDE.md Section 7](../../CLAUDE.md#7-critical-system-parameters)** - Technology Stack (Docker, Xray, stunnel), Shell & Tools, Security Testing Tools

**Quick Summary (v4.1):**

**Container Images:**
- xray: `teddysun/xray:24.11.30`
- stunnel: `dweomer/stunnel:latest` (NEW in v4.0)
- nginx: `nginx:alpine`

**System Requirements:**
- Ubuntu 20.04+ / Debian 10+ (primary support)
- Docker 20.10+
- Docker Compose v2.0+
- UFW firewall (auto-installed)

**Tools:**
- bash 4.0+
- jq 1.5+ (JSON processing)
- openssl (system default)
- certbot (Let's Encrypt certificates)
- fail2ban (brute-force protection)

---

## 12. Rollback & Troubleshooting

**For rollback procedures, troubleshooting guides, and common failure points, see:**
- **[CLAUDE.md Section 11](../../CLAUDE.md#11-common-failure-points--solutions)** - Issue detection, solutions, debug workflows
- **[CHANGELOG.md](../../CHANGELOG.md)** - Historical rollback scenarios (v3.2 → v3.3, v3.5 → v3.6)

**Quick Debug Commands:**

```bash
# System Status
sudo vless-status                    # Full system status (includes proxy info)
docker ps                            # Check container health
docker logs vless_stunnel            # stunnel TLS logs (v4.0+)
docker logs vless_xray               # Xray proxy logs

# Config Validation
jq . /opt/vless/config/xray_config.json      # Validate JSON syntax
jq . /opt/vless/config/stunnel.conf          # stunnel config (v4.0+)

# Network Tests
sudo ss -tulnp | grep -E '443|1080|8118'     # Check listening ports
openssl s_client -connect server:1080        # Test TLS on SOCKS5
curl -I --proxy https://user:pass@server:8118 https://google.com  # Test HTTPS proxy

# Security Tests
sudo vless test-security             # Run comprehensive security test suite
sudo vless test-security --quick     # Quick mode (skip long tests)
```

---

## 13. Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | User | 2025-10-07 | Approved (v4.1 heredoc + URI fix) |
| Tech Lead | Claude | 2025-10-07 | PRD v4.1 Complete |
| Security Review | Approved | 2025-10-06 | v4.0 stunnel TLS termination ✅ |

**Version History:**
- v4.1 (2025-10-07): Heredoc config generation + Proxy URI fix ✅ **CURRENT**
- v4.0 (2025-10-06): stunnel TLS termination architecture ✅ Approved
- v3.6 (2025-10-06): Server-level IP whitelist ✅ Approved
- v3.3 (2025-10-05): Mandatory TLS for public proxies ✅ Security Approved

---

## 14. References

### 14.1 Technical Documentation

- Xray TLS Configuration: https://xtls.github.io/config/transport.html#tlsobject
- stunnel Documentation: https://www.stunnel.org/static/stunnel.html (v4.0+)
- Let's Encrypt ACME HTTP-01: https://letsencrypt.org/docs/challenge-types/
- Certbot User Guide: https://eff-certbot.readthedocs.io/
- SOCKS5 RFC 1928: https://www.rfc-editor.org/rfc/rfc1928
- TLS 1.3 RFC 8446: https://www.rfc-editor.org/rfc/rfc8446

### 14.2 Project Documentation

- **[README.md](../../README.md)** - User guide, installation instructions
- **[CHANGELOG.md](../../CHANGELOG.md)** - Version history, breaking changes
- **[CLAUDE.md](../../CLAUDE.md)** - Project memory, technical details
- **[PRD.md](../../PRD.md)** - Original consolidated PRD (this document split)

### 14.3 Workflow Artifacts

- Phase 1: `/home/ikeniborn/Documents/Project/vless/workflow/phase1_technical_analysis.xml`
- Phase 2: `/home/ikeniborn/Documents/Project/vless/workflow/phase2_requirements_specification.xml`
- Phase 3: `/home/ikeniborn/Documents/Project/vless/workflow/phase3_unified_understanding.xml`
- User Responses: `/home/ikeniborn/Documents/Project/vless/workflow/phase1_user_responses.xml`

---

**END OF PRD v4.1**

**Next Steps:**
1. ✅ Review and approve PRD v4.1
2. ✅ Implementation complete (100% features implemented)
3. Monitor production performance
4. Plan v4.2 enhancements (if needed)

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

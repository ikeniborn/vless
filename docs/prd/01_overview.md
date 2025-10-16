# PRD v4.1 - Overview

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 4.1 | 2025-10-07 | System | **Heredoc migration + Proxy URI fix**: Remove templates/, heredoc config generation, fix proxy URI schemes (https://, socks5s://) |
| 4.0 | 2025-10-06 | System | **stunnel integration**: TLS termination via stunnel + template-based configuration |
| 3.6 | 2025-10-06 | System | **Server-level IP whitelist**: Migration from per-user to server-level proxy access control |
| 3.5 | 2025-10-06 | System | **IP-based access control**: Per-user IP whitelisting for proxy servers |
| 3.4 | 2025-10-05 | System | **Optional TLS**: Made TLS encryption optional (plaintext mode for dev/testing) |
| 3.3 | 2025-10-05 | System | **CRITICAL SECURITY FIX:** Mandatory TLS encryption for public proxies via Let's Encrypt |
| 3.2 | 2025-10-04 | System | Public proxy support (SECURITY ISSUE: no encryption) |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Implementation Status (v4.1)

| Feature | PRD Section | Status | Notes |
|---------|-------------|--------|-------|
| stunnel TLS termination | FR-STUNNEL-001 | ✅ COMPLETE | stunnel container + heredoc config (v4.0/v4.1) |
| Config generation (heredoc) | - | ✅ COMPLETE | lib/stunnel_setup.sh, no templates/ (v4.1) |
| Proxy URI schemes fix | FR-CONFIG-001 | ✅ COMPLETE | https://, socks5s:// (v4.1 bugfix) |
| Docker Compose stunnel service | Section 4.5 | ✅ COMPLETE | vless_stunnel container (v4.0) |
| IP whitelisting (server-level) | FR-IP-001 | ✅ COMPLETE | proxy_allowed_ips.json + optional UFW (v4.0) |
| Xray plaintext inbounds | FR-STUNNEL-001 | ✅ COMPLETE | localhost:10800/18118 (v4.0) |
| 6 proxy config files | FR-CONFIG-001 | ✅ COMPLETE | All formats with correct URIs (v4.1) |
| Template-based configs | FR-TEMPLATE-001 | ❌ DEPRECATED | Replaced by heredoc in v4.1 |

**Overall Status:** v4.1 is **100% implemented** (all active features complete, templates deprecated).

---

## Executive Summary

### Current Version: v4.1 (Implemented)

**Latest Updates:**
- ✅ **v4.1 (2025-10-07)**: Heredoc config generation + Proxy URI fix (https://, socks5s://)
- ✅ **v4.0 (2025-10-06)**: stunnel TLS termination architecture
- ✅ **v3.6 (2025-10-06)**: Server-level IP whitelist (migration from v3.5 per-user)
- ✅ **v3.5 (2025-10-06)**: Per-user IP-based access control for proxy servers
- ✅ **v3.4 (2025-10-05)**: Optional TLS encryption (plaintext mode for dev/testing)
- ✅ **v3.3 (2025-10-05)**: Mandatory TLS encryption for public proxies

**System Capabilities:**
- **VLESS Reality VPN:** DPI-resistant VPN tunnel
- **Dual Proxy Modes:** SOCKS5 (1080) + HTTP (8118)
- **TLS Termination:** stunnel handles TLS 1.3 encryption (v4.0+)
- **Heredoc Config Generation:** All configs via heredoc (v4.1, simplified from v4.0 templates)
- **Correct Proxy URIs:** https:// and socks5s:// for TLS connections (v4.1 fix)
- **IP Whitelisting:** Server-level + optional UFW firewall rules (v4.0+)
- **Multi-Format Configs:** 6 auto-generated config files per user

---

### What's New in v4.1

**PRIMARY FEATURE:** Heredoc config generation + Proxy URI scheme fix.

**Key Changes:**

| Component | v4.0 | v4.1 | Status |
|-----------|------|------|--------|
| **Config Generation** | templates/ + envsubst | heredoc in lib/*.sh | ✅ IMPLEMENTED |
| **stunnel.conf** | templates/stunnel.conf.template | heredoc in lib/stunnel_setup.sh | ✅ IMPLEMENTED |
| **Proxy URI Schemes** | http://, socks5:// | https://, socks5s:// | ✅ IMPLEMENTED (BUGFIX) |
| **Dependencies** | bash, envsubst | bash only | ✅ SIMPLIFIED |

**Benefits:**
- **Unified codebase**: All configs (Xray, stunnel, docker-compose) use heredoc
- **Simpler dependencies**: Removed envsubst (GNU gettext) requirement
- **Correct proxy URIs**: https:// and socks5s:// for TLS connections
- **Fewer files**: 1 file instead of 2 (template + script)

---

### What's New in v4.0

**PRIMARY FEATURE:** stunnel-based TLS termination architecture.

**Key Architectural Changes:**

| Component | v3.x | v4.0 | Status |
|-----------|------|------|--------|
| **TLS Handling** | Xray streamSettings | stunnel (separate container) | ✅ IMPLEMENTED |
| **Proxy Ports** | 1080/8118 (TLS in Xray) | 1080/8118 (stunnel) → 10800/18118 (Xray plaintext) | ✅ IMPLEMENTED |
| **Configuration** | Inline heredocs in scripts | Template files (v4.0), heredoc (v4.1) | ✅ IMPLEMENTED (v4.1) |
| **IP Whitelisting** | Xray routing only | Xray routing + optional UFW | ✅ IMPLEMENTED |

**New CLI Commands (4):**
```bash
vless add-ufw-ip <ip>             # Add IP to UFW whitelist for proxy ports
vless remove-ufw-ip <ip>          # Remove IP from UFW whitelist
vless show-ufw-ips                # Display UFW proxy rules
vless reset-ufw-ips               # Remove all UFW proxy rules
```

**Architecture Overview:**
```
Client → stunnel (TLS termination, ports 1080/8118)
       → Xray (plaintext proxy, localhost 10800/18118)
       → Internet
```

**Technical Implementation (v4.0/v4.1):**
- **v4.1:** `lib/stunnel_setup.sh` - stunnel config generation via heredoc (removed templates/)
- **v4.1:** `lib/user_management.sh` - proxy URI fix (https://, socks5s://)
- **v4.0:** stunnel container - TLS 1.3 termination for proxy ports
- **v4.0:** `lib/ufw_whitelist.sh` - UFW-based IP whitelisting
- **v4.0:** `lib/orchestrator.sh` - removed TLS from Xray inbounds, added stunnel service

**Benefits:**
1. **Mature TLS Stack:** stunnel has 20+ years of production stability
2. **Simpler Xray Config:** No TLS complexity in Xray, focus on proxy logic
3. **Better Debugging:** Separate logs for TLS (stunnel) vs proxy (Xray)
4. **Template-Based:** All configs generated from templates, easier to version and review
5. **Optional UFW:** Host-level firewall rules for additional security layer
6. **Defense-in-Depth:** Multiple security layers (stunnel TLS + Xray auth + UFW + fail2ban)

**Migration from v3.x:**
- Existing installations will be migrated automatically during update
- Client configs remain compatible (same ports, same URIs)
- Zero downtime migration (rolling restart)
- Backward compatibility maintained

---

### Version History Summary

**For detailed migration guides and breaking changes, see:** [CHANGELOG.md](../../CHANGELOG.md)

| Version | Date | Key Feature | Status | Notes |
|---------|------|-------------|--------|-------|
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix | ✅ **CURRENT** | https://, socks5s://, removed templates/ |
| **v4.0** | 2025-10-06 | stunnel TLS termination architecture | ✅ Implemented | Separate TLS layer, plaintext Xray inbounds |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | ⚠️ Superseded | Migration from v3.5 per-user to server-level |
| **v3.5** | 2025-10-06 | Per-user IP-based access control | ⚠️ Superseded | Xray routing rules, deprecated in v3.6 |
| **v3.4** | 2025-10-05 | Optional TLS encryption | ⚠️ Superseded | Plaintext mode for dev/testing |
| **v3.3** | 2025-10-05 | Mandatory TLS for public proxies | ⚠️ Superseded | Let's Encrypt integration, certbot |
| **v3.2** | 2025-10-04 | Public proxy support (no encryption) | ❌ Deprecated | SECURITY ISSUE - plaintext credentials |
| **v3.1** | 2025-10-03 | Dual proxy (SOCKS5 + HTTP, localhost) | ⚠️ Superseded | Localhost-only binding, VPN required |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | ⚠️ Superseded | No proxy support |

**Current Production Architecture (v4.1):**
- **VLESS Reality VPN:** DPI-resistant tunnel (port 443)
- **stunnel TLS Termination:** Handles TLS 1.3 for proxy ports (1080, 8118)
- **Dual Proxy:** SOCKS5 + HTTP with unified credentials
- **IP Whitelisting:** Server-level Xray routing + optional UFW firewall
- **Config Generation:** Heredoc-based (all configs inline in lib/*.sh)
- **Client Configs:** 6 formats with correct TLS URI schemes

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + **Secure** Proxy server deployable in < 7 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing
- **Secure SOCKS5 Proxy:** TLS-encrypted proxy on port 1080 (v4.0+ stunnel termination)
- **Secure HTTP Proxy:** HTTPS proxy on port 8118 (v4.0+ stunnel termination)
- **Hybrid Mode:** VPN for some devices, encrypted proxy for others
- **Zero Trust Network:** No plaintext proxy access, TLS mandatory

### 1.2 Target Users

- **Primary:** System administrators deploying secure VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** Encrypted proxy for desktop applications (VSCode, Git, Docker)
- **Use Case 3:** Mixed deployment (VPN + Encrypted Proxy simultaneously)
- **Use Case 4:** Development teams requiring secure proxy for CI/CD pipelines

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

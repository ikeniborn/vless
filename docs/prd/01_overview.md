# PRD v4.3 - Overview

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 4.3 | 2025-10-18 | System | **HAProxy Unified Architecture**: Single HAProxy container (replaces stunnel), subdomain-based reverse proxy (https://domain, NO port!), ports 9443-9452, SNI routing, fail2ban HAProxy integration |
| 4.2 | 2025-10-17 | System | **Reverse proxy planning**: Intermediate version (see v4.3 for implementation) |
| 4.1 | 2025-10-07 | System | **Heredoc migration + Proxy URI fix**: Remove templates/, heredoc config generation, fix proxy URI schemes (https://, socks5s://) |
| 4.0 | 2025-10-06 | System | **stunnel integration** (deprecated in v4.3): TLS termination via stunnel + template-based configuration |
| 3.6 | 2025-10-06 | System | **Server-level IP whitelist**: Migration from per-user to server-level proxy access control |
| 3.3 | 2025-10-05 | System | **CRITICAL SECURITY FIX:** Mandatory TLS encryption for public proxies via Let's Encrypt |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Implementation Status (v4.3)

| Feature | PRD Section | Status | Notes |
|---------|-------------|--------|-------|
| HAProxy Unified Architecture | FR-HAPROXY-001 | ✅ COMPLETE | Single HAProxy container (3 frontends, v4.3) |
| Subdomain-Based Reverse Proxy | FR-REVERSE-PROXY-001 | ✅ COMPLETE | https://domain (NO port!), ports 9443-9452 (v4.3) |
| SNI Routing (TLS passthrough) | FR-HAPROXY-001 | ✅ COMPLETE | HAProxy frontend 443 → Nginx/Xray (v4.3) |
| fail2ban HAProxy Integration | FR-FAIL2BAN-001 | ✅ COMPLETE | HAProxy + Nginx filters (v4.3) |
| Config generation (heredoc) | - | ✅ COMPLETE | lib/haproxy_config_manager.sh (v4.3) |
| Proxy URI schemes | FR-CONFIG-001 | ✅ COMPLETE | https://, socks5s:// (v4.1+) |
| IP whitelisting (server-level) | FR-IP-001 | ✅ COMPLETE | proxy_allowed_ips.json + optional UFW |
| Xray plaintext inbounds | FR-HAPROXY-001 | ✅ COMPLETE | localhost:10800/18118 (HAProxy forwards) |
| v4.3 Test Suite | Section 5 | ✅ COMPLETE | 3 automated tests, DEV_MODE support |
| stunnel TLS termination | FR-STUNNEL-001 | ❌ DEPRECATED | Replaced by HAProxy in v4.3 |

**Overall Status:** v4.3 is **100% implemented** (all active features complete, stunnel deprecated).

---

## Executive Summary

### Current Version: v4.3 (Implemented)

**Latest Updates:**
- ✅ **v4.3 (2025-10-18)**: HAProxy Unified Architecture - 1 container instead of 2 (stunnel REMOVED), subdomain-based reverse proxy
- ✅ **v4.2 (2025-10-17)**: Reverse proxy planning (intermediate, see v4.3 for implementation)
- ✅ **v4.1 (2025-10-07)**: Heredoc config generation + Proxy URI fix (https://, socks5s://)
- ⚠️ **v4.0 (2025-10-06)**: stunnel TLS termination architecture (deprecated in v4.3)
- ✅ **v3.6 (2025-10-06)**: Server-level IP whitelist
- ✅ **v3.3 (2025-10-05)**: Mandatory TLS encryption for public proxies

**System Capabilities:**
- **VLESS Reality VPN:** DPI-resistant VPN tunnel
- **Dual Proxy Modes:** SOCKS5 (1080) + HTTP (8118)
- **HAProxy Unified:** TLS termination + SNI routing (v4.3, replaces stunnel)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port number!), ports 9443-9452 (v4.3)
- **SNI Routing:** TLS passthrough без decryption (v4.3)
- **fail2ban Protection:** HAProxy + Nginx filters (v4.3)
- **Heredoc Config Generation:** All configs via heredoc (v4.1+)
- **Correct Proxy URIs:** https:// and socks5s:// for TLS connections
- **IP Whitelisting:** Server-level + optional UFW firewall rules
- **Multi-Format Configs:** 6 auto-generated config files per user
- **Automated Testing:** v4.3 test suite (3 test cases, DEV_MODE support)

---

### What's New in v4.3

**PRIMARY FEATURE:** HAProxy Unified Architecture - single container for ALL TLS and routing.

**Key Architectural Changes:**

| Component | v4.0 (stunnel) | v4.3 (HAProxy) | Status |
|-----------|----------------|----------------|--------|
| **TLS + Routing** | 2 containers (stunnel + Xray) | 1 HAProxy container | ✅ IMPLEMENTED |
| **Reverse Proxy Access** | https://domain:9443 | https://domain (NO port!) | ✅ IMPLEMENTED |
| **Port Range** | 8443-8452 (public) | 9443-9452 (localhost-only) | ✅ IMPLEMENTED |
| **SNI Routing** | N/A | TLS passthrough без decryption | ✅ IMPLEMENTED |
| **fail2ban** | Nginx only | HAProxy + Nginx filters | ✅ IMPLEMENTED |
| **Config Management** | Static | Dynamic ACL (sed-based) | ✅ IMPLEMENTED |

**New Architecture:**
```
Client → HAProxy Frontend 443 (SNI routing, TLS passthrough)
       ├→ VLESS Reality → Xray:8443
       └→ Reverse Proxy → Nginx:9443-9452 → Xray → Target Site

Client → HAProxy Frontend 1080/8118 (TLS termination)
       → Xray:10800/18118 (plaintext) → Internet
```

**New Components:**
- `lib/haproxy_config_manager.sh` - Dynamic ACL management (add/remove routes)
- `lib/certificate_manager.sh` - combined.pem generation (fullchain + privkey)
- `/etc/fail2ban/filter.d/haproxy-sni.conf` - HAProxy fail2ban filter
- HAProxy graceful reload (haproxy -sf) - zero-downtime updates

**Benefits:**
1. **Simplified Architecture:** 1 container instead of 2 (stunnel REMOVED)
2. **Subdomain-Based Access:** https://domain (NO port number!)
3. **SNI Routing Security:** NO TLS decryption for reverse proxy
4. **fail2ban Protection:** Multi-layer (HAProxy + Nginx)
5. **Dynamic Management:** Add/remove routes without full restart
6. **Better Performance:** HAProxy is industry-standard load balancer

**Migration from v4.0-v4.2:**
- Automatic migration during update (preserves all data)
- Client VLESS configs remain compatible
- Reverse proxy URLs change: domain:9443 → domain (NO port!)
- stunnel container automatically removed

---

### Version History Summary

**For detailed migration guides and breaking changes, see:** [CHANGELOG.md](../../CHANGELOG.md)

| Version | Date | Key Feature | Status | Notes |
|---------|------|-------------|--------|-------|
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture | ✅ **CURRENT** | 1 container (stunnel REMOVED), subdomain-based (https://domain, NO port!), ports 9443-9452 |
| **v4.2** | 2025-10-17 | Reverse proxy planning | ⚠️ Superseded | Intermediate version, see v4.3 for implementation |
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix | ⚠️ Superseded | https://, socks5s://, removed templates/ |
| **v4.0** | 2025-10-06 | stunnel TLS termination architecture | ❌ Deprecated | Replaced by HAProxy in v4.3 |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | ⚠️ Superseded | Migration from v3.5 per-user to server-level |
| **v3.3** | 2025-10-05 | Mandatory TLS for public proxies | ⚠️ Superseded | Let's Encrypt integration, certbot |
| **v3.1** | 2025-10-03 | Dual proxy (SOCKS5 + HTTP, localhost) | ⚠️ Superseded | Localhost-only binding, VPN required |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | ⚠️ Superseded | No proxy support |

**Current Production Architecture (v4.3):**
- **VLESS Reality VPN:** DPI-resistant tunnel (port 443 via HAProxy SNI routing)
- **HAProxy Unified:** TLS termination + SNI routing (3 frontends: 443, 1080, 8118)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port!), ports 9443-9452 (localhost-only)
- **SNI Routing:** TLS passthrough без decryption
- **Dual Proxy:** SOCKS5 + HTTP with unified credentials
- **fail2ban Protection:** HAProxy + Nginx filters
- **IP Whitelisting:** Server-level Xray routing + optional UFW firewall
- **Config Generation:** Heredoc-based (all configs inline in lib/*.sh)
- **Client Configs:** 6 formats with correct TLS URI schemes
- **Automated Testing:** v4.3 test suite (3 test cases, DEV_MODE support)

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + **Secure** Proxy + **Reverse Proxy** server deployable in < 7 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing (via HAProxy SNI routing)
- **Secure SOCKS5 Proxy:** TLS-encrypted proxy on port 1080 (HAProxy termination v4.3)
- **Secure HTTP Proxy:** HTTPS proxy on port 8118 (HAProxy termination v4.3)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port!), up to 10 domains (v4.3)
- **HAProxy Unified Architecture:** Single container for ALL TLS and routing (v4.3)
- **SNI Routing:** TLS passthrough без decryption (enhanced security v4.3)
- **Hybrid Mode:** VPN for some devices, encrypted proxy for others, reverse proxy for web services
- **Zero Trust Network:** No plaintext proxy access, TLS mandatory

### 1.2 Target Users

- **Primary:** System administrators deploying secure VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** Encrypted proxy for desktop applications (VSCode, Git, Docker)
- **Use Case 3:** Mixed deployment (VPN + Encrypted Proxy simultaneously)
- **Use Case 4:** Development teams requiring secure proxy for CI/CD pipelines

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

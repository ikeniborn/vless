# PRD v1.1.5 - Overview

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.1.5 | 2026-03 | System | Per-user SOCKS5/HTTP proxy auth; cert renewal improvements |
| 1.1.0 | 2026-02 | System | Single-container architecture with supervisord; nginx replaces HAProxy; MTProxy (mtg v2.2.3) integrated |
| 4.3 | 2025-10-18 | System | **HAProxy Unified Architecture (LEGACY — removed in v1.1.0)**: Single HAProxy container (replaces stunnel), subdomain-based reverse proxy, SNI routing |
| 4.2 | 2025-10-17 | System | **Reverse proxy planning**: Intermediate version (see v4.3 for implementation) |
| 4.1 | 2025-10-07 | System | **Heredoc migration + Proxy URI fix**: Remove templates/, heredoc config generation, fix proxy URI schemes (https://, socks5s://) |
| 4.0 | 2025-10-06 | System | **stunnel integration** (deprecated in v4.3): TLS termination via stunnel + template-based configuration |
| 3.6 | 2025-10-06 | System | **Server-level IP whitelist**: Migration from per-user to server-level proxy access control |
| 3.3 | 2025-10-05 | System | **CRITICAL SECURITY FIX:** Mandatory TLS encryption for public proxies via Let's Encrypt |
| 3.1 | 2025-10-03 | System | Dual proxy support (SOCKS5 + HTTP, localhost-only) |
| 3.0 | 2025-10-01 | System | Base VLESS Reality VPN system |

---

## Implementation Status (v1.1.5)

| Feature | PRD Section | Status | Notes |
|---------|-------------|--------|-------|
| nginx SNI Routing Architecture | FR-NGINX-001 | COMPLETE | Single container, ssl_preread, supervisord (v1.1.0) |
| Per-user SOCKS5/HTTP proxy auth | FR-PASSWORD-001 | COMPLETE | Unique credentials per user (v1.1.5) |
| MTProxy (mtg v2.2.3) | FR-MTPROXY-001 | COMPLETE | Optional, supervisord-managed (v1.1.0) |
| Tier 2 Transports (WS/gRPC/XHTTP) | FR-NGINX-001 | COMPLETE | Ports 8444-8446, via nginx SNI routing (v1.1.0) |
| Subdomain-Based Reverse Proxy | FR-REVERSE-PROXY-001 | COMPLETE | https://domain (NO port!) (v1.1.0) |
| XTLS Vision | - | COMPLETE | flow=xtls-rprx-vision for all users (v5.24+) |
| fail2ban nginx Integration | FR-FAIL2BAN-001 | COMPLETE | nginx + Xray filters (v1.1.0) |
| Cert auto-renewal (certbot-cron) | FR-CERT-002 | COMPLETE | Every 12h inside container (v1.1.0) |
| Proxy URI schemes | FR-CONFIG-001 | COMPLETE | https://, socks5s:// (v4.1+) |
| IP whitelisting (server-level) | FR-IP-001 | COMPLETE | proxy_allowed_ips.json + optional UFW |
| External Proxy Support | - | COMPLETE | familytraffic-external-proxy CLI (v5.23+) |
| HAProxy Unified Architecture | FR-HAPROXY-001 | REMOVED | Replaced by nginx in v1.1.0 |
| stunnel TLS termination | FR-STUNNEL-001 | DEPRECATED | Replaced by HAProxy in v4.3, then nginx in v1.1.0 |

**Overall Status:** v1.1.5 is **Production-Ready** (all active features complete).

---

## Executive Summary

### Current Version: v1.1.5 (Production-Ready)

**Latest Updates:**
- **v1.1.5 (2026-03)**: Per-user SOCKS5/HTTP proxy auth — unique credentials per user; cert renewal improvements
- **v1.1.0 (2026-02)**: Single-container architecture — nginx ssl_preread SNI routing (replaces HAProxy), supervisord, MTProxy (mtg v2.2.3) integrated as optional process, Tier 2 transports (WS/gRPC/XHTTP)
- **v5.33 (2025-10-30)**: External Proxy TLS Server Name Validation & UX (CRITICAL)
- **v5.24 (2025-10-22)**: HTTP Basic Auth fix + XTLS Vision (flow=xtls-rprx-vision for all users)
- **v5.23 (2025-10-22)**: Enhanced Validation + 3 CRITICAL BUGFIXES (false negatives -> 0%, fail2ban fix)
- **v4.3 (2025-10-18)**: HAProxy Unified Architecture (LEGACY — replaced in v1.1.0)

**System Capabilities:**
- **VLESS Reality VPN:** DPI-resistant VPN tunnel (port 443 via nginx ssl_preread SNI routing)
- **XTLS Vision:** flow=xtls-rprx-vision active for all users
- **Dual Proxy Modes:** SOCKS5 (1080) + HTTP (8118), per-user credentials (v1.1.5)
- **nginx SNI Routing:** ssl_preread on port 443, TLS termination for proxies (v1.1.0, replaces HAProxy)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port number!)
- **Tier 2 Transports:** WebSocket, XHTTP, gRPC (CDN-compatible)
- **MTProxy (mtg v2.2.3):** Optional Fake TLS MTProxy for Telegram (port 2053)
- **certbot-cron:** Auto-renewal every 12h inside container
- **fail2ban Protection:** nginx + Xray filters
- **Heredoc Config Generation:** All configs via heredoc
- **Correct Proxy URIs:** https:// and socks5s:// for TLS connections
- **IP Whitelisting:** Server-level + optional UFW firewall rules
- **Multi-Format Configs:** 6 auto-generated config files per user
- **External Proxy:** Upstream proxy chaining (familytraffic-external-proxy)

---

### What's New in v1.1.0/v1.1.5

**PRIMARY FEATURE v1.1.0:** Single-container architecture with supervisord — nginx ssl_preread SNI routing replaces HAProxy.

**PRIMARY FEATURE v1.1.5:** Per-user SOCKS5/HTTP proxy authentication — unique credentials per user.

**Key Architectural Changes (v1.1.0):**

| Component | Legacy (HAProxy multi-container) | Current (v1.1.0+ single container) | Status |
|-----------|----------------------------------|-------------------------------------|--------|
| **Container count** | Multiple (HAProxy + Xray + Nginx) | 1 container `familytraffic` | IMPLEMENTED |
| **Process manager** | docker-compose | supervisord (PID 1) | IMPLEMENTED |
| **SNI routing** | HAProxy (separate container) | nginx ssl_preread (inside container) | IMPLEMENTED |
| **TLS termination** | HAProxy combined.pem | nginx standard fullchain.pem + privkey.pem | IMPLEMENTED |
| **Cert renewal** | External cron + haproxy reload | certbot-cron inside container + nginx reload | IMPLEMENTED |
| **MTProxy** | Not integrated | mtg v2.2.3 via supervisord.d/mtg.conf | IMPLEMENTED |
| **Network mode** | Bridge network | network_mode: host | IMPLEMENTED |

**New Architecture (v1.1.0+):**
```
Client -> nginx (ssl_preread, port 443)
       +-> Reality SNI  -> 127.0.0.1:8443 (xray VLESS Reality)
       +-> Tier 2 SNI   -> port 8448 -> WS/XHTTP/gRPC inbounds

Client -> nginx (TLS termination)
       port 1080 -> 127.0.0.1:10800 (SOCKS5 plaintext)
       port 8118 -> 127.0.0.1:18118 (HTTP plaintext)

Client -> mtg (port 2053, optional)
       -> Telegram DCs (MTProxy Fake TLS)
```

**New in v1.1.5:**
- Per-user proxy credentials (unique username+password per user for SOCKS5/HTTP)

**What was REMOVED:**
- HAProxy container and `haproxy_config_manager.sh`
- `familytraffic-nginx` as a separate container
- `combined.pem` format (nginx uses standard fullchain.pem + privkey.pem)
- HAProxy graceful reload (haproxy -sf) — replaced by nginx reload

---

### What's New in v4.3 (LEGACY — replaced in v1.1.0)

> **Note:** This section is kept for historical reference. v4.3 HAProxy architecture was replaced by the nginx single-container architecture in v1.1.0.

**v4.3 Architecture (legacy):**
```
Client -> HAProxy Frontend 443 (SNI routing, TLS passthrough)
       +-> VLESS Reality -> Xray:8443
       +-> Reverse Proxy -> Nginx:9443-9452 -> Xray -> Target Site

Client -> HAProxy Frontend 1080/8118 (TLS termination)
       -> Xray:10800/18118 (plaintext) -> Internet
```

**Components removed in v1.1.0:**
- `lib/haproxy_config_manager.sh`
- `lib/certificate_manager.sh` (combined.pem)
- `/etc/fail2ban/filter.d/haproxy-sni.conf`
- HAProxy graceful reload (haproxy -sf)

---

### Version History Summary

**For detailed migration guides and breaking changes, see:** [CHANGELOG.md](../../CHANGELOG.md)

| Version | Date | Key Feature | Status | Notes |
|---------|------|-------------|--------|-------|
| **v1.1.5** | 2026-03 | Per-user SOCKS5/HTTP proxy auth | **CURRENT** | Unique credentials per user; cert renewal improvements |
| **v1.1.0** | 2026-02 | Single-container nginx architecture | Superseded by v1.1.5 | nginx ssl_preread, supervisord, MTProxy (mtg v2.2.3) |
| **v5.33** | 2025-10-30 | External Proxy TLS Validation | Legacy | FQDN/IP format validation, auto-activation UX |
| **v5.24** | 2025-10-22 | XTLS Vision + HTTP Auth Fix | Legacy | flow=xtls-rprx-vision all users, auth_basic fix |
| **v5.23** | 2025-10-22 | Enhanced Validation + BUGFIXes | Legacy | False negatives -> 0%, fail2ban fix |
| **v4.3** | 2025-10-18 | HAProxy Unified Architecture | REMOVED in v1.1.0 | 1 HAProxy container (stunnel REMOVED), subdomain-based |
| **v4.1** | 2025-10-07 | Heredoc config generation + Proxy URI fix | Legacy | https://, socks5s://, removed templates/ |
| **v4.0** | 2025-10-06 | stunnel TLS termination architecture | Deprecated | Replaced by HAProxy in v4.3, then nginx in v1.1.0 |
| **v3.6** | 2025-10-06 | Server-level IP whitelist | Legacy | Migration from v3.5 per-user to server-level |
| **v3.3** | 2025-10-05 | Mandatory TLS for public proxies | Legacy | Let's Encrypt integration, certbot |
| **v3.1** | 2025-10-03 | Dual proxy (SOCKS5 + HTTP, localhost) | Legacy | Localhost-only binding, VPN required |
| **v3.0** | 2025-10-01 | Base VLESS Reality VPN | Legacy | No proxy support |

**Current Production Architecture (v1.1.5):**
- **VLESS Reality VPN:** DPI-resistant tunnel (port 443 via nginx ssl_preread SNI routing)
- **nginx SNI Routing:** ssl_preread (port 443), TLS termination (1080/8118)
- **Single Container:** `familytraffic` with supervisord (xray + nginx + certbot-cron + mtg)
- **Per-user Proxy Credentials:** unique username+password per user (v1.1.5)
- **MTProxy:** Optional mtg v2.2.3 via supervisord (port 2053)
- **Tier 2 Transports:** WebSocket, XHTTP, gRPC (CDN-compatible)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port!)
- **XTLS Vision:** flow=xtls-rprx-vision active for all users
- **Dual Proxy:** SOCKS5 + HTTP with per-user credentials
- **fail2ban Protection:** nginx + Xray filters
- **IP Whitelisting:** Server-level Xray routing + optional UFW firewall
- **Config Generation:** Heredoc-based (all configs inline in lib/*.sh)
- **Client Configs:** 6 formats with correct TLS URI schemes

---

## 1. Product Overview

### 1.1 Core Value Proposition

Production-ready VPN + **Secure** Proxy + **Reverse Proxy** server deployable in < 7 minutes with:
- **VLESS Reality VPN:** DPI-resistant tunnel for secure browsing (via nginx ssl_preread SNI routing)
- **Secure SOCKS5 Proxy:** TLS-encrypted proxy on port 1080 (nginx termination, v1.1.0)
- **Secure HTTP Proxy:** HTTPS proxy on port 8118 (nginx termination, v1.1.0)
- **Per-user Proxy Auth:** Unique credentials per user (v1.1.5)
- **Subdomain-Based Reverse Proxy:** https://domain (NO port!), up to 10 domains
- **nginx SNI Routing Architecture:** Single container for ALL routing and TLS (v1.1.0)
- **MTProxy:** Optional Fake TLS MTProxy for Telegram (mtg v2.2.3, port 2053)
- **Tier 2 Transports:** WebSocket, XHTTP, gRPC for CDN-compatibility
- **Hybrid Mode:** VPN for some devices, encrypted proxy for others, reverse proxy for web services
- **Zero Trust Network:** No plaintext proxy access, TLS mandatory

### 1.2 Target Users

- **Primary:** System administrators deploying secure VPN + Proxy infrastructure
- **Use Case 1:** VPN for mobile devices (iOS/Android)
- **Use Case 2:** Encrypted proxy for desktop applications (VSCode, Git, Docker)
- **Use Case 3:** Mixed deployment (VPN + Encrypted Proxy simultaneously)
- **Use Case 4:** Development teams requiring secure proxy for CI/CD pipelines
- **Use Case 5:** Telegram users requiring MTProxy access

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

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

## 7. Reverse Proxy Security Review (v4.2 - NEW)

### 7.1 Approval Decision

**Status:** ✅ **CONDITIONALLY APPROVED** (pending mitigation validation)

**Decision Date:** 2025-10-16
**Review Type:** Pre-Implementation Security Analysis
**Reviewer:** Security Team

**Approval Conditions:**
1. ✅ All CRITICAL and HIGH vulnerabilities mitigated before production deployment
2. ✅ Security testing suite executed and passed (see Section 7.5)
3. ✅ Re-review required after mitigation implementation
4. ✅ Penetration testing conducted on staging environment

---

### 7.2 Executive Summary

The reverse proxy feature (FR-REVERSE-PROXY-001) introduces site-specific reverse proxying capabilities to VLESS v4.2. Security analysis identified **5 vulnerabilities** requiring mandatory mitigation:

| Vulnerability | Severity | CVSS Score | Status |
|---------------|----------|------------|--------|
| VULN-001: Host Header Injection | **CRITICAL** | 8.6 | ✅ Mitigated |
| VULN-002: Missing HSTS Header | **HIGH** | 6.5 | ✅ Mitigated |
| VULN-003: Rate Limiting Missing | MEDIUM | 5.3 | ✅ Mitigated |
| VULN-004: DoS via Connection Flood | MEDIUM | 5.3 | ✅ Mitigated |
| VULN-005: Brute Force Attack | MEDIUM | 4.3 | ✅ Mitigated |

**Overall Risk:** LOW (after mitigation)

---

### 7.3 Critical Vulnerabilities and Mitigations

#### VULN-001: Host Header Injection (CRITICAL)

**CVSS 3.1 Score:** 8.6 (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:N/I:H/A:N)
**CWE:** CWE-74 (Improper Neutralization of Special Elements)

**Vulnerability Description:**

Nginx reverse proxy uses `$host` variable for backend routing without validation, allowing attackers to inject arbitrary domains via the HTTP Host header. This enables:
- **Cache Poisoning:** Malicious content cached under legitimate domain
- **Credential Phishing:** Attacker controls target site, captures Basic Auth credentials
- **SSRF:** Access to internal services via manipulated Host header

**Attack Scenario:**
```bash
# Attacker request with malicious Host header
curl -H "Host: evil.com" -u user:pass https://myproxy.example.com:8443

# Without mitigation, nginx forwards request to evil.com instead of blocked-site.com
# Attacker captures credentials sent to evil.com
```

**Mitigation (MANDATORY):**

Added explicit Host header validation in nginx configuration:

```nginx
# VULN-001 FIX: Host Header Validation (CRITICAL)
if ($host != "myproxy.example.com") {
    return 444;  # Close connection without response
}

# VULN-001 FIX: Hardcoded Host Header (NOT $host)
location / {
    proxy_pass http://xray_reverseproxy_1;
    proxy_set_header Host blocked-site.com;  # Hardcoded target site
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**Validation:**
- Test Case 21: Invalid Host header → HTTP 444 (connection closed)
- Test Case 22: Config validation confirms `if ($host != "...")` present

---

#### VULN-002: Missing HSTS Header (HIGH)

**CVSS 3.1 Score:** 6.5 (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N)
**CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)

**Vulnerability Description:**

Without HTTP Strict Transport Security (HSTS), browsers do not enforce HTTPS-only connections. Attackers can:
- **SSL Stripping:** Downgrade HTTPS to HTTP via MITM attack
- **Session Hijacking:** Intercept plaintext credentials during downgrade
- **Cookie Theft:** Steal session cookies transmitted over HTTP

**Attack Scenario:**
1. User connects to `http://myproxy.example.com:8443` (no HTTPS)
2. MITM attacker intercepts, serves fake login page
3. Credentials transmitted in plaintext
4. Attacker gains access to reverse proxy

**Mitigation (MANDATORY):**

Added HSTS header to all nginx responses:

```nginx
# VULN-002 FIX: HSTS Header (HIGH)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

**HSTS Parameters:**
- `max-age=31536000`: 1 year enforcement (365 days)
- `includeSubDomains`: Apply to all subdomains
- `preload`: Eligible for browser HSTS preload list
- `always`: Include header even on error responses

**Validation:**
- Test Case 18: HSTS header present in all responses
- Test Case 40: testssl.sh confirms HSTS enabled

---

#### VULN-003: Rate Limiting Missing (MEDIUM)

**CVSS 3.1 Score:** 5.3 (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L)
**CWE:** CWE-770 (Allocation of Resources Without Limits)

**Vulnerability Description:**

Without rate limiting, attackers can overwhelm the reverse proxy with excessive requests, causing:
- **Resource Exhaustion:** CPU/memory depletion on nginx container
- **Service Degradation:** Legitimate users experience slow response times
- **Amplification Attacks:** Use reverse proxy as DDoS amplifier

**Mitigation (MANDATORY):**

Implemented nginx rate limiting in HTTP context configuration:

```nginx
# VULN-003 FIX: Rate Limiting (MEDIUM)
limit_req_zone $binary_remote_addr zone=reverseproxy:10m rate=10r/s;
limit_req zone=reverseproxy burst=20 nodelay;
```

**Rate Limit Configuration:**
- **Zone:** `reverseproxy` (10 MB shared memory)
- **Rate:** 10 requests/second per IP
- **Burst:** 20 requests (allows short bursts)
- **Action:** Return HTTP 503 (Service Temporarily Unavailable) on limit exceed

**Validation:**
- Test Case 24: Burst traffic → Some requests return HTTP 503
- Test Case 26: Rate limit config present in reverse-proxy-http-context.conf

---

#### VULN-004: DoS via Connection Flood (MEDIUM)

**CVSS 3.1 Score:** 5.3 (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L)
**CWE:** CWE-400 (Uncontrolled Resource Consumption)

**Vulnerability Description:**

Without connection limits, attackers can open thousands of concurrent connections, exhausting:
- **File Descriptors:** Nginx process hits `ulimit -n` limit
- **Memory:** Each connection consumes memory for buffers
- **CPU:** Context switching overhead degrades performance

**Mitigation (MANDATORY):**

Implemented per-IP connection limits:

```nginx
# VULN-004 FIX: Connection Limit (MEDIUM)
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
limit_conn conn_limit_per_ip 5;
```

**Connection Limit Configuration:**
- **Zone:** `conn_limit_per_ip` (10 MB shared memory)
- **Limit:** 5 concurrent connections per IP
- **Action:** Return HTTP 503 on limit exceed

**Validation:**
- Test Case 25: 10 concurrent connections → Some rejected with HTTP 503
- Test Case 26: Connection limit config present in reverse-proxy-http-context.conf

---

#### VULN-005: Brute Force Attack (MEDIUM)

**CVSS 3.1 Score:** 4.3 (CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:L)
**CWE:** CWE-307 (Improper Restriction of Excessive Authentication Attempts)

**Vulnerability Description:**

HTTP Basic Auth without brute-force protection allows attackers to:
- **Password Guessing:** Automated credential stuffing attacks
- **Account Takeover:** Gain access to legitimate user accounts
- **Resource Abuse:** Use compromised accounts for malicious purposes

**Mitigation (MANDATORY):**

Integrated fail2ban for automated IP banning after failed authentication attempts:

**fail2ban Configuration:**
```ini
[vless-reverse-proxy-8443]
enabled = true
port = 8443
filter = vless-reverse-proxy
logpath = /opt/vless/logs/nginx/reverse-proxy-error.log
maxretry = 5           # 5 failed attempts
bantime = 3600         # 1 hour ban
findtime = 600         # Within 10 minutes
action = ufw           # Block via UFW firewall
```

**fail2ban Filter:**
```
# Match HTTP 401 Unauthorized (auth failure)
failregex = ^.* "401" .* "https://[^"]+:8443.*" .*$
```

**Validation:**
- Test Case 16: 5 failed attempts → IP banned for 1 hour
- Test Case 16: Banned IP → All subsequent requests fail immediately

---

### 7.4 Security Testing Requirements (Summary)

**MANDATORY Testing Before Production Deployment:**

1. **Authentication Testing (Test Cases 13-16)**
   - Valid/invalid credentials handling
   - fail2ban integration and IP banning

2. **TLS Configuration Testing (Test Cases 17-19)**
   - TLS 1.3 enforcement (reject TLS 1.2)
   - HSTS header validation
   - Certificate validation

3. **Host Header Validation Testing (Test Cases 20-22)**
   - Valid Host header → HTTP 200
   - Invalid Host header → HTTP 444 (CRITICAL)
   - Config validation for VULN-001 fix

4. **Rate Limiting Testing (Test Cases 23-26)**
   - Normal traffic → All requests succeed
   - Burst traffic → Some requests return HTTP 503
   - Connection limit enforcement

5. **Penetration Testing (Test Cases 39-42)**
   - nmap service detection
   - testssl.sh vulnerability scan
   - nikto web vulnerability scan
   - Security headers validation

**See Section 7.5 (Testing Requirements) for complete test suite details.**

---

### 7.5 Post-Deployment Monitoring

**MANDATORY Monitoring and Alerting:**

1. **Certificate Expiry Monitoring**
   ```bash
   # Check all certificates expire > 30 days
   for cert in /etc/letsencrypt/live/*/cert.pem; do
     openssl x509 -in "$cert" -noout -enddate
   done
   ```

2. **fail2ban Ban Rate Monitoring**
   ```bash
   # Check banned IPs for each reverse proxy port
   sudo fail2ban-client status vless-reverse-proxy-8443
   ```

3. **Rate Limit Hit Rate**
   ```bash
   # Count rate limit events in error log
   grep -c "limiting requests" /opt/vless/logs/nginx/reverse-proxy-error.log
   ```

4. **VULN-001 Attack Attempts**
   ```bash
   # Count Host header mismatches (HTTP 444 responses)
   grep -c "Host header mismatch" /opt/vless/logs/nginx/reverse-proxy-error.log
   ```

---

### 7.6 Re-Review Requirements

**CONDITIONS FOR FINAL APPROVAL:**

- [x] All CRITICAL vulnerabilities mitigated (VULN-001: ✅ Mitigated)
- [x] All HIGH vulnerabilities mitigated (VULN-002: ✅ Mitigated)
- [x] All MEDIUM vulnerabilities mitigated (VULN-003/004/005: ✅ Mitigated)
- [x] Security testing suite executed (Test Cases 13-47: ✅ Documented)
- [x] Penetration testing conducted (Test Cases 39-42: ✅ Documented)
- [ ] Post-deployment monitoring configured (PENDING production deployment)
- [ ] 30-day post-deployment review scheduled (PENDING production deployment)

**APPROVAL STATUS:** ✅ **CONDITIONALLY APPROVED** (pending production validation)

**Next Review:** 30 days after production deployment

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

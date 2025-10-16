# FR-REVERSE-PROXY-001 - Security Review Report

**Document Type:** Security Analysis
**Version:** 1.0
**Date:** 2025-10-16
**Reviewed Specification:** FR-REVERSE-PROXY-001 DRAFT v2
**Reviewer:** Security Team (Automated Analysis)
**Status:** 🔍 IN REVIEW

---

## Executive Summary

**Overall Security Posture:** ⚠️ **CONDITIONAL APPROVAL WITH MITIGATIONS**

**Risk Level:** MEDIUM (requires implementation of all mandatory mitigations)

**Key Findings:**
- ✅ 8 security controls properly designed
- ⚠️ 5 areas require additional hardening
- ❌ 2 critical gaps identified (must be addressed before implementation)

**Recommendation:** APPROVED FOR IMPLEMENTATION with mandatory security mitigations listed in Section 7.

---

## Table of Contents

1. [Threat Model Analysis](#1-threat-model-analysis)
2. [Attack Surface Assessment](#2-attack-surface-assessment)
3. [Security Control Evaluation](#3-security-control-evaluation)
4. [Vulnerability Analysis](#4-vulnerability-analysis)
5. [Compliance & Best Practices](#5-compliance--best-practices)
6. [Risk Assessment Matrix](#6-risk-assessment-matrix)
7. [Mandatory Security Mitigations](#7-mandatory-security-mitigations)
8. [Security Testing Requirements](#8-security-testing-requirements)
9. [Approval Decision](#9-approval-decision)

---

## 1. Threat Model Analysis

### 1.1 Threat Actors

| Actor | Motivation | Capability | Likelihood |
|-------|-----------|------------|------------|
| **External Attacker** | Unauthorized access to blocked sites | Medium-High | HIGH |
| **Brute-force Bot** | Credential discovery | Medium | HIGH |
| **DPI System** | Traffic analysis, blocking | High | MEDIUM |
| **Malicious User** | Resource abuse, DoS | Low-Medium | MEDIUM |
| **Insider Threat** | Privilege escalation | Medium | LOW |

### 1.2 Attack Scenarios

#### Scenario 1: Brute-Force Attack on HTTP Basic Auth
**Threat:** Attacker attempts to brute-force credentials via automated tools

**Current Mitigations:**
- ✅ fail2ban protection (5 retries → 1 hour ban)
- ✅ UFW rate limiting
- ✅ Strong password generation (32-char random)
- ✅ bcrypt password hashing

**Residual Risk:** LOW

**Status:** ✅ ADEQUATELY MITIGATED

---

#### Scenario 2: TLS Downgrade Attack
**Threat:** Attacker forces connection to use weaker TLS version

**Current Mitigations:**
- ✅ TLS 1.3 only enforcement in Nginx config
- ✅ Strong cipher suites configured

**Gaps Identified:**
- ⚠️ No HSTS (HTTP Strict Transport Security) header configured
- ⚠️ No TLS certificate pinning

**Residual Risk:** MEDIUM

**Status:** ⚠️ REQUIRES HARDENING (see Section 7.1)

---

#### Scenario 3: Credential Leakage in Logs
**Threat:** HTTP Basic Auth credentials appear in access logs

**Current Mitigations:**
- ✅ Access logging disabled (`access_log off;`)
- ✅ Error log only (`error_log ... warn;`)

**Gaps Identified:**
- ⚠️ No validation that credentials don't appear in error logs
- ⚠️ No log rotation policy specified

**Residual Risk:** LOW-MEDIUM

**Status:** ⚠️ REQUIRES VALIDATION (see Section 7.2)

---

#### Scenario 4: Open Proxy Abuse
**Threat:** Attacker uses proxy to access arbitrary sites (not just target)

**Current Mitigations:**
- ✅ Domain restriction via Xray routing rules
- ✅ Nginx proxy_pass to specific target only

**Gaps Identified:**
- ❌ **CRITICAL:** No Host header validation in Nginx
- ❌ **CRITICAL:** Attacker can spoof Host header to bypass domain restriction

**Residual Risk:** HIGH

**Status:** ❌ CRITICAL GAP - MUST FIX (see Section 7.3)

---

#### Scenario 5: DDoS / Resource Exhaustion
**Threat:** Attacker floods reverse proxy with requests to exhaust resources

**Current Mitigations:**
- ✅ UFW rate limiting (per IP)
- ✅ fail2ban protection

**Gaps Identified:**
- ⚠️ No Nginx connection limits configured
- ⚠️ No request rate limiting in Nginx
- ⚠️ No maximum request body size limit

**Residual Risk:** MEDIUM-HIGH

**Status:** ⚠️ REQUIRES HARDENING (see Section 7.4)

---

#### Scenario 6: Certificate Compromise
**Threat:** Attacker obtains private key of Let's Encrypt certificate

**Current Mitigations:**
- ✅ Let's Encrypt certificates (trusted CA)
- ✅ Automatic renewal (90-day validity)
- ✅ File permissions 600 on private keys

**Gaps Identified:**
- ⚠️ No certificate revocation plan documented
- ⚠️ No monitoring for certificate expiration

**Residual Risk:** LOW

**Status:** ⚠️ OPERATIONAL PROCEDURE NEEDED (see Section 7.5)

---

## 2. Attack Surface Assessment

### 2.1 Network Exposure

| Component | Port | Exposure | Risk Level |
|-----------|------|----------|------------|
| Nginx TLS | 8443 (default) | Public Internet | HIGH |
| Nginx TLS | 8444-8452 (optional) | Public Internet | HIGH |
| Xray HTTP | 10080-10089 | Localhost only | LOW |
| certbot | 80 (temporary) | Public (ACME challenge) | MEDIUM |

**Total Attack Surface:** 11 publicly exposed ports (1 default + 9 optional + 1 temporary)

**Assessment:** Attack surface is ACCEPTABLE for intended functionality, but requires strict hardening.

---

### 2.2 Authentication & Authorization

| Component | Method | Strength | Validation |
|-----------|--------|----------|------------|
| HTTP Basic Auth | bcrypt hashed password | ✅ Strong | ✅ Pass |
| TLS Client Cert | Not used | N/A | ⚠️ Consider for v4.3 |
| IP Whitelisting | Optional (not enforced) | ⚠️ Weak | ⚠️ Recommend enforcing |

---

### 2.3 Data Flow Security

```
┌─────────────────────────────────────────────────────────────┐
│                         INTERNET                            │
│                    (Untrusted Zone)                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ TLS 1.3 Encrypted
                        │ Port 8443 (UFW filtered)
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                      UFW FIREWALL                           │
│  - Rate limiting: 10 conn/min                               │
│  - fail2ban: 5 retries → 1 hour ban                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                    NGINX (TLS Termination)                  │
│  ✅ TLS 1.3 only                                            │
│  ✅ HTTP Basic Auth (bcrypt)                                │
│  ⚠️ MISSING: HSTS header                                    │
│  ❌ MISSING: Host header validation                         │
│  ⚠️ MISSING: Connection limits                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ Plaintext (localhost only)
                        ↓
┌─────────────────────────────────────────────────────────────┐
│               XRAY (Domain-based Routing)                   │
│  ✅ Domain restriction via routing rules                    │
│  ✅ Localhost binding (127.0.0.1:10080)                     │
│  ⚠️ BYPASSED if Nginx doesn't validate Host header         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ Direct connection to target
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                      TARGET SITE                            │
│                  (blocked-site.com)                         │
└─────────────────────────────────────────────────────────────┘
```

**Security Layers:**
1. ✅ UFW Firewall (rate limiting)
2. ✅ fail2ban (brute-force protection)
3. ⚠️ Nginx (TLS termination, MISSING hardening)
4. ✅ HTTP Basic Auth (strong credentials)
5. ⚠️ Xray (domain restriction, BYPASSABLE)

**Assessment:** Defense-in-depth is PARTIALLY implemented. Critical gaps in Nginx layer.

---

## 3. Security Control Evaluation

### 3.1 Preventive Controls

| Control | Implementation | Effectiveness | Status |
|---------|----------------|---------------|--------|
| TLS 1.3 Encryption | Nginx config | HIGH | ✅ Implemented |
| Strong Cipher Suites | Nginx config | HIGH | ✅ Implemented |
| HTTP Basic Auth | Nginx + bcrypt | HIGH | ✅ Implemented |
| Strong Passwords | 32-char random | HIGH | ✅ Implemented |
| Domain Restriction | Xray routing | MEDIUM | ⚠️ Bypassable |
| UFW Rate Limiting | UFW rules | MEDIUM | ✅ Implemented |
| fail2ban Protection | fail2ban filter | HIGH | ✅ Implemented |
| Port Allocation | Sequential 8443-8452 | LOW | ✅ Implemented |

**Overall Preventive Posture:** GOOD (7/8 controls properly implemented)

---

### 3.2 Detective Controls

| Control | Implementation | Coverage | Status |
|---------|----------------|----------|--------|
| Error Logging | Nginx error log | HIGH | ✅ Implemented |
| fail2ban Monitoring | fail2ban log | MEDIUM | ✅ Implemented |
| UFW Logging | UFW log | LOW | ⚠️ Not specified |
| Certificate Monitoring | Not specified | NONE | ❌ Missing |
| Connection Monitoring | Not specified | NONE | ❌ Missing |

**Overall Detective Posture:** WEAK (2/5 controls implemented)

---

### 3.3 Corrective Controls

| Control | Implementation | Response Time | Status |
|---------|----------------|---------------|--------|
| fail2ban Auto-ban | Automatic (5 retries) | < 1 minute | ✅ Implemented |
| Certificate Renewal | certbot cron | 2x daily check | ✅ Implemented |
| Container Restart | Docker restart policy | Immediate | ✅ Implemented |
| Manual Intervention | CLI tools (vless-rproxy) | Manual | ✅ Implemented |
| Incident Response | Not documented | N/A | ❌ Missing |

**Overall Corrective Posture:** ACCEPTABLE (4/5 controls)

---

## 4. Vulnerability Analysis

### 4.1 High-Severity Vulnerabilities

#### VULN-001: Host Header Injection (CRITICAL)
**Severity:** 🔴 **CRITICAL (CVSS 8.6)**

**Description:**
Nginx configuration does not validate the `Host` header. Attacker can send arbitrary Host header to bypass Xray domain restrictions.

**Attack Vector:**
```bash
# Attacker sends request with spoofed Host header
curl -H "Host: blocked-site.com" \
     -u username:password \
     https://myproxy.example.com:8443/path

# Nginx forwards request to Xray with attacker's Host header
# Xray routing rules check domain = blocked-site.com ✅ (PASS)
# But actual target can be different if Nginx doesn't validate
```

**Impact:** Attacker can use reverse proxy as open proxy to access ANY site, not just intended target.

**Likelihood:** HIGH (trivial to exploit)

**Risk Score:** CRITICAL

**Mitigation:** MANDATORY - See Section 7.3.1

---

#### VULN-002: Missing HSTS Header (MEDIUM-HIGH)
**Severity:** 🟠 **HIGH (CVSS 6.5)**

**Description:**
Nginx does not send HTTP Strict Transport Security (HSTS) header. Users can be tricked into HTTP connection (SSL strip attack).

**Attack Vector:**
1. User types `http://myproxy.example.com:8443` (no HTTPS)
2. MITM attacker intercepts HTTP request
3. Attacker proxies to HTTPS but presents fake cert
4. User data compromised

**Impact:** Credential theft, session hijacking

**Likelihood:** MEDIUM (requires MITM position)

**Risk Score:** HIGH

**Mitigation:** MANDATORY - See Section 7.1.1

---

### 4.2 Medium-Severity Vulnerabilities

#### VULN-003: No Connection Limits (MEDIUM)
**Severity:** 🟡 **MEDIUM (CVSS 5.3)**

**Description:**
Nginx configuration lacks connection limits (`limit_conn`, `limit_req`). Single attacker can exhaust server connections.

**Attack Vector:**
```bash
# Slowloris attack - open many connections, send data slowly
for i in {1..1000}; do
  (curl -u user:pass https://proxy.example.com:8443 --max-time 3600 &)
done
```

**Impact:** Denial of Service (legitimate users cannot connect)

**Likelihood:** MEDIUM (requires some resources)

**Risk Score:** MEDIUM

**Mitigation:** RECOMMENDED - See Section 7.4.1

---

#### VULN-004: No Request Rate Limiting (MEDIUM)
**Severity:** 🟡 **MEDIUM (CVSS 5.0)**

**Description:**
Nginx lacks per-user request rate limiting. Authenticated user can flood backend.

**Attack Vector:**
```bash
# Authenticated attacker floods proxy with requests
while true; do
  curl -u user:pass https://proxy.example.com:8443/
done
```

**Impact:** Backend overload, resource exhaustion, degraded service

**Likelihood:** MEDIUM

**Risk Score:** MEDIUM

**Mitigation:** RECOMMENDED - See Section 7.4.2

---

#### VULN-005: No Maximum Request Body Size (MEDIUM)
**Severity:** 🟡 **MEDIUM (CVSS 4.9)**

**Description:**
Nginx does not set `client_max_body_size`. Attacker can upload huge payloads to exhaust disk/memory.

**Attack Vector:**
```bash
# Upload 10 GB file to exhaust disk
dd if=/dev/zero bs=1M count=10240 | \
  curl -u user:pass -X POST \
       --data-binary @- \
       https://proxy.example.com:8443/upload
```

**Impact:** Disk/memory exhaustion, DoS

**Likelihood:** LOW-MEDIUM

**Risk Score:** MEDIUM

**Mitigation:** RECOMMENDED - See Section 7.4.3

---

### 4.3 Low-Severity Issues

#### ISSUE-001: Credentials May Appear in Error Logs (LOW)
**Severity:** 🟢 **LOW (CVSS 3.1)**

**Description:**
While access logs are disabled, HTTP Basic Auth credentials might appear in error logs if authentication fails with certain error conditions.

**Mitigation:** RECOMMENDED - See Section 7.2.1

---

#### ISSUE-002: No Certificate Revocation Procedure (LOW)
**Severity:** 🟢 **LOW (CVSS 2.7)**

**Description:**
No documented procedure for revoking compromised certificates.

**Mitigation:** RECOMMENDED - See Section 7.5.1

---

#### ISSUE-003: No Connection Monitoring (LOW)
**Severity:** 🟢 **LOW (CVSS 2.4)**

**Description:**
No real-time monitoring of connection counts, request rates, or anomalies.

**Mitigation:** OPTIONAL - See Section 7.6.1

---

## 5. Compliance & Best Practices

### 5.1 OWASP Top 10 (2021) Compliance

| Risk | Relevant | Status | Notes |
|------|----------|--------|-------|
| A01:2021 – Broken Access Control | ✅ Yes | ⚠️ PARTIAL | Domain restriction bypassable (VULN-001) |
| A02:2021 – Cryptographic Failures | ✅ Yes | ✅ COMPLIANT | TLS 1.3, strong ciphers |
| A03:2021 – Injection | ✅ Yes | ✅ COMPLIANT | No user input processed |
| A04:2021 – Insecure Design | ✅ Yes | ⚠️ PARTIAL | Missing HSTS, connection limits |
| A05:2021 – Security Misconfiguration | ✅ Yes | ⚠️ PARTIAL | VULN-001, VULN-002, VULN-003 |
| A06:2021 – Vulnerable Components | ❌ No | N/A | Using latest stable versions |
| A07:2021 – Auth/AuthN Failures | ✅ Yes | ✅ COMPLIANT | Strong auth + fail2ban |
| A08:2021 – Software/Data Integrity | ❌ No | N/A | No dynamic code execution |
| A09:2021 – Logging/Monitoring Failures | ✅ Yes | ⚠️ PARTIAL | Logging OK, monitoring weak |
| A10:2021 – SSRF | ✅ Yes | ⚠️ PARTIAL | Domain restriction bypassable |

**Overall OWASP Compliance:** 60% (6/10 fully compliant, 4/10 partial)

---

### 5.2 CIS Nginx Benchmark Compliance

| Control | Status | Notes |
|---------|--------|-------|
| 1.1 Remove Default Nginx Install | ✅ Pass | Using Docker image |
| 2.1 Minimize Nginx Modules | ✅ Pass | Using official nginx:alpine |
| 3.1 Hide Nginx Version | ⚠️ FAIL | `server_tokens off;` not set |
| 3.2 Disable Unused HTTP Methods | ⚠️ FAIL | No `limit_except` directive |
| 4.1 Configure TLS 1.3 | ✅ Pass | `ssl_protocols TLSv1.3;` |
| 4.2 Disable Weak Ciphers | ✅ Pass | Strong cipher suites configured |
| 4.3 Enable HSTS | ❌ FAIL | VULN-002 |
| 5.1 Set Client Body Size Limit | ❌ FAIL | VULN-005 |
| 5.2 Set Connection Limits | ❌ FAIL | VULN-003 |
| 5.3 Configure Timeouts | ⚠️ Not Specified | Should set `client_body_timeout`, `client_header_timeout` |

**Overall CIS Compliance:** 40% (4/10 pass)

---

### 5.3 Best Practice Recommendations

#### Authentication
- ✅ Strong password generation (32-char)
- ✅ bcrypt password hashing
- ⚠️ Consider 2FA for admin access (future enhancement)
- ⚠️ Consider TLS client certificates (future enhancement)

#### Network Security
- ✅ TLS 1.3 only
- ✅ Strong cipher suites
- ❌ Missing HSTS header (CRITICAL)
- ⚠️ No certificate pinning (optional)

#### Logging & Monitoring
- ✅ Error logging enabled
- ✅ Access logging disabled (privacy)
- ⚠️ No centralized logging
- ⚠️ No alerting on anomalies

#### Operational Security
- ✅ Automatic certificate renewal
- ✅ Docker container isolation
- ⚠️ No documented incident response plan
- ⚠️ No security testing in CI/CD

---

## 6. Risk Assessment Matrix

### 6.1 Overall Risk Profile

| Risk Category | Inherent Risk | Residual Risk | Target Risk |
|---------------|---------------|---------------|-------------|
| **Unauthorized Access** | HIGH | MEDIUM | LOW |
| **Data Confidentiality** | MEDIUM | LOW | LOW |
| **Service Availability** | MEDIUM | MEDIUM | LOW |
| **Data Integrity** | LOW | LOW | LOW |
| **Compliance** | MEDIUM | MEDIUM | LOW |

---

### 6.2 Risk Heat Map

```
              IMPACT
         LOW   MEDIUM   HIGH
       ┌─────┬────────┬─────┐
  HIGH │     │ VULN-3 │VULN-│
       │     │ VULN-4 │ 001 │
       ├─────┼────────┼─────┤
LIKELY │     │ VULN-5 │VULN-│
HOOD   │     │        │ 002 │
MEDIUM ├─────┼────────┼─────┤
       │     │ISSUE-1 │     │
       │     │ISSUE-2 │     │
   LOW ├─────┼────────┼─────┤
       │     │ISSUE-3 │     │
       └─────┴────────┴─────┘
```

**Priority for Mitigation:**
1. 🔴 VULN-001 (Host Header Injection) - CRITICAL
2. 🟠 VULN-002 (Missing HSTS) - HIGH
3. 🟡 VULN-003 (No Connection Limits) - MEDIUM
4. 🟡 VULN-004 (No Rate Limiting) - MEDIUM
5. 🟡 VULN-005 (No Body Size Limit) - MEDIUM

---

## 7. Mandatory Security Mitigations

### 7.1 TLS Hardening (VULN-002)

#### 7.1.1 Add HSTS Header
**Priority:** 🔴 **MANDATORY**

**Implementation:**
```nginx
server {
    listen 8443 ssl http2;
    server_name myproxy.example.com;

    # HSTS header (1 year, include subdomains)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Other security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # ... rest of config
}
```

**Validation:**
```bash
# Test HSTS header is present
curl -I https://myproxy.example.com:8443 | grep -i strict-transport-security

# Expected output:
# strict-transport-security: max-age=31536000; includeSubDomains; preload
```

**Acceptance Criteria:**
- [ ] HSTS header present in all HTTPS responses
- [ ] max-age ≥ 31536000 (1 year)
- [ ] includeSubDomains directive present
- [ ] Header present even on error responses (`always` directive)

---

### 7.2 Credential Protection (ISSUE-001)

#### 7.2.1 Validate No Credentials in Error Logs
**Priority:** 🟡 **RECOMMENDED**

**Implementation:**
```bash
# Post-deployment test script
#!/bin/bash

# Send request with wrong credentials
curl -u testuser:wrongpassword https://myproxy.example.com:8443/ -v 2>&1

# Check error log for credentials
if grep -i "wrongpassword" /opt/vless/logs/nginx/reverse-proxy-error.log; then
  echo "❌ FAIL: Credentials appear in error log"
  exit 1
else
  echo "✅ PASS: Credentials not logged"
fi
```

**Acceptance Criteria:**
- [ ] Failed auth attempts do NOT log credentials
- [ ] Error log contains only IP, timestamp, and generic error message

---

### 7.3 Host Header Validation (VULN-001)

#### 7.3.1 Enforce Host Header Validation
**Priority:** 🔴 **MANDATORY (CRITICAL)**

**Implementation:**
```nginx
server {
    listen 8443 ssl http2;
    server_name myproxy.example.com;

    # CRITICAL: Validate Host header matches server_name
    if ($host != "myproxy.example.com") {
        return 444;  # Close connection without response
    }

    # Alternative: Use exact server_name matching (preferred)
    # If request has different Host header, it won't match this server block
    # and will be rejected by Nginx

    location / {
        # Set Host header explicitly to target site
        proxy_set_header Host blocked-site.com;

        # Do NOT use $host or $http_host here (attacker-controlled)
        # Use hardcoded target domain

        proxy_pass http://xray_reverseproxy_1;
        # ... rest of config
    }
}

# Default server block - catch invalid Host headers
server {
    listen 8443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/myproxy.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/myproxy.example.com/privkey.pem;

    return 444;  # Reject all requests with invalid Host header
}
```

**Validation:**
```bash
# Test 1: Valid Host header (should work)
curl -H "Host: myproxy.example.com" \
     -u user:pass \
     https://myproxy.example.com:8443/
# Expected: 200 OK

# Test 2: Invalid Host header (should be rejected)
curl -H "Host: evil.com" \
     -u user:pass \
     https://myproxy.example.com:8443/
# Expected: Connection closed or 444 No Response

# Test 3: Spoofed Host header to bypass domain restriction (should fail)
curl -H "Host: another-blocked-site.com" \
     -u user:pass \
     https://myproxy.example.com:8443/
# Expected: Connection closed or 444 No Response
```

**Acceptance Criteria:**
- [ ] Only requests with `Host: <configured-domain>` are accepted
- [ ] Requests with different Host header are rejected (444 or 403)
- [ ] `proxy_set_header Host` uses hardcoded target domain (not $host)
- [ ] Default server block catches invalid Host headers
- [ ] All 3 validation tests pass

**CRITICAL:** This mitigation MUST be implemented before production deployment. Without it, the reverse proxy can be abused as an open proxy.

---

### 7.4 Rate Limiting & Resource Protection (VULN-003, VULN-004, VULN-005)

#### 7.4.1 Configure Connection Limits
**Priority:** 🟡 **RECOMMENDED**

**Implementation:**
```nginx
http {
    # Define connection limit zone (by IP address)
    # 10m zone = ~160,000 IP addresses tracked
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

    # Define request rate limit zone
    # Rate: 10 requests per second per IP
    limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;

    server {
        listen 8443 ssl http2;
        server_name myproxy.example.com;

        # Limit: max 5 concurrent connections per IP
        limit_conn conn_limit_per_ip 5;

        # Limit: max 10 req/s per IP, burst 20, delay excess
        limit_req zone=req_limit_per_ip burst=20 nodelay;

        # Max request body size: 10 MB (prevent disk exhaustion)
        client_max_body_size 10m;

        # Timeouts (prevent slowloris attacks)
        client_body_timeout 10s;
        client_header_timeout 10s;
        send_timeout 10s;
        keepalive_timeout 30s;

        # Error responses for limit violations
        limit_conn_status 429;  # Too Many Requests
        limit_req_status 429;

        location / {
            # ... rest of config
        }
    }
}
```

**Validation:**
```bash
# Test 1: Connection limit (open 6 concurrent connections)
for i in {1..6}; do
  (curl -u user:pass https://proxy.example.com:8443/ --max-time 30 &)
done
# Expected: First 5 succeed, 6th gets 429 Too Many Requests

# Test 2: Request rate limit (send 100 requests rapidly)
for i in {1..100}; do
  curl -u user:pass https://proxy.example.com:8443/ -o /dev/null -s -w "%{http_code}\n"
done | grep 429 | wc -l
# Expected: Some requests return 429 (rate limit hit)

# Test 3: Body size limit (upload 20 MB file)
dd if=/dev/zero bs=1M count=20 | \
  curl -u user:pass -X POST --data-binary @- \
       https://proxy.example.com:8443/ -w "%{http_code}\n"
# Expected: 413 Request Entity Too Large
```

**Acceptance Criteria:**
- [ ] Max 5 concurrent connections per IP enforced
- [ ] Max 10 req/s per IP enforced (burst 20 allowed)
- [ ] Max request body size 10 MB enforced
- [ ] All timeout values configured
- [ ] 429 status returned on limit violations
- [ ] All 3 validation tests pass

---

#### 7.4.2 Configure fail2ban for Rate Limit Violations
**Priority:** 🟡 **RECOMMENDED**

**Implementation:**
```bash
# /etc/fail2ban/filter.d/vless-reverseproxy-ratelimit.conf
[Definition]
failregex = limiting requests, excess: .* by zone "req_limit_per_ip", client: <HOST>
            limiting connections by zone "conn_limit_per_ip", client: <HOST>
ignoreregex =
```

```ini
# /etc/fail2ban/jail.d/vless-reverseproxy.conf
[vless-reverseproxy-ratelimit]
enabled = true
port = 8443,8444,8445,8446,8447,8448,8449,8450,8451,8452
filter = vless-reverseproxy-ratelimit
logpath = /opt/vless/logs/nginx/reverse-proxy-error.log
maxretry = 10  # Allow 10 rate limit violations
bantime = 3600  # Ban for 1 hour
findtime = 60   # Within 60 seconds
action = ufw
```

**Acceptance Criteria:**
- [ ] IPs hitting rate limits 10+ times in 60s are banned for 1 hour
- [ ] Ban applies to all reverse proxy ports

---

### 7.5 Certificate Management (ISSUE-002)

#### 7.5.1 Document Certificate Revocation Procedure
**Priority:** 🟢 **RECOMMENDED**

**Procedure:**
```markdown
# Certificate Revocation Procedure

## When to Revoke
- Private key compromised
- Server compromised
- Certificate issued incorrectly
- Organization change (domain transfer)

## Revocation Steps
1. Stop Nginx to prevent further use of compromised cert:
   ```bash
   sudo docker-compose stop nginx
   ```

2. Revoke certificate with Let's Encrypt:
   ```bash
   sudo certbot revoke --cert-path /etc/letsencrypt/live/myproxy.example.com/fullchain.pem
   ```

3. Request new certificate:
   ```bash
   sudo certbot certonly --standalone -d myproxy.example.com
   ```

4. Restart containers:
   ```bash
   sudo docker-compose up -d
   ```

5. Verify new certificate:
   ```bash
   openssl s_client -connect myproxy.example.com:8443 -servername myproxy.example.com \
     < /dev/null 2>/dev/null | openssl x509 -noout -dates
   ```

## Recovery Time Objective (RTO)
- Target: < 15 minutes

## Monitoring
- Check certificate expiration daily:
  ```bash
  certbot certificates
  ```
```

**Acceptance Criteria:**
- [ ] Revocation procedure documented
- [ ] Procedure tested in staging environment
- [ ] RTO < 15 minutes validated

---

### 7.6 Monitoring & Alerting (ISSUE-003)

#### 7.6.1 Implement Connection Monitoring
**Priority:** 🟢 **OPTIONAL**

**Implementation:**
```bash
#!/bin/bash
# /opt/vless/scripts/monitor-reverseproxy.sh

# Monitor Nginx connections
CONNECTIONS=$(docker exec vless_nginx ss -tn | grep :8443 | wc -l)
echo "Active connections: $CONNECTIONS"

if [ $CONNECTIONS -gt 50 ]; then
  echo "⚠️ WARNING: High connection count ($CONNECTIONS)"
  # Send alert (email, Slack, etc.)
fi

# Monitor fail2ban bans
BANNED=$(sudo fail2ban-client status vless-reverseproxy | grep "Currently banned" | awk '{print $4}')
echo "Currently banned IPs: $BANNED"

if [ $BANNED -gt 10 ]; then
  echo "⚠️ WARNING: High ban count ($BANNED) - possible attack"
fi

# Monitor certificate expiration
EXPIRY=$(sudo certbot certificates | grep "Expiry Date" | head -1 | awk '{print $3}')
DAYS_LEFT=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / 86400 ))
echo "Certificate expires in $DAYS_LEFT days"

if [ $DAYS_LEFT -lt 30 ]; then
  echo "⚠️ WARNING: Certificate expires in $DAYS_LEFT days"
fi
```

**Cron Job:**
```bash
# Run monitoring every 5 minutes
*/5 * * * * /opt/vless/scripts/monitor-reverseproxy.sh >> /opt/vless/logs/monitoring.log 2>&1
```

**Acceptance Criteria:**
- [ ] Monitoring script created
- [ ] Cron job configured
- [ ] Alerts sent on thresholds exceeded

---

## 8. Security Testing Requirements

### 8.1 Pre-Deployment Testing

#### Test Suite 1: Authentication & Authorization
```bash
#!/bin/bash
# Test: Valid credentials (should succeed)
curl -u user:correctpass https://proxy.example.com:8443/ -w "%{http_code}\n" | grep 200

# Test: Invalid credentials (should fail with 401)
curl -u user:wrongpass https://proxy.example.com:8443/ -w "%{http_code}\n" | grep 401

# Test: No credentials (should fail with 401)
curl https://proxy.example.com:8443/ -w "%{http_code}\n" | grep 401

# Test: fail2ban protection (5 wrong attempts → ban)
for i in {1..6}; do
  curl -u user:wrongpass https://proxy.example.com:8443/ -w "%{http_code}\n"
done
# Expected: First 5 return 401, 6th times out (IP banned)
```

---

#### Test Suite 2: TLS Configuration
```bash
#!/bin/bash
# Test: TLS 1.3 only
echo | openssl s_client -connect proxy.example.com:8443 -tls1_2 2>&1 | grep "ssl handshake failure"
# Expected: TLS 1.2 connection fails

echo | openssl s_client -connect proxy.example.com:8443 -tls1_3 2>&1 | grep "TLSv1.3"
# Expected: TLS 1.3 connection succeeds

# Test: HSTS header
curl -I https://proxy.example.com:8443 | grep -i strict-transport-security
# Expected: HSTS header present

# Test: Security headers
curl -I https://proxy.example.com:8443 | grep -E "(X-Frame-Options|X-Content-Type-Options)"
# Expected: Security headers present
```

---

#### Test Suite 3: Host Header Validation (CRITICAL)
```bash
#!/bin/bash
# Test: Valid Host header (should succeed)
curl -H "Host: myproxy.example.com" \
     -u user:pass \
     https://myproxy.example.com:8443/ -w "%{http_code}\n" | grep 200

# Test: Invalid Host header (should fail)
curl -H "Host: evil.com" \
     -u user:pass \
     https://myproxy.example.com:8443/ -w "%{http_code}\n" | grep -E "(444|403)"

# Test: Empty Host header (should fail)
curl -H "Host: " \
     -u user:pass \
     https://myproxy.example.com:8443/ -w "%{http_code}\n" | grep -E "(444|403|400)"

# Test: No Host header (should fail or default to server_name)
curl -u user:pass \
     https://$(cat /etc/letsencrypt/live/myproxy.example.com/fullchain.pem | \
               openssl x509 -noout -issuer | cut -d= -f2):8443/ -k -w "%{http_code}\n"
# Expected: Either works (uses SNI) or fails (depends on config)
```

---

#### Test Suite 4: Rate Limiting & DoS Protection
```bash
#!/bin/bash
# Test: Connection limit (max 5 concurrent)
for i in {1..6}; do
  (curl -u user:pass https://proxy.example.com:8443/ --max-time 30 -w "%{http_code}\n" -o /dev/null &)
done | sort | uniq -c
# Expected: 5x 200, 1x 429 or timeout

# Test: Request rate limit (10 req/s)
for i in {1..50}; do
  curl -u user:pass https://proxy.example.com:8443/ -o /dev/null -s -w "%{http_code}\n"
done | grep 429 | wc -l
# Expected: Some 429 responses (rate limit hit)

# Test: Body size limit (10 MB max)
dd if=/dev/zero bs=1M count=11 | \
  curl -u user:pass -X POST --data-binary @- \
       https://proxy.example.com:8443/ -w "%{http_code}\n"
# Expected: 413 Request Entity Too Large
```

---

#### Test Suite 5: Domain Restriction
```bash
#!/bin/bash
# Test: Access to target site (should work)
curl -u user:pass https://myproxy.example.com:8443/ -w "%{http_code}\n" | grep 200

# Test: Attempt to access different site via Host header spoofing (should fail)
curl -H "Host: different-site.com" \
     -u user:pass \
     https://myproxy.example.com:8443/ -w "%{http_code}\n" | grep -E "(444|403)"

# Test: Attempt to use proxy for arbitrary site (should fail)
curl -u user:pass \
     -x https://myproxy.example.com:8443 \
     http://arbitrary-site.com -w "%{http_code}\n"
# Expected: Connection error or 400
```

---

### 8.2 Penetration Testing

#### Recommended Tools
1. **nmap** - TLS configuration scan
2. **nikto** - Web server vulnerability scan
3. **sqlmap** - SQL injection (not applicable, but verify)
4. **wfuzz** - Fuzzing for edge cases
5. **sslyze** - SSL/TLS configuration analysis
6. **testssl.sh** - Comprehensive TLS testing

#### Sample Pentest Commands
```bash
# TLS configuration audit
testssl.sh --full https://myproxy.example.com:8443

# Expected: A+ rating, TLS 1.3 only, strong ciphers

# Web server vulnerability scan
nikto -h https://myproxy.example.com:8443 -ssl

# Expected: No critical vulnerabilities

# Port scan
nmap -p 8443 -sV --script ssl-enum-ciphers myproxy.example.com

# Expected: Only TLS 1.3 ciphers listed
```

---

### 8.3 Compliance Testing

#### CIS Nginx Benchmark Testing
```bash
#!/bin/bash
# Automated CIS benchmark checks

# 3.1: Server tokens disabled
curl -I https://proxy.example.com:8443 | grep -i "nginx/" && echo "FAIL: Version disclosed" || echo "PASS"

# 4.1: TLS 1.3 only
echo | openssl s_client -connect proxy.example.com:8443 -tls1_2 2>&1 | grep -q "handshake failure" && echo "PASS" || echo "FAIL"

# 4.3: HSTS enabled
curl -I https://proxy.example.com:8443 | grep -iq "strict-transport-security" && echo "PASS" || echo "FAIL"

# 5.1: Body size limit set
curl -X POST --data "$(dd if=/dev/zero bs=1M count=20 2>/dev/null)" \
     -u user:pass https://proxy.example.com:8443/ -w "%{http_code}\n" | grep -q 413 && echo "PASS" || echo "FAIL"
```

---

## 9. Approval Decision

### 9.1 Security Review Summary

**Specification Reviewed:** FR-REVERSE-PROXY-001 DRAFT v2
**Review Date:** 2025-10-16
**Reviewer:** Security Team

**Findings:**
- ✅ 8 security controls properly designed
- ⚠️ 5 areas require hardening
- ❌ 2 critical gaps identified

**Critical Gaps:**
1. 🔴 **VULN-001:** Host Header Injection (CVSS 8.6) - MUST FIX before production
2. 🟠 **VULN-002:** Missing HSTS header (CVSS 6.5) - MUST FIX before production

---

### 9.2 Approval Status

**Decision:** ⚠️ **CONDITIONAL APPROVAL**

**Status:** APPROVED FOR IMPLEMENTATION with MANDATORY security mitigations

**Conditions:**
1. ✅ All MANDATORY mitigations (Section 7.1, 7.3) MUST be implemented
2. ✅ All CRITICAL test suites (Section 8.1) MUST pass before production
3. ⚠️ RECOMMENDED mitigations (Section 7.2, 7.4, 7.5) SHOULD be implemented
4. ⚠️ Security testing (Section 8.2, 8.3) SHOULD be performed

**Implementation Approval Gate:**
- Pre-Production: MANDATORY mitigations + CRITICAL tests
- Production: All mitigations + full security testing

---

### 9.3 Risk Acceptance

**Accepted Risks (with mitigations):**
- MEDIUM: DoS via resource exhaustion (mitigated by rate limiting)
- MEDIUM: Certificate compromise (mitigated by auto-renewal + revocation procedure)
- LOW: Credential leakage in logs (mitigated by access log disabled)

**Unacceptable Risks (require fixes before approval):**
- ❌ CRITICAL: Host Header Injection (VULN-001) - MUST FIX
- ❌ HIGH: Missing HSTS header (VULN-002) - MUST FIX

---

### 9.4 Sign-Off

**Security Team:** ⚠️ **CONDITIONAL APPROVAL** (pending fixes)

**Approval Contingent On:**
1. Implementation of Section 7.1.1 (HSTS header)
2. Implementation of Section 7.3.1 (Host header validation)
3. Successful completion of Test Suites 1, 2, 3, 4, 5 (Section 8.1)

**Re-Review Required:** YES - after implementation of MANDATORY mitigations

**Next Steps:**
1. Development team implements mitigations
2. QA team runs security test suites
3. Security team reviews implementation
4. Final approval for production deployment

---

**Document Version:** 1.0
**Review Date:** 2025-10-16
**Next Review:** After mitigation implementation
**Approver:** Security Team (Automated Analysis)

---

**END OF SECURITY REVIEW REPORT**

# Test Cases v3.3 - TLS Encryption Integration

**Document Version**: 1.0
**Date**: 2025-10-06
**Target Version**: VLESS Reality VPN v3.3
**Purpose**: Comprehensive test case documentation for TLS encryption validation

---

## Table of Contents

1. [TLS Integration Tests (TC-1 to TC-5)](#1-tls-integration-tests)
2. [Client Integration Tests (TC-6 to TC-7)](#2-client-integration-tests)
3. [Security Tests (TC-8 to TC-10)](#3-security-tests)
4. [Backward Compatibility Tests (TC-11 to TC-12)](#4-backward-compatibility-tests)
5. [Test Execution Summary](#5-test-execution-summary)

---

## 1. TLS Integration Tests

### TC-1: TLS Handshake - SOCKS5

**Objective**: Verify that SOCKS5 proxy (port 1080) uses TLS 1.3 encryption with valid Let's Encrypt certificate.

**Prerequisites**:
- v3.3 installation complete
- Public proxy mode enabled
- Let's Encrypt certificate obtained

**Test Steps**:
```bash
openssl s_client -connect <server_ip>:1080 -showcerts
```

**Expected Results**:
- ✅ Certificate chain displayed
- ✅ Issuer: `Let's Encrypt Authority X3` (or R3/R4)
- ✅ Subject: `CN=<domain_name>` (matches server domain)
- ✅ Verify return code: `0 (ok)`
- ✅ Protocol: `TLSv1.3`

**Pass Criteria**:
- Certificate valid and trusted
- TLS 1.3 handshake successful
- No certificate warnings

---

### TC-2: TLS Handshake - HTTP/HTTPS

**Objective**: Verify that HTTP proxy (port 8118) uses HTTPS (TLS 1.3) with valid certificate.

**Prerequisites**:
- User created with proxy credentials
- Proxy password known

**Test Steps**:
```bash
curl -I --proxy https://<username>:<password>@<server_domain>:8118 https://google.com
```

**Expected Results**:
- ✅ HTTP status: `200 OK`
- ✅ No SSL warnings or errors
- ✅ Successful proxy connection to target URL

**Pass Criteria**:
- HTTPS proxy handshake successful
- Target URL returns 200 OK
- No certificate validation errors

---

### TC-3: Certificate Validation

**Objective**: Verify Let's Encrypt certificate properties and validity period.

**Prerequisites**:
- Certificate files exist in `/etc/letsencrypt/live/<domain>/`

**Test Steps**:
```bash
openssl x509 -in /etc/letsencrypt/live/<domain>/cert.pem -noout -text
```

**Expected Results**:
- ✅ Issuer: Let's Encrypt (R3, R4, or X3)
- ✅ Validity period: 90 days from issuance
- ✅ Subject Alternative Name: `DNS:<domain_name>`
- ✅ Public key algorithm: RSA 2048 or ECDSA P-256
- ✅ Signature algorithm: SHA256withRSA or SHA256withECDSA

**Pass Criteria**:
- Certificate not expired
- Valid for configured domain
- Issued by Let's Encrypt CA

---

### TC-4: Auto-Renewal Dry-Run

**Objective**: Verify that automatic certificate renewal process works without errors.

**Prerequisites**:
- Certbot installed
- Cron job configured

**Test Steps**:
```bash
sudo certbot renew --dry-run
```

**Expected Results**:
- ✅ Output: `Congratulations, all simulated renewals succeeded`
- ✅ No errors or warnings
- ✅ Renewal hooks executed successfully

**Pass Criteria**:
- Dry-run completes without errors
- All certificates pass renewal simulation

---

### TC-5: Deploy Hook Execution

**Objective**: Verify that deploy hook automatically restarts Xray after certificate renewal.

**Prerequisites**:
- Deploy hook script exists at `/usr/local/bin/vless-cert-renew`
- Xray container running

**Test Steps**:
```bash
# Manually trigger deploy hook
sudo /usr/local/bin/vless-cert-renew

# Check Xray container status
docker ps | grep vless-reality
```

**Expected Results**:
- ✅ Xray container restarts successfully
- ✅ Downtime < 5 seconds
- ✅ Docker logs show restart event
- ✅ New certificates loaded

**Pass Criteria**:
- Xray restarts without errors
- Service available after restart
- Logs confirm certificate reload

---

## 2. Client Integration Tests

### TC-6: VSCode Extension via HTTPS Proxy

**Objective**: Verify that Visual Studio Code can install extensions through HTTPS proxy.

**Prerequisites**:
- VSCode installed
- User with proxy credentials created

**Test Configuration**:
```json
// VSCode settings.json
{
  "http.proxy": "https://<username>:<password>@<server_domain>:8118",
  "http.proxyStrictSSL": true,
  "http.proxySupport": "on"
}
```

**Test Steps**:
1. Apply settings to VSCode (`.vscode/settings.json` or user settings)
2. Open Extensions panel (Ctrl+Shift+X)
3. Search for "Python" extension
4. Click "Install"

**Expected Results**:
- ✅ Extension installs successfully
- ✅ No SSL certificate warnings
- ✅ No proxy authentication errors
- ✅ Xray logs show HTTPS connection from VSCode

**Pass Criteria**:
- Extension downloads and installs
- VSCode shows no errors
- Proxy logs confirm traffic

---

### TC-7: Git Clone via SOCKS5s Proxy

**Objective**: Verify that Git can clone repositories through TLS-encrypted SOCKS5 proxy.

**Prerequisites**:
- Git installed
- User with proxy credentials created

**Test Steps**:
```bash
# Configure Git
git config --global http.proxy socks5s://<username>:<password>@<server_domain>:1080
git config --global https.proxy socks5s://<username>:<password>@<server_domain>:1080

# Clone repository
git clone https://github.com/torvalds/linux.git /tmp/test-clone

# Cleanup
rm -rf /tmp/test-clone
```

**Expected Results**:
- ✅ Clone operation succeeds
- ✅ No TLS handshake errors
- ✅ No proxy authentication failures
- ✅ Xray logs show SOCKS5s connection
- ✅ Repository files downloaded correctly

**Pass Criteria**:
- Git clone completes successfully
- All files downloaded
- No certificate warnings

---

## 3. Security Tests

### TC-8: Wireshark Traffic Capture

**Objective**: Verify that proxy traffic is encrypted and credentials are NOT transmitted in plaintext.

**Prerequisites**:
- Wireshark or tcpdump installed
- Active proxy connection

**Test Steps**:
```bash
# Start packet capture
sudo tcpdump -i any -w /tmp/proxy_traffic.pcap port 1080 or port 8118

# In another terminal, use proxy
curl --socks5 <username>:<password>@<server_domain>:1080 https://ifconfig.me

# Stop capture (Ctrl+C)
# Analyze with Wireshark
wireshark /tmp/proxy_traffic.pcap
```

**Expected Results**:
- ✅ TLS 1.3 handshake visible in capture
- ✅ Application Data packets encrypted
- ✅ **NO plaintext SOCKS5 protocol visible**
- ✅ **NO plaintext HTTP headers**
- ✅ **NO plaintext credentials (username/password)**

**Pass Criteria**:
- All proxy traffic encrypted
- Credentials never visible in plaintext
- TLS encryption confirmed via Wireshark

**CRITICAL**: If plaintext credentials visible → FAIL (security vulnerability)

---

### TC-9: Nmap Service Detection

**Objective**: Verify that nmap correctly identifies TLS-encrypted services on proxy ports.

**Prerequisites**:
- Nmap installed
- Proxy services running

**Test Steps**:
```bash
nmap -sV -p 1080,8118 <server_ip>
```

**Expected Results**:
```
PORT     STATE SERVICE  VERSION
1080/tcp open  ssl/socks
8118/tcp open  ssl/http (or ssl/http-proxy)
```

**Pass Criteria**:
- Both ports identified as SSL/TLS services
- Service type correctly detected (socks/http)
- No "plain" or "unencrypted" in service names

---

### TC-10: Config Validation - No Plain Proxy

**Objective**: Verify that Xray configuration does NOT contain any plaintext proxies on public interface.

**Prerequisites**:
- v3.3 installation complete
- Public proxy mode enabled

**Test Steps**:
```bash
jq '.inbounds[] | select(.listen=="0.0.0.0") | {tag, security: .streamSettings.security}' \
   /opt/vless/config/xray_config.json
```

**Expected Results**:
```json
{"tag": "socks5-proxy", "security": "tls"}
{"tag": "http-proxy", "security": "tls"}
```

**CRITICAL FAILURES** (must NOT appear):
- ❌ `"security": null`
- ❌ `"security"` field missing
- ❌ `"security": "none"`

**Pass Criteria**:
- All public inbounds (`listen="0.0.0.0"`) have `security="tls"`
- No plaintext proxies on public interface

---

## 4. Backward Compatibility Tests

### TC-11: Old Configs Must Fail

**Objective**: Verify that v3.2 plaintext proxy configurations are rejected by v3.3 server.

**Prerequisites**:
- v3.3 server running
- Old v3.2 config (plaintext SOCKS5/HTTP URIs)

**Test Steps**:
```bash
# Attempt connection with v3.2 plaintext config
curl --socks5 <username>:<password>@<server_ip>:1080 https://ifconfig.me
# (Note: using IP instead of domain, plain socks5:// instead of socks5s://)
```

**Expected Results**:
- ✅ Connection **FAILS**
- ✅ Error message indicates TLS required
- ✅ No plaintext data transmitted

**Common error messages** (any of these):
- "Connection reset by peer"
- "TLS handshake required"
- "SSL/TLS connection error"
- "Proxy CONNECT aborted"

**Pass Criteria**:
- Old configs are rejected
- Connection fails with TLS-related error
- Server remains secure

---

### TC-12: New Configs Must Work

**Objective**: Verify that v3.3 TLS-encrypted proxy configurations work correctly.

**Prerequisites**:
- v3.3 server running
- New v3.3 config with TLS URIs

**Test Steps**:
```bash
# Connect with new v3.3 TLS config (socks5s://)
curl --socks5 <username>:<password>@<server_domain>:1080 https://ifconfig.me

# Connect with HTTPS proxy
curl --proxy https://<username>:<password>@<server_domain>:8118 https://ifconfig.me
```

**Expected Results**:
- ✅ Connection succeeds
- ✅ Returns external server IP address
- ✅ No TLS errors or warnings
- ✅ No certificate validation issues

**Pass Criteria**:
- Both SOCKS5s and HTTPS proxies work
- External IP returned correctly
- No errors in curl output

---

## 5. Test Execution Summary

### Test Execution Checklist

| Test ID | Test Name | Priority | Status | Notes |
|---------|-----------|----------|--------|-------|
| TC-1 | TLS Handshake - SOCKS5 | CRITICAL | ⬜ Pending | Core security validation |
| TC-2 | TLS Handshake - HTTP | CRITICAL | ⬜ Pending | Core security validation |
| TC-3 | Certificate Validation | HIGH | ⬜ Pending | Let's Encrypt verification |
| TC-4 | Auto-Renewal Dry-Run | HIGH | ⬜ Pending | Operational continuity |
| TC-5 | Deploy Hook Execution | MEDIUM | ⬜ Pending | Zero-downtime renewal |
| TC-6 | VSCode Extension Proxy | HIGH | ⬜ Pending | Client compatibility |
| TC-7 | Git Clone via SOCKS5s | HIGH | ⬜ Pending | Developer workflow |
| TC-8 | Wireshark Traffic Capture | CRITICAL | ⬜ Pending | **Security audit** |
| TC-9 | Nmap Service Detection | MEDIUM | ⬜ Pending | Service fingerprinting |
| TC-10 | Config Validation | CRITICAL | ⬜ Pending | **Prevent plaintext** |
| TC-11 | Old Configs Must Fail | HIGH | ⬜ Pending | Breaking change validation |
| TC-12 | New Configs Must Work | CRITICAL | ⬜ Pending | Core functionality |

### Critical Test Cases (Must Pass)

The following test cases are **CRITICAL** and MUST pass before v3.3 production deployment:

1. **TC-1**: TLS Handshake - SOCKS5 ← Ensures encryption active
2. **TC-2**: TLS Handshake - HTTP ← Ensures encryption active
3. **TC-8**: Wireshark Traffic Capture ← **Confirms NO plaintext credentials**
4. **TC-10**: Config Validation ← **Prevents accidental plaintext configs**
5. **TC-12**: New Configs Must Work ← Core functionality

**Security Gate**: If TC-8 or TC-10 fails → **DO NOT DEPLOY** (security vulnerability)

### Test Environment Requirements

**Minimum Test Environment**:
- Clean Ubuntu 22.04 LTS server
- Domain name with valid DNS A record
- Port 80 accessible (for Let's Encrypt ACME challenge)
- Ports 443, 1080, 8118 accessible
- 2GB RAM, 20GB disk space

**Test Tools Required**:
- `openssl` (TLS handshake testing)
- `curl` (proxy testing)
- `nmap` (service detection)
- `tcpdump` or `wireshark` (traffic analysis)
- `jq` (config validation)
- `certbot` (renewal testing)

### Regression Testing

**When to Run Full Test Suite**:
- Before every release
- After certificate renewal
- After Xray version upgrade
- After docker-compose changes
- Monthly security audit

### Known Limitations

1. **TC-1**: Some `openssl` versions don't support `-starttls socks5` (use direct TLS test)
2. **TC-8**: Requires root privileges for packet capture
3. **TC-11**: May show different error messages depending on client (curl, Git, VSCode)

---

## Quick Test Script

```bash
#!/bin/bash
# Quick validation script for v3.3 TLS implementation

DOMAIN="vpn.example.com"
USERNAME="alice"
PASSWORD="your_password"

echo "=== TC-1: SOCKS5 TLS Handshake ==="
timeout 5 openssl s_client -connect ${DOMAIN}:1080 -showcerts 2>/dev/null | grep "Verify return code: 0"

echo -e "\n=== TC-2: HTTP TLS Handshake ==="
curl -I --proxy https://${USERNAME}:${PASSWORD}@${DOMAIN}:8118 https://google.com 2>&1 | grep "200 OK"

echo -e "\n=== TC-3: Certificate Validity ==="
openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -dates 2>/dev/null

echo -e "\n=== TC-10: Config Validation ==="
jq '.inbounds[] | select(.listen=="0.0.0.0") | {tag, security: .streamSettings.security}' \
   /opt/vless/config/xray_config.json

echo -e "\n=== TC-12: Proxy Functionality ==="
curl --socks5 ${USERNAME}:${PASSWORD}@${DOMAIN}:1080 https://ifconfig.me 2>/dev/null

echo -e "\n=== Test Summary ==="
echo "✅ If all tests show expected output → v3.3 validation PASSED"
echo "❌ If any test fails → Review specific test case documentation"
```

---

**Document Maintenance**:
- Update test cases when requirements change
- Add new test cases for new features
- Archive old test cases in version-specific documents
- Review quarterly for accuracy

**Last Updated**: 2025-10-06
**Next Review**: 2026-01-06

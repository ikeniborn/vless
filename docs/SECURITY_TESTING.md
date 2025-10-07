# VLESS Reality VPN - Security Testing Guide

**Version:** 1.0 (v4.1)
**Last Updated:** 2025-10-07

---

## Quick Start

**Recommended:** Use built-in CLI command:

```bash
sudo vless test-security              # Full test (2-3 min)
sudo vless test-security --quick      # Fast mode (1 min, no packet capture)
sudo vless test-security --skip-pcap  # Skip tcpdump if unavailable
sudo vless test-security --verbose    # Detailed output
sudo vless test-security --dev-mode   # Development mode (no installation required)
```

**Aliases:** `vless security-test`, `vless security`

**Development Mode:** Use `--dev-mode` to test the security suite itself without a full VLESS installation.

---

## Test Coverage

### 1. **Reality Protocol (TLS 1.3)**
- X25519 key configuration validation
- Reality protocol settings verification
- Destination TLS 1.3 support check
- SNI (Server Name Indication) validation
- shortIds authentication test

### 2. **stunnel TLS Termination** (Public Proxy Mode)
- TLS 1.3 on ports 1080 (SOCKS5) and 8118 (HTTP)
- Let's Encrypt certificate validity
- Certificate expiration dates
- TLS endpoint connectivity tests

### 3. **Traffic Encryption Validation**
- Live traffic capture (tcpdump)
- Plaintext data leak detection
- TLS handshake analysis
- End-to-end encryption verification

### 4. **Certificate Security**
- Certificate chain validation
- File permissions check (600 for private keys)
- Certificate issuer verification (Let's Encrypt)
- Subject Alternative Names (SAN) validation

### 5. **DPI Resistance** (Deep Packet Inspection)
- Reality masquerading configuration
- Traffic fingerprinting resistance
- SNI-destination matching
- TLS 1.3 protocol enforcement

### 6. **SSL/TLS Vulnerabilities**
- Weak cipher suites scan (RC4, DES, 3DES, MD5, NULL)
- Obsolete protocols detection (SSLv2, SSLv3, TLS 1.0/1.1)
- Perfect Forward Secrecy (PFS) validation
- Known vulnerabilities check (POODLE, BEAST, etc.)

### 7. **Proxy Protocol Security**
- Authentication enforcement (SOCKS5, HTTP)
- Listen address validation (localhost vs public)
- Password strength check (32+ characters for v3.2+)
- UDP disabled verification (security hardening)

### 8. **Data Leak Detection**
- Exposed configuration files scan
- Default/weak credentials detection
- Container logs sensitive data check
- DNS configuration validation

---

## Prerequisites

### System Requirements
- Ubuntu 20.04+, 22.04 LTS, or Debian 10+
- Root/sudo access
- Active VLESS installation at `/opt/vless`
- At least one configured VPN user

### Required Tools

```bash
# Essential (will fail if missing)
sudo apt-get update
sudo apt-get install -y openssl curl jq iproute2 iptables

# Security testing (recommended)
sudo apt-get install -y nmap tcpdump

# Advanced analysis (optional)
sudo apt-get install -y tshark wireshark-common
```

### Verify Containers Running

```bash
cd /opt/vless
sudo docker compose ps
```

Expected output:
```
NAME            STATUS          PORTS
vless_xray      Up              0.0.0.0:443->443/tcp
vless_nginx     Up
vless_stunnel   Up              (if public proxy enabled)
```

If containers not running:
```bash
sudo docker compose up -d
```

---

## Running Tests

### Option 1: CLI Command (Recommended)

```bash
# Full comprehensive test
sudo vless test-security

# Quick test (skip packet capture)
sudo vless test-security --quick

# Skip packet capture if tcpdump unavailable
sudo vless test-security --skip-pcap

# Verbose output for debugging
sudo vless test-security --verbose
```

### Option 2: Direct Script Execution

```bash
cd /opt/vless/tests
sudo ./test_encryption_security.sh
```

### Option 3: Development Mode (No Installation Required)

For testing the security suite itself or running tests from source without a full VLESS installation:

```bash
# From project source directory
cd /path/to/vless/source
sudo bash lib/security_tests.sh --dev-mode

# Combine with other flags
sudo bash lib/security_tests.sh --dev-mode --verbose --quick
```

**Development mode features:**
- ✅ Skips installation checks (config files, users.json, Docker containers)
- ✅ Tests run from source directory instead of `/opt/vless`
- ✅ Useful for development, testing, and CI/CD pipelines
- ❌ Most tests will be skipped (expected - no config files)
- ❌ Only validates test suite logic and tool dependencies

**When to use dev mode:**
- Testing security test improvements
- Validating bash syntax and logic
- Running in CI/CD without full installation
- Developing new security checks

**Test duration:** 2-3 minutes (full), 1 minute (quick mode), <30 seconds (dev mode)

---

## Understanding Results

### ✅ All Tests Passed (Exit Code: 0)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: ALL TESTS PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Reality Protocol: TLS 1.3 configured
✓ stunnel TLS: Certificates valid
✓ Traffic Encryption: No plaintext detected
✓ DPI Resistance: Traffic looks like HTTPS
✓ SSL/TLS: No weak ciphers or protocols
✓ Proxy Security: Authentication enforced
✓ Data Leaks: None detected
```

**Action:** System is secure, no changes needed.

---

### ⚠️ Warnings (Exit Code: 0, but with warnings)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: PASSED WITH WARNINGS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Reality Protocol: OK
✓ stunnel TLS: OK
⚠ Certificate: Expires in 15 days (renew recommended)
✓ Traffic Encryption: OK
```

**Action:** Review warnings, plan certificate renewal or config updates.

---

### ❌ Test Failed (Exit Code: 1)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: TESTS FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Reality Protocol: OK
❌ stunnel TLS: Certificate expired
✓ Traffic Encryption: OK
```

**Action:** Fix identified issues immediately. System may be vulnerable.

---

## Test Details

### Reality Protocol Tests
- ✅ Private key exists and has 600 permissions
- ✅ Public key matches private key
- ✅ Destination supports TLS 1.3
- ✅ SNI configured correctly
- ✅ shortIds array not empty

### stunnel TLS Tests (Public Proxy Mode)
- ✅ stunnel.conf exists and valid
- ✅ Certificates readable by container
- ✅ Certificate not expired (>7 days validity)
- ✅ TLS 1.3 handshake successful on ports 1080, 8118
- ✅ Strong cipher suites only

### Traffic Encryption Tests
- ✅ Packet capture contains no plaintext credentials
- ✅ TLS handshake present in capture
- ✅ Application data encrypted
- ✅ No HTTP/SOCKS5 plaintext protocol headers

### DPI Resistance Tests
- ✅ Traffic looks like normal HTTPS (not VPN)
- ✅ nmap service detection reports SSL/TLS
- ✅ SNI matches destination domain
- ✅ TLS fingerprint matches legitimate website

---

## Troubleshooting

### Issue: "VLESS not installed" or "Config directory not found"

**Symptoms:**
```
ERROR: Config directory not found: /opt/vless/config
VLESS does not appear to be properly installed.
```

**Cause:** Running from source directory without full installation.

**Solutions:**

1. **Install VLESS first** (recommended for production testing):
```bash
cd /path/to/vless/source
sudo bash install.sh
sudo vless test-security
```

2. **Use development mode** (for testing the test suite itself):
```bash
cd /path/to/vless/source
sudo bash lib/security_tests.sh --dev-mode
```

**Note:** Dev mode skips most tests - only validates tool dependencies and test logic.

---

### Issue: "tcpdump: Permission denied"

**Solution:**
```bash
sudo chmod +x /opt/vless/tests/test_encryption_security.sh
sudo vless test-security --skip-pcap  # Skip packet capture
```

---

### Issue: "Certificate expired"

**Solution:**
```bash
# Manual renewal
sudo certbot renew --force-renewal

# Restart containers
cd /opt/vless
sudo docker compose restart
```

---

### Issue: "stunnel not configured"

**Cause:** Public proxy mode not enabled.

**Action:** This is expected for localhost-only mode. Tests will skip stunnel checks.

---

### Issue: "Weak cipher detected"

**Solution:**
```bash
# Check Xray config
jq '.inbounds[].streamSettings.realitySettings' /opt/vless/config/config.json

# Check stunnel config (if public proxy enabled)
cat /opt/vless/config/stunnel.conf | grep ciphersuites
```

Expected: Only TLS 1.3 cipher suites (AES-256-GCM, CHACHA20-POLY1305).

---

## Security Best Practices

### 1. Run Tests Regularly
```bash
# Monthly security audit
0 0 1 * * /usr/local/bin/vless test-security --quick
```

### 2. Monitor Certificate Expiration
```bash
# Check certificate validity
sudo openssl x509 -in /etc/letsencrypt/live/YOUR_DOMAIN/cert.pem -noout -dates
```

### 3. Review Logs
```bash
# Xray errors
sudo docker logs vless_xray --tail 100 | grep -i error

# stunnel errors (if public proxy enabled)
sudo docker logs vless_stunnel --tail 100 | grep -i error
```

### 4. Update Reality Destination
If destination site becomes unavailable or downgrades TLS:
```bash
sudo vless-config update-destination google.com:443
```

### 5. Rotate Reality Keys
Every 6-12 months or after suspected compromise:
```bash
sudo vless-config rotate-keys
# Regenerate all client configs
sudo vless-user regenerate
```

---

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | All tests passed | None |
| 1 | Tests failed | Fix issues immediately |
| 2 | Prerequisites missing | Install required tools |
| 3 | VLESS not installed | Install VLESS first |

---

## Additional Resources

- **PRD.md** - Full security requirements
- **CHANGELOG.md** - Security improvements history
- **Xray Docs** - https://xtls.github.io/config/
- **stunnel Docs** - https://www.stunnel.org/docs.html
- **Let's Encrypt** - https://letsencrypt.org/docs/

---

**Report Issues:** https://github.com/anthropics/vless-reality-vpn/issues

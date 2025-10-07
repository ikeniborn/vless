# VLESS Reality VPN - Security Testing Guide

## Overview

This guide provides comprehensive instructions for running encryption and security tests on your VLESS Reality VPN installation. The test suite validates that all connections from client to internet are properly encrypted and secure.

**Version:** 1.0
**Last Updated:** 2025-10-07

---

## Table of Contents

1. [Test Coverage](#test-coverage)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Running Tests](#running-tests)
5. [Understanding Results](#understanding-results)
6. [Troubleshooting](#troubleshooting)
7. [Security Best Practices](#security-best-practices)

---

## Test Coverage

The encryption security test suite (`test_encryption_security.sh`) validates the following:

### 1. **TLS 1.3 Configuration (Reality Protocol)**
- Verifies X25519 key configuration
- Validates Reality protocol settings
- Checks destination TLS 1.3 support
- Confirms SNI (Server Name Indication) configuration
- Tests shortIds authentication

### 2. **stunnel TLS Termination** (Public Proxy Mode)
- Validates stunnel configuration for SOCKS5 and HTTP proxies
- Checks Let's Encrypt certificate validity
- Verifies certificate expiration dates
- Tests TLS endpoints (ports 1080, 8118)

### 3. **Traffic Encryption Validation**
- Captures live traffic using tcpdump
- Analyzes packets for plaintext data leaks
- Validates TLS handshakes
- Confirms end-to-end encryption

### 4. **Certificate Security**
- Verifies certificate chain validity
- Checks certificate file permissions
- Validates certificate issuer (Let's Encrypt)
- Tests Subject Alternative Names (SAN)

### 5. **DPI Resistance** (Deep Packet Inspection)
- Validates Reality masquerading configuration
- Tests traffic fingerprinting resistance
- Verifies SNI matches destination
- Confirms TLS 1.3 usage

### 6. **SSL/TLS Vulnerabilities**
- Scans for weak cipher suites (RC4, DES, 3DES, MD5, NULL)
- Tests for obsolete protocols (SSLv2, SSLv3, TLS 1.0/1.1)
- Validates Perfect Forward Secrecy (PFS)
- Checks for known vulnerabilities (POODLE, BEAST, etc.)

### 7. **Proxy Protocol Security**
- Verifies authentication requirements (SOCKS5, HTTP)
- Validates proxy listen addresses (localhost vs public)
- Checks password strength (minimum 32 characters for v3.2)
- Tests UDP disabled (security hardening)

### 8. **Data Leak Detection**
- Scans for exposed configuration files
- Detects default/weak usernames
- Checks container logs for sensitive data
- Validates DNS configuration

---

## Prerequisites

### System Requirements

- **Operating System:** Ubuntu 20.04+, 22.04 LTS, or Debian 10+
- **Privileges:** Root or sudo access
- **VLESS Installation:** Active VLESS Reality VPN at `/opt/vless`
- **Users:** At least one VPN user configured

### Required Tools

The following tools must be installed:

```bash
# Essential tools (will fail if missing)
sudo apt-get update
sudo apt-get install -y \
    openssl \
    curl \
    jq \
    iproute2 \
    iptables \
    nmap

# Network analysis tools
sudo apt-get install -y \
    tcpdump \
    wireshark-common
```

### Optional Tools (Enhanced Testing)

```bash
# Wireshark tshark for advanced packet analysis
sudo apt-get install -y tshark

# testssl.sh for comprehensive TLS testing
wget https://testssl.sh/testssl.sh
chmod +x testssl.sh
sudo mv testssl.sh /usr/local/bin/
```

### Docker Containers

Ensure VLESS containers are running:

```bash
cd /opt/vless
docker compose ps

# Expected output: vless_xray and vless_nginx (and vless_stunnel if public proxy enabled)
```

If containers are not running:

```bash
sudo docker compose up -d
```

---

## Installation

### 1. Download Test Script

If you're working from the development repository:

```bash
cd /home/ikeniborn/Documents/Project/vless
chmod +x tests/integration/test_encryption_security.sh
```

If deployed on a production server:

```bash
# Copy from development machine or download
sudo mkdir -p /opt/vless/tests/integration
sudo cp test_encryption_security.sh /opt/vless/tests/integration/
sudo chmod +x /opt/vless/tests/integration/test_encryption_security.sh
```

### 2. Verify Installation

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh --help
```

Expected output:
```
Usage: test_encryption_security.sh [options]

Options:
  --quick       Skip long-running tests
  --skip-pcap   Skip packet capture tests
  --verbose     Show detailed output
  -h, --help    Show this help message
```

---

## Running Tests

### Basic Usage

Run all tests with default settings:

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh
```

**Note:** Root/sudo is required for packet capture (tcpdump) and system-level checks.

### Quick Mode (Skip Long Tests)

Skip traffic capture tests (~30 seconds):

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh --quick
```

### Skip Packet Capture

If tcpdump is unavailable or you want to skip packet analysis:

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh --skip-pcap
```

### Verbose Mode (Debugging)

Show detailed output for troubleshooting:

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh --verbose
```

### Combined Options

```bash
sudo /opt/vless/tests/integration/test_encryption_security.sh --quick --verbose
```

---

## Understanding Results

### Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0`  | Success | All tests passed or passed with warnings |
| `1`  | Failed  | One or more tests failed |
| `2`  | Error   | Prerequisites not met (missing tools, VLESS not installed) |
| `3`  | Critical| Critical security issues detected (immediate action required) |

### Test Output Format

Each test displays color-coded results:

- **🟢 [✓ PASS]** - Test passed successfully
- **🔴 [✗ FAIL]** - Test failed (security issue or misconfiguration)
- **🟡 [⊘ SKIP]** - Test skipped (feature disabled or tool unavailable)
- **🟡 [⚠ WARN]** - Warning (non-critical issue, review recommended)
- **🔴 [🔥 CRITICAL]** - Critical security vulnerability (immediate fix required)

### Sample Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TEST 1: Reality Protocol TLS 1.3 Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[TEST] Verifying Reality protocol TLS 1.3 settings in Xray config
[✓ PASS] Reality X25519 private key configured
[✓ PASS] Reality shortIds configured (2 entries)
[✓ PASS] Reality destination configured: google.com:443
[✓ PASS] Destination supports TLS 1.3: google.com
[✓ PASS] Reality serverNames configured: www.google.com
[✓ PASS] Reality protocol TLS 1.3 configuration valid
```

### Summary Report

At the end of the test run:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENCRYPTION SECURITY TEST SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total Tests:      45
Passed:           42
Failed:           1
Skipped:          2

Security Warnings: 3
Critical Issues:   0

Failed Tests:
  ✗ HTTP proxy port not listening: 8118

Security Issues:
  ⚠ Certificate expires within 24 hours or is already expired

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: PASSED WITH WARNINGS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Troubleshooting

### Common Issues

#### 1. "tcpdump: command not found"

**Solution:**
```bash
sudo apt-get install tcpdump
```

Or run with `--skip-pcap`:
```bash
sudo ./test_encryption_security.sh --skip-pcap
```

#### 2. "VLESS containers are not running"

**Solution:**
```bash
cd /opt/vless
sudo docker compose up -d
sudo docker compose ps  # Verify containers are running
```

#### 3. "No users configured"

**Solution:**
```bash
sudo vless-user add testuser
```

#### 4. "Certificate validation failed"

**Possible causes:**
- Certificate expired (run `sudo certbot renew`)
- Certificate files missing (check `/etc/letsencrypt/live/`)
- Incorrect domain configuration

**Solution:**
```bash
# Check certificate expiry
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -enddate

# Renew certificate
sudo certbot renew

# Restart containers
cd /opt/vless && sudo docker compose restart
```

#### 5. "Permission denied" errors

**Solution:**
```bash
# Script must be run as root for packet capture
sudo ./test_encryption_security.sh

# Verify file permissions
ls -la test_encryption_security.sh
# Should show: -rwxr-xr-x (executable)

# Fix if needed
chmod +x test_encryption_security.sh
```

#### 6. "Traffic encryption test failed - no packets captured"

**Possible causes:**
- Firewall blocking traffic
- No active connections during test
- tcpdump permissions issue

**Solution:**
```bash
# Check firewall rules
sudo ufw status

# Verify network interface
ip link show

# Run with verbose mode to see tcpdump output
sudo ./test_encryption_security.sh --verbose
```

### Test-Specific Troubleshooting

#### Reality Protocol Tests

If Reality tests fail:

1. **Check Xray configuration:**
   ```bash
   sudo jq . /opt/vless/config/xray_config.json | grep -A20 "realitySettings"
   ```

2. **Verify destination reachability:**
   ```bash
   curl -I https://google.com  # Or your configured destination
   openssl s_client -connect google.com:443 -tls1_3
   ```

3. **Regenerate Reality keys:**
   ```bash
   docker run --rm teddysun/xray:24.11.30 xray x25519
   # Update /opt/vless/config/xray_config.json with new keys
   sudo docker compose restart xray
   ```

#### stunnel Tests

If stunnel tests fail:

1. **Check stunnel container:**
   ```bash
   docker ps | grep stunnel
   docker logs vless_stunnel  # Check for errors
   ```

2. **Verify certificates:**
   ```bash
   sudo ls -la /etc/letsencrypt/live/yourdomain.com/
   sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -text
   ```

3. **Test TLS connection manually:**
   ```bash
   openssl s_client -connect yourdomain.com:1080 -tls1_3
   openssl s_client -connect yourdomain.com:8118 -tls1_3
   ```

#### Proxy Security Tests

If proxy tests fail:

1. **Check proxy configuration:**
   ```bash
   sudo jq '.inbounds[] | select(.tag | contains("proxy"))' /opt/vless/config/xray_config.json
   ```

2. **Verify authentication is enabled:**
   ```bash
   sudo jq '.inbounds[] | select(.tag == "socks5-proxy") | .settings.auth' /opt/vless/config/xray_config.json
   # Should output: "password"
   ```

3. **Test proxy connection:**
   ```bash
   # Get test user credentials
   TEST_USER=$(jq -r '.users[0].username' /opt/vless/config/users.json)
   TEST_PASS=$(jq -r '.users[0].proxy_password' /opt/vless/config/users.json)

   # Test SOCKS5 (localhost)
   curl --socks5 ${TEST_USER}:${TEST_PASS}@127.0.0.1:1080 https://ifconfig.me

   # Test HTTP (localhost)
   curl --proxy http://${TEST_USER}:${TEST_PASS}@127.0.0.1:8118 https://ifconfig.me
   ```

---

## Security Best Practices

### 1. **Regular Testing**

Run security tests:
- **After initial installation** (verify configuration)
- **After any configuration changes** (validate changes)
- **Weekly/Monthly** (detect configuration drift)
- **After system updates** (ensure compatibility)

### 2. **Certificate Management**

```bash
# Check certificate expiry
sudo certbot certificates

# Set up automatic renewal (should be default)
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Test renewal
sudo certbot renew --dry-run
```

### 3. **Password Rotation**

Rotate proxy passwords regularly:

```bash
# Reset password for user
sudo vless-user reset-proxy-password <username>

# Verify new password strength (should be 32+ characters)
sudo jq -r '.users[] | select(.username == "<username>") | .proxy_password | length' /opt/vless/config/users.json
```

### 4. **Monitoring**

Set up log monitoring:

```bash
# Monitor Xray logs
sudo docker logs -f vless_xray

# Monitor stunnel logs (if public proxy enabled)
sudo docker logs -f vless_stunnel

# Check for failed authentication attempts
sudo journalctl -u fail2ban | grep "vless-proxy"
```

### 5. **Firewall Hardening**

```bash
# Review UFW rules
sudo ufw status numbered

# Ensure rate limiting on proxy ports (if public)
sudo ufw limit 1080/tcp comment 'SOCKS5 rate limit'
sudo ufw limit 8118/tcp comment 'HTTP proxy rate limit'

# Reload firewall
sudo ufw reload
```

### 6. **Update Reality Destination**

Periodically change Reality masquerading destination to avoid patterns:

```bash
# Edit xray_config.json
sudo vi /opt/vless/config/xray_config.json

# Update "dest" field to another TLS 1.3 site (google.com, microsoft.com, cloudflare.com, etc.)
# Update "serverNames" to match

# Restart Xray
cd /opt/vless && sudo docker compose restart xray
```

### 7. **Backup Configuration**

```bash
# Backup VLESS configuration
sudo tar -czf vless_backup_$(date +%Y%m%d).tar.gz /opt/vless/config/

# Store backup securely (encrypted, off-site)
```

---

## Advanced Testing

### Manual Traffic Analysis

If you want to manually inspect traffic:

```bash
# Capture traffic to file
sudo tcpdump -i any -w /tmp/vless_traffic.pcap 'tcp and port 443'

# Analyze with Wireshark (GUI)
wireshark /tmp/vless_traffic.pcap

# Analyze with tshark (CLI)
tshark -r /tmp/vless_traffic.pcap -Y "tls.handshake.type == 1"  # Client Hello
tshark -r /tmp/vless_traffic.pcap -Y "tls.handshake.version == 0x0304"  # TLS 1.3

# Search for plaintext (should find none)
strings /tmp/vless_traffic.pcap | grep -i "password"
```

### External Security Scanning

Test from external network:

```bash
# From a different machine (not the server)
nmap -sV -p 443,1080,8118 your-server-ip

# SSL/TLS scanning with testssl.sh (comprehensive)
testssl.sh --full your-server-ip:8118
```

### DPI Simulation

Test if traffic looks like real HTTPS:

```bash
# Compare TLS fingerprint with real destination
openssl s_client -connect your-server-ip:443 -showcerts | openssl x509 -noout -fingerprint
openssl s_client -connect google.com:443 -showcerts | openssl x509 -noout -fingerprint
```

---

## Automated Testing (CI/CD)

### GitHub Actions Example

```yaml
name: Security Tests

on:
  push:
    branches: [ main ]
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  security-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Install VLESS
        run: |
          # Installation steps

      - name: Run Security Tests
        run: |
          sudo /opt/vless/tests/integration/test_encryption_security.sh --quick

      - name: Upload Test Report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: security-test-report
          path: /tmp/vless_security_test_*
```

---

## Support

### Getting Help

- **GitHub Issues:** https://github.com/anthropics/vless-reality-vpn/issues
- **Documentation:** `/opt/vless/docs/`
- **Logs:** `/opt/vless/logs/`

### Reporting Security Issues

If tests detect critical vulnerabilities, please report to:
- **Email:** security@example.com
- **Encrypted:** Use PGP key (see SECURITY.md)

### Contributing

Contributions to improve test coverage are welcome! Please submit pull requests with:
- Test description and rationale
- Expected behavior documentation
- Error handling

---

**Version:** 1.0
**Last Updated:** 2025-10-07
**License:** MIT

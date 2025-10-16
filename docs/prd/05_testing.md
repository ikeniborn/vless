# PRD v4.1 - Testing Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 7. Testing Requirements

### 7.1 TLS Integration Tests (NEW)

**Test Case 1: TLS Handshake - SOCKS5**
```bash
# Verify TLS on SOCKS5 port
openssl s_client -connect server:1080 -showcerts

# Expected Output:
# - Certificate chain displayed
# - Issuer: Let's Encrypt
# - Subject: CN=vpn.example.com
# - Verify return code: 0 (ok)
```

**Test Case 2: TLS Handshake - HTTP/HTTPS**
```bash
# Verify HTTPS on HTTP proxy port
curl -I --proxy https://user:pass@server:8118 https://google.com

# Expected Output:
# HTTP/1.1 200 OK
# (no SSL warnings)
```

**Test Case 3: Certificate Validation**
```bash
# Check certificate validity
openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -text

# Expected:
# - Issuer: Let's Encrypt
# - Validity: 90 days from issuance
# - Subject Alt Name: DNS:vpn.example.com
```

**Test Case 4: Auto-Renewal Dry-Run**
```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# Expected Output:
# Congratulations, all simulated renewals succeeded
```

**Test Case 5: Deploy Hook Execution**
```bash
# Manually trigger deploy hook
sudo /usr/local/bin/vless-cert-renew

# Expected:
# - Xray restarts successfully
# - Downtime < 5 seconds
# - docker logs shows restart
```

---

### 7.2 Client Integration Tests (NEW)

**Test Case 6: VSCode Extension via HTTPS Proxy**
```json
// VSCode settings.json
{
  "http.proxy": "https://alice:PASSWORD@server:8118",
  "http.proxyStrictSSL": true
}
```

**Steps:**
1. Apply settings.json
2. Open Extensions (Ctrl+Shift+X)
3. Search "Python"
4. Install extension

**Expected:**
- ✅ Extension installs successfully
- ✅ No SSL certificate warnings
- ✅ Xray logs show HTTPS connection

**Test Case 7: Git Clone via SOCKS5s Proxy**
```bash
# Configure Git
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

# Clone repository
git clone https://github.com/torvalds/linux.git

# Expected:
# - Clone succeeds
# - No TLS errors
# - Xray logs show SOCKS5 connection
```

---

### 7.3 Security Tests (v3.3)

**Test Case 8: Wireshark Traffic Capture**
```bash
# Capture proxy traffic
sudo tcpdump -i any -w /tmp/proxy_traffic.pcap port 1080

# Analyze in Wireshark
wireshark /tmp/proxy_traffic.pcap

# Expected:
# - TLS 1.3 handshake visible
# - Application Data encrypted
# - NO plaintext SOCKS5/HTTP
# - NO plaintext credentials
```

**Test Case 9: Nmap Service Detection**
```bash
# Scan proxy ports
nmap -sV -p 1080,8118 server

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 1080/tcp open  ssl/socks
# 8118/tcp open  ssl/http
```

**Test Case 10: Config Validation - No Plain Proxy**
```bash
# Ensure no plain proxy on public interface
jq '.inbounds[] | select(.listen=="0.0.0.0") | {tag, security: .streamSettings.security}' /opt/vless/config/xray_config.json

# Expected:
# {"tag": "socks5-tls", "security": "tls"}
# {"tag": "http-tls", "security": "tls"}
# (NO entries with "security": null or missing)
```

---

### 7.4 Backward Compatibility Tests (v3.2 → v3.3)

**Test Case 11: Old Configs Must Fail**
```bash
# Try connecting with old v3.2 plain config
curl --socks5 alice:PASSWORD@server:1080 https://ifconfig.me

# Expected:
# - Connection FAILS (plain SOCKS5 not accepted)
# - Error: "TLS handshake required"
```

**Test Case 12: New Configs Must Work**
```bash
# Connect with new v3.3 TLS config
curl --socks5 alice:PASSWORD@server:1080 --proxy-insecure https://ifconfig.me
# (Note: --proxy-insecure needed if testing with self-signed, NOT needed with Let's Encrypt)

# Expected:
# - Connection succeeds
# - Returns external IP
```

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

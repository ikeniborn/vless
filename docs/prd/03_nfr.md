# PRD v4.3 - Non-Functional Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 3. Non-Functional Requirements

### NFR-SEC-001: Mandatory TLS Policy (CRITICAL - NEW)

**Requirement:** TLS encryption MANDATORY for all public proxy inbounds. NO plain proxy allowed.

**Metrics:**
- [ ] 100% публичных прокси с TLS
- [ ] 0 plain proxy endpoints на public interface
- [ ] Audit: `nmap -sV -p 1080,8118 server` shows TLS/SSL detected
- [ ] Config validation: `jq '.inbounds[] | select(.listen=="0.0.0.0") | .streamSettings.security' config.json` returns "tls" for all

**Validation Script:**
```bash
#!/bin/bash
# Validate mandatory TLS for public proxies

CONFIG="/opt/vless/config/xray_config.json"

# Check each public inbound has TLS
jq -r '.inbounds[] | select(.listen=="0.0.0.0") | "\(.tag): \(.streamSettings.security // "NONE")"' "$CONFIG" | while read line; do
  if [[ "$line" =~ "NONE" ]]; then
    echo "❌ CRITICAL: Plain proxy detected on public interface"
    echo "   $line"
    exit 1
  fi
done

echo "✅ All public proxies have TLS enabled"
```

---

### NFR-OPS-001: Zero Manual Intervention для Certificate Renewal (CRITICAL - NEW)

**Requirement:** Сертификаты ДОЛЖНЫ обновляться автоматически без вмешательства администратора.

**Metrics:**
- [ ] 100% автоматизация renewal (cron/systemd timer)
- [ ] 0 manual steps для cert updates
- [ ] Мониторинг: cert expiry alerts за 30 дней до истечения
- [ ] Email notifications при renewal failures (Let's Encrypt default)

---

### NFR-PERF-001: TLS Performance Overhead (MEDIUM - NEW)

**Requirement:** TLS encryption НЕ ДОЛЖНО значительно влиять на производительность прокси.

**Metrics:**
- [ ] Latency overhead < 2ms (TLS handshake amortized over connection reuse)
- [ ] CPU overhead < 5% (TLS 1.3 + AES-NI hardware acceleration)
- [ ] Throughput degradation < 10% vs plain proxy
- [ ] Target: 10-50 concurrent users без performance issues

**Benchmark:**
```bash
# Baseline (no proxy)
time curl -s https://ifconfig.me

# With TLS proxy
time curl -s --proxy https://user:pass@server:8118 https://ifconfig.me

# Compare latency
```

---

### NFR-COMPAT-001: Client Compatibility (HIGH - NEW)

**Requirement:** Система ДОЛЖНА быть совместима с VSCode и Git клиентами без дополнительной настройки.

**Metrics:**
- [ ] VSCode (all versions 1.60+) - HTTPS proxy support confirmed
- [ ] Git (all versions 2.0+) - SOCKS5s support confirmed
- [ ] 100% success rate для основных операций (clone, push, extensions)
- [ ] No SSL certificate warnings (Let's Encrypt trusted by default)

---

### NFR-USABILITY-001: Installation Simplicity (MEDIUM - NEW)

**Requirement:** Установка с TLS НЕ ДОЛЖНА усложнять процесс для пользователя.

**Metrics:**
- [ ] Installation time < 7 минут (было 5 мин для v3.2, +2 мин для certbot)
- [ ] User prompts: только домен и email для Let's Encrypt
- [ ] Автоматическая валидация домена (DNS check перед certbot)
- [ ] Clear error messages on failure (DNS, port 80, rate limit)

---

### NFR-RELIABILITY-001: Cert Renewal Reliability (HIGH - NEW)

**Requirement:** Автоматическое обновление сертификатов ДОЛЖНО быть надежным.

**Metrics:**
- [ ] Cert renewal success rate > 99%
- [ ] Retry logic для failed renewals (certbot built-in: 3 attempts)
- [ ] Alert mechanism при repeated renewal failures (email notifications)
- [ ] Grace period: 30 дней до истечения для troubleshooting
- [ ] Downtime during renewal < 5 seconds

### NFR-RPROXY-001: Reverse Proxy Performance (v4.2 - NEW)

**Requirement:** Reverse proxy ДОЛЖЕН обеспечивать минимальные задержки и высокую пропускную способность.

**Metrics:**
- [ ] Latency overhead < 50ms (vs direct access to target site)
- [ ] Throughput: 100 Mbps per reverse proxy instance
- [ ] Max concurrent connections: 1000 per domain
- [ ] Total throughput with 10 domains: 1 Gbps aggregate
- [ ] CPU overhead < 10% per domain

**Benchmark:**
```bash
# Baseline (direct access)
time curl -s https://blocked-site.com > /dev/null

# With reverse proxy (v4.3: subdomain-based, NO port!)
time curl -s -u user:pass https://myproxy.example.com > /dev/null

# Compare latency: < 50ms overhead expected
```

---

### NFR-RPROXY-002: Reverse Proxy Scalability (v4.3 - UPDATED)

**Requirement:** Система ДОЛЖНА поддерживать до 10 reverse proxy доменов на одном сервере.

**Metrics:**
- [ ] Support up to 10 reverse proxy domains per server
- [ ] Each domain: 1 target site (1:1 mapping)
- [ ] Each domain: localhost-only port (9443-9452 range) **v4.3: changed from 8443-8452**
- [ ] Each domain: separate Nginx backend (binds to 127.0.0.1)
- [ ] **Subdomain-based access:** https://domain (NO port number!) **v4.3**
- [ ] **HAProxy SNI routing:** Frontend 443 → Nginx backends **v4.3**
- [ ] Port allocation: sequential 9443-9452
- [ ] Port reuse after domain removal

**Constraints:**
- Internal port range: 9443-9452 (localhost-only, NOT publicly exposed)
- Public access: HAProxy frontend 443 (SNI routing to all reverse proxies)
- Reserved ports: 443 (HAProxy SNI/TLS), 1080 (SOCKS5 TLS), 8118 (HTTP TLS), 8443 (Xray Reality) **v4.3**
- Max domains: 10 per server (architectural limit)

**Recommendation:** For > 10 domains, use multiple independent servers.

---

### NFR-RPROXY-003: Reverse Proxy Reliability (v4.2 - NEW)

**Requirement:** Reverse proxy ДОЛЖЕН обеспечивать высокую доступность с автоматическим восстановлением.

**Metrics:**
- [ ] Uptime: 99.9% (same as VLESS VPN)
- [ ] Auto-recovery: Container restart on failure (Docker restart policy)
- [ ] Certificate auto-renewal: Same as FR-CERT-002 (certbot + deploy hook)
- [ ] fail2ban ban success rate: 99% (5 failed attempts → 1 hour ban)
- [ ] Config validation before apply: 100% (nginx -t, xray run -test)

**Health Checks:**
```yaml
healthcheck:
  test: ["CMD", "nginx", "-t"]
  interval: 30s
  timeout: 5s
  retries: 3
```

---

### NFR-RPROXY-004: Reverse Proxy Security (v4.2 - NEW)

**Requirement:** Reverse proxy ДОЛЖЕН соответствовать требованиям безопасности с обязательными митигациями.

**Metrics:**
- [ ] 100% TLS 1.3 connections (no fallback to TLS 1.2)
- [ ] HSTS header present on all responses (max-age=31536000)
- [ ] fail2ban ban rate: 99% (5 failed auth → ban)
- [ ] No access log leaks: 0 IP/URL records in logs (privacy validated)
- [ ] Error log contains auth failures only (no sensitive data)
- [ ] All VULN-001/002/003/004/005 fixes validated

**Validation:**
```bash
# Check TLS version (v4.3: subdomain-based, NO port!)
openssl s_client -connect myproxy.example.com:443 -servername myproxy.example.com -tls1_3

# Check HSTS header (v4.3: https://domain, NO port number!)
curl -I -u user:pass https://myproxy.example.com | grep Strict-Transport-Security

# Check no access log
ls -la /opt/vless/logs/nginx/reverse-proxy-access.log  # Should NOT exist
```

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

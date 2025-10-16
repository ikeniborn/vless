# PRD v4.1 - Non-Functional Requirements

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

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

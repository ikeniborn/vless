# Тесты Безопасности Шифрования / Encryption Security Tests

## Quick Start (Быстрый Старт)

### ✅ Рекомендуемый способ: CLI команда (после установки VLESS)

```bash
# Полный набор тестов / Full test suite (2-3 min)
sudo vless test-security

# Быстрый режим / Quick mode (1 min)
sudo vless test-security --quick

# С подробным выводом / Verbose output
sudo vless test-security --verbose
```

**Алиасы / Aliases:** `test-security`, `security-test`, `security`

---

### Альтернативный способ: Прямой запуск модуля

```bash
# Установка зависимостей / Install dependencies
sudo apt-get update
sudo apt-get install -y openssl curl jq iproute2 iptables nmap tcpdump

# Запуск модуля / Run module directly
sudo /opt/vless/lib/security_tests.sh

# Или из development-репозитория:
cd ~/Documents/Project/vless
sudo lib/security_tests.sh --quick
```

## Что тестируется / What is tested

✅ **Reality Protocol TLS 1.3** - X25519 keys, masquerading, SNI
✅ **stunnel TLS Termination** - SOCKS5/HTTP over TLS (public proxy mode)
✅ **Traffic Encryption** - Packet capture, plaintext detection
✅ **Certificate Security** - Let's Encrypt, expiration, permissions
✅ **DPI Resistance** - Deep Packet Inspection evasion
✅ **SSL/TLS Vulnerabilities** - Weak ciphers, obsolete protocols
✅ **Proxy Security** - Authentication, password strength, binding
✅ **Data Leaks** - Config file exposure, log analysis

## Результаты / Results

| Exit Code | Значение / Meaning |
|-----------|-------------------|
| `0` | ✅ Успех / Success |
| `1` | ❌ Провал / Failed |
| `2` | ⚠️ Ошибка предварительных требований / Prerequisites error |
| `3` | 🔥 Критические уязвимости / Critical vulnerabilities |

## Документация / Documentation

- **Полное руководство (RU):** [../../docs/SECURITY_TESTING_RU.md](../../docs/SECURITY_TESTING_RU.md)
- **Full guide (EN):** [../../docs/SECURITY_TESTING.md](../../docs/SECURITY_TESTING.md)
- **Project docs:** [../../docs/CLAUDE.md](../../docs/CLAUDE.md)

## Помощь / Help

```bash
./test_encryption_security.sh --help
```

## Типичные проблемы / Common issues

**tcpdump not found:**
```bash
sudo apt-get install tcpdump
# or use: ./test_encryption_security.sh --skip-pcap
```

**Containers not running:**
```bash
cd /opt/vless && sudo docker compose up -d
```

**No users configured:**
```bash
sudo vless-user add testuser
```

**Certificate expired:**
```bash
sudo certbot renew
cd /opt/vless && sudo docker compose restart
```

---

**Version:** 1.0
**Date:** 2025-10-07

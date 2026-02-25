# 🚀 Быстрый Старт: Тесты Безопасности

## ✅ Рекомендуемый Способ: Через CLI (самый простой)

После установки VLESS используйте встроенную команду:

```bash
# Полный тест безопасности (2-3 минуты)
sudo vless test-security

# Быстрый режим (1 минута)
sudo vless test-security --quick

# С подробным выводом
sudo vless test-security --verbose

# Без packet capture
sudo vless test-security --skip-pcap
```

**Алиасы:** `test-security`, `security-test`, `security`

---

## 📁 Альтернативный Способ: Прямой Запуск Скрипта

### Вариант 1: Из директории проекта (Development)

```bash
# Перейти в корень проекта
cd ~/Documents/Project/vless

# Запустить модуль напрямую
sudo lib/security_tests.sh
```

### Вариант 2: На production-сервере

```bash
# Запустить модуль из /opt/familytraffic
sudo /opt/familytraffic/lib/security_tests.sh

# Или с опциями
sudo /opt/familytraffic/lib/security_tests.sh --quick --verbose
```

---

## ⚡ Установка Зависимостей

```bash
sudo apt-get update
sudo apt-get install -y openssl curl jq nmap tcpdump tshark
```

---

## 🎯 Команды Запуска

### Полный тест (2-3 минуты)

```bash
sudo ./test_encryption_security.sh
```

### Быстрый режим (1 минута)

```bash
sudo ./test_encryption_security.sh --quick
```

### Без packet capture (если tcpdump недоступен)

```bash
sudo ./test_encryption_security.sh --skip-pcap
```

### С подробным выводом (отладка)

```bash
sudo ./test_encryption_security.sh --verbose
```

### Комбинация опций

```bash
sudo ./test_encryption_security.sh --quick --verbose
```

---

## 📋 Что Проверяется

- ✅ Reality Protocol TLS 1.3 (X25519, SNI, маскировка)
- ✅ stunnel TLS-терминация (SOCKS5/HTTP прокси)
- ✅ Шифрование трафика (перехват пакетов, поиск plaintext)
- ✅ Безопасность сертификатов (Let's Encrypt)
- ✅ Устойчивость к DPI (Deep Packet Inspection)
- ✅ SSL/TLS уязвимости (слабые шифры, устаревшие протоколы)
- ✅ Безопасность прокси (аутентификация, пароли)
- ✅ Утечки данных (конфигурации, логи)

---

## ✅ Результат

### Успех (Exit Code: 0)
```
RESULT: ALL TESTS PASSED
```
**Ваше соединение полностью зашифровано!**

### Провал (Exit Code: 1)
```
RESULT: FAILED
```
**Есть проблемы с конфигурацией** - см. детали в выводе

### Критично (Exit Code: 3)
```
RESULT: CRITICAL SECURITY ISSUES DETECTED
```
**🔥 НЕМЕДЛЕННО ТРЕБУЕТСЯ ДЕЙСТВИЕ!**

---

## 🔧 Типичные Проблемы

### "tcpdump: command not found"
```bash
sudo apt-get install tcpdump
# или
sudo ./test_encryption_security.sh --skip-pcap
```

### "VLESS containers are not running"
```bash
cd /opt/familytraffic
sudo docker compose up -d
```

### "No users configured"
```bash
sudo vless-user add testuser
```

### "Certificate validation failed"
```bash
sudo certbot renew
cd /opt/familytraffic && sudo docker compose restart
```

---

## 📚 Полная Документация

- **Детальная инструкция (RU):** `../../docs/SECURITY_TESTING_RU.md`
- **Full guide (EN):** `../../docs/SECURITY_TESTING.md`

---

**Дата:** 2025-10-07 | **Версия:** 1.0

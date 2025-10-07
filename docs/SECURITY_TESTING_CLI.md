# Тестирование Безопасности Через CLI

## ✅ Рекомендуемый Способ Запуска

После установки VLESS используйте встроенную CLI команду для тестирования безопасности:

```bash
sudo vless test-security
```

### Опции

```bash
# Полный тест (2-3 минуты) - проверяет всё
sudo vless test-security

# Быстрый режим (1 минута) - без packet capture
sudo vless test-security --quick

# Без перехвата пакетов (если tcpdump недоступен)
sudo vless test-security --skip-pcap

# С подробным выводом (для отладки)
sudo vless test-security --verbose

# Комбинирование опций
sudo vless test-security --quick --verbose
```

### Алиасы Команды

Все три варианта работают одинаково:

```bash
sudo vless test-security
sudo vless security-test
sudo vless security
```

---

## 📋 Что Проверяется

### 1. **Reality Protocol TLS 1.3**
- Конфигурация X25519 ключей
- Настройки маскировки трафика
- Поддержка TLS 1.3 на destination
- Валидация SNI (Server Name Indication)

### 2. **stunnel TLS-терминация** (если включен публичный прокси)
- TLS 1.3 на портах 1080 (SOCKS5) и 8118 (HTTP)
- Валидность Let's Encrypt сертификатов
- Проверка срока действия сертификатов
- Конфигурация cipher suites

### 3. **Шифрование Трафика**
- Перехват пакетов (tcpdump)
- Поиск незашифрованных данных (plaintext)
- Анализ TLS handshakes
- Проверка end-to-end шифрования

### 4. **Безопасность Сертификатов**
- Валидация цепочки сертификатов
- Проверка прав доступа к файлам
- Проверка издателя (Let's Encrypt)
- Валидация Subject Alternative Names

### 5. **Устойчивость к DPI** (Deep Packet Inspection)
- Проверка маскировки Reality
- Анализ TLS fingerprint
- Проверка соответствия SNI и destination
- Тест на обнаружение VPN трафика

### 6. **SSL/TLS Уязвимости**
- Сканирование слабых шифров (RC4, DES, 3DES, MD5)
- Проверка устаревших протоколов (SSLv2, SSLv3, TLS 1.0)
- Валидация Perfect Forward Secrecy
- Проверка известных уязвимостей

### 7. **Безопасность Прокси**
- Проверка обязательной аутентификации
- Валидация длины паролей (32+ символов)
- Проверка привязки к интерфейсам
- Тест отключения UDP (security hardening)

### 8. **Утечки Данных**
- Проверка прав доступа к конфигурациям
- Поиск чувствительных данных в логах
- Проверка DNS конфигурации
- Анализ default/weak credentials

---

## 📊 Интерпретация Результатов

### ✅ Все Тесты Пройдены (Exit Code: 0)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: ALL TESTS PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Ваше соединение полностью защищено!**
- Трафик зашифрован от клиента до интернета
- Нет уязвимостей TLS/SSL
- Прокси безопасно настроен
- Нет утечек данных

**Рекомендации:**
- Запускайте тесты периодически (раз в неделю/месяц)
- Мониторьте логи: `sudo vless logs`
- Обновляйте сертификаты: `sudo certbot renew`

---

### ⚠️ Пройдено с Предупреждениями (Exit Code: 0, но есть warnings)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: PASSED WITH WARNINGS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Warnings: 3
```

**Система работает, но есть рекомендации.**

**Типичные предупреждения:**
- Сертификат скоро истекает (< 30 дней)
  ```bash
  sudo certbot renew
  ```
- Слабые имена пользователей (admin, test, demo)
  ```bash
  sudo vless add-user unique_username_123
  ```
- TLS 1.0/1.1 разрешены (устарели)
  - Обновите конфигурацию stunnel

**Действия:** Исправьте предупреждения, запустите тесты снова

---

### ❌ Тесты Провалены (Exit Code: 1)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Failed Tests:
  ✗ HTTP proxy port not listening: 8118
  ✗ Certificate validation failed
```

**Есть проблемы с конфигурацией.**

**Типичные проблемы:**

**1. Контейнеры не запущены:**
```bash
cd /opt/vless
sudo docker compose ps
sudo docker compose up -d
```

**2. Порты не слушают:**
```bash
ss -tlnp | grep -E "443|1080|8118"
sudo ufw status
```

**3. Конфигурация неправильная:**
```bash
jq . /opt/vless/config/xray_config.json
sudo vless test  # Test Xray config
```

**4. Сертификаты истекли:**
```bash
sudo certbot renew
cd /opt/vless && sudo docker compose restart
```

---

### 🔥 Критические Проблемы (Exit Code: 3)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULT: CRITICAL SECURITY ISSUES DETECTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Issues: 2
  🔥 CRITICAL: Plaintext data detected in traffic
  🔥 CRITICAL: Private key file permissions insecure
```

**⚠️ НЕМЕДЛЕННО ТРЕБУЕТСЯ ДЕЙСТВИЕ!**

**Критические проблемы включают:**
- Незашифрованный трафик (plaintext обнаружен)
- Слабые шифры (RC4, DES)
- Приватный ключ доступен всем
- Отсутствует аутентификация на прокси

**Действия (СРОЧНО):**

1. **ОСТАНОВИТЕ СЕРВИС:**
   ```bash
   cd /opt/vless
   sudo docker compose down
   ```

2. **ИЗУЧИТЕ ДЕТАЛИ В ВЫВОДЕ ТЕСТА**
   - Прочитайте все сообщения с 🔥 CRITICAL
   - Найдите конкретные файлы/конфигурации

3. **ИСПРАВЬТЕ ПРОБЛЕМЫ:**

   **Если plaintext в трафике:**
   ```bash
   # Проверьте Reality keys
   jq '.inbounds[0].streamSettings.realitySettings' /opt/vless/config/xray_config.json

   # Проверьте stunnel TLS
   docker logs vless_stunnel | grep -i error
   ```

   **Если insecure permissions:**
   ```bash
   # Исправьте права доступа
   sudo chmod 600 /opt/vless/config/*.json
   sudo chmod 600 /opt/vless/keys/*.key
   ```

   **Если слабые шифры:**
   ```bash
   # Обновите stunnel.conf
   sudo vi /opt/vless/config/stunnel.conf
   # Убедитесь: ciphersuites = TLS_AES_256_GCM_SHA384:...
   ```

4. **ЗАПУСТИТЕ ТЕСТЫ СНОВА:**
   ```bash
   sudo vless test-security --verbose
   ```

5. **ТОЛЬКО ПОСЛЕ УСПЕШНОГО ПРОХОЖДЕНИЯ:**
   ```bash
   cd /opt/vless
   sudo docker compose up -d
   ```

---

## 🔧 Решение Типичных Проблем

### Проблема: "tcpdump: command not found"

**Решение 1 (установить):**
```bash
sudo apt-get update
sudo apt-get install tcpdump
```

**Решение 2 (пропустить packet capture):**
```bash
sudo vless test-security --skip-pcap
```

---

### Проблема: "VLESS containers are not running"

**Проверка:**
```bash
cd /opt/vless
sudo docker compose ps
```

**Решение:**
```bash
sudo docker compose up -d
sudo docker compose ps  # Проверить снова
```

---

### Проблема: "No users configured"

**Решение:**
```bash
sudo vless add-user testuser
sudo vless list-users
```

---

### Проблема: "Certificate validation failed"

**Причины:**
- Сертификат истёк
- Файлы отсутствуют
- Неправильная конфигурация домена

**Диагностика:**
```bash
# Проверить срок действия
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -enddate

# Проверить наличие файлов
sudo ls -la /etc/letsencrypt/live/yourdomain.com/

# Проверить домен в конфигурации
grep DOMAIN /opt/vless/.env
```

**Решение:**
```bash
# Обновить сертификаты
sudo certbot renew

# Перезапустить сервисы
cd /opt/vless && sudo docker compose restart
```

---

### Проблема: "Permission denied"

**Причина:** Скрипт требует root для packet capture

**Решение:**
```bash
# ВСЕГДА используйте sudo
sudo vless test-security
```

---

### Проблема: "Traffic encryption test failed - no packets captured"

**Причины:**
- Firewall блокирует tcpdump
- Нет активных соединений
- Неправильный network interface

**Диагностика:**
```bash
# Проверить firewall
sudo ufw status

# Проверить network interfaces
ip link show

# Запустить с verbose для отладки
sudo vless test-security --verbose
```

**Решение:**
```bash
# Временно разрешить tcpdump (если ufw блокирует)
sudo ufw allow from any to any

# Или пропустить packet capture
sudo vless test-security --skip-pcap
```

---

## 🚀 Дополнительные Команды

### Показать Help

```bash
sudo vless test-security --help
```

### Проверить Xray Конфигурацию

```bash
sudo vless test
```

### Проверить Логи

```bash
# Все логи
sudo vless logs

# Только Xray
sudo vless logs xray

# Только stunnel
sudo vless logs stunnel
```

### Статус Сервисов

```bash
sudo vless status
```

### Информация о Сервере

```bash
sudo vless info
```

---

## 📚 Дополнительная Документация

- **Детальное руководство (RU):** `/opt/vless/docs/SECURITY_TESTING_RU.md`
- **Full guide (EN):** `/opt/vless/docs/SECURITY_TESTING.md`
- **Quick Start:** `tests/integration/QUICK_START_RU.md`
- **Project docs:** `/opt/vless/docs/CLAUDE.md`

---

## 🔄 Регулярное Тестирование

Рекомендуется запускать тесты безопасности:

- **После установки** - проверка конфигурации
- **После изменений** - валидация изменений
- **Еженедельно** - мониторинг безопасности
- **После обновлений** - проверка совместимости

### Автоматизация (Cron)

```bash
# Добавить в crontab для еженедельного запуска
sudo crontab -e

# Добавить строку:
0 2 * * 0 /usr/local/bin/vless test-security --quick > /var/log/vless_security_test.log 2>&1
```

---

**Версия:** 1.0
**Дата:** 2025-10-07
**Лицензия:** MIT

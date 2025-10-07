# Тестирование Безопасности Шифрования VLESS Reality VPN

## Краткое Руководство по Запуску

**Дата:** 2025-10-07
**Версия:** 1.0

---

## Что Тестирует Скрипт

Скрипт `test_encryption_security.sh` проверяет безопасность всего пути соединения от клиента до интернета через прокси:

### 🔐 Проверки Шифрования

1. **Reality Protocol (TLS 1.3)**
   - Конфигурация X25519 ключей
   - Правильность настроек маскировки трафика
   - Валидация destination (цели маскировки)

2. **stunnel TLS-терминация** (если включен публичный прокси)
   - Проверка TLS сертификатов Let's Encrypt
   - Валидация TLS 1.3 соединений на портах 1080 (SOCKS5) и 8118 (HTTP)

3. **Анализ Трафика**
   - Перехват пакетов (tcpdump)
   - Поиск незашифрованных данных (plaintext)
   - Проверка TLS handshake

4. **Устойчивость к DPI** (Deep Packet Inspection)
   - Проверка, что трафик выглядит как обычный HTTPS
   - Валидация SNI и fingerprint

5. **Уязвимости SSL/TLS**
   - Сканирование слабых шифров (RC4, DES, 3DES, MD5)
   - Проверка устаревших протоколов (SSLv2, SSLv3, TLS 1.0)
   - Валидация Perfect Forward Secrecy

6. **Безопасность Прокси**
   - Проверка обязательной аутентификации
   - Валидация длины паролей (32+ символов)
   - Проверка привязки к интерфейсам

7. **Утечки Данных**
   - Проверка прав доступа к конфигурационным файлам
   - Поиск чувствительных данных в логах
   - Проверка DNS-конфигурации

---

## Предварительные Требования

### Система

- Ubuntu 20.04+, 22.04 LTS или Debian 10+
- Права root/sudo
- Установленный VLESS Reality VPN в `/opt/vless`
- Минимум один созданный пользователь VPN

### Установка Необходимых Утилит

```bash
# Базовые инструменты (обязательно)
sudo apt-get update
sudo apt-get install -y openssl curl jq iproute2 iptables nmap tcpdump

# Опционально: расширенный анализ трафика
sudo apt-get install -y tshark wireshark-common
```

### Проверка Контейнеров

Убедитесь, что контейнеры VLESS запущены:

```bash
cd /opt/vless
sudo docker compose ps
```

Ожидаемый вывод:
```
NAME            STATUS          PORTS
vless_xray      Up 2 hours      0.0.0.0:443->443/tcp
vless_nginx     Up 2 hours
vless_stunnel   Up 2 hours      (только если включен публичный прокси)
```

Если контейнеры не запущены:

```bash
sudo docker compose up -d
```

---

## Запуск Тестов

### 1. Быстрый Запуск (Рекомендуется)

Запустить все тесты с настройками по умолчанию:

```bash
sudo /home/ikeniborn/Documents/Project/vless/tests/integration/test_encryption_security.sh
```

**Время выполнения:** ~2-3 минуты

### 2. Быстрый Режим (Без Длительных Тестов)

Пропустить тесты перехвата трафика (tcpdump):

```bash
sudo /home/ikeniborn/Documents/Project/vless/tests/integration/test_encryption_security.sh --quick
```

**Время выполнения:** ~1 минута

### 3. Без Packet Capture

Если tcpdump недоступен или вызывает проблемы:

```bash
sudo /home/ikeniborn/Documents/Project/vless/tests/integration/test_encryption_security.sh --skip-pcap
```

### 4. Подробный Вывод (Отладка)

Для детальной информации при поиске проблем:

```bash
sudo /home/ikeniborn/Documents/Project/vless/tests/integration/test_encryption_security.sh --verbose
```

### 5. Комбинирование Опций

```bash
sudo /home/ikeniborn/Documents/Project/vless/tests/integration/test_encryption_security.sh --quick --verbose
```

---

## Понимание Результатов

### Коды Возврата

| Код | Значение | Описание |
|-----|----------|----------|
| `0` | Успех | Все тесты пройдены или пройдены с предупреждениями |
| `1` | Провал | Один или несколько тестов не прошли |
| `2` | Ошибка | Не выполнены предварительные требования |
| `3` | Критично | Обнаружены критические уязвимости безопасности |

### Формат Вывода

Каждый тест показывает результат с цветовой кодировкой:

- **🟢 [✓ PASS]** - Тест пройден успешно
- **🔴 [✗ FAIL]** - Тест провален (проблема безопасности или неправильная конфигурация)
- **🟡 [⊘ SKIP]** - Тест пропущен (функция отключена или инструмент недоступен)
- **🟡 [⚠ WARN]** - Предупреждение (некритичная проблема, рекомендуется проверить)
- **🔴 [🔥 CRITICAL]** - Критическая уязвимость (требуется немедленное исправление)

### Пример Успешного Вывода

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TEST 1: Reality Protocol TLS 1.3 Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[TEST] Проверка настроек Reality protocol TLS 1.3 в конфигурации Xray
[✓ PASS] Приватный ключ X25519 настроен
[✓ PASS] Reality shortIds настроены (2 записи)
[✓ PASS] Reality destination настроен: google.com:443
[✓ PASS] Destination поддерживает TLS 1.3: google.com
[✓ PASS] Reality serverNames настроены: www.google.com
[✓ PASS] Конфигурация Reality protocol TLS 1.3 валидна
```

### Итоговый Отчёт

В конце тестов выводится сводка:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ИТОГОВЫЙ ОТЧЁТ ПО ТЕСТАМ БЕЗОПАСНОСТИ ШИФРОВАНИЯ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Всего Тестов:      45
Пройдено:          42
Провалено:         1
Пропущено:         2

Предупреждения:    3
Критичных Проблем: 0

Проваленные Тесты:
  ✗ HTTP proxy port not listening: 8118

Проблемы Безопасности:
  ⚠ Certificate expires within 24 hours or is already expired

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
РЕЗУЛЬТАТ: ПРОЙДЕНО С ПРЕДУПРЕЖДЕНИЯМИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Решение Типичных Проблем

### 1. "tcpdump: command not found"

**Решение:**
```bash
sudo apt-get install tcpdump
```

Или запустите с опцией `--skip-pcap`:
```bash
sudo ./test_encryption_security.sh --skip-pcap
```

### 2. "VLESS containers are not running"

**Решение:**
```bash
cd /opt/vless
sudo docker compose up -d
sudo docker compose ps  # Проверка статуса
```

### 3. "No users configured"

**Решение:**
```bash
sudo vless-user add testuser
```

### 4. "Certificate validation failed"

**Возможные причины:**
- Сертификат истёк
- Файлы сертификатов отсутствуют
- Неправильная конфигурация домена

**Решение:**
```bash
# Проверка срока действия сертификата
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -enddate

# Обновление сертификата
sudo certbot renew

# Перезапуск контейнеров
cd /opt/vless && sudo docker compose restart
```

### 5. "Permission denied"

**Решение:**
```bash
# Скрипт должен запускаться с правами root для перехвата пакетов
sudo ./test_encryption_security.sh

# Проверка прав доступа к файлу
ls -la test_encryption_security.sh
# Должен быть: -rwxr-xr-x (исполняемый)

# Исправление прав при необходимости
chmod +x test_encryption_security.sh
```

### 6. "Traffic encryption test failed - no packets captured"

**Возможные причины:**
- Брандмауэр блокирует трафик
- Нет активных соединений во время теста
- Проблемы с правами tcpdump

**Решение:**
```bash
# Проверка правил брандмауэра
sudo ufw status

# Проверка сетевых интерфейсов
ip link show

# Запуск с подробным выводом для диагностики
sudo ./test_encryption_security.sh --verbose
```

---

## Что Делать После Тестов

### ✅ Все Тесты Пройдены

**Ваше соединение безопасно!** Канал от клиента до интернета полностью зашифрован.

Рекомендации:
- Запускайте тесты периодически (раз в неделю/месяц)
- Мониторьте логи на предмет подозрительной активности
- Обновляйте сертификаты вовремя

### ⚠️ Есть Предупреждения (Warnings)

**Система работает, но есть рекомендации по улучшению.**

Типичные предупреждения:
- Сертификат скоро истекает → обновите certbot
- Слабые имена пользователей → создайте пользователей с более сложными именами
- Устаревшие версии TLS разрешены → обновите конфигурацию

### ❌ Тесты Провалены (Failed)

**Есть проблемы с конфигурацией, но не критичные.**

Проверьте:
1. Запущены ли все контейнеры (`docker compose ps`)
2. Правильно ли настроен Xray (`/opt/vless/config/xray_config.json`)
3. Доступны ли порты (`ss -tlnp | grep -E "443|1080|8118"`)

Обратитесь к разделу "Решение Типичных Проблем" выше.

### 🔥 Критические Проблемы (Critical)

**НЕМЕДЛЕННО ТРЕБУЕТСЯ ДЕЙСТВИЕ! Данные могут быть незащищены.**

Критические проблемы включают:
- Незашифрованный трафик (plaintext обнаружен)
- Слабые шифры (RC4, DES)
- Приватный ключ доступен для чтения всем
- Отсутствует аутентификация на прокси

**Действия:**
1. **Немедленно остановите сервис:** `cd /opt/vless && sudo docker compose down`
2. **Изучите детали ошибки в выводе теста**
3. **Исправьте конфигурацию**
4. **Запустите тесты снова для проверки**
5. **Только после успешного прохождения запускайте сервис**

---

## Дополнительная Проверка Вручную

### Проверка Сертификатов

```bash
# Информация о сертификате
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -text

# Срок действия
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -enddate

# Проверка цепочки
sudo openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
  /etc/letsencrypt/live/yourdomain.com/fullchain.pem
```

### Тестирование TLS Соединения

```bash
# Проверка TLS 1.3 на stunnel SOCKS5 порту
openssl s_client -connect yourdomain.com:1080 -tls1_3

# Проверка TLS 1.3 на stunnel HTTP порту
openssl s_client -connect yourdomain.com:8118 -tls1_3

# Проверка шифров
nmap --script ssl-enum-ciphers -p 8118 yourdomain.com
```

### Перехват и Анализ Трафика

```bash
# Перехват трафика (запустить в отдельном терминале)
sudo tcpdump -i any -w /tmp/vless_test.pcap 'tcp and port 443'

# В другом терминале: сделать запрос через прокси
curl --socks5 user:pass@127.0.0.1:1080 https://ifconfig.me

# Остановить tcpdump (Ctrl+C)

# Анализ пакетов
tshark -r /tmp/vless_test.pcap -Y "tls.handshake.type"

# Поиск незашифрованных данных (должно быть пусто)
strings /tmp/vless_test.pcap | grep -i "password"
```

### Проверка Логов

```bash
# Логи Xray (Reality + прокси)
sudo docker logs vless_xray --tail 100

# Логи stunnel (если публичный прокси)
sudo docker logs vless_stunnel --tail 100

# Системные логи fail2ban (если настроен)
sudo journalctl -u fail2ban | grep "vless-proxy" | tail -20
```

---

## Рекомендации по Безопасности

### 1. Регулярное Тестирование

Запускайте тесты:
- **После установки** (проверка конфигурации)
- **После изменений** (валидация изменений)
- **Еженедельно/Ежемесячно** (мониторинг)
- **После обновлений системы** (совместимость)

### 2. Управление Сертификатами

```bash
# Проверка сертификатов
sudo certbot certificates

# Автоматическое обновление (должно быть настроено по умолчанию)
sudo systemctl status certbot.timer

# Тестовое обновление
sudo certbot renew --dry-run
```

### 3. Ротация Паролей

Периодически меняйте пароли прокси:

```bash
# Сброс пароля пользователя
sudo vless-user reset-proxy-password <username>

# Проверка длины нового пароля (должно быть 32+ символов)
sudo jq -r '.users[] | select(.username == "<username>") | .proxy_password | length' \
  /opt/vless/config/users.json
```

### 4. Мониторинг

```bash
# Мониторинг логов в реальном времени
sudo docker logs -f vless_xray

# Поиск неудачных попыток подключения
sudo docker logs vless_xray | grep -i "rejected"

# Статус fail2ban
sudo fail2ban-client status vless-proxy
```

### 5. Обновление Reality Destination

Периодически меняйте цель маскировки Reality для избежания паттернов:

```bash
# Редактирование конфигурации
sudo vi /opt/vless/config/xray_config.json

# Измените поля:
# - "dest": "google.com:443" → "microsoft.com:443"
# - "serverNames": ["www.google.com"] → ["www.microsoft.com"]

# Перезапуск Xray
cd /opt/vless && sudo docker compose restart xray
```

### 6. Резервное Копирование

```bash
# Создание резервной копии конфигурации
sudo tar -czf vless_backup_$(date +%Y%m%d).tar.gz /opt/vless/config/

# Храните резервные копии в безопасном месте (зашифрованными)
```

---

## Расширенное Тестирование (Опционально)

### Внешнее Сканирование

С другой машины (не сервера):

```bash
# Сканирование портов
nmap -sV -p 443,1080,8118 your-server-ip

# Детальное сканирование SSL/TLS (если установлен testssl.sh)
testssl.sh --full your-server-ip:8118
```

### Симуляция DPI

Проверка, выглядит ли трафик как настоящий HTTPS:

```bash
# Сравнение TLS fingerprint
openssl s_client -connect your-server-ip:443 -showcerts | openssl x509 -noout -fingerprint
openssl s_client -connect google.com:443 -showcerts | openssl x509 -noout -fingerprint

# Трафик должен быть неотличим от настоящего google.com
```

---

## Интерпретация Результатов

### Успешное Шифрование

**Признаки защищённого канала:**
- ✅ Все тесты Reality protocol пройдены
- ✅ TLS 1.3 используется везде
- ✅ Нет plaintext в перехваченном трафике
- ✅ Сертификаты валидны
- ✅ Нет слабых шифров
- ✅ Аутентификация на прокси обязательна

### Проблемы с Шифрованием

**Индикаторы проблем:**
- ❌ Reality keys не настроены
- ❌ Plaintext обнаружен в трафике
- ❌ Слабые cipher suites (RC4, DES, 3DES)
- ❌ Устаревшие TLS версии (SSLv3, TLS 1.0)
- ❌ Сертификаты истекли
- ❌ Нет аутентификации на прокси

### Канал Безопасен, Когда:

1. **Reality Protocol**
   - X25519 ключи сгенерированы и применены
   - Destination поддерживает TLS 1.3
   - SNI настроен правильно
   - Трафик выглядит как HTTPS к destination

2. **stunnel (Публичный Прокси)**
   - TLS 1.3 активен
   - Валидные Let's Encrypt сертификаты
   - Нет слабых шифров
   - Perfect Forward Secrecy работает

3. **Прокси Безопасность**
   - Пароли 32+ символов
   - Аутентификация обязательна
   - UDP отключён (если не требуется)
   - Порты правильно биндятся (localhost или через stunnel)

4. **Нет Утечек**
   - Конфигурационные файлы защищены (600/700 права)
   - Нет sensitive данных в логах
   - DNS настроен в Xray

---

## Контакты и Поддержка

### Документация

- **Полное руководство:** `/home/ikeniborn/Documents/Project/vless/docs/SECURITY_TESTING.md` (English)
- **Инструкция установки:** `/opt/vless/docs/INSTALL.md`
- **Архитектура проекта:** `/opt/vless/docs/CLAUDE.md`

### Логи

- **Xray:** `sudo docker logs vless_xray`
- **stunnel:** `sudo docker logs vless_stunnel`
- **Nginx:** `sudo docker logs vless_nginx`
- **Системные:** `/opt/vless/logs/`

### Получение Помощи

Если тесты показывают ошибки, которые вы не можете решить:

1. Соберите информацию:
   ```bash
   # Версия системы
   lsb_release -a

   # Версия Docker
   docker --version

   # Статус контейнеров
   cd /opt/vless && docker compose ps

   # Логи последних ошибок
   sudo docker logs vless_xray --tail 50 > /tmp/xray_logs.txt
   ```

2. Проверьте документацию в `/opt/vless/docs/`
3. Изучите раздел "Решение Типичных Проблем"
4. Обратитесь к разработчикам с детальным описанием проблемы

---

**Версия:** 1.0
**Дата:** 2025-10-07
**Автор:** Claude Code Agent
**Лицензия:** MIT

# PLAN_FIX.md - План устранения проблем VLESS Security Tests

**Date:** 2025-10-08
**Server:** 11154.example.us
**Version:** v4.1
**Status:** DRAFT - Requires Review

---

## Executive Summary

**Статус:** 🔥 КРИТИЧНЫЕ ПРОБЛЕМЫ обнаружены при тестировании безопасности
**Тяжесть:** HIGH - Система частично неработоспособна + критичные уязвимости безопасности
**Приоритет:** P0 - Немедленное исправление требуется

**Основные проблемы:**
1. 🔥 **CRITICAL:** Права доступа к сертификатам 777 (должно быть 600) - уязвимость безопасности
2. ❌ **BLOCKER:** Отсутствие конфигурационных файлов `/opt/vless/config/config.json`, `users.json`
3. ❌ **BLOCKER:** Отсутствие пользователей в системе - невозможно использовать VPN
4. ⚠️ **HIGH:** Reality destination не настроен - VPN не работает

**Результат тестов:** 17/21 PASSED, 3 FAILED, 1 SKIPPED, 1 CRITICAL ISSUE

---

## Table of Contents

1. [Анализ логов тестирования](#1-анализ-логов-тестирования)
2. [Root Cause Analysis](#2-root-cause-analysis)
3. [План исправления](#3-план-исправления)
4. [Последовательность действий](#4-последовательность-действий)
5. [Проверка результатов](#5-проверка-результатов)
6. [Превентивные меры](#6-превентивные-меры)

---

## 1. Анализ логов тестирования

### 1.1 Тесты PASSED (17)

✅ **Инфраструктура:**
- stunnel container работает
- stunnel certificate configuration valid
- TLS certificates существуют и валидны до Jan 4 2026
- stunnel SOCKS5/HTTP порты слушают (1080/8118)

✅ **Безопасность:**
- No weak ciphers detected
- SSLv2/v3 disabled
- TLS 1.0 disabled
- No exposed configuration files
- No default/weak usernames
- No data leaks in container logs

**Вывод:** Базовая инфраструктура (stunnel, сертификаты, Docker) работает корректно.

---

### 1.2 Тесты FAILED (3)

❌ **TEST 1: Reality Protocol TLS 1.3 Configuration**
```
[✗ FAIL] Xray config not found: /opt/vless/config/config.json
```

**Детали:**
- Файл конфигурации Xray отсутствует
- Reality protocol не может быть проверен
- VPN функциональность недоступна

---

❌ **TEST 3: Traffic Encryption Validation**
```
[✗ FAIL] No test user available
```

**Детали:**
- `/opt/vless/config/users.json` отсутствует или пуст
- Невозможно создать тестовое подключение
- Шифрование трафика не может быть проверено

---

❌ **TEST 5: DPI Resistance Validation**
```
[✗ FAIL] Reality destination not configured
```

**Детали:**
- Reality destination (google.com, microsoft.com и т.д.) не настроен
- DPI resistance не работает
- VPN может быть обнаружен Deep Packet Inspection системами

---

### 1.3 Security Issues (CRITICAL)

🔥 **CRITICAL SECURITY ISSUE:**
```
[🔥 CRITICAL] Private key file permissions insecure: 777 (MUST be 600)
```

**Детали:**
- Приватный ключ сертификата доступен для чтения всем пользователям
- Путь: `/etc/letsencrypt/live/${DOMAIN}/privkey.pem`
- Текущие права: 777 (rwxrwxrwx)
- Требуемые права: 600 (rw-------)

**Риски:**
- Любой пользователь системы может прочитать приватный ключ
- Возможна компрометация TLS шифрования
- Нарушение требований PRD (Section 10: NFR-SEC-001)
- Нарушение требований CLAUDE.md (Section 9: Critical Requirements - File Permissions)

**Уровень угрозы:** CRITICAL - немедленное исправление требуется

---

⚠️ **WARNING:**
```
[⚠ WARN] Certificate file permissions: 777 (should be 644 or 600)
```

**Детали:**
- Публичный сертификат также имеет избыточные права
- Путь: `/etc/letsencrypt/live/${DOMAIN}/fullchain.pem`
- Текущие права: 777
- Требуемые права: 644 или 600

---

⚠️ **WARNING:**
```
[⚠ WARN] No DNS configuration in Xray (may use system DNS - potential leak)
```

**Детали:**
- Xray может использовать системный DNS вместо внутреннего
- Потенциальная утечка DNS запросов
- Снижение приватности VPN

---

### 1.4 Tests SKIPPED (1)

⊘ **TEST 7: Proxy Protocol Security Validation**
```
[⊘ SKIP] Proxy support not enabled
```

**Причина:** Proxy support проверяется только если ENABLE_PROXY=true в конфигурации.

---

## 2. Root Cause Analysis

### 2.1 Проблема: Отсутствие конфигурационных файлов

**Файлы отсутствуют:**
- `/opt/vless/config/config.json` (Xray configuration)
- `/opt/vless/config/users.json` (User database)

**Возможные причины:**

#### Гипотеза 1: Установка не завершена
- Скрипт `install.sh` был прерван до создания конфигурации
- Ошибка в `lib/orchestrator.sh` на этапе `create_xray_config()` или `create_initial_user()`
- Недостаточно прав доступа при создании файлов

**Проверка:**
```bash
# На удаленном сервере
ls -la /opt/vless/
ls -la /opt/vless/config/
docker ps -a | grep vless
```

**Ожидаемый результат если установка не завершена:**
- Директория `/opt/vless/` существует, но частично пустая
- Файлы `docker-compose.yml`, `.env` могут отсутствовать
- Docker контейнеры не запущены или в состоянии "Exited"

---

#### Гипотеза 2: Файлы были удалены после установки
- Ручное удаление администратором
- Скрипт обновления/миграции удалил старую конфигурацию, но не создал новую
- Проблема с правами доступа - файлы созданы, но недоступны

**Проверка:**
```bash
# Проверить логи установки
sudo journalctl -u docker | grep vless
# Проверить существование backup
ls -la /tmp/vless_backup_*
ls -la /opt/vless/data/backups/
```

---

#### Гипотеза 3: Конфигурация создана в другой директории
- Переменная `INSTALL_ROOT` указывает на другую директорию
- Проблема с путями в `.env` файле

**Проверка:**
```bash
# Поиск config.json в системе
sudo find /opt -name "config.json" -type f 2>/dev/null
sudo find /etc -name "xray_config.json" -type f 2>/dev/null
```

---

### 2.2 Проблема: Права доступа к сертификатам 777

**Файлы с неправильными правами:**
- `/etc/letsencrypt/live/${DOMAIN}/privkey.pem` - 777 (должно быть 600)
- `/etc/letsencrypt/live/${DOMAIN}/fullchain.pem` - 777 (должно быть 644)

**Возможные причины:**

#### Гипотеза 1: Certbot создал файлы с дефолтными правами, затем права изменились
- Certbot обычно создает файлы с правами 600/644 автоматически
- Кто-то вручную изменил права (`chmod 777`)
- Скрипт установки изменил права неправильной командой

**Проверка:**
```bash
# Проверить владельца и группу файлов
ls -la /etc/letsencrypt/live/${DOMAIN}/
# Проверить логи certbot
sudo cat /var/log/letsencrypt/letsencrypt.log | grep -i permission
```

**Ожидаемый результат (корректная установка certbot):**
```
lrwxrwxrwx 1 root root   fullchain.pem -> ../../archive/${DOMAIN}/fullchain1.pem
lrwxrwxrwx 1 root root   privkey.pem -> ../../archive/${DOMAIN}/privkey1.pem
```

**Проверить файлы в archive:**
```bash
ls -la /etc/letsencrypt/archive/${DOMAIN}/
# Ожидаем:
# -rw-r--r-- fullchain1.pem (644)
# -rw------- privkey1.pem (600)
```

---

#### Гипотеза 2: Установка certbot через lib/certbot_setup.sh с ошибкой
- Скрипт `lib/certbot_setup.sh` (если существует) изменяет права некорректно
- Команда `chmod -R 777 /etc/letsencrypt` была выполнена ошибочно

**Проверка:**
```bash
# Проверить существование модуля certbot_setup.sh
ls -la /opt/vless/lib/certbot_setup.sh
# Проверить скрипты в исходном коде
grep -r "chmod 777" /home/ikeniborn/Documents/Project/vless/lib/
grep -r "letsencrypt" /home/ikeniborn/Documents/Project/vless/lib/ | grep chmod
```

---

#### Гипотеза 3: Docker volume mount с неправильными правами
- Docker контейнер stunnel монтирует `/etc/letsencrypt` как volume
- При монтировании права могли быть изменены
- Проблема с umask в Docker

**Проверка:**
```bash
# Проверить docker-compose.yml
cat /opt/vless/docker-compose.yml | grep -A 5 letsencrypt
# Проверить права в контейнере
docker exec vless_stunnel ls -la /certs/live/
```

---

### 2.3 Проблема: CLI команда "vless security" vs прямой запуск скрипта

**Наблюдение из логов:**

1. Пользователь сначала запустил: `sudo vless security`
   - Команда сработала (вывод показывает запуск тестов)
   - Но обнаружила отсутствие `users.json`
   - Показала рекомендации по установке

2. Пользователь затем запустил: `/opt/vless/lib/security_tests.sh --dev-mode`
   - Сработала ошибка "This script must be run as root"
   - После `sudo` - режим разработки активирован
   - Но проблема с отсутствием конфигурации осталась

**Вывод:** CLI команды работают корректно, проблема в отсутствии конфигурационных файлов.

---

### 2.4 Проблема: Reality destination не настроен

**Причина:** `config.json` отсутствует, следовательно Reality destination не может быть настроен.

**Зависимость:** Исправляется автоматически после создания `config.json` с валидной конфигурацией Reality.

---

## 3. План исправления

### 3.1 Стратегия

**Подход:** Диагностика → Исправление → Валидация

**Приоритеты:**
1. **P0 (CRITICAL):** Исправить права доступа к сертификатам (безопасность)
2. **P0 (BLOCKER):** Определить состояние установки
3. **P1 (HIGH):** Восстановить или создать конфигурационные файлы
4. **P2 (MEDIUM):** Создать пользователей и проверить функциональность

---

### 3.2 Фазы исправления

#### PHASE 1: Диагностика (30 минут)

**Цель:** Определить текущее состояние системы и root cause проблем.

**Действия:**

1. **Проверить состояние Docker контейнеров**
   ```bash
   docker ps -a | grep vless
   docker logs vless_xray --tail 100
   docker logs vless_stunnel --tail 100
   ```

   **Ожидаемые сценарии:**
   - ✅ Контейнеры запущены: Конфигурация существует, но недоступна
   - ⚠️ Контейнеры в Exited: Ошибка в конфигурации
   - ❌ Контейнеры отсутствуют: Установка не завершена

2. **Проверить файловую структуру /opt/vless**
   ```bash
   ls -la /opt/vless/
   ls -la /opt/vless/config/
   ls -la /opt/vless/data/
   find /opt/vless -type f -name "*.json" 2>/dev/null
   ```

3. **Проверить права доступа к сертификатам**
   ```bash
   # Найти домен
   ls /etc/letsencrypt/live/

   # Проверить права (замените ${DOMAIN})
   ls -la /etc/letsencrypt/live/${DOMAIN}/
   ls -la /etc/letsencrypt/archive/${DOMAIN}/

   # Проверить symlinks
   readlink /etc/letsencrypt/live/${DOMAIN}/privkey.pem
   ```

4. **Проверить .env файл**
   ```bash
   cat /opt/vless/.env 2>/dev/null || echo ".env not found"
   ```

5. **Проверить логи установки**
   ```bash
   # Поиск логов установки
   find /var/log -name "*vless*" -o -name "*install*" 2>/dev/null
   journalctl -xe | grep -i vless | tail -50
   ```

**Deliverable:** Документ с результатами диагностики (состояние установки, найденные файлы, логи).

---

#### PHASE 2: Исправление прав доступа к сертификатам (CRITICAL - 10 минут)

**Цель:** Устранить критичную уязвимость безопасности.

**Действия:**

1. **Определить домен**
   ```bash
   DOMAIN=$(ls /etc/letsencrypt/live/ | grep -v README)
   echo "Domain: $DOMAIN"
   ```

2. **Исправить права доступа к archive файлам**
   ```bash
   # Приватный ключ - только root read/write
   sudo chmod 600 /etc/letsencrypt/archive/${DOMAIN}/privkey*.pem

   # Публичные сертификаты - root read/write, другие read
   sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/fullchain*.pem
   sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/cert*.pem
   sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/chain*.pem
   ```

3. **Проверить symlinks (права symlink не важны, важны права целевого файла)**
   ```bash
   ls -la /etc/letsencrypt/live/${DOMAIN}/
   ```

4. **Исправить права на директории**
   ```bash
   # Директории /etc/letsencrypt
   sudo chmod 755 /etc/letsencrypt
   sudo chmod 700 /etc/letsencrypt/live
   sudo chmod 700 /etc/letsencrypt/archive
   ```

5. **Перезапустить stunnel для применения изменений**
   ```bash
   docker-compose -f /opt/vless/docker-compose.yml restart stunnel
   ```

6. **Проверить результат**
   ```bash
   ls -la /etc/letsencrypt/archive/${DOMAIN}/ | grep privkey
   # Ожидаем: -rw------- (600)

   ls -la /etc/letsencrypt/archive/${DOMAIN}/ | grep fullchain
   # Ожидаем: -rw-r--r-- (644)
   ```

**Acceptance Criteria:**
- ✅ `privkey*.pem` имеют права 600
- ✅ `fullchain*.pem`, `cert*.pem`, `chain*.pem` имеют права 644
- ✅ stunnel контейнер перезапущен без ошибок
- ✅ `docker logs vless_stunnel` не показывает ошибок доступа к сертификатам

---

#### PHASE 3: Восстановление конфигурационных файлов (1-2 часа)

**Сценарий A: Конфигурация существует, но недоступна**

**Условие:** Файлы найдены командой `find /opt -name "config.json"`

**Действия:**
1. Скопировать файлы в правильную директорию
2. Установить правильные права доступа
3. Обновить `.env` если необходимо
4. Перезапустить контейнеры

---

**Сценарий B: Конфигурация отсутствует, но backup существует**

**Условие:** Найден backup в `/opt/vless/data/backups/` или `/tmp/vless_backup_*/`

**Действия:**
1. Восстановить конфигурацию из backup
   ```bash
   # Найти последний backup
   BACKUP_DIR=$(ls -td /opt/vless/data/backups/* 2>/dev/null | head -1)

   # Восстановить config.json
   sudo cp "${BACKUP_DIR}/config/config.json" /opt/vless/config/
   sudo cp "${BACKUP_DIR}/config/users.json" /opt/vless/config/

   # Установить права
   sudo chmod 600 /opt/vless/config/config.json
   sudo chmod 600 /opt/vless/config/users.json
   ```

2. Перезапустить контейнеры
   ```bash
   docker-compose -f /opt/vless/docker-compose.yml restart
   ```

---

**Сценарий C: Конфигурация отсутствует, backup не найден - ПЕРЕУСТАНОВКА**

**Условие:** Ни конфигурация, ни backup не найдены.

**Действия:**

**Вариант C.1: Partial Reinstall (рекомендуется)**

1. **Создать backup существующих данных**
   ```bash
   BACKUP_DIR="/tmp/vless_partial_backup_$(date +%Y%m%d_%H%M%S)"
   sudo mkdir -p "${BACKUP_DIR}"

   # Backup всего что есть
   sudo cp -r /opt/vless "${BACKUP_DIR}/" 2>/dev/null || true
   sudo cp -r /etc/letsencrypt "${BACKUP_DIR}/" 2>/dev/null || true
   ```

2. **Запустить установку в режиме восстановления**

   Из локальной директории проекта:
   ```bash
   cd /home/ikeniborn/Documents/Project/vless

   # Если есть опция --repair в install.sh
   sudo bash install.sh --repair

   # Или стандартная установка с сохранением сертификатов
   sudo bash install.sh
   ```

   **При установке:**
   - Использовать тот же домен (чтобы не запрашивать новые сертификаты)
   - Использовать существующие Let's Encrypt сертификаты
   - Создать нового админ пользователя

3. **Проверить результат**
   ```bash
   ls -la /opt/vless/config/
   # Ожидаем: config.json, users.json, reality_keys.json

   docker ps | grep vless
   # Ожидаем: vless_xray, vless_stunnel, vless_nginx - все running
   ```

---

**Вариант C.2: Full Reinstall (если partial не работает)**

1. **Полный backup**
   ```bash
   BACKUP_DIR="/tmp/vless_full_backup_$(date +%Y%m%d_%H%M%S)"
   sudo mkdir -p "${BACKUP_DIR}"
   sudo cp -r /opt/vless "${BACKUP_DIR}/" 2>/dev/null || true
   sudo cp -r /etc/letsencrypt "${BACKUP_DIR}/" 2>/dev/null || true
   ```

2. **Полное удаление**
   ```bash
   sudo bash /opt/vless/scripts/vless-uninstall
   # ИЛИ вручную:
   docker-compose -f /opt/vless/docker-compose.yml down -v
   sudo rm -rf /opt/vless
   ```

3. **Чистая установка**
   ```bash
   cd /home/ikeniborn/Documents/Project/vless
   sudo bash install.sh
   ```

4. **Восстановить сертификаты (если были удалены)**
   ```bash
   sudo cp -r "${BACKUP_DIR}/letsencrypt" /etc/
   sudo chmod 600 /etc/letsencrypt/archive/*/privkey*.pem
   sudo chmod 644 /etc/letsencrypt/archive/*/fullchain*.pem
   ```

---

#### PHASE 4: Создание пользователей (30 минут)

**Цель:** Создать тестовых и продакшн пользователей.

**Действия:**

1. **Проверить существующих пользователей**
   ```bash
   sudo cat /opt/vless/config/users.json | jq .
   ```

2. **Создать тестового пользователя для security tests**
   ```bash
   sudo vless add-user testuser
   ```

   **Ожидаемый вывод:**
   - UUID сгенерирован
   - Proxy password создан (32 chars)
   - 8 конфигурационных файлов созданы (3 VLESS + 5 proxy)
   - QR код показан

3. **Создать продакшн пользователей (если необходимо)**
   ```bash
   sudo vless add-user admin
   sudo vless add-user user1
   # и т.д.
   ```

4. **Проверить пользователей**
   ```bash
   sudo vless list-users
   ```

**Acceptance Criteria:**
- ✅ Минимум 1 пользователь создан (testuser)
- ✅ `users.json` содержит валидные данные пользователей
- ✅ Конфигурационные файлы созданы в `/opt/vless/data/clients/testuser/`
- ✅ `sudo vless show-user testuser` показывает корректные данные

---

#### PHASE 5: Валидация и тестирование (30 минут)

**Цель:** Убедиться, что все проблемы устранены.

**Действия:**

1. **Запустить security tests снова**
   ```bash
   sudo vless security
   ```

   **Ожидаемый результат:**
   - ✅ TEST 1: Reality Protocol TLS 1.3 Configuration - PASS
   - ✅ TEST 2: stunnel TLS Termination Configuration - PASS
   - ✅ TEST 3: Traffic Encryption Validation - PASS (с testuser)
   - ✅ TEST 4: Certificate Security Validation - PASS (права 600/644)
   - ✅ TEST 5: DPI Resistance Validation - PASS
   - ✅ TEST 6: SSL/TLS Vulnerability Scanning - PASS
   - ⊘ TEST 7: Proxy Protocol Security - SKIP или PASS (если proxy включен)
   - ✅ TEST 8: Data Leak Detection - PASS

2. **Проверить работу VPN**
   ```bash
   # Проверить что контейнеры запущены
   docker ps | grep vless

   # Проверить логи на ошибки
   docker logs vless_xray --tail 50
   docker logs vless_stunnel --tail 50

   # Проверить порты
   sudo ss -tulnp | grep -E '443|1080|8118'
   ```

3. **Проверить UFW правила**
   ```bash
   sudo ufw status numbered
   ```

   **Ожидаемый результат:**
   - Порт 443/tcp открыт (VLESS)
   - Порт 1080/tcp открыт (SOCKS5) - если proxy enabled
   - Порт 8118/tcp открыт (HTTP) - если proxy enabled

4. **Тестовое подключение (опционально)**

   Если есть клиент v2rayN/v2rayNG:
   - Импортировать конфиг из `/opt/vless/data/clients/testuser/vless_config.json`
   - Подключиться к VPN
   - Проверить IP: https://ifconfig.me
   - Должен показать IP сервера, а не клиента

5. **Документировать результаты**
   - Создать отчет о проделанной работе
   - Обновить changelog
   - Зафиксировать изменения в git (если применимо)

**Acceptance Criteria:**
- ✅ Все critical security tests PASSED
- ✅ Минимум 20/21 тестов PASSED (1 может быть SKIP если proxy не включен)
- ✅ 0 CRITICAL ISSUES
- ✅ Docker контейнеры running и healthy
- ✅ VPN подключение работает (если протестировано)

---

## 4. Последовательность действий

### 4.1 Пошаговый чеклист для удаленного сервера

**Подготовка (5 минут):**
```bash
# 1. Подключиться к серверу
ssh root@11154.example.us

# 2. Перейти в директорию установки
cd /opt/vless

# 3. Создать рабочую директорию для диагностики
mkdir -p /tmp/vless_diagnostics_$(date +%Y%m%d_%H%M%S)
cd /tmp/vless_diagnostics_*
```

---

**PHASE 1: Диагностика (30 минут)**

```bash
# Шаг 1.1: Проверить Docker
echo "=== Docker Status ===" > diagnostics.log
docker ps -a | grep vless >> diagnostics.log
echo "" >> diagnostics.log

echo "=== Xray Logs ===" >> diagnostics.log
docker logs vless_xray --tail 100 >> diagnostics.log 2>&1
echo "" >> diagnostics.log

echo "=== stunnel Logs ===" >> diagnostics.log
docker logs vless_stunnel --tail 100 >> diagnostics.log 2>&1
echo "" >> diagnostics.log

# Шаг 1.2: Проверить файловую структуру
echo "=== File Structure ===" >> diagnostics.log
ls -laR /opt/vless/ >> diagnostics.log 2>&1
echo "" >> diagnostics.log

# Шаг 1.3: Проверить сертификаты
echo "=== Certificates ===" >> diagnostics.log
DOMAIN=$(ls /etc/letsencrypt/live/ | grep -v README | head -1)
echo "Domain: $DOMAIN" >> diagnostics.log
ls -la /etc/letsencrypt/live/${DOMAIN}/ >> diagnostics.log 2>&1
ls -la /etc/letsencrypt/archive/${DOMAIN}/ >> diagnostics.log 2>&1
echo "" >> diagnostics.log

# Шаг 1.4: Проверить .env
echo "=== Environment File ===" >> diagnostics.log
cat /opt/vless/.env >> diagnostics.log 2>&1 || echo ".env not found" >> diagnostics.log
echo "" >> diagnostics.log

# Шаг 1.5: Поиск конфигурационных файлов
echo "=== Config Files Search ===" >> diagnostics.log
find /opt -name "config.json" -type f 2>/dev/null >> diagnostics.log
find /opt -name "users.json" -type f 2>/dev/null >> diagnostics.log
echo "" >> diagnostics.log

# Шаг 1.6: Просмотреть результаты
cat diagnostics.log | less
```

**Решение на основе диагностики:**
- Если Docker контейнеры running + файлы найдены → Проблема с правами доступа
- Если Docker контейнеры Exited → Проблема с конфигурацией
- Если Docker контейнеры отсутствуют → Установка не завершена

---

**PHASE 2: Исправление сертификатов (10 минут)**

```bash
# Определить домен
DOMAIN=$(ls /etc/letsencrypt/live/ | grep -v README | head -1)
echo "Fixing permissions for domain: $DOMAIN"

# Исправить права на archive
sudo chmod 600 /etc/letsencrypt/archive/${DOMAIN}/privkey*.pem
sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/fullchain*.pem
sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/cert*.pem
sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/chain*.pem

# Исправить права на директории
sudo chmod 755 /etc/letsencrypt
sudo chmod 700 /etc/letsencrypt/live
sudo chmod 700 /etc/letsencrypt/archive

# Перезапустить stunnel
docker-compose -f /opt/vless/docker-compose.yml restart stunnel

# Проверить
echo "=== Certificate Permissions Fixed ===" >> diagnostics.log
ls -la /etc/letsencrypt/archive/${DOMAIN}/ >> diagnostics.log
docker logs vless_stunnel --tail 20 >> diagnostics.log
```

---

**PHASE 3: Восстановление конфигурации**

**Если найден backup:**
```bash
# Найти последний backup
BACKUP_DIR=$(ls -td /opt/vless/data/backups/* /tmp/vless_backup_* 2>/dev/null | head -1)
echo "Found backup: $BACKUP_DIR"

# Восстановить конфигурацию
sudo cp "${BACKUP_DIR}/config/config.json" /opt/vless/config/ 2>/dev/null
sudo cp "${BACKUP_DIR}/config/users.json" /opt/vless/config/ 2>/dev/null

# Установить права
sudo chmod 600 /opt/vless/config/config.json
sudo chmod 600 /opt/vless/config/users.json

# Перезапустить
docker-compose -f /opt/vless/docker-compose.yml restart
```

**Если backup не найден - переустановка:**
```bash
# Создать backup существующего
BACKUP_DIR="/tmp/vless_full_backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "${BACKUP_DIR}"
sudo cp -r /opt/vless "${BACKUP_DIR}/" 2>/dev/null || true
sudo cp -r /etc/letsencrypt "${BACKUP_DIR}/" 2>/dev/null || true

# Скопировать установочный скрипт с локальной машины на сервер
# (выполнить на локальной машине)
scp -r /home/ikeniborn/Documents/Project/vless root@11154.example.us:/tmp/

# Запустить установку на сервере
cd /tmp/vless
sudo bash install.sh

# Во время установки:
# - Использовать существующий домен
# - Не запрашивать новые сертификаты (использовать существующие)
# - Создать нового пользователя
```

---

**PHASE 4: Создание пользователей (30 минут)**

```bash
# Создать тестового пользователя
sudo vless add-user testuser

# Проверить
sudo vless list-users
sudo vless show-user testuser

# Создать продакшн пользователей (если необходимо)
sudo vless add-user admin
# и т.д.
```

---

**PHASE 5: Финальная валидация (30 минут)**

```bash
# Запустить security tests
sudo vless security > /tmp/security_test_results.log 2>&1

# Просмотреть результаты
cat /tmp/security_test_results.log | less

# Проверить Docker
docker ps | grep vless

# Проверить порты
sudo ss -tulnp | grep -E '443|1080|8118'

# Проверить UFW
sudo ufw status numbered

# Финальный отчет
echo "=== Final Validation ===" >> diagnostics.log
cat /tmp/security_test_results.log >> diagnostics.log
docker ps | grep vless >> diagnostics.log
sudo ss -tulnp | grep -E '443|1080|8118' >> diagnostics.log

# Скопировать отчет на локальную машину (выполнить на локальной машине)
scp root@11154.example.us:/tmp/vless_diagnostics_*/diagnostics.log ~/
```

---

## 5. Проверка результатов

### 5.1 Acceptance Criteria для каждой фазы

**PHASE 1: Диагностика**
- [ ] Состояние Docker контейнеров определено
- [ ] Файловая структура проверена
- [ ] Права доступа к сертификатам зафиксированы
- [ ] Backup найден или отсутствие подтверждено
- [ ] Логи собраны в diagnostics.log

**PHASE 2: Исправление сертификатов**
- [ ] `privkey*.pem` имеют права 600
- [ ] `fullchain*.pem` имеют права 644
- [ ] stunnel перезапущен без ошибок
- [ ] `docker logs vless_stunnel` не показывает ошибок доступа

**PHASE 3: Восстановление конфигурации**
- [ ] `/opt/vless/config/config.json` существует с правами 600
- [ ] `/opt/vless/config/users.json` существует с правами 600
- [ ] Docker контейнеры запущены (vless_xray, vless_stunnel, vless_nginx)
- [ ] `docker logs vless_xray` не показывает ошибок конфигурации

**PHASE 4: Создание пользователей**
- [ ] Минимум 1 пользователь создан (testuser)
- [ ] `users.json` содержит валидные UUID и пароли
- [ ] 8 конфигурационных файлов созданы для каждого пользователя
- [ ] `sudo vless list-users` показывает всех пользователей

**PHASE 5: Финальная валидация**
- [ ] Security tests: ≥20/21 PASSED
- [ ] Security tests: 0 CRITICAL ISSUES
- [ ] Docker контейнеры: все running
- [ ] Порты 443, 1080, 8118 слушают
- [ ] UFW правила корректны

---

### 5.2 Критерии успеха всего плана

**Функциональные требования:**
- ✅ VLESS VPN полностью работоспособен
- ✅ Минимум 1 пользователь может подключиться
- ✅ Reality protocol настроен корректно
- ✅ DPI resistance работает
- ✅ Proxy сервисы (SOCKS5/HTTP) доступны (если включены)

**Безопасность:**
- ✅ Приватный ключ сертификата имеет права 600
- ✅ Публичные сертификаты имеют права 644
- ✅ Все конфигурационные файлы имеют права 600
- ✅ 0 критичных уязвимостей
- ✅ Security tests проходят без critical issues

**Эксплуатация:**
- ✅ Docker контейнеры автоматически перезапускаются (restart: unless-stopped)
- ✅ CLI команды работают корректно
- ✅ Логи доступны и не содержат ошибок
- ✅ Backup создан перед изменениями

---

## 6. Превентивные меры

### 6.1 Предотвращение повторения проблем

**Проблема 1: Неправильные права доступа к сертификатам**

**Превентивные меры:**

1. **Добавить проверку прав доступа в install.sh**

   В файл `install.sh` после установки certbot:
   ```bash
   # Установить корректные права на сертификаты
   if [[ -d "/etc/letsencrypt/archive/${DOMAIN}" ]]; then
       chmod 600 /etc/letsencrypt/archive/${DOMAIN}/privkey*.pem
       chmod 644 /etc/letsencrypt/archive/${DOMAIN}/fullchain*.pem
       chmod 644 /etc/letsencrypt/archive/${DOMAIN}/cert*.pem
       chmod 644 /etc/letsencrypt/archive/${DOMAIN}/chain*.pem
   fi
   ```

2. **Добавить валидацию прав в security_tests.sh**

   Уже реализовано в TEST 4, но можно улучшить:
   ```bash
   # Проверить что права установлены корректно
   if [[ $(stat -c "%a" "$PRIVKEY_FILE") != "600" ]]; then
       print_critical "Private key permissions: $(stat -c "%a" "$PRIVKEY_FILE") (auto-fixing to 600)"
       chmod 600 "$PRIVKEY_FILE"
   fi
   ```

3. **Добавить cron job для периодической проверки**

   Создать `/etc/cron.daily/vless-cert-permissions`:
   ```bash
   #!/bin/bash
   # Check and fix certificate permissions daily

   for domain in /etc/letsencrypt/archive/*/; do
       chmod 600 "${domain}"/privkey*.pem
       chmod 644 "${domain}"/fullchain*.pem
       chmod 644 "${domain}"/cert*.pem
       chmod 644 "${domain}"/chain*.pem
   done
   ```

---

**Проблема 2: Отсутствие конфигурационных файлов**

**Превентивные меры:**

1. **Улучшить проверку успешности установки**

   В файл `install.sh` добавить финальную валидацию:
   ```bash
   # Final validation
   validate_installation() {
       local errors=0

       # Check config files
       [[ ! -f "/opt/vless/config/config.json" ]] && ((errors++)) && echo "ERROR: config.json missing"
       [[ ! -f "/opt/vless/config/users.json" ]] && ((errors++)) && echo "ERROR: users.json missing"

       # Check containers
       docker ps | grep -q vless_xray || ((errors++)) && echo "ERROR: vless_xray not running"
       docker ps | grep -q vless_stunnel || ((errors++)) && echo "ERROR: vless_stunnel not running"

       # Check user creation
       USER_COUNT=$(jq '.users | length' /opt/vless/config/users.json 2>/dev/null || echo 0)
       [[ $USER_COUNT -eq 0 ]] && ((errors++)) && echo "ERROR: No users created"

       if [[ $errors -gt 0 ]]; then
           echo "⚠️  Installation completed with $errors errors"
           return 1
       else
           echo "✅ Installation validated successfully"
           return 0
       fi
   }

   # Call at end of install.sh
   validate_installation || {
       echo "Installation validation failed. Please check logs."
       exit 1
   }
   ```

2. **Автоматический backup конфигурации при изменениях**

   В CLI команды (vless-user, vless-config, etc.) добавить:
   ```bash
   # Backup before changes
   backup_config() {
       local backup_dir="/opt/vless/data/backups/auto_$(date +%Y%m%d_%H%M%S)"
       mkdir -p "$backup_dir/config"
       cp /opt/vless/config/*.json "$backup_dir/config/" 2>/dev/null || true
   }

   # Call before any config modification
   backup_config
   ```

3. **Добавить health check endpoint**

   Создать скрипт `/opt/vless/scripts/health-check.sh`:
   ```bash
   #!/bin/bash
   # Health check для мониторинга

   errors=0

   # Check config files
   [[ ! -f "/opt/vless/config/config.json" ]] && ((errors++))
   [[ ! -f "/opt/vless/config/users.json" ]] && ((errors++))

   # Check containers
   docker ps | grep -q vless_xray || ((errors++))
   docker ps | grep -q vless_stunnel || ((errors++))

   # Exit code: 0 = healthy, 1 = unhealthy
   exit $errors
   ```

   Добавить в cron:
   ```bash
   # /etc/cron.d/vless-health-check
   */5 * * * * root /opt/vless/scripts/health-check.sh || echo "VLESS health check failed" | mail -s "VLESS Alert" admin@example.com
   ```

---

**Проблема 3: CLI команды не находят конфигурационные файлы**

**Превентивные меры:**

1. **Добавить проверку существования конфигурации в CLI**

   В начало каждой CLI команды:
   ```bash
   # Check installation
   if [[ ! -d "/opt/vless" ]]; then
       echo "ERROR: VLESS not installed. Run: sudo bash install.sh"
       exit 1
   fi

   if [[ ! -f "/opt/vless/config/config.json" ]]; then
       echo "ERROR: Configuration missing. Installation may be incomplete."
       echo "Try: sudo bash install.sh --repair"
       exit 1
   fi
   ```

2. **Добавить --repair режим в install.sh**

   ```bash
   # In install.sh
   if [[ "$1" == "--repair" ]]; then
       echo "Running in repair mode..."

       # Preserve existing data
       backup_existing_installation

       # Regenerate only missing configs
       [[ ! -f "/opt/vless/config/config.json" ]] && create_xray_config
       [[ ! -f "/opt/vless/config/users.json" ]] && create_users_file

       # Restart containers
       docker-compose -f /opt/vless/docker-compose.yml restart

       echo "Repair completed"
       exit 0
   fi
   ```

---

### 6.2 Документация для администраторов

**Создать файл `/opt/vless/docs/TROUBLESHOOTING.md`:**

```markdown
# VLESS Reality VPN - Troubleshooting Guide

## Common Issues

### Issue 1: Configuration files missing

**Symptoms:**
- `sudo vless security` fails with "No users.json found"
- Docker containers not starting

**Diagnosis:**
```bash
ls -la /opt/vless/config/
```

**Solution:**
```bash
# Option 1: Restore from backup
sudo vless restore

# Option 2: Repair installation
cd /path/to/vless/source
sudo bash install.sh --repair

# Option 3: Full reinstall
sudo vless uninstall
sudo bash install.sh
```

---

### Issue 2: Certificate permission errors

**Symptoms:**
- `sudo vless security` shows "Private key file permissions insecure: 777"

**Solution:**
```bash
# Fix automatically
sudo /opt/vless/scripts/fix-cert-permissions.sh

# Or manually
DOMAIN=$(ls /etc/letsencrypt/live/ | grep -v README | head -1)
sudo chmod 600 /etc/letsencrypt/archive/${DOMAIN}/privkey*.pem
sudo chmod 644 /etc/letsencrypt/archive/${DOMAIN}/fullchain*.pem
docker-compose -f /opt/vless/docker-compose.yml restart stunnel
```

[... добавить другие распространенные проблемы ...]
```

---

### 6.3 Monitoring и Alerting

**Рекомендуемые инструменты:**

1. **Uptime monitoring:**
   - UptimeRobot (бесплатный)
   - Healthchecks.io
   - Проверка порта 443 каждые 5 минут

2. **Certificate expiry monitoring:**
   - Let's Encrypt автоматически отправляет email за 30/14/7 дней
   - Дополнительно: `certbot renew --dry-run` в cron

3. **Docker container monitoring:**
   - `docker stats` для мониторинга ресурсов
   - Watchtower для автоматических обновлений образов
   - Portainer для web-интерфейса управления

4. **Log aggregation:**
   - Централизованные логи в ELK stack или Graylog
   - Или простой rotation: `logrotate` для `/opt/vless/logs/`

---

## 7. Резюме

### 7.1 Краткий обзор проблем

| # | Проблема | Severity | Root Cause | Решение |
|---|----------|----------|------------|---------|
| 1 | Права доступа к сертификатам 777 | 🔥 CRITICAL | Неправильная установка или ручное изменение | chmod 600/644 + перезапуск stunnel |
| 2 | config.json отсутствует | ❌ BLOCKER | Неполная установка | Восстановление из backup или переустановка |
| 3 | users.json отсутствует | ❌ BLOCKER | Неполная установка | Восстановление из backup или переустановка |
| 4 | Reality destination не настроен | ⚠️ HIGH | Следствие отсутствия config.json | Исправляется при восстановлении config |
| 5 | Нет пользователей | ⚠️ MEDIUM | Следствие отсутствия users.json | vless add-user после восстановления |

---

### 7.2 Ожидаемое время исправления

| Phase | Estimated Time | Risk Level |
|-------|----------------|------------|
| PHASE 1: Диагностика | 30 минут | LOW |
| PHASE 2: Исправление сертификатов | 10 минут | LOW |
| PHASE 3: Восстановление конфигурации | 1-2 часа | MEDIUM |
| PHASE 4: Создание пользователей | 30 минут | LOW |
| PHASE 5: Финальная валидация | 30 минут | LOW |
| **TOTAL** | **3-4 часа** | **MEDIUM** |

**Risk Level пояснение:**
- LOW: Стандартные операции, минимальный риск
- MEDIUM: Может потребоваться переустановка, риск потери данных (если нет backup)
- HIGH: Критичные изменения, требуют тщательной проверки

---

### 7.3 Следующие шаги

**Immediate Actions (в течение 24 часов):**
1. ✅ Выполнить PHASE 1: Диагностика
2. ✅ Выполнить PHASE 2: Исправление сертификатов (CRITICAL)
3. ✅ Определить стратегию для PHASE 3 (backup или переустановка)

**Short-term (в течение недели):**
4. ✅ Выполнить PHASE 3-5: Восстановление и валидация
5. ✅ Создать превентивные меры (cron jobs, health checks)
6. ✅ Обновить документацию (TROUBLESHOOTING.md)

**Long-term (в течение месяца):**
7. ✅ Настроить мониторинг и alerting
8. ✅ Провести полное security audit
9. ✅ Обновить install.sh с улучшениями (validation, --repair mode)
10. ✅ Обучить команду использованию и troubleshooting

---

### 7.4 Контакты и поддержка

**Для вопросов по исправлению:**
- GitHub Issues: https://github.com/anthropics/vless/issues (если проект публичный)
- Документация: `/opt/vless/docs/`
- Логи: `/opt/vless/logs/`

**В случае критичных проблем:**
1. Создать backup: `sudo vless backup`
2. Собрать диагностическую информацию (см. PHASE 1)
3. Создать GitHub issue с логами
4. Не удалять backup до решения проблемы!

---

**END OF PLAN_FIX.md**

**Version:** 1.0
**Last Updated:** 2025-10-08
**Author:** Claude Code Analysis
**Status:** ✅ READY FOR REVIEW

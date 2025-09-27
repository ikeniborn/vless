# Руководство администратора VLESS+Reality VPN

## Содержание

1. [Введение](#введение)
2. [Управление пользователями](#управление-пользователями)
3. [Мониторинг и логи](#мониторинг-и-логи)
4. [Резервное копирование и восстановление](#резервное-копирование-и-восстановление)
5. [Обновление системы](#обновление-системы)
6. [Управление сервисом](#управление-сервисом)
7. [Автоматизация задач](#автоматизация-задач)
8. [Безопасность и лучшие практики](#безопасность-и-лучшие-практики)

## Введение

VLESS+Reality VPN - это защищенный VPN сервис на базе протокола VLESS с расширением REALITY для обхода DPI и блокировок. Система развернута в Docker и управляется через CLI интерфейс.

### Архитектура системы

- **Xray-core**: Основной VPN движок в Docker контейнере
- **REALITY**: Протокол маскировки трафика под обычный HTTPS
- **Рабочая директория**: `/opt/vless/` - содержит все файлы системы
- **Управление**: Bash скрипты с интерактивным меню

### Быстрые команды

После установки доступны следующие команды:

```bash
vless-users   # Управление пользователями
vless-logs    # Просмотр логов
vless-backup  # Создание резервной копии
vless-update  # Обновление Xray
```

## Управление пользователями

### Добавление нового пользователя

1. Запустите менеджер пользователей:
```bash
vless-users
```

2. Выберите опцию "1) Add new user"

3. Введите имя пользователя (только латиница, цифры и дефис)

4. Система автоматически:
   - Сгенерирует UUID для пользователя
   - Создаст уникальный Short ID
   - Обновит конфигурацию Xray
   - Перезапустит сервис
   - Создаст QR-код для подключения

5. Получите данные для подключения:
   - vless:// ссылка для быстрого импорта
   - QR-код в `/opt/vless/data/qr_codes/[username].png`

### Удаление пользователя

1. Запустите менеджер:
```bash
vless-users
```

2. Выберите "2) Remove user"

3. Выберите пользователя из списка

4. Подтвердите удаление

### Просмотр списка пользователей

```bash
vless-users
# Выберите "3) List users"
```

Или напрямую:
```bash
jq '.users[] | {name, uuid, short_id, created_at}' /opt/vless/data/users.json
```

### Экспорт конфигурации пользователя

1. Через менеджер:
```bash
vless-users
# Выберите "4) Show user config"
```

2. Выберите пользователя и формат экспорта:
   - vless:// ссылка
   - QR-код в терминале
   - Путь к сохраненному QR-коду

### Массовое добавление пользователей

Для добавления нескольких пользователей создайте скрипт:

```bash
#!/bin/bash
users=("user1" "user2" "user3")

for user in "${users[@]}"; do
    echo "Adding user: $user"
    cd /opt/vless/scripts
    ./user-manager.sh add "$user"
    sleep 2
done
```

## Мониторинг и логи

### Просмотр логов в реальном времени

```bash
vless-logs
# Выберите "1) View live logs"
```

Или напрямую:
```bash
docker-compose -f /opt/vless/docker-compose.yml logs -f --tail 50
```

### Просмотр логов за период

```bash
vless-logs
# Выберите "2) View last N lines"
# Введите количество строк
```

### Фильтрация логов по уровню

```bash
# Только ошибки
docker logs xray-server 2>&1 | grep -i error

# Предупреждения
docker logs xray-server 2>&1 | grep -i warning
```

### Анализ подключений

```bash
# Активные подключения
docker logs xray-server 2>&1 | grep "accepted"

# Статистика по пользователям
docker logs xray-server 2>&1 | grep "email:" | awk '{print $NF}' | sort | uniq -c
```

### Мониторинг ресурсов

```bash
# Использование ресурсов контейнером
docker stats xray-server

# Сетевая статистика
netstat -tuln | grep :443
```

### Экспорт логов

```bash
vless-logs
# Выберите "4) Export logs"
```

Логи сохраняются в `/opt/vless/logs/export/`

## Резервное копирование и восстановление

### Создание резервной копии

#### Автоматическое резервирование

```bash
vless-backup
```

Создает полную резервную копию в `/opt/vless/backups/[timestamp]/`

#### Ручное резервирование

```bash
# Полная резервная копия
cd /opt/vless
tar -czf vless-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
    config/ data/ .env docker-compose.yml

# Только критические данные
tar -czf vless-minimal-$(date +%Y%m%d).tar.gz \
    config/config.json data/users.json data/keys/ .env
```

### Восстановление из резервной копии

1. Остановите сервис:
```bash
cd /opt/vless
docker-compose down
```

2. Восстановите файлы:
```bash
# Из автоматической копии
cd /opt/vless
tar -xzf backups/[timestamp]/backup.tar.gz

# Из ручной копии
tar -xzf /path/to/vless-backup-*.tar.gz -C /opt/vless/
```

3. Восстановите права доступа:
```bash
chmod 600 /opt/vless/config/config.json
chmod 600 /opt/vless/data/users.json
chmod 600 /opt/vless/data/keys/*
chmod 600 /opt/vless/.env
```

4. Запустите сервис:
```bash
docker-compose up -d
```

### Автоматическое резервирование через cron

Добавьте в crontab:
```bash
# Ежедневное резервирование в 3:00
0 3 * * * /usr/local/bin/vless-backup >> /var/log/vless-backup.log 2>&1

# Еженедельное резервирование по воскресеньям
0 2 * * 0 /usr/local/bin/vless-backup weekly >> /var/log/vless-backup.log 2>&1
```

### Ротация резервных копий

Скрипт автоматически удаляет копии старше 30 дней. Для изменения периода хранения:

```bash
# Редактировать /opt/vless/scripts/backup.sh
# Изменить параметр RETENTION_DAYS
```

## Обновление системы

### Обновление Xray-core

```bash
vless-update
```

Скрипт автоматически:
1. Создает резервную копию
2. Загружает последнюю версию образа
3. Перезапускает контейнер
4. Проверяет работоспособность

### Ручное обновление

```bash
# Резервная копия
vless-backup

# Обновление образа
docker pull teddysun/xray:latest

# Перезапуск
cd /opt/vless
docker-compose down
docker-compose up -d

# Проверка
docker-compose logs --tail 20
```

### Обновление скриптов управления

```bash
cd /path/to/vless-repo
git pull

# Копирование обновленных скриптов
cp -r scripts/* /opt/vless/scripts/
chmod 750 /opt/vless/scripts/*.sh
```

## Управление сервисом

### Основные команды

```bash
# Статус сервиса
cd /opt/vless
docker-compose ps

# Остановка
docker-compose stop

# Запуск
docker-compose start

# Перезапуск
docker-compose restart

# Полная остановка с удалением контейнера
docker-compose down

# Запуск с пересозданием контейнера
docker-compose up -d --force-recreate
```

### Проверка состояния

```bash
# Проверка контейнера
docker ps -a | grep xray-server

# Проверка порта
netstat -tuln | grep :443

# Проверка конфигурации
docker exec xray-server xray test -c /etc/xray/config.json
```

### Аварийный перезапуск

При проблемах с сервисом:

```bash
#!/bin/bash
cd /opt/vless

# Остановка
docker-compose down

# Очистка
docker system prune -f

# Запуск
docker-compose up -d

# Проверка
sleep 5
docker-compose ps
docker-compose logs --tail 20
```

## Автоматизация задач

### Настройка cron задач

```bash
# Открыть crontab
crontab -e
```

Добавьте следующие задачи:

```bash
# Ежедневное резервирование в 3:00
0 3 * * * /usr/local/bin/vless-backup >> /var/log/vless-backup.log 2>&1

# Еженедельное обновление по воскресеньям в 4:00
0 4 * * 0 /usr/local/bin/vless-update >> /var/log/vless-update.log 2>&1

# Проверка состояния каждые 5 минут
*/5 * * * * /opt/vless/scripts/health-check.sh >> /var/log/vless-health.log 2>&1

# Ротация логов раз в неделю
0 0 * * 1 docker exec xray-server sh -c 'echo > /var/log/xray/access.log'
```

### Скрипт мониторинга состояния

Создайте `/opt/vless/scripts/health-check.sh`:

```bash
#!/bin/bash
source /opt/vless/scripts/lib/colors.sh
source /opt/vless/scripts/lib/utils.sh

VLESS_HOME="/opt/vless"
cd "$VLESS_HOME"

# Проверка статуса контейнера
if ! docker ps | grep -q "xray-server"; then
    echo "[$(date)] ERROR: Xray container is not running. Attempting restart..."
    docker-compose up -d
    sleep 10

    if docker ps | grep -q "xray-server"; then
        echo "[$(date)] SUCCESS: Xray container restarted"
    else
        echo "[$(date)] CRITICAL: Failed to restart Xray container"
        # Отправка уведомления (если настроено)
    fi
fi

# Проверка использования диска
disk_usage=$(df -h /opt/vless | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 80 ]; then
    echo "[$(date)] WARNING: Disk usage is ${disk_usage}%"
    # Очистка старых логов
    find /opt/vless/logs -name "*.log" -mtime +30 -delete
fi
```

### Уведомления о проблемах

Для отправки уведомлений можно использовать telegram-бота:

```bash
#!/bin/bash
# /opt/vless/scripts/notify.sh

BOT_TOKEN="your_bot_token"
CHAT_ID="your_chat_id"
MESSAGE="$1"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MESSAGE}"
```

## Безопасность и лучшие практики

### Права доступа к файлам

Регулярно проверяйте права доступа:

```bash
# Проверка критических файлов
ls -la /opt/vless/.env
ls -la /opt/vless/config/config.json
ls -la /opt/vless/data/users.json
ls -la /opt/vless/data/keys/

# Восстановление правильных прав
chmod 600 /opt/vless/.env
chmod 600 /opt/vless/config/config.json
chmod 600 /opt/vless/data/users.json
chmod 600 /opt/vless/data/keys/*
chmod 700 /opt/vless/data/keys
```

### Firewall настройки

```bash
# Разрешить только необходимые порты
ufw allow 22/tcp  # SSH
ufw allow 443/tcp # VLESS
ufw enable
```

### Ротация ключей

Рекомендуется периодически менять ключи REALITY:

```bash
# 1. Создать резервную копию
vless-backup

# 2. Сгенерировать новые ключи
docker run --rm teddysun/xray:latest xray x25519

# 3. Обновить конфигурацию
# Заменить в /opt/vless/config/config.json privateKey
# Обновить /opt/vless/data/keys/

# 4. Перезапустить сервис
cd /opt/vless && docker-compose restart

# 5. Обновить клиентские конфигурации
```

### Мониторинг безопасности

```bash
# Проверка необычной активности
docker logs xray-server 2>&1 | grep -i "rejected\|denied\|attack"

# Анализ подключений по странам (требует geoip)
docker logs xray-server 2>&1 | grep "from" | awk '{print $NF}' | sort | uniq -c | sort -rn

# Проверка на брутфорс попытки
docker logs xray-server 2>&1 | grep "failed" | tail -50
```

### Рекомендации по безопасности

1. **Регулярные обновления**
   - Обновляйте Xray-core минимум раз в месяц
   - Следите за security advisory на GitHub

2. **Ограничение доступа**
   - Используйте сложные Short ID (минимум 8 символов)
   - Не делитесь admin конфигурацией
   - Регулярно проверяйте список пользователей

3. **Мониторинг**
   - Настройте автоматические проверки состояния
   - Регулярно просматривайте логи
   - Следите за использованием ресурсов

4. **Резервирование**
   - Ежедневные автоматические бэкапы
   - Хранение копий на удаленном сервере
   - Регулярная проверка восстановления

5. **Сетевая безопасность**
   - Используйте fail2ban для защиты SSH
   - Ограничьте SSH доступ по ключам
   - Регулярно меняйте целевой домен REALITY

### Аудит системы

Регулярно выполняйте аудит:

```bash
#!/bin/bash
# /opt/vless/scripts/audit.sh

echo "=== VLESS System Audit ==="
echo "Date: $(date)"

echo -e "\n[File Permissions]"
ls -la /opt/vless/.env | awk '{print $1, $9}'
ls -la /opt/vless/config/config.json | awk '{print $1, $9}'
ls -la /opt/vless/data/users.json | awk '{print $1, $9}'

echo -e "\n[Active Users]"
jq '.users | length' /opt/vless/data/users.json

echo -e "\n[Container Status]"
docker ps -a | grep xray-server

echo -e "\n[Port Status]"
netstat -tuln | grep :443

echo -e "\n[Disk Usage]"
df -h /opt/vless

echo -e "\n[Recent Errors]"
docker logs xray-server 2>&1 | tail -20 | grep -i error || echo "No recent errors"

echo -e "\n[Last Backup]"
ls -lt /opt/vless/backups/ | head -2
```

## Дополнительные советы

### Оптимизация производительности

1. **Настройка лимитов Docker**:
```yaml
# В docker-compose.yml
services:
  xray-server:
    mem_limit: 512m
    cpus: '0.5'
```

2. **Оптимизация сети**:
```bash
# Увеличение буферов
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
```

### Отладка проблем

При проблемах с подключением:

1. Проверьте время сервера:
```bash
date
# Синхронизация при необходимости
timedatectl set-ntp true
```

2. Проверьте DNS:
```bash
nslookup speed.cloudflare.com
```

3. Тест конфигурации:
```bash
docker exec xray-server xray test -c /etc/xray/config.json
```

### Миграция на другой сервер

1. На старом сервере:
```bash
vless-backup
scp /opt/vless/backups/latest.tar.gz user@new-server:/tmp/
```

2. На новом сервере:
```bash
# Установка системы
curl -fsSL https://raw.githubusercontent.com/your-repo/vless/main/scripts/install.sh | bash

# Восстановление данных
cd /opt/vless
docker-compose down
tar -xzf /tmp/latest.tar.gz
docker-compose up -d
```

---

## Контакты и поддержка

При возникновении проблем:
1. Проверьте раздел [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Просмотрите логи системы
3. Создайте issue на GitHub с описанием проблемы

**Версия документа**: 1.0
**Последнее обновление**: 2025-09-27
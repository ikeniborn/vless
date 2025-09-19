# Руководство по устранению неполадок

> Комплексное руководство по диагностике и решению проблем в VLESS+Reality VPN системе.

## 📋 Содержание

1. [Общие принципы диагностики](#общие-принципы-диагностики)
2. [Проблемы установки](#проблемы-установки)
3. [Проблемы с VPN сервером](#проблемы-с-vpn-сервером)
4. [Проблемы с Telegram ботом](#проблемы-с-telegram-ботом)
5. [Проблемы подключения клиентов](#проблемы-подключения-клиентов)
6. [Проблемы производительности](#проблемы-производительности)
7. [Проблемы безопасности](#проблемы-безопасности)
8. [Аварийное восстановление](#аварийное-восстановление)
9. [FAQ](#faq)

## 🔍 Общие принципы диагностики

### Базовая проверка системы

Всегда начинайте диагностику с базовых проверок:

```bash
# 1. Проверка статуса главного сервиса
sudo systemctl status vless-vpn

# 2. Проверка Docker контейнеров
sudo docker ps -a

# 3. Проверка использования ресурсов
htop
df -h
free -h

# 4. Проверка сетевых портов
sudo netstat -tlnp | grep -E ":(80|443)"

# 5. Проверка логов
sudo journalctl -u vless-vpn -n 50
```

### Автоматическая диагностика

```bash
# Запуск комплексной диагностики
sudo ./tests/run_all_tests.sh

# Проверка состояния системы
sudo ./modules/monitoring.sh health

# Анализ логов на ошибки
sudo ./modules/maintenance_utils.sh analyze-logs
```

### Сбор информации для отчета

```bash
# Создание диагностического отчета
sudo ./modules/monitoring.sh system-info > diagnostic_report.txt

# Сбор логов для анализа
sudo tar -czf logs-$(date +%Y%m%d-%H%M).tar.gz /opt/vless/logs/ /var/log/syslog

# Информация о конфигурации
sudo cat /opt/vless/configs/config.json | jq '.' > xray_config.json
```

## 🛠️ Проблемы установки

### Ошибка: "Permission denied"

**Симптомы:**
```
bash: ./install.sh: Permission denied
```

**Решение:**
```bash
# Проверка прав доступа
ls -la install.sh

# Предоставление прав на выполнение
chmod +x install.sh

# Запуск с sudo
sudo bash install.sh
```

### Ошибка: "Docker not found"

**Симптомы:**
```
ERROR: Docker is not installed or not in PATH
```

**Решение:**
```bash
# Ручная установка Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER

# Перелогинивание или выполнение
newgrp docker

# Проверка установки
docker --version
docker-compose --version
```

### Ошибка: "Port already in use"

**Симптомы:**
```
Error: bind: address already in use
```

**Решение:**
```bash
# Проверка занятых портов
sudo netstat -tlnp | grep -E ":(80|443)"

# Остановка конфликтующих сервисов
sudo systemctl stop apache2 nginx

# Принудительное освобождение портов
sudo fuser -k 80/tcp
sudo fuser -k 443/tcp

# Перезапуск установки
sudo bash install.sh
```

### Ошибка: "Insufficient disk space"

**Симптомы:**
```
ERROR: No space left on device
```

**Решение:**
```bash
# Проверка свободного места
df -h

# Очистка временных файлов
sudo apt clean
sudo apt autoremove

# Очистка Docker
sudo docker system prune -a

# Очистка логов
sudo journalctl --vacuum-time=7d

# Проверка после очистки
df -h
```

### Проблемы с сетевой конфигурацией

**Симптомы:**
```
ERROR: Failed to resolve domain name
```

**Решение:**
```bash
# Проверка DNS
nslookup your-domain.com

# Проверка подключения к интернету
ping -c 4 8.8.8.8

# Проверка записей DNS
dig your-domain.com A

# Обновление /etc/hosts (временное решение)
echo "YOUR_SERVER_IP your-domain.com" | sudo tee -a /etc/hosts
```

## 🚧 Проблемы с VPN сервером

### Сервер не запускается

**Симптомы:**
```bash
sudo systemctl status vless-vpn
# Active: failed (Result: exit-code)
```

**Диагностика:**
```bash
# Подробные логи systemd
sudo journalctl -u vless-vpn -f

# Логи Docker
sudo docker-compose -f /opt/vless/docker-compose.yml logs

# Проверка конфигурации Xray
sudo docker run --rm -v /opt/vless/configs:/etc/xray teddysun/xray:latest xray -test -config /etc/xray/config.json
```

**Решения:**

1. **Проблема с конфигурацией:**
```bash
# Восстановление конфигурации из шаблона
sudo cp config/xray_config_template.json /opt/vless/configs/config.json

# Регенерация ключей
sudo ./modules/cert_management.sh regenerate

# Перезапуск сервиса
sudo systemctl restart vless-vpn
```

2. **Проблема с сертификатами:**
```bash
# Проверка сертификатов
sudo ls -la /opt/vless/certs/

# Регенерация сертификатов
sudo ./modules/cert_management.sh generate --force

# Обновление прав доступа
sudo chmod 600 /opt/vless/certs/*
```

### Xray контейнер завершается с ошибкой

**Симптомы:**
```bash
sudo docker ps
# xray-core контейнер отсутствует в списке
```

**Диагностика:**
```bash
# Логи контейнера
sudo docker logs xray-core

# Последние события Docker
sudo docker events --since 1h | grep xray-core
```

**Решения:**

1. **Ошибка в конфигурации JSON:**
```bash
# Проверка синтаксиса JSON
sudo cat /opt/vless/configs/config.json | jq '.'

# Восстановление из рабочего шаблона
sudo cp config/xray_config_template.json /opt/vless/configs/config.json

# Замена переменных в шаблоне
sudo sed -i "s/YOUR_DOMAIN/your-domain.com/g" /opt/vless/configs/config.json
```

2. **Проблемы с Reality конфигурацией:**
```bash
# Проверка доступности target сайта
curl -I https://microsoft.com

# Обновление Reality параметров
sudo ./modules/cert_management.sh update-reality

# Перезапуск с новой конфигурацией
sudo docker-compose -f /opt/vless/docker-compose.yml restart xray-core
```

### Высокое потребление ресурсов

**Симптомы:**
```bash
# CPU >90%, RAM >90%
htop
```

**Решения:**
```bash
# Оптимизация Xray конфигурации
sudo ./modules/maintenance_utils.sh optimize

# Настройка лимитов Docker
sudo echo "mem_limit: 512m" >> /opt/vless/docker-compose.yml

# Настройка TCP BBR
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 🤖 Проблемы с Telegram ботом

### Бот не отвечает на команды

**Симптомы:**
- Бот онлайн, но не отвечает на сообщения
- Команды игнорируются

**Диагностика:**
```bash
# Проверка статуса контейнера бота
sudo docker ps | grep telegram-bot

# Логи бота
sudo docker logs telegram-bot -f

# Проверка переменных окружения
sudo docker exec telegram-bot env | grep -E "(BOT_TOKEN|ADMIN_TELEGRAM_ID)"
```

**Решения:**

1. **Неверный токен бота:**
```bash
# Проверка токена через API
curl "https://api.telegram.org/bot$BOT_TOKEN/getMe"

# Обновление токена в конфигурации
sudo nano .env
# Обновите BOT_TOKEN

# Перезапуск бота
sudo docker-compose restart telegram-bot
```

2. **Неверный Admin ID:**
```bash
# Получение правильного ID через @userinfobot
# Обновление ID в конфигурации
sudo nano .env
# Обновите ADMIN_TELEGRAM_ID

# Перезапуск бота
sudo docker-compose restart telegram-bot
```

3. **Проблемы с сетью:**
```bash
# Проверка доступности Telegram API
sudo docker exec telegram-bot curl -I https://api.telegram.org

# Проверка DNS внутри контейнера
sudo docker exec telegram-bot nslookup api.telegram.org
```

### Бот падает при запуске

**Симптомы:**
```bash
sudo docker ps
# telegram-bot контейнер отсутствует
```

**Диагностика:**
```bash
# Логи при запуске
sudo docker-compose -f /opt/vless/docker-compose.yml logs telegram-bot

# Попытка ручного запуска
sudo docker run --rm -it --env-file .env python:3.11-slim python /app/bot.py
```

**Решения:**

1. **Отсутствуют зависимости:**
```bash
# Пересборка образа бота
sudo docker build -t vless-telegram-bot -f Dockerfile.bot .

# Обновление requirements.txt
sudo pip list --format=freeze > requirements.txt
```

2. **Ошибки в коде бота:**
```bash
# Проверка синтаксиса Python
sudo python3 -m py_compile modules/telegram_bot.py

# Запуск в debug режиме
sudo docker run --rm -it --env-file .env -e DEBUG=1 vless-telegram-bot
```

### Команды бота не работают

**Симптомы:**
- Бот отвечает, но команды выдают ошибки
- QR-коды не генерируются

**Диагностика:**
```bash
# Тестирование команды через Docker
sudo docker exec telegram-bot python -c "
import sys
sys.path.append('/app')
from modules.user_management import list_users
print(list_users())
"

# Проверка доступа к файлам
sudo docker exec telegram-bot ls -la /opt/vless/users/
```

**Решения:**

1. **Проблемы с правами доступа:**
```bash
# Исправление прав на volumes
sudo chown -R 1000:1000 /opt/vless/

# Обновление Docker Compose с правильными правами
sudo docker-compose -f /opt/vless/docker-compose.yml down
sudo docker-compose -f /opt/vless/docker-compose.yml up -d
```

2. **Отсутствуют библиотеки:**
```bash
# Проверка установленных пакетов
sudo docker exec telegram-bot pip list

# Переустановка зависимостей
sudo docker exec telegram-bot pip install -r /app/requirements.txt
```

## 📱 Проблемы подключения клиентов

### Клиент не может подключиться

**Симптомы:**
- Таймаут при подключении
- Ошибка "Connection failed"

**Диагностика:**
```bash
# Проверка доступности портов извне
telnet your-domain.com 443

# Проверка UFW правил
sudo ufw status verbose

# Проверка Reality конфигурации
sudo ./modules/monitoring.sh network
```

**Решения:**

1. **Проблемы с файрволлом:**
```bash
# Проверка и открытие портов
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Перезагрузка UFW
sudo ufw reload

# Проверка iptables
sudo iptables -L -n
```

2. **Проблемы с Reality маскировкой:**
```bash
# Тестирование fallback сайта
curl -I https://microsoft.com

# Обновление Reality target
sudo ./modules/cert_management.sh update-reality --target apple.com

# Проверка SNI маскировки
openssl s_client -connect your-domain.com:443 -servername www.microsoft.com
```

### Медленная скорость подключения

**Симптомы:**
- Низкая скорость загрузки/выгрузки
- Высокий пинг

**Диагностика:**
```bash
# Проверка загрузки сервера
htop

# Проверка сетевой статистики
sudo ./modules/monitoring.sh performance

# Тест скорости на сервере
wget -O /dev/null http://speedtest.wdc01.softlayer.com/downloads/test100.zip
```

**Решения:**

1. **Оптимизация TCP параметров:**
```bash
# Включение TCP BBR
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Оптимизация буферов
echo 'net.core.rmem_max = 268435456' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 268435456' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

2. **Оптимизация Xray:**
```bash
# Обновление конфигурации для производительности
sudo ./modules/maintenance_utils.sh tune-xray

# Использование более эффективного шифрования
# (автоматически применяется в конфигурации)
```

### Проблемы с определенными сайтами

**Симптомы:**
- Некоторые сайты не открываются
- DNS не резолвится

**Решения:**

1. **Настройка DNS:**
```bash
# Проверка DNS на клиенте
# В настройках VPN клиента установите DNS:
# 8.8.8.8, 1.1.1.1
```

2. **Обход блокировок:**
```bash
# Обновление routing rules в Xray
sudo ./modules/maintenance_utils.sh update-routing

# Добавление дополнительных доменов в bypass
sudo nano /opt/vless/configs/routing.json
```

## ⚡ Проблемы производительности

### Высокое потребление CPU

**Симптомы:**
```bash
htop
# CPU: 90%+ постоянно
```

**Решения:**
```bash
# Проверка процессов
sudo docker stats

# Оптимизация Xray конфигурации
sudo ./modules/maintenance_utils.sh optimize

# Ограничение ресурсов Docker
sudo docker update --cpus="1.5" xray-core
```

### Высокое потребление памяти

**Симптомы:**
```bash
free -h
# Memory usage >90%
```

**Решения:**
```bash
# Очистка кэша системы
sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# Ограничение памяти для контейнеров
sudo docker update --memory="512m" xray-core
sudo docker update --memory="256m" telegram-bot

# Настройка swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Проблемы с диском

**Симптомы:**
```bash
df -h
# Use% 95%+
```

**Решения:**
```bash
# Очистка логов
sudo journalctl --vacuum-time=7d
sudo find /opt/vless/logs/ -name "*.log" -mtime +7 -delete

# Очистка Docker
sudo docker system prune -a

# Очистка старых бэкапов
sudo find /opt/vless/backups/ -name "*.tar.gz" -mtime +30 -delete

# Настройка ротации логов
sudo ./modules/logging_setup.sh configure-rotation
```

## 🛡️ Проблемы безопасности

### Подозрительная активность

**Симптомы:**
- Множественные попытки подключения
- Неизвестные IP адреса в логах

**Диагностика:**
```bash
# Проверка fail2ban
sudo fail2ban-client status

# Анализ логов на атаки
sudo grep "Failed" /var/log/auth.log | tail -20

# Проверка активных подключений
sudo netstat -an | grep ESTABLISHED
```

**Решения:**
```bash
# Блокировка подозрительных IP
sudo ufw deny from SUSPICIOUS_IP

# Обновление правил fail2ban
sudo ./modules/security_hardening.sh update-fail2ban

# Включение более строгого логирования
sudo ./modules/logging_setup.sh enable-audit
```

### Компрометация сертификатов

**Симптомы:**
- Предупреждения о безопасности в клиентах
- Подозрительный трафик

**Решения:**
```bash
# Полная регенерация ключей
sudo ./modules/cert_management.sh regenerate --force

# Обновление всех пользователей
sudo ./modules/user_management.sh regenerate-all

# Уведомление пользователей через бота
sudo docker exec telegram-bot python -c "
import asyncio
from bot import send_security_alert
asyncio.run(send_security_alert('Security update required'))
"
```

## 🚨 Аварийное восстановление

### Полный отказ системы

**Симптомы:**
- Сервер не отвечает
- Все сервисы недоступны

**План восстановления:**

1. **Базовая диагностика:**
```bash
# Проверка доступности через SSH
ssh user@your-server-ip

# Проверка загрузки системы
sudo systemctl status

# Проверка места на диске
df -h

# Проверка памяти
free -h
```

2. **Восстановление сервисов:**
```bash
# Перезапуск Docker
sudo systemctl restart docker

# Восстановление из последнего бэкапа
sudo ./modules/backup_restore.sh restore latest

# Перезапуск VPN сервиса
sudo systemctl start vless-vpn
```

3. **Проверка целостности:**
```bash
# Запуск полного тестирования
sudo ./tests/run_all_tests.sh

# Проверка логов
sudo journalctl -u vless-vpn -n 100

# Тест подключения
curl -I http://your-domain.com
```

### Восстановление из резервной копии

```bash
# Список доступных бэкапов
sudo ./modules/backup_restore.sh list

# Восстановление конкретной копии
sudo ./modules/backup_restore.sh restore backup-20250919-120000.tar.gz

# Проверка восстановления
sudo ./tests/run_all_tests.sh quick
```

### Миграция на новый сервер

```bash
# На старом сервере - создание полного бэкапа
sudo ./modules/backup_restore.sh create --full

# Копирование бэкапа на новый сервер
scp vless-backup-*.tar.gz user@new-server:/tmp/

# На новом сервере - установка системы
sudo bash install.sh

# Восстановление данных
sudo ./modules/backup_restore.sh restore /tmp/vless-backup-*.tar.gz

# Обновление DNS записей на новый IP
```

## ❓ FAQ

### Часто задаваемые вопросы

**Q: Можно ли изменить порт VPN сервера?**
A: Да, отредактируйте `/opt/vless/configs/config.json` и обновите Docker Compose:
```bash
sudo nano /opt/vless/configs/config.json
# Измените "port": 443 на нужный порт
sudo docker-compose -f /opt/vless/docker-compose.yml restart
```

**Q: Как добавить второй домен?**
A: Обновите Reality конфигурацию:
```bash
sudo ./modules/cert_management.sh add-domain second-domain.com
sudo systemctl restart vless-vpn
```

**Q: Сколько пользователей может поддерживать сервер?**
A: Зависит от ресурсов сервера. Примерно:
- 1GB RAM: до 50 пользователей
- 2GB RAM: до 100 пользователей
- 4GB RAM: до 500 пользователей

**Q: Как обновить Xray до новой версии?**
A:
```bash
sudo docker-compose -f /opt/vless/docker-compose.yml pull
sudo docker-compose -f /opt/vless/docker-compose.yml up -d
```

**Q: Что делать если забыл Admin ID Telegram?**
A: Найдите свой ID через [@userinfobot](https://t.me/userinfobot) и обновите в `.env`:
```bash
sudo nano .env
sudo docker-compose restart telegram-bot
```

**Q: Как увеличить лимиты трафика?**
A: Лимиты задаются в Xray конфигурации или через команды бота:
```bash
/setlimit <uuid> <limit_in_gb>
```

**Q: Можно ли запускать несколько VPN серверов?**
A: Да, но каждый должен использовать разные порты и домены.

### Коды ошибок и их значения

| Код | Описание | Решение |
|-----|----------|---------|
| E001 | Docker не установлен | Установите Docker |
| E002 | Порт занят | Освободите порт 80/443 |
| E003 | Недостаточно прав | Запустите с sudo |
| E004 | Неверная конфигурация | Проверьте JSON синтаксис |
| E005 | Сетевая ошибка | Проверьте интернет |
| E006 | Нет места на диске | Очистите диск |
| E007 | Telegram API недоступен | Проверьте токен |
| E008 | Reality target недоступен | Смените target сайт |

### Контакты для поддержки

1. **Документация**: Изучите все файлы в папке `docs/`
2. **Логи**: Всегда прикладывайте логи к запросу о помощи
3. **Системная информация**: Используйте `sudo ./modules/monitoring.sh system-info`
4. **Тесты**: Запустите `sudo ./tests/run_all_tests.sh` перед обращением

---

**Следующий шаг**: [API Reference](api_reference.md)
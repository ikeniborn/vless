# Руководство по установке VLESS+Reality VPN

> Подробное руководство по установке и настройке VLESS+Reality VPN сервера с Telegram ботом.

## 📋 Содержание

1. [Предварительные требования](#предварительные-требования)
2. [Подготовка сервера](#подготовка-сервера)
3. [Автоматическая установка](#автоматическая-установка)
4. [Ручная установка](#ручная-установка)
5. [Настройка Telegram бота](#настройка-telegram-бота)
6. [Проверка установки](#проверка-установки)
7. [Первоначальная настройка](#первоначальная-настройка)
8. [Устранение неполадок](#устранение-неполадок)

## 🔧 Предварительные требования

### Системные требования

#### Минимальные требования
- **ОС**: Ubuntu 20.04+, Debian 11+, или CentOS 8+
- **CPU**: 1 ядро (рекомендуется 2+)
- **RAM**: 1GB (рекомендуется 2GB+)
- **Storage**: 5GB свободного места (рекомендуется SSD 20GB+)
- **Network**: Публичный IP адрес
- **Доступ**: Root привилегии

#### Рекомендуемые характеристики для продакшена
- **CPU**: 2+ ядра
- **RAM**: 4GB+
- **Storage**: SSD 20GB+
- **Network**: 100Mbps+ с неограниченным трафиком

### Проверка совместимости системы

```bash
# Проверка операционной системы
cat /etc/os-release

# Проверка доступной памяти
free -h

# Проверка свободного места на диске
df -h

# Проверка сетевых интерфейсов
ip addr show

# Проверка доступа к интернету
ping -c 4 google.com
```

### Подготовка учетных данных

Перед установкой подготовьте следующую информацию:

1. **Домен сервера** (например: `vpn.example.com`)
   - Домен должен указывать на IP адрес вашего сервера
   - Можно использовать поддомен или основной домен

2. **Telegram Bot Token**
   - Создайте бота через [@BotFather](https://t.me/BotFather)
   - Сохраните токен в формате: `1234567890:ABCDEFghijklmnopQRSTUVwxyz123456789`

3. **Telegram Admin ID**
   - Узнайте свой ID через [@userinfobot](https://t.me/userinfobot)
   - Запишите числовой ID (например: `123456789`)

## 🖥️ Подготовка сервера

### Обновление системы

```bash
# Обновление списка пакетов
sudo apt update

# Установка критических обновлений
sudo apt upgrade -y

# Установка базовых утилит
sudo apt install -y curl wget git nano htop unzip
```

### Настройка времени и локали

```bash
# Настройка временной зоны
sudo timedatectl set-timezone Europe/Moscow

# Синхронизация времени
sudo systemctl enable systemd-timesyncd
sudo systemctl start systemd-timesyncd

# Проверка времени
timedatectl status
```

### Настройка hostname (опционально)

```bash
# Установка имени хоста
sudo hostnamectl set-hostname vpn-server

# Обновление /etc/hosts
echo "127.0.1.1 vpn-server" | sudo tee -a /etc/hosts
```

## 🚀 Автоматическая установка

### Скачивание и запуск установщика

```bash
# Клонирование репозитория
git clone https://github.com/your-repo/vless-reality-vpn.git
cd vless-reality-vpn

# Проверка загруженных файлов
ls -la

# Запуск автоматической установки
sudo bash install.sh
```

### Интерактивная настройка

После запуска установщика вы увидите меню:

```
═══════════════════════════════════════════════════════════════
                    VLESS+Reality VPN Installer
═══════════════════════════════════════════════════════════════

Выберите действие:
1) Новая установка
2) Переустановка (сохранить пользователей)
3) Полное удаление
4) Создать резервную копию
5) Восстановить из резервной копии
6) Тестирование системы
7) Выход

Ваш выбор:
```

#### Выберите опцию "1" для новой установки

Система запросит следующую информацию:

1. **Домен сервера**:
   ```
   Введите домен вашего сервера (например: vpn.example.com):
   > your-domain.com
   ```

2. **Telegram Bot Token**:
   ```
   Введите токен Telegram бота:
   > 1234567890:ABCDEFghijklmnopQRSTUVwxyz123456789
   ```

3. **Admin Telegram ID**:
   ```
   Введите ваш Telegram ID:
   > 123456789
   ```

### Процесс автоматической установки

Установщик выполнит следующие этапы:

1. **Фаза 1: Подготовка инфраструктуры** (5-10 минут)
   ```
   ✅ Обновление системы
   ✅ Установка Docker и Docker Compose
   ✅ Настройка UFW файрволла
   ✅ Создание структуры каталогов
   ✅ Инициализация логирования
   ```

2. **Фаза 2: Установка VPN сервера** (3-5 минут)
   ```
   ✅ Генерация ключей и сертификатов
   ✅ Создание конфигурации Xray
   ✅ Настройка Docker Compose
   ✅ Запуск VPN сервера
   ```

3. **Фаза 3: Развертывание Telegram бота** (2-3 минуты)
   ```
   ✅ Создание Docker образа бота
   ✅ Настройка переменных окружения
   ✅ Запуск Telegram бота
   ✅ Проверка подключения к API
   ```

4. **Фаза 4: Финализация** (1-2 минуты)
   ```
   ✅ Настройка systemd сервиса
   ✅ Настройка автозапуска
   ✅ Создание первичной резервной копии
   ✅ Финальная проверка системы
   ```

### Результат установки

После успешной установки вы увидите:

```
═══════════════════════════════════════════════════════════════
                   УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!
═══════════════════════════════════════════════════════════════

🎯 Информация о системе:
   Домен сервера: your-domain.com
   VPN порты: 80 (HTTP), 443 (HTTPS)
   Статус сервера: ✅ Активен

🤖 Telegram бот:
   Статус: ✅ Подключен
   Первая команда: /start

📊 Управление системой:
   Статус: sudo systemctl status vless-vpn
   Логи: sudo journalctl -u vless-vpn -f
   Конфигурации: /opt/vless/

🔍 Следующие шаги:
   1. Отправьте /start вашему Telegram боту
   2. Создайте первого пользователя: /adduser test
   3. Получите конфигурацию: /getconfig <uuid>

═══════════════════════════════════════════════════════════════
```

## 🔧 Ручная установка

Если вы предпочитаете контролировать каждый этап установки:

### Фаза 1: Подготовка инфраструктуры

```bash
# Обновление системы
sudo ./modules/system_update.sh interactive

# Установка Docker
sudo ./modules/docker_setup.sh interactive

# Настройка файрволла
sudo ./modules/ufw_config.sh interactive

# Создание резервных копий
sudo ./modules/backup_restore.sh setup
```

### Фаза 2: Настройка VPN сервера

```bash
# Создание конфигурации Xray
sudo ./modules/cert_management.sh generate

# Настройка управления пользователями
sudo ./modules/user_management.sh setup

# Запуск Docker Compose
sudo docker-compose -f config/docker-compose.yml up -d
```

### Фаза 3: Развертывание Telegram бота

```bash
# Настройка переменных окружения
cp .env.example .env
nano .env  # Отредактируйте BOT_TOKEN и ADMIN_TELEGRAM_ID

# Запуск скрипта развертывания бота
sudo bash deploy_telegram_bot.sh
```

### Фаза 4: Финализация

```bash
# Настройка systemd сервиса
sudo cp config/vless-vpn.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable vless-vpn
sudo systemctl start vless-vpn

# Финальное тестирование
sudo ./tests/run_all_tests.sh
```

## 🤖 Настройка Telegram бота

### Создание Telegram бота

1. **Откройте [@BotFather](https://t.me/BotFather) в Telegram**

2. **Создайте нового бота**:
   ```
   /newbot
   ```

3. **Выберите имя бота**:
   ```
   My VPN Server Bot
   ```

4. **Выберите username бота**:
   ```
   myvpnserver_bot
   ```

5. **Сохраните токен**:
   ```
   Use this token to access the HTTP API:
   1234567890:ABCDEFghijklmnopQRSTUVwxyz123456789
   ```

### Получение Telegram ID

1. **Откройте [@userinfobot](https://t.me/userinfobot)**

2. **Отправьте любое сообщение**

3. **Сохраните ваш ID**:
   ```
   Your ID: 123456789
   ```

### Настройка переменных окружения

Создайте файл `.env` на основе `.env.example`:

```bash
# Скопируйте пример
cp .env.example .env

# Отредактируйте конфигурацию
nano .env
```

Содержимое файла `.env`:

```env
# Telegram Bot Configuration
BOT_TOKEN=1234567890:ABCDEFghijklmnopQRSTUVwxyz123456789
ADMIN_TELEGRAM_ID=123456789

# VPN Server Configuration
DOMAIN=your-domain.com
VLESS_PORT=443
HTTP_PORT=80

# Xray Configuration
REALITY_DEST=microsoft.com:443
REALITY_SNI=www.microsoft.com

# Paths
VLESS_CONFIG_DIR=/opt/vless/configs
VLESS_CERTS_DIR=/opt/vless/certs
VLESS_USERS_DIR=/opt/vless/users
VLESS_LOGS_DIR=/opt/vless/logs
VLESS_BACKUPS_DIR=/opt/vless/backups
```

## ✅ Проверка установки

### Проверка статуса сервисов

```bash
# Проверка systemd сервиса
sudo systemctl status vless-vpn

# Проверка Docker контейнеров
sudo docker-compose -f /opt/vless/docker-compose.yml ps

# Проверка портов
sudo netstat -tlnp | grep -E ":(80|443)"

# Проверка UFW
sudo ufw status verbose
```

### Проверка логов

```bash
# Логи systemd
sudo journalctl -u vless-vpn -f

# Логи Xray
sudo tail -f /opt/vless/logs/xray.log

# Логи Telegram бота
sudo docker logs telegram-bot -f

# Общие логи системы
sudo tail -f /opt/vless/logs/*.log
```

### Проверка Telegram бота

```bash
# Проверка статуса контейнера бота
sudo docker ps | grep telegram-bot

# Проверка подключения к Telegram API
sudo docker logs telegram-bot | grep "Bot started"

# Тест отправки сообщения
sudo docker exec telegram-bot python -c "
import asyncio
from telegram import Bot
bot = Bot('YOUR_BOT_TOKEN')
asyncio.run(bot.send_message(YOUR_ADMIN_ID, 'Test message'))
"
```

### Автоматическое тестирование

```bash
# Быстрая проверка системы
sudo ./tests/run_all_tests.sh quick

# Полное тестирование
sudo ./tests/run_all_tests.sh full

# Тестирование конкретных компонентов
sudo ./tests/test_installation.sh
sudo ./tests/test_telegram_bot.py
```

## 🎯 Первоначальная настройка

### Первый запуск Telegram бота

1. **Найдите вашего бота в Telegram** по username

2. **Отправьте команду `/start`**:
   ```
   🤖 Добро пожаловать в VPN Server Bot!

   Доступные команды:
   👥 Управление пользователями:
   /adduser <имя> - Создать пользователя
   /listusers - Список пользователей
   /deleteuser <uuid> - Удалить пользователя

   ⚙️ Управление сервером:
   /status - Статус сервера
   /restart - Перезапуск
   /logs - Просмотр логов
   ```

### Создание первого пользователя

```bash
# Через Telegram бота
/adduser test_user

# Или через командную строку
sudo ./modules/user_management.sh add "test_user"
```

### Получение конфигурации

После создания пользователя:

1. **Через Telegram**:
   ```
   /listusers  # Получить UUID пользователя
   /getconfig <uuid>  # Получить конфигурацию и QR-код
   ```

2. **Через командную строку**:
   ```bash
   # Список пользователей
   sudo ./modules/user_management.sh list

   # Получение конфигурации
   sudo ./modules/user_management.sh config <uuid>
   ```

### Настройка клиента

1. **Скачайте QR-код** отправленный ботом
2. **Установите VPN клиент** на устройство
3. **Отсканируйте QR-код** или импортируйте конфигурацию
4. **Протестируйте подключение**

## 🚨 Устранение неполадок

### Проблемы с установкой

#### Docker не устанавливается
```bash
# Ручная установка Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Проверка версии
docker --version
docker-compose --version
```

#### Порты заняты
```bash
# Проверка занятых портов
sudo netstat -tlnp | grep -E ":(80|443)"

# Остановка конфликтующих сервисов
sudo systemctl stop apache2 nginx

# Освобождение портов
sudo fuser -k 80/tcp
sudo fuser -k 443/tcp
```

#### Проблемы с правами доступа
```bash
# Проверка владельца файлов
sudo ls -la /opt/vless/

# Исправление прав
sudo chown -R root:root /opt/vless/
sudo chmod -R 755 /opt/vless/
sudo chmod 600 /opt/vless/certs/*
```

### Проблемы с Telegram ботом

#### Бот не отвечает
```bash
# Проверка токена
echo $BOT_TOKEN

# Проверка статуса контейнера
sudo docker ps | grep telegram-bot

# Перезапуск бота
sudo docker restart telegram-bot

# Проверка логов
sudo docker logs telegram-bot
```

#### Неверный Admin ID
```bash
# Получение правильного ID через @userinfobot
# Обновление конфигурации
sudo nano .env
sudo docker-compose restart telegram-bot
```

### Проблемы с подключением

#### VPN не подключается
```bash
# Проверка Xray сервера
sudo docker logs xray-core

# Проверка конфигурации
sudo cat /opt/vless/configs/config.json

# Проверка сертификатов
sudo ls -la /opt/vless/certs/

# Тест подключения
sudo ./modules/monitoring.sh network
```

#### Медленная скорость
```bash
# Проверка нагрузки системы
htop

# Проверка сетевой статистики
sudo ./modules/monitoring.sh performance

# Оптимизация конфигурации
sudo ./modules/maintenance_utils.sh optimize
```

### Логи для диагностики

```bash
# Сбор всех логов для анализа
sudo tar -czf vless-logs-$(date +%Y%m%d-%H%M).tar.gz \
  /opt/vless/logs/ \
  /var/log/syslog \
  /var/log/docker.log

# Отправка логов для анализа
# Архив можно отправить через Telegram бота командой /logs
```

## 📞 Получение помощи

Если проблема не решается:

1. **Изучите документацию**:
   - [User Guide](user_guide.md)
   - [Troubleshooting](troubleshooting.md)
   - [Security Guide](security_guide.md)

2. **Запустите диагностику**:
   ```bash
   sudo ./tests/run_all_tests.sh
   sudo ./modules/monitoring.sh system-info
   ```

3. **Соберите информацию о системе**:
   ```bash
   # Системная информация
   uname -a
   cat /etc/os-release
   df -h
   free -h

   # Состояние сервисов
   sudo systemctl status vless-vpn
   sudo docker ps -a
   ```

4. **Создайте issue** в репозитории с подробным описанием проблемы и логами.

---

**Следующий шаг**: [Руководство пользователя](user_guide.md)
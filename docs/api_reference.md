# API Reference - VLESS+Reality VPN

> Полный справочник по API, функциям и модулям системы VLESS+Reality VPN.

## 📋 Содержание

1. [Модули системы](#модули-системы)
2. [Telegram Bot API](#telegram-bot-api)
3. [Модуль управления пользователями](#модуль-управления-пользователями)
4. [Модуль управления сертификатами](#модуль-управления-сертификатами)
5. [Модуль мониторинга](#модуль-мониторинга)
6. [Модуль резервного копирования](#модуль-резервного-копирования)
7. [Модуль безопасности](#модуль-безопасности)
8. [Конфигурационные файлы](#конфигурационные-файлы)
9. [API эндпоинты](#api-эндпоинты)

## 🔧 Модули системы

### Структура модулей

```
modules/
├── common_utils.sh              # Общие утилиты
├── system_update.sh             # Обновление системы
├── docker_setup.sh              # Установка Docker
├── ufw_config.sh                # Настройка файрволла
├── backup_restore.sh            # Резервное копирование
├── user_management.sh           # Управление пользователями
├── cert_management.sh           # Управление сертификатами
├── telegram_bot.py              # Telegram бот
├── telegram_bot_manager.sh      # Менеджер бота
├── security_hardening.sh        # Усиление безопасности
├── logging_setup.sh             # Настройка логирования
├── monitoring.sh                # Мониторинг системы
├── maintenance_utils.sh         # Утилиты обслуживания
└── process_isolation/           # Изоляция процессов
    └── process_safe.sh
```

### Общие функции (common_utils.sh)

#### print_status()
Вывод статуса операции с цветовым кодированием.

```bash
print_status "message" "status"
```

**Параметры:**
- `message` - Текст сообщения
- `status` - Статус: `info`, `success`, `warning`, `error`

**Пример:**
```bash
print_status "Установка завершена" "success"
print_status "Внимание: порт занят" "warning"
```

#### log_message()
Запись сообщения в лог файл.

```bash
log_message "message" "level" "log_file"
```

**Параметры:**
- `message` - Текст для логирования
- `level` - Уровень: `INFO`, `WARNING`, `ERROR`, `DEBUG`
- `log_file` - Путь к лог файлу

#### safe_execute()
Безопасное выполнение команд с таймаутом.

```bash
safe_execute "command" timeout_seconds
```

**Возвращает:**
- `0` - Успешное выполнение
- `1` - Ошибка выполнения
- `124` - Таймаут

#### check_root()
Проверка прав root.

```bash
check_root
```

**Возвращает:**
- `0` - Пользователь имеет права root
- `1` - Недостаточно прав

#### check_system_requirements()
Проверка системных требований.

```bash
check_system_requirements
```

**Проверяет:**
- Операционную систему
- Доступную память
- Свободное место на диске
- Сетевое подключение

## 🤖 Telegram Bot API

### Основные команды

#### /start
Запуск бота и отображение меню.

```python
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Ответ:**
```json
{
  "message": "🤖 Добро пожаловать в VPN Server Bot!",
  "keyboard": ["👥 Пользователи", "⚙️ Сервер", "📊 Статистика"]
}
```

#### /adduser
Создание нового пользователя VPN.

```python
async def add_user_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Формат команды:**
```
/adduser <имя_пользователя> [limit:<лимит>] [expire:<срок>]
```

**Примеры:**
```
/adduser john_doe
/adduser alex limit:10GB
/adduser maria expire:30d
/adduser test limit:5GB expire:7d
```

**Ответ:**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "john_doe",
  "created": "2025-09-19T15:30:25Z",
  "status": "active",
  "config_ready": true
}
```

#### /deleteuser
Удаление пользователя.

```python
async def delete_user_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Формат команды:**
```
/deleteuser <uuid>
```

#### /listusers
Список всех пользователей.

```python
async def list_users_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Ответ:**
```json
{
  "users": [
    {
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "name": "john_doe",
      "created": "2025-09-19T15:30:25Z",
      "status": "active",
      "last_connection": "2025-09-19T18:45:12Z",
      "traffic_used": "2.5GB"
    }
  ],
  "total": 1
}
```

### Системные команды

#### /status
Статус сервера и сервисов.

```python
async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Ответ:**
```json
{
  "server": {
    "uptime": "15 days 8 hours",
    "cpu_usage": "12%",
    "memory_usage": "30%",
    "disk_usage": "42.5%"
  },
  "services": {
    "xray_core": "running",
    "telegram_bot": "running",
    "monitoring": "running"
  },
  "network": {
    "active_connections": 8,
    "total_traffic": "245GB"
  }
}
```

#### /restart
Перезапуск VPN сервера.

```python
async def restart_command(update: Update, context: ContextTypes.DEFAULT_TYPE)
```

**Параметры:** Нет

**Процесс:**
1. Остановка Xray контейнера
2. Перезапуск с новой конфигурацией
3. Проверка состояния
4. Отчет о результате

### Функции бота

#### generate_qr_code()
Генерация QR-кода для конфигурации.

```python
def generate_qr_code(vless_url: str) -> bytes
```

**Параметры:**
- `vless_url` - VLESS URL для генерации QR-кода

**Возвращает:** Байты PNG изображения

#### create_user_config()
Создание конфигурационного файла пользователя.

```python
def create_user_config(user_uuid: str, user_name: str) -> dict
```

**Возвращает:**
```json
{
  "vless_url": "vless://uuid@domain:443?type=tcp&security=reality...",
  "config_file": "/path/to/user_config.json",
  "qr_code": "/path/to/qr_code.png"
}
```

#### send_security_alert()
Отправка уведомлений безопасности.

```python
async def send_security_alert(message: str, alert_type: str = "warning")
```

## 👥 Модуль управления пользователями

### user_management.sh

#### add_user()
Добавление нового пользователя VPN.

```bash
add_user "username" [options]
```

**Опции:**
- `--limit <размер>` - Лимит трафика (например: 10GB)
- `--expire <время>` - Срок действия (например: 30d)
- `--no-config` - Не создавать конфигурацию автоматически

**Пример:**
```bash
./modules/user_management.sh add "john_doe" --limit 5GB --expire 30d
```

#### remove_user()
Удаление пользователя.

```bash
remove_user "user_uuid"
```

**Процесс:**
1. Проверка существования пользователя
2. Удаление из Xray конфигурации
3. Удаление файлов пользователя
4. Обновление конфигурации сервера

#### list_users()
Список всех пользователей.

```bash
list_users [format]
```

**Форматы:**
- `json` - JSON формат
- `table` - Табличный формат
- `csv` - CSV формат

**Пример вывода (JSON):**
```json
{
  "users": [
    {
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "name": "john_doe",
      "created": "2025-09-19 15:30:25",
      "status": "active",
      "traffic_limit": "5GB",
      "traffic_used": "1.2GB",
      "expires": "2025-10-19 15:30:25"
    }
  ]
}
```

#### get_user_config()
Получение конфигурации пользователя.

```bash
get_user_config "user_uuid" [format]
```

**Форматы:**
- `vless` - VLESS URL
- `json` - Конфигурационный файл JSON
- `qr` - Генерация QR-кода

#### get_user_stats()
Статистика использования пользователя.

```bash
get_user_stats "user_uuid"
```

**Возвращает:**
```json
{
  "upload_traffic": "856MB",
  "download_traffic": "1.2GB",
  "total_traffic": "2.056GB",
  "connection_count": 15,
  "last_connection": "2025-09-19 18:45:12",
  "online_time": "15h 23m"
}
```

## 🔒 Модуль управления сертификатами

### cert_management.sh

#### generate_certificates()
Генерация новых сертификатов и ключей.

```bash
generate_certificates [options]
```

**Опции:**
- `--force` - Принудительная перегенерация
- `--backup` - Создание резервной копии старых сертификатов
- `--domain <домен>` - Указание домена

#### generate_reality_keys()
Генерация ключей для Reality протокола.

```bash
generate_reality_keys
```

**Создает:**
- Приватный ключ Reality
- Публичный ключ Reality
- Short ID для маскировки

#### update_reality_config()
Обновление конфигурации Reality.

```bash
update_reality_config --target <сайт> --sni <sni_name>
```

**Параметры:**
- `target` - Целевой сайт для маскировки (microsoft.com, apple.com)
- `sni` - SNI имя для TLS

#### verify_certificates()
Проверка действительности сертификатов.

```bash
verify_certificates
```

**Проверяет:**
- Срок действия сертификатов
- Целостность ключей
- Соответствие домену

## 📊 Модуль мониторинга

### monitoring.sh

#### get_system_status()
Получение статуса системы.

```bash
get_system_status [format]
```

**Возвращает:**
```json
{
  "cpu": {
    "usage": "12.5%",
    "load_average": [0.85, 0.92, 1.05],
    "cores": 2
  },
  "memory": {
    "total": "4GB",
    "used": "1.2GB",
    "usage": "30%",
    "swap_used": "0MB"
  },
  "disk": {
    "total": "20GB",
    "used": "8.5GB",
    "usage": "42.5%",
    "available": "11.5GB"
  },
  "network": {
    "rx_bytes": "156GB",
    "tx_bytes": "89GB",
    "active_connections": 8
  }
}
```

#### get_service_status()
Статус сервисов.

```bash
get_service_status [service_name]
```

**Сервисы:**
- `vless-vpn` - Главный сервис
- `xray-core` - Xray контейнер
- `telegram-bot` - Telegram бот
- `monitoring` - Система мониторинга

#### get_performance_metrics()
Метрики производительности.

```bash
get_performance_metrics
```

**Возвращает:**
```json
{
  "bandwidth": {
    "current": "45 Mbps",
    "max": "892 Mbps",
    "average_1h": "78 Mbps"
  },
  "connections": {
    "total": 1245,
    "active": 8,
    "max_concurrent": 50
  },
  "latency": {
    "average": "15ms",
    "min": "8ms",
    "max": "45ms"
  }
}
```

#### check_security_status()
Статус безопасности.

```bash
check_security_status
```

**Проверяет:**
- Статус UFW файрволла
- Активность fail2ban
- Целостность файлов (AIDE)
- Активные блокировки

## 💾 Модуль резервного копирования

### backup_restore.sh

#### create_backup()
Создание резервной копии.

```bash
create_backup [options]
```

**Опции:**
- `--full` - Полная резервная копия
- `--config-only` - Только конфигурации
- `--users-only` - Только пользователи
- `--compress` - Сжатие архива
- `--encrypt` - Шифрование резервной копии

#### restore_backup()
Восстановление из резервной копии.

```bash
restore_backup <backup_file> [options]
```

**Опции:**
- `--verify` - Проверка целостности перед восстановлением
- `--test` - Тестовое восстановление без применения
- `--force` - Принудительное восстановление

#### list_backups()
Список доступных резервных копий.

```bash
list_backups [format]
```

**Возвращает:**
```json
{
  "backups": [
    {
      "filename": "vless-backup-20250919-203045.tar.gz",
      "size": "15.8MB",
      "created": "2025-09-19 20:30:45",
      "type": "full",
      "users_count": 15,
      "integrity": "verified"
    }
  ]
}
```

#### verify_backup()
Проверка целостности резервной копии.

```bash
verify_backup <backup_file>
```

## 🛡️ Модуль безопасности

### security_hardening.sh

#### setup_fail2ban()
Настройка fail2ban для защиты от атак.

```bash
setup_fail2ban [options]
```

**Опции:**
- `--ban-time <время>` - Время блокировки (по умолчанию: 1h)
- `--max-retry <количество>` - Максимум попыток (по умолчанию: 3)
- `--whitelist <ip>` - Добавление IP в белый список

#### setup_aide()
Настройка AIDE для мониторинга целостности.

```bash
setup_aide
```

**Настраивает мониторинг:**
- Конфигурационные файлы
- Исполняемые файлы
- Сертификаты и ключи

#### audit_system()
Аудит безопасности системы.

```bash
audit_system
```

**Проверяет:**
- Открытые порты
- Активные службы
- Права доступа к файлам
- Подозрительные процессы

## 📁 Конфигурационные файлы

### Xray конфигурация

#### config.json
Основная конфигурация Xray сервера.

**Расположение:** `/opt/vless/configs/config.json`

**Структура:**
```json
{
  "log": {
    "level": "info",
    "dnsLog": false
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "PRIVATE_KEY",
          "shortIds": ["SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
```

### Docker Compose конфигурация

#### docker-compose.yml
Конфигурация Docker сервисов.

**Расположение:** `/opt/vless/docker-compose.yml`

**Основные сервисы:**
- `xray-core` - VPN сервер
- `telegram-bot` - Telegram бот
- `monitoring` - Система мониторинга

### Telegram Bot конфигурация

#### .env
Переменные окружения для бота.

```env
BOT_TOKEN=your_bot_token
ADMIN_TELEGRAM_ID=your_admin_id
DOMAIN=your-domain.com
VLESS_PORT=443
HTTP_PORT=80
```

## 🌐 API эндпоинты

### REST API (если включен веб-интерфейс)

#### GET /api/v1/status
Получение статуса сервера.

**Ответ:**
```json
{
  "status": "running",
  "uptime": "15d 8h 23m",
  "version": "1.0.0",
  "users_count": 15,
  "active_connections": 8
}
```

#### GET /api/v1/users
Список пользователей.

**Параметры:**
- `limit` - Количество записей
- `offset` - Смещение
- `status` - Фильтр по статусу

#### POST /api/v1/users
Создание пользователя.

**Тело запроса:**
```json
{
  "name": "john_doe",
  "limit": "5GB",
  "expire": "30d"
}
```

#### DELETE /api/v1/users/{uuid}
Удаление пользователя.

#### GET /api/v1/users/{uuid}/config
Получение конфигурации пользователя.

### WebSocket API

#### /ws/monitoring
Мониторинг в реальном времени.

**События:**
- `status_update` - Обновление статуса
- `new_connection` - Новое подключение
- `security_alert` - Уведомление безопасности

## 🔧 Утилиты разработчика

### Функции для разработки

#### debug_mode()
Включение режима отладки.

```bash
export DEBUG=1
./modules/user_management.sh add "test"
```

#### validate_config()
Проверка конфигурационных файлов.

```bash
validate_config /opt/vless/configs/config.json
```

#### run_tests()
Запуск тестов модуля.

```bash
run_tests user_management
run_tests cert_management
run_tests telegram_bot
```

### Логирование

#### Уровни логирования
- `DEBUG` - Отладочная информация
- `INFO` - Общая информация
- `WARNING` - Предупреждения
- `ERROR` - Ошибки
- `CRITICAL` - Критические ошибки

#### Файлы логов
```
/opt/vless/logs/
├── xray.log              # Логи Xray сервера
├── telegram_bot.log      # Логи Telegram бота
├── system.log            # Системные логи
├── security.log          # Логи безопасности
├── monitoring.log        # Логи мониторинга
└── backup.log            # Логи резервного копирования
```

### Переменные окружения

#### Системные переменные
```bash
VLESS_HOME=/opt/vless
VLESS_CONFIG_DIR=${VLESS_HOME}/configs
VLESS_CERTS_DIR=${VLESS_HOME}/certs
VLESS_USERS_DIR=${VLESS_HOME}/users
VLESS_LOGS_DIR=${VLESS_HOME}/logs
VLESS_BACKUPS_DIR=${VLESS_HOME}/backups
```

#### Переменные разработки
```bash
DEBUG=1                   # Режим отладки
VLESS_TEST_MODE=1        # Тестовый режим
VLESS_LOG_LEVEL=DEBUG    # Уровень логирования
```

---

**Следующий шаг**: [Security Guide](security_guide.md)
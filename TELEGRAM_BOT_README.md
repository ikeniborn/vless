# VLESS VPN Telegram Bot

Telegram-интерфейс для управления VLESS VPN сервером через бота. Позволяет управлять пользователями, мониторить систему и выполнять административные задачи прямо из Telegram.

## 🚀 Быстрый старт

### 1. Создание Telegram бота

1. Найдите [@BotFather](https://t.me/BotFather) в Telegram
2. Отправьте команду `/newbot`
3. Следуйте инструкциям для создания бота
4. Сохраните полученный токен (формат: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### 2. Получение вашего Telegram ID

1. Найдите [@userinfobot](https://t.me/userinfobot) в Telegram
2. Отправьте команду `/start`
3. Сохраните ваш ID (числовое значение, например: `123456789`)

### 3. Настройка конфигурации

```bash
# Скопируйте пример конфигурации
cp .env.example .env

# Отредактируйте файл с вашими данными
nano .env
```

**Обязательные параметры:**
```bash
TELEGRAM_BOT_TOKEN=ВАШ_ТОКЕН_БОТА
ADMIN_TELEGRAM_ID=ВАШ_TELEGRAM_ID
SERVER_IP=IP_ВАШЕГО_СЕРВЕРА
DOMAIN=ВАШ_ДОМЕН
```

### 4. Запуск бота

```bash
# Сборка и запуск
./modules/telegram_bot_manager.sh build
./modules/telegram_bot_manager.sh start

# Проверка статуса
./modules/telegram_bot_manager.sh status
```

### 5. Первое использование

1. Найдите вашего бота в Telegram
2. Отправьте команду `/start`
3. Используйте меню или команды для управления

## 📱 Основные команды

| Команда | Описание |
|---------|----------|
| `/start` | Главное меню |
| `/adduser имя` | Добавить пользователя |
| `/listusers` | Список пользователей |
| `/getconfig uuid` | Получить конфигурацию |
| `/getqr uuid` | Получить QR-код |
| `/status` | Статус сервера |
| `/backup` | Создать резервную копию |

## 🛠 Управление ботом

```bash
# Основные команды
./modules/telegram_bot_manager.sh start      # Запустить
./modules/telegram_bot_manager.sh stop       # Остановить
./modules/telegram_bot_manager.sh restart    # Перезапустить
./modules/telegram_bot_manager.sh logs       # Просмотр логов
./modules/telegram_bot_manager.sh status     # Статус

# Обслуживание
./modules/telegram_bot_manager.sh build      # Пересборка
./modules/telegram_bot_manager.sh update     # Обновление
./modules/telegram_bot_manager.sh test       # Тест конфигурации
./modules/telegram_bot_manager.sh backup     # Резервная копия
```

## 🔧 Устранение неполадок

### Бот не отвечает
```bash
# Проверка статуса
docker ps | grep telegram-bot

# Просмотр логов
./modules/telegram_bot_manager.sh logs

# Тест конфигурации
./modules/telegram_bot_manager.sh test
```

### Ошибка "Access denied"
- Проверьте правильность `ADMIN_TELEGRAM_ID`
- Убедитесь, что ID числовой
- Перезапустите бота после изменений

### QR-коды не генерируются
```bash
# Пересборка образа
./modules/telegram_bot_manager.sh build
./modules/telegram_bot_manager.sh restart
```

## 📋 Системные требования

- **Docker** и **Docker Compose**
- **Python 3.11+** (в контейнере)
- **Linux** (Ubuntu 20.04+ / Debian 11+)
- **Интернет** для Telegram API

## 🔐 Безопасность

- ✅ Доступ только для администратора
- ✅ Проверка прав на каждую команду
- ✅ Подтверждение критических операций
- ✅ Логирование всех действий
- ✅ Запуск от непривилегированного пользователя

## 📁 Структура файлов

```
├── modules/
│   ├── telegram_bot.py              # Основной код бота
│   ├── telegram_bot_manager.sh      # Управление ботом
│   └── user_management.sh           # Управление пользователями
├── config/
│   ├── bot_config.env              # Конфигурация бота
│   └── docker-compose.yml          # Docker Compose
├── docs/
│   └── telegram_bot_setup.md       # Подробная документация
├── tests/
│   └── test_telegram_bot_integration.py
├── requirements.txt                 # Python зависимости
├── Dockerfile.bot                  # Docker образ бота
└── .env.example                    # Пример конфигурации
```

## 🔄 Обновление

```bash
# Обновление до новой версии
git pull origin master
./modules/telegram_bot_manager.sh update
```

## 📊 Мониторинг

```bash
# Статус системы
./modules/telegram_bot_manager.sh status

# Логи в реальном времени
./modules/telegram_bot_manager.sh follow-logs

# Проверка конфигурации
./modules/telegram_bot_manager.sh config
```

## 🆘 Поддержка

1. Проверьте логи: `./modules/telegram_bot_manager.sh logs`
2. Проверьте конфигурацию: `./modules/telegram_bot_manager.sh test`
3. Изучите документацию: `docs/telegram_bot_setup.md`
4. Проверьте репозиторий на наличие обновлений

---

**Версия:** 1.0
**Статус:** Готов к использованию
**Поддержка:** Python 3.11+, Docker 20.10+
# VLESS Phase 4 Integration Guide

## Overview

Phase 4 добавляет расширенные функции безопасности, мониторинга и обслуживания в систему VLESS VPN. Этот этап включает:

- **Усиленная безопасность**: fail2ban, защита ядра, мониторинг целостности файлов
- **Централизованное логирование**: rsyslog, ротация логов, анализ
- **Мониторинг системы**: проверка здоровья, алерты, автовосстановление
- **SystemD интеграция**: автозапуск, управление сервисами
- **Утилиты обслуживания**: диагностика, резервное копирование, массовые операции

## Файлы Phase 4

### Основные модули
- `modules/security_hardening.sh` - Модуль усиления безопасности
- `modules/logging_setup.sh` - Система логирования
- `modules/monitoring.sh` - Система мониторинга
- `modules/maintenance_utils.sh` - Утилиты обслуживания
- `modules/phase4_integration.sh` - Интеграционный модуль

### Конфигурационные файлы
- `config/vless-vpn.service` - SystemD сервис

### Утилиты
- `phase4.sh` - Скрипт быстрого доступа к функциям Phase 4

## Установка Phase 4

### Через главное меню
```bash
sudo ./install.sh
# Выберите опцию "4) Phase 4 Security & Monitoring"
# Затем "Install Phase 4 (full setup)"
```

### Прямая установка
```bash
sudo ./phase4.sh install
```

### Через модуль интеграции
```bash
sudo bash modules/phase4_integration.sh install
```

## Использование Phase 4

### Быстрый доступ через phase4.sh

```bash
# Общее управление
./phase4.sh status          # Показать статус Phase 4
./phase4.sh update           # Обновить конфигурации

# Безопасность
./phase4.sh security         # Применить усиление безопасности
./phase4.sh security-status  # Показать статус безопасности

# Логирование
./phase4.sh logging          # Настроить систему логирования
./phase4.sh logs error       # Просмотреть логи ошибок
./phase4.sh log-analyze      # Анализ логов

# Мониторинг
./phase4.sh monitoring       # Настроить мониторинг
./phase4.sh mon-check        # Проверить здоровье системы
./phase4.sh alerts           # Показать активные алерты

# Обслуживание
./phase4.sh cleanup          # Очистить временные файлы
./phase4.sh diagnostics      # Запустить диагностику
./phase4.sh backup-users     # Резервное копирование пользователей

# Управление сервисами
./phase4.sh service-start    # Запустить VPN сервис
./phase4.sh service-status   # Статус сервиса
```

### Системные команды

После установки Phase 4 доступны следующие команды:

```bash
# Утилиты логирования
vless-logger                 # Функции логирования
vless-log-monitor           # Мониторинг логов
vless-log-analyzer          # Анализ логов

# Мониторинг
vless-monitoring            # Основные функции мониторинга

# Обслуживание
vless-maintenance           # Утилиты обслуживания

# SystemD сервис
systemctl status vless-vpn  # Статус сервиса
systemctl start vless-vpn   # Запуск сервиса
systemctl stop vless-vpn    # Остановка сервиса
```

## Компоненты Phase 4

### 1. Модуль безопасности (security_hardening.sh)

**Функции:**
- Установка и настройка fail2ban
- Отключение неиспользуемых сервисов
- Настройка параметров безопасности ядра
- Ограничение доступа к системным файлам
- Автоматические обновления безопасности
- Мониторинг целостности файлов (AIDE)
- Аудит безопасности (auditd)

**Использование:**
```bash
# Применить все меры безопасности
bash modules/security_hardening.sh apply

# Показать статус безопасности
bash modules/security_hardening.sh status

# Удалить усиление безопасности
bash modules/security_hardening.sh remove
```

### 2. Система логирования (logging_setup.sh)

**Функции:**
- Настройка rsyslog для централизованного логирования
- Конфигурация logrotate для ротации логов
- Мониторинг аномальной активности
- Экспорт логов в JSON формате
- Алерты через Telegram

**Логи:**
- `/var/log/vless/vless.log` - Основные логи
- `/var/log/vless/access.log` - Логи доступа
- `/var/log/vless/error.log` - Логи ошибок
- `/var/log/vless/auth.log` - Логи аутентификации
- `/var/log/vless/system.log` - Системные логи
- `/var/log/vless/monitoring.log` - Логи мониторинга

**Использование:**
```bash
# Настроить логирование
bash modules/logging_setup.sh setup

# Проверить статус
bash modules/logging_setup.sh status

# Тестировать логирование
bash modules/logging_setup.sh test
```

### 3. Система мониторинга (monitoring.sh)

**Функции:**
- Мониторинг CPU, RAM, диска
- Проверка доступности сервисов
- Алерты в Telegram при критических событиях
- Автоматическое восстановление при сбоях
- Хранение метрик в JSON формате

**Пороговые значения (по умолчанию):**
- CPU Warning: 80%, Critical: 95%
- RAM Warning: 85%, Critical: 95%
- Disk Warning: 80%, Critical: 90%
- Load Warning: 3.0, Critical: 5.0

**Использование:**
```bash
# Настроить мониторинг
bash modules/monitoring.sh setup

# Проверить здоровье системы
bash modules/monitoring.sh check

# Показать статус
bash modules/monitoring.sh status

# Сгенерировать отчет
bash modules/monitoring.sh report
```

### 4. Утилиты обслуживания (maintenance_utils.sh)

**Функции:**
- Очистка временных файлов
- Проверка конфигураций
- Генерация отчетов о состоянии системы
- Массовые операции с пользователями
- Диагностика системы

**Использование:**
```bash
# Показать меню обслуживания
bash modules/maintenance_utils.sh menu

# Очистка системы
bash modules/maintenance_utils.sh cleanup

# Проверка конфигураций
bash modules/maintenance_utils.sh validate

# Генерация отчета
bash modules/maintenance_utils.sh report

# Операции с пользователями
bash modules/maintenance_utils.sh users

# Диагностика
bash modules/maintenance_utils.sh diagnostics
```

### 5. SystemD сервис (vless-vpn.service)

**Функции:**
- Автозапуск при загрузке системы
- Автоматический перезапуск при сбоях
- Интеграция с systemd журналированием
- Управление через systemctl

**Установка:**
```bash
# Копировать файл сервиса
sudo cp config/vless-vpn.service /etc/systemd/system/

# Перезагрузить systemd
sudo systemctl daemon-reload

# Включить автозапуск
sudo systemctl enable vless-vpn

# Запустить сервис
sudo systemctl start vless-vpn
```

## Интеграция с Telegram Bot

Phase 4 добавляет новые команды в Telegram бот:

- `/security` - Показать статус безопасности
- `/monitoring` - Показать статус мониторинга
- `/maintenance` - Меню обслуживания с кнопками

## Автоматизация

Phase 4 устанавливает следующие автоматические задачи:

### Cron задачи
- **Мониторинг системы**: каждую минуту
- **Проверка сервисов**: каждые 2 минуты
- **Мониторинг логов**: каждые 2 минуты
- **Ежедневное обслуживание**: в 3:00 утра
- **Ежедневный отчет**: в 6:00 утра

### Ротация логов
- **Основные логи**: ежедневно, хранятся 30 дней
- **Логи доступа**: ежедневно, хранятся 14 дней
- **Логи ошибок**: ежедневно, хранятся 60 дней
- **Логи аутентификации**: ежедневно, хранятся 90 дней

## Конфигурация

### Пороговые значения мониторинга
Файл: `/etc/vless-monitoring/thresholds.conf`

```bash
# CPU Usage (percentage)
CPU_WARNING=80
CPU_CRITICAL=95

# RAM Usage (percentage)
RAM_WARNING=85
RAM_CRITICAL=95

# Disk Usage (percentage)
DISK_WARNING=80
DISK_CRITICAL=90

# Telegram Settings
TELEGRAM_ENABLED=true
TELEGRAM_MENTION_ON_CRITICAL=true
```

### Конфигурация безопасности
- **fail2ban**: `/etc/fail2ban/jail.local`
- **Параметры ядра**: `/etc/sysctl.d/99-vless-security.conf`
- **AIDE**: `/etc/aide/aide.conf.d/99-vless-monitoring`
- **Аудит**: `/etc/audit/rules.d/99-vless-audit.rules`

### Конфигурация логирования
- **rsyslog**: `/etc/rsyslog.d/49-vless.conf`
- **logrotate**: `/etc/logrotate.d/vless`

## Удаление Phase 4

### Через главное меню
```bash
sudo ./install.sh
# Выберите "4) Phase 4 Security & Monitoring"
# Затем "Remove Phase 4 components"
```

### Прямое удаление
```bash
sudo ./phase4.sh remove
```

## Troubleshooting

### Проблемы с установкой
1. Убедитесь, что базовая установка VLESS завершена
2. Проверьте права доступа (запуск от root)
3. Убедитесь, что Docker запущен

### Проблемы с мониторингом
1. Проверьте cron задачи: `sudo crontab -l`
2. Проверьте логи мониторинга: `./phase4.sh logs monitoring`
3. Проверьте статус: `./phase4.sh mon-status`

### Проблемы с логированием
1. Проверьте статус rsyslog: `systemctl status rsyslog`
2. Тестируйте логирование: `./phase4.sh logging-test`
3. Проверьте права доступа к логам: `ls -la /var/log/vless/`

### Проблемы с безопасностью
1. Проверьте статус fail2ban: `systemctl status fail2ban`
2. Проверьте статус безопасности: `./phase4.sh security-status`
3. Проверьте логи безопасности: `/var/log/vless-security.log`

## Логи и отладка

### Основные файлы логов
- `/var/log/vless-install.log` - Логи установки
- `/var/log/vless/phase4-integration.log` - Логи интеграции Phase 4
- `/var/log/vless-security.log` - Логи безопасности
- `/var/log/vless/maintenance.log` - Логи обслуживания

### Команды отладки
```bash
# Проверить все сервисы
./phase4.sh status

# Запустить диагностику
./phase4.sh diagnostics

# Проверить активные алерты
./phase4.sh alerts

# Просмотреть логи ошибок
./phase4.sh logs error

# Сгенерировать системный отчет
./phase4.sh report
```

## Требования

- Базовая установка VLESS VPN
- Ubuntu 20.04+ или Debian 11+
- Минимум 1GB RAM
- Минимум 5GB свободного места
- Root доступ
- Интернет соединение

## Заключение

Phase 4 значительно улучшает безопасность, надежность и управляемость системы VLESS VPN. После установки система становится production-ready с автоматическим мониторингом, алертами и обслуживанием.
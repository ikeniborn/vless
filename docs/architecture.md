# Архитектура системы VLESS+Reality VPN

> Подробное описание архитектуры, дизайна и технических решений системы VLESS+Reality VPN.

## 📋 Содержание

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Компоненты системы](#компоненты-системы)
3. [Сетевая архитектура](#сетевая-архитектура)
4. [Архитектура безопасности](#архитектура-безопасности)
5. [Архитектура данных](#архитектура-данных)
6. [Контейнерная архитектура](#контейнерная-архитектура)
7. [Масштабирование](#масштабирование)
8. [Мониторинг и логирование](#мониторинг-и-логирование)
9. [Принципы дизайна](#принципы-дизайна)

## 🏗️ Обзор архитектуры

### Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                        ИНТЕРНЕТ                                 │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  EDGE LAYER                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │    UFW      │  │  fail2ban   │  │   DDoS      │            │
│  │ Firewall    │  │ Protection  │  │ Protection  │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 VPN LAYER                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Reality   │  │   VLESS     │  │    TLS      │            │
│  │ Masquerading│  │  Protocol   │  │    1.3      │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│               CONTAINER LAYER                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Xray-core   │  │ Telegram    │  │ Monitoring  │            │
│  │ Container   │  │ Bot         │  │ Service     │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│               SYSTEM LAYER                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Docker    │  │   systemd   │  │    AIDE     │            │
│  │   Engine    │  │   Services  │  │ Monitoring  │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                HOST OS LAYER                                    │
│         Ubuntu 20.04+ / Debian 11+ / CentOS 8+                │
└─────────────────────────────────────────────────────────────────┘
```

### Архитектурные принципы

1. **Модульность**
   - Независимые компоненты
   - Слабая связанность
   - Высокая связность внутри модулей

2. **Масштабируемость**
   - Горизонтальное масштабирование
   - Статeless дизайн
   - Эффективное использование ресурсов

3. **Безопасность**
   - Defense in Depth
   - Principle of Least Privilege
   - Security by Design

4. **Надежность**
   - Fault Tolerance
   - Graceful Degradation
   - Health Monitoring

## 🔧 Компоненты системы

### Основные компоненты

#### 1. Xray-core VPN Server
**Назначение:** Обработка VPN соединений по протоколу VLESS+Reality

```yaml
Component: Xray-core
Type: Core Service
Language: Go
Protocol: VLESS + Reality
Ports: 80, 443
Dependencies: TLS certificates, Reality keys
```

**Функциональность:**
- Обработка VLESS соединений
- Reality маскировка трафика
- TLS 1.3 терминирование
- Маршрутизация трафика
- Управление пользователями

#### 2. Telegram Bot Manager
**Назначение:** Управление системой через Telegram API

```yaml
Component: Telegram Bot
Type: Management Interface
Language: Python 3.11
Framework: python-telegram-bot 20.x
Dependencies: Telegram API, System modules
```

**Функциональность:**
- Управление пользователями
- Мониторинг системы
- Генерация QR-кодов
- Автоматические уведомления
- Backup/Restore операции

#### 3. System Monitoring Service
**Назначение:** Мониторинг состояния системы и безопасности

```yaml
Component: Monitoring
Type: System Service
Language: Bash/Python
Dependencies: System metrics, Log files
```

**Функциональность:**
- Мониторинг ресурсов
- Анализ логов
- Обнаружение аномалий
- Автоматические алерты
- Performance метрики

### Архитектурная диаграмма компонентов

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL INTERFACES                         │
├─────────────────────────────────────────────────────────────────┤
│  VPN Clients          Telegram API           Web Browser        │
│      ↓                    ↓                      ↓              │
└─────────┬─────────────────┬──────────────────────┬──────────────┘
          │                 │                      │
          ▼                 ▼                      ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   XRAY-CORE     │ │ TELEGRAM BOT    │ │   MONITORING    │
│                 │ │                 │ │     SERVICE     │
│ • VLESS Handler │ │ • Command Proc. │ │ • Metrics Coll. │
│ • Reality Mask  │ │ • User Mgmt     │ │ • Log Analysis  │
│ • TLS Term.     │ │ • QR Generator  │ │ • Alerting      │
│ • Traffic Route │ │ • System Ctrl   │ │ • Health Check  │
└─────────┬───────┘ └─────────┬───────┘ └─────────┬───────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SHARED SERVICES                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ User Mgmt   │  │ Cert Mgmt   │  │ Config Mgmt │            │
│  │ Module      │  │ Module      │  │ Module      │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Backup      │  │ Security    │  │ Maintenance │            │
│  │ Module      │  │ Module      │  │ Module      │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  /opt/vless/                                                   │
│  ├── configs/     # Xray configurations                        │
│  ├── certs/       # TLS certificates & Reality keys            │
│  ├── users/       # User data & configurations                 │
│  ├── logs/        # System & application logs                  │
│  └── backups/     # Backup archives                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 🌐 Сетевая архитектура

### Сетевая топология

```
                          INTERNET
                             │
                             ▼
                    ┌─────────────────┐
                    │   PUBLIC IP     │
                    │  (VPS/Server)   │
                    └─────────┬───────┘
                              │
               ┌──────────────┼──────────────┐
               │              │              │
               ▼              ▼              ▼
         ┌──────────┐   ┌──────────┐   ┌──────────┐
         │   :22    │   │   :80    │   │   :443   │
         │   SSH    │   │   HTTP   │   │  HTTPS   │
         └──────────┘   └──────────┘   └──────────┘
               │              │              │
               │              └──────┬───────┘
               │                     │
               ▼                     ▼
         ┌──────────┐           ┌──────────┐
         │   UFW    │           │  Xray    │
         │ Firewall │           │  Core    │
         └──────────┘           └──────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │   Reality    │
                              │ Masquerading │
                              └──────────┬───┘
                                         │
                              ┌──────────▼───┐
                              │   Internal   │
                              │   Network    │
                              └──────────────┘
```

### Сетевые протоколы и порты

| Порт | Протокол | Сервис | Назначение |
|------|----------|---------|------------|
| 22   | TCP      | SSH     | Удаленное управление |
| 80   | TCP      | HTTP    | Reality fallback |
| 443  | TCP      | HTTPS   | VLESS+Reality VPN |

### Traffic Flow

#### 1. VPN Client Connection Flow

```
Client → [Internet] → [UFW Firewall] → [Xray:443] → [Reality Check] → [VLESS Handler] → [Internal Network]
```

#### 2. Reality Masquerading Flow

```
Scanner → [Port 443] → [Reality Layer] → [SNI Check] → [Fallback to Real Site] → [microsoft.com]
```

#### 3. Management Flow

```
Admin → [Telegram] → [Bot API] → [System Modules] → [Configuration Files] → [Service Restart]
```

## 🔒 Архитектура безопасности

### Многоуровневая защита

#### Уровень 1: Сетевая защита
```
┌─────────────────────────────────────┐
│           NETWORK SECURITY          │
├─────────────────────────────────────┤
│ • UFW Firewall (Stateful)          │
│ • fail2ban (Intrusion Prevention)  │
│ • DDoS Protection                  │
│ • Rate Limiting                    │
│ • IP Whitelisting                  │
└─────────────────────────────────────┘
```

#### Уровень 2: Протокольная защита
```
┌─────────────────────────────────────┐
│         PROTOCOL SECURITY           │
├─────────────────────────────────────┤
│ • TLS 1.3 Encryption              │
│ • Reality SNI Masquerading         │
│ • VLESS UUID Authentication        │
│ • Forward Secrecy                  │
│ • AEAD Ciphers                     │
└─────────────────────────────────────┘
```

#### Уровень 3: Системная защита
```
┌─────────────────────────────────────┐
│          SYSTEM SECURITY            │
├─────────────────────────────────────┤
│ • AIDE File Integrity              │
│ • AppArmor/SELinux MAC              │
│ • Audit Logging                    │
│ • Privilege Separation             │
│ • Container Isolation              │
└─────────────────────────────────────┘
```

### Reality Protocol Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    REALITY PROTOCOL STACK                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Incoming TLS 1.3 Connection                                  │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                           │
│  │   SNI Check     │────────┐                                 │
│  │                 │        │                                 │
│  └─────────────────┘        │                                 │
│           │                  │                                 │
│           │ Valid            │ Invalid/Scanner                 │
│           ▼                  ▼                                 │
│  ┌─────────────────┐  ┌─────────────────┐                    │
│  │  VLESS Handler  │  │  Fallback to    │                    │
│  │                 │  │  Real Website   │                    │
│  └─────────────────┘  └─────────────────┘                    │
│           │                  │                                 │
│           ▼                  ▼                                 │
│  ┌─────────────────┐  ┌─────────────────┐                    │
│  │   VPN Tunnel    │  │  Microsoft.com  │                    │
│  │                 │  │  Apple.com      │                    │
│  └─────────────────┘  └─────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 💾 Архитектура данных

### Структура данных

```
/opt/vless/
├── configs/
│   ├── config.json              # Основная конфигурация Xray
│   ├── routing.json             # Правила маршрутизации
│   └── inbounds.json           # Конфигурация входящих соединений
├── certs/
│   ├── reality.key             # Приватный ключ Reality
│   ├── reality.pub             # Публичный ключ Reality
│   └── short_ids.txt           # Short ID для Reality
├── users/
│   ├── users.json              # База данных пользователей
│   ├── [uuid].json             # Конфигурация пользователя
│   └── stats.json              # Статистика использования
├── logs/
│   ├── xray.log                # Логи Xray сервера
│   ├── telegram_bot.log        # Логи Telegram бота
│   ├── security.log            # Логи безопасности
│   └── monitoring.log          # Логи мониторинга
└── backups/
    ├── daily/                  # Ежедневные бэкапы
    ├── weekly/                 # Еженедельные бэкапы
    └── emergency/              # Аварийные бэкапы
```

### Модель данных пользователя

```json
{
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "name": "john_doe",
  "created": "2025-09-19T15:30:25Z",
  "status": "active",
  "config": {
    "vless_url": "vless://uuid@domain:443?...",
    "traffic_limit": "5GB",
    "expire_date": "2025-10-19T15:30:25Z"
  },
  "stats": {
    "upload_bytes": 896803840,
    "download_bytes": 1288490188,
    "connection_count": 15,
    "last_connection": "2025-09-19T18:45:12Z"
  },
  "security": {
    "creation_ip": "192.168.1.100",
    "last_ip": "10.0.0.15",
    "failed_attempts": 0
  }
}
```

### Конфигурационная модель

```json
{
  "system": {
    "domain": "vpn.example.com",
    "ports": {
      "vless": 443,
      "fallback": 80
    },
    "reality": {
      "target": "microsoft.com:443",
      "sni": "www.microsoft.com",
      "private_key": "...",
      "short_ids": ["0123456789abcdef"]
    }
  },
  "security": {
    "ufw_enabled": true,
    "fail2ban_enabled": true,
    "aide_enabled": true,
    "auto_backup": true
  },
  "monitoring": {
    "telegram_alerts": true,
    "performance_monitoring": true,
    "security_monitoring": true
  }
}
```

## 🐳 Контейнерная архитектура

### Docker Compose Architecture

```yaml
version: '3.8'

services:
  xray-core:
    image: teddysun/xray:latest
    container_name: xray-core
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/vless/configs:/etc/xray:ro
      - /opt/vless/certs:/certs:ro
      - /opt/vless/logs:/var/log/xray
    networks:
      - vless-network
    healthcheck:
      test: ["CMD", "xray", "version"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'

  telegram-bot:
    build:
      context: .
      dockerfile: Dockerfile.bot
    container_name: telegram-bot
    restart: unless-stopped
    env_file: .env
    volumes:
      - /opt/vless:/opt/vless
    networks:
      - vless-network
    depends_on:
      - xray-core
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('https://api.telegram.org')"]
      interval: 60s
      timeout: 10s
      retries: 3

  monitoring:
    image: alpine:latest
    container_name: monitoring
    restart: unless-stopped
    volumes:
      - /opt/vless/logs:/logs:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    networks:
      - vless-network
    command: ["/bin/sh", "-c", "while true; do sleep 60; done"]

networks:
  vless-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### Container Security

#### Security Constraints
```yaml
security_opt:
  - no-new-privileges:true
  - seccomp:unconfined
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE
read_only: true
tmpfs:
  - /tmp:noexec,nosuid,size=100m
```

#### Resource Limits
```yaml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '1.0'
    reservations:
      memory: 256M
      cpus: '0.5'
```

## 📈 Масштабирование

### Горизонтальное масштабирование

#### Multi-Server Architecture

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │    (HAProxy)    │
                    └─────────┬───────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │  VPN Server 1   │ │  VPN Server 2   │ │  VPN Server 3   │
    │  (Primary)      │ │  (Secondary)    │ │  (Tertiary)     │
    └─────────────────┘ └─────────────────┘ └─────────────────┘
              │               │               │
              └───────────────┼───────────────┘
                              │
                    ┌─────────▼───────┐
                    │   Shared DB     │
                    │   (PostgreSQL)  │
                    └─────────────────┘
```

#### Load Balancer Configuration

```haproxy
global
    daemon
    user haproxy
    group haproxy

defaults
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend vless_frontend
    bind *:443
    default_backend vless_servers

backend vless_servers
    balance roundrobin
    server vpn1 10.0.1.10:443 check
    server vpn2 10.0.1.11:443 check
    server vpn3 10.0.1.12:443 check
```

### Вертикальное масштабирование

#### Performance Tuning

```bash
# Системные параметры для высокой нагрузки
echo 'net.core.somaxconn = 65535' >> /etc/sysctl.conf
echo 'net.core.netdev_max_backlog = 5000' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_max_syn_backlog = 65535' >> /etc/sysctl.conf
echo 'net.ipv4.ip_local_port_range = 1024 65535' >> /etc/sysctl.conf

# Лимиты файловых дескрипторов
echo '* soft nofile 65535' >> /etc/security/limits.conf
echo '* hard nofile 65535' >> /etc/security/limits.conf
```

#### Resource Optimization

```yaml
# Docker Compose с оптимизированными лимитами
services:
  xray-core:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '1.0'
    ulimits:
      nofile:
        soft: 65535
        hard: 65535
```

## 📊 Мониторинг и логирование

### Архитектура мониторинга

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONITORING ARCHITECTURE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Metrics   │  │    Logs     │  │   Events    │            │
│  │ Collection  │  │   Aggreg.   │  │   Stream    │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                │                │                    │
│         └────────────────┼────────────────┘                    │
│                          │                                     │
│                          ▼                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Processing  │  │ Analysis    │  │  Alerting   │            │
│  │  Engine     │  │  Engine     │  │   Engine    │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                │                │                    │
│         └────────────────┼────────────────┘                    │
│                          │                                     │
│                          ▼                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Dashboard  │  │  Telegram   │  │   Storage   │            │
│  │   (Web UI)  │  │    Bot      │  │ (Time Series│            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Logging Pipeline

```
Application Logs → [Structured Logging] → [Log Rotation] → [Centralized Storage] → [Analysis] → [Alerts]
```

#### Log Levels and Routing

```json
{
  "logging": {
    "levels": {
      "DEBUG": "/opt/vless/logs/debug.log",
      "INFO": "/opt/vless/logs/info.log",
      "WARNING": "/opt/vless/logs/warning.log",
      "ERROR": "/opt/vless/logs/error.log",
      "CRITICAL": "/opt/vless/logs/critical.log"
    },
    "rotation": {
      "max_size": "100MB",
      "max_files": 10,
      "compression": true
    },
    "format": "JSON",
    "timestamp": "ISO8601"
  }
}
```

## 🎯 Принципы дизайна

### SOLID Principles Application

#### 1. Single Responsibility Principle (SRP)
- Каждый модуль отвечает за одну функцию
- user_management.sh - только управление пользователями
- cert_management.sh - только управление сертификатами

#### 2. Open/Closed Principle (OCP)
- Модули открыты для расширения, закрыты для изменения
- Новые протоколы добавляются через плагины
- Новые методы аутентификации через интерфейсы

#### 3. Liskov Substitution Principle (LSP)
- Любой модуль может быть заменен совместимым
- Различные backend'ы для хранения данных
- Различные провайдеры уведомлений

#### 4. Interface Segregation Principle (ISP)
- Интерфейсы разделены по функциональности
- Отдельные API для управления и мониторинга
- Специализированные команды для разных ролей

#### 5. Dependency Inversion Principle (DIP)
- Высокоуровневые модули не зависят от низкоуровневых
- Абстракции для работы с Docker
- Интерфейсы для системных операций

### Design Patterns

#### 1. Module Pattern
```bash
# Каждый модуль - независимый компонент
modules/
├── user_management.sh     # User CRUD operations
├── cert_management.sh     # Certificate management
├── backup_restore.sh      # Backup operations
└── monitoring.sh          # System monitoring
```

#### 2. Observer Pattern
```bash
# Система событий и уведомлений
event_bus.sh:
  - user_created → [telegram_notification, audit_log]
  - security_alert → [telegram_alert, email_notification]
  - system_error → [log_error, restart_service]
```

#### 3. Strategy Pattern
```bash
# Различные стратегии для разных задач
backup_strategies/
├── local_backup.sh        # Local file backup
├── cloud_backup.sh        # Cloud storage backup
└── incremental_backup.sh  # Incremental backup
```

#### 4. Factory Pattern
```bash
# Фабрика для создания конфигураций
config_factory.sh:
  create_user_config()
  create_server_config()
  create_monitoring_config()
```

### Error Handling Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ERROR HANDLING STACK                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Application Error → [Local Handler] → [Global Handler]        │
│                              │                │                 │
│                              ▼                ▼                 │
│                     [Log Error]      [Send Alert]               │
│                              │                │                 │
│                              ▼                ▼                 │
│                    [Attempt Recovery] [Escalate]                │
│                              │                │                 │
│                              ▼                ▼                 │
│                    [Success/Failure]  [Manual Intervention]     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Management

#### Hierarchical Configuration

```
Configuration Priority (High to Low):
1. Environment Variables
2. Command Line Arguments
3. Local Configuration Files
4. Default Configuration
5. Hardcoded Defaults
```

#### Configuration Schema

```json
{
  "$schema": "https://json-schema.org/draft/2019-09/schema",
  "type": "object",
  "properties": {
    "server": {
      "type": "object",
      "properties": {
        "domain": {"type": "string"},
        "ports": {
          "type": "object",
          "properties": {
            "vless": {"type": "integer", "minimum": 1, "maximum": 65535},
            "http": {"type": "integer", "minimum": 1, "maximum": 65535}
          }
        }
      },
      "required": ["domain", "ports"]
    },
    "security": {
      "type": "object",
      "properties": {
        "reality": {
          "type": "object",
          "properties": {
            "target": {"type": "string"},
            "sni": {"type": "string"}
          }
        }
      }
    }
  },
  "required": ["server"]
}
```

### Testing Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     TESTING PYRAMID                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    [E2E Tests]                                 │
│                   /           \                                │
│              [Integration Tests]                               │
│             /                   \                              │
│        [Unit Tests]         [System Tests]                     │
│       /           \         /              \                   │
│  [Module]    [Function]  [Docker]     [Security]               │
│   Tests       Tests      Tests        Tests                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

**Заключение**: Архитектура системы спроектирована с учетом современных принципов разработки, обеспечивая высокую производительность, безопасность и масштабируемость при сохранении простоты эксплуатации.

**Следующий шаг**: [CLAUDE.md - Память проекта](../CLAUDE.md)
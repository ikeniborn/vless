# VLESS + Reality VPN — Руководство

**v5.33** · [← README](../README.md)

---

## Содержание

1. [Предварительные требования](#1-предварительные-требования)
2. [Установка](#2-установка)
3. [Управление пользователями](#3-управление-пользователями)
4. [Подключение клиентов](#4-подключение-клиентов)
5. [SOCKS5 и HTTP прокси](#5-socks5-и-http-прокси)
6. [Tier 2 транспорты (WS / XHTTP / gRPC)](#6-tier-2-транспорты-ws--xhttp--grpc)
7. [Reverse proxy](#7-reverse-proxy)
8. [External proxy](#8-external-proxy)
9. [Обновление сертификатов](#9-обновление-сертификатов)
10. [Диагностика](#10-диагностика)
11. [Удаление](#11-удаление)

---

## 1. Предварительные требования

**Сервер:**
- Ubuntu 20.04+ или Debian 10+
- Публичный IPv4-адрес
- Открытые входящие порты: `443`, `1080`, `8118`

**Для TLS-прокси, Tier 2, Reverse proxy:**
- Домен с A-записью, указывающей на IP сервера
- Email для Let's Encrypt

**Зависимости** (устанавливает `install.sh`):
- Docker 24+, Docker Compose v2
- certbot
- ufw, jq, qrencode

---

## 2. Установка

```bash
git clone <repo-url>
cd vless
sudo ./install.sh
```

Установщик пройдёт через шаги:

1. **Проверка системы** — Docker, UFW, порты, DNS
2. **Reality параметры** — домен маскировки (например, `www.microsoft.com`), порт (`443`)
3. **Домен и email** — для Let's Encrypt (опционально, нужен для прокси)
4. **DNS** — автоматическое тестирование Cloudflare/Google/Quad9, выбор оптимального
5. **Прокси-режим** — включить SOCKS5/HTTP прокси или нет
6. **Запуск** — генерация конфигов, старт контейнеров, выпуск сертификата

По окончании установщик выведет URI и QR код для первого пользователя.

**Файлы устанавливаются в `/opt/vless/`:**

```
/opt/vless/
├── config/
│   ├── xray_config.json       # Конфигурация Xray
│   ├── nginx/nginx.conf       # Конфигурация Nginx (stream + http)
│   └── keys/                  # Reality ключи
├── data/
│   ├── users.json             # База пользователей
│   ├── transports.json        # Tier 2 транспорты
│   └── clients/<name>/        # Конфигурации клиентов
└── logs/
    ├── xray/
    └── nginx/
```

**CLI-инструменты** после установки:
```
/usr/local/bin/vless
/usr/local/bin/vless-proxy
/usr/local/bin/vless-external-proxy
/usr/local/bin/vless-cert-renew
```

---

## 3. Управление пользователями

### Добавить пользователя

```bash
sudo vless add-user <name>
```

Команда:
- Генерирует UUID и fingerprint
- Добавляет пользователя в `xray_config.json` с `flow: xtls-rprx-vision`
- Выводит VLESS URI и QR код
- Создаёт конфиги в `/opt/vless/data/clients/<name>/`

### Показать пользователя

```bash
sudo vless show-user <name>
```

Выводит URI, QR код, SOCKS5/HTTP прокси URI (если прокси включён).

### Список пользователей

```bash
sudo vless list-users
```

### Удалить пользователя

```bash
sudo vless remove-user <name>
```

### Миграция на XTLS Vision

Если на сервере есть пользователи без поля `flow` (созданные до v5.25):

```bash
sudo vless migrate-vision
```

---

## 4. Подключение клиентов

### Получить URI

```bash
sudo vless show-user <name>
```

URI имеет формат:
```
vless://UUID@SERVER:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#name
```

### Рекомендуемые приложения

| Платформа | Приложение | Протокол |
|---|---|---|
| Android | v2rayNG | VLESS Reality, WS, gRPC |
| iOS | v2rayTun | VLESS Reality, WS, gRPC |
| iOS | Shadowrocket | VLESS Reality |
| Windows | v2rayN | VLESS Reality, WS, gRPC |
| macOS / Linux | v2rayA | VLESS Reality, WS |

Импортируйте URI через QR код или вставкой в буфер обмена.

### Настройки клиента (вручную)

| Параметр | Значение |
|---|---|
| Protocol | VLESS |
| Address | IP или домен сервера |
| Port | 443 |
| UUID | из `vless show-user` |
| Flow | xtls-rprx-vision |
| Security | reality |
| SNI | домен маскировки (например, `www.microsoft.com`) |
| Fingerprint | chrome |
| Public Key | из `vless show-user` |
| Short ID | из `vless show-user` |
| Network | tcp |

---

## 5. SOCKS5 и HTTP прокси

Прокси использует TLS-терминацию через `vless_nginx`. Нужен домен с сертификатом.

### Схемы подключения

```
SOCKS5:  socks5s://username:password@DOMAIN:1080
HTTP:    https://username:password@DOMAIN:8118
```

`vless show-user <name>` выводит готовые URI для обоих протоколов.

### Проверить подключение

```bash
curl --socks5 username:password@DOMAIN:1080 https://ifconfig.me
curl --proxy https://username:password@DOMAIN:8118 https://ifconfig.me
```

### Настройка в инструментах

**Git:**
```bash
git config --global http.proxy socks5s://username:password@DOMAIN:1080
```

**npm:**
```bash
npm config set proxy https://username:password@DOMAIN:8118
```

**Docker daemon** (`/etc/docker/daemon.json`):
```json
{
  "proxies": {
    "https-proxy": "https://username:password@DOMAIN:8118"
  }
}
```

Готовые файлы конфигурации для каждого пользователя — в `/opt/vless/data/clients/<name>/`.

---

## 6. Tier 2 транспорты (WS / XHTTP / gRPC)

Tier 2 транспорты используют TLS-терминацию через Nginx http-блок (порт 8448, loopback).
Требуют отдельного поддомена и сертификата для каждого транспорта.

### Архитектура Tier 2

```
Client → TCP:443 → vless_nginx (ssl_preread)
  └─ SNI ws.domain → 127.0.0.1:8448 (http block)
       └─ proxy_pass → vless_xray:8444 (WS plaintext)
```

### Включить транспорт

```bash
sudo vless add-transport ws   ws.yourdomain.com
sudo vless add-transport xhttp xhttp.yourdomain.com
sudo vless add-transport grpc  grpc.yourdomain.com
```

Команда:
- Добавляет inbound в `xray_config.json` (не затрагивает существующих пользователей)
- Обновляет `nginx.conf`: SNI map + http server block
- Перезагружает `vless_nginx` (zero-downtime) и перезапускает `vless_xray`

### Список активных транспортов

```bash
sudo vless list-transports
```

### Отключить транспорт

```bash
sudo vless remove-transport ws
```

### URI для Tier 2

URI генерируется функцией `generate_transport_uri()`. Пример для WebSocket:
```
vless://UUID@ws.domain:443?encryption=none&security=tls&sni=ws.domain&fp=chrome&type=ws&path=%2Fvless-ws#name-ws
```

### Совместимость

| Транспорт | Android (v2rayNG) | iOS (v2rayTun) | Windows (v2rayN) |
|---|---|---|---|
| WebSocket | ✅ | ✅ | ✅ |
| XHTTP | ✅ | ⚠️ требует проверки | ✅ |
| gRPC | ✅ | ✅ | ✅ |

---

## 7. Reverse proxy

Reverse proxy открывает внешний сайт через ваш поддомен без VPN. Требует домен.

### Добавить

```bash
sudo vless-proxy add
```

Интерактивный wizard запросит:
- Поддомен (например, `claude.yourdomain.com`)
- Целевой сайт (например, `claude.ai`)
- Email для сертификата

После добавления сайт доступен по `https://claude.yourdomain.com`.

### Управление

```bash
sudo vless-proxy list              # Список всех routes
sudo vless-proxy show <domain>     # Детали конкретного route
sudo vless-proxy remove <domain>   # Удалить route
```

---

## 8. External proxy

External proxy — upstream proxy, через который Xray пробрасывает трафик.

### Server-level: все пользователи через один proxy

```bash
# Добавить proxy
sudo vless-external-proxy add
# Wizard запросит: тип (socks5/http), адрес, порт, credentials

# Активировать
sudo vless-external-proxy switch <proxy-id>
sudo vless-external-proxy enable

# Статус
sudo vless-external-proxy status
```

### Per-user: у каждого пользователя свой proxy

```bash
# Назначить proxy пользователю
sudo vless set-proxy alice proxy-id

# Вернуть на direct routing
sudo vless set-proxy alice none

# Показать назначение
sudo vless show-proxy alice

# Список всех назначений
sudo vless list-proxy-assignments
```

Per-user proxy работает только для VLESS (email-based routing). SOCKS5/HTTP прокси не поддерживают user-based routing.

---

## 9. Обновление сертификатов

Certbot обновляет сертификаты автоматически через `--deploy-hook`. После обновления хук:

1. Валидирует новые файлы сертификата
2. Проверяет здоровье контейнеров `vless_nginx` и `vless_xray`
3. Выполняет `nginx -s reload` (zero-downtime)
4. Перезапускает `vless_xray`

**Принудительное обновление:**
```bash
sudo certbot renew --force-renewal
```

**Ручной вызов хука:**
```bash
RENEWED_DOMAINS="yourdomain.com" sudo /usr/local/bin/vless-cert-renew
```

**Логи:**
```
/opt/vless/logs/certbot-renew.log
/opt/vless/logs/certbot-renew-metrics.json
```

---

## 10. Диагностика

### Статус

```bash
sudo vless status           # Контейнеры, пользователи, прокси, транспорты
docker ps                   # Детальный статус контейнеров
```

### Логи

```bash
sudo vless logs xray        # Xray логи
sudo vless logs nginx       # Nginx логи
sudo vless logs all         # Все логи
docker logs vless_xray --tail 50
docker logs vless_nginx --tail 50
```

### Тесты безопасности

```bash
sudo vless test-security            # Полный набор тестов
sudo vless test-security --quick    # Без packet capture
```

### Проверка конфигурации

```bash
# Nginx
docker exec vless_nginx nginx -t

# Xray JSON
jq empty /opt/vless/config/xray_config.json && echo "OK"

# Порты
sudo ss -tulnp | grep -E '443|1080|8118'
```

### Частые проблемы

**Xray unhealthy — неправильный порт**

Xray должен слушать на `8443`, не `443`. Проверить:
```bash
jq '.inbounds[0].port' /opt/vless/config/xray_config.json  # должно быть 8443
```

**Nginx не запускается**

```bash
docker exec vless_nginx nginx -t  # покажет ошибку в конфиге
docker logs vless_nginx --tail 30
```

**Нет интернета в контейнерах (UFW блокирует Docker)**

```bash
# Проверить
docker exec vless_xray ping -c 1 8.8.8.8

# Исправить — добавить в /etc/ufw/after.rules Docker-цепочки, затем:
sudo ufw reload
```

**Cert renewal падает — vless_nginx не запущен**

```bash
docker start vless_nginx
# Затем повторить:
RENEWED_DOMAINS="domain" sudo vless-cert-renew
```

---

## 11. Удаление

```bash
sudo /opt/vless/scripts/vless-uninstall
```

Создаёт резервную копию в `/tmp/vless_backup_YYYYMMDD/`, затем удаляет:
- `/opt/vless/`
- Docker-контейнеры и volumes
- UFW-правила
- Симлинки в `/usr/local/bin/`

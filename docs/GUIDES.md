# familyTraffic VPN — Руководство

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

**Файлы устанавливаются в `/opt/familytraffic/`:**

```
/opt/familytraffic/
├── config/
│   ├── xray_config.json         # Конфигурация Xray
│   ├── nginx/nginx.conf         # Конфигурация familytraffic-nginx (stream + http)
│   ├── reverse-proxy/           # Конфиги familytraffic-nginx (если включён)
│   └── keys/                    # Reality ключи (private.key, public.key)
├── data/
│   ├── users.json               # База пользователей
│   ├── transports.json          # Tier 2 транспорты
│   └── clients/<name>/          # Конфигурации клиентов (URI, QR, proxy-файлы)
└── logs/
    ├── xray/
    └── nginx/
```

**Контейнеры Docker:**

| Контейнер | Назначение | Всегда |
|---|---|---|
| `familytraffic-nginx` | SNI routing (443), TLS termination (1080/8118), Tier 2 http block (8448) | ✅ |
| `familytraffic` | VLESS Reality + SOCKS5 + HTTP + Tier 2 inbounds | ✅ |
| `familytraffic-fake-site` | Fallback сайт для Reality handshake | ✅ |
| `familytraffic-nginx` | Reverse proxy к внешним сайтам (поддомены) | Опционально |

**CLI-инструменты** после установки:
```
/usr/local/bin/vless
/usr/local/bin/familytraffic-proxy
/usr/local/bin/familytraffic-external-proxy
/usr/local/bin/familytraffic-cert-renew
```

---

## 3. Управление пользователями

### Добавить пользователя

```bash
sudo familytraffic add-user <name>
```

Команда:
- Генерирует UUID и fingerprint
- Добавляет пользователя в `xray_config.json` с `flow: xtls-rprx-vision`
- Выводит VLESS URI и QR код
- Создаёт конфиги в `/opt/familytraffic/data/clients/<name>/`

### Показать пользователя

```bash
sudo familytraffic show-user <name>
```

Выводит URI, QR код, SOCKS5/HTTP прокси URI (если прокси включён).

### Список пользователей

```bash
sudo familytraffic list-users
```

### Удалить пользователя

```bash
sudo familytraffic remove-user <name>
```

### Миграция на XTLS Vision

Если на сервере есть пользователи без поля `flow` (созданные до v5.25):

```bash
sudo familytraffic migrate-vision
```

---

## 4. Подключение клиентов

### Получить URI

```bash
sudo familytraffic show-user <name>
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

Прокси использует TLS-терминацию через `familytraffic-nginx`. Нужен домен с сертификатом.

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

Готовые файлы конфигурации для каждого пользователя — в `/opt/familytraffic/data/clients/<name>/`.

---

## 6. Tier 2 транспорты (WS / XHTTP / gRPC)

Tier 2 транспорты используют TLS-терминацию через Nginx http-блок (порт 8448, loopback).
Требуют отдельного поддомена и сертификата для каждого транспорта.

### Архитектура Tier 2

```
Client → TCP:443 → familytraffic-nginx (ssl_preread)
  └─ SNI ws.domain → 127.0.0.1:8448 (http block)
       └─ proxy_pass → familytraffic:8444 (WS plaintext)
```

### Включить транспорт

```bash
sudo familytraffic add-transport ws   ws.yourdomain.com
sudo familytraffic add-transport xhttp xhttp.yourdomain.com
sudo familytraffic add-transport grpc  grpc.yourdomain.com
```

Команда:
- Добавляет inbound в `xray_config.json` (не затрагивает существующих пользователей)
- Обновляет `nginx.conf`: SNI map + http server block
- Перезагружает `familytraffic-nginx` (zero-downtime) и перезапускает `familytraffic`

### Список активных транспортов

```bash
sudo familytraffic list-transports
```

### Отключить транспорт

```bash
sudo familytraffic remove-transport ws
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
sudo familytraffic-proxy add
```

Интерактивный wizard запросит:
- Поддомен (например, `claude.yourdomain.com`)
- Целевой сайт (например, `claude.ai`)
- Email для сертификата

После добавления сайт доступен по `https://claude.yourdomain.com`.

### Управление

```bash
sudo familytraffic-proxy list              # Список всех routes
sudo familytraffic-proxy show <domain>     # Детали конкретного route
sudo familytraffic-proxy remove <domain>   # Удалить route
```

---

## 8. External proxy

External proxy — upstream proxy, через который Xray пробрасывает трафик.

### Server-level: все пользователи через один proxy

```bash
# Добавить proxy
sudo familytraffic-external-proxy add
# Wizard запросит: тип (socks5/http), адрес, порт, credentials

# Активировать
sudo familytraffic-external-proxy switch <proxy-id>
sudo familytraffic-external-proxy enable

# Статус
sudo familytraffic-external-proxy status
```

### Per-user: у каждого пользователя свой proxy

```bash
# Назначить proxy пользователю
sudo familytraffic set-proxy alice proxy-id

# Вернуть на direct routing
sudo familytraffic set-proxy alice none

# Показать назначение
sudo familytraffic show-proxy alice

# Список всех назначений
sudo familytraffic list-proxy-assignments
```

Per-user proxy работает только для VLESS (email-based routing). SOCKS5/HTTP прокси не поддерживают user-based routing.

---

## 9. Обновление сертификатов

Certbot обновляет сертификаты автоматически через `--deploy-hook`. После обновления хук:

1. Валидирует новые файлы сертификата
2. Проверяет здоровье контейнеров `familytraffic-nginx` и `familytraffic`
3. Выполняет `nginx -s reload` (zero-downtime)
4. Перезапускает `familytraffic`

**Принудительное обновление:**
```bash
sudo certbot renew --force-renewal
```

**Ручной вызов хука:**
```bash
RENEWED_DOMAINS="yourdomain.com" sudo /usr/local/bin/familytraffic-cert-renew
```

**Логи:**
```
/opt/familytraffic/logs/certbot-renew.log
/opt/familytraffic/logs/certbot-renew-metrics.json
```

---

## 10. Диагностика

### Статус

```bash
sudo familytraffic status           # Контейнеры, пользователи, прокси, транспорты
docker ps                   # Детальный статус контейнеров
```

### Логи

```bash
sudo familytraffic logs xray        # Xray логи
sudo familytraffic logs nginx       # Nginx логи
sudo familytraffic logs all         # Все логи
docker logs familytraffic --tail 50
docker logs familytraffic-nginx --tail 50
```

### Тесты безопасности

```bash
sudo familytraffic test-security            # Полный набор тестов
sudo familytraffic test-security --quick    # Без packet capture
```

### Проверка конфигурации

```bash
# Nginx
docker exec familytraffic-nginx nginx -t

# Xray JSON
jq empty /opt/familytraffic/config/xray_config.json && echo "OK"

# Порты
sudo ss -tulnp | grep -E '443|1080|8118'
```

### Частые проблемы

**Xray unhealthy — неправильный порт**

Xray должен слушать на `8443`, не `443`. Проверить:
```bash
jq '.inbounds[0].port' /opt/familytraffic/config/xray_config.json  # должно быть 8443
```

**Nginx не запускается**

```bash
docker exec familytraffic-nginx nginx -t  # покажет ошибку в конфиге
docker logs familytraffic-nginx --tail 30
```

**Нет интернета в контейнерах (UFW блокирует Docker)**

```bash
# Проверить
docker exec familytraffic ping -c 1 8.8.8.8

# Исправить — добавить в /etc/ufw/after.rules Docker-цепочки, затем:
sudo ufw reload
```

**Cert renewal падает — familytraffic-nginx не запущен**

```bash
docker start familytraffic-nginx
# Затем повторить:
RENEWED_DOMAINS="domain" sudo familytraffic-cert-renew
```

---

## 11. Удаление

```bash
sudo /opt/familytraffic/scripts/vless-uninstall
```

Создаёт резервную копию в `/tmp/familytraffic_backup_YYYYMMDD/`, затем удаляет:
- `/opt/familytraffic/`
- Docker-контейнеры и volumes
- UFW-правила
- Симлинки в `/usr/local/bin/`

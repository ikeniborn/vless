# Путь пользователя: установка и обновление

**v5.33** · [← README](../README.md)

---

## Содержание

1. [Первичная установка](#1-первичная-установка)
2. [Механика добавления пользователей и обновления конфига](#2-механика-добавления-пользователей-и-обновления-конфига)
3. [Добавление первого пользователя](#3-добавление-первого-пользователя)
4. [Обновление](#4-обновление)
5. [Что переживает обновление](#5-что-переживает-обновление)

---

## 1. Первичная установка

### Шаг 1 — Получить репозиторий на сервер

```bash
git clone <repo-url>
cd familytraffic
sudo bash install.sh
```

---

### Шаг 2 — Автоматические проверки (без диалогов)

Скрипт последовательно:
- Проверяет root-права
- Определяет ОС (Ubuntu 20.04+ / Debian 10+)
- Проверяет зависимости: Docker 24+, Docker Compose v2, certbot, ufw, jq, qrencode

Если зависимости отсутствуют:
```
Missing dependencies: docker, certbot
Install them automatically? [y/N]:
```

---

### Шаг 3 — Обнаружение старой установки

Если найдена `/opt/familytraffic/`:
```
Found existing installation:
  1) Backup + cleanup (recommended)
  2) Cleanup without backup
  3) Exit
```

Для неинтерактивного режима:
```bash
FT_AUTO_CLEANUP=1 sudo bash install.sh   # резервная копия + очистка
FT_AUTO_CLEANUP=2 sudo bash install.sh   # очистка без резервной копии
```

---

### Шаг 4 — Интерактивный сбор параметров

Единственный блок, требующий ввода от пользователя:

**4.1 Сайт-маскировка для Reality**
```
  1) www.google.com:443      (default, recommended)
  2) www.microsoft.com:443
  3) www.apple.com:443
  4) www.cloudflare.com:443
  5) Custom...
```
Скрипт автоматически проверяет TLS 1.3 до выбранного сайта и определяет оптимальные DNS-серверы.

**4.2 Docker subnet**
```
Default: 172.20.0.0/16
```
Скрипт сканирует существующие сети Docker и предлагает свободную подсеть.

**4.3 Публичный SOCKS5/HTTP прокси**
```
Enable public proxy access? [y/N]:
```

**4.4 Домен и email** (только если прокси включён)
```
Domain: proxy.example.com
Email:  admin@example.com
```

**4.5 Подтверждение сводки**
```
Is this configuration correct? [Y/n]:
```

---

### Шаг 5 — Получение TLS-сертификата (только при включённом прокси)

Полностью автоматически:
1. Проверяет, что A-запись домена указывает на IP сервера
2. Открывает порт 80
3. Запускает certbot (Let's Encrypt HTTP-01 challenge)
4. Закрывает порт 80
5. Настраивает cron на ежедневное автопродление
6. Устанавливает deploy hook (`familytraffic-cert-renew`)

---

### Шаг 6 — Оркестрация установки (~2–3 минуты, без диалогов)

```
[1/12]  Creating directory structure...
[1.5/12] Setting initial permissions...
[2/12]  Generating Reality X25519 keys...
[3/12]  Generating Short ID...
[4/12]  Creating Xray configuration...
[5/12]  Creating users.json...
[6/12]  Creating Nginx configuration...
[7/12]  Copying Docker Compose from repo...
[8/12]  Creating .env file...
[9/12]  Docker network: skipped (network_mode: host)
[9.5/12] Setup fail2ban...
[10/12] Configuring UFW firewall...
[11/12] Setting permissions...
[12/12] Deploying containers...
```

Результат — запущен контейнер `familytraffic` (nginx + xray + certbot + supervisord).

---

### Шаг 7 — Вывод итогов

```
Installation complete!
  Config:  /opt/familytraffic/config/
  Data:    /opt/familytraffic/data/

Next steps:
  1. Configure sudoers (see instructions above)
  2. familytraffic add-user <username>
  3. familytraffic status
```

---

## 2. Механика добавления пользователей и обновления конфига

### Два хранилища данных

| Файл | Назначение | Читает |
|------|-----------|--------|
| `data/users.json` | Метаданные: username, uuid, fingerprint, proxy_id | CLI |
| `config/xray_config.json` | inbounds, outbounds, routing rules | Xray |

Это разные файлы. CLI обновляет оба. Xray читает только `xray_config.json`.

### `familytraffic add-user <name>`

```
1. Генерация UUID + shortId
2. UUID → xray_config.json .inbounds[0].users[].id          (jq)
3. shortId → xray_config.json .realitySettings.shortIds[]   (jq)
4. Запись пользователя → users.json
5. Если назначен внешний прокси → routing rules в xray_config.json
6. reload_xray():
     docker compose kill -s HUP xray   ← SIGHUP (hot-reload)
     fallback: docker compose restart xray
```

Xray поддерживает SIGHUP — перечитывает конфиг без разрыва активных соединений.

### `familytraffic remove-user <name>`

Аналогично: удаляет UUID из `xray_config.json`, вызывает SIGHUP.

### `familytraffic set-proxy <user> <proxy-id>`

```
1. users.json: external_proxy_id = "<proxy-id>"  (flock для атомарности)
2. xray_config.json: добавляется outbound с тегом external-proxy-<id>
3. xray_config.json: routing rules — .user: ["<name>"] → outbound external-proxy-<id>
4. ⚠ reload_xray() не вызывается автоматически
```

После `set-proxy` необходим ручной перезапуск:
```bash
sudo docker exec familytraffic supervisorctl restart xray
```

### Монтирование конфигов

```yaml
# docker-compose.yml
volumes:
  - /opt/familytraffic/config/xray_config.json:/etc/xray/config.json:ro
  - /opt/familytraffic/data/users.json:/opt/familytraffic/data/users.json:ro
```

Файлы монтированы read-only. Изменения с хоста видны контейнеру сразу, но Xray перечитывает конфиг только при SIGHUP или рестарте.

### Сводная таблица

| Команда | Изменяет файлы | Reload | Вступает в силу |
|---------|---------------|--------|-----------------|
| `add-user` | xray_config.json + users.json | SIGHUP | Мгновенно |
| `remove-user` | xray_config.json + users.json | SIGHUP | Мгновенно |
| `set-proxy` | xray_config.json + users.json | ручной | После `supervisorctl restart xray` |

---

## 3. Первые шаги после установки

```bash
sudo familytraffic add-user alice
```

Выводит VLESS URI + QR-код. Конфиги сохраняются в `/opt/familytraffic/data/clients/alice/`.

---

## 4. Обновление

### Тестовый сервер — CI/CD (автоматически)

При пуше в ветку `test` с изменениями в `docker/familytraffic/**` или `docker-compose.yml` запускается pipeline:

```
Push → GitHub Actions
  │
  ├─ Job 1: build image
  │    └─ push :test + :sha-abc123 → GHCR
  │
  ├─ Job 2: deploy to test server
  │    ├─ scp docker-compose.yml → /opt/familytraffic/
  │    └─ ssh:
  │         docker pull ghcr.io/.../familytraffic:test
  │         docker compose up -d --remove-orphans
  │         verify: container status == running
  │
  └─ Job 3: cleanup registry
       └─ удалить старые sha-* теги (оставить 3, сохранить :test)
```

Пользователю сервера делать ничего не нужно. Конфиги и данные не затрагиваются — они лежат в смонтированных томах.

---

### Продакшн — вручную

```bash
sudo familytraffic backup              # создать резервную копию
git pull origin master                 # обновить скрипты
sudo bash install.sh                   # переустановить
```

Либо точечно, если изменился только образ контейнера:

```bash
cd /opt/familytraffic
docker pull ghcr.io/OWNER/familytraffic:latest
docker compose up -d --remove-orphans
```

---

## 5. Что переживает обновление

| Что | Путь | Переживает обновление |
|-----|------|-----------------------|
| Пользователи | `data/users.json` | ✓ (том) |
| Xray конфиг | `config/xray_config.json` | ✓ (том) |
| Nginx конфиг | `config/nginx/nginx.conf` | ✓ (том) |
| Reality ключи | `config/keys/` | ✓ (том) |
| TLS сертификаты | `/etc/letsencrypt/` (хост) | ✓ (монтирован) |
| `.env` | `/opt/familytraffic/.env` | ✓ (монтирован) |
| `docker-compose.yml` | `/opt/familytraffic/` | перезаписывается CI/CD |
| Код контейнера | GHCR image | заменяется при `compose up` |

---

## Структура файлов после установки

```
/opt/familytraffic/
├── .env                         # GHCR_IMAGE, VERSION, DOMAIN
├── .version                     # текущая версия (5.33.0)
├── docker-compose.yml           # определение контейнера
├── config/
│   ├── xray_config.json         # inbounds, outbounds, routing
│   ├── nginx/nginx.conf         # stream + http блоки
│   ├── external_proxy.json      # upstream proxies
│   ├── proxy_allowed_ips.json   # IP-whitelist для прокси
│   └── keys/
│       ├── private.key          # Reality X25519 private key
│       └── public.key           # Reality X25519 public key
├── data/
│   ├── users.json               # база пользователей
│   ├── transports.json          # Tier 2 транспорты
│   └── clients/<username>/
│       ├── config.vless         # VLESS URI
│       ├── qr.png               # QR-код
│       ├── proxy.socks5         # SOCKS5 URI
│       └── proxy.http           # HTTP proxy URI
└── logs/
    ├── xray/access.log
    ├── nginx/access.log
    ├── nginx/error.log
    └── certbot-renew.log
```

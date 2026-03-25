# Миграция пользователей при переустановке

**familyTraffic v5.33** · [← GUIDES](GUIDES.md) · [← README](../README.md)

---

## Содержание

1. [Контекст и совместимость](#1-контекст-и-совместимость)
2. [Шаг 1 — Резервное копирование](#2-шаг-1--резервное-копирование)
3. [Шаг 2 — Переустановка](#3-шаг-2--переустановка)
4. [Шаг 3 — Восстановление данных](#4-шаг-3--восстановление-данных)
5. [Шаг 4 — Применение конфига](#5-шаг-4--применение-конфига)
6. [Шаг 5 — Верификация](#6-шаг-5--верификация)
7. [Что не нужно восстанавливать](#7-что-не-нужно-восстанавливать)
8. [Схема users.json](#8-схема-usersjson)

---

## 1. Контекст и совместимость

| | Master (старый) | Test / новая версия |
|---|---|---|
| Архитектура | Multi-container (`vless_xray`, `vless_nginx`, …) | Single-container `familytraffic` |
| Install dir | `/opt/vless/` | `/opt/familytraffic/` |
| CLI | `vless`, `vless-external-proxy`, `mtproxy` | `familytraffic`, `familytraffic-external-proxy`, `familytraffic-mtproxy` |
| users.json | `/opt/vless/data/users.json` | `/opt/familytraffic/data/users.json` |

**Схема `users.json` одинакова в обеих версиях** — миграция данных не требуется, достаточно подстановки файлов.

`UUID` и `shortId` каждого пользователя сохраняются, поэтому клиентские конфиги после переустановки менять не нужно.

Переименование `/opt/vless` → `/opt/familytraffic` автоматически выполняется `install.sh` через `lib/migrate_rename.sh`.

---

## 2. Шаг 1 — Резервное копирование

Выполнить **до** запуска переустановки:

```bash
BACKUP_TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/familytraffic_migration_backup_${BACKUP_TS}"
sudo mkdir -p "${BACKUP_DIR}"

# 1. Пользователи (критично)
sudo cp /opt/familytraffic/data/users.json "${BACKUP_DIR}/users.json"

# 2. xray_config (содержит UUID и shortIds клиентов)
sudo cp /opt/familytraffic/config/xray_config.json "${BACKUP_DIR}/xray_config.json"

# 3. .env (domain, keys, server IP, image tag)
sudo cp /opt/familytraffic/.env "${BACKUP_DIR}/.env"

# 4. MTProxy секреты и конфиг
sudo cp -r /opt/familytraffic/config/mtproxy/ "${BACKUP_DIR}/mtproxy/"

# 5. Per-user proxy assignments
sudo cp /opt/familytraffic/config/external_proxy.json "${BACKUP_DIR}/external_proxy.json" 2>/dev/null || true

# 6. Клиентские конфиги
sudo cp -r /opt/familytraffic/data/clients/ "${BACKUP_DIR}/clients/"

# 7. Let's Encrypt сертификаты
sudo cp -r /etc/letsencrypt/ "${BACKUP_DIR}/letsencrypt/"

echo "Backup: ${BACKUP_DIR}"
sudo ls -la "${BACKUP_DIR}"
```

Проверить перед продолжением:

```bash
sudo jq '.users | length' "${BACKUP_DIR}/users.json"   # ожидаемое кол-во пользователей
sudo jq -r '.users[].username' "${BACKUP_DIR}/users.json"
```

---

## 3. Шаг 2 — Переустановка

```bash
cd /path/to/familytraffic-repo
sudo ./install.sh
```

При обнаружении существующей установки выбрать **"Cleanup without backup"** — backup уже сделан на предыдущем шаге.

---

## 4. Шаг 3 — Восстановление данных

После завершения установки:

```bash
# Подставить свой timestamp
BACKUP_DIR="/opt/familytraffic_migration_backup_<TS>"

# 1. users.json
sudo cp "${BACKUP_DIR}/users.json" /opt/familytraffic/data/users.json
sudo chmod 600 /opt/familytraffic/data/users.json
sudo chown root:root /opt/familytraffic/data/users.json

# 2. xray_config (клиенты + shortIds)
sudo cp "${BACKUP_DIR}/xray_config.json" /opt/familytraffic/config/xray_config.json

# 3. MTProxy секреты и конфиг
sudo cp -r "${BACKUP_DIR}/mtproxy/" /opt/familytraffic/config/mtproxy/

# 4. Per-user proxy assignments
sudo cp "${BACKUP_DIR}/external_proxy.json" /opt/familytraffic/config/external_proxy.json 2>/dev/null || true

# 5. Клиентские конфиги
sudo cp -r "${BACKUP_DIR}/clients/" /opt/familytraffic/data/clients/

# 6. Сертификаты (только если не сохранились)
ls /etc/letsencrypt/live/   # проверить наличие
# Если пусто:
sudo rsync -av "${BACKUP_DIR}/letsencrypt/" /etc/letsencrypt/
```

---

## 5. Шаг 4 — Применение конфига

xray применяет `users.json` по `SIGHUP` без разрыва соединений:

```bash
sudo docker kill --signal=SIGHUP familytraffic
```

---

## 6. Шаг 5 — Верификация

```bash
# Список пользователей
sudo familytraffic list-users

# MTProxy
sudo familytraffic-mtproxy status
sudo familytraffic-mtproxy list-secrets

# Внешние прокси
sudo familytraffic-external-proxy list

# Логи контейнера
sudo docker logs familytraffic --tail=50
```

---

## 7. Что не нужно восстанавливать

| Файл | Причина |
|---|---|
| `nginx.conf` | Генерируется установщиком заново по `.env` |
| `supervisord.conf` | Часть Docker-образа |
| `docker-compose.yml` | Копируется из репозитория установщиком (`create_docker_compose`) |
| UFW-правила | Настраиваются установщиком при install |

---

## 8. Схема users.json

Поля, критичные для сохранения:

```json
{
  "users": [
    {
      "username": "alice",
      "uuid": "...",               // идентификатор в xray — менять нельзя
      "shortId": "...",            // Reality shortId — менять нельзя
      "proxy_password": "...",     // пароль SOCKS5/HTTP прокси
      "fingerprint": "safari",
      "external_proxy_id": null,   // привязка к внешнему прокси
      "connection_type": "both",   // vpn | proxy | both
      "mtproxy_secret": null,
      "mtproxy_secret_type": null,
      "mtproxy_domain": null,
      "created": "...",
      "created_timestamp": ...
    }
  ],
  "metadata": {
    "created": "...",
    "last_modified": "..."
  }
}
```

UUID и shortId не меняются между версиями — клиентские конфиги остаются действительными после переустановки.

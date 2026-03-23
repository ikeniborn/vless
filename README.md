# familyTraffic VPN Server

**v5.33** · Production Ready · MIT License

VLESS + Reality — самодостаточный VPN-сервер с защитой от DPI. Трафик маскируется под TLS 1.3 к легитимному сайту (Google, Cloudflare) и статистически неотличим от обычного HTTPS.

**Возможности:**
- VLESS Reality с XTLS Vision (Tier 1) — основной транспорт, обход DPI
- WebSocket / XHTTP / gRPC (Tier 2) — альтернативные транспорты через CDN
- SOCKS5 + HTTP прокси с TLS — доступ без VPN-клиента
- MTProxy (mtg v2, Fake TLS) — встроенный Telegram-прокси, порт 2053
- Per-user external proxy — индивидуальные цепочки прокси для пользователей
- Let's Encrypt — автоматическое обновление сертификатов

---

## Архитектура

```
Client
  │
  ├─ TCP:443  ──► familytraffic (ssl_preread SNI)
  │                  ├─ Reality clients   ──► 127.0.0.1:8443  (VLESS Reality)
  │                  └─ Tier 2 subdomains ──► port 8448 (http block)
  │                                             ├─► 127.0.0.1:8444 (WebSocket)
  │                                             ├─► 127.0.0.1:8445 (XHTTP)
  │                                             └─► 127.0.0.1:8446 (gRPC)
  │
  ├─ TCP:1080 ──► familytraffic (TLS termination) ──► 127.0.0.1:10800 (SOCKS5)
  ├─ TCP:8118 ──► familytraffic (TLS termination) ──► 127.0.0.1:18118 (HTTP proxy)
  │
  ├─ TCP:2053 ──► familytraffic / mtg v2 (Fake TLS) ──► Telegram DCs  [MTProxy]
  └─ TCP:4443 ──► familytraffic / nginx (LE-cert, cloak) ──► реальный HTTPS [active probing protection]
```

**Контейнер:** `familytraffic` — единый, supervisord управляет процессами:

| Процесс | Приоритет | Описание |
|---|---|---|
| xray | 1 | VLESS Reality, Tier 2, SOCKS5, HTTP proxy |
| nginx | 2 | SNI routing (443), TLS termination, cloak-port (4443) |
| certbot-cron | 3 | Авторенew Let's Encrypt каждые 12 часов |
| mtg | 4 | MTProxy (Fake TLS, порт 2053) — `autostart=true` если включён при установке или `mtproxy setup` |

---

## Требования

| | Минимум | Рекомендовано |
|---|---|---|
| ОС | Ubuntu 20.04, Debian 10 | Ubuntu 22.04 LTS |
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1 GB | 2 GB |
| Диск | 10 GB | 20 GB |

**Обязательно:** публичный IP-адрес, Docker, домен (для TLS-прокси и Tier 2).

---

## Установка

```bash
git clone <repo-url>
cd familytraffic
sudo ./install.sh
```

Установщик интерактивно запросит домен, email, параметры Reality и настроит всё автоматически.

**Детальная инструкция:** [docs/GUIDES.md](docs/GUIDES.md)

---

## Команды

### Пользователи

```
familytraffic add-user <name>          Создать пользователя (выводит QR + URI)
familytraffic remove-user <name>       Удалить пользователя
familytraffic list-users               Список всех пользователей
familytraffic show-user <name>         Показать конфигурацию и QR код
```

### Tier 2 транспорты

```
familytraffic add-transport <type> <subdomain>    Включить транспорт (ws|xhttp|grpc)
familytraffic list-transports                     Список активных транспортов
familytraffic remove-transport <type>             Отключить транспорт
```

### Per-user external proxy

```
familytraffic set-proxy <user> <proxy-id|none>   Назначить proxy пользователю
familytraffic show-proxy <user>                  Показать назначение
familytraffic list-proxy-assignments             Список всех назначений
```

### External proxy (server-level)

```
familytraffic-external-proxy add                 Добавить upstream proxy
familytraffic-external-proxy list                Список proxies
familytraffic-external-proxy status              Статус + пользователи по proxies
```

### Сервис

```
familytraffic status                             Статус контейнера
familytraffic logs [xray|nginx|all]              Логи
familytraffic restart                            Перезапуск
familytraffic test-security [--quick]            Тесты безопасности
```

### MTProxy (Telegram proxy)

Встроенный Telegram-прокси на базе [mtg v2](https://github.com/9seconds/mtg) (Fake TLS).
Можно включить при установке (`install.sh` задаёт вопрос) или позже командой `mtproxy setup`. При включении создаётся `config/supervisord.d/mtg.conf` с `autostart=true` — mtg стартует автоматически при перезапуске контейнера.

**Защита от active probing:** nginx на порту 4443 обслуживает легитимный HTTPS с LE-сертификатом — сканеры видят обычный сайт, а не прокси.

#### Первый запуск

```
sudo mtproxy setup                                    Настроить и включить MTProxy (Fake TLS)
sudo mtproxy setup --fake-domain www.google.com       С явным fake-TLS доменом для маскировки
```

> **`--fake-domain`** — это домен для маскировки трафика, а не домен вашего сервера. mtg притворяется, что устанавливает TLS-соединение с указанным сайтом. Лучше указывать популярный HTTPS-сайт, доступный без ограничений (`www.google.com`, `telegram.org`). Если не указан — используется домен сертификата сервера.

#### Секреты

Секрет типа `ee` содержит: `ee` + 32 hex (случайный ключ) + hex-кодировка fake-домена. Передаётся клиентам через deep link.

```
sudo mtproxy add-secret --fake-domain www.google.com  Добавить ee-секрет с fake-TLS доменом
sudo mtproxy list-secrets                             Список секретов
sudo mtproxy remove-secret <SECRET>                   Удалить секрет
```

#### Управление

```
sudo mtproxy status                            Статус (supervisorctl status mtg)
sudo mtproxy start                             Запустить mtg
sudo mtproxy stop                              Остановить mtg
sudo mtproxy restart                           Перезапустить mtg
sudo mtproxy logs [--tail N] [--follow]        Логи mtg
sudo mtproxy disable                           Отключить MTProxy + закрыть UFW + убрать nginx
```

#### Конфигурация клиента

```
sudo mtproxy show-config <username>            Deep link + параметры подключения
sudo mtproxy generate-qr <username>            QR-код для Telegram
```

> **Порт 4443 (cloak-port)** слушает только на loopback — никогда не открывать в UFW.

---

## Клиентские приложения

| Платформа | Приложение |
|---|---|
| Android | [v2rayNG](https://github.com/2dust/v2rayNG) |
| iOS | v2rayTun, Shadowrocket |
| Windows | [v2rayN](https://github.com/2dust/v2rayN) |
| macOS / Linux | [v2rayA](https://v2raya.org) |

Импортируйте URI из `familytraffic show-user <name>` или отсканируйте QR код.

---

## Документация

- **[docs/GUIDES.md](docs/GUIDES.md)** — полная пошаговая инструкция
- **[docs/user-journey.md](docs/user-journey.md)** — путь пользователя: установка и обновление
- [docs/prd/04_architecture.md](docs/prd/04_architecture.md) — архитектура системы
- [docs/prd/06_appendix.md](docs/prd/06_appendix.md) — troubleshooting
- [CLAUDE.md](CLAUDE.md) — техническая документация для разработчиков

# familyTraffic VPN Server

**v5.33** · Production Ready · MIT License

VLESS + Reality — самодостаточный VPN-сервер с защитой от DPI. Трафик маскируется под TLS 1.3 к легитимному сайту (Google, Cloudflare) и статистически неотличим от обычного HTTPS.

**Возможности:**
- VLESS Reality с XTLS Vision (Tier 1) — основной транспорт, обход DPI
- WebSocket / XHTTP / gRPC (Tier 2) — альтернативные транспорты через CDN
- SOCKS5 + HTTP прокси с TLS — доступ без VPN-клиента
- Per-user external proxy — индивидуальные цепочки прокси для пользователей
- Reverse proxy — доступ к сайтам через поддомены без порта
- Let's Encrypt — автоматическое обновление сертификатов

---

## Архитектура

```
Client
  │
  ├─ TCP:443 ──► familytraffic (ssl_preread SNI)
  │                 ├─ Reality clients  ──► 127.0.0.1:8443  (VLESS Reality)
  │                 └─ Tier 2 subdomains ─► port 8448 (http block)
  │                                           ├─► 127.0.0.1:8444 (WebSocket)
  │                                           ├─► 127.0.0.1:8445 (XHTTP)
  │                                           └─► 127.0.0.1:8446 (gRPC)
  │
  ├─ TCP:1080 ─► familytraffic (TLS termination) ──► 127.0.0.1:10800 (SOCKS5)
  └─ TCP:8118 ─► familytraffic (TLS termination) ──► 127.0.0.1:18118 (HTTP proxy)
```

**Контейнер:** `familytraffic` (единый контейнер: nginx + xray + certbot + supervisord)

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
- [docs/prd/04_architecture.md](docs/prd/04_architecture.md) — архитектура системы
- [docs/prd/06_appendix.md](docs/prd/06_appendix.md) — troubleshooting
- [CLAUDE.md](CLAUDE.md) — техническая документация для разработчиков

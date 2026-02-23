# VLESS + Reality VPN Server

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
  ├─ TCP:443 ──► vless_nginx (ssl_preread SNI)
  │                 ├─ Reality clients  ──► vless_xray:8443  (VLESS Reality)
  │                 └─ Tier 2 subdomains ─► port 8448 (http block)
  │                                           ├─► vless_xray:8444 (WebSocket)
  │                                           ├─► vless_xray:8445 (XHTTP)
  │                                           └─► vless_xray:8446 (gRPC)
  │
  ├─ TCP:1080 ─► vless_nginx (TLS termination) ──► vless_xray:10800 (SOCKS5)
  └─ TCP:8118 ─► vless_nginx (TLS termination) ──► vless_xray:18118 (HTTP proxy)
```

**Контейнеры:** `vless_nginx` · `vless_xray` · `vless_fake_site`

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
cd vless
sudo ./install.sh
```

Установщик интерактивно запросит домен, email, параметры Reality и настроит всё автоматически.

**Детальная инструкция:** [docs/GUIDES.md](docs/GUIDES.md)

---

## Команды

### Пользователи

```
vless add-user <name>          Создать пользователя (выводит QR + URI)
vless remove-user <name>       Удалить пользователя
vless list-users               Список всех пользователей
vless show-user <name>         Показать конфигурацию и QR код
```

### Tier 2 транспорты

```
vless add-transport <type> <subdomain>    Включить транспорт (ws|xhttp|grpc)
vless list-transports                     Список активных транспортов
vless remove-transport <type>             Отключить транспорт
```

### Per-user external proxy

```
vless set-proxy <user> <proxy-id|none>   Назначить proxy пользователю
vless show-proxy <user>                  Показать назначение
vless list-proxy-assignments             Список всех назначений
```

### External proxy (server-level)

```
vless-external-proxy add                 Добавить upstream proxy
vless-external-proxy list                Список proxies
vless-external-proxy status              Статус + пользователи по proxies
```

### Reverse proxy

```
vless-proxy add                          Добавить reverse proxy (wizard)
vless-proxy list                         Список routes
vless-proxy remove <domain>              Удалить route
```

### Сервис

```
vless status                             Статус всех контейнеров
vless logs [xray|nginx|all]              Логи
vless restart                            Перезапуск
vless test-security [--quick]            Тесты безопасности
vless migrate-vision                     Миграция пользователей на XTLS Vision
```

---

## Клиентские приложения

| Платформа | Приложение |
|---|---|
| Android | [v2rayNG](https://github.com/2dust/v2rayNG) |
| iOS | v2rayTun, Shadowrocket |
| Windows | [v2rayN](https://github.com/2dust/v2rayN) |
| macOS / Linux | [v2rayA](https://v2raya.org) |

Импортируйте URI из `vless show-user <name>` или отсканируйте QR код.

---

## Документация

- **[docs/GUIDES.md](docs/GUIDES.md)** — полная пошаговая инструкция
- [docs/prd/04_architecture.md](docs/prd/04_architecture.md) — архитектура системы
- [docs/prd/06_appendix.md](docs/prd/06_appendix.md) — troubleshooting
- [CLAUDE.md](CLAUDE.md) — техническая документация для разработчиков

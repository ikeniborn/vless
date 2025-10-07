# Proxy URI Scheme Fix

## Проблема

Конфигурация генерации proxy URI использовала неправильные схемы для публичного режима с TLS:
- HTTP proxy использовал `http://` вместо `https://`
- SOCKS5 proxy использовал `socks5://` вместо `socks5s://`

Это приводило к тому, что клиентские приложения не могли подключиться к прокси через TLS.

## Решение

Обновлены следующие функции в `lib/user_management.sh`:

### 1. export_http_config (строка 994)
**Было:**
```bash
scheme="http"  # HTTP CONNECT protocol (TLS provided by stunnel on transport layer)
```

**Стало:**
```bash
scheme="https"  # HTTPS proxy with TLS (stunnel provides TLS termination)
```

### 2. export_socks5_config (строка 1000)
**Было:**
```bash
scheme="socks5"  # SOCKS5 protocol (TLS provided by stunnel on transport layer)
```

**Стало:**
```bash
scheme="socks5s"  # SOCKS5 with TLS (stunnel provides TLS termination)
```

### 3. show_proxy_credentials (строки 694-760)
Полностью переписана для корректного определения схем на основе режима работы:
- Добавлено определение `ENABLE_PUBLIC_PROXY` и `DOMAIN` из .env файла
- Динамически выбираются схемы: `http/https` и `socks5/socks5s`
- Динамически выбирается host: `127.0.0.1` или `${DOMAIN}`
- Улучшен вывод с указанием режима работы

### 4. reset_proxy_password (строки 889-934)
Аналогично обновлена для корректного отображения URI после сброса пароля.

## Результат

### Localhost режим (ENABLE_PUBLIC_PROXY=false):
```
HTTP:   http://username:password@127.0.0.1:8118
SOCKS5: socks5://username:password@127.0.0.1:1080
```

### Публичный режим с TLS (ENABLE_PUBLIC_PROXY=true):
```
HTTP:   https://username:password@domain:8118
SOCKS5: socks5s://username:password@domain:1080
```

## Тестирование

Создан тестовый скрипт `tests/test_proxy_uri_generation.sh`, который проверяет:
1. ✓ Localhost режим (http, socks5)
2. ✓ Публичный режим с TLS (https, socks5s)
3. ✓ VSCode конфигурация
4. ✓ Docker конфигурация
5. ✓ Bash конфигурация

Все тесты проходят успешно.

## Совместимость

Изменения обратно совместимы:
- Функции export_vscode_config, export_docker_config, export_bash_config, export_git_config уже использовали правильные схемы
- Функция regenerate_configs уже использовала правильные схемы
- Обновление затронуло только функции генерации базовых proxy URI

## Дата
2025-10-07

## Версия
v4.1 (Proxy URI Scheme Fix)

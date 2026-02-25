# Plan: Drop Generator + Remove Reverse Proxy + CI/CD Cleanup

## Context

Три задачи по упрощению проекта после перехода на v5.33 (single-container):

1. **docker_compose_generator.sh → статический файл**: `docker-compose.yml` уже хранится в репозитории и доставляется CI/CD через scp. Генерация во время установки избыточна. Статический файл лучше контролируется через git diff.

2. **Полное удаление reverse proxy**: Функциональность `familytraffic-proxy` / `familytraffic-setup-proxy` / `reverseproxy_db` была заявлена как задача рефакторинга. Scripts уже переименованы, но не удалены.

3. **CI/CD**: Текущий триггер — только `pull_request` на ветку `test`. Нужно: push в `test` (без PR) + path-фильтр + очистка старых образов (хранить 3 последних).

---

## Task 1: Replace docker_compose_generator → static cp

### Файлы к удалению
- `lib/docker_compose_generator.sh` — весь файл
- `lib/docker_compose_manager.sh` — HAProxy-эра, динамическое управление портами nginx_reverseproxy

### Изменения в `lib/orchestrator.sh`

**Строка 29** — убрать source:
```diff
-[[ -f "${SCRIPT_DIR_LIB}/docker_compose_generator.sh" ]] && source "${SCRIPT_DIR_LIB}/docker_compose_generator.sh"
```

**Функция `create_docker_compose()` (≈1134–1176)** — заменить вызов `generate_docker_compose` на `cp`:
```bash
create_docker_compose() {
    echo -e "${CYAN}[7/12] Copying Docker Compose configuration from repo...${NC}"

    local compose_src="${SCRIPT_DIR_LIB}/../docker-compose.yml"
    if [[ ! -f "${compose_src}" ]]; then
        echo -e "${RED}Source docker-compose.yml not found: ${compose_src}${NC}" >&2
        return 1
    fi

    cp "${compose_src}" "${DOCKER_COMPOSE_FILE}" || {
        echo -e "${RED}Failed to copy docker-compose.yml${NC}" >&2
        return 1
    }

    echo "  ✓ Docker Compose file: ${DOCKER_COMPOSE_FILE} (from repo)"
    echo -e "${GREEN}✓ Docker Compose configuration copied${NC}"
    return 0
}
```

**Строка 1143** — убрать комментарий про docker_compose_manager.

---

## Task 2: Remove reverse proxy completely

### 2a. Файлы к удалению (git rm)

| Файл | Причина |
|------|---------|
| `scripts/familytraffic-proxy` | Reverse proxy CLI |
| `scripts/familytraffic-setup-proxy` | Reverse proxy setup |
| `scripts/familytraffic-monitor-reverse-proxy-ips` | Мониторинг IP reverseproxy |
| `scripts/familytraffic-install-ip-monitoring` | Установка мониторинга |
| `lib/reverseproxy_db.sh` | База данных доменов reverse proxy |
| `lib/nginx_config_generator.sh` | Все 6 функций — только reverseproxy (generate_reverseproxy_nginx_config, generate_reverseproxy_http_context, add_rate_limit_zone, remove_reverseproxy_config, validate_nginx_config, reload_nginx) |
| `tests/integration/v4.3/test_03_reverse_proxy_subdomain.sh` | Тест reverse proxy |

### 2b. Изменения в `lib/orchestrator.sh`

1. **Строка 68** — удалить константу `NGINX_CONTAINER_NAME="familytraffic-nginx"`
2. **Строки 208–219** (Step 6.3) — удалить блок `ENABLE_REVERSE_PROXY → nginx_config_generator → generate_reverseproxy_http_context`
3. **Строка 354** — удалить `directories+=("${CONFIG_DIR}/reverse-proxy")`
4. **Строка 1212** — удалить `ENABLE_REVERSE_PROXY=${ENABLE_REVERSE_PROXY:-false}`
5. **Строки 1541–1587** — удалить блок установки symlink-ов для `familytraffic-proxy` и `familytraffic-setup-proxy`
6. **Строка 1939** — проверить и убрать `export -f create_docker_compose` (после задачи 1)

### 2c. Изменения в `lib/interactive_params.sh`

- Строка 30: удалить `export ENABLE_REVERSE_PROXY=""`
- Удалить функцию `ask_reverse_proxy()` (строки ~800–886) — спрашивает пользователя про reverse proxy
- Удалить вызов `ask_reverse_proxy` из основного flow (строка ~597 — display status)
- Убрать строки отображения статуса reverse proxy (~598–599)

### 2d. Изменения в `lib/nginx_stream_generator.sh`

Удалить две функции (строки 53–138):
- `add_reverse_proxy_route()` — добавление SNI-маршрута
- `remove_reverse_proxy_route()` — удаление SNI-маршрута

Оставить: `generate_nginx_config()` (строка 139+) — используется активно.

### 2e. Изменения в `lib/fail2ban_config.sh`

Функции-заглушки для reverseproxy уже созданы в предыдущем рефакторинге.
Проверить и удалить тело заглушек + сами функции если они только для reverseproxy:
- `create_haproxy_filter()` → удалить
- `setup_haproxy_jail()` → удалить
- `check_haproxy_jail_status()` → удалить
- `setup_haproxy_fail2ban()` → удалить

---

## Task 3: CI/CD — trigger + registry cleanup

### Файл: `.github/workflows/build-and-push.yml`

**1. Изменить triggers** — добавить `push` на ветку `test` с теми же path-фильтрами:

```yaml
on:
  push:
    branches:
      - test
    paths:
      - "docker/familytraffic/**"
      - "docker-compose.yml"
      - "lib/nginx_stream_generator.sh"
      - ".github/workflows/build-and-push.yml"
  pull_request:
    branches:
      - test
    paths:
      - "docker/familytraffic/**"
      - "docker-compose.yml"
      - "lib/nginx_stream_generator.sh"
      - ".github/workflows/build-and-push.yml"
  workflow_dispatch:
```

**2. Добавить job `cleanup-registry`** после `build-and-push`:

```yaml
cleanup-registry:
  name: Cleanup Old Images (keep 3)
  runs-on: ubuntu-latest
  needs: build-and-push
  permissions:
    packages: write
  steps:
    - name: Delete old versions (keep 3 latest sha-* tags)
      uses: actions/delete-package-versions@v5
      with:
        package-name: familytraffic
        package-type: container
        min-versions-to-keep: 3
        ignore-versions: '^test$'
```

`ignore-versions: '^test$'` — никогда не удалять тег `:test`.
`min-versions-to-keep: 3` — хранить 3 самых свежих версии (sha-*).

**Требуется:** `secrets.GITHUB_TOKEN` уже есть с правами `packages: write` в job `build-and-push`. Для `cleanup-registry` нужно добавить `packages: write` permissions.

---

## Критические файлы

| Файл | Тип изменения |
|------|--------------|
| `lib/orchestrator.sh` | Modify (несколько блоков) |
| `lib/interactive_params.sh` | Modify (удалить функцию + переменную) |
| `lib/nginx_stream_generator.sh` | Modify (удалить 2 функции) |
| `lib/fail2ban_config.sh` | Modify (удалить reverseproxy-stubs) |
| `lib/docker_compose_generator.sh` | Delete |
| `lib/docker_compose_manager.sh` | Delete |
| `lib/nginx_config_generator.sh` | Delete |
| `lib/reverseproxy_db.sh` | Delete |
| `scripts/familytraffic-proxy` | Delete |
| `scripts/familytraffic-setup-proxy` | Delete |
| `scripts/familytraffic-monitor-reverse-proxy-ips` | Delete |
| `scripts/familytraffic-install-ip-monitoring` | Delete |
| `tests/integration/v4.3/test_03_reverse_proxy_subdomain.sh` | Delete |
| `.github/workflows/build-and-push.yml` | Modify (triggers + new job) |

---

## Верификация

1. `bash -n lib/orchestrator.sh` — синтаксис после изменений
2. `bash -n lib/interactive_params.sh` — синтаксис
3. `bash -n lib/nginx_stream_generator.sh` — синтаксис
4. `grep -r "familytraffic-proxy\|familytraffic-setup-proxy\|ENABLE_REVERSE_PROXY\|reverseproxy_db\|nginx_config_generator\|docker_compose_generator\|docker_compose_manager" lib/ scripts/` — не должно быть активных ссылок
5. `git diff --stat` — убедиться в удалении всех нужных файлов
6. Push commit в `test` ветку → проверить что CI запустился (не только через PR)

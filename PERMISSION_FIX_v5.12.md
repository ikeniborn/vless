# VLESS v5.12 - Permission Fix для Xray Container

**Дата:** 2025-10-21
**Версия:** v5.12
**Тип:** CRITICAL FIX - Xray Container Permission Denied

## Проблема

После переустановки системы контейнер `vless_xray` не мог запуститься из-за ошибки:

```
Failed to start: main: failed to load config files: [/etc/xray/config.json] >
infra/conf/serial: failed to read config: &{Name:/etc/xray/config.json Format:json} >
open /etc/xray/config.json: permission denied
```

### Корневая причина

В функции `set_permissions()` (lib/orchestrator.sh:1481) директория `/opt/vless/config/` получала права `700`, что блокировало доступ контейнеров к файлам конфигурации:

```bash
# СТАРЫЙ КОД (ПРОБЛЕМА):
for sensitive_dir in "${CONFIG_DIR}" "${DATA_DIR}" ...; do
    chmod 700 "$sensitive_dir"  # ← CONFIG_DIR получал 700!
done
```

Это приводило к:
1. Директория `/opt/vless/config/`: `drwx------` (700) - недоступна для чтения контейнерам
2. Файл `/opt/vless/config/xray_config.json`: `rw-------` (600) - недоступен для чтения
3. Контейнер Xray (uid=65534) не мог прочитать конфигурацию
4. Контейнер постоянно перезагружался (crash loop)
5. HAProxy не мог резолвить `vless_xray` (контейнер не в сети)

### Последствия

- ❌ Контейнер `vless_xray` в состоянии "Restarting"
- ❌ Нет VPN доступа для клиентов
- ❌ HAProxy ошибки: `could not resolve address 'vless_xray'`
- ❌ SOCKS5/HTTP прокси не работают
- ❌ Невозможно добавить reverse proxy

## Решение

### Изменения в lib/orchestrator.sh

#### 1. Функция `set_permissions()` (строка 1479)

**Было:**
```bash
# Sensitive directories: 700 (root only)
for sensitive_dir in "${CONFIG_DIR}" "${DATA_DIR}" ...; do
    if [[ -d "$sensitive_dir" ]]; then
        chmod 700 "$sensitive_dir" 2>/dev/null || true
    fi
done
```

**Стало:**
```bash
# Sensitive directories: 700 (root only)
# EXCEPTION: CONFIG_DIR must be 755 to allow container users to read files inside
for sensitive_dir in "${DATA_DIR}" "${DATA_DIR}/clients" ...; do
    if [[ -d "$sensitive_dir" ]]; then
        chmod 700 "$sensitive_dir" 2>/dev/null || true
    fi
done

# CONFIG_DIR and subdirectories: 755 (readable by container users)
# This allows Xray (uid=65534) and HAProxy (uid=99) containers to read config files
if [[ -d "${CONFIG_DIR}" ]]; then
    chmod 755 "${CONFIG_DIR}" 2>/dev/null || true
fi
if [[ -d "${CONFIG_DIR}/reverse-proxy" ]]; then
    chmod 755 "${CONFIG_DIR}/reverse-proxy" 2>/dev/null || true
fi
```

#### 2. Функция `verify_file_permissions()` (строка 1596)

**Добавлена проверка прав на директорию:**
```bash
# Check CONFIG_DIR directory permissions (CRITICAL)
if [[ -d "${CONFIG_DIR}" ]]; then
    local config_dir_perms=$(stat -c '%a' "${CONFIG_DIR}" 2>/dev/null || echo "000")
    if [[ "$config_dir_perms" == "755" ]]; then
        echo -e "  ${GREEN}✓ config directory: 755 (OK)${NC}"
    else
        echo -e "  ${RED}✗ CRITICAL: config directory: $config_dir_perms (EXPECTED 755)${NC}"
        echo -e "  ${RED}  → Containers cannot read config files (permission denied)${NC}"
        echo -e "  ${YELLOW}  → Manual fix: sudo chmod 755 ${CONFIG_DIR}${NC}"
        ((ISSUES++))
    fi
fi
```

### Правильные права после установки

```
/opt/vless/config/                         drwxr-xr-x (755) root:root
/opt/vless/config/xray_config.json         -rw-r--r-- (644) root:root
/opt/vless/config/haproxy.cfg              -rw-r--r-- (644) root:root
/opt/vless/config/reverse-proxy/           drwxr-xr-x (755) root:root
```

## Ручное исправление (для существующих установок)

Если вы столкнулись с этой проблемой на уже установленной системе:

```bash
# 1. Исправить права на директорию config
sudo chmod 755 /opt/vless/config/
sudo chmod 755 /opt/vless/config/reverse-proxy/

# 2. Исправить права на конфигурационные файлы
sudo chmod 644 /opt/vless/config/xray_config.json
sudo chmod 644 /opt/vless/config/haproxy.cfg

# 3. Перезапустить контейнеры
docker restart vless_xray
docker restart vless_haproxy

# 4. Проверить статус
docker ps --filter "name=vless" --format "table {{.Names}}\t{{.Status}}"

# 5. Проверить логи
docker logs vless_xray --tail 20
```

## Автоматическая проверка

После исправления установка будет автоматически проверять права и выдавать ошибки если они неправильные:

```bash
[12/14] Verifying critical file permissions...
  ✓ config directory: 755 (OK)
  ✓ xray_config.json: 644 (OK)
  ✓ haproxy.cfg: 644 (OK)
```

Если проверка не прошла:
```bash
  ✗ CRITICAL: config directory: 700 (EXPECTED 755)
  → Containers cannot read config files (permission denied)
  → Manual fix: sudo chmod 755 /opt/vless/config
```

## Тестирование

После исправления все компоненты работают:

```bash
# Статус контейнеров
$ docker ps --filter "name=vless"
vless_xray                 Up X minutes (healthy)
vless_haproxy              Up X minutes
vless_nginx_reverseproxy   Up X minutes (healthy)
vless_fake_site            Up X minutes

# Docker сеть
$ docker network inspect vless_reality_net
vless_xray: 172.22.0.3/16  ✓

# Доступность портов из HAProxy
$ docker exec vless_haproxy nc -zv vless_xray 8443
vless_xray (172.22.0.3:8443) open ✓

# Доступ к интернету из Xray
$ docker exec vless_xray ping -c 1 8.8.8.8
64 bytes from 8.8.8.8: seq=0 ttl=42 time=7.038 ms ✓
```

## Обновление документации

- **CLAUDE.md** - добавлен Issue 6 в раздел Common Issues
- **CHANGELOG.md** - добавлена версия v5.12 с описанием исправления

## Связанные проблемы

Это исправление решает следующие ошибки:

1. **HAProxy logs**: `could not resolve address 'vless_xray'`
2. **Xray logs**: `permission denied` при чтении config.json
3. **Docker status**: `vless_xray` в состоянии "Restarting"
4. **Reverse proxy**: не может быть добавлен (HAProxy reload fails)
5. **VPN clients**: нет доступа к интернету

## Версионность

- **v5.11 и ранее**: Проблема присутствует
- **v5.12**: Проблема исправлена

**Рекомендация**: Обновите lib/orchestrator.sh на всех существующих установках.

---

**END OF PERMISSION FIX v5.12**

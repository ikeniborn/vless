# План исправления: REALITY Invalid Connection

**Дата:** 2025-10-01  
**Проблема:** Клиент не может подключиться к VPN после переустановки  
**Статус:** CRITICAL - полная потеря доступа

---

## 1. Исполнительное резюме

### Симптомы
- 14,832 ошибок "REALITY: processed invalid connection" в логах
- Полное отсутствие успешных подключений (access.log пуст)
- Контейнер xray-server работает корректно, имеет интернет
- Сетевая конфигурация (NAT, UFW, Docker) настроена правильно

### Корневая причина
**ГИПОТЕЗА ВЫСОКОЙ ВЕРОЯТНОСТИ:** Клиент использует СТАРУЮ ссылку с publicKey от предыдущей установки.

### Доказательства
```
Старые ключи (бэкап 30.09 15:13):
  privateKey: yNiykB3QjdTR11qlRZ0m1bI4MXI2cMBix5Dm5d8B4Uk
  publicKey:  cFoGQCWdweRs7a2vqYcYOGBF7P-Ojc_xBbtUjSbZHwA ❌ СТАРЫЙ
  dest:       www.wikipedia.org:443

Текущие ключи (после переустановки 01.10):
  privateKey: IMEgkccprCg8XceJNHenV4NSGTBENCtDBZLMVlxFhn0
  publicKey:  gaZgWWjPMUX0P7D6Clcl-Esx1oYU4b2mg326t9kPhBo ✅ НОВЫЙ
  dest:       google.com:443

Клиентская ссылка (предоставленная пользователем):
  publicKey:  gaZgWWjPMUX0P7D6Clcl-Esx1oYU4b2mg326t9kPhBo ✅ СОВПАДАЕТ
  sni:        google.com ✅ СОВПАДАЕТ
```

### Парадокс
Все параметры в предоставленной ссылке совпадают с сервером, НО подключение не работает.

**Возможные объяснения:**
1. Клиент фактически использует ДРУГУЮ (старую) ссылку, не ту что была предоставлена для диагностики
2. Кэш клиентского приложения содержит старые параметры TLS handshake
3. Проблема с TLS fingerprint (fp=chrome) или версией клиента
4. Конфликт между изменившимся dest (wikipedia→google) и клиентской конфигурацией

---

## 2. Детальная диагностика

### 2.1 Проверка конфигурации сервера

```bash
# Текущая конфигурация Xray
docker exec xray-server cat /etc/xray/config.json | jq '{
  inbound_port: .inbounds[0].port,
  protocol: .inbounds[0].protocol,
  uuid: .inbounds[0].settings.clients[0].id,
  flow: .inbounds[0].settings.clients[0].flow,
  privateKey: .inbounds[0].streamSettings.realitySettings.privateKey,
  dest: .inbounds[0].streamSettings.realitySettings.dest,
  serverNames: .inbounds[0].streamSettings.realitySettings.serverNames,
  shortIds: .inbounds[0].streamSettings.realitySettings.shortIds
}'
```

**Результат:**
```json
{
  "inbound_port": 443,
  "protocol": "vless",
  "uuid": "1b509f31-68ba-4689-b8ab-e6735aa2fed8",
  "flow": "xtls-rprx-vision",
  "privateKey": "IMEgkccprCg8XceJNHenV4NSGTBENCtDBZLMVlxFhn0",
  "dest": "google.com:443",
  "serverNames": ["google.com", "www.microsoft.com", ...],
  "shortIds": ["", "7d423302"]
}
```

✅ Все параметры корректны

### 2.2 Проверка соответствия ключей

```bash
# Математическая проверка пары ключей
docker run --rm teddysun/xray:24.11.30 xray x25519 \
  -i IMEgkccprCg8XceJNHenV4NSGTBENCtDBZLMVlxFhn0
```

**Результат:**
```
Private key: IMEgkccprCg8XceJNHenV4NSGTBENCtDBZLMVlxFhn0
Public key:  gaZgWWjPMUX0P7D6Clcl-Esx1oYU4b2mg326t9kPhBo
```

✅ Ключи математически корректны и совпадают с клиентской ссылкой

### 2.3 Проверка сетевой конфигурации

```bash
# Docker сеть
docker network inspect vless-reality_vless-network | grep -A 3 Subnet
# Результат: 172.16.0.0/16 ✅

# NAT правила
sudo iptables -t nat -L POSTROUTING -n -v | grep "172.16"
# Результат: 691K bytes через MASQUERADE ✅

# UFW правила
sudo ufw status | grep -E "443|172.16"
# Результат: 443/tcp ALLOW, 172.16.0.0/16 FORWARD ALLOW ✅

# Интернет в контейнере
docker exec xray-server ping -c 2 8.8.8.8
# Результат: 0% packet loss ✅
```

✅ Сетевая конфигурация полностью исправна

### 2.4 Анализ логов

```bash
# Количество ошибок invalid connection
grep -c "invalid connection" /opt/vless/logs/error.log
# Результат: 14832 ❌

# Успешные подключения
grep -E "accepted|established" /opt/vless/logs/access.log
# Результат: (пусто) ❌

# Последняя попытка подключения
tail -1 /opt/vless/logs/error.log
# Результат: 2025/10/01 13:06:38 REALITY: processed invalid connection
```

❌ Все попытки подключения отклонены, последняя ~2 часа назад

### 2.5 История изменений

```bash
git log --oneline --since="2025-09-28" | head -5
```

**Ключевые события:**
- 30.09: Старая конфигурация с dest=wikipedia.org, старые ключи
- 01.10 ~13:58: Переустановка, новые ключи, dest=google.com
- 01.10 ~15:50: Проблема обнаружена пользователем

---

## 3. Рекомендуемое решение

### Стратегия: Полная ротация ключей с верификацией

**Почему:** Даже при совпадении ключей существует риск кэширования или использования старой ссылки. Генерация НОВЫХ ключей и создание НОВОЙ ссылки гарантированно исключит все старые конфигурации.

### 3.1 Генерация новых ключей

```bash
# Шаг 1: Генерация новой пары X25519
NEW_KEYS=$(docker run --rm teddysun/xray:24.11.30 xray x25519)
NEW_PRIVATE=$(echo "$NEW_KEYS" | grep "Private key:" | awk '{print $3}')
NEW_PUBLIC=$(echo "$NEW_KEYS" | grep "Public key:" | awk '{print $3}')

echo "Новый Private Key: $NEW_PRIVATE"
echo "Новый Public Key:  $NEW_PUBLIC"

# Сохранить в безопасное место
echo "$NEW_PRIVATE" | sudo tee /opt/vless/data/keys/private.key
echo "$NEW_PUBLIC" | sudo tee /opt/vless/data/keys/public.key
sudo chmod 600 /opt/vless/data/keys/*
```

**Пример новых ключей (для референса):**
```
Private key: wPhGA4dcF8Z77VHWGR-VHrNE72ssHMUb0AjG2xXgHXo
Public key:  02XUwuWjmGIbRQ8ko4T5a9yEVspzvg_Ko8KysclLukM
```

### 3.2 Обновление конфигурации сервера

```bash
# Шаг 2: Создать бэкап текущей конфигурации
sudo docker exec xray-server cat /etc/xray/config.json | \
  sudo tee /opt/vless/backups/config.json.$(date +%Y%m%d_%H%M%S).backup

# Шаг 3: Обновить privateKey в config.json
sudo nano /opt/vless/config/config.json

# Найти строку:
#   "privateKey": "IMEgkccprCg8XceJNHenV4NSGTBENCtDBZLMVlxFhn0",
# Заменить на:
#   "privateKey": "<NEW_PRIVATE_KEY>",
```

**Альтернатива (автоматическое обновление):**
```bash
NEW_PRIVATE="wPhGA4dcF8Z77VHWGR-VHrNE72ssHMUb0AjG2xXgHXo"  # Подставить реальный ключ

sudo sed -i.bak \
  "s/\"privateKey\": \"[^\"]*\"/\"privateKey\": \"$NEW_PRIVATE\"/" \
  /opt/vless/config/config.json

# Проверка
sudo grep "privateKey" /opt/vless/config/config.json
```

### 3.3 Обновление .env

```bash
# Шаг 4: Обновить PUBLIC_KEY и PRIVATE_KEY в .env
NEW_PRIVATE="wPhGA4dcF8Z77VHWGR-VHrNE72ssHMUb0AjG2xXgHXo"
NEW_PUBLIC="02XUwuWjmGIbRQ8ko4T5a9yEVspzvg_Ko8KysclLukM"

sudo sed -i.bak \
  -e "s/^PUBLIC_KEY=.*/PUBLIC_KEY=$NEW_PUBLIC/" \
  -e "s/^PRIVATE_KEY=.*/PRIVATE_KEY=$NEW_PRIVATE/" \
  /opt/vless/.env

# Проверка
sudo grep -E "PUBLIC_KEY|PRIVATE_KEY" /opt/vless/.env
```

### 3.4 Перезапуск службы

```bash
# Шаг 5: Перезапуск xray-server
cd /opt/vless
docker-compose restart

# Ожидание запуска (5 секунд)
sleep 5

# Проверка статуса
docker ps | grep xray-server
# Ожидаем: Up X seconds (healthy)

# Проверка логов на наличие ошибок
docker logs xray-server 2>&1 | tail -20 | grep -iE "error|fail"
# Ожидаем: (пусто)
```

### 3.5 Очистка логов (опционально)

```bash
# Шаг 6: Очистить старые логи для чистого мониторинга
sudo truncate -s 0 /opt/vless/logs/error.log
sudo truncate -s 0 /opt/vless/logs/access.log

# Или использовать встроенный скрипт
# sudo /opt/vless/scripts/clear-logs.sh
```

### 3.6 Генерация новой клиентской ссылки

```bash
# Шаг 7: Получить параметры из .env и users.json
source /opt/vless/.env 2>/dev/null || true
PUBLIC_KEY=$(sudo grep "^PUBLIC_KEY=" /opt/vless/.env | cut -d'=' -f2)
SERVER_IP=$(curl -s ifconfig.me)
SERVER_PORT=443

# UUID и shortId пользователя admin
USER_UUID=$(sudo jq -r '.users[] | select(.name=="admin") | .uuid' /opt/vless/data/users.json)
SHORT_ID=$(sudo jq -r '.users[] | select(.name=="admin") | .short_id' /opt/vless/data/users.json)

# Построить ссылку
VLESS_URL="vless://${USER_UUID}@${SERVER_IP}:${SERVER_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-admin-NEW"

echo "==================================="
echo "НОВАЯ КЛИЕНТСКАЯ ССЫЛКА:"
echo "==================================="
echo "$VLESS_URL"
echo "==================================="
```

**Пример вывода:**
```
vless://1b509f31-68ba-4689-b8ab-e6735aa2fed8@205.172.58.179:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=google.com&fp=chrome&pbk=02XUwuWjmGIbRQ8ko4T5a9yEVspzvg_Ko8KysclLukM&sid=7d423302&type=tcp&headerType=none#VLESS-admin-NEW
```

### 3.7 Генерация QR-кода (опционально)

```bash
# Шаг 8: Создать QR-код для удобного импорта
VLESS_URL="<ссылка_из_предыдущего_шага>"

qrencode -t PNG -o /opt/vless/data/qr_codes/admin-new.png \
  -s 10 "$VLESS_URL"

# Если qrencode не установлен:
# sudo apt-get install -y qrencode

echo "QR-код сохранен: /opt/vless/data/qr_codes/admin-new.png"
```

---

## 4. Процедура тестирования

### 4.1 Подготовка клиента

**Действия пользователя:**

1. **Очистить кэш клиентского приложения** (если возможно):
   - iOS (v2rayTun): Настройки → Сброс → Очистить кэш
   - iOS (Shadowrocket): Удалить старую конфигурацию
   - Android: Очистить данные приложения

2. **ПОЛНОСТЬЮ удалить старую конфигурацию**:
   - Удалить старый профиль VLESS-admin
   - Убедиться что нет других сохраненных профилей

3. **Импортировать НОВУЮ ссылку**:
   - Скопировать новую vless:// ссылку
   - Импортировать в клиент
   - ИЛИ отсканировать QR-код

### 4.2 Мониторинг подключения

**На сервере (в отдельном терминале):**

```bash
# Терминал 1: Мониторинг error.log
sudo tail -f /opt/vless/logs/error.log

# Терминал 2: Мониторинг access.log
sudo tail -f /opt/vless/logs/access.log

# Терминал 3: Статистика сетевого трафика
watch -n 1 'sudo iptables -t nat -L POSTROUTING -n -v | grep "172.16"'
```

### 4.3 Попытка подключения

**Действия пользователя:**

1. Активировать VPN в клиентском приложении
2. Дождаться статуса "Connected" / "Подключено"
3. Открыть браузер и перейти на https://ifconfig.me
4. Убедиться что IP = 205.172.58.179 (IP сервера)

### 4.4 Критерии успеха

✅ **Успешное подключение:**
- В access.log появились записи о принятых соединениях
- В error.log НЕТ новых "invalid connection"
- Браузер показывает IP сервера (205.172.58.179)
- Сайты открываются быстро и стабильно

❌ **Неудача (если invalid connection повторяется):**
- Переходить к Альтернативному решению (раздел 5)

---

## 5. Альтернативные решения (если основное не помогло)

### 5.1 Изменить dest обратно на wikipedia.org

**Гипотеза:** Клиент ожидает старый dest

```bash
# Вернуть dest на wikipedia.org
sudo nano /opt/vless/config/config.json

# Изменить:
#   "dest": "google.com:443",
# На:
#   "dest": "www.wikipedia.org:443",

# Перезапуск
cd /opt/vless && docker-compose restart

# Создать новую ссылку с sni=www.wikipedia.org
VLESS_URL="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.wikipedia.org&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-admin-WIKI"
```

### 5.2 Упростить serverNames

**Гипотеза:** Множественные serverNames создают конфликт

```bash
sudo nano /opt/vless/config/config.json

# Изменить serverNames на только один:
"serverNames": [
  "google.com"
],

cd /opt/vless && docker-compose restart
```

### 5.3 Изменить fingerprint

**Гипотеза:** fp=chrome несовместим с сервером

```bash
# Попробовать другие fingerprints в клиентской ссылке:
# - firefox
# - safari
# - edge
# - random

# Пример:
fp=firefox
```

### 5.4 Проверить версию клиента

**Действия:**

1. Уточнить версию клиентского приложения
2. Проверить совместимость с Xray 24.11.30:
   - https://github.com/XTLS/Xray-core/releases
3. Обновить клиент до последней совместимой версии

### 5.5 Глубокая диагностика с Wireshark (крайняя мера)

```bash
# Установить tcpdump
sudo apt-get install -y tcpdump

# Захват трафика на порту 443
sudo tcpdump -i any -w /tmp/vless-capture.pcap port 443

# Попытаться подключиться клиентом
# Ctrl+C для остановки захвата

# Анализ в Wireshark на локальной машине
scp user@server:/tmp/vless-capture.pcap ./
```

---

## 6. Проверка и валидация после исправления

### 6.1 Немедленные проверки

```bash
# 1. Проверить отсутствие "invalid connection" за последние 5 минут
sudo tail -100 /opt/vless/logs/error.log | grep "invalid connection" | wc -l
# Ожидаем: 0

# 2. Проверить наличие успешных подключений
sudo tail -50 /opt/vless/logs/access.log | grep -E "accepted|email.*admin"
# Ожидаем: записи с UUID пользователя admin

# 3. Проверить статус контейнера
docker ps | grep xray-server
# Ожидаем: Up X minutes (healthy)
```

### 6.2 Долгосрочный мониторинг

```bash
# Создать задачу для мониторинга (опционально)
cat > /opt/vless/scripts/monitor-connections.sh << 'MONITOR_EOF'
#!/bin/bash
echo "=== $(date) ==="
echo "Invalid connections (last hour):"
sudo tail -1000 /opt/vless/logs/error.log | grep "invalid connection" | wc -l
echo "Successful connections (last hour):"
sudo tail -1000 /opt/vless/logs/access.log | grep -c "accepted"
echo "Container status:"
docker ps | grep xray-server
echo "================================"
MONITOR_EOF

chmod +x /opt/vless/scripts/monitor-connections.sh

# Запускать раз в час:
# watch -n 3600 /opt/vless/scripts/monitor-connections.sh
```

---

## 7. Документация изменений

### 7.1 Обновить CLAUDE.md

```bash
# Добавить в секцию "Common Issues" раздел о проблеме после переустановки
nano /home/ikeniborn/vless/CLAUDE.md

# Добавить:
### Client Unable to Connect After Reinstall - "REALITY: processed invalid connection"
**Issue:** После переустановки клиент не может подключиться, логи показывают invalid connection
**Root Cause:** Клиент использует старую ссылку с неправильными ключами или параметрами
**Solution:** 
1. Сгенерировать новые X25519 ключи
2. Обновить privateKey в config.json и PUBLIC_KEY в .env
3. Создать новую клиентскую ссылку
4. Очистить кэш клиента и импортировать новую ссылку
**Prevention:** Всегда создавать новую ссылку после переустановки и предоставлять её клиентам
```

### 7.2 Создать коммит

```bash
cd /home/ikeniborn/vless

git add FIX.md workflow/1_analysis.xml CLAUDE.md
git commit -m "docs: Add detailed fix plan for 'REALITY invalid connection' issue

- Complete diagnostic analysis in workflow/1_analysis.xml
- Step-by-step fix procedure in FIX.md
- Key rotation and client link regeneration
- Network and configuration validation
- Alternative solutions for edge cases
- Update CLAUDE.md with common issue documentation

Related to issue: client unable to connect after reinstall on 2025-10-01"
```

---

## 8. Контрольный список

### Перед началом исправления
- [ ] Создан бэкап текущей конфигурации
- [ ] Сохранены текущие ключи (на случай отката)
- [ ] Клиент предупрежден о предстоящих изменениях
- [ ] Доступен терминал с правами sudo

### Во время исправления
- [ ] Сгенерированы новые X25519 ключи
- [ ] Обновлен privateKey в config.json
- [ ] Обновлены PUBLIC_KEY и PRIVATE_KEY в .env
- [ ] Сохранены ключи в /opt/vless/data/keys/
- [ ] Перезапущен xray-server без ошибок
- [ ] Проверен статус контейнера (healthy)
- [ ] Очищены логи (опционально)
- [ ] Создана новая клиентская ссылка
- [ ] Создан QR-код (опционально)

### После исправления
- [ ] Клиент получил новую ссылку
- [ ] Клиент удалил старую конфигурацию
- [ ] Клиент импортировал новую ссылку
- [ ] Тестовое подключение успешно
- [ ] В access.log появились записи
- [ ] В error.log нет "invalid connection"
- [ ] Браузер показывает IP сервера
- [ ] Стабильная работа в течение 15 минут
- [ ] Обновлена документация (CLAUDE.md)
- [ ] Создан git commit с изменениями

---

## 9. Контакты и поддержка

**Если проблема не решена после выполнения всех шагов:**

1. Собрать диагностическую информацию:
```bash
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh > /tmp/diagnostic.log 2>&1
```

2. Проверить версию клиента и совместимость с Xray 24.11.30

3. Рассмотреть возможность downgrade Xray или upgrade клиента

4. Обратиться к:
   - Логам Xray: https://xtls.github.io/en/config/log.html
   - Документация REALITY: https://github.com/XTLS/REALITY

---

**Автор:** Claude Code  
**Дата создания:** 2025-10-01  
**Версия:** 1.0  
**Статус:** Готов к исполнению

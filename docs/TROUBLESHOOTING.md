# Руководство по решению проблем VLESS+Reality VPN

## Содержание

1. [Проблемы при установке](#проблемы-при-установке)
2. [Проблемы с Docker](#проблемы-с-docker)
3. [Ошибки подключения клиентов](#ошибки-подключения-клиентов)
4. [Сетевые проблемы](#сетевые-проблемы)
5. [Ошибки конфигурации](#ошибки-конфигурации)
6. [Проблемы производительности](#проблемы-производительности)
7. [Диагностика и отладка](#диагностика-и-отладка)
8. [Восстановление системы](#восстановление-системы)
9. [FAQ - Часто задаваемые вопросы](#faq---часто-задаваемые-вопросы)

## Проблемы при установке

### Ошибка: Permission denied при запуске install.sh

**Симптомы:**
```
bash: ./install.sh: Permission denied
```

**Решение:**
```bash
# Дать права на выполнение
chmod +x scripts/install.sh

# Запустить с правами root
sudo ./scripts/install.sh
```

### Ошибка: Docker не установлен или не запущен

**Симптомы:**
```
Cannot connect to the Docker daemon
docker: command not found
```

**Решение:**
```bash
# Установить Docker вручную
curl -fsSL https://get.docker.com | sh

# Запустить Docker
sudo systemctl start docker
sudo systemctl enable docker

# Добавить пользователя в группу docker
sudo usermod -aG docker $USER

# Перелогиниться или выполнить
newgrp docker
```

### Ошибка: Порт 443 уже занят

**Симптомы:**
```
Error: Port 443 is already in use
bind: address already in use
```

**Диагностика:**
```bash
# Проверить, что использует порт
sudo netstat -tlnp | grep :443
# или
sudo ss -tlnp | grep :443
```

**Решение:**
```bash
# Вариант 1: Остановить конфликтующий сервис
sudo systemctl stop nginx  # или apache2, или другой сервис

# Вариант 2: Изменить порт VLESS
# Отредактировать /opt/vless/.env
SERVER_PORT=8443  # или другой свободный порт
```

### Ошибка: Не удается определить внешний IP

**Симптомы:**
```
Could not detect external IP automatically
```

**Решение:**
```bash
# Проверить соединение с интернетом
ping -c 4 google.com

# Определить IP вручную
curl ifconfig.me
# или
curl ipinfo.io/ip

# Ввести IP вручную при установке
```

### Ошибка: Недостаточно места на диске

**Симптомы:**
```
No space left on device
```

**Решение:**
```bash
# Проверить свободное место
df -h

# Очистить Docker кэш
docker system prune -a

# Удалить старые логи
find /var/log -name "*.log" -mtime +30 -delete

# Очистить apt кэш
apt-get clean
```

## Проблемы с Docker

### Docker контейнер не запускается

**Симптомы:**
```
Container xray-server is restarting
Container exited with code 1
```

**Диагностика:**
```bash
# Проверить статус
docker ps -a

# Посмотреть логи
docker logs xray-server --tail 50

# Проверить docker-compose
cd /opt/vless
docker-compose ps
```

**Решение:**
```bash
# Пересоздать контейнер
cd /opt/vless
docker-compose down
docker-compose up -d

# При ошибках конфигурации
docker exec xray-server xray test -c /etc/xray/config.json
```

### Ошибка: Cannot pull image

**Симптомы:**
```
Error pulling image teddysun/xray:latest
```

**Решение:**
```bash
# Проверить соединение с Docker Hub
docker pull hello-world

# Использовать прокси для Docker (если нужно)
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:80"
Environment="HTTPS_PROXY=http://proxy.example.com:80"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### Docker Compose не найден

**Симптомы:**
```
docker-compose: command not found
```

**Решение:**
```bash
# Установить Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Проверить установку
docker-compose --version
```

## Ошибки подключения клиентов

### Клиент не может подключиться

**Симптомы:**
- Таймаут подключения
- Connection refused
- No route to host

**Диагностика:**
```bash
# Проверить, работает ли сервис
docker ps | grep xray-server

# Проверить порт
netstat -tuln | grep :443

# Проверить firewall
sudo ufw status
sudo iptables -L -n
```

**Решение:**
```bash
# Открыть порт в firewall
sudo ufw allow 443/tcp

# Проверить правильность конфигурации клиента
# - IP адрес сервера
# - Порт (443)
# - UUID пользователя
# - Public key
# - Short ID
# - SNI (должен совпадать с REALITY_SERVER_NAME)
```

### Ошибка: Invalid user

**Симптомы:**
```
rejected invalid user
UUID not found
```

**Решение:**
```bash
# Проверить, есть ли пользователь в системе
jq '.users' /opt/vless/data/users.json

# Проверить UUID в конфигурации
grep -A5 "clients" /opt/vless/config/config.json

# Добавить пользователя заново
vless-users
# Выбрать "Add new user"
```

### Ошибка: TLS handshake failure

**Симптомы:**
```
TLS handshake error
REALITY verification failed
```

**Причины:**
- Неправильный public key
- Неправильный SNI
- Проблемы с целевым сайтом REALITY

**Решение:**
```bash
# Проверить ключи
cat /opt/vless/data/keys/public.key

# Проверить доступность целевого сайта
curl -I https://speed.cloudflare.com

# При необходимости сменить целевой сайт
# Отредактировать /opt/vless/.env
REALITY_DEST=www.microsoft.com:443
REALITY_SERVER_NAME=www.microsoft.com

# Обновить конфигурацию
cd /opt/vless
./scripts/lib/config.sh update_config
docker-compose restart
```

### ⚠️ КРИТИЧЕСКАЯ ПРОБЛЕМА: "REALITY: processed invalid connection" - нет доступа к интернету

**Симптомы:**
- Клиент показывает статус "Connected", но сайты не открываются
- Нет доступа к интернету через VPN
- В логах сервера постоянные сообщения: `REALITY: processed invalid connection`
- Access log (`/opt/vless/logs/access.log`) пустой - нет успешных подключений
- Несколько попыток подключения в секунду, все отклоняются

**Root Cause:**
Несоответствие или повреждение X25519 ключей (privateKey на сервере / publicKey на клиенте). REALITY protocol требует **точного соответствия** cryptographic key pair для успешного handshake.

**Подробная диагностика:**
```bash
# Шаг 1: Проверить логи на ошибки REALITY
sudo tail -100 /opt/vless/logs/error.log | grep "invalid connection"
# Если видите множество таких сообщений - проблема подтверждается

# Шаг 2: Проверить privateKey в серверной конфигурации
docker exec xray-server cat /etc/xray/config.json | jq -r '.inbounds[0].streamSettings.realitySettings.privateKey'

# Шаг 3: Вычислить правильный publicKey из privateKey
# Замените <PRIVATE_KEY> на значение из шага 2
docker run --rm teddysun/xray:24.11.30 xray x25519 -i <PRIVATE_KEY>
# Output покажет: Public key: xxxxx

# Шаг 4: Сравнить с publicKey в .env файле
sudo cat /opt/vless/.env | grep PUBLIC_KEY
# Если значения НЕ совпадают - это и есть проблема!

# Шаг 5: Проверить версию Xray (должна быть 24.11.30)
docker exec xray-server xray version
```

**Решение (полная регенерация ключей):**

```bash
# 1. Создать backup текущей конфигурации
sudo cp /opt/vless/config/config.json /opt/vless/config/config.json.backup
sudo cp /opt/vless/.env /opt/vless/.env.backup

# 2. Сгенерировать новую пару X25519 ключей
docker run --rm teddysun/xray:24.11.30 xray x25519
# Сохраните вывод:
#   Private key: 4EqEF6MPw_Ca4LPZK3ZWriS39E4ghsbdrKo4JjHGiEY
#   Public key: UDawd840JWbO-4zi3izCT7FEBhMooT8nLTqeJM0CBD8

# 3. Обновить privateKey в config.json
NEW_PRIVATE="4EqEF6MPw_Ca4LPZK3ZWriS39E4ghsbdrKo4JjHGiEY"  # Замените на ваш
sudo jq ".inbounds[0].streamSettings.realitySettings.privateKey = \"$NEW_PRIVATE\"" \
  /opt/vless/config/config.json > /tmp/config_new.json
sudo mv /tmp/config_new.json /opt/vless/config/config.json
sudo chmod 600 /opt/vless/config/config.json

# 4. Обновить ключи в .env файле
NEW_PUBLIC="UDawd840JWbO-4zi3izCT7FEBhMooT8nLTqeJM0CBD8"  # Замените на ваш
sudo sed -i "s/^PRIVATE_KEY=.*/PRIVATE_KEY=$NEW_PRIVATE/" /opt/vless/.env
sudo sed -i "s/^PUBLIC_KEY=.*/PUBLIC_KEY=$NEW_PUBLIC/" /opt/vless/.env

# 5. Перезапустить сервер
cd /opt/vless && sudo docker-compose restart xray-server

# 6. Проверить что контейнер запустился успешно
sleep 5 && docker ps --filter "name=xray-server" --format "{{.Status}}"
docker logs xray-server --tail 10

# 7. Очистить error log для чистого теста
sudo truncate -s 0 /opt/vless/logs/error.log
```

**Обновление клиентских конфигураций:**

После регенерации ключей **ОБЯЗАТЕЛЬНО** обновите конфигурацию на ВСЕХ клиентах с новым `PUBLIC_KEY`:

```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=NEW_PUBLIC_KEY&sid=SHORTID&type=tcp#VLESS-admin
```

**Важно:** Параметр `pbk=` должен содержать НОВЫЙ публичный ключ!

**Превентивные меры:**
- ✅ Использовать скрипт `scripts/security/rotate-keys.sh` для безопасной ротации
- ✅ Автоматический backup перед любыми изменениями ключей
- ✅ Хранить резервные копии в `/opt/vless/backups/`
- ✅ Тестировать новые ключи перед массовой раздачей клиентам
- ✅ Валидация ключей после генерации (проверка соответствия)

**Дополнительные проверки после решения:**
```bash
# Подключиться с клиента и проверить логи
sudo tail -f /opt/vless/logs/error.log
# Не должно быть "processed invalid connection"

# Проверить access log на успешные соединения
sudo tail -f /opt/vless/logs/access.log
# Должны появиться записи о подключениях

# Проверить connectivity
# Клиент должен открывать сайты без проблем
```

**См. также:**
- PRD.md: Раздел 13.1 "Известные проблемы"
- Документация Xray REALITY: https://xtls.github.io/config/transport.html#realitysettings

### Медленная скорость подключения

**Причины:**
- Перегрузка сервера
- Проблемы с сетью
- Неоптимальные настройки

**Диагностика:**
```bash
# Проверить нагрузку
docker stats xray-server
htop

# Проверить сеть
ping -c 10 google.com
mtr google.com
```

**Решение:**
```bash
# Оптимизация сетевых параметров
sudo tee /etc/sysctl.d/99-xray.conf << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
EOF

sudo sysctl -p /etc/sysctl.d/99-xray.conf
```

## Сетевые проблемы

### Сервер недоступен извне

**Диагностика:**
```bash
# Проверить внешний IP
curl ifconfig.me

# Проверить маршрутизацию
ip route show

# Проверить NAT (если сервер за NAT)
traceroute -n 8.8.8.8
```

**Решение:**
```bash
# Для серверов за NAT:
# 1. Настроить проброс порта 443 на роутере
# 2. Использовать DDNS если IP динамический

# Проверить firewall
sudo ufw disable  # временно для теста
# Если заработало - настроить правила:
sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### DNS проблемы

**Симптомы:**
```
Cannot resolve domain
Temporary failure in name resolution
```

**Решение:**
```bash
# Проверить DNS
cat /etc/resolv.conf

# Добавить надежные DNS серверы
sudo tee /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Или использовать systemd-resolved
sudo systemctl restart systemd-resolved
```

### Нет доступа к интернету через VPN (клиент подключен, но трафик не проходит)

**Симптомы:**
- Клиент успешно подключается к серверу
- VPN соединение активно
- Но нет доступа к интернету (сайты не открываются)
- iOS Shadowrocket или другие клиенты показывают "Connected" статус

**Root Cause:**
UFW firewall блокирует forwarding трафика из Docker subnet из-за отсутствия NAT правил в `/etc/ufw/before.rules`. Хотя IP forwarding включен и iptables NAT правила существуют, UFW управляет своими правилами отдельно.

**Диагностика:**
```bash
# 1. Проверить IP forwarding (должно быть = 1)
sysctl net.ipv4.ip_forward

# 2. Проверить NAT правила в iptables
sudo iptables -t nat -L POSTROUTING -n -v | grep 172.19

# 3. Проверить NAT правила в UFW before.rules
grep "NAT table rules" /etc/ufw/before.rules
grep "172.19.0.0/16" /etc/ufw/before.rules

# 4. Проверить DEFAULT_FORWARD_POLICY
grep DEFAULT_FORWARD_POLICY /etc/default/ufw

# 5. Использовать скрипт автоматической проверки
sudo /opt/vless/scripts/verify-network.sh
# или из репозитория:
sudo bash scripts/verify-network.sh
```

**Решение (автоматическое):**
```bash
# Вариант 1: Использовать функцию из библиотеки
cd /opt/vless
sudo bash -c 'source scripts/lib/colors.sh scripts/lib/utils.sh scripts/lib/network.sh && configure_ufw_for_docker "172.19.0.0/16" "443"'

# Вариант 2: Переконфигурировать всю сеть
cd /opt/vless
source .env
sudo bash -c "source scripts/lib/colors.sh scripts/lib/utils.sh scripts/lib/network.sh && configure_network_for_vless \"$DOCKER_SUBNET\" \"$SERVER_PORT\""
```

**Решение (ручное):**
```bash
# 1. Создать backup
sudo cp /etc/ufw/before.rules /etc/ufw/before.rules.backup.$(date +%Y%m%d-%H%M%S)

# 2. Определить внешний интерфейс
EXTERNAL_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "External interface: $EXTERNAL_IFACE"

# 3. Определить Docker subnet (из .env файла)
DOCKER_SUBNET=$(grep DOCKER_SUBNET /opt/vless/.env | cut -d'=' -f2)
echo "Docker subnet: $DOCKER_SUBNET"

# 4. Добавить NAT правила в начало /etc/ufw/before.rules
sudo bash -c "cat > /tmp/ufw_nat_rules << EOF
# NAT table rules for Docker VLESS bridge network
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from Docker subnet to external interface
-A POSTROUTING -s $DOCKER_SUBNET -o $EXTERNAL_IFACE -j MASQUERADE

COMMIT
# End of NAT table rules

EOF
cat /tmp/ufw_nat_rules /etc/ufw/before.rules > /tmp/before.rules.new
mv /tmp/before.rules.new /etc/ufw/before.rules
rm -f /tmp/ufw_nat_rules"

# 5. Убедиться что DEFAULT_FORWARD_POLICY = ACCEPT
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# 6. Перезагрузить UFW
sudo ufw reload

# 7. Проверить что правила применены
sudo iptables -t nat -L POSTROUTING -n -v | grep $DOCKER_SUBNET
```

**Верификация после исправления:**
```bash
# 1. Проверить NAT правила в before.rules
grep "172.19.0.0/16" /etc/ufw/before.rules

# 2. Проверить активные NAT правила в iptables
sudo iptables -t nat -L POSTROUTING -n -v | grep 172.19

# 3. Проверить логи xray-server
sudo docker-compose -f /opt/vless/docker-compose.yml logs -f xray-server

# 4. Запустить полную проверку конфигурации
sudo /opt/vless/scripts/verify-network.sh
```

**Превентивные меры:**
- Скрипт `verify-network.sh` добавлен для проверки конфигурации
- Функция `configure_ufw_for_docker()` обновлена с дополнительными проверками
- При установке теперь автоматически проверяется корректность добавления NAT правил

**Rollback процедура:**
```bash
# Если что-то пошло не так, восстановить из backup
sudo cp /etc/ufw/before.rules.backup.* /etc/ufw/before.rules
sudo ufw reload
```

**См. также:**
- Раздел "Docker Network Configuration" в PRD.md (строка 108-110)
- Функция `configure_ufw_for_docker()` в `scripts/lib/network.sh`
- Скрипт проверки: `scripts/verify-network.sh`

## Ошибки конфигурации

### Invalid config.json

**Симптомы:**
```
Configuration file test failed
Invalid JSON syntax
```

**Диагностика:**
```bash
# Проверить синтаксис
docker exec xray-server xray test -c /etc/xray/config.json

# Проверить JSON формат
jq . /opt/vless/config/config.json
```

**Решение:**
```bash
# Восстановить из резервной копии
cp /opt/vless/backups/latest/config/config.json /opt/vless/config/

# Или пересоздать из шаблона
cd /opt/vless
source scripts/lib/config.sh
apply_template templates/config.json.tpl config/config.json

# Перезапустить
docker-compose restart
```

### Неправильные права доступа

**Симптомы:**
```
Permission denied
Cannot read configuration file
```

**Решение:**
```bash
# Восстановить правильные права
sudo chown -R root:root /opt/vless
sudo chmod 600 /opt/vless/.env
sudo chmod 600 /opt/vless/config/config.json
sudo chmod 600 /opt/vless/data/users.json
sudo chmod -R 600 /opt/vless/data/keys/*
sudo chmod 755 /opt/vless/scripts/*.sh
```

## Проблемы производительности

### Высокая нагрузка CPU

**Диагностика:**
```bash
# Мониторинг процессов
top
htop
docker stats

# Проверить количество подключений
netstat -an | grep :443 | wc -l
```

**Решение:**
```bash
# Ограничить ресурсы Docker
# В /opt/vless/docker-compose.yml добавить:
services:
  xray-server:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

# Перезапустить
docker-compose up -d
```

### Утечки памяти

**Симптомы:**
- Постоянный рост использования памяти
- Out of memory errors

**Решение:**
```bash
# Автоматический перезапуск при проблемах
# Добавить в crontab:
0 4 * * * docker restart xray-server

# Мониторинг памяти
watch -n 10 'docker stats --no-stream xray-server'
```

## Диагностика и отладка

### Полная диагностика системы

Создайте скрипт диагностики:

```bash
#!/bin/bash
# /opt/vless/scripts/diagnose.sh

echo "=== VLESS System Diagnostics ==="
echo "Date: $(date)"
echo ""

echo "[System Info]"
uname -a
echo ""

echo "[Docker Status]"
docker --version
docker-compose --version
systemctl status docker --no-pager | head -10
echo ""

echo "[Container Status]"
docker ps -a | grep xray
echo ""

echo "[Port Check]"
netstat -tuln | grep :443
echo ""

echo "[Firewall Status]"
sudo ufw status numbered
echo ""

echo "[Configuration Test]"
docker exec xray-server xray test -c /etc/xray/config.json 2>&1
echo ""

echo "[Recent Logs]"
docker logs xray-server --tail 20 2>&1
echo ""

echo "[Resource Usage]"
docker stats --no-stream xray-server
echo ""

echo "[Disk Usage]"
df -h /opt/vless
echo ""

echo "[Network Test]"
ping -c 3 8.8.8.8
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" https://speed.cloudflare.com
echo ""

echo "[File Permissions]"
ls -la /opt/vless/.env
ls -la /opt/vless/config/config.json
ls -la /opt/vless/data/users.json
echo ""

echo "=== Diagnostics Complete ==="
```

### Включение расширенного логирования

Для детальной отладки:

```bash
# Изменить уровень логирования в config.json
{
  "log": {
    "loglevel": "debug"  // Изменить с "warning" на "debug"
  }
}

# Перезапустить
docker-compose restart

# Смотреть логи
docker logs -f xray-server
```

**Важно:** Вернуть loglevel на "warning" после отладки!

## Восстановление системы

### Полный сброс и переустановка

```bash
#!/bin/bash
# ВНИМАНИЕ: Это удалит все данные!

# Сохранить важные данные
cp /opt/vless/data/users.json ~/users-backup.json
cp /opt/vless/.env ~/.env-backup

# Остановить и удалить
cd /opt/vless
docker-compose down
docker system prune -a

# Удалить директорию
sudo rm -rf /opt/vless

# Переустановить
cd /path/to/vless-repo
sudo ./scripts/install.sh

# Восстановить пользователей вручную
```

### Восстановление из резервной копии

```bash
# Найти последнюю резервную копию
ls -lt /opt/vless/backups/

# Остановить сервис
cd /opt/vless
docker-compose down

# Восстановить файлы
tar -xzf backups/[timestamp]/backup.tar.gz

# Запустить сервис
docker-compose up -d

# Проверить работоспособность
docker-compose logs --tail 20
```

### Аварийный доступ

Если потеряны все конфигурации пользователей:

```bash
# Создать временного admin пользователя
cd /opt/vless

# Сгенерировать новые credentials
TEMP_UUID=$(uuidgen)
TEMP_SHORT_ID=$(openssl rand -hex 4)

# Добавить в config.json вручную
# Отредактировать /opt/vless/config/config.json
# В секции clients добавить:
{
  "id": "$TEMP_UUID",
  "email": "emergency@admin",
  "flow": "xtls-rprx-vision"
}

# В shortIds добавить: "$TEMP_SHORT_ID"

# Перезапустить
docker-compose restart

# Создать vless:// ссылку для подключения
```

## FAQ - Часто задаваемые вопросы

### Q: Как изменить порт с 443 на другой?

**A:** Отредактируйте `/opt/vless/.env`:
```bash
SERVER_PORT=8443  # новый порт
```
Затем обновите docker-compose.yml и перезапустите:
```bash
cd /opt/vless
docker-compose down
docker-compose up -d
```

### Q: Можно ли использовать VLESS вместе с веб-сервером?

**A:** Да, но нужна дополнительная настройка:
1. Используйте nginx с stream модулем для SNI routing
2. Или используйте разные порты
3. Или используйте fallback в Xray конфигурации

### Q: Как перенести сервер на другой VPS?

**A:**
1. Создайте резервную копию на старом сервере
2. Перенесите архив на новый сервер
3. Установите систему на новом сервере
4. Восстановите данные из архива
5. Обновите IP адрес в клиентских конфигурациях

### Q: Почему скорость низкая?

**A:** Проверьте:
1. Загрузку сервера (CPU, RAM, сеть)
2. Качество интернет-канала
3. Расстояние до сервера
4. Настройки BBR (должны быть включены)
5. Количество одновременных пользователей

### Q: Как узнать, кто сейчас подключен?

**A:**
```bash
# Активные соединения
netstat -tn | grep :443 | grep ESTABLISHED

# Из логов
docker logs xray-server 2>&1 | grep "accepted" | tail -20
```

### Q: Безопасно ли использовать публичные DNS?

**A:** Для REALITY безопасно, так как трафик маскируется. Рекомендуемые домены:
- speed.cloudflare.com
- www.microsoft.com
- www.google.com
- aws.amazon.com

### Q: Как часто нужно обновлять Xray?

**A:** Рекомендуется:
- Проверять обновления раз в 2 недели
- Обязательно обновлять при security патчах
- Следить за releases на GitHub

### Q: Что делать если заблокировали IP сервера?

**A:**
1. Используйте CDN (Cloudflare) с WebSocket
2. Смените IP адрес сервера
3. Используйте другой порт
4. Примените обфускацию трафика

### Q: Как настроить автоматический перезапуск при сбоях?

**A:** Docker уже настроен с политикой restart:
```yaml
restart: unless-stopped
```
Это автоматически перезапустит контейнер при сбоях.

### Q: Можно ли ограничить скорость для пользователей?

**A:** В текущей конфигурации нет встроенного ограничения скорости. Можно использовать:
1. tc (traffic control) на уровне Linux
2. Настройки QoS на роутере
3. Сторонние решения для bandwidth management

---

## Полезные команды для отладки

```bash
# Быстрая проверка состояния
docker ps | grep xray && echo "Running" || echo "Stopped"

# Последние ошибки
docker logs xray-server 2>&1 | grep -i error | tail -10

# Проверка конфигурации
docker exec xray-server xray test -c /etc/xray/config.json

# Перезапуск с очисткой
cd /opt/vless && docker-compose down && docker-compose up -d

# Мониторинг в реальном времени
watch -n 2 'docker stats --no-stream xray-server'

# Проверка сертификата целевого домена
openssl s_client -connect speed.cloudflare.com:443 -servername speed.cloudflare.com

# Тест скорости сети
speedtest-cli

# Проверка MTU
ping -M do -s 1472 google.com
```

---

## Контакты для поддержки

Если проблема не решается:

1. Соберите диагностическую информацию (скрипт diagnose.sh)
2. Проверьте логи за последние 100 строк
3. Создайте issue на GitHub с описанием:
   - Что произошло
   - Что ожидалось
   - Шаги воспроизведения
   - Вывод диагностики
   - Версия системы

**Версия документа**: 1.0
**Последнее обновление**: 2025-09-27
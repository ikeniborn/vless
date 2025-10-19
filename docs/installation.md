# Инструкция по установке VLESS + Reality VPN

**Версия:** 5.0 (HAProxy Unified Architecture)
**Время установки:** < 5 минут
**Последнее обновление:** 2025-10-19

---

## Системные требования

### Минимальные требования

| Компонент | Минимум | Рекомендовано |
|-----------|---------|---------------|
| **ОС** | Ubuntu 20.04+, Debian 10+ | Ubuntu 22.04 LTS, 24.04 LTS |
| **RAM** | 1 GB | 2 GB |
| **Диск** | 10 GB | 20 GB |
| **CPU** | 1 core | 2+ cores |
| **Интернет** | 10 Mbps | 50+ Mbps |
| **Доступ** | Root (sudo) | Root (sudo) |

### Требования для разных режимов

| Режим | Требования |
|-------|------------|
| **VLESS-only** | IP адрес сервера |
| **Public Proxy (SOCKS5/HTTP)** | Доменное имя + DNS A-запись |
| **Reverse Proxy** | Поддомены + DNS A-записи |

### Поддерживаемые ОС

✅ **Полная поддержка:**
- Ubuntu 20.04, 22.04 LTS, 24.04 LTS
- Debian 10, 11, 12

❌ **НЕ поддерживается:**
- CentOS, RHEL, Fedora (firewalld vs UFW конфликт)
- Windows, macOS (только Linux)

---

## Предварительная подготовка

### 1. Подготовка DNS (если планируете использовать Proxy/Reverse Proxy)

```bash
# Создайте A-запись для основного домена
# Например:
# vless.example.com → 1.2.3.4 (IP вашего сервера)

# Проверьте, что DNS резолвится
dig +short vless.example.com
# Должен вывести IP вашего сервера

# Для Reverse Proxy создайте поддомены
# claude.example.com → 1.2.3.4
# proxy.example.com → 1.2.3.4
```

### 2. Подготовка сервера

```bash
# Обновите систему
sudo apt update && sudo apt upgrade -y

# Установите git (если не установлен)
sudo apt install git -y

# Проверьте доступ к интернету
ping -c 3 google.com
```

---

## Установка

### Шаг 1: Клонирование репозитория

```bash
# Клонируйте репозиторий
git clone https://github.com/yourusername/vless-reality-vpn.git
cd vless-reality-vpn

# Проверьте содержимое
ls -la
# Должны увидеть: install.sh, lib/, docs/, scripts/
```

### Шаг 2: Запуск установщика

```bash
# Запустите установщик с правами root
sudo ./install.sh
```

### Шаг 3: Интерактивная настройка

Установщик задаст вам несколько вопросов:

#### 3.1. Reality Destination Site

```
Select Reality destination site for traffic masquerading:
1. google.com:443 (default)
2. www.microsoft.com:443
3. www.apple.com:443
4. www.cloudflare.com:443
5. Custom domain

Enter choice [1-5]: 1
```

**Рекомендация:** Выберите `1` (google.com) - наиболее стабильный вариант.

**Что это:** Сайт, под который будет маскироваться ваш VPN трафик. Цензор будет видеть HTTPS запросы к этому сайту.

#### 3.2. VLESS Port

```
Select VLESS port (default: 443):
1. 443 (HTTPS - recommended)
2. 8443
3. 2053
4. 2083
5. 2087
6. Custom port

Enter choice [1-6]: 1
```

**Рекомендация:** Выберите `1` (port 443) - стандартный HTTPS порт, меньше вероятность блокировки.

**Что это:** Порт, на котором будет работать VLESS Reality VPN.

#### 3.3. Docker Network Subnet

```
Auto-detected available subnet: 172.20.0.0/16

Use this subnet? [Y/n]: Y
```

**Рекомендация:** Нажмите `Y` (использовать автоматически определённый subnet).

**Что это:** Внутренняя сеть Docker для изоляции контейнеров.

#### 3.4. Public Proxy Mode (опционально)

```
Enable public proxy access (SOCKS5 + HTTP)? [y/N]: y
```

**Выберите:**
- `y` - если хотите SOCKS5/HTTP прокси (требуется доменное имя)
- `N` - только VLESS VPN (доменное имя не требуется)

**Если выбрали `y`:**

```
Enter domain name for TLS certificates (e.g., vpn.example.com): vless.example.com

Enter email for Let's Encrypt notifications: admin@example.com
```

#### 3.5. Reverse Proxy Mode (опционально)

```
Enable reverse proxy support? [y/N]: y
```

**Выберите:**
- `y` - если планируете использовать subdomain reverse proxy
- `N` - только VPN и/или proxies

---

## Процесс установки

После ответов на вопросы начнётся автоматическая установка:

```
[1/10] Checking OS compatibility...
✓ Ubuntu 22.04 LTS detected

[2/10] Installing dependencies...
✓ Docker Engine 24.0.7 installed
✓ Docker Compose v2.21.0 installed
✓ jq, qrencode, openssl installed
✓ fail2ban installed
✓ certbot installed

[3/10] Checking old installation...
✓ No old installation detected

[4/10] Validating Reality destination...
✓ google.com:443 - TLS 1.3 ✓, SNI extraction ✓, Reachable ✓

[5/10] Generating configurations...
✓ X25519 keys generated
✓ Xray config created (/opt/vless/config/config.json)
✓ HAProxy config created (/opt/vless/config/haproxy.cfg)
✓ Docker Compose created (/opt/vless/docker-compose.yml)

[6/10] Obtaining Let's Encrypt certificate...
✓ Certificate obtained for vless.example.com
✓ combined.pem created for HAProxy

[7/10] Configuring UFW firewall...
✓ UFW enabled
✓ Port 443 allowed (VLESS + Reverse Proxy)
✓ Port 1080 allowed (SOCKS5 TLS)
✓ Port 8118 allowed (HTTP TLS)
✓ Docker chains added to /etc/ufw/after.rules

[8/10] Deploying Docker containers...
✓ Network vless_reality_net created
✓ Container vless_haproxy started
✓ Container vless_xray started
✓ Container vless_nginx started

[9/10] Installing CLI tools...
✓ vless-user linked to /usr/local/bin/
✓ vless-proxy linked to /usr/local/bin/
✓ vless-status, vless-logs, vless-restart linked

[10/10] Setting permissions...
✓ /opt/vless/config/ → 700
✓ config.json, haproxy.cfg, users.json → 600

✅ Installation completed successfully in 4 minutes 23 seconds!
```

---

## Создание первого пользователя

```bash
# Создайте пользователя (например, alice)
sudo vless-user add alice
```

**Вывод:**

```
✅ User 'alice' created successfully

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 VLESS Connection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Server: vless.example.com:443
UUID: 12345678-1234-1234-1234-123456789012
ShortID: a1b2c3d4e5f67890

🔗 Connection URI:
vless://12345678-1234-1234-1234-123456789012@vless.example.com:443?...

📲 QR Code (scan with v2rayN/v2rayNG):
[QR CODE displayed in terminal]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 Proxy Credentials (TLS Encrypted)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOCKS5: socks5s://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@vless.example.com:1080
HTTP:   https://alice:4fd0a3936e5a1e28b7c9d0f1e2a3b4c5@vless.example.com:8118

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 Config Files
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Location: /opt/vless/data/clients/alice/

Files generated:
- vless_config.json      (v2rayN/v2rayNG config)
- vless_uri.txt          (VLESS connection string)
- qrcode.png             (QR code image)
- socks5_config.txt      (SOCKS5 proxy URI)
- http_config.txt        (HTTP proxy URI)
- vscode_settings.json   (VSCode proxy settings)
- docker_daemon.json     (Docker daemon proxy)
- bash_exports.sh        (Bash environment variables)
```

---

## Подключение клиента

### Windows/Android: v2rayN/v2rayNG

1. Скачайте клиент:
   - **Windows**: [v2rayN](https://github.com/2dust/v2rayN/releases)
   - **Android**: [v2rayNG](https://github.com/2dust/v2rayNG/releases)

2. Импортируйте конфигурацию:
   - **QR Code**: Отсканируйте QR код из terminal
   - **URI**: Скопируйте connection URI из вывода команды

3. Подключитесь!

### iOS: Shadowrocket/Stash

1. Скачайте клиент из App Store
2. Импортируйте конфигурацию через QR code или URI
3. Включите VPN

### macOS/Linux: Xray-core

```bash
# Скачайте Xray-core
wget https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip
unzip Xray-linux-64.zip
chmod +x xray

# Скопируйте конфиг с сервера
scp root@vless.example.com:/opt/vless/data/clients/alice/vless_config.json ./config.json

# Запустите
./xray run -c config.json
```

---

## Проверка работы

### 1. Проверка статуса сервиса

```bash
sudo vless-status
```

**Вывод должен быть:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 VLESS Reality VPN Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🐳 Docker Containers:
  vless_haproxy              ✅ Up 5 minutes
  vless_xray                 ✅ Up 5 minutes
  vless_nginx                ✅ Up 5 minutes

🌐 Network:
  vless_reality_net          ✅ Active

🔌 Listening Ports:
  443  (HAProxy SNI routing) ✅ LISTENING
  1080 (SOCKS5 TLS)          ✅ LISTENING
  8118 (HTTP TLS)            ✅ LISTENING

👥 Users: 1
🔐 Proxy Mode: ENABLED (TLS)
🔄 Reverse Proxies: 0
```

### 2. Проверка логов

```bash
# Логи всех контейнеров
sudo vless-logs -f

# Только HAProxy
sudo docker logs vless_haproxy --tail 50

# Только Xray
sudo docker logs vless_xray --tail 50
```

### 3. Тест подключения (с клиента)

```bash
# Подключитесь через VLESS VPN клиент, затем:
curl https://ifconfig.me

# Должен вывести IP адрес вашего VPN сервера
```

### 4. Тест SOCKS5 proxy (если включён)

```bash
# Замените на свои credentials
curl --socks5 alice:PASSWORD@vless.example.com:1080 https://ifconfig.me

# Должен вывести IP адрес вашего VPN сервера
```

### 5. Тест HTTP proxy (если включён)

```bash
curl --proxy https://alice:PASSWORD@vless.example.com:8118 https://ifconfig.me

# Должен вывести IP адрес вашего VPN сервера
```

---

## Troubleshooting

### Проблема: Контейнеры не запускаются

```bash
# Проверьте логи
sudo vless-logs

# Проверьте конфигурацию Xray
sudo docker run --rm -v /opt/vless/config:/etc/xray teddysun/xray:24.11.30 xray run -test -c /etc/xray/config.json

# Проверьте конфигурацию HAProxy
sudo haproxy -c -f /opt/vless/config/haproxy.cfg
```

### Проблема: Порт 443 занят

```bash
# Проверьте, что использует порт 443
sudo ss -tulnp | grep :443

# Если это Apache/Nginx, остановите их
sudo systemctl stop apache2 nginx

# Или выберите другой порт при установке (8443, 2053, etc.)
```

### Проблема: Let's Encrypt не может получить сертификат

```bash
# Проверьте DNS
dig +short vless.example.com
# Должен вывести IP вашего сервера

# Проверьте, что порт 80 открыт (certbot использует HTTP-01 challenge)
sudo ufw allow 80/tcp

# Попробуйте получить сертификат вручную
sudo certbot certonly --standalone -d vless.example.com
```

### Проблема: UFW блокирует Docker трафик

```bash
# Проверьте Docker chains в UFW
grep "DOCKER-USER" /etc/ufw/after.rules

# Если не найдено, добавьте:
sudo nano /etc/ufw/after.rules

# Добавьте в конец файла:
# *filter
# :DOCKER-USER - [0:0]
# -A DOCKER-USER -j RETURN
# COMMIT

# Перезагрузите UFW
sudo ufw reload
```

### Проблема: Не могу подключиться к VPN

1. **Проверьте firewall на сервере:**
   ```bash
   sudo ufw status
   # Должно быть: 443/tcp ALLOW
   ```

2. **Проверьте, что контейнеры запущены:**
   ```bash
   sudo docker ps
   ```

3. **Проверьте логи Xray:**
   ```bash
   sudo docker logs vless_xray --tail 50
   # Ищите ошибки authentication
   ```

4. **Проверьте Reality destination:**
   ```bash
   curl -I https://google.com
   # Должен вернуть HTTP 200
   ```

---

## Дополнительная настройка

### Создание reverse proxy

```bash
# Интерактивное создание
sudo vless-proxy add

# Вам будет предложено ввести:
# 1. Subdomain (claude.example.com)
# 2. Target site (claude.ai)

# Результат:
# ✅ Reverse proxy created
# Access: https://claude.example.com (NO port!)
# Username: a3f9c2e1
# Password: [generated]
```

### IP Whitelisting для proxy (server-level)

```bash
# Показать текущие разрешённые IP
sudo vless-user show-proxy-ips

# Добавить IP
sudo vless-user add-proxy-ip 1.2.3.4

# Добавить CIDR range
sudo vless-user add-proxy-ip 192.168.1.0/24

# Удалить IP
sudo vless-user remove-proxy-ip 1.2.3.4

# Сбросить до localhost
sudo vless-user reset-proxy-ips
```

### Обновление сертификатов

```bash
# Сертификаты обновляются автоматически через certbot cron job
# Проверить статус:
sudo certbot renew --dry-run

# Ручное обновление (если нужно):
sudo vless-cert-renew
```

---

## Удаление

```bash
# Полное удаление с резервной копией
sudo /opt/vless/scripts/vless-uninstall

# Будет создан backup в /tmp/vless_backup_YYYYMMDD/
# Удалены: /opt/vless/, Docker containers, UFW rules, symlinks
```

---

## Дополнительная документация

- **Архитектура проекта**: [docs/prd/04_architecture.md](prd/04_architecture.md)
- **Функциональные требования**: [docs/prd/02_functional_requirements.md](prd/02_functional_requirements.md)
- **Тестирование**: [docs/prd/05_testing.md](prd/05_testing.md)
- **Troubleshooting**: [docs/prd/06_appendix.md](prd/06_appendix.md)
- **Project Memory**: [CLAUDE.md](../CLAUDE.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md)

---

**Готово!** Ваш VLESS + Reality VPN сервер установлен и готов к работе. 🎉

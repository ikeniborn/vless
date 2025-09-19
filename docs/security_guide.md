# Руководство по безопасности VLESS+Reality VPN

> Комплексное руководство по обеспечению безопасности и защите системы VLESS+Reality VPN от различных угроз.

## 📋 Содержание

1. [Обзор безопасности](#обзор-безопасности)
2. [Архитектура безопасности](#архитектура-безопасности)
3. [Настройка базовой защиты](#настройка-базовой-защиты)
4. [Усиленная защита](#усиленная-защита)
5. [Мониторинг безопасности](#мониторинг-безопасности)
6. [Обнаружение вторжений](#обнаружение-вторжений)
7. [Защита от конкретных угроз](#защита-от-конкретных-угроз)
8. [Аудит и соответствие](#аудит-и-соответствие)
9. [Планы реагирования](#планы-реагирования)

## 🛡️ Обзор безопасности

### Ключевые принципы безопасности

VLESS+Reality VPN система построена на следующих принципах безопасности:

1. **Глубокая защита (Defense in Depth)**
   - Многоуровневая система защиты
   - Независимые контрольные точки
   - Fail-safe механизмы

2. **Принцип минимальных привилегий**
   - Ограниченные права доступа
   - Изоляция компонентов
   - Контролируемое выполнение команд

3. **Безопасность по дизайну**
   - Встроенная защита в архитектуру
   - Безопасные настройки по умолчанию
   - Проактивные меры защиты

### Угрозы и их митигация

| Угроза | Вероятность | Воздействие | Митигация |
|--------|-------------|-------------|-----------|
| DDoS атаки | Высокая | Средний | fail2ban, rate limiting |
| Перебор паролей | Средняя | Высокий | fail2ban, UFW |
| Анализ трафика | Средняя | Высокий | Reality маскировка |
| Компрометация сервера | Низкая | Критический | AIDE, мониторинг |
| Утечка конфигураций | Низкая | Высокий | Шифрование, права доступа |

## 🏗️ Архитектура безопасности

### Уровни защиты

```
┌─────────────────────────────────────────────────┐
│                  ИНТЕРНЕТ                       │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────┐
│              СЕТЕВАЯ ЗАЩИТА                     │
│  • UFW Firewall (порты 22, 80, 443)           │
│  • fail2ban (защита от брутфорса)             │
│  • DDoS Protection                             │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────┐
│            REALITY МАСКИРОВКА                   │
│  • TLS 1.3 шифрование                         │
│  • SNI маскировка под microsoft.com            │
│  • Fallback на реальные сайты                 │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────┐
│              XRAY-CORE VPN                      │
│  • VLESS протокол                              │
│  • AEAD шифрование                             │
│  • UUID аутентификация                         │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────┐
│            СИСТЕМНАЯ ЗАЩИТА                     │
│  • AIDE (мониторинг целостности)               │
│  • AppArmor/SELinux                            │
│  • Аудит логирование                           │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────┴───────────────────────────────┐
│              DOCKER ИЗОЛЯЦИЯ                    │
│  • Контейнеризация сервисов                    │
│  • Ограничение ресурсов                        │
│  • Сетевая изоляция                            │
└─────────────────────────────────────────────────┘
```

### Компоненты безопасности

#### 1. Сетевая защита
- **UFW Firewall**: Базовая защита на уровне сети
- **fail2ban**: Защита от атак перебора
- **Rate Limiting**: Ограничение скорости подключений

#### 2. Криптографическая защита
- **Reality Protocol**: Маскировка VPN трафика
- **TLS 1.3**: Современное шифрование
- **Forward Secrecy**: Защита от компрометации ключей

#### 3. Системная защита
- **AIDE**: Мониторинг целостности файлов
- **AppArmor**: Обязательный контроль доступа
- **Audit Logging**: Детальное логирование действий

## 🔧 Настройка базовой защиты

### Автоматическая настройка

Базовая защита настраивается автоматически при установке:

```bash
# Запуск автоматической настройки безопасности
sudo ./modules/security_hardening.sh auto-setup

# Проверка статуса безопасности
sudo ./modules/security_hardening.sh status
```

### Конфигурация UFW Firewall

#### Базовые правила

```bash
# Сброс к настройкам по умолчанию
sudo ufw --force reset

# Запрет всех входящих соединений по умолчанию
sudo ufw default deny incoming

# Разрешение всех исходящих соединений
sudo ufw default allow outgoing

# Разрешение SSH (измените порт при необходимости)
sudo ufw allow 22/tcp

# Разрешение HTTP и HTTPS для VPN
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Активация UFW
sudo ufw enable

# Проверка статуса
sudo ufw status verbose
```

#### Расширенные правила

```bash
# Ограничение подключений SSH
sudo ufw limit ssh

# Разрешение только с определенных IP
sudo ufw allow from 192.168.1.0/24 to any port 22

# Логирование подозрительной активности
sudo ufw logging on

# Настройка лимитов скорости
echo "net/ipv4/netfilter/ip_conntrack_max = 65536" >> /etc/sysctl.conf
```

### Настройка fail2ban

#### Базовая конфигурация

```bash
# Установка fail2ban (если не установлен)
sudo apt install fail2ban -y

# Создание локальной конфигурации
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Редактирование конфигурации
sudo nano /etc/fail2ban/jail.local
```

#### Конфигурация для VPN защиты

```ini
[DEFAULT]
# Время блокировки (1 час)
bantime = 3600

# Время наблюдения (10 минут)
findtime = 600

# Максимум попыток перед блокировкой
maxretry = 3

# Игнорируемые IP (добавьте ваши IP)
ignoreip = 127.0.0.1/8 192.168.1.0/24

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[nginx-dos]
enabled = true
port = http,https
filter = nginx-dos
logpath = /var/log/nginx/access.log
maxretry = 10
findtime = 60
bantime = 3600

[vless-dos]
enabled = true
port = 443
filter = vless-dos
logpath = /opt/vless/logs/xray.log
maxretry = 20
findtime = 300
bantime = 1800
```

#### Создание фильтра для VLESS

```bash
# Создание фильтра для защиты от DoS атак на VLESS
sudo cat > /etc/fail2ban/filter.d/vless-dos.conf << 'EOF'
[Definition]
failregex = ^.*\[.*\] .* (.*) rejected.*$
            ^.*\[.*\] .* (.*) connection failed.*$
            ^.*\[.*\] .* (.*) authentication failed.*$

ignoreregex =

datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
EOF

# Перезапуск fail2ban
sudo systemctl restart fail2ban

# Проверка статуса
sudo fail2ban-client status
```

## 🛡️ Усиленная защита

### Мониторинг целостности файлов (AIDE)

#### Установка и настройка

```bash
# Автоматическая настройка AIDE
sudo ./modules/security_hardening.sh setup-aide

# Или ручная настройка:
sudo apt install aide -y

# Инициализация базы данных AIDE
sudo aideinit

# Копирование базы данных
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

#### Конфигурация мониторинга

```bash
# Редактирование конфигурации AIDE
sudo nano /etc/aide/aide.conf

# Добавление директорий для мониторинга
echo "/opt/vless/configs R" >> /etc/aide/aide.conf
echo "/opt/vless/certs R" >> /etc/aide/aide.conf
echo "/etc/systemd/system/vless-vpn.service R" >> /etc/aide/aide.conf
echo "/usr/local/bin R" >> /etc/aide/aide.conf
```

#### Автоматические проверки

```bash
# Создание скрипта проверки
sudo cat > /usr/local/bin/aide-check << 'EOF'
#!/bin/bash
LOGFILE="/var/log/aide.log"
REPORT="/tmp/aide-report.txt"

# Запуск проверки
aide --check > $REPORT 2>&1

# Проверка результатов
if [ $? -ne 0 ]; then
    echo "$(date): AIDE detected changes:" >> $LOGFILE
    cat $REPORT >> $LOGFILE

    # Отправка уведомления в Telegram
    /opt/vless/modules/telegram_bot_manager.sh send-alert "AIDE: Обнаружены изменения в системных файлах. Проверьте логи."
fi

# Обновление базы данных (если изменения легитимны)
# aide --update
EOF

sudo chmod +x /usr/local/bin/aide-check

# Добавление в cron для ежедневных проверок
echo "0 6 * * * root /usr/local/bin/aide-check" >> /etc/crontab
```

### Усиление конфигурации SSH

```bash
# Резервная копия конфигурации
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Применение усиленной конфигурации SSH
sudo cat > /etc/ssh/sshd_config.d/99-security.conf << 'EOF'
# Отключение root входа
PermitRootLogin no

# Отключение входа по паролю (только ключи)
PasswordAuthentication no
PermitEmptyPasswords no

# Ограничение пользователей
AllowUsers your_username

# Усиленные алгоритмы
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Таймауты и лимиты
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxStartups 2
LoginGraceTime 30

# Отключение ненужных функций
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
EOF

# Перезапуск SSH
sudo systemctl restart sshd
```

### Настройка AppArmor/SELinux

```bash
# Проверка статуса AppArmor
sudo aa-status

# Создание профиля для Xray
sudo cat > /etc/apparmor.d/usr.local.bin.xray << 'EOF'
#include <tunables/global>

/usr/local/bin/xray {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  capability net_bind_service,
  capability setuid,
  capability setgid,

  network inet stream,
  network inet6 stream,

  /usr/local/bin/xray mr,
  /opt/vless/configs/* r,
  /opt/vless/certs/* r,
  /opt/vless/logs/* rw,

  /proc/sys/net/core/rmem_default r,
  /proc/sys/net/core/rmem_max r,
  /proc/sys/net/core/wmem_default r,
  /proc/sys/net/core/wmem_max r,
}
EOF

# Загрузка профиля
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.xray
```

## 📊 Мониторинг безопасности

### Система мониторинга в реальном времени

#### Мониторинг сетевой активности

```bash
# Скрипт мониторинга подозрительной активности
sudo cat > /usr/local/bin/security-monitor << 'EOF'
#!/bin/bash

LOGFILE="/var/log/security-monitor.log"
THRESHOLD_CONNECTIONS=50
THRESHOLD_BANDWIDTH=100  # MB/s

while true; do
    # Проверка количества подключений
    CONNECTIONS=$(netstat -an | grep ESTABLISHED | wc -l)
    if [ $CONNECTIONS -gt $THRESHOLD_CONNECTIONS ]; then
        echo "$(date): WARNING: High connection count: $CONNECTIONS" >> $LOGFILE
    fi

    # Проверка использования пропускной способности
    RX_BYTES=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    sleep 1
    RX_BYTES_NEW=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    BANDWIDTH=$(( (RX_BYTES_NEW - RX_BYTES) / 1024 / 1024 ))

    if [ $BANDWIDTH -gt $THRESHOLD_BANDWIDTH ]; then
        echo "$(date): WARNING: High bandwidth usage: ${BANDWIDTH}MB/s" >> $LOGFILE
    fi

    sleep 10
done
EOF

sudo chmod +x /usr/local/bin/security-monitor

# Создание systemd сервиса
sudo cat > /etc/systemd/system/security-monitor.service << 'EOF'
[Unit]
Description=Security Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/security-monitor
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable security-monitor
sudo systemctl start security-monitor
```

### Анализ логов безопасности

```bash
# Скрипт анализа логов
sudo cat > /usr/local/bin/analyze-security-logs << 'EOF'
#!/bin/bash

REPORT_FILE="/tmp/security-report-$(date +%Y%m%d).txt"

echo "ОТЧЕТ БЕЗОПАСНОСТИ - $(date)" > $REPORT_FILE
echo "======================================" >> $REPORT_FILE

# Анализ попыток входа SSH
echo -e "\n1. ПОПЫТКИ ВХОДА SSH:" >> $REPORT_FILE
grep "Failed password" /var/log/auth.log | tail -20 >> $REPORT_FILE

# Анализ блокировок fail2ban
echo -e "\n2. БЛОКИРОВКИ FAIL2BAN:" >> $REPORT_FILE
fail2ban-client status | grep "Jail list" >> $REPORT_FILE
for jail in $(fail2ban-client status | grep "Jail list" | cut -d: -f2 | tr ',' ' '); do
    echo "--- $jail ---" >> $REPORT_FILE
    fail2ban-client status $jail >> $REPORT_FILE
done

# Анализ соединений VPN
echo -e "\n3. VPN СОЕДИНЕНИЯ:" >> $REPORT_FILE
grep "accepted" /opt/vless/logs/xray.log | tail -10 >> $REPORT_FILE

# Анализ подозрительной активности
echo -e "\n4. ПОДОЗРИТЕЛЬНАЯ АКТИВНОСТЬ:" >> $REPORT_FILE
grep -i "attack\|intrusion\|malware\|virus" /var/log/syslog | tail -10 >> $REPORT_FILE

# Отправка отчета в Telegram
/opt/vless/modules/telegram_bot_manager.sh send-file $REPORT_FILE "Ежедневный отчет безопасности"
EOF

sudo chmod +x /usr/local/bin/analyze-security-logs

# Добавление в cron для ежедневного анализа
echo "0 7 * * * root /usr/local/bin/analyze-security-logs" >> /etc/crontab
```

## 🚨 Обнаружение вторжений

### Система обнаружения аномалий

```bash
# Скрипт обнаружения аномалий
sudo cat > /usr/local/bin/anomaly-detector << 'EOF'
#!/bin/bash

# Базовые метрики для сравнения
BASELINE_CPU=20
BASELINE_MEMORY=30
BASELINE_CONNECTIONS=10

# Текущие метрики
CURRENT_CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
CURRENT_MEMORY=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
CURRENT_CONNECTIONS=$(netstat -an | grep ESTABLISHED | wc -l)

# Проверка аномалий
alert_triggered=false

if (( $(echo "$CURRENT_CPU > $BASELINE_CPU * 3" | bc -l) )); then
    echo "ALERT: Аномальное использование CPU: ${CURRENT_CPU}%"
    alert_triggered=true
fi

if [ $CURRENT_MEMORY -gt $((BASELINE_MEMORY * 3)) ]; then
    echo "ALERT: Аномальное использование памяти: ${CURRENT_MEMORY}%"
    alert_triggered=true
fi

if [ $CURRENT_CONNECTIONS -gt $((BASELINE_CONNECTIONS * 5)) ]; then
    echo "ALERT: Аномальное количество соединений: $CURRENT_CONNECTIONS"
    alert_triggered=true
fi

# Отправка уведомления при обнаружении аномалий
if [ "$alert_triggered" = true ]; then
    /opt/vless/modules/telegram_bot_manager.sh send-alert "Обнаружены аномалии в системе. Требуется проверка."
fi
EOF

sudo chmod +x /usr/local/bin/anomaly-detector

# Запуск каждые 5 минут
echo "*/5 * * * * root /usr/local/bin/anomaly-detector" >> /etc/crontab
```

### Honeypot для обнаружения атак

```bash
# Простой SSH honeypot
sudo cat > /usr/local/bin/ssh-honeypot << 'EOF'
#!/bin/bash

# Запуск фейкового SSH сервера на порту 2222
while true; do
    nc -l -p 2222 -c 'echo "SSH-2.0-OpenSSH_7.4"; read line; echo "$(date): Honeypot connection from $REMOTE_ADDR: $line" >> /var/log/honeypot.log'
done
EOF

sudo chmod +x /usr/local/bin/ssh-honeypot

# Создание systemd сервиса для honeypot
sudo cat > /etc/systemd/system/ssh-honeypot.service << 'EOF'
[Unit]
Description=SSH Honeypot
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-honeypot
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable ssh-honeypot
sudo systemctl start ssh-honeypot
```

## 🎯 Защита от конкретных угроз

### Защита от DDoS атак

#### Настройка лимитов подключений

```bash
# Настройка iptables для защиты от DDoS
sudo cat > /usr/local/bin/ddos-protection << 'EOF'
#!/bin/bash

# Ограничение новых подключений
iptables -A INPUT -p tcp --dport 443 -m connlimit --connlimit-above 10 -j REJECT

# Ограничение скорости подключений
iptables -A INPUT -p tcp --dport 443 -m hashlimit --hashlimit-name vless_limit --hashlimit 10/min --hashlimit-burst 20 --hashlimit-mode srcip --hashlimit-htable-expire 300000 -j ACCEPT

# Защита от SYN flood
iptables -A INPUT -p tcp --syn -m hashlimit --hashlimit-name syn_limit --hashlimit 1/s --hashlimit-burst 3 --hashlimit-mode srcip -j ACCEPT

# Блокировка после превышения лимитов
iptables -A INPUT -p tcp --dport 443 -j REJECT
EOF

sudo chmod +x /usr/local/bin/ddos-protection
sudo /usr/local/bin/ddos-protection
```

#### Настройка системных лимитов

```bash
# Увеличение лимитов для обработки большого количества соединений
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_syn_retries = 1" >> /etc/sysctl.conf
echo "net.ipv4.tcp_synack_retries = 1" >> /etc/sysctl.conf

# Применение настроек
sudo sysctl -p
```

### Защита от анализа трафика

#### Усиление Reality маскировки

```bash
# Скрипт для ротации Reality параметров
sudo cat > /usr/local/bin/rotate-reality << 'EOF'
#!/bin/bash

TARGETS=("microsoft.com" "apple.com" "google.com" "amazon.com")
SNIS=("www.microsoft.com" "www.apple.com" "www.google.com" "www.amazon.com")

# Выбор случайного target
RANDOM_INDEX=$((RANDOM % ${#TARGETS[@]}))
NEW_TARGET=${TARGETS[$RANDOM_INDEX]}
NEW_SNI=${SNIS[$RANDOM_INDEX]}

# Обновление конфигурации
/opt/vless/modules/cert_management.sh update-reality --target $NEW_TARGET --sni $NEW_SNI

# Перезапуск сервиса
systemctl restart vless-vpn

echo "Reality configuration updated: $NEW_TARGET / $NEW_SNI"
EOF

sudo chmod +x /usr/local/bin/rotate-reality

# Ротация параметров каждые 24 часа
echo "0 3 * * * root /usr/local/bin/rotate-reality" >> /etc/crontab
```

### Защита от компрометации ключей

#### Автоматическая ротация ключей

```bash
# Скрипт автоматической ротации ключей
sudo cat > /usr/local/bin/rotate-keys << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/vless/backups/keys"
DATE=$(date +%Y%m%d-%H%M%S)

# Создание резервной копии текущих ключей
mkdir -p $BACKUP_DIR
cp -r /opt/vless/certs/ $BACKUP_DIR/certs-$DATE/

# Генерация новых ключей
/opt/vless/modules/cert_management.sh regenerate --force

# Обновление конфигураций всех пользователей
/opt/vless/modules/user_management.sh regenerate-all

# Перезапуск сервиса
systemctl restart vless-vpn

# Уведомление администратора
/opt/vless/modules/telegram_bot_manager.sh send-alert "Ключи безопасности обновлены. Пользователям необходимо обновить конфигурации."

echo "Keys rotated successfully at $DATE"
EOF

sudo chmod +x /usr/local/bin/rotate-keys

# Ротация ключей каждую неделю
echo "0 2 * * 0 root /usr/local/bin/rotate-keys" >> /etc/crontab
```

## 📋 Аудит и соответствие

### Система аудита

#### Настройка auditd

```bash
# Установка auditd
sudo apt install auditd audispd-plugins -y

# Конфигурация правил аудита
sudo cat > /etc/audit/rules.d/vless-audit.rules << 'EOF'
# Мониторинг изменений конфигураций
-w /opt/vless/configs/ -p wa -k vless_config_change
-w /opt/vless/certs/ -p wa -k vless_cert_change

# Мониторинг выполнения административных команд
-w /usr/bin/sudo -p x -k sudo_usage
-w /bin/su -p x -k su_usage

# Мониторинг сетевых настроек
-w /etc/ufw/ -p wa -k firewall_change
-w /etc/fail2ban/ -p wa -k fail2ban_change

# Мониторинг SSH
-w /etc/ssh/sshd_config -p wa -k ssh_config_change
-w /etc/ssh/sshd_config.d/ -p wa -k ssh_config_change

# Мониторинг доступа к файлам паролей
-w /etc/passwd -p wa -k passwd_change
-w /etc/shadow -p wa -k shadow_change
-w /etc/group -p wa -k group_change

# Мониторинг системных вызовов
-a always,exit -F arch=b64 -S execve -k exec_commands
-a always,exit -F arch=b32 -S execve -k exec_commands
EOF

# Перезагрузка правил
sudo augenrules --load
sudo systemctl restart auditd
```

#### Анализ аудит логов

```bash
# Скрипт анализа аудит логов
sudo cat > /usr/local/bin/audit-analyzer << 'EOF'
#!/bin/bash

REPORT_FILE="/tmp/audit-report-$(date +%Y%m%d).txt"

echo "АУДИТ ОТЧЕТ - $(date)" > $REPORT_FILE
echo "========================" >> $REPORT_FILE

# Анализ изменений конфигураций
echo -e "\n1. ИЗМЕНЕНИЯ КОНФИГУРАЦИЙ VLESS:" >> $REPORT_FILE
ausearch -k vless_config_change -ts today 2>/dev/null >> $REPORT_FILE

# Анализ использования sudo
echo -e "\n2. ИСПОЛЬЗОВАНИЕ SUDO:" >> $REPORT_FILE
ausearch -k sudo_usage -ts today 2>/dev/null | aureport -x --summary >> $REPORT_FILE

# Анализ сетевых изменений
echo -e "\n3. ИЗМЕНЕНИЯ СЕТЕВЫХ НАСТРОЕК:" >> $REPORT_FILE
ausearch -k firewall_change,fail2ban_change -ts today 2>/dev/null >> $REPORT_FILE

# Анализ выполненных команд
echo -e "\n4. ВЫПОЛНЕННЫЕ КОМАНДЫ:" >> $REPORT_FILE
ausearch -k exec_commands -ts today 2>/dev/null | aureport -x --summary >> $REPORT_FILE

# Отправка отчета
/opt/vless/modules/telegram_bot_manager.sh send-file $REPORT_FILE "Аудит отчет"
EOF

sudo chmod +x /usr/local/bin/audit-analyzer

# Ежедневный анализ аудит логов
echo "0 8 * * * root /usr/local/bin/audit-analyzer" >> /etc/crontab
```

### Compliance проверки

```bash
# Скрипт проверки соответствия требованиям безопасности
sudo cat > /usr/local/bin/compliance-check << 'EOF'
#!/bin/bash

REPORT_FILE="/tmp/compliance-report-$(date +%Y%m%d).txt"

echo "ПРОВЕРКА СООТВЕТСТВИЯ ТРЕБОВАНИЯМ БЕЗОПАСНОСТИ" > $REPORT_FILE
echo "=============================================" >> $REPORT_FILE

# Проверка системных настроек
echo -e "\n1. СИСТЕМНЫЕ НАСТРОЙКИ:" >> $REPORT_FILE

# SSH конфигурация
if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
    echo "✅ SSH root login отключен" >> $REPORT_FILE
else
    echo "❌ SSH root login включен" >> $REPORT_FILE
fi

if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo "✅ SSH password authentication отключен" >> $REPORT_FILE
else
    echo "❌ SSH password authentication включен" >> $REPORT_FILE
fi

# UFW статус
if ufw status | grep -q "Status: active"; then
    echo "✅ UFW firewall активен" >> $REPORT_FILE
else
    echo "❌ UFW firewall неактивен" >> $REPORT_FILE
fi

# fail2ban статус
if systemctl is-active --quiet fail2ban; then
    echo "✅ fail2ban активен" >> $REPORT_FILE
else
    echo "❌ fail2ban неактивен" >> $REPORT_FILE
fi

# AIDE статус
if which aide > /dev/null; then
    echo "✅ AIDE установлен" >> $REPORT_FILE
else
    echo "❌ AIDE не установлен" >> $REPORT_FILE
fi

# Проверка прав доступа
echo -e "\n2. ПРАВА ДОСТУПА К ФАЙЛАМ:" >> $REPORT_FILE

# Проверка прав на конфигурации
if [ "$(stat -c %a /opt/vless/configs/)" = "755" ]; then
    echo "✅ Права на configs правильные (755)" >> $REPORT_FILE
else
    echo "❌ Неправильные права на configs" >> $REPORT_FILE
fi

# Проверка прав на сертификаты
if [ "$(stat -c %a /opt/vless/certs/)" = "700" ]; then
    echo "✅ Права на certs правильные (700)" >> $REPORT_FILE
else
    echo "❌ Неправильные права на certs" >> $REPORT_FILE
fi

# Отправка отчета
/opt/vless/modules/telegram_bot_manager.sh send-file $REPORT_FILE "Compliance отчет"
EOF

sudo chmod +x /usr/local/bin/compliance-check

# Еженедельная проверка соответствия
echo "0 9 * * 1 root /usr/local/bin/compliance-check" >> /etc/crontab
```

## 🚨 Планы реагирования

### План реагирования на инциденты

#### Классификация инцидентов

| Уровень | Описание | Время реагирования | Действия |
|---------|----------|-------------------|----------|
| P1 - Критический | Компрометация сервера | 15 минут | Немедленная изоляция |
| P2 - Высокий | DDoS атака | 30 минут | Активация защиты |
| P3 - Средний | Подозрительная активность | 1 час | Анализ и мониторинг |
| P4 - Низкий | Нарушения политик | 4 часа | Документирование |

#### Автоматические ответные меры

```bash
# Скрипт автоматического реагирования
sudo cat > /usr/local/bin/incident-response << 'EOF'
#!/bin/bash

INCIDENT_TYPE=$1
SOURCE_IP=$2

case $INCIDENT_TYPE in
    "ddos")
        # Блокировка IP
        ufw deny from $SOURCE_IP

        # Уведомление администратора
        /opt/vless/modules/telegram_bot_manager.sh send-alert "DDoS атака обнаружена от IP: $SOURCE_IP. IP заблокирован."

        # Логирование
        echo "$(date): DDoS attack blocked from $SOURCE_IP" >> /var/log/security-incidents.log
        ;;

    "intrusion")
        # Немедленная блокировка
        ufw deny from $SOURCE_IP

        # Создание snapshot системы
        /opt/vless/modules/backup_restore.sh create --emergency

        # Критическое уведомление
        /opt/vless/modules/telegram_bot_manager.sh send-alert "🚨 КРИТИЧЕСКИЙ ИНЦИДЕНТ: Обнаружено вторжение от IP: $SOURCE_IP"

        # Изоляция сервиса (опционально)
        # systemctl stop vless-vpn
        ;;

    "bruteforce")
        # Увеличение времени блокировки fail2ban
        fail2ban-client set sshd bantime 86400

        # Уведомление
        /opt/vless/modules/telegram_bot_manager.sh send-alert "Брутфорс атака обнаружена от IP: $SOURCE_IP"
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/incident-response
```

### План восстановления

#### Процедура восстановления после компрометации

```bash
# Скрипт восстановления системы
sudo cat > /usr/local/bin/disaster-recovery << 'EOF'
#!/bin/bash

echo "НАЧАЛО ПРОЦЕДУРЫ ВОССТАНОВЛЕНИЯ СИСТЕМЫ"
echo "========================================"

# 1. Изоляция системы
echo "1. Изоляция системы..."
systemctl stop vless-vpn
ufw deny incoming

# 2. Создание форензической копии
echo "2. Создание форензической копии..."
FORENSIC_DIR="/tmp/forensics-$(date +%Y%m%d-%H%M%S)"
mkdir -p $FORENSIC_DIR
cp -r /opt/vless/logs/ $FORENSIC_DIR/
cp -r /var/log/ $FORENSIC_DIR/system_logs/
ps aux > $FORENSIC_DIR/processes.txt
netstat -tulpn > $FORENSIC_DIR/network.txt

# 3. Полная регенерация ключей
echo "3. Регенерация всех ключей..."
/opt/vless/modules/cert_management.sh regenerate --force

# 4. Смена всех паролей
echo "4. Генерация новых паролей..."
NEW_SSH_PASS=$(openssl rand -base64 32)
echo "Новый пароль SSH: $NEW_SSH_PASS"

# 5. Обновление системы
echo "5. Обновление системы..."
apt update && apt upgrade -y

# 6. Проверка целостности
echo "6. Проверка целостности файлов..."
aide --check

# 7. Восстановление сервиса
echo "7. Восстановление сервиса..."
systemctl start vless-vpn
ufw allow 22,80,443/tcp

# 8. Уведомление о завершении
/opt/vless/modules/telegram_bot_manager.sh send-alert "Процедура восстановления завершена. Система восстановлена."

echo "ПРОЦЕДУРА ВОССТАНОВЛЕНИЯ ЗАВЕРШЕНА"
EOF

sudo chmod +x /usr/local/bin/disaster-recovery
```

### Контакты экстренного реагирования

```bash
# Создание файла контактов
sudo cat > /opt/vless/emergency-contacts.txt << 'EOF'
КОНТАКТЫ ЭКСТРЕННОГО РЕАГИРОВАНИЯ
==============================

Основной администратор:
- Telegram: @admin_username
- Email: admin@example.com
- Телефон: +1234567890

Резервный администратор:
- Telegram: @backup_admin
- Email: backup@example.com

Техническая поддержка:
- Email: support@example.com
- Ticket система: https://support.example.com

Правоохранительные органы:
- Полиция: 102
- Киберполиция: +7-xxx-xxx-xxxx

ПРОЦЕДУРЫ:
1. При обнаружении инцидента - немедленно уведомить основного администратора
2. При недоступности основного - связаться с резервным
3. При серьезном нарушении безопасности - уведомить правоохранительные органы
4. Все инциденты документировать в /var/log/security-incidents.log
EOF
```

---

**Важно**: Регулярно обновляйте конфигурации безопасности и следите за новыми угрозами. Безопасность - это непрерывный процесс, требующий постоянного внимания и обновлений.

**Следующий шаг**: [Architecture](architecture.md)
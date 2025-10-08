# APT Lock Handling - Автоматическое управление блокировками пакетного менеджера

## Обзор

Система установки VLESS включает интеллектуальную обработку блокировок APT/dpkg с автоматическим завершением безопасных процессов.

## Категории блокирующих процессов

### 🟢 SAFE (Безопасные - автоматическое завершение разрешено)

Процессы, которые можно безопасно завершить без риска повреждения системы:

- `apt update` / `apt-get update` - обновление индексов пакетов
- `apt-cache` - поиск и просмотр информации о пакетах
- `unattended-upgrades` - автоматические обновления (если запущены менее 5 минут назад)

**Причина безопасности:** Эти процессы только читают данные и не изменяют состояние системы.

### 🟡 CAUTION (Осторожно - требуется подтверждение пользователя)

Процессы, которые могут изменять систему, но обычно безопасны для завершения:

- `apt install` / `apt-get install` - установка пакетов (может быть на этапе загрузки)
- `dpkg --configure -a` - восстановление после сбоя

**Причина осторожности:** Завершение может потребовать повторного запуска, но не повредит систему.

### 🔴 DANGER (Опасные - никогда не завершать автоматически)

Процессы, завершение которых может повредить систему:

- `dpkg` с флагами `--install`, `--unpack`, `--configure`, `--remove`

**Причина опасности:** Прерывание может оставить пакеты в несогласованном состоянии, требующем ручного восстановления.

## Режимы работы

### 1. Интерактивный режим (по умолчанию)

При обнаружении блокировки APT пользователю предлагается выбор:

```
APT is locked. Choose an action:
  [w] Wait 30s and retry (attempt 1/5)
  [a] Auto-kill SAFE processes only (recommended)
  [k] Kill ALL blocking processes (CAUTION)
  [c] Cancel installation

Your choice [w/a/k/c] (default=wait, 60s timeout):
```

#### Опция [a] - Auto-kill SAFE (рекомендуется)
- Анализирует каждый блокирующий процесс
- Завершает только процессы категории SAFE
- Пропускает CAUTION и DANGER процессы
- Безопасно для автоматизации

#### Опция [k] - Kill ALL (требует подтверждения)
- **ВНИМАНИЕ:** Может повредить систему!
- Завершает ВСЕ блокирующие процессы включая dpkg
- Требует явного подтверждения `yes`
- Использовать только в крайнем случае

### 2. Автоматический режим (для CI/CD и скриптов)

Активируется через переменные окружения:

```bash
# Базовый автоматический режим
export VLESS_AUTO_INSTALL_DEPS=yes
sudo ./install.sh

# Автоматический режим с безопасным завершением процессов
export VLESS_AUTO_INSTALL_DEPS=yes
export VLESS_AUTO_KILL_SAFE_LOCKS=yes
sudo ./install.sh
```

**Поведение:**
- Автоматически завершает SAFE процессы
- Если остаются CAUTION/DANGER процессы - выходит с ошибкой
- Не требует пользовательского ввода
- Максимум 5 попыток с retry

## Переменные окружения

### VLESS_AUTO_INSTALL_DEPS
- **Тип:** Boolean (yes/no)
- **По умолчанию:** не установлена (интерактивный режим)
- **Назначение:** Пропускает пользовательские запросы при установке зависимостей

**Пример:**
```bash
export VLESS_AUTO_INSTALL_DEPS=yes
sudo ./install.sh
```

### VLESS_AUTO_KILL_SAFE_LOCKS
- **Тип:** Boolean (yes/no)
- **По умолчанию:** не установлена (требует подтверждения)
- **Назначение:** Автоматически завершает SAFE блокирующие процессы

**Пример:**
```bash
export VLESS_AUTO_INSTALL_DEPS=yes
export VLESS_AUTO_KILL_SAFE_LOCKS=yes
sudo ./install.sh
```

## Примеры использования

### Пример 1: Установка на чистом сервере (интерактивно)

```bash
sudo ./install.sh
```

Если APT заблокирован `unattended-upgrades`:
1. Система обнаружит блокировку
2. Покажет диагностику с классификацией
3. Предложит опции: wait/auto-kill/force-kill/cancel
4. Рекомендуется выбрать `[a]` для безопасного auto-kill

### Пример 2: Автоматизированная установка в CI/CD

```bash
#!/bin/bash
# deploy.sh

export VLESS_AUTO_INSTALL_DEPS=yes
export VLESS_AUTO_KILL_SAFE_LOCKS=yes

sudo ./install.sh

if [ $? -eq 0 ]; then
    echo "Installation successful"
else
    echo "Installation failed - check for DANGER/CAUTION locks"
    exit 1
fi
```

### Пример 3: Ansible/Terraform интеграция

```yaml
# Ansible playbook
- name: Install VLESS with auto-kill
  shell: |
    export VLESS_AUTO_INSTALL_DEPS=yes
    export VLESS_AUTO_KILL_SAFE_LOCKS=yes
    sudo ./install.sh
  args:
    chdir: /path/to/vless
  environment:
    VLESS_AUTO_INSTALL_DEPS: "yes"
    VLESS_AUTO_KILL_SAFE_LOCKS: "yes"
```

### Пример 4: Обработка оставшихся блокировок вручную

Если автоматическое завершение не помогло:

```bash
# 1. Проверить блокирующие процессы
ps aux | grep -E 'apt|dpkg'

# 2. Определить тип процесса
ps -p <PID> -o args=

# 3. Если это dpkg --configure - дождаться завершения
# 4. Если это dpkg --install - НЕ завершать!
# 5. Если это apt update - безопасно завершить:
sudo kill <PID>

# 6. Очистить состояние dpkg если нужно
sudo dpkg --configure -a

# 7. Повторить установку
sudo ./install.sh
```

## Диагностика

### Просмотр текущих блокировок

```bash
# Проверить lock файлы
fuser /var/lib/dpkg/lock
fuser /var/lib/apt/lists/lock
fuser /var/cache/apt/archives/lock

# Показать блокирующие процессы с деталями
ps aux | grep -E 'apt|dpkg|unattended'

# Проверить возраст процесса
ps -p <PID> -o etime=,cmd=
```

### Логи автоматических обновлений

```bash
# Проверить статус unattended-upgrades
sudo systemctl status unattended-upgrades

# Логи автоматических обновлений
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
```

### Восстановление после сбоя dpkg

```bash
# Если dpkg оставил систему в несогласованном состоянии
sudo dpkg --configure -a
sudo apt-get install -f
```

## Безопасность

### Что НЕ делает система:

❌ НЕ завершает процессы dpkg в середине установки
❌ НЕ удаляет lock файлы напрямую (только через kill процессов)
❌ НЕ использует `rm -f /var/lib/dpkg/lock*` (опасно!)
❌ НЕ игнорирует DANGER классификацию

### Что делает система:

✅ Классифицирует процессы по уровню риска
✅ Завершает только безопасные процессы автоматически
✅ Запрашивает подтверждение для опасных операций
✅ Восстанавливает состояние dpkg после завершения (`dpkg --configure -a`)
✅ Предоставляет детальную диагностику

## Устранение типичных проблем

### Проблема: unattended-upgrades блокирует APT

**Решение 1 (автоматически):**
```bash
export VLESS_AUTO_KILL_SAFE_LOCKS=yes
sudo ./install.sh
```

**Решение 2 (вручную):**
```bash
# Дождаться завершения (рекомендуется)
sudo systemctl status unattended-upgrades

# ИЛИ остановить службу
sudo systemctl stop unattended-upgrades
sudo ./install.sh
sudo systemctl start unattended-upgrades
```

### Проблема: dpkg блокирует после сбоя

**Решение:**
```bash
# Проверить процессы dpkg
ps aux | grep dpkg

# Если процессов нет, но lock есть - восстановить
sudo dpkg --configure -a
sudo apt-get install -f

# Повторить установку
sudo ./install.sh
```

### Проблема: Остался lock без процесса (stale lock)

**НЕ делать:** `sudo rm /var/lib/dpkg/lock*` ❌

**Правильно:**
```bash
# 1. Убедиться что нет процессов
ps aux | grep -E 'apt|dpkg'
fuser /var/lib/dpkg/lock

# 2. Восстановить состояние dpkg
sudo dpkg --configure -a

# 3. Если все равно блокировка - проверить systemd
sudo systemctl status apt-daily.service
sudo systemctl status apt-daily-upgrade.service

# 4. Остановить службы временно
sudo systemctl stop apt-daily.timer
sudo systemctl stop apt-daily-upgrade.timer

# 5. Установить VLESS
sudo ./install.sh

# 6. Включить обратно
sudo systemctl start apt-daily.timer
sudo systemctl start apt-daily-upgrade.timer
```

## FAQ

**Q: Безопасно ли использовать VLESS_AUTO_KILL_SAFE_LOCKS=yes в production?**
A: Да, безопасно. Система завершает только процессы категории SAFE (apt update, apt-cache), которые не изменяют систему.

**Q: Что делать если DANGER процесс блокирует установку?**
A: Дождаться его завершения. НЕ завершайте dpkg принудительно - это может повредить систему.

**Q: Можно ли использовать для автоматизации через Ansible/Terraform?**
A: Да, используйте обе ENV переменные для полной автоматизации.

**Q: Что происходит после завершения процессов?**
A: Система автоматически запускает `dpkg --configure -a` для восстановления согласованности пакетов.

**Q: Сколько попыток делает система перед ошибкой?**
A: 5 попыток с ожиданием 30 секунд между попытками (всего ~2.5 минуты).

## Техническая реализация

### Алгоритм классификации процессов

```bash
classify_apt_process() {
    # SAFE: apt update, apt-cache, молодые unattended-upgrades
    # CAUTION: apt install, dpkg --configure -a
    # DANGER: dpkg --install/--unpack/--remove
}
```

### Workflow обработки блокировок

```
1. apt update fails
   ↓
2. check_apt_locks()
   ↓
3. Classify each process (SAFE/CAUTION/DANGER)
   ↓
4a. If VLESS_AUTO_KILL_SAFE_LOCKS=yes:
    → kill_safe_apt_processes()
    → retry apt update

4b. Else:
    → Show interactive menu
    → User chooses action
   ↓
5. If success → continue
   If failure → diagnose and exit
```

## История изменений

**v3.3 (2025-10-08):**
- ✨ Добавлена классификация процессов (SAFE/CAUTION/DANGER)
- ✨ Автоматическое завершение SAFE процессов
- ✨ ENV переменная VLESS_AUTO_KILL_SAFE_LOCKS
- ✨ Интерактивная опция [a] для safe auto-kill
- 🔒 Защита от завершения DANGER процессов
- 📝 Подробная диагностика с классификацией

**v3.2 (2025-10-07):**
- Базовая обработка APT locks с retry механизмом
- Интерактивный выбор wait/kill/cancel

---

**Автор:** VLESS Reality VPN Team
**Лицензия:** MIT
**Документация:** https://github.com/your-repo/vless

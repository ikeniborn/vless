#!/bin/bash

# VLESS+Reality VPN - Security Tests
# Комплексные тесты безопасности системы
# Версия: 1.0
# Дата: 2025-09-19

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Глобальные переменные
TEST_LOG="/tmp/vless_security_test.log"
FAILED_TESTS=0
TOTAL_TESTS=0
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"
SECURITY_MODULE="$PROJECT_ROOT/modules/security_hardening.sh"

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
    ((FAILED_TESTS++))
}

# Функция выполнения тестов
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TOTAL_TESTS++))
    log_info "Выполняется тест: $test_name"

    if $test_function; then
        log_success "Тест '$test_name' пройден"
        return 0
    else
        log_error "Тест '$test_name' провален"
        return 1
    fi
}

# Тест 1: Проверка модуля безопасности
test_security_module_exists() {
    if [[ ! -f "$SECURITY_MODULE" ]]; then
        log_error "Модуль безопасности не найден: $SECURITY_MODULE"
        return 1
    fi

    if [[ ! -x "$SECURITY_MODULE" ]]; then
        log_error "Модуль безопасности не исполняемый: $SECURITY_MODULE"
        return 1
    fi

    # Проверка синтаксиса
    if ! bash -n "$SECURITY_MODULE" 2>/dev/null; then
        log_error "Ошибка синтаксиса в модуле безопасности"
        return 1
    fi

    return 0
}

# Тест 2: Проверка настроек UFW файрволла
test_ufw_configuration() {
    # Проверка установки UFW
    if ! command -v ufw >/dev/null 2>&1; then
        log_warning "UFW не установлен"
        return 0
    fi

    # Проверка статуса UFW
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null | head -1)

    if echo "$ufw_status" | grep -q "Status: active"; then
        log_info "UFW активен"
    else
        log_warning "UFW неактивен"
    fi

    # Проверка правил UFW
    local ufw_rules
    ufw_rules=$(ufw status numbered 2>/dev/null)

    # Проверка базовых правил
    if echo "$ufw_rules" | grep -q "22/tcp"; then
        log_info "Правило SSH найдено"
    else
        log_warning "Правило SSH не найдено"
    fi

    if echo "$ufw_rules" | grep -q "80/tcp\|443/tcp"; then
        log_info "Правила HTTP/HTTPS найдены"
    else
        log_warning "Правила HTTP/HTTPS не найдены"
    fi

    return 0
}

# Тест 3: Проверка прав доступа к файлам
test_file_permissions() {
    local critical_files=(
        "$PROJECT_ROOT/config"
        "$PROJECT_ROOT/modules"
        "/opt/vless"
    )

    for path in "${critical_files[@]}"; do
        if [[ -e "$path" ]]; then
            local permissions
            permissions=$(stat -c "%a" "$path")

            # Проверка, что файлы не доступны всем на запись
            if [[ "$permissions" =~ [0-9][0-9][2-7] ]]; then
                log_warning "Небезопасные права доступа для других пользователей: $path ($permissions)"
            else
                log_info "Права доступа безопасны: $path ($permissions)"
            fi

            # Проверка владельца файла
            local owner
            owner=$(stat -c "%U" "$path")
            if [[ "$owner" != "root" ]] && [[ "$owner" != "$USER" ]]; then
                log_warning "Неожиданный владелец файла: $path ($owner)"
            fi
        fi
    done

    return 0
}

# Тест 4: Проверка сетевых портов
test_network_ports() {
    # Проверка открытых портов
    local open_ports
    if command -v ss >/dev/null 2>&1; then
        open_ports=$(ss -tuln 2>/dev/null)
    elif command -v netstat >/dev/null 2>&1; then
        open_ports=$(netstat -tuln 2>/dev/null)
    else
        log_warning "Утилиты для проверки портов не найдены"
        return 0
    fi

    # Проверка критических портов
    local critical_ports=("22" "80" "443")

    for port in "${critical_ports[@]}"; do
        if echo "$open_ports" | grep -q ":${port} "; then
            log_info "Порт $port открыт"
        else
            log_warning "Порт $port не открыт"
        fi
    done

    # Проверка подозрительных открытых портов
    local suspicious_ports=("23" "135" "139" "445" "1433" "3389")

    for port in "${suspicious_ports[@]}"; do
        if echo "$open_ports" | grep -q ":${port} "; then
            log_warning "Подозрительный открытый порт: $port"
        fi
    done

    return 0
}

# Тест 5: Проверка SSH конфигурации
test_ssh_security() {
    local ssh_config="/etc/ssh/sshd_config"

    if [[ ! -f "$ssh_config" ]]; then
        log_warning "Файл конфигурации SSH не найден"
        return 0
    fi

    # Проверка ключевых настроек безопасности SSH
    local security_checks=(
        "PermitRootLogin.*no"
        "PasswordAuthentication.*no"
        "PubkeyAuthentication.*yes"
        "Protocol.*2"
    )

    for check in "${security_checks[@]}"; do
        local setting="${check%%.*}"
        local expected="${check##*.}"

        if grep -q "^[[:space:]]*${check}" "$ssh_config"; then
            log_info "SSH настройка безопасна: $setting = $expected"
        else
            log_warning "SSH настройка может быть небезопасна: $setting"
        fi
    done

    return 0
}

# Тест 6: Проверка системных обновлений
test_system_updates() {
    # Проверка наличия обновлений безопасности
    if command -v apt >/dev/null 2>&1; then
        # Для систем на базе Debian/Ubuntu
        local security_updates
        security_updates=$(apt list --upgradable 2>/dev/null | grep -c "security" || echo "0")

        if [[ "$security_updates" -gt 0 ]]; then
            log_warning "Доступны обновления безопасности: $security_updates"
        else
            log_info "Обновления безопасности не требуются"
        fi

    elif command -v yum >/dev/null 2>&1; then
        # Для систем на базе RHEL/CentOS
        local security_updates
        security_updates=$(yum check-update --security 2>/dev/null | wc -l || echo "0")

        if [[ "$security_updates" -gt 1 ]]; then
            log_warning "Доступны обновления безопасности"
        else
            log_info "Обновления безопасности не требуются"
        fi
    fi

    return 0
}

# Тест 7: Проверка активных пользователей
test_active_users() {
    # Проверка текущих пользователей в системе
    local logged_users
    logged_users=$(who | wc -l)

    log_info "Активных пользователей в системе: $logged_users"

    # Проверка пользователей с shell доступом
    local shell_users
    shell_users=$(grep -E "/bin/(bash|sh|zsh)$" /etc/passwd | wc -l)

    if [[ "$shell_users" -gt 5 ]]; then
        log_warning "Много пользователей с shell доступом: $shell_users"
    else
        log_info "Пользователей с shell доступом: $shell_users"
    fi

    # Проверка пользователей с root правами
    local sudo_users
    if [[ -f /etc/sudoers ]]; then
        sudo_users=$(grep -E "^[^#].*ALL.*ALL" /etc/sudoers | wc -l)
        log_info "Пользователей с sudo правами: $sudo_users"
    fi

    return 0
}

# Тест 8: Проверка запущенных сервисов
test_running_services() {
    # Получение списка запущенных сервисов
    local running_services
    if command -v systemctl >/dev/null 2>&1; then
        running_services=$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)
        log_info "Запущенных systemd сервисов: $running_services"

        # Проверка критических сервисов
        local critical_services=("ssh" "docker" "ufw")

        for service in "${critical_services[@]}"; do
            if systemctl is-active "$service" >/dev/null 2>&1; then
                log_info "Сервис $service активен"
            else
                log_warning "Сервис $service неактивен"
            fi
        done
    fi

    return 0
}

# Тест 9: Проверка целостности конфигурационных файлов
test_config_integrity() {
    local config_files=(
        "$PROJECT_ROOT/config/docker-compose.yml"
        "$PROJECT_ROOT/config/xray_config_template.json"
    )

    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            # Проверка на наличие подозрительного содержимого
            if grep -qi "password\|secret\|token" "$config_file"; then
                log_warning "Файл $config_file может содержать чувствительные данные"
            fi

            # Проверка прав доступа к конфигурации
            local permissions
            permissions=$(stat -c "%a" "$config_file")

            if [[ "$permissions" == "644" ]] || [[ "$permissions" == "600" ]]; then
                log_info "Права доступа к конфигурации безопасны: $config_file ($permissions)"
            else
                log_warning "Небезопасные права доступа к конфигурации: $config_file ($permissions)"
            fi
        fi
    done

    return 0
}

# Тест 10: Проверка логирования безопасности
test_security_logging() {
    # Проверка системных логов безопасности
    local security_logs=(
        "/var/log/auth.log"
        "/var/log/secure"
        "/var/log/syslog"
    )

    for log_file in "${security_logs[@]}"; do
        if [[ -f "$log_file" ]]; then
            log_info "Лог файл найден: $log_file"

            # Проверка размера лог файла
            local log_size
            log_size=$(stat -c "%s" "$log_file")

            if [[ "$log_size" -eq 0 ]]; then
                log_warning "Лог файл пуст: $log_file"
            fi

            # Проверка недавних событий безопасности
            if [[ -r "$log_file" ]]; then
                local failed_logins
                failed_logins=$(grep -c "Failed password\|authentication failure" "$log_file" 2>/dev/null || echo "0")

                if [[ "$failed_logins" -gt 10 ]]; then
                    log_warning "Обнаружено много неудачных попыток входа: $failed_logins"
                elif [[ "$failed_logins" -gt 0 ]]; then
                    log_info "Неудачных попыток входа: $failed_logins"
                fi
            fi
        fi
    done

    return 0
}

# Тест 11: Проверка fail2ban
test_fail2ban() {
    if command -v fail2ban-client >/dev/null 2>&1; then
        log_info "fail2ban установлен"

        # Проверка статуса fail2ban
        if systemctl is-active fail2ban >/dev/null 2>&1; then
            log_info "fail2ban активен"

            # Проверка jail'ов
            local jails
            jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2)

            if [[ -n "$jails" ]]; then
                log_info "Активные jail'ы fail2ban: $jails"
            else
                log_warning "Нет активных jail'ов fail2ban"
            fi
        else
            log_warning "fail2ban неактивен"
        fi
    else
        log_warning "fail2ban не установлен"
    fi

    return 0
}

# Тест 12: Проверка целостности системы
test_system_integrity() {
    # Проверка на наличие подозрительных процессов
    local suspicious_processes=("nc" "netcat" "nmap" "ncat")

    for process in "${suspicious_processes[@]}"; do
        if pgrep "$process" >/dev/null 2>&1; then
            log_warning "Обнаружен подозрительный процесс: $process"
        fi
    done

    # Проверка использования ресурсов
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

    if [[ "${cpu_usage%.*}" -gt 80 ]]; then
        log_warning "Высокое использование CPU: ${cpu_usage}%"
    fi

    # Проверка использования памяти
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    if [[ "$memory_usage" -gt 90 ]]; then
        log_warning "Высокое использование памяти: ${memory_usage}%"
    fi

    return 0
}

# Главная функция тестирования
main() {
    log_info "Начало тестирования безопасности VLESS+Reality VPN"
    echo "Лог-файл: $TEST_LOG" > "$TEST_LOG"
    echo "Время начала: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    # Выполнение всех тестов
    run_test "Модуль безопасности" test_security_module_exists
    run_test "Конфигурация UFW" test_ufw_configuration
    run_test "Права доступа к файлам" test_file_permissions
    run_test "Сетевые порты" test_network_ports
    run_test "Безопасность SSH" test_ssh_security
    run_test "Системные обновления" test_system_updates
    run_test "Активные пользователи" test_active_users
    run_test "Запущенные сервисы" test_running_services
    run_test "Целостность конфигураций" test_config_integrity
    run_test "Логирование безопасности" test_security_logging
    run_test "fail2ban" test_fail2ban
    run_test "Целостность системы" test_system_integrity

    # Итоговый отчет
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ БЕЗОПАСНОСТИ" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "Всего тестов выполнено: $TOTAL_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов провалено: $FAILED_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов пройдено: $((TOTAL_TESTS - FAILED_TESTS))" | tee -a "$TEST_LOG"
    echo "Время завершения: $(date)" | tee -a "$TEST_LOG"

    # Подсчет предупреждений
    local warnings
    warnings=$(grep -c "WARNING" "$TEST_LOG" || echo "0")
    echo "Предупреждений безопасности: $warnings" | tee -a "$TEST_LOG"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        if [[ "$warnings" -eq 0 ]]; then
            log_success "ВСЕ ТЕСТЫ БЕЗОПАСНОСТИ ПРОЙДЕНЫ БЕЗ ЗАМЕЧАНИЙ!"
        else
            log_warning "ТЕСТЫ БЕЗОПАСНОСТИ ПРОЙДЕНЫ, НО ЕСТЬ ПРЕДУПРЕЖДЕНИЯ ($warnings)"
        fi
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ БЕЗОПАСНОСТИ"
        echo "Подробности в логе: $TEST_LOG"
        exit 1
    fi
}

# Предупреждение о правах доступа
if [[ $EUID -ne 0 ]]; then
    log_warning "Тесты запущены не от root. Некоторые проверки могут быть недоступны."
fi

# Запуск главной функции
main "$@"
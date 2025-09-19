#!/bin/bash

# VLESS+Reality VPN - Installation Tests
# Комплексные тесты для проверки установки на чистой системе
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
TEST_LOG="/tmp/vless_installation_test.log"
FAILED_TESTS=0
TOTAL_TESTS=0
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"

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

# Тест 1: Проверка структуры проекта
test_project_structure() {
    local required_dirs=(
        "$PROJECT_ROOT/modules"
        "$PROJECT_ROOT/config"
        "$PROJECT_ROOT/tests"
    )

    local required_files=(
        "$PROJECT_ROOT/install.sh"
        "$PROJECT_ROOT/modules/system_update.sh"
        "$PROJECT_ROOT/modules/docker_setup.sh"
        "$PROJECT_ROOT/modules/ufw_config.sh"
        "$PROJECT_ROOT/modules/user_management.sh"
        "$PROJECT_ROOT/modules/backup_restore.sh"
        "$PROJECT_ROOT/modules/telegram_bot.py"
        "$PROJECT_ROOT/config/docker-compose.yml"
        "$PROJECT_ROOT/config/xray_config_template.json"
    )

    # Проверка каталогов
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Отсутствует обязательный каталог: $dir"
            return 1
        fi
    done

    # Проверка файлов
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Отсутствует обязательный файл: $file"
            return 1
        fi
    done

    return 0
}

# Тест 2: Проверка синтаксиса bash скриптов
test_bash_syntax() {
    local bash_files
    bash_files=$(find "$PROJECT_ROOT" -name "*.sh" -type f)

    for file in $bash_files; do
        if ! bash -n "$file" 2>/dev/null; then
            log_error "Ошибка синтаксиса в файле: $file"
            return 1
        fi
    done

    return 0
}

# Тест 3: Проверка выполняемости скриптов
test_script_permissions() {
    local executable_files=(
        "$PROJECT_ROOT/install.sh"
        "$PROJECT_ROOT/modules/system_update.sh"
        "$PROJECT_ROOT/modules/docker_setup.sh"
        "$PROJECT_ROOT/modules/ufw_config.sh"
        "$PROJECT_ROOT/modules/user_management.sh"
        "$PROJECT_ROOT/modules/backup_restore.sh"
    )

    for file in "${executable_files[@]}"; do
        if [[ ! -x "$file" ]]; then
            log_error "Файл не имеет прав на выполнение: $file"
            return 1
        fi
    done

    return 0
}

# Тест 4: Проверка зависимостей системы
test_system_dependencies() {
    local required_commands=(
        "curl"
        "wget"
        "jq"
        "uuidgen"
        "openssl"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_warning "Отсутствует рекомендуемая команда: $cmd"
        fi
    done

    # Проверка ОС
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удается определить версию ОС"
        return 1
    fi

    source /etc/os-release
    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID}" < "20.04" ]]; then
                log_error "Требуется Ubuntu 20.04 или новее"
                return 1
            fi
            ;;
        debian)
            if [[ "${VERSION_ID}" < "11" ]]; then
                log_error "Требуется Debian 11 или новее"
                return 1
            fi
            ;;
        *)
            log_warning "Непроверенная ОС: $ID $VERSION_ID"
            ;;
    esac

    return 0
}

# Тест 5: Проверка конфигурационных файлов
test_config_files() {
    # Проверка Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_warning "Docker Compose не установлен, пропускаем проверку"
    else
        if ! docker compose -f "$PROJECT_ROOT/config/docker-compose.yml" config >/dev/null 2>&1; then
            log_error "Ошибка в файле docker-compose.yml"
            return 1
        fi
    fi

    # Проверка JSON конфигурации
    if ! jq . "$PROJECT_ROOT/config/xray_config_template.json" >/dev/null 2>&1; then
        log_error "Ошибка в файле xray_config_template.json"
        return 1
    fi

    return 0
}

# Тест 6: Проверка Python скриптов
test_python_syntax() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_warning "Python3 не установлен, пропускаем проверку"
        return 0
    fi

    local python_files
    python_files=$(find "$PROJECT_ROOT" -name "*.py" -type f)

    for file in $python_files; do
        if ! python3 -m py_compile "$file" 2>/dev/null; then
            log_error "Ошибка синтаксиса Python в файле: $file"
            return 1
        fi
    done

    return 0
}

# Тест 7: Проверка прав доступа
test_file_permissions() {
    # Проверка, что конфигурационные файлы не доступны всем
    local sensitive_files=(
        "$PROJECT_ROOT/config"
    )

    for path in "${sensitive_files[@]}"; do
        if [[ -d "$path" ]]; then
            local perms
            perms=$(stat -c "%a" "$path")
            if [[ "$perms" == "777" ]]; then
                log_error "Небезопасные права доступа для: $path ($perms)"
                return 1
            fi
        fi
    done

    return 0
}

# Тест 8: Проверка переменных окружения
test_environment_variables() {
    # Проверка наличия критических переменных в конфигурации
    if [[ -f "$PROJECT_ROOT/config/docker-compose.yml" ]]; then
        if ! grep -q "TELEGRAM_BOT_TOKEN" "$PROJECT_ROOT/config/docker-compose.yml"; then
            log_warning "Не найдена переменная TELEGRAM_BOT_TOKEN в docker-compose.yml"
        fi

        if ! grep -q "ADMIN_TELEGRAM_ID" "$PROJECT_ROOT/config/docker-compose.yml"; then
            log_warning "Не найдена переменная ADMIN_TELEGRAM_ID в docker-compose.yml"
        fi
    fi

    return 0
}

# Тест 9: Проверка целостности модулей
test_module_integrity() {
    local modules_dir="$PROJECT_ROOT/modules"

    # Проверка, что все модули содержат основные функции
    local modules=(
        "system_update.sh:update_system"
        "docker_setup.sh:install_docker"
        "ufw_config.sh:setup_ufw"
        "user_management.sh:add_user"
        "backup_restore.sh:create_backup"
    )

    for module_info in "${modules[@]}"; do
        local module_file="${module_info%%:*}"
        local required_function="${module_info##*:}"
        local module_path="$modules_dir/$module_file"

        if [[ -f "$module_path" ]]; then
            if ! grep -q "^${required_function}()" "$module_path" && \
               ! grep -q "^function ${required_function}" "$module_path"; then
                log_error "Функция '$required_function' не найдена в модуле '$module_file'"
                return 1
            fi
        fi
    done

    return 0
}

# Тест 10: Симуляция сухого прогона установки
test_dry_run_installation() {
    local install_script="$PROJECT_ROOT/install.sh"

    if [[ ! -f "$install_script" ]]; then
        log_error "Главный установочный скрипт не найден"
        return 1
    fi

    # Попытка запустить скрипт с параметром помощи
    if grep -q "\-\-help\|\-h" "$install_script"; then
        if ! bash "$install_script" --help >/dev/null 2>&1; then
            log_error "Ошибка при выполнении install.sh --help"
            return 1
        fi
    fi

    return 0
}

# Главная функция тестирования
main() {
    log_info "Начало тестирования установки VLESS+Reality VPN"
    echo "Лог-файл: $TEST_LOG" > "$TEST_LOG"
    echo "Время начала: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    # Выполнение всех тестов
    run_test "Структура проекта" test_project_structure
    run_test "Синтаксис Bash скриптов" test_bash_syntax
    run_test "Права выполнения скриптов" test_script_permissions
    run_test "Системные зависимости" test_system_dependencies
    run_test "Конфигурационные файлы" test_config_files
    run_test "Синтаксис Python скриптов" test_python_syntax
    run_test "Права доступа к файлам" test_file_permissions
    run_test "Переменные окружения" test_environment_variables
    run_test "Целостность модулей" test_module_integrity
    run_test "Сухой прогон установки" test_dry_run_installation

    # Итоговый отчет
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ УСТАНОВКИ" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "Всего тестов выполнено: $TOTAL_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов провалено: $FAILED_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов пройдено: $((TOTAL_TESTS - FAILED_TESTS))" | tee -a "$TEST_LOG"
    echo "Время завершения: $(date)" | tee -a "$TEST_LOG"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "ВСЕ ТЕСТЫ УСТАНОВКИ ПРОЙДЕНЫ УСПЕШНО!"
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ УСТАНОВКИ"
        echo "Подробности в логе: $TEST_LOG"
        exit 1
    fi
}

# Проверка запуска от root (только предупреждение)
if [[ $EUID -eq 0 ]]; then
    log_warning "Тесты запущены от пользователя root"
fi

# Запуск главной функции
main "$@"
#!/bin/bash

# VLESS+Reality VPN - User Management Tests
# Комплексные тесты для модуля управления пользователями
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
TEST_LOG="/tmp/vless_user_management_test.log"
FAILED_TESTS=0
TOTAL_TESTS=0
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"
USER_MANAGEMENT_MODULE="$PROJECT_ROOT/modules/user_management.sh"
TEST_USERS_FILE="/tmp/test_users.json"
TEST_BACKUP_DIR="/tmp/vless_test_backup"

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

# Подготовка тестовой среды
setup_test_environment() {
    # Создание тестовых каталогов
    mkdir -p "$TEST_BACKUP_DIR"
    mkdir -p "$(dirname "$TEST_USERS_FILE")"

    # Создание тестового файла пользователей
    cat > "$TEST_USERS_FILE" << 'EOF'
{
  "users": [
    {
      "name": "test_user_1",
      "uuid": "12345678-1234-1234-1234-123456789abc",
      "created": "2025-09-19T10:00:00Z",
      "active": true
    }
  ]
}
EOF

    # Экспорт переменных для тестирования
    export VLESS_USERS_FILE="$TEST_USERS_FILE"
    export VLESS_BACKUP_DIR="$TEST_BACKUP_DIR"
}

# Очистка после тестов
cleanup_test_environment() {
    rm -rf "$TEST_BACKUP_DIR"
    rm -f "$TEST_USERS_FILE"
}

# Тест 1: Проверка существования модуля управления пользователями
test_module_exists() {
    if [[ ! -f "$USER_MANAGEMENT_MODULE" ]]; then
        log_error "Модуль управления пользователями не найден: $USER_MANAGEMENT_MODULE"
        return 1
    fi

    if [[ ! -x "$USER_MANAGEMENT_MODULE" ]]; then
        log_error "Модуль управления пользователями не исполняемый: $USER_MANAGEMENT_MODULE"
        return 1
    fi

    return 0
}

# Тест 2: Проверка синтаксиса модуля
test_module_syntax() {
    if ! bash -n "$USER_MANAGEMENT_MODULE" 2>/dev/null; then
        log_error "Ошибка синтаксиса в модуле управления пользователями"
        return 1
    fi

    return 0
}

# Тест 3: Проверка наличия основных функций
test_required_functions() {
    local required_functions=(
        "add_user"
        "remove_user"
        "list_users"
        "get_user_config"
        "validate_uuid"
        "generate_vless_link"
    )

    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || {
        log_error "Не удается загрузить модуль управления пользователями"
        return 1
    }

    for func in "${required_functions[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            log_error "Функция '$func' не найдена в модуле"
            return 1
        fi
    done

    return 0
}

# Тест 4: Тест добавления пользователя
test_add_user() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    # Добавление тестового пользователя
    local test_username="test_user_new"

    if ! add_user "$test_username" >/dev/null 2>&1; then
        log_error "Не удается добавить пользователя '$test_username'"
        return 1
    fi

    # Проверка, что пользователь добавлен в файл
    if ! grep -q "$test_username" "$TEST_USERS_FILE"; then
        log_error "Пользователь '$test_username' не найден в файле пользователей"
        return 1
    fi

    return 0
}

# Тест 5: Тест валидации UUID
test_uuid_validation() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    # Проверка валидного UUID
    local valid_uuid="12345678-1234-1234-1234-123456789abc"
    if ! validate_uuid "$valid_uuid" >/dev/null 2>&1; then
        log_error "Валидный UUID '$valid_uuid' не прошел валидацию"
        return 1
    fi

    # Проверка невалидного UUID
    local invalid_uuid="invalid-uuid"
    if validate_uuid "$invalid_uuid" >/dev/null 2>&1; then
        log_error "Невалидный UUID '$invalid_uuid' прошел валидацию"
        return 1
    fi

    return 0
}

# Тест 6: Тест листинга пользователей
test_list_users() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    local users_output
    users_output=$(list_users 2>/dev/null) || {
        log_error "Не удается получить список пользователей"
        return 1
    }

    # Проверка, что вывод содержит тестового пользователя
    if ! echo "$users_output" | grep -q "test_user_1"; then
        log_error "Тестовый пользователь не найден в списке пользователей"
        return 1
    fi

    return 0
}

# Тест 7: Тест получения конфигурации пользователя
test_get_user_config() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    local test_uuid="12345678-1234-1234-1234-123456789abc"
    local config_output

    config_output=$(get_user_config "$test_uuid" 2>/dev/null) || {
        log_error "Не удается получить конфигурацию для UUID '$test_uuid'"
        return 1
    }

    # Проверка, что вывод содержит UUID
    if ! echo "$config_output" | grep -q "$test_uuid"; then
        log_error "Конфигурация не содержит указанный UUID"
        return 1
    fi

    return 0
}

# Тест 8: Тест генерации VLESS ссылки
test_generate_vless_link() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    local test_uuid="12345678-1234-1234-1234-123456789abc"
    local vless_link

    vless_link=$(generate_vless_link "$test_uuid" "example.com" "443" 2>/dev/null) || {
        log_error "Не удается сгенерировать VLESS ссылку"
        return 1
    }

    # Проверка формата ссылки
    if ! echo "$vless_link" | grep -q "^vless://"; then
        log_error "VLESS ссылка имеет неправильный формат"
        return 1
    fi

    # Проверка наличия UUID в ссылке
    if ! echo "$vless_link" | grep -q "$test_uuid"; then
        log_error "VLESS ссылка не содержит UUID"
        return 1
    fi

    return 0
}

# Тест 9: Тест удаления пользователя
test_remove_user() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    local test_uuid="12345678-1234-1234-1234-123456789abc"

    if ! remove_user "$test_uuid" >/dev/null 2>&1; then
        log_error "Не удается удалить пользователя с UUID '$test_uuid'"
        return 1
    fi

    # Проверка, что пользователь удален из файла
    if grep -q "$test_uuid" "$TEST_USERS_FILE"; then
        log_error "Пользователь с UUID '$test_uuid' все еще найден в файле"
        return 1
    fi

    return 0
}

# Тест 10: Тест обработки ошибок
test_error_handling() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    # Попытка добавить пользователя с пустым именем
    if add_user "" >/dev/null 2>&1; then
        log_error "Функция add_user должна отклонять пустые имена"
        return 1
    fi

    # Попытка удалить несуществующего пользователя
    local nonexistent_uuid="99999999-9999-9999-9999-999999999999"
    if remove_user "$nonexistent_uuid" >/dev/null 2>&1; then
        log_warning "Функция remove_user не проверяет существование пользователя"
    fi

    return 0
}

# Тест 11: Тест работы с JSON файлом
test_json_operations() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    # Проверка, что файл пользователей является валидным JSON
    if ! jq . "$TEST_USERS_FILE" >/dev/null 2>&1; then
        log_error "Файл пользователей не является валидным JSON"
        return 1
    fi

    # Проверка структуры JSON
    local users_count
    users_count=$(jq '.users | length' "$TEST_USERS_FILE" 2>/dev/null) || {
        log_error "Неправильная структура JSON в файле пользователей"
        return 1
    }

    if [[ "$users_count" -lt 0 ]]; then
        log_error "Некорректное количество пользователей в JSON"
        return 1
    fi

    return 0
}

# Тест 12: Тест резервного копирования пользователей
test_user_backup() {
    source "$USER_MANAGEMENT_MODULE" 2>/dev/null || return 1

    # Если функция backup_users существует, тестируем ее
    if declare -f backup_users >/dev/null 2>&1; then
        if ! backup_users >/dev/null 2>&1; then
            log_error "Не удается создать резервную копию пользователей"
            return 1
        fi

        # Проверка, что файл резервной копии создан
        if [[ ! -f "$TEST_BACKUP_DIR/users_backup_"*.json ]]; then
            log_error "Файл резервной копии пользователей не создан"
            return 1
        fi
    else
        log_warning "Функция backup_users не найдена, пропускаем тест"
    fi

    return 0
}

# Главная функция тестирования
main() {
    log_info "Начало тестирования модуля управления пользователями VLESS+Reality VPN"
    echo "Лог-файл: $TEST_LOG" > "$TEST_LOG"
    echo "Время начала: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    # Подготовка тестовой среды
    setup_test_environment

    # Выполнение всех тестов
    run_test "Существование модуля" test_module_exists
    run_test "Синтаксис модуля" test_module_syntax
    run_test "Наличие обязательных функций" test_required_functions
    run_test "Добавление пользователя" test_add_user
    run_test "Валидация UUID" test_uuid_validation
    run_test "Листинг пользователей" test_list_users
    run_test "Получение конфигурации пользователя" test_get_user_config
    run_test "Генерация VLESS ссылки" test_generate_vless_link
    run_test "Удаление пользователя" test_remove_user
    run_test "Обработка ошибок" test_error_handling
    run_test "Операции с JSON" test_json_operations
    run_test "Резервное копирование пользователей" test_user_backup

    # Очистка тестовой среды
    cleanup_test_environment

    # Итоговый отчет
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "Всего тестов выполнено: $TOTAL_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов провалено: $FAILED_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов пройдено: $((TOTAL_TESTS - FAILED_TESTS))" | tee -a "$TEST_LOG"
    echo "Время завершения: $(date)" | tee -a "$TEST_LOG"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "ВСЕ ТЕСТЫ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ ПРОЙДЕНЫ УСПЕШНО!"
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ"
        echo "Подробности в логе: $TEST_LOG"
        exit 1
    fi
}

# Проверка наличия jq
if ! command -v jq >/dev/null 2>&1; then
    echo "Для тестирования необходима утилита jq. Установите ее: sudo apt-get install jq"
    exit 1
fi

# Запуск главной функции
main "$@"
#!/bin/bash

# VLESS+Reality VPN - Master Test Runner
# Запуск всех тестов и создание итогового отчета
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
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"
MASTER_LOG="/tmp/vless_master_test.log"
REPORT_FILE="$PROJECT_ROOT/tests/test_results.md"
TESTS_DIR="$PROJECT_ROOT/tests"

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$MASTER_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$MASTER_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$MASTER_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$MASTER_LOG"
}

# Список тестов для выполнения
declare -A TESTS=(
    ["installation"]="test_installation.sh"
    ["user_management"]="test_user_management.sh"
    ["telegram_bot"]="test_telegram_bot.py"
    ["docker_services"]="test_docker_services.sh"
    ["security"]="test_security.sh"
    ["backup_restore"]="test_backup_restore.sh"
)

# Результаты тестов
declare -A TEST_RESULTS=()
declare -A TEST_DETAILS=()

# Функция запуска отдельного теста
run_single_test() {
    local test_name="$1"
    local test_script="$2"
    local test_path="$TESTS_DIR/$test_script"

    log_info "Запуск теста: $test_name"

    if [[ ! -f "$test_path" ]]; then
        log_error "Тест не найден: $test_path"
        TEST_RESULTS["$test_name"]="NOT_FOUND"
        TEST_DETAILS["$test_name"]="Файл теста не найден"
        return 1
    fi

    if [[ ! -x "$test_path" ]]; then
        log_error "Тест не исполняемый: $test_path"
        TEST_RESULTS["$test_name"]="NOT_EXECUTABLE"
        TEST_DETAILS["$test_name"]="Файл теста не имеет прав выполнения"
        return 1
    fi

    # Запуск теста с таймаутом
    local test_output
    local test_exit_code

    if [[ "$test_script" == *.py ]]; then
        # Python тест
        test_output=$(timeout 120 python3 "$test_path" 2>&1) || test_exit_code=$?
    else
        # Bash тест
        test_output=$(timeout 120 bash "$test_path" 2>&1) || test_exit_code=$?
    fi

    test_exit_code=${test_exit_code:-0}

    if [[ $test_exit_code -eq 0 ]]; then
        log_success "Тест '$test_name' пройден успешно"
        TEST_RESULTS["$test_name"]="PASSED"
        TEST_DETAILS["$test_name"]="Все тесты пройдены успешно"
    elif [[ $test_exit_code -eq 124 ]]; then
        log_error "Тест '$test_name' превысил время ожидания"
        TEST_RESULTS["$test_name"]="TIMEOUT"
        TEST_DETAILS["$test_name"]="Тест превысил время ожидания (120 сек)"
    else
        log_error "Тест '$test_name' провален (код: $test_exit_code)"
        TEST_RESULTS["$test_name"]="FAILED"
        TEST_DETAILS["$test_name"]="Тест завершился с ошибкой (код: $test_exit_code)"
    fi

    # Сохранение подробного вывода
    echo "=== Результат теста $test_name ===" >> "$MASTER_LOG"
    echo "$test_output" >> "$MASTER_LOG"
    echo "=== Конец результата теста $test_name ===" >> "$MASTER_LOG"
    echo "" >> "$MASTER_LOG"

    return $test_exit_code
}

# Функция проверки синтаксиса
check_syntax() {
    log_info "Проверка синтаксиса всех скриптов..."

    local syntax_errors=0

    # Проверка Bash скриптов
    while IFS= read -r -d '' bash_file; do
        if ! bash -n "$bash_file" 2>/dev/null; then
            log_error "Ошибка синтаксиса в bash файле: $bash_file"
            ((syntax_errors++))
        fi
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f -print0)

    # Проверка Python скриптов
    while IFS= read -r -d '' python_file; do
        if ! python3 -m py_compile "$python_file" 2>/dev/null; then
            log_error "Ошибка синтаксиса в Python файле: $python_file"
            ((syntax_errors++))
        fi
    done < <(find "$PROJECT_ROOT" -name "*.py" -type f -print0)

    if [[ $syntax_errors -eq 0 ]]; then
        log_success "Проверка синтаксиса завершена без ошибок"
        return 0
    else
        log_error "Найдено ошибок синтаксиса: $syntax_errors"
        return 1
    fi
}

# Функция создания отчета
generate_report() {
    log_info "Создание итогового отчета..."

    cat > "$REPORT_FILE" << EOF
# Отчет о тестировании VLESS+Reality VPN

**Дата тестирования:** $(date)
**Система:** $(uname -a)
**Пользователь:** $(whoami)

## Обзор результатов

EOF

    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local timeout_tests=0
    local not_found_tests=0

    for test_name in "${!TEST_RESULTS[@]}"; do
        ((total_tests++))
        case "${TEST_RESULTS[$test_name]}" in
            "PASSED") ((passed_tests++)) ;;
            "FAILED") ((failed_tests++)) ;;
            "TIMEOUT") ((timeout_tests++)) ;;
            "NOT_FOUND"|"NOT_EXECUTABLE") ((not_found_tests++)) ;;
        esac
    done

    cat >> "$REPORT_FILE" << EOF
- **Всего тестов:** $total_tests
- **Пройдено:** $passed_tests
- **Провалено:** $failed_tests
- **Превышено время:** $timeout_tests
- **Не найдено/не исполняемо:** $not_found_tests

## Детальные результаты

| Тест | Статус | Описание |
|------|--------|----------|
EOF

    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local details="${TEST_DETAILS[$test_name]}"

        local status_emoji
        case "$status" in
            "PASSED") status_emoji="✅" ;;
            "FAILED") status_emoji="❌" ;;
            "TIMEOUT") status_emoji="⏰" ;;
            *) status_emoji="❓" ;;
        esac

        echo "| $test_name | $status_emoji $status | $details |" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" << EOF

## Проверка синтаксиса

EOF

    if check_syntax; then
        echo "✅ **Синтаксис всех скриптов корректен**" >> "$REPORT_FILE"
    else
        echo "❌ **Найдены ошибки синтаксиса в скриптах**" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF

## Структура проекта

\`\`\`
$(tree "$PROJECT_ROOT" -I '__pycache__|*.pyc' 2>/dev/null || find "$PROJECT_ROOT" -type f -name "*.sh" -o -name "*.py" -o -name "*.json" -o -name "*.yml" | head -20)
\`\`\`

## Рекомендации

EOF

    if [[ $failed_tests -gt 0 || $timeout_tests -gt 0 || $not_found_tests -gt 0 ]]; then
        cat >> "$REPORT_FILE" << EOF
### Критические проблемы

EOF
        for test_name in "${!TEST_RESULTS[@]}"; do
            if [[ "${TEST_RESULTS[$test_name]}" != "PASSED" ]]; then
                echo "- **$test_name**: ${TEST_DETAILS[$test_name]}" >> "$REPORT_FILE"
            fi
        done
    fi

    cat >> "$REPORT_FILE" << EOF

### Общие рекомендации

1. Убедитесь, что все зависимости установлены
2. Проверьте права доступа к файлам
3. Запустите тесты от имени соответствующего пользователя
4. Проверьте логи тестирования в \`$MASTER_LOG\`

## Заключение

EOF

    if [[ $passed_tests -eq $total_tests && $total_tests -gt 0 ]]; then
        echo "🎉 **Все тесты пройдены успешно! Система готова к развертыванию.**" >> "$REPORT_FILE"
    elif [[ $passed_tests -gt 0 ]]; then
        echo "⚠️ **Тестирование завершено с предупреждениями. Требуется внимание к проваленным тестам.**" >> "$REPORT_FILE"
    else
        echo "🚨 **Критические проблемы обнаружены. Система не готова к развертыванию.**" >> "$REPORT_FILE"
    fi

    log_success "Отчет создан: $REPORT_FILE"
}

# Главная функция
main() {
    log_info "Начало комплексного тестирования VLESS+Reality VPN"
    echo "Мастер-лог: $MASTER_LOG" > "$MASTER_LOG"
    echo "Время начала: $(date)" >> "$MASTER_LOG"
    echo "========================================" >> "$MASTER_LOG"

    # Проверка синтаксиса
    check_syntax

    # Запуск всех тестов
    for test_name in "${!TESTS[@]}"; do
        run_single_test "$test_name" "${TESTS[$test_name]}"
        echo "" # Пустая строка для разделения
    done

    # Генерация отчета
    generate_report

    # Итоговая статистика
    local total_tests=${#TESTS[@]}
    local passed_count=0

    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "${TEST_RESULTS[$test_name]}" == "PASSED" ]]; then
            ((passed_count++))
        fi
    done

    echo ""
    echo "=========================================="
    echo "ИТОГОВАЯ СТАТИСТИКА ТЕСТИРОВАНИЯ"
    echo "=========================================="
    echo "Всего тестов: $total_tests"
    echo "Пройдено: $passed_count"
    echo "Провалено: $((total_tests - passed_count))"
    echo "Отчет: $REPORT_FILE"
    echo "Лог: $MASTER_LOG"
    echo "=========================================="

    if [[ $passed_count -eq $total_tests ]]; then
        log_success "ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!"
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ"
        exit 1
    fi
}

# Проверка запуска из правильного каталога
if [[ ! -f "$PROJECT_ROOT/install.sh" ]]; then
    echo "Ошибка: Запустите скрипт из корневого каталога проекта"
    echo "Ожидаемый каталог: $PROJECT_ROOT"
    exit 1
fi

# Запуск главной функции
main "$@"
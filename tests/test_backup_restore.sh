#!/bin/bash

# VLESS+Reality VPN - Backup & Restore Tests
# Комплексные тесты системы резервного копирования и восстановления
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
TEST_LOG="/tmp/vless_backup_restore_test.log"
FAILED_TESTS=0
TOTAL_TESTS=0
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"
BACKUP_MODULE="$PROJECT_ROOT/modules/backup_restore.sh"
TEST_BACKUP_DIR="/tmp/vless_test_backups"
TEST_DATA_DIR="/tmp/vless_test_data"

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
    mkdir -p "$TEST_DATA_DIR"
    mkdir -p "$TEST_DATA_DIR/configs"
    mkdir -p "$TEST_DATA_DIR/users"
    mkdir -p "$TEST_DATA_DIR/certs"

    # Создание тестовых файлов
    cat > "$TEST_DATA_DIR/configs/test_config.json" << 'EOF'
{
  "test": "configuration",
  "version": "1.0"
}
EOF

    cat > "$TEST_DATA_DIR/users/test_users.json" << 'EOF'
{
  "users": [
    {
      "name": "test_user",
      "uuid": "12345678-1234-1234-1234-123456789abc",
      "created": "2025-09-19T10:00:00Z"
    }
  ]
}
EOF

    echo "test certificate data" > "$TEST_DATA_DIR/certs/test_cert.pem"

    # Экспорт переменных для тестирования
    export VLESS_DATA_DIR="$TEST_DATA_DIR"
    export VLESS_BACKUP_DIR="$TEST_BACKUP_DIR"
}

# Очистка тестовой среды
cleanup_test_environment() {
    rm -rf "$TEST_BACKUP_DIR"
    rm -rf "$TEST_DATA_DIR"
}

# Тест 1: Проверка модуля резервного копирования
test_backup_module_exists() {
    if [[ ! -f "$BACKUP_MODULE" ]]; then
        log_error "Модуль резервного копирования не найден: $BACKUP_MODULE"
        return 1
    fi

    if [[ ! -x "$BACKUP_MODULE" ]]; then
        log_error "Модуль резервного копирования не исполняемый: $BACKUP_MODULE"
        return 1
    fi

    # Проверка синтаксиса
    if ! bash -n "$BACKUP_MODULE" 2>/dev/null; then
        log_error "Ошибка синтаксиса в модуле резервного копирования"
        return 1
    fi

    return 0
}

# Тест 2: Проверка наличия основных функций
test_backup_functions() {
    local required_functions=(
        "create_backup"
        "restore_backup"
        "list_backups"
        "cleanup_old_backups"
    )

    source "$BACKUP_MODULE" 2>/dev/null || {
        log_error "Не удается загрузить модуль резервного копирования"
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

# Тест 3: Тест создания резервной копии
test_backup_creation() {
    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Создание резервной копии
    if ! create_backup >/dev/null 2>&1; then
        log_error "Не удается создать резервную копию"
        return 1
    fi

    # Проверка, что резервная копия создана
    local backup_files
    backup_files=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" -o -name "*.zip" 2>/dev/null | wc -l)

    if [[ "$backup_files" -eq 0 ]]; then
        log_error "Файлы резервной копии не найдены"
        return 1
    fi

    log_info "Создано файлов резервной копии: $backup_files"
    return 0
}

# Тест 4: Тест целостности резервной копии
test_backup_integrity() {
    # Поиск последней резервной копии
    local latest_backup
    latest_backup=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -z "$latest_backup" ]]; then
        log_error "Не найдены файлы резервной копии для проверки"
        return 1
    fi

    # Проверка целостности архива
    if file "$latest_backup" | grep -q "gzip compressed"; then
        if tar -tzf "$latest_backup" >/dev/null 2>&1; then
            log_info "Резервная копия является валидным tar.gz архивом"
        else
            log_error "Резервная копия повреждена (tar.gz)"
            return 1
        fi
    elif file "$latest_backup" | grep -q "Zip archive"; then
        if unzip -t "$latest_backup" >/dev/null 2>&1; then
            log_info "Резервная копия является валидным zip архивом"
        else
            log_error "Резервная копия повреждена (zip)"
            return 1
        fi
    else
        log_warning "Неизвестный формат резервной копии"
    fi

    # Проверка размера архива
    local backup_size
    backup_size=$(stat -c "%s" "$latest_backup")

    if [[ "$backup_size" -lt 100 ]]; then
        log_error "Резервная копия слишком мала: ${backup_size} байт"
        return 1
    fi

    log_info "Размер резервной копии: ${backup_size} байт"
    return 0
}

# Тест 5: Тест содержимого резервной копии
test_backup_content() {
    # Поиск последней резервной копии
    local latest_backup
    latest_backup=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -z "$latest_backup" ]]; then
        log_error "Не найдены файлы резервной копии для проверки содержимого"
        return 1
    fi

    # Создание временного каталога для извлечения
    local temp_extract_dir
    temp_extract_dir=$(mktemp -d)

    # Извлечение архива
    if tar -xzf "$latest_backup" -C "$temp_extract_dir" 2>/dev/null; then
        log_info "Резервная копия успешно извлечена"

        # Проверка наличия ключевых файлов
        local expected_files=(
            "configs"
            "users"
            "certs"
        )

        for file_or_dir in "${expected_files[@]}"; do
            if [[ -e "$temp_extract_dir/$file_or_dir" ]]; then
                log_info "Найден в резервной копии: $file_or_dir"
            else
                log_warning "Отсутствует в резервной копии: $file_or_dir"
            fi
        done

        # Очистка временного каталога
        rm -rf "$temp_extract_dir"
    else
        log_error "Не удается извлечь резервную копию"
        rm -rf "$temp_extract_dir"
        return 1
    fi

    return 0
}

# Тест 6: Тест восстановления из резервной копии
test_backup_restore() {
    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Поиск резервной копии для восстановления
    local backup_to_restore
    backup_to_restore=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" -type f | head -1)

    if [[ -z "$backup_to_restore" ]]; then
        log_error "Не найдены файлы резервной копии для восстановления"
        return 1
    fi

    # Создание каталога для восстановления
    local restore_dir
    restore_dir=$(mktemp -d)

    # Попытка восстановления
    if restore_backup "$backup_to_restore" "$restore_dir" >/dev/null 2>&1; then
        log_info "Восстановление из резервной копии выполнено"

        # Проверка восстановленных файлов
        if [[ -d "$restore_dir" ]] && [[ "$(ls -A "$restore_dir" 2>/dev/null)" ]]; then
            log_info "Файлы успешно восстановлены"
        else
            log_error "Каталог восстановления пуст"
            rm -rf "$restore_dir"
            return 1
        fi

        # Очистка
        rm -rf "$restore_dir"
    else
        log_error "Не удается восстановить из резервной копии"
        rm -rf "$restore_dir"
        return 1
    fi

    return 0
}

# Тест 7: Тест листинга резервных копий
test_backup_listing() {
    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Получение списка резервных копий
    local backup_list
    backup_list=$(list_backups 2>/dev/null)

    if [[ -n "$backup_list" ]]; then
        log_info "Список резервных копий получен"
        log_info "Количество строк в списке: $(echo "$backup_list" | wc -l)"
    else
        log_warning "Список резервных копий пуст"
    fi

    return 0
}

# Тест 8: Тест очистки старых резервных копий
test_backup_cleanup() {
    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Создание нескольких тестовых резервных копий разного возраста
    for i in {1..5}; do
        local test_backup="$TEST_BACKUP_DIR/test_backup_${i}_$(date +%Y%m%d_%H%M%S).tar.gz"
        echo "test backup content $i" | gzip > "$test_backup"
        # Изменение времени модификации для имитации старых файлов
        touch -d "$i days ago" "$test_backup"
    done

    # Подсчет резервных копий до очистки
    local backups_before
    backups_before=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" | wc -l)

    # Выполнение очистки (оставляем только файлы младше 3 дней)
    if cleanup_old_backups 3 >/dev/null 2>&1; then
        log_info "Очистка старых резервных копий выполнена"

        # Подсчет резервных копий после очистки
        local backups_after
        backups_after=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" | wc -l)

        log_info "Резервных копий до очистки: $backups_before"
        log_info "Резервных копий после очистки: $backups_after"

        if [[ "$backups_after" -lt "$backups_before" ]]; then
            log_info "Старые резервные копии успешно удалены"
        else
            log_warning "Количество резервных копий не изменилось"
        fi
    else
        log_error "Не удается выполнить очистку старых резервных копий"
        return 1
    fi

    return 0
}

# Тест 9: Тест автоматического резервного копирования
test_automatic_backup() {
    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Если функция автоматического резервного копирования существует
    if declare -f setup_automatic_backup >/dev/null 2>&1; then
        # Проверка настройки автоматического резервного копирования
        if setup_automatic_backup >/dev/null 2>&1; then
            log_info "Автоматическое резервное копирование настроено"
        else
            log_warning "Не удается настроить автоматическое резервное копирование"
        fi
    else
        log_warning "Функция автоматического резервного копирования не найдена"
    fi

    return 0
}

# Тест 10: Тест сжатия резервных копий
test_backup_compression() {
    # Создание несжатого тестового файла
    local test_file="$TEST_DATA_DIR/large_test_file.txt"
    for i in {1..1000}; do
        echo "This is test line number $i with some repetitive content" >> "$test_file"
    done

    local original_size
    original_size=$(stat -c "%s" "$test_file")

    # Создание резервной копии
    source "$BACKUP_MODULE" 2>/dev/null || return 1
    create_backup >/dev/null 2>&1

    # Поиск созданной резервной копии
    local latest_backup
    latest_backup=$(find "$TEST_BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -n "$latest_backup" ]]; then
        local compressed_size
        compressed_size=$(stat -c "%s" "$latest_backup")

        # Проверка эффективности сжатия
        if [[ "$compressed_size" -lt "$original_size" ]]; then
            local compression_ratio
            compression_ratio=$((100 - (compressed_size * 100 / original_size)))
            log_info "Сжатие эффективно: коэффициент сжатия ${compression_ratio}%"
        else
            log_warning "Сжатие неэффективно или не работает"
        fi
    fi

    return 0
}

# Тест 11: Тест резервного копирования при недостатке места
test_backup_disk_space() {
    # Проверка доступного места
    local available_space
    available_space=$(df "$TEST_BACKUP_DIR" | awk 'NR==2 {print $4}')

    log_info "Доступное место для резервных копий: ${available_space}KB"

    # Если места мало, тестируем обработку ошибки
    if [[ "$available_space" -lt 1048576 ]]; then  # Менее 1GB
        log_warning "Мало места для резервных копий"

        # Попытка создания резервной копии при недостатке места
        source "$BACKUP_MODULE" 2>/dev/null || return 1

        if ! create_backup >/dev/null 2>&1; then
            log_info "Модуль корректно обработал недостаток места"
        else
            log_warning "Модуль не проверяет доступное место"
        fi
    else
        log_info "Достаточно места для резервных копий"
    fi

    return 0
}

# Тест 12: Тест восстановления поврежденной резервной копии
test_corrupted_backup_handling() {
    # Создание поврежденного файла резервной копии
    local corrupted_backup="$TEST_BACKUP_DIR/corrupted_backup.tar.gz"
    echo "This is not a valid gzip file" > "$corrupted_backup"

    source "$BACKUP_MODULE" 2>/dev/null || return 1

    # Попытка восстановления из поврежденной резервной копии
    local restore_dir
    restore_dir=$(mktemp -d)

    if restore_backup "$corrupted_backup" "$restore_dir" >/dev/null 2>&1; then
        log_error "Модуль должен отклонять поврежденные резервные копии"
        rm -rf "$restore_dir"
        return 1
    else
        log_info "Модуль корректно обработал поврежденную резервную копию"
        rm -rf "$restore_dir"
    fi

    # Очистка поврежденного файла
    rm -f "$corrupted_backup"

    return 0
}

# Главная функция тестирования
main() {
    log_info "Начало тестирования системы резервного копирования VLESS+Reality VPN"
    echo "Лог-файл: $TEST_LOG" > "$TEST_LOG"
    echo "Время начала: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    # Подготовка тестовой среды
    setup_test_environment

    # Выполнение всех тестов
    run_test "Модуль резервного копирования" test_backup_module_exists
    run_test "Функции модуля" test_backup_functions
    run_test "Создание резервной копии" test_backup_creation
    run_test "Целостность резервной копии" test_backup_integrity
    run_test "Содержимое резервной копии" test_backup_content
    run_test "Восстановление из резервной копии" test_backup_restore
    run_test "Листинг резервных копий" test_backup_listing
    run_test "Очистка старых резервных копий" test_backup_cleanup
    run_test "Автоматическое резервное копирование" test_automatic_backup
    run_test "Сжатие резервных копий" test_backup_compression
    run_test "Обработка недостатка места" test_backup_disk_space
    run_test "Обработка поврежденных резервных копий" test_corrupted_backup_handling

    # Очистка тестовой среды
    cleanup_test_environment

    # Итоговый отчет
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ РЕЗЕРВНОГО КОПИРОВАНИЯ" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "Всего тестов выполнено: $TOTAL_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов провалено: $FAILED_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов пройдено: $((TOTAL_TESTS - FAILED_TESTS))" | tee -a "$TEST_LOG"
    echo "Время завершения: $(date)" | tee -a "$TEST_LOG"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "ВСЕ ТЕСТЫ РЕЗЕРВНОГО КОПИРОВАНИЯ ПРОЙДЕНЫ УСПЕШНО!"
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ РЕЗЕРВНОГО КОПИРОВАНИЯ"
        echo "Подробности в логе: $TEST_LOG"
        exit 1
    fi
}

# Проверка наличия необходимых утилит
for util in tar gzip; do
    if ! command -v "$util" >/dev/null 2>&1; then
        echo "Для тестирования необходима утилита: $util"
        exit 1
    fi
done

# Запуск главной функции
main "$@"
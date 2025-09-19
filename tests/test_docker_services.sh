#!/bin/bash

# VLESS+Reality VPN - Docker Services Tests
# Комплексные тесты для Docker контейнеров и сервисов
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
TEST_LOG="/tmp/vless_docker_services_test.log"
FAILED_TESTS=0
TOTAL_TESTS=0
PROJECT_ROOT="/home/ikeniborn/Documents/Project/vless"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/config/docker-compose.yml"
TEST_CONTAINER_PREFIX="vless_test"

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

# Функция очистки Docker ресурсов
cleanup_docker_resources() {
    log_info "Очистка Docker тестовых ресурсов..."

    # Остановка и удаление тестовых контейнеров
    docker ps -a --filter "name=${TEST_CONTAINER_PREFIX}" --format "{{.ID}}" | while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            docker stop "$container_id" >/dev/null 2>&1 || true
            docker rm "$container_id" >/dev/null 2>&1 || true
        fi
    done

    # Удаление тестовых образов
    docker images --filter "dangling=true" --format "{{.ID}}" | while read -r image_id; do
        if [[ -n "$image_id" ]]; then
            docker rmi "$image_id" >/dev/null 2>&1 || true
        fi
    done

    # Очистка неиспользуемых сетей
    docker network prune -f >/dev/null 2>&1 || true
}

# Тест 1: Проверка установки Docker
test_docker_installation() {
    # Проверка наличия Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker не установлен"
        return 1
    fi

    # Проверка запуска Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon не запущен"
        return 1
    fi

    # Проверка версии Docker
    local docker_version
    docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)

    if [[ -z "$docker_version" ]]; then
        log_error "Не удается определить версию Docker"
        return 1
    fi

    log_info "Версия Docker: $docker_version"
    return 0
}

# Тест 2: Проверка Docker Compose
test_docker_compose() {
    # Проверка наличия Docker Compose (v2)
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short)
        log_info "Версия Docker Compose: $compose_version"
        return 0
    elif command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
        log_info "Версия Docker Compose (legacy): $compose_version"
        return 0
    else
        log_error "Docker Compose не установлен"
        return 1
    fi
}

# Тест 3: Проверка конфигурации Docker Compose
test_docker_compose_config() {
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log_error "Файл docker-compose.yml не найден: $DOCKER_COMPOSE_FILE"
        return 1
    fi

    # Проверка синтаксиса docker-compose.yml
    if docker compose -f "$DOCKER_COMPOSE_FILE" config >/dev/null 2>&1; then
        log_info "Конфигурация Docker Compose валидна"
    elif command -v docker-compose >/dev/null 2>&1 && docker-compose -f "$DOCKER_COMPOSE_FILE" config >/dev/null 2>&1; then
        log_info "Конфигурация Docker Compose валидна (legacy)"
    else
        log_error "Ошибка в конфигурации Docker Compose"
        return 1
    fi

    # Проверка наличия обязательных сервисов
    local required_services=("xray" "telegram-bot")

    for service in "${required_services[@]}"; do
        if docker compose -f "$DOCKER_COMPOSE_FILE" config --services 2>/dev/null | grep -q "^${service}$"; then
            log_info "Сервис '$service' найден в конфигурации"
        elif command -v docker-compose >/dev/null 2>&1 && docker-compose -f "$DOCKER_COMPOSE_FILE" config --services 2>/dev/null | grep -q "^${service}$"; then
            log_info "Сервис '$service' найден в конфигурации (legacy)"
        else
            log_warning "Сервис '$service' не найден в конфигурации"
        fi
    done

    return 0
}

# Тест 4: Проверка Docker образов
test_docker_images() {
    local required_images=(
        "teddysun/xray:latest"
        "python:3.11-slim"
    )

    for image in "${required_images[@]}"; do
        log_info "Проверка доступности образа: $image"

        # Попытка загрузить образ
        if docker pull "$image" >/dev/null 2>&1; then
            log_info "Образ '$image' успешно загружен"
        else
            log_warning "Не удается загрузить образ '$image'"
        fi
    done

    return 0
}

# Тест 5: Проверка Docker сетей
test_docker_networks() {
    # Создание тестовой сети
    local test_network="${TEST_CONTAINER_PREFIX}_network"

    if docker network create "$test_network" >/dev/null 2>&1; then
        log_info "Тестовая сеть '$test_network' создана"

        # Проверка списка сетей
        if docker network ls | grep -q "$test_network"; then
            log_info "Тестовая сеть отображается в списке"
        else
            log_error "Тестовая сеть не найдена в списке"
            return 1
        fi

        # Удаление тестовой сети
        if docker network rm "$test_network" >/dev/null 2>&1; then
            log_info "Тестовая сеть удалена"
        else
            log_warning "Не удается удалить тестовую сеть"
        fi
    else
        log_error "Не удается создать тестовую сеть"
        return 1
    fi

    return 0
}

# Тест 6: Проверка Docker volumes
test_docker_volumes() {
    # Создание тестового volume
    local test_volume="${TEST_CONTAINER_PREFIX}_volume"

    if docker volume create "$test_volume" >/dev/null 2>&1; then
        log_info "Тестовый volume '$test_volume' создан"

        # Проверка списка volumes
        if docker volume ls | grep -q "$test_volume"; then
            log_info "Тестовый volume отображается в списке"
        else
            log_error "Тестовый volume не найден в списке"
            return 1
        fi

        # Удаление тестового volume
        if docker volume rm "$test_volume" >/dev/null 2>&1; then
            log_info "Тестовый volume удален"
        else
            log_warning "Не удается удалить тестовый volume"
        fi
    else
        log_error "Не удается создать тестовый volume"
        return 1
    fi

    return 0
}

# Тест 7: Тест запуска простого контейнера
test_container_lifecycle() {
    local test_container="${TEST_CONTAINER_PREFIX}_hello"

    # Запуск тестового контейнера
    if docker run --name "$test_container" --rm -d alpine:latest sleep 10 >/dev/null 2>&1; then
        log_info "Тестовый контейнер '$test_container' запущен"

        # Проверка статуса контейнера
        if docker ps | grep -q "$test_container"; then
            log_info "Тестовый контейнер активен"
        else
            log_error "Тестовый контейнер не активен"
            return 1
        fi

        # Ожидание завершения контейнера
        sleep 2

        # Выполнение команды в контейнере
        if docker exec "$test_container" echo "Hello from container" >/dev/null 2>&1; then
            log_info "Команда выполнена в контейнере"
        else
            log_warning "Не удается выполнить команду в контейнере"
        fi

        # Остановка контейнера
        if docker stop "$test_container" >/dev/null 2>&1; then
            log_info "Тестовый контейнер остановлен"
        else
            log_warning "Не удается остановить тестовый контейнер"
        fi
    else
        log_error "Не удается запустить тестовый контейнер"
        return 1
    fi

    return 0
}

# Тест 8: Проверка портов и bind
test_port_binding() {
    local test_container="${TEST_CONTAINER_PREFIX}_nginx"
    local test_port="18080"

    # Запуск контейнера с привязкой порта
    if docker run --name "$test_container" -d -p "${test_port}:80" nginx:alpine >/dev/null 2>&1; then
        log_info "Тестовый контейнер с привязкой порта запущен"

        # Ожидание запуска сервиса
        sleep 3

        # Проверка доступности порта
        if curl -s "http://localhost:${test_port}" >/dev/null 2>&1; then
            log_info "Порт ${test_port} доступен"
        else
            log_warning "Порт ${test_port} недоступен"
        fi

        # Остановка и удаление контейнера
        docker stop "$test_container" >/dev/null 2>&1
        docker rm "$test_container" >/dev/null 2>&1
    else
        log_error "Не удается запустить контейнер с привязкой порта"
        return 1
    fi

    return 0
}

# Тест 9: Проверка переменных окружения
test_environment_variables() {
    local test_container="${TEST_CONTAINER_PREFIX}_env"
    local test_env_var="TEST_VAR=hello_world"

    # Запуск контейнера с переменной окружения
    if docker run --name "$test_container" --rm -d -e "$test_env_var" alpine:latest sleep 5 >/dev/null 2>&1; then
        log_info "Тестовый контейнер с переменной окружения запущен"

        # Проверка переменной окружения
        if docker exec "$test_container" env | grep -q "TEST_VAR=hello_world"; then
            log_info "Переменная окружения установлена корректно"
        else
            log_error "Переменная окружения не установлена"
            return 1
        fi

        # Остановка контейнера
        docker stop "$test_container" >/dev/null 2>&1
    else
        log_error "Не удается запустить контейнер с переменной окружения"
        return 1
    fi

    return 0
}

# Тест 10: Проверка ресурсов системы
test_system_resources() {
    # Проверка доступной памяти
    local available_memory
    available_memory=$(free -m | awk '/^Mem:/{print $7}')

    if [[ "$available_memory" -lt 512 ]]; then
        log_warning "Доступно мало памяти: ${available_memory}MB"
    else
        log_info "Доступная память: ${available_memory}MB"
    fi

    # Проверка дискового пространства
    local available_space
    available_space=$(df / | awk '/\/$/{print $4}')

    if [[ "$available_space" -lt 1048576 ]]; then  # Менее 1GB
        log_warning "Доступно мало дискового пространства: ${available_space}KB"
    else
        log_info "Доступное дисковое пространство: ${available_space}KB"
    fi

    # Проверка использования Docker
    local docker_info
    docker_info=$(docker system df 2>/dev/null || echo "Docker system info unavailable")
    log_info "Информация о Docker: $docker_info"

    return 0
}

# Тест 11: Проверка логов контейнеров
test_container_logs() {
    local test_container="${TEST_CONTAINER_PREFIX}_logs"

    # Запуск контейнера, который генерирует логи
    if docker run --name "$test_container" --rm -d alpine:latest sh -c "echo 'Test log message'; sleep 3" >/dev/null 2>&1; then
        log_info "Тестовый контейнер для логов запущен"

        # Ожидание генерации логов
        sleep 2

        # Проверка логов
        local logs
        logs=$(docker logs "$test_container" 2>/dev/null)

        if [[ "$logs" == *"Test log message"* ]]; then
            log_info "Логи контейнера читаются корректно"
        else
            log_error "Не удается прочитать логи контейнера"
            return 1
        fi

        # Остановка контейнера
        docker stop "$test_container" >/dev/null 2>&1
    else
        log_error "Не удается запустить контейнер для тестирования логов"
        return 1
    fi

    return 0
}

# Тест 12: Проверка health checks
test_health_checks() {
    local test_container="${TEST_CONTAINER_PREFIX}_health"

    # Запуск контейнера с health check
    if docker run --name "$test_container" --rm -d \
        --health-cmd="curl -f http://localhost/ || exit 1" \
        --health-interval=5s \
        --health-timeout=3s \
        --health-retries=3 \
        nginx:alpine >/dev/null 2>&1; then

        log_info "Тестовый контейнер с health check запущен"

        # Ожидание health check
        sleep 10

        # Проверка статуса health check
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$test_container" 2>/dev/null)

        if [[ "$health_status" == "healthy" ]]; then
            log_info "Health check работает корректно"
        else
            log_warning "Health check status: $health_status"
        fi

        # Остановка контейнера
        docker stop "$test_container" >/dev/null 2>&1
    else
        log_error "Не удается запустить контейнер с health check"
        return 1
    fi

    return 0
}

# Главная функция тестирования
main() {
    log_info "Начало тестирования Docker сервисов VLESS+Reality VPN"
    echo "Лог-файл: $TEST_LOG" > "$TEST_LOG"
    echo "Время начала: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    # Выполнение всех тестов
    run_test "Установка Docker" test_docker_installation
    run_test "Docker Compose" test_docker_compose
    run_test "Конфигурация Docker Compose" test_docker_compose_config
    run_test "Docker образы" test_docker_images
    run_test "Docker сети" test_docker_networks
    run_test "Docker volumes" test_docker_volumes
    run_test "Жизненный цикл контейнера" test_container_lifecycle
    run_test "Привязка портов" test_port_binding
    run_test "Переменные окружения" test_environment_variables
    run_test "Системные ресурсы" test_system_resources
    run_test "Логи контейнеров" test_container_logs
    run_test "Health checks" test_health_checks

    # Очистка тестовых ресурсов
    cleanup_docker_resources

    # Итоговый отчет
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ DOCKER СЕРВИСОВ" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo "Всего тестов выполнено: $TOTAL_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов провалено: $FAILED_TESTS" | tee -a "$TEST_LOG"
    echo "Тестов пройдено: $((TOTAL_TESTS - FAILED_TESTS))" | tee -a "$TEST_LOG"
    echo "Время завершения: $(date)" | tee -a "$TEST_LOG"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "ВСЕ ТЕСТЫ DOCKER СЕРВИСОВ ПРОЙДЕНЫ УСПЕШНО!"
        exit 0
    else
        log_error "ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ DOCKER СЕРВИСОВ"
        echo "Подробности в логе: $TEST_LOG"
        exit 1
    fi
}

# Проверка прав пользователя для Docker
if ! groups "$USER" | grep -q docker && [[ $EUID -ne 0 ]]; then
    log_warning "Пользователь не в группе docker и не root. Некоторые тесты могут провалиться."
fi

# Запуск главной функции
main "$@"
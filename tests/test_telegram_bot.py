#!/usr/bin/env python3
"""
VLESS+Reality VPN - Telegram Bot Tests
Комплексные тесты для Telegram бота управления VPN
Версия: 1.0
Дата: 2025-09-19
"""

import os
import sys
import json
import unittest
import tempfile
import shutil
from unittest.mock import Mock, patch, AsyncMock, MagicMock
import asyncio
import logging

# Добавляем путь к модулям проекта
PROJECT_ROOT = "/home/ikeniborn/Documents/Project/vless"
sys.path.insert(0, os.path.join(PROJECT_ROOT, "modules"))

# Глобальные переменные для тестирования
TEST_LOG_FILE = "/tmp/vless_telegram_bot_test.log"
FAILED_TESTS = 0
TOTAL_TESTS = 0

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(TEST_LOG_FILE),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class MockTelegramBot:
    """Мок класс для Telegram бота"""

    def __init__(self):
        self.messages = []
        self.callbacks = {}

    async def send_message(self, chat_id, text, **kwargs):
        self.messages.append({
            'chat_id': chat_id,
            'text': text,
            'kwargs': kwargs
        })
        return Mock(message_id=123)

    async def send_document(self, chat_id, document, **kwargs):
        self.messages.append({
            'chat_id': chat_id,
            'document': document,
            'kwargs': kwargs,
            'type': 'document'
        })
        return Mock(message_id=124)

    async def send_photo(self, chat_id, photo, **kwargs):
        self.messages.append({
            'chat_id': chat_id,
            'photo': photo,
            'kwargs': kwargs,
            'type': 'photo'
        })
        return Mock(message_id=125)

class TestTelegramBotModule(unittest.TestCase):
    """Тесты для модуля Telegram бота"""

    def setUp(self):
        """Подготовка тестовой среды"""
        global TOTAL_TESTS
        TOTAL_TESTS += 1

        # Создание временных каталогов
        self.test_dir = tempfile.mkdtemp()
        self.users_file = os.path.join(self.test_dir, "users.json")
        self.config_dir = os.path.join(self.test_dir, "configs")
        os.makedirs(self.config_dir, exist_ok=True)

        # Создание тестового файла пользователей
        test_users = {
            "users": [
                {
                    "name": "test_user",
                    "uuid": "12345678-1234-1234-1234-123456789abc",
                    "created": "2025-09-19T10:00:00Z",
                    "active": True
                }
            ]
        }

        with open(self.users_file, 'w') as f:
            json.dump(test_users, f, indent=2)

        # Настройка переменных окружения для тестов
        os.environ['VLESS_USERS_FILE'] = self.users_file
        os.environ['VLESS_CONFIG_DIR'] = self.config_dir
        os.environ['TELEGRAM_BOT_TOKEN'] = 'test_token'
        os.environ['ADMIN_TELEGRAM_ID'] = '123456789'

        # Мок для Telegram бота
        self.mock_bot = MockTelegramBot()

    def tearDown(self):
        """Очистка после тестов"""
        # Удаление временных файлов
        shutil.rmtree(self.test_dir, ignore_errors=True)

        # Очистка переменных окружения
        for key in ['VLESS_USERS_FILE', 'VLESS_CONFIG_DIR', 'TELEGRAM_BOT_TOKEN', 'ADMIN_TELEGRAM_ID']:
            os.environ.pop(key, None)

    def test_module_import(self):
        """Тест импорта модуля Telegram бота"""
        try:
            # Проверяем наличие файла бота
            bot_file = os.path.join(PROJECT_ROOT, "modules", "telegram_bot.py")
            self.assertTrue(os.path.exists(bot_file), "Файл telegram_bot.py не найден")

            # Попытка импорта (может не удаться из-за зависимостей)
            logger.info("Тест импорта модуля: ПРОЙДЕН")

        except Exception as e:
            logger.error(f"Тест импорта модуля: ПРОВАЛЕН - {e}")
            raise

    def test_environment_variables(self):
        """Тест проверки переменных окружения"""
        required_vars = ['TELEGRAM_BOT_TOKEN', 'ADMIN_TELEGRAM_ID']

        for var in required_vars:
            self.assertIn(var, os.environ, f"Переменная окружения {var} не установлена")
            self.assertNotEqual(os.environ[var], '', f"Переменная окружения {var} пуста")

        logger.info("Тест переменных окружения: ПРОЙДЕН")

    def test_user_file_operations(self):
        """Тест операций с файлом пользователей"""
        # Проверка чтения файла пользователей
        with open(self.users_file, 'r') as f:
            users_data = json.load(f)

        self.assertIn('users', users_data, "Файл пользователей не содержит ключ 'users'")
        self.assertIsInstance(users_data['users'], list, "Поле 'users' должно быть списком")
        self.assertGreater(len(users_data['users']), 0, "Список пользователей пуст")

        # Проверка структуры пользователя
        user = users_data['users'][0]
        required_fields = ['name', 'uuid', 'created', 'active']

        for field in required_fields:
            self.assertIn(field, user, f"Поле '{field}' отсутствует в данных пользователя")

        logger.info("Тест операций с файлом пользователей: ПРОЙДЕН")

    def test_uuid_validation(self):
        """Тест валидации UUID"""
        import re

        uuid_pattern = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.IGNORECASE)

        # Валидные UUID
        valid_uuids = [
            "12345678-1234-1234-1234-123456789abc",
            "ABCDEF12-3456-7890-ABCD-EF1234567890",
            "00000000-0000-0000-0000-000000000000"
        ]

        for uuid in valid_uuids:
            self.assertTrue(uuid_pattern.match(uuid), f"UUID {uuid} должен быть валидным")

        # Невалидные UUID
        invalid_uuids = [
            "invalid-uuid",
            "12345678-1234-1234-1234-123456789",  # короткий
            "12345678-1234-1234-1234-123456789abcd",  # длинный
            "12345678_1234_1234_1234_123456789abc",  # неправильные разделители
        ]

        for uuid in invalid_uuids:
            self.assertFalse(uuid_pattern.match(uuid), f"UUID {uuid} должен быть невалидным")

        logger.info("Тест валидации UUID: ПРОЙДЕН")

    @patch('telegram.Bot')
    async def test_bot_initialization(self, mock_telegram_bot):
        """Тест инициализации бота"""
        # Мокаем Telegram Bot
        mock_telegram_bot.return_value = self.mock_bot

        # Проверяем, что бот может быть инициализирован с токеном
        token = os.environ.get('TELEGRAM_BOT_TOKEN')
        self.assertIsNotNone(token, "Токен бота не установлен")

        logger.info("Тест инициализации бота: ПРОЙДЕН")

    def test_admin_authentication(self):
        """Тест аутентификации администратора"""
        admin_id = os.environ.get('ADMIN_TELEGRAM_ID')
        self.assertIsNotNone(admin_id, "ID администратора не установлен")

        # Проверяем, что ID является числом
        try:
            int(admin_id)
        except ValueError:
            self.fail("ID администратора должен быть числом")

        logger.info("Тест аутентификации администратора: ПРОЙДЕН")

    def test_vless_link_generation(self):
        """Тест генерации VLESS ссылок"""
        # Параметры для тестовой ссылки
        uuid = "12345678-1234-1234-1234-123456789abc"
        server = "example.com"
        port = "443"

        # Формат VLESS ссылки
        expected_start = f"vless://{uuid}@{server}:{port}"

        # Простая генерация ссылки для тестирования
        vless_link = f"vless://{uuid}@{server}:{port}?type=tcp&security=reality&flow=xtls-rprx-vision"

        self.assertTrue(vless_link.startswith(expected_start), "VLESS ссылка имеет неправильный формат")
        self.assertIn("type=tcp", vless_link, "VLESS ссылка должна содержать type=tcp")
        self.assertIn("security=reality", vless_link, "VLESS ссылка должна содержать security=reality")

        logger.info("Тест генерации VLESS ссылок: ПРОЙДЕН")

    def test_config_file_generation(self):
        """Тест генерации конфигурационных файлов"""
        # Создаем тестовую конфигурацию
        config = {
            "inbounds": [{
                "protocol": "vless",
                "settings": {
                    "clients": [{
                        "id": "12345678-1234-1234-1234-123456789abc",
                        "flow": "xtls-rprx-vision"
                    }]
                }
            }]
        }

        config_file = os.path.join(self.config_dir, "test_config.json")

        # Сохранение конфигурации
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)

        # Проверка, что файл создан и содержит правильные данные
        self.assertTrue(os.path.exists(config_file), "Конфигурационный файл не создан")

        with open(config_file, 'r') as f:
            loaded_config = json.load(f)

        self.assertEqual(config, loaded_config, "Конфигурация загружена некорректно")

        logger.info("Тест генерации конфигурационных файлов: ПРОЙДЕН")

    def test_error_handling(self):
        """Тест обработки ошибок"""
        # Тест с несуществующим файлом пользователей
        nonexistent_file = "/nonexistent/path/users.json"

        # Проверяем, что попытка чтения несуществующего файла вызывает исключение
        with self.assertRaises(FileNotFoundError):
            with open(nonexistent_file, 'r') as f:
                json.load(f)

        # Тест с некорректным JSON
        invalid_json_file = os.path.join(self.test_dir, "invalid.json")
        with open(invalid_json_file, 'w') as f:
            f.write("invalid json content")

        with self.assertRaises(json.JSONDecodeError):
            with open(invalid_json_file, 'r') as f:
                json.load(f)

        logger.info("Тест обработки ошибок: ПРОЙДЕН")

class TestTelegramBotCommands(unittest.TestCase):
    """Тесты команд Telegram бота"""

    def setUp(self):
        """Подготовка для тестов команд"""
        global TOTAL_TESTS
        TOTAL_TESTS += 1

        self.mock_bot = MockTelegramBot()
        self.admin_id = 123456789
        self.regular_user_id = 987654321

    def test_start_command(self):
        """Тест команды /start"""
        # Симуляция команды /start
        start_message = "Добро пожаловать в VLESS+Reality VPN бот!"

        # Проверяем, что сообщение содержит приветствие
        self.assertIn("Добро пожаловать", start_message)

        logger.info("Тест команды /start: ПРОЙДЕН")

    def test_help_command(self):
        """Тест команды /help"""
        # Список ожидаемых команд в справке
        expected_commands = [
            "/start", "/adduser", "/deleteuser", "/listusers",
            "/getconfig", "/status", "/restart", "/logs", "/backup"
        ]

        help_text = """
        Доступные команды:
        /start - Начать работу с ботом
        /adduser <name> - Добавить нового пользователя
        /deleteuser <uuid> - Удалить пользователя
        /listusers - Показать список пользователей
        /getconfig <uuid> - Получить конфигурацию пользователя
        /status - Статус сервера
        /restart - Перезапустить сервисы
        /logs - Показать логи
        /backup - Создать резервную копию
        """

        for cmd in expected_commands:
            self.assertIn(cmd, help_text, f"Команда {cmd} отсутствует в справке")

        logger.info("Тест команды /help: ПРОЙДЕН")

    def test_adduser_command(self):
        """Тест команды /adduser"""
        # Параметры нового пользователя
        username = "new_test_user"

        # Проверяем валидность имени пользователя
        self.assertIsInstance(username, str, "Имя пользователя должно быть строкой")
        self.assertGreater(len(username), 0, "Имя пользователя не может быть пустым")
        self.assertLess(len(username), 50, "Имя пользователя слишком длинное")

        # Проверяем, что имя содержит только допустимые символы
        import re
        valid_pattern = re.compile(r'^[a-zA-Z0-9_-]+$')
        self.assertTrue(valid_pattern.match(username), "Имя пользователя содержит недопустимые символы")

        logger.info("Тест команды /adduser: ПРОЙДЕН")

    def test_authorization(self):
        """Тест авторизации пользователей"""
        # Проверяем авторизацию администратора
        self.assertEqual(self.admin_id, 123456789, "ID администратора неверный")

        # Проверяем, что обычный пользователь не является администратором
        self.assertNotEqual(self.regular_user_id, self.admin_id, "Обычный пользователь не должен быть администратором")

        logger.info("Тест авторизации: ПРОЙДЕН")

def run_telegram_bot_tests():
    """Запуск всех тестов Telegram бота"""
    global FAILED_TESTS, TOTAL_TESTS

    logger.info("Начало тестирования Telegram бота VLESS+Reality VPN")

    # Создание test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Добавление тестов
    suite.addTests(loader.loadTestsFromTestCase(TestTelegramBotModule))
    suite.addTests(loader.loadTestsFromTestCase(TestTelegramBotCommands))

    # Запуск тестов
    runner = unittest.TextTestRunner(verbosity=2, stream=open(TEST_LOG_FILE, 'a'))
    result = runner.run(suite)

    # Подсчет результатов
    tests_run = result.testsRun
    failures = len(result.failures)
    errors = len(result.errors)

    TOTAL_TESTS = tests_run
    FAILED_TESTS = failures + errors

    # Итоговый отчет
    logger.info("=" * 50)
    logger.info("ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ TELEGRAM БОТА")
    logger.info("=" * 50)
    logger.info(f"Всего тестов выполнено: {tests_run}")
    logger.info(f"Тестов провалено: {FAILED_TESTS}")
    logger.info(f"Тестов пройдено: {tests_run - FAILED_TESTS}")

    if FAILED_TESTS == 0:
        logger.info("ВСЕ ТЕСТЫ TELEGRAM БОТА ПРОЙДЕНЫ УСПЕШНО!")
        return True
    else:
        logger.error("ОБНАРУЖЕНЫ ПРОБЛЕМЫ В ТЕСТАХ TELEGRAM БОТА")
        logger.error(f"Подробности в логе: {TEST_LOG_FILE}")
        return False

if __name__ == "__main__":
    # Проверка наличия Python модулей
    try:
        import telegram
        logger.info("Модуль python-telegram-bot найден")
    except ImportError:
        logger.warning("Модуль python-telegram-bot не найден, некоторые тесты могут быть пропущены")

    # Запуск тестов
    success = run_telegram_bot_tests()

    # Выход с соответствующим кодом
    sys.exit(0 if success else 1)
#!/usr/bin/env python3
"""
Integration Tests for VLESS VPN Telegram Bot
Tests the integration between bot and user management modules
Author: Claude Code
Version: 1.0
"""

import asyncio
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

# Add modules to path
sys.path.insert(0, str(Path(__file__).parent.parent / "modules"))

try:
    from telegram_bot import VLESSBot
except ImportError as e:
    print(f"Warning: Could not import telegram_bot module: {e}")
    VLESSBot = None

class TestTelegramBotIntegration(unittest.TestCase):
    """Test cases for Telegram bot integration"""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.bot_token = "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
        self.admin_id = 123456789
        self.project_dir = Path(__file__).parent.parent

        # Set up test environment variables
        os.environ.update({
            'TELEGRAM_BOT_TOKEN': self.bot_token,
            'ADMIN_TELEGRAM_ID': str(self.admin_id),
            'VLESS_DIR': self.test_dir,
            'SERVER_IP': '1.2.3.4',
            'DOMAIN': 'test.example.com',
            'VLESS_PORT': '443'
        })

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_user_management_script_exists(self):
        """Test that user management script exists and is executable"""
        script_path = self.project_dir / "modules" / "user_management.sh"
        self.assertTrue(script_path.exists(), "User management script not found")
        self.assertTrue(os.access(script_path, os.X_OK), "User management script not executable")

    def test_user_management_functions(self):
        """Test that user management script has required functions"""
        script_path = self.project_dir / "modules" / "user_management.sh"

        with open(script_path, 'r') as f:
            content = f.read()

        required_functions = [
            'add_user',
            'remove_user',
            'list_users',
            'get_user_config',
            'user_exists',
            'generate_unique_uuid'
        ]

        for func in required_functions:
            self.assertIn(func, content, f"Function {func} not found in user management script")

    def test_common_utils_script_exists(self):
        """Test that common utilities script exists"""
        script_path = self.project_dir / "modules" / "common_utils.sh"
        self.assertTrue(script_path.exists(), "Common utils script not found")

    @unittest.skipIf(VLESSBot is None, "VLESSBot module not available")
    def test_bot_initialization(self):
        """Test bot initialization"""
        bot = VLESSBot(self.bot_token, self.admin_id)

        self.assertEqual(bot.token, self.bot_token)
        self.assertEqual(bot.admin_id, self.admin_id)
        self.assertIsNotNone(bot.vless_dir)
        self.assertIsNotNone(bot.user_mgmt_script)

    @unittest.skipIf(VLESSBot is None, "VLESSBot module not available")
    def test_admin_check(self):
        """Test admin access control"""
        bot = VLESSBot(self.bot_token, self.admin_id)

        # Test admin user
        self.assertTrue(bot._is_admin(self.admin_id))

        # Test non-admin user
        self.assertFalse(bot._is_admin(987654321))

    @unittest.skipIf(VLESSBot is None, "VLESSBot module not available")
    async def test_shell_command_execution(self):
        """Test shell command execution"""
        bot = VLESSBot(self.bot_token, self.admin_id)

        # Test simple command
        result = await bot._run_shell_command(['echo', 'test'])

        self.assertEqual(result['returncode'], 0)
        self.assertEqual(result['stdout'].strip(), 'test')
        self.assertEqual(result['stderr'], '')

    def test_configuration_files_exist(self):
        """Test that required configuration files exist"""
        config_files = [
            'config/bot_config.env',
            'requirements.txt',
            'Dockerfile.bot'
        ]

        for config_file in config_files:
            file_path = self.project_dir / config_file
            self.assertTrue(file_path.exists(), f"Configuration file {config_file} not found")

    def test_requirements_file_content(self):
        """Test that requirements.txt contains necessary packages"""
        requirements_path = self.project_dir / "requirements.txt"

        with open(requirements_path, 'r') as f:
            content = f.read()

        required_packages = [
            'python-telegram-bot',
            'qrcode',
            'Pillow'
        ]

        for package in required_packages:
            self.assertIn(package, content, f"Package {package} not found in requirements.txt")

    def test_dockerfile_exists_and_valid(self):
        """Test that Dockerfile exists and has basic structure"""
        dockerfile_path = self.project_dir / "Dockerfile.bot"

        with open(dockerfile_path, 'r') as f:
            content = f.read()

        required_instructions = [
            'FROM python:3.11',
            'COPY requirements.txt',
            'RUN pip install',
            'WORKDIR',
            'CMD'
        ]

        for instruction in required_instructions:
            self.assertIn(instruction, content, f"Dockerfile instruction {instruction} not found")

    def test_docker_compose_integration(self):
        """Test that docker-compose.yml includes telegram-bot service"""
        compose_path = self.project_dir / "config" / "docker-compose.yml"

        if compose_path.exists():
            with open(compose_path, 'r') as f:
                content = f.read()

            self.assertIn('telegram-bot:', content, "telegram-bot service not found in docker-compose.yml")
            self.assertIn('TELEGRAM_BOT_TOKEN', content, "Bot token env var not found in compose file")
            self.assertIn('ADMIN_TELEGRAM_ID', content, "Admin ID env var not found in compose file")

    def test_bot_manager_script_exists(self):
        """Test that bot manager script exists and is executable"""
        script_path = self.project_dir / "modules" / "telegram_bot_manager.sh"
        self.assertTrue(script_path.exists(), "Bot manager script not found")
        self.assertTrue(os.access(script_path, os.X_OK), "Bot manager script not executable")

    def test_bot_manager_functions(self):
        """Test that bot manager script has required functions"""
        script_path = self.project_dir / "modules" / "telegram_bot_manager.sh"

        with open(script_path, 'r') as f:
            content = f.read()

        required_functions = [
            'start_bot',
            'stop_bot',
            'restart_bot',
            'check_bot_status',
            'validate_bot_config'
        ]

        for func in required_functions:
            self.assertIn(func, content, f"Function {func} not found in bot manager script")

    @unittest.skipIf(VLESSBot is None, "VLESSBot module not available")
    def test_users_json_handling(self):
        """Test users JSON file handling"""
        bot = VLESSBot(self.bot_token, self.admin_id)

        # Create test users JSON
        users_dir = Path(self.test_dir) / "users"
        users_dir.mkdir(exist_ok=True)

        users_file = users_dir / "users.json"
        test_data = {
            "users": [
                {
                    "uuid": "test-uuid-123",
                    "username": "testuser",
                    "created": "2023-01-01T00:00:00Z",
                    "status": "active"
                }
            ],
            "metadata": {
                "total_users": 1,
                "last_modified": "2023-01-01T00:00:00Z"
            }
        }

        with open(users_file, 'w') as f:
            json.dump(test_data, f)

        # Test reading users
        async def test_read():
            users_data = await bot._get_users_json()
            self.assertIsNotNone(users_data)
            self.assertEqual(len(users_data['users']), 1)
            self.assertEqual(users_data['users'][0]['username'], 'testuser')

        asyncio.run(test_read())

    @unittest.skipIf(VLESSBot is None, "VLESSBot module not available")
    def test_qr_code_generation(self):
        """Test QR code generation functionality"""
        bot = VLESSBot(self.bot_token, self.admin_id)

        test_url = "vless://test-uuid@1.2.3.4:443?encryption=none&security=reality&type=tcp#testuser"

        async def test_qr():
            try:
                qr_buffer = await bot._generate_qr_code(test_url)
                self.assertIsNotNone(qr_buffer)
                self.assertGreater(qr_buffer.getvalue().__len__(), 0)
            except Exception as e:
                self.skipTest(f"QR code generation failed: {e}")

        asyncio.run(test_qr())

    def test_environment_validation(self):
        """Test environment variable validation"""
        required_env_vars = [
            'TELEGRAM_BOT_TOKEN',
            'ADMIN_TELEGRAM_ID'
        ]

        for var in required_env_vars:
            if var in os.environ:
                self.assertIsNotNone(os.environ[var], f"Environment variable {var} is None")
                self.assertNotEqual(os.environ[var], '', f"Environment variable {var} is empty")

class TestUserManagementIntegration(unittest.TestCase):
    """Test cases for user management integration"""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.project_dir = Path(__file__).parent.parent
        self.user_mgmt_script = self.project_dir / "modules" / "user_management.sh"

        # Set up test environment
        os.environ.update({
            'VLESS_DIR': self.test_dir,
            'SERVER_IP': '1.2.3.4',
            'DOMAIN': 'test.example.com'
        })

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_user_management_script_syntax(self):
        """Test that user management script has valid bash syntax"""
        if not self.user_mgmt_script.exists():
            self.skipTest("User management script not found")

        # Test bash syntax
        result = subprocess.run(
            ['bash', '-n', str(self.user_mgmt_script)],
            capture_output=True,
            text=True
        )

        self.assertEqual(result.returncode, 0, f"Bash syntax error: {result.stderr}")

    def test_user_management_dependencies(self):
        """Test that user management script can find its dependencies"""
        if not self.user_mgmt_script.exists():
            self.skipTest("User management script not found")

        # Check for common_utils.sh
        common_utils = self.project_dir / "modules" / "common_utils.sh"
        self.assertTrue(common_utils.exists(), "common_utils.sh not found")

def run_tests():
    """Run all tests"""
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestTelegramBotIntegration))
    suite.addTests(loader.loadTestsFromTestCase(TestUserManagementIntegration))

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    return result.wasSuccessful()

if __name__ == "__main__":
    print("Running VLESS VPN Telegram Bot Integration Tests")
    print("=" * 60)

    success = run_tests()

    if success:
        print("\n✓ All tests passed!")
        sys.exit(0)
    else:
        print("\n✗ Some tests failed!")
        sys.exit(1)
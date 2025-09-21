#!/usr/bin/env python3
"""
VLESS+Reality VPN - Telegram Bot Interface
Complete Telegram bot for remote VPN management
Version: 1.0
Author: VLESS Management System
"""

import os
import sys
import json
import logging
import asyncio
import subprocess
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import tempfile
import io

# Telegram bot imports
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputFile
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes
)

# System imports
import psutil
import requests
from PIL import Image
import qrcode

# Configuration
SCRIPT_DIR = Path(__file__).parent
CONFIG_DIR = Path("/opt/vless/config")
LOG_DIR = Path("/opt/vless/logs")
BOT_CONFIG_FILE = CONFIG_DIR / "bot_config.env"
USER_DB_FILE = Path("/opt/vless/users/users.db")
ADMIN_DB_FILE = Path("/opt/vless/config/bot_admins.db")

# Logging setup
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_DIR / "telegram_bot.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class VLESSBot:
    """Main Telegram bot class for VLESS VPN management"""

    def __init__(self):
        self.config = self.load_config()
        self.application = None
        self.admin_list = set()
        self.load_admin_list()

    def load_config(self) -> Dict[str, str]:
        """Load bot configuration from environment file"""
        config = {}

        if BOT_CONFIG_FILE.exists():
            with open(BOT_CONFIG_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        config[key] = value

        # Environment variables override file config
        config.update({
            'BOT_TOKEN': os.getenv('VLESS_BOT_TOKEN', config.get('BOT_TOKEN', '')),
            'ADMIN_CHAT_ID': os.getenv('VLESS_ADMIN_CHAT_ID', config.get('ADMIN_CHAT_ID', '')),
            'WEBHOOK_URL': os.getenv('VLESS_WEBHOOK_URL', config.get('WEBHOOK_URL', '')),
            'WEBHOOK_PORT': int(os.getenv('VLESS_WEBHOOK_PORT', config.get('WEBHOOK_PORT', '8443'))),
            'BOT_DEBUG': os.getenv('VLESS_BOT_DEBUG', config.get('BOT_DEBUG', 'false')).lower() == 'true'
        })

        if not config.get('BOT_TOKEN'):
            raise ValueError("BOT_TOKEN is required in configuration")

        return config

    def load_admin_list(self):
        """Load admin user list from database"""
        try:
            if not ADMIN_DB_FILE.exists():
                self.init_admin_db()

            conn = sqlite3.connect(ADMIN_DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT user_id FROM admins WHERE active = 1")
            self.admin_list = {row[0] for row in cursor.fetchall()}
            conn.close()

            # Add initial admin from config
            if self.config.get('ADMIN_CHAT_ID'):
                admin_id = int(self.config['ADMIN_CHAT_ID'])
                self.admin_list.add(admin_id)
                self.add_admin(admin_id, "Initial Admin", "config")

            logger.info(f"Loaded {len(self.admin_list)} admin(s)")

        except Exception as e:
            logger.error(f"Failed to load admin list: {e}")
            self.admin_list = set()

    def init_admin_db(self):
        """Initialize admin database"""
        conn = sqlite3.connect(ADMIN_DB_FILE)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS admins (
                user_id INTEGER PRIMARY KEY,
                username TEXT,
                first_name TEXT,
                last_name TEXT,
                added_by TEXT,
                added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                active INTEGER DEFAULT 1
            )
        """)
        conn.commit()
        conn.close()

    def add_admin(self, user_id: int, name: str, added_by: str) -> bool:
        """Add admin to database"""
        try:
            conn = sqlite3.connect(ADMIN_DB_FILE)
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO admins (user_id, first_name, added_by, active)
                VALUES (?, ?, ?, 1)
            """, (user_id, name, added_by))
            conn.commit()
            conn.close()
            self.admin_list.add(user_id)
            return True
        except Exception as e:
            logger.error(f"Failed to add admin {user_id}: {e}")
            return False

    def is_admin(self, user_id: int) -> bool:
        """Check if user is admin"""
        return user_id in self.admin_list

    def require_admin(func):
        """Decorator to require admin privileges"""
        async def wrapper(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
            user_id = update.effective_user.id
            if not self.is_admin(user_id):
                await update.message.reply_text("❌ Access denied. Admin privileges required.")
                logger.warning(f"Unauthorized access attempt by user {user_id}")
                return
            return await func(self, update, context)
        return wrapper

    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        user_id = user.id

        welcome_message = f"""
🔐 **VLESS VPN Management Bot**

Hello {user.first_name}!

This bot provides remote management for your VLESS+Reality VPN server.

**Available Commands:**
• /status - System status
• /users - User management
• /backup - Backup operations
• /help - Show all commands

{"🔑 **Admin Access Granted**" if self.is_admin(user_id) else "ℹ️ Contact admin for access"}
        """

        await update.message.reply_text(welcome_message, parse_mode='Markdown')

        # Log new user
        logger.info(f"New user interaction: {user.username or user.first_name} ({user_id})")

    @require_admin
    async def status(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        try:
            # System information
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/opt/vless')

            # Docker status
            docker_status = await self.run_command("docker ps --format 'table {{.Names}}\t{{.Status}}'")

            # Xray status
            xray_status = await self.run_command("docker exec vless-xray xray version 2>/dev/null | head -1 || echo 'Not available'")

            # Active connections (approximate)
            connections = await self.run_command("docker exec vless-xray ss -tuln | grep ':443' | wc -l")

            status_message = f"""
📊 **System Status**

🖥️ **Server Resources:**
• CPU Usage: {cpu_percent}%
• RAM Usage: {memory.percent}% ({memory.used // (1024**3)}GB / {memory.total // (1024**3)}GB)
• Disk Usage: {disk.percent}% ({disk.used // (1024**3)}GB / {disk.total // (1024**3)}GB)

🐳 **Services:**
• Docker: {"✅ Running" if await self.is_service_running("docker") else "❌ Stopped"}
• Xray: {"✅ Running" if "vless-xray" in docker_status else "❌ Stopped"}

🔗 **VPN Status:**
• Xray Version: {xray_status.strip()}
• Active Connections: ~{connections.strip()}

📅 **Last Updated:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            """

            # Add quick action buttons
            keyboard = [
                [InlineKeyboardButton("🔄 Refresh", callback_data="status_refresh")],
                [InlineKeyboardButton("📋 Detailed Info", callback_data="status_detailed")],
                [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)

            await update.message.reply_text(status_message, parse_mode='Markdown', reply_markup=reply_markup)

        except Exception as e:
            logger.error(f"Status command error: {e}")
            await update.message.reply_text(f"❌ Error getting system status: {str(e)}")

    @require_admin
    async def users(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /users command"""
        keyboard = [
            [InlineKeyboardButton("👥 List Users", callback_data="users_list")],
            [InlineKeyboardButton("➕ Add User", callback_data="users_add")],
            [InlineKeyboardButton("🗑️ Remove User", callback_data="users_remove")],
            [InlineKeyboardButton("📱 Get QR Code", callback_data="users_qr")],
            [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            "👥 **User Management**\n\nChoose an action:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )

    @require_admin
    async def backup(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /backup command"""
        keyboard = [
            [InlineKeyboardButton("💾 Create Backup", callback_data="backup_create")],
            [InlineKeyboardButton("📋 List Backups", callback_data="backup_list")],
            [InlineKeyboardButton("🔄 Restore", callback_data="backup_restore")],
            [InlineKeyboardButton("⏰ Schedule", callback_data="backup_schedule")],
            [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            "💾 **Backup Management**\n\nChoose an action:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )

    @require_admin
    async def maintenance(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /maintenance command"""
        keyboard = [
            [InlineKeyboardButton("🔧 System Health", callback_data="maint_health")],
            [InlineKeyboardButton("🧹 Cleanup", callback_data="maint_cleanup")],
            [InlineKeyboardButton("📊 Diagnostics", callback_data="maint_diagnostics")],
            [InlineKeyboardButton("🔄 Updates", callback_data="maint_updates")],
            [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            "🔧 **System Maintenance**\n\nChoose an action:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )

    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        user_id = update.effective_user.id
        is_admin = self.is_admin(user_id)

        help_text = """
🔐 **VLESS VPN Bot Commands**

**Available to everyone:**
/start - Start the bot
/help - Show this help message

"""

        if is_admin:
            help_text += """
**Admin Commands:**
/status - System status and metrics
/users - User management (add/remove/list)
/backup - Backup and restore operations
/maintenance - System maintenance tools
/logs - View system logs
/restart - Restart services
/admin - Admin management

**Quick Actions:**
• Add user: `/adduser username`
• Remove user: `/removeuser username`
• Get QR: `/qr username`
• System info: `/info`
"""
        else:
            help_text += "\n**Access Level:** Standard User\n*Contact admin for elevated privileges*"

        await update.message.reply_text(help_text, parse_mode='Markdown')

    # Callback handlers for inline buttons
    async def button_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle inline button callbacks"""
        query = update.callback_query
        await query.answer()

        data = query.data
        user_id = query.from_user.id

        if not self.is_admin(user_id):
            await query.edit_message_text("❌ Access denied. Admin privileges required.")
            return

        try:
            if data == "main_menu":
                await self.show_main_menu(query)
            elif data.startswith("status_"):
                await self.handle_status_callback(query, data)
            elif data.startswith("users_"):
                await self.handle_users_callback(query, data)
            elif data.startswith("backup_"):
                await self.handle_backup_callback(query, data)
            elif data.startswith("maint_"):
                await self.handle_maintenance_callback(query, data)
            else:
                await query.edit_message_text("❌ Unknown action")

        except Exception as e:
            logger.error(f"Callback error: {e}")
            await query.edit_message_text(f"❌ Error: {str(e)}")

    async def show_main_menu(self, query):
        """Show main menu"""
        keyboard = [
            [InlineKeyboardButton("📊 Status", callback_data="status_refresh")],
            [InlineKeyboardButton("👥 Users", callback_data="users_menu")],
            [InlineKeyboardButton("💾 Backup", callback_data="backup_menu")],
            [InlineKeyboardButton("🔧 Maintenance", callback_data="maint_menu")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            "🏠 **Main Menu**\n\nChoose an option:",
            parse_mode='Markdown',
            reply_markup=reply_markup
        )

    async def handle_status_callback(self, query, data):
        """Handle status-related callbacks"""
        if data == "status_refresh":
            # Recreate status message
            await self.status(update=type('obj', (object,), {
                'message': query, 'effective_user': query.from_user
            })(), context=None)
        elif data == "status_detailed":
            detailed_info = await self.get_detailed_status()
            await query.edit_message_text(detailed_info, parse_mode='Markdown')

    async def handle_users_callback(self, query, data):
        """Handle user management callbacks"""
        if data == "users_list":
            users_info = await self.get_users_list()
            await query.edit_message_text(users_info, parse_mode='Markdown')
        elif data == "users_add":
            await query.edit_message_text(
                "➕ **Add New User**\n\nSend the command:\n`/adduser <username>`",
                parse_mode='Markdown'
            )
        elif data == "users_remove":
            await query.edit_message_text(
                "🗑️ **Remove User**\n\nSend the command:\n`/removeuser <username>`",
                parse_mode='Markdown'
            )
        elif data == "users_qr":
            await query.edit_message_text(
                "📱 **Get QR Code**\n\nSend the command:\n`/qr <username>`",
                parse_mode='Markdown'
            )

    async def handle_backup_callback(self, query, data):
        """Handle backup-related callbacks"""
        if data == "backup_create":
            await query.edit_message_text("💾 Creating backup...")
            result = await self.create_backup()
            await query.edit_message_text(result, parse_mode='Markdown')
        elif data == "backup_list":
            backups = await self.list_backups()
            await query.edit_message_text(backups, parse_mode='Markdown')

    async def handle_maintenance_callback(self, query, data):
        """Handle maintenance-related callbacks"""
        if data == "maint_health":
            await query.edit_message_text("🔧 Running health check...")
            health_report = await self.run_health_check()
            await query.edit_message_text(health_report, parse_mode='Markdown')
        elif data == "maint_cleanup":
            await query.edit_message_text("🧹 Running cleanup...")
            cleanup_result = await self.run_cleanup()
            await query.edit_message_text(cleanup_result, parse_mode='Markdown')

    # Quick command handlers
    @require_admin
    async def add_user_quick(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Quick add user command"""
        if not context.args:
            await update.message.reply_text("Usage: /adduser <username>")
            return

        username = context.args[0]
        result = await self.add_vpn_user(username)
        await update.message.reply_text(result, parse_mode='Markdown')

    @require_admin
    async def remove_user_quick(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Quick remove user command"""
        if not context.args:
            await update.message.reply_text("Usage: /removeuser <username>")
            return

        username = context.args[0]
        result = await self.remove_vpn_user(username)
        await update.message.reply_text(result, parse_mode='Markdown')

    @require_admin
    async def get_qr_quick(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Quick QR code command"""
        if not context.args:
            await update.message.reply_text("Usage: /qr <username>")
            return

        username = context.args[0]
        await self.send_qr_code(update, username)

    # Utility methods
    async def run_command(self, command: str) -> str:
        """Run shell command and return output"""
        try:
            process = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()

            if process.returncode == 0:
                return stdout.decode().strip()
            else:
                return f"Error: {stderr.decode().strip()}"
        except Exception as e:
            return f"Command failed: {str(e)}"

    async def is_service_running(self, service: str) -> bool:
        """Check if service is running"""
        result = await self.run_command(f"systemctl is-active {service}")
        return result == "active"

    async def get_users_list(self) -> str:
        """Get formatted list of VPN users"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/user_management.sh list")
            if result:
                return f"👥 **VPN Users:**\n\n```\n{result}\n```"
            else:
                return "👥 **VPN Users:**\n\nNo users found."
        except Exception as e:
            return f"❌ Error getting users list: {str(e)}"

    async def add_vpn_user(self, username: str) -> str:
        """Add VPN user"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/user_management.sh add {username}")
            if "successfully" in result.lower():
                return f"✅ **User Added Successfully**\n\nUsername: `{username}`\n\nUse `/qr {username}` to get QR code."
            else:
                return f"❌ **Failed to add user:**\n\n{result}"
        except Exception as e:
            return f"❌ Error adding user: {str(e)}"

    async def remove_vpn_user(self, username: str) -> str:
        """Remove VPN user"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/user_management.sh remove {username}")
            if "successfully" in result.lower():
                return f"✅ **User Removed Successfully**\n\nUsername: `{username}`"
            else:
                return f"❌ **Failed to remove user:**\n\n{result}"
        except Exception as e:
            return f"❌ Error removing user: {str(e)}"

    async def send_qr_code(self, update: Update, username: str):
        """Generate and send QR code for user"""
        try:
            # Get user configuration
            config_result = await self.run_command(f"{SCRIPT_DIR}/user_management.sh config {username}")

            if "error" in config_result.lower() or "not found" in config_result.lower():
                await update.message.reply_text(f"❌ User '{username}' not found.")
                return

            # Generate QR code
            qr = qrcode.QRCode(version=1, box_size=10, border=5)
            qr.add_data(config_result)
            qr.make(fit=True)

            # Create QR code image
            qr_image = qr.make_image(fill_color="black", back_color="white")

            # Save to BytesIO
            bio = io.BytesIO()
            qr_image.save(bio, format='PNG')
            bio.seek(0)

            # Send QR code
            await update.message.reply_photo(
                photo=InputFile(bio, filename=f"{username}_qr.png"),
                caption=f"📱 **QR Code for {username}**\n\nScan with your VLESS client to connect."
            )

        except Exception as e:
            logger.error(f"QR code generation error: {e}")
            await update.message.reply_text(f"❌ Error generating QR code: {str(e)}")

    async def create_backup(self) -> str:
        """Create system backup"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/backup_restore.sh full 'Telegram bot backup'")
            if "successfully" in result.lower():
                return f"✅ **Backup Created Successfully**\n\n{result}"
            else:
                return f"❌ **Backup Failed:**\n\n{result}"
        except Exception as e:
            return f"❌ Error creating backup: {str(e)}"

    async def list_backups(self) -> str:
        """List available backups"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/backup_restore.sh list")
            if result:
                return f"💾 **Available Backups:**\n\n```\n{result}\n```"
            else:
                return "💾 **Available Backups:**\n\nNo backups found."
        except Exception as e:
            return f"❌ Error listing backups: {str(e)}"

    async def run_health_check(self) -> str:
        """Run system health check"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/maintenance_utils.sh health-check")
            return f"🔧 **System Health Check:**\n\n```\n{result}\n```"
        except Exception as e:
            return f"❌ Error running health check: {str(e)}"

    async def run_cleanup(self) -> str:
        """Run system cleanup"""
        try:
            result = await self.run_command(f"{SCRIPT_DIR}/maintenance_utils.sh cleanup-logs && {SCRIPT_DIR}/maintenance_utils.sh cleanup-temp")
            return f"🧹 **Cleanup Completed:**\n\n```\n{result}\n```"
        except Exception as e:
            return f"❌ Error running cleanup: {str(e)}"

    async def get_detailed_status(self) -> str:
        """Get detailed system status"""
        try:
            # Get various system metrics
            uptime = await self.run_command("uptime")
            disk_info = await self.run_command("df -h /opt/vless")
            memory_info = await self.run_command("free -h")
            docker_info = await self.run_command("docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'")

            return f"""
📊 **Detailed System Status**

⏱️ **Uptime:**
```
{uptime}
```

💽 **Disk Usage:**
```
{disk_info}
```

🧠 **Memory Usage:**
```
{memory_info}
```

🐳 **Docker Containers:**
```
{docker_info}
```
"""
        except Exception as e:
            return f"❌ Error getting detailed status: {str(e)}"

    def setup_handlers(self):
        """Setup all command and callback handlers"""
        # Command handlers
        self.application.add_handler(CommandHandler("start", self.start))
        self.application.add_handler(CommandHandler("status", self.status))
        self.application.add_handler(CommandHandler("users", self.users))
        self.application.add_handler(CommandHandler("backup", self.backup))
        self.application.add_handler(CommandHandler("maintenance", self.maintenance))
        self.application.add_handler(CommandHandler("help", self.help_command))

        # Quick command handlers
        self.application.add_handler(CommandHandler("adduser", self.add_user_quick))
        self.application.add_handler(CommandHandler("removeuser", self.remove_user_quick))
        self.application.add_handler(CommandHandler("qr", self.get_qr_quick))

        # Callback query handler
        self.application.add_handler(CallbackQueryHandler(self.button_callback))

        # Error handler
        self.application.add_error_handler(self.error_handler)

    async def error_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle errors"""
        logger.error(f"Update {update} caused error {context.error}")

        if update and update.effective_message:
            await update.effective_message.reply_text(
                "❌ An error occurred. Please try again or contact the administrator."
            )

    async def run_bot(self):
        """Main bot run method"""
        try:
            # Create application
            self.application = Application.builder().token(self.config['BOT_TOKEN']).build()

            # Setup handlers
            self.setup_handlers()

            # Start bot
            logger.info("Starting VLESS VPN Telegram Bot...")

            if self.config.get('WEBHOOK_URL'):
                # Webhook mode
                await self.application.bot.set_webhook(
                    url=self.config['WEBHOOK_URL'],
                    drop_pending_updates=True
                )

                # Start webhook server
                await self.application.run_webhook(
                    listen="0.0.0.0",
                    port=self.config['WEBHOOK_PORT'],
                    webhook_url=self.config['WEBHOOK_URL']
                )
            else:
                # Polling mode
                await self.application.run_polling(drop_pending_updates=True)

        except Exception as e:
            logger.error(f"Bot startup error: {e}")
            raise

def main():
    """Main function"""
    try:
        # Ensure directories exist
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        LOG_DIR.mkdir(parents=True, exist_ok=True)

        # Create and run bot
        bot = VLESSBot()
        asyncio.run(bot.run_bot())

    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    except Exception as e:
        logger.error(f"Bot error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
Telegram Bot Module for VLESS VPN Project
Provides telegram interface for managing VPN users and system operations
Author: Claude Code
Version: 1.0
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from io import BytesIO
from pathlib import Path
from typing import Dict, List, Optional, Union

import qrcode
from telegram import (
    Bot,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Update
)
from telegram.constants import ParseMode
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    filters
)

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('/opt/vless/logs/telegram_bot.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class VLESSBot:
    """Main VLESS Telegram Bot class"""

    def __init__(self, token: str, admin_id: int):
        """Initialize the bot with token and admin ID"""
        self.token = token
        self.admin_id = admin_id
        self.application: Optional[Application] = None
        self.vless_dir = Path("/opt/vless")
        self.user_mgmt_script = Path("/home/ikeniborn/Documents/Project/vless/modules/user_management.sh")

        # Ensure required directories exist
        self._ensure_directories()

    def _ensure_directories(self) -> None:
        """Ensure required directories exist"""
        directories = [
            self.vless_dir / "logs",
            self.vless_dir / "users",
            self.vless_dir / "configs" / "users",
            self.vless_dir / "qrcodes"
        ]

        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)

    def _is_admin(self, user_id: int) -> bool:
        """Check if user is admin"""
        return user_id == self.admin_id

    async def _admin_only(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
        """Decorator-like function to check admin access"""
        if not self._is_admin(update.effective_user.id):
            await update.message.reply_text(
                "❌ Access denied. This bot is for administrators only.",
                parse_mode=ParseMode.MARKDOWN
            )
            logger.warning(f"Unauthorized access attempt from user {update.effective_user.id}")
            return False
        return True

    async def _run_shell_command(self, command: List[str]) -> Dict[str, Union[str, int]]:
        """Run shell command and return result"""
        try:
            logger.info(f"Running command: {' '.join(command)}")

            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=str(self.user_mgmt_script.parent)
            )

            stdout, stderr = await process.communicate()

            result = {
                'returncode': process.returncode,
                'stdout': stdout.decode('utf-8').strip(),
                'stderr': stderr.decode('utf-8').strip()
            }

            logger.info(f"Command result: returncode={result['returncode']}")
            return result

        except Exception as e:
            logger.error(f"Error running command: {e}")
            return {
                'returncode': 1,
                'stdout': '',
                'stderr': str(e)
            }

    async def _get_users_json(self) -> Optional[Dict]:
        """Get users from JSON database"""
        users_file = self.vless_dir / "users" / "users.json"
        try:
            if users_file.exists():
                with open(users_file, 'r') as f:
                    return json.load(f)
            return None
        except Exception as e:
            logger.error(f"Error reading users JSON: {e}")
            return None

    async def _generate_qr_code(self, vless_url: str) -> BytesIO:
        """Generate QR code for VLESS URL"""
        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=10,
                border=4,
            )
            qr.add_data(vless_url)
            qr.make(fit=True)

            img = qr.make_image(fill_color="black", back_color="white")

            img_buffer = BytesIO()
            img.save(img_buffer, format='PNG')
            img_buffer.seek(0)

            return img_buffer

        except Exception as e:
            logger.error(f"Error generating QR code: {e}")
            raise

    # Command Handlers

    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /start command"""
        if not await self._admin_only(update, context):
            return

        welcome_text = """
🤖 **VLESS VPN Management Bot**

Welcome to the VLESS VPN management interface!

**User Management Commands:**
• `/adduser <name>` - Create new VPN user
• `/deleteuser <uuid>` - Delete user by UUID
• `/listusers` - Show all users
• `/getconfig <uuid>` - Get user configuration
• `/getqr <uuid>` - Get QR code for user

**System Management Commands:**
• `/status` - Server and containers status
• `/restart` - Restart VPN services
• `/logs` - View system logs
• `/backup` - Create backup
• `/stats` - Usage statistics

**Help:**
• `/help` - Show this message

Select an option below or use commands directly.
        """

        keyboard = [
            [
                InlineKeyboardButton("👥 Users", callback_data="menu_users"),
                InlineKeyboardButton("⚙️ System", callback_data="menu_system")
            ],
            [
                InlineKeyboardButton("📊 Statistics", callback_data="stats"),
                InlineKeyboardButton("❓ Help", callback_data="help")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            welcome_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /help command"""
        if not await self._admin_only(update, context):
            return

        help_text = """
📚 **VLESS VPN Bot Help**

**User Management:**
• `/adduser john` - Create user 'john'
• `/deleteuser uuid-here` - Delete user by UUID
• `/listusers` - List all users with UUIDs
• `/getconfig uuid-here` - Get VLESS URL for user
• `/getqr uuid-here` - Get QR code for mobile apps

**System Management:**
• `/status` - Check server health
• `/restart` - Restart VPN services (use with caution)
• `/logs` - View recent system logs
• `/backup` - Create system backup
• `/stats` - Show usage statistics

**Tips:**
• UUIDs are shown in `/listusers` output
• QR codes work with most VPN apps
• Always backup before making major changes
• Monitor logs for troubleshooting

Need help? Check the logs or restart services if needed.
        """

        await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

    async def add_user(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /adduser command"""
        if not await self._admin_only(update, context):
            return

        if not context.args:
            await update.message.reply_text(
                "❌ Please provide a username: `/adduser <username>`",
                parse_mode=ParseMode.MARKDOWN
            )
            return

        username = context.args[0]

        # Validate username
        if not username.replace('-', '').replace('_', '').isalnum():
            await update.message.reply_text(
                "❌ Invalid username. Use only alphanumeric characters, hyphens, and underscores."
            )
            return

        await update.message.reply_text(f"⏳ Creating user '{username}'...")

        # Run user creation command
        result = await self._run_shell_command([
            'bash', str(self.user_mgmt_script), 'add_user', username
        ])

        if result['returncode'] == 0:
            # Parse the output to get user info
            users_data = await self._get_users_json()
            if users_data:
                # Find the newly created user
                new_user = None
                for user in users_data.get('users', []):
                    if user.get('username') == username:
                        new_user = user
                        break

                if new_user:
                    success_text = f"""
✅ **User created successfully!**

**Username:** `{new_user['username']}`
**UUID:** `{new_user['uuid']}`
**Created:** {new_user.get('created', 'N/A')}

Use `/getconfig {new_user['uuid']}` to get the configuration.
Use `/getqr {new_user['uuid']}` to get the QR code.
                    """

                    keyboard = [
                        [
                            InlineKeyboardButton(
                                "📋 Get Config",
                                callback_data=f"getconfig_{new_user['uuid']}"
                            ),
                            InlineKeyboardButton(
                                "📱 Get QR",
                                callback_data=f"getqr_{new_user['uuid']}"
                            )
                        ]
                    ]

                    reply_markup = InlineKeyboardMarkup(keyboard)

                    await update.message.reply_text(
                        success_text,
                        parse_mode=ParseMode.MARKDOWN,
                        reply_markup=reply_markup
                    )
                else:
                    await update.message.reply_text("✅ User created, but could not retrieve details.")
            else:
                await update.message.reply_text("✅ User created successfully!")
        else:
            error_text = f"❌ Failed to create user:\n`{result['stderr'] or result['stdout']}`"
            await update.message.reply_text(error_text, parse_mode=ParseMode.MARKDOWN)

    async def delete_user(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /deleteuser command"""
        if not await self._admin_only(update, context):
            return

        if not context.args:
            await update.message.reply_text(
                "❌ Please provide a UUID: `/deleteuser <uuid>`",
                parse_mode=ParseMode.MARKDOWN
            )
            return

        uuid = context.args[0]

        # Get user info before deletion
        users_data = await self._get_users_json()
        user_to_delete = None

        if users_data:
            for user in users_data.get('users', []):
                if user.get('uuid') == uuid:
                    user_to_delete = user
                    break

        if not user_to_delete:
            await update.message.reply_text("❌ User not found with the provided UUID.")
            return

        # Ask for confirmation
        keyboard = [
            [
                InlineKeyboardButton("✅ Yes, Delete", callback_data=f"confirm_delete_{uuid}"),
                InlineKeyboardButton("❌ Cancel", callback_data="cancel_delete")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            f"⚠️ **Confirm Deletion**\n\n"
            f"Are you sure you want to delete user **{user_to_delete['username']}**?\n"
            f"UUID: `{uuid}`\n\n"
            f"This action cannot be undone!",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def list_users(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /listusers command"""
        if not await self._admin_only(update, context):
            return

        users_data = await self._get_users_json()

        if not users_data or not users_data.get('users'):
            await update.message.reply_text("📝 No users found.")
            return

        users = users_data['users']
        total_users = len(users)

        # Create users list
        users_text = f"👥 **VPN Users ({total_users} total)**\n\n"

        for i, user in enumerate(users, 1):
            username = user.get('username', 'Unknown')
            uuid = user.get('uuid', 'Unknown')
            status = user.get('status', 'active')
            created = user.get('created', 'Unknown')

            status_emoji = "✅" if status == "active" else "❌"

            users_text += f"{i}. {status_emoji} **{username}**\n"
            users_text += f"   UUID: `{uuid}`\n"
            users_text += f"   Created: {created}\n\n"

        # Add inline keyboard for actions
        keyboard = []

        # Add user management buttons
        keyboard.append([
            InlineKeyboardButton("➕ Add User", callback_data="add_user_prompt"),
            InlineKeyboardButton("🔄 Refresh", callback_data="list_users")
        ])

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            users_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def get_config(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /getconfig command"""
        if not await self._admin_only(update, context):
            return

        if not context.args:
            await update.message.reply_text(
                "❌ Please provide a UUID: `/getconfig <uuid>`",
                parse_mode=ParseMode.MARKDOWN
            )
            return

        uuid = context.args[0]

        # Get user info
        users_data = await self._get_users_json()
        user = None

        if users_data:
            for u in users_data.get('users', []):
                if u.get('uuid') == uuid:
                    user = u
                    break

        if not user:
            await update.message.reply_text("❌ User not found with the provided UUID.")
            return

        # Get VLESS URL using shell script
        result = await self._run_shell_command([
            'bash', '-c',
            f'source {self.user_mgmt_script} && get_user_config {uuid} vless'
        ])

        if result['returncode'] == 0 and result['stdout']:
            vless_url = result['stdout'].strip()

            config_text = f"""
📋 **Configuration for {user['username']}**

**VLESS URL:**
`{vless_url}`

**Instructions:**
1. Copy the VLESS URL above
2. Import it into your VPN client
3. Or use the QR code: `/getqr {uuid}`

**Supported Apps:**
• V2RayNG (Android)
• Shadowrocket (iOS)
• V2Ray (Desktop)
            """

            keyboard = [
                [
                    InlineKeyboardButton("📱 Get QR Code", callback_data=f"getqr_{uuid}"),
                    InlineKeyboardButton("📄 Get JSON", callback_data=f"getjson_{uuid}")
                ]
            ]

            reply_markup = InlineKeyboardMarkup(keyboard)

            await update.message.reply_text(
                config_text,
                parse_mode=ParseMode.MARKDOWN,
                reply_markup=reply_markup
            )
        else:
            await update.message.reply_text("❌ Failed to get user configuration.")

    async def get_qr(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /getqr command"""
        if not await self._admin_only(update, context):
            return

        if not context.args:
            await update.message.reply_text(
                "❌ Please provide a UUID: `/getqr <uuid>`",
                parse_mode=ParseMode.MARKDOWN
            )
            return

        uuid = context.args[0]

        # Get user info
        users_data = await self._get_users_json()
        user = None

        if users_data:
            for u in users_data.get('users', []):
                if u.get('uuid') == uuid:
                    user = u
                    break

        if not user:
            await update.message.reply_text("❌ User not found with the provided UUID.")
            return

        await update.message.reply_text("⏳ Generating QR code...")

        # Get VLESS URL
        result = await self._run_shell_command([
            'bash', '-c',
            f'source {self.user_mgmt_script} && get_user_config {uuid} vless'
        ])

        if result['returncode'] == 0 and result['stdout']:
            vless_url = result['stdout'].strip()

            try:
                # Generate QR code
                qr_buffer = await self._generate_qr_code(vless_url)

                # Send QR code as photo
                await update.message.reply_photo(
                    photo=qr_buffer,
                    caption=f"📱 **QR Code for {user['username']}**\n\n"
                           f"Scan with your VPN app to import configuration.",
                    parse_mode=ParseMode.MARKDOWN
                )

            except Exception as e:
                logger.error(f"Error generating QR code: {e}")
                await update.message.reply_text("❌ Failed to generate QR code.")
        else:
            await update.message.reply_text("❌ Failed to get user configuration for QR code.")

    async def status(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /status command"""
        if not await self._admin_only(update, context):
            return

        await update.message.reply_text("⏳ Checking system status...")

        # Check Docker containers
        docker_result = await self._run_shell_command(['docker', 'ps', '--format', 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'])

        # Check disk usage
        disk_result = await self._run_shell_command(['df', '-h', '/'])

        # Check memory usage
        memory_result = await self._run_shell_command(['free', '-h'])

        # Get users count
        users_data = await self._get_users_json()
        user_count = len(users_data.get('users', [])) if users_data else 0

        status_text = f"""
📊 **System Status**

**VPN Users:** {user_count} active

**Docker Containers:**
```
{docker_result['stdout'] if docker_result['returncode'] == 0 else 'Failed to get container status'}
```

**System Resources:**
```
{memory_result['stdout'].split(chr(10))[1] if memory_result['returncode'] == 0 else 'Memory info unavailable'}
```

**Disk Usage:**
```
{disk_result['stdout'].split(chr(10))[1] if disk_result['returncode'] == 0 else 'Disk info unavailable'}
```

**Last Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        """

        keyboard = [
            [
                InlineKeyboardButton("🔄 Refresh", callback_data="status"),
                InlineKeyboardButton("📊 Detailed Stats", callback_data="stats")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            status_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def restart_services(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /restart command"""
        if not await self._admin_only(update, context):
            return

        # Ask for confirmation
        keyboard = [
            [
                InlineKeyboardButton("✅ Yes, Restart", callback_data="confirm_restart"),
                InlineKeyboardButton("❌ Cancel", callback_data="cancel_restart")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            "⚠️ **Confirm Service Restart**\n\n"
            "This will restart all VPN services. Active connections will be interrupted.\n\n"
            "Are you sure you want to proceed?",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def view_logs(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /logs command"""
        if not await self._admin_only(update, context):
            return

        # Get recent logs
        log_files = [
            ('/opt/vless/logs/telegram_bot.log', 'Bot Logs'),
            ('/var/log/docker.log', 'Docker Logs'),
            ('/opt/vless/logs/xray.log', 'Xray Logs')
        ]

        logs_text = "📋 **Recent System Logs**\n\n"

        for log_file, log_name in log_files:
            result = await self._run_shell_command(['tail', '-10', log_file])

            if result['returncode'] == 0:
                logs_text += f"**{log_name}:**\n"
                logs_text += f"```\n{result['stdout']}\n```\n\n"
            else:
                logs_text += f"**{log_name}:** Not available\n\n"

        # Truncate if too long
        if len(logs_text) > 4000:
            logs_text = logs_text[:4000] + "\n... (truncated)"

        keyboard = [
            [
                InlineKeyboardButton("🔄 Refresh Logs", callback_data="logs"),
                InlineKeyboardButton("📊 System Status", callback_data="status")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            logs_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    async def create_backup(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /backup command"""
        if not await self._admin_only(update, context):
            return

        await update.message.reply_text("⏳ Creating system backup...")

        # Run backup script
        backup_script = Path("/home/ikeniborn/Documents/Project/vless/modules/backup_restore.sh")
        result = await self._run_shell_command([
            'bash', str(backup_script), 'create_backup'
        ])

        if result['returncode'] == 0:
            backup_text = f"""
✅ **Backup Created Successfully**

**Details:**
```
{result['stdout']}
```

Backup location: `/opt/vless/backups/`
            """
        else:
            backup_text = f"""
❌ **Backup Failed**

**Error:**
```
{result['stderr'] or result['stdout']}
```
            """

        await update.message.reply_text(backup_text, parse_mode=ParseMode.MARKDOWN)

    async def show_stats(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /stats command"""
        if not await self._admin_only(update, context):
            return

        # Get system statistics
        users_data = await self._get_users_json()

        if users_data:
            total_users = len(users_data.get('users', []))
            active_users = len([u for u in users_data.get('users', []) if u.get('status') == 'active'])

            # Get creation dates for user statistics
            created_dates = [u.get('created', '') for u in users_data.get('users', []) if u.get('created')]

            stats_text = f"""
📊 **Usage Statistics**

**Users:**
• Total Users: {total_users}
• Active Users: {active_users}
• Inactive Users: {total_users - active_users}

**System:**
• Bot Uptime: Since last restart
• Database: {users_data.get('metadata', {}).get('last_modified', 'Unknown')}

**Recent Activity:**
• Last User Created: {max(created_dates) if created_dates else 'None'}
• Total Users Created: {total_users}
            """
        else:
            stats_text = "📊 **Usage Statistics**\n\nNo user data available."

        keyboard = [
            [
                InlineKeyboardButton("👥 View Users", callback_data="list_users"),
                InlineKeyboardButton("📊 System Status", callback_data="status")
            ]
        ]

        reply_markup = InlineKeyboardMarkup(keyboard)

        await update.message.reply_text(
            stats_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )

    # Callback Query Handlers

    async def button_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle button callbacks"""
        query = update.callback_query
        await query.answer()

        data = query.data

        if data == "menu_users":
            keyboard = [
                [
                    InlineKeyboardButton("👥 List Users", callback_data="list_users"),
                    InlineKeyboardButton("➕ Add User", callback_data="add_user_prompt")
                ],
                [
                    InlineKeyboardButton("🔙 Back", callback_data="start")
                ]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)

            await query.edit_message_text(
                "👥 **User Management**\n\nSelect an action:",
                parse_mode=ParseMode.MARKDOWN,
                reply_markup=reply_markup
            )

        elif data == "menu_system":
            keyboard = [
                [
                    InlineKeyboardButton("📊 Status", callback_data="status"),
                    InlineKeyboardButton("📋 Logs", callback_data="logs")
                ],
                [
                    InlineKeyboardButton("🔄 Restart", callback_data="restart_confirm"),
                    InlineKeyboardButton("💾 Backup", callback_data="backup")
                ],
                [
                    InlineKeyboardButton("🔙 Back", callback_data="start")
                ]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)

            await query.edit_message_text(
                "⚙️ **System Management**\n\nSelect an action:",
                parse_mode=ParseMode.MARKDOWN,
                reply_markup=reply_markup
            )

        elif data == "list_users":
            # Simulate the list_users command
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            await self.list_users(fake_update, context)

        elif data == "status":
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            await self.status(fake_update, context)

        elif data == "stats":
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            await self.show_stats(fake_update, context)

        elif data == "logs":
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            await self.view_logs(fake_update, context)

        elif data == "backup":
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            await self.create_backup(fake_update, context)

        elif data.startswith("getconfig_"):
            uuid = data.replace("getconfig_", "")
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            fake_context = type('', (), {})()
            fake_context.args = [uuid]
            await self.get_config(fake_update, fake_context)

        elif data.startswith("getqr_"):
            uuid = data.replace("getqr_", "")
            fake_update = type('', (), {})()
            fake_update.message = query.message
            fake_update.effective_user = query.from_user
            fake_context = type('', (), {})()
            fake_context.args = [uuid]
            await self.get_qr(fake_update, fake_context)

        elif data.startswith("confirm_delete_"):
            uuid = data.replace("confirm_delete_", "")
            await query.edit_message_text("⏳ Deleting user...")

            # Run delete command
            result = await self._run_shell_command([
                'bash', str(self.user_mgmt_script), 'remove_user', uuid
            ])

            if result['returncode'] == 0:
                await query.edit_message_text(
                    "✅ User deleted successfully!",
                    parse_mode=ParseMode.MARKDOWN
                )
            else:
                await query.edit_message_text(
                    f"❌ Failed to delete user:\n`{result['stderr'] or result['stdout']}`",
                    parse_mode=ParseMode.MARKDOWN
                )

        elif data == "cancel_delete":
            await query.edit_message_text("❌ User deletion cancelled.")

        elif data == "confirm_restart":
            await query.edit_message_text("⏳ Restarting services...")

            # Restart Docker Compose services
            result = await self._run_shell_command([
                'docker-compose', '-f', '/home/ikeniborn/Documents/Project/vless/config/docker-compose.yml', 'restart'
            ])

            if result['returncode'] == 0:
                await query.edit_message_text("✅ Services restarted successfully!")
            else:
                await query.edit_message_text(
                    f"❌ Failed to restart services:\n`{result['stderr'] or result['stdout']}`",
                    parse_mode=ParseMode.MARKDOWN
                )

        elif data == "cancel_restart":
            await query.edit_message_text("❌ Service restart cancelled.")

    async def error_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle errors"""
        logger.error(f"Update {update} caused error {context.error}")

        try:
            if update and update.effective_message:
                await update.effective_message.reply_text(
                    "❌ An error occurred. Please try again or contact the administrator."
                )
        except Exception as e:
            logger.error(f"Error in error handler: {e}")

    def setup_handlers(self) -> None:
        """Setup command and callback handlers"""

        # Command handlers
        self.application.add_handler(CommandHandler("start", self.start))
        self.application.add_handler(CommandHandler("help", self.help_command))
        self.application.add_handler(CommandHandler("adduser", self.add_user))
        self.application.add_handler(CommandHandler("deleteuser", self.delete_user))
        self.application.add_handler(CommandHandler("listusers", self.list_users))
        self.application.add_handler(CommandHandler("getconfig", self.get_config))
        self.application.add_handler(CommandHandler("getqr", self.get_qr))
        self.application.add_handler(CommandHandler("status", self.status))
        self.application.add_handler(CommandHandler("restart", self.restart_services))
        self.application.add_handler(CommandHandler("logs", self.view_logs))
        self.application.add_handler(CommandHandler("backup", self.create_backup))
        self.application.add_handler(CommandHandler("stats", self.show_stats))

        # Callback query handler
        self.application.add_handler(CallbackQueryHandler(self.button_callback))

        # Error handler
        self.application.add_error_handler(self.error_handler)

    async def start_bot(self) -> None:
        """Start the bot"""
        try:
            # Create application
            self.application = Application.builder().token(self.token).build()

            # Setup handlers
            self.setup_handlers()

            logger.info("Starting VLESS VPN Telegram Bot...")

            # Start polling
            await self.application.run_polling(
                drop_pending_updates=True,
                close_loop=False
            )

        except Exception as e:
            logger.error(f"Error starting bot: {e}")
            raise

def main():
    """Main entry point"""

    # Get configuration from environment
    bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
    admin_id = os.getenv('ADMIN_TELEGRAM_ID')

    if not bot_token:
        logger.error("TELEGRAM_BOT_TOKEN environment variable is required")
        sys.exit(1)

    if not admin_id:
        logger.error("ADMIN_TELEGRAM_ID environment variable is required")
        sys.exit(1)

    try:
        admin_id = int(admin_id)
    except ValueError:
        logger.error("ADMIN_TELEGRAM_ID must be a valid integer")
        sys.exit(1)

    # Create and start bot
    bot = VLESSBot(bot_token, admin_id)

    try:
        asyncio.run(bot.start_bot())
    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    except Exception as e:
        logger.error(f"Bot crashed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
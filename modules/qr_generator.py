#!/usr/bin/env python3
"""
======================================================================================
VLESS+Reality VPN Management System - QR Code Generator Module
======================================================================================
This module provides QR code generation functionality for easy client configuration
import. Supports both image generation and terminal ASCII display.

Author: Claude Code
Version: 1.0
Last Modified: 2025-09-21
======================================================================================
"""

import sys
import os
import json
import re
import argparse
from pathlib import Path
from datetime import datetime

try:
    import qrcode
    from qrcode.image.styledpil import StyledPilImage
    from qrcode.image.styles.moduledrawers import RoundedModuleDrawer
    from qrcode.image.styles.colormasks import SquareGradiantColorMask
    QRCODE_AVAILABLE = True
except ImportError:
    QRCODE_AVAILABLE = False

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# Constants
SCRIPT_DIR = Path(__file__).parent
USER_DIR = Path("/opt/vless/users")
USER_DATABASE = USER_DIR / "users.json"
QR_OUTPUT_DIR = USER_DIR / "qr_codes"

# Default QR code settings
QR_VERSION = 1
QR_ERROR_CORRECT = qrcode.constants.ERROR_CORRECT_M
QR_BOX_SIZE = 10
QR_BORDER = 4

class Logger:
    """Simple logger for consistent output formatting"""

    @staticmethod
    def info(message):
        print(f"[INFO] {message}")

    @staticmethod
    def error(message):
        print(f"[ERROR] {message}", file=sys.stderr)

    @staticmethod
    def success(message):
        print(f"[SUCCESS] {message}")

    @staticmethod
    def warn(message):
        print(f"[WARN] {message}")

class VLESSQRGenerator:
    """VLESS QR Code generator with multiple output formats"""

    def __init__(self):
        self.logger = Logger()
        self.ensure_directories()

    def ensure_directories(self):
        """Ensure necessary directories exist"""
        try:
            QR_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
            os.chmod(QR_OUTPUT_DIR, 0o700)
            self.logger.info(f"QR output directory ready: {QR_OUTPUT_DIR}")
        except Exception as e:
            self.logger.error(f"Failed to create QR output directory: {e}")
            sys.exit(1)

    def get_user_info(self, identifier):
        """Get user information by username or UUID"""
        if not USER_DATABASE.exists():
            self.logger.error("User database not found")
            return None

        try:
            with open(USER_DATABASE, 'r') as f:
                data = json.load(f)

            users = data.get('users', [])
            for user in users:
                if (user.get('username') == identifier or
                    user.get('uuid') == identifier):
                    return user

            self.logger.error(f"User not found: {identifier}")
            return None

        except Exception as e:
            self.logger.error(f"Failed to read user database: {e}")
            return None

    def get_server_ip(self):
        """Get server public IP address"""
        import subprocess
        import urllib.request

        # Try multiple services to get public IP
        services = [
            "https://ifconfig.me/ip",
            "https://icanhazip.com",
            "https://ipecho.net/plain"
        ]

        for service in services:
            try:
                with urllib.request.urlopen(service, timeout=10) as response:
                    ip = response.read().decode().strip()
                    if self.validate_ip(ip):
                        return ip
            except Exception:
                continue

        # Fallback: try to get from system
        try:
            result = subprocess.run(
                ["ip", "route", "get", "8.8.8.8"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'src' in line:
                        ip = line.split('src')[1].strip().split()[0]
                        if self.validate_ip(ip):
                            return ip
        except Exception:
            pass

        self.logger.error("Failed to determine server IP address")
        return None

    def validate_ip(self, ip):
        """Validate IP address format"""
        pattern = r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
        return re.match(pattern, ip) is not None

    def validate_vless_url(self, url):
        """Validate VLESS URL format"""
        vless_pattern = r'^vless://[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@[\w\.-]+:\d+\?.*#.*$'
        return re.match(vless_pattern, url, re.IGNORECASE) is not None

    def generate_vless_url(self, user_info, server_ip):
        """Generate VLESS connection URL"""
        if not user_info or not server_ip:
            return None

        username = user_info.get('username', 'unknown')
        uuid = user_info.get('uuid')
        port = 443  # Default VLESS port

        # VLESS URL format for Reality
        vless_url = (
            f"vless://{uuid}@{server_ip}:{port}"
            f"?type=tcp&security=reality&pbk=&fp=chrome"
            f"&sni=www.google.com&sid=&spx=%2F&flow=xtls-rprx-vision"
            f"#{username}"
        )

        if not self.validate_vless_url(vless_url):
            self.logger.error(f"Generated invalid VLESS URL for user: {username}")
            return None

        return vless_url

    def create_qr_code(self, data, version=None, error_correct=None, box_size=None, border=None):
        """Create QR code object with specified parameters"""
        if not QRCODE_AVAILABLE:
            raise ImportError("qrcode library is not available")

        qr = qrcode.QRCode(
            version=version or QR_VERSION,
            error_correction=error_correct or QR_ERROR_CORRECT,
            box_size=box_size or QR_BOX_SIZE,
            border=border or QR_BORDER,
        )

        qr.add_data(data)
        qr.make(fit=True)

        return qr

    def generate_basic_qr_image(self, qr_code, fill_color='black', back_color='white'):
        """Generate basic QR code image"""
        return qr_code.make_image(fill_color=fill_color, back_color=back_color)

    def generate_styled_qr_image(self, qr_code):
        """Generate styled QR code image with enhanced appearance"""
        if not PIL_AVAILABLE:
            self.logger.warn("PIL not available, generating basic QR code")
            return self.generate_basic_qr_image(qr_code)

        try:
            # Create styled QR code with rounded modules and gradient
            img = qr_code.make_image(
                image_factory=StyledPilImage,
                module_drawer=RoundedModuleDrawer(),
                color_mask=SquareGradiantColorMask(
                    back_color=(255, 255, 255),  # White background
                    center_color=(0, 0, 0),      # Black center
                    edge_color=(100, 100, 100)   # Gray edge
                )
            )
            return img
        except Exception as e:
            self.logger.warn(f"Failed to create styled QR code: {e}")
            return self.generate_basic_qr_image(qr_code)

    def add_logo_to_qr(self, qr_image, logo_path=None):
        """Add logo to center of QR code (if logo provided)"""
        if not logo_path or not Path(logo_path).exists() or not PIL_AVAILABLE:
            return qr_image

        try:
            logo = Image.open(logo_path)

            # Calculate logo size (about 1/5 of QR code size)
            qr_width, qr_height = qr_image.size
            logo_size = min(qr_width, qr_height) // 5

            # Resize logo
            logo = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)

            # Calculate position to center logo
            logo_pos = (
                (qr_width - logo_size) // 2,
                (qr_height - logo_size) // 2
            )

            # Paste logo onto QR code
            qr_image.paste(logo, logo_pos)

            return qr_image

        except Exception as e:
            self.logger.warn(f"Failed to add logo to QR code: {e}")
            return qr_image

    def save_qr_image(self, qr_image, output_path, add_text_info=True, user_info=None):
        """Save QR code image with optional text information"""
        try:
            if add_text_info and user_info and PIL_AVAILABLE:
                # Add text information below QR code
                qr_image = self.add_text_to_qr(qr_image, user_info)

            qr_image.save(output_path)
            os.chmod(output_path, 0o600)
            self.logger.success(f"QR code saved: {output_path}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to save QR code: {e}")
            return False

    def add_text_to_qr(self, qr_image, user_info):
        """Add user information text below QR code"""
        try:
            # Create new image with extra space for text
            img_width, img_height = qr_image.size
            text_height = 100
            new_height = img_height + text_height

            new_image = Image.new('RGB', (img_width, new_height), 'white')
            new_image.paste(qr_image, (0, 0))

            # Draw text
            draw = ImageDraw.Draw(new_image)

            # Try to use a better font, fallback to default
            try:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
            except:
                font = ImageFont.load_default()

            # Add user information
            username = user_info.get('username', 'Unknown')
            created_date = user_info.get('created_date', '')[:10]  # Just date part

            text_lines = [
                f"User: {username}",
                f"Created: {created_date}",
                f"VLESS+Reality Configuration"
            ]

            y_offset = img_height + 10
            for line in text_lines:
                # Calculate text width for centering
                bbox = draw.textbbox((0, 0), line, font=font)
                text_width = bbox[2] - bbox[0]
                x_pos = (img_width - text_width) // 2

                draw.text((x_pos, y_offset), line, fill='black', font=font)
                y_offset += 25

            return new_image

        except Exception as e:
            self.logger.warn(f"Failed to add text to QR code: {e}")
            return qr_image

    def display_qr_terminal(self, qr_code):
        """Display QR code in terminal using ASCII characters"""
        try:
            # Use the qrcode library's terminal display
            qr_code.print_ascii(invert=True)
            return True
        except Exception as e:
            self.logger.error(f"Failed to display QR code in terminal: {e}")
            return False

    def generate_qr_for_user(self, identifier, output_format='png', styled=True, terminal_display=True):
        """Generate QR code for a specific user"""
        if not QRCODE_AVAILABLE:
            self.logger.error("QR code generation requires 'qrcode' library")
            self.logger.error("Install with: pip3 install qrcode[pil]")
            return False

        # Get user information
        user_info = self.get_user_info(identifier)
        if not user_info:
            return False

        # Get server IP
        server_ip = self.get_server_ip()
        if not server_ip:
            return False

        # Generate VLESS URL
        vless_url = self.generate_vless_url(user_info, server_ip)
        if not vless_url:
            return False

        username = user_info.get('username')
        self.logger.info(f"Generating QR code for user: {username}")

        try:
            # Create QR code
            qr_code = self.create_qr_code(vless_url)

            # Display in terminal if requested
            if terminal_display:
                print(f"\nQR Code for user: {username}")
                print("=" * 50)
                self.display_qr_terminal(qr_code)
                print("=" * 50)
                print(f"VLESS URL: {vless_url}")
                print("=" * 50)

            # Generate image if PNG format requested
            if output_format.lower() == 'png':
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_filename = f"{username}_qr_{timestamp}.png"
                output_path = QR_OUTPUT_DIR / output_filename

                # Create QR image (styled or basic)
                if styled and PIL_AVAILABLE:
                    qr_image = self.generate_styled_qr_image(qr_code)
                else:
                    qr_image = self.generate_basic_qr_image(qr_code)

                # Save QR image
                if self.save_qr_image(qr_image, output_path, True, user_info):
                    self.logger.success(f"QR code image generated: {output_path}")
                    return True
                else:
                    return False

            return True

        except Exception as e:
            self.logger.error(f"Failed to generate QR code for user {username}: {e}")
            return False

    def batch_generate_qr_codes(self, output_format='png', styled=True):
        """Generate QR codes for all users"""
        if not USER_DATABASE.exists():
            self.logger.error("User database not found")
            return False

        try:
            with open(USER_DATABASE, 'r') as f:
                data = json.load(f)

            users = data.get('users', [])
            if not users:
                self.logger.warn("No users found in database")
                return True

            success_count = 0
            total_count = len(users)

            self.logger.info(f"Generating QR codes for {total_count} users...")

            for user in users:
                username = user.get('username')
                if self.generate_qr_for_user(username, output_format, styled, False):
                    success_count += 1
                else:
                    self.logger.error(f"Failed to generate QR code for user: {username}")

            self.logger.success(f"Generated QR codes for {success_count}/{total_count} users")
            return success_count == total_count

        except Exception as e:
            self.logger.error(f"Failed to batch generate QR codes: {e}")
            return False

def main():
    """Main function for command line usage"""
    parser = argparse.ArgumentParser(
        description="VLESS QR Code Generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s user123                    # Generate QR for specific user
  %(prog)s user123 --no-terminal      # Generate without terminal display
  %(prog)s --batch                    # Generate for all users
  %(prog)s user123 --basic            # Generate basic QR without styling
        """
    )

    parser.add_argument(
        'user_identifier',
        nargs='?',
        help='Username or UUID to generate QR code for'
    )

    parser.add_argument(
        '--batch',
        action='store_true',
        help='Generate QR codes for all users'
    )

    parser.add_argument(
        '--format',
        choices=['png', 'terminal'],
        default='png',
        help='Output format (default: png)'
    )

    parser.add_argument(
        '--basic',
        action='store_true',
        help='Generate basic QR code without styling'
    )

    parser.add_argument(
        '--no-terminal',
        action='store_true',
        help='Skip terminal display of QR code'
    )

    args = parser.parse_args()

    # Check if running as root
    if os.geteuid() != 0:
        print("[ERROR] This script must be run as root")
        sys.exit(1)

    generator = VLESSQRGenerator()

    if args.batch:
        success = generator.batch_generate_qr_codes(
            output_format=args.format,
            styled=not args.basic
        )
        sys.exit(0 if success else 1)

    elif args.user_identifier:
        success = generator.generate_qr_for_user(
            args.user_identifier,
            output_format=args.format,
            styled=not args.basic,
            terminal_display=not args.no_terminal
        )
        sys.exit(0 if success else 1)

    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
#!/usr/bin/env python3

"""
VLESS+Reality VPN Management System - QR Code Generator
Version: 1.0.0
Description: Python-based QR code generation for mobile clients

This module provides:
- QR code generation from VLESS URLs
- PNG output with customizable size
- Batch QR code generation
- ASCII QR code for terminal display
- Error correction level configuration
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Optional, Dict, Any, List

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_L, ERROR_CORRECT_M, ERROR_CORRECT_Q, ERROR_CORRECT_H
except ImportError:
    print("Error: qrcode library not installed. Install with: pip3 install qrcode[pil]", file=sys.stderr)
    sys.exit(1)

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("Warning: PIL library not available. PNG output will be limited.", file=sys.stderr)


class QRGenerator:
    """QR Code generator for VLESS configurations"""

    def __init__(self):
        self.error_correction_levels = {
            'L': ERROR_CORRECT_L,  # ~7%
            'M': ERROR_CORRECT_M,  # ~15%
            'Q': ERROR_CORRECT_Q,  # ~25%
            'H': ERROR_CORRECT_H   # ~30%
        }

    def generate_qr_ascii(self, text: str, error_correction: str = 'M') -> str:
        """Generate ASCII QR code for terminal display"""
        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=self.error_correction_levels[error_correction],
                box_size=1,
                border=2,
            )
            qr.add_data(text)
            qr.make(fit=True)

            # Generate ASCII representation
            matrix = qr.get_matrix()
            ascii_qr = []

            for row in matrix:
                line = ""
                for cell in row:
                    line += "██" if cell else "  "
                ascii_qr.append(line)

            return "\n".join(ascii_qr)

        except Exception as e:
            raise Exception(f"Failed to generate ASCII QR code: {e}")

    def generate_qr_png(self, text: str, output_file: str, size: int = 300,
                       error_correction: str = 'M') -> bool:
        """Generate PNG QR code"""
        if not PIL_AVAILABLE:
            raise Exception("PIL library required for PNG generation")

        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=self.error_correction_levels[error_correction],
                box_size=10,
                border=4,
            )
            qr.add_data(text)
            qr.make(fit=True)

            # Create QR code image
            img = qr.make_image(fill_color="black", back_color="white")

            # Resize if needed
            if size != 300:
                img = img.resize((size, size), Image.Resampling.LANCZOS)

            # Save image
            img.save(output_file, "PNG")
            return True

        except Exception as e:
            raise Exception(f"Failed to generate PNG QR code: {e}")

    def generate_qr_batch(self, vless_urls: List[Dict[str, str]],
                         output_dir: str, format_type: str = 'png') -> List[str]:
        """Generate QR codes for multiple VLESS URLs"""
        os.makedirs(output_dir, exist_ok=True)
        generated_files = []

        for i, url_data in enumerate(vless_urls):
            email = url_data.get('email', f'user_{i}')
            vless_url = url_data.get('url', '')

            if not vless_url:
                print(f"Warning: Empty URL for user {email}", file=sys.stderr)
                continue

            # Sanitize filename
            safe_email = "".join(c for c in email if c.isalnum() or c in "._-")

            if format_type == 'png':
                output_file = os.path.join(output_dir, f"{safe_email}_qr.png")
                try:
                    self.generate_qr_png(vless_url, output_file)
                    generated_files.append(output_file)
                    print(f"Generated PNG QR code: {output_file}")
                except Exception as e:
                    print(f"Error generating PNG for {email}: {e}", file=sys.stderr)

            elif format_type == 'ascii':
                output_file = os.path.join(output_dir, f"{safe_email}_qr.txt")
                try:
                    ascii_qr = self.generate_qr_ascii(vless_url)
                    with open(output_file, 'w') as f:
                        f.write(f"QR Code for: {email}\n")
                        f.write(f"VLESS URL: {vless_url}\n\n")
                        f.write(ascii_qr)
                    generated_files.append(output_file)
                    print(f"Generated ASCII QR code: {output_file}")
                except Exception as e:
                    print(f"Error generating ASCII for {email}: {e}", file=sys.stderr)

        return generated_files

    def validate_vless_url(self, url: str) -> bool:
        """Validate VLESS URL format"""
        if not url.startswith('vless://'):
            return False

        # Basic validation - should contain essential components
        required_params = ['@', ':', '?', 'type=', 'security=']
        return all(param in url for param in required_params)


def load_users_from_database(db_file: str) -> List[Dict[str, str]]:
    """Load users from JSON database and generate VLESS URLs"""
    try:
        with open(db_file, 'r') as f:
            db_data = json.load(f)

        users = db_data.get('users', {})
        vless_urls = []

        # This is a simplified version - in practice, you'd need server config
        server_ip = "YOUR_SERVER_IP"
        server_port = "443"
        sni_domain = "www.microsoft.com"
        public_key = "YOUR_PUBLIC_KEY"
        short_id = "YOUR_SHORT_ID"

        for uuid, user_data in users.items():
            if user_data.get('status') == 'active':
                email = user_data.get('email', 'unknown')
                vless_url = (
                    f"vless://{uuid}@{server_ip}:{server_port}"
                    f"?type=tcp&security=reality&sni={sni_domain}"
                    f"&fp=chrome&pbk={public_key}&sid={short_id}"
                    f"&flow=xtls-rprx-vision#{email}"
                )

                vless_urls.append({
                    'email': email,
                    'uuid': uuid,
                    'url': vless_url
                })

        return vless_urls

    except FileNotFoundError:
        raise Exception(f"Database file not found: {db_file}")
    except json.JSONDecodeError:
        raise Exception(f"Invalid JSON in database file: {db_file}")
    except Exception as e:
        raise Exception(f"Error loading users from database: {e}")


def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="VLESS+Reality VPN QR Code Generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate ASCII QR code for VLESS URL
  %(prog)s --text "vless://uuid@server:443?..." --format ascii

  # Generate PNG QR code
  %(prog)s --text "vless://uuid@server:443?..." --format png --output qr.png

  # Generate QR codes for all users in database
  %(prog)s --database /opt/vless/users/users.json --batch-output ./qr_codes/

  # Generate QR code with custom settings
  %(prog)s --text "vless://uuid@server:443?..." --format png --size 500 --error-correction H
        """
    )

    # Input options
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('--text', type=str, help='VLESS URL text to encode')
    input_group.add_argument('--database', type=str, help='Path to user database JSON file')
    input_group.add_argument('--file', type=str, help='File containing VLESS URLs (one per line)')

    # Output options
    parser.add_argument('--format', choices=['ascii', 'png'], default='ascii',
                       help='Output format (default: ascii)')
    parser.add_argument('--output', type=str, help='Output file for PNG format')
    parser.add_argument('--batch-output', type=str, help='Output directory for batch generation')

    # QR code options
    parser.add_argument('--size', type=int, default=300,
                       help='PNG image size in pixels (default: 300)')
    parser.add_argument('--error-correction', choices=['L', 'M', 'Q', 'H'], default='M',
                       help='Error correction level (default: M)')

    # Other options
    parser.add_argument('--validate', action='store_true',
                       help='Validate VLESS URL format before generating QR code')
    parser.add_argument('--verbose', action='store_true',
                       help='Enable verbose output')

    args = parser.parse_args()

    try:
        generator = QRGenerator()

        if args.text:
            # Single VLESS URL
            if args.validate and not generator.validate_vless_url(args.text):
                print("Error: Invalid VLESS URL format", file=sys.stderr)
                return 1

            if args.format == 'ascii':
                ascii_qr = generator.generate_qr_ascii(args.text, args.error_correction)
                print(ascii_qr)

            elif args.format == 'png':
                output_file = args.output or 'qr_code.png'
                generator.generate_qr_png(args.text, output_file, args.size, args.error_correction)
                print(f"PNG QR code generated: {output_file}")

        elif args.database:
            # Batch generation from database
            output_dir = args.batch_output or './qr_codes'
            vless_urls = load_users_from_database(args.database)

            if not vless_urls:
                print("No active users found in database", file=sys.stderr)
                return 1

            if args.verbose:
                print(f"Found {len(vless_urls)} active users")

            generated_files = generator.generate_qr_batch(vless_urls, output_dir, args.format)
            print(f"Generated {len(generated_files)} QR codes in {output_dir}")

        elif args.file:
            # Batch generation from file
            output_dir = args.batch_output or './qr_codes'

            try:
                with open(args.file, 'r') as f:
                    urls = [line.strip() for line in f if line.strip()]

                vless_urls = []
                for i, url in enumerate(urls):
                    vless_urls.append({
                        'email': f'user_{i+1}',
                        'url': url
                    })

                generated_files = generator.generate_qr_batch(vless_urls, output_dir, args.format)
                print(f"Generated {len(generated_files)} QR codes in {output_dir}")

            except FileNotFoundError:
                print(f"Error: File not found: {args.file}", file=sys.stderr)
                return 1

        return 0

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
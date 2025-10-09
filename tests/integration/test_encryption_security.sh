#!/bin/bash
################################################################################
# MOVED: This test script has been relocated
#
# Old location: tests/integration/test_encryption_security.sh
# New location: lib/security_tests.sh
#
# This script has been integrated into the VLESS CLI as a module.
#
# Usage (recommended):
#   sudo vless test-security [options]
#   sudo vless test-security --quick
#   sudo vless test-security --verbose
#
# Direct module usage:
#   sudo /opt/vless/lib/security_tests.sh [options]
#
# Or from development repository:
#   cd /path/to/vless
#   sudo lib/security_tests.sh [options]
#
# See: tests/integration/QUICK_START_RU.md for full instructions
################################################################################

echo ""
echo "⚠️  This script has been moved to: lib/security_tests.sh"
echo ""
echo "Please use one of the following methods:"
echo ""
echo "1. CLI command (recommended):"
echo "   sudo vless test-security [options]"
echo ""
echo "2. Direct module execution:"
echo "   sudo /opt/vless/lib/security_tests.sh [options]"
echo ""
echo "3. From development repository:"
echo "   cd /path/to/vless"
echo "   sudo lib/security_tests.sh [options]"
echo ""
echo "For help: sudo vless test-security --help"
echo ""

# Try to run the new location if available
if [[ -f "/opt/vless/lib/security_tests.sh" ]]; then
    echo "Redirecting to /opt/vless/lib/security_tests.sh..."
    exec sudo bash /opt/vless/lib/security_tests.sh "$@"
elif [[ -f "$(dirname "$0")/../../lib/security_tests.sh" ]]; then
    echo "Redirecting to lib/security_tests.sh..."
    exec bash "$(dirname "$0")/../../lib/security_tests.sh" "$@"
else
    echo "Error: security_tests.sh not found in expected locations"
    exit 2
fi

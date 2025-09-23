#!/bin/bash

echo "Phase 5 Telegram Bot Removal Tests"
echo "==================================="
echo

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check telegram files don't exist
echo "Test 1: Telegram files removal"
if [[ ! -f "$PROJECT_DIR/telegram_bot.py" ]] && \
   [[ ! -f "$PROJECT_DIR/modules/telegram_bot.py" ]] && \
   [[ ! -f "$PROJECT_DIR/modules/telegram_bot_manager.sh" ]] && \
   [[ ! -f "$PROJECT_DIR/deploy_telegram_bot.sh" ]] && \
   [[ ! -f "$PROJECT_DIR/config/bot_config.env" ]]; then
    echo "✓ PASS: No telegram bot files found"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: Telegram bot files still exist"
    ((TESTS_FAILED++))
fi

# Test 2: Check requirements.txt
echo "Test 2: Requirements.txt verification"
if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
    if ! grep -q "python-telegram-bot\|telegram-bot" "$PROJECT_DIR/requirements.txt"; then
        echo "✓ PASS: No telegram dependencies in requirements.txt"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Telegram dependencies found in requirements.txt"
        ((TESTS_FAILED++))
    fi

    if grep -q "qrcode" "$PROJECT_DIR/requirements.txt" && grep -q "Pillow" "$PROJECT_DIR/requirements.txt"; then
        echo "✓ PASS: QR code dependencies present"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: QR code dependencies missing"
        ((TESTS_FAILED++))
    fi
else
    echo "✗ FAIL: requirements.txt not found"
    ((TESTS_FAILED++))
fi

# Test 3: Check Phase 5 naming
echo "Test 3: Phase 5 naming verification"
if [[ -f "$PROJECT_DIR/install.sh" ]]; then
    if grep -q "Backup and Maintenance Utilities" "$PROJECT_DIR/install.sh"; then
        echo "✓ PASS: Phase 5 correctly named"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Phase 5 not properly named"
        ((TESTS_FAILED++))
    fi

    if grep -q "install_phase5()" "$PROJECT_DIR/install.sh"; then
        echo "✓ PASS: install_phase5 function exists"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: install_phase5 function missing"
        ((TESTS_FAILED++))
    fi
else
    echo "✗ FAIL: install.sh not found"
    ((TESTS_FAILED++))
fi

# Test 4: Check required modules exist
echo "Test 4: Required Phase 5 modules"
if [[ -f "$PROJECT_DIR/modules/backup_restore.sh" ]] && [[ -f "$PROJECT_DIR/modules/maintenance_utils.sh" ]]; then
    echo "✓ PASS: Required Phase 5 modules exist"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: Required Phase 5 modules missing"
    ((TESTS_FAILED++))
fi

# Test 5: Check install_phase5 doesn't reference telegram
echo "Test 5: install_phase5 telegram check"
if [[ -f "$PROJECT_DIR/install.sh" ]]; then
    if ! sed -n '/^install_phase5()/,/^}/p' "$PROJECT_DIR/install.sh" | grep -q -i "telegram"; then
        echo "✓ PASS: install_phase5 has no telegram references"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: install_phase5 contains telegram references"
        ((TESTS_FAILED++))
    fi
else
    echo "✗ FAIL: install.sh not found"
    ((TESTS_FAILED++))
fi

# Summary
echo
echo "==================================="
echo "TEST SUMMARY"
echo "==================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "Result: ALL TESTS PASSED"
    echo
    echo "✓ Phase 5 Telegram bot removal verification SUCCESSFUL!"
    exit 0
else
    echo "Result: SOME TESTS FAILED"
    echo
    echo "✗ Phase 5 Telegram bot removal verification FAILED!"
    exit 1
fi
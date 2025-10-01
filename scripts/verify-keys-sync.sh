#!/bin/bash

# Скрипт для проверки синхронизации X25519 ключей между всеми местами хранения

set -e

VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   X25519 Keys Synchronization Check${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. Проверяем ключи из файлов
echo -e "${CYAN}[1] Keys from files:${NC}"
if [ -f "$VLESS_HOME/data/keys/private.key" ]; then
    PRIVATE_KEY_FILE=$(cat "$VLESS_HOME/data/keys/private.key")
    echo "  private.key: $PRIVATE_KEY_FILE"
else
    echo -e "  ${RED}✗ private.key NOT FOUND${NC}"
fi

if [ -f "$VLESS_HOME/data/keys/public.key" ]; then
    PUBLIC_KEY_FILE=$(cat "$VLESS_HOME/data/keys/public.key")
    echo "  public.key:  $PUBLIC_KEY_FILE"
else
    echo -e "  ${RED}✗ public.key NOT FOUND${NC}"
fi
echo ""

# 2. Проверяем ключи из .env
echo -e "${CYAN}[2] Keys from .env:${NC}"
if [ -f "$VLESS_HOME/.env" ]; then
    PRIVATE_KEY_ENV=$(grep '^PRIVATE_KEY=' "$VLESS_HOME/.env" | cut -d'=' -f2)
    PUBLIC_KEY_ENV=$(grep '^PUBLIC_KEY=' "$VLESS_HOME/.env" | cut -d'=' -f2)
    echo "  PRIVATE_KEY: $PRIVATE_KEY_ENV"
    echo "  PUBLIC_KEY:  $PUBLIC_KEY_ENV"
else
    echo -e "  ${RED}✗ .env NOT FOUND${NC}"
fi
echo ""

# 3. Проверяем ключ из config.json
echo -e "${CYAN}[3] Keys from config.json:${NC}"
if [ -f "$VLESS_HOME/config/config.json" ]; then
    PRIVATE_KEY_CONFIG=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$VLESS_HOME/config/config.json")
    echo "  privateKey: $PRIVATE_KEY_CONFIG"
else
    echo -e "  ${RED}✗ config.json NOT FOUND${NC}"
fi
echo ""

# 4. Сравниваем все ключи
echo -e "${CYAN}[4] Comparison:${NC}"

# Сравниваем приватные ключи
if [ "$PRIVATE_KEY_FILE" == "$PRIVATE_KEY_ENV" ] && [ "$PRIVATE_KEY_ENV" == "$PRIVATE_KEY_CONFIG" ]; then
    echo -e "  ${GREEN}✓ Private keys are SYNCHRONIZED${NC}"
else
    echo -e "  ${RED}✗ Private keys are NOT SYNCHRONIZED${NC}"
    echo "    File:   $PRIVATE_KEY_FILE"
    echo "    .env:   $PRIVATE_KEY_ENV"
    echo "    Config: $PRIVATE_KEY_CONFIG"
fi

# Сравниваем публичные ключи
if [ "$PUBLIC_KEY_FILE" == "$PUBLIC_KEY_ENV" ]; then
    echo -e "  ${GREEN}✓ Public keys are SYNCHRONIZED${NC}"
else
    echo -e "  ${RED}✗ Public keys are NOT SYNCHRONIZED${NC}"
    echo "    File: $PUBLIC_KEY_FILE"
    echo "    .env: $PUBLIC_KEY_ENV"
fi
echo ""

# 5. Проверяем соответствие приватного и публичного ключей
echo -e "${CYAN}[5] Verifying key pair correspondence:${NC}"
if command -v docker &> /dev/null; then
    EXPECTED_PUBLIC=$(docker run --rm teddysun/xray:24.11.30 xray x25519 -i "$PRIVATE_KEY_CONFIG" 2>/dev/null | grep -i "public" | awk '{print $NF}')

    if [ "$EXPECTED_PUBLIC" == "$PUBLIC_KEY_ENV" ]; then
        echo -e "  ${GREEN}✓ Key pair is VALID (private and public keys match)${NC}"
    else
        echo -e "  ${RED}✗ Key pair is INVALID (mismatch detected!)${NC}"
        echo "    Expected public key for current private: $EXPECTED_PUBLIC"
        echo "    Current public key in .env:             $PUBLIC_KEY_ENV"
        echo ""
        echo -e "  ${YELLOW}⚠ This explains the 'invalid connection' errors!${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Docker not available, skipping pair verification${NC}"
fi
echo ""

# 6. Рекомендации
echo -e "${CYAN}[6] Recommendations:${NC}"
if [ "$PRIVATE_KEY_FILE" != "$PRIVATE_KEY_ENV" ] || [ "$PRIVATE_KEY_ENV" != "$PRIVATE_KEY_CONFIG" ] || [ "$PUBLIC_KEY_FILE" != "$PUBLIC_KEY_ENV" ]; then
    echo -e "  ${YELLOW}→ Keys are out of sync. Run fix command:${NC}"
    echo "    sudo bash $VLESS_HOME/scripts/fix-keys-sync.sh"
elif [ "$EXPECTED_PUBLIC" != "$PUBLIC_KEY_ENV" ]; then
    echo -e "  ${YELLOW}→ Key pair mismatch detected. Regenerate keys:${NC}"
    echo "    sudo bash $VLESS_HOME/scripts/security/rotate-keys.sh"
else
    echo -e "  ${GREEN}✓ All keys are synchronized and valid${NC}"
fi

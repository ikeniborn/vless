#!/bin/bash

# Скрипт для синхронизации X25519 ключей между всеми местами хранения
# Использует ключи из config.json как источник истины

set -e

VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   X25519 Keys Synchronization Fix${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. Читаем текущий приватный ключ из config.json (источник истины)
if [ ! -f "$VLESS_HOME/config/config.json" ]; then
    echo -e "${RED}Error: config.json not found${NC}"
    exit 1
fi

PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$VLESS_HOME/config/config.json")

if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" == "null" ]; then
    echo -e "${RED}Error: Cannot read private key from config.json${NC}"
    exit 1
fi

echo -e "${CYAN}[1] Reading current private key from config.json...${NC}"
echo "  Private key: $PRIVATE_KEY"
echo ""

# 2. Вычисляем соответствующий публичный ключ
echo -e "${CYAN}[2] Computing corresponding public key...${NC}"
PUBLIC_KEY=$(docker run --rm teddysun/xray:24.11.30 xray x25519 -i "$PRIVATE_KEY" 2>/dev/null | grep -i "public" | awk '{print $NF}')

if [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}Error: Failed to compute public key${NC}"
    exit 1
fi

echo "  Public key:  $PUBLIC_KEY"
echo ""

# 3. Обновляем файлы ключей
echo -e "${CYAN}[3] Updating key files...${NC}"
mkdir -p "$VLESS_HOME/data/keys"
echo "$PRIVATE_KEY" > "$VLESS_HOME/data/keys/private.key"
echo "$PUBLIC_KEY" > "$VLESS_HOME/data/keys/public.key"
chmod 600 "$VLESS_HOME/data/keys/"*.key
echo -e "  ${GREEN}✓ Key files updated${NC}"
echo ""

# 4. Обновляем .env файл
echo -e "${CYAN}[4] Updating .env file...${NC}"
if [ -f "$VLESS_HOME/.env" ]; then
    # Создаем временный файл
    TMP_ENV=$(mktemp)

    # Копируем .env, обновляя ключи
    while IFS= read -r line; do
        if [[ $line =~ ^PRIVATE_KEY= ]]; then
            echo "PRIVATE_KEY=$PRIVATE_KEY"
        elif [[ $line =~ ^PUBLIC_KEY= ]]; then
            echo "PUBLIC_KEY=$PUBLIC_KEY"
        else
            echo "$line"
        fi
    done < "$VLESS_HOME/.env" > "$TMP_ENV"

    # Заменяем оригинальный файл
    mv "$TMP_ENV" "$VLESS_HOME/.env"
    chmod 600 "$VLESS_HOME/.env"

    echo -e "  ${GREEN}✓ .env file updated${NC}"
else
    echo -e "  ${RED}✗ .env file not found${NC}"
fi
echo ""

# 5. Перезапускаем Xray для применения изменений (если ключ в config.json уже правильный, то просто reload)
echo -e "${CYAN}[5] Restarting Xray service...${NC}"
cd "$VLESS_HOME"
docker-compose restart
sleep 2

if docker ps | grep -q "xray-server"; then
    echo -e "  ${GREEN}✓ Xray service restarted successfully${NC}"
else
    echo -e "  ${RED}✗ Failed to restart Xray service${NC}"
    exit 1
fi
echo ""

# 6. Верификация
echo -e "${CYAN}[6] Verification:${NC}"
PRIVATE_KEY_FILE=$(cat "$VLESS_HOME/data/keys/private.key")
PUBLIC_KEY_FILE=$(cat "$VLESS_HOME/data/keys/public.key")
PRIVATE_KEY_ENV=$(grep '^PRIVATE_KEY=' "$VLESS_HOME/.env" | cut -d'=' -f2)
PUBLIC_KEY_ENV=$(grep '^PUBLIC_KEY=' "$VLESS_HOME/.env" | cut -d'=' -f2)
PRIVATE_KEY_CONFIG=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$VLESS_HOME/config/config.json")

if [ "$PRIVATE_KEY_FILE" == "$PRIVATE_KEY_ENV" ] && [ "$PRIVATE_KEY_ENV" == "$PRIVATE_KEY_CONFIG" ] && [ "$PUBLIC_KEY_FILE" == "$PUBLIC_KEY_ENV" ]; then
    echo -e "  ${GREEN}✓ All keys are now synchronized${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Synchronization Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT: All clients must update their configuration!${NC}"
    echo ""
    echo "New public key: $PUBLIC_KEY"
    echo ""
    echo "To export updated client configuration, run:"
    echo "  vless-users export-config <username>"
    echo ""
else
    echo -e "  ${RED}✗ Synchronization failed${NC}"
    exit 1
fi

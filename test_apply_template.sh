#!/bin/bash

# Test script for apply_template function
set -e

# Source the functions
source scripts/lib/colors.sh
source scripts/lib/config.sh

# Create test directory
TEST_DIR="/tmp/vless_test_$$"
mkdir -p "$TEST_DIR"

# Cleanup on exit
trap "rm -rf $TEST_DIR" EXIT

echo "Testing apply_template function..."
echo "================================="

# Create test template
cat > "$TEST_DIR/test.tpl" << 'EOF'
{
  "key1": "{{KEY1}}",
  "key2": "{{KEY2}}",
  "key3": "{{KEY3}}",
  "private_key": "{{PRIVATE_KEY}}",
  "url": "{{URL}}",
  "path": "{{PATH}}"
}
EOF

# Test 1: Simple values
echo -n "Test 1 - Simple values: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test1.out" \
  "KEY1=simple" \
  "KEY2=value123" \
  "KEY3=test" \
  "PRIVATE_KEY=abc123" \
  "URL=https://example.com" \
  "PATH=/home/user"

if grep -q '"key1": "simple"' "$TEST_DIR/test1.out" && \
   grep -q '"key2": "value123"' "$TEST_DIR/test1.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test1.out"
fi

# Test 2: Values with forward slashes (common in base64 and paths)
echo -n "Test 2 - Values with forward slashes: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test2.out" \
  "KEY1=value/with/slashes" \
  "KEY2=base64/string/here" \
  "KEY3=normal" \
  "PRIVATE_KEY=2KQU7K/Y72fZRPRP3IMKX7/9nlHmwn0A" \
  "URL=https://example.com/path/to/resource" \
  "PATH=/opt/vless/data/keys"

if grep -q '"key1": "value/with/slashes"' "$TEST_DIR/test2.out" && \
   grep -q '"private_key": "2KQU7K/Y72fZRPRP3IMKX7/9nlHmwn0A"' "$TEST_DIR/test2.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test2.out"
fi

# Test 3: Values with backslashes
echo -n "Test 3 - Values with backslashes: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test3.out" \
  "KEY1=value\\with\\backslash" \
  "KEY2=C:\\Windows\\Path" \
  "KEY3=normal" \
  "PRIVATE_KEY=abc\\123" \
  "URL=https://example.com" \
  "PATH=/home/user"

if grep -q '"key1": "value\\\\with\\\\backslash"' "$TEST_DIR/test3.out" && \
   grep -q '"key2": "C:\\\\Windows\\\\Path"' "$TEST_DIR/test3.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test3.out"
fi

# Test 4: Values with ampersands
echo -n "Test 4 - Values with ampersands: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test4.out" \
  "KEY1=value&with&ampersand" \
  "KEY2=query=test&param=value" \
  "KEY3=normal" \
  "PRIVATE_KEY=abc&123" \
  "URL=https://example.com?a=1&b=2" \
  "PATH=/home/user"

if grep -q '"key1": "value&with&ampersand"' "$TEST_DIR/test4.out" && \
   grep -q '"url": "https://example.com?a=1&b=2"' "$TEST_DIR/test4.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test4.out"
fi

# Test 5: Real X25519 keys (base64 format)
echo -n "Test 5 - Real X25519 keys format: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test5.out" \
  "KEY1=normal" \
  "KEY2=test" \
  "KEY3=value" \
  "PRIVATE_KEY=oK7lNRZ/ccRVKxhCsMT+Ii3pw0RCi3/mhPu01EqSYnE=" \
  "URL=https://speed.cloudflare.com:443" \
  "PATH=/opt/vless/config"

if grep -q '"private_key": "oK7lNRZ/ccRVKxhCsMT+Ii3pw0RCi3/mhPu01EqSYnE="' "$TEST_DIR/test5.out" && \
   grep -q '"url": "https://speed.cloudflare.com:443"' "$TEST_DIR/test5.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test5.out"
fi

# Test 6: Values with regex special characters
echo -n "Test 6 - Values with regex special chars: "
apply_template "$TEST_DIR/test.tpl" "$TEST_DIR/test6.out" \
  "KEY1=value.*with.*regex" \
  "KEY2=[abc]test\$(pwd)" \
  "KEY3=normal^test\$end" \
  "PRIVATE_KEY=key+with+plus" \
  "URL=https://example.com" \
  "PATH=/home/user"

if grep -q '"key1": "value\.\*with\.\*regex"' "$TEST_DIR/test6.out" && \
   grep -q '"key2": "\[abc\]test\$(' "$TEST_DIR/test6.out"; then
  echo "PASS"
else
  echo "FAIL"
  cat "$TEST_DIR/test6.out"
fi

echo "================================="
echo "Test completed"
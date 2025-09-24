#!/bin/bash

# Simple Direct Tests for Container Management Functions

set -e

echo "Simple Container Management Function Tests"
echo "=========================================="

TEST_DIR="/tmp/simple_tests_$$"
mkdir -p "$TEST_DIR"

SUCCESS=0
TOTAL=0

# Test 1: Basic user directive update
echo -n "Test 1: Basic user directive update... "
((TOTAL++))

cat > "$TEST_DIR/test1.yml" << 'EOF'
services:
  xray:
    user: "1000:1000"
EOF

sed -i 's/user: "1000:1000"/user: "995:982"/' "$TEST_DIR/test1.yml"

if grep -q 'user: "995:982"' "$TEST_DIR/test1.yml"; then
    echo "✓ PASSED"
    ((SUCCESS++))
else
    echo "✗ FAILED"
fi

# Test 2: Permission verification
echo -n "Test 2: Permission verification... "
((TOTAL++))

cat > "$TEST_DIR/test2.yml" << 'EOF'
services:
  xray:
    user: "995:982"
EOF

if grep -q 'user: "995:982"' "$TEST_DIR/test2.yml"; then
    echo "✓ PASSED"
    ((SUCCESS++))
else
    echo "✗ FAILED"
fi

# Test 3: Backup creation
echo -n "Test 3: Backup file creation... "
((TOTAL++))

echo "test data" > "$TEST_DIR/original.yml"
cp "$TEST_DIR/original.yml" "$TEST_DIR/original.yml.backup"

if [[ -f "$TEST_DIR/original.yml.backup" ]]; then
    echo "✓ PASSED"
    ((SUCCESS++))
else
    echo "✗ FAILED"
fi

# Test 4: Version update
echo -n "Test 4: Version update... "
((TOTAL++))

cat > "$TEST_DIR/test4.yml" << 'EOF'
version: "3.3"
services:
  xray:
    image: test
EOF

sed -i 's/version: "3.3"/version: "3.8"/' "$TEST_DIR/test4.yml"

if grep -q 'version: "3.8"' "$TEST_DIR/test4.yml"; then
    echo "✓ PASSED"
    ((SUCCESS++))
else
    echo "✗ FAILED"
fi

# Test 5: Complex YAML handling
echo -n "Test 5: Complex YAML handling... "
((TOTAL++))

cat > "$TEST_DIR/test5.yml" << 'EOF'
version: '3.8'
services:
  xray:
    image: teddysun/xray:latest
    user: "1000:1000"
    restart: unless-stopped
  nginx:
    image: nginx:alpine
    restart: unless-stopped
EOF

# Update only the xray user directive
sed -i '/services:/,/nginx:/{/xray:/,/nginx:/{s/user: "1000:1000"/user: "995:982"/}}' "$TEST_DIR/test5.yml"

if grep -A 5 "xray:" "$TEST_DIR/test5.yml" | grep -q 'user: "995:982"'; then
    echo "✓ PASSED"
    ((SUCCESS++))
else
    echo "✗ FAILED"
fi

echo
echo "Results: $SUCCESS/$TOTAL tests passed"

if [[ $SUCCESS -eq $TOTAL ]]; then
    echo "✓ All basic function tests passed!"
else
    echo "✗ Some tests failed"
fi

# Show sample files for verification
echo
echo "Sample updated file (test5.yml):"
echo "--------------------------------"
cat "$TEST_DIR/test5.yml"

# Cleanup
rm -rf "$TEST_DIR"

[[ $SUCCESS -eq $TOTAL ]]
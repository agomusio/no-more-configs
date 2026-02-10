#!/usr/bin/env bash
# Tests the env generation script
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Testing env generation ==="

# Run in temp directory to avoid polluting repo
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp -r . "$TMPDIR"
cd "$TMPDIR"

# Remove any existing .env
rm -f .env

# Run generator with test inputs (email, name, password, org)
# Using printf for reliable newline handling
printf 'test@example.com\nTest User\ntestpass123\nTest Org\n' | ./scripts/generate-env.sh

# Verify .env exists
if [[ ! -f .env ]]; then
    echo "FAIL: .env not created"
    exit 1
fi
echo "✓ .env file created"

# Verify required vars are set (not CHANGE_ME)
for var in POSTGRES_PASSWORD ENCRYPTION_KEY LANGFUSE_INIT_PROJECT_SECRET_KEY; do
    val=$(grep "^$var=" .env | cut -d= -f2 || echo "")
    if [[ -z "$val" || "$val" == "CHANGE_ME" ]]; then
        echo "FAIL: $var not generated properly"
        exit 1
    fi
done
echo "✓ Required variables generated"

# Verify user-provided values
if ! grep -q "LANGFUSE_INIT_USER_EMAIL=test@example.com" .env; then
    echo "FAIL: User email not set correctly"
    cat .env | grep LANGFUSE_INIT_USER
    exit 1
fi
echo "✓ User-provided values set"

echo ""
echo "Environment generation test passed!"

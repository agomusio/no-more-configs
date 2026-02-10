#!/usr/bin/env bash
# Validates all scripts have correct syntax
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Validating shell scripts ==="
bash -n scripts/generate-env.sh
bash -n scripts/install-hook.sh
echo "✓ Shell scripts valid"

echo "=== Validating Python hook ==="
python3 -m py_compile hooks/langfuse_hook.py
echo "✓ Python hook valid"

echo "=== Validating docker-compose.yml ==="
docker compose config > /dev/null
echo "✓ Docker Compose valid"

echo ""
echo "All syntax checks passed!"

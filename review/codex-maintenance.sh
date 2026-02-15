#!/usr/bin/env bash
# Codex maintenance script — runs in cached containers after branch checkout.
# Tools are already installed from codex-setup.sh; this just verifies and refreshes.
set -euo pipefail

echo "=== Codex maintenance check ==="

# Verify tools are still present from setup
MISSING=0
for cmd in jq shellcheck hadolint yamllint node ruff python3; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "  MISSING: $cmd"
    MISSING=1
  fi
done

if [ "$MISSING" -eq 1 ]; then
  echo "Some tools are missing. Re-running setup..."
  bash review/codex-setup.sh
else
  echo "  All tools present."
fi

echo ""
echo "Setup complete."

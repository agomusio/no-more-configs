#!/bin/bash
set -euo pipefail

# save-secrets.sh
# Captures live credentials back into secrets.json for backup/persistence.
# Run this before rebuilding to preserve credentials across container rebuilds.

SECRETS_FILE="/workspace/secrets.json"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/node/.claude}"

# Start with existing secrets.json or empty template
if [ -f "$SECRETS_FILE" ]; then
    SECRETS=$(cat "$SECRETS_FILE")
else
    SECRETS='{"claude":{"credentials":{}},"langfuse":{"public_key":"","secret_key":""},"api_keys":{"openai":"","google":""}}'
fi

echo "[save-secrets] Capturing live credentials..."

# Capture Claude credentials
if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
    CREDS=$(cat "$CLAUDE_DIR/.credentials.json")
    SECRETS=$(echo "$SECRETS" | jq --argjson creds "$CREDS" '.claude.credentials = $creds')
    echo "[save-secrets] Claude credentials: captured"
else
    echo "[save-secrets] Claude credentials: not found (manual login required after rebuild)"
fi

# Capture Langfuse keys from settings
if [ -f "$CLAUDE_DIR/settings.local.json" ]; then
    LF_PK=$(jq -r '.env.LANGFUSE_PUBLIC_KEY // ""' "$CLAUDE_DIR/settings.local.json" 2>/dev/null || echo "")
    LF_SK=$(jq -r '.env.LANGFUSE_SECRET_KEY // ""' "$CLAUDE_DIR/settings.local.json" 2>/dev/null || echo "")
    if [ -n "$LF_PK" ]; then
        SECRETS=$(echo "$SECRETS" | jq --arg pk "$LF_PK" '.langfuse.public_key = $pk')
    fi
    if [ -n "$LF_SK" ]; then
        SECRETS=$(echo "$SECRETS" | jq --arg sk "$LF_SK" '.langfuse.secret_key = $sk')
    fi
    echo "[save-secrets] Langfuse keys: captured"
fi

# Capture API keys from environment
if [ -n "${OPENAI_API_KEY:-}" ]; then
    SECRETS=$(echo "$SECRETS" | jq --arg key "$OPENAI_API_KEY" '.api_keys.openai = $key')
    echo "[save-secrets] OpenAI API key: captured"
fi
if [ -n "${GOOGLE_API_KEY:-}" ]; then
    SECRETS=$(echo "$SECRETS" | jq --arg key "$GOOGLE_API_KEY" '.api_keys.google = $key')
    echo "[save-secrets] Google API key: captured"
fi

# Write back to secrets.json
echo "$SECRETS" | jq '.' > "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"
echo "[save-secrets] Saved to $SECRETS_FILE"

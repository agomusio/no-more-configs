#!/bin/bash
set -euo pipefail

# save-config.sh
# Captures Claude Code user preferences from ~/.claude.json into config.json.
# Only saves preferences that differ from their defaults (delta-only).
# Run this before rebuilding to preserve preferences across container rebuilds.

CONFIG_FILE="/workspace/config.json"
CLAUDE_JSON="${HOME}/.claude.json"

if [ ! -f "$CLAUDE_JSON" ]; then
    echo "[save-config] ~/.claude.json not found — nothing to save"
    exit 0
fi

if ! jq empty < "$CLAUDE_JSON" &>/dev/null; then
    echo "[save-config] ERROR: ~/.claude.json is not valid JSON"
    exit 1
fi

# Known preference keys and their defaults.
# Feature-flagged keys (no stable default) are always saved if present.
declare -A DEFAULTS=(
    ["autoCompactEnabled"]="true"
    ["autoInstallIdeExtension"]="true"
    ["autoConnectIde"]="false"
    ["respectGitignore"]="true"
    ["fileCheckpointingEnabled"]="true"
    ["terminalProgressBarEnabled"]="true"
    ["diffTool"]='"auto"'
    ["editorMode"]='"normal"'
    ["preferredNotifChannel"]='"auto"'
)

# Feature-flagged keys — saved whenever present (no stable default)
FEATURE_FLAGGED_KEYS=(
    "codeDiffFooterEnabled"
    "prStatusFooterEnabled"
    "claudeInChromeDefaultEnabled"
)

ALL_KEYS=("${!DEFAULTS[@]}" "${FEATURE_FLAGGED_KEYS[@]}")

echo "[save-config] Reading preferences from ~/.claude.json..."

DELTA='{}'
SAVED=()
SKIPPED=()

for key in "${ALL_KEYS[@]}"; do
    # Check if key exists (jq's // treats false as falsy, so we check has() separately)
    has_key=$(jq --arg k "$key" 'has($k)' "$CLAUDE_JSON")
    if [ "$has_key" != "true" ]; then
        continue
    fi

    # Read the live value
    live_value=$(jq --arg k "$key" '.[$k]' "$CLAUDE_JSON")

    # Check if this key has a known default
    if [ -n "${DEFAULTS[$key]+x}" ]; then
        default="${DEFAULTS[$key]}"
        if [ "$live_value" = "$default" ]; then
            SKIPPED+=("$key")
            continue
        fi
    fi

    # Value differs from default (or is feature-flagged) — include in delta
    DELTA=$(echo "$DELTA" | jq --arg k "$key" --argjson v "$live_value" '.[$k] = $v')
    SAVED+=("$key=$live_value")
done

# Start with existing config.json or empty object
if [ -f "$CONFIG_FILE" ]; then
    if ! jq empty < "$CONFIG_FILE" &>/dev/null; then
        echo "[save-config] ERROR: config.json is not valid JSON"
        exit 1
    fi
    CONFIG=$(cat "$CONFIG_FILE")
else
    CONFIG='{}'
fi

# Merge delta into config.json under claude_code key
CONFIG=$(echo "$CONFIG" | jq --argjson prefs "$DELTA" '.claude_code = $prefs')
echo "$CONFIG" | jq '.' > "$CONFIG_FILE"

# Summary
echo "[save-config] --- Summary ---"
if [ ${#SAVED[@]} -gt 0 ]; then
    echo "[save-config] Saved (non-default):"
    for entry in "${SAVED[@]}"; do
        echo "[save-config]   $entry"
    done
else
    echo "[save-config] No non-default preferences found"
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo "[save-config] Skipped (at default): ${SKIPPED[*]}"
fi
echo "[save-config] Written to $CONFIG_FILE under 'claude_code'"

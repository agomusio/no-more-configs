#!/bin/bash
set -euo pipefail

echo ">>> Initializing GSD (Get Shit Done) framework..."

GSD_COMMANDS_DIR="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/commands/gsd"

# Install GSD slash commands into Claude config if not already present
if [ -d "$GSD_COMMANDS_DIR" ] && [ "$(ls -A "$GSD_COMMANDS_DIR" 2>/dev/null)" ]; then
    echo "GSD commands already installed in $GSD_COMMANDS_DIR"
else
    echo "Installing GSD commands into Claude config..."
    npx get-shit-done-cc --claude --global
fi

# Report .planning status
if [ -d "/workspace/.planning" ]; then
    echo "GSD .planning directory already exists"
else
    echo "Note: Run /gsd:new-project in Claude Code to initialize project planning"
fi

echo ">>> GSD initialization complete."

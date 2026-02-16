#!/bin/bash
set -euo pipefail

# SECURITY NOTE: 666 gives all container processes full Docker daemon access.
# This is required for Docker-outside-of-Docker but grants significant host privileges.
# Claude Code with --dangerously-skip-permissions can execute arbitrary docker commands.
sudo chmod 666 /var/run/docker.sock

# Fix ownership on Docker volume mounts.
# Named volumes are created as root; the node user needs write access.
sudo chown -R node:node /home/node/.claude/projects 2>/dev/null || true
sudo chown -R node:node /commandhistory 2>/dev/null || true

# Git identity is restored from secrets.json by install-agent-config.sh.
# Run save-secrets after setting git config to persist across rebuilds.

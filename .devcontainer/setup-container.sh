#!/bin/bash
set -euo pipefail

# SECURITY NOTE: 666 gives all container processes full Docker daemon access.
# This is required for Docker-outside-of-Docker but grants significant host privileges.
# Claude Code with --dangerously-skip-permissions can execute arbitrary docker commands.
sudo chmod 666 /var/run/docker.sock

# Git identity is restored from secrets.json by install-agent-config.sh.
# Run save-secrets after setting git config to persist across rebuilds.

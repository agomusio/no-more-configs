#!/bin/bash
set -euo pipefail

# SECURITY NOTE: 666 gives all container processes full Docker daemon access.
# This is required for Docker-outside-of-Docker but grants significant host privileges.
# Claude Code with --dangerously-skip-permissions can execute arbitrary docker commands.
sudo chmod 666 /var/run/docker.sock

if [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
    git config --global user.email "$GIT_AUTHOR_EMAIL"
    git config --global user.name "${GIT_AUTHOR_NAME:-developer}"
    echo "✅ Git: Identity configured from environment"
else
    echo "⚠️ Git identity not set. Export GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL on your host."
fi

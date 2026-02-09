#!/bin/bash
# 1. Setup Git trust for all directories in this container
git config --global --add safe.directory '*'

# 2. Set line endings for WSL/Linux compatibility
git config --global core.autocrlf input

# 3. Ensure permissions for the Docker socket
sudo chmod 666 /var/run/docker.sock

# 4. Verify connectivity to Langfuse host
if ping -c 1 host.docker.internal &> /dev/null; then
    echo "✅ Host Reachable: host.docker.internal"
else
    echo "❌ Host Unreachable: Check init-firewall.sh"
fi
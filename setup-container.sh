#!/bin/bash



# 1. Setup Git trust for all directories in this container
git config --global --add safe.directory '*'

# 2. Set line endings for WSL/Linux compatibility
git config --global core.autocrlf input

# 3. Ensure permissions for the Docker socket, install Langfuse
sudo chmod 666 /var/run/docker.sock
python3 -m pip install langfuse --break-system-packages --quiet

# 4. Verify connectivity to Langfuse host
if ping -c 1 host.docker.internal &> /dev/null; then
    echo "✅ Host Reachable: host.docker.internal"
else
    echo "❌ Host Unreachable: Check init-firewall.sh"
fi

echo "🔍 Checking Langfuse on port 3052..."
if curl -s -o /dev/null -w "%{http_code}" http://host.docker.internal:3052/api/public/health | grep -q "200"; then
    echo "✅ Langfuse is reachable."
else
    echo "❌ ERROR: Langfuse unreachable on 3052."
    echo "👉 Run: cd /workspace/claudehome/langfuse-local && sudo docker compose up -d"
fi

# 5. Restore Git Identity
git config --global user.email "sam@theoryfarm.com"
git config --global user.name "agomusio"

git config --get user.email > /dev/null && echo "✅ Git: Identity is set" || echo "❌ Git: Identity MISSING"
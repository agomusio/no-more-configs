#!/bin/bash
set -euo pipefail

python3 -m pip install langfuse --break-system-packages --quiet

if ping -c 1 host.docker.internal >/dev/null 2>&1; then
    echo "✅ Host Reachable: host.docker.internal"
else
    echo "❌ Host Unreachable: Check init-firewall.sh"
fi

echo "🔍 Checking Langfuse on port 3052..."
if curl -s -o /dev/null -w "%{http_code}" http://host.docker.internal:3052/api/public/health | grep -q "200"; then
    echo "✅ Langfuse is reachable."
else
    echo "❌ ERROR: Langfuse unreachable on 3052."
    echo "👉 Run: cd ${LANGFUSE_STACK_DIR:-/workspace/infra} && sudo docker compose up -d"
fi

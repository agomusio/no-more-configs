#!/bin/sh
# MCP setup script - auto-generates .mcp.json and checks gateway health

gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"

# Generate .mcp.json at workspace root
cat <<EOF > /workspace/.mcp.json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "${gateway_url}/sse"
    }
  }
}
EOF

echo "✓ Generated /workspace/.mcp.json"

# Poll gateway health endpoint with retry logic
echo "Checking gateway health at ${gateway_url}/health..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  --retry 15 --retry-delay 2 --retry-max-time 30 --retry-connrefused \
  "${gateway_url}/health" 2>&1 || echo "000")

if [ "$http_code" = "200" ]; then
  echo "✓ Gateway is healthy"
else
  echo "⚠ Warning: Gateway not ready (HTTP ${http_code})"
  echo "  Start: cd /workspace/claudehome/langfuse-local && docker compose up -d docker-mcp-gateway"
fi

echo ""
echo "Config: /workspace/.mcp.json"
echo "Gateway: ${gateway_url}"
echo "Next: Restart Claude Code session to pick up MCP tools"
echo "To add servers: Edit langfuse-local/mcp/mcp.json, restart gateway, then re-run mcp-setup"

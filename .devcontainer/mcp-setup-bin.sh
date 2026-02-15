#!/bin/sh
# MCP setup script - regenerates .mcp.json from templates and checks gateway health
# Uses the same template system as install-agent-config.sh

gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
claude_dir="${HOME}/.claude"
workspace="${CLAUDE_WORKSPACE:-/workspace}"
config_file="${workspace}/config.json"
templates_dir="${workspace}/agent-config/mcp-templates"

mkdir -p "$claude_dir"

# Generate .mcp.json from enabled MCP templates (same logic as install-agent-config.sh)
MCP_JSON='{"mcpServers":{}}'
MCP_COUNT=0

if [ -f "$config_file" ]; then
    ENABLED_SERVERS=$(jq -r '.mcp_servers | to_entries[] | select(.value.enabled == true) | .key' "$config_file" 2>/dev/null || echo "")

    if [ -n "$ENABLED_SERVERS" ]; then
        for SERVER in $ENABLED_SERVERS; do
            TEMPLATE_FILE="${templates_dir}/${SERVER}.json"
            if [ -f "$TEMPLATE_FILE" ]; then
                HYDRATED=$(sed "s|{{MCP_GATEWAY_URL}}|$gateway_url|g" "$TEMPLATE_FILE")
                MCP_JSON=$(echo "$MCP_JSON" | jq --argjson server "{\"$SERVER\": $HYDRATED}" '.mcpServers += $server')
                MCP_COUNT=$((MCP_COUNT + 1))
            else
                echo "⚠ Template not found: $TEMPLATE_FILE"
            fi
        done
    fi
fi

# Fallback: if no servers were added, include mcp-gateway as default
if [ "$MCP_COUNT" -eq 0 ]; then
    MCP_JSON='{"mcpServers":{"mcp-gateway":{"type":"sse","url":"'"$gateway_url"'/sse"}}}'
    MCP_COUNT=1
fi

echo "$MCP_JSON" | jq '.' > "${claude_dir}/.mcp.json"
echo "✓ Generated ${claude_dir}/.mcp.json with $MCP_COUNT server(s)"

# Poll gateway health endpoint with retry logic
echo "Checking gateway health at ${gateway_url}/health..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  --retry 15 --retry-delay 2 --retry-max-time 30 --retry-connrefused \
  "${gateway_url}/health" 2>&1 || echo "000")

if [ "$http_code" = "200" ]; then
  echo "✓ Gateway is healthy"
else
  echo "⚠ Warning: Gateway not ready (HTTP ${http_code})"
  echo "  Start: cd ${LANGFUSE_STACK_DIR:-/workspace/infra} && docker compose up -d docker-mcp-gateway"
fi

echo ""
echo "Config: ${claude_dir}/.mcp.json"
echo "Gateway: ${gateway_url}"
echo "Next: Restart Claude Code session to pick up MCP tools"
echo "To add servers: Edit ${LANGFUSE_STACK_DIR:-/workspace/infra}/mcp/mcp.json, restart gateway, then re-run mcp-setup"

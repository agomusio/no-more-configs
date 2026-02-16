#!/bin/bash
# Shared MCP helper functions for install-agent-config.sh and mcp-setup-bin.sh

# Convert a JSON MCP server definition to TOML format for Codex config.toml
# Usage: json_mcp_to_toml "server-name" "$json_config"
# Output: TOML block written to stdout
json_mcp_to_toml() {
    local name="$1"
    local json="$2"
    local server_type
    server_type=$(echo "$json" | jq -r '.type // "stdio"' 2>/dev/null)

    echo ""
    echo "[mcp_servers.${name}]"

    if [ "$server_type" = "sse" ] || [ "$server_type" = "streamable-http" ]; then
        # URL-based server
        local url
        url=$(echo "$json" | jq -r '.url // ""' 2>/dev/null)
        echo "url = \"$url\""
    else
        # stdio server — combine command + args into single command array
        local cmd
        cmd=$(echo "$json" | jq -r '.command // ""' 2>/dev/null)
        local has_args
        has_args=$(echo "$json" | jq -r '.args | length // 0' 2>/dev/null)

        if [ "$has_args" -gt 0 ] 2>/dev/null; then
            # Build command array: ["command", "arg1", "arg2", ...]
            local args_toml
            args_toml=$(echo "$json" | jq -r '[.command] + .args | map("\"" + . + "\"") | join(", ")' 2>/dev/null)
            echo "command = [$args_toml]"
        else
            echo "command = \"$cmd\""
        fi
    fi

    # Per-server env vars (if present in JSON as .env object)
    local env_keys
    env_keys=$(echo "$json" | jq -r '.env // {} | keys[]' 2>/dev/null)
    if [ -n "$env_keys" ]; then
        echo ""
        echo "[mcp_servers.${name}.env]"
        echo "$json" | jq -r '.env | to_entries[] | "\(.key) = \"\(.value)\""' 2>/dev/null
    fi
}

# Check if a server targets a specific agent
# Usage: server_targets_agent "codex" "$server_config_from_config_json"
# Returns 0 (true) if the agent is in the targets list, 1 (false) otherwise
# Default when targets is not set: both agents (claude + codex)
server_targets_agent() {
    local agent="$1"
    local server_config="$2"

    local targets
    targets=$(echo "$server_config" | jq -r '.targets // ["claude", "codex"] | .[]' 2>/dev/null)

    echo "$targets" | grep -qx "$agent"
}

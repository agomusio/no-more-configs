# MCP Servers

Add servers to `mcp.json`, restart the gateway, then run `mcp-setup` in the devcontainer.

## Active Servers

- **filesystem** — File operations in /workspace (pre-configured)

## Example Servers

Copy any entry below into the `mcpServers` object in `mcp.json`.

### GitHub (via official MCP server)

```json
"github": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
  }
}
```

Requires: Set GITHUB_TOKEN in `langfuse-local/.env`

### PostgreSQL (query Langfuse database)

```json
"postgres": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres"],
  "env": {}
}
```

Uses the existing Langfuse PostgreSQL instance.

### Brave Search (web search from Claude Code)

```json
"brave-search": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-brave-search"],
  "env": {
    "BRAVE_API_KEY": "${BRAVE_API_KEY}"
  }
}
```

Requires: Set BRAVE_API_KEY in `langfuse-local/.env` (get from https://brave.com/search/api/)

## Workflow

1. Copy a server entry into `mcp.json` under `mcpServers`
2. Add any required env vars to `langfuse-local/.env`
3. Restart: `cd /workspace/claudehome/langfuse-local && docker compose restart docker-mcp-gateway`
4. Re-run: `mcp-setup`
5. Restart Claude Code session

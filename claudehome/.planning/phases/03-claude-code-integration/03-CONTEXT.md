# Phase 3: Claude Code Integration - Context

**Gathered:** 2026-02-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Claude Code auto-connects to the MCP gateway on devcontainer startup with zero manual configuration. A shell alias generates `.mcp.json` in the workspace root, waits for the gateway to be healthy, and Claude Code sessions have MCP tools available immediately. Adding new MCP servers is a config edit + alias re-run.

</domain>

<decisions>
## Implementation Decisions

### Configuration method
- `.mcp.json` in workspace root (per-project, Claude Code auto-discovers)
- Generated dynamically on startup, NOT a static committed file
- Triggered via shell alias defined in shell profile (.zshrc)
- Gateway URL sourced from `MCP_GATEWAY_URL` environment variable (set in devcontainer config)
- Single gateway SSE endpoint in `.mcp.json` — gateway handles multiplexing to individual servers internally

### Startup resilience
- Block until gateway is ready (poll health endpoint), up to 30 second timeout
- If gateway doesn't come up within 30s: warn and continue (Claude Code starts without MCP)
- Health check method: Claude's discretion (HTTP health endpoint vs TCP port check)

### Multi-server workflow
- Adding a server: edit gateway's `mcp.json`, restart gateway container, re-run the same shell alias
- `.mcp.json` points to single gateway endpoint — no per-server client config changes needed
- After re-running alias: update config + prompt user to restart Claude Code session to pick up changes

### Documentation approach
- Inline in `mcp.json` as commented-out examples — right where the user edits
- Moderate depth: example entry + 2-3 common MCP servers pre-configured but commented out
- Claude picks which example servers are most relevant to this devcontainer ecosystem
- No troubleshooting section — keep it lean, happy path only

### Claude's Discretion
- Health check method (HTTP endpoint vs TCP port check)
- Which common MCP servers to include as commented-out examples (2-3 relevant to this devcontainer)
- Exact alias name and implementation details
- Config generation script structure

</decisions>

<specifics>
## Specific Ideas

- Shell alias approach: user wants a simple command they can run anytime (initial setup or refresh after adding servers)
- Same command for initial generation and refresh — no separate workflows
- User prefers alias + shell profile over postStartCommand or dedicated init scripts

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-claude-code-integration*
*Context gathered: 2026-02-13*

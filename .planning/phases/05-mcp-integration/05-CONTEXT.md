# Phase 5: MCP Integration - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Plugin MCP servers declared in plugin.json get registered in `~/.claude/.mcp.json`, persist across container rebuilds, and have secret token placeholders hydrated from secrets.json. The install script owns .mcp.json generation. This phase does NOT cover adding new MCP servers or changing plugin discovery (Phase 4 handles that).

</domain>

<decisions>
## Implementation Decisions

### Secret sourcing
- Secrets come from `secrets.json` only — no environment variable fallback
- Secret keys are namespaced by plugin name using nested objects in secrets.json
  - Plugin declares `SECRET_KEY` in plugin.json → looked up as `secrets.json["langfuse-tracing"]["SECRET_KEY"]`
  - secrets.json structure: `{ "plugin-name": { "KEY": "value" } }`

### Missing secret behavior
- Register the MCP server with raw placeholder tokens left in place (server will fail at runtime but entry exists)
- Print inline warning during install: e.g., `⚠ langfuse-tracing: missing SECRET_KEY`
- No summary section for missing secrets — inline warning is sufficient

### Persistence strategy
- Install script has full ownership of `.mcp.json` — regenerates from scratch on every rebuild
- Plugin MCP entries are tagged with source metadata (e.g., `"_source": "plugin:langfuse-tracing"`) for traceability
- Disabled plugins have their MCP servers actively removed — install script scans for tagged entries from disabled plugins and removes them
- Since install owns .mcp.json fully, mcp-setup's postStartCommand must merge into what install already wrote (not overwrite)

### Claude's Discretion
- Token placeholder format ({{TOKEN}} vs ${TOKEN} — pick what avoids conflicts with existing patterns)
- Whether to distinguish "secret key missing" vs "secret key present but empty" — pick what's practical
- Whether to skip MCP server entirely when ALL secrets are missing vs same behavior as partial — pick the sensible approach
- Exact coordination mechanism between install script and mcp-setup postStartCommand
- MCP config structure within plugin.json

</decisions>

<specifics>
## Specific Ideas

- Full ownership model for .mcp.json mirrors how settings.json is handled — clean regeneration, not incremental patching
- Tagging enables the active removal behavior for disabled plugins without needing to track state separately

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-mcp-integration*
*Context gathered: 2026-02-15*

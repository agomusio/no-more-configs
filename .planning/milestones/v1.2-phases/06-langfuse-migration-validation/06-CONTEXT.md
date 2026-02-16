# Phase 6: Langfuse Migration & Validation - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate the Langfuse tracing hook from hardcoded settings template entries to a self-registering plugin under `agent-config/plugins/langfuse-tracing/`. Add validation warnings and install summaries so plugin issues are easy to debug. The plugin system infrastructure (discovery, copying, merging) already exists from Phases 4-5 — this phase uses it.

</domain>

<decisions>
## Implementation Decisions

### Migration approach
- Clean break — remove Langfuse from settings.json.template entirely, plugin system is the only path
- Delete the old hardcoded hook file (agent-config/hooks/langfuse_hook.py) after migration — no dead files
- Plugin manifest (plugin.json) should be minimal — only declare what Langfuse actually uses (hooks, env, MCP), not a showcase of all possible fields

### Warning behavior
- Warnings appear inline as encountered AND are recapped in the final summary
- Invalid plugin.json = error — skip the entire plugin, warn, continue with other plugins
- All other issues (missing scripts, overwrites, empty env) are warnings, never fatal to the install

### Install summary
- Full detail — show per-plugin breakdown of what was registered
- Compact list format: `langfuse-tracing: 1 hook, 2 env, 1 MCP`
- Integrate plugin summary into the existing install summary block (not a separate section)
- Include a dedicated warnings recap section at the end with full warning messages repeated

### Validation strictness
- Missing hook script file → warn and skip the entire plugin (not just the bad hook)
- Env vars declared in plugin.json but empty after merge → warn the user
- Invalid plugin.json → friendly error message first, then raw JSON parse error on next line
- File overwrite between plugins → Claude's discretion on resolution strategy

### Claude's Discretion
- Warning prefix format (e.g., [WARN], plugin: WARNING, etc.) — match existing install script style
- Warning visual styling (colors, symbols) — match existing output conventions
- Hook script location within plugin directory structure
- File overwrite conflict resolution strategy (first wins vs last wins)

</decisions>

<specifics>
## Specific Ideas

- Langfuse plugin is the reference implementation — keep it clean and minimal so it's easy to copy for new plugins
- The install script already has a summary with component counts from Phase 4 — extend that, don't create parallel output

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-langfuse-migration-validation*
*Context gathered: 2026-02-15*

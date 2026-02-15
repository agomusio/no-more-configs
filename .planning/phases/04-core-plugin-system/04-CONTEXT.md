# Phase 4: Core Plugin System - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Plugin discovery, validation, file copying, and hook/env registration with GSD protection. Users can add a plugin directory to `agent-config/plugins/`, rebuild the container, and have their plugin's skills, hooks, commands, agents, and environment variables integrated into Claude Code and Codex CLI. Standalone commands from `agent-config/commands/` are also supported. MCP server registration is Phase 5. Enhanced validation/warnings are Phase 7.

</domain>

<decisions>
## Implementation Decisions

### Spec Authority
- `.planning/nmc-plugin-spec.md` is a **strong guide** — follow its decisions (manifest format, directory layout, install order, config.json control) but write a fresh implementation that fits existing codebase patterns
- Spec decisions are current — no changes since it was written
- Do NOT copy the spec's bash pseudocode verbatim — understand the intent, then implement to match existing `install-agent-config.sh` style and patterns
- Downstream agents (researcher, planner) should read BOTH this CONTEXT.md and the spec for full technical depth

### Install Feedback
- **Per-plugin detail**: each plugin logs what it installed with names listed (hooks, skills, env vars, commands, agents) up to a reasonable count to avoid log bloat
- **Skipped plugins**: use info-style line matching installed style — `"[install] Plugin 'noisy-plugin': skipped (disabled)"` — not a warning, just a different status
- **Final recap block**: end of plugin installation includes a summary snapshot — plugin count (installed vs skipped), hook registrations, command count, any warnings
- Match the existing install script's `[install]` prefix pattern for consistency

### File Conflict Policy
- **Non-GSD file overwrites**: overwrite + log — `"Plugin 'x': overwrote skills/my-skill (was standalone)"` — basic awareness without blocking
- **GSD protection**: hardcoded check for `commands/gsd/` directory and `agents/gsd-*.md` prefix — no configurable protected paths list
- **GSD conflict**: error-level message + skip — `"ERROR: Plugin 'x' attempted to overwrite GSD-protected file agents/gsd-executor.md — skipping"` — treat as plugin misconfiguration
- **Protection scope**: GSD-only — standalone commands and plugin commands can overwrite each other freely (GSD installs last via npx and is the only protected namespace)

### Edge Case Behavior
- **Env var conflicts between plugins**: error on conflict — if two plugins declare the same env var, warn and skip the duplicate (first alphabetically wins, second is skipped with warning). `config.json` overrides always take precedence over any plugin env vars.
- **Multiple plugins on same hook event**: all fire, alphabetical order by plugin directory name — no warning needed, this is expected behavior
- **Missing/invalid plugin.json**: skip everything — no files copied, no registrations, nothing installs. Clean skip with info message.
- **Plugin name mismatch**: `plugin.json` name field must match directory name — mismatch is an error, plugin is skipped with warning

### Cross-Agent Skill Installation
- Skills are copied to **both** `~/.claude/skills/` and `~/.codex/skills/` — same directory structure, same files, single source
- Applies to standalone skills (`agent-config/skills/`) AND plugin skills (`plugins/*/skills/`)
- Enable Codex skill discovery: add `skills = true` under `[features]` in generated Codex `config.toml`
- **Only skills are cross-agent** — hooks, commands, agents, and MCP servers remain Claude-only (Codex has no equivalent lifecycle hook system)
- Install feedback reflects the dual destination: `"[install] Skills: 4 skill(s) → Claude + Codex"`

### Claude's Discretion
- Install script architecture (functions, helpers, inline code)
- Exact log message formatting beyond the patterns described above
- JSON merging implementation for hook accumulation in settings.local.json
- How to detect GSD files (prefix matching, path checking, etc.)
- Temp file handling during JSON merging operations
- Order of operations within plugin installation loop

</decisions>

<specifics>
## Specific Ideas

- Env var conflict policy is a **departure from the spec** — spec says "last alphabetically wins" but user wants "error on conflict, first wins". Update mental model accordingly.
- Plugin name must match directory name is also **stricter than spec** — spec doesn't mention this validation. Add it.
- Install output should feel like the existing `[install]` prefixed lines — same style, just more detail for plugins
- The recap block at the end should give a quick "at a glance" view of what the plugin system did during this rebuild
- Cross-agent skill installation is a **post-spec addition** — not in `nmc-plugin-spec.md` but decided during context gathering. Codex CLI now supports the same SKILL.md convention.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-core-plugin-system*
*Context gathered: 2026-02-15*

# Roadmap: Claude Code Sandbox

## Completed Milestones

- **v1: Container-Local Config Refactor** (2026-02-14) — 3 phases, 6 plans, 40 requirements. [Archive](.planning/milestones/v1-ROADMAP.md)

## Current Milestone: v1.2 Plugins & Proper Skills/Commands

**Goal:** Add a plugin system with self-registering hooks/env/MCP, standalone commands support, and migrate langfuse to plugin as proof-of-concept.

### Overview

This milestone adds a plugin system that extends the container's configuration-as-code foundation. Plugins are self-registering bundles (skills, hooks, commands, agents, MCP servers) discovered from `agent-config/plugins/` with manifests declaring their registrations. The install script orchestrates discovery, validation, file copying with GSD protection, and accumulation/merging of hook, environment, and MCP registrations into Claude Code settings. The Langfuse tracing hook migrates to a plugin as proof-of-concept, validating the system end-to-end. Enhanced validation provides warnings and summaries for better debugging.

### Phases

**Phase Numbering:**
- Integer phases (4, 5, 6, 7): Planned milestone work (continuing from v1 phases 1-3)
- Decimal phases (4.1, 4.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 4: Core Plugin System** - Plugin discovery, file copying, hook/env registration with GSD protection
- [ ] **Phase 5: MCP Integration** - Plugin MCP server registration and persistence fix
- [ ] **Phase 6: Langfuse Migration** - Migrate Langfuse tracing to plugin system
- [ ] **Phase 7: Enhanced Validation** - Warnings, conflict detection, installation summaries

### Phase Details

#### Phase 4: Core Plugin System
**Goal**: Plugins are discovered, validated, and their files/registrations integrated into the container
**Depends on**: Nothing (v1 complete)
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05, PLUG-06, COPY-01, COPY-02, COPY-03, COPY-04, COPY-05, COPY-06, HOOK-01, HOOK-02, HOOK-03, HOOK-04, ENV-01, ENV-02, ENV-03, CMD-01, CMD-02, CMD-03
**Success Criteria** (what must be TRUE):
  1. User can add a plugin directory to `agent-config/plugins/` and rebuild container to activate it
  2. Plugin skills, hooks, commands, and agents are copied to `~/.claude/` without overwriting GSD files
  3. Plugin hook registrations accumulate in settings.local.json allowing multiple plugins to register the same event
  4. Plugin environment variables from manifests merge correctly with config.json overrides taking precedence
  5. Standalone commands from `agent-config/commands/` are available in Claude Code
  6. User can disable a plugin via `config.json` and its files/registrations are fully skipped
**Plans**: 3 plans in 3 waves

Plans:
- [ ] 04-01-PLAN.md — Standalone commands copy + cross-agent skills + Codex config
- [ ] 04-02-PLAN.md — Plugin discovery, validation, and file copying with GSD protection
- [ ] 04-03-PLAN.md — Hook/env registration merging + install summary update

#### Phase 5: MCP Integration
**Goal**: Plugin MCP servers persist across container rebuilds and token placeholders are hydrated
**Depends on**: Phase 4
**Requirements**: MCP-01, MCP-02, MCP-03, MCP-04
**Success Criteria** (what must be TRUE):
  1. Plugin MCP servers declared in plugin.json appear in `~/.claude/.mcp.json` after container rebuild
  2. Placeholder tokens like `{{LANGFUSE_SECRET_KEY}}` in plugin MCP configs are hydrated from secrets.json
  3. Plugin MCP servers persist when mcp-setup runs in postStartCommand (no double-write overwrite)
  4. Missing secret tokens produce warnings without crashing install script
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

#### Phase 6: Langfuse Migration
**Goal**: Langfuse tracing runs as a plugin instead of hardcoded in settings template
**Depends on**: Phase 4
**Requirements**: LANG-01, LANG-02, LANG-03, LANG-04, LANG-05
**Success Criteria** (what must be TRUE):
  1. Langfuse hook exists in `agent-config/plugins/langfuse-tracing/` with plugin.json manifest
  2. Langfuse hook registration is removed from settings.json.template
  3. Langfuse tracing fires on Stop event identically to pre-migration behavior
  4. User can disable Langfuse via config.json plugins section without manual file edits
**Plans**: TBD

Plans:
- [ ] 06-01: TBD

#### Phase 7: Enhanced Validation
**Goal**: Install script provides clear warnings and summaries for debugging plugin issues
**Depends on**: Phase 4
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04
**Success Criteria** (what must be TRUE):
  1. Install script warns when plugin hook references non-existent script file
  2. Install script warns when plugin file would overwrite another plugin's file
  3. Install summary displays plugin count, command count, and any warnings encountered
  4. Invalid plugin.json produces clear error with plugin name and JSON parse failure reason
**Plans**: TBD

Plans:
- [ ] 07-01: TBD

### Progress

**Execution Order:**
Phases execute in numeric order: 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Core Plugin System | 0/3 | Planned | - |
| 5. MCP Integration | 0/? | Not started | - |
| 6. Langfuse Migration | 0/? | Not started | - |
| 7. Enhanced Validation | 0/? | Not started | - |

---
*Roadmap created: 2026-02-15 for milestone v1.2*

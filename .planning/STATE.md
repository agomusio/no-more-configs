# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-14)

**Core value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.
**Current focus:** Phase 1 complete — human verification pending, then Phase 2

## Current Position

Phase: 1 of 3 (Configuration Consolidation)
Plan: 2 of 2
Status: Complete — human verification pending (6 runtime tests)
Last activity: 2026-02-14 — Phase 1 executed (2/2 plans), verification 11/11 automated checks passed

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 1.5 min
- Total execution time: 0.05 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Configuration Consolidation | 2 | 3 min | 1.5 min |

**Recent Trend:**
- Last completed: 01-02 (1 min)
- Trend: Phase 1 complete (2 plans, 3 min total)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Dissolve claudehome/ rather than rename — contents serve different purposes (skills, infra, planning)
- Two master files (config.json + secrets.json) — clean separation of committed config vs gitignored secrets
- agent-config/ with template hydration — version-controlled source that generates runtime config
- Core-first scope (defer multi-model) — stabilize infrastructure before adding CLI agent complexity
- Work from Windows host — can't safely refactor container from inside itself

**From 01-01 execution:**
- Nested object structure for config.json with firewall, langfuse, agent, vscode, mcp_servers top-level keys
- Separated credentials into secrets.json with claude.credentials, langfuse keys, api_keys structure
- Placeholder tokens use {{UPPER_SNAKE_CASE}} format for template hydration
- Empty git_scan_paths array means auto-detect from gitprojects/ .git directories

**From 01-02 execution:**
- Natural idempotency (no state markers) — script uses mkdir -p, regenerates files, safe to run multiple times
- Graceful degradation — script provides defaults when config.json missing, empty placeholders when secrets.json missing
- JSON validation before processing — prevents cryptic jq errors from malformed files
- Prefix all output with [install] — enables grep filtering in build logs

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 1 (Configuration Consolidation):**
- RESOLVED: Credential persistence — secrets.json schema implemented, install script restores credentials
- RESOLVED: GSD framework compatibility — install script installs to ~/.claude/commands/ and ~/.claude/agents/
- RESOLVED: Idempotency markers — used natural idempotency (mkdir -p, regeneration) instead of state markers

**Phase 2 (Directory Dissolution):**
- Commit ordering — must use add-wire-delete sequence to keep container buildable at every commit
- Path translation — WSL2 path issues require testing with environment variable indirection
- GSD upward traversal — framework needs to find .planning/ when sessions launch from gitprojects/ subdirectories

**Phase 3 (Runtime Generation):**
- Template hydration — must handle missing placeholders gracefully (warnings, not failures)
- Build continuity — bind mount removal is point of no return, everything must work before this step
- Plugin compatibility — Claude Code plugins bundle their own `.mcp.json` (loaded independently of workspace `.mcp.json`). Firewall generation (GEN-01) must account for domains that plugin MCP servers need. Plugin stdio MCP servers need binaries in the Dockerfile. Plugins installed at runtime need persistence across rebuilds (postCreateCommand or version-controlled plugin dirs).

## Session Continuity

Last session: 2026-02-14 (phase execution + verification)
Stopped at: Phase 1 complete — 11/11 automated checks passed, 6 human verification items pending
Resume file: None

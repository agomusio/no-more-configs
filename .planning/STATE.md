# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-14)

**Core value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.
**Current focus:** Phase 2 complete — ready for Phase 3 (Runtime Generation & Cut-Over)

## Current Position

Phase: 2 of 3 (Directory Dissolution)
Plan: 2 of 2
Status: Complete — verified (15/15 checks passed)
Last activity: 2026-02-14 — Phase 2 executed and verified

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 3.5 min
- Total execution time: 0.23 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Configuration Consolidation | 2 | 3 min | 1.5 min |
| 2. Directory Dissolution | 2 | 11 min | 5.5 min |

**Recent Trend:**
- Last completed: 02-02 (6 min)
- Trend: Phase 2 complete (2 plans, 11 min total)

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

**From 02-01 execution:**
- git mv preserves history for langfuse-local/ → infra/ rename (20 files)
- Custom skills (devcontainer, gitprojects) copied to agent-config/skills/ via cp (new files)
- Verification scripts moved alongside langfuse scripts in infra/scripts/
- LANGFUSE_STACK_DIR and CLAUDE_WORKSPACE set as both ENV directives and shell exports

**From 02-02 execution:**
- All 4 custom skills (aa-cloudflare, aa-fullstack, devcontainer, gitprojects) live in agent-config/skills/
- aa-cloudflare and aa-fullstack were initially misclassified as vendor skills — restored from git history
- Scripts use ${LANGFUSE_STACK_DIR:-/workspace/infra} pattern with fallback for sh compatibility
- README.md Project Structure tree and Key Paths table completely overhauled

### Pending Todos

None.

### Blockers/Concerns

**Phase 1 (Configuration Consolidation):**
- RESOLVED: Credential persistence — secrets.json schema implemented, install script restores credentials
- RESOLVED: GSD framework compatibility — install script installs to ~/.claude/commands/ and ~/.claude/agents/
- RESOLVED: Idempotency markers — used natural idempotency (mkdir -p, regeneration) instead of state markers

**Phase 2 (Directory Dissolution):**
- RESOLVED: Commit ordering — used add-wire-delete sequence (6 commits, build continuity maintained)
- RESOLVED: Path translation — environment variables (LANGFUSE_STACK_DIR, CLAUDE_WORKSPACE) with fallback defaults
- RESOLVED: GSD upward traversal — .planning/ at workspace root, aliases no longer force working directory
- RESOLVED: Skill classification — aa-cloudflare and aa-fullstack are custom forked skills, not vendor packages

**Phase 3 (Runtime Generation):**
- Template hydration — must handle missing placeholders gracefully (warnings, not failures)
- Build continuity — bind mount removal is point of no return, everything must work before this step
- Plugin compatibility — Claude Code plugins bundle their own `.mcp.json` (loaded independently of workspace `.mcp.json`). Firewall generation (GEN-01) must account for domains that plugin MCP servers need. Plugin stdio MCP servers need binaries in the Dockerfile. Plugins installed at runtime need persistence across rebuilds (postCreateCommand or version-controlled plugin dirs).

## Session Continuity

Last session: 2026-02-14 (phase 2 execution + verification)
Stopped at: Phase 2 complete — 15/15 verification checks passed, ready for Phase 3
Resume file: None

# Milestone v1 Roadmap Archive: Claude Code Sandbox Refactor

**Completed:** 2026-02-14
**Duration:** ~22 min across 6 plans
**Stats:** 27 commits, 186 files changed, 4166 insertions(+), 6174 deletions(-)

## Overview

Eliminated configuration scatter and host bind mount dependencies by consolidating all settings into two master files (config.json for structure, secrets.json for credentials), dissolving the claudehome/ directory into purpose-named locations, and implementing template-based config generation. The result is a container that builds cleanly from Windows with all agent configuration generated from version-controlled source files.

## Key Accomplishments

1. **Two-file config system** — config.json (committed settings) + secrets.json (gitignored credentials) as single sources of truth for all sandbox behavior
2. **Template hydration pipeline** — agent-config/ with {{PLACEHOLDER}} tokens hydrated by install-agent-config.sh at build time
3. **claudehome/ dissolved** — skills to agent-config/skills/, planning to .planning/, infrastructure to infra/, verification scripts to infra/scripts/
4. **Bind mount removed** — container-local ~/.claude/ populated from agent-config/ at build time, no host filesystem dependency
5. **Credential round-trip** — secrets.json -> install (restore) -> live container -> save-secrets -> secrets.json
6. **Config generation** — firewall domains, VS Code settings, MCP configs, and agent settings all generated from config.json

## Phases

### Phase 1: Configuration Consolidation (2 plans, ~3 min)

**Goal:** User can define all sandbox behavior in two master files with idempotent install script.

**Requirements:** CFG-01 through CFG-05, AGT-01, AGT-02, AGT-06, AGT-07, INS-01 through INS-06 (15 total)

Plans:
- 01-01: Created config.json, secrets.example.json, config.example.json, agent-config/ with templates (2 commits)
- 01-02: Created install-agent-config.sh (177 lines) with JSON validation, template hydration, GSD install, graceful degradation (2 commits)

### Phase 2: Directory Dissolution (2 plans, ~11 min)

**Goal:** claudehome/ directory eliminated with all contents redistributed to purpose-named locations.

**Requirements:** DIR-01 through DIR-08, CTR-02, CTR-03, CTR-04 (11 total)

Plans:
- 02-01: Redistributed claudehome/ contents — langfuse-local/ to infra/, skills to agent-config/skills/, updated Dockerfile env vars and aliases (3 commits)
- 02-02: Updated all path references in scripts and docs, deleted claudehome/ (3 commits)

### Phase 3: Runtime Generation & Cut-Over (2 plans, ~8 min)

**Goal:** All runtime configs generated from templates, bind mount removed, credential persistence.

**Requirements:** AGT-03 through AGT-05, CRD-01 through CRD-04, GEN-01 through GEN-06, CTR-01 (14 total)

Plans:
- 03-01: Removed bind mount (isolated commit), asset copy pipeline for skills/hooks/commands, placeholder detection (3 commits)
- 03-02: Firewall domain generation, VS Code settings generation, save-secrets helper, API key exports, generate-env.sh writeback (4 commits)

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Dissolve claudehome/ rather than rename | Contents serve different purposes — skills, infra, planning belong in separate locations |
| Two master files (config.json + secrets.json) | Clean separation of committed config vs gitignored secrets |
| agent-config/ with template hydration | Version-controlled source of truth that generates runtime config |
| Core-first scope (defer multi-model) | Stabilize infrastructure before adding CLI agent complexity |
| Natural idempotency (no state markers) | mkdir -p and file regeneration is simpler and more reliable |
| Bind mount removal as isolated first commit | Riskiest change gets easy revert path |

## Tech Debt Carried Forward

1. **mcp.json overwrite** (Low) — mcp-setup in postStartCommand overwrites install-agent-config.sh output. No impact with single MCP server, but blocks multi-server configs.
2. **Plugin compatibility** (Deferred) — Plugin MCP server domains need firewall whitelist entries via config.json extra_domains.

---

*Archived: 2026-02-15*

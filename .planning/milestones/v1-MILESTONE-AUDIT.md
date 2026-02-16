# Milestone v1 Audit Report

**Audited:** 2026-02-15
**Status:** passed
**Milestone:** v1 — Claude Code Sandbox Refactor

## Scope

**Core value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.

**Phases:** 3 phases, 6 plans, 27 commits
**Stats:** 186 files changed, 4166 insertions(+), 6174 deletions(-)

| Phase | Plans | Verification | Score |
|-------|-------|-------------|-------|
| 1. Configuration Consolidation | 2/2 | 11/11 checks | human_needed → confirmed |
| 2. Directory Dissolution | 2/2 | 15/15 checks | passed |
| 3. Runtime Generation & Cut-Over | 2/2 | 7/7 checks | passed |

## Phase Verification Summary

All 3 phases have VERIFICATION.md files confirming goal achievement:

- **Phase 1** (11/11): config.json + secrets.json schema, agent-config/ directory, install-agent-config.sh with idempotent config hydration, GSD framework installation
- **Phase 2** (15/15): claudehome/ dissolved, 4 skills + infra moved, all path references updated, env vars for LANGFUSE_STACK_DIR and CLAUDE_WORKSPACE, aliases cleaned
- **Phase 3** (7/7): Bind mount removed, firewall domain generation (27 core + extras), VS Code settings generation, credential round-trip (install → save-secrets → install), API key exports, placeholder detection

## Human Verification

User confirmed via manual testing:
- Container rebuilds from Windows with no bind mount
- Claude Code authenticates from secrets.json credentials
- save-secrets captures live credentials back to secrets.json
- Deleting secrets.json correctly causes auth loss (graceful degradation)
- Build logs show: 29 domains, 78-79 IPs resolved, 4 skills, 1 hook, GSD: 28 commands + 11 agents
- Langfuse reachable, MCP gateway healthy

## Cross-Phase Integration

Spawned integration checker: 6/6 integration points PASS.

| # | Integration Point | Status |
|---|---|---|
| 1 | Phase 1 → Phase 2: config.json + secrets.json at repo root | PASS |
| 2 | Phase 2 → Phase 3: agent-config/ + infra/ references in install script | PASS |
| 3 | E2E config flow: config.json → install → firewall-domains.conf → refresh → init-firewall | PASS |
| 4 | E2E credential flow: secrets.json → install → runtime → save-secrets → secrets.json | PASS |
| 5 | E2E agent setup flow: agent-config/{skills,hooks} → install → ~/.claude/{skills,hooks} | PASS |
| 6 | Devcontainer lifecycle: postCreateCommand → postStartCommand ordering | PASS |

## Requirements Coverage (40/40)

All 40 v1 requirements satisfied across 3 phases:

### Config Consolidation (5/5)
| Req | Description | Status |
|-----|-------------|--------|
| CFG-01 | Single config.json for non-secret settings | SATISFIED |
| CFG-02 | Single secrets.json for credentials | SATISFIED |
| CFG-03 | config.json ships with sensible defaults | SATISFIED |
| CFG-04 | secrets.example.json with placeholder schema | SATISFIED |
| CFG-05 | Config validation with clear error messages | SATISFIED |

### Agent Config Source (7/7)
| Req | Description | Status |
|-----|-------------|--------|
| AGT-01 | agent-config/ as version-controlled source | SATISFIED |
| AGT-02 | settings.json template with {{PLACEHOLDER}} tokens | SATISFIED |
| AGT-03 | Skills copied to ~/.claude/skills/ | SATISFIED |
| AGT-04 | Hooks copied to ~/.claude/hooks/ | SATISFIED |
| AGT-05 | Commands copied non-destructively | SATISFIED |
| AGT-06 | GSD framework: 28 commands + 11 agents | SATISFIED |
| AGT-07 | ~/.claude/agents/ directory created | SATISFIED |

### Install Script (6/6)
| Req | Description | Status |
|-----|-------------|--------|
| INS-01 | Single orchestrated install flow | SATISFIED |
| INS-02 | Idempotent (safe to re-run) | SATISFIED |
| INS-03 | Works with missing config.json | SATISFIED |
| INS-04 | Works with missing secrets.json | SATISFIED |
| INS-05 | Works with both files missing | SATISFIED |
| INS-06 | Prints install summary | SATISFIED |

### Directory Restructure (8/8)
| Req | Description | Status |
|-----|-------------|--------|
| DIR-01 | claudehome/ dissolved | SATISFIED |
| DIR-02 | Skills in agent-config/skills/ | SATISFIED |
| DIR-03 | Planning at workspace root | SATISFIED |
| DIR-04 | Infrastructure at infra/ | SATISFIED |
| DIR-05 | Verification scripts at infra/scripts/ | SATISFIED |
| DIR-06 | All path references updated | SATISFIED |
| DIR-07 | settings.local.json deleted | SATISFIED |
| DIR-08 | claudehome/ removed | SATISFIED |

### Container Independence (4/4)
| Req | Description | Status |
|-----|-------------|--------|
| CTR-01 | ~/.claude bind mount removed | SATISFIED |
| CTR-02 | Aliases updated (no cd prefix) | SATISFIED |
| CTR-03 | Sessions launch from any directory | SATISFIED |
| CTR-04 | GSD finds .planning/ from gitprojects/ | SATISFIED |

### Credential Persistence (4/4)
| Req | Description | Status |
|-----|-------------|--------|
| CRD-01 | save-secrets helper captures live credentials | SATISFIED |
| CRD-02 | Install restores credentials from secrets.json | SATISFIED |
| CRD-03 | Shell exports OPENAI_API_KEY and GOOGLE_API_KEY | SATISFIED |
| CRD-04 | generate-env.sh writes Langfuse keys to secrets.json | SATISFIED |

### Config Generation (6/6)
| Req | Description | Status |
|-----|-------------|--------|
| GEN-01 | firewall-domains.conf generated from config.json | SATISFIED |
| GEN-02 | API domains (openai, googleapis) always present | SATISFIED |
| GEN-03 | .vscode/settings.json generated | SATISFIED |
| GEN-04 | MCP configs generated with hydrated tokens | SATISFIED |
| GEN-05 | settings.json hydrated from template | SATISFIED |
| GEN-06 | Unresolved placeholders replaced + warned | SATISFIED |

**Coverage: 40/40 requirements SATISFIED (100%)**

## Tech Debt / Deferred Items

### 1. .mcp.json Overwrite Conflict (Low severity)

`mcp-setup` in postStartCommand unconditionally overwrites the `.mcp.json` that `install-agent-config.sh` generates from config.json MCP templates. Currently produces identical output (only `mcp-gateway` configured), but adding a second MCP server to config.json would be silently overwritten on every container start.

**Fix when needed:** Either remove .mcp.json generation from mcp-setup (health check only) or have mcp-setup read from the already-generated file.

### 2. agent-config/commands/ Not Yet Created (Negligible)

The install script has wiring for custom commands (`cp -rn`), but `agent-config/commands/` doesn't exist yet. Guarded by conditional — no error. GSD commands install via npm package separately.

### 3. Plugin Compatibility (Deferred to v2)

Users can add plugin MCP server domains to config.json `extra_domains`, but plugin-specific MCP configuration is not yet templated. Deferred per Phase 3 planning.

## Conclusion

**Status: PASSED**

All 40 requirements satisfied. All 3 phase verifications passed (33/33 total checks). All 6 cross-phase integration points verified. User confirmed end-to-end behavior via manual testing. Tech debt is minimal (1 low-severity latent conflict, 2 negligible items).

The milestone achieves its core value: all container configuration is generated from source files checked into the repo with no host bind mounts, no scattered settings, and no manual file placement.

---

*Audited: 2026-02-15*
*Auditor: Claude (gsd-audit-milestone)*

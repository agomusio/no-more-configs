# Roadmap: Claude Code Sandbox Refactor

## Overview

This refactor eliminates configuration scatter and host bind mount dependencies by consolidating all settings into two master files (config.json for structure, secrets.json for credentials), dissolving the claudehome/ directory into purpose-named locations, and implementing template-based config generation. The result is a container that builds cleanly from Windows with all agent configuration generated from version-controlled source files.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Configuration Consolidation** - Establish config foundation with secrets isolation
- [ ] **Phase 2: Directory Dissolution** - Restructure directories and resolve path dependencies
- [ ] **Phase 3: Runtime Generation & Cut-Over** - Remove bind mount (first, isolated), then implement full config automation

## Phase Details

### Phase 1: Configuration Consolidation
**Goal**: User can define all sandbox behavior in two master files — config.json for settings, secrets.json for credentials — with idempotent install script that hydrates templates.

**Depends on**: Nothing (first phase)

**Requirements**: CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, AGT-01, AGT-02, AGT-06, AGT-07, INS-01, INS-02, INS-03, INS-04, INS-05, INS-06

**Success Criteria** (what must be TRUE):
  1. User can edit config.json to change all non-secret settings (firewall domains, projects, MCP servers, agent defaults) and see changes applied on rebuild
  2. User can edit secrets.json to update credentials (Claude auth, API keys) without touching any other files
  3. Container rebuilds successfully with missing config.json (sensible defaults + warning printed)
  4. Container rebuilds successfully with missing secrets.json (placeholders + warning listing missing values)
  5. install-agent-config.sh runs multiple times without creating duplicates or failing
  6. GSD framework installs with 29 commands in ~/.claude/commands/gsd/ and 11 agents in ~/.claude/agents/

**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md — Create config files (config.json, secrets.example.json, config.example.json) and agent-config/ directory with settings and MCP templates
- [x] 01-02-PLAN.md — Create install-agent-config.sh script and wire into devcontainer lifecycle

### Phase 2: Directory Dissolution
**Goal**: claudehome/ directory eliminated with all contents redistributed to purpose-named locations, all path references use environment variables, and sessions can launch from any directory.

**Depends on**: Phase 1

**Requirements**: DIR-01, DIR-02, DIR-03, DIR-04, DIR-05, DIR-06, DIR-07, DIR-08, CTR-02, CTR-03, CTR-04

**Success Criteria** (what must be TRUE):
  1. claudehome/ directory no longer exists — all files redistributed to agent-config/, /workspace/.planning/, /workspace/infra/, infra/scripts/
  2. User can launch agent sessions from gitprojects/ subdirectories and GSD finds .planning/ at workspace root
  3. All scripts and aliases reference directories via environment variables (LANGFUSE_STACK_DIR, CLAUDE_WORKSPACE) not hard-coded paths
  4. Aliases no longer prefix commands with "cd /workspace/claudehome &&"
  5. docker-compose, setup scripts, mcp-setup, and README reference infra/ (not langfuse-local/)

**Plans**: TBD

Plans:
- [ ] 02-01: [To be planned]

### Phase 3: Runtime Generation & Cut-Over
**Goal**: All runtime configs (firewall domains, VS Code settings, MCP gateway, agent settings) generated from templates, bind mount removed, validation catches errors pre-startup.

**Depends on**: Phase 2

**Requirements**: AGT-03, AGT-04, AGT-05, CRD-01, CRD-02, CRD-03, CRD-04, GEN-01, GEN-02, GEN-03, GEN-04, GEN-05, GEN-06, CTR-01

**Critical ordering:** The bind mount removal (CTR-01) is the riskiest single change. It MUST be:
- The first commit in this phase (isolated, easy to revert)
- Tested with a full container rebuild immediately after
- Only then proceed to config generation and automation

**Success Criteria** (what must be TRUE):
  1. Container rebuilds from Windows with no ~/.claude bind mount and Claude Code authenticates successfully (CTR-01 — test FIRST)
  2. firewall-domains.conf generated from config.json includes core domains (Anthropic, GitHub, npm) plus extra_domains, with API domains (openai.com, googleapis.com) always present
  3. .vscode/settings.json generated from config.json with git.scanRepositories matching projects list
  4. MCP configs generated with {{PLACEHOLDER}} tokens hydrated from secrets.json
  5. ~/.claude/settings.json hydrated from agent-config/settings.json template with values from both config files
  6. save-secrets helper captures live credentials back into secrets.json for backup
  7. Skills and hooks load correctly from container-local ~/.claude/ paths

**Plans**: TBD

Plans:
- [ ] 03-01: [To be planned]

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Configuration Consolidation | 2/2 | ✓ Complete | 2026-02-14 |
| 2. Directory Dissolution | 0/TBD | Not started | - |
| 3. Runtime Generation & Cut-Over | 0/TBD | Not started | - |

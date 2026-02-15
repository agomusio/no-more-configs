# Requirements Archive: v1 — Claude Code Sandbox Refactor

**Defined:** 2026-02-14
**Completed:** 2026-02-14
**Core Value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.

## v1 Requirements (40/40 satisfied)

### Config Consolidation (5/5)

- [x] **CFG-01**: User can define all non-secret sandbox settings in a single `config.json` at repo root
- [x] **CFG-02**: User can define all credentials in a single gitignored `secrets.json` at repo root
- [x] **CFG-03**: `config.json` ships as an example template with sensible defaults
- [x] **CFG-04**: `secrets.example.json` committed with placeholder values showing required schema
- [x] **CFG-05**: Config validation runs pre-startup and catches malformed JSON with clear error messages

### Agent Config Source (7/7)

- [x] **AGT-01**: `agent-config/` directory exists as version-controlled source of truth
- [x] **AGT-02**: `agent-config/settings.json` is a template with `{{PLACEHOLDER}}` tokens
- [x] **AGT-03**: Skills in `agent-config/skills/` are copied to `~/.claude/skills/`
- [x] **AGT-04**: Hooks in `agent-config/hooks/` are copied to `~/.claude/hooks/`
- [x] **AGT-05**: Commands in `agent-config/commands/` are copied non-destructively
- [x] **AGT-06**: GSD framework installs correctly (28 commands + 11 agents)
- [x] **AGT-07**: Install script creates `~/.claude/agents/` directory

### Install Script (6/6)

- [x] **INS-01**: `install-agent-config.sh` reads both files and generates all runtime config
- [x] **INS-02**: Install script is idempotent
- [x] **INS-03**: Container works with missing `config.json`
- [x] **INS-04**: Container works with missing `secrets.json`
- [x] **INS-05**: Container works with both files missing
- [x] **INS-06**: Install script prints summary of installed components

### Directory Restructure (8/8)

- [x] **DIR-01**: `claudehome/` directory dissolved
- [x] **DIR-02**: Skills moved to `agent-config/skills/`
- [x] **DIR-03**: Planning state moved to `/workspace/.planning/`
- [x] **DIR-04**: Infrastructure stack moved to `/workspace/infra/`
- [x] **DIR-05**: Verification scripts moved to `infra/scripts/`
- [x] **DIR-06**: All path references updated
- [x] **DIR-07**: `claudehome/.claude/settings.local.json` deleted
- [x] **DIR-08**: `claudehome/` directory removed

### Container Independence (4/4)

- [x] **CTR-01**: `~/.claude` bind mount removed from `devcontainer.json`
- [x] **CTR-02**: Dockerfile aliases updated (no cd prefix)
- [x] **CTR-03**: Agent sessions can launch from any directory
- [x] **CTR-04**: GSD framework finds `.planning/` from gitprojects/ subdirectories

### Credential Persistence (4/4)

- [x] **CRD-01**: `save-secrets` helper captures live credentials into `secrets.json`
- [x] **CRD-02**: `install-agent-config.sh` restores credentials on rebuild
- [x] **CRD-03**: Shell profile exports `OPENAI_API_KEY` and `GOOGLE_API_KEY`
- [x] **CRD-04**: `generate-env.sh` writes Langfuse keys back into `secrets.json`

### Config Generation (6/6)

- [x] **GEN-01**: `firewall-domains.conf` generated from `config.json`
- [x] **GEN-02**: `api.openai.com` and `generativelanguage.googleapis.com` always present
- [x] **GEN-03**: `.vscode/settings.json` generated from `config.json`
- [x] **GEN-04**: MCP configs generated with hydrated tokens
- [x] **GEN-05**: `~/.claude/settings.json` hydrated from template
- [x] **GEN-06**: Unresolved `{{PLACEHOLDER}}` tokens replaced with empty strings + warning

## Traceability

| Phase | Requirements | Count |
|-------|-------------|-------|
| Phase 1: Configuration Consolidation | CFG-01..05, AGT-01, AGT-02, AGT-06, AGT-07, INS-01..06 | 15 |
| Phase 2: Directory Dissolution | DIR-01..08, CTR-02, CTR-03, CTR-04 | 11 |
| Phase 3: Runtime Generation | AGT-03..05, CTR-01, CRD-01..04, GEN-01..06 | 14 |
| **Total** | | **40** |

## Out of Scope (deferred to v2)

- Multi-model orchestration (Codex CLI, Gemini CLI)
- Multi-model skill and aliases
- Plugin compatibility beyond firewall domain additions
- Docker Compose service changes, MCP gateway logic changes, firewall mechanism changes

---

*Archived: 2026-02-15*

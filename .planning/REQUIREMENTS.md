# Requirements: Claude Code Sandbox Refactor

**Defined:** 2026-02-14
**Core Value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.

## v1 Requirements

Requirements for the core infrastructure refactor. Each maps to roadmap phases.

### Config Consolidation

- [ ] **CFG-01**: User can define all non-secret sandbox settings in a single `config.json` at repo root (firewall domains, projects, MCP servers, Langfuse endpoint, agent defaults, VS Code settings)
- [ ] **CFG-02**: User can define all credentials in a single gitignored `secrets.json` at repo root (Claude auth, Langfuse keys, future API keys)
- [ ] **CFG-03**: `config.json` ships as an example template (`config.json` committed with sensible defaults) so users cloning the repo get a working starting point
- [ ] **CFG-04**: `secrets.example.json` committed with placeholder values showing required schema for all credential types
- [ ] **CFG-05**: Config validation runs pre-startup and catches malformed JSON or missing secrets with clear error messages (warnings, not failures)

### Agent Config Source

- [ ] **AGT-01**: `agent-config/` directory exists as version-controlled source of truth for skills, hooks, commands, and settings template
- [ ] **AGT-02**: `agent-config/settings.json` is a template with `{{PLACEHOLDER}}` tokens that get hydrated from `config.json` and `secrets.json`
- [ ] **AGT-03**: Skills in `agent-config/skills/` are copied to `~/.claude/skills/` preserving directory structure
- [ ] **AGT-04**: Hooks in `agent-config/hooks/` are copied to `~/.claude/hooks/`
- [ ] **AGT-05**: Commands in `agent-config/commands/` are copied to `~/.claude/commands/` non-destructively (GSD commands not overwritten)
- [ ] **AGT-06**: GSD framework installs correctly — 29 commands in `~/.claude/commands/gsd/` and 11 agents in `~/.claude/agents/gsd-*.md`
- [ ] **AGT-07**: Install script creates `~/.claude/agents/` directory for GSD's 11 agent files

### Install Script

- [ ] **INS-01**: `install-agent-config.sh` reads `config.json` + `secrets.json` and generates all runtime config in a single orchestrated flow
- [ ] **INS-02**: Install script is idempotent — safe to re-run without creating duplicates, corrupting state, or failing
- [ ] **INS-03**: Container works with missing `config.json` (uses sensible defaults, prints warning)
- [ ] **INS-04**: Container works with missing `secrets.json` (uses placeholders, prints warning listing what's missing)
- [ ] **INS-05**: Container works with both files missing (defaults + placeholders + warnings, no failures)
- [ ] **INS-06**: Install script prints summary of what was installed, which agents are available, and any warnings

### Directory Restructure

- [ ] **DIR-01**: `claudehome/` directory dissolved — all contents redistributed to purpose-named locations
- [ ] **DIR-02**: Skills moved from `claudehome/.claude/skills/` to `agent-config/skills/`
- [ ] **DIR-03**: Planning state moved from `claudehome/.planning/` to `/workspace/.planning/`
- [ ] **DIR-04**: Infrastructure stack moved from `claudehome/langfuse-local/` to `/workspace/infra/`
- [ ] **DIR-05**: Verification scripts moved from `claudehome/scripts/` to `infra/scripts/`
- [ ] **DIR-06**: All path references updated — docker-compose, setup scripts, mcp-setup, aliases, README
- [ ] **DIR-07**: `claudehome/.claude/settings.local.json` deleted (no longer needed)
- [ ] **DIR-08**: `claudehome/` directory removed after all contents redistributed

### Container Independence

- [ ] **CTR-01**: `~/.claude` bind mount removed from `devcontainer.json`
- [ ] **CTR-02**: Dockerfile aliases updated — no `cd /workspace/claudehome &&` prefix
- [ ] **CTR-03**: Agent sessions can launch from any directory (primarily `gitprojects/` subdirectories)
- [ ] **CTR-04**: GSD framework finds `.planning/` when sessions launch from `gitprojects/` subdirectories

### Credential Persistence

- [ ] **CRD-01**: `save-secrets` helper script captures live credentials (Claude auth, Langfuse keys, API keys) into `secrets.json`
- [ ] **CRD-02**: `install-agent-config.sh` restores Claude Code auth tokens from `secrets.json` on container rebuild
- [ ] **CRD-03**: Shell profile exports `OPENAI_API_KEY` and `GOOGLE_API_KEY` from `secrets.json` (ready for v2 agents)
- [ ] **CRD-04**: `infra/scripts/generate-env.sh` writes generated Langfuse keys back into `secrets.json` (single source of truth)

### Config Generation

- [ ] **GEN-01**: `firewall-domains.conf` generated from `config.json` — core domains (Anthropic, GitHub, npm, etc.) always included, plus `config.firewall.extra_domains`
- [ ] **GEN-02**: `api.openai.com` and `generativelanguage.googleapis.com` added to core firewall domains (always present, not user-configured)
- [ ] **GEN-03**: `.vscode/settings.json` generated from `config.json` — `git.scanRepositories` from `projects` and `vscode.git_scan_paths`
- [ ] **GEN-04**: MCP configs generated from `config.json` → `mcp_servers` with `{{PLACEHOLDER}}` tokens hydrated from `secrets.json`
- [ ] **GEN-05**: `~/.claude/settings.json` hydrated from `agent-config/settings.json` template with values from both `config.json` and `secrets.json`
- [ ] **GEN-06**: Unresolved `{{PLACEHOLDER}}` tokens replaced with empty strings and warning printed listing which placeholders were unresolved

## v2 Requirements

Deferred to multi-model milestone. Tracked but not in current roadmap.

### Multi-Model Integration

- **MLT-01**: Codex CLI installed globally and available from any directory
- **MLT-02**: Gemini CLI installed globally and available from any directory
- **MLT-03**: `agent-config/skills/multi-model/SKILL.md` teaches orchestration patterns
- **MLT-04**: `agent-config/codex/instructions.md` provides default Codex instructions
- **MLT-05**: `agent-config/gemini/settings.json` provides default Gemini config
- **MLT-06**: Aliases for Codex (`codexr`, `codexf`) and Gemini (`geminir`)
- **MLT-07**: CLI auth investigation completed and documented (Codex config location, Gemini auth method, exact API domains)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| GUI config editor | Over-engineering — JSON files are sufficient for developer users |
| Automatic secret detection/rotation | Complexity without value for single-user sandbox |
| Per-project secrets.json | Security risk — one secrets file at workspace root is safer |
| Nested devcontainers | Architectural complexity with no clear benefit |
| Secret manager integration (Vault, AWS) | File-based secrets sufficient for single-user dev sandbox |
| Agent-specific session routing | v2+ concern — not needed until multiple agents active |
| Firewall domain auto-refresh | CDN IP rotation is a rare edge case, manual update sufficient |
| Docker Compose service changes | Only directory location moves; service configs unchanged |
| MCP gateway logic changes | Only path references change |
| Firewall mechanism changes | Only domain list updates |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CFG-01 | — | Pending |
| CFG-02 | — | Pending |
| CFG-03 | — | Pending |
| CFG-04 | — | Pending |
| CFG-05 | — | Pending |
| AGT-01 | — | Pending |
| AGT-02 | — | Pending |
| AGT-03 | — | Pending |
| AGT-04 | — | Pending |
| AGT-05 | — | Pending |
| AGT-06 | — | Pending |
| AGT-07 | — | Pending |
| INS-01 | — | Pending |
| INS-02 | — | Pending |
| INS-03 | — | Pending |
| INS-04 | — | Pending |
| INS-05 | — | Pending |
| INS-06 | — | Pending |
| DIR-01 | — | Pending |
| DIR-02 | — | Pending |
| DIR-03 | — | Pending |
| DIR-04 | — | Pending |
| DIR-05 | — | Pending |
| DIR-06 | — | Pending |
| DIR-07 | — | Pending |
| DIR-08 | — | Pending |
| CTR-01 | — | Pending |
| CTR-02 | — | Pending |
| CTR-03 | — | Pending |
| CTR-04 | — | Pending |
| CRD-01 | — | Pending |
| CRD-02 | — | Pending |
| CRD-03 | — | Pending |
| CRD-04 | — | Pending |
| GEN-01 | — | Pending |
| GEN-02 | — | Pending |
| GEN-03 | — | Pending |
| GEN-04 | — | Pending |
| GEN-05 | — | Pending |
| GEN-06 | — | Pending |

**Coverage:**
- v1 requirements: 40 total
- Mapped to phases: 0
- Unmapped: 40 (pending roadmap creation)

---
*Requirements defined: 2026-02-14*
*Last updated: 2026-02-14 after initial definition*

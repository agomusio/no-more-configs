# Claude Code Sandbox — Container-Local Config Refactor

## What This Is

A major refactor of the Claude Code Sandbox devcontainer that eliminates the `~/.claude` host bind mount, consolidates scattered configuration into two master files (`config.json` for settings, `secrets.json` for credentials), and dissolves the `claudehome/` directory by redistributing its contents to purpose-named locations. The result is a container where all agent config is generated fresh at build time from version-controlled source files.

## Core Value

All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement. `config.json` + `secrets.json` in, working container out.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Centralized `config.json` as single source of truth for all non-secret settings (firewall domains, projects, MCP servers, Langfuse endpoint, agent defaults, VS Code settings)
- [ ] Centralized `secrets.json` (gitignored) as single source of truth for all credentials (Claude auth, Langfuse keys, future API keys)
- [ ] `agent-config/` directory as version-controlled source for skills, hooks, commands, and settings template with `{{placeholder}}` hydration
- [ ] `install-agent-config.sh` orchestration script that reads `config.json` + `secrets.json` and generates all runtime config (firewall domains, VS Code settings, MCP configs, Claude settings, hooks, skills)
- [ ] Dissolve `claudehome/` — skills to `agent-config/skills/`, planning state to `/workspace/.planning/`, infra stack to `/workspace/infra/`, verification scripts to `infra/scripts/`
- [ ] Rename `langfuse-local/` to `infra/` — update all path references in docker-compose, scripts, mcp-setup, README
- [ ] Remove `~/.claude` bind mount from `devcontainer.json`
- [ ] Update Dockerfile aliases to remove `cd /workspace/claudehome &&` prefix
- [ ] `save-secrets` helper that captures live credentials back into `secrets.json`
- [ ] `secrets.example.json` and `config.example.json` committed as schema references
- [ ] GSD commands and agents install correctly into container-local `~/.claude/`
- [ ] Container rebuilds cleanly from Windows with all config generated
- [ ] Claude Code authenticates and works after rebuild (auth restored from `secrets.json`)
- [ ] Hooks and skills load correctly from container-local paths
- [ ] Sessions can launch from any directory (primarily `gitprojects/` subdirectories)

### Out of Scope

- Multi-model orchestration (Codex CLI, Gemini CLI) — deferred to v2 milestone after infrastructure is solid
- Multi-model skill (`agent-config/skills/multi-model/SKILL.md`) — depends on v2 CLI integration
- Codex/Gemini aliases (`codexr`, `codexf`, `geminir`) — v2
- OpenAI/Google API domains in firewall — v2 (no agents to use them yet)
- Changes to Langfuse stack internals (Docker Compose services, ports, volumes) — only the directory location moves
- Changes to the firewall mechanism itself — only domain list updates
- Changes to MCP gateway logic — only path references change

## Context

- The sandbox is a VS Code devcontainer running on Windows 11 via WSL2/Docker Desktop
- Currently bind-mounts `~/.claude` from the Windows host, which causes path mismatches (Linux paths referencing `/home/node/` don't resolve on Windows and vice versa — as seen with the hooks error this session)
- Sessions currently forced to launch from `/workspace/claudehome/` via aliases
- Config is scattered across `devcontainer.json`, `firewall-domains.conf`, `.vscode/settings.json`, `mcp.json`, multiple scripts, and a host-mounted `settings.json`
- GSD (Get Shit Done) is the workflow framework — 29 slash commands and 11 specialized agents installed via `npx get-shit-done-cc --claude --global`
- Infrastructure stack: Langfuse (tracing), MCP gateway, Postgres, ClickHouse, Redis, MinIO
- All work is executed from the Windows host side (not from inside the container being modified)
- A research phase will investigate Codex CLI and Gemini CLI tooling to inform the v2 multi-model milestone
- Claude Code plugins (public beta) are a separate extension system — plugins bundle skills, hooks, agents, and MCP servers in directories with `.claude-plugin/plugin.json` manifests. They coexist with standalone `.claude/` config (our approach). Plugin MCP servers load from the plugin directory's own `.mcp.json`, independent of the workspace-level `.mcp.json` our install script generates. Three considerations for later phases: (1) plugin MCP servers connecting to external services need those domains in the firewall whitelist, (2) plugin MCP servers using stdio need their binaries available in the container (Dockerfile), (3) plugins installed at runtime need a persistence strategy across container rebuilds (e.g., install in postCreateCommand or store plugin dirs in version control)

## Constraints

- **Working environment**: All changes staged from Windows host — cannot safely modify a running devcontainer from inside itself
- **Build continuity**: Commit sequence must keep the devcontainer buildable at every step (add-then-wire-then-delete)
- **Idempotent scripts**: `install-agent-config.sh` must be safe to run multiple times
- **GSD compatibility**: GSD must find `.planning/` when sessions launch from `gitprojects/` subdirectories
- **No secrets in git**: `secrets.json` must be gitignored; `config.json` must contain zero sensitive values
- **Claude Code `latest`**: Do not pin version — always install latest

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Dissolve claudehome/ rather than rename | Contents serve different purposes — skills, infra, planning state belong in separate locations | — Pending |
| Two master files (config.json + secrets.json) | Clean separation of committed config vs gitignored secrets; single place to edit each | — Pending |
| agent-config/ with template hydration | Version-controlled source of truth that generates runtime config; users edit one directory | — Pending |
| Core-first scope (defer multi-model) | Stabilize infrastructure before adding complexity of three CLI agents | — Pending |
| Research CLI tooling as separate phase | Need real investigation of Codex/Gemini auth and config before building integration | — Pending |
| Work from Windows host | Can't safely refactor the container from inside it | — Pending |

---
*Last updated: 2026-02-14 after initialization*

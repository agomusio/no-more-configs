# Claude Code Sandbox

## Current State

**Shipped:** v1 — Container-Local Config Refactor (2026-02-14)

The sandbox is a VS Code devcontainer running on Windows 11 via WSL2/Docker Desktop. All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.

### How It Works

1. **Two master files** at repo root: `config.json` (committed settings) + `secrets.json` (gitignored credentials)
2. **`agent-config/`** directory holds version-controlled templates (settings, MCP, skills, hooks)
3. **`install-agent-config.sh`** reads both files, hydrates templates, copies assets to `~/.claude/`, generates firewall domains and VS Code settings
4. **`save-secrets`** helper captures live credentials back into `secrets.json` for persistence across rebuilds

### Key Paths

| Path | Purpose |
|------|---------|
| `config.json` | Non-secret settings (firewall, langfuse, agent, vscode, mcp) |
| `secrets.json` | Credentials (Claude auth, Langfuse keys, API keys) — gitignored |
| `agent-config/` | Templates, skills, hooks — version-controlled source of truth |
| `.devcontainer/` | Dockerfile, install scripts, firewall, devcontainer.json |
| `infra/` | Langfuse stack (docker-compose, scripts, hooks, MCP config) |
| `.planning/` | GSD planning state (roadmap, phases, verification) |
| `gitprojects/` | Cloned project repositories |

### Infrastructure

- **Langfuse** tracing at `infra/` (Postgres, ClickHouse, Redis, MinIO)
- **MCP gateway** for tool access
- **Firewall** with domain whitelist (27 core + extras from config.json)
- **GSD framework** — 28 commands + 11 agents for structured development workflows

### Tech Debt

1. `.mcp.json` overwrite — mcp-setup in postStartCommand overwrites install-agent-config.sh output (low severity, only affects multi-server configs)
2. Plugin compatibility — plugin MCP server domains need manual addition to config.json extra_domains

## Current Milestone: v1.2 Plugins & Proper Skills/Commands

**Goal:** Add a plugin system with self-registering hooks/env/MCP, standalone commands support, and migrate langfuse to plugin as proof-of-concept.

**Target features:**
- Plugin system — `agent-config/plugins/` with `plugin.json` manifests, hook/env/MCP registration, config.json control
- Standalone commands — `agent-config/commands/*.md` copied to `~/.claude/commands/`
- Langfuse plugin migration — Move langfuse hook from standalone to `plugins/langfuse-tracing/`
- Install script integration — Plugin install, merge hooks/env/MCP into settings, correct ordering

### Active Requirements

See `.planning/REQUIREMENTS.md` for full scoped requirements.

## Context

- VS Code devcontainer on Windows 11 via WSL2/Docker Desktop
- GSD (Get Shit Done) workflow framework for structured development
- All work executed from Windows host side
- Claude Code plugins (public beta) coexist with standalone .claude/ config

<details>
<summary>v1 Milestone Details</summary>

**Core Value:** All container configuration is generated from source files checked into the repo — no host bind mounts, no scattered settings, no manual file placement.

**Phases:**
1. Configuration Consolidation — config.json + secrets.json, agent-config/ templates, install-agent-config.sh
2. Directory Dissolution — claudehome/ eliminated, contents to agent-config/, infra/, .planning/
3. Runtime Generation & Cut-Over — bind mount removed, config generation, credential persistence

**Stats:** 3 phases, 6 plans, 27 commits, 186 files changed, 40/40 requirements satisfied

See [v1 Roadmap Archive](.planning/milestones/v1-ROADMAP.md) and [v1 Requirements Archive](.planning/milestones/v1-REQUIREMENTS.md) for full details.
</details>

---
*Last updated: 2026-02-15 after v1.2 milestone start*

# Claude Code Sandbox

## Current State

**Shipped:** v1.2 — Plugins & Proper Skills/Commands (2026-02-16)

The sandbox is a VS Code devcontainer running on Windows 11 via WSL2/Docker Desktop. All container configuration is generated from source files checked into the repo. A plugin system extends the install pipeline with self-registering bundles — each plugin declares hooks, env vars, commands, agents, and MCP servers in a `plugin.json` manifest, and the install script discovers, validates, copies, and merges everything into Claude Code settings.

### How It Works

1. **Two master files** at repo root: `config.json` (committed settings) + `secrets.json` (gitignored credentials)
2. **`agent-config/`** directory holds version-controlled templates, skills, and plugins
3. **`agent-config/plugins/`** — self-registering plugin bundles with `plugin.json` manifests
4. **`install-agent-config.sh`** reads both files, discovers plugins, hydrates `{{TOKEN}}` placeholders from namespaced secrets, copies assets to `~/.claude/`, merges hooks/env/MCP into settings
5. **`save-secrets`** captures live credentials and derives plugin namespaces for secret hydration
6. **`mcp-setup`** preserves plugin MCP servers across container restarts via `_source` tagging

### Key Paths

| Path | Purpose |
|------|---------|
| `config.json` | Non-secret settings (firewall, langfuse, codex, vscode, mcp, plugins) |
| `secrets.json` | Credentials + plugin-namespaced secrets — gitignored |
| `agent-config/plugins/` | Self-registering plugin bundles with plugin.json manifests |
| `agent-config/settings.json.template` | Permissions-only template (hooks/env via plugins) |
| `.devcontainer/` | Dockerfile, install scripts, firewall, devcontainer.json |
| `infra/` | Langfuse stack (docker-compose, scripts, hooks, MCP config) |
| `.planning/` | GSD planning state (roadmap, phases, verification) |
| `gitprojects/` | Cloned project repositories |

### Infrastructure

- **Langfuse** tracing via `plugins/langfuse-tracing/` (Stop hook + env vars hydrated from secrets)
- **MCP gateway** for tool access (plugin MCP servers persist across restarts)
- **Firewall** with domain whitelist (27 core + extras from config.json)
- **GSD framework** — 30+ commands + 11 agents for structured development workflows
- **Cross-agent skills** — deployed to both Claude and Codex

### Plugin System

Plugins are discovered from `agent-config/plugins/*/plugin.json`. Each manifest can declare:
- **hooks** — registered in settings.json (array concatenation, multiple plugins accumulate)
- **env** — injected with `{{TOKEN}}` hydration from `secrets.json[plugin-name][TOKEN]`
- **mcp_servers** — merged into `.mcp.json` with `_source` tagging for persistence
- **files** — skills, hooks, commands, agents copied to `~/.claude/` with GSD protection

Plugins are enabled by default. Disable via `config.json`: `"plugins": {"name": {"enabled": false}}`.

Validation catches: missing hook scripts (skip plugin), file overwrites (first-wins), invalid JSON (friendly + raw error), unresolved `{{TOKEN}}` placeholders (warning). All warnings recapped after install summary.

**Reference implementation:** `langfuse-tracing` plugin (Stop hook + 4 env vars).

### Tech Debt

1. Plugin compatibility — plugin MCP server domains need manual addition to config.json extra_domains
2. secrets.example.json — plugin namespace structure added but could use more complete documentation

## Requirements

### Validated

- ✓ All container config generated from source files — v1
- ✓ Plugin discovery, validation, and file integration — v1.2
- ✓ Hook/env/MCP accumulation with multi-plugin coexistence — v1.2
- ✓ GSD file protection (commands/gsd/, gsd-* agents) — v1.2
- ✓ Plugin MCP server persistence across container restarts — v1.2
- ✓ Langfuse tracing as self-registering plugin — v1.2
- ✓ Validation warnings with recap for plugin debugging — v1.2
- ✓ Cross-agent skills (Claude + Codex) — v1.2
- ✓ Standalone commands from agent-config/commands/ — v1.2

### Active

(None — next milestone requirements TBD via `/gsd:new-milestone`)

### Out of Scope

| Feature | Reason |
|---------|--------|
| Per-session plugin enable/disable | No runtime config reload API in Claude Code |
| Plugin auto-updates | No package registry; rebuild container handles updates |
| Plugin conflict blocking | Informational warnings sufficient; blocking creates UX friction |
| Strict plugin dependency resolution | Premature until plugin ecosystem proves need |
| Remote plugin installation | Security concern; plugins are version-controlled in repo |
| Plugin versioning enforcement | Premature — only 5 plugins, no inter-plugin deps yet |

## Key Decisions

| Decision | Milestone | Outcome |
|----------|-----------|---------|
| config.json + secrets.json as master files | v1 | ✓ Good — clean separation of committed vs secret config |
| agent-config/ as version-controlled source | v1 | ✓ Good — single source of truth for all templates |
| Plugin system via plugin.json manifests | v1.2 | ✓ Good — self-registering, minimal boilerplate |
| First-wins for env var + file conflicts | v1.2 | ✓ Good — deterministic (alphabetical order), consistent |
| Namespaced secrets: secrets.json[plugin-name][TOKEN] | v1.2 | ✓ Good — prevents cross-plugin secret collision |
| _source tagging for MCP persistence | v1.2 | ✓ Good — enables mcp-setup to preserve plugin servers |
| Settings template → permissions-only | v1.2 | ✓ Good — plugins are sole extensibility path |
| Minimal manifests (no empty arrays) | v1.2 | ✓ Good — less noise, langfuse-tracing as reference |

## Context

- VS Code devcontainer on Windows 11 via WSL2/Docker Desktop
- GSD (Get Shit Done) workflow framework for structured development
- All work executed from Windows host side
- Claude Code plugins (public beta) coexist with standalone .claude/ config
- 5 plugins active: langfuse-tracing, nmc, frontend-design, plugin-dev, ralph-wiggum

<details>
<summary>v1.2 Milestone Details</summary>

**Goal:** Add a plugin system with self-registering hooks/env/MCP, standalone commands support, and migrate langfuse to plugin as proof-of-concept.

**Phases:**
4. Core Plugin System — Discovery, validation, file copying, hook/env accumulation, GSD protection
5. MCP Integration — Plugin MCP servers with namespaced hydration and persistence
6. Langfuse Migration & Validation — Plugin migration, env hydration, validation warnings, install summary

**Stats:** 3 phases, 6 plans, 11 tasks, 110 files changed, 35/35 requirements satisfied, 34 days

See [v1.2 Roadmap Archive](.planning/milestones/v1.2-ROADMAP.md) and [v1.2 Requirements Archive](.planning/milestones/v1.2-REQUIREMENTS.md) for full details.
</details>

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

## Changelog

- **2026-02-16** — Codex MCP parity: MCP servers now configured in Codex `config.toml` alongside Claude `.mcp.json`. Added `targets` field for per-agent server filtering. Fixed mcp-gateway template double-nesting bug. Fixed `codexr` alias (`codex resume`). GSD count updated to 30+.

---
*Last updated: 2026-02-16*

# Changelog

All notable changes to No More Configs will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned per [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

GitHub releases should use the title format: **vX.Y.Z — YYYY-MM-DD**

---

## [1.0.3] - 2026-02-16 `released`

### Fixed

- Project-repo plugins (`projects/*/.claude/plugins/*/`) not loading — install script now auto-discovers and copies their components (skills, commands, agents, hooks) to runtime locations, same as agent-config plugins
- Project plugin commands now namespaced into `commands/<plugin-name>/` subdirectories to avoid collisions (e.g. `uproot:build-hook`)
- Project plugin `hooks.json` (settings format) merged directly into `settings.json` instead of through the agent-config accumulator which wrapped them in an extra layer, causing `Invalid Settings` errors
- Hooks and env vars now reset before rebuilding on each install run, preventing stale entries from persisting across re-runs

---

## [1.0.2] - 2026-02-16 `released`

### Changed

- `gitprojects/` renamed to `projects/` — simpler, less confusing for new users
- `save-secrets` now captures GitHub CLI credentials; restored automatically on rebuild
- README version badge now auto-updates from GitHub releases

### Removed

- `config.example.json`, `secrets.example.json` — schema is documented inline in the README

---

## [1.0.1] - 2026-02-16 `released`

### Fixed

- `langfuse-setup` MinIO/ClickHouse data directory ownership — replaced busybox chown (broken in Docker-outside-of-Docker) with direct `sudo chown`
- GSD framework not updating on container rebuild — now updates to latest on every container start

### Changed

- `config.json` no longer ships in repo — created at runtime by `save-config` and `save-secrets`
- README fully redesigned — centered header, shields.io badges, feature matrix, value proposition
- Copyright year corrected to 2026
- Platform support clarified — tested on Windows (WSL2), macOS/Linux untested
- Acknowledgments expanded — Claude Code credited for plugins and hooks framework, not just devcontainer
- GSD framework description clarified

### Removed

- `review/` directory (internal-only, not useful for end users)
- Personal author name replaced with `agomusio` in plugin and skill metadata

### Added

- `CHANGELOG.md` — project history and release notes
- `TROUBLESHOOTING.md` — common Docker Desktop, WSL2, networking, and filesystem issues with fixes

---

## [1.0.0] - 2026-02-16 `released`

First public release. Everything below is what ships out of the box.

### Core

- **Claude Code** CLI (latest) — Opus 4.6, high effort, bypass permissions
- **Codex CLI** (latest) — GPT-5.3-Codex, full-auto mode, file-based auth
- **Two-file configuration** — `config.json` (settings) + `secrets.json` (credentials, gitignored)
- **Credential persistence** — `save-secrets` captures auth tokens, git identity, and infra secrets; restored automatically on rebuild
- **Preference persistence** — `save-config` captures Claude Code preferences; restored on rebuild

### Plugin System

- Self-registering plugins via `agent-config/plugins/*/plugin.json`
- Hook accumulation (multiple plugins on same events)
- Environment variable injection with `{{TOKEN}}` hydration from `secrets.json`
- Plugin MCP server registration with `_source` tagging
- Config-driven enable/disable and env overrides
- Validation with warnings recap (missing scripts, file conflicts, unresolved tokens)
- **Included plugins:** `nmc`, `nmc-langfuse-tracing`, `nmc-ralph-loop`, `plugin-dev`, `frontend-design`

### Infrastructure

- **iptables firewall** — default-deny, 31 core domains, auto-generated VS Code extension CDN domains, user-configurable extras
- **Langfuse observability** — self-hosted stack (Langfuse + PostgreSQL + ClickHouse + Redis + MinIO), one-command setup via `langfuse-setup`
- **MCP gateway** — Docker MCP Gateway with health checking and auto-configuration
- **Codex MCP server** — optional, lets Claude delegate to Codex mid-session
- **GSD framework** — 30+ slash commands, 11 specialized agents, installed via `npx get-shit-done-cc`

### Developer Experience

- Oh-My-Zsh with Powerlevel10k, fzf, git-delta, GitHub CLI
- Shell aliases: `claude`, `clauder`, `codex`, `codexr`, `save-secrets`, `save-config`, `langfuse-setup`, `mcp-setup`
- Lifecycle log aliases: `slc` (postCreate), `sls` (postStart)
- Cross-agent skills (Claude + Codex)
- Upstream plugin auto-download at build time (plugin-dev, frontend-design)

### Files

- `config.example.json` — annotated config reference
- `secrets.example.json` — secret schema reference
- `LICENSE` — MIT

[1.0.3]: https://github.com/agomusio/no-more-configs/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/agomusio/no-more-configs/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/agomusio/no-more-configs/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/agomusio/no-more-configs/releases/tag/v1.0.0

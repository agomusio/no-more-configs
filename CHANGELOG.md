# Changelog

All notable changes to No More Configs will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned per [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-02-16

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

[1.0.0]: https://github.com/agomusio/no-more-configs/releases/tag/v1.0.0

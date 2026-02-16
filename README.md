<div align="center">

# NO MORE CONFIGS

**A clone-and-go VS Code devcontainer for agentic coding with Claude Code and Codex CLI.**

**Clone. Open. Code.**

**Free, transparent, and fully customizable. No subscription walls, no black-box abstractions — just a devcontainer you own and control. For developers who'd rather read the source than trust the vendor.**

[![GitHub stars](https://img.shields.io/github/stars/agomusio/no-more-configs?style=for-the-badge&logo=github&color=181717)](https://github.com/agomusio/no-more-configs)
[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-brightgreen?style=for-the-badge)](https://github.com/agomusio/no-more-configs/releases/tag/v1.0.0)

<br>

```bash
git clone https://github.com/agomusio/no-more-configs.git
cd no-more-configs && code .
```

**Tested on Windows (WSL2). macOS and Linux should work but are untested.**

<br>

*"I spent a week configuring Claude Code in Docker. This would have taken me five minutes."*

<br>

[What You Get](#what-you-get) · [Quick Start](#quick-start) · [How It Works](#how-it-works) · [Plugin System](#plugin-system) · [Customization](#customization)

</div>

```
You                         Container
 │                           ├── Claude Code CLI + Codex CLI
 ├── config.json ──────────► ├── Firewall domains
 │   (settings)              ├── VS Code settings
 │                           ├── MCP server config
 ├── secrets.json ─────────► ├── Claude + Codex auth tokens
 │   (credentials)           ├── Git identity
 │                           ├── Plugin env vars (hydrated)
 ├── agent-config/plugins/ ► └── Hooks, commands, agents, skills, MCP
 │   (self-registering)
 └── Open in Container ────► Done.
```

---

## What You Get

| Feature | Description | Status |
|---------|-------------|--------|
| **Claude Code** | Anthropic's agentic coding CLI — Opus 4.6, high effort, permissions bypassed | Out of the box |
| **Codex CLI** | OpenAI's agentic coding CLI — GPT-5.3-Codex, full-auto mode | Out of the box |
| **Plugin system** | Drop a directory with a `plugin.json` to register hooks, env vars, commands, agents, MCP servers | Out of the box |
| **GSD framework** | 30+ slash commands and 11 specialized agents for structured development | Out of the box |
| **iptables firewall** | Default-deny network with domain whitelist (31 core domains) | Out of the box |
| **Oh-My-Zsh** | Powerlevel10k, fzf, git-delta, GitHub CLI | Out of the box |
| **Langfuse observability** | Self-hosted tracing — every conversation traced to a local dashboard | Opt-in |
| **MCP gateway** | Model Context Protocol tool access via Docker MCP Gateway | Opt-in |
| **Codex MCP server** | Let Claude delegate to Codex mid-session | Opt-in |

---

## Quick Start

### Prerequisites

- [VS Code](https://code.visualstudio.com/) with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [Git](https://git-scm.com/)

### 1. Clone and Open

```bash
git clone https://github.com/agomusio/no-more-configs.git
cd no-more-configs
code .
```

VS Code will detect the devcontainer and prompt to reopen in container. Click **Reopen in Container** (or use `Ctrl+Shift+P` → `Dev Containers: Reopen in Container`).

First build takes a few minutes. Subsequent opens are fast.

### 2. Authenticate

Once the container is running, authenticate the CLI agents you want to use:

```bash
claude          # Follow OAuth prompts (Claude Pro/Max subscription)
codex           # Follow OAuth prompts (ChatGPT Plus/Pro subscription)
```

Set your git identity:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Then capture everything so it survives container rebuilds:

```bash
save-secrets
```

### 3. Start the Langfuse Stack (Optional)

If you want conversation tracing:

```bash
langfuse-setup
```

This generates credentials (into `secrets.json`), starts the stack, and verifies health. View traces at `http://localhost:3052`.

### 4. Done

Start coding:

```bash
claude                         # Claude Code (Opus 4.6, high effort, permissions bypassed)
clauder                        # Resume a recent Claude session
codex                          # Codex CLI (GPT-5.3-Codex, full-auto mode)
codexr                         # Resume a recent Codex session
```

Your projects go in `gitprojects/`. Clone repos there and they'll be auto-detected by VS Code's git scanner.

---

## How It Works

### Two-File Configuration

Everything is driven by two files at the repo root:

**`config.json`** — non-secret settings (created by `save-config`, see `config.example.json`):

```json
{
  "firewall": { "extra_domains": ["your-api.example.com"] },
  "codex": { "model": "gpt-5.3-codex" },
  "langfuse": { "host": "http://host.docker.internal:3052" },
  "vscode": { "git_scan_paths": ["gitprojects/my-project"] },
  "mcp_servers": {
    "mcp-gateway": { "enabled": true },
    "codex": { "enabled": false, "targets": ["claude"] }
  },
  "plugins": { "nmc-langfuse-tracing": { "enabled": true, "env": {} } }
}
```

**`secrets.json`** (gitignored) — credentials and plugin secrets:

```json
{
  "git": { "name": "Your Name", "email": "you@example.com" },
  "claude": { "credentials": { "...auth tokens..." } },
  "codex": { "auth": { "...oauth tokens..." } },
  "nmc-langfuse-tracing": { "LANGFUSE_HOST": "...", "LANGFUSE_PUBLIC_KEY": "...", "LANGFUSE_SECRET_KEY": "..." },
  "infra": { "postgres_password": "...", "langfuse_project_secret_key": "...", "..." }
}
```

Plugin secrets use namespaced keys (`secrets.json["plugin-name"]["TOKEN"]`). The `infra` section holds Langfuse stack infrastructure secrets. Run `langfuse-setup` to generate these automatically — `save-secrets` derives the plugin namespace from the infra keys.

On container creation, `install-agent-config.sh` reads both files, discovers plugins, hydrates `{{TOKEN}}` placeholders, and generates all runtime configuration. On container start, the firewall and MCP servers are initialized from the generated files.

> **Important:** All hooks, env vars, and functional settings must be in `settings.json`. Never use `settings.local.json` for hooks or env vars — Claude Code does not execute hooks defined there. The install script merges everything (template + plugins + GSD) into `~/.claude/settings.json`.

### Credential Persistence

```
authenticate Claude/Codex → set git identity → save-secrets → secrets.json → rebuild → auto-restored
```

`save-secrets` captures live Claude credentials, Codex credentials, git identity, infrastructure secrets, and derives plugin secret namespaces. The install script restores them on the next rebuild. Delete `secrets.json` to start fresh.

### Pre-configured Defaults

Both CLI agents are pre-configured for container use — no interactive prompts on subsequent starts:

| Setting         | Claude Code                                | Codex CLI                                      |
| --------------- | ------------------------------------------ | ---------------------------------------------- |
| **Permissions** | Bypassed (`bypassPermissions` in settings) | Bypassed (`approval_policy = "never"`)         |
| **Model**       | Opus 4.6 (high effort)                     | GPT-5.3-Codex (configurable via `config.json`) |
| **Credentials** | `~/.claude/.credentials.json`              | `~/.codex/auth.json` (file-based, no keyring)  |
| **MCP**         | `~/.claude/.mcp.json`                      | `config.toml [mcp_servers.*]`                  |
| **Onboarding**  | Skipped when credentials present           | Workspace pre-trusted                          |

---

## Plugin System

Plugins are self-registering bundles discovered from `agent-config/plugins/*/plugin.json`. Each manifest can declare:

- **hooks** — registered in settings.json (multiple plugins accumulate on same events)
- **env** — injected with `{{TOKEN}}` placeholder hydration from `secrets.json[plugin-name][TOKEN]`
- **mcp_servers** — merged into `.mcp.json` with `_source` tagging for persistence
- **files** — skills, hooks, commands, agents copied to `~/.claude/`

### Creating a Plugin

```
agent-config/plugins/my-plugin/
├── plugin.json           # Manifest (required)
├── hooks/                # Hook scripts
├── commands/             # Slash commands (*.md)
├── agents/               # Agent definitions (*.md)
└── skills/               # Skills directories
```

Minimal `plugin.json`:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin does",
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "python3 /home/node/.claude/hooks/my_hook.py"
      }
    ]
  },
  "env": {
    "MY_VAR": "value",
    "MY_SECRET": "{{MY_SECRET}}"
  }
}
```

Only declare fields you use — no empty arrays needed.

### Plugin Control

Plugins are enabled by default. Disable via `config.json`:

```json
{ "plugins": { "my-plugin": { "enabled": false } } }
```

Override env vars via `config.json`:

```json
{ "plugins": { "my-plugin": { "env": { "MY_VAR": "override-value" } } } }
```

### Validation

The install script validates plugins and provides clear feedback:

- Missing hook scripts → plugin skipped with warning
- File conflicts between plugins → first-wins with warning
- Invalid `plugin.json` → friendly error + raw parse details
- Unresolved `{{TOKEN}}` placeholders → warning (non-fatal)
- All warnings recapped after install summary

### Included Plugins

| Plugin             | Description                                                                                                                                                      |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nmc`              | NMC system status command (`/nmc`)                                                                                                                               |
| `nmc-langfuse-tracing` | Claude Code conversation tracing to Langfuse (Stop hook + env vars)                                                                                              |
| `plugin-dev`       | Plugin development guidance ([source](https://github.com/anthropics/claude-code/tree/main/plugins/plugin-dev))                                                   |
| `nmc-ralph-loop`   | Ralph Wiggum technique for iterative, self-referential AI development loops (forked from [ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)) |
| `frontend-design`  | Frontend design skills and patterns ([source](https://github.com/anthropics/claude-code/tree/main/plugins/frontend-design))                                      |

---

## Agent Config

The `agent-config/` directory is the version-controlled source of truth:

- **`settings.json.template`** — Permissions-only template (hooks and env come from plugins)
- **`plugins/`** — Self-registering plugin bundles with `plugin.json` manifests
- **`skills/`** — Standalone skills copied to `~/.claude/skills/` and `~/.codex/skills/`
- **`commands/`** — Standalone slash commands copied to `~/.claude/commands/`
- **`mcp-templates/`** — MCP server templates (mcp-gateway, codex) with placeholder hydration

Add your own skills by creating a directory under `agent-config/skills/` with a `SKILL.md` file. They'll be installed to both Claude and Codex automatically on rebuild.

---

## Architecture

```
Host (Docker Desktop)
 ├── VS Code → Dev Container (Debian 12 Bookworm / Node 20)
 │   ├── Claude Code + Codex CLI + plugins + GSD framework
 │   ├── iptables whitelist firewall
 │   └── /var/run/docker.sock (from host)
 │
 └── Sidecar Stack (Docker-outside-of-Docker)
     ├── langfuse-web          :3052
     ├── langfuse-worker       :3030
     ├── docker-mcp-gateway    :8811
     ├── postgres              :5433
     ├── clickhouse            :8124 (HTTP) / :9000 (native)
     ├── redis                 :6379
     └── minio                 :9090 (API) / :9091 (console)
```

The dev container and sidecar services are sibling containers on the same Docker engine. They communicate via `host.docker.internal`.

---

## Firewall

Default policy is **DROP**. Only whitelisted domains are reachable.

**Always included** (31 core domains): Anthropic API, GitHub, npm, PyPI, Debian repos, VS Code Marketplace, OpenAI (API + Auth + Platform + ChatGPT), Google AI API, Cloudflare, and more.

**Auto-generated**: Per-publisher VS Code extension CDN domains are derived from `devcontainer.json` so extensions install without firewall errors.

**User-configured**: Add domains to `config.json → firewall.extra_domains` — they're appended automatically on rebuild.

To temporarily allow a domain inside the container:

```bash
IP=$(dig +short example.com | tail -1)
sudo iptables -I OUTPUT -d "$IP" -j ACCEPT
```

To refresh DNS for all firewall domains without restarting:

```bash
sudo /usr/local/bin/refresh-firewall-dns.sh
```

---

## MCP Servers

MCP servers come from two sources:

1. **Templates** in `agent-config/mcp-templates/`, enabled in `config.json → mcp_servers`
2. **Plugins** declaring `mcp_servers` in their `plugin.json` manifest

| Server        | Source   | Description                                                                              |
| ------------- | -------- | ---------------------------------------------------------------------------------------- |
| `mcp-gateway` | Template | Docker MCP Gateway at `127.0.0.1:8811`                                                   |
| `codex`       | Template | Codex CLI as MCP server — gives Claude access to `codex`, `review`, `listSessions` tools |

Enable a template server:

```json
{
  "mcp_servers": {
    "mcp-gateway": { "enabled": true },
    "codex": { "enabled": true, "targets": ["claude"] }
  }
}
```

### Server Targeting

By default, enabled MCP servers are configured for both Claude Code (`~/.claude/.mcp.json`) and Codex CLI (`config.toml [mcp_servers.*]`). To restrict a server to a specific agent, add `targets`:

```json
{ "mcp-gateway": { "enabled": true, "targets": ["codex"] } }
```

Valid targets: `"claude"`, `"codex"`. Default (when `targets` is omitted): both agents. The `codex` MCP server template should always target `["claude"]` since it would be circular for Codex to have itself as an MCP server.

Plugin MCP servers are registered automatically and persist across container restarts. The `mcp-setup` command regenerates base template servers on every container start for both agents while preserving plugin servers.

---

## GSD Framework

[Get Shit Done](https://github.com/glittercowboy/get-shit-done) is a project management framework for Claude Code that breaks work into atomic tasks sized for fresh context windows.

**Key commands:** `/gsd:new-project`, `/gsd:plan-phase`, `/gsd:execute-phase`, `/gsd:verify-work`, `/gsd:progress`

Run `/gsd:help` inside a Claude session for the full command list.

---

## Langfuse Tracing

Every Claude conversation is automatically traced to your local Langfuse instance via the `nmc-langfuse-tracing` plugin. The plugin registers a Stop hook that reads transcript files, groups messages into turns, and sends structured traces with generation and tool spans.

View traces at `http://localhost:3052` after starting the Langfuse stack.

To disable tracing, set `"nmc-langfuse-tracing": { "enabled": false }` in `config.json → plugins`.

### Hook Logs

```bash
tail -50 ~/.claude/state/langfuse_hook.log
```

---

## Shell Shortcuts

| Command          | Action                                                                  |
| ---------------- | ----------------------------------------------------------------------- |
| `claude`         | Claude Code — Opus 4.6, high effort, permissions bypassed               |
| `clauder`        | Alias for `claude --resume`                                             |
| `codex`          | Codex CLI — GPT-5.3-Codex, full-auto, no sandbox                        |
| `codexr`         | Alias for `codex resume`                                                |
| `save-secrets`   | Capture live credentials, git identity, and keys to `secrets.json`      |
| `langfuse-setup` | Generate secrets, start Langfuse stack, verify health                   |
| `mcp-setup`      | Regenerate MCP configs (Claude + Codex) and health-check gateway        |
| `slc`            | Show postCreate lifecycle log (`/tmp/devcontainer-logs/postCreate.log`) |
| `sls`            | Show postStart lifecycle log (`/tmp/devcontainer-logs/postStart.log`)   |

---

## Project Structure

```
/workspace/
├── .devcontainer/              # Container definition and lifecycle scripts
│   ├── Dockerfile
│   ├── devcontainer.json
│   ├── install-agent-config.sh # Master config generator (plugins, hooks, env, MCP)
│   ├── init-firewall.sh
│   └── ...
│
├── agent-config/               # Version-controlled agent config source
│   ├── settings.json.template  # Permissions-only template
│   ├── plugins/                # Self-registering plugin bundles
│   │   ├── nmc-langfuse-tracing/   #   Langfuse conversation tracing
│   │   ├── nmc/                #   NMC system status
│   │   └── .../                #   Your plugins here
│   ├── mcp-templates/          # MCP server templates (mcp-gateway, codex)
│   ├── skills/                 # Standalone skills (Claude + Codex)
│   └── commands/               # Standalone slash commands
│
├── config.example.json         # Annotated config reference
├── secrets.example.json        # Secret schema reference
│
├── infra/                      # Langfuse + MCP gateway stack
│   ├── docker-compose.yml
│   ├── data/                   # Persistent bind mounts (gitignored)
│   └── mcp/mcp.json
│
└── gitprojects/                # Your repos go here
```

---

## Customization

### Adding Firewall Domains

Edit `config.json`:

```json
{ "firewall": { "extra_domains": ["api.example.com", "cdn.example.com"] } }
```

Rebuild the container to apply.

### Changing the Codex Model

Edit `config.json`:

```json
{ "codex": { "model": "o4-mini" } }
```

Rebuild the container. Default is `gpt-5.3-codex`.

### Adding Skills

Create `agent-config/skills/my-skill/SKILL.md` with a YAML front matter block and skill content. It'll be copied to both `~/.claude/skills/` and `~/.codex/skills/` on rebuild.

### Adding Plugins

Create `agent-config/plugins/my-plugin/plugin.json` with a manifest declaring hooks, env vars, commands, agents, or MCP servers. See the [Plugin System](#plugin-system) section for details.

### Adding Git Repos

```bash
cd /workspace/gitprojects && git clone <url>
```

Add the path to `config.json → vscode.git_scan_paths` for VS Code git integration.

### Adding MCP Servers

Via templates:

1. Create a template in `agent-config/mcp-templates/`
2. Enable it in `config.json → mcp_servers`
3. Rebuild

Via plugins:

1. Add `mcp_servers` to your plugin's `plugin.json`
2. Add secrets to `secrets.json` under the plugin name
3. Rebuild

---

## Troubleshooting

### Langfuse unreachable / port 3052 blocked

WSL2's networking can enter a broken state (Windows only). Fix:

```powershell
# PowerShell as Administrator
wsl --shutdown
Restart-Service hns
```

Reopen VS Code and the container.

### Traces not appearing

1. Inside a Claude session, check `echo $TRACE_TO_LANGFUSE` (should be `true` — this env var is set in Claude's `settings.json`, not in the shell)
2. Check `curl http://host.docker.internal:3052/api/public/health`
3. Check `tail -20 ~/.claude/state/langfuse_hook.log`

### Plugin warnings during install

Check the install output for the `--- Warnings Recap ---` section. Common issues:

- Missing hook script file → plugin skipped (check the file path in your plugin.json)
- Unresolved `{{TOKEN}}` → add the secret to `secrets.json` under your plugin name
- File conflict → two plugins provide the same file (first alphabetically wins)

### Docker socket permission denied

```bash
sudo chmod 666 /var/run/docker.sock
```

### Git "dubious ownership" errors

Handled automatically. If it recurs: `git config --global --add safe.directory '*'`

---

## Known Issues

| Issue                                                                                | Cause                                                                                                                                            | Status                                                                                                 |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| Claude Code Edit tool throws `ENOENT: no such file or directory` on files that exist | WSL2 bind mount (C:\ → 9P → container) causes stale file metadata; the Edit tool's freshness check sees a mismatched mtime and rejects the write | Intermittent, self-healing (re-read + retry succeeds). Likely resolved in a future Claude Code update. |
| Lifecycle terminal closes before you can read output                                 | VS Code dismisses the postCreate/postStart terminal on completion                                                                                | Use `slc` / `sls` aliases to view saved logs from `/tmp/devcontainer-logs/`                            |

---

<div align="center">

## Acknowledgments

Built on the shoulders of:

**[Claude Code](https://github.com/anthropics/claude-code)** (devcontainer, plugins, hooks framework) · **[claude-code-langfuse-template](https://github.com/doneyli/claude-code-langfuse-template)** · **[Get Shit Done](https://github.com/glittercowboy/get-shit-done)** · **[codex-mcp-server](https://github.com/tuannvm/codex-mcp-server)**

<br>

MIT License · Copyright (c) 2026 agomusio

</div>

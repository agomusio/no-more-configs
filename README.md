# No More Configs

No More Configs (NMC) is a clone-and-go VS Code devcontainer for agentic coding with Claude Code, Codex CLI, and other models. Langfuse observability, MCP gateway, GSD workflow framework, iptables firewall — all configured from two files at the repo root. No host dependencies, no scattered config, no yak shaving.

```
You                         Container
 │                           ├── Claude Code CLI + Codex CLI
 ├── config.json ──────────► ├── Firewall domains
 │   (settings)              ├── VS Code settings
 │                           ├── MCP server config
 ├── secrets.json ─────────► ├── Claude + Codex auth tokens
 │   (credentials)           ├── Git identity
 │                           └── Langfuse infra + tracing keys
 │
 └── Open in Container ────► Done.
```

## What You Get

- **Claude Code** (latest) — Anthropic's agentic coding CLI, pre-configured with bypass permissions, Opus model, high effort
- **Codex CLI** (latest) — OpenAI's agentic coding CLI (GPT-5.3-Codex), pre-configured with full-auto mode
- **Langfuse** self-hosted observability — every conversation traced to a local dashboard (optional)
- **MCP gateway** for Model Context Protocol tool access
- **Codex MCP server** — lets Claude delegate to Codex mid-session (optional, enable in config.json)
- **GSD framework** — 28 slash commands and 11 specialized agents for structured development
- **iptables firewall** — default-deny network with domain whitelist
- **Oh-My-Zsh** with Powerlevel10k, fzf, git-delta, GitHub CLI

## Quick Start

### Prerequisites

- [VS Code](https://code.visualstudio.com/) with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [Git](https://git-scm.com/)

### 1. Clone and Open

```bash
git clone https://github.com/agomusio/claude-code-sandbox.git
cd claude-code-sandbox
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
claude                         # Claude Code (Opus, high effort, permissions bypassed)
clauder                        # Resume last Claude session
codex                          # Codex CLI (GPT-5.3-Codex, full-auto mode)
codexr                         # Resume last Codex session
```

Your projects go in `gitprojects/`. Clone repos there and they'll be auto-detected by VS Code's git scanner.

---

## How It Works

### Two-File Configuration

Everything is driven by two files at the repo root:

**`config.json`** (committed) — non-secret settings:
```json
{
  "firewall": { "extra_domains": ["your-api.example.com"] },
  "codex": { "model": "gpt-5.3-codex" },
  "langfuse": { "host": "http://host.docker.internal:3052" },
  "vscode": { "git_scan_paths": ["gitprojects/my-project"] },
  "mcp_servers": { "mcp-gateway": { "enabled": true }, "codex": { "enabled": false } }
}
```

**`secrets.json`** (gitignored) — credentials:
```json
{
  "git": { "name": "Your Name", "email": "you@example.com" },
  "claude": { "credentials": { "...auth tokens..." } },
  "codex": { "auth": { "...oauth tokens..." } },
  "infra": { "postgres_password": "...", "langfuse_project_secret_key": "...", "..." }
}
```

The `infra` section holds all Langfuse stack secrets (database passwords, encryption keys, project keys, admin credentials). Run `langfuse-setup` to generate these automatically.

On container creation, `install-agent-config.sh` reads both files and generates all runtime configuration. On container start, the firewall and MCP servers are initialized from the generated files.

### Credential Persistence

```
authenticate Claude/Codex → set git identity → save-secrets → secrets.json → rebuild → auto-restored
```

`save-secrets` captures live Claude credentials, Codex credentials, git identity, and infrastructure secrets back into `secrets.json`. The install script restores them on the next rebuild. Delete `secrets.json` to start fresh.

### Pre-configured Defaults

Both CLI agents are pre-configured for container use — no interactive prompts on subsequent starts:

| Setting | Claude Code | Codex CLI |
|---------|-------------|-----------|
| **Permissions** | `bypassPermissions` (no prompts) | `approval_policy = "never"` |
| **Model** | Opus (high effort) | `gpt-5.3-codex` (configurable via `config.json`) |
| **Sandbox** | N/A (container is the sandbox) | `danger-full-access` |
| **Credentials** | `~/.claude/.credentials.json` | `~/.codex/auth.json` (file-based, no keyring) |
| **Onboarding** | Skipped when credentials present | Workspace pre-trusted |

### Agent Config

The `agent-config/` directory is the version-controlled source of truth:

- **`settings.json.template`** — Claude Code settings with `{{PLACEHOLDER}}` tokens hydrated from config/secrets
- **`skills/`** — Custom skills copied to `~/.claude/skills/`
- **`hooks/`** — Hooks copied to `~/.claude/hooks/`
- **`mcp-templates/`** — MCP server templates (mcp-gateway, codex) with placeholder hydration

Add your own skills by creating a directory under `agent-config/skills/` with a `SKILL.md` file. They'll be installed automatically on rebuild.

---

## Architecture

```
Host (Docker Desktop)
 ├── VS Code → Dev Container (Debian/Node 20)
 │   ├── Claude Code + Codex CLI + skills + GSD framework
 │   ├── iptables whitelist firewall
 │   └── /var/run/docker.sock (from host)
 │
 └── Sidecar Stack (Docker-outside-of-Docker)
     ├── langfuse-web          :3052
     ├── langfuse-worker       :3030
     ├── docker-mcp-gateway    :8811
     ├── postgres              :5433
     ├── clickhouse            :8124
     ├── redis                 :6379
     └── minio                 :9090
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

MCP servers are managed through templates in `agent-config/mcp-templates/` and enabled in `config.json → mcp_servers`.

| Server | Template | Description |
|--------|----------|-------------|
| `mcp-gateway` | `mcp-gateway.json` | Docker MCP Gateway at `127.0.0.1:8811` |
| `codex` | `codex.json` | Codex CLI as MCP server — gives Claude access to `codex`, `review`, `listSessions` tools |

Enable a server:
```json
{ "mcp_servers": { "mcp-gateway": { "enabled": true }, "codex": { "enabled": true } } }
```

The `mcp-setup` command regenerates `~/.claude/.mcp.json` from enabled templates on every container start.

To add a custom MCP server, create a template in `agent-config/mcp-templates/` and enable it in `config.json`.

---

## GSD Framework

[Get Shit Done](https://github.com/glittercowboy/get-shit-done) is a project management framework for Claude Code that breaks work into atomic tasks sized for fresh context windows.

**Key commands:** `/gsd:new-project`, `/gsd:plan-phase`, `/gsd:execute-phase`, `/gsd:verify-work`, `/gsd:progress`

Run `/gsd:help` inside a Claude session for the full command list.

---

## Langfuse Tracing

Every Claude conversation is automatically traced to your local Langfuse instance via a Stop hook (`langfuse_hook.py`). The hook reads transcript files, groups messages into turns, and sends structured traces with generation and tool spans.

View traces at `http://localhost:3052` after starting the Langfuse stack.

### Hook Logs

```bash
tail -50 ~/.claude/state/langfuse_hook.log
```

---

## Shell Shortcuts

| Command | Action |
|---------|--------|
| `claude` | Claude Code — Opus, high effort, permissions bypassed |
| `clauder` | Alias for `claude --resume` |
| `codex` | Codex CLI — GPT-5.3-Codex, full-auto, no sandbox |
| `codexr` | Alias for `codex --resume` |
| `save-secrets` | Capture live credentials, git identity, and keys to `secrets.json` |
| `langfuse-setup` | Generate secrets, start Langfuse stack, verify health |
| `mcp-setup` | Regenerate `.mcp.json` from templates and health-check MCP gateway |

---

## Project Structure

```
/workspace/
├── .devcontainer/              # Container definition and lifecycle scripts
│   ├── Dockerfile
│   ├── devcontainer.json
│   ├── install-agent-config.sh # Master config generator
│   ├── init-firewall.sh
│   └── ...
│
├── agent-config/               # Version-controlled agent config source
│   ├── settings.json.template  # Settings with {{PLACEHOLDER}} tokens
│   ├── mcp-templates/          # MCP server templates (mcp-gateway, codex)
│   ├── skills/                 # Custom skills
│   └── hooks/                  # Custom hooks
│
├── config.json                 # Settings (committed)
│
├── infra/                      # Langfuse + MCP gateway stack
│   ├── docker-compose.yml
│   ├── data/                   # Persistent bind mounts (gitignored)
│   └── mcp/mcp.json
│
├── .planning/                  # GSD project planning state
├── gitprojects/                # Your repos go here
└── review/                     # Reviews and specs
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

Create `agent-config/skills/my-skill/SKILL.md` with a YAML front matter block and skill content. It'll be copied to `~/.claude/skills/` on rebuild.

### Adding Git Repos

```bash
cd /workspace/gitprojects && git clone <url>
```

Add the path to `config.json → vscode.git_scan_paths` for VS Code git integration.

### Adding MCP Servers

1. Create a template in `agent-config/mcp-templates/`
2. Enable it in `config.json → mcp_servers`
3. Rebuild

---

## Troubleshooting

### Langfuse unreachable / port 3052 blocked

WSL2's networking can enter a broken state. Fix:

```powershell
# PowerShell as Administrator
wsl --shutdown
Restart-Service hns
```

Reopen VS Code and the container.

### Traces not appearing

1. Inside a Claude session, check `echo $TRACE_TO_LANGFUSE` (should be `true` — this env var is set in Claude's `settings.local.json`, not in the shell)
2. Check `curl http://host.docker.internal:3052/api/public/health`
3. Check `tail -20 ~/.claude/state/langfuse_hook.log`

### Docker socket permission denied

```bash
sudo chmod 666 /var/run/docker.sock
```

### Git "dubious ownership" errors

Handled automatically. If it recurs: `git config --global --add safe.directory '*'`

---

## Acknowledgments

- **Dev Container** — Modified from the official [Claude Code Dev Container](https://github.com/anthropics/claude-code) reference configuration.
- **Langfuse Stack** — Built from Doneyli de Jesus's [claude-code-langfuse-template](https://github.com/doneyli/claude-code-langfuse-template), as described in [I Built My Own Observability for Claude Code](https://doneyli.substack.com/p/i-built-my-own-observability-for).
- **GSD Framework** — [Get Shit Done](https://github.com/glittercowboy/get-shit-done) by glittercowboy.
- **Codex MCP Server** — [codex-mcp-server](https://github.com/tuannvm/codex-mcp-server) by tuannvm.

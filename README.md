# No More Configs

No More Configs (NMC) is a clone-and-go VS Code devcontainer for agentic coding with Claude Code and other models. Langfuse observability, MCP gateway, GSD workflow framework, iptables firewall — all configured from two files at the repo root. No host dependencies, no scattered config, no yak shaving.

```
You                         Container
 │                           ├── Claude Code CLI + Codex CLI
 ├── config.json ──────────► ├── Firewall domains
 │   (settings)              ├── VS Code settings
 │                           ├── MCP gateway config
 ├── secrets.json ─────────► ├── Claude + Codex auth tokens
 │   (credentials)           ├── Langfuse tracing keys
 │                           └── API key exports
 │
 └── Open in Container ────► Done.
```

## What You Get

- **Claude Code** (latest) with custom skills and hooks pre-installed
- **Codex CLI** (latest) — OpenAI's agentic coding CLI (GPT-5.3-Codex)
- **Langfuse** self-hosted observability — every conversation traced to a local dashboard
- **MCP gateway** for Model Context Protocol tool access
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

After authenticating, capture your credentials so they survive container rebuilds:

```bash
save-secrets
```

### 3. Start the Langfuse Stack (Optional)

If you want conversation tracing:

```bash
cd /workspace/infra
./scripts/generate-env.sh      # Interactive — creates .env with random secrets
sudo docker compose up -d      # Starts all 8 services
```

Wait 30-60s, then verify at `http://localhost:3052`.

### 4. Done

Start coding:

```bash
claude                         # Claude Code — permissions bypassed by default
clauder                        # Resume last Claude session
codex                          # Codex CLI — OpenAI's agentic coding agent
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
  "langfuse": { "host": "http://host.docker.internal:3052" },
  "vscode": { "git_scan_paths": ["gitprojects/my-project"] },
  "mcp_servers": { "mcp-gateway": { "enabled": true } }
}
```

**`secrets.json`** (gitignored) — credentials:
```json
{
  "claude": { "credentials": { "...auth tokens..." } },
  "codex": { "auth": { "...oauth tokens..." } },
  "langfuse": { "public_key": "pk-...", "secret_key": "sk-..." },
  "api_keys": { "openai": "", "google": "" }
}
```

On container creation, `install-agent-config.sh` reads both files and generates all runtime configuration. On container start, the firewall and MCP gateway are initialized from the generated files.

### Credential Persistence

```
authenticate Claude/Codex → save-secrets → secrets.json → rebuild → auto-restored
```

`save-secrets` captures live Claude credentials, Codex credentials, Langfuse keys, and API keys back into `secrets.json`. The install script restores them on the next rebuild. Delete `secrets.json` to start fresh.

### Agent Config

The `agent-config/` directory is the version-controlled source of truth:

- **`settings.json.template`** — Claude Code settings with `{{PLACEHOLDER}}` tokens hydrated from config/secrets
- **`skills/`** — Custom skills copied to `~/.claude/skills/`
- **`hooks/`** — Hooks copied to `~/.claude/hooks/`
- **`mcp-templates/`** — MCP server templates with placeholder hydration

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

**Always included** (30 core domains): Anthropic API, GitHub, npm, PyPI, Debian repos, VS Code Marketplace, OpenAI (API + Auth + Platform + ChatGPT), Google AI API, Cloudflare, and more.

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

## MCP Gateway

The Docker MCP Gateway provides Model Context Protocol server access at `127.0.0.1:8811`.

- **Gateway config:** `infra/mcp/mcp.json`
- **Client config:** `.mcp.json` (generated, gitignored)
- **Default server:** `@modelcontextprotocol/server-filesystem` (workspace root)

To add a server, see [`infra/mcp/SERVERS.md`](infra/mcp/SERVERS.md) for examples.

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
│   ├── mcp-templates/          # MCP server templates
│   ├── skills/                 # Custom skills
│   └── hooks/                  # Custom hooks
│
├── config.json                 # Settings (committed)
│
├── infra/                      # Langfuse + MCP gateway stack
│   ├── docker-compose.yml
│   ├── mcp/mcp.json
│   └── scripts/
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

1. Check `echo $TRACE_TO_LANGFUSE` (should be `true`)
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

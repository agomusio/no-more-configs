---
name: devcontainer
description: Claude Code Sandbox devcontainer knowledge. Use when the user asks about the devcontainer, Docker setup, container configuration, workspace layout, installed tools, firewall, networking, Langfuse tracing, MCP gateway, mounted volumes, ports, environment variables, shell configuration, or any question about how this development environment is set up.
license: MIT
metadata:
  author: Sam Boland
  version: "1.0.0"
---

# Claude Code Sandbox — Devcontainer Reference

Complete reference for the development environment Claude Code runs inside. Use this to answer questions about the container setup, networking, tools, and configuration without searching the filesystem.

## Architecture

```
Windows Host (WSL2)
 ├── VS Code → Dev Container (Debian/Node 20, user: node)
 │   ├── Claude Code CLI + custom skills + GSD framework
 │   ├── iptables whitelist firewall
 │   └── /var/run/docker.sock (bind-mounted from host)
 │
 └── Sidecar Stack (Docker-outside-of-Docker, same Docker engine)
     ├── langfuse-web          127.0.0.1:3052 → :3000
     ├── langfuse-worker       127.0.0.1:3030 → :3030
     ├── docker-mcp-gateway    127.0.0.1:8811 → :8811
     ├── postgres              127.0.0.1:5433 → :5432
     ├── clickhouse            127.0.0.1:8124 → :8123
     ├── redis                 127.0.0.1:6379 → :6379
     └── minio                 127.0.0.1:9090 → :9000 (console :9091 → :9001)
```

The dev container and sidecar stack are sibling containers sharing the host Docker engine. They communicate via `host.docker.internal` which resolves to the WSL2 host gateway.

## Workspace Layout

```
/workspace/                          # Bind-mounted from Windows, delegated consistency
├── .devcontainer/
│   ├── Dockerfile                   # Node 20 + Claude Code + GSD + Docker CLI + firewall tools
│   ├── devcontainer.json            # Mounts, ports, env vars, extensions, lifecycle hooks
│   ├── init-firewall.sh             # iptables whitelist (runs on every start)
│   ├── init-gsd.sh                  # GSD slash command installer (runs on create)
│   └── setup-container.sh           # pip install langfuse, git config, Docker socket perms
├── .vscode/settings.json            # Multi-repo git scanning
├── claudehome/                      # Claude Code always launches from HERE
│   ├── CLAUDE.md                    # Project-level Claude instructions
│   ├── .claude/
│   │   ├── settings.local.json      # bypassPermissions, Langfuse env, Stop hook
│   │   └── skills/
│   │       ├── aa-fullstack/        # Adventure Alerts full-stack skill
│   │       ├── aa-cloudflare/       # Cloudflare platform skill
│   │       └── devcontainer/        # This skill
│   ├── .planning/                   # GSD project planning (phases, research, state)
│   ├── langfuse-local/
│   │   ├── docker-compose.yml       # 8-service stack (Langfuse + MCP gateway)
│   │   ├── .env                     # Generated secrets (git-ignored)
│   │   ├── mcp/mcp.json             # MCP gateway server config
│   │   ├── scripts/                 # generate-env.sh, validate-setup.sh
│   │   └── settings-examples/       # Reference settings.json files
│   └── scripts/                     # Verification scripts (MCP, gateway connectivity)
├── gitprojects/
│   └── adventure-alerts/            # Monorepo: Next.js + Hono + D1 + Durable Objects
└── docs/
```

## Key Paths

| Path                                 | Purpose                                                                  |
| ------------------------------------ | ------------------------------------------------------------------------ |
| `/workspace/claudehome/`             | Claude Code launch directory (has CLAUDE.md + .claude/)                  |
| `/home/node/.claude/`                | Global Claude config (bind-mounted from Windows `%USERPROFILE%\.claude`) |
| `/home/node/.claude/commands/gsd/`   | 29 GSD slash commands                                                    |
| `/home/node/.claude/agents/gsd-*.md` | 11 GSD specialized agents                                                |
| `/home/node/.claude/hooks/`          | langfuse_hook.py, gsd-check-update.js, gsd-statusline.js                 |
| `/home/node/.claude/settings.json`   | Global hook registration + env vars                                      |
| `/home/node/.claude/state/`          | langfuse_hook.log, langfuse_state.json                                   |
| `/var/run/docker.sock`               | Host Docker socket (bind-mounted)                                        |
| `/usr/local/bin/init-firewall.sh`    | Firewall script (copied from .devcontainer/)                             |
| `/commandhistory/`                   | Persistent shell history (Docker volume)                                 |

## Ports

| Port     | Service         | Notes                                                                                                     |
| -------- | --------------- | --------------------------------------------------------------------------------------------------------- |
| **3052** | Langfuse Web UI | Canonical port. From container: `http://host.docker.internal:3052`. From Windows: `http://localhost:3052` |
| 3030     | Langfuse Worker | Internal async job processing                                                                             |
| 5433     | PostgreSQL      | Offset from 5432 to avoid collisions                                                                      |
| 6379     | Redis           | Cache + job queue                                                                                         |
| 8124     | ClickHouse      | Analytics engine                                                                                          |
| **8811** | MCP Gateway     | Model Context Protocol gateway (loopback-only)                                                            |
| 9090     | MinIO S3        | Object storage                                                                                            |
| 9091     | MinIO Console   | Admin UI                                                                                                  |
| 3000     | Dev App         | Forwarded by devcontainer.json (silent)                                                                   |
| 8787     | Dev App 2       | Forwarded by devcontainer.json (silent)                                                                   |

## Environment Variables

### Set in devcontainer.json (containerEnv)

| Variable                         | Value                              | Purpose                           |
| -------------------------------- | ---------------------------------- | --------------------------------- |
| `CLAUDE_CONFIG_DIR`              | `/home/node/.claude`               | Claude Code config location       |
| `NODE_OPTIONS`                   | `--max-old-space-size=4096`        | 4GB Node.js heap                  |
| `POWERLEVEL9K_DISABLE_GITSTATUS` | `true`                             | Prevent slow git status in prompt |
| `LANGFUSE_HOST`                  | `http://host.docker.internal:3052` | Container-level Langfuse endpoint |

### Set in ~/.claude/settings.json (env)

| Variable              | Value                              | Purpose                            |
| --------------------- | ---------------------------------- | ---------------------------------- |
| `TRACE_TO_LANGFUSE`   | `true`                             | Master switch for tracing hook     |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-local-claude-code`          | Auto-provisioned project key       |
| `LANGFUSE_SECRET_KEY` | _(from .env)_                      | Generated by generate-env.sh       |
| `LANGFUSE_HOST`       | `http://host.docker.internal:3052` | Langfuse API from within container |

## Installed Tools

| Category       | Tools                                                      |
| -------------- | ---------------------------------------------------------- |
| **Runtime**    | Node.js 20, Python 3.11, npm 10, zsh 5.9                   |
| **Shell**      | Oh-My-Zsh, Powerlevel10k theme, fzf, plugins: git + fzf    |
| **VCS**        | Git 2.39, GitHub CLI (gh), git-delta 0.18.2                |
| **Docker**     | Docker CLI 29.2, Docker Compose v2                         |
| **Network**    | curl, wget, iptables, ipset, iproute2, dnsutils, aggregate |
| **Editors**    | nano (default), vim                                        |
| **Utilities**  | jq, fzf, unzip, man-db, procps, less                       |
| **Python**     | langfuse, openai, opentelemetry-api, httpx                 |
| **npm global** | get-shit-done-cc, claude (latest)                          |

## Shell Shortcuts

Defined as functions in `~/.zshrc` (not aliases):

- `claudey` — `cd /workspace/claudehome && claude --dangerously-skip-permissions "$@"`
- `claudeyr` — `cd /workspace/claudehome && claude --dangerously-skip-permissions --resume "$@"`

Both accept extra arguments. The `cd` ensures Claude Code picks up the project CLAUDE.md and .claude/settings.local.json.

## Hooks

| Event            | Script                                              | Purpose                                |
| ---------------- | --------------------------------------------------- | -------------------------------------- |
| **Stop**         | `python3 /home/node/.claude/hooks/langfuse_hook.py` | Send conversation traces to Langfuse   |
| **SessionStart** | `node /home/node/.claude/hooks/gsd-check-update.js` | Check for GSD framework updates        |
| **StatusLine**   | `node /home/node/.claude/hooks/gsd-statusline.js`   | Show GSD state in terminal status line |

The Langfuse hook reads `.jsonl` transcripts from `~/.claude/projects/`, groups messages into turns, creates traces with generation and tool spans, applies secret redaction, and flushes to Langfuse. It is non-blocking (exits 0 on any error).

## Firewall

The iptables-based firewall (`init-firewall.sh`) runs on every container start (`postStartCommand`). Default policy is **DROP** — only whitelisted domains are reachable.

**Whitelisted domains:**

- **VCS:** github.com, api.github.com, objects.githubusercontent.com + GitHub IP ranges (fetched dynamically)
- **Package registries:** registry.npmjs.org, deb.debian.org, security.debian.org, pypi.python.org
- **Claude/Anthropic:** api.anthropic.com, statsig.anthropic.com, statsig.com, sentry.io
- **IDE/Tools:** marketplace.visualstudio.com, vscode.blob.core.windows.net, update.code.visualstudio.com, json.schemastore.org
- **Cloud:** api.cloudflare.com, storage.googleapis.com
- **Internal:** host.docker.internal, 172.16.0.0/12 (Docker bridge), 192.168.65.0/24 (Docker Desktop)

**Policies:** Loopback allowed, DNS (53) allowed, ESTABLISHED/RELATED allowed, everything else DROPped.

To temporarily allow a blocked domain:

```bash
IP=$(dig +short example.com | tail -1)
sudo iptables -I OUTPUT -d "$IP" -j ACCEPT
```

To permanently allow: edit `.devcontainer/init-firewall.sh`.

## Mounts & Volumes

| Source                          | Target                 | Type   | Purpose                                    |
| ------------------------------- | ---------------------- | ------ | ------------------------------------------ |
| Windows `%USERPROFILE%\.claude` | `/home/node/.claude`   | Bind   | Claude config persists across rebuilds     |
| Host Docker socket              | `/var/run/docker.sock` | Bind   | Docker-outside-of-Docker                   |
| `claude-code-bashhistory-*`     | `/commandhistory`      | Volume | Shell history persists across rebuilds     |
| Workspace (Windows via WSL2)    | `/workspace`           | Bind   | Delegated consistency for WSL2 performance |

## Docker Run Capabilities

- `NET_ADMIN` + `NET_RAW` — required for iptables firewall
- `--add-host=host.docker.internal:host-gateway` — enables host resolution

## MCP Gateway

The Docker MCP Gateway (`docker/mcp-gateway:latest`) at port 8811 provides MCP server access.

- **Config:** `/workspace/claudehome/langfuse-local/mcp/mcp.json`
- **Transport:** stdio (servers via npx)
- **Current servers:** `@modelcontextprotocol/server-filesystem` (root: `/workspace`)

To add a server: edit `mcp.json`, then restart:

```bash
sudo docker compose -f /workspace/claudehome/langfuse-local/docker-compose.yml restart docker-mcp-gateway
```

## VS Code Extensions

| Extension                                        | Purpose                                             |
| ------------------------------------------------ | --------------------------------------------------- |
| dbaeumer.vscode-eslint                           | JavaScript/TypeScript linting                       |
| esbenp.prettier-vscode                           | Code formatting (format-on-save, default formatter) |
| cloudflare.cloudflare-workers-bindings-extension | Cloudflare Workers development                      |
| qwtel.sqlite-viewer                              | SQLite database inspection                          |
| bradlc.vscode-tailwindcss                        | Tailwind CSS IntelliSense                           |

Settings: format-on-save enabled, ESLint auto-fix on save, zsh default terminal.

## Lifecycle Commands

### postStartCommand (every start)

1. Runs `init-firewall.sh` (iptables whitelist)
2. Adds all dirs to git safe.directory
3. Sets `core.autocrlf input` for WSL compatibility

### postCreateCommand (first build only)

1. Runs `setup-container.sh` (git config, Docker socket perms, pip install langfuse, connectivity checks)
2. Runs `init-gsd.sh` (installs GSD slash commands if not present)

## Rebuild Behavior

Rebuilding the dev container does NOT affect the sidecar stack because:

- Langfuse/MCP gateway run on the host Docker engine, not inside the container
- Data persists in named volumes (langfuse_postgres_data, langfuse_clickhouse_data, etc.)
- `~/.claude/` is bind-mounted from Windows host — settings, hooks, skills, and GSD commands survive rebuilds
- Python packages (langfuse) are reinstalled by postCreateCommand since they live in the container's system Python

## Common Operations

### Start/stop sidecar stack

```bash
cd /workspace/claudehome/langfuse-local
sudo docker compose up -d     # start
sudo docker compose down       # stop (data preserved in volumes)
```

### Check Langfuse health

```bash
curl http://host.docker.internal:3052/api/public/health
```

### View hook logs

```bash
tail -50 ~/.claude/state/langfuse_hook.log
```

### Validate setup

```bash
/workspace/claudehome/langfuse-local/scripts/validate-setup.sh --post
```

### Fix WSL2 networking (port forwarding broken)

On Windows PowerShell (Admin):

```powershell
wsl --shutdown
Restart-Service hns
```

Then reopen VS Code and the container.

## Git Configuration

- **User:** agomusio / sam@theoryfarm.com
- **Safe directory:** `*` (all directories trusted — WSL UID mismatch workaround)
- **Line endings:** `core.autocrlf input`
- **Multi-repo scanning:** `.`, `gitprojects/adventure-alerts`, `gitprojects/claude-aimtrainer`
- **Remote:** `https://github.com/agomusio/claude-code-sandbox.git` (main branch)

## Permissions

- **Node user:** passwordless sudo (`NOPASSWD:ALL`)
- **Claude Code:** `bypassPermissions` mode for `/workspace/` and `/workspace/gitprojects/adventure-alerts/`
- **Additional directories:** `/workspace/gitprojects/` accessible
- **Docker socket:** `chmod 666` applied on create

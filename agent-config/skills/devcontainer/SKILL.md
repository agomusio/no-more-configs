---
name: devcontainer
description: No More Configs devcontainer knowledge. Use when the user asks about the devcontainer, Docker setup, container configuration, workspace layout, installed tools, firewall, networking, Langfuse tracing, MCP gateway, mounted volumes, ports, environment variables, shell configuration, or any question about how this development environment is set up.
license: MIT
metadata:
  author: Sam Boland
  version: "2.0.0"
---

# No More Configs — Devcontainer Reference

Complete reference for the development environment Claude Code runs inside. Use this to answer questions about the container setup, networking, tools, and configuration without searching the filesystem.

## Architecture

```
Host (VS Code + Docker Desktop)
 ├── VS Code → Dev Container (Debian/Node 20, user: node)
 │   ├── Claude Code CLI + Codex CLI + custom skills + GSD framework
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

The dev container and sidecar stack are sibling containers sharing the host Docker engine. They communicate via `host.docker.internal`.

## Configuration System

All container configuration is driven by two files at the repo root:

| File | Tracked | Purpose |
|------|---------|---------|
| `config.json` | Yes | Non-secret settings: firewall domains, Langfuse host, VS Code git scan paths, MCP servers |
| `secrets.json` | No (gitignored) | Credentials: Claude auth tokens, Langfuse keys, API keys |

On container creation, `install-agent-config.sh` reads both files and generates:
- `~/.claude/settings.local.json` (hydrated from `agent-config/settings.json.template`)
- `~/.claude/skills/`, `~/.claude/hooks/`, `~/.claude/commands/` (copied from `agent-config/`)
- `.devcontainer/firewall-domains.conf` (core domains + `config.json` extras)
- `.vscode/settings.json` (git scan paths from `config.json` + auto-detected repos)
- `.mcp.json` (MCP client config from enabled templates)
- `~/.claude/.credentials.json` (restored from `secrets.json`)
- `~/.codex/auth.json` (restored from `secrets.json`)
- `~/.claude-api-env` (API key exports sourced by shell)

### Credential Round-Trip

```
secrets.json → install-agent-config.sh → runtime files
                                              ↓
secrets.json ← save-secrets ← live container
```

`save-secrets` (installed to PATH) captures live Claude credentials, Codex credentials, Langfuse keys, and API keys back into `secrets.json` for persistence across rebuilds.

## Workspace Layout

```
/workspace/
├── .devcontainer/
│   ├── Dockerfile              # Node 20 + Claude Code + GSD + Docker CLI + firewall tools
│   ├── devcontainer.json       # Mounts, ports, env vars, lifecycle hooks
│   ├── install-agent-config.sh # Master config generator (reads config.json + secrets.json)
│   ├── init-firewall.sh        # iptables whitelist (runs on every start)
│   ├── refresh-firewall-dns.sh # DNS refresh for firewall domains
│   ├── save-secrets.sh         # Credential capture helper (installed to PATH)
│   ├── init-gsd.sh             # GSD framework installer
│   ├── setup-container.sh      # Post-create setup (git config, Docker socket)
│   ├── setup-network-checks.sh # Langfuse pip install + connectivity checks
│   └── mcp-setup-bin.sh        # MCP auto-config (installed to PATH as mcp-setup)
│
├── agent-config/               # Version-controlled agent config source
│   ├── settings.json.template  # Claude Code settings with {{PLACEHOLDER}} tokens
│   ├── mcp-templates/          # MCP server templates
│   │   └── mcp-gateway.json
│   ├── skills/                 # Custom skills (copied to ~/.claude/skills/)
│   │   └── devcontainer/       # This skill
│   └── hooks/                  # Hooks (copied to ~/.claude/hooks/)
│       └── langfuse_hook.py    # Langfuse tracing hook
│
├── config.json                 # Master non-secret settings
├── config.example.json         # Schema reference with sensible defaults
├── secrets.example.json        # Credential schema reference
│
├── infra/                      # Langfuse + MCP gateway infrastructure
│   ├── docker-compose.yml      # 8-service stack
│   ├── .env                    # Generated credentials (gitignored)
│   ├── mcp/mcp.json            # MCP gateway server configuration
│   ├── scripts/                # generate-env.sh, validate-setup.sh, verification scripts
│   ├── hooks/                  # Standalone langfuse hook copy
│   └── settings-examples/      # Reference settings.json examples
│
├── .planning/                  # GSD project planning state
├── gitprojects/                # Working directory for repos developed in the sandbox
└── review/                     # Reviews, specs, external AI output
```

## Key Paths

| Path | Purpose |
|------|---------|
| `/workspace/config.json` | Master settings (firewall, langfuse, vscode, mcp) |
| `/workspace/secrets.json` | Credentials (Claude auth, Codex auth, API keys) — gitignored |
| `/workspace/agent-config/` | Version-controlled templates, skills, hooks |
| `/home/node/.claude/` | Container-local Claude config (generated at build time) |
| `/home/node/.codex/` | Codex CLI config and credentials |
| `/home/node/.codex/config.toml` | Codex config (file-based credential store) |
| `/home/node/.codex/auth.json` | Codex OAuth credentials (restored from secrets.json) |
| `/home/node/.claude/commands/gsd/` | GSD slash commands (~28 commands) |
| `/home/node/.claude/agents/gsd-*.md` | GSD specialized agents (11 agents) |
| `/home/node/.claude/hooks/langfuse_hook.py` | Langfuse tracing hook |
| `/home/node/.claude/settings.local.json` | Generated settings (Langfuse env, hooks) |
| `/home/node/.claude-api-env` | API key exports (sourced by .bashrc/.zshrc) |
| `/usr/local/bin/save-secrets` | Credential capture helper |
| `/usr/local/bin/init-firewall.sh` | Firewall script |
| `/usr/local/bin/mcp-setup` | MCP auto-config script |
| `/var/run/docker.sock` | Host Docker socket (bind-mounted) |
| `/commandhistory/` | Persistent shell history (Docker volume) |

## Ports

| Port | Service | Notes |
|------|---------|-------|
| **3052** | Langfuse Web UI | From container: `http://host.docker.internal:3052`. From host: `http://localhost:3052` |
| 3030 | Langfuse Worker | Internal async job processing |
| 5433 | PostgreSQL | Offset from 5432 to avoid collisions |
| 6379 | Redis | Cache + job queue |
| 8124 | ClickHouse | Analytics engine |
| **8811** | MCP Gateway | Model Context Protocol gateway (loopback-only) |
| 9090 | MinIO S3 | Object storage |
| 9091 | MinIO Console | Admin UI |
| 3000 | Dev App | Forwarded by devcontainer.json (silent) |
| 8787 | Dev App 2 | Forwarded by devcontainer.json (silent) |

## Environment Variables

### Set in devcontainer.json (containerEnv)

| Variable | Value | Purpose |
|----------|-------|---------|
| `NODE_OPTIONS` | `--max-old-space-size=4096` | 4GB Node.js heap |
| `POWERLEVEL9K_DISABLE_GITSTATUS` | `true` | Prevent slow git status in prompt |
| `LANGFUSE_HOST` | `http://host.docker.internal:3052` | Langfuse endpoint |
| `MCP_GATEWAY_URL` | `http://host.docker.internal:8811` | MCP gateway endpoint |

### Set in ~/.claude/settings.local.json (env)

| Variable | Value | Purpose |
|----------|-------|---------|
| `TRACE_TO_LANGFUSE` | `true` | Master switch for tracing hook |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-local-claude-code` | Auto-provisioned project key |
| `LANGFUSE_SECRET_KEY` | _(from secrets.json)_ | Generated by generate-env.sh |
| `LANGFUSE_HOST` | `http://host.docker.internal:3052` | Langfuse API endpoint |

### Set via ~/.claude-api-env (sourced by shell)

| Variable | Source | Purpose |
|----------|--------|---------|
| `OPENAI_API_KEY` | `secrets.json → api_keys.openai` | For OpenAI-compatible agents |
| `GOOGLE_API_KEY` | `secrets.json → api_keys.google` | For Google AI agents |

## Installed Tools

| Category | Tools |
|----------|-------|
| **Runtime** | Node.js 20, Python 3.11, npm 10, zsh 5.9 |
| **Shell** | Oh-My-Zsh, Powerlevel10k theme, fzf, plugins: git + fzf |
| **VCS** | Git 2.39, GitHub CLI (gh), git-delta 0.18.2 |
| **Docker** | Docker CLI 29.2, Docker Compose v2 |
| **Network** | curl, wget, iptables, ipset, iproute2, dnsutils, aggregate |
| **Editors** | nano (default), vim |
| **Utilities** | jq, fzf, unzip, man-db, procps, less |
| **Python** | langfuse, openai, opentelemetry-api, httpx |
| **npm global** | get-shit-done-cc, claude (latest), @openai/codex (latest) |

## Shell Shortcuts

| Command | Action |
|---------|--------|
| `claude` | Runs with bypassPermissions by default (set in global settings.json) |
| `clauder` | Alias for `claude --resume` |
| `codex` | OpenAI Codex CLI — agentic coding with GPT-5.3-Codex |
| `codexr` | Alias for `codex --resume` |
| `save-secrets` | Capture live credentials to secrets.json |
| `mcp-setup` | Regenerate .mcp.json and health-check MCP gateway |

## Hooks

| Event | Script | Purpose |
|-------|--------|---------|
| **Stop** | `python3 /home/node/.claude/hooks/langfuse_hook.py` | Send conversation traces to Langfuse |
| **SessionStart** | `node /home/node/.claude/hooks/gsd-check-update.js` | Check for GSD framework updates |
| **StatusLine** | `node /home/node/.claude/hooks/gsd-statusline.js` | Show GSD state in terminal status line |

## Firewall

The iptables-based firewall (`init-firewall.sh`) runs on every container start. Default policy is **DROP** — only whitelisted domains are reachable.

Core domains (30, always included): Anthropic, GitHub, npm, PyPI, Debian, VS Code Marketplace, Cloudflare, Google Storage, OpenAI (API, Auth, Platform, ChatGPT), Google AI API.

Extra domains from `config.json → firewall.extra_domains` are appended.

To temporarily allow a blocked domain:

```bash
IP=$(dig +short example.com | tail -1)
sudo iptables -I OUTPUT -d "$IP" -j ACCEPT
```

To permanently add: edit `config.json → firewall.extra_domains` and rebuild.

## Mounts & Volumes

| Source | Target | Type | Purpose |
|--------|--------|------|---------|
| Host Docker socket | `/var/run/docker.sock` | Bind | Docker-outside-of-Docker |
| `claude-code-bashhistory-*` | `/commandhistory` | Volume | Shell history persists across rebuilds |
| Workspace | `/workspace` | Bind | Delegated consistency |

Note: No `~/.claude` bind mount. All Claude config is generated container-locally by `install-agent-config.sh`.

## Lifecycle Commands

### postCreateCommand (first build only)

1. `setup-container.sh` — Docker socket perms, git config
2. `install-agent-config.sh` — Reads config.json + secrets.json, generates all runtime config, installs skills/hooks/commands, installs GSD framework

### postStartCommand (every start)

1. `init-firewall.sh` — iptables whitelist
2. Git trust + line ending config
3. `setup-network-checks.sh` — Langfuse pip install + connectivity checks
4. `init-gsd.sh` — GSD command check
5. `mcp-setup` — Regenerate .mcp.json + gateway health check

## Rebuild Behavior

Rebuilding the dev container does NOT affect the sidecar stack (Langfuse runs on host Docker engine, data in named volumes). If `secrets.json` contains credentials, they are automatically restored on rebuild by `install-agent-config.sh`. Run `save-secrets` before rebuilding to capture current credentials.

## Docker Run Capabilities

- `NET_ADMIN` + `NET_RAW` — required for iptables firewall
- `--add-host=host.docker.internal:host-gateway` — enables host resolution

## Permissions

- **Node user:** passwordless sudo (`NOPASSWD:ALL`)
- **Docker socket:** `chmod 666` applied on create

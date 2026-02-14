# Claude Code Sandbox

A VS Code Dev Container environment purpose-built for Claude Code development. Pairs Claude Code with a self-hosted [Langfuse](https://langfuse.com) observability stack, an [MCP gateway](https://github.com/docker/mcp-gateway), custom skills, and a network firewall — all running as sibling containers via Docker-outside-of-Docker. Every Claude conversation is automatically traced and viewable in a local dashboard.

> **Codex:** Place reviews, suggestions, specs, and plans in [`docs/`](docs/). See [`docs/README.md`](docs/README.md) for the index.

## Architecture Overview

```
Windows Host (WSL2)
 |
 ├── VS Code ──────────────────────────────────────────────────┐
 |                                                             |
 |   Dev Container (Debian/Node 20)                            |
 |   ├── Claude Code CLI + Custom Skills (aa-fullstack, etc.)  |
 |   ├── GSD framework         (get-shit-done-cc)              |
 |   ├── langfuse_hook.py       (Stop hook → sends traces)     |
 |   ├── gsd-statusline.js      (terminal status line)         |
 |   ├── init-firewall.sh       (iptables domain whitelist)    |
 |   └── /var/run/docker.sock   (bind-mounted from host)       |
 |                                                             |
 |   Sidecar Stack (Docker-outside-of-Docker)                  |
 |   ├── langfuse-web          :3052 → :3000                   |
 |   ├── langfuse-worker       :3030                           |
 |   ├── docker-mcp-gateway    :8811                           |
 |   ├── postgres              :5433 → :5432                   |
 |   ├── clickhouse            :8124 → :8123                   |
 |   ├── redis                 :6379                           |
 |   └── minio                 :9090 → :9000                   |
 └─────────────────────────────────────────────────────────────┘
```

The Dev Container uses the **host's Docker engine** via a bind-mounted `/var/run/docker.sock`. The Langfuse stack and MCP gateway run as sibling containers managed by Docker Compose, not nested inside the dev container. Connectivity between the container and the Windows host is bridged through `host.docker.internal`.

---

## Quick Start

### Prerequisites

- **Windows** with WSL2 enabled
- **Docker Desktop** running on the Windows host
- **VS Code** with the Dev Containers extension

### 1. Open the Dev Container

Via the command palette (`Ctrl+Shift+P`):

- **`Dev Containers: Open Folder in Container...`** — opens a local folder and builds the container from scratch
- **`Dev Containers: Reopen in Container`** — reopens the current folder inside an existing container

If you open the folder locally first, VS Code will detect `.devcontainer/devcontainer.json` and show a prompt offering to reopen in the container.

On first build, the `postCreateCommand` runs `.devcontainer/setup-container.sh`, which:

- Grants Docker socket access (`chmod 666 /var/run/docker.sock`)
- Applies git identity from host-provided env vars (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`)

On every start (including rebuilds), `postStartCommand` now runs in this order:

1. `init-firewall.sh`
2. Git trust + line ending config (`safe.directory`, `core.autocrlf`)
3. `.devcontainer/setup-network-checks.sh` (Langfuse pip install + host/Langfuse reachability checks)
4. `.devcontainer/init-gsd.sh` (installs GSD slash commands if missing)
5. `mcp-setup` (regenerates `/workspace/.mcp.json` and health-checks MCP gateway)

This ordering avoids first-create race conditions where network checks run before firewall rules are active.

### 2. Start the Langfuse Stack

If this is your first time, generate credentials first:

```bash
cd /workspace/claudehome/langfuse-local
./scripts/generate-env.sh        # Interactive — creates .env with random secrets
sudo docker compose up -d        # Starts all 8 services
```

Wait 30-60 seconds for initialization, then verify:

```bash
curl http://host.docker.internal:3052/api/public/health
```

A `200` response means Langfuse is ready.

### 3. Verify the Langfuse UI

Open in your browser on the **Windows host**:

```
http://localhost:3052
```

Log in with the email and password you chose during `generate-env.sh`.

### 4. Configure Claude Code Tracing

Your `~/.claude/settings.json` needs the Langfuse hook registered. Use the example at `claudehome/langfuse-local/settings-examples/global-settings.json` as a reference:

```json
{
  "env": {
    "TRACE_TO_LANGFUSE": "true",
    "LANGFUSE_PUBLIC_KEY": "pk-lf-local-claude-code",
    "LANGFUSE_SECRET_KEY": "<your secret key from .env>",
    "LANGFUSE_HOST": "http://host.docker.internal:3052"
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 /home/node/.claude/hooks/langfuse_hook.py"
          }
        ]
      }
    ]
  }
}
```

The hook fires after every assistant response (the `Stop` event matcher). It reads Claude's transcript files from `~/.claude/projects/`, parses conversation turns, and sends structured traces to Langfuse.

### 5. Initialize a GSD Project (Optional)

Once inside a Claude Code session, run:

```
/gsd:new-project
```

This creates a `.planning/` directory with structured project files (`PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json`). GSD breaks work into atomic tasks sized for fresh context windows, using specialized sub-agents (planner, executor, verifier, researcher).

See `/gsd:help` for the full command list.

### 6. Test End-to-End

1. Start a Claude Code session: `claude`
2. Send any prompt
3. Check traces at `http://localhost:3052` — they appear within seconds

---

## Shell Shortcuts

Defined as shell commands available on `PATH` (plus aliases for Claude launchers):

| Command     | Action                                                                       |
| ----------- | ---------------------------------------------------------------------------- |
| `claudey`   | `cd /workspace/claudehome && claude --dangerously-skip-permissions`          |
| `claudeyr`  | `cd /workspace/claudehome && claude --dangerously-skip-permissions --resume` |
| `mcp-setup` | Regenerates `/workspace/.mcp.json` and health-checks the MCP gateway        |

Both accept extra arguments (e.g. `claudey -p "do something"`). Claude Code is always launched from `/workspace/claudehome` so it picks up the project-level `CLAUDE.md` and `.claude/settings.local.json`.

---

## Custom Skills

Skills are installed at `/workspace/claudehome/.claude/skills/` and provide domain-specific knowledge to Claude Code sessions.

### aa-fullstack

Full-stack development skill for the Adventure Alerts project. Covers:

- **Frontend:** Next.js (App Router), React, Mantine UI, Tailwind CSS
- **Backend:** Cloudflare Workers, Hono, Durable Objects
- **Database:** Cloudflare D1, Drizzle ORM
- **Architecture:** Edge-first monorepo with npm workspaces (`apps/`, `packages/`)
- **Mobile:** Capacitor JS (planned)

Triggers on: React, Next.js, Mantine, Hono, Drizzle, Cloudflare Workers, D1, Durable Objects, full-stack development.

### aa-cloudflare

Cloudflare platform deployment skill with decision trees for compute, storage, AI/ML, networking, and security. Includes 40+ reference docs covering Workers, Pages, D1, KV, R2, Queues, Durable Objects, Containers, WAF, and more.

Triggers on: deploy, host, publish, or set up a project on Cloudflare.

---

## Hooks & Automation

Claude Code hooks are registered in `~/.claude/settings.json` and fire on specific lifecycle events.

| Event            | Hook                  | Purpose                                                         |
| ---------------- | --------------------- | --------------------------------------------------------------- |
| **Stop**         | `langfuse_hook.py`    | Sends conversation traces to local Langfuse after each response |
| **SessionStart** | `gsd-check-update.js` | Checks for GSD framework updates on session start               |
| **StatusLine**   | `gsd-statusline.js`   | Renders current GSD state in the terminal status line           |

---

## GSD Framework

[Get Shit Done](https://github.com/glittercowboy/get-shit-done) (v1.18.0) is a project management framework for Claude Code that breaks work into atomic tasks sized for fresh context windows.

**29 slash commands** organized by workflow stage:

- **Project init:** `/gsd:new-project`, `/gsd:new-milestone`, `/gsd:map-codebase`
- **Planning:** `/gsd:discuss-phase`, `/gsd:research-phase`, `/gsd:plan-phase`, `/gsd:list-phase-assumptions`
- **Execution:** `/gsd:execute-phase`, `/gsd:quick`, `/gsd:debug`
- **Verification:** `/gsd:verify-work`, `/gsd:audit-milestone`
- **Roadmap:** `/gsd:add-phase`, `/gsd:insert-phase`, `/gsd:remove-phase`, `/gsd:progress`
- **Session management:** `/gsd:pause-work`, `/gsd:resume-work`
- **Todos:** `/gsd:add-todo`, `/gsd:check-todos`

**11 specialized agents** (installed at `~/.claude/agents/gsd-*.md`):

| Agent                      | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| `gsd-planner`              | Plan phase execution with task decomposition |
| `gsd-executor`             | Execute tasks with state tracking            |
| `gsd-verifier`             | Verify phase goal completion                 |
| `gsd-debugger`             | Systematic debugging framework               |
| `gsd-phase-researcher`     | Research phase domain and constraints        |
| `gsd-project-researcher`   | Research full project requirements           |
| `gsd-research-synthesizer` | Synthesize research findings                 |
| `gsd-roadmapper`           | Create project roadmaps                      |
| `gsd-plan-checker`         | Verify plan completeness and quality         |
| `gsd-codebase-mapper`      | Systematically map codebases                 |
| `gsd-integration-checker`  | Validate component integration               |

---

## MCP Gateway

The Docker MCP Gateway (`docker/mcp-gateway:latest`) provides Model Context Protocol server access to Claude Code sessions.

- **Port:** `127.0.0.1:8811` (loopback-only)
- **Transport:** SSE between Claude Code and gateway; stdio between gateway and MCP servers
- **Gateway config:** `langfuse-local/mcp/mcp.json` (server definitions)
- **Client config:** `/workspace/.mcp.json` (generated by `mcp-setup`, git-ignored)
- **Current servers:** `@modelcontextprotocol/server-filesystem` (workspace root: `/workspace`)

### Auto-Configuration

On every container start, `postStartCommand` runs `mcp-setup`, which:

1. Generates `/workspace/.mcp.json` pointing to the gateway's SSE endpoint (`$MCP_GATEWAY_URL/sse`)
2. Polls the gateway health endpoint with a 30-second timeout (warns but doesn't block if unavailable)
3. Prints a summary with next steps

No manual MCP setup is required. Claude Code sessions started after container boot automatically pick up the gateway connection.

### Adding a Server

Example configurations for GitHub, PostgreSQL, and Brave Search are in [`langfuse-local/mcp/SERVERS.md`](claudehome/langfuse-local/mcp/SERVERS.md).

1. Copy a server entry into `langfuse-local/mcp/mcp.json` under `mcpServers`
2. Add any required env vars to `langfuse-local/.env`
3. Restart the gateway:
   ```bash
   cd /workspace/claudehome/langfuse-local && sudo docker compose restart docker-mcp-gateway
   ```
4. Re-run `mcp-setup` (regenerates `.mcp.json` and health-checks)
5. Restart Claude Code session

---


## Firewall & Docker Socket Security Notes

- The firewall is IPv4+IPv6 default-deny and allowlist-based, with domain names resolved to IPs at runtime.
- CDN-backed domains can rotate IPs; to refresh domain IPs without restarting the container run:
  ```bash
  sudo /usr/local/bin/refresh-firewall-dns.sh
  ```
- Project-specific firewall domains are configured in `.devcontainer/firewall-domains.conf`.
- `setup-container.sh` uses `chmod 666 /var/run/docker.sock` for Docker-outside-of-Docker convenience. This grants any process in the dev container full control of the host Docker daemon; treat the container as highly privileged.

---

## VS Code Extensions

Installed via `devcontainer.json`:

| Extension                                          | Purpose                                             |
| -------------------------------------------------- | --------------------------------------------------- |
| `dbaeumer.vscode-eslint`                           | JavaScript/TypeScript linting                       |
| `esbenp.prettier-vscode`                           | Code formatting (default formatter, format-on-save) |
| `cloudflare.cloudflare-workers-bindings-extension` | Cloudflare Workers development                      |
| `qwtel.sqlite-viewer`                              | SQLite database inspection                          |
| `bradlc.vscode-tailwindcss`                        | Tailwind CSS IntelliSense                           |

VS Code is configured with format-on-save, Prettier as default formatter, ESLint auto-fix on save, and zsh as the default terminal.

---

## The "Golden State" Configuration

These are the canonical ports, IPs, and paths that the system expects. If any of these drift, things break.

### Ports

| Port     | Service         | Binding                  | Notes                                                                                                   |
| -------- | --------------- | ------------------------ | ------------------------------------------------------------------------------------------------------- |
| **3052** | Langfuse Web UI | `127.0.0.1:3052 → :3000` | The canonical port. Ports 3050/3051 are avoided due to persistent zombie process collisions on Windows. |
| 3030     | Langfuse Worker | `127.0.0.1:3030 → :3030` | Internal worker process                                                                                 |
| 5433     | PostgreSQL      | `127.0.0.1:5433 → :5432` | Offset from default to avoid collisions                                                                 |
| 6379     | Redis           | `127.0.0.1:6379 → :6379` | Default port                                                                                            |
| 8124     | ClickHouse HTTP | `127.0.0.1:8124 → :8123` | Analytics engine                                                                                        |
| **8811** | MCP Gateway     | `127.0.0.1:8811 → :8811` | Model Context Protocol gateway                                                                          |
| 9090     | MinIO S3        | `127.0.0.1:9090 → :9000` | Object storage for media/exports                                                                        |
| 9091     | MinIO Console   | `127.0.0.1:9091 → :9001` | MinIO admin UI                                                                                          |

Dev Container forwarded ports (via `devcontainer.json`):

| Port | Label     | Purpose                   |
| ---- | --------- | ------------------------- |
| 3000 | Dev App   | Development application   |
| 8787 | Dev App 2 | Secondary dev application |

### Network Addresses

| Context                            | Langfuse URL                       |
| ---------------------------------- | ---------------------------------- |
| From the **Windows host** browser  | `http://localhost:3052`            |
| From **inside the Dev Container**  | `http://host.docker.internal:3052` |
| `NEXTAUTH_URL` (in docker-compose) | `http://localhost:3052`            |

### Key Paths

| Path                                                | Purpose                                                               |
| --------------------------------------------------- | --------------------------------------------------------------------- |
| `/workspace`                                        | Workspace root (bind-mounted from Windows)                            |
| `/workspace/claudehome/`                            | Claude Code home — Claude always launches from here                   |
| `/workspace/claudehome/.claude/skills/`             | Custom skills (aa-fullstack, aa-cloudflare)                           |
| `/workspace/claudehome/.claude/settings.local.json` | Project-level Claude Code settings overrides                          |
| `/workspace/claudehome/langfuse-local/`             | Langfuse + MCP gateway Docker Compose stack                           |
| `/workspace/claudehome/langfuse-local/mcp/`         | MCP gateway server configuration                                      |
| `/workspace/claudehome/.planning/`                  | GSD project planning files (PROJECT.md, ROADMAP.md, phases, research) |
| `/workspace/claudehome/scripts/`                    | Validation and verification scripts                                   |
| `/workspace/gitprojects/`                           | Working directory for repositories developed in the sandbox           |
| `/home/node/.claude/`                               | Claude Code config dir (bind-mounted from `%USERPROFILE%\.claude`)    |
| `/home/node/.claude/commands/gsd/`                  | GSD slash commands (29 commands, installed by `init-gsd.sh`)          |
| `/home/node/.claude/agents/`                        | GSD specialized agents (11 agent definitions)                         |
| `/home/node/.claude/hooks/langfuse_hook.py`         | The tracing hook script                                               |
| `/home/node/.claude/hooks/gsd-check-update.js`      | GSD update checker (SessionStart hook)                                |
| `/home/node/.claude/hooks/gsd-statusline.js`        | GSD terminal status line                                              |
| `/home/node/.claude/settings.json`                  | Claude Code settings (hook registration + env vars)                   |
| `/home/node/.claude/state/langfuse_hook.log`        | Hook execution log                                                    |
| `/home/node/.claude/state/langfuse_state.json`      | Incremental processing state (tracks last-processed line per session) |
| `/var/run/docker.sock`                              | Host Docker socket (bind-mounted)                                     |
| `/usr/local/bin/init-firewall.sh`                   | Firewall whitelist script (runs on `postStartCommand`)                |
| `/usr/local/bin/mcp-setup`                          | MCP auto-config script (runs on `postStartCommand`)                   |
| `/workspace/.mcp.json`                              | Claude Code MCP client config (generated by `mcp-setup`, git-ignored) |

### Environment Variables

Set via `devcontainer.json` → `containerEnv`:

| Variable                         | Value                              | Purpose                                         |
| -------------------------------- | ---------------------------------- | ----------------------------------------------- |
| `CLAUDE_CONFIG_DIR`              | `/home/node/.claude`               | Claude Code config location                     |
| `NODE_OPTIONS`                   | `--max-old-space-size=4096`        | Increase Node.js memory limit                   |
| `POWERLEVEL9K_DISABLE_GITSTATUS` | `true`                             | Disable slow git status in Powerlevel10k prompt |
| `LANGFUSE_HOST`                  | `http://host.docker.internal:3052` | Langfuse API endpoint (container-level default) |
| `MCP_GATEWAY_URL`                | `http://host.docker.internal:8811` | MCP gateway endpoint (used by `mcp-setup`)      |

Set via `~/.claude/settings.json` → `env`:

| Variable              | Value                              | Purpose                                              |
| --------------------- | ---------------------------------- | ---------------------------------------------------- |
| `TRACE_TO_LANGFUSE`   | `true`                             | Master switch — hook exits immediately if not `true` |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-local-claude-code`          | Auto-provisioned project key                         |
| `LANGFUSE_SECRET_KEY` | _(from .env)_                      | Generated by `generate-env.sh`                       |
| `LANGFUSE_HOST`       | `http://host.docker.internal:3052` | Langfuse API endpoint from within the container      |

---

## Firewall

The dev container runs an iptables-based whitelist firewall (`init-firewall.sh`) that executes on every container start via `postStartCommand`. The default policy is **DROP** — only explicitly whitelisted domains are reachable.

### Whitelisted Domains

| Category               | Domains                                                                                                                |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **VCS**                | `github.com`, `api.github.com`, `objects.githubusercontent.com` + GitHub IP ranges (fetched dynamically)               |
| **Package Registries** | `registry.npmjs.org`, `deb.debian.org`, `security.debian.org`, `pypi.python.org`                                       |
| **Claude/Anthropic**   | `api.anthropic.com`, `statsig.anthropic.com`, `statsig.com`, `sentry.io`                                               |
| **IDE/Tools**          | `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com`, `json.schemastore.org` |
| **Cloud Services**     | `api.cloudflare.com`, `storage.googleapis.com`                                                                         |
| **Internal**           | `host.docker.internal`, `172.16.0.0/12` (Docker bridge), `192.168.65.0/24` (Docker Desktop)                            |

### Network Policies

- **Loopback:** full accept on `lo`
- **DNS:** allow UDP/TCP port 53
- **Stateful:** allow ESTABLISHED/RELATED return traffic
- **Default:** DROP all other inbound/forward/outbound
- **Rejection:** ICMP admin-prohibited for debugging

To temporarily allow a blocked domain:

```bash
IP=$(dig +short example.com | tail -1)
sudo iptables -I OUTPUT -d "$IP" -j ACCEPT
```

To permanently add a domain, edit `.devcontainer/init-firewall.sh`.

---

## Installed Tools

### Container Image (Dockerfile)

| Category         | Tools                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| **Runtime**      | Node.js 20, Python 3.11, npm 10, zsh 5.9                                    |
| **Shell**        | Oh-My-Zsh with Powerlevel10k theme, fzf fuzzy finder, plugins: git + fzf    |
| **VCS**          | Git 2.39, GitHub CLI (gh) 2.23, git-delta 0.18.2 (syntax-highlighted diffs) |
| **Docker**       | Docker CLI 29.2, Docker Compose v2 plugin                                   |
| **Network**      | curl, wget, iptables, ipset, iproute2, dnsutils, aggregate                  |
| **Editors**      | nano (default), vim                                                         |
| **Utilities**    | jq, fzf, unzip, man-db, procps, less                                        |
| **Python**       | langfuse 3.14, openai 2.20, opentelemetry-api 1.39, httpx 0.28              |
| **npm (global)** | `get-shit-done-cc` 1.18.0, `claude` (latest)                                |

### Bind Mounts & Volumes

| Mount                             | Target                 | Type   | Purpose                                     |
| --------------------------------- | ---------------------- | ------ | ------------------------------------------- |
| Host `%USERPROFILE%\.claude`      | `/home/node/.claude`   | Bind   | Claude Code config persists across rebuilds |
| Host Docker socket                | `/var/run/docker.sock` | Bind   | Docker-outside-of-Docker                    |
| `claude-code-bashhistory-*`       | `/commandhistory`      | Volume | Shell history persists across rebuilds      |
| Workspace (from Windows via WSL2) | `/workspace`           | Bind   | Delegated consistency for WSL2 performance  |

### Docker Run Capabilities

- `NET_ADMIN` + `NET_RAW` — required for iptables firewall
- `--add-host=host.docker.internal:host-gateway` — enables host resolution

---

## Maintenance

### Rebuilding the Dev Container

Rebuilding the container (e.g., after Dockerfile changes) **does not** affect the Langfuse stack because:

- Langfuse runs as sibling containers on the host Docker engine, not inside the dev container
- Langfuse data is persisted in Docker named volumes (`langfuse_postgres_data`, `langfuse_clickhouse_data`, etc.)
- Your `.claude/` directory is bind-mounted from the Windows host, so settings and hook state survive rebuilds

However, rebuilding **does** re-run `postCreateCommand` (`.devcontainer/setup-container.sh` and `.devcontainer/init-gsd.sh`), which reinstalls the `langfuse` Python package and ensures GSD slash commands are present. This is intentional — the Python package is installed into the container's system Python and is lost on rebuild. GSD commands persist across rebuilds because they're installed into `~/.claude/`, which is bind-mounted from the Windows host.

**To rebuild**, use the command palette (`Ctrl+Shift+P`):

- **`Dev Containers: Rebuild Container`** — rebuilds the image and recreates the container in place
- **`Dev Containers: Rebuild Container Without Cache`** — full rebuild, ignoring Docker layer cache (use after Dockerfile base image changes)

VS Code may also show a popup when it detects changes to `.devcontainer/` files, offering to rebuild automatically.

The Langfuse stack keeps running throughout — it's on the host Docker engine, not inside the container.

### Updating the Langfuse Stack

```bash
cd /workspace/claudehome/langfuse-local
sudo docker compose pull          # Pull latest images
sudo docker compose up -d         # Recreate with new images
```

Data is preserved across upgrades via the named volumes.

### Viewing Hook Logs

```bash
# Recent hook activity
tail -50 ~/.claude/state/langfuse_hook.log

# Enable verbose debug logging
export CC_LANGFUSE_DEBUG=true
```

### Running the Validation Script

```bash
cd /workspace/claudehome/langfuse-local

# Pre-flight (check prerequisites)
./scripts/validate-setup.sh

# Post-setup (check everything is wired up)
./scripts/validate-setup.sh --post
```

---

## Troubleshooting

### Port 3052 is blocked / Langfuse unreachable

This is the most common issue. WSL2's networking layer (HNS - Host Network Service) can enter a broken state where port forwarding silently fails. Symptoms:

- `curl http://host.docker.internal:3052` times out from inside the container
- `http://localhost:3052` shows nothing in the browser
- `docker compose ps` shows all containers as healthy

**The fix (the "Emergency Protocol"):**

1. Close VS Code
2. Open **PowerShell as Administrator** on Windows:
   ```powershell
   wsl --shutdown
   Restart-Service hns
   ```
3. Wait 10 seconds, then reopen VS Code and the dev container
4. Verify: `curl http://host.docker.internal:3052/api/public/health`

### Traces not appearing in Langfuse

1. **Check the hook log:**

   ```bash
   cat ~/.claude/state/langfuse_hook.log
   ```

   Look for `ERROR` lines.

2. **Verify tracing is enabled:**

   ```bash
   echo $TRACE_TO_LANGFUSE   # Should print: true
   ```

3. **Verify Langfuse is reachable from the container:**

   ```bash
   curl http://host.docker.internal:3052/api/public/health
   ```

4. **Verify API keys match:**
   - The `LANGFUSE_SECRET_KEY` in `~/.claude/settings.json` must match `LANGFUSE_INIT_PROJECT_SECRET_KEY` in `/workspace/claudehome/langfuse-local/.env`

5. **Check the hook can import langfuse:**
   ```bash
   python3 -c "import langfuse; print(langfuse.__version__)"
   ```
   If this fails, reinstall: `python3 -m pip install langfuse --break-system-packages`

### `pip install` fails with "externally-managed-environment"

Debian's PEP 668 restricts system-wide pip installs. The `--break-system-packages` flag is required:

```bash
python3 -m pip install langfuse --break-system-packages
```

This is already handled by `.devcontainer/setup-container.sh` on container creation.

### Git "dubious ownership" errors

The workspace is bind-mounted from Windows into a Linux container, which causes UID mismatches. The fix is applied automatically by both `postStartCommand` and `.devcontainer/setup-container.sh`:

```bash
git config --global --add safe.directory '*'
```

### Docker socket permission denied

If `docker compose` commands fail with permission errors:

```bash
sudo chmod 666 /var/run/docker.sock
```

This is also handled automatically by `.devcontainer/setup-container.sh`.

---

## How the Tracing Hook Works

The hook (`langfuse_hook.py`) is registered as a Claude Code **Stop** hook — it runs after every assistant response.

**Flow:**

1. Claude Code emits a `Stop` event after each response
2. The hook checks `TRACE_TO_LANGFUSE=true` (exits immediately if not set)
3. Finds the most recently modified transcript file in `~/.claude/projects/<project>/`
4. Reads the `.jsonl` transcript and parses new messages since the last run (tracked via `langfuse_state.json`)
5. Groups messages into conversation turns: `user → assistant → tool calls → tool results`
6. Creates a Langfuse trace per turn with:
   - A **generation** span for Claude's response (includes model name)
   - A **tool span** for each tool invocation (name, input, output)
7. Applies secret redaction (API keys, passwords, tokens) before sending
8. Flushes traces to the local Langfuse instance

The hook is designed to be **non-blocking**: all errors exit with code 0 so Claude Code is never interrupted.

---

## Project Structure

```
/workspace/
├── .devcontainer/
│   ├── Dockerfile              # Dev container image (Node 20 + Claude Code + GSD + Docker CLI)
│   ├── devcontainer.json       # Container config, mounts, ports, lifecycle hooks
│   ├── init-firewall.sh        # iptables domain whitelist (runs on postStartCommand)
│   ├── init-gsd.sh             # GSD slash command installer (runs on postCreateCommand)
│   ├── mcp-setup.sh            # MCP setup shell function (appended to .bashrc/.zshrc)
│   ├── mcp-setup-bin.sh        # Standalone mcp-setup script (installed to /usr/local/bin)
│   └── setup-container.sh      # Post-create setup (pip install, git config, health checks)
│
├── .vscode/
│   └── settings.json           # Git multi-repo scanning configuration
│
├── claudehome/                 # Claude Code home — always launch from here
│   ├── CLAUDE.md               # Project-level Claude Code instructions
│   ├── .claude/
│   │   ├── settings.local.json # Local Claude Code settings overrides
│   │   └── skills/
│   │       ├── aa-fullstack/   # Adventure Alerts full-stack skill
│   │       └── aa-cloudflare/  # Cloudflare platform deployment skill
│   ├── .planning/              # GSD project planning (phases, research, state)
│   ├── langfuse-local/
│   │   ├── docker-compose.yml  # Langfuse + MCP gateway stack (8 services)
│   │   ├── .env                # Generated credentials (git-ignored)
│   │   ├── mcp/
│   │   │   ├── mcp.json        # MCP gateway server configuration
│   │   │   └── SERVERS.md      # Example server configs (GitHub, PostgreSQL, Brave Search)
│   │   ├── scripts/
│   │   │   ├── generate-env.sh     # Interactive credential generator
│   │   │   └── validate-setup.sh   # Pre-flight and post-setup validator
│   │   └── settings-examples/
│   │       ├── global-settings.json    # Reference settings.json for tracing
│   │       └── project-opt-out.json    # Example: disable tracing per-project
│   └── scripts/                # Verification scripts (MCP, gateway connectivity)
│
├── gitprojects/                # Working directory for repos developed in the sandbox
│   └── adventure-alerts/       # Hybrid trip-planning & booking intelligence engine
│
└── docs/                       # Home for reviews, suggestions, specs and plans by Codex
```

### Git Multi-Repo Support

VS Code scans multiple repositories within the workspace (configured in `.vscode/settings.json`):

- `/workspace/` — root repo (this sandbox)
- `/workspace/gitprojects/adventure-alerts/` — Adventure Alerts monorepo
- `/workspace/gitprojects/claude-aimtrainer/` — (configured, not yet cloned)

---

## Acknowledgments

### Infrastructure

- **Dev Container** — Modified from the official [Claude Code Dev Container](https://github.com/anthropics/claude-code) reference configuration, with additions for Docker-outside-of-Docker, the iptables firewall, and WSL2 bridge networking.
- **Langfuse Observability Stack** — Built from Doneyli de Jesus's [claude-code-langfuse-template](https://github.com/doneyli/claude-code-langfuse-template), as described in his Signal Over Noise newsletter post: [I Built My Own Observability for Claude Code](https://doneyli.substack.com/p/i-built-my-own-observability-for). The hook script, Docker Compose stack, and credential generation tooling in `claudehome/langfuse-local/` originate from that template, adapted here for the containerized WSL2 environment (port 3052, `host.docker.internal` routing, PEP 668 workaround).

### Skills

- **aa-cloudflare** — Forked from [cloudflare-deploy](https://github.com/anthropics/awesome-claude-skills) by OpenAI/skills (Apache-2.0). Original decision trees and product index retained; extended with Hono, Drizzle ORM + D1, Durable Object alarm scheduling, and monorepo deployment patterns.
- **aa-fullstack** — Forked from [fullstack-developer](https://github.com/anthropics/awesome-claude-skills) by Shubhamsaboo/awesome-llm-apps (MIT). Substantially modified to target the Adventure Alerts technology stack and conventions.

# Claude Code Sandbox

A VS Code Dev Container environment that pairs Claude Code with a self-hosted [Langfuse](https://langfuse.com) observability stack. Every Claude conversation is automatically traced — prompts, responses, tool calls — and viewable in a local dashboard.

## Architecture Overview

```
Windows Host (WSL2)
 |
 ├── VS Code ──────────────────────────────────────────────┐
 |                                                         |
 |   Dev Container (Debian/Node 20)                        |
 |   ├── Claude Code CLI                                   |
 |   ├── langfuse_hook.py  (Stop hook → sends traces)      |
 |   ├── init-firewall.sh  (iptables domain whitelist)     |
 |   └── /var/run/docker.sock  (bind-mounted from host)    |
 |                                                         |
 |   Sidecar Stack (Docker-outside-of-Docker)              |
 |   ├── langfuse-web       :3052 → :3000                  |
 |   ├── langfuse-worker    :3030                          |
 |   ├── postgres           :5433 → :5432                  |
 |   ├── clickhouse         :8124 → :8123                  |
 |   ├── redis              :6379                          |
 |   └── minio              :9090 → :9000                  |
 └─────────────────────────────────────────────────────────┘
```

The Dev Container uses the **host's Docker engine** via a bind-mounted `/var/run/docker.sock`. The Langfuse stack runs as sibling containers managed by Docker Compose, not nested inside the dev container. Connectivity between the container and the Windows host is bridged through `host.docker.internal`.

---

## Quick Start

### Prerequisites

- **Windows** with WSL2 enabled
- **Docker Desktop** running on the Windows host
- **VS Code** with the Dev Containers extension

### 1. Open the Dev Container

```
code .
```

VS Code will detect `.devcontainer/devcontainer.json` and prompt to reopen in the container. On first build, the `postCreateCommand` runs `setup-container.sh`, which:

- Whitelists all git directories (`git config --global --add safe.directory '*'`)
- Sets line endings for WSL compatibility (`core.autocrlf input`)
- Grants Docker socket access (`chmod 666 /var/run/docker.sock`)
- Installs the Langfuse Python SDK (`python3 -m pip install langfuse --break-system-packages`)
- Verifies connectivity to `host.docker.internal`
- Health-checks the Langfuse API on port 3052

### 2. Start the Langfuse Stack

If this is your first time, generate credentials first:

```bash
cd /workspace/claudehome/langfuse-local
./scripts/generate-env.sh        # Interactive — creates .env with random secrets
sudo docker compose up -d        # Starts all 6 services
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

### 5. Test End-to-End

1. Start a Claude Code session: `claude`
2. Send any prompt
3. Check traces at `http://localhost:3052` — they appear within seconds

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
| 9090     | MinIO S3        | `127.0.0.1:9090 → :9000` | Object storage for media/exports                                                                        |
| 9091     | MinIO Console   | `127.0.0.1:9091 → :9001` | MinIO admin UI                                                                                          |

### Network Addresses

| Context                            | Langfuse URL                       |
| ---------------------------------- | ---------------------------------- |
| From the **Windows host** browser  | `http://localhost:3052`            |
| From **inside the Dev Container**  | `http://host.docker.internal:3052` |
| `NEXTAUTH_URL` (in docker-compose) | `http://localhost:3052`            |

### Key Paths

| Path                                           | Purpose                                                                    |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| `/workspace`                                   | Workspace root (bind-mounted from Windows)                                 |
| `/workspace/claudehome/langfuse-local/`        | Langfuse Docker Compose stack + hook source                                |
| `/workspace/gitprojects/`                      | Working directory for repositories cloned and developed within the sandbox |
| `/home/node/.claude/`                          | Claude Code config dir (bind-mounted from `%USERPROFILE%\.claude`)         |
| `/home/node/.claude/hooks/langfuse_hook.py`    | The tracing hook script                                                    |
| `/home/node/.claude/settings.json`             | Claude Code settings (hook registration + env vars)                        |
| `/home/node/.claude/state/langfuse_hook.log`   | Hook execution log                                                         |
| `/home/node/.claude/state/langfuse_state.json` | Incremental processing state (tracks last-processed line per session)      |
| `/var/run/docker.sock`                         | Host Docker socket (bind-mounted)                                          |
| `/usr/local/bin/init-firewall.sh`              | Firewall whitelist script (runs on `postStartCommand`)                     |

### Environment Variables

Set via `devcontainer.json` → `containerEnv`:

| Variable            | Value                       | Purpose                       |
| ------------------- | --------------------------- | ----------------------------- |
| `CLAUDE_CONFIG_DIR` | `/home/node/.claude`        | Claude Code config location   |
| `NODE_OPTIONS`      | `--max-old-space-size=4096` | Increase Node.js memory limit |

Set via `~/.claude/settings.json` → `env`:

| Variable              | Value                              | Purpose                                              |
| --------------------- | ---------------------------------- | ---------------------------------------------------- |
| `TRACE_TO_LANGFUSE`   | `true`                             | Master switch — hook exits immediately if not `true` |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-local-claude-code`          | Auto-provisioned project key                         |
| `LANGFUSE_SECRET_KEY` | _(from .env)_                      | Generated by `generate-env.sh`                       |
| `LANGFUSE_HOST`       | `http://host.docker.internal:3052` | Langfuse API endpoint from within the container      |

---

## Maintenance

### Rebuilding the Dev Container

Rebuilding the container (e.g., after Dockerfile changes) **does not** affect the Langfuse stack because:

- Langfuse runs as sibling containers on the host Docker engine, not inside the dev container
- Langfuse data is persisted in Docker named volumes (`langfuse_postgres_data`, `langfuse_clickhouse_data`, etc.)
- Your `.claude/` directory is bind-mounted from the Windows host, so settings and hook state survive rebuilds

However, rebuilding **does** re-run `postCreateCommand` (`setup-container.sh`), which reinstalls the `langfuse` Python package. This is intentional — the package is installed into the container's system Python and is lost on rebuild.

**To rebuild without downtime:**

```bash
# Langfuse keeps running — it's on the host Docker, not in the container
# Just rebuild the dev container from VS Code:
#   Ctrl+Shift+P → "Dev Containers: Rebuild Container"
```

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

This is already handled by `setup-container.sh` on container creation.

### Git "dubious ownership" errors

The workspace is bind-mounted from Windows into a Linux container, which causes UID mismatches. The fix is applied automatically by both `postStartCommand` and `setup-container.sh`:

```bash
git config --global --add safe.directory '*'
```

### Docker socket permission denied

If `docker compose` commands fail with permission errors:

```bash
sudo chmod 666 /var/run/docker.sock
```

This is also handled automatically by `setup-container.sh`.

### Firewall blocking Langfuse or external services

The dev container runs an iptables-based firewall (`init-firewall.sh`) that whitelists specific domains (GitHub, npm, Anthropic API, PyPI, etc.) and blocks everything else. The firewall explicitly allows traffic to `host.docker.internal` and the Docker bridge subnet for Langfuse connectivity.

If a domain is blocked that shouldn't be, add it to the whitelist in `.devcontainer/init-firewall.sh` and rebuild, or manually allow it:

```bash
# Temporarily allow a domain
IP=$(dig +short example.com | tail -1)
sudo iptables -I OUTPUT -d "$IP" -j ACCEPT
```

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
│   ├── Dockerfile              # Dev container image (Node 20 + Claude Code + Docker CLI)
│   ├── devcontainer.json       # Container config, mounts, ports, lifecycle hooks
│   └── init-firewall.sh        # iptables domain whitelist (runs on postStartCommand)
├── setup-container.sh          # Post-create setup (pip install, git config, health checks)
├── claudehome/
│   ├── .claude/
│   │   └── settings.local.json # Local Claude Code settings overrides
│   └── langfuse-local/
│       ├── docker-compose.yml  # Langfuse stack (6 services)
│       ├── .env.example        # Credential template
│       ├── .env                # Generated credentials (git-ignored)
│       ├── hooks/
│       │   └── langfuse_hook.py    # The tracing hook
│       ├── scripts/
│       │   ├── generate-env.sh     # Interactive credential generator
│       │   └── validate-setup.sh   # Pre-flight and post-setup validator
│       └── settings-examples/
│           ├── global-settings.json    # Reference settings.json for tracing
│           └── project-opt-out.json    # Example: disable tracing per-project
└── gitprojects/                # Working directory for repos developed in the sandbox
```

---

## Acknowledgments

This sandbox stands on two foundations:

- **Dev Container** — Modified from the official [Claude Code Dev Container](https://github.com/anthropics/claude-code) reference configuration, with additions for Docker-outside-of-Docker, the iptables firewall, and WSL2 bridge networking.
- **Langfuse Observability Stack** — Built from Doneyli de Jesus's [claude-code-langfuse-template](https://github.com/doneyli/claude-code-langfuse-template), as described in his Signal Over Noise newsletter post: [I Built My Own Observability for Claude Code](https://doneyli.substack.com/p/i-built-my-own-observability-for). The hook script, Docker Compose stack, and credential generation tooling in `claudehome/langfuse-local/` originate from that template, adapted here for the containerized WSL2 environment (port 3052, `host.docker.internal` routing, PEP 668 workaround).

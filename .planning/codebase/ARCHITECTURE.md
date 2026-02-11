# Architecture

**Analysis Date:** 2026-02-10

## Pattern Overview

**Overall:** Multi-layer workspace architecture combining:
1. **Dev Container Environment** — Isolated Linux development sandbox with Docker-outside-of-Docker
2. **Observability Stack** — Self-hosted Langfuse instance for Claude Code session tracing
3. **Project Monorepos** — TypeScript/Node workspaces (git-tracked) for independent development
4. **Workspace Directories** — Specialized storage for configuration, projects, and documentation

**Key Characteristics:**
- **Isolation by Intent**: Dev container uses host's Docker engine via bind-mounted socket; Langfuse runs as sibling containers, not nested
- **Stop Hook Pattern**: Post-response observability via Python hook executed after Claude Code generates output
- **Monorepo Workspaces**: npm workspaces for shared types, APIs, and frontends within `adventure-alerts`
- **State Persistence**: Claude Code config and Langfuse state persists across container rebuilds via bind-mounted `.claude/` directory and named volumes
- **Firewall-Gated Access**: iptables whitelist on container startup restricts outbound domains (only approved services reachable)

## Layers

**Dev Container (Debian Linux):**
- Purpose: Isolated Claude Code execution environment with CLI tools, GSD framework, and Docker access
- Location: `.devcontainer/`
- Contains: Dockerfile, devcontainer.json, setup scripts, firewall rules
- Depends on: Host Docker engine (via `/var/run/docker.sock`), Windows WSL2 network bridge
- Used by: Claude Code CLI, GSD commands, script execution

**Langfuse Observability Stack:**
- Purpose: Self-hosted LLM observability — captures every Claude Code conversation as structured traces
- Location: `/workspace/claudehome/langfuse-local/`
- Contains: docker-compose.yml, Python hook script, credential generation, validation scripts
- Depends on: Host Docker engine, PostgreSQL, ClickHouse, Redis, MinIO, named volumes for persistence
- Used by: Hook script (post-response tracing), manual dashboard inspection

**Claude Code Hook Layer:**
- Purpose: Intercept Claude Code output and send structured conversation traces to Langfuse
- Location: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py`
- Contains: JSONL transcript parsing, session grouping, secret sanitization, Langfuse client calls
- Depends on: Claude Code transcript files at `~/.claude/projects/*/`, Langfuse Python SDK, state tracking
- Used by: Langfuse API ingestion, user dashboard inspection, conversation auditing

**Project Layer (Monorepos):**
- Purpose: Independent development environments for applications and libraries
- Location: `/workspace/gitprojects/adventure-alerts/` (primary active project)
- Contains: Package workspaces (apps/*, packages/*), TypeScript configs, shared types
- Depends on: Node.js, npm workspaces, TypeScript, framework-specific tools
- Used by: Frontend (Next.js), backend (Cloudflare Workers), database (Drizzle ORM)

**Configuration Layer:**
- Purpose: Machine-specific settings, secrets, and environment configuration
- Location: `/workspace/claudehome/.claude/` (local overrides), `.env` files (git-ignored), Docker Compose `.env`
- Contains: Claude Code settings.json, Langfuse credentials, database passwords, Git identity
- Depends on: `.env.example` templates, credential generation scripts
- Used by: Runtime initialization, hook execution, Docker services

## Data Flow

**Claude Code Session Tracing:**

1. User starts Claude Code session in dev container (`/workspace` bind-mounted)
2. Claude Code writes messages to `~/.claude/projects/<project-dir>/<session-id>.jsonl` (JSONL format, one message per line)
3. User sends prompt → Claude responds with text and/or tool calls
4. After Claude finishes response, **Stop hook** is triggered (registered in `~/.claude/settings.json`)
5. Hook (`langfuse_hook.py`) executes:
   - Finds most recently modified `.jsonl` file in projects directory
   - Parses new messages since last execution (tracked via `~/.claude/state/langfuse_state.json`)
   - Groups messages into conversation turns: `user → assistant → tool_calls → tool_results`
   - Sanitizes secrets (API keys, tokens, passwords) using regex patterns
   - Creates Langfuse trace with generation span (model info, timing) and nested tool spans
   - POSTs structured JSON to Langfuse API at `http://host.docker.internal:3052`
6. Langfuse API validates and stores in PostgreSQL (traces, sessions, metadata)
7. Background worker processes for ClickHouse analytics (dashboards, aggregations)
8. User views traces in Langfuse UI at `http://localhost:3052` (Windows host) or `http://host.docker.internal:3052` (container)

**State Management:**

- **Hook State**: `~/.claude/state/langfuse_state.json` tracks last-processed line number per session (prevents duplicate ingestion)
- **Container State**: Bind-mounted `.claude/` directory survives container rebuilds; Langfuse named volumes persist across `docker compose` restarts
- **Project State**: Git-tracked repos maintain state via commits; `.planning/` directories (git-ignored by default) store per-project planning docs
- **Configuration State**: `.env` files (git-ignored) store runtime secrets; `settings.json` stores global Claude Code configuration

## Key Abstractions

**Langfuse Hook (Observability Abstraction):**
- Purpose: Decouple Claude Code output from observability infrastructure
- Examples: `langfuse_hook.py` (hook implementation), `langfuse_hook.log` (execution logs), `langfuse_state.json` (incremental processing state)
- Pattern: Stop hook fires post-response → parses transcript asynchronously → POSTs to API → fails gracefully (exit 0) so Claude Code never blocked

**Dev Container Layers (Abstraction):**
- Purpose: Separate concerns of CLI tools, firewall rules, setup logic, and workspace access
- Examples:
  - `Dockerfile` — base image with Node 20, Claude CLI, GSD framework, Docker CLI
  - `init-firewall.sh` — iptables whitelist (runs `postStartCommand`)
  - `setup-container.sh` — post-create initialization (pip install, git config, health checks)
  - `init-gsd.sh` — GSD command installation from npm registry
- Pattern: Layered startup — firewall → git setup → Python packages → health checks → GSD

**Monorepo Workspace (Code Abstraction):**
- Purpose: Share types, libraries, and infrastructure across independent apps
- Examples: `adventure-alerts/packages/types/`, `adventure-alerts/packages/api/`, `adventure-alerts/apps/dashboard/`
- Pattern: npm workspaces allow `npm run dev --workspace=apps/dashboard` for scoped execution

**Credential Generation (Configuration Abstraction):**
- Purpose: Derive secure, per-environment credentials from interactive prompts without manual editing
- Examples: `scripts/generate-env.sh` (creates `.env` with random secrets), `scripts/validate-setup.sh` (pre-flight and post-setup checks)
- Pattern: Template `.env.example` → user input (email, password) → random key generation → `.env` written (git-ignored)

## Entry Points

**Claude Code Session:**
- Location: Dev container shell (`/workspace`)
- Triggers: User runs `claude` command or `/gsd:*` slash command
- Responsibilities: Loads transcript history, accepts user prompts, streams responses, triggers hooks on Stop events

**Langfuse Hook Execution:**
- Location: `~/.claude/hooks/langfuse_hook.py`
- Triggers: Stop hook (after Claude response completes) if `TRACE_TO_LANGFUSE=true`
- Responsibilities: Parse transcripts, sanitize secrets, create traces, POST to Langfuse API, update state

**Dev Container Startup:**
- Location: `.devcontainer/devcontainer.json` → VS Code
- Triggers: User clicks "Reopen in Dev Container" or runs `code .`
- Responsibilities: Build image, mount volumes, run firewall, execute setup scripts, initialize GSD

**Langfuse Stack Startup:**
- Location: `/workspace/claudehome/langfuse-local/` → `docker compose up -d`
- Triggers: Manual execution or rebuild after `generate-env.sh`
- Responsibilities: Initialize PostgreSQL, ClickHouse, Redis, MinIO, provision auth tokens, health checks

**GSD Commands:**
- Location: `/home/node/.claude/commands/gsd/` (installed by `init-gsd.sh`)
- Triggers: User types `/gsd:command` in Claude Code session
- Responsibilities: Orchestrate planning workflows, create phase tasks, manage state

## Error Handling

**Strategy:** Graceful degradation with structured logging. Observability failures do not block Claude Code execution.

**Patterns:**

**Hook Failures (Non-Blocking):**
- Langfuse unreachable → log error to `~/.claude/state/langfuse_hook.log` and exit 0
- Transcript parsing error → skip malformed messages, log warning, continue
- Secret sanitization → regex-safe patterns, never crash on unexpected input
- All errors are caught and logged; `sys.exit(0)` ensures Claude Code continues

**Container Initialization Failures (Early Warning):**
- Firewall failure → logged by `init-firewall.sh`, container continues but internet access restricted
- Git config failure → logged, non-fatal (git operations warn but don't fail)
- Langfuse health check failure → logged warning, suggests manual startup command
- Python package install → logged, shows pip install instructions if missing

**Service Health Monitoring:**
- `validate-setup.sh --post` checks all prerequisites and service connectivity
- Health checks in `docker-compose.yml` (all services have health check probes)
- Periodic log rotation in hook script prevents disk space exhaustion
- Named volumes persist across restarts; data loss only on `docker compose down -v`

## Cross-Cutting Concerns

**Logging:**
- **Hook Logging:** `~/.claude/state/langfuse_hook.log` (10MB rotation, 3 backups). Timestamped entries with `[DEBUG]`, `[ERROR]`, `[INFO]` levels.
- **Container Logging:** Streamed to VS Code Dev Container output; `postStartCommand` and `postCreateCommand` output visible at container open time.
- **Docker Logging:** `docker compose logs -f <service>` for service-level inspection. Individual service logs in named volumes (`langfuse_postgres_data`, etc.).
- **Application Logging:** Adventure Alerts uses structured logging via application code; GSD commands log to stdout/stderr in Claude sessions.

**Validation:**
- **Hook Validation:** `test_hook_unit.py`, `test_hook_integration.py` — validate parsing, sanitization, trace creation
- **Setup Validation:** `validate-setup.sh` checks Docker, Python, git, Claude CLI, Langfuse connectivity
- **Environment Validation:** `test_env_generation.sh` ensures `.env` generation is idempotent
- **Syntax Validation:** `test_syntax.sh` checks shell script syntax

**Authentication & Secrets:**
- **Langfuse API Keys:** `LANGFUSE_PUBLIC_KEY` (pk-lf-local-claude-code), `LANGFUSE_SECRET_KEY` (auto-generated) stored in `~/.claude/settings.json`
- **Database Credentials:** PostgreSQL user/password, ClickHouse password stored in `.env` (git-ignored)
- **Git Identity:** User email/name configured via `setup-container.sh` (from git global config)
- **Secret Sanitization:** Hook applies regex patterns to scrub API keys, Bearer tokens, passwords before sending to Langfuse
- **Credential Generation:** `scripts/generate-env.sh` generates 32-character random secrets using OpenSSL

**Security Boundary:**
- Dev container runs on **localhost only** — no external network exposure
- Langfuse accessible only from container and Windows host (via `host.docker.internal`)
- iptables firewall whitelists approved domains (GitHub, npm, Anthropic API, PyPI, Cloudflare) — all other outbound traffic blocked
- No telemetry sent to external services (fully self-hosted)
- Secrets never committed to git (`.env`, `.claude/settings.json` are git-ignored)

---

*Architecture analysis: 2026-02-10*

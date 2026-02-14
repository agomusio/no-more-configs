# Feature Landscape

**Domain:** Devcontainer Configuration Management for Multi-Agent AI Coding Sandbox
**Researched:** 2026-02-14
**Confidence:** MEDIUM (based on project context analysis and devcontainer best practices knowledge)

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Idempotent setup scripts | Rebuilds/restarts must not fail if run multiple times | LOW | Scripts must check state before acting (e.g., `git config --get` before `git config --add`) |
| Single-file agent config source | All agent-specific settings in one discoverable location | LOW | Centralizes `CLAUDE_CONFIG_DIR`, API keys, model selection, bypass permissions flags |
| Containerized secrets management | Secrets cannot be committed to version control | MEDIUM | Separate `secrets.json` (git-ignored) from `config.json` (version-controlled defaults) |
| Environment variable injection | Agent CLIs require env vars for configuration | LOW | `containerEnv` in devcontainer.json sources from config files |
| Automated config generation | Container startup generates runtime config from templates | MEDIUM | `install-agent-config.sh` reads templates, merges secrets, writes to agent-specific locations |
| Workspace-relative launches | Agent sessions start from correct working directory | LOW | Shell aliases/commands use `cd /workspace/[project] && agent-cli` pattern |
| Git identity configuration | Commits from agents must have proper author attribution | LOW | `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL` from host env vars, applied via `git config --global` |
| Health checks on startup | Verify dependencies (firewall, network, services) are ready | MEDIUM | `postStartCommand` runs validation scripts, warns but doesn't block on failures |
| Lifecycle hook ordering | Firewall → Git config → Network checks → Agent setup | MEDIUM | `postStartCommand` sequences dependencies correctly to avoid race conditions |
| Volume persistence for state | Agent state (history, sessions, logs) survives rebuilds | LOW | Named volumes for `~/.claude`, command history, container data |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Version-controlled config templates | Agent configs are reproducible across team members | MEDIUM | `agent-config/` directory with templates for Claude Code, Codex CLI, Gemini CLI; install script merges with local secrets |
| Single directory dissolution | Eliminates scattered config files (6+ files → 2 files) | MEDIUM | `config.json` + `secrets.json` replace dispersed settings; `agent-config/` for templates; install script generates runtime config |
| Multi-agent orchestration ready | Container supports multiple AI agents without path conflicts | HIGH | Per-agent config directories (`~/.claude`, `~/.codex`, `~/.gemini`), namespace separation, shared MCP gateway |
| Save/restore credential workflows | Easily switch between API keys or model endpoints | MEDIUM | `secrets.json` supports profiles (e.g., `default`, `work`, `personal`); install script accepts `--profile` flag |
| Config validation pre-startup | Detect missing secrets or malformed config before agent launch | MEDIUM | `validate-config.sh` runs in `postCreateCommand`, checks required fields, warns on schema violations |
| Centralized MCP configuration | Single MCP gateway config shared across all agents | LOW | `.mcp.json` generated once, referenced by all agent CLIs; no per-agent MCP duplication |
| Agent-specific override support | Project-level settings override global defaults | LOW | `claudehome/.claude/settings.local.json` pattern extended to all agents; layered config (global → project → local) |
| Firewall domain auto-refresh | CDN IP rotation handled automatically | LOW | `refresh-firewall-dns.sh` re-resolves domains without container restart; scheduled or manual trigger |
| Session launch from any directory | Agents can start sessions in any workspace subdirectory | MEDIUM | Shell functions accept optional path argument: `claudey /workspace/gitprojects/project-name` |
| Unified agent CLI wrapper | Single command to launch any agent with consistent flags | MEDIUM | `agent start <claude\|codex\|gemini> [--project path] [--resume]` wrapper handles agent-specific quirks |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| GUI configuration editor | Adds complexity, requires web server, hard to version control | Hand-edit JSON files; provide JSON schema for IDE autocomplete; validation script catches errors |
| Automatic secret detection | Too many false positives (hashes, IDs look like secrets), silent failures | Explicit `secrets.json` with documented fields; validation script enforces required secrets |
| Per-project secret storage | Secrets scattered across projects, rotation nightmare | Single `~/.claude/secrets.json` (outside workspace); symlink or env var injection per project |
| Agent CLI auto-installation | Version drift, silent breakage on updates, supply chain risk | Pin versions in Dockerfile `ARG`; explicit `RUN npm install -g claude@1.x.x`; rebuild to upgrade |
| Dynamic config file discovery | "Magic" behavior confuses users, hard to debug | Explicit paths in env vars (`CLAUDE_CONFIG_FILE=/workspace/claudehome/.claude/config.json`); convention over configuration |
| Nested devcontainers per agent | Resource overhead, complexity, shared volume conflicts | Single devcontainer with multi-agent support; namespace separation via config, not containers |
| Hot-reload config changes | File watching, restart daemons, state management complexity | Manual reload (`agent reload` or restart session); config changes are infrequent enough not to justify automation |
| Encrypted secrets at rest | Key management, decryption on boot, false sense of security | Secrets in git-ignored files with proper `.gitignore`; container itself is security boundary (local dev, not production) |
| Agent selection via environment variable | Hidden behavior, hard to discover, error-prone | Explicit commands (`claudey`, `codexcli`, `geminicli`) or wrapper with subcommands (`agent start claude`) |
| Shared session history across agents | Cross-contamination, different agents have different capabilities | Per-agent history files (`~/.claude/history`, `~/.codex/history`); isolated command namespaces |

## Feature Dependencies

```
[Automated config generation]
    └──requires──> [Single-file agent config source]
    └──requires──> [Containerized secrets management]
    └──requires──> [Environment variable injection]

[Multi-agent orchestration ready]
    └──requires──> [Version-controlled config templates]
    └──requires──> [Agent-specific override support]
    └──requires──> [Centralized MCP configuration]

[Save/restore credential workflows]
    └──requires──> [Containerized secrets management]
    └──requires──> [Config validation pre-startup]

[Session launch from any directory]
    └──requires──> [Workspace-relative launches]
    └──enhances──> [Unified agent CLI wrapper]

[Config validation pre-startup]
    └──requires──> [Single-file agent config source]
    └──requires──> [Idempotent setup scripts]

[Unified agent CLI wrapper]
    └──requires──> [Multi-agent orchestration ready]
    └──requires──> [Environment variable injection]

[Health checks on startup]
    └──requires──> [Lifecycle hook ordering]
    └──enables──> [Automated config generation] (dependencies verified before config generation runs)

[Single directory dissolution]
    └──requires──> [Automated config generation]
    └──requires──> [Version-controlled config templates]
    └──enables──> [Multi-agent orchestration ready] (reduces per-agent config complexity)
```

## MVP Recommendation

**Target:** Refactor existing Claude Code setup with single-agent focus, prepare for multi-agent expansion.

### Prioritize (Phase 1: Single-Agent Cleanup)

1. **Containerized secrets management** — Immediate pain point: bind-mount causes path mismatches; `secrets.json` isolates sensitive data from version control
2. **Single-file agent config source** — Consolidate 6+ scattered files into `config.json` + `secrets.json`
3. **Version-controlled config templates** — Move `agent-config/` templates into version control, reproducible setups
4. **Automated config generation** — `install-agent-config.sh` generates runtime config from templates + secrets on container startup
5. **Idempotent setup scripts** — Fix current scripts to handle rebuilds/restarts without errors
6. **Config validation pre-startup** — Catch missing secrets or malformed config before first agent launch
7. **Single directory dissolution** — Dissolve `claudehome/` directory, move templates to `agent-config/`, working projects to `gitprojects/`

**Phase 1 success criteria:** Claude Code sessions launch from any project directory with config sourced from `config.json` + `secrets.json`, no bind-mount path issues, rebuild-safe.

### Add Later (Phase 2: Multi-Agent Support)

1. **Multi-agent orchestration ready** — Add Codex CLI and Gemini CLI with namespace separation
2. **Unified agent CLI wrapper** — `agent start <name>` command abstracts agent-specific flags
3. **Agent-specific override support** — Per-project settings override global defaults
4. **Session launch from any directory** — Flexible workspace navigation for all agents

**Phase 2 trigger:** User requests second agent (Codex or Gemini) integration

### Defer (Future Consideration)

1. **Save/restore credential workflows** — Nice-to-have for API key rotation, not critical for single-user local dev
2. **Firewall domain auto-refresh** — Rare need; manual `refresh-firewall-dns.sh` acceptable
3. **Centralized MCP configuration** — Already working; defer deeper integration until multi-agent phase

**Why defer:** These optimize workflows but don't unblock current pain points (bind-mount issues, config scatter).

## Pain Point Mapping

Current pain points from project context and how features address them:

| Pain Point | Feature That Fixes It | Priority |
|------------|----------------------|----------|
| Bind-mounting `~/.claude` from Windows causes path mismatches | Containerized secrets management + Single-file agent config source | P1 |
| Config scattered across 6+ files | Single directory dissolution + Version-controlled config templates | P1 |
| No centralized secrets management | Containerized secrets management | P1 |
| Sessions forced to launch from fixed directory (`/workspace/claudehome`) | Session launch from any directory + Workspace-relative launches | P2 |
| Scripts fail on rebuild/restart | Idempotent setup scripts | P1 |
| Adding new agent (Codex, Gemini) requires duplicating entire setup | Multi-agent orchestration ready + Unified agent CLI wrapper | P2 |
| No validation until first agent launch fails | Config validation pre-startup | P1 |
| `.env` files scattered across services | Automated config generation consolidates into `secrets.json` | P1 |

## Production-Quality Devcontainer Patterns

Based on analysis of existing setup and industry best practices:

### Configuration Hierarchy (Table Stakes)

```
1. Dockerfile ARGs (build-time, version pinning)
2. devcontainer.json containerEnv (container-level defaults)
3. Global agent settings (~/.claude/settings.json)
4. Project-level overrides (project/.claude/settings.local.json)
5. Session-level flags (--dangerously-skip-permissions, --resume)
```

**Why:** Layered config allows team defaults with per-project customization without duplicating configuration.

### Secrets Isolation (Table Stakes)

```
- secrets.json (git-ignored, contains API keys, auth tokens)
- config.json (version-controlled, contains non-sensitive defaults)
- .env files (per-service, generated from secrets.json by install script)
```

**Why:** Separation enables version control of configuration structure while protecting sensitive values.

### Idempotent Lifecycle Hooks (Table Stakes)

```bash
# BAD: Fails on second run
git config --global --add safe.directory /workspace

# GOOD: Check before adding
if ! git config --get-all safe.directory | grep -q "^/workspace$"; then
    git config --global --add safe.directory /workspace
fi
```

**Why:** Container rebuilds and restarts are common; scripts must handle repeated execution without errors.

### Health Check Sequencing (Table Stakes)

```
postStartCommand:
  init-firewall.sh &&        # 1. Network access control
  git-config.sh &&            # 2. VCS identity
  network-checks.sh &&        # 3. Dependency validation
  generate-agent-config.sh && # 4. Config generation
  mcp-setup.sh                # 5. MCP integration
```

**Why:** Dependency ordering prevents race conditions (e.g., network checks before firewall is active).

### Multi-Agent Namespace Separation (Differentiator)

```
~/.claude/         # Claude Code config, sessions, state
~/.codex/          # Codex CLI config, sessions, state
~/.gemini/         # Gemini CLI config, sessions, state
/workspace/.mcp.json  # Shared MCP gateway (single source of truth)
```

**Why:** Agents have different capabilities and config requirements; isolation prevents cross-contamination.

### Config Generation Over Bind-Mounting (Differentiator)

```
# BAD: Bind-mount host config (path mismatches, state leakage)
"mounts": [
  "source=${localEnv:USERPROFILE}/.claude,target=/home/node/.claude,type=bind"
]

# GOOD: Generate config on container startup
"postStartCommand": "install-agent-config.sh --secrets /workspace/secrets.json"
```

**Why:** Generated config eliminates Windows/Linux path mismatches, enables template-based reproducibility.

## Anti-Pattern Recognition

Patterns observed in current setup that should be refactored:

### Anti-Pattern 1: Scattered Config Files

**Current:** `devcontainer.json` (env vars) + `settings.local.json` (API keys) + `.env` (Langfuse secrets) + `mcp.json` (MCP servers) + `config.json` (GSD settings) + `CLAUDE.md` (instructions)

**Problem:** No single source of truth; hard to onboard new developers; duplication across projects

**Fix:** `config.json` (structure, defaults) + `secrets.json` (sensitive values) + `agent-config/` (templates); install script generates runtime config

### Anti-Pattern 2: Bind-Mounting Agent Config from Host

**Current:** `source=${localEnv:USERPROFILE}/.claude,target=/home/node/.claude,type=bind`

**Problem:** Windows paths (`C:\Users\...`) don't translate to Linux paths (`/home/node/...`); agent state leaks across projects

**Fix:** Generate `~/.claude/` contents from templates on container startup; use named volumes for state persistence

### Anti-Pattern 3: Manual MCP Setup Commands

**Current:** User must run `mcp-setup` after adding servers; easy to forget; sessions miss new tools

**Problem:** Manual steps break automation; new developers forget; agents launch with stale config

**Fix:** `postStartCommand` auto-generates `.mcp.json`; file watching (future) or "restart to apply" convention

### Anti-Pattern 4: Fixed Launch Directory

**Current:** `claudey` alias does `cd /workspace/claudehome && claude ...`; forces all sessions to start from same directory

**Problem:** Can't launch agent from project root; breaks multi-repo workflows; requires manual `cd` after launch

**Fix:** Shell function accepts optional path: `claudey [path]` → `cd ${path:-/workspace/claudehome} && claude ...`

### Anti-Pattern 5: Non-Idempotent Setup Scripts

**Current:** Scripts assume first-run; `git config --add` duplicates entries on rebuild

**Problem:** Rebuilds fail or create duplicate config; developers avoid rebuilds; drift accumulates

**Fix:** All scripts check state before mutating: `command -v`, `git config --get`, `test -f`, etc.

## Sources

**Confidence Level: MEDIUM** — Research based on project context analysis, existing devcontainer configuration, and training knowledge of devcontainer best practices. No external sources accessed due to tool restrictions (WebSearch/WebFetch unavailable).

### Primary Sources (Project Context)

- C:\Users\sam\Dev-Projects\claude-code-sandbox\.devcontainer\devcontainer.json
- C:\Users\sam\Dev-Projects\claude-code-sandbox\.devcontainer\setup-container.sh
- C:\Users\sam\Dev-Projects\claude-code-sandbox\.devcontainer\mcp-setup-bin.sh
- C:\Users\sam\Dev-Projects\claude-code-sandbox\README.md
- C:\Users\sam\Dev-Projects\claude-code-sandbox\.claude\settings.local.json
- C:\Users\sam\Dev-Projects\claude-code-sandbox\claudehome\.planning\research\FEATURES.md

### Knowledge Domains Applied

- Devcontainer specification (lifecycle hooks, mounts, environment variables)
- Multi-agent configuration patterns (namespace separation, config layering)
- Secret management best practices (git-ignore, env var injection, template generation)
- Idempotent script design (state checking, graceful handling)
- AI coding agent ecosystems (Claude Code, Codex CLI, Gemini CLI capabilities)

### Gaps Requiring Validation

- **LOW confidence:** Codex CLI and Gemini CLI configuration requirements (assumed similar to Claude Code based on typical agent patterns)
- **LOW confidence:** MCP gateway behavior with multiple concurrent agent connections (assumed standard SSE multiplexing)
- **MEDIUM confidence:** Windows → Linux path translation edge cases beyond basic bind-mount mismatches

**Recommendation:** Validate multi-agent assumptions with Codex CLI and Gemini CLI documentation once available; test MCP gateway under concurrent load in Phase 2.

---

*Feature research for: Devcontainer Configuration Management for Multi-Agent AI Coding Sandbox*
*Researched: 2026-02-14*
*Confidence: MEDIUM (project context analysis + training knowledge, no external verification)*

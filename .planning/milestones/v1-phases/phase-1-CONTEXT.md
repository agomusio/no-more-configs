# Phase 1 Context: Configuration Consolidation

**Phase goal**: User can define all sandbox behavior in two master files — config.json for settings, secrets.json for credentials — with idempotent install script that hydrates templates.

**Requirements**: CFG-01–05, AGT-01, AGT-02, AGT-06, AGT-07, INS-01–06

---

## Decisions

### 1. config.json Schema Design

**Structure**: Nested objects with top-level grouping.

```jsonc
{
  "firewall": {
    "extra_domains": ["example.com"]
  },
  "langfuse": {
    "host": "http://host.docker.internal:3052"
  },
  "agent": {
    "defaults": { /* agent default settings */ }
  },
  "vscode": {
    "git_scan_paths": []  // optional override, auto-detected if absent
  },
  "mcp_servers": {
    "filesystem": { /* references template in agent-config/mcp-templates/ */ }
  }
}
```

**MCP servers**: Name + template reference pattern. config.json lists which servers are enabled; actual server configs (command, args, env with `{{PLACEHOLDER}}` tokens) live in `agent-config/mcp-templates/`. The install script reads config.json to know which templates to hydrate.

**Langfuse split**: config.json owns connection config (host, port). secrets.json owns credentials (public_key, secret_key). Clean separation.

**Projects**: Auto-detect from `gitprojects/` (scan for .git directories). config.json can override or extend the list via `vscode.git_scan_paths`. If the key is absent, auto-detect is the default behavior.

### 2. secrets.json Scope

**Structure**: Mirrors config.json nesting style.

```jsonc
{
  "claude": {
    "auth": { /* format TBD — needs investigation, see Research Notes below */ }
  },
  "langfuse": {
    "public_key": "pk-lf-...",
    "secret_key": "sk-lf-..."
  },
  "api_keys": {
    "openai": "",
    "google": ""
  }
}
```

**Infrastructure secrets (Langfuse stack) stay in `infra/.env`**. These are internal to docker-compose (Postgres password, encryption key, ClickHouse password, MinIO password, Redis auth, NextAuth secret). Pulling them into secrets.json would create a round-trip for no benefit.

**Exception**: `LANGFUSE_SECRET_KEY` crosses the boundary — it's needed by the Claude Code Langfuse hook (outside the infra stack). `generate-env.sh` writes it into both `infra/.env` (for Langfuse itself) and `secrets.json` (for the install script to hydrate into Claude settings).

**Placeholder for missing values**: Empty string `""`. Warning printed in install output stating what's missing and what feature won't work.

### 3. Install Script Integration

**Relationship to existing scripts**: Standalone addition. `install-agent-config.sh` only handles config.json/secrets.json hydration and agent-config installation. Existing scripts (`setup-container.sh`, `init-gsd.sh`, `mcp-setup-bin.sh`, `init-firewall.sh`) remain unchanged and independent.

**Lifecycle hook**: `postCreateCommand` — runs once when container is first created. Added alongside existing postCreate scripts.

**Prerequisites**: Script verifies tools exist (claude, gsd) and installs if missing. Self-contained — doesn't assume Dockerfile has already installed everything.

**Idempotency**: No state markers. Every operation is naturally idempotent:
- `cp -r` overwrites existing files
- `mkdir -p` is a no-op if directory exists
- `jq` regenerates files fresh from source every time
- `npm install -g` updates or skips

No marker invalidation logic needed. Script is fast (file copies + jq), and output always matches current inputs.

### 4. Degraded Mode Behavior

**Zero-config philosophy**: Both files missing = container still works. Clone repo, open devcontainer, start coding immediately. Authentication is manual, firewall uses defaults, default skills install, GSD works. Nothing is broken — just not customized. config.json is a convenience, not a dependency.

**Default firewall (no config.json)**: Current `firewall-domains.conf` list plus API domains (`api.openai.com`, `generativelanguage.googleapis.com`). Matches current behavior with GEN-02 additions.

**Missing secrets behavior**: Configure everything with empty values. MCP server configs are generated but may fail to connect. Langfuse hook exists but traces go nowhere. Warnings explain what's missing and what breaks.

**Install output format**: Prefixed, greppable, one-line-per-item:
```
[install] ⚠ secrets.json not found — using empty placeholders
[install] ⚠ secrets.json: langfuse.secret_key missing — tracing will not work
[install] ⚠ secrets.json: api_keys.openai missing — Codex CLI will not authenticate
[install] ✓ config.json loaded
[install] ✓ Skills: 3 installed (aa-fullstack, aa-cloudflare, multi-model)
[install] ✓ Hooks: 3 installed
[install] ✓ GSD: 29 commands + 11 agents
[install] ✓ Claude Code: v1.x.x
[install] ⚠ Codex CLI: not installed (npm install -g @openai/codex)
[install] ✓ Gemini CLI: v1.x.x
```

Warnings state what's missing AND what breaks because of it. Successes confirm what's working. `[install]` prefix for grep in build logs. No walls of text, no stack traces, no multi-step fix instructions.

---

## Research Notes

**Claude Code auth format**: Needs investigation. The researcher should determine what files/tokens Claude Code stores in `~/.claude/` for authentication, and how to capture/restore them via secrets.json. A runbook has been placed at `claude-auth-investigation.md` in the repo root — use it as a starting point.

---

## Deferred Ideas

None captured during this discussion. All decisions stayed within phase scope.

---

## Scope Boundary

Phase 1 creates config.json, secrets.json, agent-config/ directory, and install-agent-config.sh. It does NOT:
- Move or rename directories (Phase 2)
- Remove the ~/.claude bind mount (Phase 3)
- Generate firewall-domains.conf from config.json (Phase 3 — GEN-01)
- Generate .vscode/settings.json from config.json (Phase 3 — GEN-03)
- Implement save-secrets helper (Phase 3 — CRD-01)
- Copy skills/hooks/commands to ~/.claude/ (Phase 3 — AGT-03/04/05)

Phase 1 establishes the files and the script. Phase 3 adds the generation logic that reads them.

---
*Created: 2026-02-14 — from discuss-phase session*

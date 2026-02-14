# Architecture Patterns

**Domain:** Devcontainer Config Management System
**Researched:** 2026-02-14
**Confidence:** MEDIUM (based on existing codebase analysis, devcontainer lifecycle knowledge, and infrastructure patterns from training data)

## Recommended Architecture

The devcontainer config management system should follow a **Source-of-Truth → Template Hydration → Runtime Config** pattern with clear component boundaries and lifecycle stage responsibilities.

```
┌─────────────────────────────────────────────────────────────────┐
│                        SOURCE OF TRUTH                          │
│  (Version controlled, user-facing, declarative)                 │
├─────────────────────────────────────────────────────────────────┤
│  config.json (committed)        secrets.json (gitignored)       │
│  - Firewall domains             - Claude credentials            │
│  - MCP server definitions       - OpenAI API key                │
│  - Langfuse endpoint            - Google API key                │
│  - Projects/repos               - Langfuse secret key           │
│  - Agent model preferences      - GitHub tokens                 │
│  - VS Code settings             - MCP server credentials        │
│                                                                  │
│  agent-config/ (committed)                                      │
│  - settings.json (template with {{placeholders}})               │
│  - skills/                                                      │
│  - hooks/                                                       │
│  - commands/                                                    │
└──────────────┬──────────────────────────────────────────────────┘
               │
               │ postCreateCommand: install-agent-config.sh
               │ (reads both config files, merges, hydrates templates)
               │
               ↓
┌─────────────────────────────────────────────────────────────────┐
│                    HYDRATION & GENERATION                        │
│  (One-time transformation at container creation)                │
├─────────────────────────────────────────────────────────────────┤
│  install-agent-config.sh orchestrates:                          │
│                                                                  │
│  1. Read config.json + secrets.json                             │
│  2. Generate firewall-domains.conf                              │
│     (config.firewall.extra_domains → .devcontainer/)            │
│  3. Hydrate settings template                                   │
│     (agent-config/settings.json + placeholders → runtime)       │
│  4. Generate MCP configs                                        │
│     (config.mcp_servers + secrets → infra/mcp/mcp.json)         │
│  5. Copy static assets                                          │
│     (skills/, hooks/, commands/ → ~/.claude/)                   │
│  6. Generate .vscode/settings.json                              │
│     (config.projects → git.scanRepositories)                    │
└──────────────┬──────────────────────────────────────────────────┘
               │
               │ Files written to disk
               │
               ↓
┌─────────────────────────────────────────────────────────────────┐
│                       RUNTIME CONFIG                             │
│  (Read by services at runtime, never edited by users)           │
├─────────────────────────────────────────────────────────────────┤
│  ~/.claude/settings.json        Hydrated from template          │
│  ~/.claude/skills/              Copied from agent-config/       │
│  ~/.claude/hooks/               Copied from agent-config/       │
│  ~/.claude/commands/            Merged (user + GSD)             │
│  .devcontainer/firewall-domains.conf  Generated                 │
│  .vscode/settings.json          Generated                       │
│  infra/mcp/mcp.json             Generated (with secrets)        │
│  /workspace/.mcp.json           Generated (runtime, gitignored) │
└──────────────┬──────────────────────────────────────────────────┘
               │
               │ postStartCommand: init-firewall.sh, mcp-setup
               │
               ↓
┌─────────────────────────────────────────────────────────────────┐
│                    RUNTIME SERVICES                              │
│  (Services start and consume runtime config)                    │
├─────────────────────────────────────────────────────────────────┤
│  - init-firewall.sh reads firewall-domains.conf                 │
│  - mcp-setup generates .mcp.json from infra/mcp/mcp.json        │
│  - Claude Code reads ~/.claude/settings.json                    │
│  - Docker Compose reads infra/.env (generated separately)       │
└─────────────────────────────────────────────────────────────────┘
```

### Component Boundaries

| Component | Responsibility | Owns | Communicates With |
|-----------|---------------|------|-------------------|
| **config.json** | Master non-secret configuration source | Firewall domains, MCP server defs (structure only), Langfuse endpoint, projects list, agent preferences, VS Code settings | Install script (read), User (edit) |
| **secrets.json** | Master credential storage | Claude auth, OpenAI key, Google key, Langfuse keys, MCP server tokens, GitHub PATs | Install script (read), save-secrets helper (write), User (manual edit) |
| **agent-config/** | Agent behavior configuration source | Skills, hooks, commands, settings template (with {{placeholders}}) | Install script (read/copy), User (edit) |
| **install-agent-config.sh** | Config orchestrator | Reads sources, hydrates templates, generates runtime configs, copies assets | config.json, secrets.json, agent-config/, runtime destinations |
| **Runtime configs** | Service-consumable configuration | Hydrated settings.json, firewall-domains.conf, .vscode/settings.json, mcp.json | Services (read), Install script (write), NEVER user (readonly) |
| **init-firewall.sh** | Firewall service bootstrap | Firewall rules from firewall-domains.conf | firewall-domains.conf (read), iptables (write) |
| **mcp-setup** | MCP runtime config generator | /workspace/.mcp.json from infra/mcp/mcp.json | infra/mcp/mcp.json (read), Claude Code (via .mcp.json) |
| **save-secrets** | Credential extraction helper | Reverse flow: captures live credentials back into secrets.json | Claude Code runtime config (read), secrets.json (write) |
| **infra/.env** | Infrastructure secret storage | Docker Compose stack credentials (separate from agent secrets) | generate-env.sh (write), docker-compose.yml (read) |

### Data Flow

```
USER EDIT FLOW (most common):
1. User edits config.json or secrets.json or agent-config/*
2. User rebuilds devcontainer (triggers postCreateCommand)
3. install-agent-config.sh runs
4. Runtime configs regenerated
5. postStartCommand services start with new config

CREDENTIAL CAPTURE FLOW (save-secrets):
1. User configures Claude Code via CLI (e.g., `claude auth`)
2. Live credentials stored in ~/.claude/settings.json or OS keyring
3. User runs save-secrets helper
4. Helper extracts credentials from runtime locations
5. Helper writes to secrets.json
6. Next rebuild: secrets.json → install script → runtime configs

INFRASTRUCTURE SECRETS FLOW (separate):
1. User runs infra/scripts/generate-env.sh
2. Script generates random passwords/keys
3. Writes to infra/.env (gitignored)
4. docker-compose.yml reads .env at stack startup
5. (Never touches config.json/secrets.json — isolated subsystem)

CONFIG HYDRATION FLOW (template engine):
1. install-agent-config.sh loads config.json + secrets.json into memory
2. Reads agent-config/settings.json (contains {{LANGFUSE_SECRET_KEY}}, etc.)
3. Regex replace: {{KEY}} → secrets.json[path.to.key]
4. If key missing: placeholder → empty string + warning logged
5. Writes hydrated output to ~/.claude/settings.json
6. Same pattern for MCP server env vars

FILE GENERATION FLOW (derived configs):
1. firewall-domains.conf:
   - Core domains (hardcoded: anthropic.com, github.com, npmjs.org)
   - + config.firewall.extra_domains[]
   - Written as newline-delimited list
2. .vscode/settings.json:
   - git.scanRepositories = config.projects[].path
   - Other VS Code settings merged in
3. infra/mcp/mcp.json:
   - config.mcp_servers structure copied
   - env vars hydrated from secrets.json
   - Persisted for mcp-setup to consume
```

## Patterns to Follow

### Pattern 1: Declarative Source Files
**What:** User-facing config is declarative JSON. No imperative scripts in the source-of-truth layer.
**When:** Always for user-edited configuration.
**Example:**
```json
// config.json — declarative
{
  "firewall": {
    "extra_domains": ["api.cloudflare.com", "storage.googleapis.com"]
  }
}
```
Not:
```bash
# BAD: imperative script as source-of-truth
echo "api.cloudflare.com" >> firewall-domains.conf
```

**Why:** JSON is diff-friendly, mergeable, validatable with schema. Users can understand and edit it without shell scripting knowledge.

### Pattern 2: Template Hydration with {{PLACEHOLDERS}}
**What:** Runtime config files are templates with {{KEY}} placeholders replaced by install script.
**When:** When a config file needs both static structure (committed) and dynamic secrets (gitignored).
**Example:**
```json
// agent-config/settings.json (template, committed)
{
  "environmentVariables": {
    "LANGFUSE_SECRET_KEY": "{{LANGFUSE_SECRET_KEY}}",
    "LANGFUSE_PUBLIC_KEY": "{{LANGFUSE_PUBLIC_KEY}}"
  }
}

// secrets.json (gitignored)
{
  "langfuse": {
    "secret_key": "sk-lf-abc123",
    "public_key": "pk-lf-xyz789"
  }
}

// Result: ~/.claude/settings.json (runtime, generated)
{
  "environmentVariables": {
    "LANGFUSE_SECRET_KEY": "sk-lf-abc123",
    "LANGFUSE_PUBLIC_KEY": "pk-lf-xyz789"
  }
}
```

**Implementation (bash/jq):**
```bash
# Load secrets
LANGFUSE_SECRET=$(jq -r '.langfuse.secret_key // ""' secrets.json)
LANGFUSE_PUBLIC=$(jq -r '.langfuse.public_key // ""' secrets.json)

# Hydrate template
sed -e "s|{{LANGFUSE_SECRET_KEY}}|$LANGFUSE_SECRET|g" \
    -e "s|{{LANGFUSE_PUBLIC_KEY}}|$LANGFUSE_PUBLIC|g" \
    agent-config/settings.json > ~/.claude/settings.json
```

### Pattern 3: Fail-Safe with Warnings
**What:** If config.json or secrets.json is missing or malformed, use sensible defaults and warn. Never fail the build.
**When:** All config reads in install-agent-config.sh.
**Example:**
```bash
if [ ! -f config.json ]; then
  echo "⚠️  config.json not found. Using defaults."
  EXTRA_DOMAINS=()
else
  EXTRA_DOMAINS=$(jq -r '.firewall.extra_domains[]' config.json 2>/dev/null || echo "")
fi

if [ ! -f secrets.json ]; then
  echo "⚠️  secrets.json not found. Credential placeholders will be empty."
  echo "    Run save-secrets after configuring Claude Code."
fi
```

**Why:** Missing config shouldn't brick the container. New users can boot the container, configure manually, then save secrets for next rebuild. Experienced users can populate config before first boot.

### Pattern 4: Idempotent Install Script
**What:** install-agent-config.sh can run multiple times safely. Overwrites are intentional (regenerating from source).
**When:** postCreateCommand (runs once), manual re-runs for testing.
**Example:**
```bash
# Always safe to run
rm -rf ~/.claude/skills/*
cp -r agent-config/skills/* ~/.claude/skills/

# Generate configs (overwrite existing)
generate_firewall_domains > .devcontainer/firewall-domains.conf
hydrate_settings > ~/.claude/settings.json
```

**Why:** Rebuilding the container should always produce a clean, known-good state. No drift from accumulated manual edits.

### Pattern 5: Separate Infrastructure Secrets
**What:** infra/.env (Docker Compose stack credentials) is generated independently from config.json/secrets.json.
**When:** Initial setup of Langfuse/Postgres/Redis/etc.
**Example:**
```bash
# infra/scripts/generate-env.sh
POSTGRES_PASSWORD=$(openssl rand -hex 24)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env
```

**Why:** Langfuse stack credentials are infrastructure-level (database passwords, encryption keys). Agent secrets are application-level (API keys for external services). Mixing them in one file creates confusion. Infrastructure secrets are generated once and rarely change. Agent secrets are edited frequently as users add/remove services.

### Pattern 6: Reverse Flow for Credential Capture
**What:** A save-secrets helper extracts live credentials from runtime locations back into secrets.json.
**When:** After user configures Claude Code via `claude auth` or similar interactive flows.
**Example:**
```bash
#!/bin/bash
# save-secrets — extracts credentials from runtime and saves to secrets.json

# Read Claude auth from OS keyring or settings.json
CLAUDE_CREDS=$(claude config get credentials 2>/dev/null || echo "")

# Read current secrets.json (or create new)
if [ -f secrets.json ]; then
  SECRETS=$(cat secrets.json)
else
  SECRETS='{}'
fi

# Merge new credentials
SECRETS=$(echo "$SECRETS" | jq --arg creds "$CLAUDE_CREDS" \
  '.claude.credentials = $creds')

# Write back
echo "$SECRETS" | jq . > secrets.json
echo "✓ Saved Claude credentials to secrets.json"
```

**Why:** Users shouldn't manually copy-paste credentials. Capture from the official source (Claude CLI, OS keyring) to avoid typos and format errors.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Editing Runtime Configs Directly
**What:** User edits ~/.claude/settings.json or .devcontainer/firewall-domains.conf directly.
**Why bad:** Next container rebuild overwrites their changes. All manual edits lost.
**Instead:** Edit config.json, secrets.json, or agent-config/*, then rebuild. Runtime configs are read-only outputs of the install script.

**Detection:** Git tracking of generated files (e.g., if ~/.claude/settings.json shows up in git status).
**Prevention:** Document clearly: "NEVER EDIT. Generated from config.json + secrets.json."

### Anti-Pattern 2: Hardcoding Secrets in config.json
**What:** Putting API keys directly in config.json instead of using {{PLACEHOLDER}} + secrets.json.
**Why bad:** Secrets get committed to git. Security risk.
**Instead:**
```json
// config.json (committed) — structure only
{
  "mcp_servers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_TOKEN": "{{GITHUB_TOKEN}}" }
    }
  }
}

// secrets.json (gitignored) — credentials only
{
  "mcp_tokens": {
    "GITHUB_TOKEN": "ghp_abc123xyz"
  }
}
```

**Detection:** Grep config.json for patterns like `".*key":\s*"[a-zA-Z0-9]{20,}"` (looks like a real token).
**Prevention:** Validation step in install script that warns if config.json contains suspicious patterns.

### Anti-Pattern 3: Scattering Config Across Multiple Scripts
**What:** firewall-domains.conf managed in init-firewall.sh, MCP config in mcp-setup, VS Code settings in devcontainer.json.
**Why bad:** Users must hunt through multiple files to change one logical setting (e.g., "add a new project").
**Instead:** Single config.json → install-agent-config.sh distributes values to all destinations.

**Example of centralization:**
```json
// config.json — ONE place to add a project
{
  "projects": [
    { "path": "gitprojects/new-project", "label": "New Project" }
  ]
}
```
Install script updates:
- .vscode/settings.json → git.scanRepositories
- (Future) firewall-domains.conf if project has custom domains
- (Future) Per-project Claude settings

### Anti-Pattern 4: Stateful Install Script
**What:** Install script checks "did I already do X?" and skips steps.
**Why bad:** Partial failures leave container in inconsistent state. Hard to debug.
**Instead:** Always regenerate everything. Idempotent operations.

**Bad:**
```bash
if [ ! -f ~/.claude/settings.json ]; then
  hydrate_settings > ~/.claude/settings.json
fi
# Problem: If user deletes file, script won't regenerate
```

**Good:**
```bash
# Always regenerate (overwrite)
hydrate_settings > ~/.claude/settings.json
```

### Anti-Pattern 5: Mixing Infrastructure and Agent Secrets
**What:** Putting Postgres password in secrets.json alongside Claude API key.
**Why bad:** Different lifecycles. Infra secrets generated once and rarely change. Agent secrets edited frequently. Mixing them creates noise.
**Instead:** infra/.env for Docker Compose stack. secrets.json for Claude/OpenAI/Google/MCP agents.

## Scalability Considerations

| Concern | Initial (1 user, 1 project) | Medium (1 user, 5 projects) | Large (team, 20+ projects) |
|---------|-----------------------------|-----------------------------|----------------------------|
| **Config complexity** | Single config.json with inline settings | Config grows but manageable in one file | Consider splitting: config.json references project-specific configs in gitprojects/*/project.json |
| **Secret management** | Manual secrets.json editing | save-secrets helper essential | Secret manager integration (Vault, AWS Secrets Manager) instead of file-based |
| **Build time** | <30s (install script runs fast) | Same (config size doesn't affect runtime much) | Optimize: cache npm packages, parallel asset copying |
| **Runtime config drift** | Non-issue (single user rebuilds regularly) | Risk of users forgetting to rebuild after config edits | CI/CD check: "config.json changed → rebuild required" |
| **MCP server count** | 2-3 servers (filesystem, github) | 5-10 servers (add databases, APIs) | Template generation helper for repetitive server defs |
| **Firewall domain list** | ~10 extra domains | ~50 extra domains | Auto-discovery: parse package.json deps for known CDN domains |

### Phase 1 (MVP) Focus
- Core components: config.json, secrets.json, install-agent-config.sh
- Template hydration for settings.json
- Firewall domain generation
- MCP config generation
- Static asset copying (skills, hooks, commands)

### Defer to Later Phases
- save-secrets helper (can configure manually at first)
- Per-project config overrides (start with global-only)
- Secret manager integrations (file-based is fine for single user)
- Advanced validation/schema checking (warnings are sufficient initially)
- Config file splitting for large projects

## Lifecycle Hook Responsibilities

Devcontainer lifecycle hooks from official spec (confidence: MEDIUM — based on training data + existing devcontainer.json):

| Hook | Timing | Runs As | Responsibility in This Architecture |
|------|--------|---------|-------------------------------------|
| **postCreateCommand** | Once per container creation (after build) | Container user (node) | **install-agent-config.sh** — Read config.json + secrets.json, hydrate templates, generate all runtime configs, copy assets |
| **postStartCommand** | Every container start/restart | Container user (node) | **init-firewall.sh** (requires sudo) — Apply firewall rules from generated firewall-domains.conf<br>**init-gsd.sh** — Install GSD framework<br>**mcp-setup** — Generate .mcp.json from infra/mcp/mcp.json |
| **postAttachCommand** | Every time editor attaches | Container user (node) | (Not currently used — could run validation checks) |

**Key insight:** Config generation (postCreateCommand) happens BEFORE service initialization (postStartCommand). This ensures firewall rules and MCP configs exist before services try to use them.

**Ordering within postStartCommand:**
```bash
"postStartCommand": "sudo init-firewall.sh && init-gsd.sh && mcp-setup && docker compose -f infra/docker-compose.yml up -d"
```
1. init-firewall.sh FIRST (blocks network until rules applied)
2. init-gsd.sh (installs GSD commands into ~/.claude/)
3. mcp-setup (generates runtime .mcp.json)
4. docker compose up (starts Langfuse stack — depends on network access)

## Build Order Dependencies

```
LAYER 1 (No dependencies):
├── config.json (user edits)
├── secrets.json (user edits or save-secrets generates)
└── agent-config/* (user edits)

LAYER 2 (Depends on Layer 1):
└── install-agent-config.sh execution
    ├── Reads config.json + secrets.json
    └── Outputs →

LAYER 3 (Generated by Layer 2):
├── .devcontainer/firewall-domains.conf
├── ~/.claude/settings.json
├── ~/.claude/skills/*
├── ~/.claude/hooks/*
├── ~/.claude/commands/*
├── .vscode/settings.json
└── infra/mcp/mcp.json

LAYER 4 (Depends on Layer 3):
└── postStartCommand services
    ├── init-firewall.sh (reads firewall-domains.conf)
    ├── mcp-setup (reads infra/mcp/mcp.json)
    └── docker compose (reads infra/.env — separate flow)

PARALLEL TRACK (Infrastructure secrets):
infra/scripts/generate-env.sh → infra/.env → docker-compose.yml
(Never touches config.json/secrets.json)
```

**Critical path for initial setup:**
1. User creates config.json + secrets.json (or accepts defaults)
2. User runs infra/scripts/generate-env.sh (one-time)
3. User rebuilds devcontainer
4. postCreateCommand: install-agent-config.sh generates runtime configs
5. postStartCommand: Services start with generated configs

**Critical path for config changes:**
1. User edits config.json or secrets.json or agent-config/*
2. User rebuilds devcontainer (or manually runs install-agent-config.sh for testing)
3. Runtime configs regenerated
4. (If firewall/MCP changed) Restart affected services

## Sources

**HIGH confidence (official/verified):**
- Existing devcontainer.json structure (read from codebase)
- Existing init-firewall.sh, mcp-setup, generate-env.sh scripts (read from codebase)
- Opus refactor prompt (read from codebase — authoritative design doc)

**MEDIUM confidence (training data + multiple sources):**
- Devcontainer lifecycle hooks (postCreateCommand, postStartCommand) — standard VS Code Remote Containers pattern
- Template hydration with sed/jq — common shell scripting pattern
- JSON schema validation — standard practice for config management

**LOW confidence (training data only, needs validation):**
- Specific Claude Code config file locations (~/.claude/settings.json) — inferred from existing scripts but should verify with official Claude Code docs
- save-secrets implementation details — conceptual design, needs API research
- Secret manager integrations for scale — general knowledge, not specific to this stack

**Gaps to address in implementation phases:**
- [ ] Verify exact Claude Code config file paths and schema
- [ ] Research Codex CLI and Gemini CLI config file locations (not yet installed)
- [ ] Test template hydration error handling (missing keys, malformed JSON)
- [ ] Validate firewall refresh-firewall-dns.sh integration with new firewall-domains.conf
- [ ] Confirm postStartCommand execution order guarantees (sequential or parallel?)

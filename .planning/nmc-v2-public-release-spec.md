# NMC v2 Spec: Public Release

> **Goal:** Ship `agomusio/no-more-configs` — the battle-tested sandbox stripped down to a generic, clone-and-go devcontainer that anyone with VS Code and Docker Desktop can use in minutes. Two agents (Claude Code + Codex CLI), plugin system, Langfuse observability, GSD framework, iptables firewall. Nothing project-specific. MIT licensed.

---

## What v2 Is

A packaging and polish pass. The architecture is done — v1 proved it works. v2 takes the internal sandbox and turns it into a public product:

1. Strip all project-specific content (Adventure Alerts, personal config)
2. Genericize defaults so cold-start works for anyone
3. Polish documentation for a first-time user who knows nothing about the internals
4. Verify the end-to-end flow on a clean machine
5. Ship as a public GitHub repo

## What v2 Is NOT

- No new agent integrations (Gemini deferred indefinitely)
- No multi-model orchestration skill
- No installer/TUI/extension (future)
- No architecture changes — the foundation is stable

---

## Prerequisites for v2

Everything from v1 must be working and stable:

- [x] `config.json` + `secrets.json` two-file configuration
- [x] `install-agent-config.sh` idempotent install with graceful degradation
- [x] Claude Code + Codex CLI fully integrated (auth, config, skills, persistence)
- [x] Plugin system with hook registration and `config.json` control
- [x] Cross-agent skills (Claude + Codex)
- [x] Official Claude plugins downloaded at build time
- [x] `save-secrets` credential capture
- [x] `save-config.sh` preference persistence (delta-only)
- [x] Langfuse observability stack with `langfuse-setup`
- [x] GSD framework (commands + agents)
- [x] iptables firewall with domain whitelist
- [x] MCP gateway + configurable MCP servers

---

## Content to Strip

These are project-specific artifacts that must not ship in the public repo.

### Skills

| Skill | Action | Rationale |
|---|---|---|
| `aa-cloudflare` | **Remove** | Adventure Alerts-specific Cloudflare reference library |
| `aa-fullstack` | **Remove** | Adventure Alerts-specific fullstack patterns |
| `devcontainer` | **Keep** | Generic — teaches Claude how to work with the NMC devcontainer itself |
| `gitprojects` | **Keep** | Generic — teaches Claude the gitprojects workflow |

### Config files

| File | Action |
|---|---|
| `config.json` | **Replace** with generic defaults (see Default Config section) |
| `secrets.json` | **Does not exist in repo** (gitignored) — no action needed |
| `config.example.json` | **Update** to match generic defaults with inline comments |
| `secrets.example.json` | **Update** — remove any AA-specific key names, keep generic schema |

### Planning state

| Path | Action |
|---|---|
| `.planning/` | **Clean** — remove all existing GSD state. Ship empty with `.gitkeep` |

### Git projects

| Path | Action |
|---|---|
| `gitprojects/` | **Clean** — remove all cloned repos. Ship empty with `.gitkeep` |
| `gitprojects/no-more-configs/` | **This is where we're working** — don't ship recursively |

### Review / docs

| Path | Action |
|---|---|
| `review/` | **Remove** or clean — strip any internal review content |
| `docs/` | **Keep** generic design docs. Remove any AA-specific specs |

### VS Code settings

| File | Action |
|---|---|
| `.vscode/settings.json` | **Generated at build time** from `config.json` — no action needed. Verify it generates clean defaults |

---

## Default Config

The `config.json` that ships in the public repo must work out of the box with zero edits.

### `config.json`

```json
{
  "firewall": {
    "extra_domains": []
  },
  "codex": {
    "model": "gpt-5.3-codex"
  },
  "langfuse": {
    "host": "http://host.docker.internal:3052"
  },
  "vscode": {
    "git_scan_paths": []
  },
  "mcp_servers": {
    "mcp-gateway": { "enabled": true },
    "codex": { "enabled": false }
  },
  "plugins": {}
}
```

**Notes:**
- `firewall.extra_domains` empty — core domains cover both agents, users add their own
- `codex.model` set to current default — users can change
- `vscode.git_scan_paths` empty — auto-detection from `gitprojects/` handles the common case
- `mcp-gateway` enabled by default, `codex` MCP server disabled (opt-in)
- `plugins` empty — all plugins enabled by default (convention), this section exists for disabling

### `config.example.json`

Same structure as `config.json` but with comments showing what's available:

```jsonc
{
  // Firewall: additional domains beyond the 31 core domains
  // Core domains (Anthropic, OpenAI, GitHub, npm, PyPI, etc.) are always included
  "firewall": {
    "extra_domains": [
      "api.example.com",
      "your-service.example.com"
    ]
  },

  // Codex CLI: default model for codex sessions
  // Options: "gpt-5.3-codex", "o4-mini", "gpt-5-pro", etc.
  "codex": {
    "model": "gpt-5.3-codex"
  },

  // Claude Code: user preferences that persist across rebuilds
  // Run save-config to capture current preferences, or set them here
  // Only non-default values are applied — omitted keys keep their defaults
  "claude": {
    "preferences": {
      "autoCompact": false,
      "theme": "dark"
    }
  },

  // Langfuse: observability endpoint (only needed if running the Langfuse stack)
  "langfuse": {
    "host": "http://host.docker.internal:3052"
  },

  // VS Code: git repos to scan (auto-detected from gitprojects/ if empty)
  "vscode": {
    "git_scan_paths": [
      "gitprojects/my-project",
      "gitprojects/another-project"
    ]
  },

  // MCP servers: enable/disable MCP server templates from agent-config/mcp-templates/
  "mcp_servers": {
    "mcp-gateway": { "enabled": true },
    "codex": { "enabled": false }
  },

  // Plugins: all plugins in agent-config/plugins/ are enabled by default
  // Add an entry here only to disable a plugin or override its env vars
  "plugins": {
    "example-plugin": { "enabled": false },
    "another-plugin": {
      "enabled": true,
      "env": { "CUSTOM_VAR": "override-value" }
    }
  }
}
```

Since JSON doesn't support comments, `config.example.json` ships as a reference doc. The actual `config.json` is clean JSON. The README explains each field.

### `secrets.example.json`

```json
{
  "git": {
    "name": "Your Name",
    "email": "you@example.com"
  },
  "claude": {
    "credentials": {}
  },
  "codex": {
    "auth": {}
  },
  "infra": {
    "postgres_password": "",
    "langfuse_project_secret_key": "",
    "langfuse_project_public_key": "",
    "langfuse_admin_email": "",
    "langfuse_admin_password": "",
    "langfuse_encryption_key": "",
    "langfuse_salt": "",
    "langfuse_nextauth_secret": "",
    "clickhouse_password": "",
    "minio_root_password": "",
    "redis_auth": ""
  }
}
```

**Note:** Users never manually fill in `secrets.example.json`. The flow is: authenticate → run `save-secrets` → `secrets.json` is generated automatically. The example file exists purely as schema documentation.

---

## README Polish

The current README is close to public-ready. Changes needed:

### Tone and framing
- Open with the value prop: what you get, why it exists, who it's for
- Assume the reader has never heard of GSD, MCP, or Langfuse — brief explanations, not just links
- Remove any "we" language that implies an internal team

### Quick Start refinement
- Verify every step works on a completely clean machine (no prior Docker images, no cached layers)
- Time the first build and document it ("First build takes ~5 minutes")
- Make the optional steps clearly optional (Langfuse, Codex — Claude is the only requirement)

### Sections to add or expand
- **What's Included** — a quick feature matrix with "out of the box" vs "opt-in"
- **Prerequisites** — explicit: VS Code, Docker Desktop, Git. That's it. Platform-agnostic (macOS and Linux, Windows via WSL2)
- **Upgrading** — how to pull updates from the NMC repo without losing your config/secrets
- **Contributing** — basic guidelines if people want to submit plugins or skills
- **License** — MIT at root, component licenses preserved

### Sections to review
- **Troubleshooting** — the WSL2/HNS section is Windows-specific. Keep it but add a note that it only applies to Windows. Add macOS equivalents if any
- **Acknowledgments** — verify all attributions are current and accurate

### Sections to remove
- Any references to Adventure Alerts or project-specific workflows
- Any internal links or paths that don't exist in the public repo

---

## Directory Structure (what ships)

```
no-more-configs/
├── .devcontainer/
│   ├── Dockerfile
│   ├── devcontainer.json
│   ├── install-agent-config.sh
│   ├── init-firewall.sh
│   ├── setup-container.sh
│   ├── mcp-setup.sh
│   ├── mcp-setup-bin.sh
│   └── ...
│
├── agent-config/
│   ├── settings.json.template
│   ├── mcp-templates/
│   │   ├── mcp-gateway.json
│   │   └── codex.json
│   ├── skills/
│   │   ├── devcontainer/
│   │   │   └── SKILL.md
│   │   └── gitprojects/
│   │       └── SKILL.md
│   ├── hooks/
│   │   └── (standalone hooks, if any remain after plugin migration)
│   ├── commands/
│   │   └── .gitkeep
│   └── plugins/
│       ├── .official/            # Downloaded at build time, gitignored
│       └── nmc-langfuse-tracing/  # Ships with NMC
│           ├── plugin.json
│           └── hooks/
│               └── langfuse_hook.py
│
├── infra/
│   ├── docker-compose.yml
│   ├── mcp/
│   │   └── mcp.json
│   ├── scripts/
│   │   ├── generate-env.sh
│   │   ├── validate-setup.sh
│   │   └── ...
│   └── settings-examples/
│
├── gitprojects/
│   └── .gitkeep
│
├── .planning/
│   └── .gitkeep
│
├── docs/
│   └── claude-auth-investigation.md
│
├── config.json
├── config.example.json
├── secrets.example.json
├── .gitignore
├── LICENSE                        # MIT
├── README.md
└── review/
    └── .gitkeep
```

---

## Cold-Start Flow Verification

This is the critical test. A new user with zero context must be able to go from nothing to a working sandbox.

### Test script (manual)

```
1. Fresh machine (or clean Docker state: docker system prune -a)
2. Prerequisites installed: VS Code + Dev Containers extension, Docker Desktop running, Git
3. Clone:
   git clone https://github.com/agomusio/no-more-configs.git
   cd no-more-configs
   code .
4. VS Code prompts "Reopen in Container" → click it
5. Wait for build (time this — document in README)
6. Terminal opens in container
7. Verify warnings:
   - "[install] secrets.json not found — using empty placeholders"
   - "[install] Claude credentials not found — manual login required"
   - "[install] Codex credentials not found — manual login required"
8. Authenticate Claude:
   claude
   (complete OAuth flow)
   (exit)
9. Save credentials:
   save-secrets
10. Verify secrets.json was created:
    cat secrets.json | jq keys
    (should show: ["claude", "codex", "git", "infra"])
11. Set git identity:
    git config --global user.name "Test User"
    git config --global user.email "test@example.com"
    save-secrets
12. Test container rebuild:
    Ctrl+Shift+P → "Dev Containers: Rebuild Container"
    Wait for rebuild
    Verify: "[install] Claude credentials restored"
    Verify: claude works without login prompt
13. Optional — Codex:
    codex
    (complete OAuth flow)
    (exit)
    save-secrets
14. Optional — Langfuse:
    langfuse-setup
    curl http://localhost:3052/api/public/health
    (run a Claude session, check traces appear)
15. Clone a project:
    cd gitprojects && git clone https://github.com/some/test-repo.git
    (verify VS Code git scanner picks it up)
16. Run Claude in the project:
    cd gitprojects/test-repo
    claude
    (verify skills are available, GSD commands work)
```

### Platform matrix

| Platform | Tester | Status |
|---|---|---|
| Windows (WSL2) | Maintainer | — |
| macOS (Docker Desktop) | Friend/tester | — |
| Linux (Docker Desktop or Engine) | If available | — |

---

## License

### Root license

MIT. Create `LICENSE` at repo root:

```
MIT License

Copyright (c) 2025 agomusio

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Component licenses

| Component | License | Location |
|---|---|---|
| NMC (this repo) | MIT | `LICENSE` |
| aa-cloudflare skill | Apache 2.0 | **Removed in v2** — not shipped |
| aa-fullstack skill | MIT variant | **Removed in v2** — not shipped |
| Langfuse hook | MIT (NMC original) | Part of NMC |
| GSD framework | Third-party | Installed at runtime via npx, not bundled |
| Official Claude plugins | Per-plugin | Downloaded at build time, gitignored |

No Apache-licensed components ship in the public repo after stripping the AA skills. The license situation is clean MIT.

---

## Upgrade Path

Users who clone NMC and customize it need a way to pull updates without losing their work. Document this in the README:

### What's safe to customize (survives `git pull`):
- `config.json` — not tracked after initial clone (add to `.gitignore` after first edit, or use `git update-index --skip-worktree config.json`)
- `secrets.json` — already gitignored
- `agent-config/skills/` — user-added skills won't conflict unless they have the same name as an NMC-shipped skill
- `agent-config/plugins/` — user-added plugins won't conflict
- `agent-config/commands/` — user-added commands won't conflict
- `gitprojects/` — gitignored

### What gets updated on `git pull`:
- `.devcontainer/` — build scripts, Dockerfile
- `agent-config/settings.json.template` — new placeholders or hook patterns
- `agent-config/mcp-templates/` — new or updated MCP server templates
- `infra/` — Docker Compose stack, setup scripts
- `README.md`

### Recommended workflow:
```bash
git stash              # Save local changes
git pull origin main   # Pull NMC updates
git stash pop          # Restore local changes
# Rebuild container to apply
```

For heavy customizers: fork the repo and periodically merge upstream.

---

## Deliverables

1. **Stripped `agent-config/skills/`** — AA skills removed, generic skills kept
2. **Generic `config.json`** — works out of the box with zero edits
3. **Updated `config.example.json`** — annotated schema reference
4. **Updated `secrets.example.json`** — clean generic schema
5. **Clean `gitprojects/`** and `.planning/` — empty with `.gitkeep`
6. **Clean `docs/`** and `review/`** — no AA-specific content
7. **`LICENSE`** — MIT at repo root
8. **Polished `README.md`** — public-facing, platform-agnostic, cold-start verified
9. **Cold-start test** — verified on Windows (WSL2), ideally macOS
10. **Public repo** — `agomusio/no-more-configs` on GitHub

---

## Out of Scope (future)

- Gemini CLI integration
- Multi-model orchestration skill
- Installer script / TUI / VS Code extension
- Plugin marketplace or registry
- CI/CD for the NMC repo itself

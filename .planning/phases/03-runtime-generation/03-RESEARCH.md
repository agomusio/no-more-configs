# Phase 3: Runtime Generation & Cut-Over - Research

**Researched:** 2026-02-14
**Domain:** Template hydration, firewall configuration, credential management, devcontainer lifecycle
**Confidence:** HIGH

## Summary

Phase 3 completes the refactor by removing the `~/.claude` host bind mount, extending `install-agent-config.sh` to copy skills/hooks/commands and generate all runtime configuration files (firewall domains, VS Code settings, MCP configs, Claude settings), and adding credential persistence tooling (`save-secrets` helper, API key exports, Langfuse key writeback).

The riskiest change is the bind mount removal (CTR-01). Once removed, the container no longer inherits any config from the Windows host — everything depends on `install-agent-config.sh`. The existing install script already generates `settings.local.json`, restores credentials, generates `.mcp.json`, and installs GSD, so basic Claude Code operation should work immediately after bind mount removal. The remaining work adds asset copying and config generation capabilities.

**Primary recommendation:** Remove bind mount first as an isolated commit, then extend the install script incrementally with asset copy, firewall generation, VS Code settings generation, and credential tooling.

## Current State Analysis

### What install-agent-config.sh already does (from Phase 1)
| Capability | Requirement | Status |
|-----------|-------------|--------|
| Load config.json with defaults | CFG-01 | Done |
| Load secrets.json with placeholders | CFG-02 | Done |
| Validate JSON before processing | CFG-05 | Done |
| Generate settings.local.json from template | GEN-05 | Done |
| Restore Claude credentials from secrets.json | CRD-02 | Done |
| Generate .mcp.json from templates | GEN-04 | Done |
| Install GSD framework | AGT-06 | Done |
| Print summary | INS-06 | Done |

### What install-agent-config.sh needs to add (Phase 3)
| Capability | Requirement | Details |
|-----------|-------------|---------|
| Copy skills to ~/.claude/skills/ | AGT-03 | `cp -r agent-config/skills/* ~/.claude/skills/` |
| Copy hooks to ~/.claude/hooks/ | AGT-04 | `cp agent-config/hooks/* ~/.claude/hooks/` |
| Copy commands non-destructively | AGT-05 | `cp -rn agent-config/commands/* ~/.claude/commands/` (skip GSD) |
| Generate firewall-domains.conf | GEN-01 | Core domains + config.json extra_domains |
| Add API domains to firewall | GEN-02 | api.openai.com, generativelanguage.googleapis.com |
| Generate .vscode/settings.json | GEN-03 | git.scanRepositories from config.json |
| Warn on unresolved placeholders | GEN-06 | Scan output, replace {{...}} with "", warn |
| Export API keys to shell env | CRD-03 | OPENAI_API_KEY, GOOGLE_API_KEY from secrets.json |

### Files that need the langfuse hook at runtime
The `agent-config/settings.json.template` references `/home/node/.claude/hooks/langfuse_hook.py`. Currently this file comes from the bind mount. After removal, it must be installed by the script. The hook source file is at `infra/hooks/langfuse_hook.py`. It needs to be copied to `agent-config/hooks/langfuse_hook.py` for the agent config pipeline, then installed to `~/.claude/hooks/` by the script.

## Architecture Patterns

### Pattern 1: Bind Mount Removal (Isolated Commit)

**What:** Remove the `~/.claude` bind mount line from devcontainer.json as the very first commit of the phase.

**Why isolated:** This is the point of no return. If it breaks auth, `git revert` brings it back instantly. Mixing it with other changes makes reverting difficult.

**What still works after removal:**
- `install-agent-config.sh` already generates `settings.local.json` (Langfuse config, hooks definition)
- `install-agent-config.sh` already restores `.credentials.json` from `secrets.json`
- `install-agent-config.sh` already generates `.mcp.json`
- `init-gsd.sh` already installs GSD commands and agents

**What breaks after removal (fixed in subsequent commits):**
- Skills not available (AGT-03 — no copy logic yet)
- Hooks not available (AGT-04 — langfuse hook not copied)
- Any host-side custom commands not available (AGT-05 — no copy logic yet)
- Session memory/history lost (ephemeral — acceptable)

### Pattern 2: Asset Copy Pipeline

**What:** Copy version-controlled agent config files to `~/.claude/` runtime locations.

**Implementation:**
```bash
# Skills: preserve directory structure (AGT-03)
if [ -d "$AGENT_CONFIG_DIR/skills" ]; then
    cp -r "$AGENT_CONFIG_DIR/skills/"* "$CLAUDE_DIR/skills/" 2>/dev/null || true
fi

# Hooks: flat copy (AGT-04)
if [ -d "$AGENT_CONFIG_DIR/hooks" ]; then
    cp "$AGENT_CONFIG_DIR/hooks/"* "$CLAUDE_DIR/hooks/" 2>/dev/null || true
fi

# Commands: non-destructive (AGT-05 — don't overwrite GSD commands)
if [ -d "$AGENT_CONFIG_DIR/commands" ]; then
    cp -rn "$AGENT_CONFIG_DIR/commands/"* "$CLAUDE_DIR/commands/" 2>/dev/null || true
fi
```

**Why `-rn` for commands:** GSD installs 29 commands in `~/.claude/commands/gsd/`. The `-n` (no-clobber) flag ensures custom commands don't overwrite GSD commands if there's a naming conflict.

### Pattern 3: Firewall Domain Generation

**What:** Generate `firewall-domains.conf` from config.json, replacing the hardcoded DOMAINS array in `refresh-firewall-dns.sh`.

**Current flow:**
1. `refresh-firewall-dns.sh` has a hardcoded DOMAINS array (25 domains)
2. It also reads `firewall-domains.conf` for additional domains
3. It resolves all domains to IPs and adds them to the ipset

**New flow:**
1. `install-agent-config.sh` generates `firewall-domains.conf` with ALL domains:
   - Core domains (always present, hardcoded in the install script)
   - API domains: api.openai.com, generativelanguage.googleapis.com (GEN-02)
   - Extra domains from config.json: `.firewall.extra_domains`
2. `refresh-firewall-dns.sh` reads ALL domains from `firewall-domains.conf` (no hardcoded array)

**Benefits:** Single source of truth for domain configuration. Users add domains in config.json, install script generates the conf file, firewall script reads it.

### Pattern 4: Generated .vscode/settings.json

**What:** Generate `.vscode/settings.json` from config.json during install.

**Current state:** Static file committed to git with `{"git.scanRepositories": [".", "gitprojects/adventure-alerts"]}`.

**New flow:**
1. `install-agent-config.sh` reads `vscode.git_scan_paths` from config.json
2. If empty, auto-detects .git directories under `gitprojects/`
3. Always includes "." (workspace root)
4. Generates `.vscode/settings.json`

**Note:** `devcontainer.json` also provides VS Code settings via `customizations.vscode.settings` (editor formatting, terminal profile). These are separate from `.vscode/settings.json` and VS Code merges both sources. No conflict.

### Pattern 5: API Key Environment File

**What:** Write API keys to a sourced file for shell availability.

**Problem:** `install-agent-config.sh` runs as `postCreateCommand`. Environment variables set in the script don't persist to later interactive shells.

**Solution:**
1. `install-agent-config.sh` generates `~/.claude-api-env`:
   ```bash
   export OPENAI_API_KEY="sk-..."
   export GOOGLE_API_KEY="AIza..."
   ```
2. Dockerfile adds `source ~/.claude-api-env 2>/dev/null || true` to `.bashrc` and `.zshrc`
3. Idempotent: regenerating the file overwrites it (no duplicate lines)

### Pattern 6: save-secrets Helper

**What:** Captures live credentials back into `secrets.json` for backup.

**Sources captured:**
- `~/.claude/.credentials.json` -> `.claude.credentials`
- Langfuse keys from `~/.claude/settings.local.json` env section
- API keys from `~/.claude-api-env`

**Implementation:** Shell script installed to PATH, aliased as `save-secrets`.

## Common Pitfalls

### Pitfall 1: Bind Mount Removal Breaks Auth
**What goes wrong:** After removing bind mount, Claude Code can't authenticate because credentials weren't in secrets.json.

**Why it happens:** User never ran the old `save-secrets` flow or credentials weren't backed up.

**How to avoid:**
1. Before removing bind mount, ensure secrets.json has `.claude.credentials` populated
2. Test credential restoration in current container (with bind mount still active)
3. Have clear rollback: `git revert <commit>` to restore bind mount

### Pitfall 2: Firewall Conf Not Ready When Firewall Starts
**What goes wrong:** `init-firewall.sh` runs in `postStartCommand` but `firewall-domains.conf` is generated by `install-agent-config.sh` in `postCreateCommand`. If the timing is wrong, the firewall uses an old or missing conf file.

**Why it happens:** `postCreateCommand` runs once at container creation, `postStartCommand` runs on every start. The conf file persists after initial creation.

**How to avoid:**
- `postCreateCommand` runs BEFORE `postStartCommand` per devcontainer spec
- The generated `firewall-domains.conf` is on the bind-mounted workspace volume (persists)
- `postStartCommand` will always find the generated file

### Pitfall 3: cp -rn Not Available on All Systems
**What goes wrong:** `-n` (no-clobber) flag for `cp` doesn't exist on some minimal Linux installs.

**How to avoid:** The devcontainer uses Debian's coreutils which includes `-n` support. Verify with `cp --version` in Dockerfile if concerned.

### Pitfall 4: .vscode/settings.json Git Conflict
**What goes wrong:** Generated `.vscode/settings.json` conflicts with the committed version.

**How to avoid:**
1. Remove `.vscode/settings.json` from git tracking (`git rm --cached`)
2. Add `.vscode/settings.json` to `.gitignore`
3. Generate it fresh on each container creation

### Pitfall 5: generate-env.sh Interactive Prompts
**What goes wrong:** `generate-env.sh` uses `read -p` for interactive input. CRD-04 requires it to write Langfuse keys back to `secrets.json`, but the script runs interactively.

**How to avoid:** Add the secrets.json writeback at the END of generate-env.sh, after the interactive flow completes and credentials are known. Don't modify the interactive portion.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON merge (save-secrets) | sed/awk manipulation | jq | Reliable JSON manipulation |
| Template placeholder detection | Custom parser | `grep -oP '\{\{[A-Z_]+\}\}'` | Regex covers all cases |
| Directory copy with exclusion | Manual file listing | `cp -rn` with glob | Handles nested structure |
| API key env persistence | Appending to bashrc | Separate sourced file | Idempotent, no duplicates |

## Open Questions

1. **Credential format for .credentials.json**
   - What we know: `install-agent-config.sh` already writes `.claude.credentials` from secrets.json to `.credentials.json`
   - What's unclear: Exact JSON structure Claude Code expects
   - Recommendation: Capture from live container with bind mount active, then save to secrets.json as-is
   - Risk: LOW — this already works in Phase 1 implementation

2. **Plugin MCP server domains (noted in STATE.md)**
   - What we know: Claude Code plugins can bundle MCP servers that need firewall domains
   - What's unclear: Which plugin domains to whitelist
   - Recommendation: Defer to future — GEN-01 generates the conf file, users can add plugin domains to config.json extra_domains
   - Risk: LOW — not blocking for Phase 3

## Metadata

**Confidence breakdown:**
- Bind mount removal: HIGH — isolated change, well-understood devcontainer mechanism
- Asset copy pipeline: HIGH — standard cp/mkdir operations
- Firewall generation: HIGH — extending existing pattern (hardcoded list -> generated list)
- VS Code settings generation: HIGH — simple JSON generation with jq
- Credential persistence: HIGH — jq-based JSON manipulation, well-tested patterns
- save-secrets helper: MEDIUM — needs testing with live credentials, format validation

**Research date:** 2026-02-14
**Valid until:** 30 days (stable patterns)

**Key files modified in this phase:**
- `.devcontainer/devcontainer.json` (bind mount removal)
- `.devcontainer/install-agent-config.sh` (all generation logic)
- `.devcontainer/Dockerfile` (source ~/.claude-api-env, save-secrets alias)
- `.devcontainer/refresh-firewall-dns.sh` (read from generated conf instead of hardcoded array)
- `agent-config/hooks/langfuse_hook.py` (new — copy of infra/hooks/)
- `.devcontainer/save-secrets.sh` (new — credential capture helper)
- `infra/scripts/generate-env.sh` (CRD-04 — write Langfuse keys to secrets.json)
- `.gitignore` (add .vscode/settings.json)

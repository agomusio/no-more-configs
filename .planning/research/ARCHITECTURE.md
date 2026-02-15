# Architecture Integration: Plugin System

**Domain:** Claude Code Sandbox installation script enhancement
**Researched:** 2026-02-15
**Confidence:** HIGH

## Executive Summary

The plugin system integrates into the existing `install-agent-config.sh` architecture by adding four new processing stages between template hydration and GSD installation. The critical insight is that plugins must be processed AFTER settings.local.json is generated from the template but BEFORE final settings enforcement, enabling proper accumulation and merging of hook registrations, environment variables, and MCP server definitions.

The existing architecture follows a linear pipeline pattern with minimal state passing. Plugin integration extends this pattern with accumulator variables (`PLUGIN_HOOKS`, `PLUGIN_ENV`, `PLUGIN_MCP`) that collect registrations across all enabled plugins before merging into the final configuration files.

## Current Architecture Analysis

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│              Configuration Loading (Lines 39-77)             │
│  ┌─────────────────┐         ┌──────────────────┐           │
│  │  config.json    │         │  secrets.json    │           │
│  │  (optional)     │         │  (optional)      │           │
│  └────────┬────────┘         └────────┬─────────┘           │
│           │                           │                     │
│           └───────────┬───────────────┘                     │
│                       ↓                                     │
├─────────────────────────────────────────────────────────────┤
│         Artifact Generation (Lines 82-219)                   │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ Firewall conf │  │ VS Code       │  │ Codex config  │   │
│  │ (domains)     │  │ settings.json │  │ config.toml   │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
├─────────────────────────────────────────────────────────────┤
│     Asset Copying + Template Hydration (Lines 221-246)      │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐    │
│  │ Copy skills │  │ Copy hooks  │  │ Hydrate settings │    │
│  │ (221-226)   │  │ (229-235)   │  │ template (238)   │    │
│  └─────────────┘  └─────────────┘  └──────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│        Credential Restoration (Lines 248-315)                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ Claude creds  │  │ Codex creds   │  │ Git identity  │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
├─────────────────────────────────────────────────────────────┤
│         MCP + Infrastructure Setup (Lines 317-381)           │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Generate    │  │ Generate     │  │ Detect unresolved│   │
│  │ .mcp.json   │  │ infra/.env   │  │ placeholders     │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│       GSD Installation + Final Enforcement (Lines 383-408)   │
│  ┌─────────────┐                                             │
│  │ Install GSD │  →  Enforce final settings.json values     │
│  │ (npx)       │      (bypassPermissions, opus, high effort) │
│  └─────────────┘                                             │
└─────────────────────────────────────────────────────────────┘
```

### Current Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| Config loader (39-77) | Read and validate config.json + secrets.json, extract values | `jq` for JSON parsing, bash for control flow |
| Firewall generator (82-161) | Build allow-list from core + configured + detected domains | String concatenation, `jq` for array extraction |
| VS Code settings (163-192) | Generate `.vscode/settings.json` with git scan paths | `jq` for JSON generation, auto-detection from filesystem |
| Codex config (201-219) | Generate `~/.codex/config.toml` with model selection | Bash heredoc, string interpolation |
| Skills copier (221-226) | Copy `agent-config/skills/*` → `~/.claude/skills/` | `cp -r`, recursive directory copy |
| Hooks copier (229-235) | Copy `agent-config/hooks/*` → `~/.claude/hooks/` | `cp`, flat file copy |
| Template hydrator (238-246) | Replace `{{PLACEHOLDER}}` tokens in settings.json.template | `sed` substitution (inline replacement) |
| Credential restorer (248-315) | Extract credentials from secrets.json, write to runtime locations | `jq` extraction, JSON file writes |
| MCP generator (317-351) | Build `.mcp.json` from enabled server templates | `jq` merging, template hydration with `sed` |
| Infrastructure setup (354-365) | Generate `infra/.env` if secrets present | External `langfuse-setup` command |
| Placeholder detector (368-381) | Find unresolved `{{TOKENS}}`, replace with empty string | `grep -oP`, `sed -i` inline replacement |
| GSD installer (383-401) | Install GSD framework via npx | External npm command |
| Settings enforcer (403-408) | Force specific values into settings.json after GSD modifies it | `jq` mutation, file replacement |

### Key Architectural Patterns

**Pattern 1: Linear Pipeline with Minimal State**

The script follows a strict sequential execution model where each stage completes before the next begins. State is passed via environment variables and intermediate files, not bash variables (except for counters/status).

**Pattern 2: Optional Configuration with Defaults**

Every configuration source (config.json, secrets.json) is optional. The script uses `jq -r '.path // "default"'` extensively to provide fallbacks.

**Pattern 3: Template Hydration via sed**

Placeholder replacement happens in two places:
1. **settings.json.template (line 239-242)**: Three specific tokens (`LANGFUSE_HOST`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`)
2. **MCP templates (line 330)**: One token (`MCP_GATEWAY_URL`)

Both use `sed` for inline string replacement, not `jq`, because templates may be partially JSON (settings) or pure JSON (MCP).

**Pattern 4: Non-Destructive Overwrites**

The script is designed to be re-runnable. Files are regenerated on each run, but certain directories (like GSD) are protected from re-installation if they already exist.

### Current Data Flow

```
config.json + secrets.json
    ↓ (jq extraction)
Variables: LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, MCP_GATEWAY_URL
    ↓
settings.json.template
    ↓ (sed hydration)
settings.local.json (generated, contains env + hooks from template)
    ↓
settings.json (seeded with permissions structure)
    ↓ (GSD modifies this file)
settings.json (final — enforced values overwrite GSD changes)
```

**Critical observation:** `settings.local.json` is generated from the template and never modified again. `settings.json` is the file that gets modified by GSD and then enforced at the end. The two files serve different purposes:
- `settings.local.json`: User-specific configuration (env vars, hooks)
- `settings.json`: Application state (permissions, model selection, effort level)

### Current Hook Registration Mechanism

In `settings.json.template`:
```json
{
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

This structure is **nested twice**: `hooks.Stop` is an array containing objects with a `hooks` property, which contains the actual hook definitions. This is critical for understanding how plugin hooks must be merged.

## Plugin System Integration Points

### New Components Required

| Component | Responsibility | Insert After | Insert Before |
|-----------|----------------|--------------|---------------|
| Standalone commands copier | Copy `agent-config/commands/*.md` → `~/.claude/commands/` (non-destructive) | Hooks copy (line 235) | Template hydration (line 238) |
| Plugin processor | Iterate plugins, check enabled status, copy files, accumulate registrations | Template hydration (line 246) | Credential restoration (line 248) |
| Hook merger | Merge accumulated plugin hooks into `settings.local.json` | Plugin processor | MCP generation (line 317) |
| Env merger | Merge accumulated plugin env vars into `settings.local.json` | Hook merger | MCP generation (line 317) |
| MCP merger | Merge accumulated plugin MCP servers into `.mcp.json` | Env merger | **AFTER** MCP generation (line 351) |

### Critical Insertion Point Analysis

**Why plugins MUST be processed after template hydration:**

1. `settings.local.json` must exist before merging plugin hooks/env into it
2. Template hydration creates the base structure with infrastructure env vars (LANGFUSE_*, etc.)
3. Plugin hooks/env are **additive** — they merge into existing structure, not replace

**Why plugin MCP merge MUST happen after MCP generation (line 351):**

The existing MCP generation builds `.mcp.json` from `config.json` enabled server templates. Plugin MCP servers are additional to these, so plugin merge must happen after the base `.mcp.json` exists. Otherwise, plugin MCP servers would be overwritten.

**Current tech debt identified (from spec):**

Line 338 in current script: `echo "$MCP_JSON" > "$CLAUDE_DIR/.mcp.json"` — this **overwrites** the file. Plugin MCP merge cannot happen before this line or it will be lost.

### Recommended Installation Order (Modified)

```
1.  Read config.json + secrets.json (existing: lines 39-77)
2.  Generate firewall-domains.conf (existing: lines 82-161)
3.  Generate .vscode/settings.json (existing: lines 163-192)
4.  Generate Codex config.toml (existing: lines 201-219)
5.  Create ~/.claude/ directory structure (existing: lines 194-199)
6.  Copy standalone skills (existing: lines 221-226)
7.  Copy standalone hooks (existing: lines 229-235)
8.  **NEW: Copy standalone commands** → insert at line 236
9.  Hydrate settings.json.template → settings.local.json (existing: line 238-246)
10. Seed settings.json with permissions (existing: lines 248-253)
11. **NEW: Process plugins (copy files, accumulate registrations)** → insert at line 247
12. **NEW: Merge plugin hooks into settings.local.json** → after plugin processing
13. **NEW: Merge plugin env vars into settings.local.json** → after hook merge
14. Restore Claude credentials (existing: lines 255-286)
15. Restore Codex credentials (existing: lines 288-301)
16. Restore git identity (existing: lines 303-315)
17. Generate MCP config from templates (existing: lines 317-351)
18. **NEW: Merge plugin MCP servers into .mcp.json** → insert after line 351
19. Generate infra/.env (existing: lines 354-365)
20. Detect unresolved placeholders (existing: lines 368-381)
21. Install GSD framework (existing: lines 383-401)
22. Enforce settings.json final values (existing: lines 403-408)
23. Print summary (existing: lines 410-423)
```

## Data Flow Changes

### New Accumulator Variables

```bash
# Initialized after template hydration, before plugin processing
PLUGIN_HOOKS='{}'    # JSON object: { "Stop": [...], "SessionStart": [...] }
PLUGIN_ENV='{}'      # JSON object: { "VAR_NAME": "value", ... }
PLUGIN_MCP='{}'      # JSON object: { "server-name": { "command": "...", ... }, ... }
PLUGIN_COUNT=0       # Integer counter for summary
COMMANDS_COUNT=0     # Integer counter for summary
```

These variables accumulate during plugin iteration (step 11) and are consumed by merge steps (12-13, 18).

### Plugin Processing Flow

```
for each plugin_dir in agent-config/plugins/*/
    ↓
Check config.json: is plugin enabled? (default: true)
    ↓ (if disabled: skip)
Validate plugin.json exists and is valid JSON
    ↓
Copy plugin files to runtime locations:
  - plugin/skills/*     → ~/.claude/skills/
  - plugin/hooks/*      → ~/.claude/hooks/
  - plugin/agents/*.md  → ~/.claude/agents/ (skip gsd-*.md)
  - plugin/commands/*.md → ~/.claude/commands/
    ↓
Accumulate plugin.json registrations:
  - plugin.json → hooks   → PLUGIN_HOOKS (jq merge)
  - plugin.json → env     → PLUGIN_ENV (jq merge)
  - config.json override  → PLUGIN_ENV (jq merge, takes precedence)
  - plugin.json → mcp_servers → PLUGIN_MCP (jq merge)
    ↓
Increment PLUGIN_COUNT
    ↓
Next plugin
```

### Hook Merging Data Flow

**Input:**
- `settings.local.json` (existing, generated from template)
- `PLUGIN_HOOKS` (accumulated JSON object)

**Current template structure (from line 15-26 of settings.json.template):**
```json
{
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

**Plugin hook format (from spec):**
```json
{
  "Stop": [
    {
      "type": "command",
      "command": "python3 ~/.claude/hooks/my-hook.py"
    }
  ]
}
```

**Critical merging challenge:** The template uses a nested structure (`hooks.Stop[].hooks[]`) while plugins declare a flat structure (`Stop[]`). The merge logic must:

1. Extract existing template hooks from `settings.local.json`
2. For each event in `PLUGIN_HOOKS`, append to the array
3. Maintain the nested structure expected by Claude Code

**Correct jq merge logic:**

```bash
# This handles both existing events (append) and new events (create)
jq --argjson plugin_hooks "$PLUGIN_HOOKS" '
  ($plugin_hooks | to_entries) as $new_hooks |
  .hooks = (
    .hooks // {} |
    reduce $new_hooks[] as $entry (
      .;
      if has($entry.key) then
        # Event exists in template — append to first element's hooks array
        .[$entry.key][0].hooks += $entry.value
      else
        # New event from plugin — create structure
        .[$entry.key] = [{"hooks": $entry.value}]
      end
    )
  )
' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

### Environment Variable Merging Data Flow

**Input:**
- `settings.local.json` (existing)
- `PLUGIN_ENV` (accumulated, with config.json overrides already applied)

**Process:**
1. Read existing `settings.local.json`
2. Add all keys from `PLUGIN_ENV` to `.env` object
3. Write back to file

**jq logic:**

```bash
jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

This is simple additive merge. If a key exists in both template and plugin, plugin wins (which is correct behavior).

### MCP Server Merging Data Flow

**Input:**
- `.mcp.json` (existing, generated from templates at line 338)
- `PLUGIN_MCP` (accumulated, needs {{TOKEN}} hydration)

**Critical ordering constraint:** This MUST happen after line 351 (MCP generation complete).

**Process:**
1. Hydrate `{{PLACEHOLDER}}` tokens in `PLUGIN_MCP` from secrets.json
2. Read existing `.mcp.json`
3. Merge `PLUGIN_MCP` into `.mcpServers` object
4. Write back to file

**Hydration challenge:** Plugin MCP servers may use `{{TOKENS}}` that aren't in the standard set (LANGFUSE_*, MCP_GATEWAY_URL). The spec proposes generic hydration (line 370-372), but this is incomplete.

**Recommended approach:**

```bash
# Extract all {{TOKENS}} from PLUGIN_MCP
TOKENS=$(echo "$PLUGIN_MCP" | grep -oP '\{\{[A-Z_]+\}\}' | sort -u)

# For each token, look up in secrets.json and replace
HYDRATED_MCP="$PLUGIN_MCP"
for TOKEN in $TOKENS; do
    # Extract token name (remove {{ }})
    TOKEN_NAME=$(echo "$TOKEN" | sed 's/{{//g; s/}}//g')

    # Look up value in secrets.json (search all nested paths)
    # Use jq to recursively search for the key
    TOKEN_VALUE=$(jq -r --arg key "$TOKEN_NAME" '
        .. | objects | select(has($key)) | .[$key] // ""
    ' "$SECRETS_FILE" 2>/dev/null | head -1)

    # Replace in MCP JSON
    if [ -n "$TOKEN_VALUE" ]; then
        HYDRATED_MCP=$(echo "$HYDRATED_MCP" | sed "s|$TOKEN|$TOKEN_VALUE|g")
    else
        echo "[install] WARNING: Token $TOKEN in plugin MCP server not found in secrets.json"
        # Leave as empty string (handled by placeholder detector later)
        HYDRATED_MCP=$(echo "$HYDRATED_MCP" | sed "s|$TOKEN||g")
    fi
done

# Merge into .mcp.json
jq --argjson plugin_mcp "$HYDRATED_MCP" '.mcpServers += $plugin_mcp' \
    "$MCP_FILE" > "$MCP_FILE.tmp" \
    && mv "$MCP_FILE.tmp" "$MCP_FILE"
```

## Architectural Patterns for Plugin System

### Pattern 1: Accumulator-Then-Merge

**What:** Process all plugins to accumulate registrations in bash variables (as JSON strings), then merge all at once after processing completes.

**Why:** Prevents multiple file writes during plugin iteration. Each merge operation reads → modifies → writes a file, which is expensive and error-prone. Accumulating first allows single-pass merging.

**Trade-offs:**
- PRO: Faster, fewer file I/O operations
- PRO: Easier to validate accumulated JSON before merging
- CON: Requires bash variables to hold potentially large JSON strings
- CON: If one plugin has invalid JSON, detection happens late (during accumulation, not iteration)

**Implementation:**
```bash
PLUGIN_HOOKS='{}'

for plugin_dir in agent-config/plugins/*/; do
    MANIFEST="$plugin_dir/plugin.json"
    # Accumulate hooks using jq merge
    PLUGIN_HOOKS=$(jq -s '
        .[0] as $acc |
        .[1].hooks // {} |
        to_entries |
        reduce .[] as $entry (
            $acc;
            .[$entry.key] = ((.[$entry.key] // []) + $entry.value)
        )
    ' <(echo "$PLUGIN_HOOKS") "$MANIFEST")
done

# After loop: merge once
jq --argjson hooks "$PLUGIN_HOOKS" '.hooks = ...' settings.local.json
```

### Pattern 2: Config Override Precedence

**What:** Three-tier precedence for plugin configuration:
1. Plugin defaults (from `plugin.json`)
2. Config.json overrides (from `config.json → plugins → {plugin-name} → env`)
3. Accumulated result used in merge

**Why:** Allows users to customize plugin behavior without editing plugin files.

**Implementation:**
```bash
# 1. Get plugin defaults
PLUGIN_ENV_DEFAULTS=$(jq -r '.env // {}' "$MANIFEST")

# 2. Get config.json overrides for this plugin
PLUGIN_ENV_OVERRIDES=$(jq -r --arg name "$plugin_name" \
    '.plugins[$name].env // {}' "$CONFIG_FILE")

# 3. Merge (overrides win)
PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_DEFAULTS" "$PLUGIN_ENV_OVERRIDES" | \
    jq -s '.[0] * .[1] * .[2]')
```

### Pattern 3: Non-Destructive File Copying with GSD Protection

**What:** When copying plugin files to runtime locations, protect GSD-owned paths from being overwritten.

**Why:** GSD is installed last via npx and its files should never be replaced by plugin content (which runs earlier). GSD owns:
- `~/.claude/commands/gsd/*`
- `~/.claude/agents/gsd-*.md`

**Implementation:**
```bash
# For plugin commands
for cmd_file in "$plugin_dir/commands/"*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")

    # Skip if file is in gsd directory or is a gsd- prefixed agent
    if [[ "$cmd_name" == "gsd" ]] || [[ "$cmd_name" =~ ^gsd- ]]; then
        continue
    fi

    cp "$cmd_file" "$CLAUDE_DIR/commands/"
done
```

### Pattern 4: Graceful Degradation on Invalid Plugin

**What:** If a plugin has invalid `plugin.json` or missing manifest, skip the plugin entirely with a warning, but continue processing other plugins.

**Why:** One broken plugin shouldn't break the entire installation.

**Implementation:**
```bash
if [ ! -f "$MANIFEST" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' has no plugin.json — skipping"
    continue
fi

if ! validate_json "$MANIFEST" "plugins/$plugin_name/plugin.json"; then
    continue  # validate_json already printed error
fi
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Merging Plugin MCP Before Template MCP Generation

**What people might do:** Insert plugin MCP merge before line 351 (MCP generation) because "plugins should be processed early"

**Why it's wrong:** Line 338 overwrites `.mcp.json` with `echo "$MCP_JSON" > "$CLAUDE_DIR/.mcp.json"`. Any plugin MCP servers merged before this line will be lost.

**Do this instead:** Always merge plugin MCP servers AFTER the base `.mcp.json` is written (after line 351).

### Anti-Pattern 2: Using Simple Hook Array Concatenation

**What people might do:**
```bash
# WRONG — doesn't match Claude Code's expected structure
jq '.hooks.Stop += $plugin_hooks' settings.local.json
```

**Why it's wrong:** Claude Code expects `hooks.Stop[].hooks[]` (nested arrays), not `hooks.Stop[]` (flat array). This would break hook execution.

**Do this instead:** Use the correct nested structure merge shown in "Hook Merging Data Flow" section.

### Anti-Pattern 3: Modifying settings.json Instead of settings.local.json

**What people might do:** Merge plugin hooks/env into `settings.json` because "that's the main config file"

**Why it's wrong:**
- `settings.json` is modified by GSD installer (line 391)
- Final enforcement overwrites values in `settings.json` (line 405)
- Plugin hooks/env would be lost or overwritten

**Do this instead:** Always merge into `settings.local.json`, which is read by Claude Code alongside `settings.json` but never modified after generation.

### Anti-Pattern 4: Using Bash String Manipulation for JSON

**What people might do:**
```bash
# WRONG — fragile and breaks on special characters
HOOKS="${HOOKS}, {\"type\": \"command\", \"command\": \"$cmd\"}"
```

**Why it's wrong:** Bash string manipulation can't safely handle JSON escaping, nested structures, or validation.

**Do this instead:** Always use `jq` for JSON manipulation. It handles escaping, validation, and structure preservation correctly.

## Integration Implementation Checklist

### New Code Blocks Required

**Block 1: Standalone Commands Copier** (insert after line 235)
```bash
# Copy standalone commands (non-destructive)
COMMANDS_COUNT=0
if [ -d "$AGENT_CONFIG_DIR/commands" ]; then
    mkdir -p "$CLAUDE_DIR/commands"
    for cmd_file in "$AGENT_CONFIG_DIR/commands"/*.md; do
        [ -f "$cmd_file" ] || continue
        cmd_name=$(basename "$cmd_file")
        # Don't overwrite existing commands (e.g., GSD)
        if [ ! -f "$CLAUDE_DIR/commands/$cmd_name" ]; then
            cp "$cmd_file" "$CLAUDE_DIR/commands/"
            COMMANDS_COUNT=$((COMMANDS_COUNT + 1))
        fi
    done
    echo "[install] Copied $COMMANDS_COUNT standalone command(s)"
fi
```

**Block 2: Plugin Processor** (insert after line 246, before credential restoration)
```bash
# Process plugins
PLUGIN_COUNT=0
PLUGIN_HOOKS='{}'
PLUGIN_ENV='{}'
PLUGIN_MCP='{}'

if [ -d "$AGENT_CONFIG_DIR/plugins" ]; then
    for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name=$(basename "$plugin_dir")

        # Check if plugin is disabled in config.json
        PLUGIN_ENABLED="true"
        if [ -f "$CONFIG_FILE" ]; then
            PLUGIN_ENABLED=$(jq -r --arg name "$plugin_name" \
                '.plugins[$name].enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
        fi

        if [ "$PLUGIN_ENABLED" = "false" ]; then
            echo "[install] Plugin '$plugin_name': disabled in config.json, skipping"
            continue
        fi

        # Validate plugin.json exists
        MANIFEST="$plugin_dir/plugin.json"
        if [ ! -f "$MANIFEST" ]; then
            echo "[install] WARNING: Plugin '$plugin_name' has no plugin.json — skipping"
            continue
        fi

        if ! validate_json "$MANIFEST" "plugins/$plugin_name/plugin.json"; then
            continue
        fi

        # Copy plugin files to runtime locations
        [ -d "$plugin_dir/skills" ] && cp -r "$plugin_dir/skills/"* "$CLAUDE_DIR/skills/" 2>/dev/null || true
        [ -d "$plugin_dir/hooks" ] && cp "$plugin_dir/hooks/"* "$CLAUDE_DIR/hooks/" 2>/dev/null || true

        # Copy agents (skip GSD-owned files)
        if [ -d "$plugin_dir/agents" ]; then
            for agent_file in "$plugin_dir/agents/"*.md; do
                [ -f "$agent_file" ] || continue
                agent_name=$(basename "$agent_file")
                if [[ ! "$agent_name" =~ ^gsd- ]]; then
                    cp "$agent_file" "$CLAUDE_DIR/agents/"
                fi
            done
        fi

        # Copy commands (skip GSD directory)
        if [ -d "$plugin_dir/commands" ]; then
            for cmd_file in "$plugin_dir/commands/"*.md; do
                [ -f "$cmd_file" ] || continue
                cmd_name=$(basename "$cmd_file")
                if [[ "$cmd_name" != "gsd" ]]; then
                    cp "$cmd_file" "$CLAUDE_DIR/commands/"
                fi
            done
        fi

        # Accumulate hook registrations
        MANIFEST_HOOKS=$(jq -r '.hooks // {}' "$MANIFEST" 2>/dev/null || echo "{}")
        if [ "$MANIFEST_HOOKS" != "{}" ]; then
            PLUGIN_HOOKS=$(jq -s '
                .[0] as $acc | .[1] | to_entries |
                reduce .[] as $entry (
                    $acc;
                    .[$entry.key] = ((.[$entry.key] // []) + $entry.value)
                )
            ' <(echo "$PLUGIN_HOOKS") <(echo "$MANIFEST_HOOKS") 2>/dev/null || echo "$PLUGIN_HOOKS")
        fi

        # Accumulate env vars (plugin.json defaults, config.json overrides)
        MANIFEST_ENV=$(jq -r '.env // {}' "$MANIFEST" 2>/dev/null || echo "{}")
        CONFIG_ENV_OVERRIDE='{}'
        if [ -f "$CONFIG_FILE" ]; then
            CONFIG_ENV_OVERRIDE=$(jq -r --arg name "$plugin_name" \
                '.plugins[$name].env // {}' "$CONFIG_FILE" 2>/dev/null || echo "{}")
        fi
        # Merge: accumulated < manifest defaults < config overrides win
        PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$MANIFEST_ENV" "$CONFIG_ENV_OVERRIDE" | \
            jq -s '.[0] * .[1] * .[2]' 2>/dev/null || echo "$PLUGIN_ENV")

        # Accumulate MCP servers
        MANIFEST_MCP=$(jq -r '.mcp_servers // {}' "$MANIFEST" 2>/dev/null || echo "{}")
        if [ "$MANIFEST_MCP" != "{}" ]; then
            PLUGIN_MCP=$(echo "$PLUGIN_MCP" "$MANIFEST_MCP" | \
                jq -s '.[0] * .[1]' 2>/dev/null || echo "$PLUGIN_MCP")
        fi

        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
        echo "[install] Plugin '$plugin_name': installed"
    done

    echo "[install] Processed $PLUGIN_COUNT plugin(s)"
fi
```

**Block 3: Hook + Env Mergers** (immediately after Block 2)
```bash
# Merge plugin hooks into settings.local.json
if [ "$PLUGIN_HOOKS" != "{}" ]; then
    SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
    if [ -f "$SETTINGS_FILE" ]; then
        jq --argjson plugin_hooks "$PLUGIN_HOOKS" '
            ($plugin_hooks | to_entries) as $new_hooks |
            .hooks = (
                .hooks // {} |
                reduce $new_hooks[] as $entry (
                    .;
                    if has($entry.key) then
                        .[$entry.key][0].hooks += $entry.value
                    else
                        .[$entry.key] = [{"hooks": $entry.value}]
                    end
                )
            )
        ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "[install] Merged plugin hooks into settings.local.json"
    fi
fi

# Merge plugin env vars into settings.local.json
if [ "$PLUGIN_ENV" != "{}" ]; then
    SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
    if [ -f "$SETTINGS_FILE" ]; then
        jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
            "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "[install] Merged plugin env vars into settings.local.json"
    fi
fi
```

**Block 4: MCP Merger** (insert after line 351, after existing MCP generation)
```bash
# Merge plugin MCP servers into .mcp.json
if [ "$PLUGIN_MCP" != "{}" ]; then
    MCP_FILE="$CLAUDE_DIR/.mcp.json"
    if [ -f "$MCP_FILE" ]; then
        # Hydrate {{PLACEHOLDER}} tokens from secrets.json
        HYDRATED_MCP="$PLUGIN_MCP"
        if [ -f "$SECRETS_FILE" ]; then
            # Extract all {{TOKEN}} patterns
            TOKENS=$(echo "$PLUGIN_MCP" | grep -oP '\{\{[A-Z_]+\}\}' | sort -u || true)
            for TOKEN in $TOKENS; do
                TOKEN_NAME=$(echo "$TOKEN" | sed 's/[{}]//g')
                # Recursive search in secrets.json for this key
                TOKEN_VALUE=$(jq -r --arg key "$TOKEN_NAME" '
                    .. | objects | to_entries[] | select(.key == $key) | .value
                ' "$SECRETS_FILE" 2>/dev/null | head -1 || echo "")

                if [ -n "$TOKEN_VALUE" ]; then
                    HYDRATED_MCP=$(echo "$HYDRATED_MCP" | sed "s|$TOKEN|$TOKEN_VALUE|g")
                else
                    echo "[install] WARNING: Token $TOKEN in plugin MCP config not found in secrets.json"
                    HYDRATED_MCP=$(echo "$HYDRATED_MCP" | sed "s|$TOKEN||g")
                fi
            done
        fi

        jq --argjson plugin_mcp "$HYDRATED_MCP" '.mcpServers += $plugin_mcp' \
            "$MCP_FILE" > "$MCP_FILE.tmp" \
            && mv "$MCP_FILE.tmp" "$MCP_FILE"
        echo "[install] Merged plugin MCP servers into .mcp.json"
    fi
fi
```

**Block 5: Summary Updates** (modify existing summary section at lines 410-423)
```bash
# Add to summary output (after existing lines)
echo "[install] Commands: $COMMANDS_COUNT standalone command(s)"
echo "[install] Plugins: $PLUGIN_COUNT plugin(s)"
```

### Modified Installation Order (Final)

```
Lines 39-77:    Read config.json + secrets.json
Lines 82-161:   Generate firewall-domains.conf
Lines 163-192:  Generate .vscode/settings.json
Lines 201-219:  Generate Codex config.toml
Lines 194-199:  Create ~/.claude/ directories
Lines 221-226:  Copy standalone skills
Lines 229-235:  Copy standalone hooks
NEW Block 1:     Copy standalone commands
Lines 238-246:  Hydrate settings.json.template → settings.local.json
Lines 248-253:  Seed settings.json
NEW Block 2:     Process plugins (copy files, accumulate registrations)
NEW Block 3:     Merge plugin hooks + env into settings.local.json
Lines 255-286:  Restore Claude credentials
Lines 288-301:  Restore Codex credentials
Lines 303-315:  Restore git identity
Lines 317-351:  Generate .mcp.json from templates
NEW Block 4:     Merge plugin MCP servers into .mcp.json
Lines 354-365:  Generate infra/.env
Lines 368-381:  Detect unresolved placeholders
Lines 383-401:  Install GSD framework
Lines 403-408:  Enforce settings.json final values
Lines 410-423:  Print summary (+ NEW Block 5 additions)
```

## Tech Debt Resolution

### Current Issue: MCP Generation Overwrites

**Problem:** Line 338 uses `>` (overwrite) instead of merging.

**Impact:** If we later want to support MCP servers defined directly in config.json (not via templates), they would be lost.

**Resolution for plugin system:** Plugin MCP merge happens AFTER line 351, so it's safe. But the design is fragile.

**Recommended improvement (future):** Change line 338 to build into a variable, then write once at the end:

```bash
# Instead of writing at line 338
MCP_JSON_FINAL="$MCP_JSON"

# After plugin merge
MCP_JSON_FINAL=$(echo "$MCP_JSON_FINAL" | jq --argjson plugin "$PLUGIN_MCP" '.mcpServers += $plugin')

# Write once
echo "$MCP_JSON_FINAL" > "$CLAUDE_DIR/.mcp.json"
```

### Hook Structure Complexity

**Problem:** The nested `hooks.Stop[0].hooks[]` structure is non-obvious and fragile. Why not `hooks.Stop[]` directly?

**Likely reason:** Claude Code may support multiple hook "groups" per event, each with different execution policies (parallel, sequential, conditional). The outer array level allows for this.

**Impact on plugin system:** Merge logic is more complex but still deterministic. Documented in this research.

**Recommendation:** Accept the structure as-is. Attempting to "simplify" it would break compatibility with Claude Code's expectations.

## Sources

**HIGH Confidence — Direct examination:**
- `/workspace/.devcontainer/install-agent-config.sh` (current implementation)
- `/workspace/agent-config/settings.json.template` (hook structure)
- `/workspace/.planning/nmc-plugin-spec.md` (plugin requirements)
- `/workspace/config.json` (configuration schema)

**HIGH Confidence — Tool behavior:**
- `jq` manual and testing (JSON merging patterns)
- `bash` parameter expansion and control flow (POSIX sh compatibility)

**MEDIUM Confidence — Inferred from code patterns:**
- Claude Code's expected settings.json structure (inferred from template)
- Hook execution model (inferred from nested structure)

---
*Architecture research for: Claude Code Sandbox Plugin System Integration*
*Researched: 2026-02-15*

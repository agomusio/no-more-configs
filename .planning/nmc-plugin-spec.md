# NMC Plugin & Agent Config Integration Spec

> **Purpose:** Define how skills, commands, agents, hooks, and plugins are structured, installed, and controlled in No More Configs. This spec builds on the existing v1 `agent-config/` system and adds a plugin layer with hook registration.

---

## Hierarchy of Control

```
config.json (master)
 └── controls which plugins are enabled/disabled, overrides settings
      └── plugin.json (manifest per plugin)
           └── declares what the plugin offers (hooks, MCP servers, env vars)
                └── file conventions (auto-detected)
                     └── skills/, commands/, agents/ copied if present
```

`config.json` always wins. A plugin can declare whatever it wants in `plugin.json` — the install script only installs what `config.json` allows.

---

## Directory Layout

### `agent-config/` after this integration

```
agent-config/
├── settings.json.template       # Claude Code settings (hydrated from config.json + secrets.json)
├── mcp-templates/                # MCP server templates (unchanged)
│   ├── mcp-gateway.json
│   └── codex.json
│
├── skills/                       # Standalone skills (not part of any plugin)
│   ├── aa-fullstack/
│   │   └── SKILL.md
│   ├── aa-cloudflare/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── ...
│   ├── devcontainer/
│   │   └── SKILL.md
│   └── gitprojects/
│       └── SKILL.md
│
├── hooks/                        # Standalone hooks (not part of any plugin)
│   └── (empty after langfuse migrates to a plugin — see Migration section)
│
├── commands/                     # NEW: Standalone slash commands
│   └── (user-defined .md files)
│
└── plugins/                      # NEW: Bundled packages of skills + commands + agents + hooks
    └── langfuse-tracing/         # Example: the existing langfuse hook as a plugin
        ├── plugin.json
        └── hooks/
            └── langfuse_hook.py
```

### Runtime locations (inside the container)

| Source | Destination |
|---|---|
| `agent-config/skills/*` | `~/.claude/skills/` |
| `agent-config/commands/*` | `~/.claude/commands/` (non-destructive, GSD not overwritten) |
| `agent-config/hooks/*` | `~/.claude/hooks/` |
| `agent-config/plugins/*/skills/*` | `~/.claude/skills/` |
| `agent-config/plugins/*/commands/*` | `~/.claude/commands/` |
| `agent-config/plugins/*/agents/*` | `~/.claude/agents/` (non-destructive, GSD not overwritten) |
| `agent-config/plugins/*/hooks/*` | `~/.claude/hooks/` |
| Plugin hook registrations | Merged into `~/.claude/settings.local.json` |
| GSD (via npx) | `~/.claude/commands/gsd/` + `~/.claude/agents/gsd-*.md` |

---

## Standalone Components (no plugin required)

These work exactly as they do today. Drop files in, rebuild, done.

### Skills

A directory under `agent-config/skills/` with at minimum a `SKILL.md` file.

```
agent-config/skills/my-skill/
├── SKILL.md          # Required — skill definition with YAML front matter
└── references/       # Optional — supporting docs
    └── api.md
```

Copied to `~/.claude/skills/my-skill/` preserving directory structure. No registration needed — Claude Code auto-discovers skills from the skills directory.

### Commands

A markdown file under `agent-config/commands/`. The filename becomes the slash command name.

```
agent-config/commands/
├── review-code.md      # Available as /review-code in Claude sessions
└── write-tests.md      # Available as /write-tests in Claude sessions
```

Copied to `~/.claude/commands/`. The copy is non-destructive — existing files (particularly `gsd/`) are not overwritten.

### Hooks (standalone)

Script files under `agent-config/hooks/`. These are copied to `~/.claude/hooks/` but **still require manual registration** in `settings.json.template` to fire on events. Standalone hooks are for cases where you want to manage the registration yourself in the template.

For hooks that should be self-registering, use a plugin instead.

---

## Plugins

A plugin is a directory under `agent-config/plugins/` that bundles related functionality together. The key difference from standalone components: **plugins can self-register hooks** via a `plugin.json` manifest.

### Plugin structure

```
agent-config/plugins/my-plugin/
├── plugin.json           # Required — manifest declaring hooks, env vars, MCP servers
├── skills/               # Optional — skills bundled with this plugin
│   └── my-skill/
│       └── SKILL.md
├── commands/             # Optional — slash commands bundled with this plugin
│   └── do-thing.md
├── agents/               # Optional — agent definitions bundled with this plugin
│   └── my-agent.md
└── hooks/                # Optional — hook scripts referenced by plugin.json
    └── my-hook.py
```

Only `plugin.json` is required. All subdirectories are optional — a plugin might only register a hook with no other files, or only provide skills with no hooks.

### `plugin.json` manifest

```jsonc
{
  "name": "my-plugin",
  "description": "What this plugin does",
  "version": "1.0.0",

  // Hook registrations — merged into settings.local.json
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "python3 ~/.claude/hooks/my-hook.py"
      }
    ],
    "SessionStart": [
      {
        "type": "command",
        "command": "node ~/.claude/hooks/my-startup.js"
      }
    ]
  },

  // Additional env vars injected into settings.local.json → env
  "env": {
    "MY_PLUGIN_ENABLED": "true",
    "MY_PLUGIN_ENDPOINT": "http://localhost:9999"
  },

  // MCP server to register (optional — alternative to mcp-templates/)
  "mcp_servers": {
    "my-server": {
      "command": "npx",
      "args": ["-y", "my-mcp-server"],
      "env": { "API_KEY": "{{MY_API_KEY}}" }
    }
  }
}
```

**Field details:**

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Plugin identifier (must match directory name) |
| `description` | No | Human-readable description |
| `version` | No | Semver version string |
| `hooks` | No | Hook registrations keyed by event (`Stop`, `SessionStart`, `StatusLine`, etc.) |
| `env` | No | Environment variables added to `settings.local.json` → `env` |
| `mcp_servers` | No | MCP server definitions merged into `~/.claude/.mcp.json` (tokens hydrated from `secrets.json`) |

### `config.json` plugin control

```json
{
  "plugins": {
    "langfuse-tracing": { "enabled": true },
    "noisy-plugin": { "enabled": false },
    "custom-plugin": {
      "enabled": true,
      "env": {
        "MY_PLUGIN_ENDPOINT": "http://custom-host:8080"
      }
    }
  }
}
```

**Rules:**

1. If a plugin exists in `agent-config/plugins/` but is **not mentioned** in `config.json` → **enabled** by default. Drop it in, it works.
2. If `config.json` sets `"enabled": false` → plugin is fully skipped (no files copied, no hooks registered, no env vars set).
3. If `config.json` provides `env` overrides → they take precedence over the plugin's `plugin.json` → `env` values.
4. `config.json` cannot add hook registrations — only plugins declare hooks. `config.json` can only enable/disable entire plugins.

---

## Install Script Changes

The following additions go into `install-agent-config.sh`, after existing skills/hooks copy and before GSD installation.

### Copy standalone commands

```bash
# Copy standalone commands (non-destructive)
COMMANDS_COUNT=0
if [ -d "$AGENT_CONFIG_DIR/commands" ]; then
    for cmd_file in "$AGENT_CONFIG_DIR/commands"/*.md; do
        [ -f "$cmd_file" ] || continue
        cmd_name=$(basename "$cmd_file")
        # Don't overwrite existing commands (e.g., GSD)
        if [ ! -f "$CLAUDE_DIR/commands/$cmd_name" ]; then
            cp "$cmd_file" "$CLAUDE_DIR/commands/"
        fi
        COMMANDS_COUNT=$((COMMANDS_COUNT + 1))
    done
    echo "[install] Copied $COMMANDS_COUNT command(s) to $CLAUDE_DIR/commands/"
fi
```

### Install plugins

```bash
# Install plugins
PLUGIN_COUNT=0
PLUGIN_HOOKS='{}'  # Accumulates hook registrations across all plugins
PLUGIN_ENV='{}'    # Accumulates env vars across all plugins
PLUGIN_MCP='{}'    # Accumulates MCP servers across all plugins

if [ -d "$AGENT_CONFIG_DIR/plugins" ]; then
    for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name=$(basename "$plugin_dir")

        # Check if plugin is disabled in config.json
        if [ -f "$CONFIG_FILE" ]; then
            PLUGIN_ENABLED=$(jq -r --arg name "$plugin_name" \
                '.plugins[$name].enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
            if [ "$PLUGIN_ENABLED" = "false" ]; then
                echo "[install] Plugin '$plugin_name': disabled in config.json, skipping"
                continue
            fi
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
        [ -d "$plugin_dir/agents" ] && {
            for agent_file in "$plugin_dir/agents/"*.md; do
                [ -f "$agent_file" ] || continue
                agent_name=$(basename "$agent_file")
                # Don't overwrite GSD agents
                if [ ! -f "$CLAUDE_DIR/agents/$agent_name" ] || [[ ! "$agent_name" =~ ^gsd- ]]; then
                    cp "$agent_file" "$CLAUDE_DIR/agents/"
                fi
            done
        }
        [ -d "$plugin_dir/commands" ] && {
            for cmd_file in "$plugin_dir/commands/"*.md; do
                [ -f "$cmd_file" ] || continue
                cp "$cmd_file" "$CLAUDE_DIR/commands/"
            done
        }

        # Accumulate hook registrations from plugin.json
        PLUGIN_HOOKS=$(jq -s --arg name "$plugin_name" \
            '.[0] as $acc | .[1].hooks // {} | to_entries[] |
             .key as $event | .value as $hooks |
             $acc | .[$event] = ((.[$event] // []) + $hooks)' \
            <(echo "$PLUGIN_HOOKS") "$MANIFEST" 2>/dev/null || echo "$PLUGIN_HOOKS")

        # Accumulate env vars (plugin.json defaults, config.json overrides)
        PLUGIN_ENV_FROM_MANIFEST=$(jq -r '.env // {}' "$MANIFEST" 2>/dev/null || echo "{}")
        PLUGIN_ENV_OVERRIDES='{}'
        if [ -f "$CONFIG_FILE" ]; then
            PLUGIN_ENV_OVERRIDES=$(jq -r --arg name "$plugin_name" \
                '.plugins[$name].env // {}' "$CONFIG_FILE" 2>/dev/null || echo "{}")
        fi
        # Merge: manifest defaults, then config.json overrides win
        PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" "$PLUGIN_ENV_OVERRIDES" | \
            jq -s '.[0] * .[1] * .[2]' 2>/dev/null || echo "$PLUGIN_ENV")

        # Accumulate MCP servers from plugin.json
        PLUGIN_MCP_SERVERS=$(jq -r '.mcp_servers // {}' "$MANIFEST" 2>/dev/null || echo "{}")
        if [ "$PLUGIN_MCP_SERVERS" != "{}" ]; then
            PLUGIN_MCP=$(echo "$PLUGIN_MCP" "$PLUGIN_MCP_SERVERS" | \
                jq -s '.[0] * .[1]' 2>/dev/null || echo "$PLUGIN_MCP")
        fi

        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
        echo "[install] Plugin '$plugin_name': installed"
    done

    echo "[install] Installed $PLUGIN_COUNT plugin(s)"
fi
```

### Merge plugin registrations into settings

After template hydration and plugin installation, merge all accumulated plugin data into the generated settings:

```bash
# Merge plugin hooks into settings.local.json
if [ "$PLUGIN_HOOKS" != "{}" ]; then
    # Read existing settings
    SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
    if [ -f "$SETTINGS_FILE" ]; then
        # Merge plugin hooks with template hooks
        # Template hooks (e.g., standalone langfuse) are preserved
        # Plugin hooks are appended under each event key
        jq --argjson plugin_hooks "$PLUGIN_HOOKS" '
            .hooks as $existing |
            ($plugin_hooks | to_entries) |
            reduce .[] as $entry ($existing // {};
                .[$entry.key] = ((.[$entry.key] // []) + [{
                    "hooks": $entry.value
                }])
            ) | . as $merged |
            input | .hooks = $merged
        ' <(echo "$PLUGIN_HOOKS") "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
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

# Merge plugin MCP servers into .mcp.json
if [ "$PLUGIN_MCP" != "{}" ]; then
    MCP_FILE="$CLAUDE_DIR/.mcp.json"
    if [ -f "$MCP_FILE" ]; then
        # Hydrate any {{PLACEHOLDER}} tokens from secrets.json
        HYDRATED_MCP="$PLUGIN_MCP"
        if [ -f "$SECRETS_FILE" ]; then
            # Extract all placeholder tokens and replace from secrets
            HYDRATED_MCP=$(echo "$PLUGIN_MCP" | sed "s|{{MCP_GATEWAY_URL}}|$MCP_GATEWAY_URL|g")
            # Add more hydration as needed for plugin-specific secrets
        fi

        jq --argjson plugin_mcp "$HYDRATED_MCP" '.mcpServers += $plugin_mcp' \
            "$MCP_FILE" > "$MCP_FILE.tmp" \
            && mv "$MCP_FILE.tmp" "$MCP_FILE"
        echo "[install] Merged plugin MCP servers into .mcp.json"
    fi
fi
```

### Summary line addition

```bash
echo "[install] Commands: $COMMANDS_COUNT command(s)"
echo "[install] Plugins: $PLUGIN_COUNT plugin(s)"
```

---

## Installation Order

The full install sequence with plugins integrated:

1. Read `config.json` + `secrets.json`
2. Generate firewall-domains.conf
3. Generate .vscode/settings.json
4. Generate Codex config.toml
5. Create `~/.claude/` directory structure
6. **Copy standalone skills** → `~/.claude/skills/`
7. **Copy standalone hooks** → `~/.claude/hooks/`
8. **Copy standalone commands** → `~/.claude/commands/`
9. Hydrate `settings.json.template` → `~/.claude/settings.local.json`
10. Seed `~/.claude/settings.json` with permissions
11. **Install plugins** (copy files + accumulate hook/env/MCP registrations)
12. **Merge plugin hooks** into `settings.local.json`
13. **Merge plugin env vars** into `settings.local.json`
14. **Merge plugin MCP servers** into `.mcp.json`
15. Restore Claude credentials
16. Restore Codex credentials
17. Restore git identity
18. Generate MCP config from `config.json` templates
19. Generate `infra/.env` if applicable
20. Detect unresolved `{{PLACEHOLDER}}` tokens
21. Install GSD framework (npx)
22. Enforce `settings.json` final values (bypassPermissions, opus, high effort)
23. Print summary

---

## Migration: Langfuse Hook → Plugin

The existing langfuse hook is currently a standalone hook with hardcoded registration in `settings.json.template`. To migrate it to the plugin system:

### Before (current)

```
agent-config/
├── hooks/
│   └── langfuse_hook.py          # Script lives here
└── settings.json.template        # Registration hardcoded here
```

### After (plugin)

```
agent-config/
├── hooks/                         # Empty (or removed)
├── plugins/
│   └── langfuse-tracing/
│       ├── plugin.json
│       └── hooks/
│           └── langfuse_hook.py
└── settings.json.template         # Stop hook registration REMOVED from template
```

**`plugins/langfuse-tracing/plugin.json`:**

```json
{
  "name": "langfuse-tracing",
  "description": "Traces Claude Code conversations to a local Langfuse instance",
  "version": "1.0.0",
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "python3 ~/.claude/hooks/langfuse_hook.py"
      }
    ]
  },
  "env": {
    "TRACE_TO_LANGFUSE": "true"
  }
}
```

The Langfuse env vars (`LANGFUSE_HOST`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`) stay in the settings template since they're hydrated from `config.json` and `secrets.json` — they're not plugin-specific configuration, they're infrastructure wiring.

**To disable tracing:** set `"langfuse-tracing": { "enabled": false }` in `config.json` → `plugins`. No file deletion needed.

This migration is optional and non-breaking — the current standalone approach works fine. But it demonstrates the plugin pattern and makes tracing togglable from `config.json`.

---

## Example: Creating a Custom Plugin

Say you want a plugin that runs a linter after every Claude response and provides a `/lint` slash command.

### 1. Create the plugin directory

```
agent-config/plugins/auto-lint/
├── plugin.json
├── hooks/
│   └── run-linter.sh
└── commands/
    └── lint.md
```

### 2. Write the manifest

**`plugin.json`:**

```json
{
  "name": "auto-lint",
  "description": "Runs ESLint after every Claude response and provides /lint command",
  "version": "1.0.0",
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "bash ~/.claude/hooks/run-linter.sh"
      }
    ]
  }
}
```

### 3. Write the hook script

**`hooks/run-linter.sh`:**

```bash
#!/bin/bash
# Find changed JS/TS files and lint them
cd /workspace/gitprojects/my-project 2>/dev/null || exit 0
git diff --name-only --diff-filter=M -- '*.js' '*.ts' '*.tsx' | head -20 | xargs npx eslint --fix 2>/dev/null || true
exit 0  # Non-blocking — always exit 0
```

### 4. Write the slash command

**`commands/lint.md`:**

```markdown
Run ESLint on all modified files in the current project and fix auto-fixable issues. Report any remaining errors.
```

### 5. Done

Rebuild the container. The plugin's hook fires after every Claude response, the `/lint` command is available in sessions, and you can disable it anytime:

```json
{ "plugins": { "auto-lint": { "enabled": false } } }
```

---

## Edge Cases

1. **Plugin name conflicts.** If a plugin provides a skill with the same name as a standalone skill, the plugin's version overwrites the standalone one (plugins are installed after standalone files). Document this — last write wins.

2. **Multiple plugins registering the same hook event.** All registrations are merged. If three plugins register `Stop` hooks, all three fire. Order is determined by filesystem sort order of plugin directory names (alphabetical).

3. **Plugin hook references a script that doesn't exist.** The hook registration still gets written to `settings.local.json`, but Claude Code will log an error when the event fires. The install script could validate this and warn, but shouldn't block.

4. **GSD protection.** The install script must never overwrite `~/.claude/commands/gsd/` or `~/.claude/agents/gsd-*.md` with plugin content. GSD is installed last (via npx) and its files are protected.

5. **Plugin env var conflicts.** If two plugins set the same env var, last-alphabetically wins. If `config.json` overrides the var, `config.json` always wins. Document this precedence.

6. **Missing `plugin.json`.** Plugin directory is skipped with a warning. Files are not copied. This prevents partial installations from plugins that are being developed.

7. **Plugin provides MCP server with `{{PLACEHOLDER}}` tokens.** Tokens are hydrated from `secrets.json` using the same mechanism as `mcp-templates/`. If the secret is missing, the token becomes an empty string and a warning is printed.

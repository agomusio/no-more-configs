# Stack Research: Plugin System Integration

**Domain:** DevContainer Configuration & Plugin System
**Researched:** 2026-02-15
**Confidence:** HIGH

## Recommended Stack

### Core Technologies (Already Present)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Bash** | 5.2.15+ | Install script orchestration, plugin file operations | Standard shell in Debian containers, proven robust for file operations and JSON processing pipelines. Native support for directory iteration with shopt safety options. |
| **jq** | 1.6+ | JSON parsing, template hydration, deep merging | De facto standard for shell-based JSON manipulation. Built-in recursive merge with `*` operator, efficient reduce patterns for accumulation, widely used in container init scripts. |
| **Python** | 3.11.2+ | Hook execution runtime (existing langfuse_hook.py) | Already present for langfuse hook. No new dependency. Widely used for event hooks due to rich stdlib and JSON support. |
| **Node.js** | 20.20.0+ | Hook execution runtime (optional), potential schema validation | Already present for GSD framework. Enables JavaScript-based hooks. Optional for ajv-cli schema validation if needed. |

### Supporting Libraries (NEW for Plugin System)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **ajv-cli** | 5.0.0 (or @jirutka/ajv-cli 6.0.0) | JSON schema validation for plugin.json manifests | Optional. Only install if strict schema validation is required. jq's basic validation (`jq empty < file`) is sufficient for MVP. |
| None required | - | Deep merge, iteration, hydration all handled by bash + jq | The existing stack is sufficient. No new runtime dependencies needed. |

### Development Tools (No Changes)

| Tool | Purpose | Notes |
|------|---------|-------|
| **VS Code Dev Container** | Container orchestration | Already configured. Plugin system integrates transparently. |
| **Docker Desktop + WSL2** | Container runtime | Existing infrastructure. No changes needed. |
| **Git** | Credential restoration, identity config | Already handled by install-agent-config.sh. No plugin impact. |

## Installation

**No new packages required for core plugin functionality.**

All capabilities needed for the plugin system are already present in the container:
- Bash 5.2 for directory iteration and file operations
- jq 1.6 for JSON parsing and deep merge
- Python 3.11 for hook execution (existing)
- Node.js 20 for hook execution (existing)

### Optional: JSON Schema Validation

If strict plugin.json schema validation is desired (beyond jq's basic validation), install ajv-cli:

```bash
# Option 1: Official (unmaintained, last update 5 years ago)
npm install -g ajv-cli@5.0.0

# Option 2: Community fork (maintained, last update 1 year ago)
npm install -g @jirutka/ajv-cli@6.0.0
```

**Recommendation:** Skip schema validation tooling for MVP. Use jq's built-in validation (`jq empty < file`) which is already in the codebase pattern (line 22-27 of install-agent-config.sh). Add ajv-cli later if schema enforcement becomes critical.

## Core Patterns for Plugin System

### 1. Deep JSON Merge with jq 1.6

**Pattern:** Use `*` operator for recursive merge of nested objects.

```bash
# Merge plugin hooks into accumulated hooks object
PLUGIN_HOOKS=$(echo "$PLUGIN_HOOKS" "$NEW_HOOKS" | jq -s '.[0] * .[1]')
```

**Why:** The `*` operator recursively merges nested objects at all depths, preserving keys from both sources. The `+` operator only merges top-level keys (right side wins for conflicts). For plugin hook registration where multiple plugins can register hooks for the same event, we need recursive merge to preserve all registrations.

**Source:** [jq 1.6 Manual](https://jqlang.org/manual/v1.6/), [How to Recursively Merge JSON Objects](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/)

### 2. Array Accumulation with reduce

**Pattern:** Use `reduce` to accumulate hook arrays per event.

```bash
# Accumulate hooks from plugin.json into PLUGIN_HOOKS
PLUGIN_HOOKS=$(jq -s --arg name "$plugin_name" '
    .[0] as $acc | .[1].hooks // {} | to_entries[] |
    .key as $event | .value as $hooks |
    $acc | .[$event] = ((.[$event] // []) + $hooks)
' <(echo "$PLUGIN_HOOKS") "$MANIFEST")
```

**Why:** The reduce pattern safely accumulates arrays across multiple plugins. For each event type (Stop, SessionStart, etc.), concatenate hook arrays rather than overwriting. This allows multiple plugins to register hooks for the same event without conflicts.

**Source:** [jq Manual - reduce](https://jqlang.org/manual/), [Guide to Passing Bash Variables to jq](https://techkluster.com/linux/jq-passing-bash-variables/)

### 3. Safe Directory Iteration

**Pattern:** Use shopt options with glob patterns.

```bash
# Iterate over plugin directories safely
shopt -s nullglob  # Glob expands to nothing if no matches (prevents literal "*" in loop)
for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do
    [ -d "$plugin_dir" ] || continue
    plugin_name=$(basename "$plugin_dir")
    # ... process plugin
done
```

**Why:** `nullglob` prevents the loop from running with a literal `*` string if no plugins exist. The `[ -d "$plugin_dir" ] || continue` pattern guards against edge cases. Always quote variables (`"$plugin_dir"`) to handle spaces safely.

**Alternative:** `shopt -s dotglob` is NOT needed here (we don't want hidden directories like `.git` as plugins).

**Source:** [Bash Globbing Tutorial](https://linuxhint.com/bash_globbing_tutorial/), [Bash Scripting: The Complete Guide for 2026](https://devtoolbox.dedyn.io/blog/bash-scripting-complete-guide)

### 4. JSON Validation Pattern (Existing)

**Pattern:** Reuse existing `validate_json` function from install-agent-config.sh.

```bash
# From install-agent-config.sh (lines 19-27)
validate_json() {
    local file="$1"
    local label="$2"
    if ! jq empty < "$file" &>/dev/null; then
        echo "[install] ERROR: $label is not valid JSON — skipping"
        return 1
    fi
    return 0
}

# Usage in plugin installation
if ! validate_json "$MANIFEST" "plugins/$plugin_name/plugin.json"; then
    continue
fi
```

**Why:** Reuse existing pattern. `jq empty` validates JSON syntax without processing content. Returns exit code 1 on parse errors. Sufficient for catching malformed plugin.json files. No external schema validator needed unless strict schema enforcement is required.

**Source:** [How To Check the Validity of JSON with jq](https://pavolkutaj.medium.com/how-to-check-the-validity-of-json-with-jq-in-bash-scripts-21523418f67d)

### 5. Template Hydration Pattern (Existing)

**Pattern:** Reuse sed-based token replacement from existing install script.

```bash
# Hydrate MCP server definitions from plugin.json
HYDRATED_MCP=$(echo "$PLUGIN_MCP" | sed "s|{{MCP_GATEWAY_URL}}|$MCP_GATEWAY_URL|g")

# For multiple secrets, chain sed commands
HYDRATED=$(sed -e "s|{{LANGFUSE_HOST}}|$LANGFUSE_HOST|g" \
               -e "s|{{LANGFUSE_PUBLIC_KEY}}|$LANGFUSE_PUBLIC_KEY|g" \
               "$TEMPLATE_FILE")
```

**Why:** Consistent with existing hydration pattern (lines 239-242 of install-agent-config.sh). Sed handles simple token replacement efficiently. For complex scenarios, could use jq's string interpolation, but sed is proven and readable for this use case.

**Source:** Existing codebase pattern, standard Unix text processing.

### 6. Non-Destructive File Copy

**Pattern:** Check existence before copying to avoid overwriting protected files.

```bash
# Don't overwrite GSD commands
for cmd_file in "$plugin_dir/commands/"*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    if [ ! -f "$CLAUDE_DIR/commands/$cmd_name" ]; then
        cp "$cmd_file" "$CLAUDE_DIR/commands/"
    fi
done

# Alternative: explicit GSD protection
if [ ! -f "$CLAUDE_DIR/agents/$agent_name" ] || [[ ! "$agent_name" =~ ^gsd- ]]; then
    cp "$agent_file" "$CLAUDE_DIR/agents/"
fi
```

**Why:** Plugin files should not overwrite GSD framework files (installed via npx). GSD owns `~/.claude/commands/gsd/` and `~/.claude/agents/gsd-*.md`. Test for file existence or pattern match before copy.

**Source:** Spec requirement (lines 549, 273-280 of nmc-plugin-spec.md)

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **jq for JSON** | yq (YAML processor) | If plugin manifests need to support YAML format. Not needed — JSON is universal and already standard in this codebase. |
| **jq for JSON** | Python json module | If complex JSON transformations exceed jq's capabilities. Not needed — jq handles all plugin system requirements efficiently. |
| **Bash loops** | find command | For very large plugin directories (100+). Current scale (likely <10 plugins) makes bash loops more readable. |
| **sed for hydration** | jq string interpolation | If token replacement needs conditional logic or format transformations. Current simple token swap is perfect for sed. |
| **No schema validator** | ajv-cli | If plugin manifest schemas become complex and need strict enforcement. Start simple, add if needed. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **ls in loops** | Output parsing is fragile (breaks on spaces, newlines, special chars). Anti-pattern in 2026. | Glob patterns with shopt options (`for dir in */`) |
| **jq -s for large files** | Loads all JSON into memory. Can cause OOM on large files (>5GB). | `jq -n 'reduce inputs as $item ({}; . * $item)'` for memory efficiency |
| **Array overwrite with +** | `{hooks: [A]} + {hooks: [B]}` results in `{hooks: [B]}` (loses A). Wrong for multi-plugin hook accumulation. | Use reduce with array concatenation or `*` for objects |
| **Unquoted variables** | `cp $file $dest` breaks on spaces. Shell expansion gotcha. | Always quote: `cp "$file" "$dest"` |
| **External JSON schema libs** | Adds npm/pip dependencies for validation. Overkill for MVP. | `jq empty < file` for syntax validation |

## Stack Patterns by Integration Point

### For Plugin File Copy
- Use bash glob with `nullglob`: `for dir in */`
- Quote all variables: `"$plugin_dir"`
- Guard with existence checks: `[ -f "$file" ] || continue`
- Protect GSD files: test before copy

### For Hook Registration Merge
- Use jq reduce to accumulate per-event arrays
- Pass JSON objects with `--argjson`: `jq --argjson hooks "$PLUGIN_HOOKS"`
- Use process substitution for multi-source merge: `jq -s '...' <(echo "$A") <(echo "$B")`
- Store accumulated state in bash variables: `PLUGIN_HOOKS=$(jq ...)`

### For Env Var Merge
- Use jq `*` operator for recursive merge: `jq -s '.[0] * .[1] * .[2]'`
- Precedence: manifest defaults → config.json overrides
- Example: `MERGED=$(echo "$DEFAULTS" "$OVERRIDES" | jq -s '.[0] * .[1]')`

### For MCP Server Merge
- Reuse existing MCP template hydration pattern
- Hydrate plugin MCP servers with sed: `sed "s|{{TOKEN}}|$VALUE|g"`
- Merge into .mcp.json with jq: `jq '.mcpServers += $plugin_mcp'`
- Handle missing secrets gracefully (replace with empty string, warn)

### For Validation
- Reuse existing `validate_json()` function
- Validate before processing: `validate_json "$file" "$label" || continue`
- Don't block on warnings (missing optional fields)
- Block on errors (malformed JSON, missing required name field)

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| **jq 1.6** | Bash 5.2 | Stable pairing. jq 1.7-1.8 available but 1.6 is sufficient. No breaking changes needed. |
| **jq 1.6** | Python 3.11, Node 20 | Completely independent. jq processes JSON in shell, doesn't interact with hook runtimes. |
| **Bash 5.2** | Debian 12 (bookworm) | Default bash in current Debian stable. shopt, glob, process substitution all stable. |
| **Python 3.11** | langfuse-sdk, requests | Existing hook runtime. No version conflicts with plugin system. |
| **Node 20** | npx, GSD framework | Existing for GSD install. Compatible with potential JS-based hooks. |

## jq Version Considerations

**Current:** jq 1.6 (2018 release, very stable)

**Latest:** jq 1.8.1 (2026 recommendation per web research)

**Decision:** Stay on jq 1.6 for now. All required features available:
- `*` operator for recursive merge (since 1.5)
- `reduce` for accumulation (since 1.3)
- `--argjson` for variable passing (since 1.2)
- Process substitution support (bash feature, not jq version dependent)

**Upgrade path:** If jq 1.7+ becomes available in Debian repos, upgrade is drop-in compatible. No script changes needed.

## Integration Points with Existing install-agent-config.sh

### Reuse Patterns

| Existing Pattern | Lines | How Plugins Use It |
|------------------|-------|-------------------|
| JSON validation | 19-27 | Validate plugin.json manifests |
| Skill directory copy | 222-227 | Copy plugin skills/ to ~/.claude/skills/ |
| Hook file copy | 229-235 | Copy plugin hooks/ to ~/.claude/hooks/ |
| Template hydration | 239-242 | Hydrate plugin MCP server configs |
| Settings.json merge | 405-408 | Merge plugin hooks/env into settings |
| MCP config merge | 318-351 | Merge plugin MCP servers into .mcp.json |

### New Patterns Needed

| Pattern | Purpose | Implementation |
|---------|---------|----------------|
| Plugin directory iteration | Find all plugins in agent-config/plugins/ | `for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/` with nullglob |
| Plugin enabled check | Read config.json plugins section | `jq -r '.plugins[$name].enabled // true' "$CONFIG_FILE"` |
| Hook accumulation | Collect hooks across all plugins | `jq reduce` pattern with per-event arrays |
| Env var override | Merge manifest defaults + config overrides | `jq -s '.[0] * .[1] * .[2]'` (defaults, manifest, overrides) |
| Agent non-destructive copy | Don't overwrite GSD agents | Existence check + gsd- prefix pattern match |

### Installation Order Impact

The spec defines installation order (lines 390-422 of nmc-plugin-spec.md). Key constraints:

1. **Standalone files before plugins:** Plugins can override standalone skills/hooks (last write wins)
2. **Plugin copy before merge:** All plugin files copied before hook/env/MCP merge step
3. **Settings hydration before plugin merge:** Template generates base settings, then plugins augment
4. **Plugin merge before GSD:** Plugin hooks/env/MCP in place before GSD framework install
5. **GSD before final enforcement:** GSD modifies settings.json, then final values enforced

**No stack changes needed** — bash sequential execution naturally handles this ordering.

## Sources

### Core Technology Documentation
- [jq 1.6 Manual](https://jqlang.org/manual/v1.6/) — Recursive merge operator, reduce patterns
- [How to Recursively Merge JSON Objects](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/) — Deep merge examples
- [Bash Globbing Tutorial](https://linuxhint.com/bash_globbing_tutorial/) — Safe glob patterns with shopt
- [Bash Scripting: The Complete Guide for 2026](https://devtoolbox.dedyn.io/blog/bash-scripting-complete-guide) — Modern bash patterns

### JSON Processing
- [How to Merge JSON Files Using jq](https://copyprogramming.com/howto/how-to-merge-json-files-using-jq-or-any-tool) — Merge strategies 2026
- [Guide to Passing Bash Variables to jq](https://techkluster.com/linux/jq-passing-bash-variables/) — --argjson patterns
- [How To Check the Validity of JSON with jq](https://pavolkutaj.medium.com/how-to-check-the-validity-of-json-with-jq-in-bash-scripts-21523418f67d) — Validation patterns

### Schema Validation (Optional)
- [ajv-cli - npm](https://www.npmjs.com/package/ajv-cli) — Official CLI (v5.0.0, unmaintained)
- [@jirutka/ajv-cli - npm](https://www.npmjs.com/package/@jirutka/ajv-cli) — Community fork (v6.0.0, maintained)
- [How to Validate JSON from the Command Line](https://linuxhint.com/validate-json-files-from-command-line-linux/) — Validation tools comparison

### Existing Codebase
- /workspace/.devcontainer/install-agent-config.sh — Current implementation patterns
- /workspace/.planning/nmc-plugin-spec.md — Plugin system specification

---
*Stack research for: Claude Code Sandbox Plugin System*
*Researched: 2026-02-15*
*Confidence: HIGH — All patterns verified against existing codebase and current documentation*

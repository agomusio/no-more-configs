# Phase 6: Langfuse Migration & Validation - Research

**Researched:** 2026-02-15
**Domain:** Bash shell scripting, plugin system migration, validation patterns
**Confidence:** HIGH

## Summary

Phase 6 migrates the hardcoded Langfuse tracing hook to the plugin system (validating Phases 4-5) and adds validation warnings + install summaries for debugging plugin issues. This is NOT about building new infrastructure — the plugin system exists. This phase uses it and enhances it with user-facing diagnostics.

The technical domain is straightforward: (1) restructure existing Langfuse code into plugin format, (2) add validation checks to the existing install script loop, (3) extend the existing summary output. The migration serves as the reference implementation for future plugins.

**Primary recommendation:** Keep validation minimal and actionable. Warn on real problems (missing files, broken JSON, conflicts), not hypotheticals. The install summary should be scannable — one line per plugin with counts, warnings recapped at end.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Migration approach
- Clean break — remove Langfuse from settings.json.template entirely, plugin system is the only path
- Delete the old hardcoded hook file (agent-config/hooks/langfuse_hook.py) after migration — no dead files
- Plugin manifest (plugin.json) should be minimal — only declare what Langfuse actually uses (hooks, env, MCP), not a showcase of all possible fields

#### Warning behavior
- Warnings appear inline as encountered AND are recapped in the final summary
- Invalid plugin.json = error — skip the entire plugin, warn, continue with other plugins
- All other issues (missing scripts, overwrites, empty env) are warnings, never fatal to the install

#### Install summary
- Full detail — show per-plugin breakdown of what was registered
- Compact list format: `langfuse-tracing: 1 hook, 2 env, 1 MCP`
- Integrate plugin summary into the existing install summary block (not a separate section)
- Include a dedicated warnings recap section at the end with full warning messages repeated

#### Validation strictness
- Missing hook script file → warn and skip the entire plugin (not just the bad hook)
- Env vars declared in plugin.json but empty after merge → warn the user
- Invalid plugin.json → friendly error message first, then raw JSON parse error on next line
- File overwrite between plugins → Claude's discretion on resolution strategy

### Claude's Discretion

- Warning prefix format (e.g., [WARN], plugin: WARNING, etc.) — match existing install script style
- Warning visual styling (colors, symbols) — match existing output conventions
- Hook script location within plugin directory structure
- File overwrite conflict resolution strategy (first wins vs last wins)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | Shell scripting | Alpine/Debian default, POSIX-compliant |
| jq | 1.6+ | JSON processing | Industry standard for shell JSON manipulation |
| Python 3 | 3.11+ | Hook scripts | Claude Code hook runtime requirement |
| langfuse | 2.x (Python SDK) | Tracing | Existing dependency in requirements.txt |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| sed | GNU sed | Text substitution | Template token hydration |
| grep | GNU grep | Pattern extraction | Token detection, validation |
| find | GNU findutils | File discovery | Counting plugin files |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq for JSON validation | python -m json.tool | jq already required, no benefit |
| Inline warnings | Log file only | Users need immediate feedback during install |
| shellcheck | Manual review | Not available in container, manual review sufficient |

**Installation:**

No new dependencies required. All tools already present in the devcontainer.

## Architecture Patterns

### Recommended Project Structure

```
agent-config/
├── plugins/
│   └── langfuse-tracing/          # New plugin directory
│       ├── plugin.json             # Manifest declaring hook/env/MCP
│       └── hooks/
│           └── langfuse_hook.py    # Moved from agent-config/hooks/
├── hooks/                          # (langfuse_hook.py deleted after migration)
└── settings.json.template          # (Langfuse hook/env removed)
```

### Pattern 1: Plugin Manifest Structure (Minimal)

**What:** Declare only what the plugin actually uses — no empty arrays, no unused fields

**When to use:** Every plugin.json file

**Example:**
```json
{
  "name": "langfuse-tracing",
  "version": "1.0.0",
  "description": "Claude Code conversation tracing to Langfuse",
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "python3 /home/node/.claude/hooks/langfuse_hook.py"
      }
    ]
  },
  "env": {
    "TRACE_TO_LANGFUSE": "true",
    "LANGFUSE_HOST": "{{LANGFUSE_HOST}}",
    "LANGFUSE_PUBLIC_KEY": "{{LANGFUSE_PUBLIC_KEY}}",
    "LANGFUSE_SECRET_KEY": "{{LANGFUSE_SECRET_KEY}}"
  }
}
```

**Source:** User decision — minimal plugin.json, existing Phase 4-5 implementations (nmc, frontend-design plugins)

### Pattern 2: Validation Check Pattern

**What:** Check condition, increment warning counter, print inline warning, store for recap

**When to use:** Any validation that shouldn't be fatal to install

**Example:**
```bash
# Array to accumulate warning messages for recap
declare -a PLUGIN_WARNING_MESSAGES=()

# Validation check
if [ ! -f "$hook_script_file" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' hook references non-existent file: $hook_file"
    PLUGIN_WARNINGS=$((PLUGIN_WARNINGS + 1))
    PLUGIN_WARNING_MESSAGES+=("Plugin '$plugin_name': hook references non-existent file: $hook_file")
    PLUGIN_SKIPPED=$((PLUGIN_SKIPPED + 1))
    continue  # Skip entire plugin
fi
```

**Source:** Existing install script patterns (lines 341-343, 369-370, 412-413), user decision on warning behavior

### Pattern 3: Install Summary Integration

**What:** Extend existing summary block with plugin details, don't create parallel output

**When to use:** Final summary section

**Example:**
```bash
echo "[install] --- Summary ---"
echo "[install] Config: $CONFIG_STATUS"
echo "[install] Secrets: $SECRETS_STATUS"
# ... existing lines ...
echo "[install] Plugins: $PLUGIN_INSTALLED installed, $PLUGIN_SKIPPED skipped"
if [ "$PLUGIN_WARNINGS" -gt 0 ]; then
    echo "[install] Plugin warnings: $PLUGIN_WARNINGS (see recap below)"
fi
# ... rest of summary ...
echo "[install] Done."

# Warnings recap (if any)
if [ "$PLUGIN_WARNINGS" -gt 0 ]; then
    echo "[install] --- Warnings Recap ---"
    for warning in "${PLUGIN_WARNING_MESSAGES[@]}"; do
        echo "[install] ⚠ $warning"
    done
fi
```

**Source:** User decision on summary format, existing install script summary (lines 760-775)

### Pattern 4: Hook Script Validation

**What:** Validate declared hook scripts exist before copying

**When to use:** During plugin loop, after manifest parsing

**Example:**
```bash
# After parsing manifest hooks, validate referenced scripts exist
MANIFEST_HOOKS=$(jq -r '.hooks // {}' "$MANIFEST" 2>/dev/null)
if [ "$MANIFEST_HOOKS" != "{}" ] && [ "$MANIFEST_HOOKS" != "null" ]; then
    # Extract all hook commands and check if script files exist
    hook_commands=$(echo "$MANIFEST_HOOKS" | jq -r '.[][] | select(.type == "command") | .command' 2>/dev/null || true)

    for hook_cmd in $hook_commands; do
        # Extract script path from command (handles: python3 /path/to/script.py)
        hook_script=$(echo "$hook_cmd" | awk '{for(i=1;i<=NF;i++) if($i ~ /\.py$|\.sh$/) print $i}')

        if [ -n "$hook_script" ]; then
            # Check if script exists in plugin directory
            hook_basename=$(basename "$hook_script")
            if [ ! -f "$plugin_dir/hooks/$hook_basename" ]; then
                echo "[install] WARNING: Plugin '$plugin_name' hook references non-existent script: $hook_basename"
                PLUGIN_WARNINGS=$((PLUGIN_WARNINGS + 1))
                PLUGIN_WARNING_MESSAGES+=("Plugin '$plugin_name': hook script missing: $hook_basename")
                PLUGIN_SKIPPED=$((PLUGIN_SKIPPED + 1))
                continue 2  # Skip entire plugin (continue outer loop)
            fi
        fi
    done
fi
```

**Source:** User decision on validation strictness (missing hook → skip plugin), VAL-01 requirement

### Anti-Patterns to Avoid

- **Fatal errors for plugin issues:** Don't exit 1 for bad plugins — warn and continue with other plugins
- **Silent failures:** Don't skip validation without informing the user — every check must produce output
- **Duplicate warnings:** Store warnings in array for recap, don't re-generate at recap time
- **Inconsistent prefixes:** Use `[install]` prefix consistently, match existing script style
- **Hook path assumptions:** Don't assume hooks/ subdirectory exists — validate before accessing

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | String manipulation, regex | jq | Handles escaping, nested structures, edge cases |
| JSON validation | Custom parser | jq empty < file | Built-in, returns proper exit codes |
| File locking | Sleep loops, PID files | fcntl.flock (Python) | Race-condition free, OS-level guarantee |
| Atomic writes | Direct overwrites | tmp file + mv | Crash-safe, prevents corruption |
| Hook command parsing | awk/sed chains | jq with proper filters | JSON-aware, handles quoted args |

**Key insight:** The install script already uses jq extensively and correctly. Don't introduce new parsing mechanisms — follow existing patterns.

## Common Pitfalls

### Pitfall 1: Invalid JSON Halts Plugin Discovery

**What goes wrong:** jq parse failure terminates the plugin loop instead of skipping one plugin

**Why it happens:** Default bash error handling (`set -e`) causes exit on first jq error

**How to avoid:** Wrap jq calls with `|| echo "{}"` fallbacks, validate JSON before parsing

**Warning signs:** Script exits mid-plugin-loop, no summary printed

**Example:**
```bash
# BAD: Will exit script on invalid JSON
MANIFEST_HOOKS=$(jq -r '.hooks // {}' "$MANIFEST")

# GOOD: Falls back to empty object on parse error
MANIFEST_HOOKS=$(jq -r '.hooks // {}' "$MANIFEST" 2>/dev/null || echo "{}")
```

### Pitfall 2: Warnings Lost to Log Scroll

**What goes wrong:** Users miss warnings because they scroll past during container build

**Why it happens:** Inline-only warnings disappear from view, no final recap

**How to avoid:** Store warnings in array, print recap after summary

**Warning signs:** Users report "it worked" but plugins aren't loaded

**Example:**
```bash
# Store warning for recap
PLUGIN_WARNING_MESSAGES+=("Plugin '$plugin_name': missing required field 'version'")

# Later, after summary:
if [ ${#PLUGIN_WARNING_MESSAGES[@]} -gt 0 ]; then
    echo "[install] --- Warnings Recap ---"
    for msg in "${PLUGIN_WARNING_MESSAGES[@]}"; do
        echo "[install] ⚠ $msg"
    done
fi
```

### Pitfall 3: Hook Script Path Extraction Fails on Complex Commands

**What goes wrong:** Validation can't extract script path from commands like `bash -c 'python3 /path/to/hook.py'`

**Why it happens:** Simple awk patterns don't handle quoting, nested commands

**How to avoid:** Design plugin.json format to use simple commands, validate against that constraint

**Warning signs:** False negatives (validation passes but hook fails at runtime)

**Example:**
```bash
# Extract script assuming simple command format: "python3 /path/to/script.py"
# NOT supporting: "bash -c 'python3 /path/to/script.py'"
hook_script=$(echo "$hook_cmd" | awk '{for(i=1;i<=NF;i++) if($i ~ /\.py$|\.sh$/) print $i}')
```

**User guidance:** Document in nmc-plugin-spec.md that hook commands must be simple (interpreter + script path), not shell expressions.

### Pitfall 4: Empty Env Var Detection After Hydration

**What goes wrong:** Declared env vars empty after merging but before template hydration, false positives

**Why it happens:** Checking emptiness too early in the install flow

**How to avoid:** Check after ALL merging/hydration, or check template tokens not values

**Warning signs:** Warnings for `LANGFUSE_PUBLIC_KEY=""` even when secrets.json has the value

**Example:**
```bash
# BAD: Check in plugin loop (before hydration)
if [ -z "$(echo "$PLUGIN_ENV" | jq -r '.LANGFUSE_PUBLIC_KEY')" ]; then
    echo "WARNING: Empty env var"
fi

# GOOD: Check after final merge into settings.json
# Or check for unresolved {{TOKEN}} placeholders instead of empty strings
```

### Pitfall 5: Hook File Overwrite Detection Complexity

**What goes wrong:** Detecting if plugin A's hook file conflicts with plugin B's hook file requires tracking

**Why it happens:** Plugins processed in sequence, no lookahead

**How to avoid:** Build a map of file→plugin as you go, check map before copy

**Warning signs:** Later plugins silently overwrite earlier plugins' hook files

**Example:**
```bash
# Track which plugin owns each hook file
declare -A HOOK_FILE_OWNERS

# Before copying hook
hook_basename=$(basename "$hook_file")
if [ -n "${HOOK_FILE_OWNERS[$hook_basename]}" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' hook file '$hook_basename' conflicts with plugin '${HOOK_FILE_OWNERS[$hook_basename]}' — skipping"
    PLUGIN_WARNINGS=$((PLUGIN_WARNINGS + 1))
    PLUGIN_WARNING_MESSAGES+=("Plugin '$plugin_name': hook file '$hook_basename' conflicts with '${HOOK_FILE_OWNERS[$hook_basename]}'")
    # Decision: first wins (skip this plugin's copy)
    continue
else
    HOOK_FILE_OWNERS[$hook_basename]="$plugin_name"
    cp "$hook_file" "$CLAUDE_DIR/hooks/"
fi
```

## Code Examples

Verified patterns from existing codebase:

### Invalid plugin.json Handling

```bash
# Source: .devcontainer/install-agent-config.sh:332-336
# Validate plugin.json is valid JSON
if ! validate_json "$MANIFEST" "plugins/$plugin_name/plugin.json"; then
    PLUGIN_SKIPPED=$((PLUGIN_SKIPPED + 1))
    continue
fi
```

Where `validate_json` is:
```bash
# Source: .devcontainer/install-agent-config.sh:18-27
validate_json() {
    local file="$1"
    local label="$2"
    if ! jq empty < "$file" &>/dev/null; then
        echo "[install] ERROR: $label is not valid JSON — skipping"
        return 1
    fi
    return 0
}
```

**Enhancement for Phase 6:** Add friendly error before generic message, show parse error details:
```bash
validate_json() {
    local file="$1"
    local label="$2"
    if ! jq empty < "$file" &>/dev/null; then
        echo "[install] ERROR: $label has invalid JSON format"
        # Show actual parse error
        local parse_error
        parse_error=$(jq empty < "$file" 2>&1 || true)
        echo "[install]   Parse error: $parse_error"
        return 1
    fi
    return 0
}
```

### Per-Plugin Detail Logging (Current Implementation)

```bash
# Source: .devcontainer/install-agent-config.sh:449-468
detail_parts=()
[ "${plugin_skills:-0}" -gt 0 ] && detail_parts+=("${plugin_skills} skill(s)")
[ "${plugin_hooks_count:-0}" -gt 0 ] && detail_parts+=("${plugin_hooks_count} hook(s)")
[ "${plugin_cmds:-0}" -gt 0 ] && detail_parts+=("${plugin_cmds} command(s)")
[ "${plugin_agents:-0}" -gt 0 ] && detail_parts+=("${plugin_agents} agent(s)")

plugin_env_count=$(jq -r '.env // {} | length' "$MANIFEST" 2>/dev/null || echo "0")
[ "$plugin_env_count" -gt 0 ] && detail_parts+=("${plugin_env_count} env var(s)")

plugin_mcp_count=$(echo "$MANIFEST_MCP" | jq 'if . == {} or . == null then 0 else length end' 2>/dev/null || echo "0")
[ "$plugin_mcp_count" -gt 0 ] && detail_parts+=("${plugin_mcp_count} MCP server(s)")

detail_str=$(IFS=", "; echo "${detail_parts[*]}")
if [ -n "$detail_str" ]; then
    echo "[install] Plugin '$plugin_name': installed ($detail_str)"
else
    echo "[install] Plugin '$plugin_name': installed (manifest only)"
fi
```

**No changes needed** — this already provides the format user requested: `langfuse-tracing: 1 hook, 2 env, 1 MCP`

### Install Summary (Current Implementation)

```bash
# Source: .devcontainer/install-agent-config.sh:760-775
echo "[install] --- Summary ---"
echo "[install] Config: $CONFIG_STATUS"
echo "[install] Secrets: $SECRETS_STATUS"
echo "[install] Settings: generated"
echo "[install] Credentials (Claude): $CREDS_STATUS"
echo "[install] Credentials (Codex): $CODEX_CREDS_STATUS"
echo "[install] Git identity: $GIT_IDENTITY_STATUS"
echo "[install] Skills: $SKILLS_COUNT skill(s) -> Claude + Codex"
echo "[install] Hooks: $HOOKS_COUNT hook(s)"
echo "[install] Commands: $COMMANDS_COUNT standalone command(s)"
echo "[install] Plugins: $PLUGIN_INSTALLED installed, $PLUGIN_SKIPPED skipped"
echo "[install] MCP: $MCP_COUNT server(s)"
echo "[install] Infra .env: $INFRA_ENV_STATUS"
echo "[install] GSD: $GSD_COMMANDS commands + $GSD_AGENTS agents"
echo "[install] Done."
```

**Enhancement for Phase 6:** Add warning count + recap section AFTER "Done.":
```bash
echo "[install] Plugins: $PLUGIN_INSTALLED installed, $PLUGIN_SKIPPED skipped"
if [ "$PLUGIN_WARNINGS" -gt 0 ]; then
    echo "[install] Plugin warnings: $PLUGIN_WARNINGS (see recap below)"
fi
# ... rest of summary ...
echo "[install] Done."

# Warnings recap
if [ "$PLUGIN_WARNINGS" -gt 0 ]; then
    echo ""
    echo "[install] --- Warnings Recap ---"
    for warning in "${PLUGIN_WARNING_MESSAGES[@]}"; do
        echo "[install] ⚠ $warning"
    done
fi
```

### Env Var Conflict Detection (Current Implementation)

```bash
# Source: .devcontainer/install-agent-config.sh:407-413
CONFLICTS=$(jq -n --argjson existing "$PLUGIN_ENV" --argjson new "$MANIFEST_ENV" '
    [$new | keys[] | select(. as $k | $existing | has($k))]
' 2>/dev/null)
if [ "$CONFLICTS" != "[]" ] && [ -n "$CONFLICTS" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' env var conflict: $CONFLICTS -- using earlier plugin's values"
    PLUGIN_WARNINGS=$((PLUGIN_WARNINGS + 1))
    # ...
fi
```

**Enhancement for Phase 6:** Store in PLUGIN_WARNING_MESSAGES array for recap:
```bash
if [ "$CONFLICTS" != "[]" ] && [ -n "$CONFLICTS" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' env var conflict: $CONFLICTS -- using earlier plugin's values"
    PLUGIN_WARNINGS=$((PLUGIN_WARNINGS + 1))
    PLUGIN_WARNING_MESSAGES+=("Plugin '$plugin_name': env var conflict: $CONFLICTS (first plugin wins)")
    # ... rest of logic
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded hooks in settings template | Plugin-based hook registration | Phase 4 (2026-02-15) | Hooks are now extensible without template edits |
| Manual .mcp.json edits | Plugin MCP auto-registration | Phase 5 (2026-02-15) | MCP servers survive container rebuilds |
| Silent plugin failures | Validation warnings + recap | Phase 6 (this phase) | Users can debug plugin issues without reading logs |
| settings.local.json for plugins | settings.json for hooks/env | Phase 4-5 revision | Claude Code only reads hooks from settings.json |

**Deprecated/outdated:**
- **settings.local.json for hook/env registration:** Claude Code does not execute hooks declared in settings.local.json. All hooks and env vars must be in settings.json. This was corrected during Phase 4-5 execution.

## Open Questions

1. **Hook script validation: Should we validate Python syntax?**
   - What we know: Hook scripts are Python files, we could run `python3 -m py_compile` to check syntax
   - What's unclear: Is compile-time syntax check valuable vs runtime error on first hook fire?
   - Recommendation: LOW priority — runtime error is equally informative, adds complexity for minimal gain

2. **Empty env var warning: Before or after hydration?**
   - What we know: User wants warning for "env vars declared but empty after merge"
   - What's unclear: Does "after merge" mean after plugin accumulation OR after template token hydration?
   - Recommendation: Check after plugin accumulation but before token hydration — warn if plugin declares env var but config.json override is empty string

3. **File overwrite resolution: First wins or last wins?**
   - What we know: User left this to Claude's discretion
   - What's unclear: Best UX for hook file conflicts between plugins
   - Recommendation: FIRST WINS — preserves alphabetically earlier plugin, consistent with env var conflict resolution, easier to reason about (later plugins see what already exists)

## Sources

### Primary (HIGH confidence)

- `/workspace/.devcontainer/install-agent-config.sh` - Current implementation of plugin system (Phases 4-5)
- `/workspace/agent-config/hooks/langfuse_hook.py` - Existing Langfuse hook to be migrated
- `/workspace/agent-config/settings.json.template` - Current hardcoded Langfuse registration
- `/workspace/agent-config/plugins/nmc/plugin.json` - Example plugin manifest
- `/workspace/.planning/phases/06-langfuse-migration-validation/06-CONTEXT.md` - User decisions for this phase
- `/workspace/.planning/REQUIREMENTS.md` - Phase 6 requirements (LANG-01 through VAL-04)

### Secondary (MEDIUM confidence)

- Bash best practices for error handling (`set -euo pipefail`, jq fallbacks)
- jq manual for JSON manipulation patterns
- Python langfuse SDK documentation (for hook functionality verification)

### Tertiary (LOW confidence)

None — all findings verified against existing codebase or official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools already in use, no new dependencies
- Architecture: HIGH - Following existing Phases 4-5 patterns, user decisions locked
- Pitfalls: MEDIUM - Some inferred from general bash/jq experience, not all tested in this specific codebase

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (30 days - stable codebase)

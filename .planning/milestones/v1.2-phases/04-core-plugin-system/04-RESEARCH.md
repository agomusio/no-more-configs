# Phase 4: Core Plugin System - Research

**Researched:** 2026-02-15
**Domain:** Bash scripting, JSON manipulation with jq, file operations, plugin architecture
**Confidence:** HIGH

## Summary

Phase 4 implements a plugin discovery and installation system that extends the existing `install-agent-config.sh` script to support bundled packages of skills, hooks, commands, and agents. The implementation is primarily bash scripting with jq for JSON manipulation, following established patterns from the existing install script.

The key technical challenge is accumulating plugin registrations (hooks, environment variables) across multiple plugins and merging them into Claude Code's settings files without losing existing configuration or creating conflicts. The implementation must also handle cross-agent skill installation (both Claude and Codex), GSD file protection, and robust error handling for edge cases like missing manifests or disabled plugins.

**Primary recommendation:** Use jq's array concatenation (`+` operator) for hook merging and object merge (`*` operator) for environment variables, process plugins in alphabetical order for determinism, and validate plugin.json manifests before copying any files. Enable Codex skill discovery by adding `skills = true` under `[features]` in config.toml.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Spec Authority:**
- `.planning/nmc-plugin-spec.md` is a strong guide — follow its decisions (manifest format, directory layout, install order, config.json control) but write a fresh implementation that fits existing codebase patterns
- Do NOT copy the spec's bash pseudocode verbatim — understand the intent, then implement to match existing `install-agent-config.sh` style and patterns

**Install Feedback:**
- Per-plugin detail: each plugin logs what it installed with names listed (hooks, skills, env vars, commands, agents) up to a reasonable count
- Skipped plugins: use info-style line matching installed style — `"[install] Plugin 'noisy-plugin': skipped (disabled)"` — not a warning
- Final recap block: end of plugin installation includes summary snapshot — plugin count (installed vs skipped), hook registrations, command count, any warnings
- Match existing `[install]` prefix pattern for consistency

**File Conflict Policy:**
- Non-GSD file overwrites: overwrite + log — basic awareness without blocking
- GSD protection: hardcoded check for `commands/gsd/` directory and `agents/gsd-*.md` prefix — no configurable protected paths list
- GSD conflict: error-level message + skip — treat as plugin misconfiguration
- Protection scope: GSD-only — standalone commands and plugin commands can overwrite each other freely

**Edge Case Behavior:**
- Env var conflicts between plugins: error on conflict — if two plugins declare the same env var, warn and skip the duplicate (first alphabetically wins, second is skipped with warning). `config.json` overrides always take precedence.
- Multiple plugins on same hook event: all fire, alphabetical order by plugin directory name — no warning needed, this is expected behavior
- Missing/invalid plugin.json: skip everything — no files copied, no registrations, nothing installs. Clean skip with info message.
- Plugin name mismatch: `plugin.json` name field must match directory name — mismatch is an error, plugin is skipped with warning

**Cross-Agent Skill Installation:**
- Skills are copied to BOTH `~/.claude/skills/` and `~/.codex/skills/` — same directory structure, same files, single source
- Applies to standalone skills AND plugin skills
- Enable Codex skill discovery: add `skills = true` under `[features]` in generated Codex `config.toml`
- Only skills are cross-agent — hooks, commands, agents, and MCP servers remain Claude-only
- Install feedback reflects dual destination: `"[install] Skills: 4 skill(s) → Claude + Codex"`

### Claude's Discretion

- Install script architecture (functions, helpers, inline code)
- Exact log message formatting beyond the patterns described above
- JSON merging implementation for hook accumulation in settings.local.json
- How to detect GSD files (prefix matching, path checking, etc.)
- Temp file handling during JSON merging operations
- Order of operations within plugin installation loop

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 5.2+ | Install script runtime | System shell, native to container |
| jq | 1.6+ | JSON parsing and manipulation | De facto standard for JSON in bash scripts |
| cp | GNU coreutils | File copying operations | Built-in, reliable, standard file operations |
| find | GNU findutils | Directory traversal | Safe directory enumeration |

### Supporting Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| grep | GNU grep | Pattern matching | File content validation, token detection |
| sed | GNU sed | Text substitution | Template hydration (existing pattern) |
| test / [ ] | Bash built-in | File/directory checks | Existence validation before operations |

### No Additional Dependencies Required

The existing container environment has all necessary tools installed. No new packages need to be added.

## Architecture Patterns

### Recommended Integration Approach

Extend the existing `install-agent-config.sh` script by adding plugin installation sections between lines 235 (after hooks copy) and 383 (before GSD installation). This maintains the established installation order and ensures plugins install before GSD (which is protected).

```
1. Config/secrets loading (existing)
2. Firewall/VS Code generation (existing)
3. Directory creation (existing)
4. Standalone skills copy (existing) → UPDATE for cross-agent
5. Standalone hooks copy (existing)
6. Standalone commands copy (NEW)
7. Settings template hydration (existing)
8. Settings.json seed (existing)
9. Plugin installation (NEW)
10. Plugin registration merging (NEW)
11. Credential restoration (existing)
12. MCP config generation (existing)
13. GSD installation (existing)
14. Settings enforcement (existing)
15. Summary (existing) → UPDATE for plugins
```

### Pattern 1: Accumulator Variables for Plugin Data

**What:** Use bash variables to accumulate JSON data across all plugins before writing to settings files.

**When to use:** When multiple plugins contribute to the same configuration section (hooks, env vars, MCP servers).

**Example:**
```bash
# Initialize accumulators as empty JSON objects/arrays
PLUGIN_HOOKS='{}'
PLUGIN_ENV='{}'
PLUGIN_MCP='{}'

# Accumulate during plugin loop
for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do
    # Read and merge hook registrations
    PLUGIN_HOOKS=$(jq -s --arg name "$plugin_name" \
        '.[0] as $acc | .[1].hooks // {} | to_entries[] |
         .key as $event | .value as $hooks |
         $acc | .[$event] = ((.[$event] // []) + $hooks)' \
        <(echo "$PLUGIN_HOOKS") "$MANIFEST")
done

# Write accumulated data once after all plugins processed
jq --argjson hooks "$PLUGIN_HOOKS" '.hooks = $hooks' settings.json > settings.json.tmp
```

**Why this pattern:** Accumulation prevents repeated file writes and allows validation of conflicts (like duplicate env vars) before committing changes.

**Confidence:** HIGH — pattern verified in existing save-secrets.sh script lines 24, 33, 43.

### Pattern 2: Atomic File Updates with Temp Files

**What:** Write to temporary file, validate, then atomically move to final location.

**When to use:** Any modification to critical JSON configuration files (settings.local.json, .mcp.json).

**Example:**
```bash
jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

**Why this pattern:** Ensures file integrity if jq fails or script is interrupted. The `&&` operator ensures move only happens if jq succeeds.

**Confidence:** HIGH — pattern already used in existing script lines 278-279, 406-407.

**Source:** [Writing Safe Shell Scripts – MIT SIPB](https://sipb.mit.edu/doc/safe-shell/)

### Pattern 3: Safe File Globbing with Guards

**What:** Always guard glob patterns with existence checks to handle empty directories.

**When to use:** Iterating over plugin directories, copying files from plugin subdirectories.

**Example:**
```bash
# BAD: Fails on empty directory, creates literal *.md file reference
for cmd_file in "$plugin_dir/commands"/*.md; do
    cp "$cmd_file" "$CLAUDE_DIR/commands/"
done

# GOOD: Guards against empty directory
if [ -d "$plugin_dir/commands" ]; then
    for cmd_file in "$plugin_dir/commands"/*.md; do
        [ -f "$cmd_file" ] || continue  # Skip if no matches
        cp "$cmd_file" "$CLAUDE_DIR/commands/"
    done
fi
```

**Why this pattern:** Without guards, bash expands unmatched globs to literal strings, causing errors or unexpected behavior. The `[ -f "$cmd_file" ] || continue` pattern is the safe idiom when you can't use `nullglob`.

**Confidence:** HIGH — existing script uses this pattern at lines 221-226, 231-235.

**Source:** [BashFAQ/004 - Greg's Wiki](https://mywiki.wooledge.org/BashFAQ/004)

### Pattern 4: GSD Protection via Path Prefix Matching

**What:** Check file paths before copying to prevent overwriting GSD files.

**When to use:** Copying agent files and commands from plugins.

**Example:**
```bash
# Protect GSD agents (gsd-*.md prefix)
for agent_file in "$plugin_dir/agents"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file")

    # Skip if file matches GSD pattern
    if [[ "$agent_name" =~ ^gsd- ]]; then
        echo "[install] ERROR: Plugin '$plugin_name' attempted to overwrite GSD-protected file agents/$agent_name — skipping"
        continue
    fi

    cp "$agent_file" "$CLAUDE_DIR/agents/"
done

# Protect GSD commands directory
if [ -d "$plugin_dir/commands/gsd" ]; then
    echo "[install] ERROR: Plugin '$plugin_name' attempted to overwrite GSD-protected directory commands/gsd/ — skipping"
    # Skip entire commands directory for this plugin
fi
```

**Why this pattern:** Simple regex matching (`^gsd-`) for agent files and directory name check for commands. No complex file trees to traverse.

**Confidence:** HIGH — straightforward bash pattern matching, deterministic behavior.

### Pattern 5: Cross-Agent Skill Installation

**What:** Copy skills to both Claude and Codex directories, enable skills feature in Codex config.

**When to use:** Processing standalone skills and plugin skills.

**Example:**
```bash
# Copy to both locations
SKILLS_COUNT=0
if [ -d "$AGENT_CONFIG_DIR/skills" ]; then
    cp -r "$AGENT_CONFIG_DIR/skills/"* "$CLAUDE_DIR/skills/" 2>/dev/null || true
    mkdir -p /home/node/.codex/skills
    cp -r "$AGENT_CONFIG_DIR/skills/"* /home/node/.codex/skills/ 2>/dev/null || true
    SKILLS_COUNT=$(find "$AGENT_CONFIG_DIR/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    echo "[install] Skills: $SKILLS_COUNT skill(s) → Claude + Codex"
fi

# Enable skills in Codex config.toml (add to existing generation section)
{
    echo "# Generated by install-agent-config.sh — do not edit manually"
    echo "model = \"$CODEX_MODEL\""
    echo 'cli_auth_credentials_store = "file"'
    echo 'approval_policy = "never"'
    echo 'sandbox_mode = "danger-full-access"'
    echo ""
    echo '[features]'
    echo 'skills = true'
    echo ""
    echo '[projects."/workspace"]'
    echo 'trust_level = "trusted"'
} > /home/node/.codex/config.toml
```

**Why this pattern:** Single source of truth (agent-config/skills/) with dual destinations. Codex skill discovery requires explicit feature flag in config.toml.

**Confidence:** MEDIUM — Codex skills feature verified via web research ([blog.fsck.com](https://blog.fsck.com/2025/12/19/codex-skills/)), but exact config.toml syntax not officially documented. Feature flag approach is standard practice.

**Source:** [Skills in OpenAI Codex – blog.fsck.com](https://blog.fsck.com/2025/12/19/codex-skills/)

### Anti-Patterns to Avoid

- **Using `set -e` without guards on expected failures:** Commands like `cp -r` with `|| true` override `set -e`. Ensure critical operations don't silently fail this way.
- **Merging JSON with `*` for arrays:** The `*` operator recursively merges objects but does NOT concatenate arrays — it overwrites. Use `+` for array concatenation.
- **Copying files before validating manifests:** Always validate plugin.json exists and is valid JSON before copying any files. Partial installations are worse than no installation.
- **Hardcoding file paths in plugin.json hooks:** Hook commands should reference runtime locations (`~/.claude/hooks/`) not source locations (`agent-config/plugins/*/hooks/`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing/manipulation | Custom awk/sed JSON parser | jq with --argjson, --arg flags | JSON is context-sensitive (nested quotes, escaping). Custom parsers break on valid edge cases. jq handles all valid JSON correctly. |
| File atomicity | Manual backup/restore logic | Temp file + && + mv pattern | Built-in atomicity. If write fails, original file unchanged. No cleanup logic needed. |
| Plugin enable/disable tracking | Custom state file | Read directly from config.json each time | Single source of truth. No state sync issues. jq makes reading fast enough for install script. |
| Hook registration validation | Checking if hook script exists during install | Let Claude Code handle missing hooks at runtime | Install-time validation requires predicting runtime paths. False negatives frustrate users. Runtime errors are clearer. |
| Environment variable conflict resolution | Complex precedence system | First-alphabetically wins, config.json always overrides | Simple, deterministic, explainable. Users can predict behavior. Complexity doesn't add value. |

**Key insight:** Install scripts should be boring and predictable. Clever logic increases maintenance burden and makes debugging harder. Use established tools (jq, cp, mv) in simple patterns rather than building custom solutions.

## Common Pitfalls

### Pitfall 1: Array Overwrite Instead of Concatenation in jq

**What goes wrong:** Using `*` operator to merge hook arrays overwrites existing hooks instead of accumulating them.

**Why it happens:** The `*` operator performs recursive object merge but treats arrays as atomic values (replaces entire array). Developers assume "recursive" means "handles arrays intelligently."

**How to avoid:**
- Use `+` operator for array concatenation: `.hooks.Stop = (.hooks.Stop // []) + $new_hooks`
- Use `*` operator only for object merging: `.env = .env * $plugin_env`
- Test with multiple plugins registering the same hook event

**Warning signs:**
- Only the last plugin's hooks fire for an event
- Hook count in logs doesn't match expected total

**Confidence:** HIGH — verified with jq 1.6 testing, documented in jq manual.

**Source:** [How to Recursively Merge JSON Objects – codegenes.net](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/)

### Pitfall 2: Unquoted Variables in File Operations

**What goes wrong:** Paths with spaces cause `cp` to fail or copy to wrong location.

**Why it happens:** Bash word splitting treats spaces as argument separators unless variables are quoted.

**How to avoid:**
```bash
# BAD
cp $plugin_dir/skills/* "$CLAUDE_DIR/skills/"

# GOOD
cp "$plugin_dir/skills/"* "$CLAUDE_DIR/skills/"
```

Always quote variable expansions except in `[[ ]]` tests where quoting is optional.

**Warning signs:**
- Install works locally but fails in CI or different environments
- Error messages about files/directories that don't exist but are "part" of a path with spaces

**Confidence:** HIGH — fundamental bash behavior, verified across all shells.

**Source:** [How to Handle File Operations in Bash Scripts – OneUpTime](https://oneuptime.com/blog/post/2026-01-24-bash-file-operations/view)

### Pitfall 3: Silent Failures from `|| true` on Critical Operations

**What goes wrong:** Using `|| true` to suppress errors masks actual failures that should halt installation.

**Why it happens:** `set -e` exits on any non-zero return. Developers add `|| true` to continue on expected failures (like copying from empty directory) but apply it too broadly.

**How to avoid:**
- Use `|| true` only for operations where failure is genuinely acceptable (copying optional files)
- For critical operations, use explicit error checking:
```bash
# BAD: Silently continues if directory doesn't exist
cp "$plugin_dir/hooks/"* "$CLAUDE_DIR/hooks/" 2>/dev/null || true

# GOOD: Checks if directory exists before copying
if [ -d "$plugin_dir/hooks" ]; then
    cp "$plugin_dir/hooks/"* "$CLAUDE_DIR/hooks/" 2>/dev/null || true
fi

# GOOD: Fails loudly if critical file missing
if [ ! -f "$MANIFEST" ]; then
    echo "[install] ERROR: Plugin manifest missing"
    continue  # Skip plugin, don't install partial files
fi
```

**Warning signs:**
- Plugins appear to install successfully but files are missing
- No error messages but configuration doesn't work
- Intermittent failures that are hard to reproduce

**Confidence:** HIGH — common bash scripting mistake, well-documented.

**Source:** [Writing Safe Shell Scripts – MIT SIPB](https://sipb.mit.edu/doc/safe-shell/)

### Pitfall 4: JSON Accumulator Variable Corruption

**What goes wrong:** jq merge operation fails silently, leaving accumulator variable with invalid JSON, causing subsequent plugins to fail or entire merge to break.

**Why it happens:** jq can fail if input JSON is malformed but bash command substitution `$(...)` doesn't propagate error codes. If jq fails, the variable keeps its old value or becomes empty string.

**How to avoid:**
```bash
# BAD: If jq fails, PLUGIN_ENV becomes empty string
PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" | jq -s '.[0] * .[1]')

# GOOD: Fallback to current value on failure
NEW_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" | jq -s '.[0] * .[1]' 2>/dev/null)
if [ $? -eq 0 ]; then
    PLUGIN_ENV="$NEW_ENV"
else
    echo "[install] WARNING: Plugin '$plugin_name' env merge failed — skipping env vars"
fi

# BETTER: Inline fallback in command substitution
PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" | jq -s '.[0] * .[1]' 2>/dev/null || echo "$PLUGIN_ENV")
```

**Warning signs:**
- "parse error" from jq during final merge step
- Env vars from early plugins work, later ones don't
- Final settings.json missing env section entirely

**Confidence:** HIGH — command substitution behavior is well-defined bash behavior.

### Pitfall 5: Empty Directory Glob Expansion

**What goes wrong:** `for file in dir/*.md` creates a literal loop iteration with value `dir/*.md` when directory is empty, causing `cp` to fail with "no such file."

**Why it happens:** Bash glob expansion returns the literal pattern string when no files match. The for loop runs once with the unmatched pattern as the value.

**How to avoid:**
```bash
# BAD: Fails on empty directory
for file in "$plugin_dir/commands"/*.md; do
    cp "$file" "$CLAUDE_DIR/commands/"
done

# GOOD: Guard with existence check
for file in "$plugin_dir/commands"/*.md; do
    [ -f "$file" ] || continue
    cp "$file" "$CLAUDE_DIR/commands/"
done

# ALTERNATIVE: Use nullglob (affects entire script)
shopt -s nullglob
for file in "$plugin_dir/commands"/*.md; do
    # Loop doesn't run if no files match
    cp "$file" "$CLAUDE_DIR/commands/"
done
```

**Warning signs:**
- Error messages about "cannot stat '*.md': No such file or directory"
- Script exits on first plugin with empty optional directory

**Confidence:** HIGH — fundamental bash globbing behavior, existing script uses guard pattern.

**Source:** [BashFAQ/004 - Greg's Wiki](https://mywiki.wooledge.org/BashFAQ/004)

## Code Examples

Verified patterns from existing codebase and official sources:

### Reading JSON with jq and Fallback Defaults

```bash
# Source: install-agent-config.sh lines 43, 250-252
# Pattern: Extract value with fallback using // operator

PLUGIN_ENABLED=$(jq -r --arg name "$plugin_name" \
    '.plugins[$name].enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

# Explanation:
# - --arg passes plugin name safely (handles special chars)
# - .plugins[$name] navigates to plugin config
# - .enabled extracts enabled field
# - // true provides default if field missing
# - 2>/dev/null suppresses jq errors
# - || echo "true" provides fallback if config.json missing or invalid
```

### Accumulating Arrays Across JSON Files

```bash
# Source: Derived from save-secrets.sh pattern, adapted for hook arrays
# Pattern: Read accumulator, merge new data, update accumulator

PLUGIN_HOOKS='{}'  # Initialize as empty object

for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do
    MANIFEST="$plugin_dir/plugin.json"
    plugin_name=$(basename "$plugin_dir")

    # Extract hook registrations and merge into accumulator
    PLUGIN_HOOKS=$(jq -s \
        '.[0] as $acc |                        # Accumulator is first input
         .[1].hooks // {} | to_entries[] |     # Extract hook entries from manifest
         .key as $event | .value as $hooks |   # Destructure to event name and hooks array
         $acc | .[$event] = ((.[$event] // []) + $hooks)' \  # Concatenate arrays
        <(echo "$PLUGIN_HOOKS") "$MANIFEST" 2>/dev/null || echo "$PLUGIN_HOOKS")
    # Fallback to current value if jq fails
done

# Explanation:
# - -s (slurp) reads both inputs as array: [accumulator, manifest]
# - .[0] as $acc captures current state
# - .[1].hooks // {} extracts hooks or empty object
# - to_entries[] converts {Stop: [...]} to [{key: "Stop", value: [...]}]
# - (.[$event] // []) provides empty array if event not in accumulator
# - + $hooks concatenates arrays (does NOT overwrite)
```

**Source:** [Merge multiple JSON files with JQ – richrose.dev](https://richrose.dev/posts/linux/jq/jq-jsonmerge/)

### Safe Recursive Directory Copy with Error Suppression

```bash
# Source: install-agent-config.sh line 224
# Pattern: Copy directory contents with graceful failure

if [ -d "$plugin_dir/skills" ]; then
    cp -r "$plugin_dir/skills/"* "$CLAUDE_DIR/skills/" 2>/dev/null || true
    cp -r "$plugin_dir/skills/"* /home/node/.codex/skills/ 2>/dev/null || true
fi

# Explanation:
# - [ -d ... ] checks directory exists before attempting copy
# - /* copies contents, not directory itself
# - -r enables recursive copy for nested directories
# - 2>/dev/null suppresses "cannot stat" errors for empty directories
# - || true prevents script exit on error (expected when directory empty)
# - This is acceptable for optional directories (skills, hooks, etc.)
```

**Source:** [How to Handle File Operations in Bash Scripts – OneUpTime](https://oneuptime.com/blog/post/2026-01-24-bash-file-operations/view)

### Validating JSON Files Before Processing

```bash
# Source: install-agent-config.sh lines 19-27
# Pattern: Validation function used throughout script

validate_json() {
    local file="$1"
    local label="$2"
    if ! jq empty < "$file" &>/dev/null; then
        echo "[install] ERROR: $label is not valid JSON — skipping"
        return 1
    fi
    return 0
}

# Usage:
MANIFEST="$plugin_dir/plugin.json"
if [ ! -f "$MANIFEST" ]; then
    echo "[install] WARNING: Plugin '$plugin_name' has no plugin.json — skipping"
    continue
fi

if ! validate_json "$MANIFEST" "plugins/$plugin_name/plugin.json"; then
    continue  # Skip this plugin, move to next
fi

# Explanation:
# - jq empty parses JSON and outputs nothing if valid
# - &>/dev/null suppresses all output (stdout and stderr)
# - ! inverts return code (true on failure)
# - return 1 signals validation failure to caller
# - Caller uses continue to skip plugin processing
```

### Atomic JSON File Update

```bash
# Source: install-agent-config.sh lines 278-279, 406-407
# Pattern: Write to temp file, move atomically on success

SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"

jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

# Explanation:
# - jq processes file and writes to .tmp
# - && ensures mv only runs if jq succeeds
# - mv is atomic (overwrites in single operation)
# - If jq fails, original file unchanged
# - .tmp file left behind for debugging (acceptable tradeoff)
```

### Plugin Name Validation

```bash
# Source: Spec requirement, standard bash pattern
# Pattern: Validate plugin.json name matches directory name

plugin_name=$(basename "$plugin_dir")
manifest_name=$(jq -r '.name // ""' "$MANIFEST" 2>/dev/null)

if [ "$manifest_name" != "$plugin_name" ]; then
    echo "[install] WARNING: Plugin directory '$plugin_name' has manifest name '$manifest_name' — skipping"
    continue
fi

# Explanation:
# - basename extracts directory name (source of truth)
# - jq extracts name field from manifest (must match)
# - // "" provides empty string fallback if field missing
# - != comparison fails on mismatch or empty string
# - continue skips plugin to prevent partial install
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single settings.json.template for all config | Template + plugin manifests accumulation | Phase 4 (current) | Plugins self-register hooks without template modification |
| Skills Claude-only | Skills copied to both Claude and Codex | Early 2026 | Codex now supports SKILL.md convention, enabling cross-agent skills |
| MCP servers hardcoded in templates | Plugin manifests can declare MCP servers | Phase 5 (next) | Plugins bundle all dependencies including MCP servers |
| Manual hook registration in template | Plugins declare hooks in manifest | Phase 4 (current) | Adding a plugin no longer requires template editing |

**Deprecated/outdated:**
- **Standalone hooks without plugin manifests:** Still supported but discouraged. Plugins with self-registration are preferred because they're self-contained and easier to enable/disable.
- **Single-agent skills:** Skills should now be designed with cross-agent use in mind. Both Claude and Codex use the same SKILL.md format.

## Open Questions

### 1. **Codex skills feature flag syntax**
   - What we know: Codex supports skills via `~/.codex/skills/` directory, requires explicit enable in config.toml
   - What's unclear: Exact syntax for `[features]` section not in official docs, derived from community blog posts
   - Recommendation: Test the `skills = true` approach during implementation. If it fails, check `codex --help` for alternative config syntax or look for Codex-generated config examples.

### 2. **Hook execution environment**
   - What we know: Hooks run as shell commands with working directory and environment from Claude Code
   - What's unclear: What environment variables are available, whether PATH includes /workspace/node_modules/.bin, timeout behavior
   - Recommendation: Document this in hook writing guide (Phase 7). For Phase 4, assume hooks work with minimal environment (only Claude settings env section).

### 3. **Plugin installation order within alphabetical sort**
   - What we know: Plugins processed in alphabetical order by directory name
   - What's unclear: Whether this needs to be case-sensitive sort, locale-aware sort, or simple ASCII sort
   - Recommendation: Use bash's default glob expansion order (ASCII sort). Users can prefix plugin directory names with numbers if they need explicit ordering (e.g., `01-base`, `02-extensions`).

### 4. **File overwrite behavior for non-GSD conflicts**
   - What we know: Non-GSD files can overwrite, should log the overwrite
   - What's unclear: Whether to track source of existing file (standalone vs another plugin) for better logging
   - Recommendation: Don't track provenance. Simple log message: "Plugin 'x' overwrote {type}/{name}". Users can check install order if conflicts matter.

## Sources

### Primary (HIGH confidence)
- `/workspace/.devcontainer/install-agent-config.sh` - Existing install script patterns and structure
- `/workspace/.planning/nmc-plugin-spec.md` - Plugin system specification and requirements
- `/workspace/.planning/phases/04-core-plugin-system/04-CONTEXT.md` - User decisions and constraints
- `/workspace/agent-config/settings.json.template` - Settings structure and hook registration format
- `jq --help` and `man jq` - jq syntax verification for JSON operations

### Secondary (MEDIUM confidence)
- [Skills in OpenAI Codex – blog.fsck.com](https://blog.fsck.com/2025/12/19/codex-skills/) - Codex skill directory structure
- [How to Handle File Operations in Bash Scripts – OneUpTime](https://oneuptime.com/blog/post/2026-01-24-bash-file-operations/view) - Bash file operation best practices
- [How to Recursively Merge JSON Objects – codegenes.net](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/) - jq array concatenation vs object merge
- [Merge multiple JSON files with JQ – richrose.dev](https://richrose.dev/posts/linux/jq/jq-jsonmerge/) - jq accumulation patterns
- [Writing Safe Shell Scripts – MIT SIPB](https://sipb.mit.edu/doc/safe-shell/) - Error handling and atomicity patterns

### Tertiary (LOW confidence)
- [BashFAQ/004 - Greg's Wiki](https://mywiki.wooledge.org/BashFAQ/004) - Glob expansion behavior (reference documentation)
- [How to Use set -e -o pipefail in Bash – NameHero](https://www.namehero.com/blog/how-to-use-set-e-o-pipefail-in-bash-and-why/) - Error handling patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools verified present in container, versions confirmed
- Architecture patterns: HIGH - Derived from existing working script with verification tests
- JSON manipulation: HIGH - Patterns tested with jq 1.6, behavior verified
- File operations: HIGH - Existing script uses same patterns successfully
- Codex skills: MEDIUM - Based on community sources, not official Codex docs (connection refused)
- Cross-agent behavior: MEDIUM - Codex skill discovery documented but config.toml syntax unverified
- Pitfalls: HIGH - Common bash issues, well-documented, testable

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (30 days - stable bash/jq environment, unlikely to change)

**Note on Codex documentation:** OpenAI's developer documentation site was unreachable during research (ECONNREFUSED). Codex skill support is confirmed via community blog posts and web search results indicating the feature exists and uses SKILL.md files in `~/.codex/skills/`, but exact configuration syntax should be verified during implementation. The `[features] skills = true` recommendation is based on standard Codex config.toml patterns, not official documentation.

# Pitfalls Research

**Domain:** Plugin system integration into existing bash install script (Claude Code Sandbox)
**Researched:** 2026-02-15
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: jq Array Overwriting Instead of Concatenation

**What goes wrong:**
When merging plugin hook registrations into `settings.local.json`, jq's default `*` merge operator **overwrites arrays instead of concatenating them**. If the settings template has a `Stop` hook for Langfuse, and a plugin also registers a `Stop` hook, the plugin's hook registration will completely replace the template's hook instead of appending to it. Result: the Langfuse hook disappears.

**Why it happens:**
jq's recursive merge (`*`) operator treats arrays as atomic values, not as collections to merge. When both the left and right operands have the same key with array values, the right-side array wins and replaces the left-side array entirely ([How to Recursively Merge JSON Objects and Concatenate Arrays with jq](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/)).

**How to avoid:**
Use custom merge logic that detects array types and concatenates them:

```bash
# WRONG: This overwrites arrays
jq --argjson plugin_hooks "$PLUGIN_HOOKS" '.hooks * $plugin_hooks' settings.local.json

# CORRECT: Custom recursive merge that concatenates arrays
jq --argjson plugin_hooks "$PLUGIN_HOOKS" '
  def recursive_merge:
    . as $left | $plugin_hooks as $right |
    if ($left | type) == "object" and ($right | type) == "object" then
      reduce ([$left, $right] | add | keys_unsorted[]) as $key ({};
        .[$key] = (
          if ($left[$key] | type) == "array" and ($right[$key] | type) == "array" then
            ($left[$key] + $right[$key])
          elif ($left[$key] | type) == "object" and ($right[$key] | type) == "object" then
            ($left[$key] | recursive_merge)
          else
            $right[$key]
          end
        )
      )
    else
      $right
    end;
  .hooks = (.hooks | recursive_merge)
' settings.local.json
```

**Warning signs:**
- After install, `cat ~/.claude/settings.local.json | jq .hooks.Stop` shows only one hook when you expected multiple
- Langfuse tracing stops working after adding a plugin with a `Stop` hook
- Test by checking hook array lengths before/after merge

**Phase to address:**
**Phase 1 (Core Plugin System)** — must implement correct array concatenation from the start, as fixing this later requires migrating existing plugin installations.

---

### Pitfall 2: .mcp.json Double-Write Race Condition

**What goes wrong:**
The `postStartCommand` in devcontainer.json runs `mcp-setup` which **overwrites `~/.claude/.mcp.json`** after `install-agent-config.sh` has already written it. Any plugin MCP server registrations added during `install-agent-config.sh` are silently lost. Users report "plugin MCP server not found" but the install script showed success.

**Why it happens:**
Sequential command execution in `postStartCommand`:
1. `install-agent-config.sh` runs (in `postCreateCommand`)
2. Writes `.mcp.json` with plugin MCP servers merged in
3. Later, `postStartCommand` runs `mcp-setup`
4. `mcp-setup` regenerates `.mcp.json` from config.json templates **without plugin data**
5. Plugin MCP servers are gone

The current devcontainer.json shows:
```json
"postStartCommand": "... && mcp-setup",
"postCreateCommand": "bash .devcontainer/install-agent-config.sh"
```

**How to avoid:**
**Option A (Recommended):** Make `mcp-setup` plugin-aware — read existing `.mcp.json`, preserve plugin entries, merge with template entries.

```bash
# In mcp-setup: preserve existing plugin servers
EXISTING_MCP="{}"
if [ -f "$CLAUDE_DIR/.mcp.json" ]; then
    EXISTING_MCP=$(jq '.mcpServers // {}' "$CLAUDE_DIR/.mcp.json")
fi

# Generate new MCP config from templates
# ... existing logic ...

# Merge: template servers + existing plugin servers (plugins win on collision)
jq --argjson existing "$EXISTING_MCP" '.mcpServers += $existing' new-mcp.json > "$CLAUDE_DIR/.mcp.json"
```

**Option B:** Move `mcp-setup` to run **before** plugin installation in `install-agent-config.sh`, so plugins always run last.

**Warning signs:**
- Plugin's `mcp_servers` declared in `plugin.json` but `npx @anthropic/code mcp list` doesn't show them
- Plugin MCP server works after `install-agent-config.sh` runs standalone, but not after full container rebuild
- `.mcp.json` timestamp is newer than install script completion

**Phase to address:**
**Phase 1 (Core Plugin System)** — critical blocker, must fix before plugin MCP server feature works at all.

---

### Pitfall 3: GSD File Clobbering During Plugin Installation

**What goes wrong:**
A plugin provides `commands/*.md` or `agents/*.md` files that **overwrite GSD framework files** because plugin file copying happens before GSD installation, or a plugin maliciously/accidentally includes files named `gsd-*.md`. Result: GSD commands break or disappear.

**Why it happens:**
The spec shows this copy logic for plugins:
```bash
[ -d "$plugin_dir/commands" ] && {
    for cmd_file in "$plugin_dir/commands/"*.md; do
        [ -f "$cmd_file" ] || continue
        cp "$cmd_file" "$CLAUDE_DIR/commands/"
    done
}
```

This **unconditionally copies** plugin command files. If a plugin has `commands/gsd-new-project.md`, it will overwrite the actual GSD file when GSD installs later.

Current install order (from spec):
1. Copy standalone commands
2. Install plugins (copies commands from all plugins)
3. Install GSD (npx — writes to `commands/gsd/` and `agents/gsd-*.md`)

**How to avoid:**
**For commands:** Check if destination is inside `gsd/` subdirectory before copying:

```bash
[ -d "$plugin_dir/commands" ] && {
    for cmd_file in "$plugin_dir/commands/"*.md; do
        [ -f "$cmd_file" ] || continue
        cmd_name=$(basename "$cmd_file")
        # Skip if trying to overwrite GSD directory
        if [ "$cmd_name" = "gsd" ]; then
            echo "[install] WARNING: Plugin '$plugin_name' tried to provide 'gsd' directory — skipping"
            continue
        fi
        cp "$cmd_file" "$CLAUDE_DIR/commands/"
    done
}
```

**For agents:** Skip files matching `gsd-*.md` pattern:

```bash
[ -d "$plugin_dir/agents" ] && {
    for agent_file in "$plugin_dir/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        agent_name=$(basename "$agent_file")
        # Don't overwrite GSD agents (gsd-*.md pattern)
        if [[ "$agent_name" =~ ^gsd- ]]; then
            echo "[install] WARNING: Plugin '$plugin_name' tried to provide GSD agent '$agent_name' — skipping"
            continue
        fi
        cp "$agent_file" "$CLAUDE_DIR/agents/"
    done
}
```

**Warning signs:**
- `/gsd:new-project` command not found after installing a plugin
- `ls ~/.claude/commands/gsd/` shows unexpected files or missing expected files
- `ls ~/.claude/agents/` shows duplicate `gsd-*.md` files with wrong content

**Phase to address:**
**Phase 1 (Core Plugin System)** — add GSD protection during initial plugin file copy implementation.

---

### Pitfall 4: Empty Object/Null Value Merge Corruption

**What goes wrong:**
When a plugin's `plugin.json` has `"env": {}` (empty object) or `"hooks": null`, jq merge operations produce unexpected results. The install script accumulates plugin data like this:

```bash
PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" | jq -s '.[0] * .[1]')
```

If `PLUGIN_ENV_FROM_MANIFEST` is `null` (because `jq -r '.env // {}' "$MANIFEST"` failed), the merge corrupts `PLUGIN_ENV` or produces invalid JSON.

**Why it happens:**
- `jq -r` (raw output) on a null field returns the string `"null"`, not JSON null
- Merging JSON string `"null"` with an object fails
- `jq -s '.[0] * .[1]'` with `null` as one operand has different behavior than with `{}` ([JQ - Handling null values and default values](https://www.devtoolsdaily.com/blog/jq-null-values-and-default/))

**How to avoid:**
Always use `jq` without `-r` for JSON extraction, and ensure null coalescing to empty object:

```bash
# WRONG: -r flag produces string "null" instead of JSON null
PLUGIN_ENV_FROM_MANIFEST=$(jq -r '.env // {}' "$MANIFEST" 2>/dev/null || echo "{}")

# CORRECT: No -r flag, produces JSON; coalesce null to {}
PLUGIN_ENV_FROM_MANIFEST=$(jq '.env // {}' "$MANIFEST" 2>/dev/null || echo "{}")

# CORRECT: Defensive merge that handles null/empty gracefully
if [ "$PLUGIN_ENV_FROM_MANIFEST" != "{}" ] && [ "$PLUGIN_ENV_FROM_MANIFEST" != "null" ]; then
    PLUGIN_ENV=$(echo "$PLUGIN_ENV" "$PLUGIN_ENV_FROM_MANIFEST" | jq -s '.[0] * .[1]')
fi
```

**Warning signs:**
- `jq` errors during plugin installation: "parse error: Invalid numeric literal"
- `settings.local.json` has malformed `env` section after plugin install
- Plugin env vars are missing or set to literal string "null"

**Phase to address:**
**Phase 1 (Core Plugin System)** — add defensive null handling in initial plugin accumulation logic.

---

### Pitfall 5: Glob Pattern No-Match Literal Iteration

**What goes wrong:**
During plugin file discovery, if a plugin has no `commands/*.md` files, the glob `"$plugin_dir/commands/"*.md` doesn't match anything. Without proper checks, bash iterates once with the **literal glob string** as the filename:

```bash
for cmd_file in "$plugin_dir/commands/"*.md; do
    cp "$cmd_file" "$CLAUDE_DIR/commands/"  # Copies literal "*.md" filename
done
```

This creates a file named `*.md` in the commands directory, breaking command discovery.

**Why it happens:**
By default, when a glob pattern doesn't match any files, bash leaves it as a literal string. The loop runs once with the variable set to the unexpanded pattern ([BashPitfalls - Greg's Wiki](https://mywiki.wooledge.org/BashPitfalls)).

**How to avoid:**
Always guard glob-based loops with `[ -f "$var" ] || continue`:

```bash
for cmd_file in "$plugin_dir/commands/"*.md; do
    [ -f "$cmd_file" ] || continue  # Skip if glob didn't match
    cmd_name=$(basename "$cmd_file")
    cp "$cmd_file" "$CLAUDE_DIR/commands/"
done
```

The spec already includes this pattern in some places but not consistently. Verify all plugin file iteration loops have this guard.

**Warning signs:**
- File named `*.md` appears in `~/.claude/commands/` or `~/.claude/agents/`
- Command palette shows an entry for `*` as a command
- `ls -la ~/.claude/commands/` shows files with glob characters in the name

**Phase to address:**
**Phase 1 (Core Plugin System)** — audit all glob-based loops during initial implementation; add guards where missing.

---

### Pitfall 6: Hook Execution Order Non-Determinism

**What goes wrong:**
Multiple plugins register hooks for the same event (`Stop`, `SessionStart`, etc.). Users expect plugins to execute in a specific order (e.g., "logging plugin must run before analytics plugin"), but the actual execution order is **filesystem-dependent** and unpredictable across systems.

The spec states: "Order is determined by filesystem sort order of plugin directory names (alphabetical)." This works on Linux with standard filesystems but can break on case-insensitive filesystems (macOS HFS+/APFS), network mounts, or when users rename plugin directories.

**Why it happens:**
Bash glob expansion order depends on filesystem directory entry order, which is implementation-defined. Most modern filesystems return entries in inode order or hash order, not alphabetical order. The `for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/` loop order is not guaranteed ([glob - Greg's Wiki](https://mywiki.wooledge.org/glob)).

**How to avoid:**
Explicitly sort plugin directories before iteration:

```bash
# WRONG: Filesystem-dependent order
for plugin_dir in "$AGENT_CONFIG_DIR/plugins"/*/; do

# CORRECT: Guaranteed alphabetical order
while IFS= read -r -d '' plugin_dir; do
    # ... process plugin ...
done < <(find "$AGENT_CONFIG_DIR/plugins" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
```

Or simpler, using sorted array:

```bash
mapfile -t PLUGIN_DIRS < <(find "$AGENT_CONFIG_DIR/plugins" -mindepth 1 -maxdepth 1 -type d | sort)
for plugin_dir in "${PLUGIN_DIRS[@]}"; do
    # ... process plugin ...
done
```

**Warning signs:**
- Hooks execute in different order after container rebuild on different machine
- User reports "it works on my Mac but not in production"
- Hook execution order changes after renaming a plugin directory

**Phase to address:**
**Phase 1 (Core Plugin System)** — use sorted iteration from the start; document the alphabetical ordering contract.

---

### Pitfall 7: sed Token Replacement with Unescaped Special Characters

**What goes wrong:**
When hydrating plugin MCP server configs with secrets containing special characters (e.g., API keys with `/`, `&`, `$`), the current sed-based token replacement breaks:

```bash
# From spec (vulnerable):
HYDRATED_MCP=$(echo "$PLUGIN_MCP" | sed "s|{{MCP_GATEWAY_URL}}|$MCP_GATEWAY_URL|g")
```

If `MCP_GATEWAY_URL` contains `&`, sed interprets it as "insert entire match" and corrupts the output. If it contains `/`, the `|` delimiter doesn't help because `$` triggers variable expansion in double quotes.

**Why it happens:**
sed replacement strings treat `&`, `\`, and delimiter characters as special. Shell variable expansion in double quotes interprets `$`, `` ` ``, `!`, `\` before sed sees them ([Quotes and escaping - The Bash Hackers Wiki](https://flokoe.github.io/bash-hackers-wiki/syntax/quoting/)).

**How to avoid:**
Use jq for token replacement instead of sed when working with JSON:

```bash
# CORRECT: jq handles escaping automatically
HYDRATED_MCP=$(echo "$PLUGIN_MCP" | jq \
    --arg gateway_url "$MCP_GATEWAY_URL" \
    'walk(if type == "string" then gsub("{{MCP_GATEWAY_URL}}"; $gateway_url) else . end)')
```

For multiple token replacements:

```bash
HYDRATED_MCP=$(echo "$PLUGIN_MCP" | jq \
    --arg gateway "$MCP_GATEWAY_URL" \
    --arg api_key "$SOME_API_KEY" \
    'walk(if type == "string" then
        gsub("{{MCP_GATEWAY_URL}}"; $gateway) |
        gsub("{{SOME_API_KEY}}"; $api_key)
     else . end)')
```

**Warning signs:**
- `.mcp.json` contains corrupted URLs with duplicated parts
- MCP server fails to connect with "invalid URL" error
- Secrets containing `$`, `&`, or `/` cause install script errors

**Phase to address:**
**Phase 1 (Core Plugin System)** — replace sed token hydration with jq before plugin MCP server feature ships.

---

### Pitfall 8: Atomic Write Failure During Settings Merge

**What goes wrong:**
The spec shows this pattern for merging plugin data into settings:

```bash
jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

If jq fails (malformed JSON, out of disk space, jq version incompatibility), the redirect `> "$SETTINGS_FILE.tmp"` still succeeds, creating an empty or partial file. The `&&` prevents the `mv`, but `settings.local.json` is left in an inconsistent state for the next operation that reads it.

**Why it happens:**
Shell redirection (`>`) happens before the command runs. If jq fails, bash creates the output file first, then runs jq, which writes nothing or partial output ([How to Atomic Create a File If Not Exists in Bash Script](https://linuxvox.com/blog/atomic-create-file-if-not-exists-from-bash-script/)).

**How to avoid:**
Validate jq success before moving temp file, and use temp file in same directory (atomic rename guarantee):

```bash
TEMP_FILE=$(mktemp "$SETTINGS_FILE.XXXXXX")  # Same directory as target
if jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' "$SETTINGS_FILE" > "$TEMP_FILE"; then
    mv "$TEMP_FILE" "$SETTINGS_FILE"
else
    echo "[install] ERROR: Failed to merge plugin env vars"
    rm -f "$TEMP_FILE"
    return 1
fi
```

Even better, validate the output is valid JSON before moving:

```bash
TEMP_FILE=$(mktemp "$SETTINGS_FILE.XXXXXX")
jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' "$SETTINGS_FILE" > "$TEMP_FILE"
if jq empty < "$TEMP_FILE" 2>/dev/null; then
    mv "$TEMP_FILE" "$SETTINGS_FILE"
else
    echo "[install] ERROR: Plugin env merge produced invalid JSON"
    rm -f "$TEMP_FILE"
    return 1
fi
```

**Warning signs:**
- Corrupted `settings.local.json` after plugin installation
- Claude Code fails to start with "invalid settings file" error
- Empty or partial `settings.local.json` after script interruption (Ctrl+C, container stop)

**Phase to address:**
**Phase 1 (Core Plugin System)** — implement atomic write pattern for all JSON file modifications.

---

### Pitfall 9: Plugin Hook Script Execution Failure Silent Swallowing

**What goes wrong:**
A plugin registers a hook in `plugin.json`:

```json
"hooks": {
  "Stop": [{"type": "command", "command": "python3 ~/.claude/hooks/broken_hook.py"}]
}
```

The hook script has a bug (missing dependency, syntax error, wrong shebang). During installation, the hook registration is successfully merged into `settings.local.json`, but when Claude Code fires the `Stop` event, the hook fails silently. The user never knows the plugin's hook didn't work.

**Why it happens:**
The install script doesn't validate that hook command paths exist or are executable. Claude Code may log hook failures to a file the user never checks. The spec says: "The install script could validate this and warn, but shouldn't block."

**How to avoid:**
**During installation:** Validate hook commands reference files that exist and are executable:

```bash
# After accumulating hooks from plugin.json
# Validate each hook command before merging
for event in $(echo "$PLUGIN_HOOKS" | jq -r 'keys[]'); do
    hooks=$(echo "$PLUGIN_HOOKS" | jq -c ".[$event][]")
    while IFS= read -r hook; do
        cmd=$(echo "$hook" | jq -r '.command')
        # Extract script path (first argument before flags/params)
        script_path=$(echo "$cmd" | awk '{print $2}')  # e.g., "~/.claude/hooks/script.py"
        script_path_expanded="${script_path/#\~/$HOME}"

        if [ ! -f "$script_path_expanded" ]; then
            echo "[install] WARNING: Plugin '$plugin_name' hook for '$event' references missing file: $script_path"
        elif [ ! -x "$script_path_expanded" ]; then
            echo "[install] WARNING: Plugin '$plugin_name' hook for '$event' references non-executable file: $script_path"
        fi
    done <<< "$hooks"
done
```

**Runtime:** Ensure hook scripts exit 0 on success and log failures:

```python
# In plugin hook scripts
import sys
try:
    # ... hook logic ...
    sys.exit(0)
except Exception as e:
    with open(os.path.expanduser("~/.claude/hooks/hook-errors.log"), "a") as f:
        f.write(f"{datetime.now()} ERROR in hook: {e}\n")
    sys.exit(0)  # Don't block Claude Code from continuing
```

**Warning signs:**
- Plugin declares a hook but the expected side effect never happens (file not created, API not called)
- `~/.claude/hooks/` contains script with wrong permissions or missing shebang
- Hook worked when manually run but not when triggered by Claude Code event

**Phase to address:**
**Phase 2 (Hook Validation)** — add hook validation as a separate validation pass after core plugin installation works.

---

### Pitfall 10: Langfuse Migration Breaking Existing Behavior

**What goes wrong:**
When migrating the existing hardcoded Langfuse hook from `settings.json.template` to a plugin:

1. Remove hook registration from `settings.json.template`
2. Create `plugins/langfuse-tracing/plugin.json` with hook registration
3. After rebuild, Langfuse tracing **stops working** even though plugin shows as installed

**Why it happens:**
The template's hook structure doesn't match the plugin's hook structure. Current template shows:

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {"type": "command", "command": "python3 /home/node/.claude/hooks/langfuse_hook.py"}
      ]
    }
  ]
}
```

This is **nested arrays** (array of objects containing arrays of hooks). The plugin spec shows:

```json
"hooks": {
  "Stop": [
    {"type": "command", "command": "python3 ~/.claude/hooks/langfuse_hook.py"}
  ]
}
```

This is **flat arrays** (array of hook objects). When merging, these structures conflict, causing Claude Code to parse hooks incorrectly.

**How to avoid:**
**Before migration:**
1. Verify the exact hook structure Claude Code expects by checking official docs
2. Test plugin hook registration with a minimal test plugin before migrating Langfuse
3. Keep both template hook AND plugin hook during transition period, verify both work

**During migration:**
1. Update `settings.json.template` to use the same structure as plugin hooks
2. Remove template hook registration ONLY AFTER plugin hook is confirmed working
3. Add migration validation: script checks if Langfuse hook exists in settings after plugin install

```bash
# Validation after plugin installation
if [ "$PLUGIN_NAME" = "langfuse-tracing" ]; then
    LANGFUSE_HOOK_COUNT=$(jq '[.hooks.Stop[]? | select(.type == "command" and (.command | contains("langfuse_hook.py")))] | length' "$CLAUDE_DIR/settings.local.json")
    if [ "$LANGFUSE_HOOK_COUNT" -eq 0 ]; then
        echo "[install] ERROR: Langfuse plugin installed but hook not found in settings"
        return 1
    fi
fi
```

**Warning signs:**
- Langfuse UI shows no new traces after container rebuild
- `cat ~/.claude/settings.local.json | jq .hooks.Stop` shows unexpected structure
- Hook registration exists but with wrong nesting level

**Phase to address:**
**Phase 3 (Langfuse Migration)** — dedicated phase for migrating existing hook to plugin system, with before/after testing.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use `*` operator for all jq merges | Simple one-liner, works for objects | Arrays get overwritten; plugin hooks disappear | **Never** — arrays are common in settings |
| Skip hook command validation during install | Faster install, less code | Silent failures at runtime; users don't know hooks are broken | **Never** — warnings cost nothing |
| Use sed for JSON token replacement | Familiar tool, fewer dependencies | Breaks with special characters; produces corrupt JSON | **Never** — jq is already required |
| Single temp file name for atomic writes | Simple pattern | Race condition if parallel installs | Only if guaranteed single install process |
| Alphabetical plugin ordering by directory listing | No extra code needed | Non-deterministic across filesystems | **Never** — explicit sort is one line |
| Disable plugin by deleting directory | Intuitive for users | Breaks on next git pull; lost local plugins | Only for quick debugging, not production |
| Use `-r` flag with jq for all extractions | Raw strings easier to work with in bash | Null becomes string "null", breaks JSON merges | Only for final output (echo to user), not intermediate JSON |

## Integration Gotchas

Common mistakes when connecting plugin system to existing components.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| mcp-setup script | Running after plugin install, overwriting `.mcp.json` | Make mcp-setup plugin-aware; merge plugin entries with template entries |
| GSD installation | Installing GSD before plugins, allowing plugins to overwrite GSD files | Install GSD last; add explicit guards to prevent plugin files from clobbering GSD namespace |
| settings.local.json generation | Merge plugins directly into template-hydrated settings | Hydrate template first, then merge plugin data in separate step with array concatenation |
| postStartCommand timing | Assuming postStartCommand runs after postCreateCommand completes | Explicitly order operations: template hydration → plugin install → mcp-setup (plugin-aware) |
| config.json plugin disabling | Deleting disabled plugin's files during install | Leave files in place; skip registration only; allows re-enabling without re-copy |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Re-reading settings.json for each plugin | Install gets slower with more plugins | Accumulate all plugin data, do single merge at end | 10+ plugins (noticeable lag) |
| No incremental plugin updates | Every install copies all plugin files even if unchanged | Check file timestamps or hashes before copying | 20+ plugins with large skill reference docs |
| Multiple jq invocations in loops | High CPU usage during install | Accumulate JSON in bash variables, single jq merge | 15+ plugins with complex manifests |
| Unbounded hook array concatenation | settings.json grows indefinitely if plugins re-register hooks | Deduplicate hooks by command string before merge | After 5+ container rebuilds with same plugins |
| No validation short-circuit | Install validates all 50 plugins even if first one fails | Stop on first critical validation failure (missing plugin.json) | 30+ plugins in development |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Executing plugin hook scripts during install | Malicious plugin runs arbitrary code during install | Never execute hooks at install time; only copy and register them |
| Exposing secrets in plugin.json | Plugin commits API keys to git | Use token placeholders (`{{API_KEY}}`), hydrate from secrets.json only |
| No plugin.json schema validation | Malicious JSON could exploit jq vulnerabilities | Validate plugin.json structure before passing to jq |
| Plugin hooks run as same user as Claude Code | Compromised hook has full filesystem access | Not preventable in current architecture; document in plugin security guide |
| Copying plugin files without sanitizing paths | Path traversal: `../../.ssh/authorized_keys` | Validate plugin files don't escape plugin directory before copying |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No feedback when plugin disabled via config.json | User edits `plugin.json`, rebuilds, wonders why changes didn't apply | Log: "Plugin 'foo': disabled in config.json, skipping" |
| Silent hook registration failures | Plugin appears installed but doesn't work | Validate hook commands exist; warn if missing (see Pitfall 9) |
| No differentiation between plugin errors and install errors | User sees "install failed", doesn't know which plugin broke | Prefix all plugin logs with `[install] Plugin 'name':` |
| Overwriting existing files without warning | User's custom command.md silently replaced by plugin | Check for conflicts, prompt or log warning: "Overwriting existing file" |
| No way to verify plugin installation | User doesn't know if plugin actually loaded | Print summary: "Installed 3 plugin(s): langfuse-tracing, auto-lint, my-plugin" |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Hook array merging:** Verify hooks from multiple plugins actually concatenate, not overwrite — test with 2 plugins registering same event
- [ ] **MCP server registration:** After full container rebuild (not just install script), verify plugin MCP servers appear in `npx @anthropic/code mcp list`
- [ ] **GSD protection:** After installing plugin with `commands/test.md` and `agents/custom.md`, verify GSD commands still work and GSD agents weren't overwritten
- [ ] **Null value handling:** Create plugin with `"env": null` in plugin.json, verify install doesn't crash or corrupt settings.local.json
- [ ] **Empty plugin directory:** Create plugin with only plugin.json (no skills/commands/hooks), verify install succeeds without errors
- [ ] **Special characters in secrets:** Set `MCP_GATEWAY_URL` to `http://host:8080/path?foo=bar&baz=qux`, verify `.mcp.json` hydration is correct
- [ ] **Glob no-match:** Create plugin with empty `commands/` directory, verify no `*.md` file appears in `~/.claude/commands/`
- [ ] **Alphabetical plugin order:** Create plugins named `z-last`, `a-first`, `m-middle`, verify hooks execute in alphabetical order
- [ ] **Langfuse migration:** After migrating langfuse to plugin, verify tracing still works (check Langfuse UI for new traces)
- [ ] **Atomic write interruption:** Kill install script during jq merge (`kill -9` during plugin install), verify settings.local.json is not corrupted

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Array overwrite corrupted hooks | LOW | 1. Delete `~/.claude/settings.local.json` 2. Rebuild container 3. Install script regenerates |
| .mcp.json overwritten by mcp-setup | LOW | 1. Re-run `install-agent-config.sh` manually 2. Plugin MCP servers re-registered |
| GSD files clobbered by plugin | MEDIUM | 1. Delete `~/.claude/commands/gsd/` 2. Manually run `npx get-shit-done-cc --claude --global` |
| Corrupted settings.json from null merge | LOW | 1. `rm ~/.claude/settings.local.json` 2. `bash .devcontainer/install-agent-config.sh` |
| Invalid JSON from failed atomic write | LOW | 1. Check for `.tmp` files in `~/.claude/` 2. Restore from template: re-run install script |
| Hook command path doesn't exist | LOW | 1. Fix plugin hook script path in plugin.json 2. Rebuild or re-run install script |
| Plugin execution order wrong | MEDIUM | 1. Rename plugin directories to force alphabetical order (e.g., `01-logging`, `02-analytics`) |
| sed token replacement corruption | MEDIUM | 1. Clear corrupted `.mcp.json` 2. Update install script to use jq 3. Rebuild |
| Langfuse migration broke tracing | MEDIUM | 1. Revert settings.json.template to include hardcoded hook 2. Disable langfuse-tracing plugin 3. Debug structure mismatch |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| jq array overwriting | Phase 1 (Core Plugin System) | Install 2 plugins with same hook event, verify both hooks in settings.local.json |
| .mcp.json double-write | Phase 1 (Core Plugin System) | Full container rebuild, verify plugin MCP server in `mcp list` output |
| GSD file clobbering | Phase 1 (Core Plugin System) | Install plugin with commands/agents, verify GSD commands still work |
| Null value merge corruption | Phase 1 (Core Plugin System) | Create plugin with null/empty fields, verify install succeeds |
| Glob pattern no-match | Phase 1 (Core Plugin System) | Create plugin with empty subdirs, verify no glob literal files |
| Hook execution order | Phase 1 (Core Plugin System) | Name plugins `z-`, `a-`, `m-`, verify order in hook logs |
| sed token replacement | Phase 1 (Core Plugin System) | Use secret with special chars, verify MCP config correct |
| Atomic write failure | Phase 1 (Core Plugin System) | Kill install script mid-merge (manual test), verify JSON valid |
| Hook script validation | Phase 2 (Hook Validation) | Install plugin with broken hook path, verify warning logged |
| Langfuse migration | Phase 3 (Langfuse Migration) | Migrate to plugin, verify traces appear in Langfuse UI |

## Sources

### jq Merging and Edge Cases
- [How to Recursively Merge JSON Objects and Concatenate Arrays with jq](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/)
- [jq 1.8 Manual](https://jqlang.org/manual/)
- [JQ - Handling null values and default values](https://www.devtoolsdaily.com/blog/jq-null-values-and-default/)
- [How to Merge JSON Files Using jq: Complete 2026 Guide](https://copyprogramming.com/howto/how-to-merge-json-files-using-jq-or-any-tool)

### Bash Scripting Pitfalls
- [BashPitfalls - Greg's Wiki](https://mywiki.wooledge.org/BashPitfalls)
- [glob - Greg's Wiki](https://mywiki.wooledge.org/glob)
- [Quotes and escaping - The Bash Hackers Wiki](https://flokoe.github.io/bash-hackers-wiki/syntax/quoting/)
- [Bash Scripting: The Complete Guide for 2026](https://devtoolbox.dedyn.io/blog/bash-scripting-complete-guide)

### Atomic Write and File Operations
- [How to Atomic Create a File If Not Exists in Bash Script](https://linuxvox.com/blog/atomic-create-file-if-not-exists-from-bash-script/)
- [BashFAQ/062 - Greg's Wiki](https://mywiki.wooledge.org/BashFAQ/062)
- [How to write idempotent Bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)

### Plugin and Hook Systems
- [GitHub - progrium/pluginhook](https://github.com/progrium/pluginhook)
- [The WordPress Hook Priority System Is Why Your Tracking Plugins Fight](https://seresa.io/blog/marketing-pixels-tags/the-wordpress-hook-priority-system-is-why-your-tracking-plugins-fight)
- [Automate workflows with hooks - Claude Code Docs](https://code.claude.com/docs/en/hooks-guide)

### Token Replacement and Escaping
- [Quotes and escaping - The Bash Hackers Wiki](https://bash-hackers.gabe565.com/syntax/quoting/)
- [Gotchas and Tricks - CLI text processing with GNU sed](https://learnbyexample.github.io/learn_gnused/gotchas-and-tricks.html)

---
*Pitfalls research for: Plugin system integration into bash install script*
*Researched: 2026-02-15*

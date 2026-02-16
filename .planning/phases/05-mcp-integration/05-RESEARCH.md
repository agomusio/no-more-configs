# Phase 5: MCP Integration - Research

**Researched:** 2026-02-15
**Domain:** Model Context Protocol (MCP) server registration for plugins
**Confidence:** HIGH

## Summary

Phase 5 integrates plugin MCP servers into the NMC container's configuration-as-code system. The install script will discover MCP server declarations in plugin.json manifests, hydrate secret token placeholders from secrets.json, merge the servers into ~/.claude/.mcp.json with source tagging, and coordinate with the mcp-setup postStartCommand to prevent overwriting. This builds directly on Phase 4's plugin discovery and accumulation patterns.

**Primary recommendation:** Use jq-based token hydration with namespaced secret lookups and full ownership of .mcp.json by install script, mirroring the proven settings.json merge pattern from Phase 4.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Secret sourcing:**
- Secrets come from `secrets.json` only — no environment variable fallback
- Secret keys are namespaced by plugin name using nested objects in secrets.json
  - Plugin declares `SECRET_KEY` in plugin.json → looked up as `secrets.json["langfuse-tracing"]["SECRET_KEY"]`
  - secrets.json structure: `{ "plugin-name": { "KEY": "value" } }`

**Missing secret behavior:**
- Register the MCP server with raw placeholder tokens left in place (server will fail at runtime but entry exists)
- Print inline warning during install: e.g., `⚠ langfuse-tracing: missing SECRET_KEY`
- No summary section for missing secrets — inline warning is sufficient

**Persistence strategy:**
- Install script has full ownership of `.mcp.json` — regenerates from scratch on every rebuild
- Plugin MCP entries are tagged with source metadata (e.g., `"_source": "plugin:langfuse-tracing"`) for traceability
- Disabled plugins have their MCP servers actively removed — install script scans for tagged entries from disabled plugins and removes them
- Since install owns .mcp.json fully, mcp-setup's postStartCommand must merge into what install already wrote (not overwrite)

### Claude's Discretion

- Token placeholder format ({{TOKEN}} vs ${TOKEN} — pick what avoids conflicts with existing patterns)
- Whether to distinguish "secret key missing" vs "secret key present but empty" — pick what's practical
- Whether to skip MCP server entirely when ALL secrets are missing vs same behavior as partial — pick the sensible approach
- Exact coordination mechanism between install script and mcp-setup postStartCommand
- MCP config structure within plugin.json

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.6+ | JSON manipulation and token replacement | Already used throughout install script, handles escaping correctly |
| bash | 4.0+ | Install script runtime | Container standard, existing pattern |
| grep | GNU grep | Token extraction for warnings | Standard Unix tool, existing pattern |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| sed | GNU sed | Simple non-JSON string replacement | Only for non-JSON templates (avoided for token hydration) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq token replacement | sed-based replacement | sed breaks with special characters in secrets (see Pitfall 7 in PITFALLS.md) — jq is safer |
| Incremental .mcp.json patching | Full ownership regeneration | Incremental patching requires complex state tracking — full regen is simpler and matches settings.json pattern |
| Environment variable fallback | secrets.json only | User decided — secrets.json only, no fallback |

**Installation:**
Already installed in container — no additional dependencies needed.

## Architecture Patterns

### Recommended Integration Structure

Install script flow with Phase 5 additions:

```
1. Read config.json + secrets.json
2. Generate firewall-domains.conf
3. Generate .vscode/settings.json
4. Generate Codex config.toml
5. Create directory structure
6. Copy standalone skills/hooks/commands
7. Hydrate settings.json.template
8. Seed settings.json with permissions
9. **Install plugins** (Phase 4 — copy files + accumulate hooks/env/MCP)
10. **PHASE 5: Merge plugin MCP servers into .mcp.json (BEFORE base MCP generation)**
11. Generate base .mcp.json from config.json templates (merges with plugin entries)
12. Restore credentials
13. Restore git identity
14. Generate infra/.env
15. Detect unresolved placeholders
16. Install GSD framework
17. Enforce settings.json final values
18. **Merge plugin hooks into settings.json** (Phase 4)
19. **Merge plugin env into settings.json** (Phase 4)
20. Print summary
```

**Critical ordering:** Plugin MCP merge MUST happen BEFORE base .mcp.json generation so that install script has full ownership and can write .mcp.json once with all content.

### Pattern 1: Full Ownership of .mcp.json

**What:** Install script regenerates .mcp.json from scratch on every run, combining base template servers + plugin servers in a single write.

**When to use:** This is the ONLY pattern for .mcp.json generation.

**Example:**
```bash
# Phase 4 accumulates plugin MCP during plugin loop
PLUGIN_MCP='{}'  # Initialized at top of script

# In plugin loop (Phase 4 already implemented):
MANIFEST_MCP=$(jq -r '.mcp_servers // {}' "$MANIFEST")
if [ "$MANIFEST_MCP" != "{}" ]; then
    PLUGIN_MCP=$(jq -n --argjson acc "$PLUGIN_MCP" --argjson new "$MANIFEST_MCP" \
        '$acc * $new')
fi

# Phase 5: After plugin loop, BEFORE base .mcp.json generation
# Build complete .mcp.json with plugin servers + base servers in one operation
MCP_JSON='{"mcpServers":{}}'

# Step 1: Add plugin servers (hydrated)
if [ "$PLUGIN_MCP" != "{}" ]; then
    HYDRATED_PLUGIN_MCP=$(hydrate_mcp_tokens "$PLUGIN_MCP")
    MCP_JSON=$(echo "$MCP_JSON" | jq --argjson plugin "$HYDRATED_PLUGIN_MCP" \
        '.mcpServers = $plugin')
fi

# Step 2: Add base template servers from config.json
for SERVER in $ENABLED_SERVERS; do
    # ... existing template hydration logic ...
    MCP_JSON=$(echo "$MCP_JSON" | jq --argjson server "{\"$SERVER\": $HYDRATED}" \
        '.mcpServers += $server')
done

# Write once
echo "$MCP_JSON" > "$CLAUDE_DIR/.mcp.json"
```

**Why this pattern:** Matches Phase 4's settings.json pattern, prevents mcp-setup conflicts, enables source tagging, simplifies disabled plugin cleanup.

### Pattern 2: Namespaced Secret Lookups

**What:** Plugin secret tokens are looked up in secrets.json under a namespace matching the plugin name.

**When to use:** Any plugin MCP server with secret placeholders.

**Example:**
```bash
# Plugin: langfuse-tracing
# plugin.json declares: "env": { "SECRET_KEY": "{{LANGFUSE_SECRET_KEY}}" }
# secrets.json structure: { "langfuse-tracing": { "LANGFUSE_SECRET_KEY": "pk-..." } }

# Lookup:
SECRET_VALUE=$(jq -r --arg plugin "$plugin_name" --arg key "LANGFUSE_SECRET_KEY" \
    '.[$plugin][$key] // ""' "$SECRETS_FILE")

# If empty, print warning:
if [ -z "$SECRET_VALUE" ]; then
    echo "⚠ $plugin_name: missing $key"
fi
```

**Why this pattern:** Prevents collisions between plugins using same secret key names, matches user decision for namespaced structure.

### Pattern 3: Source Tagging for Traceability

**What:** Each plugin MCP server entry gets a `_source` metadata field identifying its origin.

**When to use:** All plugin MCP servers.

**Example:**
```bash
# During plugin loop accumulation:
MANIFEST_MCP=$(jq -r --arg plugin "$plugin_name" '.mcp_servers // {} |
    to_entries |
    map(.value._source = "plugin:\($plugin)") |
    from_entries' "$MANIFEST")

# Result in .mcp.json:
{
  "mcpServers": {
    "langfuse-api": {
      "_source": "plugin:langfuse-tracing",
      "type": "http",
      "url": "https://api.langfuse.com"
    }
  }
}
```

**Why this pattern:** Enables cleanup when plugin is disabled, debugging which plugin added which server, future conflict resolution.

### Pattern 4: jq-based Token Hydration

**What:** Replace `{{TOKEN}}` placeholders using jq's walk function with string substitution.

**When to use:** Hydrating plugin MCP configs before merging into .mcp.json.

**Example:**
```bash
# Extract all unique tokens from PLUGIN_MCP
TOKENS=$(echo "$PLUGIN_MCP" | grep -oP '\{\{[A-Z_]+\}\}' | sort -u || true)

HYDRATED_MCP="$PLUGIN_MCP"
for TOKEN_PATTERN in $TOKENS; do
    # Extract token name (remove {{ and }})
    TOKEN_NAME=$(echo "$TOKEN_PATTERN" | sed 's/{{//;s/}}//')

    # Look up in secrets.json under plugin namespace
    # (plugin_name determined from _source tag or context)
    SECRET_VALUE=$(jq -r --arg plugin "$plugin_name" --arg key "$TOKEN_NAME" \
        '.[$plugin][$key] // ""' "$SECRETS_FILE" 2>/dev/null || echo "")

    # Warn if missing
    if [ -z "$SECRET_VALUE" ]; then
        echo "⚠ $plugin_name: missing $TOKEN_NAME"
    fi

    # Hydrate using jq (safe for special characters)
    HYDRATED_MCP=$(echo "$HYDRATED_MCP" | jq \
        --arg token "$TOKEN_PATTERN" \
        --arg value "$SECRET_VALUE" \
        'walk(if type == "string" then gsub($token; $value) else . end)')
done
```

**Why this pattern:** Avoids sed pitfalls with special characters (see Pitfall 7), handles nested JSON correctly, safe for all secret values.

### Anti-Patterns to Avoid

- **sed-based token replacement for JSON:** Breaks with special characters in secrets ($, &, /)
- **Incremental .mcp.json patching:** Complex state tracking, race conditions with mcp-setup
- **Global secret namespace:** Collisions between plugins using same key names
- **Merge instead of regenerate:** Can't cleanly remove disabled plugin servers

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON token replacement | sed with s/// | jq with walk + gsub | sed interprets special chars, breaks with $, &, / in values |
| .mcp.json state tracking | Incremental patch system | Full regeneration pattern | State tracking is complex, prone to bugs, full regen is proven |
| Secret collision detection | Manual namespace checking | Nested secrets.json structure | Structure enforces namespace, no runtime checking needed |
| mcp-setup coordination | Lock files or timestamps | Full ownership by install | Install writes once, mcp-setup reads and merges, simple ordering |

**Key insight:** The install script already has proven patterns for JSON merging (settings.json, hooks, env vars). Reusing these patterns for MCP integration is safer than inventing new mechanisms.

## Common Pitfalls

### Pitfall 1: mcp-setup Overwrites Plugin MCP Servers

**What goes wrong:** mcp-setup runs in postStartCommand AFTER install-agent-config.sh. If mcp-setup regenerates .mcp.json from scratch (current behavior), it wipes out plugin MCP servers that install script added.

**Why it happens:** Current mcp-setup-bin.sh (lines 13-40) follows same pattern as install script — builds .mcp.json from enabled config.json templates. It doesn't know about plugin servers.

**How to avoid:**
1. Install script writes .mcp.json with plugin servers + base servers (full ownership)
2. mcp-setup loads existing .mcp.json, preserves entries with `_source: "plugin:*"` tag
3. mcp-setup only updates/adds base template servers
4. Final .mcp.json has plugin servers (from install) + base servers (refreshed by mcp-setup)

**Warning signs:**
- `/mcp` command shows servers after rebuild, but they disappear after container start
- Plugin MCP servers work in postCreateCommand but not after postStartCommand
- .mcp.json is correct after install but gets overwritten later

**Implementation:**
```bash
# In mcp-setup-bin.sh (modified):
# Load existing .mcp.json
EXISTING_MCP=$(cat "$claude_dir/.mcp.json" 2>/dev/null || echo '{"mcpServers":{}}')

# Extract plugin servers (preserve them)
PLUGIN_SERVERS=$(echo "$EXISTING_MCP" | jq '.mcpServers |
    with_entries(select(.value._source? // "" | startswith("plugin:")))')

# Build new base servers from templates (existing logic)
BASE_SERVERS='{"mcpServers":{}}'
for SERVER in $ENABLED_SERVERS; do
    # ... existing template hydration ...
    BASE_SERVERS=$(echo "$BASE_SERVERS" | jq --argjson s "{\"$SERVER\": $HYDRATED}" \
        '.mcpServers += $s')
done

# Merge: plugin servers + base servers
FINAL_MCP=$(echo "$BASE_SERVERS" | jq --argjson plugins "$PLUGIN_SERVERS" \
    '.mcpServers = $plugins + .mcpServers')

echo "$FINAL_MCP" > "$claude_dir/.mcp.json"
```

### Pitfall 2: Special Characters in Secrets Break Token Replacement

**What goes wrong:** API keys often contain special characters (`/`, `+`, `=`, `$`). Using sed for token replacement interprets these as sed metacharacters and corrupts the output.

**Why it happens:** sed replacement syntax treats `&` (insert match), `\` (escape), `/` (delimiter), and shell variables in double quotes expand before sed sees them.

**How to avoid:** Use jq's `walk` + `gsub` for all token replacement in JSON:

```bash
# WRONG (breaks with special chars):
HYDRATED=$(echo "$MCP_JSON" | sed "s|{{API_KEY}}|$SECRET_VALUE|g")

# CORRECT (safe for all values):
HYDRATED=$(echo "$MCP_JSON" | jq \
    --arg token "{{API_KEY}}" \
    --arg value "$SECRET_VALUE" \
    'walk(if type == "string" then gsub($token; $value) else . end)')
```

**Warning signs:**
- MCP server URLs have duplicated segments
- Auth tokens appear corrupted in .mcp.json
- MCP connection fails with "invalid URL" or "authentication failed"

### Pitfall 3: Missing Secrets Crash Install Script

**What goes wrong:** If secrets.json doesn't exist or plugin secret is missing, token hydration code tries to access undefined jq paths and fails.

**Why it happens:** Unsafe jq path access without `// ""` fallback.

**How to avoid:**
```bash
# WRONG (crashes if path doesn't exist):
SECRET=$(jq -r '.["plugin-name"]["SECRET_KEY"]' "$SECRETS_FILE")

# CORRECT (returns empty string on missing):
SECRET=$(jq -r '.["plugin-name"]["SECRET_KEY"] // ""' "$SECRETS_FILE" 2>/dev/null || echo "")

# Then check and warn:
if [ -z "$SECRET" ]; then
    echo "⚠ plugin-name: missing SECRET_KEY"
fi
```

**Warning signs:**
- Install script exits with jq error "null (null) cannot be accessed"
- Container rebuild fails when secrets.json is incomplete
- Error on first rebuild before secrets.json exists

### Pitfall 4: Disabled Plugin Servers Persist in .mcp.json

**What goes wrong:** User disables a plugin in config.json, but its MCP servers remain in .mcp.json because install script doesn't actively remove them.

**Why it happens:** Full regeneration without checking plugin enabled state means disabled plugin servers linger.

**How to avoid:** During plugin loop, only accumulate MCP servers from ENABLED plugins. Install script regenerates .mcp.json from scratch each time, so disabled plugins naturally disappear.

```bash
# In plugin loop (Phase 4):
if [ "$plugin_enabled" = "false" ]; then
    echo "[install] Plugin '$plugin_name': skipped (disabled)"
    continue  # Don't accumulate MCP servers
fi

# ... later, accumulate MCP servers only from enabled plugins ...
MANIFEST_MCP=$(jq -r '.mcp_servers // {}' "$MANIFEST")
if [ "$MANIFEST_MCP" != "{}" ]; then
    PLUGIN_MCP=$(jq -n --argjson acc "$PLUGIN_MCP" --argjson new "$MANIFEST_MCP" \
        '$acc * $new')
fi
```

Source tagging enables verification: after .mcp.json written, check no disabled plugins appear:

```bash
# Verification (optional, helps debugging):
DISABLED_PLUGINS=$(jq -r '.plugins | to_entries[] |
    select(.value.enabled == false) | .key' "$CONFIG_FILE")

for disabled in $DISABLED_PLUGINS; do
    HAS_ENTRY=$(jq --arg src "plugin:$disabled" \
        '.mcpServers | with_entries(select(.value._source == $src)) | length' \
        "$CLAUDE_DIR/.mcp.json")
    if [ "$HAS_ENTRY" -gt 0 ]; then
        echo "⚠ WARNING: Disabled plugin $disabled still has MCP servers in .mcp.json"
    fi
done
```

**Warning signs:**
- MCP servers from disabled plugins still appear in `/mcp` output
- User reports plugin is "disabled but still connecting to external service"

### Pitfall 5: Token Placeholder Format Conflicts

**What goes wrong:** If plugin uses `${TOKEN}` format (shell variable style), bash expands it during string interpolation before jq sees it.

**Why it happens:** Bash performs variable expansion on `${VAR}` in double quotes.

**How to avoid:** Use `{{TOKEN}}` format (double braces) for all placeholders. This doesn't conflict with shell syntax or jq syntax.

**Warning signs:**
- Placeholder tokens disappear before hydration happens
- .mcp.json has empty strings where secrets should be
- Error "unbound variable" in install script

**Decision:** Use `{{TOKEN}}` format to match existing settings.json.template pattern (verified at agent-config/settings.json.template lines 11-13).

## Code Examples

Verified patterns from existing codebase and research:

### Plugin MCP Accumulation (in plugin loop)

```bash
# Source: Phase 4 pattern + .planning/nmc-plugin-spec.md lines 308-312
# Location: install-agent-config.sh plugin loop

# Initialize accumulator (top of script with other accumulators)
PLUGIN_MCP='{}'

# In plugin loop, after plugin enabled check:
MANIFEST_MCP=$(jq -r --arg plugin "$plugin_name" '.mcp_servers // {} |
    to_entries |
    map(.value._source = "plugin:\($plugin)" | .value) |
    from_entries' "$MANIFEST" 2>/dev/null || echo "{}")

if [ "$MANIFEST_MCP" != "{}" ]; then
    # Merge into accumulator (object merge, not array append)
    PLUGIN_MCP=$(jq -n --argjson acc "$PLUGIN_MCP" --argjson new "$MANIFEST_MCP" \
        '$acc * $new' 2>/dev/null || echo "$PLUGIN_MCP")
fi
```

### Token Hydration with Namespaced Secret Lookup

```bash
# Source: .planning/research/PITFALLS.md lines 315-331 + user decisions
# Location: After plugin loop, before .mcp.json generation

hydrate_plugin_mcp() {
    local plugin_mcp="$1"
    local secrets_file="$2"

    # Extract all unique {{TOKEN}} patterns
    local tokens=$(echo "$plugin_mcp" | grep -oP '\{\{[A-Z_]+\}\}' | sort -u || true)

    local hydrated="$plugin_mcp"

    # For each plugin server, extract plugin name from _source tag and hydrate
    local servers=$(echo "$plugin_mcp" | jq -r 'keys[]')

    for server in $servers; do
        # Get plugin name from _source tag
        local plugin_name=$(echo "$plugin_mcp" | jq -r --arg s "$server" \
            '.[$s]._source // "" | sub("^plugin:"; "")')

        [ -z "$plugin_name" ] && continue

        # Extract tokens specific to this server
        local server_json=$(echo "$plugin_mcp" | jq --arg s "$server" '.[$s]')
        local server_tokens=$(echo "$server_json" | grep -oP '\{\{[A-Z_]+\}\}' | sort -u || true)

        for token_pattern in $server_tokens; do
            local token_name=$(echo "$token_pattern" | sed 's/{{//;s/}}//')

            # Lookup in secrets.json under plugin namespace
            local secret_value=$(jq -r --arg p "$plugin_name" --arg k "$token_name" \
                '.[$p][$k] // ""' "$secrets_file" 2>/dev/null || echo "")

            # Warn if missing
            if [ -z "$secret_value" ]; then
                echo "⚠ $plugin_name: missing $token_name"
            fi

            # Hydrate using jq (safe for special characters)
            hydrated=$(echo "$hydrated" | jq \
                --arg token "$token_pattern" \
                --arg value "$secret_value" \
                'walk(if type == "string" then gsub($token; $value) else . end)')
        done
    done

    echo "$hydrated"
}

# Usage:
if [ "$PLUGIN_MCP" != "{}" ]; then
    HYDRATED_PLUGIN_MCP=$(hydrate_plugin_mcp "$PLUGIN_MCP" "$SECRETS_FILE")
fi
```

### Unified .mcp.json Generation

```bash
# Source: .devcontainer/install-agent-config.sh lines 547-581 + Phase 5 requirements
# Location: After credential restoration, before infra/.env generation

# Start with base structure
MCP_JSON='{"mcpServers":{}}'

# Step 1: Add hydrated plugin servers FIRST
if [ "$PLUGIN_MCP" != "{}" ]; then
    HYDRATED_PLUGIN_MCP=$(hydrate_plugin_mcp "$PLUGIN_MCP" "$SECRETS_FILE")
    MCP_JSON=$(echo "$MCP_JSON" | jq --argjson plugin "$HYDRATED_PLUGIN_MCP" \
        '.mcpServers = $plugin')
fi

# Step 2: Add base template servers from config.json (existing logic)
if [ -f "$CONFIG_FILE" ]; then
    ENABLED_SERVERS=$(jq -r '.mcp_servers | to_entries[] |
        select(.value.enabled == true) | .key' "$CONFIG_FILE" 2>/dev/null || echo "")

    if [ -n "$ENABLED_SERVERS" ]; then
        for SERVER in $ENABLED_SERVERS; do
            TEMPLATE_FILE="$MCP_TEMPLATES_DIR/${SERVER}.json"
            if [ -f "$TEMPLATE_FILE" ]; then
                # Hydrate template and merge
                HYDRATED=$(sed "s|{{MCP_GATEWAY_URL}}|$MCP_GATEWAY_URL|g" "$TEMPLATE_FILE")
                MCP_JSON=$(echo "$MCP_JSON" | jq --argjson server "{\"$SERVER\": $HYDRATED}" \
                    '.mcpServers += $server')
                MCP_COUNT=$((MCP_COUNT + 1))
            else
                echo "[install] WARNING: Template $TEMPLATE_FILE not found for enabled server $SERVER"
            fi
        done
    fi
fi

# Fallback: if still empty, add default
SERVER_COUNT=$(echo "$MCP_JSON" | jq '.mcpServers | length')
if [ "$SERVER_COUNT" -eq 0 ]; then
    MCP_JSON='{"mcpServers":{"mcp-gateway":{"type":"sse","url":"'"$MCP_GATEWAY_URL"'/sse"}}}'
fi

# Write once
echo "$MCP_JSON" > "$CLAUDE_DIR/.mcp.json"
echo "[install] Generated .mcp.json with $(echo "$MCP_JSON" | jq '.mcpServers | length') server(s)"
```

### mcp-setup Coordination (preserve plugin servers)

```bash
# Source: New pattern for .devcontainer/mcp-setup-bin.sh
# Location: Replace existing .mcp.json generation (lines 13-40)

# Load existing .mcp.json (written by install script)
EXISTING_MCP=$(cat "$claude_dir/.mcp.json" 2>/dev/null || echo '{"mcpServers":{}}')

# Extract and preserve plugin servers (identified by _source tag)
PLUGIN_SERVERS=$(echo "$EXISTING_MCP" | jq '.mcpServers |
    with_entries(select(.value._source? // "" | startswith("plugin:")))')

# Build base servers from config.json templates (existing logic)
BASE_SERVERS='{"mcpServers":{}}'
if [ -f "$config_file" ]; then
    ENABLED_SERVERS=$(jq -r '.mcp_servers | to_entries[] |
        select(.value.enabled == true) | .key' "$config_file" 2>/dev/null || echo "")

    for SERVER in $ENABLED_SERVERS; do
        TEMPLATE_FILE="${templates_dir}/${SERVER}.json"
        if [ -f "$TEMPLATE_FILE" ]; then
            HYDRATED=$(sed "s|{{MCP_GATEWAY_URL}}|$gateway_url|g" "$TEMPLATE_FILE")
            BASE_SERVERS=$(echo "$BASE_SERVERS" | jq --argjson s "{\"$SERVER\": $HYDRATED}" \
                '.mcpServers += $s')
        fi
    done
fi

# Merge: plugin servers take precedence (from install), base servers updated
FINAL_MCP=$(jq -n --argjson plugins "$PLUGIN_SERVERS" --argjson base "$BASE_SERVERS" \
    '{mcpServers: ($plugins + $base.mcpServers)}')

# Write merged result
echo "$FINAL_MCP" | jq '.' > "$claude_dir/.mcp.json"
echo "✓ Generated .mcp.json with $(echo "$FINAL_MCP" | jq '.mcpServers | length') server(s)"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| sed token replacement | jq walk + gsub | Phase 5 | Handles special chars in secrets safely |
| mcp-setup overwrites .mcp.json | mcp-setup preserves plugin entries | Phase 5 | Plugin MCP servers persist across starts |
| Global secret namespace | Plugin-namespaced secrets | Phase 5 | No collision risk between plugins |
| Manual .mcp.json editing | Declarative plugin.json | Phase 5 | Plugin MCP servers auto-register |

**Deprecated/outdated:**
- **sed for JSON token replacement:** Replaced by jq to avoid special character bugs
- **SSE transport in MCP:** MCP specification deprecated SSE in favor of Streamable HTTP (but Claude Code still uses SSE for some servers)

## Open Questions

1. **Should we validate MCP server config structure before merging?**
   - What we know: plugin.json can declare arbitrary JSON in `mcp_servers` field
   - What's unclear: Do we validate it's a valid MCP config (has `type` or `command`, etc.) before merging?
   - Recommendation: Basic validation (check it's an object, has expected top-level keys). Invalid configs fail at runtime when Claude Code tries to connect, user sees error in /mcp output. Better than blocking install.

2. **What if two plugins declare the same MCP server name?**
   - What we know: PLUGIN_MCP accumulator uses object merge (`$acc * $new`), last write wins
   - What's unclear: Should we warn on collision?
   - Recommendation: Log warning when collision detected (check if key exists in accumulator before merge). Example: `⚠ WARNING: Plugin 'foo' MCP server 'api' overwrites earlier declaration`

3. **Should base template servers be able to override plugin servers?**
   - What we know: Current pattern adds plugin servers first, then base servers with `+=` (append)
   - What's unclear: User decision for precedence
   - Recommendation: Plugin servers should NOT be overridable by base templates (they're plugin-owned). But mcp-setup refreshes base servers each start. Use key precedence: if same name exists in plugin servers, skip base server addition with warning.

## Sources

### Primary (HIGH confidence)

- `.devcontainer/install-agent-config.sh` (lines 547-581) - Current .mcp.json generation pattern
- `.devcontainer/mcp-setup-bin.sh` (lines 13-60) - postStartCommand MCP regeneration
- `agent-config/settings.json.template` (lines 11-13) - {{TOKEN}} placeholder format
- `.planning/nmc-plugin-spec.md` (lines 241, 308-312, 366-379) - Plugin MCP accumulation spec
- `.planning/research/PITFALLS.md` (lines 295-340) - sed vs jq for token replacement
- `.planning/phases/04-core-plugin-system/04-RESEARCH.md` - Phase 4 accumulator patterns
- `agent-config/plugins/plugin-dev/skills/mcp-integration/SKILL.md` - MCP server types and config

### Secondary (MEDIUM confidence)

- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25) - Official MCP config format
- [MCP on OpenAI Codex](https://developers.openai.com/codex/mcp/) - Codex MCP configuration patterns
- [VS Code MCP Servers](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) - VS Code MCP integration

### Tertiary (LOW confidence)

None used — all sources verified against codebase or official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - jq, bash, grep already in use and verified in codebase
- Architecture: HIGH - Patterns match proven Phase 4 implementation, verified in install-agent-config.sh
- Pitfalls: HIGH - All pitfalls derived from existing PITFALLS.md research or identified in current codebase

**Research date:** 2026-02-15
**Valid until:** 2026-03-17 (30 days, stable technology)

**Sources verification:**
- All code examples reference specific line numbers in workspace files
- User decisions from CONTEXT.md incorporated as constraints
- No speculative features — all recommendations based on existing patterns

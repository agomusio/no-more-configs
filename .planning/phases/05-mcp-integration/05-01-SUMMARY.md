---
phase: 05-mcp-integration
plan: 01
subsystem: plugin-system
tags: [mcp, plugins, secrets, hydration]
dependency-graph:
  requires: [04-03]
  provides: [plugin-mcp-integration]
  affects: [install-agent-config.sh, mcp-setup-bin.sh]
tech-stack:
  added: [plugin-mcp-accumulation, namespaced-secret-hydration]
  patterns: [source-tagging, unified-mcp-generation]
key-files:
  created: []
  modified:
    - .devcontainer/install-agent-config.sh
    - .devcontainer/mcp-setup-bin.sh
decisions:
  - "Token placeholder format: {{TOKEN}} to match existing settings.json.template pattern"
  - "Missing secrets: register server with raw placeholders, print inline warning per token"
  - "Secret lookup: namespaced by plugin name (secrets.json[plugin-name][TOKEN])"
  - "Install script owns .mcp.json fully, mcp-setup preserves plugin entries by _source tag"
  - "Plugin servers added first, then base template servers (plugin precedence)"
metrics:
  duration: 151s
  completed: 2026-02-16T01:57:08Z
  tasks: 2
  commits: 2
  files_modified: 2
---

# Phase 5 Plan 1: Plugin MCP Integration Summary

**One-liner:** Plugin MCP servers auto-register in .mcp.json with namespaced secret hydration and persistence across container starts

## What Was Built

### Task 1: Plugin MCP Accumulation and Hydration (Commit: d08c858)

**Added to install-agent-config.sh:**

1. **PLUGIN_MCP accumulator** initialized alongside existing plugin accumulators (line 43)
2. **MCP server accumulation** in plugin loop with _source tagging for traceability
   - Extracts `mcp_servers` field from plugin.json
   - Tags each server with `"_source": "plugin:plugin-name"`
   - Merges into PLUGIN_MCP accumulator using jq object merge
3. **hydrate_plugin_mcp function** performs per-server, per-token namespaced secret lookup
   - Iterates over each server, extracts plugin name from _source tag
   - Finds {{TOKEN}} patterns in server config
   - Looks up secrets using namespaced path: `secrets.json[plugin-name][TOKEN]`
   - Uses jq walk+gsub for safe token replacement (handles special characters in secrets)
   - Prints inline warning for missing secrets: "⚠ plugin-name: missing TOKEN"
4. **Unified .mcp.json generation** replaces old template-only approach
   - Step 1: Add hydrated plugin servers to .mcpServers
   - Step 2: Add base template servers from config.json
   - Fallback: default mcp-gateway if no servers at all
   - Single write operation with full ownership
5. **Plugin Recap** includes MCP server count (total across all plugins)
6. **Per-plugin detail logging** shows MCP server count per plugin

**Pattern:** Full ownership regeneration - install script writes .mcp.json from scratch each rebuild, combining plugin + base servers in one operation.

### Task 2: mcp-setup Preservation Logic (Commit: 3a3c7d4)

**Modified mcp-setup-bin.sh:**

1. **Load existing .mcp.json** before regenerating (written by install-agent-config.sh)
2. **Extract plugin servers** by filtering for `_source` tag starting with "plugin:"
3. **Build base servers** from config.json templates (existing logic, refreshed each start)
4. **Merge results:** plugin servers + base servers
   - Plugin servers preserved from install (static across starts)
   - Base servers refreshed from templates (dynamic, can change via config.json)
   - Plugin servers take precedence if same name collision
5. **Output message** shows breakdown when plugins present: "N server(s) (M plugin, K base)"

**Pattern:** Preservation merge - mcp-setup respects plugin entries as plugin-owned, only updates base template servers.

## Success Criteria Met

- ✅ MCP-01: Plugin MCP servers from plugin.json accumulated with _source tagging and merged into .mcp.json
- ✅ MCP-02: {{PLACEHOLDER}} tokens hydrated from secrets.json using plugin-namespaced lookups (secrets.json[plugin-name][TOKEN])
- ✅ MCP-03: mcp-setup preserves plugin-tagged entries and only refreshes base template servers
- ✅ MCP-04: Missing secret tokens produce inline warning "⚠ plugin-name: missing TOKEN_NAME" without crashing
- ✅ Both scripts pass bash syntax validation
- ✅ Plugin Recap section shows MCP server count

## Deviations from Plan

None - plan executed exactly as written.

## Key Implementation Details

### Namespaced Secret Lookup Pattern

```bash
# Plugin: langfuse-tracing
# plugin.json: "env": { "SECRET_KEY": "{{LANGFUSE_SECRET_KEY}}" }
# secrets.json: { "langfuse-tracing": { "LANGFUSE_SECRET_KEY": "pk-..." } }

# Lookup extracts plugin name from _source tag:
p_name=$(jq -r '.[$s]._source // "" | sub("^plugin:"; "")' ...)
secret_value=$(jq -r --arg p "$p_name" --arg k "$token_name" \
    '.[$p][$k] // ""' "$secrets_file")
```

### Source Tagging for Traceability

```bash
# During accumulation:
TAGGED_MCP=$(echo "$MANIFEST_MCP" | jq --arg plugin "$plugin_name" '
    to_entries | map(.value._source = "plugin:\($plugin)") | from_entries
')

# Result in .mcp.json:
{
  "mcpServers": {
    "my-server": {
      "_source": "plugin:my-plugin",
      "command": "npx",
      "args": ["-y", "my-mcp-server"]
    }
  }
}
```

### Preservation in mcp-setup

```bash
# Extract plugin servers (filter by _source tag):
PLUGIN_SERVERS=$(echo "$EXISTING_MCP" | jq '.mcpServers |
    with_entries(select(.value._source? // "" | startswith("plugin:")))')

# Merge with base servers:
FINAL_MCP=$(jq -n --argjson plugins "$PLUGIN_SERVERS" --argjson base "$MCP_JSON" \
    '{mcpServers: ($plugins + $base.mcpServers)}')
```

## Testing Recommendations

1. **Plugin with MCP server and secrets:**
   - Create plugin with `mcp_servers` field in plugin.json
   - Add secrets to secrets.json under plugin name namespace
   - Rebuild container, verify server appears in `~/.claude/.mcp.json` with hydrated secrets
   - Restart container (postStartCommand runs mcp-setup), verify server persists

2. **Missing secrets:**
   - Plugin declares {{TOKEN}} but secrets.json missing or incomplete
   - Verify inline warning printed during install
   - Server registered with raw placeholder, fails at runtime (expected)

3. **Disabled plugin:**
   - Add plugin with MCP server, rebuild (server appears)
   - Disable plugin in config.json, rebuild
   - Verify server removed from .mcp.json

4. **Multiple plugins with MCP servers:**
   - Create 2+ plugins each with MCP servers
   - Verify all appear in .mcp.json with correct _source tags
   - Verify Plugin Recap shows correct total count

5. **Base + plugin server interaction:**
   - Enable base template server (e.g., mcp-gateway)
   - Add plugin with different MCP server
   - Verify .mcp.json contains both
   - Restart container, verify both persist

## Integration Points

**Upstream dependencies:**
- Phase 04-03: Plugin accumulation patterns (PLUGIN_HOOKS, PLUGIN_ENV)
- Phase 04-02: Plugin enabled/disabled logic in config.json
- secrets.json structure with nested plugin namespaces

**Downstream impacts:**
- Plugins can now declare MCP servers in plugin.json
- secrets.json needs plugin-namespaced structure for MCP tokens
- .mcp.json becomes a generated artifact (never manually edit)
- mcp-setup coordination pattern established for future plugin-generated configs

## Next Steps

**Immediate (same milestone):**
- None - Phase 5 complete (1 plan total)

**Future enhancements (out of scope):**
- Plugin MCP server validation before merging (check for required fields)
- Collision detection and warning when multiple plugins use same server name
- Support for dynamic MCP server URLs (not just secrets, but computed values)

## Self-Check: PASSED

**Files created:**
- ✅ .planning/phases/05-mcp-integration/05-01-SUMMARY.md (this file)

**Files modified:**
- ✅ .devcontainer/install-agent-config.sh (exists, syntax valid)
- ✅ .devcontainer/mcp-setup-bin.sh (exists, syntax valid)

**Commits:**
- ✅ d08c858: feat(05-01): add plugin MCP accumulation and hydration
- ✅ 3a3c7d4: feat(05-01): preserve plugin MCP servers in mcp-setup

**Verification commands:**
```bash
# All checks passed during execution
bash -n .devcontainer/install-agent-config.sh  # ✅ syntax valid
bash -n .devcontainer/mcp-setup-bin.sh         # ✅ syntax valid
grep -c 'PLUGIN_MCP' .devcontainer/install-agent-config.sh  # ✅ 12 references
grep 'hydrate_plugin_mcp' .devcontainer/install-agent-config.sh  # ✅ function exists + called
grep '_source' .devcontainer/install-agent-config.sh .devcontainer/mcp-setup-bin.sh  # ✅ both files
grep '⚠.*missing' .devcontainer/install-agent-config.sh  # ✅ inline warning present
```

---

**Duration:** 2m 31s
**Completed:** 2026-02-16T01:57:08Z
**Commits:** 2 (d08c858, 3a3c7d4)
**Files Modified:** 2

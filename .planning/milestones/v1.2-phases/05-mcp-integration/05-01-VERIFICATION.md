---
phase: 05-mcp-integration
plan: "01"
verified: 2026-02-15T18:05:00Z
status: passed
score: 6/6 truths verified
re_verification: false
---

# Phase 5 Plan 1: Plugin MCP Integration Verification Report

**Phase Goal:** Plugin MCP servers persist across container rebuilds and token placeholders are hydrated
**Verified:** 2026-02-15T18:05:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Plugin MCP servers declared in plugin.json appear in ~/.claude/.mcp.json after install | ✓ VERIFIED | PLUGIN_MCP accumulator initialized (line 43), accumulation logic in plugin loop (lines 435-446), unified .mcp.json write (lines 625-631) |
| 2 | {{TOKEN}} placeholders in plugin MCP configs are hydrated from secrets.json using plugin-namespaced lookups | ✓ VERIFIED | hydrate_plugin_mcp function implements namespaced lookup (lines 573-619), pattern `.[$p][$k]` for secrets.json[plugin-name][TOKEN] (line 602) |
| 3 | Plugin MCP servers persist when mcp-setup runs in postStartCommand | ✓ VERIFIED | mcp-setup loads existing .mcp.json (line 14), extracts plugin servers by _source tag (lines 17-18), merges with refreshed base servers (lines 43-46) |
| 4 | Missing secret tokens produce inline warnings without crashing install script | ✓ VERIFIED | Inline warning "⚠ $p_name: missing $token_name" (line 607), no exit/crash, server registered with raw placeholder |
| 5 | Disabled plugins have no MCP servers in .mcp.json | ✓ VERIFIED | Plugin loop checks enabled status (lines 312-316), skips disabled plugins before accumulation (lines 319-323), accumulation only happens for enabled plugins |
| 6 | Each plugin MCP server entry has _source metadata tag for traceability | ✓ VERIFIED | Source tagging in accumulation: `.value._source = "plugin:\($plugin)"` (line 440), used by mcp-setup for preservation (line 18) |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.devcontainer/install-agent-config.sh` | PLUGIN_MCP accumulator, hydrate_plugin_mcp function, unified .mcp.json generation with plugin + base servers | ✓ VERIFIED | PLUGIN_MCP initialized (line 43), 12 references total, hydrate_plugin_mcp function defined (lines 573-619) and called (line 626), unified generation (lines 621-659), _source tagging present (line 440), inline warnings (line 607) |
| `.devcontainer/mcp-setup-bin.sh` | Plugin server preservation during postStartCommand regeneration | ✓ VERIFIED | Loads existing .mcp.json (line 14), extracts plugin servers by _source tag with `startswith("plugin:")` filter (line 18), merges with base servers (lines 43-46), plugin precedence maintained |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| install-agent-config.sh plugin loop | PLUGIN_MCP accumulator | jq merge with _source tagging | ✓ WIRED | Lines 436-446: extracts mcp_servers from plugin.json, tags with `_source: "plugin:$plugin_name"`, merges into PLUGIN_MCP using jq object merge `$acc * $new` |
| install-agent-config.sh hydrate_plugin_mcp | secrets.json | namespaced jq lookup | ✓ WIRED | Line 602: `'.[$p][$k] // ""'` performs namespaced lookup secrets.json[plugin-name][TOKEN], function called at line 626 |
| install-agent-config.sh .mcp.json generation | PLUGIN_MCP + base template servers | unified write combining plugin and base servers | ✓ WIRED | Lines 625-631: hydrated plugin servers added first, lines 633-649: base template servers added second, single write at line 658 |
| mcp-setup-bin.sh | existing .mcp.json plugin entries | preserve entries with _source tag starting with plugin: | ✓ WIRED | Line 14: loads existing .mcp.json, line 18: `startswith("plugin:")` filter extracts plugin servers, line 45: merges preserved plugins + refreshed base |

### Requirements Coverage

Requirements from ROADMAP.md success criteria:

| Requirement | Status | Supporting Truths |
|-------------|--------|-------------------|
| Plugin MCP servers declared in plugin.json appear in ~/.claude/.mcp.json after container rebuild | ✓ SATISFIED | Truth 1 verified |
| Placeholder tokens like {{LANGFUSE_SECRET_KEY}} in plugin MCP configs are hydrated from secrets.json | ✓ SATISFIED | Truth 2 verified |
| Plugin MCP servers persist when mcp-setup runs in postStartCommand (no double-write overwrite) | ✓ SATISFIED | Truth 3 verified |
| Missing secret tokens produce warnings without crashing install script | ✓ SATISFIED | Truth 4 verified |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.devcontainer/install-agent-config.sh` | 675 | Comment mentions "{{PLACEHOLDER}}" | ℹ️ Info | Unrelated to this phase — comment about placeholder detection in generated files (GEN-06), not a stub |

**No blockers or warnings.** The {{PLACEHOLDER}} reference is a comment about general placeholder detection, not related to MCP token hydration.

### Syntax Validation

```bash
# Both scripts pass syntax validation
bash -n .devcontainer/install-agent-config.sh  # ✅ passed
sh -n .devcontainer/mcp-setup-bin.sh           # ✅ passed
```

### Pattern Verification

**PLUGIN_MCP references:** 12 occurrences
- Line 43: initialization
- Lines 443-444: accumulation
- Lines 499-503: recap count
- Lines 625-630: hydration and .mcp.json generation

**hydrate_plugin_mcp function:**
- Definition: lines 573-619
- Call: line 626
- Implements per-server, per-token namespaced secret lookup
- Uses jq walk+gsub for safe token replacement

**Source tagging:**
- install-agent-config.sh line 440: tags servers with `_source: "plugin:$plugin_name"`
- mcp-setup-bin.sh line 18: filters by `startswith("plugin:")`

**Missing secret warnings:**
- Line 607: prints "⚠ $p_name: missing $token_name" when secret not found
- No exit/crash — continues with empty string, registers server with raw placeholder

### Commits Verified

Both commits from SUMMARY.md exist and match expected changes:

```bash
✅ d08c858 — feat(05-01): add plugin MCP accumulation and hydration
   Modified: .devcontainer/install-agent-config.sh (+96, -18 lines)

✅ 3a3c7d4 — feat(05-01): preserve plugin MCP servers in mcp-setup
   Modified: .devcontainer/mcp-setup-bin.sh (+27, -7 lines)
```

### Implementation Quality

**Strengths:**
1. Proper separation of concerns: install-agent-config.sh owns full .mcp.json generation, mcp-setup preserves plugin entries
2. Source tagging enables traceability and safe preservation across regenerations
3. Namespaced secret lookup prevents plugin conflicts (secrets.json[plugin-name][TOKEN])
4. Inline warnings for missing secrets without crashing — graceful degradation
5. Disabled plugins excluded naturally by existing plugin loop logic (skip before accumulation)
6. Plugin Recap includes MCP server count for visibility
7. Per-plugin detail logging shows MCP server count

**Implementation patterns:**
- Full ownership regeneration (install script writes .mcp.json from scratch each rebuild)
- Preservation merge (mcp-setup respects plugin entries, only updates base template servers)
- Plugin precedence in merge (plugin servers + base servers, plugin wins on collision)

**Edge cases handled:**
- Missing secrets.json: warnings printed, servers registered with raw placeholders
- No plugin MCP servers: only base template servers in .mcp.json
- No servers at all: fallback to default mcp-gateway
- Disabled plugins: skipped before accumulation, MCP servers not included

### Human Verification Required

None. All aspects of this phase are programmatically verifiable:
- File modifications verified by commit inspection
- Logic patterns verified by grep/code inspection
- Wiring verified by tracing function calls and data flow
- No UI, visual, or runtime behavior requiring human testing

---

## Overall Assessment

**Status: PASSED**

All 6 observable truths verified. All artifacts exist, are substantive (implement required logic), and are properly wired. All 4 key links verified. All ROADMAP.md success criteria satisfied. Both scripts pass syntax validation. No blocker or warning anti-patterns found.

**Phase 5 Plan 1 goal achieved:** Plugin MCP servers persist across container rebuilds and token placeholders are hydrated from secrets.json using plugin-namespaced lookups. Plugins can now declare MCP servers in plugin.json that auto-register in ~/.claude/.mcp.json with secrets hydrated, and these servers persist when mcp-setup regenerates base template servers in postStartCommand.

---

_Verified: 2026-02-15T18:05:00Z_
_Verifier: Claude (gsd-verifier)_

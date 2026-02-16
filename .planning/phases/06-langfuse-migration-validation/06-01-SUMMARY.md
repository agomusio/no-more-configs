---
phase: 06-langfuse-migration-validation
plan: 01
subsystem: agent-config
tags:
  - plugin-system
  - langfuse
  - migration
  - env-hydration
dependency_graph:
  requires:
    - phase-04-plugin-system
    - phase-05-mcp-integration
  provides:
    - langfuse-tracing-plugin
    - plugin-env-hydration
  affects:
    - settings.json.template
    - install-agent-config.sh
tech_stack:
  added:
    - plugins/langfuse-tracing
  patterns:
    - plugin-env-token-hydration
    - namespaced-secrets-lookup
key_files:
  created:
    - agent-config/plugins/langfuse-tracing/plugin.json
    - agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py
  modified:
    - agent-config/settings.json.template
    - .devcontainer/install-agent-config.sh
  deleted:
    - agent-config/hooks/langfuse_hook.py
decisions:
  - "Minimal plugin manifest: only declare used fields (hooks, env), no empty arrays"
  - "Plugin env vars use {{TOKEN}} placeholders hydrated from secrets.json[plugin-name][TOKEN]"
  - "Settings template simplified to permissions-only (all hooks/env via plugins)"
  - "Hardcoded Langfuse extraction removed from install script"
  - "Per-plugin env hydration during accumulation (before conflict detection)"
metrics:
  duration_seconds: 144
  task_count: 2
  file_count: 4
  completed_date: "2026-02-16"
---

# Phase 6 Plan 1: Langfuse Migration to Plugin System Summary

**One-liner:** Migrated Langfuse tracing from hardcoded settings template to self-registering plugin with {{TOKEN}} placeholder hydration using namespaced secrets lookup.

## What Was Built

### Langfuse-Tracing Plugin
- Created `/agent-config/plugins/langfuse-tracing/` plugin directory
- Moved `langfuse_hook.py` from hardcoded hooks to plugin hooks (preserves git history)
- Created minimal `plugin.json` manifest declaring:
  - Stop hook registration
  - 4 env vars (TRACE_TO_LANGFUSE, LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY)
  - All using {{TOKEN}} placeholders for secret values

### Settings Template Cleanup
- Removed all Langfuse content from `settings.json.template`
- Template now contains only permissions section
- Simplified from 27 lines to 9 lines (clean break)

### Install Script Enhancements
- **Removed hardcoded Langfuse extraction:**
  - Deleted LANGFUSE_HOST from config.json loading
  - Deleted LANGFUSE_PUBLIC_KEY/SECRET_KEY from secrets.json loading
  - Deleted empty-key warnings and fallback assignments
  - Simplified settings template hydration (no sed token substitution)

- **Added plugin env var hydration:**
  - Hydrates {{TOKEN}} placeholders during plugin env accumulation
  - Uses namespaced lookup: `secrets.json[plugin-name][TOKEN]`
  - Runs per-plugin before conflict detection
  - Preserves config.json env override precedence
  - Non-hydrated tokens caught by existing unresolved placeholder detection

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create langfuse-tracing plugin directory and manifest | `49eca05` | plugin.json, hooks/langfuse_hook.py, settings.json.template |
| 2 | Clean up install script and add plugin env var hydration | `46b8de3` | install-agent-config.sh |

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Minimal manifest pattern**: Plugin.json only declares fields it uses (hooks, env). No empty arrays, no unused fields. Follows NMC plugin pattern.

2. **Token hydration location**: Added hydration during plugin env accumulation (after line 384) rather than as separate function. This keeps plugin_name context available for namespaced lookup.

3. **Settings template simplification**: Completely removed hooks and env blocks from template. Template is now permissions-only, making the plugin system the single source of truth for extensibility.

4. **Backward compatibility**: Config.json env overrides still work via existing override mechanism (lines 404-411). Users can override plugin env vars in config.json plugins section.

## Verification Results

All verification checks passed:

- ✓ Valid bash syntax (install-agent-config.sh)
- ✓ Valid JSON (plugin.json)
- ✓ Old hook file deleted (agent-config/hooks/langfuse_hook.py)
- ✓ No Langfuse references in settings template (count: 0)
- ✓ Plugin env hydration code exists (env_tokens extraction)
- ✓ Namespaced secrets lookup implemented
- ✓ Settings template hydration simplified (no sed token substitution)

## Success Criteria Met

- [x] Langfuse-tracing plugin directory exists with valid plugin.json and hooks/langfuse_hook.py
- [x] settings.json.template contains no Langfuse references
- [x] Old agent-config/hooks/langfuse_hook.py is deleted (git mv preserves history)
- [x] Install script has no hardcoded Langfuse secret extraction
- [x] Plugin env var {{TOKEN}} placeholders are hydrated from namespaced secrets.json
- [x] All LANG-01 through LANG-05 requirements satisfied (per 06-RESEARCH.md)

## Reference Implementation

The langfuse-tracing plugin serves as the reference implementation for:

1. **Plugin env var hydration**: Other plugins can use {{TOKEN}} placeholders in env values, hydrated from `secrets.json[plugin-name][TOKEN]`

2. **Hook registration**: Shows proper Stop hook declaration with runtime path (`/home/node/.claude/hooks/langfuse_hook.py`)

3. **Minimal manifest**: Demonstrates declaring only required fields (no empty arrays for unused fields)

4. **Secret management**: Shows namespaced secret lookup pattern matching MCP hydration from Phase 5

## Impact

**Before:**
- Langfuse hardcoded in settings.json.template
- Install script had special-case Langfuse extraction
- No generic plugin env var hydration mechanism

**After:**
- Langfuse is a self-registering plugin (can be disabled via config.json)
- Settings template is permissions-only (9 lines)
- Generic plugin env hydration works for any plugin
- Reference implementation for future plugins

## Self-Check: PASSED

**Created files exist:**
```
✓ agent-config/plugins/langfuse-tracing/plugin.json
✓ agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py
```

**Modified files updated:**
```
✓ agent-config/settings.json.template (9 lines, permissions only)
✓ .devcontainer/install-agent-config.sh (17 insertions, 23 deletions)
```

**Deleted files removed:**
```
✓ agent-config/hooks/langfuse_hook.py (git mv preserves history)
```

**Commits exist:**
```
✓ 49eca05 - feat(06-01): create langfuse-tracing plugin
✓ 46b8de3 - feat(06-01): add plugin env var hydration, remove hardcoded Langfuse
```

---

**Execution time:** 144 seconds (2.4 minutes)
**Completed:** 2026-02-16T03:22:27Z

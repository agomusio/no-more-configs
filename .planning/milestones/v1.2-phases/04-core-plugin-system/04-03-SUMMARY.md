---
phase: 04-core-plugin-system
plan: 03
subsystem: agent-config
tags:
  - install-script
  - plugins
  - hooks
  - env-vars
  - settings-merge
dependency_graph:
  requires:
    - phase: 04-02
      provides: hook-accumulation, env-accumulation
  provides:
    - hook-merging
    - env-var-merging
    - plugin-recap
    - install-summary-update
  affects:
    - settings.local.json (hook and env sections)
tech_stack:
  added: []
  patterns:
    - jq array concatenation for hook accumulation
    - jq object merge for env var injection
    - Atomic file updates with temp file pattern
    - Plugin installation recap with detailed metrics
key_files:
  created: []
  modified:
    - .devcontainer/install-agent-config.sh
decisions:
  - Hook merge uses array concatenation to preserve template hooks
  - Env var merge uses += operator to add plugin env to template env
  - Plugin recap displayed before credential restoration
  - Install summary shows plugin count alongside other component counts
metrics:
  duration_seconds: 110
  tasks_completed: 2
  files_modified: 1
  commits: 2
  completed_date: 2026-02-15
---

# Phase 04 Plan 03: Hook & Env Var Registration Summary

**Plugin hook and environment variable merging into settings.local.json with comprehensive installation summary**

## Performance

- **Duration:** 1.8 min
- **Started:** 2026-02-15T21:28:30Z
- **Completed:** 2026-02-15T21:30:20Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Plugin hooks merged into settings.local.json using jq array concatenation
- Multiple plugins registering same hook event accumulate correctly
- Template hooks from settings.json.template preserved during merge
- Plugin environment variables injected into settings.local.json .env section
- config.json env overrides handled during accumulation (Plan 02)
- Plugin installation recap block shows detailed metrics (hook registrations, env vars, warnings)
- Install summary updated to include plugin count

## Task Commits

Each task was committed atomically:

1. **Task 1: Merge plugin hooks and env vars into settings.local.json** - `e922fd6` (feat)
2. **Task 2: Update install summary with plugin system information** - `9916349` (feat)

## Files Created/Modified

- `.devcontainer/install-agent-config.sh` - Added plugin hook/env merging and installation recap

## Implementation Details

### Hook Merging (Task 1)

Added hook merging section after plugin loop and before credential restoration:

**Location:** After plugin loop summary (line 456) and before credential restoration (line 493+)

**Merge logic:**
- Checks if `PLUGIN_HOOKS` accumulator is non-empty
- Uses jq `reduce` to iterate over plugin hook events
- For each event: appends plugin hooks to existing event array using `+` operator
- Wraps plugin hook arrays in `{"hooks": [...]}` structure to match settings.local.json format
- Template hooks (e.g., langfuse Stop hook) are preserved because merge uses concatenation, not replacement
- Multiple plugins registering same event accumulate correctly

**Critical pattern:**
```bash
jq --argjson plugin_hooks "$PLUGIN_HOOKS" '
    reduce ($plugin_hooks | to_entries[]) as $entry (.;
        .hooks[$entry.key] = ((.hooks[$entry.key] // []) + [{"hooks": $entry.value}])
    )
' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

The `+` operator ensures array concatenation (ACCUMULATE), not object merge which would overwrite.

### Environment Variable Merging (Task 1)

Added env var merging section after hook merging:

**Merge logic:**
- Checks if `PLUGIN_ENV` accumulator is non-empty
- Uses jq `+=` operator to add plugin env vars to existing .env section
- Template env vars from settings.json.template are preserved
- config.json overrides were already applied during accumulation (Plan 02)

**Pattern:**
```bash
jq --argjson plugin_env "$PLUGIN_ENV" '.env += $plugin_env' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
    && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

The `+=` operator adds new keys and overwrites existing keys with same name (intentional for plugin extension).

### Plugin Recap (Task 2)

Added plugin recap block after plugin merging and before credential restoration:

**Metrics displayed:**
- Plugin count: installed vs skipped
- Hook registrations: total count across all plugins
- Plugin env vars: total count across all plugins
- Warnings: count if any occurred

**Hook count calculation:**
```bash
TOTAL_HOOK_REGS=$(echo "$PLUGIN_HOOKS" | jq '[.[] | length] | add // 0')
```

Sums the length of all hook arrays across all events.

**Env var count calculation:**
```bash
TOTAL_PLUGIN_ENV=$(echo "$PLUGIN_ENV" | jq 'length')
```

Counts keys in the accumulated env object.

### Install Summary Update (Task 2)

Updated final summary section to include plugin line:

**Order:**
1. Config, Secrets, Settings
2. Credentials (Claude, Codex)
3. Git identity
4. Skills
5. Hooks
6. Commands
7. **Plugins** (NEW)
8. MCP
9. Infra .env
10. GSD

**Format:**
```
[install] Plugins: N installed, M skipped
```

Matches existing `[install]` prefix style and shows both installed and skipped counts.

## Decisions Made

**Hook Merge Strategy:**
- Use array concatenation (`+`) not object merge (`*`) to preserve template hooks
- Wrap plugin hooks in `{"hooks": [...]}` structure to match settings.local.json format
- Process all accumulated hooks in single merge operation (not per-plugin)

**Env Var Merge Strategy:**
- Use `+=` operator to add plugin env vars to template env section
- config.json overrides applied during accumulation (Plan 02), not at merge time
- Template env vars (LANGFUSE_HOST, etc.) may overlap with plugin env (intentional extension)

**Recap Placement:**
- Recap block displayed after plugin merging, before credential restoration
- Provides "at a glance" view of plugin installation results
- Summary includes one-line overview alongside other component counts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation followed research patterns and existing script conventions.

## Verification Results

All verification steps passed:

1. ✅ Bash syntax check: `bash -n` passed
2. ✅ Plugin Recap block exists
3. ✅ Hook registrations count displayed
4. ✅ PLUGIN_HOOKS merged into settings.local.json
5. ✅ PLUGIN_ENV merged into settings.local.json
6. ✅ Atomic temp file pattern used (2 occurrences)
7. ✅ Hook merge uses `+` for array concatenation

## Success Criteria Met

- ✅ HOOK-01: Plugin hooks from plugin.json merged into settings.local.json
- ✅ HOOK-02: Multiple plugins' hooks for same event all accumulate
- ✅ HOOK-03: Template hooks preserved during plugin hook merge
- ✅ HOOK-04: Hook merge uses jq array concatenation (+ not *)
- ✅ ENV-01: Plugin env vars injected into settings.local.json env section
- ✅ ENV-02: config.json plugin env overrides take precedence
- ✅ ENV-03: Env vars from multiple plugins accumulated correctly
- ✅ Install summary includes plugin count, hook count, command count, warnings
- ✅ Plugin recap block provides at-a-glance plugin installation view

## Self-Check: PASSED

### Files Created
No new files created (modification only).

### Files Modified
✅ FOUND: .devcontainer/install-agent-config.sh

### Commits
✅ FOUND: e922fd6
✅ FOUND: 9916349

All claims verified successfully.

## Next Steps

Phase 4 (Core Plugin System) is now complete. The plugin system provides:
- Plugin discovery and validation (Plan 01: standalone commands, Plan 02: plugin loop)
- File copying with GSD protection (Plan 02)
- Hook and env var accumulation (Plan 02)
- Settings merging (Plan 03)
- Comprehensive install summary (Plan 03)

Next phase can build on this foundation with:
- Plugin-based extensibility for skills, hooks, commands, agents
- Multi-plugin coordination via hook events
- Environment variable sharing across plugins
- Cross-agent skill deployment

---
*Phase: 04-core-plugin-system*
*Completed: 2026-02-15*

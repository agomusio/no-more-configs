---
phase: 04-core-plugin-system
plan: 02
subsystem: agent-config
tags:
  - install-script
  - plugins
  - cross-agent
  - gsd-protection
dependency_graph:
  requires:
    - phase: 04-01
      provides: standalone-commands-copy, cross-agent-skills
  provides:
    - plugin-discovery
    - plugin-validation
    - plugin-file-copying
    - gsd-protection
    - hook-accumulation
    - env-accumulation
  affects:
    - 04-03
tech_stack:
  added: []
  patterns:
    - Plugin discovery with alphabetical ordering
    - Plugin validation (manifest, name matching, enabled state)
    - GSD file protection (commands/gsd/ directory, gsd-* agent prefix)
    - Hook registration accumulation via jq array concatenation
    - Environment variable conflict detection and config.json override
key_files:
  created: []
  modified:
    - .devcontainer/install-agent-config.sh
decisions:
  - Plugins not in config.json default to enabled (PLUG-04)
  - Plugin name must match directory name (validation requirement)
  - First alphabetically wins for env var conflicts
  - config.json env overrides always take precedence
  - GSD protection applies to commands/gsd/ directory and gsd-* agent files
  - Per-plugin detail logging shows installed components
metrics:
  duration_seconds: 110
  tasks_completed: 2
  files_modified: 1
  commits: 2
  completed_date: 2026-02-15
---

# Phase 04 Plan 02: Plugin Discovery & Installation Summary

**Plugin discovery, validation, and file copying with GSD protection and cross-agent skill installation**

## Performance

- **Duration:** 1.8 min
- **Started:** 2026-02-15T21:24:06Z
- **Completed:** 2026-02-15T21:25:57Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Plugin discovery loop iterates agent-config/plugins/*/ in alphabetical order
- Plugin validation checks existence, JSON validity, and name matching
- Plugin files (skills, hooks, commands, agents) copied to runtime directories
- GSD protection prevents plugins from overwriting GSD framework files
- Hook registrations accumulated using jq array concatenation for Plan 03 merging
- Environment variables accumulated with conflict detection and config.json override support
- Per-plugin detail logging shows what was installed (skills, hooks, commands, agents, env vars)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement plugin discovery loop with validation** - `fab02ac` (feat)
2. **Task 2: Implement plugin file copying with GSD protection** - `8f18212` (feat)

## Files Created/Modified

- `.devcontainer/install-agent-config.sh` - Added plugin discovery, validation, and file copying with GSD protection

## Implementation Details

### Plugin Discovery (Task 1)

Added plugin discovery section after settings.json seed and before credential restoration. The discovery loop:

1. Checks for `agent-config/plugins/` directory existence
2. Iterates plugin directories in alphabetical order (deterministic)
3. Validates each plugin:
   - Checks enabled/disabled state from config.json (default: enabled)
   - Validates plugin.json exists
   - Validates plugin.json is valid JSON using existing validate_json function
   - Validates plugin name matches directory name
4. Skips disabled or invalid plugins with appropriate messages

**Accumulators initialized:**
- `PLUGIN_INSTALLED=0` - count of successfully installed plugins
- `PLUGIN_SKIPPED=0` - count of skipped plugins
- `PLUGIN_HOOKS='{}'` - accumulated hook registrations
- `PLUGIN_ENV='{}'` - accumulated environment variables
- `PLUGIN_WARNINGS=0` - count of warnings during installation

### Plugin File Copying (Task 2)

For each valid, enabled plugin, files are copied with these rules:

**Skills (COPY-01, cross-agent):**
- Copied to both `~/.claude/skills/` and `~/.codex/skills/`
- Cross-agent support matches Plan 01 pattern

**Hooks (COPY-02):**
- Copied to `~/.claude/hooks/`
- Individual file copying with guards

**Commands (COPY-03, COPY-05):**
- Copied to `~/.claude/commands/`
- GSD protection: checks for `commands/gsd/` directory conflict
- Error message and warning counter increment if conflict detected

**Agents (COPY-04, COPY-05):**
- Copied to `~/.claude/agents/`
- GSD protection: skips any file with `gsd-` prefix
- Error message and warning counter increment per protected file

**Hook Accumulation:**
- Reads `.hooks` from plugin.json manifest
- Merges into `PLUGIN_HOOKS` accumulator using jq array concatenation (`+` operator)
- Handles missing/null hooks gracefully

**Environment Variable Accumulation:**
- Reads `.env` from plugin.json manifest
- Checks for conflicts with already-accumulated env vars
- First alphabetically wins (warns and skips duplicate keys)
- Applies config.json overrides (always take precedence)
- Conflict detection shows conflicting keys in warning message

**Per-Plugin Detail Logging:**
- Counts components per plugin (skills, hooks, commands, agents, env vars)
- Logs installed components in format: `[install] Plugin 'name': installed (N skill(s), M hook(s), ...)`
- Falls back to `installed (manifest only)` if no files copied
- Increments `PLUGIN_INSTALLED` counter

**Post-Loop Summary:**
- Logs total installed vs skipped count: `[install] Plugins: N installed, M skipped`

## Decisions Made

**Plugin Enabled Default:**
- Plugins not mentioned in config.json are enabled by default (PLUG-04)
- Users must explicitly set `enabled: false` to disable a plugin

**Plugin Name Validation:**
- Plugin name in plugin.json must match directory name
- Mismatch causes skip with warning

**Environment Variable Conflicts:**
- First alphabetically wins for env var conflicts between plugins
- config.json overrides always take precedence
- Warnings logged for conflicts

**GSD Protection Scope:**
- Protects `commands/gsd/` directory (prevents entire directory conflict)
- Protects `agents/gsd-*.md` files (prefix-based protection)
- Standalone commands and plugin commands can overwrite each other freely

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation followed research patterns and existing script conventions.

## Verification Results

All verification steps passed:

1. ✅ Bash syntax check: `bash -n` passed
2. ✅ Accumulator initialization: 8 references to PLUGIN_INSTALLED/SKIPPED/HOOKS/ENV
3. ✅ Plugin directory iteration: Found `agent-config/plugins/*/` loop
4. ✅ Name validation: Found manifest_name vs plugin_name comparison
5. ✅ GSD agent protection: Found `gsd-` prefix regex check
6. ✅ GSD commands protection: Found `commands/gsd` directory check
7. ✅ Hook accumulation: Found PLUGIN_HOOKS with jq merging
8. ✅ Env accumulation: Found PLUGIN_ENV with conflict detection
9. ✅ Per-plugin logging: Found detail_parts array construction

## Success Criteria Met

- ✅ PLUG-01: Plugin directories under agent-config/plugins/ are discovered
- ✅ PLUG-02: plugin.json validated for existence and valid JSON
- ✅ PLUG-03: Missing plugin.json causes skip with info message
- ✅ PLUG-04: Plugins not in config.json are enabled by default
- ✅ PLUG-05: Disabled plugins are fully skipped
- ✅ PLUG-06: Plugins processed in deterministic alphabetical order
- ✅ COPY-01: Plugin skills copied to both Claude and Codex directories
- ✅ COPY-02: Plugin hooks copied to ~/.claude/hooks/
- ✅ COPY-03: Plugin commands copied to ~/.claude/commands/
- ✅ COPY-04: Plugin agents copied to ~/.claude/agents/
- ✅ COPY-05: GSD agents (gsd-*.md) and commands (gsd/) are never overwritten
- ✅ COPY-06: Empty directories and missing subdirectories handled gracefully
- ✅ Hook and env accumulation ready for Plan 03 merging
- ✅ Per-plugin detail logging implemented

## Self-Check: PASSED

### Files Created
No new files created (modification only).

### Files Modified
✅ FOUND: .devcontainer/install-agent-config.sh

### Commits
✅ FOUND: fab02ac
✅ FOUND: 8f18212

All claims verified successfully.

## Next Steps

This plan establishes the plugin installation loop and file copying. Plan 03 (Hook & Env Var Registration) will:
- Merge accumulated `PLUGIN_HOOKS` into settings.local.json
- Merge accumulated `PLUGIN_ENV` into settings.local.json
- Handle hook event ordering (alphabetical by plugin name)
- Apply final environment variable resolution
- Build on the accumulator pattern established here

---
*Phase: 04-core-plugin-system*
*Completed: 2026-02-15*

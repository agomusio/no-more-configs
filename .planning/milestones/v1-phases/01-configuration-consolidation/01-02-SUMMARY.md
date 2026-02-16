---
phase: 01-configuration-consolidation
plan: 02
subsystem: infra
tags: [bash, config-hydration, templates, automation, gsd]

# Dependency graph
requires:
  - phase: 01-01
    provides: Master configuration files (config.json, secrets.json, agent-config/ templates)
provides:
  - Automated config hydration script (install-agent-config.sh)
  - Devcontainer lifecycle integration (postCreateCommand)
  - Idempotent template processing with graceful degradation
affects: [Phase 2, Phase 3]

# Tech tracking
tech-stack:
  added: []
  patterns: [bash validation functions, jq for JSON processing, sed for placeholder substitution, natural idempotency via mkdir -p and regeneration]

key-files:
  created:
    - .devcontainer/install-agent-config.sh
  modified:
    - .devcontainer/devcontainer.json

key-decisions:
  - "Natural idempotency (no state markers) — script uses mkdir -p, regenerates files, safe to run multiple times"
  - "Graceful degradation — script provides defaults when config.json missing, empty placeholders when secrets.json missing"
  - "JSON validation before processing — prevents cryptic jq errors from malformed files"
  - "Prefix all output with [install] — enables grep filtering in build logs"

patterns-established:
  - "Validation helper pattern: validate_json() function for consistent error handling"
  - "Status tracking pattern: initialize status variables, update during execution, print in summary"
  - "MCP template merge pattern: read enabled servers from config, hydrate templates, merge into single .mcp.json"

# Metrics
duration: 1 min
completed: 2026-02-14
---

# Phase 01 Plan 02: Install Script Creation Summary

**Automated config hydration script (install-agent-config.sh) reads two master files, validates JSON, hydrates templates with placeholder substitution, installs GSD framework, and prints comprehensive summary — all with graceful degradation for missing files**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-14T19:44:52Z
- **Completed:** 2026-02-14T19:46:34Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created 177-line install-agent-config.sh with complete config automation
- Integrated script into devcontainer lifecycle via postCreateCommand chaining
- Implemented graceful degradation for all missing file scenarios (no config, no secrets, neither)
- Added JSON validation to prevent cryptic errors from malformed files
- Script generates settings.local.json, .mcp.json, restores credentials, installs GSD framework

## Task Commits

Each task was committed atomically:

1. **Task 1: Create install-agent-config.sh** - `f49921c` (feat)
   - 177-line bash script with set -euo pipefail
   - JSON validation helper function
   - Reads config.json and secrets.json with jq, provides defaults if missing
   - Generates settings.local.json from template with sed placeholder substitution
   - Restores Claude credentials from secrets.json when available
   - Generates .mcp.json from enabled MCP templates
   - Installs GSD framework idempotently
   - Prints [install]-prefixed summary listing what was configured

2. **Task 2: Wire install script into devcontainer lifecycle** - `f2d400a` (feat)
   - Updated postCreateCommand to chain install script after setup-container.sh
   - Preserved bind mount (Phase 3 scope)
   - Preserved postStartCommand (init-gsd.sh provides fallback check)
   - Validated devcontainer.json is valid JSON

## Files Created/Modified

- `.devcontainer/install-agent-config.sh` - Complete config hydration automation (177 lines)
- `.devcontainer/devcontainer.json` - Updated postCreateCommand to call install script

## Decisions Made

**Natural idempotency approach:**
- No state markers (like ~/.local/state/gsd-initialized) needed
- Script uses mkdir -p (creates if missing, no-op if exists)
- Regenerates all output files (settings.local.json, .mcp.json) on every run
- GSD installation checks if commands already exist before running npx
- Result: safe to run multiple times without duplicates or failures

**Graceful degradation strategy:**
- config.json missing → use hardcoded defaults, print warning
- secrets.json missing → use empty placeholders, print warnings per missing secret
- Both missing → "zero-config mode" works with defaults and empty placeholders
- Invalid JSON → validate_json() catches errors early, continues with defaults

**JSON validation before processing:**
- validate_json() helper prevents cryptic jq errors
- Returns 1 on invalid JSON, allowing caller to skip processing
- Prints clear error message identifying which file is malformed

**Output prefixing for grep:**
- All echo statements use `[install]` prefix
- Enables build log filtering: `docker logs | grep "\[install\]"`
- Summary block clearly shows what was configured and what is missing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. Script automates all internal config hydration.

## Next Phase Readiness

**Phase 1 complete!** Ready for Phase 2 (Directory Dissolution).

The install script is the complete automation for Phase 1. When the container is created:
1. setup-container.sh handles Docker socket permissions and git config
2. install-agent-config.sh reads config.json and secrets.json
3. Templates are hydrated with extracted values
4. GSD framework is installed
5. Comprehensive summary is printed

All degraded modes work:
- Container starts with no config.json → uses defaults
- Container starts with no secrets.json → uses empty placeholders
- Container starts with both missing → zero-config mode works
- Running script multiple times → identical results, no errors

## Self-Check: PASSED

All created files verified on disk:
- FOUND: .devcontainer/install-agent-config.sh (177 lines)

All modified files verified:
- FOUND: .devcontainer/devcontainer.json (postCreateCommand updated)

All commits verified in git history:
- FOUND: f49921c (Task 1 - install script creation)
- FOUND: f2d400a (Task 2 - devcontainer lifecycle integration)

All key patterns verified in install script:
- FOUND: set -euo pipefail (error handling)
- FOUND: jq.*config.json (config reading)
- FOUND: jq.*secrets (secrets reading)
- FOUND: LANGFUSE_HOST (placeholder substitution)
- FOUND: get-shit-done-cc (GSD installation)
- FOUND: \[install\] (output prefix)
- FOUND: mkdir -p (idempotency)
- FOUND: credentials (credential restoration)
- FOUND: settings.local.json (template output)

---
*Phase: 01-configuration-consolidation*
*Completed: 2026-02-14*

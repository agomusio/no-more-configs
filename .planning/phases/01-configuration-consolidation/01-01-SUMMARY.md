---
phase: 01-configuration-consolidation
plan: 01
subsystem: infra
tags: [config, templates, json, bash]

# Dependency graph
requires:
  - phase: none
    provides: First plan in project
provides:
  - Master configuration files (config.json, secrets.json schema)
  - Agent config template directory with hydration placeholders
  - Gitignore rules for secrets isolation
affects: [01-02, Phase 2, Phase 3]

# Tech tracking
tech-stack:
  added: []
  patterns: [nested JSON config schema, placeholder token hydration, gitignored secrets]

key-files:
  created:
    - config.json
    - config.example.json
    - secrets.example.json
    - agent-config/settings.json.template
    - agent-config/mcp-templates/mcp-gateway.json
  modified:
    - .gitignore

key-decisions:
  - "Used nested object structure for config.json with firewall, langfuse, agent, vscode, mcp_servers top-level keys"
  - "Separated credentials into secrets.json with claude.credentials, langfuse keys, api_keys structure"
  - "Placeholder tokens use {{UPPER_SNAKE_CASE}} format for template hydration"
  - "Empty git_scan_paths array means auto-detect from gitprojects/ .git directories"

patterns-established:
  - "Config schema: Nested objects grouped by concern (firewall, langfuse, agent, vscode, mcp_servers)"
  - "Secrets schema: Mirrors config nesting style with credential-specific keys"
  - "Template tokens: {{PLACEHOLDER}} format for install script substitution"

# Metrics
duration: 2 min
completed: 2026-02-14
---

# Phase 01 Plan 01: Configuration Foundation Summary

**Master configuration files established with two-file system (config.json for settings, secrets.json for credentials) and version-controlled templates using placeholder hydration pattern**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T19:40:25Z
- **Completed:** 2026-02-14T19:42:30Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Created config.json with current codebase values (firewall domains, Langfuse host, MCP servers)
- Created config.example.json and secrets.example.json as schema documentation
- Established agent-config/ directory as version-controlled source of truth for templates
- Added secrets.json to .gitignore to prevent credential leaks

## Task Commits

Each task was committed atomically:

1. **Task 1: Create config.json, config.example.json, and secrets.example.json** - `0d81761` (feat)
   - config.json with actual values from firewall-domains.conf and devcontainer.json
   - config.example.json with generic placeholders
   - secrets.example.json with empty credential schema
   - .gitignore updated to exclude secrets.json

2. **Task 2: Create agent-config/ directory with settings and MCP templates** - `ca8e2c8` (feat)
   - settings.json.template based on current settings.local.json structure
   - mcp-gateway.json template based on current mcp-setup-bin.sh output
   - Placeholder tokens: {{LANGFUSE_HOST}}, {{LANGFUSE_PUBLIC_KEY}}, {{LANGFUSE_SECRET_KEY}}, {{MCP_GATEWAY_URL}}

## Files Created/Modified

- `config.json` - Master non-secret settings with 5 top-level keys (firewall, langfuse, agent, vscode, mcp_servers)
- `config.example.json` - Schema documentation with sensible defaults
- `secrets.example.json` - Credential schema placeholder (claude, langfuse, api_keys)
- `agent-config/settings.json.template` - Claude Code settings template with Langfuse env placeholders
- `agent-config/mcp-templates/mcp-gateway.json` - MCP gateway server template with URL placeholder
- `.gitignore` - Added secrets.json exclusion rule

## Decisions Made

**Config schema structure:**
- Chose nested objects grouped by concern (firewall, langfuse, agent, vscode, mcp_servers) for clarity
- Empty arrays (like vscode.git_scan_paths) signal auto-detection behavior
- MCP servers list which templates are enabled; actual configs live in agent-config/mcp-templates/

**Secrets schema structure:**
- Mirrors config.json nesting style for consistency
- claude.credentials key matches .credentials.json file structure (per RESEARCH.md finding)
- Langfuse split: config.json owns host, secrets.json owns public_key/secret_key

**Placeholder token format:**
- Used {{UPPER_SNAKE_CASE}} format for clarity and grep-ability
- Self-documenting names (LANGFUSE_HOST, MCP_GATEWAY_URL) make mapping obvious
- No metadata keys in templates — pure JSON that becomes valid after hydration

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. This plan creates local files only.

## Next Phase Readiness

Ready for 01-02-PLAN.md (install-agent-config.sh script creation). All configuration source files exist and define the contract for the install script to read and hydrate.

## Self-Check: PASSED

All created files verified on disk:
- FOUND: config.json
- FOUND: config.example.json
- FOUND: secrets.example.json
- FOUND: agent-config/settings.json.template
- FOUND: agent-config/mcp-templates/mcp-gateway.json

All commits verified in git history:
- FOUND: 0d81761 (Task 1)
- FOUND: ca8e2c8 (Task 2)

---
*Phase: 01-configuration-consolidation*
*Completed: 2026-02-14*

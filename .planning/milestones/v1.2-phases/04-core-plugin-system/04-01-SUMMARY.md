---
phase: 04-core-plugin-system
plan: 01
subsystem: agent-config
tags:
  - install-script
  - commands
  - skills
  - cross-agent
  - codex
dependency_graph:
  requires: []
  provides:
    - standalone-commands-copy
    - cross-agent-skills
    - codex-skills-feature
  affects:
    - .devcontainer/install-agent-config.sh
tech_stack:
  added: []
  patterns:
    - Cross-agent skill installation (Claude + Codex)
    - Standalone command namespace protection
    - Counter-based install summary
key_files:
  created: []
  modified:
    - .devcontainer/install-agent-config.sh
decisions:
  - GSD namespace protection for standalone commands (skip any command named "gsd")
  - Skills copied to both Claude and Codex directories for cross-agent support
  - Codex config.toml includes [features] skills = true for skill discovery
  - Install summary shows dual destination for skills
metrics:
  duration_seconds: 67
  tasks_completed: 1
  files_modified: 1
  commits: 1
  completed_date: 2026-02-15
---

# Phase 04 Plan 01: Standalone Commands & Cross-Agent Skills Summary

**One-liner:** Added standalone command copying from agent-config/commands/ and cross-agent skill installation to both Claude and Codex with feature flag enabled.

## What Was Built

Updated `install-agent-config.sh` to support two new foundational capabilities before the plugin system:

1. **Standalone Commands Copy**: Copies `*.md` files from `agent-config/commands/` to `~/.claude/commands/` with GSD namespace protection
2. **Cross-Agent Skills**: Copies skills from `agent-config/skills/` to both `~/.claude/skills/` and `~/.codex/skills/` for dual-agent support
3. **Codex Skill Discovery**: Added `[features] skills = true` to generated Codex `config.toml`
4. **Enhanced Install Feedback**: Updated summary to show dual-destination skills and standalone command count

## Implementation Details

### Standalone Commands Section

- Iterates over `agent-config/commands/*.md` files
- Protects GSD namespace (skips any command named "gsd" with warning)
- Increments `COMMANDS_COUNT` counter for summary
- Copies to `~/.claude/commands/` (flat files, no directory conflicts with `commands/gsd/`)

### Cross-Agent Skills Installation

Modified existing skills copy section to:
- Create `~/.codex/skills/` directory with `mkdir -p`
- Copy skills to both Claude and Codex destinations
- Update log line to reflect dual destination: "Skills: N skill(s) -> Claude + Codex"

### Codex Configuration

Added `[features]` section to generated Codex `config.toml`:
```toml
[features]
skills = true
```

Inserted between global settings and project configuration for skill discovery.

### Install Summary Updates

- Added `COMMANDS_COUNT` counter initialization at line 38
- Updated Skills line: "Skills: $SKILLS_COUNT skill(s) -> Claude + Codex"
- Added Commands line: "Commands: $COMMANDS_COUNT standalone command(s)"

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add standalone commands copy and cross-agent skills to install script | 60dd92b | .devcontainer/install-agent-config.sh |

## Verification Results

All verification steps passed:

1. ✅ Bash syntax check: `bash -n` passed
2. ✅ COMMANDS_COUNT occurrences: 6 (init, increment in loop, summary output, etc.)
3. ✅ Cross-agent skills copy: Found `mkdir -p /home/node/.codex/skills` and copy commands
4. ✅ Codex feature flag: Found `skills = true` in config generation
5. ✅ Standalone commands section: Found `agent-config/commands` directory check and loop

## Deviations from Plan

None - plan executed exactly as written.

## Success Criteria Met

- ✅ CMD-01: Standalone commands copied from agent-config/commands/ to ~/.claude/commands/
- ✅ CMD-02: GSD commands directory protected (standalone .md files don't conflict with gsd/ subdirectory)
- ✅ CMD-03: Command count reported in install summary
- ✅ Cross-agent skills: Skills copied to both Claude and Codex directories
- ✅ Codex discovery: config.toml includes [features] skills = true
- ✅ Install feedback: Skills line reflects dual destination

## Self-Check: PASSED

### Files Created
No new files created (modification only).

### Files Modified
✅ FOUND: .devcontainer/install-agent-config.sh

### Commits
✅ FOUND: 60dd92b

All claims verified successfully.

## Next Steps

This plan lays the groundwork for Plan 02 (Plugin Discovery & Installation), which will:
- Discover plugins in `agent-config/plugins/*/`
- Validate `plugin.json` manifests
- Copy plugin files (skills, hooks, commands, agents) with GSD protection
- Register hooks and environment variables
- Build on the standalone commands and cross-agent skills patterns established here

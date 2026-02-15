# Project Research Summary

**Project:** Claude Code Sandbox Plugin System
**Domain:** DevContainer Configuration & CLI Plugin Architecture
**Researched:** 2026-02-15
**Confidence:** HIGH

## Executive Summary

The plugin system integrates into the existing `install-agent-config.sh` bash script by extending its linear pipeline pattern with four new stages: plugin discovery, file copying, registration accumulation, and configuration merging. The critical architectural insight is that plugins must be processed AFTER settings.local.json template hydration but BEFORE final MCP/GSD installation to enable proper merging of hooks, environment variables, and MCP server definitions.

The recommended approach leverages existing infrastructure (bash 5.2, jq 1.6, Python 3.11) without new dependencies. The core challenge is correctly merging plugin hook registrations into Claude Code's nested `hooks.Stop[0].hooks[]` structure using jq array concatenation rather than the default `*` operator which overwrites arrays. Plugin MCP server registration must happen AFTER the base `.mcp.json` is written (line 351 of install script) to avoid being overwritten.

Key risks include: (1) jq array overwrites causing hook loss, (2) `.mcp.json` double-write from mcp-setup timing, (3) GSD file clobbering by plugins, and (4) Langfuse migration breaking existing tracing. Mitigation requires careful merge logic validation, atomic write patterns for JSON files, GSD-protected file paths, and phased migration with before/after testing.

## Key Findings

### Recommended Stack

No new runtime dependencies required. The plugin system uses the existing container stack exclusively: bash 5.2 for installation orchestration and directory iteration, jq 1.6 for JSON parsing and recursive merging, Python 3.11 and Node.js 20 for hook execution runtimes (already present for Langfuse and GSD).

**Core technologies:**
- **Bash 5.2+**: Install script orchestration, plugin file operations — standard in Debian containers, proven robust for file operations with shopt safety options
- **jq 1.6+**: JSON parsing, deep merging, template hydration — de facto standard for shell JSON manipulation, built-in recursive merge and reduce patterns
- **Python 3.11+**: Hook execution runtime — already present for langfuse_hook.py, widely used for event hooks
- **Node.js 20+**: Optional hook runtime, potential schema validation — already present for GSD framework

**Key patterns:**
- Deep merge with jq `*` operator for objects, custom reduce for array concatenation
- Safe directory iteration with `shopt -s nullglob` and existence guards
- Template hydration via sed (simple tokens) or jq (complex/nested tokens)
- Non-destructive file copy with GSD protection (skip `gsd-*.md` and `commands/gsd/`)

### Expected Features

Plugin system must support auto-discovery, manifest validation, enable/disable control, hook self-registration, MCP server registration, environment variable injection, and non-destructive file copies. Config.json overrides plugin defaults to provide hierarchical precedence (base < plugin < config).

**Must have (table stakes):**
- Plugin discovery (filesystem-based) — Claude Code pattern: drop files in directory, rebuild, works
- Manifest validation (plugin.json) — prevents broken plugins from causing runtime failures
- Enable/disable control via config.json — toggle plugins without file deletion
- Hook self-registration — plugins declare hooks in manifest, install script merges into settings.local.json
- MCP server registration — plugins bundle capabilities (skills + hooks + MCP servers)
- Env var injection — plugins set runtime environment (API endpoints, feature flags)
- Non-destructive file copies — plugins never overwrite GSD or user files

**Should have (competitive):**
- Config.json overrides plugin defaults — infrastructure-as-code pattern, master config controls all plugins
- Plugin-enabled-by-default — zero-config for simple use case (opt-out not opt-in)
- Hook event accumulation — multiple plugins register same event, all fire in order
- File conflict warnings (informational) — debugging aid when plugins overwrite each other

**Defer (v2+):**
- Plugin versioning — log version from manifest but don't enforce (no use case until plugin sharing exists)
- Plugin dependencies — complexity unclear, defer until ecosystem proves need
- JSON Schema validation for plugin.json — jq empty check sufficient for MVP
- Plugin uninstall command — rebuild container achieves same goal faster

### Architecture Approach

The plugin system extends the existing 423-line install script's linear pipeline with approximately 150 lines of new code across five insertion points. Plugin processing happens in stage 11 (after template hydration at line 246, before credential restoration at line 248), with accumulator variables (`PLUGIN_HOOKS`, `PLUGIN_ENV`, `PLUGIN_MCP`) collecting registrations across all enabled plugins before three merge operations update settings.local.json and .mcp.json.

**Major components:**
1. **Standalone commands copier** (insert after line 235) — copies `agent-config/commands/*.md` to `~/.claude/commands/` with existence checks
2. **Plugin processor** (insert after line 246) — iterates plugins, validates manifests, copies files (skills/hooks/commands/agents), accumulates registrations in bash JSON variables
3. **Hook + Env mergers** (immediately after plugin processor) — merges accumulated `PLUGIN_HOOKS` and `PLUGIN_ENV` into settings.local.json using jq with array concatenation for hooks
4. **MCP merger** (insert after line 351, after base MCP generation) — hydrates `{{PLACEHOLDER}}` tokens from secrets.json, merges plugin MCP servers into .mcp.json
5. **Summary output** (modify lines 410-423) — adds plugin count and command count to installation summary

**Critical ordering constraints:**
- Plugins AFTER settings.local.json hydration (base structure must exist before merge)
- Plugin MCP merge AFTER base .mcp.json write (line 338 overwrites file)
- GSD installation AFTER plugin file copy (protects GSD namespace from plugin overwrites)

### Critical Pitfalls

**Top 5 pitfalls with prevention strategies:**

1. **jq Array Overwriting Instead of Concatenation** — The `*` merge operator overwrites arrays completely. If template has a `Stop` hook and plugin adds another, plugin's hook replaces template's instead of appending. Prevention: Use custom reduce logic with array concatenation (`(.[$event.key] // []) + $entry.value`) instead of `*` operator for hooks.

2. **.mcp.json Double-Write Race Condition** — `mcp-setup` (in postStartCommand) overwrites `.mcp.json` after install-agent-config.sh writes it, losing plugin MCP servers. Prevention: Make mcp-setup plugin-aware (preserve existing entries) OR move mcp-setup before plugin installation.

3. **GSD File Clobbering During Plugin Installation** — Plugins can overwrite GSD framework files if they provide `gsd-*.md` agents or `commands/gsd/*`. Prevention: Add pattern match guards to skip copying files matching `^gsd-` or directory name `gsd`.

4. **Empty Object/Null Value Merge Corruption** — Using `jq -r` produces string `"null"` instead of JSON null, breaking subsequent merges. Prevention: Never use `-r` flag for intermediate JSON (only for final string output), always coalesce null to `{}` with `// {}`.

5. **sed Token Replacement with Unescaped Special Characters** — Secrets containing `$`, `&`, `/` corrupt MCP configs when hydrated via sed. Prevention: Use jq for token replacement with `--arg` and `walk(gsub())` instead of sed.

## Implications for Roadmap

Based on research, suggested 4-phase structure:

### Phase 1: Core Plugin System
**Rationale:** Establish foundation with plugin discovery, validation, file copying, and basic registration. Must implement correct jq array concatenation and GSD protection from the start as these are architectural and cannot be fixed later without breaking existing plugins.

**Delivers:** Working plugin system with all table-stakes features (discovery, manifest validation, enable/disable, file copy with GSD protection, hook/env/MCP accumulation and merging).

**Addresses:** All must-have features from FEATURES.md — plugin discovery, manifest validation, enable/disable control, hook self-registration, env var injection, MCP server registration, non-destructive file copies.

**Avoids:** Pitfalls 1 (array overwrite), 3 (GSD clobbering), 4 (null merge), 5 (sed escaping), 6 (hook order) — all require prevention in initial implementation.

**Implementation estimate:** ~150 lines across 5 code blocks, ~8-12 hours development + testing.

### Phase 2: MCP Integration Fix
**Rationale:** Plugin MCP servers only work after fixing mcp-setup timing issue. This is a blocker for plugin MCP feature but doesn't block other plugin features, so can be decoupled from Phase 1.

**Delivers:** Plugin MCP servers persist across container rebuilds. `npx @anthropic/code mcp list` shows plugin-registered servers.

**Uses:** jq recursive merge pattern from STACK.md, token hydration with special character handling.

**Implements:** mcp-setup modification to preserve plugin entries OR reordering of mcp-setup before plugin processing.

**Avoids:** Pitfall 2 (.mcp.json double-write).

**Implementation estimate:** ~30 lines modification to mcp-setup script, ~2-4 hours.

### Phase 3: Langfuse Migration
**Rationale:** Migrate existing hardcoded Langfuse hook to plugin system after core plugin system validated. Requires careful structure matching and before/after testing to avoid breaking production tracing.

**Delivers:** Langfuse tracing runs as a plugin (`plugins/langfuse-tracing/`) instead of hardcoded in settings.json.template. Validates plugin hook registration works end-to-end.

**Addresses:** Dogfooding — first real plugin validates all Phase 1 patterns.

**Avoids:** Pitfall 10 (Langfuse migration breaking tracing) — dedicated phase with validation ensures no regression.

**Implementation estimate:** ~1 hour (create plugin.json, test migration, remove template hook).

### Phase 4: Enhanced Validation & UX
**Rationale:** Add nice-to-have features after core system proven. Hook script existence checks, file conflict warnings, plugin installation summary. These improve UX but aren't blockers for launch.

**Delivers:** Better debugging and transparency. Users see warnings when plugins have issues, installation summary shows what was installed.

**Addresses:** Should-have features from FEATURES.md — file conflict warnings, plugin installation summary. Also addresses Pitfall 9 (hook script validation).

**Implementation estimate:** ~50 lines validation logic, ~4-6 hours.

### Phase Ordering Rationale

- **Phase 1 first:** Foundation must be correct before building on it. Array concatenation, GSD protection, and null handling cannot be retrofitted without breaking changes.
- **Phase 2 decoupled:** MCP feature is independent. Plugins without MCP servers (pure hooks/skills) work after Phase 1. MCP fix can be developed in parallel.
- **Phase 3 after Phase 1+2:** Langfuse migration validates the system end-to-end but requires both plugin core (Phase 1) and MCP integration (Phase 2) to work fully (Langfuse plugin has no MCP servers currently, but validates hook registration).
- **Phase 4 last:** UX/validation enhancements have no dependencies and don't block core functionality.

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Well-documented bash/jq patterns, architecture research already complete
- **Phase 3:** Simple migration following established patterns
- **Phase 4:** Validation patterns are straightforward

**Phases potentially needing deeper research:**
- **Phase 2:** May need to understand mcp-setup internals and postStartCommand timing guarantees (currently ~70% confidence on fix approach)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies already present in container, patterns verified against existing codebase |
| Features | HIGH | Features derived from Claude Code official docs and community plugin systems (WP-CLI, GitHub Copilot CLI) |
| Architecture | HIGH | Based on direct examination of install-agent-config.sh (423 lines analyzed), settings.json.template structure, and devcontainer.json timing |
| Pitfalls | HIGH | Identified from jq manual, bash pitfalls wiki, and existing codebase patterns. Top 10 pitfalls tested against ARCHITECTURE.md integration points |

**Overall confidence:** HIGH

### Gaps to Address

- **mcp-setup script internals:** Research shows mcp-setup overwrites .mcp.json but didn't examine its full implementation. Need to verify if it supports plugin preservation or if reordering is better approach. *Addressable during Phase 2 planning.*

- **Hook structure validation:** The nested `hooks.Stop[0].hooks[]` structure is inferred from settings.json.template (lines 15-26). Official Claude Code documentation on exact hook registration format not found during research. *Validate with test plugin in Phase 1.*

- **Plugin load order guarantees:** Alphabetical sorting recommended but filesystem behavior across WSL2/Docker/network mounts needs verification. *Test on target deployment environment during Phase 1.*

- **Token placeholder recursive search in secrets.json:** Spec proposes `jq '.. | objects | select(has($key))'` for finding tokens in nested secrets.json, but collision handling (same key in multiple paths) undefined. *Resolve during Phase 2 with explicit precedence rules.*

## Sources

### Primary (HIGH confidence)
- `/workspace/.devcontainer/install-agent-config.sh` (423 lines) — current implementation patterns, integration points
- `/workspace/agent-config/settings.json.template` — hook structure, env section format
- `/workspace/.planning/nmc-plugin-spec.md` — plugin requirements, edge cases
- `/workspace/config.json` — configuration schema, mcp-templates structure
- [jq 1.6 Manual](https://jqlang.org/manual/v1.6/) — recursive merge operator, reduce patterns
- [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events](https://claudefa.st/blog/tools/hooks/hooks-guide) — hook events and registration
- [Extend Claude with skills - Claude Code Docs](https://code.claude.com/docs/en/skills) — skill auto-discovery patterns

### Secondary (MEDIUM confidence)
- [How to Recursively Merge JSON Objects and Concatenate Arrays with jq](https://www.codegenes.net/blog/jq-recursively-merge-objects-and-concatenate-arrays/) — array concatenation vs `*` operator behavior
- [BashPitfalls - Greg's Wiki](https://mywiki.wooledge.org/BashPitfalls) — glob no-match literal iteration
- [Bash Scripting: The Complete Guide for 2026](https://devtoolbox.dedyn.io/blog/bash-scripting-complete-guide) — modern bash patterns
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/plugin/toggle/) — plugin enable/disable patterns
- [Inside Claude Code Skills: Structure, prompts, invocation](https://mikhail.io/2025/10/claude-code-skills/) — skill directory structure

### Tertiary (LOW confidence)
- Community blog posts on jq merging strategies (multiple sources)
- Generic bash scripting tutorials (validation only, not novel patterns)

---
*Research completed: 2026-02-15*
*Ready for roadmap: yes*

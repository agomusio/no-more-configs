# Requirements: Claude Code Sandbox v1.2

**Defined:** 2026-02-15
**Core Value:** All container configuration is generated from source files checked into the repo — plugins extend this with self-registering bundles.

## v1.2 Requirements

Requirements for milestone v1.2. Each maps to roadmap phases.

### Plugin Discovery

- [ ] **PLUG-01**: Install script discovers plugin directories under `agent-config/plugins/`
- [ ] **PLUG-02**: Install script validates `plugin.json` manifest exists and is valid JSON
- [ ] **PLUG-03**: Plugin with no `plugin.json` is skipped with a warning
- [ ] **PLUG-04**: Plugins are enabled by default when not mentioned in `config.json`
- [ ] **PLUG-05**: Plugin set to `"enabled": false` in `config.json` is fully skipped (no files copied, no registrations)
- [ ] **PLUG-06**: Plugins are processed in deterministic alphabetical order

### Plugin File Copying

- [ ] **COPY-01**: Plugin skills directories are copied to `~/.claude/skills/`
- [ ] **COPY-02**: Plugin hooks scripts are copied to `~/.claude/hooks/`
- [ ] **COPY-03**: Plugin commands are copied to `~/.claude/commands/`
- [ ] **COPY-04**: Plugin agents are copied to `~/.claude/agents/`
- [ ] **COPY-05**: GSD files are never overwritten by plugin copies (`gsd-*.md` agents, `commands/gsd/`)
- [ ] **COPY-06**: Plugin file copy handles empty directories and missing subdirectories gracefully

### Hook Registration

- [ ] **HOOK-01**: Plugin hooks declared in `plugin.json` are merged into `settings.local.json`
- [ ] **HOOK-02**: Multiple plugins registering the same event accumulate (all fire, none lost)
- [ ] **HOOK-03**: Template hooks (from settings.json.template) are preserved when plugin hooks merge
- [ ] **HOOK-04**: Hook merge uses jq array concatenation (not `*` operator) to prevent overwriting

### Environment Variables

- [ ] **ENV-01**: Plugin env vars from `plugin.json` are injected into `settings.local.json` env section
- [ ] **ENV-02**: `config.json` plugin env overrides take precedence over `plugin.json` defaults
- [ ] **ENV-03**: Env vars from multiple plugins are accumulated correctly

### MCP Server Registration

- [ ] **MCP-01**: Plugin MCP servers from `plugin.json` are merged into `~/.claude/.mcp.json`
- [ ] **MCP-02**: `{{PLACEHOLDER}}` tokens in plugin MCP configs are hydrated from `secrets.json`
- [ ] **MCP-03**: Plugin MCP servers persist across container rebuilds (mcp-setup timing fixed)
- [ ] **MCP-04**: Missing secret tokens result in empty string with warning (not crash)

### Standalone Commands

- [ ] **CMD-01**: Markdown files in `agent-config/commands/` are copied to `~/.claude/commands/`
- [ ] **CMD-02**: Existing commands (especially GSD) are not overwritten by standalone command copies
- [ ] **CMD-03**: Command count is reported in install summary

### Langfuse Migration

- [ ] **LANG-01**: Langfuse hook moved from `agent-config/hooks/` to `agent-config/plugins/langfuse-tracing/`
- [ ] **LANG-02**: `plugins/langfuse-tracing/plugin.json` manifest declares Stop hook registration
- [ ] **LANG-03**: Langfuse hook registration removed from `settings.json.template`
- [ ] **LANG-04**: Langfuse tracing works identically after migration (no regression)
- [ ] **LANG-05**: Langfuse can be disabled via `config.json` plugins section

### Enhanced Validation

- [ ] **VAL-01**: Install script warns when a plugin hook references a non-existent script file
- [ ] **VAL-02**: Install script warns when a plugin file would overwrite an existing file from another plugin
- [ ] **VAL-03**: Install summary shows plugin count, command count, and any warnings
- [ ] **VAL-04**: Invalid `plugin.json` produces clear error message with plugin name

## Future Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Plugin Ecosystem

- **ECO-01**: Plugin versioning enforcement (semver checks)
- **ECO-02**: Plugin dependency declarations (plugin A requires plugin B)
- **ECO-03**: Plugin uninstall command
- **ECO-04**: JSON Schema validation for plugin.json manifests (ajv-cli)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Per-session plugin enable/disable | No runtime config reload API in Claude Code |
| Plugin auto-updates | No package registry; rebuild container handles updates |
| Plugin conflict blocking | Informational warnings sufficient; blocking creates UX friction |
| Strict plugin dependency resolution | Premature until plugin ecosystem proves need |
| Remote plugin installation | Security concern; plugins are version-controlled in repo |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUG-01 | Phase 4 | Pending |
| PLUG-02 | Phase 4 | Pending |
| PLUG-03 | Phase 4 | Pending |
| PLUG-04 | Phase 4 | Pending |
| PLUG-05 | Phase 4 | Pending |
| PLUG-06 | Phase 4 | Pending |
| COPY-01 | Phase 4 | Pending |
| COPY-02 | Phase 4 | Pending |
| COPY-03 | Phase 4 | Pending |
| COPY-04 | Phase 4 | Pending |
| COPY-05 | Phase 4 | Pending |
| COPY-06 | Phase 4 | Pending |
| HOOK-01 | Phase 4 | Pending |
| HOOK-02 | Phase 4 | Pending |
| HOOK-03 | Phase 4 | Pending |
| HOOK-04 | Phase 4 | Pending |
| ENV-01 | Phase 4 | Pending |
| ENV-02 | Phase 4 | Pending |
| ENV-03 | Phase 4 | Pending |
| CMD-01 | Phase 4 | Pending |
| CMD-02 | Phase 4 | Pending |
| CMD-03 | Phase 4 | Pending |
| MCP-01 | Phase 5 | Pending |
| MCP-02 | Phase 5 | Pending |
| MCP-03 | Phase 5 | Pending |
| MCP-04 | Phase 5 | Pending |
| LANG-01 | Phase 6 | Pending |
| LANG-02 | Phase 6 | Pending |
| LANG-03 | Phase 6 | Pending |
| LANG-04 | Phase 6 | Pending |
| LANG-05 | Phase 6 | Pending |
| VAL-01 | Phase 6 | Pending |
| VAL-02 | Phase 6 | Pending |
| VAL-03 | Phase 6 | Pending |
| VAL-04 | Phase 6 | Pending |

**Coverage:**
- v1.2 requirements: 35 total
- Mapped to phases: 35
- Unmapped: 0

---
*Requirements defined: 2026-02-15*
*Last updated: 2026-02-15 after roadmap creation*

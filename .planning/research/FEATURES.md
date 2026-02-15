# Feature Research

**Domain:** CLI Plugin System for Agent Configuration
**Researched:** 2026-02-15
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = plugin system feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Plugin discovery (filesystem-based) | Standard CLI pattern — drop files in directory, rebuild, works | LOW | Claude Code auto-discovers from `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/agents/` [1] |
| Manifest validation (plugin.json) | Prevents broken plugins from causing runtime failures | LOW | Validate at install time with jq, skip plugin if invalid. Standard pattern across plugin systems [2][3] |
| Enable/disable control via config.json | Users expect to toggle plugins without file deletion | LOW | `"plugins": { "name": { "enabled": false } }` pattern, proven in WP-CLI, GitHub Copilot CLI [4] |
| Hook self-registration | Manual registration in settings.json defeats plugin purpose | MEDIUM | Plugins declare hooks in manifest → install script merges into settings.local.json [5][6] |
| Non-destructive file copies | Plugins shouldn't overwrite GSD or user files | LOW | Check if file exists before copy, skip GSD-protected paths [7] |
| MCP server registration | Plugins bundle capabilities (skills + hooks + MCP servers) | MEDIUM | Plugins declare mcp_servers in manifest → merged into .mcp.json with token hydration [8][9] |
| Env var injection | Plugins need to set runtime environment (API endpoints, feature flags) | LOW | Plugins declare env vars → merged into settings.local.json env section [10] |

### Differentiators (Competitive Advantage)

Features that set this plugin system apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Config.json overrides plugin defaults | Master config controls all plugins — infrastructure-as-code | LOW | Plugin declares default env, config.json overrides win. Hierarchical precedence [11] |
| Plugin-enabled-by-default | Zero-config for simple use case — drop plugin in, works immediately | LOW | If plugin not in config.json, treat as enabled=true. Opt-out not opt-in [12] |
| Standalone vs plugin dual mode | Gradual migration path — langfuse hook works standalone OR as plugin | LOW | Install script processes standalone files first, then plugins. Both patterns coexist |
| Hook event accumulation | Multiple plugins can register same event — all fire in order | MEDIUM | Install script uses jq to merge all plugin hooks under each event key [13] |
| File conflict warnings (informational) | Transparency when plugins overwrite each other — debugging aid | LOW | Log "Plugin B overwrote skill X from Plugin A" during install |
| Idempotent installation | Rebuild container safely — install script re-runs without breaking state | LOW | Already exists in install-agent-config.sh. Extends naturally to plugins |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Per-session plugin enable/disable | "I want to try this plugin just for this conversation" | Claude Code has no API for runtime enable/disable. Would need settings.json rewrite mid-session causing race conditions [14] | Document that plugins are container-scoped. Disable in config.json, rebuild container (15 seconds) |
| Plugin version pinning / updates | "Plugins should auto-update like npm packages" | Plugins are local files, not packages. No registry. Updates = user copies new files | Document "plugins are not packages" — update by replacing files, rebuild |
| Nested plugin dependencies | "Plugin A requires Plugin B" | Circular dependencies, load order complexity, debugging hell [15] | Document plugins as isolated units. Duplicate code if needed |
| Plugin conflict detection | "Warn if two plugins provide same skill name" | Last-write-wins is simple, predictable. Auto-conflict resolution creates surprise [16] | Log which plugin won during install. User reads logs if behavior unexpected |
| Hook registration validation (script exists check) | "Don't register hook if script missing" | False negatives (script generated at runtime), blocks experimentation | Register hook regardless, Claude Code logs error when hook fires. Non-blocking |
| JSON Schema for plugin.json | "Enforce strict schema for plugin manifest" | Over-engineering for small system. jq empty check sufficient for MVP [17] | Use jq validation. Add JSON Schema later if plugin ecosystem grows |

## Feature Dependencies

```
Plugin Discovery
    └──requires──> Manifest Validation (can't process invalid plugin.json)
                       └──requires──> Enable/Disable Control (config.json gates processing)

Hook Self-Registration
    └──requires──> Hook Event Accumulation (multiple plugins → same event)

MCP Server Registration
    └──requires──> Env Var Injection (MCP servers need env vars like API keys)
    └──requires──> Token Hydration ({{PLACEHOLDER}} from secrets.json)

Non-Destructive File Copies
    └──conflicts──> File Conflict Warnings (if non-destructive, no conflicts to warn about)
                    └──resolution──> Warn only when plugin files overwrite OTHER plugins, not when skipping existing files
```

### Dependency Notes

- **Plugin Discovery requires Manifest Validation:** Can't determine what a plugin offers without valid plugin.json
- **Hook Self-Registration requires Event Accumulation:** Multiple plugins registering `Stop` hook must all fire
- **MCP Server Registration requires Token Hydration:** Plugins declare `"env": { "API_KEY": "{{MY_SECRET}}" }` → install script hydrates from secrets.json
- **Non-Destructive Copies conflicts with Conflict Warnings:** Original design said "non-destructive" (skip existing files). But plugins CAN overwrite each other's files in `~/.claude/skills/` if they provide same-named skill. Resolution: Non-destructive applies to USER files (GSD) and EXISTING container files. Plugins in same install pass overwrite each other (last alphabetically wins). Log this.

## MVP Definition

### Launch With (v1)

Minimum viable plugin system — what's needed for langfuse migration and basic plugin support.

- [x] **Plugin discovery** — Scan `agent-config/plugins/*/`, load plugin.json from each
- [x] **Manifest validation** — Use jq to validate JSON, skip plugin if invalid
- [x] **Enable/disable via config.json** — `"plugins": { "name": { "enabled": false } }` gates install
- [x] **Hook self-registration** — Merge plugin hooks into settings.local.json
- [x] **Env var injection** — Merge plugin env into settings.local.json
- [x] **File copies (skills, hooks, commands, agents)** — Copy from plugin subdirectories to `~/.claude/`
- [x] **MCP server registration** — Merge plugin mcp_servers into .mcp.json
- [x] **Config.json overrides plugin env** — Precedence: config.json > plugin.json > defaults
- [x] **Plugin-enabled-by-default** — If not in config.json, treat as enabled
- [x] **GSD protection** — Never overwrite `~/.claude/commands/gsd/` or `~/.claude/agents/gsd-*.md`

Rationale: These are the minimum features to migrate langfuse from standalone hook → plugin and support the example auto-lint plugin from the spec.

### Add After Validation (v1.x)

Features to add once core plugin system is working and users have 2-3 plugins installed.

- [ ] **File conflict warnings** — Log when Plugin B overwrites skill from Plugin A (trigger: users report "my skill disappeared")
- [ ] **Plugin installation summary** — Print "Plugin 'langfuse-tracing': 1 hook, 2 env vars, 0 skills" per plugin (trigger: debugging installation issues)
- [ ] **Hook script existence check (warning only)** — Warn if plugin.json references hook script that doesn't exist in plugin directory (trigger: user typo in manifest)
- [ ] **Unresolved token detection in plugin manifests** — Detect `{{PLACEHOLDER}}` in plugin.json that can't be hydrated from secrets.json (trigger: users confused why MCP server doesn't work)

### Future Consideration (v2+)

Features to defer until plugin ecosystem exists and patterns emerge.

- [ ] **Plugin versioning** — `"version": "1.2.0"` in plugin.json, logged during install (why defer: no use case until users share plugins)
- [ ] **Plugin dependencies** — `"requires": ["other-plugin"]` in manifest (why defer: complexity, unclear if needed)
- [ ] **Plugin uninstall command** — Script to remove plugin files from `~/.claude/` (why defer: rebuild container achieves same, faster)
- [ ] **JSON Schema validation for plugin.json** — Strict schema with $schema keyword (why defer: jq sufficient for MVP, schema useful if ecosystem grows [17])
- [ ] **Plugin directory for standalone commands** — Support `agent-config/commands/` for slash commands not in plugins (why defer: spec already includes this, just needs implementation in install script)
- [ ] **Plugin load order control** — `"priority": 10` to control which plugin's files win conflicts (why defer: alphabetical sort sufficient, unclear if load order matters)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Plugin discovery | HIGH | LOW | P1 |
| Manifest validation | HIGH | LOW | P1 |
| Enable/disable control | HIGH | LOW | P1 |
| Hook self-registration | HIGH | MEDIUM | P1 |
| Env var injection | HIGH | LOW | P1 |
| MCP server registration | HIGH | MEDIUM | P1 |
| Non-destructive file copies | HIGH | LOW | P1 |
| Config.json overrides | MEDIUM | LOW | P1 |
| Plugin-enabled-by-default | MEDIUM | LOW | P1 |
| File conflict warnings | MEDIUM | LOW | P2 |
| Plugin installation summary | MEDIUM | LOW | P2 |
| Hook script existence check | LOW | LOW | P2 |
| Token detection in manifests | MEDIUM | LOW | P2 |
| Plugin versioning | LOW | LOW | P3 |
| Plugin dependencies | LOW | HIGH | P3 |
| Plugin uninstall command | LOW | MEDIUM | P3 |
| JSON Schema validation | LOW | MEDIUM | P3 |
| Load order control | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch (langfuse migration requires these)
- P2: Should have, add when debugging/UX issues arise
- P3: Nice to have, future consideration after ecosystem exists

## Claude Code Expectations

Based on official documentation and community patterns, Claude Code expects specific behaviors:

### Skills Directory (`~/.claude/skills/`)

**Auto-Discovery:** Claude Code scans `~/.claude/skills/` for directories containing `SKILL.md` files [18]. Skills use progressive disclosure: metadata loaded first (~100 tokens), full instructions loaded when skill matches task (<5k tokens) [19].

**Structure:** Each skill is a directory with:
- `SKILL.md` (required) — YAML frontmatter + markdown instructions
- `references/` (optional) — Supporting docs loaded on-demand

**Discovery Sources:** User settings (`~/.config/claude/skills/`), project settings (`.claude/skills/`), plugin-provided skills, built-in skills [20].

**Implications for Plugin System:**
- Plugins copy skills to `~/.claude/skills/` → Claude discovers automatically
- No registration needed, file presence = discovered
- Multiple plugins can provide skills (all discovered)

### Commands Directory (`~/.claude/commands/`)

**Auto-Discovery:** Custom slash commands in `~/.claude/commands/` are auto-discovered [21]. Personal commands available across all projects, project commands in `.claude/commands/` available in that project only.

**Structure:**
- Markdown files (`.md`) → slash command name matches filename
- Example: `.claude/commands/review.md` → `/review` command

**Merged with Skills:** Commands have been merged into skills system. A file at `.claude/commands/review.md` and a skill at `.claude/skills/review/SKILL.md` both create `/review` and work the same way. Existing `.claude/commands/` files keep working [22].

**Implications for Plugin System:**
- Plugins copy .md files to `~/.claude/commands/` → auto-discovered as slash commands
- No registration needed
- GSD protection required: don't overwrite `~/.claude/commands/gsd/`

### Hooks and Hook Events

**Hook Events (12 total):** [23]
- **SessionStart** — New session or resume, receives source/model/agent_type
- **SessionEnd** — Session terminates
- **Stop** — Agent finishes responding (most common hook point)
- **SubagentStop** — Subagent finishes
- **StatusLine** — Live context metrics (only hook that receives real-time data)
- **PreToolUse** — Before tool runs
- **PostToolUse** — After tool succeeds
- **Notification** — Alert sent
- **UserPromptSubmit** — User sends message

**Registration:** Hooks must be registered in `settings.local.json` under `hooks` key [24]:
```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "python3 ~/.claude/hooks/langfuse_hook.py"
      }
    ]
  }
}
```

**Implications for Plugin System:**
- Plugins can't just copy hook scripts to `~/.claude/hooks/` — must also register in settings
- Multiple hooks for same event → all fire (accumulation, not replacement)
- Install script must merge plugin hook registrations into settings.local.json

### Agents Directory (`~/.claude/agents/`)

**Auto-Discovery:** Agent definitions in `~/.claude/agents/` are auto-discovered [25].

**GSD Protection:** GSD installs agents with `gsd-` prefix (e.g., `gsd-project.md`, `gsd-milestone.md`). Plugins must not overwrite these [26].

**Implications for Plugin System:**
- Plugins can provide agent definitions (rare use case)
- Non-destructive copy with GSD pattern exclusion: skip `gsd-*.md`

## Existing Install Script Integration Points

The proposed plugin system integrates into existing `install-agent-config.sh` at these points:

### Installation Order (Proposed)

Current order with plugin additions (NEW steps bolded):

1. Read config.json + secrets.json
2. Generate firewall-domains.conf
3. Generate .vscode/settings.json
4. Generate Codex config.toml
5. Create `~/.claude/` directory structure
6. Copy standalone skills → `~/.claude/skills/`
7. Copy standalone hooks → `~/.claude/hooks/`
8. **NEW: Copy standalone commands → `~/.claude/commands/`**
9. Hydrate settings.json.template → `~/.claude/settings.local.json`
10. Seed settings.json with permissions
11. **NEW: Install plugins (discover, validate, copy files, accumulate registrations)**
12. **NEW: Merge plugin hooks into settings.local.json**
13. **NEW: Merge plugin env vars into settings.local.json**
14. **NEW: Merge plugin MCP servers into .mcp.json**
15. Restore Claude credentials
16. Restore Codex credentials
17. Restore git identity
18. Generate .mcp.json from config.json templates
19. Generate infra/.env if applicable
20. Detect unresolved `{{PLACEHOLDER}}` tokens
21. Install GSD framework (npx)
22. Enforce settings.json final values (bypassPermissions, opus, high effort)
23. Print summary

**Rationale for Order:**
- Plugins processed AFTER standalone files (standalone = base layer, plugins = enhancement)
- Plugin registrations merged AFTER settings.local.json hydration (hydration = base, plugins add to it)
- GSD installed LAST (protects GSD files from plugin overwrites)
- Settings enforcement AFTER GSD (GSD modifies settings.json, we overwrite its changes)

### Dependencies on Existing Functions

**Validation:** Plugin system reuses `validate_json()` function for plugin.json validation.

**Token Hydration:** Plugin MCP servers use same hydration pattern as mcp-templates (sed replacement of `{{PLACEHOLDER}}`).

**Idempotency:** Plugin installation inherits idempotency from existing script design (safe to re-run on rebuild).

## Complexity Assessment

| Feature | Implementation Lines | Complexity Factors |
|---------|---------------------|-------------------|
| Plugin discovery | ~5 lines | Simple directory iteration with [ -d ] check |
| Manifest validation | ~10 lines | Reuse validate_json(), skip plugin on failure |
| Enable/disable control | ~10 lines | jq query to config.json, continue if enabled=false |
| File copies (4 types) | ~40 lines | Skills, hooks, commands, agents — 4 similar blocks with GSD protection on commands/agents |
| Hook accumulation | ~15 lines | jq merge arrays under each event key |
| Env var accumulation | ~15 lines | jq merge objects with config.json override precedence |
| MCP server accumulation | ~20 lines | jq merge + token hydration (reuse existing pattern) |
| Merge registrations | ~30 lines | 3 merge operations (hooks, env, mcp) into existing files |
| Summary output | ~5 lines | Echo counts |

**Total estimated additions to install-agent-config.sh:** ~150 lines

**Risk Areas:**
- **jq merge logic for hooks:** Arrays of objects, must preserve existing + add new. Test with langfuse migration.
- **Precedence for env vars:** Config.json overrides must win. Three-way merge (base env, plugin env, config.json override).
- **GSD protection in agents/commands:** Regex match for `gsd-*.md` and directory `commands/gsd/`. Test with GSD already installed.

## Edge Cases Documented in Spec

The nmc-plugin-spec.md already identifies these edge cases. Feature system confirms they're handled:

1. **Plugin name conflicts (same skill from two plugins):** Last alphabetically wins. Log which plugin won. ✅ ACCEPTABLE
2. **Multiple plugins registering same hook event:** All fire in alphabetical order. ✅ ACCEPTABLE
3. **Plugin hook references missing script:** Hook registered anyway, Claude logs error at runtime. ✅ ACCEPTABLE (non-blocking)
4. **GSD protection:** Commands/agents with gsd pattern never overwritten. ✅ REQUIRED
5. **Plugin env var conflicts:** Last alphabetically wins, config.json always wins. ✅ ACCEPTABLE
6. **Missing plugin.json:** Skip plugin with warning, no partial install. ✅ REQUIRED
7. **Unresolved {{PLACEHOLDER}} in plugin MCP servers:** Empty string replacement + warning. ✅ ACCEPTABLE

## Competitor Feature Analysis

| Feature | WP-CLI (WordPress) | GitHub Copilot CLI | Claude Code (Proposed) | Our Approach |
|---------|-------------------|-------------------|----------------------|--------------|
| Plugin discovery | Auto-scan plugins directory | Manual install command | Auto-scan plugins directory | Auto-scan `agent-config/plugins/` |
| Enable/disable | `wp plugin activate/deactivate` | `copilot extension enable/disable` | Config.json enabled=true/false | Config.json (declarative, rebuild to apply) |
| Manifest validation | WordPress validates plugin headers | Extension manifest validation | No official plugin system | jq validation at install time |
| Hook registration | WordPress action/filter registration API | No hooks (extensions are tools only) | settings.local.json registration | Auto-registration from plugin.json |
| Env var injection | WordPress defines constants | No env injection | settings.local.json env section | Auto-injection from plugin.json |
| MCP server registration | N/A (WordPress-specific) | N/A | .mcp.json registration | Auto-registration from plugin.json |
| Conflict resolution | Last activated plugin wins | N/A | Last-write-wins | Last alphabetically wins, logged |
| Versioning | Plugin version in header | Extension version in manifest | No versioning | Optional version field (logged, not enforced) |

**Key Insight:** Our approach is **declarative + auto-registration** (config.json + rebuild) vs **imperative + CLI commands** (wp/copilot pattern). This fits devcontainer model where configuration is code and rebuilds are fast (15 seconds).

## Sources

### Claude Code Official Documentation
1. [Extend Claude with skills - Claude Code Docs](https://code.claude.com/docs/en/skills)
2. [Plugin Structure and Manifest | anthropics/claude-plugins-official | DeepWiki](https://deepwiki.com/anthropics/claude-plugins-official/5.1-plugin-structure-and-manifest)
3. [Plugin Manifest - OpenClaw](https://docs.openclaw.ai/plugins/manifest)
4. [wp plugin toggle – WP-CLI Command | Developer.WordPress.org](https://developer.wordpress.org/cli/commands/plugin/toggle/)
5. [Hooks reference - Claude Code Docs](https://code.claude.com/docs/en/hooks)
6. [Event-Driven Claude Code and OpenCode Workflows with Hooks](https://www.subaud.io/event-driven-claude-code-and-opencode-workflows-with-hooks/)
7. [Inside Claude Code Skills: Structure, prompts, invocation | Mikhail Shilkov](https://mikhail.io/2025/10/claude-code-skills/)
8. [From Abilities to AI Agents: Introducing the WordPress MCP Adapter – WordPress Developer Blog](https://developer.wordpress.org/news/2026/02/from-abilities-to-ai-agents-introducing-the-wordpress-mcp-adapter/)
9. [Two Essential Patterns for Building MCP Servers-Shaaf's Blog](https://shaaf.dev/post/2026-01-08-two-essential-patterns-for-buildingm-mcp-servers/)
10. [Configuration System | alvinunreal/oh-my-opencode-slim | DeepWiki](https://deepwiki.com/alvinunreal/oh-my-opencode-slim/4-background-task-system)
11. [Manage Configuration | Meltano Documentation](https://docs.meltano.com/guide/configuration/)
12. [Become a Claude Code Hero: Core Concepts of the Claude CLI (Plugins, Hooks, Skills & MCP) | by Ankush Singh | Jan, 2026 | Medium](https://medium.com/@diehardankush/become-a-claude-code-hero-core-concepts-of-the-claude-cli-plugins-hooks-skills-mcp-54ae48d7c145)
13. [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events](https://claudefa.st/blog/tools/hooks/hooks-guide)
14. [[CRITICAL] Plugin-MCP Configuration Mismatch Causes Misleading 'Request Timed Out' Errors · Issue #18762 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/18762)
15. [Plugin discovery system stops scanning when a plugin manifest is found · Issue #124305 · elastic/kibana](https://github.com/elastic/kibana/issues/124305)
16. [How to Implement Last-Write-Wins](https://oneuptime.com/blog/post/2026-01-30-last-write-wins/view)
17. [JSON Schema Validation: A Vocabulary for Structural Validation of JSON](https://json-schema.org/draft/2020-12/json-schema-validation)
18. [Agent Skills - Claude API Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
19. [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
20. [User skills in ~/.claude/skills/ not auto-discovered · Issue #11266 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/11266)
21. [Slash commands - Claude Code Docs](https://code.claude.com/docs/en/slash-commands)
22. [Claude Code Customization: CLAUDE.md, Slash Commands, Skills, and Subagents | alexop.dev](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)
23. [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events](https://claudefa.st/blog/tools/hooks/hooks-guide)
24. [Claude Code power user customization: How to configure hooks | Claude](https://claude.com/blog/how-to-configure-hooks)
25. [How to Use Claude Code: A Guide to Slash Commands, Agents, Skills, and Plug-ins](https://www.producttalk.org/how-to-use-claude-code-features/)
26. Existing install-agent-config.sh implementation (GSD protection pattern lines 384-401)

---
*Feature research for: CLI Plugin System for Agent Configuration*
*Researched: 2026-02-15*

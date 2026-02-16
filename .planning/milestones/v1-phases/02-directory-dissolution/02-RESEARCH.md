# Phase 2: Directory Dissolution - Research

**Researched:** 2026-02-14
**Domain:** Directory refactoring, environment variable management, shell configuration
**Confidence:** HIGH

## Summary

Phase 2 dissolves the `claudehome/` directory by redistributing its contents to purpose-named locations (`agent-config/skills/`, `/workspace/.planning/`, `/workspace/infra/`, `infra/scripts/`), updates all path references to use environment variables, and removes the working directory prefix from Dockerfile aliases to enable sessions launching from any directory.

This is primarily an infrastructure refactoring operation with a critical constraint: the commit sequence must maintain build continuity at every step. The add-wire-delete pattern (add files to new locations, update references, then delete old locations) ensures the devcontainer remains buildable throughout the migration.

The phase has minimal external dependencies because it's moving existing files and updating hardcoded paths. The core risks are incomplete reference updates (leading to broken paths post-migration) and violating build continuity (creating unbuildable intermediate commits).

**Primary recommendation:** Use atomic commits with the add-wire-delete pattern, environment variables for all path references, and comprehensive verification of all 38 files that reference claudehome/ or langfuse-local/.

## Standard Stack

This phase uses standard Unix shell tools and Docker/devcontainer configuration patterns. No external libraries are required.

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 5.x+ | Shell scripting, path manipulation | Universal Unix shell, installed in base image |
| jq | 1.6+ | JSON manipulation (if needed) | Standard JSON CLI tool, already in container |
| git | 2.x+ | Atomic commits, build continuity | Version control for migration sequence |
| Docker | 24.x+ | Container rebuild validation | Devcontainer host environment |

### Environment Variable Patterns
| Variable | Scope | Purpose | Set By |
|----------|-------|---------|--------|
| `LANGFUSE_STACK_DIR` | Container | Path to infra stack (docker-compose, .env, scripts) | Dockerfile ENV |
| `CLAUDE_WORKSPACE` | Container | Workspace root path (typically /workspace) | Dockerfile ENV |
| `WORKSPACE_FOLDER` | VS Code | Set by devcontainer, references workspace root | devcontainer.json |

**Installation:**
No new tools required. All dependencies already present in container.

## Architecture Patterns

### Recommended Migration Structure

**Before (claudehome/ centralized):**
```
claudehome/
├── .claude/
│   ├── skills/          → scattered purpose files in monolithic directory
│   └── settings.local.json
├── .planning/           → duplicate of workspace .planning
├── langfuse-local/      → infrastructure mixed with agent config
└── scripts/             → verification scripts mixed with config
```

**After (purpose-based distribution):**
```
/workspace/
├── agent-config/
│   └── skills/          → devcontainer.SKILL.md, gitprojects.SKILL.md
├── .planning/           → single source of truth at workspace root
├── infra/               → all infrastructure (renamed from langfuse-local/)
│   ├── docker-compose.yml
│   ├── .env
│   ├── mcp/
│   └── scripts/         → verify-filesystem-mcp.sh, verify-gateway-connectivity.sh
└── gitprojects/         → user projects (unchanged)
```

### Pattern 1: Add-Wire-Delete Commit Sequence

**What:** Migration broken into three atomic commit phases to maintain build continuity.

**When to use:** Any refactoring that moves files referenced by build scripts, aliases, or runtime configuration.

**Example sequence:**
```bash
# Commit 1: ADD - Create new locations, copy files
mkdir -p agent-config/skills infra/scripts
cp -r claudehome/.claude/skills/devcontainer agent-config/skills/
cp -r claudehome/.claude/skills/gitprojects agent-config/skills/
mv claudehome/langfuse-local infra
mv claudehome/scripts/* infra/scripts/
git add agent-config/ infra/
git commit -m "feat(phase-2): add redistributed directory structure"

# Commit 2: WIRE - Update all references
# Update Dockerfile, devcontainer.json, mcp-setup-bin.sh, README.md, etc.
# Use environment variables instead of hardcoded paths
git add .devcontainer/ README.md docs/
git commit -m "refactor(phase-2): update path references to use environment variables"

# Commit 3: DELETE - Remove old locations
rm -rf claudehome/
git add -u
git commit -m "refactor(phase-2): remove claudehome directory"
```

**Why this works:**
- Commit 1: Build still works (old paths exist, new paths added)
- Commit 2: Build still works (both old and new paths valid)
- Commit 3: Build still works (only new paths remain, all references updated)

### Pattern 2: Environment Variable Path References

**What:** Replace hardcoded paths with environment variables for portability and maintainability.

**When to use:** Any script, alias, or configuration that references workspace paths.

**Example:**
```bash
# Anti-pattern (hardcoded path)
alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'
docker compose -f /workspace/claudehome/langfuse-local/docker-compose.yml up

# Pattern (environment variable)
alias claudey='claude --dangerously-skip-permissions'  # No cd prefix needed
docker compose -f "${LANGFUSE_STACK_DIR}/docker-compose.yml" up
```

**Implementation in Dockerfile:**
```dockerfile
# Set environment variables for path references
ENV LANGFUSE_STACK_DIR=/workspace/infra
ENV CLAUDE_WORKSPACE=/workspace

# Add to shell configs for interactive use
RUN echo "export LANGFUSE_STACK_DIR=/workspace/infra" >> /home/node/.bashrc && \
    echo "export CLAUDE_WORKSPACE=/workspace" >> /home/node/.bashrc
```

**Sources:**
- [Docker Compose: Set environment variables](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables)
- [Environment variables in devcontainer.json](https://code.visualstudio.com/remote/advancedcontainers/environment-variables)

### Pattern 3: Alias Working Directory Independence

**What:** Remove `cd /workspace/claudehome &&` prefix from aliases to enable sessions launching from any directory.

**Why it matters:** GSD sessions should work from `gitprojects/` subdirectories. The framework needs to find `.planning/` via upward traversal, which fails if aliases force a specific working directory.

**Example:**
```bash
# Before (forces working directory)
alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'
alias claudeyr='cd /workspace/claudehome && claude --dangerously-skip-permissions --resume'

# After (respects current directory)
alias claudey='claude --dangerously-skip-permissions'
alias claudeyr='claude --dangerously-skip-permissions --resume'
```

**GSD .planning discovery pattern (upward traversal):**
```bash
# Pattern: Search parent directories for .planning
find_planning_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.planning" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}
```

**Sources:**
- [Finding Git root directory techniques](https://sqlpey.com/git/finding-git-repo-root-techniques/)
- [Bash script to find parent directory of a file](https://gist.github.com/dajulia3/f43b9174746d4ef6404c8a8883a29cf1)

### Pattern 4: Comprehensive Reference Update

**What:** Use grep to find ALL occurrences of paths being changed, update each systematically.

**When to use:** Any refactoring that renames or moves frequently-referenced directories.

**Example discovery:**
```bash
# Find all references to claudehome/ or langfuse-local/
grep -r "claudehome\|langfuse-local" \
  .devcontainer/ README.md docs/ claudehome/ \
  --include="*.sh" --include="*.json" --include="*.yml" --include="*.md"
```

**Update categories:**
1. **Scripts** (`.sh`): Update hardcoded paths, add environment variable usage
2. **Docker Compose** (`.yml`): Update volume mounts, working directories
3. **Documentation** (`.md`): Update example commands, path references
4. **Configuration** (`.json`): Update file paths in devcontainer settings

### Anti-Patterns to Avoid

- **Partial migration:** Moving some files but leaving others creates confusion. Dissolve completely in one phase.
- **Breaking build continuity:** Single commit that moves files and updates references simultaneously breaks bisectability.
- **Hardcoded paths in new code:** After establishing environment variables, using `/workspace/infra` directly instead of `$LANGFUSE_STACK_DIR`.
- **Forgetting documentation updates:** README.md and docs/ still referencing old paths after migration.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding all path references | Manual search, memory | `grep -r "pattern" --include="*.ext"` | Regex search is comprehensive, repeatable |
| Upward directory traversal | Custom implementation | Git root pattern (`while [ "$dir" != "/" ]`) | Standard, well-tested pattern |
| Environment variable substitution | String concatenation | Docker ENV + shell export | Consistent across Dockerfile and runtime |
| Migration validation | Manual testing | Git bisect + container rebuild | Automated verification of build continuity |

**Key insight:** Directory refactoring is deceptively complex because scattered references create hidden dependencies. Automated discovery (grep) and systematic verification (rebuild at each commit) prevent "works on my machine" failures.

## Common Pitfalls

### Pitfall 1: Incomplete Reference Updates
**What goes wrong:** Scripts and configs still reference old paths after migration, leading to "file not found" errors at runtime.

**Why it happens:** References scattered across 38+ files in different formats (shell variables, JSON paths, markdown examples, docker-compose volumes).

**How to avoid:**
1. Run comprehensive grep before starting: `grep -r "claudehome\|langfuse-local"`
2. Update ALL matches systematically (scripts first, then configs, then docs)
3. Verify with second grep after updates (should return zero matches outside deleted directory)

**Warning signs:**
- Container builds but features fail at runtime
- Error messages referencing `/workspace/claudehome/`
- MCP gateway fails to start with "no such file or directory"

### Pitfall 2: Breaking Build Continuity
**What goes wrong:** Intermediate commits that move files but don't update references, or update references before creating new locations. Container fails to build mid-migration.

**Why it happens:** Treating migration as single logical operation instead of three atomic commits (add, wire, delete).

**How to avoid:**
1. Commit 1: Create new directories, copy/move files (old paths still exist)
2. Commit 2: Update references to new paths (both paths work)
3. Commit 3: Delete old directories (only new paths remain)
4. Test container rebuild after EACH commit

**Warning signs:**
- `docker compose up` fails between commits
- Aliases reference non-existent directories
- devcontainer refuses to build with "file not found"

### Pitfall 3: Environment Variable Scope Confusion
**What goes wrong:** Environment variables set in Dockerfile but not available in interactive shells, or vice versa.

**Why it happens:** Docker ENV is build-time only unless also added to shell configs (.bashrc/.zshrc). Scripts sourced at different lifecycle stages may not inherit variables.

**How to avoid:**
1. Set in Dockerfile with ENV directive (available during build and runtime)
2. Export in shell configs for interactive sessions (`echo "export VAR=value" >> ~/.bashrc`)
3. Use `containerEnv` in devcontainer.json for VS Code-spawned processes

**Warning signs:**
- Variable works in Dockerfile RUN commands but not in terminal
- docker-compose references undefined variable
- Aliases work but manual commands fail with "command not found"

### Pitfall 4: Forgotten Skills Migration
**What goes wrong:** `claudehome/.claude/skills/` contains devcontainer.SKILL.md and gitprojects.SKILL.md but they're overlooked during migration because skills are auto-installed by GSD.

**Why it happens:** Confusion between GSD-installed skills (installed at runtime) and custom skills (version-controlled).

**How to avoid:**
1. Review `claudehome/.claude/skills/` before migration
2. Move ONLY custom skills (devcontainer, gitprojects) to `agent-config/skills/`
3. Don't move GSD-installed skills (they reinstall from npm)
4. Don't move aa-cloudflare, aa-fullstack (example vendor skills, reinstall separately)

**Warning signs:**
- devcontainer skill missing after rebuild
- gitprojects skill not loading project metadata

### Pitfall 5: Planning Directory Confusion
**What goes wrong:** `claudehome/.planning/` is an OLD planning directory from a different project scope. Deleting it is correct, but might feel wrong.

**Why it happens:** Two `.planning/` directories exist — one at workspace root (current, active), one in claudehome (old, stale).

**How to avoid:**
1. Verify `/workspace/.planning/` contains current PROJECT.md, ROADMAP.md, phases/
2. Verify `claudehome/.planning/` contains DIFFERENT content (old project scope)
3. Delete `claudehome/.planning/` without copying (it's obsolete)

**Warning signs:**
- Two PROJECT.md files with different content
- Planning files referencing "Codex integration" (old scope, already reframed)

### Pitfall 6: Docker Compose Working Directory References
**What goes wrong:** docker-compose.yml references relative paths that break when stack moves from `claudehome/langfuse-local/` to `/workspace/infra/`.

**Why it happens:** Compose resolves paths relative to the docker-compose.yml location unless explicitly configured otherwise.

**How to avoid:**
1. Review docker-compose.yml for relative paths (.env, ./mcp/, ./hooks/)
2. Verify paths still resolve correctly after move (they should, since relative paths are maintained)
3. Update CLI commands that reference compose file: `docker compose -f "${LANGFUSE_STACK_DIR}/docker-compose.yml"`

**Warning signs:**
- Compose fails with "cannot find .env file"
- Volume mounts reference non-existent directories

## Code Examples

Verified patterns from official sources and existing codebase:

### Dockerfile Alias Update
```dockerfile
# Before (forces working directory)
RUN echo "alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'" >> /home/node/.bashrc && \
    echo "alias claudeyr='cd /workspace/claudehome && claude --dangerously-skip-permissions --resume'" >> /home/node/.bashrc

# After (respects current directory)
RUN echo "alias claudey='claude --dangerously-skip-permissions'" >> /home/node/.bashrc && \
    echo "alias claudeyr='claude --dangerously-skip-permissions --resume'" >> /home/node/.bashrc
```

### Environment Variable Setup
```dockerfile
# Add environment variables for path references
ENV LANGFUSE_STACK_DIR=/workspace/infra
ENV CLAUDE_WORKSPACE=/workspace

# Export for interactive shells
RUN echo "export LANGFUSE_STACK_DIR=/workspace/infra" >> /home/node/.bashrc && \
    echo "export CLAUDE_WORKSPACE=/workspace" >> /home/node/.bashrc && \
    echo "export LANGFUSE_STACK_DIR=/workspace/infra" >> /home/node/.zshrc && \
    echo "export CLAUDE_WORKSPACE=/workspace" >> /home/node/.zshrc
```

### Script Path Reference Update
```bash
# Before (mcp-setup-bin.sh with hardcoded path)
echo "  Start: cd /workspace/claudehome/langfuse-local && docker compose up -d docker-mcp-gateway"

# After (using environment variable)
echo "  Start: cd ${LANGFUSE_STACK_DIR} && docker compose up -d docker-mcp-gateway"
```

### Comprehensive Reference Discovery
```bash
# Find all files referencing old paths
grep -r "claudehome\|langfuse-local" \
  .devcontainer/ \
  README.md \
  docs/ \
  claudehome/ \
  --include="*.sh" \
  --include="*.json" \
  --include="*.yml" \
  --include="*.yaml" \
  --include="*.md"

# Output: 38 files total (as documented in additional_context)
```

### Directory Migration Commands
```bash
# Phase 1: Create new structure (add)
mkdir -p agent-config/skills
mkdir -p infra/scripts
cp claudehome/.claude/skills/devcontainer agent-config/skills/
cp claudehome/.claude/skills/gitprojects agent-config/skills/
mv claudehome/langfuse-local infra/
mv claudehome/scripts/* infra/scripts/

# Phase 2: Update references (wire)
# - Update .devcontainer/Dockerfile aliases
# - Update .devcontainer/mcp-setup-bin.sh paths
# - Update README.md examples
# - Update docs/ references

# Phase 3: Remove old structure (delete)
rm -rf claudehome/
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Monolithic config directory | Purpose-based distribution | This phase (Feb 2026) | Clearer separation of concerns, easier to understand |
| Hardcoded paths in scripts | Environment variables | This phase (Feb 2026) | Portable, maintainable, easier to refactor |
| Forced working directory (aliases) | Working directory independence | This phase (Feb 2026) | GSD can launch from gitprojects/ subdirectories |
| Duplicate .planning directories | Single .planning at workspace root | This phase (Feb 2026) | Single source of truth for planning state |

**Deprecated/outdated:**
- `claudehome/` directory: Dissolved into agent-config/, /workspace/.planning/, infra/
- `langfuse-local/` name: Renamed to `infra/` (more accurate — includes MCP gateway, scripts, not just Langfuse)
- `cd /workspace/claudehome &&` alias prefix: Removed to enable directory-independent sessions

## Open Questions

1. **GSD .planning upward traversal verification**
   - What we know: GSD uses .planning/ directory, should work from subdirectories
   - What's unclear: Exact implementation of upward traversal in GSD codebase
   - Recommendation: Test manually after migration — launch session from `gitprojects/adventure-alerts/`, run `/gsd:status`, verify it finds `/workspace/.planning/`

2. **Skills reinstall strategy**
   - What we know: Custom skills (devcontainer, gitprojects) need to move to agent-config/skills/
   - What's unclear: Whether install-agent-config.sh needs to copy them to ~/.claude/skills/ or if Claude Code auto-discovers from agent-config/
   - Recommendation: Defer to Phase 1 install script implementation — if it copies skills, migration is just moving source files

3. **Langfuse stack .env file location**
   - What we know: .env currently in claudehome/langfuse-local/, moves to infra/
   - What's unclear: Whether generate-env.sh needs path update
   - Recommendation: grep for generate-env.sh, verify it writes to correct location after infra/ rename

## Sources

### Primary (HIGH confidence)
- [Docker Compose: Set environment variables](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables) - Environment variable best practices
- [Environment variables in devcontainer.json](https://code.visualstudio.com/remote/advancedcontainers/environment-variables) - VS Code container env config
- [Git best practices 2025](https://acompiler.com/git-best-practices/) - Atomic commits and trunk-based development
- [Atomic Git commits guide](https://medium.com/@sandrodz/a-developers-guide-to-atomic-git-commits-c7b873b39223) - Build continuity through atomic commits
- Existing codebase (.devcontainer/Dockerfile, mcp-setup-bin.sh, claudehome/ structure) - Current implementation patterns

### Secondary (MEDIUM confidence)
- [Finding git root directory techniques](https://sqlpey.com/git/finding-git-repo-root-techniques/) - Upward traversal patterns
- [Bash parent directory search pattern](https://gist.github.com/dajulia3/f43b9174746d4ef6404c8a8883a29cf1) - Directory discovery implementation
- [Docker Compose environment variables precedence](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/) - Understanding variable resolution
- [Dockerfile best practices 2026](https://devtoolbox.dedyn.io/blog/dockerfile-complete-guide) - ARG vs ENV, shell configuration

### Tertiary (LOW confidence)
- [GSD GitHub repository](https://github.com/gsd-build/get-shit-done) - GSD framework overview (doesn't document .planning discovery implementation)

## Metadata

**Confidence breakdown:**
- Migration patterns (add-wire-delete): HIGH - Standard refactoring practice, verified by multiple sources
- Environment variables: HIGH - Official Docker/VS Code documentation
- Atomic commits: HIGH - Git best practices from multiple authoritative sources
- GSD .planning discovery: MEDIUM - Framework behavior documented but implementation details not verified
- Path reference scope: HIGH - Grep results show 38 files, comprehensive audit needed

**Research date:** 2026-02-14
**Valid until:** 30 days (stable patterns, directory refactoring best practices don't change rapidly)

**Key files requiring updates (38 total):**
- .devcontainer/Dockerfile (aliases)
- .devcontainer/devcontainer.json (bind mount — NOTE: Phase 3 scope, not Phase 2)
- .devcontainer/mcp-setup-bin.sh (path references)
- .devcontainer/setup-network-checks.sh (path references)
- README.md (example commands)
- docs/* (various path references in documentation)
- claudehome/langfuse-local/* (internal references within stack, move to infra/)

**Migration scope:**
- Skills: Move devcontainer/SKILL.md + gitprojects/SKILL.md to agent-config/skills/
- Planning: Delete claudehome/.planning/ (obsolete, different project scope)
- Infrastructure: Move langfuse-local/ to infra/
- Scripts: Move claudehome/scripts/ to infra/scripts/
- References: Update all 38 files to use environment variables
- Aliases: Remove `cd /workspace/claudehome &&` prefix
- Deletion: Remove claudehome/.claude/settings.local.json, then claudehome/ directory

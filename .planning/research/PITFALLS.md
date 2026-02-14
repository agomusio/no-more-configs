# Devcontainer Configuration Refactor Pitfalls

**Domain:** Devcontainer configuration management on Windows 11/WSL2/Docker Desktop
**Researched:** 2026-02-14
**Confidence:** MEDIUM (based on training data + codebase analysis, WebSearch unavailable)

## Critical Pitfalls

These mistakes cause container rebuilds to fail, data loss, or broken tooling requiring complete rework.

### Pitfall 1: Bind Mount Removal Without Secret Persistence Strategy

**What goes wrong:** Removing `~/.claude` bind mount (line 49 in devcontainer.json) deletes access to Claude Code authentication tokens and settings. Container rebuilds lose authentication, breaking CLI sessions.

**Why it happens:** Developers assume removing bind mount and switching to container-local config is just a "location change." They don't realize:
- Claude Code stores auth tokens in `~/.claude/config.json` or `~/.claude/secrets.json`
- Containers are ephemeral - data not in volumes or bind mounts vanishes on rebuild
- Template-generated config ≠ persistent secrets

**Consequences:**
- Every container rebuild requires re-authentication
- Langfuse API keys lost (currently in `settings.local.json`)
- Project-specific settings lost
- Hook configurations lost

**Prevention:**
1. **BEFORE removing bind mount:**
   - Create `secrets.json.template` with placeholder values
   - Document secret hydration process in install script
   - Add `secrets.json` to `.gitignore` (check: already done for `.env`)
   - Add `config.json` to git (non-secret project defaults)

2. **Install script pattern:**
   ```bash
   # Check for secrets file
   if [ ! -f "$CLAUDE_CONFIG_DIR/secrets.json" ]; then
     echo "⚠️  No secrets.json found. Creating from template..."
     cp "$CLAUDE_CONFIG_DIR/secrets.json.template" "$CLAUDE_CONFIG_DIR/secrets.json"
     echo "❌ SETUP REQUIRED: Edit $CLAUDE_CONFIG_DIR/secrets.json with your credentials"
     exit 1  # Fail loudly, don't silently continue with invalid config
   fi
   ```

3. **Use Docker named volumes for persistent data:**
   ```json
   "mounts": [
     "source=claude-code-secrets-${devcontainerId},target=/home/node/.claude/secrets,type=volume"
   ]
   ```

**Detection:**
- Warning sign: Container rebuild prompts for Claude Code login
- Warning sign: Langfuse traces stop appearing after rebuild
- Warning sign: GSD commands fail with "config not found"

**Phase mapping:** Phase 1 (Config Migration) must solve this BEFORE removing bind mount.

---

### Pitfall 2: Hard-Coded Path References in Aliases and Scripts

**What goes wrong:** Scripts contain hard-coded paths to `claudehome/` that break when directory structure changes. Aliases in Dockerfile (lines 134-137) and scripts reference `/workspace/claudehome` directly.

**Why it happens:**
- Convenience paths (claudey/claudeyr aliases) bake in directory structure
- Scripts use relative paths from assumed locations
- No indirection layer (env vars) between logical locations and physical paths

**Consequences:**
- Aliases broken: `claudey` and `claudeyr` stop working
- Scripts fail: `setup-network-checks.sh` references `claudehome/langfuse-local`
- Documentation becomes stale immediately
- Incremental refactoring impossible (can't do add-then-wire-then-delete safely)

**Prevention:**
1. **Environment variable indirection:**
   ```bash
   # In devcontainer.json containerEnv
   "LANGFUSE_STACK_DIR": "/workspace/infra/langfuse",
   "CLAUDE_WORKSPACE": "/workspace"
   ```

2. **Alias refactoring pattern:**
   ```bash
   # BEFORE (brittle)
   alias claudey='cd /workspace/claudehome && claude'

   # AFTER (flexible)
   alias claudey='cd ${CLAUDE_WORKSPACE:-/workspace} && claude'
   ```

3. **Script path resolution:**
   ```bash
   # BEFORE (assumes structure)
   cd /workspace/claudehome/langfuse-local

   # AFTER (discovers structure)
   LANGFUSE_DIR="${LANGFUSE_STACK_DIR:-/workspace/infra/langfuse}"
   if [ ! -d "$LANGFUSE_DIR" ]; then
     echo "❌ Langfuse directory not found: $LANGFUSE_DIR"
     exit 1
   fi
   cd "$LANGFUSE_DIR"
   ```

**Detection:**
- Grep for hard-coded paths: `grep -r "/workspace/claudehome" .devcontainer/`
- Check aliases: Source `.bashrc`/`.zshrc` and test `claudey` command
- Test from non-root working directories: `cd gitprojects/adventure-alerts && mcp-setup`

**Phase mapping:** Phase 0 (Preparation) - add env vars, update scripts BEFORE moving files.

---

### Pitfall 3: GSD Framework Can't Find `.planning/` From Subdirectories

**What goes wrong:** GSD commands fail when Claude Code sessions launch from `gitprojects/*/` subdirectories because framework looks for `.planning/` in current working directory, not repository root.

**Why it happens:**
- GSD assumes `.planning/` is in current directory or one level up
- Git repository root ≠ Claude Code working directory
- No upward directory traversal to find `.planning/`

**Consequences:**
- `/gsd:*` commands fail in subdirectory projects
- Users forced to `cd /workspace` before running GSD commands
- Breaks workflow isolation (adventure-alerts project can't be self-contained)

**Prevention:**
1. **Git root detection in GSD:**
   ```bash
   # Find .planning by walking up to git root
   find_planning_dir() {
     local current="$PWD"
     while [ "$current" != "/" ]; do
       if [ -f "$current/.planning/PROJECT.md" ]; then
         echo "$current/.planning"
         return 0
       fi
       if [ -d "$current/.git" ]; then
         # At git root, check here
         if [ -f "$current/.planning/PROJECT.md" ]; then
           echo "$current/.planning"
           return 0
         fi
         # Not found
         return 1
       fi
       current="$(dirname "$current")"
     done
     return 1
   }
   ```

2. **Environment variable fallback:**
   ```bash
   PLANNING_DIR="${GSD_PLANNING_DIR:-$(find_planning_dir)}"
   ```

3. **Validate during install:**
   ```bash
   # In init-gsd.sh
   echo "Testing .planning discovery from subdirectory..."
   cd /workspace/gitprojects/adventure-alerts 2>/dev/null || true
   if ! gsd --check-config; then
     echo "⚠️  Warning: GSD may not work from subdirectories"
   fi
   ```

**Detection:**
- Test: `cd /workspace/gitprojects/adventure-alerts && gsd --version`
- Expected: Finds config
- Actual (broken): "Config not found"

**Phase mapping:** Phase 2 (Path Resolution) - fix GSD discovery before redistributing `.planning/` content.

---

### Pitfall 4: Non-Idempotent Install Scripts Creating Duplicate Entries

**What goes wrong:** `init-gsd.sh` and `mcp-setup` run on every container start (`postStartCommand`). Scripts that append to files or re-install on every run create duplicate configurations.

**Why it happens:**
- `postStartCommand` runs every time VS Code reconnects to container
- Scripts don't check if work already done
- Appending to shell configs (`.bashrc`) without duplicate detection

**Consequences:**
- Shell startup slows down (repeated alias definitions)
- Config files grow unbounded
- npm global installs re-run unnecessarily
- Race conditions if multiple VS Code windows connect simultaneously

**Prevention:**
1. **Idempotency guards:**
   ```bash
   # Check before action
   if grep -q "alias claudey=" ~/.bashrc; then
     echo "Aliases already configured"
   else
     echo "alias claudey='...'" >> ~/.bashrc
   fi
   ```

2. **State markers:**
   ```bash
   STATE_FILE="/home/node/.local/state/gsd-initialized"
   if [ -f "$STATE_FILE" ]; then
     echo "GSD already initialized (marker: $STATE_FILE)"
     exit 0
   fi
   # ... do initialization ...
   mkdir -p "$(dirname "$STATE_FILE")"
   touch "$STATE_FILE"
   ```

3. **Separate postCreate vs postStart:**
   ```json
   // Run once on container create
   "postCreateCommand": "setup-container.sh",
   // Run on every start (lightweight checks only)
   "postStartCommand": "init-firewall.sh && check-services.sh"
   ```

**Detection:**
- Count alias definitions: `grep -c "alias claudey" ~/.bashrc` (should be 1)
- Check npm list: `npm list -g --depth=0 | grep -c get-shit-done-cc` (should be 1)
- Monitor script execution time: If `init-gsd.sh` takes >5s on restart, likely re-running work

**Phase mapping:** Phase 1 (Config Migration) - make all install scripts idempotent before adding config generation logic.

---

### Pitfall 5: Commit Ordering Breaks Buildability

**What goes wrong:** Refactoring commits delete old structure before new structure is wired, breaking `devcontainer.json` references and making intermediate commits unbuildable.

**Why it happens:**
- "Delete-then-add" approach breaks containers between commits
- Path references in multiple files (Dockerfile, devcontainer.json, shell scripts) update asynchronously
- Git bisect becomes unusable
- CI/CD fails on intermediate commits

**Consequences:**
- Can't roll back to specific commit safely
- Can't bisect bugs introduced during refactor
- Team members pulling mid-refactor get broken containers
- Lost trust in commit history

**Prevention:**
1. **Add-Wire-Delete ordering:**
   ```
   Commit 1: Add new structure (infra/, new env vars)
   Commit 2: Update references to use env vars
   Commit 3: Test both old and new paths work
   Commit 4: Remove old structure (claudehome/)
   ```

2. **Dual-path support during transition:**
   ```bash
   # Support both locations during migration
   if [ -d "/workspace/infra/langfuse" ]; then
     LANGFUSE_DIR="/workspace/infra/langfuse"
   elif [ -d "/workspace/claudehome/langfuse-local" ]; then
     LANGFUSE_DIR="/workspace/claudehome/langfuse-local"
     echo "⚠️  Using deprecated path. Update to /workspace/infra/langfuse"
   else
     echo "❌ Langfuse not found"
     exit 1
   fi
   ```

3. **Buildability smoke test:**
   ```bash
   # Before each commit
   git add . && git commit -m "..."
   docker build -f .devcontainer/Dockerfile .
   # If build fails, fix before pushing
   ```

**Detection:**
- Warning sign: Dockerfile references path that doesn't exist in same commit
- Warning sign: Script errors on container rebuild after checkout
- Test: `git log --oneline | while read commit; do git checkout $commit && rebuild && test || echo "BROKEN: $commit"; done`

**Phase mapping:** Phase 0 (Preparation) - establish commit ordering strategy before starting structural changes.

---

## Moderate Pitfalls

These cause confusion, debugging time, or minor breakage but don't require full rewrites.

### Pitfall 6: WSL2 Path Translation Issues in Bind Mounts

**What goes wrong:** Devcontainer.json uses `${localEnv:USERPROFILE}/.claude` which translates to Windows path (`C:\Users\sam\...`) but Docker on WSL2 expects `/mnt/c/Users/sam/...` or WSL2 native paths.

**Why it happens:**
- Docker Desktop on Windows runs Docker daemon in WSL2
- Environment variables from Windows shell get passed through
- Path translation is implicit and version-dependent

**Consequences:**
- Bind mount silently creates empty directory instead of mounting host directory
- Config appears to work but doesn't persist across Docker restarts
- Different behavior on Docker Desktop versions

**Prevention:**
- Use WSL2-native paths: `source=/home/user/.claude` (assumes WSL2 file location)
- OR verify path translation: Add init script that checks bind mount actually contains expected files
- Document expected host setup: "Claude Code config must be in WSL2 filesystem at /home/$USER/.claude"

**Detection:**
- Check mount: `mount | grep .claude` should show source path
- Test persistence: Create file in container `.claude/`, restart Docker Desktop, check if file persists

**Phase mapping:** Phase 1 (Config Migration) - validate path translation when switching from bind mount to volume.

---

### Pitfall 7: Secrets in Environment Variables Visible in Process Listings

**What goes wrong:** `devcontainer.json` `containerEnv` sets `LANGFUSE_SECRET_KEY` directly, making it visible in `ps aux` output and container inspect.

**Why it happens:**
- Convenience over security
- Environment variables seem "safe" because they're not in git
- Don't realize container metadata is accessible to all processes

**Consequences:**
- Secrets visible to any process in container
- Logged in container metadata
- Exposed in Docker inspect output
- Harder to rotate secrets (requires rebuild)

**Prevention:**
1. **Use secrets files instead:**
   ```json
   // devcontainer.json - NO secrets
   "containerEnv": {
     "LANGFUSE_SECRETS_FILE": "/home/node/.claude/secrets.json"
   }
   ```

2. **Load secrets at runtime:**
   ```bash
   # In application startup
   if [ -f "$LANGFUSE_SECRETS_FILE" ]; then
     export LANGFUSE_SECRET_KEY=$(jq -r '.langfuse.secretKey' "$LANGFUSE_SECRETS_FILE")
   fi
   ```

3. **Validate secrets not in env:**
   ```bash
   # Safety check
   if env | grep -i "secret\|password\|key" | grep -v "_FILE="; then
     echo "⚠️  Secrets detected in environment variables"
   fi
   ```

**Detection:**
- Check: `docker inspect <container> | grep -i secret`
- Check: `env | grep -i secret` inside container

**Phase mapping:** Phase 1 (Config Migration) - move secrets from containerEnv to secrets.json.

---

### Pitfall 8: Generated Config Files Committed to Git

**What goes wrong:** `.mcp.json` is generated by `mcp-setup` on container start but accidentally gets committed, causing merge conflicts and stale config.

**Why it happens:**
- File appears in workspace root
- Looks like a config file that should be versioned
- Not in `.gitignore` initially (added later)

**Consequences:**
- Merge conflicts when multiple developers have different gateway URLs
- Stale config overrides generated config
- Git status always dirty

**Prevention:**
1. **Defensive .gitignore pattern:**
   ```gitignore
   # Generated configs (MUST be regenerated per-environment)
   .mcp.json
   **/*.generated.json
   ```

2. **Template approach:**
   ```
   Commit:  .mcp.json.template
   Generate: .mcp.json (gitignored)
   Script:   mcp-setup generates from template
   ```

3. **Validate in CI:**
   ```bash
   # Pre-commit hook
   if git diff --cached --name-only | grep -q ".mcp.json"; then
     echo "❌ .mcp.json should not be committed (generated file)"
     exit 1
   fi
   ```

**Detection:**
- Check: `git status` should never show `.mcp.json` as modified
- Check: `.gitignore` contains pattern for generated files

**Phase mapping:** Phase 0 (Preparation) - audit all generated files, ensure .gitignore complete.

---

## Minor Pitfalls

These cause small annoyances or cosmetic issues.

### Pitfall 9: Shell Aliases Not Available in Non-Interactive Shells

**What goes wrong:** Aliases like `claudey` work in interactive terminal but fail in scripts or `postStartCommand`.

**Why it happens:**
- `.bashrc` and `.zshrc` only sourced for interactive shells
- Aliases are shell-specific, not inherited by child processes
- Scripts often run in `/bin/sh` not `/bin/bash`

**Consequences:**
- Can't use `claudey` in automation
- Documentation says "run claudey" but scripts must use full command
- Inconsistent UX between manual and automated workflows

**Prevention:**
1. **Functions instead of aliases:**
   ```bash
   # Functions work in scripts
   claudey() {
     cd "${CLAUDE_WORKSPACE:-/workspace}" && claude --dangerously-skip-permissions "$@"
   }
   export -f claudey  # Make available to subshells
   ```

2. **PATH-based commands:**
   ```bash
   # Create /usr/local/bin/claudey
   #!/bin/bash
   cd "${CLAUDE_WORKSPACE:-/workspace}" && claude --dangerously-skip-permissions "$@"
   ```

3. **Document shell requirements:**
   ```
   # Aliases only work in interactive bash/zsh
   # For scripts, use: cd /workspace && claude
   ```

**Detection:**
- Test: `bash -c "claudey --version"` (non-interactive shell)
- Expected: Works
- Actual (broken): Command not found

**Phase mapping:** Phase 0 (Preparation) - convert critical aliases to functions or PATH commands.

---

### Pitfall 10: Firewall Script Runs Before Docker Socket Permissions Fixed

**What goes wrong:** `postStartCommand` runs `init-firewall.sh` before `setup-container.sh` has run `chmod 666 /var/run/docker.sock`, causing permission errors.

**Why it happens:**
- `postCreateCommand` runs once (setup-container.sh)
- `postStartCommand` runs every start (init-firewall.sh first)
- Race condition on first container start

**Consequences:**
- Firewall setup fails on initial container create
- Error message confusing ("Permission denied" on docker.sock)
- Requires manual restart to fix

**Prevention:**
1. **Correct command ordering:**
   ```json
   "postCreateCommand": "bash .devcontainer/setup-container.sh",
   "postStartCommand": "bash .devcontainer/init-firewall.sh && ..."
   ```

2. **Defensive permission check:**
   ```bash
   # In init-firewall.sh
   if [ ! -w /var/run/docker.sock ]; then
     echo "⚠️  Waiting for docker.sock permissions..."
     for i in {1..10}; do
       sleep 1
       if [ -w /var/run/docker.sock ]; then
         break
       fi
     done
   fi
   ```

3. **Inline permission fix:**
   ```json
   "postStartCommand": "sudo chmod 666 /var/run/docker.sock && sudo /usr/local/bin/init-firewall.sh && ..."
   ```

**Detection:**
- Check container logs: Look for permission errors in postStartCommand
- Test: Fresh container create (delete container, rebuild)

**Phase mapping:** Phase 0 (Preparation) - verify command execution order is correct.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Directory dissolution (claudehome/) | Path references in 10+ files break simultaneously | Create reference inventory first: `grep -r "claudehome" .devcontainer/ claudehome/` |
| Bind mount removal (~/.claude) | Auth tokens lost on rebuild | Implement secrets.json + volume strategy before removing mount |
| Config generation (mcp-setup, init-gsd) | Non-idempotent scripts run on every start | Add state markers and duplicate detection |
| Skills redistribution | Import paths in agent configs break | Update skills before moving files, test with grep |
| Langfuse path change | Scripts hard-coded to claudehome/langfuse-local/ | Add LANGFUSE_STACK_DIR env var first |
| .planning/ discovery | GSD can't find config from gitprojects/ subdirs | Fix GSD upward traversal before testing from subdirs |

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: "Works on My Machine" Testing

**What it looks like:**
- Test refactor only from cached container layers
- Don't test fresh container create from scratch
- Don't test from different working directories

**Why it's bad:**
- Cached layers hide missing dependencies
- Fresh create reveals ordering bugs
- Different working dirs reveal hard-coded paths

**Do instead:**
```bash
# Force fresh build
docker compose down -v
docker system prune -f
# Rebuild from scratch
# Test from multiple starting directories
```

---

### Anti-Pattern 2: Silent Fallbacks

**What it looks like:**
```bash
# BAD: Silent fallback to broken state
CONFIG_FILE="${CUSTOM_CONFIG:-/dev/null}"
cat "$CONFIG_FILE" || true  # Continues with empty config
```

**Why it's bad:**
- Errors hidden until much later
- User doesn't know config missing
- Debugging becomes archaeological exercise

**Do instead:**
```bash
# GOOD: Fail loudly and early
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ ERROR: Config not found: $CONFIG_FILE"
  echo "Expected location: ..."
  exit 1
fi
```

---

### Anti-Pattern 3: Mega-Commit Refactors

**What it looks like:**
- Single commit: "Refactor devcontainer structure"
- 50+ files changed
- Multiple concerns mixed (path changes + secret handling + feature adds)

**Why it's bad:**
- Can't bisect bugs
- Can't review atomically
- Can't roll back partially

**Do instead:**
- Commit per logical change
- Each commit builds and runs
- Group related changes: "Add env vars" → "Update scripts to use env vars" → "Remove old paths"

---

## Sources

**Confidence Assessment:**
- **Training Data (MEDIUM confidence):** Devcontainer patterns, Docker best practices, shell scripting pitfalls are well-established in training data (pre-2025)
- **Codebase Analysis (HIGH confidence):** Specific pitfalls identified by reading actual `.devcontainer/`, scripts, and current structure
- **WebSearch (UNAVAILABLE):** Could not verify 2026-specific devcontainer changes or recent VS Code updates

**Verification recommended:**
- Check VS Code devcontainer.json schema for new features (official docs)
- Verify Docker Desktop WSL2 integration behavior (official docs)
- Validate GSD framework path discovery implementation (source code)

**Limitations:**
- No access to official devcontainer spec updates from 2025-2026
- WSL2 path translation behavior may have changed in recent Docker Desktop versions
- GSD framework internals not verified (assumed standard path resolution)

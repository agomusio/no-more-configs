# Codebase Concerns

**Analysis Date:** 2026-02-16

## Known Issues (From README)

### 1. Claude Code Edit Tool File Freshness Check
- **Issue:** Edit tool throws `ENOENT: no such file or directory` on files that exist
- **Files:** Claude Code (external) affects `/workspace` operations
- **Impact:** Intermittent write failures when using the Edit tool on existing files; may require retry
- **Cause:** WSL2 bind mount (C:\ → 9P → container) causes stale file metadata; Edit tool's freshness check mismatches mtime
- **Workaround:** Re-read file + retry edit operation (usually succeeds on second attempt)
- **Status:** Known limitation; likely resolved in future Claude Code update

### 2. Dev Container Lifecycle Terminal Closes Early
- **Issue:** VS Code dismisses postCreate/postStart terminal before output can be read
- **Files:** `.devcontainer/devcontainer.json`, `.devcontainer/*.sh` initialization scripts
- **Impact:** User cannot read script output during container build; logs are lost
- **Workaround:** Use `slc` / `sls` aliases to view saved logs from `/tmp/devcontainer-logs/`
- **Status:** Known limitation; workaround in place

---

## Tech Debt

### 1. Shell Script Error Handling in Install Script
- **Issue:** Large bash script (`831` lines) with many moving parts (plugins, MCP servers, GSD install, settings hydration)
- **Files:** `/.devcontainer/install-agent-config.sh`
- **Impact:** Complex error states with multiple points of failure; error messages scattered throughout; recovery not always clear
- **Specific concerns:**
  - Line 737: GSD installation via `npx` can fail silently; no retry logic
  - Line 717-727: Unresolved `{{PLACEHOLDER}}` tokens are replaced with empty strings (non-blocking but silent)
  - Lines 390-416: GSD-protected directory conflicts skip plugins without atomic transaction; partial state possible
  - Token hydration uses `jq walk` (line 649-652) which may fail on special characters; errors caught but logged as warning only
- **Fix approach:**
  - Add structured error logging with unique error codes (ERR-001, ERR-002, etc.)
  - Implement atomic transaction pattern for plugin installations (all-or-nothing per plugin)
  - Retry logic for external commands (GSD install, langfuse-setup)
  - Collect and report all errors at end rather than early exit

### 2. Langfuse Hook State File Race Condition
- **Issue:** Multiple concurrent hooks can write state simultaneously; locking is implemented but may not cover all cases
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 139-156)
- **Impact:** State file corruption if multiple Claude Code sessions end simultaneously, causing duplicate traces or lost progress
- **Specific concerns:**
  - Line 146-149: File lock is held only during write; read-modify-write pattern still has window
  - Line 418-419: Reading entire transcript file into memory; large files (>100MB) cause memory spike
  - Line 437-443: Partial tail line handling doesn't prevent re-processing on next run if hook crashes
- **Fix approach:**
  - Implement read-lock before state load (line 414-415)
  - Add max file size check before reading; process in chunks if needed
  - Track processed message count, not just line number (more robust to partial writes)
  - Add lock timeout to prevent deadlock if previous hook crashes

### 3. JSON Parsing Edge Cases in Hook
- **Issue:** JSONL transcript files are parsed line-by-line with limited error recovery
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 430-443)
- **Impact:** Malformed transcript lines (not UTF-8, truncated JSON) cause skipped messages; conversation gaps may not be noticed
- **Specific concerns:**
  - No validation of message structure before processing (assumes required fields present)
  - Invalid UTF-8 in transcript causes decode error, entire message skipped silently
  - Tool ID matching (line 332) assumes structure; fails gracefully but tool results lost
- **Fix approach:**
  - Add pre-processing validation schema (check required fields, types)
  - Use strict UTF-8 decoding with error handler (replace/ignore invalid chars)
  - Log per-message validation failures with context (line #, first 100 chars)
  - Add recovery marker to catch and skip corrupted message ranges

### 4. MCP Server Hydration Token Substitution
- **Issue:** `{{TOKEN}}` placeholders in MCP configs hydrated via sed/jq; special characters in secrets break substitution
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 679, 649-652), `/.devcontainer/langfuse-setup.sh`
- **Impact:** Secrets containing `&`, `/`, `\` fail to hydrate; MCP servers fail to start with malformed config
- **Specific concerns:**
  - Line 679: `sed` substitution not escaped for regex special characters
  - Line 651: `jq gsub` is safer but slower; no length validation of secrets
  - No test of hydrated output before writing to config
- **Fix approach:**
  - Add secret validation (length, allowed characters) to langfuse-setup.sh
  - Use `jq` exclusively for all substitutions (safer than sed)
  - Validate JSON after hydration before writing (parse + pretty-print)
  - Add secrets policy: document allowed character set

### 5. Plugin Installation File Conflicts (First-Wins)
- **Issue:** When two plugins provide same file, first one alphabetically wins; second is silently skipped
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 354-388, 391-420)
- **Impact:** Plugin features silently lost; user unaware that second plugin's hooks/commands not installed
- **Specific concerns:**
  - Conflict detection warns but proceeds (line 382-383)
  - No option to merge or namespace conflicting files
  - Alphabetical order non-deterministic for users (depends on plugin naming)
- **Fix approach:**
  - Implement explicit conflict resolution policy in config.json (`"conflict_resolution": "first|error|namespace"`)
  - For hooks/commands: namespace by plugin (e.g., `pre-start-plugin-dev.sh`)
  - Add dry-run mode to show conflicts before installing
  - Error on critical conflicts (permissions, GSD-protected files) rather than warning

---

## Performance Bottlenecks

### 1. Langfuse Hook Full Transcript Scan
- **Issue:** Hook re-scans all transcript files every execution; no incremental processing optimization
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 246-280)
- **Impact:** Slow hook execution on systems with many projects/sessions; O(n) scan time grows linearly with transcript count
- **Specific concerns:**
  - Line 265-268: Reads first line of every transcript to extract session_id (stat + read for each file)
  - Line 278: Sorts all transcripts by mtime on every run
  - No caching of session ID mappings (transcript file → session_id)
- **Fix approach:**
  - Cache session ID mappings in state file (`state.json`; add `file_to_session_id: {}` dict)
  - Skip stat/read if file mtime unchanged since last run
  - Add `--incremental` flag to force full rescan if corruption suspected
  - Benchmark: document expected scan time for N projects (current: ~50ms per 100 transcripts)

### 2. Langfuse Hook Log Rotation
- **Issue:** Log file rotation (line 54-68) is naively implemented; may block hook on first execution after size exceeded
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 54-69)
- **Impact:** Hook latency spike (200-500ms) first time log exceeds 10MB; user perceives Claude Code slowdown
- **Specific concerns:**
  - Line 59-67: Rotates all backups in loop; 4 rotations = 4 rename syscalls
  - No size check before appending (line 77-78); grows unbounded if rotation fails
  - Rotation happens on every call (checked before every log write)
- **Fix approach:**
  - Check size only once per hook execution (cache `stat` result)
  - Use atomic multi-step rotation (rename current → .1, then write)
  - Add hard cap: if log > 50MB, truncate instead of rotate (safety valve)
  - Document expected log growth (~5-10MB per 100 sessions)

---

## Fragile Areas

### 1. Plugin Manifest Validation
- **Issue:** Plugin manifests (`plugin.json`) validated for syntax but not against schema; missing required fields not caught
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 314-324)
- **Impact:** Plugin loaded with missing hooks/env vars; silent no-op behavior; hard to debug
- **Specific concerns:**
  - No check that `hooks`, `env`, `mcp_servers` fields exist if declared (assumed structure)
  - Hook file paths not validated against filesystem
  - No version field; plugin compatibility not checked
- **Safe modification:**
  - Add JSON schema validation before processing manifests
  - Validate all declared files exist before installing plugin
  - Test plugin installation in isolation before applying to system
- **Test coverage:** No unit tests for plugin validation logic

### 2. Settings.json GSD Merge
- **Issue:** GSD installer modifies `settings.json` after install script generates it; merge logic not atomic
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 729-747, 750+)
- **Impact:** If GSD install partially fails, settings.json may be in corrupt state; manual recovery needed
- **Specific concerns:**
  - Line 737: GSD install via `npx` can fail; existing settings.json not backed up
  - Lines 750+: Settings enforcement happens after GSD (assume GSD left valid JSON)
  - No rollback if GSD leaves settings.json unreadable
- **Safe modification:**
  - Backup settings.json before GSD install (copy to `.backup`)
  - Validate JSON after GSD install
  - Rollback to backup if validation fails
- **Test coverage:** No test for GSD merge failure scenarios

### 3. Firewall Whitelist Domain Resolution
- **Issue:** Firewall domain whitelist resolved to IPs during container build; IP changes not detected on restart
- **Files:** `/.devcontainer/install-firewall.sh`, `/.devcontainer/init-firewall.sh`
- **Impact:** If domain's IP changes (CDN failover, DNS update), firewall blocks traffic until container rebuild
- **Specific concerns:**
  - DNS resolution happens once at build time
  - Container restart doesn't refresh IPs
  - Workaround requires running `/usr/local/bin/refresh-firewall-dns.sh` manually
- **Safe modification:**
  - Document that `refresh-firewall-dns.sh` must run after long container uptime
  - Consider cron job to refresh DNS every 6 hours
  - Add health check that verifies critical domains are reachable
- **Test coverage:** No test for stale IP scenarios

### 4. Concurrent Hook Execution
- **Issue:** If two Claude sessions end simultaneously, both hooks may execute concurrently; file locking may not be sufficient
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 139-156)
- **Impact:** State file may be overwritten; traces may duplicate or be lost
- **Specific concerns:**
  - Lock file (`langfuse_state.lock`) held only during write (line 146-149)
  - Read-modify-write pattern (line 565, 523-529) has race window
  - No process-level locking; only file-level
- **Safe modification:**
  - Hold lock for entire read-modify-write operation
  - Add lock timeout (5 seconds) to prevent deadlock
  - Use atomic append pattern instead of read-modify-write
- **Test coverage:** No concurrency tests

---

## Security Considerations

### 1. Secret Redaction in Langfuse Traces
- **Issue:** Conservative secret redaction patterns (lines 44-51) may not catch all secret formats
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (lines 44-51, 87-111)
- **Impact:** API keys, tokens, or passwords may leak to Langfuse if they don't match patterns
- **Specific concerns:**
  - Pattern for `api_key` requires 16+ chars; short keys not caught
  - Pattern for Bearer tokens requires 20+ chars; not all tokens are that long
  - Custom API formats (e.g., `Authorization: Basic base64(...)`) not matched
  - Env var names with secrets not sanitized (e.g., `STRIPE_SECRET_sk-...`)
- **Current mitigation:** `CC_LANGFUSE_REDACT=true` enables redaction (default); can be disabled with `false`
- **Recommendations:**
  - Add more permissive patterns (any string after `key:` or `token:`)
  - Implement list of known secret env var names (STRIPE_SECRET, OPENAI_API_KEY, etc.)
  - Test redaction patterns against real secret formats
  - Consider blocklist approach: redact any value matching `.*key.*`, `.*secret.*`, `.*token.*`

### 2. Sudo Access for Node User
- **Issue:** Node user has unrestricted NOPASSWD sudo for all commands
- **Files:** `/.devcontainer/Dockerfile` (line 82-83)
- **Impact:** Claude Code running as node can execute arbitrary system commands without password
- **Risk:** If Claude Code is compromised or malicious prompt injection occurs, attacker gains root access
- **Current mitigation:** Container is isolated from host; `/var/run/docker.sock` mounted allows docker access
- **Recommendations:**
  - Document that this is intentional for dev container (expected sandbox behavior)
  - Restrict sudo to specific commands only (firewall, docker, iptables)
  - Consider removing docker.sock mount unless actively needed
  - Add warning in README about security implications of docker.sock access

### 3. Secrets.json in Workspace Root
- **Issue:** `secrets.json` contains sensitive credentials (Claude auth, Langfuse keys, Postgres password)
- **Files:** `/workspace/secrets.json` (gitignored but exists in running container)
- **Impact:** If container is compromised, all credentials leaked; no encryption at rest
- **Current mitigation:** File is gitignored; secrets are in-memory only for container session
- **Recommendations:**
  - Document that secrets.json should never be committed
  - Consider encrypting secrets.json with user password (requires decryption prompt on startup)
  - Add pre-commit hook to prevent accidental commit
  - Document secrets rotation procedure (regenerate with langfuse-setup --generate-new)

### 4. Unvalidated Environment Variable Injection
- **Issue:** Plugin env vars from `config.json` and `secrets.json` injected into shell environment without validation
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 491-499, 520-545)
- **Impact:** If secrets.json is tampered, arbitrary env vars can be injected; Claude Code may use malicious values
- **Specific concerns:**
  - No whitelist of allowed env var names
  - No validation of env var values (could inject shell metacharacters)
  - Env vars not quoted in some places (line 545: `'${...}' = ...`)
- **Fix approach:**
  - Add whitelist of allowed plugin env var names in plugin.json schema
  - Validate env var values: no shell metacharacters, max length
  - Use safe quoting: always quote in JSON generation

---

## Scaling Limits

### 1. Langfuse Hook Memory Usage
- **Issue:** Hook loads entire transcript file into memory (line 418)
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py` (line 418)
- **Impact:** Very large transcript files (>100MB) cause OOM or slowdown
- **Current capacity:** Tested up to ~50MB transcript files; likely fails >200MB
- **Scaling path:**
  - Stream JSONL line-by-line instead of loading entire file
  - Keep sliding window of last N messages in memory (e.g., 1000)
  - Document max transcript size recommendation

### 2. Firewall Whitelist Domain Count
- **Issue:** Each domain adds one iptables rule; large whitelists slow netfilter processing
- **Files:** `/.devcontainer/init-firewall.sh`
- **Impact:** If >500 custom domains added, firewall rule lookup time increases linearly
- **Current capacity:** ~50 core domains + ~50 extension domains = 100 total (negligible perf impact)
- **Scaling path:**
  - Use ipset for bulk domain matching (faster than individual rules)
  - Group domains by zone (e.g., "api-providers", "cdn", "registries")
  - Consider netfilter rate limiting if many requests to unknown domains

### 3. Plugin Count at Install Time
- **Issue:** Install script iterates all plugins and checks manifests (O(n) complexity)
- **Files:** `/.devcontainer/install-agent-config.sh` (lines 280-545)
- **Impact:** If >100 plugins installed, install time grows linearly (~100ms per plugin)
- **Current capacity:** Tested up to ~15 plugins; likely linear to 100+
- **Scaling path:**
  - Parallelize independent operations (hook copy, env var merge)
  - Cache plugin manifest parsing results
  - Document install time expectations

---

## Dependencies at Risk

### 1. Langfuse Client Library
- **Risk:** `langfuse` package is external dependency; no version pinning
- **Impact:** Breaking changes in new version could break hook without warning
- **Current state:** Package installed via `pip install langfuse` (unpinned)
- **Migration plan:** Pin langfuse version in requirements.txt; test on upgrade before deploying

### 2. GSD Framework Installation
- **Risk:** GSD installed via `npx get-shit-done-cc` on every build; version not pinned
- **Impact:** Major version change could break command syntax or behavior
- **Current state:** Install script calls `npx` without version spec (line 737)
- **Migration plan:** Pin version in install script or create local copy

### 3. Claude Code CLI
- **Risk:** Claude Code updated on every container build (`ARG CLAUDE_CODE_VERSION=latest`)
- **Impact:** Major CLI changes (command removal, API changes) could break automation
- **Current state:** Dockerfile line 7: `ARG CLAUDE_CODE_VERSION=latest`
- **Migration plan:** Pin to known stable version; document breaking changes on upgrade

---

## Missing Critical Features

### 1. Hook Execution Monitoring
- **Problem:** No visibility into whether hooks are executing correctly; failures silent and unnoticed
- **Blocks:** Debugging trace gaps; users unaware of missing conversations
- **Recommendation:** Add `/nmc:hook-status` command to check hook logs and last execution time

### 2. Plugin Hot Reload
- **Problem:** Changes to plugin config or hooks require container rebuild
- **Blocks:** Rapid iteration on plugins; experimentation with new features
- **Recommendation:** Add `/nmc:reload-plugins` command to reload from disk without rebuild

### 3. Settings Migration
- **Problem:** No tooling to migrate settings.json when schema changes (e.g., new plugin fields)
- **Blocks:** Major version upgrades; users must manually merge changes
- **Recommendation:** Add migration system with `settings.json.schema.json` and upgrade script

---

## Test Coverage Gaps

### 1. Install Script Validation
- **What's not tested:** Plugin conflict resolution, GSD merge failures, unresolved token cleanup
- **Files:** `/.devcontainer/install-agent-config.sh`
- **Risk:** Regressions in install logic not caught; errors appear only on rebuild
- **Priority:** High — install failures block container startup
- **Suggestion:** Unit tests for token hydration, file conflict detection, manifest validation

### 2. Hook State Machine
- **What's not tested:** Concurrent execution, state file corruption recovery, partial write handling
- **Files:** `/workspace/agent-config/plugins/langfuse-tracing/hooks/langfuse_hook.py`
- **Risk:** Edge cases cause trace loss or duplication; unnoticed until users complain
- **Priority:** High — data loss risk
- **Suggestion:** Integration tests with simulated concurrent executions, corrupted state files

### 3. MCP Server Configuration
- **What's not tested:** Token hydration edge cases, invalid server configs, fallback behavior
- **Files:** `/.devcontainer/install-agent-config.sh` (MCP generation), `.mcp.json` templates
- **Risk:** MCP servers fail silently on invalid config; Claude Code unable to use tools
- **Priority:** Medium — user-visible but not critical
- **Suggestion:** Validation script that tests each MCP server config for valid JSON + required fields

### 4. Firewall Rules
- **What's not tested:** IP resolution accuracy, rule ordering, race conditions during startup
- **Files:** `/.devcontainer/init-firewall.sh`, `/etc/iptables/rules.v4`
- **Risk:** Domains unreachable or too permissive due to misconfiguration
- **Priority:** Medium — security and functionality both affected
- **Suggestion:** Verify connectivity test for all whitelisted domains on container start

---

*Concerns audit: 2026-02-16*

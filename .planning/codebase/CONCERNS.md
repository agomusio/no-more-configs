# Codebase Concerns

**Analysis Date:** 2026-02-10

## Tech Debt

**Docker Socket Binding - Security Risk:**
- Issue: The devcontainer binds to `/var/run/docker.sock` without restrictions, giving the container full Docker daemon access (root equivalent on the host).
- Files: `.devcontainer/devcontainer.json` (line 49)
- Impact: Any vulnerability in the container or Claude Code instance gives attacker host-level access and ability to launch containers, access other containers, steal credentials from other images.
- Fix approach: Only mount socket if Docker operations are necessary. If needed, use `docker-slim` or similar tools to delegate only specific Docker API calls, not full daemon access. Document as a security trade-off for development convenience.

**Firewall Script - Hardcoded DNS Dependencies:**
- Issue: `init-firewall.sh` resolves domain names at startup and bakes IPs into the firewall rules. DNS changes after boot won't be reflected; new services aren't automatically whitelisted.
- Files: `.devcontainer/init-firewall.sh` (lines 115-141)
- Impact: If DNS IP changes or new service domains are added, firewall blocks them silently. Debugging is slow ("why can't I reach this?"). Network operations appear to fail mysteriously.
- Fix approach: Implement dynamic DNS resolution with dnsmasq or systemd-resolved integration. Add logging to show what IPs were resolved. Consider making domain resolution idempotent (safe to re-run).

**Firewall Script - GitHub Meta API Hard Dependency:**
- Issue: `init-firewall.sh` fetches GitHub IPs from `api.github.com/meta` and fails with error if fetch fails (exit 1).
- Files: `.devcontainer/init-firewall.sh` (lines 102-107)
- Impact: If GitHub API is unreachable or rate-limited during devcontainer startup, firewall initialization fails completely, blocking all container networking.
- Fix approach: Make GitHub IP fetch optional with fallback to cached IPs. Add exponential backoff and retry. Log failure but continue with sensible defaults (allow GitHub's public IP ranges by hardcoded CIDR).

**Firewall Script - Magic IP Resolution with Silent Fallback:**
- Issue: `init-firewall.sh` attempts to resolve `host.docker.internal` but silently falls back to hardcoded 192.168.65.0/24 subnet if resolution fails.
- Files: `.devcontainer/init-firewall.sh` (lines 69-81)
- Impact: On systems where the magic IP differs from 192.168.65.0/24 (WSL2 with non-standard network config), the fallback allows wrong traffic or blocks legitimate host traffic. Silent failure means users won't know networking is misconfigured until Langfuse calls fail.
- Fix approach: Make the fallback explicit and logged. Verify the firewall rule works by testing connectivity to a known host service (Langfuse) before declaring success. Fail loudly if verification fails.

**Langfuse Hook - No Error Recovery on Timeout:**
- Issue: `langfuse_hook.py` processes the entire transcript and flushes traces synchronously. If Langfuse is slow or unresponsive, hook blocks indefinitely and then warns if it took >3min (line 550).
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 543-551)
- Impact: Slow or hanging Langfuse instance delays Claude Code's next turn. User perceives Claude as "frozen" when the hook is actually waiting. No timeout protection.
- Fix approach: Add a configurable timeout (default 10s) for `langfuse.flush()`. Implement async processing or queue traces to process later if Langfuse is unreachable. Log timeout but don't fail the hook (graceful degradation).

**Port Collision Risk - S3 Media Upload Endpoint:**
- Issue: `docker-compose.yml` line 40 references `http://localhost:9090` for S3 media uploads, but all services run in containers. This assumes the host has minio accessible on 9090, which breaks if multiple Langfuse instances or other services compete for ports.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (line 40)
- Impact: If port 9090 is in use by another service, Langfuse workers fail to upload media. Error messages are cryptic (connection refused). Multiple developers running this stack conflict.
- Fix approach: Change to internal service name: `http://minio:9000` (which works within Docker network). Remove the loopback binding assumption; services should talk via Docker network DNS, not localhost.

**Port Collision Risk - Comprehensive List:**
- Issue: All Langfuse services bind to loopback on hardcoded ports: 3030, 3052, 5433, 6379, 8124, 9000, 9090, 9091. If any are in use on host, docker compose silently fails to bind.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (lines 15, 54, 80-81, 98-99, 116, 138)
- Impact: Running multiple projects, other services, or concurrent Langfuse stacks causes port bind failures. Error messages reference the wrong service. Developers restart blindly or kill unrelated processes.
- Fix approach: Support `docker compose --profile` for test scenarios with offset ports (already provided in `docker-compose.test.yml` lines 26, 65, 91-92, etc.). Document port requirements. Consider environment variable overrides: `LANGFUSE_WEB_PORT=${LANGFUSE_WEB_PORT:-3052}`.

**Secrets in Environment Variables - No Rotation:**
- Issue: `.env` file contains 6+ critical secrets: `POSTGRES_PASSWORD`, `ENCRYPTION_KEY`, `NEXTAUTH_SECRET`, `SALT`, `CLICKHOUSE_PASSWORD`, `MINIO_ROOT_PASSWORD`, `REDIS_AUTH`.
- Files: `/workspace/claudehome/langfuse-local/.env` (present but contents not shown per policy), referenced in `.env.example`
- Impact: If `.env` is committed (even accidentally), all secrets are exposed. No rotation mechanism exists. If one developer's `.env` leaks, all instances with that secret are compromised. No audit trail for secret changes.
- Fix approach: Never commit `.env`; ensure `.gitignore` blocks it. Implement secret rotation script: `scripts/rotate-secrets.sh` to update all 6 secrets and restart services. Consider using `docker secret` or external secret manager (Vault, AWS Secrets Manager) for production.

**Langfuse Hook - No Transaction Batching:**
- Issue: `langfuse_hook.py` creates one Langfuse trace per conversation turn and calls `langfuse.flush()` once at end. If conversation has 10 turns, that's 10 network calls (or buffered as one batch). No control over batching strategy.
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 340-360, 545)
- Impact: High latency sessions with many tool calls generate many traces that could be batched. Network overhead is unnecessary. If one trace fails mid-flush, partial data is lost.
- Fix approach: Implement batched trace creation with configurable batch size. Add idempotency tokens to prevent duplicate traces on retry. Handle partial flush failures gracefully.

**MCP Integration - Docker Socket Mount in Future (Not Yet Implemented):**
- Issue: `/workspace/docs/mcp-integration-spec.md` notes that future Docker-backed MCP tools may require `/var/run/docker.sock` mounting (lines 27, 67-74). This duplicates the existing socket risk but compounds it.
- Files: `/workspace/docs/mcp-integration-spec.md` (lines 27, 67-74)
- Impact: If enabled, MCP gateway gets full Docker daemon access on top of devcontainer. Attackers can abuse MCP API to launch containers. Privilege escalation vector.
- Fix approach: Implement MCP as separate low-privilege container without socket mount for now. Only enable docker socket mount behind explicit `--profile mcp-docker-tools` flag (already in spec). Strongly document this as high-risk. Consider socket relay or filtered API proxy instead of full mount.

**Langfuse Init Credentials - Weak Default User Password:**
- Issue: `.env.example` line 41 suggests default user password is `change-me-on-first-login`. If deployer forgets to change it, Langfuse admin account is brute-forceable.
- Files: `/workspace/claudehome/langfuse-local/.env.example` (line 41), and in script validation
- Impact: Anyone with access to Langfuse web UI can guess the password and access traces from all Claude Code sessions (potentially containing API keys, prompts, sensitive data).
- Fix approach: Generate strong random password by default in `scripts/generate-env.sh`. Force password change on first login in Langfuse UI. Add NEXTAUTH rate limiting and lockout.

**Secret Redaction - Pattern-Based and Incomplete:**
- Issue: `langfuse_hook.py` applies regex-based secret redaction (lines 42-49) with patterns for API keys, tokens, passwords. This misses:
  - Base64-encoded credentials
  - Environment variable interpolations (`$SOME_KEY`)
  - Structured data (JSON with nested credentials)
  - Credentials in URLs (query params)
  - Custom or proprietary secret formats
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 42-98)
- Impact: Sensitive data leaks into Langfuse traces despite redaction effort. A Claude Code session that happens to echo a config file or API response gets partial redaction only.
- Fix approach: Implement Content Security Policy (CSP) for Langfuse: deny upload of files containing hardcoded secrets (detect via entropy or well-known patterns). Add configurable blocklist of secret keys. Implement opt-in mode where users must explicitly allow uploading of prompts/responses.

---

## Known Bugs

**Host Connectivity - Fallback IP May Be Wrong:**
- Symptoms: Langfuse unreachable after devcontainer starts, but `ping host.docker.internal` works. Error: `curl: connection refused` to `http://host.docker.internal:3052`.
- Files: `.devcontainer/init-firewall.sh` (lines 69-81), `.devcontainer/setup-container.sh` (lines 14-26)
- Trigger: Run devcontainer on WSL2 where host IP is not in 192.168.65.0/24 range (custom networks, different distros).
- Workaround: Manually test: `docker exec <container> dig +short host.docker.internal` and verify the IP. If wrong, iptables rules are blocking it. Re-run `init-firewall.sh` with debug output.

**Minio Media Upload - Hardcoded Localhost:**
- Symptoms: Langfuse worker logs: "Failed to upload media: connection refused". Media/charts don't appear in Langfuse UI, but traces are recorded.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (line 40)
- Trigger: Run services in non-standard network config or on non-Linux host (Docker Desktop on Mac, Windows).
- Workaround: Services in Docker Compose can reach each other via service name: change `http://localhost:9090` to `http://minio:9000` (the internal service name).

**Firewall Initialization - May Block Initial Setup:**
- Symptoms: `docker compose up -d` hangs or times out. Container starts but can't reach postgres/redis.
- Files: `.devcontainer/init-firewall.sh` (lines 25-36 flush, 102-142 domain resolution)
- Trigger: First run of firewall script takes 30-60s while resolving all domains. If devcontainer doesn't have network access during init, timeouts occur.
- Workaround: Run `init-firewall.sh` after services are up: `docker compose up -d && sudo /usr/local/bin/init-firewall.sh`.

---

## Security Considerations

**Docker Daemon Access - Containers are Privileged:**
- Risk: Devcontainer and any MCP gateway have full Docker daemon access. Compromised Claude instance or Claude Code extension can:
  - Launch containers with arbitrary images (pull from malicious registries)
  - Access other containers' environment variables (may contain API keys for production systems)
  - Modify or delete volumes (data loss)
  - Inspect network traffic of other containers
- Files: `.devcontainer/devcontainer.json` (line 49), `/workspace/docs/mcp-integration-spec.md` (lines 27, 67-74)
- Current mitigation: Access is restricted to `node` user within devcontainer; host-level Docker daemon is protected by system permissions.
- Recommendations:
  1. Implement Docker API filtering: use `docker-slim` or a socket proxy to block dangerous calls (only allow specific image pulls, no container removal, no socket mount access).
  2. Use rootless Docker mode on host if possible.
  3. Restrict which images can be pulled via registry allowlist.
  4. Audit container activity: log all docker API calls from devcontainer.
  5. Never mount socket to production or untrusted containers.

**Secrets in Langfuse Traces:**
- Risk: User prompts, API responses, and tool outputs sent to Langfuse may contain:
  - API keys (OpenAI, Anthropic, AWS, etc.)
  - Database credentials
  - Internal URLs and infrastructure details
  - Customer data (PII, private info)
  - Configuration files with hardcoded secrets
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 282-360, traces stored in docker volume)
- Current mitigation: Pattern-based secret redaction (lines 42-98); Langfuse is self-hosted (not cloud); `.env` not committed to git.
- Recommendations:
  1. Implement content filtering in hook: require explicit opt-in to trace certain message types or attach a "do not trace" marker to prompts.
  2. Store traces in encrypted volume or encrypted at-rest Langfuse config.
  3. Implement Langfuse access control: only trace owner and admins can view traces (not shared by default).
  4. Regular audit of traces for leaked credentials (automated scanning).
  5. Implement trace retention policy: auto-delete old traces to limit exposure window.

**Firewall Rules - Incomplete Whitelisting:**
- Risk: Firewall blocks unlisted domains at startup but doesn't dynamically update. If user adds new external API calls later:
  - Requests silently fail (appear as network errors)
  - Debugging is slow (looks like infrastructure problem, not security)
  - Users may be tempted to disable firewall entirely (bad security posture)
- Files: `.devcontainer/init-firewall.sh` (lines 115-141)
- Current mitigation: GitHub meta API is dynamic (pulled at startup). Hardcoded domains are major services.
- Recommendations:
  1. Add dynamic domain resolution via systemd-resolved or dnsmasq caching.
  2. Log all blocked outbound connections (firewall rejection logs).
  3. Provide easy re-run mechanism: `alias firewall-refresh='sudo /usr/local/bin/init-firewall.sh'`.
  4. Implement warning when new domain is added but not in whitelist.

**Unencrypted Local Storage:**
- Risk: All Langfuse data (postgres, minio, clickhouse) stored in local Docker volumes in plaintext:
  - Traces (prompts, responses, API keys) in postgres
  - Media/exports in minio
  - Analytics data in clickhouse
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (volumes: langfuse_postgres_data, langfuse_minio_data, langfuse_clickhouse_data, langfuse_clickhouse_logs)
- Current mitigation: Volumes are on local filesystem; assumes host security is maintained.
- Recommendations:
  1. Enable encryption at rest: postgres with pgcrypto, minio with encryption policy.
  2. Restrict volume permissions: ensure only `root` and container user can access.
  3. Securely delete volumes when Langfuse is torn down: `docker volume rm langfuse_*` with secure deletion.
  4. If moving to external storage (cloud), enable encryption in transit (TLS) and at rest.

---

## Performance Bottlenecks

**Langfuse Hook - Linear Trace Processing:**
- Problem: `langfuse_hook.py` reads entire transcript, processes all turns sequentially, then creates traces one by one (lines 340-360). No parallelization or async I/O.
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 261-400, 543-558)
- Cause: Synchronous design; waits for file I/O, JSON parsing, and Langfuse API responses serially.
- Improvement path:
  1. Use async/await for file I/O and HTTP calls to Langfuse.
  2. Batch traces before sending (5-10 per flush instead of one per turn).
  3. Process multiple conversation turns in parallel (if independent).
  4. Add trace caching: skip re-processing old turns if state file says they're already sent.

**Firewall Initialization - Synchronous DNS Resolution:**
- Problem: `init-firewall.sh` resolves each domain sequentially with `dig` (lines 115-141). For ~15 domains, this takes 10-30s (1-2s per domain). Blocks devcontainer startup.
- Files: `.devcontainer/init-firewall.sh` (lines 115-141)
- Cause: Serial execution of curl, dig, and iptables commands. No parallelization.
- Improvement path:
  1. Resolve domains in parallel: `... | xargs -P 10 dig` for 10 parallel jobs.
  2. Pre-cache resolved IPs: store in `/etc/hosts.allow` or ipset file, reuse if fresh (< 1 hour old).
  3. Make domain list configurable: users can trim domains they don't need.
  4. Move firewall setup to background task, allow container to start with permissive rules initially.

**Langfuse Database Queries - No Query Optimization:**
- Problem: Langfuse clickhouse stores raw traces without aggregation. Analytics queries over large trace volumes (thousands of turns) may scan entire dataset.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (clickhouse service)
- Cause: Langfuse is general-purpose; no indexing strategy for Claude Code specific queries.
- Improvement path:
  1. Add materialized views in ClickHouse for common queries (traces per project, tools per turn, session stats).
  2. Implement trace sampling: store 100% for recent (< 1 day), 10% for older data.
  3. Archive old traces to cheaper storage (minio cold tier).

---

## Fragile Areas

**Docker Compose Service Dependencies - Ordering Issues:**
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (lines 5-13 depends_on)
- Why fragile: Langfuse web and worker depend on postgres, minio, redis, clickhouse being "healthy", but health checks can be flakey:
  - Postgres `pg_isready` may pass before schema is initialized
  - ClickHouse HTTP ping works before shards are ready
  - Redis ping works before maxmemory policy is applied
  - Minio is ready before buckets are created
- Safe modification:
  1. Increase health check retries: `retries: 20` instead of 10 (lines 86, 107, 131).
  2. Add post-startup hooks in Langfuse to verify schema migrations are complete.
  3. Test end-to-end: `curl http://localhost:3052/api/public/health` waits for all deps.
- Test coverage: Integration tests should verify startup order works. `tests/test_full_integration.sh` should check this.

**Langfuse Hook - State File Consistency:**
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 112-125 state file management)
- Why fragile: Hook loads state from `~/.claude/state/langfuse_state.json`, processes transcript, updates state, and saves it. If save fails or hook is interrupted:
  - State becomes stale (traces are re-processed next time, duplicates in Langfuse)
  - Or state is lost (older turns are re-processed forever)
  - No lock mechanism: concurrent hook invocations (parallel Claude Code sessions) may corrupt state
- Safe modification:
  1. Use atomic file writes: write to temp file, then `mv` (already done implicitly, but verify).
  2. Add file locking: `fcntl.flock()` to prevent concurrent modification.
  3. Add checksum of state: detect corruption and reset to safe state.
  4. Implement state versioning: if format changes, migration logic needed.
- Test coverage: Test concurrent hook invocations; test state file corruption recovery; test state file missing (clean boot).

**Firewall Rules - Iptables State Volatility:**
- Files: `.devcontainer/init-firewall.sh` (lines 25-36, 148-154)
- Why fragile: Firewall sets iptables rules to strict DROP policy. If any rule is missing or wrong:
  - Network completely fails (can't even contact host)
  - Can't re-run script to fix (already disconnected)
  - Docker container may need full restart
  - Fallback rules (e.g., 192.168.65.0/24) are wrong on some systems
- Safe modification:
  1. Implement "safe mode": start with permissive rules, test, then lock down (atomic transition).
  2. Add timeout: revert firewall rules if not confirmed within 30s.
  3. Log all rule additions: verify each rule was applied correctly with `iptables-save`.
  4. Implement rollback: keep old rules in `/etc/firewall.bak`, restore on error.
- Test coverage: Test firewall in isolation; test on different Docker/WSL2 setups; test that host.docker.internal is actually reachable after firewall.

**Langfuse Environment Variables - No Validation:**
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` (environment sections), `.env.example`
- Why fragile: Services read 20+ env vars but don't validate them at startup. If a var is missing or malformed:
  - Service may start but silently fail (e.g., bad DATABASE_URL produces silent auth errors)
  - Errors appear downstream (Langfuse web can't connect to worker, looks like network issue)
  - Hard to debug: no validation error message at startup
- Safe modification:
  1. Add validation script: `scripts/validate-env.sh` checks all required vars are set and non-empty.
  2. Run validation before `docker compose up`: source `.env`, then check each var.
  3. Add semantic validation: try connecting to postgres with DATABASE_URL before starting services.
  4. Add startup healthchecks: Langfuse web should verify it can reach all deps before reporting healthy.
- Test coverage: Test with missing env vars; test with invalid values (bad DB URL, bad passwords).

---

## Scaling Limits

**Single Langfuse Instance - No Horizontal Scaling:**
- Current capacity: All services (postgres, minio, redis, clickhouse) run as single instances. Can handle ~100-1000 traces/day depending on trace size and query complexity.
- Limit: When traces exceed database capacity or query latency becomes unacceptable (> 5s to view traces).
- Scaling path:
  1. Read replicas: add postgres read replicas for scaling read queries.
  2. ClickHouse sharding: configure clickhouse cluster (current config has CLICKHOUSE_CLUSTER_ENABLED=false).
  3. Redis clustering: switch to Redis Cluster for distributed caching.
  4. Langfuse workers: run multiple langfuse-worker instances behind load balancer.
  5. Timeline: implement in phases; start with read replicas, then sharding.

**Docker Volume Storage - Finite Local Disk:**
- Current capacity: Volumes grow over time. Postgres can reach GB quickly with thousands of traces. ClickHouse is larger (analytics data). Minio stores media uploads.
- Limit: When Docker volumes consume all available disk space, services fail and crash (container I/O errors).
- Scaling path:
  1. Monitor volume usage: add disk usage alerts.
  2. Archive old traces: move traces older than N days to cheaper storage (S3, external minio).
  3. Implement trace retention: auto-delete traces older than retention policy.
  4. Use external storage: mount NFS or cloud block storage instead of local volumes.

**Memory - Langfuse Worker and Web Processes:**
- Current capacity: Devcontainer has NODE_OPTIONS max heap 4GB (`.devcontainer/devcontainer.json` line 52). Langfuse services will use available memory.
- Limit: When processing large traces or running complex analytics, Node process may OOM (out of memory).
- Scaling path:
  1. Profile memory usage: identify memory leaks or inefficient queries.
  2. Increase heap size: modify NODE_OPTIONS to 8GB or 16GB if available.
  3. Implement streaming: for large trace uploads, stream instead of loading into memory.
  4. Move heavy analytics to ClickHouse: let database do aggregations, not Node.

---

## Dependencies at Risk

**Langfuse - Community-Maintained, May Diverge:**
- Risk: Langfuse is open-source but not as widely used as commercial APM tools. Breaking changes may be introduced with minor version bumps. Custom hooks or config may not be supported in future versions.
- Impact: Version upgrades may require rewriting hook or updating docker-compose.yml.
- Migration plan:
  1. Pin Langfuse version in docker-compose.yml: change `langfuse:3` to `langfuse:3.X.Y` (specific patch).
  2. Implement integration tests: verify hook still works after Langfuse upgrade.
  3. Evaluate alternatives: PostHog, Datadog, Anthropic's native observability (when available) for fallback.

**Docker Desktop - WSL2 Dependency (Windows):**
- Risk: This setup assumes Docker Desktop on Windows with WSL2. If Docker Desktop stops being the standard (Podman, OCI, etc.), compatibility breaks.
- Impact: Devcontainer won't start on non-Docker runtimes.
- Migration plan:
  1. Abstract Docker: devcontainer.json should work with any OCI runtime via `dev-container-cli`.
  2. Support Podman: test and document Podman compatibility.
  3. Test on Linux native: ensure setup works on native Linux (no WSL2 dependency).

**Python Langfuse Client - API Stability:**
- Risk: Hook depends on `langfuse` Python package API. If package is deprecated or API changes, hook breaks.
- Impact: Claude Code sessions fail to trace to Langfuse. Users can't see observability.
- Migration plan:
  1. Pin package version: `pip install langfuse==X.Y.Z` instead of latest.
  2. Implement fallback: if Langfuse client fails to initialize, skip tracing gracefully (already done, exit 0).
  3. Monitor package releases: watch for deprecation warnings and breaking changes.

---

## Missing Critical Features

**No Distributed Tracing Across Multiple Devcontainer Instances:**
- Problem: If user runs multiple Claude Code sessions (different projects or devcontainers), traces are isolated per instance. No way to correlate traces across sessions.
- Blocks: User can't see full impact of changes across multiple projects; can't trace dependencies between projects.

**No Alerts or Anomaly Detection:**
- Problem: Langfuse stores traces but has no built-in alerting for anomalies (e.g., sudden increase in errors, slow responses, failed tool calls).
- Blocks: User discovers problems only by manually reviewing Langfuse UI. Can't proactively detect issues.

**No Cost Attribution:**
- Problem: Traces don't include token counts or cost estimates per turn. Hard to understand which operations are expensive.
- Blocks: User can't optimize for cost; doesn't know if tool calls are expensive or cheap.

**No Trace Filtering or Search by Project/Model/Tool:**
- Problem: Langfuse UI is generic. No Claude Code-specific views (e.g., "show me all traces where tool X failed").
- Blocks: Debugging specific issues is slow; user must manually parse traces.

---

## Test Coverage Gaps

**Firewall Initialization - No Automated Tests:**
- What's not tested: `init-firewall.sh` is untested. No validation that rules are correct, that host.docker.internal is reachable, or that blocked domains actually fail.
- Files: `.devcontainer/init-firewall.sh`
- Risk: Firewall changes break silently. User won't notice until Langfuse calls fail in a session. Debugging is slow.
- Priority: High - firewall is critical infrastructure and touches all network operations.

**Langfuse Hook - No Concurrent Invocation Tests:**
- What's not tested: Hook state file management under concurrent load (e.g., multiple Claude Code sessions running in parallel). No test for race conditions or state corruption.
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py`
- Risk: State file is corrupted in concurrent scenarios, leading to duplicate traces or lost sessions.
- Priority: High - concurrent sessions are common use case.

**Docker Compose - No Integration Tests:**
- What's not tested: Startup sequence verification (services start in correct order), health checks are correct, all env vars are validated before services start.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml` and test files
- Risk: Hidden startup failures (e.g., postgres health check passes before schema migrations complete) cause flaky tests and user confusion.
- Priority: High - startup is critical path.

**Secret Redaction - No Coverage for Real Secrets:**
- What's not tested: Secret redaction patterns don't cover real-world secrets used by Claude Code (Anthropic keys, AWS keys, GitHub tokens, etc.). No tests that actual redaction works end-to-end.
- Files: `/workspace/claudehome/langfuse-local/hooks/langfuse_hook.py` (lines 42-98)
- Risk: Secrets leak into Langfuse despite redaction. User accidentally shares Langfuse link, exposing API keys.
- Priority: Critical - security issue.

**Port Collision - No Detection or Recovery:**
- What's not tested: Verify that services can't bind to same port, or handle port bind failures gracefully. No test for multiple Langfuse instances running simultaneously.
- Files: `/workspace/claudehome/langfuse-local/docker-compose.yml`
- Risk: Port conflicts silently prevent services from starting. User is left with partial Langfuse stack and confusing errors.
- Priority: Medium - affects multi-user/multi-project scenarios.

---

*Concerns audit: 2026-02-10*

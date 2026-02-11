# Pitfalls Research

**Domain:** MCP Gateway Integration in Docker Devcontainers
**Researched:** 2026-02-10
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Volume Path Mismatch (Sibling Container Pattern)

**What goes wrong:**
The MCP gateway container and devcontainer both mount the workspace, but at different host paths, causing the filesystem MCP server to reference a completely different directory tree than what the devcontainer sees. Files appear missing or operations fail silently.

**Why it happens:**
Docker-outside-of-Docker means the MCP gateway is a *sibling* container to the devcontainer, not a child. When you reference `../..` from inside the devcontainer, that's a container filesystem path. When the MCP gateway mounts `${MCP_WORKSPACE_BIND}`, it must resolve to a *host daemon-visible* absolute path. Developers often use relative paths that resolve correctly inside the devcontainer but incorrectly on the host.

**How to avoid:**
1. Set `MCP_WORKSPACE_BIND` to the *host daemon-visible* absolute path of the workspace root
2. Test volume mount correctness: `docker exec docker-mcp-gateway ls -la /workspace | head`
3. Verify path consistency: the devcontainer's `/workspace` and gateway's `/workspace` must point to the same host directory
4. Document the host path mapping explicitly in `.env` files, not compose file comments

**Warning signs:**
- `docker exec docker-mcp-gateway ls /workspace` shows empty or unexpected directory structure
- MCP filesystem operations succeed but changes don't appear in devcontainer
- File paths in MCP responses reference non-existent directories
- Different file counts between `ls /workspace` in devcontainer vs. gateway container

**Phase to address:**
Phase 1 (Infrastructure Setup) — Mount configuration must be correct before any MCP server testing begins

---

### Pitfall 2: Firewall Rule Bypass (iptables DOCKER-USER Chain)

**What goes wrong:**
The MCP gateway port (8811) is accessible from external networks despite iptables INPUT rules blocking it, because Docker's published ports bypass the INPUT chain entirely. Security policy is silently violated.

**Why it happens:**
Docker modifies iptables with higher precedence than user rules. Port publishing creates rules in the DOCKER chain that run before INPUT chain. Developers test with `iptables -L INPUT` and assume their whitelist is enforced, but Docker's FORWARD chain allows traffic through. The existing iptables firewall is domain/port whitelisting; adding a new port requires DOCKER-USER chain rules, not just INPUT rules.

**How to avoid:**
1. Bind MCP gateway to loopback only: `127.0.0.1:8811:8811` (not `0.0.0.0:8811:8811`)
2. Add explicit DOCKER-USER chain rules if broader access needed:
   ```bash
   iptables -I DOCKER-USER -p tcp --dport 8811 ! -s 172.16.0.0/12 -j DROP
   ```
3. Test external accessibility: `nmap -p 8811 <host-ip>` from different network
4. Document firewall requirements in integration spec Phase 1

**Warning signs:**
- Port 8811 appears in `nmap` scan from external host
- `iptables -L INPUT` shows DROP rule but port remains accessible
- Docker logs show connections from unexpected source IPs
- Security audit flags unapproved listening ports

**Phase to address:**
Phase 1 (Infrastructure Setup) — Security configuration must be validated before exposing any services

---

### Pitfall 3: Docker Socket Mount = Root Escalation

**What goes wrong:**
Future requirement for Docker-backed MCP tools leads to mounting `/var/run/docker.sock` into the MCP gateway container. This gives the containerized MCP server (and by extension, any AI agent with MCP access) full root-equivalent access to the host system. Container escape is trivial.

**Why it happens:**
The Docker socket owner is root, and any process with socket access can launch privileged containers, bind-mount host filesystems, or run commands as root. Developers add the socket mount to "make Docker tools work" without recognizing it eliminates container isolation. MCP servers execute arbitrary commands on behalf of AI agents, turning the gateway into a remote root shell.

**How to avoid:**
1. Default stance: **NO** Docker socket mount (Phase 1)
2. Gate socket access behind disabled-by-default compose profile:
   ```yaml
   profiles: ["mcp-docker-tools"]
   volumes:
     - /var/run/docker.sock:/var/run/docker.sock
   ```
3. Document escalation: mounting socket = host root access = requires security review
4. Implement least-privilege alternative: dedicated Docker-in-Docker sidecar with limited permissions, never full socket access
5. Audit MCP tool capabilities before enabling Docker tools

**Warning signs:**
- `/var/run/docker.sock` appears in `docker inspect docker-mcp-gateway`
- MCP server documentation requests Docker socket access without justification
- No compose profile gating socket mount
- Missing documentation of security implications

**Phase to address:**
Phase 1 (Architecture Decision) — Socket policy must be established before *any* MCP server configuration, not added "later when needed"

---

### Pitfall 4: `host.docker.internal` DNS Resolution Failure

**What goes wrong:**
The devcontainer cannot reach the MCP gateway at `http://host.docker.internal:8811` — DNS resolution fails or times out. Claude Code cannot auto-discover the gateway, manual configuration fails with connection errors.

**Why it happens:**
`host.docker.internal` is not universally available across Docker environments. It's automatically configured on Docker Desktop (Mac/Windows) but requires manual setup on Linux, especially in devcontainer scenarios. The docker-from-docker pattern (devcontainer using host daemon) can break DNS resolution because the devcontainer's network namespace differs from standard containers. Codespaces and custom networks may not include the special hostname.

**How to avoid:**
1. Test resolution early: `docker exec <devcontainer> ping -c 1 host.docker.internal`
2. Fallback to hardcoded gateway IP (typically `172.17.0.1` for default bridge):
   ```bash
   GATEWAY_IP=$(docker network inspect bridge | jq -r '.[0].IPAM.Config[0].Gateway')
   ```
3. Add manual host entry in devcontainer.json:
   ```json
   "runArgs": ["--add-host=host.docker.internal:host-gateway"]
   ```
4. Prefer explicit compose network with alias over `host.docker.internal`
5. Document both connection methods (DNS + IP fallback) in verification commands

**Warning signs:**
- `ping host.docker.internal` fails with "unknown host"
- `curl http://host.docker.internal:8811/health` hangs or connection refused
- Works on Docker Desktop but fails in Codespaces/Linux CI
- Gateway logs show no incoming connection attempts

**Phase to address:**
Phase 2 (Manual Verification) — DNS resolution must be confirmed before any client configuration

---

### Pitfall 5: Health Check Race Condition (Premature "Healthy" Status)

**What goes wrong:**
`docker compose ps` shows the MCP gateway as "healthy" but connections fail. The gateway container started but the MCP server process inside hasn't finished initialization. Requests return connection refused or incomplete responses.

**Why it happens:**
Default Docker health checks only verify the container is running, not that the application inside is ready. The MCP gateway has multi-stage startup: container starts → npx downloads packages → MCP server initializes → server listens on port. A naive health check hitting the port during package download returns success (port binding happened) but the server isn't processing requests yet. Without proper `start_period` configuration, the health check runs too early and succeeds before initialization completes.

**How to avoid:**
1. Configure health check with adequate startup buffer:
   ```yaml
   healthcheck:
     test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
     interval: 10s
     timeout: 3s
     retries: 5
     start_period: 20s  # Critical: allows initialization time
   ```
2. Implement depends_on with service_healthy condition for dependent services
3. Verify gateway responds to actual MCP protocol requests, not just HTTP health endpoint
4. Test with fresh container (no cached npm packages): `docker compose up --force-recreate`
5. Monitor startup logs for "server started" message before trusting health status

**Warning signs:**
- Health check passes but `curl http://host.docker.internal:8811/health` fails from devcontainer
- Logs show npm package download *after* health check reports success
- First few connection attempts fail then succeed after delay
- `docker compose up` reports "healthy" within 5 seconds (suspiciously fast for npx-based server)

**Phase to address:**
Phase 2 (Manual Verification) — Health check configuration must be validated during infrastructure testing

---

### Pitfall 6: Environment Variable Injection in stdio Commands

**What goes wrong:**
The `mcp.json` config includes MCP servers using stdio transport with API keys hardcoded in the command args array: `["--api-key", "sk-..."]`. These secrets leak into container logs, process listings, and git history. Shell expansion in command args causes unexpected behavior or security holes.

**Why it happens:**
MCP server configuration uses JSON arrays for command arguments, which appear safer than shell strings but still capture literal values. Developers copy examples from documentation that use placeholder values, then substitute real API keys directly into the JSON. Docker Compose doesn't perform environment variable substitution inside mounted config files (only in the compose YAML itself). The gateway runs commands via exec, not shell, so `${VARIABLE}` in args remains literal.

**How to avoid:**
1. Pass secrets via environment variables in docker-compose.yml, not mcp.json:
   ```yaml
   environment:
     - GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_TOKEN}
   ```
2. Reference env vars in MCP server commands (server must support it):
   ```json
   "args": ["--token-env", "GITHUB_PERSONAL_ACCESS_TOKEN"]
   ```
3. Mount secrets as files from host environment, not embedded in configs:
   ```yaml
   volumes:
     - ${HOME}/.config/github-token:/run/secrets/github-token:ro
   ```
4. Add `mcp/mcp.json` to `.gitignore`, commit `mcp/mcp.json.example` template
5. Scan mounted configs for leaked secrets: `docker exec docker-mcp-gateway grep -r "sk-\|ghp_" /etc/mcp/`

**Warning signs:**
- `docker inspect docker-mcp-gateway` shows API keys in process command line
- `docker logs docker-mcp-gateway` contains authentication tokens
- `git log -p` shows committed secrets in mcp.json changes
- Security scanning tools flag secrets in repository

**Phase to address:**
Phase 1 (Configuration Setup) — Secret handling pattern must be established in initial gateway configuration

---

### Pitfall 7: Port Conflict Detection Failure (Brownfield Integration)

**What goes wrong:**
`docker compose up` succeeds but the MCP gateway doesn't respond on port 8811. Another service (forgotten dev server, old container, conflicting compose stack) already bound the port. Docker silently fails to publish the port or assigns a random port instead. Client configuration points to wrong port.

**Why it happens:**
The project already has multiple port bindings (3030, 3052, 5433, 6379, 8124, 9000, 9090, 9091). Brownfield environments accumulate zombie processes and orphaned containers over time. `docker compose up` doesn't fail loudly on port conflicts if the compose file uses host-mode networking or if multiple compose projects share ports. Port 8811 might be free when *planning* but occupied when *executing* due to parallel development or stale containers from previous experiments.

**How to avoid:**
1. Pre-flight port check before compose up:
   ```bash
   netstat -tuln | grep :8811 && echo "Port 8811 already bound!" || echo "Port available"
   ```
2. Scan for port conflicts across all existing services:
   ```bash
   docker ps --format '{{.Ports}}' | grep -o '0.0.0.0:[0-9]*' | sort | uniq -c
   ```
3. Document reserved port in centralized port registry (e.g., `.env` or docs/ports.md)
4. Use Docker Compose v2 port conflict detection: update to compose v2.20+
5. Verify actual published port after startup:
   ```bash
   docker port docker-mcp-gateway 8811
   ```

**Warning signs:**
- `docker compose ps` shows container running but no port mapping listed
- `netstat -tuln | grep :8811` returns process other than docker-proxy
- Gateway accessible at unexpected port (e.g., `32768` instead of `8811`)
- `docker logs docker-mcp-gateway` shows "address already in use" buried in startup logs

**Phase to address:**
Phase 2 (Manual Verification) — Port availability must be verified during "Confirm listening endpoint" step

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Relative paths in `MCP_WORKSPACE_BIND` | Works in simple setups | Breaks in CI, multi-host, or when repo moves | Never (always use absolute paths) |
| Skipping health check `start_period` | Faster initial testing | Race conditions in production, flaky restarts | Local dev only, must fix before Phase 3 |
| Hardcoding gateway IP instead of DNS | Works immediately on Linux | Breaks on network changes, not portable | Temporary during troubleshooting, document TODO |
| Mounting `:rw` for workspace instead of `:ro` where possible | Convenient for testing write operations | Accidental file corruption from buggy MCP tools | MVP only, audit write requirements in Phase 3 |
| Using default bridge network | Simple configuration | No DNS resolution between containers, IP changes | Single-container gateways, upgrade for multi-service |
| Committing `.mcp.json` with placeholder secrets | Easy to share example config | Risk of accidental real secret commit | Only with `.example` suffix, real config in `.gitignore` |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code auto-discovery | Expect automatic connection without configuration | Must explicitly add MCP gateway via `claude mcp add --transport sse mcp-gateway http://host.docker.internal:8811` |
| Filesystem MCP server | Mounting workspace to `/projects` but configuring server for `/workspace` | Ensure mount path matches MCP server args: `"args": ["/workspace"]` and volume `- ${MCP_WORKSPACE_BIND}:/workspace:rw` |
| iptables firewall | Adding rules to INPUT chain and expecting Docker to respect them | Use DOCKER-USER chain: `iptables -I DOCKER-USER -p tcp --dport 8811 -j ACCEPT` |
| Docker socket access | Mounting socket directly when MCP server doesn't actually need Docker | Verify MCP server's actual requirements, avoid socket mount unless explicitly needed for Docker operations |
| Multiple compose projects | Assuming `docker compose up` affects only one project | Use explicit project name: `docker compose -p langfuse up` or place gateway in same compose file as Langfuse |
| Gateway health endpoint | Testing with `curl localhost:8811` from host | Use `curl http://host.docker.internal:8811` from *inside devcontainer* to match Claude Code's perspective |
| Environment variable expansion | Using `${VAR}` in mcp.json and expecting substitution | Compose only expands vars in YAML, not in mounted config files; use environment section in compose |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No MCP tool lazy-loading | Claude Code slow to start, high memory usage | Enable tool search optimization (v2.1.7+) for 85% token reduction | 10+ MCP servers or 100+ tools |
| Gateway container without resource limits | Runaway MCP server consumes all host RAM/CPU | Set compose `deploy.resources.limits`: `cpus: '1.0'`, `memory: 512M` | Complex MCP operations (e.g., large file processing) |
| Single gateway for all environments | Dev experiments pollute prod gateway state | Run separate gateway instances per environment with isolated configs | 5+ developers sharing one gateway |
| Unbounded log retention | Docker logs consume GB of disk space | Configure logging driver: `driver: "json-file"`, `max-size: "10m"`, `max-file: "3"` | After weeks of operation |
| Synchronous MCP requests without timeout | Client hangs on unresponsive MCP server | Implement request timeout in client configuration (30s default) | MCP server calls slow external APIs |
| Mounting entire home directory | `- $HOME:/host-home:ro` exposes all secrets | Mount only required subdirectories, never entire $HOME | First security audit |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Publishing gateway to `0.0.0.0` instead of `127.0.0.1` | External network access to MCP, unauthorized tool execution | Always bind to loopback: `127.0.0.1:8811:8811` |
| Storing API keys in mcp.json | Secrets leaked in git history, logs, backups | Use environment variables or mounted secret files, add mcp.json to .gitignore |
| Mounting Docker socket without compose profile gate | Permanent root-equivalent access, container escape | Gate behind disabled profile: `profiles: ["mcp-docker-tools"]` |
| `:rw` on sensitive directories | MCP tool can modify source code, configs, secrets | Use `:ro` except for explicitly writable workspace areas |
| No network segmentation | Compromised MCP gateway reaches internal services | Use Docker custom networks, firewall rules to limit gateway's network access |
| Trusting MCP server images without verification | Supply chain attack, malicious code execution | Pin image digests, verify signatures, audit Dockerfiles for official servers |
| Running gateway as root user | Privilege escalation easier if container compromised | Use `user: "1000:1000"` in compose to run as non-root (verify MCP server supports it) |
| No request rate limiting | DoS via excessive MCP requests | Implement rate limiting at gateway or reverse proxy layer |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Gateway fails silently with no diagnostic output | Developer spends hours debugging "it doesn't work" | Add verbose logging in Phase 1, expose `/logs` endpoint, clear error messages |
| No clear indicator when gateway is ready | Developer tests too early, concludes setup is broken | Health check + explicit "ready" log message, startup banner with connection URL |
| Manual port/IP configuration required | High friction, documentation drift, copy-paste errors | Document both auto-discovery and manual config, provide connection test script |
| Gateway restart loses in-flight requests | Claude Code sessions timeout mid-operation | Implement graceful shutdown with request draining (advanced Phase) |
| No visibility into which MCP servers are loaded | "Why isn't this tool available?" confusion | Add `/servers` endpoint listing active MCP servers and tool counts |
| Error messages reference container internals | "Failed to access /etc/mcp/mcp.json" meaningless to user | Map container paths to user-facing concepts in error messages |
| No validation of mcp.json syntax | Gateway fails to start with cryptic JSON parse error | Add config validation step, suggest fixes for common mistakes |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Gateway container running:** Often missing verification that `/workspace` mount points to correct host path — verify with `docker exec docker-mcp-gateway ls /workspace | head` vs `ls /workspace` in devcontainer
- [ ] **Health check passing:** Often missing adequate `start_period` — verify npx package download completes before health check succeeds
- [ ] **Port accessible from host:** Often missing test from *inside devcontainer* — verify with `curl http://host.docker.internal:8811/health` not just `curl localhost:8811`
- [ ] **Firewall allows port 8811:** Often missing DOCKER-USER chain rules — verify with external `nmap` scan, not just local `iptables -L INPUT`
- [ ] **mcp.json loaded:** Often missing validation that servers start — verify with `docker logs docker-mcp-gateway | grep "server started"` or equivalent
- [ ] **Secrets in environment variables:** Often missing .gitignore entry — verify `git status` doesn't show mcp.json with real secrets, check git history for leaks
- [ ] **Claude Code configured:** Often missing explicit `claude mcp add` command — verify `.mcp.json` exists in project root with correct gateway URL
- [ ] **Read-only mounts where appropriate:** Often missing security hardening — verify sensitive paths use `:ro` suffix in compose volumes section
- [ ] **Resource limits configured:** Often missing DoS protection — verify `docker inspect docker-mcp-gateway | jq '.[0].HostConfig.Memory'` returns non-zero value
- [ ] **Logging configured:** Often missing log rotation — verify `docker inspect docker-mcp-gateway | jq '.[0].HostConfig.LogConfig'` shows max-size/max-file limits

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Volume path mismatch | LOW | 1. Stop gateway: `docker compose stop docker-mcp-gateway` 2. Fix `MCP_WORKSPACE_BIND` in compose file to absolute host path 3. Recreate: `docker compose up -d --force-recreate docker-mcp-gateway` 4. Verify: `docker exec docker-mcp-gateway ls /workspace` |
| Firewall bypass | LOW | 1. Change compose ports to `127.0.0.1:8811:8811` 2. Recreate container 3. Verify: `nmap -p 8811 <external-ip>` should show filtered/closed 4. Add DOCKER-USER rules if broader access needed |
| Docker socket mounted | MEDIUM | 1. Remove volume mount from compose 2. Recreate container 3. Audit: review MCP tool capabilities that required socket 4. Implement alternative: dedicated Docker-in-Docker sidecar if truly needed 5. Document security decision |
| DNS resolution failure | LOW | 1. Test alternatives: gateway IP (`172.17.0.1`), bridge network DNS 2. Add `--add-host=host.docker.internal:host-gateway` to devcontainer runArgs 3. Update Claude Code config with working URL 4. Document platform-specific connection strings |
| Health check race | LOW | 1. Add `start_period: 30s` to health check config 2. Increase retries to 5 3. Recreate container 4. Verify: `docker compose ps` only shows healthy after 30s+ uptime |
| Leaked secrets | HIGH | 1. IMMEDIATELY revoke/rotate exposed API keys 2. Remove secrets from git history: `git filter-repo --path mcp/mcp.json --invert-paths` 3. Add mcp.json to .gitignore 4. Move secrets to environment variables 5. Scan for other leaks: `git log -p | grep -E "sk-\|ghp_"` |
| Port conflict | LOW | 1. Find conflicting process: `netstat -tuln | grep :8811` 2. Kill or reconfigure conflicting service 3. Restart gateway: `docker compose restart docker-mcp-gateway` 4. Verify: `docker port docker-mcp-gateway` |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Volume path mismatch | Phase 1: Infrastructure Setup | `docker exec` ls comparison between containers shows identical files |
| Firewall bypass | Phase 1: Infrastructure Setup | External nmap scan shows port closed, loopback curl succeeds |
| Docker socket mount | Phase 1: Architecture Decision | `docker inspect` shows no `/var/run/docker.sock` volume mount |
| DNS resolution failure | Phase 2: Manual Verification | Devcontainer can `curl http://host.docker.internal:8811/health` successfully |
| Health check race | Phase 2: Manual Verification | Container remains unhealthy during first 20s, then transitions to healthy |
| Secret injection | Phase 1: Configuration Setup | `git status` ignores mcp.json, `docker inspect` shows secrets in environment only |
| Port conflict | Phase 2: Manual Verification | `docker port` command shows 8811 mapped correctly, no other services on port |
| iptables DOCKER-USER rules | Phase 1: Infrastructure Setup | Firewall audit shows gateway port handled in DOCKER-USER chain |
| Claude Code discovery | Phase 3: Client Configuration | `.mcp.json` file exists with correct gateway URL, `claude mcp list` shows gateway |
| MCP server path args | Phase 2: Manual Verification | Filesystem MCP operations succeed, paths match devcontainer workspace |

## Sources

### MCP Security and Docker Best Practices
- [MCP Security: Risks, Challenges, and How to Mitigate | Docker](https://www.docker.com/blog/mcp-security-explained/)
- [MCP Security Issues Threatening AI Infrastructure | Docker](https://www.docker.com/blog/mcp-security-issues-threatening-ai-infrastructure/)
- [Docker with iptables | Docker Docs](https://docs.docker.com/engine/network/firewall-iptables/)
- [Why is Exposing the Docker Socket a Really Bad Idea? - Quarkslab's blog](https://blog.quarkslab.com/why-is-exposing-the-docker-socket-a-really-bad-idea.html)

### Volume Mount and Path Resolution
- [How to Fix "Permission Denied" Errors in Docker Volumes](https://oneuptime.com/blog/post/2026-01-24-fix-permission-denied-docker-volumes/view)
- [How to Debug Docker Volume Mount Issues](https://oneuptime.com/blog/post/2026-01-25-debug-docker-volume-mount-issues/view)
- [How to Debug Docker Compose Volume Issues](https://oneuptime.com/blog/post/2026-01-25-debug-docker-compose-volume-issues/view)
- [Docker in docker, issues with mounting a volume · GitHub](https://gist.github.com/Drowze/c07c7acc5ed42f358e82798bb488ca09)

### Networking and DNS Resolution
- [Docker-from-docker: host.docker.internel is not resolving as expected · Issue #1497](https://github.com/microsoft/vscode-dev-containers/issues/1497)
- [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/)

### Health Checks and Startup
- [How to Create Docker Compose Health Checks](https://oneuptime.com/blog/post/2026-01-30-docker-compose-health-checks/view)
- [How to Use Docker Compose depends_on with Health Checks](https://oneuptime.com/blog/post/2026-01-16-docker-compose-depends-on-healthcheck/view)
- [Control startup order - Docker Compose](https://docs.docker.com/compose/how-tos/startup-order/)

### MCP Gateway Configuration
- [MCP Gateway | Docker Docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/)
- [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp)
- [How to Run MCP Servers in Docker - Deployment Guide 2026 | Fast.io](https://fast.io/resources/mcp-server-docker/)
- [Docker MCP compatibility with vscode devcontainers · Issue #112](https://github.com/docker/mcp-gateway/issues/112)

### Port Conflicts and Brownfield Integration
- [Port conflict with multiple "host:<port range>:port" services · Issue #7188](https://github.com/docker/compose/issues/7188)
- [Restricting exposed Docker ports with iptables - Docker Community Forums](https://forums.docker.com/t/restricting-exposed-docker-ports-with-iptables/108075)

---
*Pitfalls research for: MCP Gateway Integration in Docker Devcontainers*
*Researched: 2026-02-10*

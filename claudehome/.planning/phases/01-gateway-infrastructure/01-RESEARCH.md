# Phase 1: Gateway Infrastructure - Research

**Researched:** 2026-02-10
**Domain:** Docker MCP Gateway deployment as Docker Compose sidecar service
**Confidence:** MEDIUM-HIGH

## Summary

Phase 1 establishes the foundational MCP gateway infrastructure by adding a Docker Compose service to the existing Langfuse stack. The Docker MCP Gateway (`docker/mcp-gateway:latest`) runs as a sidecar container, spawning MCP servers via stdio transport and exposing them through a unified HTTP endpoint. This research focuses on brownfield integration patterns, security-first configuration (loopback-only binding, no Docker socket by default), and path alignment between gateway and devcontainer for workspace operations.

**Critical insight:** The gateway container and devcontainer are *sibling* containers sharing the same host Docker daemon. Volume mounts must use host-daemon-visible absolute paths, not devcontainer-relative paths, to ensure both containers see identical workspace content.

**Primary recommendation:** Configure gateway with stdio transport for filesystem MCP server, bind to `127.0.0.1:8811` only, gate Docker socket access behind disabled-by-default compose profile, and use adequate `start_period` in health checks to account for npx package download delays.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **docker/mcp-gateway** | latest | MCP gateway container | Official Docker-maintained gateway with built-in stdio server lifecycle management, logging, and isolation |
| **@modelcontextprotocol/server-filesystem** | 2026.1.14 | Filesystem MCP server | Official Anthropic filesystem server, latest stable release as of Jan 2026 |
| **Docker Compose** | 2.x+ | Service orchestration | Already in use for Langfuse stack; maintains sidecar pattern |
| **npx** | (Node.js bundled) | Zero-install MCP server runner | Eliminates pre-installation; gateway spawns servers on-demand |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **wget** or **curl** | (alpine/debian) | Health check HTTP client | Gateway health endpoint verification; wget preferred for Alpine images |
| **iptables** | (host system) | Firewall enforcement | Enforce DOCKER-USER chain rules for port security |
| **Docker socket** | N/A | Container lifecycle access | ONLY when enabling `mcp-docker-tools` profile; NOT default |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| docker/mcp-gateway | IBM Context Forge (ghcr.io/ibm/mcp-context-forge) | Adds admin UI, Redis caching, federation; overkill for single-user devcontainer |
| docker/mcp-gateway | Custom stdio-to-HTTP bridge | Avoids dependency but requires maintaining protocol translation layer |
| npx (zero-install) | Pre-installed npm packages in custom image | Faster startup but requires image maintenance and version pinning |
| stdio transport | SSE/streamable-http for MCP servers | Stdio is simpler for local containerized servers; SSE for remote/cross-network only |

**Installation:**
```bash
# No installation needed for gateway image (pulled by docker compose)
# Filesystem MCP server installed at runtime via npx
# Gateway added to existing langfuse-local/docker-compose.yml
```

## Architecture Patterns

### Recommended Docker Compose Structure
```yaml
# langfuse-local/docker-compose.yml
services:
  # Existing Langfuse services...

  docker-mcp-gateway:
    image: docker/mcp-gateway:latest
    container_name: docker-mcp-gateway
    restart: unless-stopped
    ports:
      - "127.0.0.1:8811:8811"  # Loopback-only binding
    volumes:
      - ./mcp/mcp.json:/etc/mcp/mcp.json:ro
      - ${MCP_WORKSPACE_BIND}:/workspace:rw
    environment:
      # Gateway runs in container mode, not CLI mode
      # Configuration driven by mcp.json file
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s  # CRITICAL: allows npx package download
    profiles:
      - ""  # Default profile (always runs)

  # Docker socket access gated behind disabled profile
  docker-mcp-gateway-with-docker:
    extends: docker-mcp-gateway
    volumes:
      - ./mcp/mcp.json:/etc/mcp/mcp.json:ro
      - ${MCP_WORKSPACE_BIND}:/workspace:rw
      - /var/run/docker.sock:/var/run/docker.sock  # ROOT-EQUIVALENT ACCESS
    profiles:
      - mcp-docker-tools  # Disabled by default
```

### Pattern 1: Stdio MCP Server via Gateway (Filesystem Example)
**What:** Gateway spawns MCP server as child process using stdio transport
**When to use:** Local filesystem, memory, or compute-bound tools without external API dependencies
**Example:**
```json
// langfuse-local/mcp/mcp.json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem@2026.1.14",
        "/workspace"
      ],
      "env": {}
    }
  }
}
```
**Source:** [@modelcontextprotocol/server-filesystem - npm](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem)

### Pattern 2: Loopback-Only Port Binding
**What:** Bind gateway to `127.0.0.1` instead of `0.0.0.0` to prevent LAN exposure
**When to use:** ALWAYS for dev environments; localhost-only access pattern
**Why critical:** Docker bypasses iptables INPUT chain for published ports; loopback binding is the only reliable defense against external network access
**Example:**
```yaml
ports:
  - "127.0.0.1:8811:8811"  # Good: localhost only
  # NOT "8811:8811"          # Bad: exposes to 0.0.0.0
  # NOT "0.0.0.0:8811:8811"  # Bad: explicit external exposure
```
**Source:** [Port publishing and mapping | Docker Docs](https://docs.docker.com/engine/network/port-publishing/)

### Pattern 3: Workspace Mount Alignment (Sibling Container Pattern)
**What:** Gateway and devcontainer mount identical workspace paths from host
**Critical for:** Path-dependent MCP operations (filesystem server returns paths gateway container sees)
**Example:**
```yaml
# docker-compose.yml
services:
  docker-mcp-gateway:
    volumes:
      - ${MCP_WORKSPACE_BIND}:/workspace:rw

# .env (host-daemon-visible absolute path)
MCP_WORKSPACE_BIND=/home/user/projects/claudehome

# devcontainer.json (must match gateway mount point)
"workspaceFolder": "/workspace"
```
**Verification:**
```bash
# Both commands should show identical file listings
docker exec docker-mcp-gateway ls -la /workspace | head
docker exec <devcontainer-name> ls -la /workspace | head
```

### Pattern 4: Health Check with Adequate Startup Period
**What:** Health check delays 20s before counting failures to allow npx package download
**Why critical:** First container start downloads @modelcontextprotocol packages; health check during download causes premature "unhealthy" status
**Example:**
```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
  interval: 10s
  timeout: 3s
  retries: 5
  start_period: 20s  # No failures counted during first 20s
```
**Source:** [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view)

### Pattern 5: Secret Management via Environment Variables
**What:** Pass secrets to MCP servers via compose environment, not mcp.json
**Why critical:** mcp.json is often version-controlled; hardcoded secrets leak in git history
**Example:**
```yaml
# docker-compose.yml
services:
  docker-mcp-gateway:
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}  # Injected from .env

# .env (gitignored)
GITHUB_TOKEN=ghp_xxxxxxxxxxxx

# .env.example (committed)
GITHUB_TOKEN=your_github_token_here

# mcp.json references env var (server must support this)
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```
**Note:** Variable substitution in mcp.json depends on gateway implementation; verify with testing

### Anti-Patterns to Avoid

- **Mounting Docker socket by default:** Grants root-equivalent host access; use compose profile to gate this capability
- **Using relative paths in MCP_WORKSPACE_BIND:** Breaks in CI, multi-host, or when repo moves; always use absolute paths
- **Binding to 0.0.0.0:** Exposes gateway to LAN/internet; Docker bypasses firewall INPUT chain rules
- **Skipping start_period in health check:** Causes race conditions where container reports unhealthy during normal initialization
- **Hardcoding secrets in mcp.json:** Leaks credentials in version control; use environment variable references
- **Using :rw for read-only operations:** Increases attack surface; use :ro for config files and read-only workspace areas

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MCP protocol translation | Custom stdio-to-HTTP bridge | docker/mcp-gateway:latest | Official implementation handles edge cases (buffering, stderr, process lifecycle), logging, isolation |
| MCP server package management | Custom Docker image with pre-installed servers | npx zero-install pattern | Eliminates image maintenance; gateway downloads latest on first run; simplifies version updates |
| Health endpoint implementation | Custom /health route in gateway wrapper | Gateway's built-in /health endpoint | Already implemented; returns 200 OK when gateway is ready |
| Firewall rule management | Custom iptables script | Loopback binding (127.0.0.1) + DOCKER-USER chain rules | Docker bypasses INPUT chain; loopback binding is platform-agnostic solution |
| Container networking | Custom network bridge config | Docker Compose default network | Auto-creates bridge network with DNS resolution; gateway and Langfuse services share namespace |

**Key insight:** Docker MCP Gateway is purpose-built infrastructure, not a generic proxy. Custom alternatives miss critical features like stdio buffering, process supervision, and credential injection.

## Common Pitfalls

### Pitfall 1: Volume Path Mismatch (Sibling Container Pattern)
**What goes wrong:** Gateway and devcontainer mount workspace at different host paths; filesystem MCP operations reference non-existent files from devcontainer perspective
**Why it happens:** Docker-outside-of-Docker pattern means gateway is sibling, not child; `${MCP_WORKSPACE_BIND}` must be host-daemon-visible absolute path, not devcontainer-relative path
**How to avoid:**
1. Set `MCP_WORKSPACE_BIND` to absolute host path in `.env`
2. Verify both containers see identical files: `docker exec docker-mcp-gateway ls /workspace` vs `docker exec <devcontainer> ls /workspace`
3. Test file creation in one container appears in the other
**Warning signs:**
- Gateway shows empty /workspace despite devcontainer showing files
- MCP filesystem operations succeed but changes invisible in devcontainer
- Different file counts between containers

**Source:** Documented in `.planning/research/PITFALLS.md` (project-level research)

### Pitfall 2: Firewall Bypass via Docker Port Publishing
**What goes wrong:** Port 8811 accessible from external network despite iptables INPUT rules blocking it
**Why it happens:** Docker modifies iptables FORWARD chain with higher precedence than INPUT chain; published ports bypass user firewall rules unless explicitly added to DOCKER-USER chain
**How to avoid:**
1. Primary defense: Bind to `127.0.0.1:8811:8811` (loopback-only)
2. Secondary defense (if broader access needed): Add DOCKER-USER chain rules:
   ```bash
   iptables -I DOCKER-USER -p tcp --dport 8811 ! -s 172.16.0.0/12 -j DROP
   ```
3. Verify with external scan: `nmap -p 8811 <host-ip>` should show filtered/closed
**Warning signs:**
- Port 8811 appears in nmap scan from external host
- `iptables -L INPUT` shows DROP rule but port remains accessible
**Source:** [Docker with iptables | Docker Docs](https://docs.docker.com/engine/network/firewall-iptables/)

### Pitfall 3: Health Check Race Condition
**What goes wrong:** Container shows "healthy" immediately but connections fail; or shows "unhealthy" during normal startup
**Why it happens:** Gateway has multi-stage startup (container start → npx downloads packages → server initializes → port listens); default health check has no `start_period`, so failures during download count toward retry limit
**How to avoid:**
1. Always configure `start_period: 20s` (or higher for slow networks)
2. Test with clean container (no npm cache): `docker compose up --force-recreate`
3. Monitor logs for "server started" before trusting health status
**Warning signs:**
- Container transitions to healthy in <5s (suspiciously fast for npx-based server)
- First connection attempts fail, then succeed after delay
- Logs show npm package download *after* health check passes
**Source:** [Docker Compose Health Checks: An Easy-to-follow Guide | Last9](https://last9.io/blog/docker-compose-health-checks/)

### Pitfall 4: Docker Socket = Root Escalation
**What goes wrong:** Mounting `/var/run/docker.sock` grants container root-equivalent access to host; AI agent with MCP access can escape container, bind-mount host filesystems, or run privileged containers
**Why it happens:** Docker socket owner is root; any process with socket access can launch privileged containers
**How to avoid:**
1. Default: NO Docker socket mount (Phase 1 MVP)
2. Gate behind disabled-by-default compose profile: `profiles: ["mcp-docker-tools"]`
3. Document escalation: socket mount = host root access = security review required
4. Only enable when Docker-based MCP tools explicitly needed
**Warning signs:**
- `/var/run/docker.sock` appears in `docker inspect docker-mcp-gateway` without justification
- No compose profile gating socket mount
- Missing documentation of security implications
**Source:** [MCP Security: Risks, Challenges, and How to Mitigate | Docker](https://www.docker.com/blog/mcp-security-explained/)

### Pitfall 5: Port Conflict with Existing Services
**What goes wrong:** `docker compose up` succeeds but gateway doesn't respond; another service already bound port 8811
**Why it happens:** Brownfield environment with multiple port bindings (Langfuse uses 3030, 3052, 5433, 6379, 8124, 9000, 9090, 9091); zombie processes or orphaned containers may occupy port
**How to avoid:**
1. Pre-flight check before compose up:
   ```bash
   netstat -tuln | grep :8811 && echo "Port conflict!" || echo "Available"
   ```
2. Verify actual binding after startup:
   ```bash
   docker port docker-mcp-gateway 8811
   ```
3. Document reserved port in centralized registry (e.g., `.env` comment)
**Warning signs:**
- `docker compose ps` shows container running but no port mapping
- `netstat` shows port bound to different process
- Gateway logs show "address already in use"

### Pitfall 6: host.docker.internal DNS Resolution Failure
**What goes wrong:** Devcontainer cannot reach gateway at `http://host.docker.internal:8811`; DNS resolution fails or connection refused
**Why it happens:** `host.docker.internal` requires manual setup on Linux; docker-from-docker pattern can break DNS resolution in devcontainer network namespace
**How to avoid:**
1. Test resolution early: `docker exec <devcontainer> ping -c 1 host.docker.internal`
2. Add manual host entry in devcontainer runArgs if needed:
   ```json
   "runArgs": ["--add-host=host.docker.internal:host-gateway"]
   ```
3. Fallback to gateway IP: `docker network inspect bridge | jq -r '.[0].IPAM.Config[0].Gateway'`
4. Document both connection methods (DNS + IP fallback)
**Warning signs:**
- `ping host.docker.internal` fails with "unknown host"
- `curl http://host.docker.internal:8811/health` hangs
- Works on Docker Desktop but fails in Codespaces/Linux CI
**Source:** [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/)

## Code Examples

Verified patterns from official sources:

### Complete Gateway Service Configuration
```yaml
# Source: https://collabnix.com/docs/docker-mcp-gateway/using-docker-mcp-gateway-with-docker-compose-2/
# Adapted for brownfield Langfuse integration with security hardening

services:
  docker-mcp-gateway:
    image: docker/mcp-gateway:latest
    container_name: docker-mcp-gateway
    restart: unless-stopped
    ports:
      - "127.0.0.1:8811:8811"  # Loopback-only
    volumes:
      - ./mcp/mcp.json:/etc/mcp/mcp.json:ro  # Read-only config
      - ${MCP_WORKSPACE_BIND}:/workspace:rw  # Workspace access
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s
    # No Docker socket by default (security-first)
```

### Filesystem MCP Server Configuration
```json
// Source: https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem
// mcp/mcp.json

{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem@2026.1.14",
        "/workspace"
      ],
      "env": {}
    }
  }
}
```

### Environment Variable Configuration
```bash
# Source: Project security requirements (SEC-03)
# .env (gitignored)

# Workspace mount (host-daemon-visible absolute path)
MCP_WORKSPACE_BIND=/home/user/projects/claudehome

# Future: API keys for remote MCP servers
# GITHUB_TOKEN=ghp_xxxxxxxxxxxx
# SENTRY_API_KEY=xxxxxxxxxxxx
```

### Health Check Verification Commands
```bash
# Source: Docker official docs + project verification requirements
# From host (direct gateway access)
curl http://localhost:8811/health

# From devcontainer (via host.docker.internal)
curl http://host.docker.internal:8811/health

# Check actual port binding
docker port docker-mcp-gateway 8811
# Expected: 127.0.0.1:8811

# Verify workspace mount alignment
docker exec docker-mcp-gateway ls -la /workspace | head
docker exec <devcontainer-name> ls -la /workspace | head
# Should show identical file listings
```

### Firewall Rule Configuration (DOCKER-USER Chain)
```bash
# Source: https://docs.docker.com/engine/network/firewall-iptables/
# Only needed if binding to 0.0.0.0 (NOT recommended)

# Allow only Docker network range to access gateway
iptables -I DOCKER-USER -p tcp --dport 8811 -s 172.16.0.0/12 -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 8811 -j DROP

# Save rules (Debian/Ubuntu)
iptables-save > /etc/iptables/rules.v4
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SSE transport for MCP | Streamable HTTP (protocol v2026-03-26) | Q1 2026 | SSE deprecated but still supported; stdio remains preferred for local containerized servers |
| Pre-installed MCP servers in custom image | npx zero-install pattern | 2025+ | Gateway downloads packages at runtime; eliminates image maintenance |
| Global MCP client config only (~/.claude/.claude.json) | Project-scoped .mcp.json | Claude Code v2.x+ | Teams share MCP server config in version control; user approves on first use |
| Manual OAuth token management | Docker Desktop 4.37.1+ built-in token management | Dec 2024 | Auto-refresh for remote MCP servers; standalone gateway still manual |
| Port exposure to 0.0.0.0 with firewall rules | Loopback binding (127.0.0.1) | Best practice since Docker 20.10 | Eliminates firewall bypass attack vector |

**Deprecated/outdated:**
- **ghcr.io/anthropics/docker-mcp-gateway**: Image does not exist; likely documentation error (use `docker/mcp-gateway:latest`)
- **SSE transport for new deployments**: Replaced by Streamable HTTP; stdio still preferred for local
- **Host network mode for gateway**: Breaks container isolation; use bridge with explicit port bindings

## Open Questions

1. **Gateway /health endpoint implementation details**
   - What we know: Endpoint exists at `/health`, returns 200 OK when ready
   - What's unclear: Does it verify MCP servers started, or just gateway process running?
   - Recommendation: Test health check timing with `docker compose up --force-recreate`, monitor logs

2. **mcp.json schema and environment variable substitution**
   - What we know: JSON format with `mcpServers` object; Docker Compose expands ${VAR} in YAML, not mounted files
   - What's unclear: Does gateway perform env var substitution in mcp.json, or must servers handle it?
   - Recommendation: Test with placeholder `"env": {"TOKEN": "${GITHUB_TOKEN}"}`, verify in server logs

3. **Docker socket mount alternatives for MCP Docker tools**
   - What we know: Socket mount grants root-equivalent access; gated behind compose profile
   - What's unclear: Can Docker-in-Docker sidecar provide safer alternative with limited permissions?
   - Recommendation: Phase 1 MVP excludes Docker tools entirely; research alternatives in future phase

4. **Gateway health check endpoint vs MCP protocol verification**
   - What we know: /health endpoint exists; health check configured with wget/curl
   - What's unclear: Should verification test actual MCP list_tools request, not just HTTP 200?
   - Recommendation: Phase 1 uses /health; Phase 2 manual verification includes MCP protocol test

5. **Optimal start_period for npx package download**
   - What we know: First startup downloads packages; 20s recommended as baseline
   - What's unclear: Varies by network speed and package cache; how to calibrate for environment?
   - Recommendation: Start with 20s; increase if logs show health check during download; monitor with `docker compose logs -f`

## Sources

### Primary (HIGH confidence)
- [MCP Gateway | Docker Docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) - Official gateway documentation
- [GitHub - docker/mcp-gateway](https://github.com/docker/mcp-gateway) - Official repository
- [docker/mcp-gateway - Docker Image](https://hub.docker.com/r/docker/mcp-gateway) - Official Docker Hub registry
- [@modelcontextprotocol/server-filesystem - npm](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) - Official filesystem server package (v2026.1.14)
- [Docker with iptables | Docker Docs](https://docs.docker.com/engine/network/firewall-iptables/) - Official firewall documentation
- [Port publishing and mapping | Docker Docs](https://docs.docker.com/engine/network/port-publishing/) - Official port binding security
- [Packet filtering and firewalls | Docker Docs](https://docs.docker.com/engine/network/packet-filtering-firewalls/) - DOCKER-USER chain documentation

### Secondary (MEDIUM confidence)
- [Using Docker MCP Gateway with Docker Compose - Collabnix](https://collabnix.com/docs/docker-mcp-gateway/using-docker-mcp-gateway-with-docker-compose-2/) - Community docker-compose examples
- [Running Docker MCP Gateway in a Docker container](https://www.ajeetraina.com/running-docker-mcp-gateway-in-a-docker-container/) - Standalone container deployment patterns
- [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view) - 2026 health check guidance
- [How to Create Docker Compose Health Checks](https://oneuptime.com/blog/post/2026-01-30-docker-compose-health-checks/view) - Compose-specific health check patterns
- [Docker Compose Health Checks: An Easy-to-follow Guide | Last9](https://last9.io/blog/docker-compose-health-checks/) - Comprehensive health check guide
- [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/) - host.docker.internal patterns
- [Reaching host's localhost from inside a vscode devcontainer | Medium](https://goledger.medium.com/reaching-hosts-localhost-from-inside-a-vscode-devcontainer-932e1c08df5c) - Devcontainer networking
- [MCP Security: Risks, Challenges, and How to Mitigate | Docker](https://www.docker.com/blog/mcp-security-explained/) - Official security guidance
- [Publishing docker ports to 127.0.0.1 instead of 0.0.0.0 – brokkr.net](https://brokkr.net/2022/03/29/publishing-docker-ports-to-127-0-0-1-instead-of-0-0-0-0/) - Loopback binding pattern

### Tertiary (LOW confidence - needs validation)
- Gateway environment variable configuration (inferred from CLI docs; containerized gateway may differ)
- Exact mcp.json schema (widely documented but no official JSON schema published)
- start_period optimal values (20s recommendation from general guidance, not MCP-specific benchmarks)

### Project-Specific Sources
- `.planning/research/STACK.md` - Project stack research (docker/mcp-gateway selection rationale)
- `.planning/research/ARCHITECTURE.md` - System architecture patterns
- `.planning/research/PITFALLS.md` - Domain-specific pitfalls (volume path mismatch, firewall bypass, etc.)
- `.planning/REQUIREMENTS.md` - Phase 1 requirements (INFRA-01 through SEC-04)
- `langfuse-local/docker-compose.yml` - Existing Langfuse stack (port conflict analysis)

## Metadata

**Confidence breakdown:**
- **Standard stack:** HIGH - Docker Hub and npm verified, official documentation consistent
- **Architecture patterns:** HIGH - Official Docker Compose docs, verified brownfield integration examples
- **Security practices:** HIGH - Official Docker security documentation, multiple authoritative sources
- **Health check timing:** MEDIUM - General best practices documented; npx-specific timing estimated from first principles
- **mcp.json schema:** MEDIUM - Format widely documented but no official JSON schema definition published
- **Environment variable substitution:** LOW - Gateway documentation incomplete; requires testing to confirm behavior

**Research date:** 2026-02-10
**Valid until:** 2026-03-10 (30 days for stable infrastructure; MCP protocol evolving rapidly)

**Critical gaps requiring validation during implementation:**
1. Gateway /health endpoint behavior (process-only vs MCP server verification)
2. mcp.json environment variable substitution support
3. Optimal start_period for local network conditions
4. Gateway container logging verbosity and format

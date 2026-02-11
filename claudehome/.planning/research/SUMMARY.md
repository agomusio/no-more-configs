# Project Research Summary

**Project:** MCP Gateway Integration for Claude Code Devcontainer
**Domain:** Docker-based MCP infrastructure for AI agent tooling
**Researched:** 2026-02-10
**Confidence:** HIGH

## Executive Summary

The Model Context Protocol (MCP) ecosystem has matured significantly, with Docker's official `docker/mcp-gateway` container providing production-ready orchestration for brownfield devcontainer integration. For this project's existing Langfuse Docker Compose stack, the recommended approach deploys the MCP gateway as a sidecar container using stdio transport for local MCP servers and Streamable HTTP for remote servers. The gateway runs as a sibling container to the devcontainer, exposing localhost:8811 only, with strict firewall enforcement.

**Critical Correction:** The original spec references `ghcr.io/anthropics/docker-mcp-gateway:latest` which does NOT exist. The correct image is `docker/mcp-gateway:latest` on Docker Hub. This changes all configuration examples, docker-compose entries, and documentation. Additionally, the MCP protocol deprecated SSE transport in favor of Streamable HTTP as of March 2026, though both remain supported during transition.

The key architectural insight is that the gateway and devcontainer are siblings, not parent-child, requiring identical workspace mount paths (both `/workspace`) to avoid path resolution failures. The most critical pitfall is Docker socket mounting, which grants root-equivalent access and must be gated behind a disabled-by-default compose profile, never mounted in Phase 1. The recommended MVP focuses on filesystem MCP server only (sufficient to validate infrastructure), deferring Docker tools, multi-server orchestration, and admin UI to later phases. Confidence is high due to extensive official Docker documentation, verified implementation guides, and mature security best practices documentation.

## Key Findings

### Recommended Stack

Docker's official MCP Gateway (`docker/mcp-gateway:latest`) is the recommended solution for this brownfield integration. It provides containerized MCP server lifecycle management, native Docker Desktop integration (4.37.1+), and built-in security isolation without requiring custom implementation. The gateway handles protocol translation between Claude Code's HTTP/SSE transport and MCP servers' stdio/HTTP transport, enabling a single configuration point for all MCP tooling.

**Core technologies:**
- **docker/mcp-gateway:latest** — Official Docker MCP proxy — provides containerized server lifecycle, security isolation, and native Docker integration
- **Docker Compose 2.x+** — Service orchestration — already in use for Langfuse stack, maintains existing sidecar pattern
- **@modelcontextprotocol/server-filesystem 2026.1.14** — Official filesystem MCP server — latest stable release, primary use case for code editing
- **Streamable HTTP transport** — Current MCP standard (2026-03-26+) — replaces deprecated SSE for remote servers
- **host.docker.internal** — Network alias — enables devcontainer to reach gateway at predictable endpoint

**Critical finding:** The protocol has moved from SSE to Streamable HTTP as the standard remote transport. Documentation and examples using SSE are still valid but deprecated. New integrations should use Streamable HTTP.

### Expected Features

MVP focuses on core infrastructure with filesystem access. Multi-server orchestration and advanced features deferred to post-validation phases based on proven need.

**Must have (table stakes):**
- Config-driven server management — Standard `mcp.json` format with servers object
- Stdio transport support — Required for filesystem MCP (primary use case)
- HTTP transport support — Future-proofing for remote servers, table stakes
- Health check endpoint — Required for Docker Compose orchestration
- Server lifecycle management — Gateway must start/stop servers reliably
- Workspace path mapping — Filesystem MCP useless without workspace access
- Basic logging — Debugging server failures is critical for MVP
- Error handling & retries — Production-grade reliability

**Should have (competitive):**
- Auto-connection from Claude Code — Core differentiator, eliminates manual setup pain (HIGH value)
- Multi-server orchestration — Single config manages 5-10+ servers simultaneously (post-MVP)
- Profile-based server groups — Enable "basic" vs "full" vs "docker-tools" modes (security pattern)
- Rate limiting per server — Protect backend services from excessive calls (LOW complexity)

**Defer (v2+):**
- Admin web UI — Nice for non-technical users but docker logs sufficient for MVP
- Dynamic server discovery — Hot-reload is convenience feature, restart acceptable initially
- Caching layer — Add when performance profiling shows repeated expensive operations
- Federation — Enterprise multi-team feature, not relevant for single-developer devcontainer

**Anti-features (avoid):**
- Docker socket mount by default — Security risk, must be profile-gated opt-in only
- TLS for localhost — Unnecessary complexity, bind to 127.0.0.1 for isolation
- Custom MCP protocol extensions — Creates incompatibility with standard clients

### Architecture Approach

The architecture uses a sidecar pattern where the MCP gateway runs as a Docker Compose service alongside the existing Langfuse stack. Claude Code (on host) connects to the gateway via localhost:8811, the gateway spawns/proxies MCP servers as Docker containers, and all services share the `langfuse-local_default` bridge network. The critical architectural constraint is the sibling container pattern: the devcontainer and gateway are peers, not nested, requiring identical workspace mount paths to avoid filesystem path resolution failures.

**Major components:**
1. **Claude Code Client (host-side)** — Initiates MCP tool calls via HTTP/SSE to localhost:8811, configured via `.mcp.json` in project root
2. **MCP Gateway (container)** — Protocol translation (HTTP/SSE to stdio/HTTP), server lifecycle, auth proxy, port bound to 127.0.0.1 only
3. **MCP Servers (gateway-managed)** — Provide tools via stdio (local) or HTTP (remote), spawned/proxied by gateway as isolated containers
4. **Docker Compose Project** — Unified lifecycle management, shared bridge network, single `docker compose up` command

**Key architectural patterns:**
- **Gateway as sidecar:** Deploy in same compose project as Langfuse, share network and lifecycle
- **Stdio-to-HTTP bridge:** Gateway converts local stdio servers to HTTP endpoints accessible by Claude Code
- **Workspace mount alignment:** Gateway and devcontainer must mount same host path at same container path (`/workspace`)
- **Loopback-only binding:** Always `127.0.0.1:8811:8811`, never `0.0.0.0`, enforced by firewall audit

### Critical Pitfalls

Research identified 7 critical pitfalls, all preventable with proper Phase 1 setup. The top pitfalls have direct security or architectural implications.

1. **Volume Path Mismatch (Sibling Container Pattern)** — Gateway and devcontainer mount workspace at different host paths, causing filesystem operations to reference wrong files. PREVENTION: Use absolute host path in `MCP_WORKSPACE_BIND`, verify with `docker exec docker-mcp-gateway ls /workspace` vs devcontainer ls. Address in Phase 1.

2. **Firewall Rule Bypass (iptables DOCKER-USER Chain)** — Port 8811 accessible externally despite INPUT chain rules because Docker FORWARD chain runs first. PREVENTION: Bind to `127.0.0.1:8811:8811` only AND add DOCKER-USER chain rules if broader access needed. Address in Phase 1.

3. **Docker Socket Mount = Root Escalation** — Mounting `/var/run/docker.sock` gives containerized MCP servers root-equivalent host access. PREVENTION: Never mount by default, gate behind disabled-by-default compose profile `mcp-docker-tools`, document escalation. Address in Phase 1 (architecture decision).

4. **host.docker.internal DNS Resolution Failure** — Devcontainer cannot reach gateway because DNS alias not available on Linux/custom networks. PREVENTION: Test with `ping host.docker.internal` early, add `--add-host=host.docker.internal:host-gateway` to devcontainer runArgs, document fallback to gateway IP. Address in Phase 2.

5. **Health Check Race Condition** — Container shows "healthy" before MCP server process completes initialization (npx package download). PREVENTION: Configure `start_period: 20s` in healthcheck, verify npx completes before success. Address in Phase 2.

6. **Environment Variable Injection in stdio Commands** — Hardcoded API keys in `mcp.json` args arrays leak into logs and git history. PREVENTION: Pass secrets via compose environment variables, add `mcp.json` to `.gitignore`, use `mcp.json.example` template. Address in Phase 1.

7. **Port Conflict Detection Failure** — Port 8811 already bound by zombie process/container, compose succeeds but gateway inaccessible. PREVENTION: Pre-flight check with `netstat -tuln | grep :8811`, verify with `docker port docker-mcp-gateway 8811`. Address in Phase 2.

## Implications for Roadmap

Based on research, the integration breaks into 3 phases: infrastructure setup with security hardening, manual verification and debugging, then client configuration and documentation. This order ensures security baseline before exposing services, validates assumptions before automation, and defers user-facing integration until infrastructure is proven stable.

### Phase 1: Infrastructure Setup & Security Baseline
**Rationale:** All critical pitfalls stem from incorrect Phase 1 configuration. Volume paths, firewall rules, Docker socket policy, and secret handling must be correct before any MCP testing. Security decisions (socket mount policy, loopback binding) are architectural and cannot be retrofitted safely.

**Delivers:** MCP gateway running as compose service with filesystem MCP server, health check passing, security hardened (no socket mount, loopback binding, secrets in env vars, iptables verified).

**Addresses:**
- Config-driven server management (table stakes)
- Stdio transport support (filesystem MCP)
- Health check endpoint (compose integration)
- Server lifecycle management (gateway spawns filesystem server)
- Workspace path mapping (sibling container pattern)

**Avoids:**
- Pitfall 1: Volume path mismatch (absolute path in MCP_WORKSPACE_BIND)
- Pitfall 2: Firewall bypass (127.0.0.1 binding, DOCKER-USER chain)
- Pitfall 3: Docker socket escalation (no socket mount, compose profile architecture)
- Pitfall 6: Leaked secrets (environment variables, .gitignore)

**Research flag:** None — well-documented Docker Compose pattern, extensive security documentation available.

### Phase 2: Manual Verification & Debugging
**Rationale:** Infrastructure must be validated before automating client integration. This phase catches health check race conditions, DNS resolution failures, and port conflicts that only manifest under specific timing or network conditions.

**Delivers:** Verified gateway reachability from devcontainer, confirmed filesystem MCP operations work end-to-end, health check timing validated, documented debugging procedures.

**Addresses:**
- Basic logging (troubleshooting server failures)
- Error handling verification (retry logic, graceful degradation)

**Avoids:**
- Pitfall 4: host.docker.internal DNS failure (test early, document fallback)
- Pitfall 5: Health check race (start_period configuration)
- Pitfall 7: Port conflicts (pre-flight checks)

**Research flag:** None — standard Docker troubleshooting techniques, well-documented connectivity patterns.

### Phase 3: Client Configuration & Auto-Discovery
**Rationale:** User-facing integration deferred until infrastructure proven stable. This phase implements the key differentiator (zero-config Claude Code integration) and validates the end-to-end workflow.

**Delivers:** `.mcp.json` project config with gateway URL, automated connection setup (minimal user steps), documented workflow for adding new MCP servers.

**Addresses:**
- Auto-connection from Claude Code (differentiator)
- HTTP transport support (for future remote servers)

**Avoids:** Configuration drift through project-scoped `.mcp.json` (team consistency)

**Research flag:** MEDIUM — Claude Code auto-discovery implementation may need iteration based on actual behavior, `.mcp.json` project scope requires validation.

### Phase Ordering Rationale

- **Phase 1 before 2:** Security baseline cannot be retrofitted. Docker socket policy, firewall rules, and volume path architecture are foundational decisions that affect all subsequent phases.
- **Phase 2 before 3:** Client configuration is wasted effort if gateway is unreachable due to DNS/networking issues. Manual verification catches environmental issues before automating integration.
- **Filesystem-only MVP:** Defer multi-server orchestration, Docker tools, and admin UI until filesystem MCP proven. This validates infrastructure pattern with minimal complexity before expanding scope.

**Dependency chain:**
```
Phase 1 (Gateway + Security)
  ├─ Volume mount correctness (pitfall 1)
  ├─ Firewall enforcement (pitfall 2)
  ├─ Socket policy (pitfall 3)
  └─ Secret handling (pitfall 6)
    ↓
Phase 2 (Verification)
  ├─ Gateway reachability (pitfall 4)
  ├─ Health check timing (pitfall 5)
  └─ Port availability (pitfall 7)
    ↓
Phase 3 (Client Config)
  └─ Claude Code auto-connection
```

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Docker Compose sidecar pattern, volume mounting, iptables DOCKER-USER chain — extensively documented in official Docker docs and security guides
- **Phase 2:** Docker networking troubleshooting, health check configuration — standard operational practices

**Phases likely needing deeper research during planning:**
- **Phase 3 (MEDIUM priority):** Claude Code `.mcp.json` project scope and auto-discovery behavior may need iteration. Official docs provide config format but implementation patterns less documented. Suggest quick validation test before full automation.

**Future phases flagged for research (v2+):**
- **Multi-server orchestration:** Merging tool lists, request routing, cache invalidation across servers
- **Admin web UI:** Gateway dashboard implementation options, observability integration
- **Dynamic server discovery:** File watching, hot reload, `list_changed` notification protocol

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Docker image verified via Docker Hub, multiple independent sources confirm architecture, official MCP specification supports transport choices |
| Features | HIGH | Feature landscape well-documented across IBM ContextForge, Docker blogs, and competitor analysis, MVP definition aligned with standard patterns |
| Architecture | HIGH | Official Docker and IBM documentation, verified networking patterns, extensive community implementation guides |
| Pitfalls | HIGH | Docker security best practices extensively documented, volume mount issues covered in official docs, firewall behavior verified across multiple sources |

**Overall confidence:** HIGH

The research is based primarily on official Docker documentation, Claude Code official docs, IBM's open-source MCP Context Forge documentation, and the official MCP protocol specification. All core technologies have stable releases, well-documented APIs, and extensive community validation. The main uncertainty is Claude Code's `.mcp.json` project-scoped configuration behavior, which has official documentation but limited real-world implementation examples (addressed via Phase 3 research flag).

### Gaps to Address

Despite high overall confidence, research identified specific gaps to validate during implementation:

- **Official mcp.json schema:** No published JSON schema for gateway configuration file format. Rely on examples from Docker blog posts and ContextForge docs. RESOLUTION: Test with minimal config first, expand incrementally.

- **Gateway versioning strategy:** Docker recommends `docker/mcp-gateway:latest` but no guidance on SHA-256 pinning or semver releases. RESOLUTION: Pin to `:latest` for MVP, document upgrade testing procedure for production use.

- **Claude Code project scope .mcp.json approval flow:** Documentation describes team approval prompt but not implementation timing or bypass methods. RESOLUTION: Test project-scoped config in Phase 3, document actual behavior for team rollout guide.

- **Host.docker.internal on Linux:** Behavior varies across Docker versions and devcontainer configurations. RESOLUTION: Test early in Phase 2, document platform-specific connection strings and fallback to explicit gateway IP.

- **Health check timing for npx-based servers:** Gateway spawns MCP servers via npx (on-demand package download), startup time varies based on npm cache state. RESOLUTION: Conservative `start_period: 20s` in Phase 1, tune based on actual startup logs.

## Sources

Research drew from 40+ sources across official documentation, security guides, implementation examples, and architectural references. Sources organized by confidence level.

### Primary (HIGH confidence)
- [MCP Gateway | Docker Docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) — Official gateway documentation, configuration patterns
- [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp) — Official client configuration, .mcp.json format
- [Model Context Protocol Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25) — Official protocol spec, transport definitions
- [docker/mcp-gateway - Docker Hub](https://hub.docker.com/r/docker/mcp-gateway) — Verified official image location (corrects spec error)
- [IBM MCP Context Forge - Official Docs](https://ibm.github.io/mcp-context-forge/) — Alternative gateway, architecture patterns
- [Docker with iptables | Docker Docs](https://docs.docker.com/engine/network/firewall-iptables/) — DOCKER-USER chain, port publishing behavior
- [@modelcontextprotocol/server-filesystem - npm](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) — Version 2026.1.14 verified

### Secondary (MEDIUM confidence)
- [MCP Security: Risks, Challenges, and How to Mitigate | Docker](https://www.docker.com/blog/mcp-security-explained/) — Security best practices, socket mount risks
- [Top 5 MCP Server Best Practices | Docker](https://www.docker.com/blog/mcp-server-best-practices/) — Configuration patterns, performance considerations
- [AI Guide to the Galaxy: MCP Toolkit and Gateway, Explained | Docker](https://www.docker.com/blog/mcp-toolkit-gateway-explained/) — Architecture overview, use cases
- [Docker Desktop 4.37: AI Catalog and Command-Line Efficiency | Docker](https://www.docker.com/blog/docker-desktop-4-37/) — Gateway integration timeline, Desktop features
- [Comparing MCP Gateways | Moesif Blog](https://www.moesif.com/blog/monitoring/model-context-protocol/Comparing-MCP-Model-Context-Protocol-Gateways/) — Gateway comparison, feature matrix
- [Why MCP Deprecated SSE and Went with Streamable HTTP - fka.dev](https://blog.fka.dev/blog/2025-06-06-why-mcp-deprecated-sse-and-go-with-streamable-http/) — Transport protocol rationale
- [Building a Secure AI Development Environment | Medium](https://medium.com/@brett_4870/building-a-secure-ai-development-environment-containerized-claude-code-mcp-integration-e2129fe3af5a) — Implementation guide, security patterns
- [Why Exposing Docker Socket is a Bad Idea - Quarkslab](https://blog.quarkslab.com/why-is-exposing-the-docker-socket-a-really-bad-idea.html) — Security implications, container escape

### Tertiary (LOW confidence, validation needed)
- Resource limit recommendations (Docker blog estimates, no published benchmarks)
- Gateway performance metrics (50-200ms latency estimates from vendor blogs)
- Multi-gateway federation patterns (ContextForge feature, limited production examples)

---
*Research completed: 2026-02-10*
*Ready for roadmap: yes*

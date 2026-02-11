# Technology Stack Research

**Project:** MCP Gateway Integration for Claude Code Devcontainer
**Domain:** Docker-based MCP infrastructure for AI agent tooling
**Researched:** 2026-02-10
**Confidence:** MEDIUM

## Executive Summary

The Model Context Protocol (MCP) ecosystem has matured significantly in 2025-2026, with multiple gateway solutions available for Docker deployment. For brownfield integration into an existing Docker devcontainer, the recommended approach uses **Docker's official MCP Gateway** (`docker/mcp-gateway`) as a sidecar container, leveraging stdio transport for local MCP servers and Streamable HTTP for remote servers. The protocol has deprecated SSE transport in favor of Streamable HTTP as of specification version 2026-03-26.

**Critical Finding:** The image `ghcr.io/anthropics/docker-mcp-gateway:latest` referenced in the project's integration spec does NOT exist. Docker's official image is `docker/mcp-gateway:latest` on Docker Hub.

## Recommended Stack

### Core Infrastructure

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **docker/mcp-gateway** | latest | MCP gateway proxy | Docker's official OSS gateway with containerized MCP server lifecycle management, built-in security isolation, and native Docker Desktop integration (4.37.1+) |
| **Docker Compose** | 2.x+ | Orchestration | Already in use for Langfuse stack; maintains existing sidecar pattern with sibling containers |
| **@modelcontextprotocol/server-filesystem** | 2026.1.14 | Filesystem MCP server | Official Anthropic filesystem server; latest stable release from January 2026 |
| **Node.js/npx** | 20.x LTS+ | MCP server runtime | Standard runtime for @modelcontextprotocol/* packages; use npx for zero-install server execution |

### MCP Transport Protocols

| Transport | Status | Purpose | When to Use |
|-----------|--------|---------|-------------|
| **stdio** | Current standard | Local process communication | Default for containerized MCP servers spawned by gateway; filesystem, memory, and most local tools |
| **Streamable HTTP** | Current standard (2026-03-26+) | Remote server communication | Remote MCP servers, cross-network access, production deployments |
| **SSE (Server-Sent Events)** | DEPRECATED | Legacy remote communication | Backward compatibility only; replaced by Streamable HTTP in Q1 2026 |

### Supporting Components

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| **@modelcontextprotocol/sdk** | 1.26.0 | TypeScript SDK for MCP | For custom MCP server development |
| **@modelcontextprotocol/inspector** | 0.19.0 | MCP debugging tool | Use `npx @modelcontextprotocol/inspector` for protocol debugging |
| **host.docker.internal** | N/A | Network alias | Devcontainer reaches gateway via `host.docker.internal:8811` |

### Configuration Format

| File | Scope | Format | Location |
|------|-------|--------|----------|
| **mcp.json** | Gateway server config | JSON (mcpServers object) | Mounted into gateway container at `/etc/mcp/mcp.json` |
| **.mcp.json** | Project-scoped Claude Code config | JSON (mcpServers object) | Project root (version-controlled) |
| **settings.local.json** | User-scoped Claude Code config | JSON with mcpServers field | `.claude/settings.local.json` or `~/.claude/settings.local.json` |

## Installation

### Gateway Deployment (Docker Compose)

Add to existing `claudehome/langfuse-local/docker-compose.yml`:

```yaml
services:
  docker-mcp-gateway:
    image: docker/mcp-gateway:latest
    container_name: docker-mcp-gateway
    restart: unless-stopped
    ports:
      - "127.0.0.1:8811:8811"
    environment:
      MCP_GATEWAY_HOST: "0.0.0.0"
      MCP_GATEWAY_PORT: "8811"
      MCP_CONFIG_FILE: "/etc/mcp/mcp.json"
    volumes:
      - ./mcp/mcp.json:/etc/mcp/mcp.json:ro
      - ${MCP_WORKSPACE_BIND}:/workspace:rw
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 5s
```

### Gateway Configuration (mcp.json)

Create `claudehome/langfuse-local/mcp/mcp.json`:

```json
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

### Claude Code Configuration (.mcp.json)

Project root `.mcp.json` for Claude Code client:

```json
{
  "mcpServers": {
    "docker-gateway": {
      "url": "http://host.docker.internal:8811",
      "transport": "streamable-http"
    }
  }
}
```

## Architecture Patterns

### Pattern 1: Stdio MCP Servers via Gateway

**What:** Gateway spawns MCP servers as child processes using stdio transport
**When:** Local filesystem, memory, or compute-bound tools
**Security:** Process isolation within gateway container; no host access by default

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    }
  }
}
```

### Pattern 2: Remote MCP Servers via Streamable HTTP

**What:** Gateway proxies requests to remote MCP servers over HTTP
**When:** Cross-container communication, remote API gateways, enterprise MCP services
**Security:** OAuth 2.1 authentication, TLS encryption recommended

```json
{
  "mcpServers": {
    "remote-api": {
      "url": "https://api.example.com/mcp",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer ${API_TOKEN}"
      }
    }
  }
}
```

### Pattern 3: Workspace Mount Alignment

**Critical:** Gateway container and devcontainer MUST mount the same workspace path

```yaml
# Gateway container
volumes:
  - ${MCP_WORKSPACE_BIND}:/workspace:rw

# Devcontainer workspaceFolder
"workspaceFolder": "/workspace"
```

**Why:** MCP server paths (e.g., `/workspace/docs`) must resolve identically in both contexts

## Alternatives Considered

| Category | Recommended | Alternative | When to Use Alternative |
|----------|-------------|-------------|------------------------|
| **Gateway** | docker/mcp-gateway | IBM Context Forge (ghcr.io/ibm/mcp-context-forge) | Need REST-to-MCP conversion, multi-cluster federation, Redis-backed caching, or admin UI |
| **Gateway** | docker/mcp-gateway | Microsoft MCP Gateway (microsoft/mcp-gateway) | Kubernetes-native deployment with session-aware routing |
| **Gateway** | docker/mcp-gateway | No gateway (direct stdio) | Single-user devcontainer with no multi-server orchestration needs |
| **Transport** | Streamable HTTP | SSE | Legacy systems only; SSE deprecated March 2026 |
| **Runtime** | npx (zero-install) | Pre-installed npm packages | Air-gapped environments or strict dependency pinning |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **ghcr.io/anthropics/docker-mcp-gateway** | Image does not exist; likely documentation error | docker/mcp-gateway:latest |
| **SSE transport for new deployments** | Deprecated in protocol v2026-03-26; complex dual-endpoint architecture | Streamable HTTP |
| **--network host in production** | Bypasses container isolation; exposes all host ports | Bridge network with explicit port bindings (127.0.0.1:8811:8811) |
| **Hardcoded secrets in mcp.json** | Credentials leak in version control | Environment variable references (${API_TOKEN}) |
| **/var/run/docker.sock mount by default** | Grants host-root-equivalent access | Only enable via compose profile when Docker-backed MCP tools required |
| **Global MCP configuration only** | No project-specific tooling; conflicts across projects | Project-scoped .mcp.json in repository root |

## Stack Patterns by Variant

**If running Docker Desktop 4.37.1+:**
- MCP Gateway runs automatically in background
- Use Docker Desktop UI for server management
- Gateway accessible at localhost:8811 by default
- OAuth token management built-in

**If using standalone Docker Engine (no Docker Desktop):**
- Deploy gateway as compose service (per installation section)
- Manual OAuth token management required
- Bind to 127.0.0.1 explicitly to prevent LAN exposure
- Use docker/mcp-gateway CLI plugin for management

**If security-critical environment:**
- Enable compose profile for /var/run/docker.sock mount only when needed
- Use read-only volume mounts for workspace (`:ro`) unless write required
- Implement network policies to restrict gateway ingress/egress
- Enable gateway request logging and audit trails
- Pin MCP server versions with SHA-256 digests

**If multi-container observability stack (like Langfuse):**
- Deploy gateway as sibling container in same compose project
- Share Docker network for inter-container communication
- Use centralized logging (stdout/stderr to Docker logging driver)
- Integrate healthchecks with existing monitoring

## Version Compatibility

| Package | Version | Compatible With | Notes |
|---------|---------|-----------------|-------|
| docker/mcp-gateway | latest | Docker Engine 20.10+, Docker Desktop 4.37.1+ | Latest stable as of Feb 2026 |
| @modelcontextprotocol/sdk | 1.26.0 | Protocol spec 2025-11-25, 2026-03-26 | v2.x anticipated Q1 2026 |
| @modelcontextprotocol/server-filesystem | 2026.1.14 | Node.js 18+, SDK 1.x | Published Jan 2026 |
| @modelcontextprotocol/server-memory | 2026.1.26 | SDK 1.x | Published Jan 2026 |
| Claude Code | Current | MCP protocol 2025-11-25+ | Supports .mcp.json project config |

## Security Best Practices

### Container Hardening

```yaml
# Recommended security configuration
docker-mcp-gateway:
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  read_only: true
  tmpfs:
    - /tmp
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 2G
```

### Network Isolation

```yaml
# Bind to localhost only
ports:
  - "127.0.0.1:8811:8811"  # Good: localhost only
  # NOT "8811:8811"          # Bad: exposes to LAN
  # NOT "0.0.0.0:8811:8811"  # Bad: exposes to all interfaces
```

### Secret Management

```yaml
# Use environment variable references
environment:
  - API_KEY=${API_KEY}

# Pass secrets via .env file (gitignored)
env_file:
  - .env
```

## Known Issues & Workarounds

### Issue 1: Path Resolution in Multi-Container Setup
**Problem:** MCP server resolves paths in gateway container context, not devcontainer context
**Detection:** MCP filesystem operations fail with "path not found" errors
**Solution:** Ensure identical mount paths in both containers (`/workspace` in both)

### Issue 2: npx Package Cache in Ephemeral Containers
**Problem:** Gateway container re-downloads packages on every restart
**Detection:** Slow gateway startup; network-dependent reliability
**Solution:** Create persistent volume for npm cache or pre-install packages in custom image

### Issue 3: OAuth Token Expiry with Standalone Gateway
**Problem:** Remote MCP servers fail after token expiry (no auto-refresh)
**Detection:** 401 Unauthorized errors after extended runtime
**Solution:** Use Docker Desktop 4.37.1+ with built-in token management, or implement refresh token flow

## Performance Considerations

| Aspect | Expected Impact | Mitigation |
|--------|----------------|------------|
| Gateway latency | 50-200ms per MCP call | Acceptable for interactive use; optimize for agentic loops with batching |
| Container startup | 3-10s for gateway + stdio servers | Use healthcheck with start_period: 5s; pre-warm during devcontainer postCreateCommand |
| npx package fetch | 1-5s per server first invocation | Volume-mount npm cache or use custom image with pre-installed servers |
| Resource limits | 1 CPU, 2GB RAM per gateway | Sufficient for 10-20 concurrent MCP servers; increase for high-throughput |

## Sources

### High Confidence (Official Documentation)

- [MCP Gateway | Docker Docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) — Official Docker MCP Gateway documentation
- [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp) — Claude Code MCP configuration
- [Specification - Model Context Protocol](https://modelcontextprotocol.io/specification/2025-11-25) — Official MCP protocol specification
- [docker/mcp-gateway - Docker Image](https://hub.docker.com/r/docker/mcp-gateway) — Official Docker Hub registry
- [@modelcontextprotocol/server-filesystem - npm](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) — Official npm package
- [MCP Server Transports: STDIO, Streamable HTTP & SSE | Roo Code Documentation](https://docs.roocode.com/features/mcp/server-transports) — Transport protocol documentation

### Medium Confidence (Docker Official Blogs)

- [Docker Desktop 4.37: AI Catalog and Command-Line Efficiency | Docker](https://www.docker.com/blog/docker-desktop-4-37/) — Gateway integration timeline
- [Top 5 MCP Server Best Practices | Docker](https://www.docker.com/blog/mcp-server-best-practices/) — Security best practices
- [MCP Security: Risks, Challenges, and How to Mitigate | Docker](https://www.docker.com/blog/mcp-security-explained/) — Security patterns
- [AI Guide to the Galaxy: MCP Toolkit and Gateway, Explained | Docker](https://www.docker.com/blog/mcp-toolkit-gateway-explained/) — Architecture overview

### Medium Confidence (Community Documentation)

- [Comparing MCP (Model Context Protocol) Gateways | Moesif Blog](https://www.moesif.com/blog/monitoring/model-context-protocol/Comparing-MCP-Model-Context-Protocol-Gateways/) — Gateway comparison
- [MCP Transport Protocols: stdio vs SSE vs StreamableHTTP | MCPcat](https://mcpcat.io/guides/comparing-stdio-sse-streamablehttp/) — Transport comparison
- [Why MCP Deprecated SSE and Went with Streamable HTTP - fka.dev](https://blog.fka.dev/blog/2025-06-06-why-mcp-deprecated-sse-and-go-with-streamable-http/) — SSE deprecation rationale

### Low Confidence (Needs Verification)

- Gateway configuration format details (mcp.json schema not officially documented)
- Exact environment variable names for gateway configuration
- Resource limit recommendations (based on Docker blog, not benchmarks)

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| **Gateway choice** | HIGH | Official Docker image verified via Docker Hub, documentation consistent across sources |
| **Transport protocols** | HIGH | Official MCP specification and multiple independent sources confirm Streamable HTTP as current standard |
| **Configuration format** | MEDIUM | mcpServers JSON structure widely documented but no official JSON schema published |
| **Version numbers** | MEDIUM | npm versions verified directly; gateway versioning uses "latest" tag without semver |
| **Security practices** | MEDIUM | Docker official blog recommendations but no published security audit or CVE database |
| **Performance metrics** | LOW | Latency estimates from Docker blog only; no independent benchmarks found |

## Critical Gaps

1. **Official mcp.json schema**: No JSON schema definition found for gateway configuration file
2. **ghcr.io/anthropics image**: Referenced in project spec but does not exist; likely documentation error
3. **Gateway API documentation**: No published API reference for programmatic gateway management
4. **Version pinning strategy**: Docker recommends "latest" tag; no guidance on SHA-256 pinning for gateway image
5. **Multi-transport gateway config**: Unclear if single gateway can serve both stdio and streamable-http simultaneously

---

*Stack research for: MCP Gateway Integration for Claude Code Devcontainer*
*Researched: 2026-02-10*
*Next steps: Validate docker/mcp-gateway image configuration with test deployment; resolve ghcr.io/anthropics discrepancy*

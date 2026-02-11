# Architecture Research

**Domain:** MCP Gateway Integration in Docker Devcontainer
**Researched:** 2026-02-10
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Host Machine (Windows)                          │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │ Claude Code Client                                            │       │
│  │ Config: ~/.claude/.claude.json                                │       │
│  │ Transport: HTTP/SSE to localhost:8811                         │       │
│  └─────────────┬────────────────────────────────────────────────┘       │
│                │ HTTP Request                                            │
├────────────────┼─────────────────────────────────────────────────────────┤
│                │ Bind Mount: /var/run/docker.sock                        │
│                ↓                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Devcontainer (Docker-outside-of-Docker)                          │    │
│  │ Network: bridge (langfuse-local_default: 172.18.0.0/16)         │    │
│  │                                                                   │    │
│  │  ┌────────────────────────────────────────────────────┐         │    │
│  │  │ MCP Gateway (Port 8811)                             │         │    │
│  │  │ Type: Docker Compose service (sidecar)              │         │    │
│  │  │ Transport: SSE/HTTP server                          │         │    │
│  │  │ Binding: 127.0.0.1:8811 (loopback-only)             │         │    │
│  │  │ Config: docker-compose.yml environment vars         │         │    │
│  │  │                                                      │         │    │
│  │  │  Manages MCP Servers:                               │         │    │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐  │         │    │
│  │  │  │ MCP Server 1│ │ MCP Server 2│ │ MCP Server N │  │         │    │
│  │  │  │ (container) │ │ (container) │ │ (container)  │  │         │    │
│  │  │  └─────────────┘ └─────────────┘ └──────────────┘  │         │    │
│  │  └────────────────────────────────────────────────────┘         │    │
│  │                                                                   │    │
│  │  ┌────────────────────────────────────────────────────┐         │    │
│  │  │ Langfuse Stack (Existing)                           │         │    │
│  │  │ ┌──────────┐ ┌──────────┐ ┌──────────┐             │         │    │
│  │  │ │   Web    │ │  Worker  │ │ Postgres │             │         │    │
│  │  │ └──────────┘ └──────────┘ └──────────┘             │         │    │
│  │  │ ┌──────────┐ ┌──────────┐ ┌──────────┐             │         │    │
│  │  │ │Clickhouse│ │  Redis   │ │  Minio   │             │         │    │
│  │  │ └──────────┘ └──────────┘ └──────────┘             │         │    │
│  │  │                                                      │         │    │
│  │  │ Network: langfuse-local_default (shared)            │         │    │
│  │  └────────────────────────────────────────────────────┘         │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Claude Code Client** | Initiates MCP tool calls, discovers servers, manages user interactions | CLI binary on host, reads config from ~/.claude/.claude.json |
| **MCP Gateway** | Protocol translation (stdio↔HTTP/SSE), MCP server orchestration, authentication proxy, audit logging | Docker container (docker/mcp-gateway or IBM ContextForge) |
| **MCP Servers** | Provide tools/resources/prompts via MCP protocol | Docker containers spawned by gateway or pre-existing services |
| **Docker Compose** | Define gateway + MCP servers as unified project, manage lifecycle, networking | docker-compose.yml in project root |
| **Docker Daemon (Host)** | Container runtime, network management, volume persistence | Accessed via /var/run/docker.sock bind mount |
| **Firewall (iptables)** | Enforce outbound connection policy, whitelist approved domains/ports | init-firewall.sh executed on container startup |

## Component Boundaries

### 1. Claude Code Client (Host-Side)

**Location:** Windows host machine, outside devcontainer
**Configuration Files:**
- `~/.claude/.claude.json` - MCP server definitions (user/local scope)
- Project `.mcp.json` - Team-shared MCP servers (project scope)

**Discovery Mechanism:**
- Claude Code reads config files to discover MCP servers
- Supports three scopes: `user` (global), `local` (project-specific user), `project` (shared)
- Automatically enables "Tool Search" when MCP tools exceed 10% of context window
- Uses `/mcp` command for OAuth authentication with remote servers

**Transport Modes:**
1. **HTTP** (recommended for remote servers): `claude mcp add --transport http gateway http://localhost:8811/mcp`
2. **SSE** (deprecated but supported): `claude mcp add --transport sse gateway http://localhost:8811/sse`
3. **stdio** (local processes): Not suitable for gateway pattern

**Key Characteristics:**
- Stateless from session perspective (config is persistent)
- Supports OAuth 2.0 for remote server authentication
- Can reference MCP resources via `@mentions` (e.g., `@github:issue://123`)
- Executes MCP prompts as commands (e.g., `/mcp__github__list_prs`)

### 2. MCP Gateway (Container-Side)

**Location:** Docker container in same compose project as Langfuse
**Network:** Attached to `langfuse-local_default` bridge network
**Port Binding:** `127.0.0.1:8811:8811` (loopback-only, firewall-enforced)

**Gateway Options:**

#### Option A: Docker MCP Gateway (Official)
```yaml
services:
  mcp-gateway:
    image: docker/mcp-gateway:latest
    ports:
      - "127.0.0.1:8811:8811"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./gateway-config:/config
    environment:
      - MCP_GATEWAY_PORT=8811
      - MCP_GATEWAY_TRANSPORT=sse  # or streamable-http
```

**Characteristics:**
- Spawns MCP servers as isolated Docker containers
- Built-in logging and call-tracing
- Enforces resource limits and network restrictions per server
- SSE transport for HTTP-based streaming communication

#### Option B: IBM ContextForge (Production-Grade)
```yaml
services:
  contextforge:
    image: ghcr.io/ibm/mcp-context-forge:latest
    ports:
      - "127.0.0.1:8811:8811"
      - "127.0.0.1:4444:4444"  # Admin UI (optional)
    volumes:
      - ./contextforge-data:/data
    environment:
      - JWT_SECRET_KEY=${JWT_SECRET}
      - PLATFORM_ADMIN_EMAIL=${ADMIN_EMAIL}
      - MCPGATEWAY_UI_ENABLED=true
      - DATABASE_URL=sqlite:////data/contextforge.db
```

**Characteristics:**
- Multi-protocol support (stdio, SSE, WebSocket, streamable-HTTP)
- Virtual server composition (wraps REST APIs as MCP servers)
- Federation support (multi-gateway orchestration via mDNS)
- PostgreSQL/Redis for production, SQLite for development

**Gateway Responsibilities:**
1. **Protocol Translation:** Converts between HTTP/SSE (client) and stdio/HTTP (MCP servers)
2. **Server Lifecycle:** Starts/stops MCP server containers on-demand
3. **Authentication Proxy:** Handles OAuth flows, API key injection
4. **Audit Trail:** Logs all tool calls for compliance
5. **Rate Limiting:** Enforces per-server/per-user quotas
6. **Security Isolation:** Runs servers in sandboxed containers

### 3. MCP Servers (Managed by Gateway)

**Location:** Docker containers spawned/managed by gateway
**Network:** Same bridge network as gateway (`langfuse-local_default`)
**Communication:** Gateway proxies requests to servers via stdio or HTTP

**Lifecycle:**
- **Stateful servers:** Long-running containers (databases, monitoring integrations)
- **Stateless servers:** Ephemeral containers spawned per-request
- **Pre-existing services:** External HTTP endpoints wrapped as virtual MCP servers

**Configuration Sources:**
1. **Gateway-managed:** Defined in gateway config (docker-compose env vars, config files)
2. **Dynamic registration:** Servers register via gateway admin API
3. **Auto-discovery:** Gateway discovers peer gateways/servers via mDNS (ContextForge only)

### 4. Docker Compose Project

**Structure:**
```
langfuse-local/
├── docker-compose.yml         # Langfuse + Gateway services
├── .env                        # Secrets (POSTGRES_PASSWORD, etc.)
├── gateway/
│   ├── servers.json           # MCP server definitions
│   └── auth.json              # OAuth credentials
└── volumes/
    ├── postgres/
    ├── minio/
    └── gateway/               # Gateway state/logs
```

**Network Design:**
- Single bridge network (`langfuse-local_default`)
- All services communicate via Docker DNS (e.g., `postgres:5432`)
- Gateway exposes only loopback binding (`127.0.0.1:8811`) to host

**Service Dependencies:**
```yaml
mcp-gateway:
  depends_on:
    - postgres  # If using PostgreSQL for gateway state
    - redis     # If using Redis for caching
```

## Data Flow

### Request Flow: Claude Code → MCP Tool Execution

```
1. User Prompt
   "Show me the most recent errors in Sentry"
   ↓
2. Claude Code analyzes available tools
   - Checks ~/.claude/.claude.json for MCP servers
   - If >10% context used by tools, activates Tool Search
   - Discovers "sentry" server at http://localhost:8811/mcp
   ↓
3. Claude Code → MCP Gateway (HTTP/SSE)
   POST http://localhost:8811/mcp
   {
     "jsonrpc": "2.0",
     "method": "tools/call",
     "params": {
       "name": "sentry_list_errors",
       "arguments": {"limit": 10}
     }
   }
   ↓
4. MCP Gateway processes request
   - Validates authentication (OAuth token, API key)
   - Checks rate limits
   - Logs tool call for audit trail
   - Identifies target MCP server (sentry)
   ↓
5. Gateway → MCP Server (stdio or HTTP)
   If stdio server:
     - Spawns/reuses Docker container
     - Sends JSON-RPC via stdin
     - Reads response from stdout
   If HTTP server:
     - Forwards HTTP request to container
     - Receives HTTP response
   ↓
6. MCP Server → External API
   - Server makes authenticated request to Sentry API
   - Applies filtering, pagination
   - Returns structured data
   ↓
7. Gateway ← MCP Server
   JSON-RPC response with tool result
   ↓
8. Gateway → Claude Code
   HTTP response with MCP tool result
   {
     "jsonrpc": "2.0",
     "result": {
       "content": [
         {"type": "text", "text": "Top 10 errors:\n1. ..."}
       ]
     }
   }
   ↓
9. Claude Code renders result
   - Displays to user
   - May trigger follow-up tool calls
   - Updates conversation context
```

### Configuration Flow

```
1. Administrator defines MCP servers
   ↓
   Option A: Gateway-managed (docker-compose.yml)
   environment:
     - MCP_SERVERS=[{"name":"github","type":"http","url":"..."}]

   Option B: Gateway admin API
   POST http://localhost:4444/admin/servers
   {"name":"sentry","url":"https://mcp.sentry.dev/mcp"}

   Option C: Dynamic registration (ContextForge)
   Server registers itself via mDNS or API call
   ↓
2. Gateway persists configuration
   - SQLite/PostgreSQL for server metadata
   - Filesystem for OAuth credentials
   - Redis for runtime state (if distributed)
   ↓
3. Claude Code discovers servers
   - User adds gateway as MCP server:
     claude mcp add --transport http gateway http://localhost:8811/mcp
   - Gateway exposes available tools via MCP list_tools
   - Claude Code caches tool definitions
   ↓
4. User authenticates (if required)
   - Claude Code: /mcp
   - Gateway redirects to OAuth provider
   - User completes browser flow
   - Gateway stores OAuth token, returns to Claude Code
   ↓
5. Ongoing: Dynamic updates
   - MCP servers can send list_changed notifications
   - Claude Code refreshes tool list without reconnecting
```

### Network Flow (Devcontainer Context)

```
Claude Code (Host)
  ↓ HTTP to localhost:8811
Docker Host Network Stack
  ↓ Port forwarding (127.0.0.1:8811 → container)
langfuse-local_default Bridge Network (172.18.0.0/16)
  ↓ Container DNS resolution
MCP Gateway Container (172.18.0.x)
  ↓ Internal HTTP/stdio calls
MCP Server Containers (172.18.0.y)
  ↓ Outbound HTTPS (firewall-enforced whitelist)
External APIs (github.com, sentry.io, etc.)
```

**Key Networking Patterns:**
1. **Loopback Binding:** Gateway only accessible from host (not other containers or external network)
2. **Container-to-Container:** Gateway and MCP servers use Docker DNS (e.g., `http://sentry-mcp:8080`)
3. **Firewall Enforcement:** iptables rules block non-whitelisted outbound connections
4. **host.docker.internal:** Containers can reach host services (e.g., Langfuse at `http://host.docker.internal:3052`)

## Architectural Patterns

### Pattern 1: Gateway as Sidecar

**What:** MCP Gateway runs as a service alongside Langfuse in the same compose project

**When to use:** When you want unified lifecycle management and shared networking

**Trade-offs:**
- **Pros:** Simple configuration, shared network, integrated logging
- **Cons:** Gateway restarts affect all MCP tools, coupled deployment lifecycle

**Example:**
```yaml
# docker-compose.yml
services:
  mcp-gateway:
    image: docker/mcp-gateway:latest
    restart: always
    depends_on:
      - postgres  # If gateway uses same DB
    ports:
      - "127.0.0.1:8811:8811"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./gateway-config:/config
    networks:
      - default  # Shares langfuse-local_default

  langfuse-web:
    # existing config
    networks:
      - default
```

### Pattern 2: Stdio-to-HTTP Bridge

**What:** Gateway converts stdio MCP servers (designed for local execution) to HTTP endpoints

**When to use:** When you want to use existing stdio servers remotely or share them across team

**Trade-offs:**
- **Pros:** Reuses existing MCP servers, no code changes needed
- **Cons:** Adds latency, complexity in error handling, requires gateway to spawn processes

**Example:**
```json
// gateway-config/servers.json
{
  "servers": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"],
      "env": {
        "ALLOWED_PATHS": "/workspace"
      }
    }
  }
}
```

Gateway exposes this as HTTP endpoint: `http://localhost:8811/servers/filesystem`

### Pattern 3: Virtual Server Composition

**What:** Gateway wraps non-MCP REST APIs as MCP servers (ContextForge feature)

**When to use:** When integrating existing APIs that don't have native MCP support

**Trade-offs:**
- **Pros:** No need to write custom MCP servers, declarative configuration
- **Cons:** Limited to request/response patterns, may not support all MCP features

**Example:**
```yaml
# contextforge-config.yml
virtual_servers:
  - name: "company-api"
    base_url: "https://api.company.com"
    auth:
      type: "bearer"
      token: "${COMPANY_API_TOKEN}"
    tools:
      - name: "search_docs"
        method: "GET"
        path: "/docs/search"
        params:
          query: "{{args.query}}"
        response_format: "json"
```

### Pattern 4: Distributed Federation (Advanced)

**What:** Multiple gateway instances discover and load-balance across each other (ContextForge only)

**When to use:** Multi-region deployments, high-availability requirements, team-specific gateway isolation

**Trade-offs:**
- **Pros:** Scalability, fault tolerance, regional compliance
- **Cons:** Complex configuration, requires Redis/PostgreSQL, network overhead

**Example:**
```yaml
# Gateway 1 (US region)
services:
  contextforge-us:
    image: ghcr.io/ibm/mcp-context-forge
    environment:
      - FEDERATION_ENABLED=true
      - FEDERATION_REGION=us-east
      - REDIS_URL=redis://redis-us:6379
      - MDNS_DISCOVERY=true

# Gateway 2 (EU region)
services:
  contextforge-eu:
    image: ghcr.io/ibm/mcp-context-forge
    environment:
      - FEDERATION_ENABLED=true
      - FEDERATION_REGION=eu-west
      - REDIS_URL=redis://redis-eu:6379
      - PEER_GATEWAY_URL=http://contextforge-us:8811
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **Single developer** | SQLite-backed gateway, stdio servers, local-only binding |
| **Small team (5-10)** | PostgreSQL gateway, pre-built MCP server containers, project-scoped config in `.mcp.json` |
| **Large team (50+)** | ContextForge with Redis, managed MCP config (allowlist/denylist), dedicated gateway infrastructure |
| **Enterprise (500+)** | Federated gateways per region, PostgreSQL HA + Redis Cluster, audit log streaming to SIEM, centralized `managed-mcp.json` deployment |

### Scaling Priorities

1. **First bottleneck:** Gateway spawning stdio servers (overhead per request)
   - **Fix:** Convert to long-running HTTP MCP servers, use container pooling

2. **Second bottleneck:** Gateway becomes SPOF (single point of failure)
   - **Fix:** Deploy multiple gateway instances with load balancer, use Redis for shared state

3. **Third bottleneck:** Network latency (Claude Code → Gateway → MCP Server → External API)
   - **Fix:** Co-locate gateway with external APIs, use caching layer, implement response streaming

## Anti-Patterns

### Anti-Pattern 1: Exposing Gateway to Public Internet

**What people do:** Bind gateway to `0.0.0.0:8811` to make it accessible from anywhere

**Why it's wrong:**
- Exposes internal tools/credentials to attackers
- Bypasses firewall policies
- No authentication on gateway by default

**Do this instead:**
- Always bind to `127.0.0.1:8811` (loopback only)
- If remote access needed, use VPN or SSH tunnel
- Enable gateway authentication (JWT, OAuth) if exposing to team

```yaml
# WRONG
ports:
  - "0.0.0.0:8811:8811"  # Accessible from external network

# RIGHT
ports:
  - "127.0.0.1:8811:8811"  # Only accessible from host
```

### Anti-Pattern 2: Running MCP Servers Directly (No Gateway)

**What people do:** Configure Claude Code to connect directly to stdio/HTTP MCP servers

**Why it's wrong:**
- No audit trail (can't track which tools were used)
- No centralized authentication/secrets management
- Each developer needs to configure servers individually
- Can't enforce rate limits or security policies

**Do this instead:**
- Use gateway to proxy all MCP connections
- Store server configs in gateway (single source of truth)
- Team adds gateway URL to Claude Code, gateway manages servers

```yaml
# WRONG: Claude Code connects directly to servers
# ~/.claude/.claude.json
{
  "mcpServers": {
    "github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/"},
    "sentry": {"type": "http", "url": "https://mcp.sentry.dev/mcp"}
  }
}

# RIGHT: Claude Code connects to gateway, gateway manages servers
# ~/.claude/.claude.json
{
  "mcpServers": {
    "gateway": {"type": "http", "url": "http://localhost:8811/mcp"}
  }
}

# docker-compose.yml (gateway manages servers)
services:
  mcp-gateway:
    environment:
      - MCP_SERVERS=[{"name":"github","url":"..."},{"name":"sentry","url":"..."}]
```

### Anti-Pattern 3: Storing Secrets in Git

**What people do:** Commit `.env` files or `docker-compose.yml` with hardcoded API keys

**Why it's wrong:**
- Credentials leak in version control history
- Team members share production credentials
- Rotation requires updating all copies

**Do this instead:**
- Use `.env.example` with placeholder values in Git
- Store real secrets in `.env` (gitignored) or secrets manager
- Gateway handles credential injection for MCP servers

```bash
# .env.example (committed to Git)
SENTRY_API_KEY=your_sentry_key_here
GITHUB_TOKEN=your_github_token_here

# .env (gitignored, real secrets)
SENTRY_API_KEY=actual_secret_key
GITHUB_TOKEN=ghp_actual_token

# docker-compose.yml
services:
  mcp-gateway:
    environment:
      - SENTRY_API_KEY=${SENTRY_API_KEY}  # Injected from .env
```

### Anti-Pattern 4: Using Host Network Mode

**What people do:** Run gateway with `network_mode: host` to avoid port mapping complexity

**Why it's wrong:**
- Breaks container network isolation
- Conflicts with firewall rules
- Can't use Docker DNS for service discovery
- Security risk (container has full host network access)

**Do this instead:**
- Use bridge network with explicit port bindings
- Leverage Docker DNS for inter-container communication
- Use `extra_hosts` if you need to reach host services

```yaml
# WRONG
services:
  mcp-gateway:
    network_mode: host  # Direct host network access

# RIGHT
services:
  mcp-gateway:
    ports:
      - "127.0.0.1:8811:8811"
    networks:
      - default
    extra_hosts:
      - "host.docker.internal:host-gateway"  # For accessing host services
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **GitHub** | HTTP MCP server at `https://api.githubcopilot.com/mcp/` | Requires OAuth, supports PR reviews, issue management |
| **Sentry** | HTTP MCP server at `https://mcp.sentry.dev/mcp` | OAuth via `/mcp` command, error tracking queries |
| **Langfuse** | Potential custom MCP server (future) | Could expose trace queries, model performance metrics |
| **Docker Daemon** | Socket bind mount (`/var/run/docker.sock`) | Gateway uses to spawn MCP server containers |
| **OAuth Providers** | Gateway redirects for authentication | Tokens stored in gateway's secure storage |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Claude Code ↔ Gateway** | HTTP/SSE over loopback (localhost:8811) | JSON-RPC 2.0, configurable timeout (MCP_TIMEOUT env var) |
| **Gateway ↔ MCP Servers** | stdio (JSON-RPC via stdin/stdout) or HTTP | Gateway spawns stdio containers, proxies HTTP servers |
| **Gateway ↔ Docker Daemon** | Unix socket (`/var/run/docker.sock`) | For container lifecycle management |
| **MCP Servers ↔ External APIs** | HTTPS outbound | Firewall enforces whitelist (iptables rules) |
| **Gateway ↔ Langfuse Services** | Docker DNS (e.g., `postgres:5432`) | If gateway needs to query Langfuse data |
| **Devcontainer ↔ Host Services** | `host.docker.internal` | Devcontainer reaches Langfuse UI at `http://host.docker.internal:3052` |

## Configuration Flow

### 1. Initial Setup (Administrator)

```bash
# Step 1: Add MCP Gateway to docker-compose.yml
cd /workspace/claudehome/langfuse-local
nano docker-compose.yml  # Add mcp-gateway service

# Step 2: Configure gateway environment
nano .env  # Add JWT_SECRET, ADMIN_EMAIL, etc.

# Step 3: Start gateway
docker-compose up -d mcp-gateway

# Step 4: Verify gateway is running
curl http://localhost:8811/health
```

### 2. Register MCP Servers (Administrator or via Config)

**Option A: Environment Variable (Simple)**
```yaml
# docker-compose.yml
services:
  mcp-gateway:
    environment:
      - MCP_SERVERS=[
          {"name":"github","type":"http","url":"https://api.githubcopilot.com/mcp/"},
          {"name":"sentry","type":"http","url":"https://mcp.sentry.dev/mcp"}
        ]
```

**Option B: Config File (Structured)**
```json
// gateway/servers.json
{
  "servers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "auth": {"type": "oauth", "provider": "github"}
    },
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"],
      "env": {"ALLOWED_PATHS": "/workspace"}
    }
  }
}
```

**Option C: Admin API (Dynamic)**
```bash
# Requires ContextForge with admin API enabled
curl -X POST http://localhost:4444/admin/servers \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "custom-api",
    "type": "http",
    "url": "https://api.company.com/mcp"
  }'
```

### 3. Claude Code Configuration (Developer)

```bash
# Step 1: Add gateway as MCP server
claude mcp add --transport http gateway http://localhost:8811/mcp

# Step 2: Verify connection
claude  # Start Claude Code
> /mcp  # List connected servers, authenticate if needed

# Step 3: Test tool call
> "List my open GitHub PRs"  # Claude uses gateway's GitHub server
```

**Config Result:**
```json
// ~/.claude/.claude.json (local scope)
{
  "mcpServers": {
    "gateway": {
      "type": "http",
      "url": "http://localhost:8811/mcp"
    }
  }
}
```

**For Team Sharing:**
```bash
# Add to project scope (creates .mcp.json in repo)
claude mcp add --transport http --scope project gateway http://localhost:8811/mcp

# Team members approve project servers on first use
> /mcp
# Prompt: "Approve server 'gateway' from .mcp.json? [y/n]"
```

### 4. Secrets Management

```bash
# Step 1: Add secrets to .env (gitignored)
echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxx" >> .env
echo "SENTRY_API_KEY=xxxxxxxxxxxx" >> .env

# Step 2: Gateway injects secrets into MCP servers
# docker-compose.yml
services:
  mcp-gateway:
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - SENTRY_API_KEY=${SENTRY_API_KEY}

# Step 3: MCP servers use injected secrets
# Gateway passes env vars to spawned containers
```

## Build Order (Dependency Graph)

```
1. Prerequisites
   ├─ Docker Daemon accessible via /var/run/docker.sock
   ├─ Langfuse stack running (postgres, redis, etc.)
   └─ Firewall rules configured (init-firewall.sh)

2. MCP Gateway Infrastructure
   ├─ Choose gateway implementation (Docker MCP Gateway vs ContextForge)
   ├─ Add gateway service to docker-compose.yml
   ├─ Configure gateway environment variables (.env)
   ├─ Start gateway container
   └─ Verify gateway health endpoint (curl http://localhost:8811/health)

3. MCP Server Registration
   ├─ Define servers in gateway config (env vars, JSON file, or API)
   ├─ Configure authentication (OAuth credentials, API keys)
   ├─ Test server connectivity from gateway
   └─ Verify tools are exposed via gateway's list_tools

4. Claude Code Integration
   ├─ Add gateway to Claude Code config (claude mcp add)
   ├─ Authenticate with OAuth servers (/mcp command)
   ├─ Test tool discovery (claude should see gateway's tools)
   └─ Execute test tool call

5. Team Rollout (Optional)
   ├─ Add gateway to project scope (.mcp.json)
   ├─ Document authentication flow for team
   ├─ Configure managed MCP settings (allowlist/denylist if needed)
   └─ Team members approve project servers on first use
```

**Critical Build Order Rules:**
1. **Gateway must start AFTER Docker daemon is accessible** (requires /var/run/docker.sock mount)
2. **Gateway must start AFTER dependencies** (PostgreSQL/Redis if used for state)
3. **MCP servers must be registered BEFORE Claude Code connects** (or Claude sees no tools)
4. **OAuth credentials must be configured BEFORE first tool call** (or authentication fails)
5. **Firewall rules must be applied BEFORE MCP servers spawn** (or policy is bypassed)

## Sources

### Official Documentation
- [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp)
- [Docker MCP Gateway | Docker Docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/)
- [IBM MCP Context Forge - Model Context Protocol Gateway](https://ibm.github.io/mcp-context-forge/)
- [IBM MCP Context Forge Architecture Overview](https://ibm.github.io/mcp-context-forge/architecture/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25)

### Implementation Guides
- [Docker MCP Gateway with Docker Compose - Collabnix](https://collabnix.com/docs/docker-mcp-gateway/using-docker-mcp-gateway-with-docker-compose-2/)
- [AI Guide to the Galaxy: MCP Toolkit and Gateway, Explained | Docker](https://www.docker.com/blog/mcp-toolkit-gateway-explained/)
- [Docker MCP Gateway: Secure Infrastructure for Agentic AI](https://www.docker.com/blog/docker-mcp-gateway-secure-infrastructure-for-agentic-ai/)
- [GitHub - docker/mcp-gateway](https://github.com/docker/mcp-gateway)
- [GitHub - IBM/mcp-context-forge](https://github.com/IBM/mcp-context-forge)

### Architecture References
- [MCP Gateway: How It Works, Capabilities and Use Cases](https://obot.ai/resources/learning-center/mcp-gateway/)
- [MCP Gateways: A Developer's Guide to AI Agent Architecture in 2026](https://composio.dev/blog/mcp-gateways-guide)
- [Model Context Protocol (MCP) and the MCP Gateway: Concepts, Architecture, and Case Studies](https://bytebridge.medium.com/model-context-protocol-mcp-and-the-mcp-gateway-concepts-architecture-and-case-studies-3470b6d549a1)

### Networking Patterns
- [Connect to localhost from inside a dev container](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/)
- [Reaching host's localhost from inside a vscode devcontainer](https://goledger.medium.com/reaching-hosts-localhost-from-inside-a-vscode-devcontainer-932e1c08df5c)
- [Docker Networking | Docker Docs](https://docs.docker.com/engine/network/)
- [Docker Container Networking Modes 2026](https://oneuptime.com/blog/post/2026-01-25-docker-container-networking-modes/view)

---
*Architecture research for: MCP Gateway Integration in Docker Devcontainer*
*Researched: 2026-02-10*
*Confidence: HIGH - Based on official Docker and IBM documentation, Claude Code docs, and verified networking patterns*

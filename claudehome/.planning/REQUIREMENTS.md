# Requirements: MCP Gateway Integration

**Defined:** 2026-02-10
**Core Value:** Claude Code sessions in this devcontainer have seamless access to MCP servers without manual setup — any supported MCP server can be plugged in through a single gateway.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Infrastructure

- [x] **INFRA-01**: MCP gateway runs as a Docker Compose sidecar service in the existing Langfuse stack
- [x] **INFRA-02**: Gateway uses correct image (`docker/mcp-gateway:latest`) with loopback-only port binding (`127.0.0.1:8811:8811`)
- [x] **INFRA-03**: Gateway config is driven by `mcp.json` — adding a new MCP server requires only editing this file and restarting
- [x] **INFRA-04**: Gateway health check endpoint (`/health`) passes and is used by Docker Compose for orchestration
- [x] **INFRA-05**: No port conflicts with existing Langfuse services (3030, 3052, 5433, 6379, 8124, 9000, 9090, 9091)

### Filesystem MCP

- [x] **FSMCP-01**: Filesystem MCP server is configured in `mcp.json` and started by the gateway via stdio transport
- [x] **FSMCP-02**: Workspace content is mounted identically in both devcontainer and gateway (`/workspace`) to avoid path mismatch
- [ ] **FSMCP-03**: Filesystem MCP can read and write files in the workspace directory

### Security

- [x] **SEC-01**: Gateway binds to `127.0.0.1` only — no LAN exposure
- [x] **SEC-02**: Docker socket is NOT mounted by default; gated behind a disabled-by-default compose profile (`mcp-docker-tools`)
- [x] **SEC-03**: API keys and secrets are passed via environment variables, not hardcoded in `mcp.json`
- [x] **SEC-04**: Firewall (iptables) allows traffic to gateway port 8811 from devcontainer

### Connectivity

- [ ] **CONN-01**: Gateway is reachable from devcontainer via `host.docker.internal:8811`
- [ ] **CONN-02**: Claude Code auto-connects to MCP gateway on devcontainer start (via `.mcp.json` or `settings.local.json`)
- [ ] **CONN-03**: Gateway logs are accessible via `docker logs docker-mcp-gateway` for debugging

### Verification

- [ ] **VERIF-01**: End-to-end test: Claude Code session can invoke filesystem MCP tools (list files, read file, write file)
- [ ] **VERIF-02**: Health check timing accounts for npx package download delay (`start_period: 20s`)
- [ ] **VERIF-03**: Adding a second MCP server to `mcp.json` and restarting makes it available to Claude Code

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Multi-Server

- **MULTI-01**: Single config manages 5-10+ MCP servers simultaneously with tool list merging
- **MULTI-02**: Rate limiting per MCP server to prevent excessive calls
- **MULTI-03**: Credential management for servers requiring authentication (GitHub, database)

### Server Groups

- **GROUP-01**: Profile-based server groups (basic, full, docker-tools) via Docker Compose profiles
- **GROUP-02**: Caching layer for repeated expensive MCP operations

### Observability

- **OBS-01**: Observability integration with existing Langfuse stack
- **OBS-02**: Structured logging with request tracing

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Docker socket mount by default | Security risk — root-equivalent host access |
| TLS/HTTPS for local gateway | Unnecessary for loopback traffic |
| Custom MCP protocol extensions | Creates incompatibility with standard clients |
| Admin web UI | docker logs sufficient for dev environment |
| Dynamic server discovery / hot-reload | Restart is acceptable for v1 |
| Federation with peer gateways | Single-user devcontainer, not enterprise |
| Building custom MCP servers | Using existing ecosystem servers only |
| Production deployment | This is a development environment tool |
| Cross-host access | Loopback binding sufficient for local use |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | ✓ Done |
| INFRA-02 | Phase 1 | ✓ Done |
| INFRA-03 | Phase 1 | ✓ Done |
| INFRA-04 | Phase 1 | ✓ Done |
| INFRA-05 | Phase 1 | ✓ Done |
| FSMCP-01 | Phase 1 | ✓ Done |
| FSMCP-02 | Phase 1 | ✓ Done |
| FSMCP-03 | Phase 2 | Pending |
| SEC-01 | Phase 1 | ✓ Done |
| SEC-02 | Phase 1 | ✓ Done |
| SEC-03 | Phase 1 | ✓ Done |
| SEC-04 | Phase 1 | ✓ Done |
| CONN-01 | Phase 2 | Pending |
| CONN-02 | Phase 3 | Pending |
| CONN-03 | Phase 2 | Pending |
| VERIF-01 | Phase 3 | Pending |
| VERIF-02 | Phase 2 | Pending |
| VERIF-03 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18/18 (100%)
- Unmapped: 0

---
*Requirements defined: 2026-02-10*
*Last updated: 2026-02-10 — Phase 1 requirements verified*

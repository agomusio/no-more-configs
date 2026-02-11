# MCP Integration for Devcontainer

## What This Is

A flexible MCP (Model Context Protocol) gateway infrastructure for the Claude Code devcontainer. Enables Claude Code sessions to auto-connect to any MCP server from the ecosystem — starting with filesystem access and designed so adding new servers is just a config edit and restart.

## Core Value

Claude Code sessions in this devcontainer have seamless access to MCP servers without manual setup — any supported MCP server can be plugged in through a single gateway.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Docker MCP Gateway runs as a sidecar service in the existing Langfuse compose stack
- [ ] Filesystem MCP server is configured and accessible from Claude Code
- [ ] Claude Code auto-connects to MCP gateway on devcontainer start
- [ ] Adding a new MCP server requires only editing mcp.json and restarting the gateway
- [ ] Gateway is reachable from devcontainer via loopback (no LAN exposure)
- [ ] Health check endpoint confirms gateway and servers are operational
- [ ] No port conflicts with existing Langfuse services (3030, 3052, 5433, 6379, 8124, 9000, 9090, 9091)

### Out of Scope

- Docker socket mounting for Docker-backed MCP tools — security risk, defer to future profile-gated approach
- Cross-host access or TLS — loopback binding sufficient for local devcontainer use
- Building custom MCP servers — using existing ecosystem servers only
- Production deployment — this is a development environment tool

## Context

- Devcontainer runs on Docker Desktop (WSL2) with host Docker daemon access via bind-mounted socket
- Existing sidecar services (Langfuse stack) run as sibling containers on the host daemon
- Devcontainer reaches host-published services via `host.docker.internal`
- Detailed integration spec exists at `docs/mcp-integration-spec.md` covering compose patches, mcp.json config, verification commands, and security considerations
- Port 8811 reserved for MCP gateway (avoids all existing bindings)
- Claude Code configuration lives in `/home/node/.claude/` (bind-mounted from Windows host)

## Constraints

- **Network**: Gateway must bind to `127.0.0.1` only — no LAN exposure
- **Isolation**: Gateway runs in separate container, not inside devcontainer
- **Compatibility**: Must not break existing Langfuse compose stack or devcontainer startup
- **Security**: No Docker socket mount by default; filesystem MCP uses `:rw` only for workspace directory
- **Firewall**: Gateway port must be allowed through devcontainer iptables whitelist

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Add gateway to existing Langfuse compose project | Follows established sidecar model, shares Docker network | — Pending |
| Use port 8811 for gateway | Avoids all existing port bindings | — Pending |
| Start with filesystem MCP only | Lowest risk, validates gateway infrastructure | — Pending |
| Config-driven server management via mcp.json | Makes adding servers trivial — edit JSON, restart | — Pending |

---
*Last updated: 2026-02-10 after initialization*

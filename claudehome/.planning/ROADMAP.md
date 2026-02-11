# Roadmap: MCP Integration for Devcontainer

## Overview

This roadmap delivers MCP (Model Context Protocol) gateway infrastructure for the Claude Code devcontainer in three phases: establishing the gateway as a secure Docker Compose sidecar with filesystem access, validating connectivity and health checks from the devcontainer, and automating Claude Code client integration for zero-config startup. Each phase delivers a complete, verifiable capability building toward seamless MCP server access without manual setup.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Gateway Infrastructure** - MCP gateway runs as secure sidecar service
- [ ] **Phase 2: Connectivity & Health Validation** - Gateway is reachable and operational from devcontainer
- [ ] **Phase 3: Claude Code Integration** - Claude Code auto-connects to MCP gateway on startup

## Phase Details

### Phase 1: Gateway Infrastructure
**Goal**: MCP gateway runs as secure Docker Compose sidecar with filesystem MCP server configured and operational
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05, SEC-01, SEC-02, SEC-03, SEC-04, FSMCP-01, FSMCP-02
**Success Criteria** (what must be TRUE):
  1. MCP gateway container runs as sidecar in Langfuse Docker Compose stack without port conflicts
  2. Gateway binds to localhost:8811 only (127.0.0.1), preventing LAN exposure
  3. Filesystem MCP server is configured in mcp.json and started by gateway via stdio transport
  4. Gateway health check endpoint returns success (200 OK)
  5. Workspace directory is mounted at identical path (/workspace) in both gateway and devcontainer
  6. Docker socket is NOT mounted by default and mcp-docker-tools compose profile is disabled
**Plans:** 1 plan

Plans:
- [x] 01-01-PLAN.md — Add MCP gateway sidecar service with filesystem MCP config to Docker Compose stack

### Phase 2: Connectivity & Health Validation
**Goal**: Gateway is reachable from devcontainer and filesystem MCP operations work end-to-end
**Depends on**: Phase 1
**Requirements**: CONN-01, CONN-02, CONN-03, VERIF-02, FSMCP-03
**Success Criteria** (what must be TRUE):
  1. Devcontainer can reach gateway at host.docker.internal:8811 (or fallback IP)
  2. Gateway logs are accessible via docker logs docker-mcp-gateway for troubleshooting
  3. Filesystem MCP can list files in /workspace from gateway context
  4. Filesystem MCP can read and write files in /workspace with changes visible in devcontainer
  5. Health check timing accounts for npx package download (start_period configured correctly)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD during planning

### Phase 3: Claude Code Integration
**Goal**: Claude Code auto-connects to MCP gateway on devcontainer startup with zero manual configuration
**Depends on**: Phase 2
**Requirements**: CONN-02 (enhanced for auto-connection), VERIF-01, VERIF-03
**Success Criteria** (what must be TRUE):
  1. Claude Code session can invoke filesystem MCP tools (list files, read file, write file) without manual setup
  2. Claude Code configuration (.mcp.json or settings.local.json) contains gateway URL and auto-connects on start
  3. Adding a second MCP server to mcp.json and restarting gateway makes it available to Claude Code
  4. Documentation exists for adding new MCP servers (config edit + restart workflow)
**Plans**: TBD

Plans:
- [ ] 03-01: TBD during planning

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Gateway Infrastructure | 1/1 | ✓ Complete | 2026-02-10 |
| 2. Connectivity & Health Validation | 0/TBD | Not started | - |
| 3. Claude Code Integration | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-10*
*Last updated: 2026-02-10 — Phase 1 complete*

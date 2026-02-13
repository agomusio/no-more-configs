# MCP Integration Spec (RFC)

## 1) Dependency Analysis

### Current runtime topology
- The devcontainer is a single container defined in `.devcontainer/devcontainer.json` and uses the host Docker daemon via `/var/run/docker.sock` bind mount.
- The existing `docker-compose.yml` stack (Langfuse) is launched as sibling containers on the host daemon.
- The devcontainer reaches host-published services using `host.docker.internal`.

### Recommended MCP placement
Add a new `docker-mcp-gateway` service to the **same compose project** as `langfuse-local/docker-compose.yml` so it:
1. follows your existing sidecar model,
2. remains isolated from the devcontainer filesystem/permissions model,
3. can be reached from the devcontainer through a loopback-published port.

### Network and port-conflict analysis
Existing host bindings in `langfuse-local/docker-compose.yml`:
- `3030`, `3052`, `5433`, `6379`, `8124`, `9000`, `9090`, `9091`.

To avoid collisions, reserve an MCP gateway port not currently used (example: `8811`) and bind to loopback only:
- `127.0.0.1:8811:8811`

This keeps the endpoint private to host/devcontainer traffic and avoids LAN exposure.

### Security stance
- **Filesystem MCP only**: no Docker socket mount is required.
- For future Docker-backed MCP tools that must dynamically launch containerized servers, `/var/run/docker.sock` may become necessary. If enabled later, treat it as host-root-equivalent access and gate it behind a compose profile (disabled by default).

---

## 2) Configuration Patches

> Assumption: compose file is `claudehome/langfuse-local/docker-compose.yml`.

### Patch A — `docker-compose.yml` service addition

```yaml
services:
  docker-mcp-gateway:
    image: ghcr.io/anthropics/docker-mcp-gateway:latest
    container_name: docker-mcp-gateway
    restart: unless-stopped
    ports:
      - "127.0.0.1:8811:8811"
    environment:
      # Gateway listen address
      MCP_GATEWAY_HOST: 0.0.0.0
      MCP_GATEWAY_PORT: 8811
      # Path to gateway config
      MCP_CONFIG_FILE: /etc/mcp/mcp.json
    volumes:
      # Gateway config
      - ./mcp/mcp.json:/etc/mcp/mcp.json:ro
      # Workspace content exposed to filesystem MCP server
      # IMPORTANT: set MCP_WORKSPACE_BIND to a host-daemon-visible path.
      # Example when compose is run from this repo checkout:
      # MCP_WORKSPACE_BIND=../..
      - ${MCP_WORKSPACE_BIND}:/workspace:rw
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8811/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 5s
```

#### Optional future-only profile for Docker-backed MCP tools

```yaml
services:
  docker-mcp-gateway:
    profiles: ["mcp-docker-tools"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

Use only when needed:

```bash
docker compose --profile mcp-docker-tools up -d docker-mcp-gateway
```

### Patch B — `mcp.json` for Filesystem MCP mapping

Create `claudehome/langfuse-local/mcp/mcp.json`:

```json
{
  "servers": {
    "filesystem": {
      "transport": {
        "type": "stdio",
        "command": "npx",
        "args": [
          "-y",
          "@modelcontextprotocol/server-filesystem",
          "/workspace"
        ]
      }
    }
  }
}
```

### Mount/path correctness relative to devcontainer
- Devcontainer workspace path is `/workspace`.
- Gateway container must also mount repository content at `/workspace` (as in Patch A).
- `mcp.json` points the Filesystem MCP server at `/workspace`, ensuring both your primary agent context and MCP server target the same in-container path.

---

## 3) Manual Verification Commands

Run these from inside your devcontainer shell (same as current workflow):

### Bring up gateway
```bash
cd /workspace/claudehome/langfuse-local
mkdir -p mcp
# ensure MCP_WORKSPACE_BIND resolves to daemon-visible source path
export MCP_WORKSPACE_BIND=../..
docker compose up -d docker-mcp-gateway
```

### Confirm container and health
```bash
docker compose ps docker-mcp-gateway
```

```bash
docker inspect --format '{{json .State.Health}}' docker-mcp-gateway | jq
```

### Confirm listening endpoint
```bash
curl -i http://host.docker.internal:8811/health
```

### Confirm filesystem mount is present
```bash
docker exec docker-mcp-gateway sh -lc 'ls -la /workspace | head'
```

### Confirm gateway loaded Filesystem MCP config
```bash
docker exec docker-mcp-gateway sh -lc 'cat /etc/mcp/mcp.json'
```

### Tail logs for protocol/startup errors
```bash
docker logs --tail=200 docker-mcp-gateway
```

---

## 4) Risk Notes and Hardening

1. Keep host exposure minimal: bind gateway to `127.0.0.1` only.
2. Prefer `:ro` for config mounts and use `:rw` only for folders that Filesystem MCP must modify.
3. If you later enable Docker socket mounting, document it as a privileged mode and restrict usage via compose profile + local policy.
4. Consider adding request auth/TLS only if you need cross-host access; for local devcontainer use, loopback binding is usually sufficient.

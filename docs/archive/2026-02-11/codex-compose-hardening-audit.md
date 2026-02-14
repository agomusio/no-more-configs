# Docker Compose Hardening Audit

Date: 2026-02-11  
Scope: `infra/docker-compose.yml`

## Key findings

1. **No resource limits set for any service**
   - `mem_limit`/`cpus` (or `deploy.resources`) are absent, so runaway service behavior can impact host stability.

2. **Restart policy is inconsistent**
   - Most services use `restart: always`; MCP gateway uses `restart: unless-stopped`.

3. **read_only root filesystem not applied where feasible**
   - Stateless services (`langfuse-web`, `langfuse-worker`, `docker-mcp-gateway`) could likely run with `read_only: true` plus targeted writable mounts/tmpfs.

4. **MinIO service likely starts as root shell (`entrypoint: sh`)**
   - Explicit user is not set; shell entrypoint increases risk surface.

5. **Health checks exist but are unevenly tuned**
   - Some services have aggressive timings (`start_period: 1s`) that can flap on slower hosts.
   - `langfuse-web` and `langfuse-worker` have no direct health checks.

## Actionable recommendations

### 1) Add per-service resource caps

Example baseline for local dev (tune based on host):

```yaml
langfuse-web:
  mem_limit: 768m
  cpus: 1.0

langfuse-worker:
  mem_limit: 1024m
  cpus: 1.5

clickhouse:
  mem_limit: 2048m
  cpus: 2.0

postgres:
  mem_limit: 1024m
  cpus: 1.0

redis:
  mem_limit: 256m
  cpus: 0.5

minio:
  mem_limit: 512m
  cpus: 0.5

docker-mcp-gateway:
  mem_limit: 256m
  cpus: 0.5
```

### 2) Enforce non-root users where supported

- Keep ClickHouse explicit `user: "101:101"`.
- Add `user` for MinIO and MCP gateway if images support it.
- Prefer image-native entrypoint over `entrypoint: sh` wrapper where possible.

### 3) Apply read-only root filesystem for stateless services

Candidate services:
- `langfuse-web`
- `langfuse-worker`
- `docker-mcp-gateway`

Pattern:

```yaml
read_only: true
tmpfs:
  - /tmp:size=64m
```

Add explicit writable volume mounts for required app paths only.

### 4) Standardize restart policy

Pick one policy for local reliability (recommend `unless-stopped`) and apply consistently across services unless a specific dependency requires `always`.

### 5) Expand and normalize health checks

- Add health checks for `langfuse-web` and `langfuse-worker` (HTTP `/api/public/health` or service-appropriate command).
- Raise `start_period` for heavier services (`clickhouse`, `minio`, `postgres`) to reduce false negatives.
- Include explicit `interval`, `timeout`, `retries` on all services.

### 6) Security hardening extras

- Add `security_opt: ["no-new-privileges:true"]` where possible.
- Drop Linux caps for services that do not require them:

```yaml
cap_drop:
  - ALL
```

## Priority plan

- **P0:** resource limits + health checks for web/worker.
- **P1:** user hardening for MinIO/MCP gateway, restart policy normalization.
- **P2:** read-only rootfs + cap_drop validation service-by-service.

## Source references

- `infra/docker-compose.yml:2-168` (all services currently without resource caps)
- `infra/docker-compose.yml:4,51,70,91,111,125,145` (restart policy usage)
- `infra/docker-compose.yml:89-107` (MinIO entrypoint/healthcheck)
- `infra/docker-compose.yml:49-67` (langfuse-web currently no healthcheck)
- `infra/docker-compose.yml:2-48` (langfuse-worker currently no healthcheck)

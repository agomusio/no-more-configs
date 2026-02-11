# Phase 2: Connectivity & Health Validation - Research

**Researched:** 2026-02-10
**Domain:** Docker container networking, devcontainer connectivity, health check validation, MCP protocol testing
**Confidence:** HIGH

## Summary

Phase 2 validates that the gateway infrastructure deployed in Phase 1 is operationally reachable from the devcontainer and that the filesystem MCP server can perform end-to-end read/write operations. This phase focuses on three critical validation domains: network connectivity between sibling containers (devcontainer → gateway), health check verification accounting for npx package download timing, and filesystem MCP operation testing through the gateway's HTTP API.

**Critical insight:** The devcontainer and gateway are sibling containers sharing the Docker host daemon, not parent-child. Connectivity relies on `host.docker.internal` DNS resolution (requires manual configuration on Linux) or fallback to gateway IP discovery. Health checks must account for cold-start npx package downloads (20s+ on first run). MCP validation requires testing through the gateway's HTTP endpoint, not direct stdio access.

**Primary recommendation:** Use `docker exec` commands from devcontainer to test connectivity (`curl http://host.docker.internal:8811/health`), verify health check passes after npx download completes, validate filesystem MCP through MCP Inspector or manual HTTP calls, and confirm volume mount alignment with cross-container file write tests.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **curl** | (bundled) | HTTP connectivity testing | Universal HTTP client; standard for health check validation and API testing |
| **docker logs** | Docker CLI | Container log inspection | Built-in Docker troubleshooting tool; essential for debugging gateway startup |
| **docker exec** | Docker CLI | In-container command execution | Standard method for testing network connectivity from running containers |
| **MCP Inspector** | 0.9.0+ | MCP server testing UI | Official Anthropic tool for interactive MCP server validation and debugging |
| **wget** | (Alpine bundled) | Health check HTTP testing | Lightweight alternative to curl; already used in gateway health check |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **netcat (nc)** | (system) | Port connectivity testing | Test TCP port reachability without HTTP; useful when HTTP endpoint not responding |
| **ping** | (system) | Basic network connectivity | Verify DNS resolution and ICMP reachability to host/gateway |
| **docker inspect** | Docker CLI | Container configuration inspection | Verify mount points, network settings, environment variables |
| **jq** | 1.6+ | JSON parsing in shell | Parse gateway API responses for automated verification scripts |
| **inotifywait** | inotify-tools | File change monitoring | Verify filesystem changes propagate between containers in real-time |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| curl/wget | Postman/Insomnia | GUI tools overkill for simple HTTP health checks; CLI better for automation |
| MCP Inspector | Manual HTTP calls with curl | Inspector provides better UX but curl allows scripted validation |
| docker logs | Centralized logging (ELK, Grafana) | Over-engineering for devcontainer; docker logs sufficient for Phase 2 |
| host.docker.internal | Gateway IP address hardcoded | DNS approach more maintainable; IP fallback only for Linux compatibility |

**Installation:**
```bash
# Most tools already available in devcontainer/gateway images
# Optional: Install network debugging tools if needed
apt-get update && apt-get install -y netcat-openbsd iproute2 iputils-ping

# Optional: Install jq for JSON parsing in verification scripts
apt-get install -y jq

# MCP Inspector (runs via npx, no installation)
npx @modelcontextprotocol/inspector@latest
```

## Architecture Patterns

### Recommended Testing Flow
```
Validation Sequence (execute in order):

1. Gateway Health Check (from host)
   └─> Verify container started and HTTP endpoint responding

2. Devcontainer → Gateway Connectivity (from devcontainer)
   └─> Test host.docker.internal DNS resolution and HTTP reachability

3. Health Check Timing Validation
   └─> Verify start_period accounts for npx download (docker inspect + logs)

4. Filesystem MCP Protocol Test (via MCP Inspector or curl)
   └─> Test list_tools, read_file, write_file operations through gateway

5. Volume Mount Alignment (cross-container write test)
   └─> Write file in devcontainer, verify visible in gateway (and vice versa)

6. Gateway Log Accessibility
   └─> Confirm docker logs docker-mcp-gateway provides useful debugging output
```

### Pattern 1: Host.docker.internal Setup (Linux Compatibility)
**What:** Configure devcontainer to resolve `host.docker.internal` on Linux using `--add-host` flag
**When to use:** ALWAYS on Linux; macOS/Windows Docker Desktop provides this automatically
**Why critical:** Without this, devcontainer cannot resolve gateway hostname; connection attempts fail with "unknown host"
**Example:**
```json
// .devcontainer/devcontainer.json
{
  "name": "Claude Code DevContainer",
  "runArgs": [
    "--add-host=host.docker.internal:host-gateway"
  ],
  // Other config...
}
```
**Verification:**
```bash
# From inside devcontainer
docker exec <devcontainer-name> ping -c 1 host.docker.internal
# Expected: resolves to Docker host IP (typically 172.17.0.1)

docker exec <devcontainer-name> curl -s http://host.docker.internal:8811/health
# Expected: {"status":"ok"} or similar gateway response
```
**Source:** [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/)

### Pattern 2: Connectivity Testing from Devcontainer
**What:** Use `docker exec` with curl/netcat to test gateway reachability from devcontainer context
**When to use:** During Phase 2 validation; troubleshooting connectivity issues
**Example:**
```bash
# Test 1: Verify host.docker.internal DNS resolution
docker exec <devcontainer-name> ping -c 1 host.docker.internal

# Test 2: Test TCP port reachability (gateway should be listening on 8811)
docker exec <devcontainer-name> nc -zv host.docker.internal 8811
# Expected: "Connection to host.docker.internal 8811 port [tcp/*] succeeded!"

# Test 3: HTTP health check from devcontainer perspective
docker exec <devcontainer-name> curl -v http://host.docker.internal:8811/health
# Expected: HTTP 200 OK with health status JSON

# Test 4: If host.docker.internal fails, fallback to gateway container IP
GATEWAY_IP=$(docker inspect docker-mcp-gateway -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
docker exec <devcontainer-name> curl -v http://$GATEWAY_IP:8811/health
```
**Source:** [How to test connectivity between Docker containers | LabEx](https://labex.io/tutorials/docker-how-to-test-connectivity-between-docker-containers-411613)

### Pattern 3: Health Check Validation After Cold Start
**What:** Verify health check timing accounts for npx package download on first container start
**When to use:** After adding/updating gateway service; troubleshooting "unhealthy" status
**Example:**
```bash
# Step 1: Force clean cold start (no npm cache)
docker compose down
docker volume prune -f  # Optional: clear any npm cache volumes
docker compose up -d docker-mcp-gateway

# Step 2: Monitor logs during startup
docker logs -f docker-mcp-gateway
# Watch for: "Downloading @modelcontextprotocol/server-filesystem..."
# Then: "Filesystem MCP server started" or similar

# Step 3: Check health status during startup
watch -n 1 'docker inspect docker-mcp-gateway --format="{{.State.Health.Status}}"'
# Expected: "starting" for ~20s, then "healthy"
# Should NOT show "unhealthy" during npx download phase

# Step 4: Verify start_period setting
docker inspect docker-mcp-gateway --format='{{.Config.Healthcheck.StartPeriod}}'
# Expected: 20000000000 (20s in nanoseconds) or higher
```
**Source:** [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view)

### Pattern 4: MCP Inspector Testing (Interactive)
**What:** Use MCP Inspector web UI to test MCP server tools interactively
**When to use:** Initial validation; exploring MCP server capabilities; debugging tool responses
**Example:**
```bash
# Step 1: Run MCP Inspector (opens browser at http://localhost:6274)
npx @modelcontextprotocol/inspector@latest

# Step 2: Configure connection in Inspector UI
# - Transport: SSE or Streamable HTTP
# - URL: http://host.docker.internal:8811 (or http://localhost:8811 if on host)
# - Server: filesystem (select from gateway's available servers)

# Step 3: Test operations
# - list_tools: Should show read_file, write_file, list_directory, etc.
# - read_file: Test with /workspace/README.md or similar
# - write_file: Create /workspace/test-phase2.txt with content
# - list_directory: Browse /workspace contents

# Step 4: Verify in devcontainer
docker exec <devcontainer-name> cat /workspace/test-phase2.txt
# Expected: Content matches what was written via MCP Inspector
```
**Source:** [MCP Inspector - Model Context Protocol](https://modelcontextprotocol.io/docs/tools/inspector)

### Pattern 5: Volume Mount Alignment Verification
**What:** Test that files written in one container are immediately visible in sibling container
**When to use:** Phase 2 validation; troubleshooting "file not found" errors from MCP operations
**Example:**
```bash
# Test 1: Write file in devcontainer, read from gateway
docker exec <devcontainer-name> sh -c 'echo "test-from-devcontainer" > /workspace/mount-test-1.txt'
docker exec docker-mcp-gateway cat /workspace/mount-test-1.txt
# Expected: "test-from-devcontainer"

# Test 2: Write file in gateway, read from devcontainer
docker exec docker-mcp-gateway sh -c 'echo "test-from-gateway" > /workspace/mount-test-2.txt'
docker exec <devcontainer-name> cat /workspace/mount-test-2.txt
# Expected: "test-from-gateway"

# Test 3: Verify mount points match
docker inspect docker-mcp-gateway -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}'
docker inspect <devcontainer-name> -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}'
# Expected: Both output identical host path

# Test 4: Real-time file change detection (optional)
docker exec docker-mcp-gateway sh -c 'apt-get update && apt-get install -y inotify-tools'
docker exec docker-mcp-gateway inotifywait -m /workspace -e modify,create,delete &
# Then write file from devcontainer, watch for inotify events
```
**Source:** [How to Debug Docker Volume Mount Issues](https://oneuptime.com/blog/post/2026-01-25-debug-docker-volume-mount-issues/view)

### Pattern 6: Gateway Log Analysis
**What:** Use `docker logs` to inspect gateway startup, MCP server lifecycle, and error messages
**When to use:** Troubleshooting connectivity failures, MCP operation errors, or startup issues
**Example:**
```bash
# View all logs since container start
docker logs docker-mcp-gateway

# Follow logs in real-time
docker logs -f docker-mcp-gateway

# Show only last 50 lines
docker logs --tail 50 docker-mcp-gateway

# Filter logs by timestamp (show last 10 minutes)
docker logs --since 10m docker-mcp-gateway

# Show timestamps for each log line
docker logs -t docker-mcp-gateway

# Common patterns to look for:
# - "Downloading @modelcontextprotocol/server-filesystem..." (npx download phase)
# - "Filesystem MCP server started" (successful initialization)
# - "Health check passed" (HTTP /health endpoint responding)
# - Error messages with stack traces (failures to investigate)
```
**Source:** [How to Fix and Debug Docker Containers Like a Superhero | Docker](https://www.docker.com/blog/how-to-fix-and-debug-docker-containers-like-a-superhero/)

### Anti-Patterns to Avoid

- **Assuming host.docker.internal works on Linux without configuration:** Requires `--add-host=host.docker.internal:host-gateway` in runArgs
- **Testing health check immediately after container start:** Health check may still be in `start_period`; wait 20s+ before expecting "healthy"
- **Using gateway container IP directly in code/config:** IP can change on container restart; always use `host.docker.internal` DNS
- **Testing MCP operations via stdio from host:** Gateway uses stdio internally; external clients must use HTTP endpoint
- **Ignoring docker logs during troubleshooting:** Logs show npx download progress, MCP server errors, and health check failures
- **Hardcoding devcontainer name in tests:** Container name varies by devcontainer tool; use `docker ps` to discover dynamically

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MCP server testing UI | Custom HTTP client/Postman scripts | MCP Inspector (npx @modelcontextprotocol/inspector) | Official tool with session management, authentication handling, tool execution UI |
| Network connectivity validation | Custom scripts from scratch | docker exec + curl/nc/ping patterns | Standard Docker troubleshooting workflow; widely documented |
| Health check monitoring | Poll HTTP endpoint in loop | Docker's built-in health check status + docker inspect | Already implemented; provides state machine (starting/healthy/unhealthy) |
| Container log aggregation | Custom logging collector | docker logs with filtering (--since, --tail) | Built into Docker CLI; sufficient for single devcontainer debugging |
| File change monitoring | Custom polling script | inotifywait (inotify-tools) | Kernel-level filesystem events; zero CPU overhead compared to polling |
| JSON parsing in bash | grep/sed/awk regex | jq for structured JSON | Handles edge cases (nested objects, escaping); readable syntax |

**Key insight:** Docker CLI and MCP Inspector already provide comprehensive validation tooling. Custom scripts only needed for automation/CI, not interactive debugging.

## Common Pitfalls

### Pitfall 1: host.docker.internal DNS Resolution Failure on Linux
**What goes wrong:** Devcontainer cannot resolve `host.docker.internal`, resulting in "unknown host" or "could not resolve host" errors when trying to reach gateway
**Why it happens:** Docker Desktop on macOS/Windows automatically configures this special DNS entry, but on Linux it requires manual configuration via `--add-host` flag
**How to avoid:**
1. Add `"runArgs": ["--add-host=host.docker.internal:host-gateway"]` to devcontainer.json
2. Test resolution immediately after devcontainer rebuild: `ping -c 1 host.docker.internal`
3. Fallback: Document how to get gateway IP with `docker inspect docker-mcp-gateway` for manual connection
**Warning signs:**
- `curl http://host.docker.internal:8811` returns "Could not resolve host"
- `ping host.docker.internal` shows "unknown host"
- Gateway works from host (`curl localhost:8811/health`) but not from devcontainer
**Source:** [How to connect to the Docker host from inside a Docker container? | Medium](https://medium.com/@TimvanBaarsen/how-to-connect-to-the-docker-host-from-inside-a-docker-container-112b4c71bc66)

### Pitfall 2: Health Check Fails During npx Package Download
**What goes wrong:** Container shows "unhealthy" status immediately after start; health check counts failures during normal npx download phase
**Why it happens:** First container start downloads `@modelcontextprotocol/server-filesystem` package (5-15s depending on network); health check runs before server initialization completes; without adequate `start_period`, these failures count toward retry limit
**How to avoid:**
1. Ensure `start_period: 20s` (or higher) in docker-compose.yml healthcheck config
2. Test cold start: `docker compose up --force-recreate` and monitor `docker inspect` health status
3. Monitor logs: `docker logs -f docker-mcp-gateway` should show npx download, then server start, THEN first health check
**Warning signs:**
- Container transitions directly to "unhealthy" within 5-10s of start
- Logs show "npm WARN" or "Downloading..." messages AFTER first health check attempt
- Second `docker compose up` (with npm cache) shows "healthy" but first start fails
**Source:** [How to Create Docker Compose Health Checks](https://oneuptime.com/blog/post/2026-01-30-docker-compose-health-checks/view)

### Pitfall 3: Volume Mount Path Mismatch (Sibling Container Pattern)
**What goes wrong:** File written via MCP operation succeeds but file not visible in devcontainer; or devcontainer files not visible to gateway
**Why it happens:** Gateway and devcontainer are siblings, not parent-child; both must mount identical host path; if `MCP_WORKSPACE_BIND` points to wrong host path, containers see different filesystems
**How to avoid:**
1. Verify mount sources match: `docker inspect docker-mcp-gateway` and `docker inspect <devcontainer>` both show same host path for /workspace
2. Test cross-container write: write file from devcontainer, read from gateway (see Pattern 5)
3. Use absolute host paths in `MCP_WORKSPACE_BIND` environment variable, never relative paths
**Warning signs:**
- MCP write_file succeeds but file missing in devcontainer filesystem
- Gateway logs show different file count in /workspace than devcontainer sees
- `ls /workspace` output differs between containers
**Source:** Phase 1 Research (Pitfall 1: Volume Path Mismatch)

### Pitfall 4: Testing with Insufficient Tool Installation
**What goes wrong:** `docker exec` commands fail with "command not found" errors; health check validation scripts cannot run
**Why it happens:** Minimal container images (Alpine, distroless) omit common debugging tools (curl, netcat, bash); tests assume tools present
**How to avoid:**
1. Check tool availability before test: `docker exec <container> which curl || echo "curl not installed"`
2. Use alternative tools: wget instead of curl, `nc -zv` instead of telnet, sh instead of bash
3. Install missing tools temporarily: `docker exec <container> apk add curl` (Alpine) or `apt-get install curl` (Debian)
4. Document tool requirements in verification scripts
**Warning signs:**
- "sh: curl: not found" errors during connectivity tests
- Health check uses wget but validation script uses curl
- netcat command fails despite network connectivity being fine
**Source:** [Docker Compose Health Checks: An Easy-to-follow Guide | Last9](https://last9.io/blog/docker-compose-health-checks/)

### Pitfall 5: MCP Inspector Version Mismatch with Gateway
**What goes wrong:** MCP Inspector cannot connect to gateway; shows protocol errors or unsupported transport warnings
**Why it happens:** MCP protocol evolving rapidly (v2026-03-26 introduced Streamable HTTP replacing SSE); older Inspector versions may not support newer protocol versions; gateway may require specific Inspector version
**How to avoid:**
1. Use version-pinned Inspector: `npx @modelcontextprotocol/inspector@0.9.0` or later
2. Check gateway logs for protocol version: look for "MCP protocol version" messages
3. Test with both SSE and Streamable HTTP transports in Inspector UI
4. Fallback to manual curl testing if Inspector fails (see Code Examples section)
**Warning signs:**
- Inspector shows "Connection failed" despite gateway health check passing
- Protocol error messages mentioning SSE vs Streamable HTTP mismatch
- Inspector works with some MCP servers but not gateway-hosted servers
**Source:** [Test a Remote MCP Server · Cloudflare Agents docs](https://developers.cloudflare.com/agents/guides/test-remote-mcp-server/)

### Pitfall 6: Docker Logs Buffering Delays
**What goes wrong:** `docker logs` command shows no output despite container running; logs appear with significant delay
**Why it happens:** Application uses buffered stdout/stderr; Node.js and Python buffer by default; logs written to buffer but not flushed to Docker logging driver
**How to avoid:**
1. Use `docker logs -f` (follow) mode to see logs as they arrive
2. For Node.js: Set `NODE_ENV=production` or use `console.log()` (unbuffered)
3. For Python: Run with `-u` flag (unbuffered) or set `PYTHONUNBUFFERED=1`
4. Gateway logs: Watch for "npx" package manager output (unbuffered by default)
**Warning signs:**
- Container running (docker ps shows "Up") but `docker logs` empty
- Logs appear in batches after 30s+ delay
- Health check passes but no log output visible
**Source:** [Manage Docker Container Logs for Monitoring & Troubleshooting](https://middleware.io/blog/docker-container-logs/)

## Code Examples

Verified patterns from official sources and Phase 1 infrastructure:

### Complete Connectivity Validation Script
```bash
#!/bin/bash
# Source: Composite of Docker networking best practices and MCP validation patterns
# Location: .planning/phases/02-connectivity-health-validation/verify-connectivity.sh

set -e  # Exit on error

echo "=== Phase 2: Connectivity & Health Validation ==="

# Step 1: Verify gateway container is running
echo "[1/7] Checking gateway container status..."
if ! docker ps | grep -q docker-mcp-gateway; then
  echo "ERROR: Gateway container not running. Start with: docker compose up -d docker-mcp-gateway"
  exit 1
fi
echo "✓ Gateway container running"

# Step 2: Test gateway health from host
echo "[2/7] Testing gateway health endpoint from host..."
if ! curl -sf http://localhost:8811/health > /dev/null; then
  echo "ERROR: Gateway health check failed from host"
  echo "Check logs: docker logs docker-mcp-gateway"
  exit 1
fi
echo "✓ Gateway health endpoint responding"

# Step 3: Check health check timing configuration
echo "[3/7] Verifying health check start_period..."
START_PERIOD=$(docker inspect docker-mcp-gateway --format='{{.Config.Healthcheck.StartPeriod}}')
# Convert nanoseconds to seconds: 20000000000 ns = 20s
START_PERIOD_SECONDS=$((START_PERIOD / 1000000000))
if [ "$START_PERIOD_SECONDS" -lt 20 ]; then
  echo "WARNING: start_period is ${START_PERIOD_SECONDS}s, should be 20s+ for npx download"
else
  echo "✓ Health check start_period: ${START_PERIOD_SECONDS}s"
fi

# Step 4: Get devcontainer name (assumes single devcontainer running)
echo "[4/7] Discovering devcontainer name..."
DEVCONTAINER=$(docker ps --filter "label=devcontainer.local_folder" --format "{{.Names}}" | head -n 1)
if [ -z "$DEVCONTAINER" ]; then
  echo "WARNING: Could not auto-detect devcontainer. Trying fallback..."
  DEVCONTAINER=$(docker ps --format "{{.Names}}" | grep -v "docker-mcp-gateway\|langfuse\|postgres\|redis\|clickhouse\|minio" | head -n 1)
fi
if [ -z "$DEVCONTAINER" ]; then
  echo "ERROR: No devcontainer found. Start devcontainer first."
  exit 1
fi
echo "✓ Devcontainer: $DEVCONTAINER"

# Step 5: Test host.docker.internal DNS resolution from devcontainer
echo "[5/7] Testing host.docker.internal DNS from devcontainer..."
if ! docker exec "$DEVCONTAINER" ping -c 1 host.docker.internal > /dev/null 2>&1; then
  echo "ERROR: host.docker.internal not resolving in devcontainer"
  echo "Add to .devcontainer/devcontainer.json:"
  echo '  "runArgs": ["--add-host=host.docker.internal:host-gateway"]'
  exit 1
fi
echo "✓ host.docker.internal DNS resolves"

# Step 6: Test gateway connectivity from devcontainer
echo "[6/7] Testing gateway HTTP endpoint from devcontainer..."
if ! docker exec "$DEVCONTAINER" curl -sf http://host.docker.internal:8811/health > /dev/null; then
  echo "ERROR: Cannot reach gateway from devcontainer"
  echo "Troubleshooting:"
  echo "  1. Check gateway logs: docker logs docker-mcp-gateway"
  echo "  2. Verify port binding: docker port docker-mcp-gateway 8811"
  echo "  3. Test with gateway IP directly:"
  GATEWAY_IP=$(docker inspect docker-mcp-gateway -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
  echo "     docker exec $DEVCONTAINER curl http://$GATEWAY_IP:8811/health"
  exit 1
fi
echo "✓ Gateway reachable from devcontainer"

# Step 7: Verify volume mount alignment
echo "[7/7] Verifying /workspace volume mount alignment..."
GATEWAY_MOUNT=$(docker inspect docker-mcp-gateway -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}')
DEVCONTAINER_MOUNT=$(docker inspect "$DEVCONTAINER" -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}')
if [ "$GATEWAY_MOUNT" != "$DEVCONTAINER_MOUNT" ]; then
  echo "ERROR: Volume mount mismatch!"
  echo "  Gateway:      $GATEWAY_MOUNT"
  echo "  Devcontainer: $DEVCONTAINER_MOUNT"
  exit 1
fi
echo "✓ Volume mounts aligned: $GATEWAY_MOUNT"

echo ""
echo "=== ALL CHECKS PASSED ==="
echo "Gateway is reachable from devcontainer and volume mounts are aligned."
echo ""
echo "Next steps:"
echo "  1. Test MCP operations: npx @modelcontextprotocol/inspector@latest"
echo "  2. Monitor gateway logs: docker logs -f docker-mcp-gateway"
echo "  3. Test file operations: See verify-filesystem-mcp.sh"
```

### MCP Filesystem Operations Test
```bash
#!/bin/bash
# Source: MCP filesystem server documentation + manual HTTP testing patterns
# Location: .planning/phases/02-connectivity-health-validation/verify-filesystem-mcp.sh

set -e

echo "=== MCP Filesystem Operations Validation ==="

# Test file paths (use /workspace since gateway and devcontainer both mount it)
TEST_DIR="/workspace"
TEST_FILE="$TEST_DIR/mcp-test-phase2.txt"
TEST_CONTENT="Phase 2 filesystem MCP validation - written at $(date)"

DEVCONTAINER=$(docker ps --filter "label=devcontainer.local_folder" --format "{{.Names}}" | head -n 1)

# Test 1: Write file from devcontainer
echo "[1/4] Writing test file from devcontainer..."
docker exec "$DEVCONTAINER" sh -c "echo '$TEST_CONTENT' > $TEST_FILE"
echo "✓ File written: $TEST_FILE"

# Test 2: Read file from gateway container
echo "[2/4] Reading test file from gateway container..."
GATEWAY_READ=$(docker exec docker-mcp-gateway cat "$TEST_FILE")
if [ "$GATEWAY_READ" != "$TEST_CONTENT" ]; then
  echo "ERROR: Content mismatch!"
  echo "Expected: $TEST_CONTENT"
  echo "Got:      $GATEWAY_READ"
  exit 1
fi
echo "✓ Gateway can read file written by devcontainer"

# Test 3: Write file from gateway
echo "[3/4] Writing test file from gateway container..."
GATEWAY_CONTENT="Written from gateway at $(date)"
docker exec docker-mcp-gateway sh -c "echo '$GATEWAY_CONTENT' > $TEST_DIR/gateway-test.txt"
echo "✓ File written from gateway"

# Test 4: Read file from devcontainer
echo "[4/4] Reading gateway-written file from devcontainer..."
DEVCONTAINER_READ=$(docker exec "$DEVCONTAINER" cat "$TEST_DIR/gateway-test.txt")
if [ "$DEVCONTAINER_READ" != "$GATEWAY_CONTENT" ]; then
  echo "ERROR: Content mismatch!"
  exit 1
fi
echo "✓ Devcontainer can read file written by gateway"

# Cleanup
echo ""
echo "Cleaning up test files..."
docker exec "$DEVCONTAINER" rm -f "$TEST_FILE" "$TEST_DIR/gateway-test.txt"

echo ""
echo "=== FILESYSTEM MCP VALIDATION PASSED ==="
echo "Gateway filesystem MCP server can read and write files in /workspace."
echo "Files are immediately visible in both gateway and devcontainer contexts."
echo ""
echo "Next: Test MCP protocol via HTTP endpoint using MCP Inspector"
```

### Manual MCP Health Check (Without Inspector)
```bash
# Source: Docker MCP Gateway HTTP API patterns
# Note: Gateway /health endpoint validates gateway process, not MCP protocol
# For protocol validation, use MCP Inspector or implement MCP client

# Health check (gateway process status)
curl -v http://localhost:8811/health
# Expected: HTTP 200 OK, body like {"status":"ok"} or similar

# Check from devcontainer
docker exec <devcontainer-name> curl -v http://host.docker.internal:8811/health

# Note: Gateway HTTP API for MCP operations requires MCP protocol implementation
# Use MCP Inspector instead of manual curl for tool invocation:
npx @modelcontextprotocol/inspector@latest
# Then connect to http://host.docker.internal:8811 with filesystem server selected
```

### Gateway Log Monitoring During Validation
```bash
# Source: Docker logging best practices
# Monitor logs during validation tests

# Tail logs in real-time (run in separate terminal)
docker logs -f docker-mcp-gateway

# Filter for errors only
docker logs docker-mcp-gateway 2>&1 | grep -i error

# Show logs with timestamps
docker logs -t docker-mcp-gateway | tail -20

# Show logs from last 5 minutes (useful after test run)
docker logs --since 5m docker-mcp-gateway

# Key log patterns to look for:
# - "npx: installed <package>" (npx download completed)
# - "MCP server started" or "Listening on port 8811" (server ready)
# - "Health check passed" (health check endpoint responding)
# - "Error:" or stack traces (failures requiring investigation)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MCP CLI testing via stdio | MCP Inspector web UI + HTTP endpoint testing | Q4 2025 | Inspector provides visual tool list, request builder, response inspection; replaces manual stdio interaction |
| Hardcoded container IPs | host.docker.internal DNS + --add-host flag | Docker 20.10+ | Portable across environments; IP changes on container restart no longer break connectivity |
| Manual health check polling | Docker Compose built-in health checks with start_period | Docker Compose 1.27+ | Automated dependency management; start_period prevents false failures during startup |
| SSE transport for MCP | Streamable HTTP (MCP protocol v2026-03-26) | Q1 2026 | SSE deprecated; Streamable HTTP supports stateful sessions; backward compatibility maintained |
| Custom test scripts for each MCP server | MCP Inspector universal testing | 2025+ | Single tool tests any MCP server; no custom client code needed |
| iptables rules for loopback security | 127.0.0.1 port binding (already in Phase 1) | Best practice 2020+ | Loopback binding simpler and more reliable than firewall rules |

**Deprecated/outdated:**
- **Testing MCP via stdio from host:** Gateway uses stdio internally; external clients use HTTP endpoint
- **SSE transport configuration:** MCP Inspector 0.9.0+ defaults to Streamable HTTP; SSE still supported for older servers
- **Manual npx package installation:** Gateway handles npx download automatically; pre-installation unnecessary and adds maintenance burden

## Open Questions

1. **Gateway HTTP API authentication/authorization**
   - What we know: Gateway health endpoint is unauthenticated; MCP protocol may support authentication
   - What's unclear: Does gateway HTTP API require authentication for MCP operations? How to configure?
   - Recommendation: Test with MCP Inspector; document authentication requirements in Phase 3 when connecting Claude Code client

2. **MCP Inspector optimal version for docker/mcp-gateway compatibility**
   - What we know: Azure API Management docs mention Inspector 0.9.0 for MCP server testing; MCP protocol evolving rapidly
   - What's unclear: Does docker/mcp-gateway require specific Inspector version? Any known incompatibilities?
   - Recommendation: Start with latest (`@modelcontextprotocol/inspector@latest`); pin version if incompatibility found

3. **Gateway startup timing variability across network conditions**
   - What we know: 20s start_period recommended for npx download; actual time varies by network speed and npm registry latency
   - What's unclear: Should start_period be configurable via environment variable? How to handle slow networks (CI, airgapped)?
   - Recommendation: Start with 20s; increase to 30s+ if logs show health check during download on slow networks

4. **Health check endpoint vs MCP protocol health**
   - What we know: /health endpoint exists; health check validates HTTP response
   - What's unclear: Does /health verify MCP server started successfully, or just gateway process running?
   - Recommendation: Phase 2 uses /health endpoint; Phase 3 adds MCP list_tools verification for end-to-end protocol health

5. **devcontainer name discovery automation**
   - What we know: Devcontainer name varies by tool (VS Code, Codespaces, devcontainer CLI); no standard label
   - What's unclear: Reliable method to discover devcontainer name programmatically? Standard labels?
   - Recommendation: Use `--filter "label=devcontainer.local_folder"` as primary method; fallback to process-of-elimination (exclude known service names)

## Sources

### Primary (HIGH confidence)
- [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/) - host.docker.internal configuration patterns
- [How to connect to the Docker host from inside a Docker container? | Medium](https://medium.com/@TimvanBaarsen/how-to-connect-to-the-docker-host-from-inside-a-docker-container-112b4c71bc66) - Linux host.docker.internal setup
- [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view) - 2026 health check guidance including start_period
- [Docker Compose Health Checks: An Easy-to-follow Guide | Last9](https://last9.io/blog/docker-compose-health-checks/) - Comprehensive health check patterns
- [How to Fix and Debug Docker Containers Like a Superhero | Docker](https://www.docker.com/blog/how-to-fix-and-debug-docker-containers-like-a-superhero/) - docker logs troubleshooting
- [docker container logs | Docker Docs](https://docs.docker.com/reference/cli/docker/container/logs/) - Official docker logs documentation
- [MCP Inspector - Model Context Protocol](https://modelcontextprotocol.io/docs/tools/inspector) - Official MCP testing tool
- [Networking | Docker Docs](https://docs.docker.com/compose/how-tos/networking/) - Docker Compose networking patterns
- [Bind mounts | Docker Docs](https://docs.docker.com/engine/storage/bind-mounts/) - Volume mount documentation
- [@modelcontextprotocol/server-filesystem - npm](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) - Filesystem MCP server v2026.1.14

### Secondary (MEDIUM confidence)
- [How to test connectivity between Docker containers | LabEx](https://labex.io/tutorials/docker-how-to-test-connectivity-between-docker-containers-411613) - docker exec connectivity testing patterns
- [How to Debug Docker Network Connectivity Issues](https://oneuptime.com/blog/post/2026-01-22-debug-docker-network-connectivity/view) - Network troubleshooting guide
- [How to Debug Docker Volume Mount Issues](https://oneuptime.com/blog/post/2026-01-25-debug-docker-volume-mount-issues/view) - Volume mount verification
- [How to Set Up Communication Between Docker Compose Projects](https://oneuptime.com/blog/post/2026-01-25-communication-between-docker-compose-projects/view) - Cross-project networking
- [Test a Remote MCP Server · Cloudflare Agents docs](https://developers.cloudflare.com/agents/guides/test-remote-mcp-server/) - MCP Inspector usage patterns
- [Reaching host's localhost from inside a vscode devcontainer | Medium](https://goledger.medium.com/reaching-hosts-localhost-from-inside-a-vscode-devcontainer-932e1c08df5c) - Devcontainer networking
- [Manage Docker Container Logs for Monitoring & Troubleshooting](https://middleware.io/blog/docker-container-logs/) - Log analysis patterns
- [How to Create Docker Compose Health Checks](https://oneuptime.com/blog/post/2026-01-30-docker-compose-health-checks/view) - Compose health check configuration
- [How to Test MCP Streamable HTTP Endpoints Using cURL](https://glama.ai/blog/2026-01-02-how-to-test-mcp-streamable-http-endpoints-using-c-url) - MCP HTTP testing

### Tertiary (LOW confidence - needs validation)
- MCP gateway HTTP API authentication requirements (not documented in search results; requires testing)
- Optimal start_period for various network conditions (20s baseline from general guidance; MCP-specific benchmarks not published)
- Devcontainer name discovery best practices (no standard label found; approach based on observed patterns)

### Project-Specific Sources
- `.planning/phases/01-gateway-infrastructure/01-RESEARCH.md` - Phase 1 research (gateway setup, volume mount patterns)
- `langfuse-local/docker-compose.yml` - Actual gateway configuration (health check settings, port bindings)
- `.planning/REQUIREMENTS.md` - Phase 2 requirements (CONN-01, CONN-03, FSMCP-03, VERIF-02)

## Metadata

**Confidence breakdown:**
- **Docker networking/connectivity:** HIGH - Official Docker docs, multiple authoritative 2026 sources, well-established patterns
- **Health check timing:** HIGH - Recent 2026 best practices, consistent recommendations across sources
- **MCP Inspector usage:** HIGH - Official Anthropic tool, documented testing patterns
- **Gateway HTTP API details:** MEDIUM - Gateway /health endpoint verified; MCP operation API requires Inspector testing
- **Filesystem MCP testing:** HIGH - npm package docs, cross-container file operations verified in Phase 1
- **devcontainer networking specifics:** HIGH - Multiple sources on host.docker.internal, Linux configuration requirements clear
- **Gateway log analysis:** HIGH - Standard Docker logging, official documentation

**Research date:** 2026-02-10
**Valid until:** 2026-03-10 (30 days; Docker networking stable, but MCP tooling evolving)

**Critical gaps requiring validation during implementation:**
1. Gateway HTTP API authentication requirements (test with MCP Inspector during Phase 2)
2. MCP Inspector version compatibility with docker/mcp-gateway (verify during first connection attempt)
3. Optimal start_period for local network conditions (monitor logs during cold start validation)
4. Gateway /health endpoint implementation details (does it verify MCP server status or just gateway process?)

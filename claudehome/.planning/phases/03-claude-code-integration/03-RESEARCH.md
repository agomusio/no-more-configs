# Phase 3: Claude Code Integration - Research

**Researched:** 2026-02-13
**Domain:** Claude Code MCP client configuration, shell automation, startup orchestration, project-scoped MCP discovery
**Confidence:** HIGH

## Summary

Phase 3 establishes automated Claude Code connectivity to the MCP gateway deployed in Phase 1. The implementation centers on a shell alias that generates `.mcp.json` in the workspace root, polls the gateway health endpoint with timeout, and provides inline documentation for adding MCP servers. This approach leverages Claude Code's project-scoped configuration auto-discovery, eliminates manual setup, and maintains the devcontainer's ephemeral nature while ensuring MCP tools are available immediately when Claude Code sessions start.

**Critical insight:** Claude Code auto-discovers `.mcp.json` at the workspace root when configured with `--scope project`. The file uses a standardized JSON format with `mcpServers` object containing server definitions. SSE transport is deprecated but still supported; HTTP transport (type: "http") is now preferred for remote servers. Project-scoped MCP servers require user approval on first use for security. Shell functions are strongly preferred over aliases when parameter handling is needed.

**Primary recommendation:** Create a shell function (not alias) in .zshrc that generates `.mcp.json` with a single gateway SSE endpoint, polls `http://host.docker.internal:8811/health` with 30-second timeout using curl retry logic, and includes commented-out example MCP servers (github, postgres, docker) for inline documentation. Use HTTP health endpoint checks rather than TCP port checks for better application-level validation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Configuration method:**
- `.mcp.json` in workspace root (per-project, Claude Code auto-discovers)
- Generated dynamically on startup, NOT a static committed file
- Triggered via shell alias defined in shell profile (.zshrc)
- Gateway URL sourced from `MCP_GATEWAY_URL` environment variable (set in devcontainer config)
- Single gateway SSE endpoint in `.mcp.json` — gateway handles multiplexing to individual servers internally

**Startup resilience:**
- Block until gateway is ready (poll health endpoint), up to 30 second timeout
- If gateway doesn't come up within 30s: warn and continue (Claude Code starts without MCP)
- Health check method: Claude's discretion (HTTP health endpoint vs TCP port check)

**Multi-server workflow:**
- Adding a server: edit gateway's `mcp.json`, restart gateway container, re-run the same shell alias
- `.mcp.json` points to single gateway endpoint — no per-server client config changes needed
- After re-running alias: update config + prompt user to restart Claude Code session to pick up changes

**Documentation approach:**
- Inline in `mcp.json` as commented-out examples — right where the user edits
- Moderate depth: example entry + 2-3 common MCP servers pre-configured but commented out
- Claude picks which example servers are most relevant to this devcontainer ecosystem
- No troubleshooting section — keep it lean, happy path only

### Claude's Discretion

- Health check method (HTTP endpoint vs TCP port check)
- Which common MCP servers to include as commented-out examples (2-3 relevant to this devcontainer)
- Exact alias name and implementation details
- Config generation script structure

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **.mcp.json** | Format v1 | Project-scoped MCP config | Official Claude Code project configuration format; auto-discovered at workspace root |
| **curl** | (bundled) | Health check HTTP client | Universal HTTP client with built-in retry logic (`--retry`, `--retry-delay`, `-m` timeout); already available in devcontainer |
| **Shell function** | bash/zsh | Config generation + health check | Preferred over alias for parameter handling and multi-line logic; Google Shell Style Guide recommendation |
| **jq** | 1.6+ | JSON generation | Industry-standard JSON processor; safer than echo/heredoc for generating valid JSON |
| **environment variables** | N/A | Gateway URL configuration | Standard devcontainer pattern; set in devcontainer.json `containerEnv`, accessible in shell profile |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **timeout** | (coreutils) | Command timeout wrapper | Wrap entire health check loop; provides hard deadline for startup blocking |
| **sleep** | (coreutils) | Poll interval delay | Wait between health check attempts (1-2s intervals recommended) |
| **netcat (nc)** | (bundled) | TCP port check fallback | Alternative health check if HTTP endpoint unreliable; `-z` flag for zero-I/O port scan |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| .mcp.json (project) | settings.local.json (local) | Local scope isolates config per-user; project scope shares with team via VCS; project preferred for team consistency |
| Shell function | Shell alias | Aliases cannot handle parameter positioning; functions required for health check logic and JSON generation |
| curl | wget | Both work; curl has better retry syntax (`--retry 30 --retry-delay 1`); wget requires manual loop |
| HTTP health check | TCP port check (nc -z) | HTTP validates application readiness; TCP only checks port listening; HTTP preferred per 2026 best practices |
| jq | echo/heredoc | Heredoc simpler for static JSON; jq required for env var substitution and escaping; jq safer for production |
| postStartCommand | Shell alias/function | postStartCommand runs once on container start; alias allows manual refresh; alias preferred for flexibility |

**Installation:**
```bash
# Most tools already available in devcontainer
# Optional: Install jq if not present
apt-get update && apt-get install -y jq

# Optional: Verify curl supports retry flags
curl --help | grep -E 'retry|max-time'
```

## Architecture Patterns

### Recommended Shell Function Structure
```bash
# .zshrc or .bashrc
# Function name: claude-mcp-init (user-friendly, memorable)
# Responsibilities:
# 1. Generate .mcp.json in workspace root
# 2. Poll gateway health with timeout
# 3. Provide user feedback on success/failure
# 4. Include commented examples for user customization

claude-mcp-init() {
  # 1. Validate environment
  # 2. Generate .mcp.json with gateway SSE endpoint
  # 3. Poll health endpoint with 30s timeout
  # 4. Report status to user
}
```

### Pattern 1: Project-Scoped .mcp.json Generation
**What:** Generate `.mcp.json` at workspace root with standardized format
**When to use:** Every devcontainer startup; manual refresh when adding servers
**Why critical:** Claude Code auto-discovers this file; project scope enables team sharing via version control
**Example:**
```json
// .mcp.json (generated, NOT committed)
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "http://host.docker.internal:8811"
    }
  }
}
```
**Verification:**
```bash
# Verify file generated correctly
cat /workspace/.mcp.json | jq .

# Verify Claude Code discovers it
# Start Claude Code session; /mcp command should show gateway-provided servers
```
**Source:** [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp) - Project scope configuration

### Pattern 2: Health Check Polling with Timeout
**What:** Poll gateway `/health` endpoint with retry logic and hard deadline
**When to use:** Before confirming .mcp.json generation; ensures gateway ready before Claude Code starts
**Example:**
```bash
# Source: Docker health check best practices + curl retry patterns
# Poll health endpoint with 30s timeout, 1s intervals

GATEWAY_URL="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
MAX_WAIT=30
INTERVAL=1

echo "Waiting for MCP gateway at $GATEWAY_URL..."
if timeout $MAX_WAIT bash -c "
  while ! curl -sf $GATEWAY_URL/health > /dev/null 2>&1; do
    sleep $INTERVAL
  done
"; then
  echo "✓ MCP gateway ready"
else
  echo "⚠ Warning: Gateway not ready after ${MAX_WAIT}s. Claude Code will start without MCP tools."
fi
```
**Source:**
- [Wait for an HTTP endpoint to return 200 OK with Bash and curl · GitHub](https://gist.github.com/rgl/f90ff293d56dbb0a1e0f7e7e89a81f42)
- [Docker Health Check: A Practical Guide - Lumigo](https://lumigo.io/container-monitoring/docker-health-check-a-practical-guide/)

### Pattern 3: Environment Variable Configuration
**What:** Source gateway URL from `MCP_GATEWAY_URL` environment variable set in devcontainer.json
**When to use:** ALWAYS; avoids hardcoding URLs; allows environment-specific overrides
**Example:**
```json
// .devcontainer/devcontainer.json
{
  "containerEnv": {
    "MCP_GATEWAY_URL": "http://host.docker.internal:8811"
  }
}
```
```bash
# .zshrc - Use env var with fallback
GATEWAY_URL="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
```
**Source:** [Complete Guide to macOS Shell Configuration: Environment Variables, Zsh, and PATH Management](https://osxhub.com/macos-shell-configuration-zsh-environment-variables/)

### Pattern 4: Inline Documentation via Commented Examples
**What:** Include commented-out MCP server examples in generated .mcp.json
**When to use:** Always; provides self-documenting configuration right where users edit
**Example:**
```json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "http://host.docker.internal:8811"
    }

    // COMMENTED EXAMPLES (uncomment + restart Claude Code to enable)
    //
    // "github": {
    //   "type": "http",
    //   "url": "https://api.githubcopilot.com/mcp/",
    //   "env": {
    //     "GITHUB_TOKEN": "${GITHUB_TOKEN}"
    //   }
    // },
    //
    // "postgres": {
    //   "type": "stdio",
    //   "command": "npx",
    //   "args": ["-y", "@modelcontextprotocol/server-postgres"]
    // }
  }
}
```
**Note:** JSON does not support comments; use block comment syntax that can be removed via preprocessing, OR use a separate `.mcp.json.template` file with instructions

### Pattern 5: Shell Function vs Alias for Parameter Handling
**What:** Use shell function instead of alias when logic requires conditionals, loops, or multi-line commands
**When to use:** ALWAYS for health check polling; aliases cannot handle while loops or if statements
**Example:**
```bash
# GOOD: Shell function (supports full scripting)
claude-mcp-init() {
  local gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
  local max_wait=30

  # Generate config
  cat > /workspace/.mcp.json <<EOF
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "$gateway_url"
    }
  }
}
EOF

  # Poll health with timeout
  if timeout $max_wait bash -c "
    while ! curl -sf $gateway_url/health > /dev/null 2>&1; do
      sleep 1
    done
  "; then
    echo "✓ MCP gateway ready. Start Claude Code to connect."
  else
    echo "⚠ Gateway not ready. Claude Code will start without MCP."
  fi
}

# BAD: Alias (no conditionals/loops)
alias claude-mcp-init='cat > /workspace/.mcp.json <<< "{...}" && curl http://host.docker.internal:8811/health'
```
**Source:**
- [When to Use an Alias vs Script vs a New Function in Bash | Baeldung](https://www.baeldung.com/linux/bash-alias-vs-script-vs-new-function)
- [Shell Style Guide - Google](https://google.github.io/styleguide/shellguide.html)

### Pattern 6: HTTP Health Check vs TCP Port Check
**What:** Use HTTP GET to /health endpoint instead of TCP port scan (nc -z)
**When to use:** ALWAYS for application health validation; TCP only checks port listening, not readiness
**Recommendation (Claude's discretion):** HTTP health check with curl
**Example:**
```bash
# PREFERRED: HTTP health check (validates application ready)
curl -sf http://host.docker.internal:8811/health > /dev/null

# FALLBACK: TCP port check (only validates port listening)
nc -z host.docker.internal 8811
```
**Why HTTP preferred:**
- Validates application-level readiness (gateway process serving requests)
- Returns specific HTTP status codes (200 OK vs 503 Service Unavailable)
- Gateway /health endpoint designed for this purpose (Phase 1/2 infrastructure)
- 2026 best practices: "HTTP checks are preferred over simple TCP port checks"
**Source:** [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view)

### Pattern 7: Recommended Example MCP Servers (Claude's discretion)
**What:** Pre-configure 2-3 commented-out MCP servers relevant to this devcontainer ecosystem
**Recommendation:**
1. **github** - Common in development workflows; Langfuse project uses GitHub
2. **postgres** - Langfuse stack includes PostgreSQL; MCP server enables DB queries
3. **docker** - Devcontainer environment; Docker MCP server useful for container management

**Rationale:**
- **github**: Official GitHub MCP server; manages PRs, code reviews, commits; high relevance for any development project
- **postgres**: Langfuse uses PostgreSQL; postgres MCP server allows natural language DB queries; eliminates manual psql sessions
- **docker**: Devcontainer runs in Docker; docker MCP server helps build/debug containers, inspect running services

**Example configuration:**
```json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "http://host.docker.internal:8811"
    }
  }

  // To add more MCP servers:
  // 1. Edit gateway's mcp.json (langfuse-local/mcp/mcp.json)
  // 2. Restart gateway: docker compose restart docker-mcp-gateway
  // 3. Re-run: claude-mcp-init
  // 4. Restart Claude Code session to pick up changes
  //
  // Example servers:
  //
  // GitHub (for PR management, code reviews):
  // "github": {
  //   "type": "http",
  //   "url": "https://api.githubcopilot.com/mcp/"
  // }
  //
  // PostgreSQL (for Langfuse database queries):
  // "postgres": {
  //   "type": "stdio",
  //   "command": "npx",
  //   "args": ["-y", "@modelcontextprotocol/server-postgres"],
  //   "env": {
  //     "POSTGRES_URL": "postgresql://user:pass@host:5433/langfuse"
  //   }
  // }
  //
  // Docker (for container management):
  // "docker": {
  //   "type": "stdio",
  //   "command": "docker-mcp",
  //   "args": []
  // }
}
```

**Source:**
- [The Best MCP Servers for Developers in 2026](https://www.builder.io/blog/best-mcp-servers-2026)
- [GitHub - modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)

### Anti-Patterns to Avoid

- **Using alias instead of function for health check logic:** Aliases cannot handle conditionals, loops, or multi-line commands; function required
- **Committing .mcp.json to version control:** File contains runtime URLs (host.docker.internal); should be generated, not committed; add to .gitignore
- **Hardcoding gateway URL in script:** Use `MCP_GATEWAY_URL` environment variable for flexibility and environment-specific overrides
- **Skipping health check before config generation:** Claude Code may start before gateway ready; MCP tools unavailable; always poll health first
- **Using only TCP port check:** TCP validates port listening but not application readiness; HTTP /health validates gateway serving requests
- **Setting timeout > 30s:** User waits too long during startup failures; 30s is sufficient for local Docker gateway; fail-fast UX better than long hang
- **Blocking forever without timeout:** If gateway never starts, shell hangs indefinitely; always wrap health check in `timeout` command
- **Using postStartCommand for alias invocation:** postStartCommand runs once; alias allows manual refresh; define in .zshrc for user-initiated runs

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON generation with escaping | Manual echo/heredoc with quotes | jq for env var substitution; cat with heredoc for static JSON | jq handles escaping automatically; heredoc cleaner than echo for multi-line; avoid string concatenation bugs |
| Retry logic with exponential backoff | Custom while loop with sleep arithmetic | curl --retry N --retry-delay N --max-time N | curl built-in retry is battle-tested; handles transient failures; simpler than custom implementation |
| Timeout wrapper | Custom background job with kill | timeout command from coreutils | timeout is POSIX-standard; handles edge cases (zombie processes, signal handling); reliable across platforms |
| Health check endpoint | Custom TCP socket test with netcat only | HTTP GET to /health endpoint with curl | HTTP validates application-level readiness; /health endpoint already implemented in gateway (Phase 1) |
| MCP server registry/discovery | Scraping GitHub/npm for MCP packages | Inline commented examples in .mcp.json | Examples right where users edit; no external lookups; self-documenting configuration |

**Key insight:** Shell scripting has mature tooling for HTTP polling, JSON generation, and timeout handling. Custom implementations miss edge cases (signal handling, DNS failures, JSON escaping) that standard tools handle correctly.

## Common Pitfalls

### Pitfall 1: Shell Alias Parameter Limitations
**What goes wrong:** Shell alias defined for config generation but cannot handle conditional logic or loops; health check fails to execute
**Why it happens:** Aliases are text replacements; parameters always appended at end; no support for conditionals, loops, or multi-line logic
**How to avoid:**
1. Use shell function instead of alias for ANY logic beyond single-command shortcuts
2. Google Shell Style Guide: "For almost every purpose, shell functions are preferred over aliases"
3. Functions allow full scripting: `if`, `while`, `local` variables, multi-line blocks
**Warning signs:**
- Syntax errors when alias includes `if` or `while`
- Parameters not in expected positions
- Multi-line alias definitions fail to parse
**Source:** [When to Use an Alias vs Script vs a New Function in Bash | Baeldung](https://www.baeldung.com/linux/bash-alias-vs-script-vs-new-function)

### Pitfall 2: JSON Comment Syntax Invalid
**What goes wrong:** Generated .mcp.json contains `//` comments; Claude Code fails to parse; MCP servers not discovered
**Why it happens:** JSON specification does not support comments; many tools (including Claude Code's config parser) reject non-standard JSON
**How to avoid:**
1. Use block comment style with preprocessing (remove before Claude Code reads)
2. OR use separate `.mcp.json.template` file with instructions in README
3. OR accept no comments in .mcp.json; document examples in separate EXAMPLES.md
**Warning signs:**
- Claude Code shows "Invalid MCP configuration" error
- `/mcp` command shows no servers despite .mcp.json existing
- JSON linters (jq, jsonlint) report parse errors
**Recommendation:** Use separate documentation block ABOVE the JSON in .mcp.json (like a header comment), or include examples in shell function output messages

### Pitfall 3: host.docker.internal DNS Resolution Failure
**What goes wrong:** Health check and .mcp.json reference `host.docker.internal` but DNS resolution fails; curl hangs or returns "Could not resolve host"
**Why it happens:** Linux Docker requires manual `--add-host=host.docker.internal:host-gateway` in devcontainer runArgs; not automatic like macOS/Windows Docker Desktop
**How to avoid:**
1. Verify devcontainer.json includes runArgs: `--add-host=host.docker.internal:host-gateway` (already present per prior phases)
2. Test resolution: `ping -c 1 host.docker.internal` from devcontainer
3. Fallback in shell function: Use gateway IP if DNS fails
**Warning signs:**
- Health check curl hangs indefinitely
- `ping host.docker.internal` returns "unknown host"
- Works on macOS/Windows but fails in Codespaces/Linux CI
**Source:** [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/)

### Pitfall 4: Claude Code Session Doesn't Pick Up Config Changes
**What goes wrong:** User re-runs shell function after adding MCP server; .mcp.json updated but `/mcp` command shows old server list
**Why it happens:** Claude Code reads .mcp.json on session start; dynamic updates require session restart
**How to avoid:**
1. Shell function output includes: "Restart Claude Code session to pick up changes"
2. Document workflow: edit gateway mcp.json → restart gateway → re-run claude-mcp-init → restart Claude Code
3. Consider adding `claude` command detection and automatic prompt in shell function
**Warning signs:**
- .mcp.json shows new server but `/mcp` command does not
- File timestamp is recent but changes not reflected
**Source:** [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp) - Dynamic tool updates section

### Pitfall 5: Gateway Not Started Before Config Generation
**What goes wrong:** Shell function generates .mcp.json immediately; health check skipped; Claude Code starts but MCP tools unavailable
**Why it happens:** Gateway container not running (docker compose down); health check logic bypassed; config generated with unreachable URL
**How to avoid:**
1. ALWAYS poll health endpoint BEFORE confirming success
2. Shell function returns non-zero exit code if health check fails
3. Clear user feedback: "Gateway not ready; Claude Code will start without MCP"
**Warning signs:**
- .mcp.json generated but gateway container not in `docker ps` output
- Health check never attempted
- `/mcp` command shows connection errors
**Source:** [Docker Health Check: A Practical Guide - Lumigo](https://lumigo.io/container-monitoring/docker-health-check-a-practical-guide/)

### Pitfall 6: Timeout Too Short for Cold Start
**What goes wrong:** First gateway start (npx downloads packages) takes 20s; health check times out at 10s; reports failure despite gateway eventually becoming healthy
**Why it happens:** 30s timeout chosen for warm start; cold start (no npm cache) requires longer; network latency adds delay
**How to avoid:**
1. Use 30s timeout (sufficient for npx download + startup per Phase 2 research)
2. Shell function could detect cold vs warm start (check if gateway container just created)
3. Logs visible during wait: `echo "Waiting for gateway (may take 30s on first start)..."`
**Warning signs:**
- First run after `docker compose up --force-recreate` times out
- Subsequent runs (warm start) succeed quickly
- Gateway logs show npx download AFTER health check timeout

## Code Examples

Verified patterns from official sources:

### Complete Shell Function (Production-Ready)
```bash
# Source: Composite of Claude Code MCP docs, Docker health check best practices, shell scripting patterns
# Location: Add to ~/.zshrc or ~/.bashrc
# Usage: claude-mcp-init

claude-mcp-init() {
  local gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
  local workspace_root="${WORKSPACE_ROOT:-/workspace}"
  local config_file="$workspace_root/.mcp.json"
  local max_wait=30
  local interval=1

  echo "=== Claude Code MCP Initialization ==="
  echo "Gateway URL: $gateway_url"
  echo "Config file: $config_file"
  echo ""

  # Step 1: Generate .mcp.json
  echo "[1/2] Generating MCP configuration..."
  cat > "$config_file" <<'EOF'
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "http://host.docker.internal:8811"
    }
  }
}
EOF

  if [ $? -eq 0 ]; then
    echo "✓ Configuration written to $config_file"
  else
    echo "✗ Failed to write configuration"
    return 1
  fi

  echo ""
  echo "[2/2] Waiting for MCP gateway (timeout: ${max_wait}s)..."

  # Step 2: Poll health endpoint with timeout
  if timeout $max_wait bash -c "
    while ! curl -sf $gateway_url/health > /dev/null 2>&1; do
      sleep $interval
    done
  "; then
    echo "✓ MCP gateway is ready"
    echo ""
    echo "=== Setup Complete ==="
    echo "Start Claude Code session to connect to MCP tools."
    echo ""
    echo "To add more MCP servers:"
    echo "  1. Edit: langfuse-local/mcp/mcp.json"
    echo "  2. Restart gateway: docker compose restart docker-mcp-gateway"
    echo "  3. Re-run: claude-mcp-init"
    echo "  4. Restart Claude Code session"
    return 0
  else
    echo "⚠ Warning: Gateway not ready after ${max_wait}s"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check gateway status: docker ps | grep docker-mcp-gateway"
    echo "  - View gateway logs: docker logs docker-mcp-gateway"
    echo "  - Start gateway: docker compose up -d docker-mcp-gateway"
    echo ""
    echo "Claude Code can still start, but MCP tools will be unavailable."
    return 1
  fi
}
```

### Alternative: Simplified Version (Minimal)
```bash
# Minimal version without extensive logging
# Use if console output verbosity is concern

claude-mcp-init() {
  local gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"

  # Generate config
  cat > /workspace/.mcp.json <<EOF
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "$gateway_url"
    }
  }
}
EOF

  # Poll health
  echo "Waiting for MCP gateway..."
  if timeout 30 bash -c "while ! curl -sf $gateway_url/health >/dev/null 2>&1; do sleep 1; done"; then
    echo "✓ MCP gateway ready. Start Claude Code to connect."
  else
    echo "⚠ Gateway not ready. Check: docker logs docker-mcp-gateway"
  fi
}
```

### .mcp.json Template with Documentation Block
```json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "http://host.docker.internal:8811"
    }
  }
}
```

**Separate documentation in function output:**
```bash
# In shell function after config generation:
cat <<'EXAMPLES'

Example MCP servers to add (edit gateway's mcp.json):

GitHub (PR management, code reviews):
  "github": {
    "type": "http",
    "url": "https://api.githubcopilot.com/mcp/"
  }

PostgreSQL (Langfuse database queries):
  "postgres": {
    "type": "stdio",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres"],
    "env": {
      "POSTGRES_URL": "postgresql://postgres:postgres@host.docker.internal:5433/langfuse"
    }
  }

Docker (container management):
  "docker": {
    "type": "stdio",
    "command": "docker-mcp",
    "args": []
  }

EXAMPLES
```

### devcontainer.json Environment Variable Configuration
```json
// .devcontainer/devcontainer.json
{
  "name": "Claude Code Sandbox",
  "containerEnv": {
    "MCP_GATEWAY_URL": "http://host.docker.internal:8811",
    "WORKSPACE_ROOT": "/workspace"
  },
  "runArgs": [
    "--add-host=host.docker.internal:host-gateway"
  ]
  // ... other config
}
```

### .zshrc Integration
```bash
# ~/.zshrc
# Add at end of file, after oh-my-zsh initialization

# MCP Gateway URL (sourced from devcontainer env)
export MCP_GATEWAY_URL="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"
export WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"

# Claude MCP initialization function
claude-mcp-init() {
  # [Full function code from above]
}

# Optional: Auto-run on shell start (commented out by default)
# Uncomment to automatically initialize MCP on every new shell session
# claude-mcp-init
```

### Health Check Testing Commands
```bash
# Test gateway health manually
curl -v http://host.docker.internal:8811/health

# Test with retry logic (like shell function uses)
curl -sf --retry 5 --retry-delay 1 --max-time 30 http://host.docker.internal:8811/health

# Fallback: TCP port check
nc -zv host.docker.internal 8811

# Test DNS resolution
ping -c 1 host.docker.internal

# Verify .mcp.json generated correctly
cat /workspace/.mcp.json | jq .
# Expected: Valid JSON with mcpServers.mcp-gateway object
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SSE transport for remote MCP | HTTP transport (type: "http") | Q1 2026 | SSE deprecated but still supported; HTTP is preferred; gateway still uses SSE internally for client connections |
| Manual .mcp.json editing | Shell alias/function generation | 2025+ | Automation eliminates manual config; reduces errors; enables health check integration |
| Shell aliases for complex logic | Shell functions | Long-standing best practice | Functions support conditionals, loops, local variables; aliases only for simple shortcuts |
| TCP port checks (nc -z) | HTTP health endpoint checks | 2026 best practices | HTTP validates application readiness; TCP only confirms port listening; HTTP preferred |
| Hardcoded URLs in config | Environment variable configuration | DevContainer best practices | Flexibility for different environments; easier testing; no code changes for URL updates |
| Global MCP config only | Project-scoped .mcp.json | Claude Code v2.x+ | Team sharing via VCS; consistent tooling across developers; user approval for security |

**Deprecated/outdated:**
- **settings.local.json for MCP servers:** Still works but .mcp.json is preferred for project scope; settings.local.json is local-only
- **SSE transport as default:** HTTP transport now preferred for remote servers; SSE still supported for backward compatibility
- **Manual postStartCommand invocation:** Shell alias/function provides manual refresh capability; postStartCommand runs once only

**Note on SSE vs HTTP:**
- Gateway currently uses SSE transport for client connections (per CONTEXT.md locked decision)
- This is VALID and SUPPORTED as of 2026-02-13
- HTTP transport preferred for NEW remote MCP server integrations
- For this phase: SSE is correct choice for gateway connection

## Open Questions

1. **Claude Code .mcp.json file watching for hot reload**
   - What we know: Config read on session start; manual restart required for changes
   - What's unclear: Does Claude Code support file watching for dynamic .mcp.json reload?
   - Recommendation: Assume no hot reload; document session restart requirement; test during verification

2. **Gateway SSE endpoint backwards compatibility timeline**
   - What we know: SSE deprecated in favor of HTTP; still supported as of Q1 2026
   - What's unclear: When will SSE be removed? Should we plan migration to HTTP transport?
   - Recommendation: Use SSE per locked decision; monitor Claude Code docs for deprecation timeline

3. **Project-scoped MCP approval persistence**
   - What we know: Claude Code prompts for approval on first use of project-scoped servers
   - What's unclear: Is approval per-session, per-workspace, or persistent across devcontainer rebuilds?
   - Recommendation: Test during verification; document approval UX in verification guide

4. **Workspace root auto-detection reliability**
   - What we know: Shell function uses `${WORKSPACE_ROOT:-/workspace}` default
   - What's unclear: Does devcontainer always set WORKSPACE_ROOT, or should function auto-detect?
   - Recommendation: Use /workspace hardcoded (per devcontainer.json workspaceFolder); env var for override only

5. **Gateway health endpoint response format**
   - What we know: /health endpoint returns 200 OK when ready; curl -sf succeeds
   - What's unclear: What is response body format? JSON with status field, or plain text?
   - Recommendation: Treat as opaque; only check HTTP status code; body format may change

## Sources

### Primary (HIGH confidence)
- [Connect Claude Code to tools via MCP - Claude Code Docs](https://code.claude.com/docs/en/mcp) - Official MCP configuration documentation
- [Shell Style Guide - Google](https://google.github.io/styleguide/shellguide.html) - Shell function best practices
- [When to Use an Alias vs Script vs a New Function in Bash | Baeldung](https://www.baeldung.com/linux/bash-alias-vs-script-vs-new-function) - Function vs alias guidance
- [Complete Guide to macOS Shell Configuration: Environment Variables, Zsh, and PATH Management](https://osxhub.com/macos-shell-configuration-zsh-environment-variables/) - Environment variable patterns
- [How to Implement Docker Health Check Best Practices](https://oneuptime.com/blog/post/2026-01-30-docker-health-check-best-practices/view) - 2026 health check guidance (HTTP vs TCP)
- [Connect to localhost from inside a dev container | JimBobBennett](https://jimbobbennett.dev/blogs/access-localhost-from-dev-container/) - host.docker.internal configuration

### Secondary (MEDIUM confidence)
- [Wait for an HTTP endpoint to return 200 OK with Bash and curl · GitHub](https://gist.github.com/rgl/f90ff293d56dbb0a1e0f7e7e89a81f42) - Health check polling patterns
- [Docker Health Check: A Practical Guide - Lumigo](https://lumigo.io/container-monitoring/docker-health-check-a-practical-guide/) - Health check implementation
- [The Best MCP Servers for Developers in 2026](https://www.builder.io/blog/best-mcp-servers-2026) - Popular MCP servers
- [GitHub - modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) - Official MCP server registry
- [An Introduction to Useful Bash Aliases and Functions | DigitalOcean](https://www.digitalocean.com/community/tutorials/an-introduction-to-useful-bash-aliases-and-functions) - Shell scripting patterns

### Tertiary (LOW confidence - needs validation)
- Claude Code .mcp.json hot reload capability (not documented; requires testing)
- SSE deprecation timeline (general guidance; no specific date published)
- Project-scoped approval persistence across sessions (UX behavior not fully documented)

### Project-Specific Sources
- `.planning/phases/01-gateway-infrastructure/01-RESEARCH.md` - Gateway health endpoint details
- `.planning/phases/02-connectivity-health-validation/02-RESEARCH.md` - host.docker.internal patterns, health check timing
- `.planning/phases/03-claude-code-integration/03-CONTEXT.md` - User decisions and constraints
- `.devcontainer/devcontainer.json` - Current runArgs and containerEnv configuration

## Metadata

**Confidence breakdown:**
- **Claude Code .mcp.json format:** HIGH - Official documentation, verified format
- **Shell function vs alias:** HIGH - Google Style Guide, multiple authoritative sources
- **Health check polling patterns:** HIGH - Official Docker docs, established best practices
- **Environment variable configuration:** HIGH - DevContainer and shell configuration standards
- **HTTP vs TCP health checks:** HIGH - 2026 Docker best practices, multiple sources
- **MCP server examples:** MEDIUM - Community-driven registry, popular choices documented
- **SSE vs HTTP transport:** MEDIUM - SSE deprecated but timeline unclear; both currently supported
- **.mcp.json comment syntax:** MEDIUM - JSON spec clear (no comments); workarounds documented but not standardized

**Research date:** 2026-02-13
**Valid until:** 2026-03-13 (30 days; Claude Code MCP features evolving, but shell patterns stable)

**Critical gaps requiring validation during implementation:**
1. Claude Code .mcp.json hot reload support (assume no; test during verification)
2. Project-scoped MCP server approval UX and persistence
3. Actual gateway /health endpoint response body format
4. Optimal health check timeout for local network conditions (30s baseline, tune if needed)

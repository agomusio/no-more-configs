# Devcontainer Follow-up Validation Notes

Date: 2026-02-14

This follow-up addresses review feedback from Claude on the prior changeset.

## Decisions and updates

1. **Claude Code version policy**
   - Updated `.devcontainer/Dockerfile` and `.devcontainer/devcontainer.json` to keep `CLAUDE_CODE_VERSION=latest` intentionally.
   - Rationale: maintainer preference is always-current Claude CLI over strict image reproducibility.

2. **Lifecycle ordering sanity check**
   - Verified `postStartCommand` order remains:
     1. `init-firewall.sh`
     2. git trust/line-ending config
     3. `setup-network-checks.sh`
     4. `init-gsd.sh`
     5. `mcp-setup`
   - This keeps all network checks after firewall initialization.

3. **Git identity behavior when host env vars are missing**
   - Verified `setup-container.sh` warns when `GIT_AUTHOR_EMAIL` is unset and does not hard-fail.

4. **DNS refresh idempotency**
   - Verified `.devcontainer/refresh-firewall-dns.sh` uses `ipset add ... -exist` (no flush/rebuild), avoiding transient allowlist drops.

## Host-side validation still required

Because this environment is not the target WSL2 Docker Desktop runtime, final behavioral verification should still be done on host by rebuilding the devcontainer and checking:

```bash
# In VS Code: Rebuild Container
# Then in container shell:
cat /workspace/.mcp.json
mcp-setup
bash .devcontainer/setup-container.sh
```

Expected:
- `mcp-setup` succeeds after firewall init.
- missing git identity env vars produce warning only.
- Langfuse/MCP checks behave based on sidecar availability.

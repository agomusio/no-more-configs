# docs/

Outputs from ChatGPT Codex reviews, suggestions, and plans for this repository. Files here are Codex-generated artifacts — specs, RFCs, audits, and recommendations — preserved for reference.

## Contents

| File                            | Codex Version | Date       | Description                                               |
| ------------------------------- | ------------- | ---------- | --------------------------------------------------------- |
| `codex-mcp-integration-spec.md` | 5.3           | 2026-02-10 | MCP gateway integration RFC (implemented in phases 01-02) |
| `codex-setup.sh`                | —             | 2026-02-11 | Codex sandbox setup script (linters, analysis tools)      |
| `codex-maintenance.sh`          | —             | 2026-02-11 | Codex cached container maintenance (verify tools, re-run setup if needed) |
| `codex-dockerfile-audit.md`     | 5.2           | 2026-02-11 | Audit of `.devcontainer/Dockerfile` with image-size and caching recommendations |
| `codex-startup-latency-audit.md`| 5.2           | 2026-02-11 | Startup firewall latency analysis with API caching/fallback design |
| `codex-compose-hardening-audit.md` | 5.2        | 2026-02-11 | Security/reliability hardening plan for Langfuse sidecar compose stack |
| `codex-langfuse-hook-robustness.md` | 5.2      | 2026-02-11 | Concurrency, crash-safety, and observability review of Langfuse Stop hook |
| `codex-firewall-whitelist-audit.md` | 5.2      | 2026-02-11 | Domain allowlist gap analysis for npm/pip/gh/wrangler/Claude workflows |

# Firewall Whitelist Completeness Audit

Date: 2026-02-11  
Scope: `.devcontainer/init-firewall.sh` domain whitelist vs expected tool traffic

## Current whitelist snapshot

Currently included domains are listed in the script loop (`registry.npmjs.org`, `api.anthropic.com`, `api.cloudflare.com`, `pypi.python.org`, GitHub domains, etc.).

## Gap analysis by tool

| Tool / workflow | Expected domains in normal operation | Present now? | Recommendation |
|---|---|---:|---|
| `npm install` | `registry.npmjs.org` + occasional package assets on additional npm/CDN endpoints | Partial | Keep `registry.npmjs.org`; add `registry.npmjs.com` as fallback and monitor blocked requests logs. |
| `pip install` | `pypi.org`, `files.pythonhosted.org` | **No** (only `pypi.python.org`) | Add `pypi.org` and `files.pythonhosted.org`; keep `pypi.python.org` for legacy redirect safety. |
| `gh` CLI | `api.github.com`, `github.com`, `uploads.github.com`, `objects.githubusercontent.com`, `codeload.github.com` | Partial | Add `uploads.github.com` and `codeload.github.com`. |
| `wrangler` | `api.cloudflare.com`; login/deploy can involve `dash.cloudflare.com`, `*.workers.dev` APIs | Partial | Add `dash.cloudflare.com` and `workers.dev` (or concrete API endpoints used in your workflow). |
| Claude Code CLI | `api.anthropic.com`, telemetry endpoints (`statsig.anthropic.com`, `statsig.com`, `sentry.io`) | Mostly yes | Keep current set; optionally add `claude.ai` if installer/login workflows run post-start under firewall. |

## High-impact missing domains (prioritized)

1. `pypi.org`
2. `files.pythonhosted.org`
3. `uploads.github.com`
4. `codeload.github.com`
5. `dash.cloudflare.com`
6. `workers.dev` (or specific workers API domains used by Wrangler deploy flow)
7. `registry.npmjs.com` (defensive fallback)

## Recommended patch snippet

Add these to the domain loop in `.devcontainer/init-firewall.sh`:

```bash
"pypi.org" \
"files.pythonhosted.org" \
"uploads.github.com" \
"codeload.github.com" \
"dash.cloudflare.com" \
"workers.dev" \
"registry.npmjs.com" \
```

## Additional robustness recommendations

- Resolve both **A and AAAA** records, then decide explicitly whether IPv6 should be denied or supported; current script only whitelists IPv4 A records.
- Emit a blocked-domain diagnostics log (e.g., from iptables reject counters) to quickly identify new required endpoints.
- Keep an allowlist source-of-truth in `docs/` and generate script domains from it to avoid drift.

## Validation commands run

- `dig +short` checks for candidate domains to verify they resolve and are reachable targets for these tools.

## Source references

- `.devcontainer/init-firewall.sh:116-141` (static domain resolution whitelist)
- `.devcontainer/init-firewall.sh:103-113` (GitHub range fetch and ipset population)
- `README.md:341-348` (documented firewall categories)

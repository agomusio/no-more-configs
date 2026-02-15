# Devcontainer Review & Fixes

Date: 2026-02-14  
Scope: `.devcontainer/*` and root `README.md`

## 1) Lifecycle Hook Race Condition
- **Problem/impact:** Network-dependent setup ran in `postCreateCommand` before firewall setup in `postStartCommand`.
- **Affected:** `.devcontainer/devcontainer.json` (`postCreateCommand`, `postStartCommand`), `.devcontainer/setup-container.sh`
- **Fix:** Moved network steps to new `.devcontainer/setup-network-checks.sh` and invoke it from `postStartCommand` after `init-firewall.sh`. `postCreateCommand` now only runs identity/socket setup.
- **Trade-off:** First start is a little slower; startup behavior is now deterministic and firewall-first (recommended).

## 2) Hardcoded Git Identity
- **Problem/impact:** Commits were authored as a single hardcoded user.
- **Affected:** `.devcontainer/setup-container.sh`, `.devcontainer/devcontainer.json`
- **Fix:** Added `GIT_AUTHOR_*`/`GIT_COMMITTER_*` passthrough env vars in `containerEnv`; `setup-container.sh` now configures git identity only if env vars are present.
- **Trade-off:** Requires users to export vars on host; prevents incorrect authorship (recommended).

## 3) Duplicated Git Configuration
- **Problem/impact:** `safe.directory` and `core.autocrlf` were configured in two places.
- **Affected:** `.devcontainer/devcontainer.json`, `.devcontainer/setup-container.sh`
- **Fix:** Kept git trust/line-ending config only in `postStartCommand`, removed duplicates from `setup-container.sh`.

## 4) Dual mcp-setup Scripts with Drift Risk
- **Problem/impact:** Same MCP logic existed in binary + shell function, increasing drift risk.
- **Affected:** `.devcontainer/mcp-setup.sh`, `.devcontainer/mcp-setup-bin.sh`, `.devcontainer/Dockerfile`
- **Fix:** Removed `.devcontainer/mcp-setup.sh`; Dockerfile now installs only `/usr/local/bin/mcp-setup`.

## 5) No IPv6 Firewall Rules
- **Problem/impact:** IPv6 traffic could bypass IPv4-only firewall.
- **Affected:** `.devcontainer/init-firewall.sh`
- **Fix:** Added `ip6tables` reset + default DROP + loopback/stateful allow rules.

## 6) DNS-Based Firewall Fragility
- **Problem/impact:** CDN IP drift could break allowed domains after startup.
- **Affected:** `.devcontainer/init-firewall.sh`
- **Fix:** Added explicit limitation comments and implemented Option A via `.devcontainer/refresh-firewall-dns.sh`; `init-firewall.sh` now invokes it.
- **Trade-off:** Still best-effort DNS/IP mapping; periodic execution can be added later (cron/systemd) if desired.

## 7) Project-Specific Domain in Shared Infra
- **Problem/impact:** Shared firewall script had project-specific domain hardcoded.
- **Affected:** `.devcontainer/init-firewall.sh`, new `.devcontainer/firewall-domains.conf`
- **Fix:** Moved project domain into `firewall-domains.conf`, loaded by `refresh-firewall-dns.sh`.

## 8) Docker Socket Permissions (`chmod 666`)
- **Problem/impact:** All container processes can control host Docker daemon.
- **Affected:** `.devcontainer/setup-container.sh`, `README.md`
- **Fix:** Kept behavior (intentional for DooD) but added explicit security warning comments and README security section.
- **Trade-off:** Convenience vs host-level privilege exposure; group-based access is stricter but more setup.

## 9) Implicit `wget` Dependency in Dockerfile
- **Problem/impact:** Build depended on base image including `wget`.
- **Affected:** `.devcontainer/Dockerfile`
- **Fix:** Replaced `wget` usage with explicit `curl` equivalents.

## 10) Dockerfile Layer Cache Inefficiency
- **Problem/impact:** Early `COPY init-firewall.sh` invalidated many heavy layers.
- **Affected:** `.devcontainer/Dockerfile`
- **Fix:** Moved firewall-related `COPY` steps to the end of Dockerfile.

## 11) Unpinned Claude Code Version Default
- **Problem/impact:** `latest` is non-reproducible across time.
- **Affected:** `.devcontainer/Dockerfile`, `.devcontainer/devcontainer.json`
- **Fix decision:** Kept `latest` intentionally per maintainer preference (always get newest CLI). Added explicit Dockerfile comment documenting this trade-off.

## 12) `mcp-setup-bin.sh` shebang inconsistency
- **Problem/impact:** Potential future shell drift between duplicated scripts.
- **Affected:** `.devcontainer/mcp-setup.sh`, `.devcontainer/mcp-setup-bin.sh`
- **Fix:** Resolved by consolidation in issue #4; only bin script remains.

## Recommended Follow-up
- Add a scheduled task (cron/systemd timer) to run `/usr/local/bin/refresh-firewall-dns.sh` every 15 minutes for long-lived sessions.

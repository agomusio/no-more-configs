# Container Startup Latency Audit

Date: 2026-02-11  
Scope: `.devcontainer/init-firewall.sh`

## Key findings

1. **Startup is hard-blocked on live GitHub API**
   - Script always fetches `https://api.github.com/meta` and exits non-zero if response validation fails.
   - This makes every container start dependent on network/API availability.

2. **No cache or staleness policy**
   - GitHub ranges are rebuilt from scratch every run even though they change infrequently.

3. **DNS resolution loop is serial and chatty**
   - Each domain is resolved one-by-one with `dig`, increasing latency.

4. **Failure mode is fail-closed even for transient startup networking issues**
   - If GitHub meta call fails once, firewall setup exits and can break expected developer startup behavior.

## Actionable recommendations

### 1) Add on-disk cache with TTL for GitHub meta

Store raw API response and timestamp in `~/.cache/firewall/github-meta.json` (or `/var/cache/devcontainer-firewall/github-meta.json`).

Recommended policy:
- Use cache if age < 24h.
- If stale, refresh in background or refresh once with timeout.
- If refresh fails but cache exists (even stale), continue with cached ranges and log warning.

Suggested implementation sketch:

```bash
CACHE_FILE="/var/cache/devcontainer-firewall/github-meta.json"
CACHE_MAX_AGE=86400
mkdir -p "$(dirname "$CACHE_FILE")"

fetch_github_meta() {
  curl --silent --show-error --fail --max-time 5 https://api.github.com/meta
}

if cache_is_fresh; then
  gh_ranges="$(cat "$CACHE_FILE")"
else
  if gh_new="$(fetch_github_meta 2>/dev/null)"; then
    printf '%s' "$gh_new" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    gh_ranges="$gh_new"
  elif [ -s "$CACHE_FILE" ]; then
    echo "WARN: GitHub API unreachable; using cached ranges"
    gh_ranges="$(cat "$CACHE_FILE")"
  else
    echo "ERROR: No GitHub ranges available (API failed + no cache)"
    exit 1
  fi
fi
```

### 2) Add explicit fallback allowlist for GitHub critical CIDRs

Maintain a static emergency list file in repo:
- `.devcontainer/firewall-fallback/github-meta-fallback.txt`

Use it only when both API and cache fail.

### 3) Reduce per-start DNS work

- Resolve all configured domains once and cache resolved A-record set with short TTL (e.g., 1h).
- Use `xargs -P` for parallel `dig` operations.
- Deduplicate early (`sort -u`) before `ipset add`.

### 4) Add strict network timeouts and retries

For all outbound fetches:
- `curl --connect-timeout 2 --max-time 5 --retry 2 --retry-delay 1`

This avoids multi-minute stalls from packet loss/DNS drift.

### 5) Avoid full firewall teardown when unchanged

Optional optimization:
- Compute hash of generated rule inputs (GitHub ranges + domain A records).
- If unchanged from previous run, skip iptables/ipset rebuild and only verify expected rules.

## Suggested success criteria

- postStart firewall phase median < 2s on warm cache.
- startup still succeeds offline if cached ranges exist.
- clear log line when cache is used vs. API fresh fetch.

## Source references

- `.devcontainer/init-firewall.sh:101-107` (mandatory GitHub API fetch + hard fail)
- `.devcontainer/init-firewall.sh:111-113` (GitHub CIDR insertion)
- `.devcontainer/init-firewall.sh:116-141` (serial domain DNS resolution loop)
- `.devcontainer/init-firewall.sh:159-172` (verification requests affecting startup wall time)

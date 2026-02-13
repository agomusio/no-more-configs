# Dockerfile Optimization Audit

Date: 2026-02-11  
Scope: `.devcontainer/Dockerfile`

## Key findings

1. **Redundant package install layer exists**
   - `curl` and `ca-certificates` are installed in the base apt layer and then installed again later, with an extra `apt-get update` invocation. This adds rebuild time and layer churn with no functional gain.
   - Evidence: first install layer (`curl`, `ca-certificates`) and second install layer (`curl`, `bash`, `ca-certificates`).

2. **User switching and setup are fragmented across many layers**
   - `USER node` → `USER root` → `USER node` toggles happen multiple times. This hurts readability and cache predictability.

3. **Remote installer scripts are uncached and unpinned**
   - `curl https://claude.ai/install.sh | bash -s latest` and `wget zsh-in-docker.sh` both depend on moving targets (`latest`), making deterministic builds and layer caching harder.

4. **Potentially unnecessary packages likely inflating image**
   - `dnsutils`, `aggregate`, `man-db`, `vim`, `nano`, `iputils-ping`, and full Python tooling may not all be needed for day-to-day Claude workflows.
   - Keep only proven runtime dependencies for: firewall script, Docker CLI, Claude CLI, and Langfuse hook.

5. **Current Dockerfile is single-stage with build-only artifacts mixed into runtime**
   - Multi-stage can reduce final image size by extracting only required binaries/artifacts from transient stages.

## Actionable recommendations

### 1) Consolidate apt work into one deterministic layer

**Current pattern (fragmented):**

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ... curl ca-certificates ...
...
RUN apt-get update && apt-get install -y curl bash ca-certificates ...
```

**Recommended pattern:**

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash ca-certificates curl ... && \
    rm -rf /var/lib/apt/lists/*
```

- Remove the later apt layer entirely.
- Keep `--no-install-recommends` consistently.

### 2) Pin external installers to versions

- Use `ARG CLAUDE_CODE_VERSION=<fixed-version>` and pass that value to installer.
- Pin `zsh-in-docker` URL to fixed version (already partly done via `ARG`, keep it immutable in CI).
- Prefer checksum verification for downloaded `.deb` (`git-delta`) and shell scripts.

### 3) Reorder layers for cache efficiency

- Place **most stable** steps first:
  1. OS package installation
  2. Docker CLI repo/key setup
  3. Common filesystem/permissions setup
  4. Rarely changed tooling installs (`git-delta`, zsh config)
  5. Frequently changing app/tooling (`claude`, `get-shit-done-cc`)
- This keeps expensive OS layers reusable when app version changes.

### 4) Evaluate package removals with a strict allowlist

Candidate removals to test behind feature flags:
- `man-db`
- one of `vim` or `nano` (keep one)
- `iputils-ping` (if not used in scripts)
- `dnsutils` and `aggregate` (if moved to Python/JQ based processing or precomputed CIDRs)

Suggested process:
1. Build a “minimal” variant branch.
2. Run `.devcontainer/setup-container.sh`, firewall init, Claude launch, Langfuse hook smoke test.
3. Re-add only what fails.

### 5) Use a multi-stage build where practical

Use a throwaway builder stage for downloaded artifacts and script-based installers, then copy only final binaries/config into runtime.

Example sketch:

```dockerfile
FROM node:20 AS builder
# install curl/wget, download delta .deb, claude artifacts, etc.

FROM node:20
# install minimal runtime packages
COPY --from=builder /usr/bin/delta /usr/bin/delta
COPY --from=builder /home/node/.local/bin/claude /home/node/.local/bin/claude
```

This is most useful if Claude installer and other tooling leave behind caches/build deps in builder.

## Priority plan

- **P0:** remove duplicate apt layer and pin install versions.
- **P1:** reduce packages with compatibility smoke tests.
- **P2:** prototype multi-stage and compare size (`docker image inspect` + cold build timing).

## Source references

- `.devcontainer/Dockerfile:10-37` (main apt install)
- `.devcontainer/Dockerfile:43-52` (Docker CLI apt repo + install)
- `.devcontainer/Dockerfile:96-103` (zsh installer download)
- `.devcontainer/Dockerfile:110-114` (redundant apt install)
- `.devcontainer/Dockerfile:120` (Claude installer with `latest`)

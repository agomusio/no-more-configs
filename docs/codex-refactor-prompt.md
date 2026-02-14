# Refactor: Container-Local Claude Configuration

> **Context:** This is a major refactor of how the Claude Code Sandbox manages Claude Code instances. The current design bind-mounts `~/.claude` from the Windows host and forces all sessions to launch from `/workspace/claudehome`. This conflicts with GSD's per-project workflow and makes the devcontainer non-portable. The new design generates all Claude configuration inside the container at build/create time from source files checked into the repo.

---

## Design Decisions (confirmed by maintainer)

1. **Fully container-local config.** Remove the `~/.claude` bind mount from the Windows host entirely. All Claude Code configuration lives inside the container.
2. **Launch from anywhere.** Claude Code sessions can be started from any directory in the container — not just `/workspace/claudehome`.
3. **Global config with per-project overrides.** One global `~/.claude/settings.json` with skills, hooks, and slash commands. Individual projects can override via their own `.claude/settings.local.json`.
4. **Regenerated fresh on build.** Skills, slash commands, and settings are sourced from a canonical directory in the repo root and installed into the container's `~/.claude/` during `postCreateCommand`. Container rebuilds always produce a clean, current config.
5. **Modular for users.** The repo-root source directory should be easy for users to add/remove skills, commands, and hooks without touching Dockerfile or devcontainer.json.
6. **Claude Code version stays `latest`.** Do not pin.
7. **Centralized secrets via `secrets.json`.** A single gitignored `secrets.json` at the repo root is the master source for all credentials. Every component that needs secrets (Claude settings, Langfuse `.env`, future services) reads from this one file. No secrets are duplicated across files or injected ad-hoc.

---

## Current State (what exists today)

### Bind mount (to be removed)
```jsonc
// devcontainer.json → mounts
"source=${localEnv:USERPROFILE}/.claude,target=/home/node/.claude,type=bind"
```

### Fixed launch directory
```bash
# Dockerfile — aliases force cd to /workspace/claudehome
alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'
alias claudeyr='cd /workspace/claudehome && claude --dangerously-skip-permissions --resume'
```

### Skills location
```
/workspace/claudehome/.claude/skills/
├── aa-fullstack/
└── aa-cloudflare/
```

### GSD commands
Installed by `init-gsd.sh` into `~/.claude/commands/gsd/` via `npx get-shit-done-cc --claude --global`.

### Hooks
Registered in `~/.claude/settings.json` (on the host bind mount):
- `langfuse_hook.py` (Stop hook)
- `gsd-check-update.js` (SessionStart hook)
- `gsd-statusline.js` (StatusLine hook)

### Settings
- Global: `~/.claude/settings.json` (host-mounted, contains env vars, hooks, permissions)
- Project: `/workspace/claudehome/.claude/settings.local.json`

---

## Target State (what to build)

### New repo-root directory: `claude-config/`

Create a canonical source directory at the repo root that contains everything needed to configure Claude Code. This is the single source of truth — the container setup script reads from here and installs into `~/.claude/`.

```
/workspace/claude-config/
├── settings.json              # Global settings template (hooks, env, permissions)
├── skills/                    # All skills (copied to ~/.claude/skills/)
│   ├── aa-fullstack/
│   │   └── ... (skill files)
│   └── aa-cloudflare/
│       └── ... (skill files)
├── hooks/                     # Hook scripts (copied to ~/.claude/hooks/)
│   ├── langfuse_hook.py
│   ├── gsd-check-update.js
│   └── gsd-statusline.js
└── commands/                  # Custom slash commands (copied to ~/.claude/commands/)
    └── (user-defined commands, if any — GSD commands are installed separately via npx)
```

### Master secrets file: `secrets.json`

A single gitignored file at the repo root that holds every credential the sandbox needs. This is the **only place secrets are stored** — all other files reference it or are hydrated from it at setup time.

```
/workspace/secrets.json        # Gitignored — single source of truth for all credentials
```

**Schema:**

```jsonc
{
  "langfuse": {
    "secret_key": "sk-lf-...",
    "public_key": "pk-lf-local-claude-code"
  },
  "claude": {
    // Claude Code auth tokens — preserved across rebuilds
    // install-claude-config.sh restores these into ~/.claude/
    "credentials": { /* opaque blob, structure owned by Claude Code */ }
  }
  // Future services add keys here (e.g., "github", "cloudflare", "openai")
}
```

**Rules:**

1. `secrets.json` is listed in `.gitignore` — never committed.
2. A `secrets.example.json` with placeholder values is committed, showing the required structure.
3. `install-claude-config.sh` reads `secrets.json` at install time and:
   - Injects `langfuse.secret_key` and `langfuse.public_key` into the generated `~/.claude/settings.json` (replacing template placeholders).
   - Restores `claude.credentials` into `~/.claude/` so Claude Code auth survives rebuilds.
   - If `secrets.json` doesn't exist, prints a clear warning with setup instructions and continues with placeholders (tracing won't work, but the container is usable).
4. A helper script (`save-secrets`) is provided that **exports** current live credentials back into `secrets.json` — so after authenticating Claude Code or rotating Langfuse keys, the user runs one command to persist them.
5. Langfuse's `generate-env.sh` should also read from / write to `secrets.json` instead of managing its own `.env` secrets independently. If full integration is too complex, at minimum `install-claude-config.sh` should sync the Langfuse secret key from `secrets.json` into the Langfuse `.env`.

**Auth persistence flow:**

```
First setup:
  1. User runs generate-env.sh → creates Langfuse keys
  2. User authenticates Claude Code → creates auth tokens
  3. User runs `save-secrets` → both are captured in secrets.json

Subsequent rebuilds:
  1. postCreateCommand runs install-claude-config.sh
  2. Script reads secrets.json
  3. Injects Langfuse keys into settings.json
  4. Restores Claude auth tokens into ~/.claude/
  5. No re-auth needed
```

**Modularity principle:** Users add a skill by dropping a folder into `claude-config/skills/`. They add a hook by dropping a script into `claude-config/hooks/` and registering it in `claude-config/settings.json`. They add slash commands by dropping `.md` files into `claude-config/commands/`. No Dockerfile or devcontainer.json changes required.

### Installation flow

During `postCreateCommand`, a new script (`.devcontainer/install-claude-config.sh`) should:

1. Create `~/.claude/` directory structure (`settings.json`, `skills/`, `hooks/`, `commands/`, `state/`).
2. Copy `claude-config/settings.json` → `~/.claude/settings.json`, replacing `{{...}}` placeholder tokens with values from `/workspace/secrets.json` (via `jq` read + `sed` substitution or `jq` merge).
3. If `secrets.json` exists and contains `claude.credentials`, restore Claude Code auth tokens into `~/.claude/`.
4. Copy `claude-config/skills/*` → `~/.claude/skills/` (preserving directory structure).
5. Copy `claude-config/hooks/*` → `~/.claude/hooks/`.
6. Copy `claude-config/commands/*` → `~/.claude/commands/` (non-destructively — GSD installs its own commands separately and must not be overwritten).
7. Run `npx get-shit-done-cc --claude --global` to install GSD commands (this goes into `~/.claude/commands/gsd/`).
8. Print a summary: what was installed, whether secrets were loaded or skipped, whether Claude auth was restored.

If `secrets.json` is missing, the script warns but does **not** fail — the container is usable, just without tracing or pre-authenticated Claude.

The script should be idempotent — safe to run multiple times.

### Settings template

`claude-config/settings.json` is a template with placeholder tokens for secrets. It needs to contain:

- **Environment variables:** `TRACE_TO_LANGFUSE`, `LANGFUSE_PUBLIC_KEY` (placeholder: `{{LANGFUSE_PUBLIC_KEY}}`), `LANGFUSE_SECRET_KEY` (placeholder: `{{LANGFUSE_SECRET_KEY}}`), `LANGFUSE_HOST`
- **Hook registrations:** Stop → `langfuse_hook.py`, SessionStart → `gsd-check-update.js`, StatusLine → `gsd-statusline.js` (paths should reference `~/.claude/hooks/` since that's where they'll be installed)
- **Permissions:** whatever the current settings.json grants

`install-claude-config.sh` replaces `{{...}}` placeholders with values from `secrets.json` using `jq` + `sed` (or pure `jq` merge). If `secrets.json` is missing, placeholders are replaced with empty strings and a warning is printed.

Use `$HOME` or `/home/node` for paths — they must work inside the container regardless of cwd.

### Alias changes

The `claudey` / `claudeyr` aliases should no longer `cd` to a fixed directory. Update them to launch Claude Code from the current working directory:

```bash
alias claudey='claude --dangerously-skip-permissions'
alias claudeyr='claude --dangerously-skip-permissions --resume'
```

### Environment variable changes

- `CLAUDE_CONFIG_DIR` stays as `/home/node/.claude` (this tells Claude Code where to find its global config).
- Remove the `~/.claude` bind mount from `devcontainer.json` → `mounts`.
- Remove the `workspaceMount` override that forces `/workspace` as workspace folder, OR keep it but don't couple Claude sessions to it.

### What happens to `/workspace/claudehome/`

This directory currently serves as the forced launch point and holds project-level Claude config. After the refactor:

- It can remain as a project directory if desired, but it is no longer special.
- Its `.claude/settings.local.json` stays as an example of per-project overrides.
- Its `CLAUDE.md` stays as a project-level instruction file (Claude Code reads these from cwd automatically).
- Skills move from `/workspace/claudehome/.claude/skills/` to `claude-config/skills/` (the source) and `~/.claude/skills/` (the installed location).
- Hooks move from `/home/node/.claude/hooks/` (host-mounted) to `claude-config/hooks/` (source) and `~/.claude/hooks/` (installed).

### Per-project override pattern

Any project repo can create its own `.claude/settings.local.json` to override or extend the global config. Document this pattern in the README. Example:

```
/workspace/gitprojects/adventure-alerts/
├── .claude/
│   └── settings.local.json    # Project-specific overrides
├── CLAUDE.md                  # Project-specific instructions
└── ... (project files)
```

---

## Files to Modify

### `.devcontainer/devcontainer.json`
- **Remove** the `~/.claude` bind mount from `mounts` array.
- **Update** `postCreateCommand` to call `install-claude-config.sh` (replaces or supplements current `setup-container.sh` + `init-gsd.sh` flow).
- Keep `CLAUDE_CONFIG_DIR` in `containerEnv`.

### `.devcontainer/Dockerfile`
- **Update** the alias definitions (lines 139-142) to remove the `cd /workspace/claudehome &&` prefix.
- **Remove** the `mcp-setup.sh` function append to `.bashrc`/`.zshrc` (already done in prior PR, but verify).
- The `mkdir -p /home/node/.claude` can stay (ensures the directory exists even before `postCreateCommand`).

### `.devcontainer/setup-container.sh`
- **Remove** any remaining references to host-mounted `~/.claude` content.
- Keep git config, Docker socket permissions, and Langfuse pip install.

### `.devcontainer/init-gsd.sh`
- Should still work — it installs GSD commands into `$CLAUDE_CONFIG_DIR/commands/gsd/`. Verify that it doesn't assume host-mounted content.
- Consider calling it from within `install-claude-config.sh` for a single orchestration point.

### New: `.devcontainer/install-claude-config.sh`
- The main orchestration script as described above.

### New: `claude-config/` directory
- Move skills from `/workspace/claudehome/.claude/skills/` to `claude-config/skills/`.
- Move hooks from their current location to `claude-config/hooks/`.
- Create `claude-config/settings.json` template with `{{...}}` placeholder tokens.
- Create `claude-config/commands/` (may be empty initially if all slash commands come from GSD).

### New: `secrets.json` ecosystem
- **`secrets.example.json`** — committed to repo, shows required schema with placeholder values.
- **`secrets.json`** — gitignored, holds real credentials. Created by user on first setup.
- **`.gitignore` update** — add `secrets.json` if not already present.

### New: `save-secrets` helper script
- Installed to `/usr/local/bin/save-secrets` (or as a shell function).
- Reads current live state from `~/.claude/` (auth tokens) and `~/.claude/settings.json` (Langfuse keys) and writes them into `/workspace/secrets.json`.
- Must be runnable manually at any time (e.g., after `claude` login, after rotating Langfuse keys).
- Prints what was captured.

### Required investigation: Claude Code auth file layout

Before implementing `save-secrets` and the auth restore logic in `install-claude-config.sh`, you **must** investigate exactly which files under `~/.claude/` constitute Claude Code's authentication state. Do this by:

1. Running `claude --version` to confirm the installed version.
2. Running `claude` and completing authentication.
3. Diffing the `~/.claude/` directory before and after auth to identify which files were created or modified.
4. Checking Claude Code's source/docs for any documented config structure (e.g., `~/.claude/.credentials`, `~/.claude/auth.json`, OAuth tokens, session files).
5. Testing that removing **only** those files forces re-authentication, confirming they are necessary and sufficient.

Document your findings in the design doc under `docs/`. The `save-secrets` and `install-claude-config.sh` scripts must target exactly the identified files — not a blanket copy of `~/.claude/`. If the auth layout is undocumented or unstable across versions, fall back to capturing the identified files as a base64 tarball in `secrets.json` under `claude.credentials`, and document that this may need updating when Claude Code is upgraded.

### `README.md`
- Update architecture diagram to reflect container-local config.
- Update "Quick Start" to remove any mention of host `~/.claude`.
- Update "Shell Shortcuts" to reflect aliases without `cd`.
- Add section on the `claude-config/` directory and how to customize.
- Document per-project override pattern.
- Update "Project Structure" tree.

---

## What NOT to Change

- **Firewall** — keep as-is from the prior PR.
- **MCP gateway** — `mcp-setup` stays in `postStartCommand`, generates `/workspace/.mcp.json`.
- **Langfuse stack** — unchanged, still Docker-outside-of-Docker.
- **Docker socket mount** — stays (needed for sibling containers).
- **Command history volume** — stays (persists shell history).
- **`CLAUDE_BYPASS_PERMISSIONS`** — stays.
- **Claude Code version** — stays `latest`.
- **GSD framework** — stays, just installed into container-local `~/.claude/` instead of host-mounted.

---

## Edge Cases to Handle

1. **Missing `secrets.json` on first setup.** The container must be usable without `secrets.json` — `install-claude-config.sh` warns clearly and leaves placeholders. Tracing won't work, but Claude Code itself is functional. The README should document the first-setup flow: build container → authenticate Claude → run `generate-env.sh` → run `save-secrets` → rebuild picks everything up.

2. **Claude auth token structure.** Claude Code may store auth across multiple files or in a format that changes between versions. `save-secrets` should capture the minimal set needed (investigate what files under `~/.claude/` constitute auth state — likely `.credentials` or similar). `install-claude-config.sh` restores them. If the exact files aren't deterministic, fall back to capturing/restoring a tarball of auth-related files as a base64 blob in `secrets.json` under `claude.credentials`.

3. **GSD state.** GSD stores state in `~/.claude/commands/gsd/` and `.planning/` (project-level). The project-level `.planning/` is in the workspace (persists). The command definitions in `~/.claude/` are regenerated by `npx get-shit-done-cc`. Verify nothing is lost.

4. **Hook state.** `langfuse_hook.py` uses `~/.claude/state/langfuse_state.json` to track last-processed transcript lines. This state is transient and can be lost on rebuild without issue, but verify.

5. **Langfuse `.env` sync.** If `secrets.json` has a `langfuse.secret_key` but the Langfuse `.env` was generated independently with a different key, they'll be out of sync. `install-claude-config.sh` should detect this and warn. Ideally `generate-env.sh` is updated to write its generated keys into `secrets.json`, and `install-claude-config.sh` reads from there — making `secrets.json` the canonical source for both.

---

## Deliverables

1. **`claude-config/`** directory with settings template (using `{{...}}` placeholders), skills, hooks, and commands (moved from their current locations).
2. **`secrets.example.json`** — committed, shows the required schema.
3. **`.devcontainer/install-claude-config.sh`** — the installation/orchestration script that reads `secrets.json`, hydrates templates, restores auth, and installs config.
4. **`save-secrets` script** — captures live credentials back into `secrets.json`.
5. **Modified `.devcontainer/` files** — devcontainer.json, Dockerfile, setup-container.sh, init-gsd.sh as needed.
6. **Updated `README.md`** — reflecting the new architecture, `secrets.json` setup flow, `save-secrets` usage, and per-project override pattern.
7. **Updated `docs/`** — a design doc explaining the refactor rationale, the `secrets.json` design, and the new config flow.
8. **Clean commits** — one per logical change group (e.g., "refactor: add claude-config source directory", "refactor: add secrets.json ecosystem", "refactor: remove host bind mount", "refactor: update aliases and launch flow", "docs: update README for container-local config").

Test with the same syntax validation pattern as before. Flag the real WSL2 build test as required.

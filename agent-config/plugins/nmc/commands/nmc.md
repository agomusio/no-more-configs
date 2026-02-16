---
description: "Show NMC system status — installed plugins, hooks, MCP servers, environment variables, and container info"
argument-hint: "[all|plugins|hooks|mcp|env|container|gsd]"
allowed-tools: ["Read", "Bash", "Grep", "Glob"]
---

# NMC System Status

Display the current state of the No More Configs system. Parse `$ARGUMENTS` to determine which section to show. If empty or "all", show all sections. Otherwise show only the requested section.

## Section: plugins

Discover installed NMC plugins and their status.

1. Use Glob to find all `/workspace/agent-config/plugins/*/plugin.json` files
2. Read `/workspace/config.json` once to get plugin enable/disable settings from `.plugins`
3. For each plugin.json found:
   - Read the manifest to get: name, version, description
   - Check `config.json` `.plugins[name].enabled` — if not mentioned, it's enabled by default
   - Count components using Bash `ls` on the plugin's subdirectories:
     - `skills/*/SKILL.md` count (each subdirectory with SKILL.md = 1 skill)
     - `commands/*.md` count
     - `agents/*.md` count
     - `hooks/*` count (non-json files only)
   - Note if the manifest declares `.hooks` (hook registrations)

Present as a table:

```
## Installed Plugins

| Plugin | Version | Status | Skills | Cmds | Agents | Hooks |
|--------|---------|--------|--------|------|--------|-------|
| nmc    | 1.0.0   | active | 1      | 1    | 1      | 0     |
```

Below the table, show a one-line total: "N plugins installed (N active, N disabled)"

## Section: hooks

Show all registered hooks from Claude Code settings.

1. Read `/home/node/.claude/settings.json` and extract `.hooks`
2. Read `/home/node/.claude/settings.json` and extract `.hooks`
3. For each hook event found across both files, list the commands:

```
## Registered Hooks

**Stop** (2 hooks)
  - `python3 /home/node/.claude/hooks/langfuse_hook.py` — settings.json
  - `bash /home/node/.claude/hooks/stop-hook.sh` — settings.json

**SessionStart** (1 hook)
  - `node /home/node/.claude/hooks/gsd-check-update.js` — settings.json
```

For each hook command, verify the script file exists using Bash `test -f`. If missing, append "(MISSING)" after the path.

## Section: mcp

Show configured MCP servers.

1. Read `/home/node/.claude/.mcp.json` and extract `.mcpServers`
2. For each server, display:
   - Name
   - Type: "sse" if it has a `url` field, "stdio" if it has a `command` field
   - Connection: the url or command + first few args

```
## MCP Servers

| Server | Type | Connection |
|--------|------|------------|
| mcp-gateway | sse | http://host.docker.internal:8811/sse |
| codex | stdio | npx -y codex-mcp-server |
```

## Section: env

Show environment variables set by the plugin system.

1. Read `/home/node/.claude/settings.json` and extract `.env`
2. For each variable, show the key and value
3. **Redact values** where the key contains SECRET, KEY, PASSWORD, or TOKEN (case-insensitive) — show `[redacted]` instead

```
## Plugin Environment Variables

| Variable | Value |
|----------|-------|
| TRACE_TO_LANGFUSE | true |
| LANGFUSE_HOST | http://host.docker.internal:3052 |
| LANGFUSE_PUBLIC_KEY | [redacted] |
| LANGFUSE_SECRET_KEY | [redacted] |
```

## Section: gsd

Show GSD (Get Shit Done) workflow system status.

1. Read `/home/node/.claude/gsd-file-manifest.json` to get:
   - `.version` — installed version
2. Read `/home/node/.claude/cache/gsd-update-check.json` to get:
   - `.update_available` — boolean
   - `.latest` — latest available version
   - `.checked` — unix timestamp of last check
3. Count GSD components using Bash:
   - `ls /home/node/.claude/commands/gsd/*.md 2>/dev/null | wc -l` — command count
   - `ls /home/node/.claude/agents/gsd-*.md 2>/dev/null | wc -l` — agent count
   - `ls /home/node/.claude/get-shit-done/workflows/*.md 2>/dev/null | wc -l` — workflow count
   - `ls /home/node/.claude/get-shit-done/references/*.md 2>/dev/null | wc -l` — reference count
   - `ls /home/node/.claude/get-shit-done/templates/*.md 2>/dev/null | wc -l` — template count
4. Check if GSD config exists: `test -f /home/node/.claude/get-shit-done/templates/config.json`

```
## GSD (Get Shit Done)

| Property | Value |
|----------|-------|
| Installed version | 1.19.1 |
| Latest version | 1.20.0 |
| Update available | yes |
| Last update check | 2026-02-15 23:16 |
| Commands | 29 |
| Agents | 11 |
| Workflows | 30 |
| References | 12 |
| Templates | 20 |
```

If `.update_available` is true, add a note after the table:
"Run `/gsd:update` to update to the latest version."

If the manifest file does not exist, show:
"GSD is not installed. Visit https://gsd.sh to install."

## Section: container

Show container environment info.

1. Run these Bash commands to gather info:
   - `node --version` — Node.js version
   - `claude --version 2>/dev/null || echo "not found"` — Claude Code version
   - `test -S /var/run/docker.sock && echo "yes" || echo "no"` — Docker socket
   - `whoami` — Current user
   - `echo $SHELL` — Shell

2. Check key paths exist using Bash `test -d`:
   - `/workspace` (workspace mount)
   - `/home/node/.claude` (Claude config)
   - `/commandhistory` (bash history volume)
   - `/home/node/.claude/projects` (conversations volume)

```
## Container

| Property | Value |
|----------|-------|
| User | node |
| Shell | /bin/zsh |
| Node.js | v20.x.x |
| Claude Code | x.x.x |
| Docker socket | yes |
| Workspace | /workspace (exists) |
| Conversations volume | /home/node/.claude/projects (exists) |
| History volume | /commandhistory (exists) |
```

## Summary Line

After all requested sections, print a single summary line:

```
---
NMC Status: X plugins (Y active) · Z hooks · W MCP servers · GSD vX.X.X
```

If GSD is not installed, omit the GSD portion from the summary line.

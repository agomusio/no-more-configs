---
description: "Orient yourself in this workspace — read the README, discover projects, and understand the environment"
allowed-tools: ["Read", "Bash", "Glob", "Grep"]
---

# NMC: Hi

Familiarize yourself with this workspace by reading key documentation and discovering what's here. Do this quickly and present a concise summary — don't overwhelm the user with raw file contents.

## Step 1: Read the workspace README

Read `/workspace/README.md`. Extract:
- What this workspace is (purpose, key tools)
- Shell shortcuts and aliases available
- Any quick reference or troubleshooting notes

## Step 2: Discover projects

List directories in `/workspace/projects/` using Bash `ls -1 /workspace/projects/`. For each project found:
- Check if it has a `README.md` and read the first 30 lines to get a one-line description
- Check if it has a `CLAUDE.md` (project-specific agent instructions)
- Check if it has `.claude/plugins/` (project plugins)
- Check if it's a git repo and show the current branch

## Step 3: Check environment

Run these quick checks:
- `claude --version 2>/dev/null` — Claude Code version
- `jq -r '.model // "unknown"' /home/node/.claude/settings.json 2>/dev/null` — configured model
- `jq -r '.effortLevel // "unknown"' /home/node/.claude/settings.json 2>/dev/null` — effort level
- `test -S /var/run/docker.sock && echo "available" || echo "unavailable"` — Docker socket

## Step 4: Present summary

Output a concise orientation like:

```
## Workspace: <name>

<1-2 sentence description from README>

### Projects
| Project | Branch | Description | Plugins |
|---------|--------|-------------|---------|
| ...     | main   | ...         | 1       |

### Environment
- **Claude Code** vX.X.X (opus, high effort)
- **Docker**: available
- **Shell shortcuts**: claude, clauder, codex, save-secrets, langfuse-setup, ...

### Quick Start
<any relevant tips from README — what to do first, key commands>
```

Keep the output short and actionable. The goal is to orient, not to dump everything.

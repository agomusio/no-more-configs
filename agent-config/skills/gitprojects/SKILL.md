---
name: gitprojects
description: Project directory mapping for repositories in the sandbox. Use when the user mentions a project by name, references gitprojects, asks about repos in the sandbox, or wants to work on a specific project.
license: MIT
metadata:
  author: Sam Boland
  version: "2.0.0"
---

# Git Projects Directory

All repositories developed inside the sandbox live under `/workspace/gitprojects/`. This skill maps project names to their paths so Claude Code can find them immediately.

## Project Registry

| Project Name | Directory | Remote | Status |
|-------------|-----------|--------|--------|
| **Adventure Alerts** | `/workspace/gitprojects/adventure-alerts/` | `https://github.com/agomusio/adventure-alerts.git` | Active |

## Name Aliases

When the user says any of these, resolve to the corresponding project:

- "Adventure Alerts", "adventure alerts", "AA", "aa", "the alerts project", "the trip planner" → `/workspace/gitprojects/adventure-alerts/`

## Project Details

### Adventure Alerts

**Path:** `/workspace/gitprojects/adventure-alerts/`
**Description:** Hybrid Trip-Planning & Booking Intelligence Engine

**Key files to read first:**

- `CLAUDE.md` — AI assistant context and working conventions
- `DECISIONS.md` — Implementation patterns and code conventions
- `README.md` — Product vision, setup, roadmap, implementation state

**Monorepo structure:**

```
adventure-alerts/
├── apps/
│   └── dashboard/          # Next.js 16.1 (App Router), Mantine UI, Tailwind CSS
├── packages/
│   ├── api/                # Cloudflare Workers + Hono, Durable Objects
│   ├── db/                 # Drizzle ORM schemas (Cloudflare D1)
│   └── types/              # Shared TypeScript interfaces, constants
```

**Tech stack:** Next.js, React, Mantine UI, Tailwind CSS, Cloudflare Workers, Hono, Durable Objects, D1, Drizzle ORM

## Adding a New Project

1. Clone into `/workspace/gitprojects/`:
   ```bash
   cd /workspace/gitprojects && git clone <url>
   ```
2. Add the path to `config.json → vscode.git_scan_paths` for VS Code git integration
3. Rebuild the container (or manually add to `.vscode/settings.json`)
4. Update this skill file with the new project entry

# Codebase Structure

**Analysis Date:** 2026-02-10

## Directory Layout

```
/workspace/                                # Workspace root (Windows host mount point)
├── .devcontainer/                          # VS Code Dev Container configuration
│   ├── Dockerfile                          # Container image definition (Node 20, CLI tools)
│   ├── devcontainer.json                   # Container metadata, mounts, ports, lifecycle hooks
│   ├── init-firewall.sh                    # iptables domain whitelist (postStartCommand)
│   ├── init-gsd.sh                         # GSD slash command installer (postCreateCommand)
│   ├── setup-container.sh                  # Post-create setup (git, Python packages, health checks)
│   └── docker-desktop (wsl.localhost).lnk  # Shortcut (Windows-specific)
├── .vscode/                                # VS Code workspace settings
├── .git/                                   # Git repository metadata
├── .gitignore                              # Global ignore patterns (node_modules, .env, logs, etc.)
├── .gitattributes                          # Line ending normalization for WSL/Windows
├── .planning/                              # GSD planning directory (created by /gsd:new-project)
│   └── codebase/                           # Codebase analysis documents (written by /gsd:map-codebase)
│       ├── ARCHITECTURE.md                 # Architecture patterns, layers, data flow
│       ├── STRUCTURE.md                    # Directory layout, file organization
│       ├── CONVENTIONS.md                  # Coding style, naming, patterns (quality focus)
│       ├── TESTING.md                      # Test frameworks, patterns (quality focus)
│       ├── STACK.md                        # Technology stack, dependencies (tech focus)
│       ├── INTEGRATIONS.md                 # External APIs, services (tech focus)
│       └── CONCERNS.md                     # Tech debt, issues (concerns focus)
├── README.md                               # Workspace overview, setup instructions
├── claudehome/                             # Claude Code home and local Langfuse stack
│   ├── .claude/                            # Claude Code configuration (bind-mounted from Windows %USERPROFILE%\.claude)
│   │   └── settings.local.json             # Local overrides for Claude Code settings
│   ├── .planning/                          # Per-project planning directory (git-ignored)
│   ├── CONTEXT_LOG.md                      # Perpetual context across Claude sessions
│   └── langfuse-local/                     # Self-hosted Langfuse observability stack
│       ├── docker-compose.yml              # Langfuse services: web, worker, postgres, clickhouse, redis, minio
│       ├── .env.example                    # Credential template (copy to .env and run generate-env.sh)
│       ├── .env                            # Generated credentials (git-ignored)
│       ├── LICENSE                         # Langfuse template license (MIT)
│       ├── README.md                       # Langfuse setup and operation guide
│       ├── hooks/
│       │   └── langfuse_hook.py            # Python script executed as Claude Code Stop hook (post-response tracing)
│       ├── scripts/
│       │   ├── generate-env.sh             # Interactive credential generator (random keys, user email/password)
│       │   ├── install-hook.sh             # Install hook into Claude Code settings and pip install langfuse
│       │   └── validate-setup.sh           # Pre-flight and post-setup validation
│       ├── settings-examples/
│       │   ├── global-settings.json        # Reference: global Claude Code settings with Langfuse tracing enabled
│       │   └── project-opt-out.json        # Reference: per-project override to disable tracing
│       └── tests/
│           ├── test_env_generation.sh      # Validate .env generation is idempotent
│           ├── test_hook_integration.py    # Integration test: hook parses transcripts and sends to Langfuse
│           ├── test_hook_unit.py           # Unit tests: parsing, sanitization, state tracking
│           └── test_syntax.sh              # Bash syntax validation for shell scripts
├── docs/                                   # Documentation (user-created)
│   └── mcp-integration-spec.md             # Model Context Protocol integration specification
├── projects/                               # Temporary project storage
│   ├── Test1/                              # Test project directory
│   ├── VCV/                                # VCV Rack patch files
│   │   ├── DefaultExample.vcv              # Example VCV module patch
│   │   ├── instructions.txt                # VCV usage instructions
│   │   └── Patch1/                         # VCV patch with npm dependencies
│   │       ├── patch.json                  # VCV patch metadata
│   │       ├── package.json                # Node dependencies (if any)
│   │       └── test_patch.vcv              # Test patch file
│   └── webapp/                             # Express.js web application skeleton
│       ├── package.json                    # Dependencies: express ^5.2.1
│       ├── package-lock.json               # Lockfile
│       └── public/                         # Static assets (placeholder)
└── gitprojects/                            # Git-tracked repositories (primary working directory for active development)
    └── adventure-alerts/                   # Main monorepo project (full-stack trip planning app)
        ├── .git/                           # Git repository metadata
        ├── .planning/                      # GSD project planning (git-ignored)
        │   └── config.json                 # GSD configuration and phase tracking
        ├── README.md                       # Product vision, roadmap, architecture overview
        ├── CLAUDE.md                       # Guidance for Claude Code working in this repo (stack, conventions, tier limits)
        ├── DECISIONS.md                    # Implementation patterns, code conventions, UI terminology, theme colors
        ├── package.json                    # Workspace root: dev dependencies, monorepo workspace definitions
        ├── package-lock.json               # Lockfile for all workspace packages
        ├── tsconfig.json                   # Root TypeScript configuration (extended by workspace packages)
        ├── .env                            # Secrets (git-ignored)
        ├── .gitignore                      # Git ignore patterns
        ├── prompt1.txt                     # Initial project prompt (archived)
        ├── apps/                           # Application packages
        │   └── dashboard/                  # Next.js 16.1 frontend (App Router)
        │       ├── src/
        │       │   ├── app/                # Next.js App Router pages
        │       │   │   ├── page.tsx        # Dashboard home (/dashboard)
        │       │   │   ├── layout.tsx      # Root layout wrapper
        │       │   │   ├── providers.tsx   # Client-side context providers
        │       │   │   ├── booking-browser/page.tsx  # Booking search page
        │       │   │   ├── trips/page.tsx  # Trip management page
        │       │   │   ├── settings/page.tsx # User settings page
        │       │   │   └── go-time/[activityId]/page.tsx # Focused booking countdown (planned)
        │       │   ├── components/         # Reusable UI components
        │       │   │   ├── header.tsx      # App header with nav
        │       │   │   ├── sidebar.tsx     # Main navigation sidebar
        │       │   │   ├── alerts-table.tsx # Activity alert list
        │       │   │   ├── alert-form.tsx  # Add/edit alert form
        │       │   │   ├── trip-form.tsx   # Add/edit trip form
        │       │   │   ├── upcoming-bookings.tsx # Upcoming activities widget
        │       │   │   ├── system-status.tsx # Health/status display
        │       │   │   ├── master-clock.tsx # Master countdown timer
        │       │   │   ├── utc-clock.tsx   # UTC time display
        │       │   │   └── [other components] # Theme, forms, etc.
        │       │   └── lib/
        │       │       └── theme.ts        # Tailwind/Mantine theme configuration
        │       ├── next.config.ts          # Next.js configuration
        │       ├── tailwind.config.ts      # Tailwind CSS configuration
        │       ├── package.json            # Dependencies: next 16.1, mantine, tailwindcss, typescript
        │       ├── tsconfig.json           # TypeScript configuration (App Router)
        │       └── next-env.d.ts           # Next.js type definitions (auto-generated)
        └── packages/                       # Shared libraries and backends
            ├── api/                        # Cloudflare Workers backend (Hono + Durable Objects)
            │   ├── src/
            │   │   ├── alert-manager.ts    # Alert lifecycle and notification logic
            │   │   ├── index.ts            # Worker entry point (Hono router)
            │   │   ├── durable-objects/    # Durable Objects (stateful counters, timers)
            │   │   └── routes/             # API endpoints (bookings, alerts, trips)
            │   ├── wrangler.toml           # Cloudflare Workers configuration
            │   ├── package.json            # Dependencies: hono, @cloudflare/workers-types, typescript
            │   └── tsconfig.json           # TypeScript configuration for Worker
            ├── db/                         # Drizzle ORM schemas and migrations
            │   ├── src/
            │   │   ├── schema.ts           # Drizzle table definitions (users, trips, activities, events, rules)
            │   │   └── migrations/         # SQL migrations (managed by drizzle-kit)
            │   ├── migrations/
            │   │   └── meta/               # Migration metadata
            │   ├── package.json            # Dependencies: drizzle-orm, drizzle-kit, sqlite3
            │   └── tsconfig.json           # TypeScript configuration
            └── types/                      # Shared TypeScript interfaces
                ├── src/
                │   ├── api.ts              # API request/response types
                │   ├── models.ts           # Data model types (User, Trip, Activity, Event, Rule, Blueprint)
                │   ├── enums.ts            # Enums (TierLimits, AlertStage, RuleOperators)
                │   └── index.ts            # Barrel export
                ├── package.json            # Dependencies: typescript (dev only)
                └── tsconfig.json           # TypeScript configuration
```

## Directory Purposes

**`.devcontainer/`:**
- Purpose: Container configuration and initialization scripts for VS Code Dev Containers
- Contains: Dockerfile (base image, tools, Claude CLI), JSON config (mounts, ports, lifecycle), shell scripts (firewall, git, GSD)
- Key files: `Dockerfile` (image definition), `devcontainer.json` (container runtime config), `init-firewall.sh` (security), `setup-container.sh` (post-create)

**`claudehome/`:**
- Purpose: Claude Code home directory and self-hosted observability stack
- Contains: `.claude/` config, `.planning/` project state, Langfuse Docker Compose stack, tracing hook
- Key files: `langfuse-local/docker-compose.yml` (services), `langfuse_hook.py` (tracing), `scripts/` (setup/validation)

**`claudehome/langfuse-local/`:**
- Purpose: Self-hosted Langfuse observability for Claude Code session tracing
- Contains: Docker Compose definition, credential generation, Python hook, tests
- Key files:
  - `docker-compose.yml`: 6 services (web, worker, postgres, clickhouse, redis, minio)
  - `hooks/langfuse_hook.py`: Post-response tracer (executed by Stop hook)
  - `scripts/generate-env.sh`: Credential generator (interactive, creates `.env`)
  - `.env.example`: Template (cp to `.env`)

**`projects/`:**
- Purpose: Scratch space for temporary projects and examples
- Contains: Test projects, VCV Rack patches, prototype webapps
- Not git-tracked (gitignored); used for experimentation and single-session work

**`gitprojects/`:**
- Purpose: Primary working directory for git-tracked projects under active development
- Contains: `adventure-alerts/` monorepo with apps, packages, planning docs
- Key file: `adventure-alerts/` is the main development project

**`gitprojects/adventure-alerts/`:**
- Purpose: Full-stack trip planning application using Next.js, Cloudflare Workers, SQLite
- Contains: Monorepo with apps (frontend), packages (backend, ORM, types)
- Key structure:
  - `apps/dashboard/`: Next.js 16.1 frontend (Mantine UI, Tailwind)
  - `packages/api/`: Hono + Cloudflare Workers + Durable Objects backend
  - `packages/db/`: Drizzle ORM schemas and migrations
  - `packages/types/`: Shared TypeScript interfaces

**`docs/`:**
- Purpose: User-created documentation and specifications
- Contains: MCP integration spec, architecture notes

## Key File Locations

**Entry Points:**

- `/.devcontainer/Dockerfile` — Container base image definition (Node 20, Claude CLI, GSD)
- `/workspace` (bind-mounted) — Dev container working directory and Claude Code default workspace
- `gitprojects/adventure-alerts/` — Primary git-tracked project
- `/home/node/.claude/settings.json` (in container) — Claude Code configuration with hook registration (bind-mounted from Windows `%USERPROFILE%\.claude`)

**Configuration:**

- `/.devcontainer/devcontainer.json` — Container runtime config (mounts, ports, env vars, lifecycle)
- `/claudehome/.claude/settings.local.json` — Local Claude Code settings overrides
- `/claudehome/langfuse-local/.env` — Langfuse credentials (generated, git-ignored)
- `/claudehome/langfuse-local/.env.example` — Credential template
- `gitprojects/adventure-alerts/package.json` — Monorepo workspace definitions
- `gitprojects/adventure-alerts/tsconfig.json` — Root TypeScript config

**Core Logic:**

- `/claudehome/langfuse-local/hooks/langfuse_hook.py` — Tracing hook (parses transcripts, sends to Langfuse)
- `gitprojects/adventure-alerts/apps/dashboard/src/` — Next.js frontend source
- `gitprojects/adventure-alerts/packages/api/src/` — Cloudflare Worker API
- `gitprojects/adventure-alerts/packages/db/src/schema.ts` — Drizzle ORM schema

**Testing:**

- `/claudehome/langfuse-local/tests/` — Hook unit, integration, and shell tests
- (Adventure Alerts testing: TBD, no test files found in current structure)

**Documentation:**

- `/README.md` — Workspace overview
- `/claudehome/CONTEXT_LOG.md` — Perpetual session context
- `/claudehome/langfuse-local/README.md` — Langfuse setup guide
- `gitprojects/adventure-alerts/CLAUDE.md` — Claude Code guidance for repo
- `gitprojects/adventure-alerts/DECISIONS.md` — Implementation decisions and patterns
- `gitprojects/adventure-alerts/README.md` — Product vision and architecture

## Naming Conventions

**Files:**

- **Shell scripts:** `lowercase-with-hyphens.sh` (e.g., `init-firewall.sh`, `setup-container.sh`)
- **Python scripts:** `lowercase_with_underscores.py` (e.g., `langfuse_hook.py`, `test_hook_unit.py`)
- **TypeScript:** `camelCase.ts` or `PascalCase.tsx` depending on export type:
  - **Components:** `PascalCase.tsx` (e.g., `AlertForm.tsx`, `Header.tsx`)
  - **Utilities:** `camelCase.ts` (e.g., `theme.ts`, `alert-manager.ts`)
  - **Types/Schemas:** `camelCase.ts` or `index.ts` for barrel exports (e.g., `schema.ts`, `index.ts`)
- **Config files:** `lowercase-dotted.ext` or plain names (e.g., `.env`, `next.config.ts`, `wrangler.toml`, `tailwind.config.ts`)
- **Documentation:** `UPPERCASE.md` for major docs (e.g., `README.md`, `CLAUDE.md`, `DECISIONS.md`)
- **Markdown in `.planning/`:** `UPPERCASE.md` (e.g., `ARCHITECTURE.md`, `STRUCTURE.md`)

**Directories:**

- **Package directories:** `lowercase-with-hyphens` (e.g., `langfuse-local`, `adventure-alerts`)
- **Feature directories:** `lowercase-with-hyphens` (e.g., `durable-objects`, `booking-browser`)
- **Standard directories:** `lowercase` (e.g., `src`, `tests`, `scripts`, `hooks`, `apps`, `packages`)
- **Special directories:** Prefixed with dot for hidden (e.g., `.devcontainer`, `.planning`, `.git`, `.vscode`)
- **Capitalized directories:** Non-existent in current codebase (avoid)

## Where to Add New Code

**New Feature in Adventure Alerts:**

- **Frontend Page/Component:**
  - Pages: `gitprojects/adventure-alerts/apps/dashboard/src/app/[feature]/page.tsx`
  - Components: `gitprojects/adventure-alerts/apps/dashboard/src/components/[feature].tsx`
  - Shared types: `gitprojects/adventure-alerts/packages/types/src/models.ts`

- **Backend API Endpoint:**
  - Worker route: `gitprojects/adventure-alerts/packages/api/src/routes/[feature].ts`
  - Durable Object: `gitprojects/adventure-alerts/packages/api/src/durable-objects/[feature].ts`
  - Types: `gitprojects/adventure-alerts/packages/types/src/api.ts`

- **Database Schema Extension:**
  - Schema: `gitprojects/adventure-alerts/packages/db/src/schema.ts` (add new Drizzle table)
  - Migration: `gitprojects/adventure-alerts/packages/db/migrations/` (run `drizzle-kit generate`)

**New Shared Library:**

- Create new workspace in `gitprojects/adventure-alerts/packages/[library-name]/`
- Include: `src/index.ts` (barrel), `package.json`, `tsconfig.json`
- Update root `package.json` workspaces array

**New Hook or Utility:**

- Shared utilities: `gitprojects/adventure-alerts/packages/api/src/` (if backend-specific)
- Claude tracing utilities: `claudehome/langfuse-local/hooks/` (if observability-related)
- Dev container scripts: `.devcontainer/` (if container-specific)

**New Test:**

- Hook tests: `claudehome/langfuse-local/tests/test_[feature].py` (Python unit/integration)
- Adventure Alerts tests: `gitprojects/adventure-alerts/[workspace]/src/__tests__/` (TBD, not yet structured)

## Special Directories

**`.devcontainer/`:**
- Purpose: Dev Container configuration (not executed during normal development)
- Generated: No
- Committed: Yes (version-controlled)
- Modified: Only when container requirements change (packages, firewall rules, lifecycle hooks)

**`claudehome/.planning/`:**
- Purpose: Per-project GSD planning state (created by `/gsd:new-project`)
- Generated: Yes (by GSD commands)
- Committed: No (git-ignored in root `.gitignore`)
- Contains: `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json`

**`.planning/codebase/`:**
- Purpose: Codebase analysis documents (created by `/gsd:map-codebase`)
- Generated: Yes (by GSD mapper agent)
- Committed: Varies (typically git-ignored, uploaded to planning system)
- Contains: `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `TESTING.md`, `STACK.md`, `INTEGRATIONS.md`, `CONCERNS.md`

**`claudehome/langfuse-local/`:**
- Purpose: Self-hosted observability stack (Docker Compose project)
- Generated: `.env` (by `generate-env.sh`), logs (by services)
- Committed: Yes for code, No for `.env` (git-ignored)
- Volumes: Named volumes for PostgreSQL, ClickHouse (persist across restarts)

**`.claude/` (in container):**
- Purpose: Claude Code configuration and state (bind-mounted from Windows host)
- Generated: Yes (by Claude Code and hook script)
- Committed: Partially (some files tracked in git, `settings.json` often git-ignored)
- Persistence: Survives container rebuilds (bound from Windows host)

**`node_modules/` and `dist/`:**
- Purpose: Build artifacts and dependencies (git-ignored)
- Generated: Yes (by npm install, build scripts)
- Committed: No (git-ignored)
- Cleanup: `npm ci` (clean install), `npm run clean` (if defined)

---

*Structure analysis: 2026-02-10*

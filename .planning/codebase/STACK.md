# Technology Stack

**Analysis Date:** 2026-02-10

## Languages

**Primary:**
- TypeScript 5.7.2 - All projects use TypeScript for type safety
- JavaScript (ES Modules) - Runtime execution through Node.js and Cloudflare Workers
- YAML - Docker Compose configuration and devcontainer setup

**Secondary:**
- Python 3 - Development utilities and scripting support
- Bash - Shell scripting for setup and initialization
- SQL - Database schema and migrations via Drizzle Kit

## Runtime

**Environment:**
- Node.js 20 - Base runtime in devcontainer (`FROM node:20`)
- Cloudflare Workers - Serverless compute for API deployments
- Docker - Container orchestration for local development services
- Cloudflare D1 - Distributed SQLite database for Workers

**Package Manager:**
- npm - Primary package manager with monorepo workspaces
- Lockfile: Not detected in provided artifacts (npm-shrinkwrap.json or package-lock.json assumed)

## Frameworks

**Core:**
- Hono 4.6.14 - Lightweight web framework for Cloudflare Workers API (`packages/api`)
- Next.js 16.1 - React meta-framework for dashboard UI (`apps/dashboard`)
- React 19.2.0 - UI library with React DOM 19.2.0

**Data/ORM:**
- Drizzle ORM 0.38.3 - Type-safe SQL query builder
- Drizzle Kit 0.31.8 - Schema generation and migration management
- SQLite - Database dialect via Cloudflare D1 and Drizzle

**UI Libraries:**
- Mantine 8.3.12 - React component library with theming
- Mantine Hooks 8.3.12 - Custom React hooks for form and state management
- Mantine Form 8.3.12 - Form state management
- Mantine Dates 8.3.12 - Date picker components
- TailwindCSS 3.4.17 - Utility-first CSS framework
- Tabler Icons React 3.36.1 - Icon library integration
- Lucide React 0.469.0 - Alternative/supplementary icon library

**Build/Dev:**
- Wrangler 4.59.2 - Cloudflare Workers CLI and bundler
- Next.js Dev Server - Built-in development server with hot reload
- TypeScript Compiler 5.7.2 - Type checking without transpilation (tsc --noEmit)

**Testing:**
- Not detected in current package.json files

## Key Dependencies

**Critical:**
- `@adventure-alerts/db` - Internal monorepo package for database schema and migrations
- `@adventure-alerts/types` - Internal monorepo package for shared TypeScript types
- `@adventure-alerts/api` - Internal monorepo package for Workers API logic
- `@adventure-alerts/dashboard` - Internal monorepo package for Next.js frontend
- `@cloudflare/workers-types` 4.20241230.0 - Type definitions for Cloudflare Workers APIs

**Infrastructure:**
- `postcss` 8.5.6 - CSS transformation for Tailwind processing
- `postcss-preset-mantine` 1.18.0 - Mantine CSS preprocessing
- `postcss-simple-vars` 7.0.1 - CSS variable support
- `autoprefixer` 10.4.20 - CSS vendor prefixing
- `dayjs` 1.11.19 - Lightweight date/time manipulation library
- `drizzle-orm` 0.38.3 - ORM for type-safe database queries

## Configuration

**Environment:**
- Monorepo workspaces: `packages/db`, `packages/api`, `packages/types`, `apps/dashboard`
- Node requirement: `>= 20.0.0` (specified in root `package.json`)
- Devcontainer target: Linux with Docker-in-Docker support
- Langfuse integration: Configured via `LANGFUSE_HOST` environment variable pointing to `http://host.docker.internal:3052`

**Build:**
- TypeScript configuration: `tsconfig.json` in each package with module resolution
- Next.js config: `next.config.ts` in dashboard with Turbopack and webpack overrides for polling
- PostCSS config: `postcss.config.mjs` in dashboard
- Tailwind config: `tailwind.config.ts` in dashboard
- Drizzle config: `drizzle.config.ts` in database package (SQLite, D1 driver)
- Wrangler config: `wrangler.toml` for Workers deployment (not provided but referenced)

## Platform Requirements

**Development:**
- Linux-based container environment (Debian-based in devcontainer)
- Docker daemon access via `/var/run/docker.sock` bind mount
- Git 2.37+ for version control
- `node` user with sudo access for Docker operations
- Tools: fzf, zsh, jq, curl, tar-stream support (zstd compression libraries)

**Production:**
- Cloudflare Workers runtime for API deployment
- Cloudflare Pages for dashboard deployment
- Local Docker Compose stack for Langfuse integration (optional, self-hosted observability)

## Development Tooling

**Editor/IDE:**
- VS Code extensions configured:
  - ESLint integration
  - Prettier formatter
  - Cloudflare Workers Bindings
  - SQLite Viewer
  - TailwindCSS IntelliSense
- Default formatter: Prettier
- Format on save: Enabled
- ESLint auto-fix on save: Enabled

**VCS:**
- Git with delta diff viewer
- Git delta version: 0.18.2
- Safe directory configuration for multi-workspace setup

**Claude Integration:**
- Claude Code CLI installed in devcontainer
- GSD (Get Shit Done) framework installed via npm globally
- Claude configuration directory: `/home/node/.claude`

---

*Stack analysis: 2026-02-10*

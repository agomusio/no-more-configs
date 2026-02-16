# Technology Stack

**Analysis Date:** 2026-02-16

## Languages

**Primary:**
- TypeScript 5.7.2 - All source code across monorepo (frontend, backend, schemas, types)
- JavaScript - Build tooling (Next.js config, PostCSS config)

**Markup & Styling:**
- JSX/TSX - React components
- CSS - Tailwind CSS utility classes with Mantine preset
- JSONC - Wrangler configuration

## Runtime

**Environment:**
- Node.js >= 20.0.0 (development and build)
- Cloudflare Workers (API production deployment)
- Browser (React 19)

**Package Manager:**
- npm 10+ (workspace-based monorepo)
- Lockfile: `package-lock.json` present and committed

## Frameworks

**Core Web:**
- Next.js 16.1 - Dashboard frontend with App Router (`apps/dashboard/`)
- React 19.2.0 - UI component library
- Hono 4.6.14 - Lightweight API framework for Cloudflare Workers (`packages/api/`)

**UI Components:**
- Mantine UI 8.3.12 - Component library with theming system
  - @mantine/core - Core components (Container, Stack, Paper, Modal, etc.)
  - @mantine/form - Form handling and validation
  - @mantine/dates - Date/time picker components
  - @mantine/hooks - Utility hooks (useInterval, useDisclosure, etc.)
- Tabler Icons React 3.36.1 - Icon library
- Lucide React 0.469.0 - Additional icon set

**Styling & Layout:**
- Tailwind CSS 3.4.17 - Utility-first CSS framework
- PostCSS 8.5.6 - CSS transformation pipeline
- autoprefixer 10.4.20 - Browser vendor prefixing
- postcss-preset-mantine 1.18.0 - Mantine variables plugin
- postcss-simple-vars 7.0.1 - CSS variable support

**Date/Time:**
- dayjs 1.11.19 - Lightweight date manipulation library (Unix timestamp handling)

**Database & ORM:**
- Drizzle ORM 0.38.3 - Type-safe SQL query builder
- Drizzle Kit 0.31.8 - Schema generation and migrations
- SQLite (Cloudflare D1) - Database backend

## Key Dependencies

**Critical:**
- drizzle-orm 0.38.3 - ORM for all database operations across `packages/db/` and `packages/api/`
- hono 4.6.14 - API request routing and middleware (CORS, response handling)
- @adventure-alerts/types * - Shared TypeScript interfaces (types are the leaf dependency)

**Infrastructure:**
- cloudflare:workers - Durable Objects and Workers platform API
- @cloudflare/workers-types 4.20241230.0 - TypeScript definitions for Cloudflare Workers

**Build & Development:**
- wrangler 4.59.2 - Cloudflare Workers CLI (dev server, deployment)
- typescript 5.7.2 - TypeScript compiler across all packages
- next 16.1 - Next.js CLI and build system with Turbopack

## Configuration

**Environment:**
- Cloudflare account credentials required (CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN in `.env`)
- API URL configurable via NEXT_PUBLIC_API_URL environment variable (defaults to `http://localhost:8787`)
- Wrangler configuration in `packages/api/wrangler.jsonc` defines D1 database and Durable Object bindings

**Build:**
- Root `tsconfig.json` - Shared TypeScript compiler settings (ES2022 target, strict mode)
- `apps/dashboard/tsconfig.json` - Next.js-specific overrides with DOM types and path aliases (@/*)
- `packages/api/tsconfig.json` - Workers-specific configuration
- Next.js Turbopack enabled for dev builds (`turbopack: {}` in next.config.ts)
- Webpack polling configured for WSL/Docker environments (WATCHPACK_POLLING=true, CHOKIDAR_USEPOLLING=true)

**Workspace:**
- Monorepo root `package.json` with npm workspaces pointing to `apps/*` and `packages/*`
- Cross-package imports allowed via npm workspace resolution (`@adventure-alerts/` namespace)
- Shared dev dependencies in root (typescript, wrangler, drizzle-kit)

## Platform Requirements

**Development:**
- VS Code with Dev Containers extension (optional, but project designed for containerized dev)
- Docker Desktop (if using devcontainer)
- Git
- Node.js >= 20.0.0
- Cloudflare account with:
  - D1 Database provisioned (database_id: c65216e5-aedf-4a5d-a3a5-f9873558c851)
  - Durable Objects enabled
  - Worker account for API deployment

**Production:**
- Cloudflare Workers (App Engine equivalent)
- Cloudflare D1 (managed SQLite)
- Cloudflare Durable Objects (state management for precision timers)
- Vercel or similar platform for Next.js Dashboard deployment (currently configured for local dev)

## Build & Dev Commands

```bash
# Root monorepo
npm run dev              # Runs dashboard in watch mode (port 3000)
npm run dev:api          # Runs API worker in local mode (port 8787)
npm run build            # Builds all workspaces
npm run lint             # Lints all workspaces
npm run typecheck        # Type-checks all workspaces

# Dashboard only
cd apps/dashboard
npm run dev              # Next.js dev server with polling enabled
npm run build            # Next.js production build
npm run start            # Start production server
npm run lint             # Next.js ESLint
npm run typecheck        # tsc type checking

# API only
cd packages/api
npm run dev              # Wrangler dev server (local environment)
npm run deploy           # Deploy to Cloudflare edge
npm run typecheck        # tsc type checking
```

---

*Stack analysis: 2026-02-16*

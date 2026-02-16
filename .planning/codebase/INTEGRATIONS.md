# External Integrations

**Analysis Date:** 2026-02-16

## APIs & External Services

**Meilisearch (Planned):**
- Service - Event/booking search engine integration
- Status: Planned, not yet implemented
- Endpoint: `/events/search` (documented but unimplemented in `packages/api/README.md`)
- Use Case: Full-text search across event catalog (Disney dining, permits, tours, cruises)

**Master Authority Clock Sync:**
- Service - Internal API endpoint for time synchronization across client and server
- Endpoint: `GET /time` via `packages/api/`
- Returns: UTC ISO string, Unix milliseconds, and timezone info
- Used By: Dashboard components and Activities for countdown calculations

## Data Storage

**Databases:**

**Cloudflare D1 (SQLite):**
- Connection: Wrangler binding named `DB` in `packages/api/wrangler.jsonc`
- Database ID: c65216e5-aedf-4a5d-a3a5-f9873558c851
- Database Name: adventure-alerts-db
- Client: Drizzle ORM 0.38.3 (`packages/db/`)
- Migrations: Located in `packages/db/migrations/` (managed via drizzle-kit)
- Tables:
  - `users` - User profiles with tier (scout/voyager/advisor) and preferences
  - `trips` - User's trip groupings with date ranges
  - `activities` (aliased as `alerts` for backward compatibility) - Booking instances with precise Unix ms timestamps
  - `events` - Searchable event catalog with vendor, category, and booking rules
  - `booking_rules` - Reusable timing patterns (offset days, exact time, timezone)
  - `blueprints` - Planning documents attached to booking rules

**File Storage:**
- Local filesystem only - No external S3 or cloud storage integration detected

**Caching:**
- None detected - No Redis or in-memory caching layer configured

## Authentication & Identity

**Auth Provider:**
- Custom/Placeholder - Currently hardcoded to `demo-user`
- Implementation: All API endpoints accept `userId` as `demo-user` (Phase 2 TODO)
- Location: `packages/api/src/index.ts` - All endpoints reference a placeholder user ID
- Planned: OAuth or session-based auth (not yet implemented)

## Monitoring & Observability

**Error Tracking:**
- Not configured - No Sentry, Rollbar, or error reporting service integrated

**Logs:**
- Console-based only - Standard Node.js/browser console.log
- Wrangler logs available via `wrangler tail` command for deployed workers

## CI/CD & Deployment

**Hosting:**

**Frontend:**
- Target: Vercel or similar Next.js hosting (not yet deployed)
- Local: Next.js dev server on `http://localhost:3000`
- Environment: Next.js App Router with React 19

**Backend:**
- Platform: Cloudflare Workers (production deployment target)
- Local Dev: Wrangler dev server on `http://localhost:8787` with `--local-protocol http`
- Deployment Command: `npx wrangler deploy` (~5 seconds to edge)
- Compatibility: nodejs_compat flag enabled for Node.js built-ins

**CI Pipeline:**
- None detected - No GitHub Actions, GitLab CI, or other automated testing configured

## Environment Configuration

**Required env vars:**
- `CLOUDFLARE_ACCOUNT_ID` - Cloudflare account identifier (in `.env`)
- `CLOUDFLARE_API_TOKEN` - Cloudflare API authentication (in `.env`)
- `NEXT_PUBLIC_API_URL` - Dashboard API endpoint (optional, defaults to `http://localhost:8787`)

**Development environment vars:**
- `WATCHPACK_POLLING=true` - Enable polling for file changes (WSL/Docker)
- `CHOKIDAR_USEPOLLING=true` - Enable polling for Next.js file watcher (WSL/Docker)

**Secrets location:**
- `.env` file at project root contains Cloudflare credentials (should be in .gitignore)
- NMC workspace may hydrate additional secrets from `secrets.json` into plugin env vars

## Webhooks & Callbacks

**Incoming:**
- None detected - No webhook receivers configured

**Outgoing:**
- Cloudflare Durable Object alarms trigger internal HTTP calls
- Location: `packages/api/src/alert-manager.ts`
- Pattern: Alarm fires 100ms before target time, triggers internal routes:
  - `POST /schedule` - Schedule a new alert in the PRECISION_TIMER Durable Object
  - `DELETE /cancel/{id}` - Cancel pending alert
  - `GET /status` - Query pending count and next alarm time
- Not exposed externally - Internal HTTP interface only

## Durable Objects (Stateful Computing)

**AlertManager (PRECISION_TIMER):**
- Binding: `PRECISION_TIMER` in wrangler.jsonc
- Class: `AlertManager` (defined in `packages/api/src/alert-manager.ts`)
- Persistence: Transactional storage for alert metadata (stored as `alert:{id}` keys)
- Purpose: Millisecond-accurate alert scheduling using Cloudflare Alarms API
- Instance: Single global instance using `idFromName('global-timer')`
- Lifecycle:
  1. Dashboard calls `POST /alerts` endpoint
  2. API stores alert data in D1 database
  3. API calls `POST /schedule` on PRECISION_TIMER DO
  4. DO stores alert state and schedules alarm 100ms before target time
  5. Alarm fires: DO triggers alerts, updates D1 status, chains to next alarm
  6. Dashboard cancels: calls `DELETE /alerts/:id`, which triggers `DELETE /cancel/{id}` on DO

## CORS Configuration

**Allowed Origins:**
- `localhost:3000` - Dashboard dev server
- `localhost:3001` - Alternative local frontend
- Cloudflare Pages deployment URL (configured in API worker via `cors()` middleware from Hono)
- Configured in: `packages/api/src/index.ts` using Hono's built-in CORS middleware

## Data Flow & API Contracts

**Trip Management Flow:**
1. Dashboard: `GET /trips` - Fetch user's trips
2. Dashboard: `POST /trips` - Create trip with date range validation
3. API validates: Trip duration matches tier limits (`validateTripDuration()`)
4. Database: Stores in `trips` table with `userId`

**Activity (Booking Alert) Flow:**
1. Dashboard: `GET /alerts` - List pending activities
2. Dashboard: `POST /alerts` - Create alert with event and target time
3. API validates: Tier limits via `TIER_LIMITS[userTier]`
4. Database: Stores in `activities` table with precise `targetTimeUtc` (Unix ms)
5. Durable Object: Schedules alarm 100ms before `targetTimeUtc`
6. Dashboard: `GET /time` - Syncs master clock for countdown calculations
7. Dashboard: `DELETE /alerts/:id` - Cancel alert and unschedule from DO

**Response Format (Consistent across all endpoints):**
```typescript
Success: { success: true, data?: T }
Error:   { success: false, error: "message" }
```

---

*Integration audit: 2026-02-16*

# Architecture

**Analysis Date:** 2026-02-16

## Pattern Overview

**Overall:** Monorepo with layered separation (frontend, backend API, shared types/database). Event-driven booking system with precision timing requirements using Cloudflare Workers + Durable Objects for millisecond-accurate alert scheduling.

**Key Characteristics:**
- Monorepo workspace structure (Yarn/npm workspaces)
- Clean separation of concerns: types → database schemas → API layer → frontend HTTP client
- Precision timing via Cloudflare Durable Objects for alert scheduling
- Tier-based access control enforced at API endpoints
- Server-synced clock mechanism for client-side time accuracy

## Layers

**Types & Constants Layer (`packages/types`):**
- Purpose: Single source of truth for TypeScript interfaces, constants, and business logic validators
- Location: `/workspace/gitprojects/adventure-alerts/packages/types/src/index.ts`
- Contains: User/activity/trip/event types, tier limits, validation functions (validateTripDuration, getDashboardState), API request/response contracts
- Depends on: Nothing (leaf module)
- Used by: API and Dashboard for type safety and validation

**Database Schema & ORM (`packages/db`):**
- Purpose: Cloudflare D1 SQLite schema definitions with Drizzle ORM
- Location: `/workspace/gitprojects/adventure-alerts/packages/db/src/`
  - `schema.ts`: 8 tables (users, trips, activities, events, booking_rules, blueprints, and legacy alerts)
  - `index.ts`: Factory function `createDb()` for D1 binding
- Contains: Drizzle table definitions, type inference exports
- Depends on: `@adventure-alerts/types` (imports types for schema references)
- Used by: API package via `createDb()` factory

**API Layer (`packages/api`):**
- Purpose: Cloudflare Workers HTTP API (Hono.js) with Durable Object integration
- Location: `/workspace/gitprojects/adventure-alerts/packages/api/src/`
  - `index.ts`: 11 HTTP endpoints, CORS handling, request validation, tier enforcement
  - `alert-manager.ts`: AlertManager Durable Object class for precision scheduling
- Contains: Route handlers, database queries (both Drizzle ORM and raw SQL), Durable Object integration
- Depends on: `@adventure-alerts/db`, `@adventure-alerts/types`
- Used by: Dashboard via HTTP (never imported directly)

**Frontend Dashboard (`apps/dashboard`):**
- Purpose: Next.js 16 App Router SPA with real-time clock sync and booking countdown UI
- Location: `/workspace/gitprojects/adventure-alerts/apps/dashboard/src/`
  - Entry: `app/page.tsx` (home/Mission Control page)
  - Pages: `trips/`, `booking-browser/`, `settings/`
  - Components: Modular Mantine UI components (master-clock, upcoming-bookings, sidebar, header, etc.)
  - Theme: `lib/theme.ts` (Mantine + Tailwind CSS)
- Contains: Server-side time sync logic, real-time countdown rendering, UI state management
- Depends on: `@adventure-alerts/types` (for type contracts)
- Used by: Browser clients via URL

## Data Flow

**Alert Creation & Scheduling:**

1. User submits alert form in Dashboard (page.tsx or alert-form.tsx component)
2. Dashboard POST to `/alerts` endpoint with event details
3. API validates required fields (eventName, targetTimeUtc)
4. API inserts into `alerts` table (raw SQL for legacy compatibility)
5. API calls Durable Object via `PRECISION_TIMER` namespace: POST `/schedule`
6. AlertManager.scheduleAlert() stores alert state in DO storage, sets alarm
7. Return 201 with alert details to Dashboard

**Trip Creation & Tier Validation:**

1. User submits trip form in Dashboard (trips/page.tsx)
2. Dashboard POST to `/trips` with name, startDate, endDate
3. API validates date order and calls `validateTripDuration()` from types
4. API queries user tier from `users` table
5. API checks active trip count against `TIER_LIMITS[userTier].maxActiveTrips`
6. If under limit, insert into `trips` table via Drizzle ORM
7. Return 201 with trip or 403 with error message

**Real-Time Clock Synchronization:**

1. Dashboard mounts (page.tsx useEffect)
2. Calls GET `/time` endpoint, measures round-trip latency
3. Calculates `serverTimeOffset` = estimated server time - client time
4. Stores offset for all downstream time comparisons
5. Every 30s, re-syncs offset via useInterval hook
6. Master clock component uses `serverTimeOffset` to display corrected UTC time
7. Countdown cards use `getDashboardState(targetMs, Date.now() + serverTimeOffset)` for accuracy

**Alert Triggering (Durable Object Alarm):**

1. AlertManager.alarm() fires at scheduled time
2. Loops through stored alerts in DO storage
3. For triggered alerts (scheduledTime <= now + 100ms):
   - Calls `markAlertTriggered()` to update alerts table status
   - Deletes from DO storage
4. Calculates next alarm time and re-schedules
5. Dashboard polls GET `/alerts` every 5s, displays updated status

**State Management:**

- **Server state**: D1 database (persistent) + Durable Object storage (alert scheduling memory)
- **Client state**: React hooks in Dashboard (alerts array, serverTimeOffset, connectionStatus)
- **No client-side persistence**: All state synced from API on each fetch cycle

## Key Abstractions

**AlertManager (Durable Object):**
- Purpose: High-precision event scheduling with millisecond accuracy
- Location: `/workspace/gitprojects/adventure-alerts/packages/api/src/alert-manager.ts`
- Pattern: Class-based Durable Object with storage/alarm lifecycle
- Methods: `scheduleAlert()`, `cancelAlert()`, `getStatus()`, `alarm()`, `markAlertTriggered()`
- Uses Cloudflare storage.setAlarm() for persistent scheduling

**Tier-Based Validation:**
- Purpose: Enforce feature access based on user subscription tier
- Location: Types defined in `/workspace/gitprojects/adventure-alerts/packages/types/src/index.ts` (TIER_LIMITS)
- Pattern: Constants-based lookup + validation functions
- Enforced at: API POST/PATCH routes for trips and activities

**Server Time Sync:**
- Purpose: Guarantee millisecond-accurate countdowns across clients with variable latency
- Location: Dashboard page.tsx `syncServerTime()` function + all countdown components
- Pattern: Client measures round-trip latency, calculates offset, applies to all time comparisons
- Confidence levels: Excellent (<50ms), Good (<200ms), Fair (<1000ms), Poor (>1000ms)

**Dashboard State Machine:**
- Purpose: Dynamically style UI based on time-to-target thresholds
- Location: `getDashboardState()` in `/workspace/gitprojects/adventure-alerts/packages/types/src/index.ts`
- States: 'normal' (>2h), 'approaching' (30min-2h), 'urgent' (<30min), 'past' (<=0)
- Used by: upcoming-bookings component for accent color selection

## Entry Points

**API Entry Point:**
- Location: `/workspace/gitprojects/adventure-alerts/packages/api/src/index.ts`
- Triggers: Cloudflare Workers HTTP request routing via wrangler
- Responsibilities: CORS handling, route dispatch, request validation, response formatting

**Dashboard Entry Point:**
- Location: `/workspace/gitprojects/adventure-alerts/apps/dashboard/src/app/page.tsx`
- Triggers: Browser navigation to `/`
- Responsibilities: Server time sync, alert polling, rendering Mission Control layout with clock and cards

**Durable Object Entry Point:**
- Location: `AlertManager.fetch()` in `/workspace/gitprojects/adventure-alerts/packages/api/src/alert-manager.ts`
- Triggers: HTTP stub calls from API routes (POST /schedule, DELETE /cancel/:id, GET /status)
- Responsibilities: Parse request method/path, dispatch to scheduleAlert/cancelAlert/getStatus

## Error Handling

**Strategy:** Explicit error responses with `{ success: false, error: "message" }` format

**Patterns:**

**API Validation Errors (400):**
```typescript
// Missing required fields
return c.json({
  success: false,
  error: 'Missing required fields: eventName, targetTimeUtc'
}, 400);

// Trip duration validation
const durationError = validateTripDuration(startDate, endDate, userTier);
if (durationError) {
  return c.json({ success: false, error: durationError }, 403);
}
```

**Authorization/Tier Errors (403):**
```typescript
// Trip limit enforcement
if (activeTrips && activeTrips.count >= maxActiveTrips) {
  return c.json({
    success: false,
    error: `Free tier is limited to ${maxActiveTrips} active trip${maxActiveTrips === 1 ? '' : 's'}...`
  }, 403);
}
```

**Not Found Errors (404):**
```typescript
// Trip not found during update
if (!current) {
  return c.json({ success: false, error: 'Trip not found' }, 404);
}
```

**Server Errors (500):**
```typescript
// Catch-all for unexpected errors
catch (err) {
  console.error('Error creating trip:', err);
  return c.json({ success: false, error: String(err) }, 500);
}
```

**Client Connectivity Errors:**
- Dashboard silently catches fetch failures (no network error display yet)
- Sets `connectionStatus` to 'disconnected'
- Retries on 5s/30s intervals via useInterval hooks

## Cross-Cutting Concerns

**Logging:**
- API: `console.error()` and `console.log()` in Cloudflare Workers context
- AlertManager: `console.log('[AlertManager]...')` for alarm lifecycle events
- Dashboard: No explicit logging (relies on browser console)

**Validation:**
- Request bodies: Checked in each route handler (missing fields, date ordering)
- Tier limits: Centralized in `/packages/types` (`TIER_LIMITS`, `validateTripDuration()`)
- Time comparisons: Always use `Date.now() + serverTimeOffset` on client, server-generated timestamps on API

**Authentication:**
- Currently hardcoded as 'demo-user' (TODO comments in API routes)
- Tier lookup via query on users table per request
- No JWT/session validation yet

**Time Handling:**
- All database timestamps stored as Unix milliseconds (integer mode in Drizzle)
- No timezone conversion on server (stored UTC, timezone applied only on client display)
- Client sync mechanism corrects clock drift via server round-trip measurement

---
name: aa-fullstack
description: |
  Adventure Alerts full-stack development skill for Next.js, Cloudflare Workers, Hono, Drizzle ORM,
  Mantine UI, and edge-first architecture. Use when: building web applications, developing APIs,
  creating frontends, setting up databases, deploying web apps, or when user mentions React, Next.js,
  Mantine, Hono, Drizzle, Cloudflare Workers, D1, Durable Objects, Capacitor, Meilisearch,
  or full-stack development.
license: MIT
metadata:
  author: Adventure Alerts
  version: "1.0.0"
  forked_from: fullstack-developer v1.0.0 by awesome-llm-apps (MIT)
---

# AA Full-Stack Developer

Expert full-stack web development skill customized for the Adventure Alerts stack: Next.js + Mantine UI frontend, Cloudflare Workers + Hono API, Drizzle ORM + D1 database, and npm workspaces monorepo.

> **Fork notice:** Derived from [fullstack-developer](https://github.com/anthropics/awesome-claude-skills) by awesome-llm-apps (MIT). Substantially modified to target the Adventure Alerts technology stack and conventions.

## When to Apply

Use this skill when:
- Building complete web applications (monorepo or single-app)
- Developing edge APIs with Hono on Cloudflare Workers
- Creating React/Next.js frontends with Mantine UI
- Setting up databases with Drizzle ORM and Cloudflare D1
- Implementing Durable Objects for real-time or precision timing
- Deploying to Cloudflare (Workers, Pages, D1)
- Integrating search with Meilisearch
- Building hybrid mobile apps with Capacitor JS
- Implementing authentication and authorization
- Integrating third-party services

## Technology Stack

### Frontend
- **Next.js** (App Router) — SSR, SSG, server components, `use client` boundaries
- **React** — Modern component patterns, hooks, context
- **Mantine UI** — Primary component library (DataGrid, Modal, Alert, AppShell, CommandBar)
- **Mantine Hooks** — `useDisclosure`, `useForm`, `useInterval`, `useDebouncedValue`
- **Tailwind CSS** — Utility-first styling alongside Mantine components
- **TypeScript** — Strict type-safe frontend code

### Backend
- **Cloudflare Workers** — Edge-first serverless runtime (not Node.js)
- **Hono** — Lightweight web framework for Workers (routing, middleware, context)
- **Durable Objects** — Stateful coordination, real-time, precision scheduling (Alarms API)
- **TypeScript** — Type-safe backend code
- **Zod** — Schema validation for request bodies

### Database
- **Cloudflare D1** — Serverless SQLite at the edge
- **Drizzle ORM** — Type-safe schema definition, query builder, migrations
- **Unix milliseconds** — All timestamps stored as integers (`{ mode: 'timestamp_ms' }`)

### Search (Planned)
- **Meilisearch** — Typo-tolerant, sub-50ms full-text search
- **Meilisearch JS SDK** — Client for indexing and querying

### Mobile (Planned)
- **Capacitor JS** — Native iOS/Android wrapper for web apps
- **Native push notifications**, biometric auth, offline caching

### DevOps
- **Cloudflare Workers + Wrangler** — API deployment (~5 seconds)
- **Cloudflare Pages** — Frontend deployment with Git integration
- **npm workspaces** — Monorepo package management
- **GitHub Actions** — CI/CD pipelines

## Architecture Patterns

### Monorepo Structure (npm workspaces)
```
project-root/
├── apps/
│   └── dashboard/           # Next.js frontend (App Router)
│       ├── src/
│       │   ├── app/         # App Router pages and layouts
│       │   ├── components/  # React + Mantine components
│       │   └── lib/         # Theme, utilities, API client
│       └── package.json
├── packages/
│   ├── api/                 # Cloudflare Worker (Hono)
│   │   ├── src/
│   │   │   ├── index.ts     # Hono app entry, route registration
│   │   │   ├── routes/      # Route modules (trips.ts, alerts.ts)
│   │   │   └── durable/     # Durable Object classes
│   │   └── wrangler.jsonc   # Worker config, D1 bindings, DO bindings
│   ├── db/                  # Drizzle ORM schemas
│   │   ├── src/schema.ts    # Table definitions
│   │   └── drizzle.config.ts
│   └── types/               # Shared TypeScript interfaces
│       └── src/index.ts     # Types, constants, validators
├── package.json             # Workspaces root
└── tsconfig.json
```

**Cross-package rules:**
- `types` is the leaf — imports nothing from other packages
- `db` exports schemas consumed by `api`
- `dashboard` accesses `api` via HTTP only — never import from `packages/` into `apps/`
- Never import from `apps/` into `packages/`

### Single-App Structure (simpler projects)
```
src/
├── app/              # Next.js App Router pages
├── components/       # React + Mantine components
│   ├── ui/          # Base components
│   └── features/    # Feature-specific components
├── lib/             # Utilities, API client, theme
├── hooks/           # Custom React hooks
├── types/           # TypeScript types
└── styles/          # Global styles
```

## Best Practices

### Frontend
1. **Component Design**
   - Use Mantine components as the foundation — avoid reinventing DataGrid, Modal, Alert, etc.
   - Keep components small and focused
   - Use composition over prop drilling
   - Handle loading and error states with Mantine Skeleton/Alert

2. **Performance**
   - Code splitting with `dynamic()` imports
   - Use `useInterval()` for polling (every 5 seconds for lists)
   - Use `useCallback()` for fetch functions to avoid stale closures
   - Optimize bundle size — only import needed Mantine components

3. **State Management**
   - Server state with `fetch` + `useEffect` + `useInterval` (or React Query for complex cases)
   - Form state with Mantine `useForm`
   - UI state with `useDisclosure`, `useState`
   - Avoid prop drilling — use context for deeply shared state

### Backend (Hono + Workers)
1. **API Design**
   - Consistent response shapes: `{ success: true, data: T }` or `{ success: false, error: "message" }`
   - Never return bare arrays — wrap in named properties
   - Use Hono context (`c.json()`, `c.req.json()`, `c.env`)
   - Group routes in separate files, register on main app

2. **Security**
   - Validate all inputs with Zod
   - Enforce tier limits server-side — never trust the client
   - Use parameterized queries via Drizzle (never raw string interpolation)
   - Rate limiting by tier

3. **Database (Drizzle + D1)**
   - Prefer Drizzle ORM over raw SQL
   - Use joins/subqueries to batch related data — D1 cold starts make N+1 costly
   - All timestamps as Unix milliseconds: `integer('col', { mode: 'timestamp_ms' })`
   - Migration protocol: edit schema → `drizzle-kit generate` → `wrangler d1 migrations apply`

4. **Durable Objects**
   - Use for precision scheduling (Alarms API), real-time state, WebSocket coordination
   - Schedule alarms with a precision buffer (e.g., 100ms early)
   - Access via `c.env.BINDING_NAME.idFromName()` → `.get()` → `.fetch()`

## Code Examples

### Hono API Route with Drizzle + D1
```typescript
// packages/api/src/routes/trips.ts
import { Hono } from "hono";
import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { trips, activities } from "@adventure-alerts/db";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const createTripSchema = z.object({
  name: z.string().min(1).max(100),
  startDate: z.number(), // Unix ms
  endDate: z.number(),
});

app.get("/", async (c) => {
  const db = createDb(c.env.DB);
  const userId = c.get("userId");

  const result = await db
    .select({
      trip: trips,
      activityCount: sql<number>`count(${activities.id})`,
    })
    .from(trips)
    .leftJoin(activities, eq(trips.id, activities.tripId))
    .where(eq(trips.userId, userId))
    .groupBy(trips.id);

  return c.json({ success: true, trips: result });
});

app.post("/", async (c) => {
  const body = createTripSchema.parse(await c.req.json());
  const db = createDb(c.env.DB);
  const userId = c.get("userId");

  // Enforce tier limits
  const activeTrips = await db
    .select({ count: sql<number>`count(*)` })
    .from(trips)
    .where(and(eq(trips.userId, userId), eq(trips.status, "active")))
    .get();

  if (activeTrips.count >= TIER_LIMITS[userTier].maxActiveTrips) {
    return c.json({ success: false, error: "Trip limit reached" }, 403);
  }

  const trip = await db.insert(trips).values({
    id: crypto.randomUUID(),
    userId,
    name: body.name,
    startDate: body.startDate,
    endDate: body.endDate,
  }).returning().get();

  return c.json({ success: true, data: trip }, 201);
});

export default app;
```

### Hono App Entry with Bindings
```typescript
// packages/api/src/index.ts
import { Hono } from "hono";
import { cors } from "hono/cors";
import trips from "./routes/trips";
import time from "./routes/time";

export type Bindings = {
  DB: D1Database;
  PRECISION_TIMER: DurableObjectNamespace;
};

const app = new Hono<{ Bindings: Bindings }>();
app.use("*", cors());
app.route("/trips", trips);
app.route("/time", time);

export default app;
export { AlertManager } from "./durable/alert-manager";
```

### Drizzle Schema Definition
```typescript
// packages/db/src/schema.ts
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";

export const trips = sqliteTable("trips", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull(),
  name: text("name").notNull(),
  startDate: integer("start_date", { mode: "timestamp_ms" }).notNull(),
  endDate: integer("end_date", { mode: "timestamp_ms" }).notNull(),
  status: text("status", { enum: ["planning", "active", "completed"] })
    .default("planning")
    .notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const activities = sqliteTable("activities", {
  id: text("id").primaryKey(),
  tripId: text("trip_id").references(() => trips.id).notNull(),
  name: text("name").notNull(),
  targetTimeUtc: integer("target_time_utc", { mode: "timestamp_ms" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});
```

### React Component with Mantine
```typescript
// apps/dashboard/src/components/TripCard.tsx
"use client";

import { Card, Text, Badge, Group, Stack, Alert } from "@mantine/core";
import { IconAlertCircle } from "@tabler/icons-react";

interface Trip {
  id: string;
  name: string;
  startDate: number;
  endDate: number;
  status: string;
  activityCount: number;
}

export function TripCard({ trip }: { trip: Trip }) {
  return (
    <Card shadow="sm" padding="lg" radius="md" withBorder>
      <Group justify="space-between" mb="xs">
        <Text fw={500}>{trip.name}</Text>
        <Badge color={trip.status === "active" ? "blue" : "gray"}>
          {trip.status}
        </Badge>
      </Group>

      <Stack gap="xs">
        <Text size="sm" c="dimmed">
          {new Date(trip.startDate).toLocaleDateString()} —{" "}
          {new Date(trip.endDate).toLocaleDateString()}
        </Text>
        <Text size="sm">
          {trip.activityCount} {trip.activityCount === 1 ? "alert" : "alerts"}
        </Text>
      </Stack>
    </Card>
  );
}
```

### Durable Object with Alarms API
```typescript
// packages/api/src/durable/alert-manager.ts
export class AlertManager implements DurableObject {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/schedule" && request.method === "POST") {
      const alert = await request.json();
      // Store alert and schedule alarm 100ms early for precision buffer
      await this.state.storage.put(`alert:${alert.id}`, alert);
      const alarmTime = alert.targetTimeUtc - 100;
      await this.state.storage.setAlarm(alarmTime);
      return new Response(JSON.stringify({ success: true }));
    }

    return new Response("Not found", { status: 404 });
  }

  async alarm(): Promise<void> {
    // Alarm fired — process pending alerts
    const alerts = await this.state.storage.list({ prefix: "alert:" });
    const now = Date.now();

    for (const [key, alert] of alerts) {
      if (alert.targetTimeUtc <= now + 200) {
        // Fire alert, update D1, clean up
        await this.state.storage.delete(key);
      }
    }

    // Chain to next alarm if more alerts pending
    await this.scheduleNextAlarm();
  }
}
```

## Wrangler Configuration
```jsonc
// packages/api/wrangler.jsonc
{
  "name": "my-api",
  "main": "src/index.ts",
  "compatibility_date": "2024-01-01",
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "my-db",
      "database_id": "<your-database-id>"
    }
  ],
  "durable_objects": {
    "bindings": [
      {
        "name": "PRECISION_TIMER",
        "class_name": "AlertManager"
      }
    ]
  },
  "migrations": [
    {
      "tag": "v1",
      "new_classes": ["AlertManager"]
    }
  ]
}
```

## Migration Workflow
```bash
# 1. Edit schema in packages/db/src/schema.ts

# 2. Generate migration SQL
cd packages/db && npx drizzle-kit generate

# 3. Apply to D1 (remote)
cd packages/api && npx wrangler d1 migrations apply my-db --remote

# 4. Deploy updated Worker
cd packages/api && npx wrangler deploy
```

## Output Format

When building features, provide:
1. **File location** — Exact path in the monorepo (e.g., `packages/api/src/routes/trips.ts`)
2. **Complete code** — Fully functional, typed TypeScript
3. **Dependencies** — Required npm packages
4. **Migration steps** — If schema changes are involved
5. **Wrangler config** — If new bindings are needed

## Cloudflare Integration

For detailed Cloudflare product references (Workers, D1, Durable Objects, Pages, KV, R2, etc.), see the `aa-cloudflare` skill. This skill covers application code patterns; `aa-cloudflare` covers infrastructure and deployment specifics.

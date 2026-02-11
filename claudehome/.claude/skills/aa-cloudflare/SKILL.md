---
name: aa-cloudflare
description: Deploy and build on the Cloudflare platform with integration patterns for Hono, Drizzle ORM, D1, Durable Objects, and monorepo deployments. Use when the user asks to deploy, host, publish, or set up a project on Cloudflare.
metadata:
  author: Adventure Alerts
  version: "1.0.0"
  forked_from: cloudflare-deploy by OpenAI (Apache-2.0)
  license: Apache-2.0
---

# AA Cloudflare Deploy

Consolidated skill for building on the Cloudflare platform, extended with integration patterns for Hono, Drizzle ORM + D1, Durable Object alarm scheduling, and monorepo deployments.

> **Fork notice:** Derived from [cloudflare-deploy](https://github.com/anthropics/awesome-claude-skills) by OpenAI (Apache-2.0). Original decision trees and product index retained. Added "Common Integration Patterns" section. See NOTICE file for full attribution.

## Prerequisites

- When sandboxing blocks the deployment network calls, rerun with `sandbox_permissions=require_escalated`.
- The deployment might take a few minutes. Use appropriate timeout values.

## Authentication (Required Before Deploy)

Verify auth before `wrangler deploy`, `wrangler pages deploy`, or `npm run deploy`:

```bash
npx wrangler whoami    # Shows account if authenticated
```

Not authenticated? → `references/wrangler/auth.md`
- Interactive/local: `wrangler login` (one-time OAuth)
- CI/CD: Set `CLOUDFLARE_API_TOKEN` env var

## Quick Decision Trees

### "I need to run code"

```
Need to run code?
├─ Serverless functions at the edge → workers/
├─ Full-stack web app with Git deploys → pages/
├─ Stateful coordination/real-time → durable-objects/
├─ Long-running multi-step jobs → workflows/
├─ Run containers → containers/
├─ Multi-tenant (customers deploy code) → workers-for-platforms/
├─ Scheduled tasks (cron) → cron-triggers/
├─ Lightweight edge logic (modify HTTP) → snippets/
├─ Process Worker execution events (logs/observability) → tail-workers/
└─ Optimize latency to backend infrastructure → smart-placement/
```

### "I need to store data"

```
Need storage?
├─ Key-value (config, sessions, cache) → kv/
├─ Relational SQL → d1/ (SQLite) or hyperdrive/ (existing Postgres/MySQL)
├─ Object/file storage (S3-compatible) → r2/
├─ Message queue (async processing) → queues/
├─ Vector embeddings (AI/semantic search) → vectorize/
├─ Strongly-consistent per-entity state → durable-objects/ (DO storage)
├─ Secrets management → secrets-store/
├─ Streaming ETL to R2 → pipelines/
└─ Persistent cache (long-term retention) → cache-reserve/
```

### "I need AI/ML"

```
Need AI?
├─ Run inference (LLMs, embeddings, images) → workers-ai/
├─ Vector database for RAG/search → vectorize/
├─ Build stateful AI agents → agents-sdk/
├─ Gateway for any AI provider (caching, routing) → ai-gateway/
└─ AI-powered search widget → ai-search/
```

### "I need networking/connectivity"

```
Need networking?
├─ Expose local service to internet → tunnel/
├─ TCP/UDP proxy (non-HTTP) → spectrum/
├─ WebRTC TURN server → turn/
├─ Private network connectivity → network-interconnect/
├─ Optimize routing → argo-smart-routing/
├─ Optimize latency to backend (not user) → smart-placement/
└─ Real-time video/audio → realtimekit/ or realtime-sfu/
```

### "I need security"

```
Need security?
├─ Web Application Firewall → waf/
├─ DDoS protection → ddos/
├─ Bot detection/management → bot-management/
├─ API protection → api-shield/
├─ CAPTCHA alternative → turnstile/
└─ Credential leak detection → waf/ (managed ruleset)
```

### "I need media/content"

```
Need media?
├─ Image optimization/transformation → images/
├─ Video streaming/encoding → stream/
├─ Browser automation/screenshots → browser-rendering/
└─ Third-party script management → zaraz/
```

### "I need infrastructure-as-code"

```
Need IaC? → pulumi/ (Pulumi), terraform/ (Terraform), or api/ (REST API)
```

## Product Index

### Compute & Runtime
| Product | Reference |
|---------|-----------|
| Workers | `references/workers/` |
| Pages | `references/pages/` |
| Pages Functions | `references/pages-functions/` |
| Durable Objects | `references/durable-objects/` |
| Workflows | `references/workflows/` |
| Containers | `references/containers/` |
| Workers for Platforms | `references/workers-for-platforms/` |
| Cron Triggers | `references/cron-triggers/` |
| Tail Workers | `references/tail-workers/` |
| Snippets | `references/snippets/` |
| Smart Placement | `references/smart-placement/` |

### Storage & Data
| Product | Reference |
|---------|-----------|
| KV | `references/kv/` |
| D1 | `references/d1/` |
| R2 | `references/r2/` |
| Queues | `references/queues/` |
| Hyperdrive | `references/hyperdrive/` |
| DO Storage | `references/do-storage/` |
| Secrets Store | `references/secrets-store/` |
| Pipelines | `references/pipelines/` |
| R2 Data Catalog | `references/r2-data-catalog/` |
| R2 SQL | `references/r2-sql/` |

### AI & Machine Learning
| Product | Reference |
|---------|-----------|
| Workers AI | `references/workers-ai/` |
| Vectorize | `references/vectorize/` |
| Agents SDK | `references/agents-sdk/` |
| AI Gateway | `references/ai-gateway/` |
| AI Search | `references/ai-search/` |

### Networking & Connectivity
| Product | Reference |
|---------|-----------|
| Tunnel | `references/tunnel/` |
| Spectrum | `references/spectrum/` |
| TURN | `references/turn/` |
| Network Interconnect | `references/network-interconnect/` |
| Argo Smart Routing | `references/argo-smart-routing/` |
| Workers VPC | `references/workers-vpc/` |

### Security
| Product | Reference |
|---------|-----------|
| WAF | `references/waf/` |
| DDoS Protection | `references/ddos/` |
| Bot Management | `references/bot-management/` |
| API Shield | `references/api-shield/` |
| Turnstile | `references/turnstile/` |

### Media & Content
| Product | Reference |
|---------|-----------|
| Images | `references/images/` |
| Stream | `references/stream/` |
| Browser Rendering | `references/browser-rendering/` |
| Zaraz | `references/zaraz/` |

### Real-Time Communication
| Product | Reference |
|---------|-----------|
| RealtimeKit | `references/realtimekit/` |
| Realtime SFU | `references/realtime-sfu/` |

### Developer Tools
| Product | Reference |
|---------|-----------|
| Wrangler | `references/wrangler/` |
| Miniflare | `references/miniflare/` |
| C3 | `references/c3/` |
| Observability | `references/observability/` |
| Analytics Engine | `references/analytics-engine/` |
| Web Analytics | `references/web-analytics/` |
| Sandbox | `references/sandbox/` |
| Workerd | `references/workerd/` |
| Workers Playground | `references/workers-playground/` |

### Infrastructure as Code
| Product | Reference |
|---------|-----------|
| Pulumi | `references/pulumi/` |
| Terraform | `references/terraform/` |
| API | `references/api/` |

### Other Services
| Product | Reference |
|---------|-----------|
| Email Routing | `references/email-routing/` |
| Email Workers | `references/email-workers/` |
| Static Assets | `references/static-assets/` |
| Bindings | `references/bindings/` |
| Cache Reserve | `references/cache-reserve/` |

## Common Integration Patterns

These patterns cover frequently used combinations of Cloudflare products with popular frameworks. They supplement the per-product references with practical "glue" guidance.

### Hono + Workers

[Hono](https://hono.dev) is the most common framework for building APIs on Cloudflare Workers. It provides routing, middleware, and typed context with minimal overhead.

```typescript
// src/index.ts — Hono app entry
import { Hono } from "hono";
import { cors } from "hono/cors";

// Type your env bindings for full autocomplete
export type Bindings = {
  DB: D1Database;
  MY_KV: KVNamespace;
  MY_DO: DurableObjectNamespace;
};

const app = new Hono<{ Bindings: Bindings }>();
app.use("*", cors());

// Access bindings via c.env
app.get("/items", async (c) => {
  const db = createDb(c.env.DB);
  const items = await db.select().from(table).all();
  return c.json({ success: true, data: items });
});

export default app;
```

**Key patterns:**
- Type `Bindings` to get autocomplete on `c.env.DB`, `c.env.MY_KV`, etc.
- Group routes in separate files: `const routes = new Hono<{ Bindings: Bindings }>()` then `app.route("/path", routes)`
- Use `c.req.json()` for request bodies, `c.json()` for responses
- Hono middleware works like Express middleware but runs at the edge

### Drizzle ORM + D1

Drizzle is the recommended ORM for D1. It provides type-safe schemas, a query builder, and migration tooling that works with Wrangler.

**Schema definition:**
```typescript
// packages/db/src/schema.ts
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  tier: text("tier", { enum: ["scout", "voyager", "advisor"] }).default("scout").notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});
```

**Connecting Drizzle to D1 in a Worker:**
```typescript
import { drizzle } from "drizzle-orm/d1";
import * as schema from "@my-project/db";

export function createDb(d1: D1Database) {
  return drizzle(d1, { schema });
}

// In a Hono route:
app.get("/users", async (c) => {
  const db = createDb(c.env.DB);
  const result = await db.select().from(schema.users).all();
  return c.json({ success: true, data: result });
});
```

**Migration workflow:**
```bash
# 1. Edit schema in packages/db/src/schema.ts
# 2. Generate migration SQL
cd packages/db && npx drizzle-kit generate

# 3. Apply locally (for development)
cd packages/api && npx wrangler d1 migrations apply my-db --local

# 4. Apply to production
cd packages/api && npx wrangler d1 migrations apply my-db --remote
```

**Query patterns to prefer:**
```typescript
// Good: Single query with join (minimizes D1 round-trips)
const tripsWithCounts = await db
  .select({
    trip: trips,
    count: sql<number>`count(${activities.id})`,
  })
  .from(trips)
  .leftJoin(activities, eq(trips.id, activities.tripId))
  .groupBy(trips.id);

// Bad: N+1 queries (each incurs cold-start latency)
const allTrips = await db.select().from(trips).all();
for (const trip of allTrips) {
  const activities = await db.select().from(activities).where(eq(activities.tripId, trip.id));
}
```

**Gotchas:**
- D1 is SQLite — no `RETURNING *` in older compatibility dates; use `.returning().get()` via Drizzle
- Timestamps should be stored as Unix milliseconds (integer), not ISO strings
- Always generate migrations immediately after schema changes — never let schema and migrations drift

### Durable Objects — Alarm Scheduling

Durable Objects with the Alarms API provide precision server-side scheduling without cron granularity limits.

```typescript
export class PrecisionTimer implements DurableObject {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/schedule") {
      const { id, targetTime } = await request.json();
      await this.state.storage.put(`job:${id}`, { id, targetTime });
      // Schedule 100ms early for precision buffer
      await this.state.storage.setAlarm(targetTime - 100);
      return new Response(JSON.stringify({ success: true }));
    }

    if (url.pathname === "/cancel") {
      const { id } = await request.json();
      await this.state.storage.delete(`job:${id}`);
      return new Response(JSON.stringify({ success: true }));
    }

    return new Response("Not found", { status: 404 });
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    const jobs = await this.state.storage.list({ prefix: "job:" });

    for (const [key, job] of jobs) {
      if (job.targetTime <= now + 200) {
        // Execute the job (update D1, send notification, etc.)
        await this.state.storage.delete(key);
      }
    }

    // Chain to next alarm if more jobs exist
    const remaining = await this.state.storage.list({ prefix: "job:" });
    if (remaining.size > 0) {
      const nextTime = Math.min(...[...remaining.values()].map(j => j.targetTime));
      await this.state.storage.setAlarm(nextTime - 100);
    }
  }
}
```

**Accessing from Hono:**
```typescript
app.post("/schedule", async (c) => {
  const id = c.env.PRECISION_TIMER.idFromName("global-timer");
  const stub = c.env.PRECISION_TIMER.get(id);
  const resp = await stub.fetch(new Request("http://internal/schedule", {
    method: "POST",
    body: JSON.stringify(await c.req.json()),
  }));
  return c.json(await resp.json());
});
```

**Wrangler config for DOs:**
```jsonc
{
  "durable_objects": {
    "bindings": [{ "name": "PRECISION_TIMER", "class_name": "PrecisionTimer" }]
  },
  "migrations": [{ "tag": "v1", "new_classes": ["PrecisionTimer"] }]
}
```

### Monorepo Deployment

When deploying a Worker from within a monorepo (e.g., `packages/api/`), Wrangler needs correct path context.

```bash
# Deploy from the package directory (wrangler.jsonc lives here)
cd packages/api && npx wrangler deploy

# Or from root with --config flag
npx wrangler deploy --config packages/api/wrangler.jsonc
```

**Key considerations:**
- `wrangler.jsonc` must be in the package directory or referenced via `--config`
- D1 migration paths in `wrangler.jsonc` are relative to that file's location
- Cross-package imports (e.g., `@my-project/db`) must be resolvable — ensure the workspace `package.json` defines them and `tsconfig.json` paths are set
- Use npm workspaces `"workspaces": ["apps/*", "packages/*"]` in root `package.json`

## Troubleshooting

### Escalated Network Access

If deployment fails due to network issues (timeouts, DNS errors, connection resets), rerun the deploy with escalated permissions (use `sandbox_permissions=require_escalated`). The deploy requires escalated network access when sandbox networking blocks outbound requests.

Example guidance to the user:

```
The deploy needs escalated network access to deploy to Cloudflare. I can rerun the command with escalated permissions—want me to proceed?
```

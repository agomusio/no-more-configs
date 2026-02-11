# External Integrations

**Analysis Date:** 2026-02-10

## APIs & External Services

**Langfuse (LLM Observability):**
- Service: Langfuse 3 - Production observability and evaluation platform
  - SDK/Client: `langfuse-python` (implied from docker-compose, not in npm packages)
  - Connection: Docker Compose service at `http://host.docker.internal:3052` (devcontainer access)
  - Web UI: `127.0.0.1:3052` (exposed to localhost)
  - Worker service: `127.0.0.1:3030` (background job processing)
  - Status: Self-hosted via Docker Compose in `/workspace/claudehome/langfuse-local/`

**Cloudflare Services:**
- Cloudflare Workers API - Serverless compute for `packages/api`
  - Type: Function-as-a-Service platform
  - SDK: Wrangler CLI 4.59.2 and `@cloudflare/workers-types` 4.20241230.0
  - Bindings: D1 database, Durable Objects (AlertManager)
  - Deployment target: `wrangler deploy` command
- Cloudflare Pages - Static/hybrid hosting for dashboard
  - Type: Edge hosting platform
  - Deployment: Next.js built artifacts

**Adventure Alerts API:**
- Endpoint: Hono-based REST API on Cloudflare Workers
  - Base path: `/`
  - Health check: `GET /` returns "Adventure Alerts API"
  - Server time: `GET /time` returns UTC timestamp and timezone
  - Legacy alerts: `GET /alerts`, `POST /alerts` (SQLite-backed)
  - Trips: Trip management endpoints via Drizzle ORM queries
  - CORS: Enabled for `http://localhost:3000`, `http://localhost:3001`, `https://adventure-alerts-dashboard.pages.dev`

## Data Storage

**Databases:**

**Cloudflare D1 (Primary Application DB):**
- Type: SQLite distributed via Cloudflare network
- Client: Drizzle ORM 0.38.3 with `d1-http` driver
- Schema location: `packages/db/src/schema.ts`
- Migration tool: Drizzle Kit 0.31.8
- Tables:
  - `users` - User accounts with tier levels (scout, voyager, advisor)
  - `booking_rules` - Reusable timing configurations for alerts
  - `trips` - User adventure trips with durations
  - `events` - Bookable events tied to trips
  - `alerts` - Alert records with status tracking
  - Additional tables defined in schema (line 50+ in schema.ts)
- Environment binding: `DB: D1Database` in Workers Env
- Connection string: Built-in through Workers bindings (no explicit connection string needed)

**Langfuse ClickHouse:**
- Type: OLAP column-oriented database for analytics
- Version: ClickHouse latest
- Container: `docker.io/clickhouse/clickhouse-server`
- Port: `127.0.0.1:8124` (HTTP), `127.0.0.1:9000` (native protocol)
- Default database: `default`
- Credentials: Environment variables `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`
- Purpose: Analytics queries, aggregations, and LLM trace storage in Langfuse
- Volumes: `langfuse_clickhouse_data`, `langfuse_clickhouse_logs`

**Langfuse PostgreSQL:**
- Type: Primary relational database for Langfuse metadata
- Version: PostgreSQL 17
- Container: `docker.io/postgres:17`
- Port: `127.0.0.1:5433:5432` (exposed to localhost)
- User: `postgres`
- Database: `postgres`
- Credentials: Environment variable `POSTGRES_PASSWORD`
- Purpose: Langfuse user accounts, projects, traces metadata
- Volumes: `langfuse_postgres_data`

**File Storage:**

**MinIO (S3-Compatible Object Storage):**
- Type: MinIO for S3-compatible object storage
- Version: Chainguard MinIO image (`cgr.dev/chainguard/minio`)
- Ports:
  - API: `127.0.0.1:9090:9000` (exposed to localhost)
  - Console: `127.0.0.1:9091:9001` (management UI)
- Credentials: `MINIO_ROOT_USER=minio`, `MINIO_ROOT_PASSWORD={env}`
- Buckets: `langfuse` (auto-created)
- Purpose: Media uploads and event exports for Langfuse
- Langfuse S3 config:
  - Event upload: `langfuse_s3_event_upload_*` env vars (endpoint: `http://minio:9000`)
  - Media upload: `langfuse_s3_media_upload_*` env vars (endpoint: `http://localhost:9090`)
  - Region: `auto` (MinIO region)
  - Force path style: `true`
- Volumes: `langfuse_minio_data`

**Caching:**

**Redis 7:**
- Type: In-memory data store for caching and job queues
- Version: `docker.io/redis:7`
- Port: `127.0.0.1:6379:6379`
- Auth: `REDIS_AUTH` environment variable (requirepass)
- TLS: Disabled (`REDIS_TLS_ENABLED=false`)
- Memory policy: `noeviction` (reject writes when memory full)
- Purpose: Session caching, job queue, rate limiting in Langfuse
- Volumes: None (ephemeral in-memory storage)

## Authentication & Identity

**Auth Provider:**
- Custom implementation via NextAuth (implied by `NEXTAUTH_SECRET`, `NEXTAUTH_URL`)
- Langfuse admin user: Auto-created on startup
  - Email: `${LANGFUSE_INIT_USER_EMAIL}`
  - Password: `${LANGFUSE_INIT_USER_PASSWORD}`
  - Name: `${LANGFUSE_INIT_USER_NAME}`
- Langfuse session secret: `NEXTAUTH_SECRET` (64 hex characters required)
- Langfuse project auth:
  - Public key: `LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-local-claude-code`
  - Secret key: `LANGFUSE_INIT_PROJECT_SECRET_KEY` (env var, required)

**Encryption at Rest:**
- Langfuse encryption key: `ENCRYPTION_KEY` (64 hex characters)
- Langfuse salt: `SALT` (32 hex characters)
- Used for sensitive data encryption in Langfuse PostgreSQL

## Monitoring & Observability

**Error Tracking:**
- Langfuse provides LLM observability and evaluation
  - Web UI: `http://127.0.0.1:3052`
  - Organization: Auto-created as `local-org`
  - Project: Auto-created as `claude-code`
  - Telemetry: Disabled via `TELEMETRY_ENABLED=false`
  - Experimental features: Enabled via `LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=true`

**Logs:**
- Langfuse web/worker logs: Available via `docker logs`
- Database logs: ClickHouse logs mounted at `langfuse_clickhouse_logs`
- Access logs: Standard Docker container logs for all services

## CI/CD & Deployment

**Hosting:**
- Cloudflare Workers - API (`packages/api`) deployment target
- Cloudflare Pages - Dashboard (`apps/dashboard`) deployment target
- Local Docker Compose - Development and self-hosted Langfuse stack

**CI Pipeline:**
- Not detected in configuration files (no GitHub Actions, GitLab CI, or similar found)

**Build Tools:**
- Wrangler 4.59.2 - Cloudflare Workers build and deploy CLI
- Next.js built-in build system - Dashboard compilation
- TypeScript compiler - Type checking without transpilation

## Environment Configuration

**Required env vars (Langfuse):**
- `POSTGRES_PASSWORD` - PostgreSQL admin password
- `CLICKHOUSE_PASSWORD` - ClickHouse user password
- `MINIO_ROOT_PASSWORD` - MinIO root user password
- `REDIS_AUTH` - Redis authentication token
- `ENCRYPTION_KEY` - 64 hex characters for data encryption at rest
- `NEXTAUTH_SECRET` - 64 hex characters for session token encryption
- `SALT` - 32 hex characters for password hashing
- `LANGFUSE_INIT_PROJECT_SECRET_KEY` - Project-level authentication key
- `LANGFUSE_INIT_USER_EMAIL` - Admin user email for auto-creation
- `LANGFUSE_INIT_USER_PASSWORD` - Admin user password
- `LANGFUSE_INIT_USER_NAME` - Admin user display name (optional, defaults to "Admin")
- `LANGFUSE_INIT_ORG_NAME` - Organization name (optional, defaults to "My Org")

**Secrets location:**
- `.env` file in `/workspace/claudehome/langfuse-local/` (not committed, template at `.env.example`)
- Generated via `./scripts/generate-env.sh` script (mentioned in .env.example but not found in artifacts)
- Devcontainer environment: Set via `containerEnv` in `devcontainer.json`

**Optional features:**
- Azure Blob Storage: `LANGFUSE_USE_AZURE_BLOB=false` (currently disabled)
- Batch exports: `LANGFUSE_S3_BATCH_EXPORT_ENABLED=false` (currently disabled)
- ClickHouse clustering: `CLICKHOUSE_CLUSTER_ENABLED=false` (single node)
- MCP gateway: Not yet configured (documented in RFC at `/workspace/docs/mcp-integration-spec.md`)

## Webhooks & Callbacks

**Incoming:**
- Adventure Alerts API endpoints:
  - `POST /alerts` - Create alert with event name and target time
  - `POST /trips` - Create trip with booking rules
  - `PATCH /users/:userId` - Update user tier/preferences
  - `DELETE /alerts/:alertId` - Cancel alert
  - Health endpoints: `GET /`, `GET /time`

**Outgoing:**
- None detected in current codebase
- Langfuse worker could implement webhook callbacks for alert triggers (AlertManager Durable Object)

## Data Models & Relationships

**Users:**
- `id` (text, PK)
- `email` (text, unique)
- `name` (text)
- `tier` (enum: scout, voyager, advisor)
- `preferences` (JSON)
- `createdAt`, `updatedAt` (timestamps)

**Trips:**
- Foreign key relationships to users
- Duration validation
- Tier-based limits via `TIER_LIMITS`

**Alerts:**
- `id`, `userId`, `tripId`, `eventId`
- `targetTimeUtc` - Target trigger time
- `status` (pending, triggered, cancelled)
- `createdAt`, `updatedAt`
- Managed by AlertManager Durable Object for precise scheduling

**Booking Rules:**
- Reusable timing configurations
- `offsetDays`, `offsetDirection` (before/after)
- `exactTimeHour`, `exactTimeMinute`, `exactTimeSecond`
- `timezone` (IANA format)
- `isCurated` flag for official vs user-created

## Development Network

**Local ports (devcontainer access via `host.docker.internal`):**
- `3052` - Langfuse web UI (Next.js app)
- `3030` - Langfuse worker service (background jobs)
- `5433` - PostgreSQL
- `6379` - Redis
- `8124` - ClickHouse HTTP
- `9000` - ClickHouse native protocol
- `9090` - MinIO API
- `9091` - MinIO console
- `3000`, `8787` - Dev app ports (forwarded in devcontainer)

**Docker Compose network:**
- All Langfuse services communicate via Docker internal network
- No external network exposure (all ports bound to `127.0.0.1`)
- Devcontainer reaches services via `host.docker.internal` hostname

---

*Integration audit: 2026-02-10*

# Coding Conventions

**Analysis Date:** 2026-02-16

## Naming Patterns

**Files:**
- React components: PascalCase (e.g., `alert-form.tsx` → exported as `AlertForm`)
- API routes: kebab-case routes in URL, PascalCase handler functions
- TypeScript files: camelCase for utility files (e.g., `alert-manager.ts`), PascalCase for class-based files
- Type/interface files: All exports in `packages/types/src/index.ts` as one monolithic file

**Functions:**
- camelCase for all regular functions (e.g., `validateTripDuration`, `getDashboardState`, `formatLocalTime`)
- Utility functions at module level: camelCase (e.g., `getConfidenceLevel`, `getTimezoneName`)
- React hook functions: camelCase prefixed with `use` (e.g., `useInterval`, `useForm`, `useDisclosure`)
- Private/internal functions: camelCase, no underscore prefix convention observed

**Variables:**
- camelCase for all variables and constants (e.g., `serverTimeOffset`, `latencyMs`, `userTimezone`)
- State hooks: `const [isLoading, setIsLoading] = useState(false)` pattern
- Type guard variables: camelCase (e.g., `durationError`, `activeTrips`, `userTier`)
- Constants: UPPER_SNAKE_CASE only for truly immutable exports (e.g., `TIER_LIMITS`, `DEFAULT_APPROACHING_THRESHOLD`)

**Types:**
- PascalCase for all interfaces and types (e.g., `CreateAlertRequest`, `DashboardState`, `UserTier`)
- Union types use PascalCase members (e.g., `UserTier = 'scout' | 'voyager' | 'advisor'`)
- Discriminated unions: camelCase for discriminator values (e.g., `status: 'planning' | 'active' | 'completed'`)
- Response types always end with `Response` suffix (e.g., `CreateAlertResponse`, `ListTripsResponse`)
- Request types always end with `Request` suffix (e.g., `CreateTripRequest`, `CreateActivityRequest`)

## Code Style

**Formatting:**
- Language: TypeScript with React (18+)
- No explicit formatter config detected — using sensible defaults (ESM, no semicolons in some files, semicolons in others — inconsistent)
- Indentation: 2 spaces (observed in all files)
- Line length: No hard limit enforced, typical wrapping around 80-100 characters in templates

**Linting:**
- No `.eslintrc` detected; project relies on TypeScript strict mode
- TypeScript strict mode enabled in all `tsconfig.json` files
- React Strict Mode enabled in `next.config.ts`: `reactStrictMode: true`

## Import Organization

**Order (observed pattern):**
1. React/Next.js imports from `'react'`, `'next/*'`
2. Third-party UI library imports (`'@mantine/core'`, `'@mantine/hooks'`, `'@tabler/icons-react'`)
3. Internal package imports (`'@adventure-alerts/types'`, `'@adventure-alerts/db'`)
4. Local relative imports (`'./alert-form'`, `'./sidebar'`)
5. Type imports separated: `import type { ... } from '...'`

**Path Aliases:**
- `@/*` → `src/*` in dashboard and apps
- Monorepo workspaces: `@adventure-alerts/types`, `@adventure-alerts/db`, `@adventure-alerts/api`
- No path aliases in packages (use relative imports or full workspace names)

**Example:**
```typescript
import { useState, useCallback } from 'react';
import { Button, Modal, Group } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import type { CreateAlertRequest } from '@adventure-alerts/types';
import { AlertForm } from './alert-form';
```

## Error Handling

**Patterns:**
- Try-catch blocks with specific error type checking: `if (err instanceof Error) { ... }`
- Frontend form errors: Mantine `Alert` component with `IconAlertCircle` and `color="red"`
- API error responses: `{ success: false, error: "Descriptive message" }` format
- Silent error fallback in non-critical operations (e.g., in `alert-form.tsx` line 44: `catch { // Silently fail }`)
- Database/validation errors: Return with HTTP status code + error message (400, 403, 404, 500)
- No custom error classes observed; strings used for error messages

**Example:**
```typescript
try {
  const response = await fetch(`${API_URL}/alerts`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  const data: CreateAlertResponse = await response.json();
  if (!data.success) {
    throw new Error(data.error || 'Failed to create alert');
  }
} catch (err) {
  setError(err instanceof Error ? err.message : 'An error occurred');
}
```

## Logging

**Framework:** `console.log()` and `console.error()`

**Patterns:**
- API errors logged with context prefix (e.g., `console.error('Error creating alert:', err)`)
- Durable Object events logged with scope prefix: `console.log('[AlertManager] ...')`
- No structured logging observed; plain console output
- Silent failures acceptable for non-critical operations (catch without logging)

**Example:**
```typescript
// From alert-manager.ts (line 66)
console.log(`[AlertManager] Marked alert ${alertId} as triggered in D1`);

// From index.ts (line 158)
console.error('Error creating trip:', err);
```

## Comments

**When to Comment:**
- Inline: Explain the "why" for non-obvious logic (e.g., `// For high precision, we wake up slightly before (100ms)`)
- Section headers: Capital-letter divider comments to organize file sections
  ```typescript
  // ============================================================================
  // TRIPS API (using Drizzle ORM)
  // ============================================================================
  ```
- TODO markers: Used for future work (e.g., `// TODO: Get from auth`, `// TODO: Count activities`)

**JSDoc/TSDoc:**
- Minimal observed; only on exported utility functions and interfaces
- Parameter/return descriptions rare; focus on type safety via TypeScript
- Example from `packages/types/src/index.ts`:
  ```typescript
  /**
   * Validates trip duration against tier limits.
   * Returns null if valid, or an error message if invalid.
   */
  export function validateTripDuration(
    startDate: number,
    endDate: number,
    tier: UserTier
  ): string | null { ... }
  ```

## Function Design

**Size:**
- Small focused functions preferred (most functions 10-50 lines)
- Form handlers often 30-40 lines with validation + API call + error handling
- Complex business logic extracted into utility functions in `packages/types`

**Parameters:**
- Destructured object parameters for functions with 2+ arguments
- Example: `export function getDashboardState(targetTimeUtc: number, now: number, approachingMins: number = 120, urgentMins: number = 30)`
- Sensible defaults provided for optional parameters

**Return Values:**
- Explicit return types always specified
- Union return types for error conditions (e.g., `string | null` for validation)
- API handlers always return typed response objects (`CreateTripResponse`, `ListTripsResponse`)

## Module Design

**Exports:**
- Named exports for components: `export function AlertForm({ ... })`
- Type-only exports: `export type { UserTier, CreateAlertRequest }`
- Namespace exports from `packages/db`: `export * from './schema'`

**Barrel Files:**
- `packages/types/src/index.ts` is a single barrel file exporting all types, interfaces, and validators
- No barrel files in components (`apps/dashboard/src/components/` each imports individually)
- Re-export pattern in API: `export { AlertManager } from './alert-manager'`

## Constants & Configuration

**Configuration:**
- Environment variables: `process.env.NEXT_PUBLIC_API_URL` for frontend
- Default values defined in `packages/types`: `DEFAULT_APPROACHING_THRESHOLD = 120`
- Mantine theme colors used directly as hex values in inline styles (not theme-based yet)
- Theme color palette defined in `DECISIONS.md` (seaBlue, compassGold, parchment, ink)

**API URL Pattern:**
```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8787';
```

## React Component Patterns

**Component Structure:**
```typescript
'use client'; // Always for interactive components

import { useState, useCallback, useEffect } from 'react';
import { Button, Modal, TextInput, Alert } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDisclosure } from '@mantine/hooks';
import type { ComponentProps } from '@adventure-alerts/types';

interface ComponentNameProps {
  onAction: () => void;
  variant?: 'button' | 'inline';
}

export function ComponentName({ onAction, variant = 'button' }: ComponentNameProps) {
  const [state, setState] = useState(initialValue);
  const [opened, { open, close }] = useDisclosure(false);

  const handleAction = async (values) => {
    // Handle submission
  };

  return <div>{/* JSX */}</div>;
}
```

**Form Handling:**
- Mantine `useForm()` hook with validation object
- Form values destructured from hook return
- Validation functions return `null` for valid, error string for invalid
- Form reset after successful submission: `form.reset()`
- Pre-populated values for optional fields: `values.fieldName || undefined`

**State Management:**
- Client-side state only (no Redux/Zustand observed)
- Server state fetched via `fetch()` with try-catch
- `useCallback` for fetch functions to avoid stale closures (observed in line 36-48 of `alert-form.tsx`)
- `useEffect` triggers fetches on mount/dependency change

## Timestamp Handling

**Unix Milliseconds Convention:**
- All timestamps stored/transmitted as `number` (Unix milliseconds)
- Never use `new Date().toISOString()` for storage; convert to number before DB insert
- Date math: `1000 * 60 * 60 * 24` for milliseconds per day
- Example: `const durationMs = endDate - startDate; const durationDays = Math.ceil(durationMs / msPerDay);`

## Tier Validation Pattern

**Always used before insert/update:**
```typescript
const durationError = validateTripDuration(body.startDate, body.endDate, userTier);
if (durationError) {
  return c.json({ success: false, error: durationError }, 403);
}

const maxActiveTrips = TIER_LIMITS[userTier].maxActiveTrips;
if (maxActiveTrips !== Infinity) {
  const activeTrips = await db
    .select({ count: sql<number>`count(*)` })
    .from(trips)
    .where(and(eq(trips.userId, userId), inArray(trips.status, ['planning', 'active'])))
    .get();
  if (activeTrips && activeTrips.count >= maxActiveTrips) {
    return c.json({ success: false, error: 'Trip limit reached' }, 403);
  }
}
```

---

*Convention analysis: 2026-02-16*

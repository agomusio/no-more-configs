# Testing Patterns

**Analysis Date:** 2026-02-16

## Test Framework

**Runner:**
- No test framework detected in codebase
- TypeScript strict mode provides compile-time type checking
- React testing would use Jest or Vitest (not yet configured)

**Assertion Library:**
- Not applicable — testing not yet implemented

**Run Commands:**
```bash
# Linting and type checking (currently available)
npm run lint              # Lint all workspaces
npm run typecheck         # TypeScript strict check all workspaces

# Future commands (not yet configured)
# npm run test            # Run all tests
# npm run test:watch      # Watch mode
# npm run test:coverage   # Coverage report
```

## Test File Organization

**Location:**
- No test files currently exist in codebase
- Recommended location: Co-located with source files (`.test.ts` or `.spec.ts` suffix)
- Example pattern to implement:
  ```
  src/components/alert-form.tsx
  src/components/alert-form.test.tsx

  src/lib/validators.ts
  src/lib/validators.test.ts
  ```

**Naming:**
- Suffix: `.test.ts` (preferred for consistency with Jest default)
- Alternative: `.spec.ts`
- Example: `validateTripDuration.test.ts`, `getDashboardState.test.ts`

**Structure:**
```
apps/dashboard/
├── src/
│   ├── components/
│   │   ├── alert-form.tsx
│   │   └── alert-form.test.tsx    # Co-located test
│   └── lib/
│       ├── theme.ts
│       └── theme.test.ts          # Utility tests
packages/api/
├── src/
│   ├── index.ts
│   └── index.test.ts              # API route tests
└── __tests__/                      # Alternative: grouped in __tests__
    └── alert-manager.test.ts
```

## Test Structure (Recommended)

**Suite Organization:**
```typescript
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { validateTripDuration, getDashboardState } from '@adventure-alerts/types';

describe('validateTripDuration', () => {
  describe('scout tier (1 trip, 7 days max)', () => {
    it('should return null for valid 7-day trip', () => {
      const startDate = Date.now();
      const endDate = startDate + 7 * 24 * 60 * 60 * 1000;

      const result = validateTripDuration(startDate, endDate, 'scout');

      expect(result).toBeNull();
    });

    it('should return error for 8-day trip', () => {
      const startDate = Date.now();
      const endDate = startDate + 8 * 24 * 60 * 60 * 1000;

      const result = validateTripDuration(startDate, endDate, 'scout');

      expect(result).toContain('7 days');
    });

    it('should return null for voyager tier (no limit)', () => {
      const startDate = Date.now();
      const endDate = startDate + 365 * 24 * 60 * 60 * 1000;

      const result = validateTripDuration(startDate, endDate, 'voyager');

      expect(result).toBeNull();
    });
  });

  describe('edge cases', () => {
    it('should handle same-day trips', () => {
      const startDate = Date.now();
      const endDate = startDate + 1000; // 1 second

      const result = validateTripDuration(startDate, endDate, 'scout');

      expect(result).toBeNull();
    });
  });
});

describe('getDashboardState', () => {
  const now = 1000000;

  it('should return "urgent" when within 30 minutes', () => {
    const targetTime = now + 15 * 60 * 1000; // 15 minutes

    const state = getDashboardState(targetTime, now);

    expect(state).toBe('urgent');
  });

  it('should return "approaching" when within 2 hours', () => {
    const targetTime = now + 1 * 60 * 60 * 1000; // 1 hour

    const state = getDashboardState(targetTime, now);

    expect(state).toBe('approaching');
  });

  it('should return "normal" when more than 2 hours away', () => {
    const targetTime = now + 3 * 60 * 60 * 1000; // 3 hours

    const state = getDashboardState(targetTime, now);

    expect(state).toBe('normal');
  });

  it('should return "past" when target time has passed', () => {
    const targetTime = now - 1000; // 1 second ago

    const state = getDashboardState(targetTime, now);

    expect(state).toBe('past');
  });

  it('should respect custom thresholds', () => {
    const targetTime = now + 45 * 60 * 1000; // 45 minutes

    const state = getDashboardState(targetTime, now, 60, 60); // 60-min thresholds

    expect(state).toBe('approaching'); // Within 60-min approaching threshold
  });
});
```

**Patterns:**
- Use `describe()` for grouping related tests
- Nested `describe()` for scenario organization
- `it()` for individual test cases with clear names
- AAA pattern (Arrange, Act, Assert) in body

## Mocking

**Framework:**
- Recommended: Vitest with `vi` object for mocking
- No mocking infrastructure currently in place

**Patterns (to implement):**
```typescript
import { vi } from 'vitest';

// Mock API calls
const mockFetch = vi.fn();
global.fetch = mockFetch as any;

// Example: Mock successful response
mockFetch.mockResolvedValueOnce({
  json: async () => ({ success: true, alert: { id: '123', ... } }),
});

// Example: Mock error response
mockFetch.mockResolvedValueOnce({
  json: async () => ({ success: false, error: 'Invalid input' }),
});

// Reset between tests
afterEach(() => {
  mockFetch.mockClear();
});
```

**What to Mock:**
- External API calls (`fetch()` requests to `/trips`, `/alerts`)
- Durable Object interactions (`c.env.PRECISION_TIMER.get()`)
- Cloudflare D1 database calls
- Browser APIs that require environment setup (`Intl.DateTimeFormat` if needed)

**What NOT to Mock:**
- Pure utility functions (`validateTripDuration`, `getDashboardState`)
- React component rendering (use React Testing Library)
- Date/time calculations (test actual values)
- TypeScript type validation (compile-time check sufficient)

## Fixtures and Factories

**Test Data:**

Not yet implemented. Recommended factory pattern:

```typescript
// src/__tests__/factories.ts

export function createTrip(overrides?: Partial<Trip>): Trip {
  return {
    id: 'trip-123',
    userId: 'user-123',
    name: 'Spring Break 2026',
    destination: 'Walt Disney World',
    startDate: Date.now(),
    endDate: Date.now() + 7 * 24 * 60 * 60 * 1000,
    notes: null,
    status: 'planning',
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...overrides,
  };
}

export function createAlert(overrides?: Partial<Alert>): Alert {
  return {
    id: 'alert-456',
    userId: 'user-123',
    tripId: 'trip-123',
    eventId: 'event-789',
    eventName: 'Grand Canyon Mule Ride',
    targetTimeUtc: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
    notes: null,
    status: 'pending',
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

// Usage in tests:
it('should create trip with custom name', () => {
  const trip = createTrip({ name: 'Custom Trip' });
  expect(trip.name).toBe('Custom Trip');
});
```

**Location:**
- `src/__tests__/factories.ts` — Shared factory functions
- Or inline in test files for simple one-off data

## Coverage

**Requirements:**
- Not yet enforced
- Recommended targets (to establish):
  - Utility functions: 90%+ coverage
  - Components: 70%+ coverage
  - API routes: 85%+ coverage
  - Critical business logic (tier validation): 100%

**View Coverage:**
```bash
# After test framework setup
npm run test:coverage
# Generates: coverage/
```

## Test Types

**Unit Tests:**
- Scope: Pure functions and utilities in `packages/types/`
- Approach: Direct function call, assert output
- Examples to write:
  - `validateTripDuration()` with various date ranges and tiers
  - `getDashboardState()` with different time deltas
  - `getNotificationStage()` with time boundary conditions
  - Timestamp calculation logic

**Integration Tests:**
- Scope: API endpoints + database interaction
- Approach: Mock D1/Durable Objects, call endpoint, verify response and DB state
- Examples to write:
  - POST `/trips` → validate tier, create in DB, return response
  - POST `/alerts` → create in DB, schedule with Durable Object, return success
  - GET `/trips` → fetch user's trips with activity counts
  - PATCH `/trips/:id` → validate dates, update, verify response
  - Error cases: tier violations (403), invalid dates (400), missing fields (400)

**E2E Tests:**
- Not yet planned
- Would test: User flow from dashboard → form submission → API → response → UI update
- Framework options: Playwright, Cypress

## Common Patterns (to Implement)

**Async Testing:**
```typescript
// Async function with error handling
it('should create alert successfully', async () => {
  mockFetch.mockResolvedValueOnce({
    json: async () => ({ success: true, alert: testAlert }),
  });

  const result = await createAlert({ eventName: 'Test' });

  expect(result.success).toBe(true);
  expect(mockFetch).toHaveBeenCalledWith(
    'http://localhost:8787/alerts',
    expect.objectContaining({ method: 'POST' })
  );
});

// Error handling
it('should handle API errors', async () => {
  mockFetch.mockResolvedValueOnce({
    json: async () => ({ success: false, error: 'Invalid input' }),
  });

  const result = await createAlert({ eventName: '' });

  expect(result.success).toBe(false);
  expect(result.error).toContain('Invalid');
});
```

**Error Testing:**
```typescript
// Validation errors
it('should reject trip with end date before start date', () => {
  const startDate = Date.now();
  const endDate = startDate - 1000;

  expect(() => {
    if (endDate < startDate) throw new Error('End date must be after start date');
  }).toThrow('End date must be after start date');
});

// Tier enforcement
it('should reject scout tier trip exceeding 7 days', () => {
  const startDate = Date.now();
  const endDate = startDate + 8 * 24 * 60 * 60 * 1000;

  const error = validateTripDuration(startDate, endDate, 'scout');

  expect(error).toBeTruthy();
  expect(error).toContain('7 days');
});
```

**Component Testing (React Testing Library):**
```typescript
// Not yet implemented, recommended pattern:
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AlertForm } from '@/components/alert-form';

it('should show error when submission fails', async () => {
  mockFetch.mockResolvedValueOnce({
    json: async () => ({ success: false, error: 'Network error' }),
  });

  render(<AlertForm onAlertCreated={vi.fn()} />);

  fireEvent.click(screen.getByRole('button', { name: /new alert/i }));
  await waitFor(() => screen.getByDisplayValue(/event name/i));

  fireEvent.change(screen.getByPlaceholderText(/event name/i), {
    target: { value: 'Test Event' },
  });
  fireEvent.click(screen.getByRole('button', { name: /create/i }));

  await waitFor(() => {
    expect(screen.getByText(/network error/i)).toBeInTheDocument();
  });
});
```

## Critical Areas for Testing

**High Priority (Business Logic):**
1. Tier validation: `validateTripDuration()`, trip/activity count limits
2. Dashboard state calculation: `getDashboardState()` with all threshold conditions
3. API response format: All endpoints return `{ success: boolean, ... }`
4. Durable Object scheduling: Alert triggers at correct time
5. Timestamp calculations: Unix milliseconds consistency across frontend/API

**Medium Priority:**
1. Form validation: Required fields, date ranges
2. Error handling: API errors surface to user correctly
3. Timezone handling: Time display in user's timezone
4. CORS: API accepts requests from allowed origins

**Lower Priority (UI/Polish):**
1. Component styling
2. Animation/transitions
3. Accessibility (once framework setup)

## Test Infrastructure Setup (TODO)

1. Install Vitest: `npm install -D vitest @vitest/ui`
2. Create `vitest.config.ts` at root:
   ```typescript
   import { defineConfig } from 'vitest/config';
   import react from '@vitejs/plugin-react';

   export default defineConfig({
     plugins: [react()],
     test: {
       globals: true,
       environment: 'jsdom',
       setupFiles: ['./src/__tests__/setup.ts'],
     },
   });
   ```
3. Create setup file: `src/__tests__/setup.ts` with global mocks
4. Add to `package.json`:
   ```json
   "test": "vitest",
   "test:watch": "vitest --watch",
   "test:coverage": "vitest --coverage"
   ```

---

*Testing analysis: 2026-02-16*

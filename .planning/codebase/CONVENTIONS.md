# Coding Conventions

**Analysis Date:** 2026-02-10

## Naming Patterns

**Files:**
- TypeScript/TSX files: kebab-case (e.g., `alert-form.tsx`, `trip-form.tsx`, `upcoming-bookings.tsx`)
- Shell scripts: snake_case (e.g., `generate-env.sh`, `validate-setup.sh`, `test_env_generation.sh`)
- Python files: snake_case (e.g., `langfuse_hook.py`, `test_hook_unit.py`)
- Configuration files: specific formats (e.g., `docker-compose.yml`, `tsconfig.json`, `next.config.ts`)

**Functions:**
- TypeScript: camelCase (e.g., `fetchTrips()`, `handleSubmit()`, `sanitizeText()`)
- Python: snake_case (e.g., `load_state()`, `get_text_content()`, `extract_project_name()`)
- React components: PascalCase (e.g., `AlertForm`, `Sidebar`, `HeroClock`)

**Variables:**
- TypeScript: camelCase (e.g., `isLoading`, `serverTimeOffset`, `connectionStatus`)
- Python: snake_case (e.g., `log_file`, `secret_patterns`, `latest_mtime`)
- React state hooks: camelCase (e.g., `const [opened, { open, close }] = useDisclosure(false)`)

**Types/Interfaces:**
- TypeScript: PascalCase (e.g., `AlertFormProps`, `CreateAlertRequest`, `AlertState`)
- Type aliases for union types: PascalCase (e.g., `ConnectionStatus = 'connected' | 'disconnected' | 'syncing'`)

**Constants:**
- Bash/Shell: UPPER_SNAKE_CASE (e.g., `RED='\033[0;31m'`, `COMPOSE_PROJECT="langfuse-integration-test"`)
- Python: UPPER_SNAKE_CASE (e.g., `LOG_FILE`, `SECRET_PATTERNS`, `LOG_MAX_SIZE_BYTES`)
- TypeScript: UPPER_SNAKE_CASE or camelCase depending on context (e.g., `API_URL = 'http://localhost:8787'`)

## Code Style

**Formatting:**
- Prettier is the formatting tool (referenced in Next.js project)
- No explicit `.prettierrc` found; uses Next.js defaults
- Line length: Not explicitly enforced; observe existing code (~80-100 chars typical)
- Indentation: 2 spaces (TypeScript/JSX files)
- Bash scripts: 2-space or 4-space indentation (varies by script)

**Linting:**
- Next.js lint: `npm run lint` (uses Next.js ESLint config)
- TypeScript strict mode: Enabled in `tsconfig.json` (`"strict": true`)
- No explicit `.eslintrc` configuration files found (using Next.js defaults)

**Import Organization:**

Order observed:
1. External packages (React, Next.js, installed dependencies)
2. Type imports from external packages
3. Local module imports
4. Type imports from local modules
5. CSS/style imports

Example from `alert-form.tsx`:
```typescript
import { useState, useEffect, useCallback } from 'react';  // React hooks
import { Modal, Button, TextInput, ... } from '@mantine/core';  // UI library
import { useDisclosure } from '@mantine/hooks';  // Mantine hooks
import { IconPlus, ... } from '@tabler/icons-react';  // Icon library
import type { CreateAlertRequest, ... } from '@adventure-alerts/types';  // Type imports
```

**Path Aliases:**
- `@/*` → `./src/*` in Next.js dashboard (defined in `tsconfig.json`)
- Used for imports: `import { Sidebar } from '@/components/sidebar'`
- Monorepo workspace imports: `@adventure-alerts/types`, `@adventure-alerts/db`, `@adventure-alerts/api`

## Error Handling

**TypeScript Patterns:**
- Inline try-catch with typed error messages
- Pass errors to UI state: `setError(err instanceof Error ? err.message : 'An error occurred')`
- API responses use explicit success flags: `{ success: boolean, error?: string }`
- Silent failures for non-critical operations (e.g., trip fetching) with fallback UI

Example from `alert-form.tsx`:
```typescript
try {
  const response = await fetch(`${API_URL}/alerts`, { ... });
  const data: CreateAlertResponse = await response.json();
  if (!data.success) {
    throw new Error(data.error || 'Failed to create alert');
  }
  // Success handling
} catch (err) {
  setError(err instanceof Error ? err.message : 'An error occurred');
} finally {
  setIsLoading(false);
}
```

**Python Patterns:**
- Return early from main() on error with `sys.exit(0)` (hooks exit gracefully)
- Log errors to file with timestamps
- Exception handling in hooks is broad (all errors non-blocking)
- JSON decode errors silently skip bad lines: `except json.JSONDecodeError: continue`

Example from `langfuse_hook.py`:
```python
try:
    langfuse = Langfuse(public_key=..., secret_key=..., host=...)
except Exception as e:
    log("ERROR", f"Failed to initialize Langfuse client: {e}")
    sys.exit(0)  # Non-blocking failure
```

**Bash Patterns:**
- Set `set -euo pipefail` at script start (exit on error, undefined vars, pipe failures)
- Check command availability before use: `if command -v openssl &> /dev/null`
- Helper functions for consistent error reporting: `check_pass()`, `check_fail()`, `check_warn()`

Example from `validate-setup.sh`:
```bash
check_fail() {
    echo -e "${RED}✗ $1${NC}"
    FAILURES=$((FAILURES + 1))
}

if command -v docker &> /dev/null; then
    check_pass "Docker installed"
else
    check_fail "Docker not installed"
fi
```

## Logging

**Framework:**
- Bash: Custom colored output with helper functions (RED, GREEN, YELLOW colors)
- Python: File-based logging with `log()` function; timestamps added per-line
- TypeScript: `console.error()` for errors; no centralized logging library found

**Patterns:**

Bash logging with colors:
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

echo -e "${GREEN}✓ Check passed${NC}"
echo -e "${RED}Error: Something failed${NC}"
```

Python logging with rotation:
```python
LOG_FILE = Path.home() / ".claude" / "state" / "langfuse_hook.log"

def log(level: str, message: str) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"{timestamp} [{level}] {message}\n")
```

Debug logging (conditional):
```python
DEBUG = os.environ.get("CC_LANGFUSE_DEBUG", "").lower() == "true"

def debug(message: str) -> None:
    if DEBUG:
        log("DEBUG", message)
```

## Comments

**When to Comment:**

- Document why (not what) - code structure is usually self-documenting
- Explain non-obvious algorithms: seen in `langfuse_hook.py` process_transcript() which groups messages into turns
- Mark incomplete work: `TODO:` comments found in API code (`# TODO: Get from auth`, `# TODO: Count activities`)
- Explain cross-cutting concerns: shell scripts use comments to separate logical sections

Example from `index.ts`:
```typescript
// ============================================================================
// LEGACY ALERTS API (backward compatibility during migration)
// Uses raw SQL to query existing alerts table
// ============================================================================
```

**JSDoc/TSDoc:**
- Function documentation found in Python hook (`"""Docstrings"""`), not TypeScript
- Python uses triple-quoted docstrings with parameter descriptions
- TypeScript files do not use JSDoc comments

Python example from `langfuse_hook.py`:
```python
def extract_project_name(project_dir: Path) -> str:
    """Extract a human-readable project name from Claude's project directory name.

    Claude Code stores transcripts in directories named like:
    -Users-username-project-name

    We extract the project name portion.
    """
    # Implementation
```

## Function Design

**Size:**
- Functions stay compact and focused
- React components often 100-200 lines (including JSX)
- Utility functions 10-50 lines (examples: `sanitizeText()`, `get_text_content()`)
- Script functions vary by purpose (validation helpers are 5-10 lines; processing functions are 50-100 lines)

**Parameters:**
- React hooks receive typed props objects: `interface AlertFormProps { onAlertCreated: () => void; ... }`
- API endpoints receive Hono context: `async (c): Promise<Response>`
- Callbacks are typed as function types: `useCallback(async () => { ... }, [deps])`

Example:
```typescript
interface AlertFormProps {
  onAlertCreated: () => void;
  preselectedTripId?: string;
  variant?: 'button' | 'inline';
}

export function AlertForm({ onAlertCreated, preselectedTripId, variant = 'button' }: AlertFormProps) {
  // Implementation
}
```

**Return Values:**
- API responses follow consistent shape: `{ success: boolean, data?: T, error?: string }`
- React components return JSX (implicit return in functional components)
- Utility functions return typed values (Python uses type hints: `-> str`, `-> dict`, `-> int`)
- Callbacks often return void or Promise<void>

## Module Design

**Exports:**
- Named exports for functions and components: `export function AlertForm(...)`
- Default export for page components in Next.js: `export default function HomePage()`
- Re-exports from package indexes: `export { AlertManager } from './alert-manager'`

Example from `index.ts`:
```typescript
export { AlertManager } from './alert-manager';
export default app;  // Main Hono application
```

**Barrel Files:**
- Not explicitly used in current structure
- Each component file exports its own component directly

## API Design

**HTTP Methods:**
- GET: List and retrieve resources
- POST: Create resources
- PATCH: Update (partial) resources
- DELETE: Remove resources

Example from `index.ts`:
```typescript
app.get('/alerts', async (c): Promise<Response> => { ... });
app.post('/alerts', async (c): Promise<Response> => { ... });
app.patch('/trips/:id', async (c): Promise<Response> => { ... });
app.delete('/alerts/:id', async (c): Promise<Response> => { ... });
```

**Request/Response Types:**
- All requests/responses fully typed with TypeScript interfaces from `@adventure-alerts/types`
- Error responses include error message: `{ success: false, error: string }`
- Success responses include data: `{ success: true, data?: T }`

---

*Convention analysis: 2026-02-10*

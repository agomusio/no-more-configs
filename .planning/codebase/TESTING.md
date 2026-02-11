# Testing Patterns

**Analysis Date:** 2026-02-10

## Test Framework

**Runner (Bash/Shell):**
- Bash 5.0+ (scripts explicitly use `#!/usr/bin/env bash`)
- `docker compose` for integration testing
- No explicit test runner; tests are shell scripts that call other tools

**Validation Tools:**
- `bash -n`: Shell syntax validation
- `python3 -m py_compile`: Python syntax validation
- `docker compose config`: Docker Compose YAML validation
- `curl`: HTTP health checks
- `grep`/`grep -q`: Assertion tool for output validation

**Python Testing:**
- No external test framework found; uses simple function-based testing
- Unit tests in `test_hook_unit.py` use direct assertions
- Integration tests in `test_hook_integration.py` require langfuse package

**Run Commands:**

Bash tests - Validate syntax and structure:
```bash
./tests/test_syntax.sh              # Validate all script/config syntax
./tests/test_env_generation.sh      # Test environment generation script
./tests/test_full_integration.sh    # Full Docker + Langfuse integration
./tests/test_full_integration.sh --isolated  # Isolated ports for CI
```

Python tests - Unit and integration:
```bash
python3 tests/test_hook_unit.py     # Unit tests for utility functions
# (test_hook_integration.py runs as part of test_full_integration.sh)
```

## Test File Organization

**Location:**
- Bash integration tests: `/workspace/claudehome/langfuse-local/tests/test_*.sh`
- Python unit tests: `/workspace/claudehome/langfuse-local/tests/test_*.py`
- Tests are separate from source code (not co-located)

**Naming:**
- `test_[feature].sh` for bash tests (e.g., `test_syntax.sh`, `test_env_generation.sh`)
- `test_[feature].py` for Python tests (e.g., `test_hook_unit.py`)
- Pattern: `test_` prefix is standard across both languages

**Structure:**
```
claudehome/langfuse-local/
├── hooks/
│   └── langfuse_hook.py          # Source
├── scripts/
│   ├── generate-env.sh           # Source
│   ├── install-hook.sh           # Source
│   └── validate-setup.sh          # Source
└── tests/
    ├── test_syntax.sh             # Validates all scripts
    ├── test_env_generation.sh     # Environment setup tests
    ├── test_full_integration.sh   # Docker + API integration
    ├── test_hook_unit.py          # Unit tests (no mocking needed)
    └── test_hook_integration.py   # Langfuse client tests
```

## Test Structure

**Bash Suite Organization:**

Syntax validation (`test_syntax.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Validating shell scripts ==="
bash -n scripts/generate-env.sh
echo "✓ Shell scripts valid"

echo "=== Validating Python hook ==="
python3 -m py_compile hooks/langfuse_hook.py
echo "✓ Python hook valid"
```

Environment generation (`test_env_generation.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Setup temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Copy repo to temp, modify there
cp -r . "$TMPDIR"
cd "$TMPDIR"

# Run generator with test inputs
printf 'test@example.com\nTest User\ntestpass123\nTest Org\n' | ./scripts/generate-env.sh

# Assertions
if [[ ! -f .env ]]; then
    echo "FAIL: .env not created"
    exit 1
fi
echo "✓ .env file created"

# Verify generated values aren't placeholders
for var in POSTGRES_PASSWORD ENCRYPTION_KEY LANGFUSE_INIT_PROJECT_SECRET_KEY; do
    val=$(grep "^$var=" .env | cut -d= -f2 || echo "")
    if [[ -z "$val" || "$val" == "CHANGE_ME" ]]; then
        echo "FAIL: $var not generated properly"
        exit 1
    fi
done
echo "✓ Required variables generated"
```

Full integration (`test_full_integration.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

cleanup() {
    docker compose -p "langfuse-integration-test" down -v 2>/dev/null || true
}

trap cleanup EXIT

# Test sections:
# 1. Syntax validation (bash -n, python -m py_compile, docker compose config)
# 2. Environment generation (run script, verify .env created)
# 3. Docker Compose startup (docker compose up, wait for health)
# 4. Langfuse health check (curl /api/public/health)
# 5. Hook integration (run python tests with env vars set)
```

**Python Unit Testing:**

Simple assertion-based structure (`test_hook_unit.py`):
```python
#!/usr/bin/env python3
"""Unit tests for langfuse_hook.py

Tests the pure utility functions without requiring the langfuse package.
"""
import sys
from pathlib import Path
from unittest.mock import MagicMock

# Mock the langfuse module before importing
sys.modules['langfuse'] = MagicMock()
sys.path.insert(0, str(Path(__file__).parent.parent / 'hooks'))

from langfuse_hook import extract_project_name, get_text_content, is_tool_result

def test_extract_project_name():
    """Test project name extraction from Claude's directory format."""
    assert extract_project_name(Path("-Users-doneyli-djg-family-office")) == "djg-family-office"
    assert extract_project_name(Path("-Users-john-my-project")) == "my-project"
    print("✓ extract_project_name tests passed")

def test_get_text_content():
    """Test text extraction from messages."""
    assert get_text_content({"content": "hello"}) == "hello"
    assert get_text_content({"content": [{"type": "text", "text": "hello"}]}) == "hello"

    multi_text = {"content": [
        {"type": "text", "text": "hello"},
        {"type": "text", "text": "world"}
    ]}
    assert get_text_content(multi_text) == "hello\nworld"
    print("✓ get_text_content tests passed")

if __name__ == "__main__":
    test_extract_project_name()
    test_get_text_content()
    # ... other tests
    print("\nAll unit tests passed!")
```

**Patterns:**

Setup and cleanup:
```bash
# Bash: Setup/cleanup traps
trap cleanup EXIT
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Python: Not needed for unit tests (no side effects)
```

Assertion:
```bash
# Bash: if/then with echo messages
if [[ ! -f .env ]]; then
    echo "FAIL: .env not created"
    exit 1
fi

# Python: assert statements
assert extract_project_name(Path("-Users-bob")) == "-Users-bob"
assert get_content({"content": "hello"}) == "hello"
```

## Mocking

**Framework:**
- Python: `unittest.mock.MagicMock` for mocking the langfuse package
- Bash: No mocking framework; uses real commands and tools
- Shell integration tests use real Docker Compose containers

**Patterns:**

Python mocking (from `test_hook_unit.py`):
```python
from unittest.mock import MagicMock

# Mock langfuse module before importing hook
sys.modules['langfuse'] = MagicMock()

# Now import the hook that depends on langfuse
from langfuse_hook import extract_project_name, get_text_content
```

This allows unit tests to run without the langfuse package installed.

Bash real dependency testing (from `test_full_integration.sh`):
```bash
# Real Docker containers
docker compose -p "$COMPOSE_PROJECT" up -d

# Real health check
curl -s "http://localhost:$LANGFUSE_PORT/api/public/health"

# Real file operations
cp .env.example .env
printf 'email\npassword\n' | ./scripts/generate-env.sh
```

**What to Mock:**
- External Python packages (langfuse) in unit tests
- Do NOT mock: file I/O, CLI tools, or system commands in bash tests

**What NOT to Mock:**
- Shell commands and utilities
- Docker operations
- File system operations
- HTTP calls in integration tests (real endpoints)

## Fixtures and Factories

**Test Data:**

Bash fixtures (temporary directories):
```bash
# Setup isolated test environment
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp -r . "$TMPDIR"
cd "$TMPDIR"
```

Python fixtures (test message data):
```python
# Simple assertions with literal test data
def test_get_content():
    assert get_content({"content": "hello"}) == "hello"
    assert get_content({"message": {"content": "nested"}}) == "nested"
    content_list = [{"type": "text", "text": "hello"}]
    assert get_content({"content": content_list}) == content_list
```

**Location:**
- Bash: Fixtures created in temp directories within tests
- Python: Test data defined inline in test functions
- Docker: `docker-compose.yml` and `docker-compose.test.yml` serve as fixture configs

## Coverage

**Requirements:**
- No explicit coverage tool found (no pytest-cov, no bash coverage tool)
- Tests validate critical paths: syntax, setup, integration
- Python unit tests cover utility functions used across the hook

**View Coverage:**
- For Python: Would require `pytest --cov` (not currently configured)
- For Bash: Would require `kcov` (not found)

**Test Scope:**

Bash tests focus on:
- Script syntax validity
- Environment variable generation
- Docker service startup and health
- API responsiveness
- Hook file installation

Python tests focus on:
- Message content extraction
- Tool result detection
- Project name parsing
- Text sanitization (with/without redaction)
- Assistant message merging

## Test Types

**Unit Tests:**
- Scope: Pure utility functions in `langfuse_hook.py`
- Approach: Direct function calls with test inputs, assert on outputs
- Framework: Simple assertions with print statements
- Example: `test_extract_project_name()`, `test_get_text_content()`, `test_is_tool_result()`

**Integration Tests:**

Bash integration:
- Scope: Full setup workflow (env generation → Docker startup → API checks)
- Approach: Sequential test steps with cleanup trap
- Verification: HTTP health checks, file existence, Docker container health
- Example: `test_full_integration.sh`

Python integration:
- Scope: Langfuse client API (if `test_hook_integration.py` exists)
- Approach: Run hook against real Langfuse service
- Requirements: Docker-running Langfuse, langfuse Python package installed
- Verification: Traces created and queryable

**E2E Tests:**
- Not explicitly defined; `test_full_integration.sh` serves as end-to-end validation
- Tests real Docker Compose cluster, real file I/O, real HTTP calls

## Common Patterns

**Async Testing (Python/TypeScript):**
Not applicable to current test suite (bash and synchronous Python).

TypeScript async patterns observed in component tests would follow:
```typescript
// Not yet implemented in codebase
// Pattern to follow when tests are added:
test('fetches trips on open', async () => {
  render(<AlertForm onAlertCreated={() => {}} />);
  fireEvent.click(screen.getByText('New Alert'));
  await waitFor(() => expect(fetchMock).toHaveBeenCalled());
});
```

**Error Testing:**

Bash error assertions:
```bash
if [ $? -eq 0 ]; then
    pass "generate-env.sh executed successfully"
else
    fail "generate-env.sh failed"
fi
```

Python error assertions:
```python
# Silent failures with graceful exit patterns
try:
    langfuse = Langfuse(public_key=..., secret_key=..., host=...)
except Exception as e:
    log("ERROR", f"Failed to initialize Langfuse client: {e}")
    sys.exit(0)  # Non-blocking
```

**Bash Test Isolation:**

Tests create isolated environments:
```bash
# Each test runs in isolated temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"
# Run tests here, cleanup happens automatically
```

**Docker Test Isolation:**

Full integration test supports isolated mode:
```bash
# Standard mode: uses default ports (may conflict with existing services)
./tests/test_full_integration.sh

# Isolated mode: uses alternate ports for CI/parallel testing
./tests/test_full_integration.sh --isolated
# Uses LANGFUSE_PORT=3150 instead of 3050
```

## Test Configuration Files

**Relevant configs:**
- `docker-compose.test.yml`: Isolated Docker configuration for CI
- `.devcontainer/setup-container.sh`: Container-specific test setup
- Bash scripts themselves are configuration (test what, how, when)

**Bash Configuration Example:**
```bash
# From test_full_integration.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_PROJECT="langfuse-integration-test"
ISOLATED_MODE=false
LANGFUSE_PORT=3050

# Parse arguments
for arg in "$@"; do
    case $arg in
        --isolated)
            ISOLATED_MODE=true
            LANGFUSE_PORT=3150
            ;;
    esac
done
```

---

*Testing analysis: 2026-02-10*

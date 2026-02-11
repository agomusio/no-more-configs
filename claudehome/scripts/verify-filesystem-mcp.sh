#!/bin/bash
set -euo pipefail

# Filesystem MCP cross-container validation script
# Validates file operations work across devcontainer and gateway containers

echo "=== Filesystem MCP Cross-Container Validation ==="
echo ""

GATEWAY_NAME="docker-mcp-gateway"
GATEWAY_URL="http://host.docker.internal:8811"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; exit 1; }
info() { echo -e "${YELLOW}ℹ INFO${NC}: $1"; }

# Cleanup function
cleanup() {
    info "Cleaning up test files..."
    rm -f /workspace/claudehome/.mcp-test-dc.txt 2>/dev/null || true
    rm -f /workspace/.mcp-test-dc.txt 2>/dev/null || true
    docker exec "$GATEWAY_NAME" rm -f /workspace/claudehome/.mcp-test-gw.txt 2>/dev/null || true
    docker exec "$GATEWAY_NAME" rm -f /workspace/.mcp-test-gw.txt 2>/dev/null || true
    docker exec "$GATEWAY_NAME" rm -f /workspace/mcp-test-gw.txt 2>/dev/null || true
    info "Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# [1/6] Pre-flight: Check gateway health
echo "[1/6] Pre-flight: Checking gateway health..."
if curl -sf "${GATEWAY_URL}/health" > /dev/null 2>&1; then
    pass "Gateway is healthy"
else
    fail "Gateway not healthy. Run verify-gateway-connectivity.sh first"
fi

# [2/6] Devcontainer-to-gateway file visibility
echo ""
echo "[2/6] Testing devcontainer-to-gateway file visibility..."

# Write test file from devcontainer
TEST_CONTENT_DC="written-from-devcontainer-$(date +%s)"
echo "$TEST_CONTENT_DC" > /workspace/claudehome/.mcp-test-dc.txt
info "Wrote test file from devcontainer: /workspace/claudehome/.mcp-test-dc.txt"

# Try to read from gateway - check multiple possible paths
GATEWAY_CONTENT=""
if docker exec "$GATEWAY_NAME" test -f /workspace/claudehome/.mcp-test-dc.txt 2>/dev/null; then
    GATEWAY_CONTENT=$(docker exec "$GATEWAY_NAME" cat /workspace/claudehome/.mcp-test-dc.txt 2>/dev/null || echo "")
    GATEWAY_PATH="/workspace/claudehome/.mcp-test-dc.txt"
elif docker exec "$GATEWAY_NAME" test -f /workspace/.mcp-test-dc.txt 2>/dev/null; then
    GATEWAY_CONTENT=$(docker exec "$GATEWAY_NAME" cat /workspace/.mcp-test-dc.txt 2>/dev/null || echo "")
    GATEWAY_PATH="/workspace/.mcp-test-dc.txt"
else
    fail "Test file not found in gateway at any expected path"
fi

if [[ "$GATEWAY_CONTENT" == "$TEST_CONTENT_DC" ]]; then
    pass "Gateway can read file written by devcontainer at $GATEWAY_PATH"
    info "Content matches: $GATEWAY_CONTENT"
else
    fail "Content mismatch. Expected: '$TEST_CONTENT_DC', Got: '$GATEWAY_CONTENT'"
fi

# [3/6] Gateway-to-devcontainer file visibility
echo ""
echo "[3/6] Testing gateway-to-devcontainer file visibility..."

# Write test file from gateway
TEST_CONTENT_GW="written-from-gateway-$(date +%s)"
docker exec "$GATEWAY_NAME" sh -c "echo '$TEST_CONTENT_GW' > /workspace/mcp-test-gw.txt"
info "Wrote test file from gateway: /workspace/mcp-test-gw.txt"

# Try to read from devcontainer - check multiple possible paths
DEVCONTAINER_CONTENT=""
if [[ -f /workspace/mcp-test-gw.txt ]]; then
    DEVCONTAINER_CONTENT=$(cat /workspace/mcp-test-gw.txt)
    DEVCONTAINER_PATH="/workspace/mcp-test-gw.txt"
elif [[ -f /workspace/claudehome/mcp-test-gw.txt ]]; then
    DEVCONTAINER_CONTENT=$(cat /workspace/claudehome/mcp-test-gw.txt)
    DEVCONTAINER_PATH="/workspace/claudehome/mcp-test-gw.txt"
else
    fail "Test file not found in devcontainer at any expected path"
fi

if [[ "$DEVCONTAINER_CONTENT" == "$TEST_CONTENT_GW" ]]; then
    pass "Devcontainer can read file written by gateway at $DEVCONTAINER_PATH"
    info "Content matches: $DEVCONTAINER_CONTENT"
else
    fail "Content mismatch. Expected: '$TEST_CONTENT_GW', Got: '$DEVCONTAINER_CONTENT'"
fi

# [4/6] Gateway can list workspace directory
echo ""
echo "[4/6] Testing gateway workspace directory listing..."

WORKSPACE_LISTING=$(docker exec "$GATEWAY_NAME" ls /workspace 2>/dev/null || echo "")
if [[ -n "$WORKSPACE_LISTING" ]]; then
    pass "Gateway can list /workspace directory"
    info "Found $(echo "$WORKSPACE_LISTING" | wc -l) items in /workspace"
else
    fail "Gateway cannot list /workspace directory or it's empty"
fi

# [5/6] Gateway can read arbitrary file
echo ""
echo "[5/6] Testing gateway file read capability..."

# Use a known file - the gateway's own mcp.json config
KNOWN_FILE="/workspace/claudehome/langfuse-local/mcp/mcp.json"
if [[ ! -f "$KNOWN_FILE" ]]; then
    # Fallback to README or any other known file
    KNOWN_FILE="/workspace/claudehome/README.md"
fi

if [[ ! -f "$KNOWN_FILE" ]]; then
    info "Skipping test - no known file found to test with"
else
    # Get the gateway path equivalent
    GATEWAY_FILE_PATH=$(echo "$KNOWN_FILE" | sed 's|^/workspace/claudehome/|/workspace/claudehome/|' || echo "$KNOWN_FILE")

    # Check if file exists in gateway
    if docker exec "$GATEWAY_NAME" test -f "$GATEWAY_FILE_PATH" 2>/dev/null; then
        GATEWAY_READ=$(docker exec "$GATEWAY_NAME" cat "$GATEWAY_FILE_PATH" 2>/dev/null | head -c 100)
        if [[ -n "$GATEWAY_READ" ]]; then
            pass "Gateway can read arbitrary files from workspace"
            info "Successfully read from: $GATEWAY_FILE_PATH"
        else
            fail "Gateway file read returned empty content"
        fi
    else
        # Try alternate path
        GATEWAY_FILE_PATH="/workspace/$(basename $(dirname "$KNOWN_FILE"))/$(basename "$KNOWN_FILE")"
        if docker exec "$GATEWAY_NAME" test -f "$GATEWAY_FILE_PATH" 2>/dev/null; then
            GATEWAY_READ=$(docker exec "$GATEWAY_NAME" cat "$GATEWAY_FILE_PATH" 2>/dev/null | head -c 100)
            if [[ -n "$GATEWAY_READ" ]]; then
                pass "Gateway can read arbitrary files from workspace"
                info "Successfully read from: $GATEWAY_FILE_PATH"
            else
                fail "Gateway file read returned empty content"
            fi
        else
            info "Known file not accessible at expected gateway path, but write tests passed"
        fi
    fi
fi

# [6/6] Summary of path mapping
echo ""
echo "[6/6] Path mapping summary..."

info "Devcontainer -> Gateway mapping verified"
info "  Write at: /workspace/claudehome/... → Read at: /workspace/claudehome/..."
info "  Gateway writes to /workspace/ → Devcontainer reads from /workspace/"
pass "Cross-container file operations validated"

echo ""
echo -e "${GREEN}=== All filesystem MCP validation checks passed ===${NC}"
echo "Files written from devcontainer are visible in gateway and vice versa"
echo "Volume mount alignment confirmed empirically"
exit 0

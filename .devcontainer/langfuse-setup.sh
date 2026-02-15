#!/bin/bash
set -euo pipefail

# langfuse-setup — single command for all Langfuse infrastructure management.
# Generates secrets, writes infra/.env, starts docker compose, verifies health.
#
# Usage:
#   langfuse-setup              Full setup: generate secrets if needed, write .env, start stack, verify
#   langfuse-setup --generate-env   Just regenerate infra/.env from secrets.json (used by install-agent-config.sh)
#   langfuse-setup --status     Check health of running stack

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKSPACE_ROOT="/workspace"
SECRETS_FILE="$WORKSPACE_ROOT/secrets.json"
CONFIG_FILE="$WORKSPACE_ROOT/config.json"
INFRA_DIR="$WORKSPACE_ROOT/infra"
ENV_FILE="$INFRA_DIR/.env"
COMPOSE_FILE="$INFRA_DIR/docker-compose.yml"
LANGFUSE_HOST="${LANGFUSE_HOST:-http://host.docker.internal:3052}"

# ─── Helpers ─────────────────────────────────────────────────────────────────

die()  { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; }
info() { echo -e "${BLUE}  → $1${NC}"; }

need_cmd() {
    command -v "$1" &>/dev/null || die "$1 is required but not installed"
}

# Read a key from secrets.json (returns empty string if missing)
secret() {
    jq -r "$1 // \"\"" "$SECRETS_FILE" 2>/dev/null || echo ""
}

# Read a key from config.json (returns default if missing)
config() {
    local path="$1" default="${2:-}"
    if [ -f "$CONFIG_FILE" ]; then
        jq -r "$path // \"$default\"" "$CONFIG_FILE" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# ─── Generate secrets into secrets.json ──────────────────────────────────────

generate_secrets() {
    need_cmd openssl
    need_cmd jq

    echo ""
    echo -e "${BLUE}Generating infrastructure secrets...${NC}"

    # Derive Langfuse user info from git identity if available
    local user_email user_name
    user_email=$(secret '.git.email')
    user_name=$(secret '.git.name')
    [ -z "$user_email" ] && user_email="admin@localhost"
    [ -z "$user_name" ] && user_name="Admin"

    local pg_pass ek nas salt ch_pass minio_pass redis_auth user_pass lf_sk
    pg_pass=$(openssl rand -hex 24)
    ek=$(openssl rand -hex 32)
    nas=$(openssl rand -hex 32)
    salt=$(openssl rand -hex 16)
    ch_pass=$(openssl rand -hex 24)
    minio_pass=$(openssl rand -hex 24)
    redis_auth=$(openssl rand -hex 24)
    user_pass=$(openssl rand -hex 12)
    lf_sk="sk-lf-local-$(openssl rand -hex 16)"

    # Build the infra section
    local infra
    infra=$(jq -n \
        --arg pg "$pg_pass" \
        --arg ek "$ek" \
        --arg nas "$nas" \
        --arg salt "$salt" \
        --arg ch "$ch_pass" \
        --arg minio "$minio_pass" \
        --arg redis "$redis_auth" \
        --arg email "$user_email" \
        --arg name "$user_name" \
        --arg pass "$user_pass" \
        --arg org "My Org" \
        '{
            postgres_password: $pg,
            encryption_key: $ek,
            nextauth_secret: $nas,
            salt: $salt,
            clickhouse_password: $ch,
            minio_root_password: $minio,
            redis_auth: $redis,
            langfuse_project_public_key: "pk-lf-local-claude-code",
            langfuse_project_secret_key: $sk,
            langfuse_user_email: $email,
            langfuse_user_name: $name,
            langfuse_user_password: $pass,
            langfuse_org_name: $org
        }')

    # Update secrets.json
    if [ -f "$SECRETS_FILE" ]; then
        jq --argjson infra "$infra" '.infra = $infra' \
            "$SECRETS_FILE" > "$SECRETS_FILE.tmp" && mv "$SECRETS_FILE.tmp" "$SECRETS_FILE"
    else
        jq -n --argjson infra "$infra" \
            '{git:{name:"",email:""},claude:{credentials:{}},codex:{auth:{}},infra:$infra}' \
            > "$SECRETS_FILE"
    fi
    chmod 600 "$SECRETS_FILE"

    ok "Generated infrastructure secrets"
    info "Langfuse admin: $user_email / $user_pass"
    info "Project secret key: $lf_sk"
}

# ─── Write infra/.env from secrets.json ──────────────────────────────────────

write_env() {
    need_cmd jq

    [ -f "$SECRETS_FILE" ] || die "secrets.json not found — run langfuse-setup first"

    # Check infra section exists
    local has_infra
    has_infra=$(jq -e '.infra.postgres_password // empty' "$SECRETS_FILE" 2>/dev/null && echo "yes" || echo "")
    [ -n "$has_infra" ] || die "secrets.json has no infra section — run langfuse-setup to generate"

    # Read all values
    local pg_pass ek nas salt ch_pass minio_pass redis_auth
    local lf_pk lf_sk user_email user_name user_pass org_name mcp_bind
    pg_pass=$(secret '.infra.postgres_password')
    ek=$(secret '.infra.encryption_key')
    nas=$(secret '.infra.nextauth_secret')
    salt=$(secret '.infra.salt')
    ch_pass=$(secret '.infra.clickhouse_password')
    minio_pass=$(secret '.infra.minio_root_password')
    redis_auth=$(secret '.infra.redis_auth')
    lf_pk=$(secret '.infra.langfuse_project_public_key')
    lf_sk=$(secret '.infra.langfuse_project_secret_key')
    user_email=$(secret '.infra.langfuse_user_email')
    user_name=$(secret '.infra.langfuse_user_name')
    user_pass=$(secret '.infra.langfuse_user_password')
    org_name=$(secret '.infra.langfuse_org_name')
    mcp_bind=$(config '.infra.mcp_workspace_bind' '/workspace')

    [ -z "$lf_pk" ] && lf_pk="pk-lf-local-claude-code"
    [ -z "$org_name" ] && org_name="My Org"

    cat > "$ENV_FILE" << EOF
# Generated by langfuse-setup from secrets.json — do not edit manually

# Service passwords
POSTGRES_PASSWORD=$pg_pass
ENCRYPTION_KEY=$ek
NEXTAUTH_SECRET=$nas
SALT=$salt
CLICKHOUSE_PASSWORD=$ch_pass
MINIO_ROOT_PASSWORD=$minio_pass
REDIS_AUTH=$redis_auth

# Langfuse project (auto-created)
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=$lf_pk
LANGFUSE_INIT_PROJECT_SECRET_KEY=$lf_sk

# Langfuse admin user (auto-created)
LANGFUSE_INIT_USER_EMAIL=$user_email
LANGFUSE_INIT_USER_NAME=$user_name
LANGFUSE_INIT_USER_PASSWORD=$user_pass
LANGFUSE_INIT_ORG_NAME=$org_name

# MCP gateway host bind path
MCP_WORKSPACE_BIND=$mcp_bind
EOF

    chmod 600 "$ENV_FILE"
    ok "Generated infra/.env from secrets.json"
}

# ─── Status / health check ───────────────────────────────────────────────────

check_status() {
    echo ""
    echo -e "${BLUE}Langfuse Stack Status${NC}"
    echo ""

    # Check containers
    local running
    running=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Name}} {{.Status}}' 2>/dev/null || echo "")

    if [ -z "$running" ]; then
        fail "No containers found — stack is not running"
        echo "    Run: langfuse-setup"
        return 1
    fi

    local all_ok=true
    while IFS= read -r line; do
        local name status
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | cut -d' ' -f2-)
        if echo "$status" | grep -qi "up\|running"; then
            if echo "$status" | grep -qi "unhealthy"; then
                warn "$name — unhealthy"
                all_ok=false
            else
                ok "$name — $status"
            fi
        else
            fail "$name — $status"
            all_ok=false
        fi
    done <<< "$running"

    # Check Langfuse API
    echo ""
    local health
    health=$(curl -s --max-time 5 "$LANGFUSE_HOST/api/public/health" 2>/dev/null || echo "")
    if echo "$health" | grep -qi "ok"; then
        local version
        version=$(echo "$health" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
        ok "Langfuse API healthy (v$version)"
    else
        fail "Langfuse API not responding at $LANGFUSE_HOST"
        all_ok=false
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}All services healthy.${NC}"
        echo "  UI: http://localhost:3052"
    else
        echo -e "${YELLOW}Some services need attention.${NC}"
        echo "  Logs: docker compose -f $COMPOSE_FILE logs -f"
        return 1
    fi
}

# ─── Full setup ──────────────────────────────────────────────────────────────

full_setup() {
    need_cmd docker
    need_cmd jq

    echo "====================================="
    echo " Langfuse Setup"
    echo "====================================="

    # Step 1: Ensure secrets exist
    local has_infra=""
    if [ -f "$SECRETS_FILE" ]; then
        has_infra=$(jq -e '.infra.postgres_password // empty' "$SECRETS_FILE" 2>/dev/null && echo "yes" || echo "")
    fi

    if [ -z "$has_infra" ]; then
        info "No infrastructure secrets found — generating..."
        generate_secrets
    else
        ok "Infrastructure secrets found in secrets.json"
    fi

    # Step 2: Write .env
    echo ""
    write_env

    # Step 3: Start the stack
    echo ""
    echo -e "${BLUE}Starting Langfuse stack...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d 2>&1 | while IFS= read -r line; do
        echo "  $line"
    done

    # Step 4: Wait for health
    echo ""
    echo -e "${BLUE}Waiting for Langfuse to become healthy...${NC}"
    local attempts=0 max_attempts=30
    while [ $attempts -lt $max_attempts ]; do
        local health
        health=$(curl -s --max-time 3 "$LANGFUSE_HOST/api/public/health" 2>/dev/null || echo "")
        if echo "$health" | grep -qi "ok"; then
            ok "Langfuse is healthy"
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    if [ $attempts -eq $max_attempts ]; then
        warn "Langfuse not yet responding — it may still be starting"
        echo "    Check: langfuse-setup --status"
        echo ""
        return
    fi

    # Step 5: Summary
    local user_email user_pass
    user_email=$(secret '.infra.langfuse_user_email')
    user_pass=$(secret '.infra.langfuse_user_password')

    echo ""
    echo "====================================="
    echo -e "${GREEN} Setup Complete${NC}"
    echo "====================================="
    echo ""
    echo "  UI:       http://localhost:3052"
    echo "  Email:    $user_email"
    echo "  Password: $user_pass"
    echo ""
    echo "  Traces appear automatically after Claude Code conversations."
    echo ""
}

# ─── Main dispatch ───────────────────────────────────────────────────────────

case "${1:-}" in
    --generate-env)
        write_env
        ;;
    --status)
        check_status
        ;;
    --help|-h)
        echo "Usage: langfuse-setup [--generate-env | --status | --help]"
        echo ""
        echo "  (no args)       Full setup: generate secrets, write .env, start stack, verify"
        echo "  --generate-env  Regenerate infra/.env from secrets.json"
        echo "  --status        Check health of running Langfuse stack"
        ;;
    "")
        full_setup
        ;;
    *)
        die "Unknown option: $1 (try --help)"
        ;;
esac

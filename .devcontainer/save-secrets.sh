#!/bin/bash
set -euo pipefail

# save-secrets.sh
# Captures live credentials back into secrets.json for backup/persistence.
# Run this before rebuilding to preserve credentials across container rebuilds.

SECRETS_FILE="/workspace/secrets.json"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/node/.claude}"

# Start with existing secrets.json or empty template
if [ -f "$SECRETS_FILE" ]; then
    SECRETS=$(cat "$SECRETS_FILE")
else
    SECRETS='{"git":{"name":"","email":""},"claude":{"credentials":{}},"codex":{"auth":{}},"infra":{}}'
fi

echo "[save-secrets] Capturing live credentials..."

# Capture git identity
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
if [ -n "$GIT_NAME" ] || [ -n "$GIT_EMAIL" ]; then
    SECRETS=$(echo "$SECRETS" | jq --arg name "$GIT_NAME" --arg email "$GIT_EMAIL" '.git.name = $name | .git.email = $email')
    echo "[save-secrets] Git identity: captured ($GIT_NAME <$GIT_EMAIL>)"
else
    echo "[save-secrets] Git identity: not set"
fi

# Capture Claude credentials
if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
    CREDS=$(cat "$CLAUDE_DIR/.credentials.json")
    SECRETS=$(echo "$SECRETS" | jq --argjson creds "$CREDS" '.claude.credentials = $creds')
    echo "[save-secrets] Claude credentials: captured"
else
    echo "[save-secrets] Claude credentials: not found (manual login required after rebuild)"
fi

# Capture Codex CLI credentials
CODEX_AUTH_FILE="/home/node/.codex/auth.json"
if [ -f "$CODEX_AUTH_FILE" ]; then
    CODEX_AUTH=$(cat "$CODEX_AUTH_FILE")
    SECRETS=$(echo "$SECRETS" | jq --argjson auth "$CODEX_AUTH" '.codex.auth = $auth')
    echo "[save-secrets] Codex credentials: captured"
else
    echo "[save-secrets] Codex credentials: not found (run 'codex' to authenticate)"
fi

# Capture GitHub CLI credentials
GH_HOSTS_FILE="/home/node/.config/gh/hosts.yml"
if [ -f "$GH_HOSTS_FILE" ]; then
    GH_TOKEN=$(grep -oP 'oauth_token:\s*\K.*' "$GH_HOSTS_FILE" 2>/dev/null || echo "")
    GH_USER=$(grep -oP 'user:\s*\K.*' "$GH_HOSTS_FILE" 2>/dev/null || echo "")
    GH_PROTO=$(grep -oP 'git_protocol:\s*\K.*' "$GH_HOSTS_FILE" 2>/dev/null || echo "https")
    if [ -n "$GH_TOKEN" ]; then
        SECRETS=$(echo "$SECRETS" | jq \
            --arg token "$GH_TOKEN" \
            --arg user "$GH_USER" \
            --arg proto "$GH_PROTO" \
            '.gh = { oauth_token: $token, user: $user, git_protocol: $proto }')
        echo "[save-secrets] GitHub CLI credentials: captured ($GH_USER)"
    else
        echo "[save-secrets] GitHub CLI credentials: no token found"
    fi
else
    echo "[save-secrets] GitHub CLI credentials: not found (run 'gh auth login' to authenticate)"
fi

# Capture infrastructure secrets from infra/.env (includes Langfuse project keys)
INFRA_ENV="/workspace/infra/.env"
if [ -f "$INFRA_ENV" ]; then
    get_env() { grep -oP "^$1=\\K.*" "$INFRA_ENV" 2>/dev/null || echo ""; }

    INFRA_PG=$(get_env "POSTGRES_PASSWORD")
    INFRA_EK=$(get_env "ENCRYPTION_KEY")
    INFRA_NAS=$(get_env "NEXTAUTH_SECRET")
    INFRA_SALT=$(get_env "SALT")
    INFRA_CH=$(get_env "CLICKHOUSE_PASSWORD")
    INFRA_MINIO=$(get_env "MINIO_ROOT_PASSWORD")
    INFRA_REDIS=$(get_env "REDIS_AUTH")
    INFRA_LF_PK=$(get_env "LANGFUSE_INIT_PROJECT_PUBLIC_KEY")
    INFRA_LF_SK=$(get_env "LANGFUSE_INIT_PROJECT_SECRET_KEY")
    INFRA_EMAIL=$(get_env "LANGFUSE_INIT_USER_EMAIL")
    INFRA_NAME=$(get_env "LANGFUSE_INIT_USER_NAME")
    INFRA_PASS=$(get_env "LANGFUSE_INIT_USER_PASSWORD")
    INFRA_ORG=$(get_env "LANGFUSE_INIT_ORG_NAME")
    [ -z "$INFRA_LF_PK" ] && INFRA_LF_PK="pk-lf-local-claude-code"

    if [ -n "$INFRA_PG" ]; then
        SECRETS=$(echo "$SECRETS" | jq \
            --arg pg "$INFRA_PG" \
            --arg ek "$INFRA_EK" \
            --arg nas "$INFRA_NAS" \
            --arg salt "$INFRA_SALT" \
            --arg ch "$INFRA_CH" \
            --arg minio "$INFRA_MINIO" \
            --arg redis "$INFRA_REDIS" \
            --arg lf_pk "$INFRA_LF_PK" \
            --arg lf_sk "$INFRA_LF_SK" \
            --arg email "$INFRA_EMAIL" \
            --arg name "$INFRA_NAME" \
            --arg pass "$INFRA_PASS" \
            --arg org "$INFRA_ORG" \
            '.infra = {
                postgres_password: $pg,
                encryption_key: $ek,
                nextauth_secret: $nas,
                salt: $salt,
                clickhouse_password: $ch,
                minio_root_password: $minio,
                redis_auth: $redis,
                langfuse_project_public_key: $lf_pk,
                langfuse_project_secret_key: $lf_sk,
                langfuse_user_email: $email,
                langfuse_user_name: $name,
                langfuse_user_password: $pass,
                langfuse_org_name: $org
            }')
        echo "[save-secrets] Infrastructure secrets: captured"
    fi
fi

# Populate plugin namespaces for plugin env hydration
# nmc-langfuse-tracing: derive from infra keys + config.json host
CONFIG_FILE="/workspace/config.json"
LF_HOST=""
if [ -f "$CONFIG_FILE" ]; then
    LF_HOST=$(jq -r '.langfuse.host // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
fi
LF_PK=$(echo "$SECRETS" | jq -r '.infra.langfuse_project_public_key // ""')
LF_SK=$(echo "$SECRETS" | jq -r '.infra.langfuse_project_secret_key // ""')
if [ -n "$LF_PK" ] || [ -n "$LF_SK" ] || [ -n "$LF_HOST" ]; then
    SECRETS=$(echo "$SECRETS" | jq \
        --arg host "$LF_HOST" \
        --arg pk "$LF_PK" \
        --arg sk "$LF_SK" \
        '."nmc-langfuse-tracing" = {
            LANGFUSE_HOST: $host,
            LANGFUSE_PUBLIC_KEY: $pk,
            LANGFUSE_SECRET_KEY: $sk
        }')
    echo "[save-secrets] Plugin namespace 'nmc-langfuse-tracing': populated from infra keys + config"
fi

# Write back to secrets.json
echo "$SECRETS" | jq '.' > "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"
echo "[save-secrets] Saved to $SECRETS_FILE"
echo ""
echo "[save-secrets] Tip: also run save-config to persist Claude Code preferences (auto-compact, editor mode, etc.)"

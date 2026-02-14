#!/usr/bin/env bash
# Codex environment setup for claude-code-sandbox review tasks.
# Run this in the Codex sandbox before starting work.
set -euo pipefail

echo "=== Codex environment setup for claude-code-sandbox ==="

# Core analysis tools
apt-get update -qq
apt-get install -y -qq jq shellcheck python3 python3-pip yamllint > /dev/null 2>&1

# Node.js (for parsing package.json, running eslint checks)
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
  apt-get install -y -qq nodejs > /dev/null 2>&1
fi

# Dockerfile linting
if ! command -v hadolint &> /dev/null; then
  curl -fsSL -o /usr/local/bin/hadolint \
    https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
  chmod +x /usr/local/bin/hadolint
fi

# Python linting
pip3 install --quiet ruff 2>/dev/null || true

echo ""
echo "=== Available tools ==="
echo "  jq:         $(jq --version 2>/dev/null || echo 'missing')"
echo "  shellcheck: $(shellcheck --version 2>/dev/null | head -2 | tail -1 || echo 'missing')"
echo "  hadolint:   $(hadolint --version 2>/dev/null || echo 'missing')"
echo "  yamllint:   $(yamllint --version 2>/dev/null || echo 'missing')"
echo "  node:       $(node --version 2>/dev/null || echo 'missing')"
echo "  ruff:       $(ruff --version 2>/dev/null || echo 'missing')"
echo "  python3:    $(python3 --version 2>/dev/null || echo 'missing')"

echo ""
echo "=== Files in the repo (reviewable) ==="
echo "  README.md                                     # Full architecture reference — read first"
echo "  .devcontainer/Dockerfile                      # Container image definition (2.4GB)"
echo "  .devcontainer/devcontainer.json               # Mounts, ports, env vars, lifecycle hooks"
echo "  .devcontainer/init-firewall.sh                # iptables whitelist firewall"
echo "  .devcontainer/setup-container.sh              # Post-create setup (pip, git, Docker socket)"
echo "  .devcontainer/init-gsd.sh                     # GSD framework installer"
echo "  infra/docker-compose.yml                       # 8-service sidecar stack"
echo "  infra/mcp/mcp.json                            # MCP gateway server config"
echo "  agent-config/settings.json.template           # Claude Code settings template"

echo ""
echo "=== Files NOT in the repo (bind-mounted at runtime from Windows host) ==="
echo "  /home/node/.claude/hooks/langfuse_hook.py     # Langfuse tracing hook (18KB Python)"
echo "  /home/node/.claude/hooks/gsd-check-update.js  # GSD update checker"
echo "  /home/node/.claude/hooks/gsd-statusline.js    # GSD terminal status line"
echo "  /home/node/.claude/settings.json              # Global Claude Code settings"
echo "  /home/node/.claude/commands/gsd/              # 29 GSD slash commands"
echo "  /home/node/.claude/agents/gsd-*.md            # 11 GSD specialized agents"
echo "  These files come from the Windows host %USERPROFILE%\\.claude bind mount."
echo "  Review them only if they are provided separately."

echo ""
echo "=== Quick checks ==="
echo "  hadolint .devcontainer/Dockerfile"
echo "  shellcheck .devcontainer/*.sh"
echo "  yamllint infra/docker-compose.yml"
echo "  jq . infra/mcp/mcp.json"
echo "  jq . agent-config/settings.json.template"

echo ""
echo "=== Output ==="
echo "  Write all review files to docs/ (e.g. docs/codex-dockerfile-audit.md)"
echo "  Update the table in docs/README.md with each new file"

echo ""
echo "Setup complete."

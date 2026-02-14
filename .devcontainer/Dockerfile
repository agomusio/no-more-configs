FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
# ADDED: lsb-release, curl, ca-certificates for Docker install
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  python3-pip \
  python3-venv \
  lsb-release \
  curl \
  ca-certificates \
  iputils-ping \
  locales \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ADDED: Install Docker CLI (Docker-outside-of-Docker)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh

# GIVE 'node' FULL SUDO ACCESS
# This allows Claude Code to run the firewall script AND use tar/zstd
RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node && \
    chmod 0440 /etc/sudoers.d/node

# Set up non-root user
USER node

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude Code (it will go into /home/node/.local/bin)
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}"

# Add the node user's local bin to the PATH
ENV PATH="/home/node/.local/bin:${PATH}"

# Skip permissions for Claude in WSL
ENV CLAUDE_BYPASS_PERMISSIONS=true

# Verify as the node user
RUN claude --version

# Install GSD (Get Shit Done) framework for Claude Code
RUN npm install -g get-shit-done-cc

# Add claudey/claudeyr aliases and mcp-setup function to both shell configs
RUN echo "alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'" >> /home/node/.bashrc && \
    echo "alias claudeyr='cd /workspace/claudehome && claude --dangerously-skip-permissions --resume'" >> /home/node/.bashrc && \
    echo "alias claudey='cd /workspace/claudehome && claude --dangerously-skip-permissions'" >> /home/node/.zshrc && \
    echo "alias claudeyr='cd /workspace/claudehome && claude --dangerously-skip-permissions --resume'" >> /home/node/.zshrc && \
    cat <<'SHELL_FUNCTION' >> /home/node/.bashrc && \

# MCP setup function - auto-generates .mcp.json and checks gateway health
mcp-setup() {
  local gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"

  # Generate .mcp.json at workspace root
  cat <<EOF > /workspace/.mcp.json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "${gateway_url}/sse"
    }
  }
}
EOF

  echo "✓ Generated /workspace/.mcp.json"

  # Poll gateway health endpoint with retry logic
  echo "Checking gateway health at ${gateway_url}/health..."
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --retry 15 --retry-delay 2 --retry-max-time 30 --retry-connrefused \
    "${gateway_url}/health" 2>&1 || echo "000")

  if [ "$http_code" = "200" ]; then
    echo "✓ Gateway is healthy"
  else
    echo "⚠ Warning: Gateway not ready (HTTP ${http_code})"
    echo "  Start: cd /workspace/claudehome/langfuse-local && docker compose up -d docker-mcp-gateway"
  fi

  echo ""
  echo "Config: /workspace/.mcp.json"
  echo "Gateway: ${gateway_url}"
  echo "Next: Restart Claude Code session to pick up MCP tools"
  echo "To add servers: Edit langfuse-local/mcp/mcp.json, restart gateway, then re-run mcp-setup"
}
SHELL_FUNCTION
    cat <<'SHELL_FUNCTION' >> /home/node/.zshrc

# MCP setup function - auto-generates .mcp.json and checks gateway health
mcp-setup() {
  local gateway_url="${MCP_GATEWAY_URL:-http://host.docker.internal:8811}"

  # Generate .mcp.json at workspace root
  cat <<EOF > /workspace/.mcp.json
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "sse",
      "url": "${gateway_url}/sse"
    }
  }
}
EOF

  echo "✓ Generated /workspace/.mcp.json"

  # Poll gateway health endpoint with retry logic
  echo "Checking gateway health at ${gateway_url}/health..."
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --retry 15 --retry-delay 2 --retry-max-time 30 --retry-connrefused \
    "${gateway_url}/health" 2>&1 || echo "000")

  if [ "$http_code" = "200" ]; then
    echo "✓ Gateway is healthy"
  else
    echo "⚠ Warning: Gateway not ready (HTTP ${http_code})"
    echo "  Start: cd /workspace/claudehome/langfuse-local && docker compose up -d docker-mcp-gateway"
  fi

  echo ""
  echo "Config: /workspace/.mcp.json"
  echo "Gateway: ${gateway_url}"
  echo "Next: Restart Claude Code session to pick up MCP tools"
  echo "To add servers: Edit langfuse-local/mcp/mcp.json, restart gateway, then re-run mcp-setup"
}
SHELL_FUNCTION



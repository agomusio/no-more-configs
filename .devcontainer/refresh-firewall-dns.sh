#!/bin/bash
set -euo pipefail

if ! ipset list allowed-domains >/dev/null 2>&1; then
  echo "ERROR: ipset 'allowed-domains' not found. Run init-firewall.sh first."
  exit 1
fi

DOMAINS=(
  "registry.npmjs.org"
  "registry.npmjs.com"
  "api.anthropic.com"
  "sentry.io"
  "statsig.anthropic.com"
  "statsig.com"
  "marketplace.visualstudio.com"
  "gallerycdn.vsassets.io"
  "gallery.vsassets.io"
  "vsassets.io"
  "vscode.blob.core.windows.net"
  "deb.debian.org"
  "security.debian.org"
  "github.com"
  "objects.githubusercontent.com"
  "uploads.github.com"
  "codeload.github.com"
  "api.cloudflare.com"
  "dash.cloudflare.com"
  "workers.dev"
  "update.code.visualstudio.com"
  "storage.googleapis.com"
  "pypi.python.org"
  "pypi.org"
  "files.pythonhosted.org"
  "json.schemastore.org"
)

EXTRA_DOMAINS_FILE="/workspace/.devcontainer/firewall-domains.conf"
if [ -f "$EXTRA_DOMAINS_FILE" ]; then
  while IFS= read -r domain; do
    if [ -z "$domain" ] || [[ "$domain" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    DOMAINS+=("$domain")
  done < "$EXTRA_DOMAINS_FILE"
fi

resolve_domain() {
  local domain="$1"
  dig +noall +answer A "$domain" 2>/dev/null | awk '$4 == "A" {print $5}'
}
export -f resolve_domain

echo "Refreshing DNS for ${#DOMAINS[@]} firewall domains..."
resolved_ips=$(printf '%s\n' "${DOMAINS[@]}" | xargs -P 8 -I{} bash -c 'resolve_domain "$@"' _ {} | sort -u)

added=0
while read -r ip; do
  if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ipset add allowed-domains "$ip" -exist
    added=$((added + 1))
  fi
done <<< "$resolved_ips"

echo "Refreshed firewall DNS entries (${added} IPv4 addresses processed)."

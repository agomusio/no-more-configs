#!/bin/bash
set -euo pipefail

if ! ipset list allowed-domains >/dev/null 2>&1; then
  echo "ERROR: ipset 'allowed-domains' not found. Run init-firewall.sh first."
  exit 1
fi

DOMAINS_FILE="/workspace/.devcontainer/firewall-domains.conf"
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "ERROR: $DOMAINS_FILE not found. Run install-agent-config.sh first."
    exit 1
fi

DOMAINS=()
while IFS= read -r domain; do
    # Skip empty lines and comments
    if [ -z "$domain" ] || [[ "$domain" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    DOMAINS+=("$domain")
done < "$DOMAINS_FILE"

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

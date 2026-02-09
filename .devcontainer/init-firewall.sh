#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo ">>> Starting Firewall Configuration..."

# --- 1. PRE-FLIGHT CHECKS & VARIABLES ---

# Detect Host IP (WSL Gateway)
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")

echo "Host IP: $HOST_IP"
echo "Host Network: $HOST_NETWORK"

# Extract Docker DNS info (if any)
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# --- 2. RESET & CLEANUP ---

# Set default policies to ACCEPT temporarily (prevents lockout during script execution)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Flush all existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Destroy old ipsets
ipset destroy allowed-domains 2>/dev/null || true

# --- 3. INFRASTRUCTURE & DNS ---

# Restore Docker DNS resolution if it existed
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

# Allow Loopback (Critical)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS (UDP/TCP 53) - Outbound & Inbound responses
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# --- 4. HOST & DOCKER CONNECTIVITY (The Fix) ---

# 1. Allow Traffic to the Default Gateway (Routing)
iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT
iptables -A INPUT -s "$HOST_IP" -j ACCEPT

# 2. RESOLVE AND ALLOW "host.docker.internal" (The Magic IP)
# This is critical for Docker Desktop/WSL where the internal host IP differs from the gateway
echo "Resolving host.docker.internal..."
MAGIC_IP=$(dig +short host.docker.internal | tail -n1)

if [ -n "$MAGIC_IP" ]; then
    echo "  > Found Magic IP: $MAGIC_IP"
    iptables -A OUTPUT -d "$MAGIC_IP" -j ACCEPT
    iptables -A INPUT -s "$MAGIC_IP" -j ACCEPT
else
    echo "  > WARNING: Could not resolve host.docker.internal. Langfuse might fail."
    # Fallback: Allow the common Docker Desktop magic subnet just in case
    iptables -A OUTPUT -d 192.168.65.0/24 -j ACCEPT
    iptables -A INPUT -s 192.168.65.0/24 -j ACCEPT
fi

# 3. Allow Docker Bridge Subnet (Sibling containers)
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT

# 4. Allow the Host Network (WSL integration)
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# --- 5. STATEFUL TRACKING ---

# Allow Established/Related connections (CRITICAL for return traffic)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- 6. DOMAIN WHITELISTING (IPSet) ---

ipset create allowed-domains hash:net

# Fetch GitHub Meta
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: Failed to fetch valid GitHub meta data"
    exit 1
fi

echo "Processing GitHub IPs..."
# Add GitHub ranges
echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q | while read -r cidr; do
    ipset add allowed-domains "$cidr" -exist
done

# Resolve other domains
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "deb.debian.org" \
    "security.debian.org" \
    "github.com" \
    "objects.githubusercontent.com" \
    "api.cloudflare.com" \
    "update.code.visualstudio.com" \
    "storage.googleapis.com" \
    "pypi.python.org" \
    "json.schemastore.org" \
    "adventure-alerts-api.sam-ed4.workers.dev"; do
    
    echo "Resolving $domain..."
    dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}' | while read -r ip; do
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ipset add allowed-domains "$ip" -exist
        fi
    done
done

# Apply the Allow List
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# --- 7. LOCKDOWN & VERIFY ---

# Set Default Policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Reject anything else with ICMP error (faster debugging than silent DROP)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo ">>> Firewall Configured. Verifying..."

# Verification: Should Fail
if curl --connect-timeout 2 https://example.com >/dev/null 2>&1; then
    echo "❌ ERROR: Firewall failed - reached https://example.com"
    exit 1
else
    echo "✅ Success: Blocked https://example.com"
fi

# Verification: Should Pass
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "❌ ERROR: Firewall failed - blocked https://api.github.com"
    exit 1
else
    echo "✅ Success: Reached https://api.github.com"
fi

echo ">>> Firewall setup complete."
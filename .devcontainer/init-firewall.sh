#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Check if firewall is disabled via config.json
CONFIG_FILE="/workspace/config.json"
if [ -f "$CONFIG_FILE" ]; then
    FIREWALL_ENABLED=$(jq -r '.firewall.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
    if [ "$FIREWALL_ENABLED" = "false" ]; then
        echo ">>> Firewall disabled (config.json → firewall.enabled = false)"
        # Ensure all policies are ACCEPT (clean slate)
        iptables -P INPUT ACCEPT 2>/dev/null || true
        iptables -P FORWARD ACCEPT 2>/dev/null || true
        iptables -P OUTPUT ACCEPT 2>/dev/null || true
        iptables -F 2>/dev/null || true
        ip6tables -P INPUT ACCEPT 2>/dev/null || true
        ip6tables -P FORWARD ACCEPT 2>/dev/null || true
        ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
        ip6tables -F 2>/dev/null || true
        exit 0
    fi
fi

echo ">>> Starting Firewall Configuration..."

# --- 1. PRE-FLIGHT CHECKS & VARIABLES ---

CACHE_DIR="/var/cache/devcontainer-firewall"
GH_CACHE_FILE="$CACHE_DIR/github-meta.json"
CACHE_MAX_AGE=86400  # 24 hours

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

# --- 4. HOST & DOCKER CONNECTIVITY ---

iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT
iptables -A INPUT -s "$HOST_IP" -j ACCEPT

echo "Resolving host.docker.internal..."
MAGIC_IP=$(dig +short host.docker.internal | tail -n1)

if [ -n "$MAGIC_IP" ]; then
    echo "  > Found Magic IP: $MAGIC_IP"
    iptables -A OUTPUT -d "$MAGIC_IP" -j ACCEPT
    iptables -A INPUT -s "$MAGIC_IP" -j ACCEPT
else
    echo "  > WARNING: Could not resolve host.docker.internal. Langfuse might fail."
    iptables -A OUTPUT -d 192.168.65.0/24 -j ACCEPT
    iptables -A INPUT -s 192.168.65.0/24 -j ACCEPT
fi

iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# --- 5. STATEFUL TRACKING ---

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- 6. DOMAIN WHITELISTING (IPSet) ---

ipset create allowed-domains hash:net

mkdir -p "$CACHE_DIR"

cache_is_fresh() {
    [ -s "$GH_CACHE_FILE" ] && \
    [ "$(( $(date +%s) - $(stat -c %Y "$GH_CACHE_FILE") ))" -lt "$CACHE_MAX_AGE" ]
}

echo "Fetching GitHub IP ranges..."
if cache_is_fresh; then
    echo "  Using cached GitHub meta (age < 24h)"
    gh_ranges=$(cat "$GH_CACHE_FILE")
else
    if gh_new=$(curl --connect-timeout 5 --max-time 10 --retry 2 --retry-delay 1 \
                     -sf https://api.github.com/meta 2>/dev/null) && \
       echo "$gh_new" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
        echo "  Fetched fresh GitHub meta from API"
        printf '%s' "$gh_new" > "$GH_CACHE_FILE.tmp" && mv "$GH_CACHE_FILE.tmp" "$GH_CACHE_FILE"
        gh_ranges="$gh_new"
    elif [ -s "$GH_CACHE_FILE" ]; then
        echo "  WARN: GitHub API unreachable; using stale cached ranges"
        gh_ranges=$(cat "$GH_CACHE_FILE")
    else
        echo "ERROR: No GitHub ranges available (API failed + no cache)"
        exit 1
    fi
fi

echo "Processing GitHub IPs..."
echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q | while read -r cidr; do
    ipset add allowed-domains "$cidr" -exist
done

# NOTE: DNS-resolved IPs for CDN-backed domains can go stale after startup.
# A periodic refresh script is installed at /usr/local/bin/refresh-firewall-dns.sh.
# To refresh manually without restarting the container:
#   sudo /usr/local/bin/refresh-firewall-dns.sh
sudo /usr/local/bin/refresh-firewall-dns.sh

iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# --- 7. LOCKDOWN & VERIFY ---

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Reject anything else with ICMP error (faster debugging than silent DROP)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Locking down IPv6..."
ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true
ip6tables -P INPUT DROP 2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP 2>/dev/null || true
ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

echo ">>> Firewall Configured. Verifying..."

if curl --connect-timeout 2 --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall failed - reached https://example.com"
    exit 1
else
    echo "Success: Blocked https://example.com"
fi

if ! curl --connect-timeout 5 --max-time 10 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall failed - blocked https://api.github.com"
    exit 1
else
    echo "Success: Reached https://api.github.com"
fi

echo ">>> Firewall setup complete."

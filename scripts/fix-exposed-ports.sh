#!/bin/bash
# Restrict NPM admin (81, 3000) and Cockpit (9090) to LAN + Tailscale only.
# These are bound to 0.0.0.0 and already blocked by UFW's default deny, but
# this makes the restriction explicit so it survives rule reorders or resets.
# Run as: sudo bash /opt/homelab/scripts/fix-exposed-ports.sh
set -e

echo "=== Restricting NPM admin ports (81, 3000) and Cockpit (9090) ==="
echo ""

for PORT in 81 3000 9090; do
    # Allow from LAN first (must be before the deny rule)
    ufw insert 1 allow from 100.64.0.0/10 to any port $PORT proto tcp \
        comment "port $PORT - Tailscale only"
    ufw insert 1 allow from YOUR_LAN_SUBNET to any port $PORT proto tcp \
        comment "port $PORT - LAN only"
    # Explicit deny from everywhere else
    ufw deny $PORT/tcp \
        comment "port $PORT - block internet"
    echo "  ✓  Port $PORT: LAN + Tailscale only"
done

echo ""
echo "Current status:"
ufw status numbered | grep -E "81|3000|9090"

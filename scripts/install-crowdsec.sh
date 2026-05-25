#!/bin/bash
# Full CrowdSec install: agent + firewall bouncer + collections
# Run as: sudo bash /opt/homelab/scripts/install-crowdsec.sh [enrollment-key]
set -e

ENROLLMENT_KEY="${1:-}"

echo "=== CrowdSec Installation ==="
echo ""

# --- 1. Add apt repo ---
echo "[1/5] Adding CrowdSec apt repository..."
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash

# --- 2. Install agent ---
echo "[2/5] Installing CrowdSec agent..."
apt-get install -y crowdsec

systemctl enable crowdsec
systemctl start crowdsec

echo "Agent status:"
systemctl is-active crowdsec

# --- 3. Install firewall bouncer ---
echo ""
echo "[3/5] Installing firewall bouncer..."
apt-get install -y crowdsec-firewall-bouncer

systemctl enable crowdsec-firewall-bouncer
systemctl start crowdsec-firewall-bouncer

# --- 4. Install collections ---
echo ""
echo "[4/5] Installing collections..."
cscli hub update
cscli collections install crowdsecurity/linux
cscli collections install crowdsecurity/nginx
cscli collections install crowdsecurity/sshd
systemctl reload crowdsec

# --- 5. Cloud enrollment (optional) ---
echo ""
if [ -n "$ENROLLMENT_KEY" ]; then
    echo "[5/5] Enrolling with CrowdSec console..."
    cscli console enroll "$ENROLLMENT_KEY"
    systemctl restart crowdsec
    echo "Enrolled. Accept the engine in app.crowdsec.net if prompted."
else
    echo "[5/5] Skipping cloud enrollment (no key provided)."
    echo "      To enroll later: sudo cscli console enroll <key>"
fi

# --- Summary ---
echo ""
echo "=== Done ==="
cscli version
echo ""
echo "Bouncers:"
cscli bouncers list
echo ""
echo "Collections:"
cscli collections list
echo ""
echo "Bouncer service:"
systemctl status crowdsec-firewall-bouncer --no-pager | head -5

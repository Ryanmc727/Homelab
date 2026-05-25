#!/bin/bash
# Network security hardening: UFW firewall + CrowdSec firewall bouncer
# Run as: sudo bash /opt/homelab/scripts/secure-network.sh
set -e

echo "=== Homelab Network Security Setup ==="
echo ""

# ------- UFW FIREWALL -------
echo "[1/3] Configuring UFW firewall..."

# Install UFW if not present
apt-get install -y ufw > /dev/null 2>&1

# Reset to clean state (non-interactively)
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH - allow from anywhere as a safety net
ufw allow 22/tcp comment "SSH"

# Allow all traffic from local network
ufw allow from YOUR_LAN_SUBNET comment "LAN"

# Public-facing ports (for Nginx Proxy Manager)
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Transmission peer port
ufw allow 51413/tcp comment "Transmission TCP"
ufw allow 51413/udp comment "Transmission UDP"

# Enable UFW non-interactively
ufw --force enable

echo "UFW enabled. Status:"
ufw status verbose

echo ""

# ------- CROWDSEC AGENT -------
echo "[2/3] Installing CrowdSec agent + firewall bouncer..."

curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt-get install -y crowdsec crowdsec-firewall-bouncer > /dev/null 2>&1

systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

echo ""
echo "[3/3] Installing CrowdSec community collections..."
cscli hub update
cscli collections install crowdsecurity/linux
cscli collections install crowdsecurity/nginx
cscli collections install crowdsecurity/sshd

systemctl reload crowdsec

echo ""
echo "=== Security setup complete ==="
echo ""
echo "Verify with:"
echo "  sudo ufw status verbose"
echo "  sudo systemctl status crowdsec crowdsec-firewall-bouncer"
echo "  sudo cscli bouncers list"
echo "  sudo cscli decisions list"
echo ""
echo "To enroll in the cloud console:"
echo "  sudo cscli console enroll <key-from-app.crowdsec.net>"

#!/bin/bash
# Homelab Security Hardening — run with sudo
# Installs fail2ban + hardens SSH
set -e

echo "=== Installing fail2ban (SSH brute-force protection) ==="
apt-get update -q
apt-get install -y fail2ban --no-install-recommends

# Configure fail2ban for SSH
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 5
bantime  = 24h
EOF

systemctl enable --now fail2ban
echo "fail2ban active — SSH IPs banned after 5 failures in 10 min, 24h ban"

echo ""
echo "=== Hardening SSH configuration ==="
# Backup original
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

# Apply hardening
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 4/' /etc/ssh/sshd_config
sed -i 's/#LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

# Add if not present
grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers your-username" >> /etc/ssh/sshd_config

systemctl reload sshd
echo "SSH hardened: no root login, 4 auth tries max, 30s grace period"

echo ""
echo "=== Setting up UFW firewall ==="
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp   # NPM HTTP
ufw allow 443/tcp  # NPM HTTPS
ufw allow 81/tcp   # NPM Admin (restrict later)
ufw allow 53/tcp   # Pi-hole DNS
ufw allow 53/udp   # Pi-hole DNS
ufw allow from YOUR_LAN_SUBNET to any  # Full LAN access
ufw allow from 100.64.0.0/10 to any   # Tailscale
ufw --force enable
echo "UFW active"

echo ""
echo "=== Done! Security hardening applied ==="
echo "  - fail2ban: SSH ban after 5 failures (24h ban)"
echo "  - SSH: no root login, max 4 attempts, 30s grace"
echo "  - UFW: deny all incoming except SSH, HTTP, HTTPS, DNS, LAN, Tailscale"

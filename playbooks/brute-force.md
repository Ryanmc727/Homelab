# Brute Force Attack — Response Playbook

> **Trigger:** Grafana "SSH Brute Force >5 in 10min" alert, or Pi-hole showing repeated auth attempts  
> **Goal:** Block attacker, verify no successful login, document.

---

## Step 1 — Confirm and identify the attacker

```bash
# Who's hammering SSH?
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -rn | head -20

# Or from Suricata if it's more than SSH
docker exec suricata grep '"signature":".*[Bb]rute"' /var/log/suricata/eve.json \
  | python3 -c "import sys,json; [print(json.loads(l).get('src_ip')) for l in sys.stdin if l.strip()]" \
  | sort | uniq -c | sort -rn | head -10

# Get attacker details
ATTACKER_IP="<paste IP here>"
whois $ATTACKER_IP | grep -i "org\|country\|netname\|abuse"
```

---

## Step 2 — Block immediately

```bash
# Add to Homelab block chain
sudo iptables -A HOMELAB-BLOCK -s $ATTACKER_IP -j DROP

# Verify
sudo iptables -L HOMELAB-BLOCK -n | grep $ATTACKER_IP

# Log the block
echo "$(date)  MANUAL-BLOCK  $ATTACKER_IP  reason=ssh-brute-force" \
  | sudo tee -a /var/log/homelab-blocks.log
```

---

## Step 3 — Check for successful logins

```bash
# Any successful auth from that IP?
grep "Accepted" /var/log/auth.log | grep $ATTACKER_IP

# Check last logins (all users)
last | head -30

# Active sessions right now
who
w

# Check for new users or sudoers changes
lastmod /etc/passwd 2>/dev/null || stat /etc/passwd
sudo cat /etc/sudoers.d/*
```

---

## Step 4 — If a successful login is found

This is an incident. Follow these steps immediately:

```bash
# Kill active session
# Find the session PID
ps aux | grep sshd
sudo kill -9 <session_pid>

# Change all credentials
passwd <your_username>
# Rotate SSH keys: revoke attacker's key from ~/.ssh/authorized_keys

# Check for persistence
# New cron jobs?
crontab -l
sudo crontab -l
sudo cat /etc/cron.d/*

# New SSH authorized keys added?
cat ~/.ssh/authorized_keys

# New systemd services?
systemctl list-units --state=failed
find /etc/systemd/system -newer /var/log/auth.log -name "*.service" 2>/dev/null

# Unusual processes?
ps auxf | grep -v "\[" | grep -v "^root.*ps"

# Network connections to unknown external IPs?
ss -tnp | grep ESTAB
```

---

## Step 5 — Harden and document

```bash
# Make block permanent (survives reboot)
sudo apt install -y iptables-persistent
sudo netfilter-persistent save

# Add to fail2ban if not already catching this class
sudo fail2ban-client status sshd

# Document in incident log
echo "$(date) | SSH-BRUTE-FORCE | $ATTACKER_IP | BLOCKED | iptables + verified no successful login" \
  >> /opt/homelab/playbooks/incidents.log
```

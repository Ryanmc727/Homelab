# P1 Suricata Alert — Triage Playbook

> **Trigger:** Grafana fires "Suricata P1" alert → ntfy push to homelab-alerts  
> **Goal:** Determine if it's a real attack within 5 minutes, take action, document.

---

## Step 1 — Get context (60 seconds)

```bash
# What fired and from where?
docker exec suricata grep '"severity":1' /var/log/suricata/eve.json \
  | tail -20 | python3 -m json.tool | grep -E "timestamp|signature|src_ip|dest_ip|dest_port"

# Check auto-block log — was anything already blocked?
cat /var/log/homelab-blocks.log | tail -20

# Check EveBox for full alert context
open https://evebox.yourdomain.com
```

---

## Step 2 — Classify the source IP

**External IP (not 192.168.0.x):**
- High likelihood of real attack → auto-block daemon should have already blocked it
- Verify: `sudo iptables -L HOMELAB-BLOCK -n`
- If not blocked: `sudo iptables -A HOMELAB-BLOCK -s <IP> -j DROP`
- Look up the IP: `whois <IP>` or check [ipinfo.io](https://ipinfo.io)

**Internal LAN IP (192.168.0.x):**
- Much more serious — a device inside the network is behaving maliciously
- Cross-reference with known devices in ops/main.py KNOWN_DEVICES
- **Do NOT auto-block** — isolate instead (see below)
- Check what that device has been querying in Pi-hole

```bash
# DNS history for suspect IP in pihole
docker exec pihole grep "192.168.0.X" /var/log/pihole/pihole.log | grep "query\[" | tail -50
```

---

## Step 3 — Check blast radius

```bash
# Did the attacker reach anything?
docker exec suricata grep '"src_ip":"<ATTACKER_IP>"' /var/log/suricata/eve.json \
  | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        e=json.loads(line)
        print(e.get('timestamp','')[:19], e.get('event_type'), e.get('dest_ip'), e.get('dest_port'))
    except: pass
" | sort -u

# Check for any successful connections (flow.state = established)
docker exec suricata grep '"src_ip":"<ATTACKER_IP>"' /var/log/suricata/eve.json \
  | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        e=json.loads(line)
        if e.get('event_type')=='flow' and e.get('flow',{}).get('state')=='closed':
            print(e)
    except: pass
"
```

---

## Step 4 — Isolate (if internal source)

```bash
# Temporarily block a LAN device's traffic at the host level
sudo iptables -A HOMELAB-BLOCK -s 192.168.0.X -j DROP

# Or isolate at the router — log into TP-Link and block the MAC
# Router: YOUR_ROUTER_IP
```

---

## Step 5 — Document and notify

```bash
# Add a suppression if this is a false positive
# Edit /opt/homelab/suricata/config/threshold.conf
# Format: suppress gen_id 1, sig_id <SID>, track by_src, ip <IP>
# Then: docker exec suricata suricatasc -c reload-rules
```

Record the incident in `/opt/homelab/playbooks/incidents.log`:
```
DATE | ALERT | SRC_IP | DISPOSITION | ACTION_TAKEN
```

---

## Quick reference

| IP type | Auto-blocked? | Action |
|---|---|---|
| External, hits honeypot | ✅ Yes | Verify block, document |
| External, P1 alert | ✅ Yes | Verify block, check blast radius |
| Internal, hits honeypot | ❌ No | Alert fired, manual isolation |
| Internal, P1 alert | ❌ No | Investigate device, isolate if needed |

**Useful dashboards:**
- EveBox: https://evebox.yourdomain.com
- Grafana: https://grafana.yourdomain.com → Suricata IDS dashboard
- Pi-hole: https://pihole.yourdomain.com

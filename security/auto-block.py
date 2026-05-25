#!/usr/bin/env python3
"""
Homelab Auto-Block Daemon
Watches Suricata eve.json for P1 alerts and honeypot hits.
External IPs → iptables block + ntfy alert.
Internal IPs  → ntfy alert only (never auto-block LAN).

Run as root via systemd: auto-block.service
"""

import json
import time
import logging
import subprocess
import ipaddress
import urllib.request
import base64
from pathlib import Path
from datetime import datetime

EVE_LOG    = "/var/log/suricata/eve.json"
BLOCK_LOG  = "/var/log/homelab-blocks.log"
CHAIN      = "GULFWAVE-BLOCK"
NTFY_URL   = os.getenv("NTFY_URL",      "http://127.0.0.1:3004/homelab-alerts")
NTFY_USER  = os.getenv("NTFY_USER",    "")
NTFY_PASS  = os.getenv("NTFY_PASS",    "")
HONEYPOT   = os.getenv("HONEYPOT_IP",  "YOUR_HONEYPOT_IP")

# Subnets that should NEVER be auto-blocked
WHITELIST = [
    ipaddress.ip_network("YOUR_LAN_SUBNET"),   # LAN
    ipaddress.ip_network("10.0.0.0/8"),        # Private
    ipaddress.ip_network("172.16.0.0/12"),     # Private
    ipaddress.ip_network("127.0.0.0/8"),       # Loopback
    ipaddress.ip_network("100.64.0.0/10"),     # Tailscale
    ipaddress.ip_network("224.0.0.0/4"),       # Multicast
]

blocked_ips: set[str] = set()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("auto-block")


def is_internal(ip_str: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip_str)
        return any(addr in net for net in WHITELIST)
    except ValueError:
        return True


def iptables_chain_ready():
    """Ensure GULFWAVE-BLOCK chain exists and is referenced from INPUT."""
    subprocess.run(["iptables", "-N", CHAIN], capture_output=True)
    r = subprocess.run(
        ["iptables", "-C", "INPUT", "-j", CHAIN],
        capture_output=True
    )
    if r.returncode != 0:
        subprocess.run(["iptables", "-I", "INPUT", "1", "-j", CHAIN], check=True)
    log.info(f"iptables chain {CHAIN} ready")


def block_ip(ip: str, reason: str):
    if ip in blocked_ips:
        return
    blocked_ips.add(ip)

    result = subprocess.run(
        ["iptables", "-A", CHAIN, "-s", ip, "-j", "DROP"],
        capture_output=True, text=True
    )
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if result.returncode == 0:
        entry = f"{ts}  BLOCKED  {ip}  reason={reason}\n"
        log.warning(f"BLOCKED {ip} — {reason}")
    else:
        entry = f"{ts}  BLOCK_FAILED  {ip}  reason={reason}  err={result.stderr.strip()}\n"
        log.error(f"iptables failed for {ip}: {result.stderr.strip()}")

    Path(BLOCK_LOG).parent.mkdir(parents=True, exist_ok=True)
    with open(BLOCK_LOG, "a") as f:
        f.write(entry)

    send_ntfy(
        title=f"🚫 AUTO-BLOCKED: {ip}",
        message=f"IP blocked via iptables\nReason: {reason}\nChain: {CHAIN}\nTime: {ts}",
        priority="high",
        tags="no_entry,auto-block",
    )


def send_ntfy(title: str, message: str, priority: str = "high", tags: str = "warning"):
    creds = base64.b64encode(f"{NTFY_USER}:{NTFY_PASS}".encode()).decode()
    req = urllib.request.Request(
        NTFY_URL,
        data=message.encode(),
        headers={
            "Title":         title,
            "Priority":      priority,
            "Tags":          tags,
            "Authorization": f"Basic {creds}",
        },
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        log.error(f"ntfy failed: {e}")


def alert_only(title: str, message: str):
    """Alert without blocking — for LAN/internal IPs."""
    send_ntfy(title, message, priority="high", tags="warning,internal")


def process_event(event: dict):
    etype = event.get("event_type")
    if etype != "alert":
        return

    alert    = event.get("alert", {})
    severity = alert.get("severity", 99)  # 1 = P1 (highest)
    sig      = alert.get("signature", "")
    src_ip   = event.get("src_ip", "")
    dst_ip   = event.get("dest_ip", "")
    dst_port = event.get("dest_port", "?")
    ts       = event.get("timestamp", "")[:19]

    # Only act on P1 (severity=1) or honeypot hits
    is_honeypot_hit = dst_ip == HONEYPOT
    is_p1           = severity == 1

    if not (is_p1 or is_honeypot_hit):
        return

    if not src_ip:
        return

    internal = is_internal(src_ip)
    reason = f"P1 Suricata alert: {sig}" if is_p1 else f"Honeypot hit on port {dst_port}"

    if internal:
        # Never auto-block LAN — alert and investigate manually
        alert_only(
            title=f"⚠️ INTERNAL THREAT: {src_ip}",
            message=(
                f"LAN device triggered a {reason}\n"
                f"Source: {src_ip} → {dst_ip}:{dst_port}\n"
                f"Signature: {sig}\n"
                f"Time: {ts}\n"
                f"Action: Manual investigation required — see playbook"
            ),
        )
        log.warning(f"Internal threat from {src_ip}: {sig}")
    else:
        # External IP — auto-block immediately
        block_ip(src_ip, reason)


def tail_eve(path: str):
    p = Path(path)
    log.info(f"Waiting for {path}")
    while not p.exists():
        time.sleep(3)

    log.info("Tailing eve.json for P1 alerts and honeypot hits")
    with open(path) as fh:
        fh.seek(0, 2)
        while True:
            line = fh.readline()
            if line:
                try:
                    process_event(json.loads(line.strip()))
                except (json.JSONDecodeError, Exception) as e:
                    log.debug(f"Skipped line: {e}")
            else:
                time.sleep(0.25)


if __name__ == "__main__":
    log.info("Homelab Auto-Block Daemon starting")
    iptables_chain_ready()
    tail_eve(EVE_LOG)

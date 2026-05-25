#!/usr/bin/env python3
"""
Tails OpenCanary's JSON log and sends ntfy push alerts for every hit.
Runs alongside opencanaryd inside the honeypot container.
"""
import json
import time
import logging
import os
import requests
from pathlib import Path

LOG_FILE  = os.getenv("NTFY_LOG_FILE",  "/var/log/opencanary/opencanary.log")
NTFY_URL  = os.getenv("NTFY_URL",       "https://ntfy.example.com/homelab-alerts")
NTFY_USER = os.getenv("NTFY_USER",      "")
NTFY_PASS = os.getenv("NTFY_PASS",      "")

# OpenCanary logtype int → human label + emoji
LOGTYPES = {
    1000: ("SSH",    "🔐"),
    1001: ("SSH",    "🔐"),
    2000: ("FTP",    "📁"),
    3000: ("HTTP",   "🌐"),
    3001: ("HTTP",   "🌐"),
    4000: ("MySQL",  "🗄️"),
    5000: ("Telnet", "📺"),
    6000: ("Redis",  "🔴"),
    7000: ("SMB",    "📂"),
    8000: ("VNC",    "🖥️"),
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("notifier")


def send_alert(event: dict) -> None:
    logtype  = event.get("logtype", 0)
    src_ip   = event.get("src_host", "unknown")
    src_port = event.get("src_port", "?")
    dst_port = event.get("dst_port", "?")
    ts       = event.get("local_time", "unknown time")
    logdata  = event.get("logdata", {})

    svc_name, emoji = LOGTYPES.get(logtype, ("Unknown", "⚠️"))

    # Build a human-readable detail line from logdata if present
    details = ""
    if isinstance(logdata, dict):
        if "USERNAME" in logdata:
            details += f"\nUsername tried: {logdata['USERNAME']}"
        if "PASSWORD" in logdata:
            details += f"\nPassword tried: {logdata['PASSWORD']}"
        if "HOSTNAME" in logdata:
            details += f"\nHostname: {logdata['HOSTNAME']}"
        if "CMD" in logdata:
            details += f"\nCommand: {logdata['CMD']}"

    title   = f"🍯 HONEYPOT HIT — {emoji} {svc_name}"
    message = (
        f"Attacker:  {src_ip}:{src_port}\n"
        f"Service:   {svc_name} (port {dst_port})\n"
        f"Time:      {ts}"
        f"{details}"
    )

    try:
        resp = requests.post(
            NTFY_URL,
            auth=(NTFY_USER, NTFY_PASS),
            headers={
                "Title":    title,
                "Priority": "high",
                "Tags":     "rotating_light,honeypot",
            },
            data=message.encode("utf-8"),
            timeout=15,
        )
        resp.raise_for_status()
        log.info(f"Alert sent → {src_ip} hit {svc_name}:{dst_port}")
    except Exception as exc:
        log.error(f"ntfy POST failed: {exc}")


def tail_log(path: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)

    log.info(f"Waiting for log file: {path}")
    while not p.exists():
        time.sleep(2)

    log.info("Log file found — tailing for events")
    with open(path) as fh:
        fh.seek(0, 2)          # jump to end, ignore historical events
        while True:
            line = fh.readline()
            if line:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    send_alert(event)
                except json.JSONDecodeError:
                    log.warning(f"Non-JSON line skipped: {line[:80]}")
                except Exception as exc:
                    log.error(f"Unhandled error processing event: {exc}")
            else:
                time.sleep(0.3)


if __name__ == "__main__":
    tail_log(LOG_FILE)

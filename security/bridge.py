#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, urllib.request, base64, logging, threading, time

import os
NTFY_URL      = os.environ.get("NTFY_URL",  "http://ntfy/homelab-alerts")
NTFY_USER     = os.environ.get("NTFY_USER", "")
NTFY_PASS     = os.environ.get("NTFY_PASS", "")
HOLD_SECONDS  = 90    # wait this long before sending ntopng alerts
COOLDOWN      = 600   # don't re-notify the same alert within 10 minutes

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

# { alert_key: {"data": ..., "first_seen": t, "last_seen": t, "timer": ...} }
pending  = {}
sent_at  = {}  # alert_key -> last sent timestamp
lock     = threading.Lock()

def send_ntfy(title, message, priority="default", tag="bell"):
    creds = base64.b64encode(f"{NTFY_USER}:{NTFY_PASS}".encode()).decode()
    req = urllib.request.Request(
        NTFY_URL,
        data=message.encode(),
        headers={
            "Title":         title,
            "Priority":      priority,
            "Tags":          tag,
            "Authorization": f"Basic {creds}",
        },
    )
    urllib.request.urlopen(req)

def _fire(key):
    with lock:
        entry = pending.pop(key, None)
        if not entry:
            return
        # If alert hasn't been seen in last 30s it already resolved — drop it
        if time.time() - entry["last_seen"] > 30:
            logging.info(f"ntopng → resolved before hold expired, dropped: {key}")
            return
        # Respect cooldown — don't spam the same alert
        last = sent_at.get(key, 0)
        if time.time() - last < COOLDOWN:
            logging.info(f"ntopng → cooldown active, suppressed: {key}")
            return
        sent_at[key] = time.time()

    d = entry["data"]
    send_ntfy(d["title"], d["message"], d["priority"], d["tag"])
    logging.info(f"ntopng → ntfy (held {HOLD_SECONDS}s): {key}")

def queue_ntopng_alert(key, title, message, priority, tag):
    with lock:
        now = time.time()
        if key in pending:
            pending[key]["last_seen"] = now
            return  # timer already running
        # New alert — start hold timer
        t = threading.Timer(HOLD_SECONDS, _fire, args=[key])
        t.daemon = True
        pending[key] = {
            "data":       {"title": title, "message": message,
                           "priority": priority, "tag": tag},
            "first_seen": now,
            "last_seen":  now,
            "timer":      t,
        }
        t.start()
        logging.info(f"ntopng → holding {HOLD_SECONDS}s: {key}")

class Bridge(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        try:
            length  = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length))
            if self.path == "/ntopng":
                self._handle_ntopng(payload)
            else:
                self._handle_grafana(payload)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        except Exception as e:
            logging.error(f"Error: {e}")
            self.send_response(500)
            self.end_headers()

    def _handle_grafana(self, payload):
        for alert in payload.get("alerts", []):
            status = alert.get("status")
            if status not in ("firing", "resolved"):
                continue

            labels   = alert.get("labels", {})
            ann      = alert.get("annotations", {})
            alertname = labels.get("alertname", "Alert")
            title     = alert.get("title", alertname)

            # Skip infrastructure errors — they're not real security events
            if alertname in ("DatasourceError", "DatasourceNoData") or "Error" in alertname:
                logging.info(f"Grafana → skipped infra alert: {alertname}")
                continue

            if status == "resolved":
                send_ntfy(f"✅ RESOLVED: {alertname}", "Alert has cleared.", "low", "white_check_mark")
                logging.info(f"Grafana → ntfy resolved: {alertname}")
                continue

            severity = labels.get("severity", "high")
            priority = "urgent" if severity in ("critical", "high") else "default"
            tag      = "rotating_light" if priority == "urgent" else "warning"

            # Build a rich message body
            summary = ann.get("summary", "")
            parts   = []
            if summary:
                parts.append(summary)
            # Include evaluated values when present (e.g. count of matches)
            values = alert.get("values") or {}
            if values:
                val_str = ", ".join(f"{k}={v}" for k, v in values.items() if v not in (None, ""))
                if val_str:
                    parts.append(f"Value: {val_str}")
            # Include generator URL for quick drill-down
            gen_url = alert.get("generatorURL", "")
            if gen_url:
                parts.append(f"Grafana: {gen_url}")

            message = "\n".join(parts) if parts else alertname
            send_ntfy(alertname, message, priority, tag)
            logging.info(f"Grafana → ntfy: {alertname} [{priority}]")

    def _handle_ntopng(self, payload):
        for alert in payload.get("alerts", []):
            name     = alert.get("alert_name",  alert.get("name", "ntopng Alert"))
            msg      = alert.get("msg",          alert.get("description", ""))
            severity = alert.get("severity",     "")
            src      = alert.get("ip",           alert.get("cli_ip", alert.get("srv_ip", "")))
            score    = int(alert.get("score",    alert.get("alert_score", 0)))

            if score < 75:
                logging.info(f"ntopng → suppressed (score {score}): {name}")
                continue

            benign = [
                "probing attempt", "tcp connection issues",
                "web mining", "connectivity check", "dns invalid chars",
            ]
            if any(b in name.lower() for b in benign):
                logging.info(f"ntopng → suppressed (benign): {name}")
                continue

            parts = [msg] if msg else [name]
            if src:
                parts.append(f"Host: {src}")
            message  = " | ".join(parts) or name
            priority = "high" if "critical" in str(severity).lower() or "error" in str(severity).lower() else "default"
            tag      = "rotating_light" if priority == "high" else "warning"
            key      = f"{name}|{src}"

            queue_ntopng_alert(key, f"ntopng: {name}", message, priority, tag)

HTTPServer(("", 8080), Bridge).serve_forever()

# Home Lab

---

## Architecture

```
Internet
    │
    ▼
Router (WiFi 7)
    │
    ├── Homelab Server (Ubuntu 24, bare metal)
    │       ├── Reverse Proxy   (Nginx Proxy Manager — single external entry point)
    │       ├── IDS             (Suricata → EveBox → Grafana dashboards)
    │       ├── DNS + Blocking  (Pi-hole → DNSCrypt-Proxy → Cloudflare DoH)
    │       ├── Honeypot        (OpenCanary — decoy SSH/FTP/HTTP/MySQL/Redis)
    │       ├── Monitoring      (Netdata, Grafana, Loki, Promtail, Uptime Kuma)
    │       ├── SSO             (Authentik)
    │       ├── Traffic Intel   (ntopng)
    │       └── Alerts          (ntfy self-hosted push notifications)
    │
    ├── WiFi 6 AP (wired Ethernet backhaul)
    └── 30+ LAN devices (categorised: PER / WORK / IOT / LAB / NET)
```

---

## Stack

| Category | Services |
|---|---|
| **Security / IDS** | Suricata (af-packet on NIC), EveBox, OpenCanary honeypot, auto-block daemon |
| **DNS** | Pi-hole (280k+ blocked domains) → DNSCrypt-Proxy → Cloudflare DoH |
| **Observability** | Grafana, Loki, Promtail, Netdata, ntopng, Uptime Kuma |
| **Infrastructure** | Nginx Proxy Manager, Portainer, Watchtower, Authentik SSO |
| **Notifications** | ntfy (self-hosted), Grafana alerting, custom webhook bridge |
| **Lab** | Kali Linux (containerised desktop) |
| **Ops API** | FastAPI — ARP scanning, Suricata alert aggregation, Pi-hole control, AI assistant → [homelab-ops](https://github.com/Ryanmc727/homelab-ops) |

All services run in Docker, managed via a single `docker-compose.yml`.

---

## Security Features

**Suricata IDS** monitors raw packets directly on the physical interface. Alerts flow to EveBox for browsing and Grafana for dashboards and alerting.

**OpenCanary honeypot** sits at a decoy IP on the LAN, advertising fake SSH, FTP, HTTP, MySQL, Redis, and Telnet services. Every connection triggers an instant push notification.

**Auto-block daemon** (`security/auto-block.py`) tails `eve.json` in real time. External IPs triggering P1 alerts or honeypot hits are immediately blocked via iptables. LAN/internal IPs are never auto-blocked — alert only with a manual investigation prompt.

**Encrypted DNS chain** — all DNS queries exit the network encrypted via DNS-over-HTTPS. Pi-hole blocklists prevent ad, malware, and phishing domains at the resolver level.

**SSO via Authentik** — all internal dashboards sit behind single sign-on.

**Incident response playbooks** — documented runbooks in `playbooks/` for P1 Suricata alerts, SSH brute force, and unknown device detection.

---

## Monitoring Dashboards

| Dashboard | What it shows |
|---|---|
| Suricata IDS | Alert timeline, top signatures, P1/P2/P3 counts, source IP heatmap |
| Server Security | SSH logins, sudo events, failed auth attempts, syslog error rate |
| Uptime Kuma | 11 service monitors with ntfy push alerting |
| Netdata | Real-time CPU, memory, network, disk metrics |

---

## Repo Layout

```
containers/     docker-compose.yml (full stack) and legacy docker-run reference
honeypot/       OpenCanary build — Dockerfile, config, ntfy notifier script
playbooks/      Incident response runbooks (P1 alert, brute force, unknown device)
scripts/        Security hardening, snapshot backup, port audit utilities
security/       Auto-block daemon, Grafana→ntfy webhook bridge
monitoring/     Loki config
homepage/       Homepage dashboard config
```

The ops dashboard lives in its own repo: [homelab-ops](https://github.com/Ryanmc727/homelab-ops)

---

## Setup

```bash
git clone https://github.com/Ryanmc727/Homelab.git
cp .env.example .env          # fill in your values
docker compose -f containers/docker-compose.yml up -d
sudo bash scripts/security-hardening.sh
```

See `.env.example` for all required environment variables.

> Network-specific values (IPs, domain names) in configs are examples — replace with your own.

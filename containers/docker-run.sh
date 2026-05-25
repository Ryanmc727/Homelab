#!/bin/bash
# Homelab — Docker container rebuild commands
# Run these in order to recreate all containers from scratch
# Set HOMELAB_DIR to your data directory before running

HOMELAB_DIR="${HOMELAB_DIR:-/opt/homelab}"

# ---- Infrastructure ----
docker run -d --name homepage --restart unless-stopped --network host \
  -e PORT=3001 \
  -e HOMEPAGE_ALLOWED_HOSTS=localhost,127.0.0.1 \
  -v "${HOMELAB_DIR}/homepage/config:/app/config" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  ghcr.io/gethomepage/homepage:latest

docker run -d --name nginx-proxy-manager --restart unless-stopped --network host \
  -v "${HOMELAB_DIR}/npm/data:/data" \
  -v "${HOMELAB_DIR}/npm/letsencrypt:/etc/letsencrypt" \
  jc21/nginx-proxy-manager:latest

docker run -d --name portainer --restart unless-stopped \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/var/data \
  portainer/portainer-ce:latest

docker run -d --name netdata --restart unless-stopped \
  -p 19999:19999 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  netdata/netdata:latest

# ---- Security ----
docker run -d --name suricata --restart unless-stopped \
  --network host --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_NICE \
  -v "${HOMELAB_DIR}/suricata/logs:/var/log/suricata" \
  -v "${HOMELAB_DIR}/suricata/rules:/var/lib/suricata" \
  -v "${HOMELAB_DIR}/suricata/run:/var/run/suricata" \
  jasonish/suricata:latest -i eth0

docker network create monitoring 2>/dev/null || true

docker run -d --name loki --restart unless-stopped \
  --network monitoring -p 3100:3100 \
  -v "${HOMELAB_DIR}/loki/config:/etc/loki" \
  -v "${HOMELAB_DIR}/loki/data:/loki" \
  grafana/loki:latest -config.file=/etc/loki/loki.yaml

docker run -d --name grafana --restart unless-stopped \
  --network monitoring -p 3003:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=YOUR_GRAFANA_PASSWORD \
  -v "${HOMELAB_DIR}/grafana/data:/var/lib/grafana" \
  grafana/grafana:latest

docker run -d --name promtail --restart unless-stopped \
  --network monitoring \
  -v "${HOMELAB_DIR}/promtail:/etc/promtail" \
  -v "${HOMELAB_DIR}/suricata/logs:/var/log/suricata:ro" \
  -v /var/log:/var/log/host:ro \
  grafana/promtail:latest -config.file=/etc/promtail/config.yaml

docker run -d --name grafana-ntfy --restart unless-stopped \
  --network monitoring -p 8585:8080 \
  grafana-ntfy-bridge

docker run -d --name ntfy --restart unless-stopped \
  -p 3004:80 \
  -v "${HOMELAB_DIR}/ntfy:/var/lib/ntfy" \
  binwiederhier/ntfy serve --config /var/lib/ntfy/server.yml

docker run -d --name uptime-kuma --restart unless-stopped \
  -p 3002:3001 \
  -v "${HOMELAB_DIR}/uptime-kuma/data:/app/data" \
  louislam/uptime-kuma:latest

# ---- Network ----
docker run -d --name ntopng --restart unless-stopped \
  --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  -v "${HOMELAB_DIR}/ntopng/data:/var/lib/ntopng" \
  ntop/ntopng --interface=eth0 --http-port=3005 --community

# ---- Tools ----
docker run -d --name kali_desktop --restart "no" \
  -p 3008:3000 \
  --cap-add NET_RAW --cap-add NET_ADMIN --cap-add SYS_PTRACE \
  -v "${HOMELAB_DIR}/kali/config:/config" \
  lscr.io/linuxserver/kali-linux:latest

docker run -d --name watchtower --restart unless-stopped \
  -e WATCHTOWER_CLEANUP=true \
  -e WATCHTOWER_SCHEDULE="0 0 3 * * *" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower

#!/bin/bash
# Homelab configuration snapshot — backs up all service configs and container metadata
# Usage: bash snapshot.sh [output-dir]

set -e

HOMELAB_DIR="${HOMELAB_DIR:-/opt/homelab}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${1:-${HOMELAB_DIR}/snapshots}/snapshot_${TIMESTAMP}"

echo "=== Homelab Snapshot: ${TIMESTAMP} ==="
echo "Destination: ${BACKUP_DIR}"
echo ""

mkdir -p "${BACKUP_DIR}"

# ------- CONFIG DIRECTORIES -------
echo "[1/3] Copying config directories..."

CONFIGS=(
    "${HOMELAB_DIR}/homepage/config:homepage"
    "${HOMELAB_DIR}/npm/data:npm-data"
    "${HOMELAB_DIR}/npm/letsencrypt:npm-letsencrypt"
    "${HOMELAB_DIR}/uptime-kuma/data:uptime-kuma"
    "${HOMELAB_DIR}/suricata/config:suricata-config"
    "${HOMELAB_DIR}/loki/config:loki-config"
    "${HOMELAB_DIR}/promtail:promtail"
    "${HOMELAB_DIR}/grafana/data:grafana-data"
    "${HOMELAB_DIR}/pihole/etc-pihole:pihole-etc"
    "${HOMELAB_DIR}/pihole/etc-dnsmasq.d:pihole-dnsmasq"
    "${HOMELAB_DIR}/ntfy:ntfy"
    "${HOMELAB_DIR}/evebox:evebox"
)

for entry in "${CONFIGS[@]}"; do
    src="${entry%%:*}"
    name="${entry##*:}"
    if [ -d "$src" ]; then
        cp -r "$src" "${BACKUP_DIR}/${name}"
        echo "  ✓ ${name}"
    else
        echo "  - ${name} (not found, skipping)"
    fi
done

cp "${HOMELAB_DIR}/docker-compose.yml" "${BACKUP_DIR}/docker-compose.yml" 2>/dev/null && echo "  ✓ docker-compose.yml" || true

# ------- DOCKER CONTAINER METADATA -------
echo ""
echo "[2/3] Exporting Docker container configs..."

mkdir -p "${BACKUP_DIR}/docker"

CONTAINERS=(
    nginx-proxy-manager suricata evebox pihole loki promtail grafana
    grafana-ntfy ntfy ntopng netdata homepage uptime-kuma
    watchtower portainer homelab-ops
)

for c in "${CONTAINERS[@]}"; do
    if docker inspect "$c" > /dev/null 2>&1; then
        docker inspect "$c" > "${BACKUP_DIR}/docker/${c}.json"
        echo "  ✓ ${c}"
    fi
done

# ------- COMPRESS -------
echo ""
echo "[3/3] Compressing snapshot..."

ARCHIVE="${HOMELAB_DIR}/snapshots/snapshot_${TIMESTAMP}.tar.gz"
mkdir -p "${HOMELAB_DIR}/snapshots"
tar -czf "${ARCHIVE}" -C "$(dirname ${BACKUP_DIR})" "$(basename ${BACKUP_DIR})"
rm -rf "${BACKUP_DIR}"

SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
echo ""
echo "=== Snapshot complete ==="
echo "Archive: ${ARCHIVE} (${SIZE})"

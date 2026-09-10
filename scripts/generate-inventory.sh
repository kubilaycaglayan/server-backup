#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_root
load_config

OUTPUT_DIR="${1:-}"
[[ -n "$OUTPUT_DIR" ]] || die "Usage: generate-inventory.sh OUTPUT_DIRECTORY"
mkdir -p "$OUTPUT_DIR"

dpkg-query -W -f='${binary:Package}\t${Version}\n' >"$OUTPUT_DIR/dpkg-packages.tsv"
apt-mark showmanual >"$OUTPUT_DIR/apt-manual-packages.txt"
snap list >"$OUTPUT_DIR/snap-packages.txt" 2>&1 || true
systemctl list-unit-files --state=enabled --no-pager >"$OUTPUT_DIR/enabled-systemd-units.txt"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,ROTA,MODEL >"$OUTPUT_DIR/block-devices.txt"
findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS >"$OUTPUT_DIR/mounts.txt"
ip -brief address >"$OUTPUT_DIR/network-addresses.txt"
ip route show >"$OUTPUT_DIR/network-routes.txt"

if command -v docker >/dev/null 2>&1; then
  docker version >"$OUTPUT_DIR/docker-version.txt" 2>&1 || true
  docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' >"$OUTPUT_DIR/docker-containers.tsv"
  docker volume ls --format '{{.Name}}\t{{.Driver}}' >"$OUTPUT_DIR/docker-volumes.tsv"
  docker compose ls --all --format json >"$OUTPUT_DIR/docker-compose-projects.json" 2>/dev/null || true
fi

find "$BACKUP_USER_HOME" -maxdepth 5 -type f \
  \( -name 'compose.yml' -o -name 'compose.yaml' -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) \
  -print >"$OUTPUT_DIR/compose-files.txt" 2>/dev/null || true

log INFO "System inventory created at $OUTPUT_DIR"

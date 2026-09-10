#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands restic mountpoint gzip docker
acquire_lock
mkdir -p "$LOG_DIR" "$STAGING_ROOT"
rotate_logs

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="$LOG_DIR/backup-$run_id.log"
exec > >(tee -a "$log_file") 2>&1

staging_dir="$STAGING_ROOT/$run_id"
cleanup() {
  local status=$?
  rm -rf -- "$staging_dir"
  if [[ $status -eq 0 ]]; then
    log INFO "Backup run completed successfully"
  else
    log ERROR "Backup run failed with status $status"
  fi
  exit "$status"
}
trap cleanup EXIT

log INFO "Starting ${BACKUP_TRIGGER:-manual} backup"
require_backup_mount
mkdir -p "$RESTIC_REPOSITORY" "$staging_dir/inventory" "$staging_dir/postgresql"

if ! restic snapshots >/dev/null 2>&1; then
  if [[ -e "$RESTIC_REPOSITORY/config" ]]; then
    die "Restic repository exists but could not be opened."
  fi
  log INFO "Initializing Restic repository"
  restic init
fi

"$SCRIPT_DIR/generate-inventory.sh" "$staging_dir/inventory"
"$SCRIPT_DIR/postgres-dump.sh" "$staging_dir/postgresql"

sources=(
  /etc
  /usr/local/bin
  /usr/local/sbin
  "$BACKUP_USER_HOME"
  /var/lib/docker/volumes
  /var/lib/prometheus
  /var/lib/grafana
  "$staging_dir"
)

if [[ -n "${EXTRA_BACKUP_PATHS:-}" ]]; then
  read -r -a extra_paths <<<"$EXTRA_BACKUP_PATHS"
  sources+=("${extra_paths[@]}")
fi

existing_sources=()
for source_path in "${sources[@]}"; do
  if [[ -e "$source_path" ]]; then
    existing_sources+=("$source_path")
  else
    log WARN "Skipping missing optional source: $source_path"
  fi
done

log INFO "Creating encrypted Restic snapshot"
restic backup \
  --exclude-file "$PROJECT_DIR/config/excludes.txt" \
  --exclude "$RESTIC_REPOSITORY" \
  --tag "${BACKUP_TRIGGER:-manual}" \
  --host "$(hostname)" \
  "${existing_sources[@]}"

log INFO "Applying retention policy: $KEEP_WEEKLY weekly snapshots"
restic forget --keep-weekly "$KEEP_WEEKLY" --keep-last 1 --prune

"$SCRIPT_DIR/check-repository.sh"


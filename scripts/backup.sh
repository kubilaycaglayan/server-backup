#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands restic mountpoint gzip docker
acquire_lock

dry_run=false
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=true ;;
  *) die "Usage: backup.sh [--dry-run]" ;;
esac

mkdir -p "$LOG_DIR" "$STAGING_ROOT"
rotate_logs

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="$LOG_DIR/backup-$run_id.log"
touch "$log_file"
chown root:"$(id -gn "$BACKUP_USER")" "$log_file"
chmod 0640 "$log_file"
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

log INFO "Starting ${BACKUP_TRIGGER:-manual} backup (dry-run=$dry_run)"
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

# Raw PostgreSQL data directories are not transactionally safe to copy while
# live. Their online logical dumps above are the authoritative backup.
postgres_excludes=()
while IFS= read -r container; do
  if docker exec "$container" sh -c 'test "$(cat /proc/1/comm)" = postgres' >/dev/null 2>&1; then
    while IFS= read -r volume_path; do
      if [[ -n "$volume_path" ]]; then
        postgres_excludes+=(--exclude "$volume_path")
        log INFO "Excluding live PostgreSQL data directory: $volume_path"
      fi
    done < <(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{println .Source}}{{end}}{{end}}' "$container")
  fi
done < <(docker ps --format '{{.Names}}')

log INFO "Creating encrypted Restic snapshot"
restic_options=()
if [[ "$dry_run" == "true" ]]; then
  restic_options+=(--dry-run)
fi
restic backup \
  "${restic_options[@]}" \
  --exclude-file "$PROJECT_DIR/config/excludes.txt" \
  --exclude "$RESTIC_REPOSITORY" \
  "${postgres_excludes[@]}" \
  --tag "${BACKUP_TRIGGER:-manual}" \
  --host "$(hostname)" \
  "${existing_sources[@]}"

if [[ "$dry_run" == "false" ]]; then
  log INFO "Verifying database dumps and inventory in the new snapshot"
  dump_count=0
  while IFS= read -r -d '' dump_file; do
    if ! restic dump latest "$dump_file" | gzip -t; then
      die "Backed-up PostgreSQL dump could not be verified: $dump_file"
    fi
    ((dump_count += 1))
  done < <(find "$staging_dir/postgresql" -maxdepth 1 -type f -name '*.sql.gz' -print0)

  if [[ "$dump_count" -eq 0 && "${REQUIRE_POSTGRES_DUMPS:-false}" == "true" ]]; then
    die "No PostgreSQL dumps were found in the new snapshot."
  fi

  if ! restic dump latest "$staging_dir/inventory/dpkg-packages.tsv" >/dev/null; then
    die "System inventory was not found in the new snapshot."
  fi
  log INFO "Verified $dump_count PostgreSQL dump(s) and system inventory in the snapshot"

  log INFO "Applying retention policy: $KEEP_WEEKLY weekly snapshots"
  restic forget --keep-weekly "$KEEP_WEEKLY" --keep-last 1 --prune
else
  log INFO "Dry-run complete; no snapshot or retention changes were made"
fi

"$SCRIPT_DIR/check-repository.sh"

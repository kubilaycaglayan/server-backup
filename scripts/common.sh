#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
ENV_FILE="$PROJECT_DIR/.env"
LOG_DIR="$PROJECT_DIR/logs"
# Consumed by scripts that source this file.
# shellcheck disable=SC2034
STAGING_ROOT="$PROJECT_DIR/staging"
LOCK_FILE="/run/lock/server-backup.lock"

timestamp() {
  date --iso-8601=seconds
}

log() {
  printf '%s [%s] %s\n' "$(timestamp)" "$1" "$2"
}

die() {
  log ERROR "$1" >&2
  exit "${2:-1}"
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this command as root."
}

load_config() {
  [[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE; copy .env.example and customize it."

  local mode
  mode="$(stat -c '%a' "$ENV_FILE")"
  [[ "$mode" == "600" || "$mode" == "400" || "$mode" == "640" || "$mode" == "440" ]] || \
    die "$ENV_FILE must have mode 0600/0400, or 0640/0440 with a user-only read ACL (current: $mode)."

  if command -v getfacl >/dev/null 2>&1; then
    getfacl -cp "$ENV_FILE" | grep -q '^other::---$' || die "$ENV_FILE must deny access to other users."
    getfacl -cp "$ENV_FILE" | grep -q '^group::---$' || die "$ENV_FILE must deny access to its owning group."
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/config/retention.conf"
  set +a

  : "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
  : "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"
  : "${BACKUP_MOUNT:?BACKUP_MOUNT is required}"
  : "${BACKUP_USER:?BACKUP_USER is required}"
  : "${BACKUP_USER_HOME:?BACKUP_USER_HOME is required}"

  [[ "$RESTIC_REPOSITORY" == /* ]] || die "RESTIC_REPOSITORY must be an absolute path."
  [[ "$BACKUP_MOUNT" == /* ]] || die "BACKUP_MOUNT must be an absolute path."
  [[ "$BACKUP_USER_HOME" == /* ]] || die "BACKUP_USER_HOME must be an absolute path."

  export RESTIC_REPOSITORY RESTIC_PASSWORD
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
  done
}

acquire_lock() {
  require_commands flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Another server-backup process is already running."
}

require_backup_mount() {
  mountpoint -q "$BACKUP_MOUNT" || die "Backup mount is unavailable: $BACKUP_MOUNT" 20
  [[ -w "$BACKUP_MOUNT" ]] || die "Backup mount is not writable: $BACKUP_MOUNT" 21
}

rotate_logs() {
  mkdir -p "$LOG_DIR"
  find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${LOG_RETENTION_DAYS:-28}" -delete
}

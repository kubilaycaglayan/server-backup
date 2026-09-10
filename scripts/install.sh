#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands restic systemctl systemd-analyze sed install

[[ -d "$BACKUP_USER_HOME" ]] || die "Configured user home does not exist: $BACKUP_USER_HOME"
id "$BACKUP_USER" >/dev/null 2>&1 || die "Configured backup user does not exist: $BACKUP_USER"

calendar="${BACKUP_CALENDAR:-Sun *-*-* 02:00:00}"
timezone="${BACKUP_TIMEZONE:-Etc/GMT-3}"
systemd-analyze calendar "$calendar $timezone" >/dev/null

backup_group="$(id -gn "$BACKUP_USER")"
install -d -m 0750 -o root -g "$backup_group" "$LOG_DIR" "$STAGING_ROOT"
chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"
find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.sh' -exec chmod 0755 {} +

install -m 0644 "$PROJECT_DIR/systemd/server-backup.service" /etc/systemd/system/server-backup.service
timer_tmp="$(mktemp)"
trap 'rm -f "$timer_tmp"' EXIT
sed \
  -e "s|@BACKUP_CALENDAR@|$calendar|g" \
  -e "s|@BACKUP_TIMEZONE@|$timezone|g" \
  "$PROJECT_DIR/systemd/server-backup.timer.in" >"$timer_tmp"
install -m 0644 "$timer_tmp" /etc/systemd/system/server-backup.timer

systemd-analyze verify /etc/systemd/system/server-backup.service /etc/systemd/system/server-backup.timer
systemctl daemon-reload
systemctl enable --now server-backup.timer

log INFO "Installed server-backup timer. The first backup remains manual."
systemctl list-timers server-backup.timer --no-pager

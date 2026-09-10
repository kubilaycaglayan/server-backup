#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands restic mountpoint
require_backup_mount

snapshot="${1:-}"
if [[ "$snapshot" == "snapshots" ]]; then
  exec restic snapshots
fi

destination="${2:-}"
[[ -n "$snapshot" && -n "$destination" ]] || die "Usage: restore.sh snapshots | restore.sh SNAPSHOT EMPTY_DESTINATION"
[[ "$destination" == /* ]] || die "Restore destination must be an absolute path."
[[ "$destination" != "/" ]] || die "Refusing to restore directly to /."
[[ -d "$destination" ]] || die "Restore destination does not exist: $destination"
[[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "Restore destination must be empty."

log INFO "Restoring snapshot $snapshot into $destination"
restic restore "$snapshot" --target "$destination"
log INFO "Restore extraction completed; review files before copying them into place."


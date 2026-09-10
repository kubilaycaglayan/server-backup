#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands restic mountpoint
require_backup_mount

log INFO "Checking Restic repository integrity"
restic check --read-data-subset="${RESTIC_CHECK_SUBSET:-5%}"
log INFO "Restic repository check completed"

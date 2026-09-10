# Configuration

Copy `.env.example` to `.env`. The local file is ignored by Git and must be
owned by root with mode `0600` after installation.

Required values:

- `RESTIC_REPOSITORY`: absolute path to the Restic repository.
- `RESTIC_PASSWORD`: encryption password; preserve another copy securely.
- `BACKUP_USER` and `BACKUP_USER_HOME`: account and home directory to protect.

Scheduling defaults to Sunday at 02:00 in UTC+3. `BACKUP_TIMEZONE` uses an IANA
timezone and `BACKUP_CALENDAR` uses systemd calendar syntax. Rerun
`scripts/install.sh` after changing schedule values.

`EXTRA_BACKUP_PATHS` accepts space-separated absolute paths for irreplaceable
data not covered by the standard scope. Do not add paths containing spaces.

The committed exclusion file is intentionally conservative. Review
`config/excludes.txt` before the first backup. Restic's `--exclude-file` rules
are evaluated against full source paths and directory names.

## Standard backup scope

- `/etc`, `/usr/local/bin`, and `/usr/local/sbin`
- selected user home data, with caches and downloadable tooling excluded
- `/var/lib/docker/volumes`, `/var/lib/prometheus`, and `/var/lib/grafana`
- generated PostgreSQL dumps and system inventories
- any paths in `EXTRA_BACKUP_PATHS`

Missing optional paths are skipped and recorded in the log.


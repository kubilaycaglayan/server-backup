# Configuration

Install `.env.example` as `.env`, then customize it. The local file is ignored
by Git, owned by root, and the installer grants only the configured backup user
read access through a filesystem ACL so it can be viewed in VS Code.

```bash
sudo install -m 0600 -o root -g root .env.example .env
sudo editor .env
```

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

Running PostgreSQL containers are handled specially: logical dumps are made
online, and their raw live data directories are excluded from the filesystem
snapshot. Other Docker volume files are copied live.

Backup logs are readable by the configured backup user's primary group. The
temporary staging directory is group-traversable but dump files remain
root-only under the project's restrictive umask.

# Recovery

Never restore directly onto a running system without reviewing the snapshot
and destination. The restore helper requires an existing, empty destination
directory and refuses `/`.

## Full host recovery outline

1. Install a compatible Ubuntu release and mount the backup disk.
2. Install Restic, Docker, PostgreSQL client tools, and required packages.
3. Obtain this project and recreate the root-only `.env` with the original
   Restic password.
4. List snapshots with `sudo scripts/restore.sh snapshots`.
5. Restore into an empty staging destination.
6. Review and copy host configuration and user data into place.
7. Reinstall packages using the generated inventories.
8. Recreate Docker stacks and volumes, then restore application data.
9. Restore logical database dumps with `pg_restore` into newly created
   PostgreSQL databases.
10. Reinstall custom systemd services and restart applications.
11. Restore SSH private keys separately; this project excludes them.

Example safe extraction:

```bash
sudo mkdir -p /srv/server-restore
sudo scripts/restore.sh latest /srv/server-restore
```

Database dumps are found under the restored staging tree. Validate one with
`gzip -t dump.sql.gz`, inspect it with `zless`, and restore it with a command
such as `gzip -dc dump.sql.gz | psql`. Database ownership, roles, and
credentials are application-specific and must be reconciled with the relevant
deployment configuration.

PostgreSQL raw volume directories are intentionally absent because a live file
copy is not transactionally reliable. Use the compressed logical SQL dumps.

# Server Backup

Public-safe Restic automation for an Ubuntu server. It creates online
PostgreSQL logical dumps, records system inventories, backs up selected host
and Docker data without stopping production services, retains four weekly
snapshots, and checks repository integrity after each run.

The first backup is intentionally manual. Installing the timer does not invoke
a backup immediately.

## Safety model

- Secrets and machine-specific settings live in the ignored `.env` file.
- Restic encrypts repository contents; losing the password makes recovery
  impossible.
- SSH private keys, caches, downloadable runtimes, Docker build data, logs,
  Ollama models, and JetBrains caches are excluded.
- A repository on a disk inside the same machine protects against OS-disk
  failure and mistakes, but not loss of that disk or the whole machine. Add an
  independent remote repository later.

## Quick start

```bash
cp .env.example .env
sudo editor .env
sudo ./scripts/install.sh
sudo ./scripts/backup.sh
```

See [configuration](docs/CONFIGURATION.md) and [recovery](docs/RECOVERY.md)
before relying on the backup.

## Commands

```bash
sudo ./scripts/backup.sh             # backup on demand
sudo ./scripts/backup.sh --dry-run   # validate scope without a snapshot
sudo ./scripts/check-repository.sh   # explicit repository check
sudo ./scripts/restore.sh snapshots  # list snapshots
sudo ./scripts/restore.sh latest /safe/restore/directory
```

Runtime logs are written to `logs/` and retained for 28 days by default.

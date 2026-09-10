#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_root
load_config
require_commands docker gzip

OUTPUT_DIR="${1:-}"
[[ -n "$OUTPUT_DIR" ]] || die "Usage: postgres-dump.sh OUTPUT_DIRECTORY"
mkdir -p "$OUTPUT_DIR"

containers=()
if [[ -n "${POSTGRES_CONTAINERS:-}" ]]; then
  read -r -a containers <<<"$POSTGRES_CONTAINERS"
else
  while IFS= read -r container; do
    if docker exec "$container" sh -c 'pg_isready -U "${POSTGRES_USER:-postgres}"' >/dev/null 2>&1; then
      containers+=("$container")
    fi
  done < <(docker ps --format '{{.Names}}')
fi

dump_count=0
for container in "${containers[@]}"; do
  safe_name="${container//[^a-zA-Z0-9_.-]/_}"
  output_file="$OUTPUT_DIR/${safe_name}.sql.gz"
  log INFO "Creating online PostgreSQL dump for $container"

  if docker exec -u postgres "$container" sh -c \
    'exec pg_dumpall --clean --if-exists -U "${POSTGRES_USER:-postgres}"' \
    | gzip -1 >"$output_file"; then
    gzip -t "$output_file"
    ((dump_count += 1))
  else
    rm -f "$output_file"
    die "PostgreSQL dump failed for container: $container"
  fi
done

if [[ "$dump_count" -eq 0 && "${REQUIRE_POSTGRES_DUMPS:-false}" == "true" ]]; then
  die "No running PostgreSQL server was discovered, but dumps are required."
fi

log INFO "Created $dump_count PostgreSQL dump(s) at $OUTPUT_DIR"


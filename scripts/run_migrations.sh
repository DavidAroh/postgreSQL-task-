#!/usr/bin/env bash
# Applies sql/migrations/*.sql in filename order, exactly once each.
# The applied set is recorded in public.schema_migrations.
set -euo pipefail

cd "$(dirname "$0")/.."

DB="${PGDATABASE:-advdb}"
USER="${PGUSER:-app}"

PSQL="docker exec -i advdb-postgres psql -v ON_ERROR_STOP=1 -q -U ${USER} -d ${DB}"
if ! docker ps --format '{{.Names}}' | grep -q '^advdb-postgres$'; then
  echo "error: container advdb-postgres is not running (docker compose up -d)" >&2
  exit 1
fi

$PSQL -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  filename text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);" > /dev/null

shopt -s nullglob
for f in sql/migrations/*.sql; do
  name="$(basename "$f")"
  if $PSQL -Atc "SELECT 1 FROM schema_migrations WHERE filename = '${name}'" | grep -q 1; then
    echo "  = ${name} (already applied)"
  else
    echo "  -> ${name}"
    $PSQL < "$f" > /dev/null
    $PSQL -c "INSERT INTO schema_migrations(filename) VALUES ('${name}');" > /dev/null
  fi
done
echo "migrations complete."

#!/usr/bin/env bash
# Drops and recreates the public schema. Used by reset.sh.
set -euo pipefail
docker exec -i advdb-postgres psql -v ON_ERROR_STOP=1 -q -U app -d advdb <<'SQL'
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL
echo "schema dropped."

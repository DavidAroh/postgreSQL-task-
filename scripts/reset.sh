#!/usr/bin/env bash
# Full fresh start: drop schema, replay migrations, seed data.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/drop.sh
./scripts/run_migrations.sh
echo "seeding (this takes ~30-60s)..."
docker exec -i advdb-postgres psql -v ON_ERROR_STOP=1 -q -U app -d advdb -f - < scripts/seed.sql > /dev/null
echo "done. Connect with:  docker exec -it advdb-postgres psql -U app -d advdb"

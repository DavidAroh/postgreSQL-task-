# Advanced Database Engineering & Data Modelling

A self-contained training kit for a back-end intern. Everything is built around one
realistic system — a small e-commerce platform (users, addresses, vendors, products,
variants, inventory, carts, orders) — so every topic is demonstrated against the same
schema instead of toy examples.

## What's inside

```
docker-compose.yml         One-command PostgreSQL 16 instance (no other dependencies)
scripts/
  reset.sh                 Drop everything, replay all migrations, reseed  (fresh start)
  drop.sh                  Drop the whole schema (used by reset)
  run_migrations.sh        Applies sql/migrations/*.sql in filename order, tracks them in schema_migrations
  seed.sql                 Deterministic seed data (~2.5k products, ~10k orders, 80k order items)
sql/
  00_schema/               "Live" schema pieces (triggers that aren't migrations)
  migrations/              001…011 — the full build-up of the database, run in order
docs/                      One short file per topic, each with the "why" and interview-style questions
labs/                      Hands-on exercises: 01 … 12 + solutions/
WORKBOOK.md                The recommended path through the whole module
DEMO-SCRIPT.md             Shot-by-shot screen-recording guide for a demo to a senior dev
```

## Prerequisites

- Docker (the only hard requirement — PostgreSQL itself runs in a container)
- Bash (Git Bash is fine on Windows) and `psql` available locally is *nice* but not
  required: you can also run every `.sql` file from a GUI (pgAdmin, DBeaver, TablePlus).

## Quick start

```bash
docker compose up -d          # starts postgres on localhost:5433 (host) -> 5432 (container)
./scripts/reset.sh            # applies migrations + seed data (~30–60s)

# connect
docker exec -it advdb-postgres psql -U app -d advdb
```

If you have `psql` locally: `psql "postgresql://app:app@localhost:5433/advdb"`.

Want to record yourself demoing the module? Follow `DEMO-SCRIPT.md` — every SQL block
in it has been tested against the seeded database.

## The module in one paragraph

You will model a moderately complex system with proper relationships and constraints,
learn exactly what those constraints cost at write time, index for the queries that
actually run, read real `EXPLAIN (ANALYZE, BUFFERS)` plans and fix bad ones, then move
to the concurrency layer: transactions, isolation levels, row locks, optimistic
locking, deadlocks, and a real job queue built with `FOR UPDATE SKIP LOCKED`. The
last lab makes you *cause* the N+1 problem and then measure three different cures.

## Recommended path (see WORKBOOK.md for the detailed version)

1. Read `docs/01…03` while the migrations are fresh in your head.
2. Do labs 01–04 against the seeded database (constraints → indexes → plans → joins).
3. Read `docs/04…06`, then labs 05–08 (transactions, isolation, pessimistic, optimistic).
4. Read `docs/07`, then labs 09–12 (deadlocks, queues, audit/soft delete, N+1).
5. Finish with the capstone in `WORKBOOK.md` §7 — a review of the whole schema.

## Ground rules for the intern

- Every experiment happens on your local container. Breaking the seed database is
  expected — `./scripts/reset.sh` puts it back in under a minute.
- Never guess about performance. Every claim you make in review must be backed by an
  `EXPLAIN (ANALYZE, BUFFERS)` output pasted into your notes.
- Concurrency labs (05–09) need **two psql sessions side by side**. Do them properly —
  this is the part most engineers skip and it shows later.

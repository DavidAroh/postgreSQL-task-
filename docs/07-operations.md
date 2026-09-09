# 07 · Operations: pooling, migrations, soft deletes, audit, bottlenecks

## Connection pooling

PostgreSQL costs ~5–10MB of RAM and one OS process per connection; thousands of
connections mean the scheduler thrashes before your query even runs. The architecture
is always:

```
apps (many short-lived connections) → pooler (few long-lived) → postgres
```

- **Client-side**: your app's pool (HikariCP, pgx pool, SQLAlchemy). Know its limits:
  max pool size × app instances = total connections the database sees.
- **Server-side**: **PgBouncer** in *transaction* mode is the standard front door:
  a connection is borrowed per transaction, not per session. Consequences: no session
  state (no `SET`, no advisory locks held across transactions, no prepared statements
  spanning transactions on older versions). Formula to memorise:
  `pool size ≈ (cores × 2) + effective_spindle_count` — for modern NVMe, `cores × 2–4`
  is the working range. More is *slower*, not safer.

Watch it live:

```sql
SELECT count(*), usename, state FROM pg_stat_activity GROUP BY 2, 3;
SELECT max_conn, used, res_for_super, max_conn - used - res_for_super AS avail
FROM (SELECT count(*) used FROM pg_stat_activity) s,
     (SELECT setting::int max_conn FROM pg_settings WHERE name = 'max_connections') m,
     (SELECT setting::int res_for_super FROM pg_settings WHERE name = 'superuser_reserved_connections') r;
```

## Database migrations (the discipline)

Zero-downtime migration rules — each step is a deploy, the schema is always compatible
with both old and new app versions during the transition:

1. **Expand**: additive change only (add nullable column / new table / new index CONCURRENTLY).
2. **Migrate**: backfill in **batches** (`WHERE id BETWEEN a AND b` or
   `WHERE id IN (SELECT id FROM t WHERE migrated IS NULL LIMIT 1000)`), throttled, in
   app-visible chunks, with a `migrated` marker or a separate job table.
3. **Contract**: only after all writers use the new shape — drop the old column/trigger.

Concrete hazards, each of which has taken down real systems:

- `ALTER TABLE ... ADD COLUMN ... NOT NULL DEFAULT constant` — instant in PG11+;
  but a *volatile* default forces a full table rewrite under lock.
- `CREATE INDEX` (non-CONCURRENTLY) takes a SHARE lock: reads OK, writes **blocked**
  for the whole build. On big tables always `CREATE INDEX CONCURRENTLY` (it cannot run
  in a transaction, hence twice-run bookkeeping; and on failure it leaves an INVALID
  index to clean up).
- Changing a column type (`int` → `bigint`) rewrites the table: do the expand/contract
  dance with a new column + trigger-synced backfill.
- Lock queues: a waiting `ACCESS EXCLUSIVE` blocks every later query on the table
  *queued behind it* — use `SET lock_timeout = '3s'` before DDL and retry, so you fail
  fast instead of freezing the app.
- Deploy ordering: schema first, app second (never the reverse), and never ship a
  migration that assumes today's app version.

## Soft deletes and audit history

**Soft delete** (`status = 'deleted'` / `deleted_at IS NOT NULL`):

- Pros: undo, referential history, GDPR-trappable forgotten data, FKs survive.
- Cons: *every* query must remember the predicate (an accidental missing
  `WHERE status <> 'deleted'` shows deleted rows to users); partial indexes grow;
  UNIQUE constraints need care (`UNIQUE (email)` blocks re-registration — partial
  unique `WHERE status <> 'deleted'` is the usual fix).

In this schema: `users.status` + partial indexes are the pattern; lab 11 exercises it.

**Audit history** — two levels, this schema has both:

- **Append-only trigger log** (`audit_log`, 009/011): U/D captured as JSONB with who
  and when. Cheap, generic, queryable per row via `(table_name, row_pk, occurred_at)`.
  Database-enforced append-only (RULEs reject UPDATE/DELETE). Data changes are
  versioned; *schema* changes of the logged tables are the pain — JSONB absorbs them.
- **Temporal tables / SCD2**: valid-from/valid-to columns, "state of the world at
  time T" queries via a range predicate. More powerful, much heavier. Reach for it
  when audit must answer "what did the *whole* order look like at T", not "which
  columns changed".

Append-only beats UPDATE-in-place for money-adjacent history: the old version can
never be lost, only superseded. It is also why `order_items` snapshots exist (docs/02).

## Database bottlenecks: where the time actually goes

Bottleneck checklist, in the order real incidents unfold:

1. **CPU saturation** — hundreds of active queries, high load average: usually missing
   index → massive sort/hash spill, or pathological plan flips.
2. **Buffer cache misses** (`track_io_timing` shows I/O wait inside plans) — working
   set > shared_buffers; check hit ratio per relation in `pg_statio_user_tables`.
3. **Lock waits** — `pg_stat_activity` full of `wait_event_type = Lock`: find the
   blocker chain with `pg_blocking_pids` (docs/06).
4. **Connection churn** — thousands of short-lived connections: pooler misconfig.
5. **Autovacuum falling behind** — bloat (docs/01), plans degrading as dead tuples grow:
   check `n_dead_tup`, tune `autovacuum_vacuum_scale_factor` per hot table.
6. **WAL/checkpoint storms** — `pg_stat_bgwriter.checkpoints_timed` vs `..._req`;
   requested (un-timed) checkpoints are a warning light.

## Read-heavy vs write-heavy design

- **Read-heavy** (catalogue, dashboards): denormalise aggressively, materialise
  (`MATERIALIZED VIEW ... REFRESH CONCURRENTLY`), cache layers (Redis), replicas for
  read scale — at the price of stale reads (decide per feature whether staleness is OK).
- **Write-heavy** (inventory, order events, analytics ingest): fewer indexes (every
  index is a write), batch inserts, drop FKs on ingested-only tables when you can
  validate later, partition by time so old data prunes cheaply, consider
  `COPY`/`INSERT ... SELECT` pipelines and deferring constraint checks.

This schema is deliberately both: the catalogue side is read-heavy (trigram search,
covering reads), while inventory/orders are write-heavy (atomic decrement, totals
trigger, audit log). Point at any table and say which side it serves and why.

## Explain-back questions

1. Your app has 40 pods × 20 connections. `max_connections = 100`. What happens under load, and what are the two fixes (one app-side, one db-side)?
2. Why must `CREATE INDEX CONCURRENTLY` not run inside a transaction, and what breaks if it fails midway?
3. Soft delete: what is the UNIQUE-constraint trap on `users.email`, and its standard fix?
4. For a 2TB append-only events table queried only by time ranges: which index type and why?

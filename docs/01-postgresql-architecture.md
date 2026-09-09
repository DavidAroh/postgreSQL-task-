# 01 · PostgreSQL architecture fundamentals

The goal is a mental model good enough to explain *why* the database behaves the way it
does in the labs — not to memorise internals.

## The process model

PostgreSQL is not one process. It is a **postmaster** that forks a fresh **backend
process per connection**, plus a set of shared workers. All backends talk through
**shared buffers** (one shared memory region, default `128MB`).

```
                 ┌─ checkpointer ─ flushes dirty pages, writes WAL markers
postmaster ──────┼─ bgwriter ───── writes dirty pages ahead of demand
                 ├─ walwriter ──── flushes WAL buffers
                 ├─ autovacuum ─── reclaims dead tuples, refreshes stats
                 └─ one backend per client connection (your SQL runs here)
```

Probe it in your container:

```sql
SELECT pid, backend_type, state, query
FROM pg_stat_activity
ORDER BY backend_type, pid;
```

## Memory: shared buffers vs work_mem

- **shared_buffers** — the page cache shared by all backends. Hit here and no disk read
  happens. `EXPLAIN (ANALYZE, BUFFERS)` shows `shared hit` vs `shared read`.
- **work_mem** — private scratch space **per sort/hash node, per query**. A query with
  three sort nodes can allocate 3 × work_mem. Too small → the node *spills to disk*
  (`Sort Method: external merge  Disk: 3000kB` in the plan). Never a global excuse to
  raise it blindly: 200 concurrent sorts × 64MB is real memory.

## WAL and durability

Every change is first written to the **write-ahead log** and flushed on COMMIT — the
table pages themselves are written later (checkpoints). Consequences:

- COMMIT means *durable*, not "data reached the table files".
- Sequential scans of a hot table are fast because pages are cached; the first run of a
  lab query is always slower than the second. Re-run before you judge a plan.
- `synchronous_commit = off` is a real production knob (faster commit, loses the last
  ~600ms of transactions only on an OS crash, never corruption).

## MVCC: why UPDATE copies rows

Rows carry `xmin` (creating transaction id) and `xmax` (destroying tx id). A reader
decides which version of a row is visible to it — writers never block readers, and
readers never block writers. **UPDATE = insert a new tuple version + mark the old one
dead.** Dead tuples are reclaimed by **VACUUM** (usually autovacuum):

- Long-running transactions keep *every* version since they started → table and index
  bloat (see `pg_stat_activity` in lab 09 after you open an idle transaction).
- Hot-rotate columns cause full-row rewrites (new version) — a reason audit tables are
  append-only instead of "one JSONB column on the row".

## Process-per-connection is why pooling exists

Each connection is an OS process with its own memory (~5–10MB). 5,000 connections =
5,000 processes thrashing your CPU. This is the root cause behind docs/07's connection
pooling section: keep PostgreSQL connections in the low hundreds; let a pooler queue.

## Try this

```sql
SHOW shared_buffers; SHOW work_mem; SHOW synchronous_commit;
SELECT * FROM pg_stat_bgwriter;
-- watch dead tuples appear and disappear:
CREATE TABLE mvcc_demo (id int, t text);
INSERT INTO mvcc_demo SELECT g, 'x' FROM generate_series(1,10000) g;
UPDATE mvcc_demo SET t = 'y';
SELECT n_dead_tup, n_live_tup FROM pg_stat_user_tables WHERE relname = 'mvcc_demo';
VACUUM mvcc_demo;
SELECT n_dead_tup, n_live_tup FROM pg_stat_user_tables WHERE relname = 'mvcc_demo';
```

## Explain-back questions

1. Why can a long-running reporting query make table bloat *worse* even though it only reads?
2. Your COMMIT took 900ms. Which subsystem do you suspect first, and what would you check?
3. Why does `work_mem = 4MB` sometimes matter and sometimes not, for the same query?

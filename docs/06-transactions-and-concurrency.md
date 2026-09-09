# 06 · Transactions, isolation levels, locking, concurrency control

## ACID, honestly

- **Atomicity** — all or nothing per transaction (WAL undo via rollback; clog decides
  commit status). Lab 05.
- **Consistency** — the constraint set *between* transactions; the app's job *within*
  them. Constraints + triggers are the database's half.
- **Isolation** — concurrent transactions don't see each other's uncommitted state. The
  whole rest of this doc.
- **Durability** — committed survives a crash (WAL, docs/01).

## Isolation levels in PostgreSQL (the official table)

| Isolation level | Dirty read | Non-repeatable read | Phantom read | Serialization anomaly |
|---|---|---|---|---|
| READ COMMITTED (default) | allowed | allowed | allowed | allowed |
| REPEATABLE READ | no | no | allowed* | allowed |
| SERIALIZABLE | no | no | no | no |

*PostgreSQL REPEATABLE READ actually prevents phantom reads of *snapshot* state; the
anomaly that remains is write skew (two transactions each commit based on a
precondition the other invalidated — lab 06). Only SERIALIZABLE aborts those.

PostgreSQL implements MVCC: readers take a snapshot, never block. **READ COMMITTED
takes a new snapshot per statement; REPEATABLE READ/SERIALIZABLE take one per
transaction** — that single sentence is most of the practical difference. Note what
READ COMMITTED really means: two SELECTs in one transaction may disagree with each
other, and an UPDATE re-evaluates its WHERE against the *latest* committed row
(`EvalPlanQual` re-check) — the source of several labs' surprises.

## Row-level locking and the RW conflict

`SELECT ... FOR UPDATE` takes a row-exclusive lock until commit/rollback; concurrent
writers **block** (pessimistic). Plain UPDATE/DELETE take the same lock implicitly.
Without it, two sessions read quantity 10, both decide to sell 3, both UPDATE to 7 —
**lost update** (the classic race; lab 07 makes you create it).

PostgreSQL has no reader/writer block on plain SELECT — locks are writer/writer. So:
- read-modify-write flows need explicit `FOR UPDATE` (or an atomic UPDATE — see below);
- plain SELECTs never block anything, but they also *guarantee nothing* about what
  you'll see when you act on the data.

**Skip the lock entirely when the update is self-contained.** `UPDATE inventory SET
quantity = quantity - 3 WHERE variant_id = 1 AND quantity >= 3` is atomic under READ
COMMITTED: the row lock serialises the two writers, and the second one re-evaluates
the WHERE against the post-update row (EvalPlanQual) — it returns 0 rows instead of
overselling. This is the single most useful concurrency pattern in the kit.

## Optimistic vs pessimistic concurrency control

| | Pessimistic (`FOR UPDATE`) | Optimistic (version column) |
|---|---|---|
| Contention | blocking under contention | retries under contention |
| Fairness | FIFO-ish, no starvation | livelock under extreme contention |
| Distributed apps | holds a DB connection while "thinking" | no locks held across requests |
| Use when | short critical sections, hot single rows | low contention, long think-time, multi-service writes |

Optimistic locking needs a `version` column checked in the UPDATE's WHERE and
incremented in the SET; zero rows updated = someone else moved first → reload + retry
or 409. See lab 08 for the full implementation including retry-bounded loops.

## Deadlocks

A deadlock needs four conditions (Coffman): mutual exclusion, hold-and-wait,
no preemption, circular wait. Break any one — in practice: **consistent lock ordering**
is the practical cure; `deadlock_timeout` (default 1s) is how fast PG detects the
circle and kills one victim. Lab 09 makes you build one deliberately, then fix it.

## SELECT FOR UPDATE: the fine print

- `NOWAIT` — error instead of waiting: for user-facing paths where waiting is worse
  than failing fast.
- `SKIP LOCKED` — grab whatever is *unlocked*; the basis of the job queue in lab 10
  (workers never block each other, jobs processed exactly once while a row is locked).
- `FOR UPDATE` cannot be used with `GROUP BY`/aggregate, and in the outer query of a
  window function — lock the rows in a subquery/LATERAL instead.
- Locking a parent row *also* takes `FOR KEY SHARE`-compatible locks on referenced
  FK rows implicitly — that's what keeps FK checks from racing with parent deletes.

## Try this (feel a lock block)

```sql
-- Session A
BEGIN;
SELECT * FROM inventory WHERE variant_id = 1 FOR UPDATE;
-- Session B
UPDATE inventory SET quantity = quantity - 1 WHERE variant_id = 1;  -- blocks
-- Session A
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity WHERE wait_event IS NOT NULL;
ROLLBACK;  -- B unblocks
```

`pg_locks` + `pg_blocking_pids(pid)` is your production toolkit:

```sql
SELECT blocked.pid AS blocked_pid, blocking.pid AS blocking_pid,
       blocked.query AS blocked_query, blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) bpid ON true
JOIN pg_stat_activity blocking ON blocking.pid = bpid;
```

## Explain-back questions

1. Why does `UPDATE ... WHERE quantity >= 3` need no FOR UPDATE to be safe under READ COMMITTED?
2. A colleague sets REPEATABLE READ "for consistency" on a transfer endpoint. What new failure mode did they just add, and what's the correct fix?
3. Name a query pattern in this schema where SERIALIZABLE would reject a transaction that READ COMMITTED happily commits.
4. Why does optimistic locking degrade into livelock at high contention, and what would you do at 10k rps on one row?

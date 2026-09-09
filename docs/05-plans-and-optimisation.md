# 05 · Query execution plans, statistics, and optimisation

## Reading a plan

A plan is a tree; the optimiser composes it bottom-up. Read it **inside-out** (deepest
indentation first), and always start from `EXPLAIN (ANALYZE, BUFFERS)` — the estimated
costs tell you what the planner *thought*, the actual rows tell you what *happened*.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```

- `rows=` at each node vs the node's own estimate → misestimates.
- `loops=N` — the value is **per loop**, multiply by loops for the real total. The #1
  beginner misread (and the engine of most N+1 discoveries — lab 08).
- `Buffers: shared hit` = served from cache, `shared read` = from disk,
  `shared dirtied` = pages you wrote. `track_io_timing=on` (compose file) adds I/O time.
- `rows removed by filter` — high values mean "we read data to throw it away"; that is
  where an index (or better predicate) usually goes.

## The scan and join menu

| Node | What it means |
|---|---|
| Seq Scan | read every page; right for small tables, wrong for a selective predicate |
| Index Scan | seek + heap fetches; random I/O, exact rows |
| Index Only Scan | leaf pages only; needs the visibility map to be fresh |
| Bitmap Heap Scan | index → bitmap → ordered heap passes; middle ground |
| Nested Loop | for each outer row, probe inner (index probe = great for few outer rows) |
| Hash Join | build hash on smaller side, probe with other; good for big×big, no order |
| Merge Join | both sides sorted; good for big×big when order is useful |
| Sort / HashAggregate | may spill: watch `Sort Method: external merge Disk: ...` |

The planner picks based on **statistics**: per-column histograms, most-common-values,
distinct counts, correlation. Run `ANALYZE` after bulk changes. Autovacuum does this,
but a big seed/batch insert is exactly when you can't wait for it.

## Statistics: the planner's world view

```sql
SELECT * FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';
SELECT count(*) FROM orders WHERE status = 'pending';      -- real value
EXPLAIN SELECT * FROM orders WHERE status = 'pending';     -- estimated value
```

The gap between those two numbers is why plans go wrong. Extreme skew is where the
classic pitfall bites: a plan that is perfect for the common case can be terrible for
the rare case. PostgreSQL has *generic* plans for prepared statements that may flip a
fast query slow after five executions — lab 03 includes a demo of `plan_cache_mode = force_custom_plan`.

## Prepared statements: parse, plan, execute

`PREPARE`/`EXECUTE` skip re-parsing; every driver ("prepared statements" in your ORM)
does this under the hood. Two consequences worth knowing:

1. Generic plans can misfire under skew (above).
2. Transaction pooling (PgBouncer) can't span multi-statement transactions — hence
   docs/07 §pooling.

## The optimisation drill (in priority order)

1. **Right rows early**: filter before joining; push aggregates down.
2. **Index the real predicate** (sargable, correct column order).
3. **Rewrite the shape**: `EXISTS` vs `JOIN DISTINCT` vs `GROUP BY` (lab 03/04);
   window function instead of self-join; LATERAL instead of correlated subquery in SELECT.
4. **Batch**: N round-trips → one statement with arrays/CTEs (lab 08).
5. **Only then** consider planner knobs (`SET enable_seqscan = off` — diagnostics only,
   never a fix; you're bribing the optimiser, not fixing the estimate).

`enable_*` GUCs are GUCs, not switches: they *cost* plans, they don't forbid nodes —
a 10⁴× cost penalty you can also apply to a single table to discourage it.

## A worked read of this schema

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.total_cents, u.email
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.status = 'paid'
ORDER BY o.occurred_at DESC
LIMIT 20;
```

Expected shape: a btree probe on `idx_orders_status_created` → but wait, it's ordered
by `occurred_at`, not `created_at`, so the planner may instead use
`idx_orders_user_occurred`? No — there's no `user_id` predicate. Watch which index it
actually picks, then try:

- replacing `status`-lookup ordering with `occurred_at DESC` and a filter;
- `SELECT ... FROM orders o WHERE o.status = 'paid' ORDER BY o.occurred_at DESC LIMIT 20` (no join) vs joined.

Explain to yourself every difference. That habit — *read, hypothesise, re-explain* — is
the entire skill.

## Try this (skew demo)

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42;                  -- whale: thousands of rows
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 380;                 -- minnow: a handful
```

Same query text, wildly different row counts. Now:

```sql
BEGIN;
SET LOCAL enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 42;
ROLLBACK;
```

Ask: which plan does the *average* user deserve? Skew means there is no single right
answer — plan choices are statistical bets.

## Explain-back questions

1. A query was fast in staging, slow in prod. Name four concrete differences you'd check, in order.
2. `loops=1000, rows=1` on an index scan — what does `rows` mean here, and what's the actual output estimate?
3. Why can `ORDER BY ... LIMIT 20` turn a seq scan into a top-N heapsort — and when does that become pathological?
4. When is a Seq Scan the *correct* answer? Give a query against this schema.

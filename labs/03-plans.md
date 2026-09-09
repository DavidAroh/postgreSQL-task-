# Lab 03 · Reading plans: EXPLAIN (ANALYZE, BUFFERS)

**Sessions:** one. **Goal:** read every line of a plan and know what to do about it.

## Part A — warm-up: read three plans completely

For each query: paste the plan, then write one sentence per node explaining what it
did and whether its `actual rows` matched its estimate.

```sql
-- 1. point lookup
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM product_variants WHERE sku = 'VEN-' || upper(substr(md5('5'),1,6)) || '-001';
-- (replace with a real SKU: SELECT sku FROM product_variants LIMIT 5;)

-- 2. a selective filter on an unindexed predicate
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE total_cents > 50000;

-- 3. the same predicate, but the planner knows better
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';
-- Why does the estimate differ so much between 2 and 3? (MCVs — docs/05)
```

## Part B — make something slow, then fix it two ways

```sql
-- The per-user lifetime spend, computed naively:
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.email,
       (SELECT sum(o.total_cents) FROM orders o WHERE o.user_id = u.id) AS lifetime
FROM users u
WHERE u.status = 'active';
-- Note: loops= on the subquery. Multiply. Where is the time?

-- Fix 1: rewrite as a join+aggregate (group first, then join)
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.email, s.lifetime
FROM users u
LEFT JOIN (
  SELECT user_id, sum(total_cents) AS lifetime
  FROM orders GROUP BY user_id
) s ON s.user_id = u.id
WHERE u.status = 'active';

-- Fix 2: LATERAL (keeps per-user semantics, one scan with a nested loop)
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.email, s.lifetime
FROM users u
CROSS JOIN LATERAL (
  SELECT sum(o.total_cents) AS lifetime FROM orders o WHERE o.user_id = u.id
) s
WHERE u.status = 'active';
-- Compare: same results, radically different shapes. When does LATERAL beat the join?
```

## Part C — statistics lie (instructively)

```sql
SELECT * FROM pg_stats WHERE tablename = 'orders' AND attname = 'status'\gx
SELECT status, count(*) FROM orders GROUP BY status ORDER BY 2 DESC;
-- Real histogram vs planner's histogram: guess which statuses are mis-estimated.

-- Memory pressure: force a spill and see it in the plan
SET work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*) FROM orders GROUP BY status ORDER BY 2 DESC;
RESET work_mem;
-- Find: "Sort Method: external merge  Disk: ..." — that is work_mem exhaustion.
```

## Part D — prepared statements and plan flips

```sql
-- Skew: user 42 has thousands of orders, user 380 has ~30
PREPARE user_orders(bigint) AS SELECT * FROM orders WHERE user_id = $1;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(42);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(42);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(42);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(42);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(42);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(380);
-- After 5 executions, PostgreSQL may switch to a GENERIC plan. Do you see it?
-- Now force the other mode:
SET plan_cache_mode = force_custom_plan;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE user_orders(380);
DEALLOCATE user_orders;
```

## Exercises

1. Take the dashboard query `SELECT * FROM orders WHERE status='paid' ORDER BY occurred_at DESC LIMIT 20` and write a query with the same result set that uses a different join strategy. Explain which you'd ship and why.
2. Find the 3 most expensive query shapes so far in this database:
   `SELECT query, calls, mean_exec_time, total_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 5;`
   (Requires the extension — check `docker-compose.yml` enabled it.) Write one improvement per row.
3. `rows removed by filter: 24800` on an orders scan — state the index you'd add and prove it helps.
4. Why is the *first* execution of any lab query slower than the second? (Two reasons: buffers, and...?)

**Solutions:** [solutions/03-plans.md](solutions/03-plans.md)

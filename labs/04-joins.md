# Lab 04 · Joins, skew, and aggregate shapes

**Sessions:** one. **Goal:** understand why the planner changes strategies, using the
seeded skew (whale users 1–40).

## Part A — the same join, three plans

```sql
-- users × their order counts, all users:
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, count(o.id) AS n
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id;

-- Restrict to whales (users 1..40, thousands of orders each):
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, count(o.id) AS n
FROM users u JOIN orders o ON o.user_id = u.id
WHERE u.id <= 40
GROUP BY u.id;

-- Restrict to minnows (users 341..400):
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, count(o.id) AS n
FROM users u JOIN orders o ON o.user_id = u.id
WHERE u.id > 340
GROUP BY u.id;
```

Identify: where did the planner switch between Hash Join and Nested Loop, and why did
the switch make sense in each direction?

## Part B — anti-join and semi-join shapes

```sql
-- Users who never ordered (should be very few — check):
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Variants that have never sold:
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.id FROM product_variants v
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.variant_id = v.id);
-- Look for: Hash Anti Join. Now the SAME query written with LEFT JOIN + IS NULL —
-- compare plans and actual times. Which is cleaner and why?
```

## Part C — top-N per group (the window-function classic)

```sql
-- Latest order per user, version 1 (window function):
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM (
  SELECT o.*, row_number() OVER (PARTITION BY user_id ORDER BY occurred_at DESC) rn
  FROM orders o
) t WHERE rn = 1;

-- Version 2 (DISTINCT ON — a PostgreSQL speciality):
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT ON (user_id) * FROM orders ORDER BY user_id, occurred_at DESC;

-- Version 3 (LATERAL, per-user index probe):
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, x.*
FROM users u
CROSS JOIN LATERAL (
  SELECT * FROM orders o WHERE o.user_id = u.id
  ORDER BY occurred_at DESC LIMIT 1
) x;
-- All three return the same rows. Argue which survives a 100× data growth best, and why.
```

## Part D — aggregates that scale (or don't)

```sql
-- Revenue per day:
EXPLAIN (ANALYZE, BUFFERS)
SELECT occurred_at::date, sum(total_cents) FROM orders GROUP BY 1 ORDER BY 1;

-- Same, but only 2026:
EXPLAIN (ANALYZE, BUFFERS)
SELECT occurred_at::date, sum(total_cents) FROM orders
WHERE occurred_at >= '2026-01-01' AND occurred_at < '2027-01-01'
GROUP BY 1 ORDER BY 1;
-- The WHERE saved work by... how much? Which plan node got cheaper?
```

## Exercises

1. Write "for each vendor, the count of active products and the count of active *variants*", one query, no lateral joins, no scalar subqueries. Verify with `EXPLAIN` that there is no per-row subplan.
2. The products table has a trigram GIN index. Prove it helps for `%runner%` but does nothing for `%un%` (too short). What is the minimum trigram length, and which GUC controls it?
3. Take any query from this lab and flip its join order manually with `JOIN ... ON` reordering + `SET LOCAL` GUCs to *see* the alternative plan. When would you ever ship a query with planner hints?
4. Hash joins need work_mem for the build side. With 4 sorts + 2 hash joins at `work_mem=64MB` and 50 concurrent copies of the query, how much RAM could this one query shape demand? What is the sane response (hint: it is not `work_mem=2GB`)?

**Solutions:** [solutions/04-joins.md](solutions/04-joins.md)

# Lab 02 · Indexing drill: composite order, covering indexes, HOT updates

**Sessions:** one. **Goal:** stop guessing column order; prove every choice with
`EXPLAIN` and with write-side measurements.

## Part A — column-order quiz, now with evidence

From docs/04. For each query below: predict the index you'd build, then create it and
verify the plan uses it.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42 AND status = 'paid';          -- Q1

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE status = 'paid' AND total_cents > 10000
ORDER BY created_at DESC LIMIT 20;                                    -- Q2 (an index for this already exists — design it on paper first, then check)

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM order_items WHERE variant_id = 700;                     -- Q3 (already indexed — check shape)

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 42 ORDER BY occurred_at DESC LIMIT 20;  -- Q4

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM products WHERE name ILIKE '%runner%';                   -- Q5

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE EXTRACT(year FROM occurred_at) = 2026;     -- Q6: sargability trap
```

Deliverables:

1. `CREATE INDEX` statements for Q1 and Q2 with your chosen column order, and the plan
   proving each is used.
2. The rewrite of Q6 that *is* indexable, and its plan.
3. One sentence on why Q4 is served perfectly by an *existing* index without creating
   anything new.

## Part B — covering index → index-only scan

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, occurred_at, status FROM orders WHERE user_id = 42;

-- give it a covering index, then re-run:
CREATE INDEX idx_orders_user_occ_status
  ON orders (user_id, occurred_at) INCLUDE (status);

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, occurred_at, status FROM orders WHERE user_id = 42;
-- Look for: Index Only Scan. Then explain why the FIRST run after creating it may
-- still show heap fetches (visibility map), and run it a third time.
```

## Part C — measure the write cost of an index

```sql
\timing on
CREATE TABLE write_cost (id bigint GENERATED ALWAYS AS IDENTITY, a int, b int, t text);
INSERT INTO write_cost (a, b, t) SELECT g % 1000, g % 100, 'x' FROM generate_series(1, 200000) g;

-- copy the table, add one index, repeat:
CREATE TABLE write_cost2 (LIKE write_cost INCLUDING ALL);
CREATE INDEX ON write_cost2 (a);
INSERT INTO write_cost2 (a, b, t) SELECT g % 1000, g % 100, 'x' FROM generate_series(1, 200000) g;

-- and one more with two:
CREATE TABLE write_cost3 (LIKE write_cost INCLUDING ALL);
CREATE INDEX ON write_cost3 (a);
CREATE INDEX ON write_cost3 (b);
INSERT INTO write_cost3 (a, b, t) SELECT g % 1000, g % 100, 'x' FROM generate_series(1, 200000) g;
```

Compare the three INSERT times. This is write amplification, measured. Then:

```sql
DROP TABLE write_cost, write_cost2, write_cost3;
```

## Part D — HOT vs non-HOT updates

```sql
CREATE TABLE hot_demo (id int PRIMARY KEY, n int, t text);
INSERT INTO hot_demo SELECT g, 0, 'x' FROM generate_series(1, 50000) g;

-- Case 1: update a column in NO index
UPDATE hot_demo SET t = 'y' WHERE id <= 50000;
SELECT pg_stat_get_tuples_hot_updated('hot_demo'::regclass) AS hot_updates;

-- Case 2: index the column you update
CREATE INDEX ON hot_demo (n);
UPDATE hot_demo SET n = n + 1 WHERE id <= 50000;
SELECT pg_stat_get_tuples_hot_updated('hot_demo'::regclass) AS hot_updates;
-- Which case updated fewer index structures? What does HOT skip?
```

## Exercises

1. The ops dashboard runs `SELECT id FROM orders WHERE status = 'pending' ORDER BY created_at LIMIT 50` constantly. Which existing index serves it, and what does `LIMIT` change about the scan? Verify.
2. `idx_orders_status_created` will suffer from status churn (HOT broken). Measure it: update 5,000 orders' statuses, check `pg_stat_get_tuples_hot_updated('orders'::regclass)` and the index size before/after (`pg_relation_size('idx_orders_status_created'::regclass)`).
3. When would you add an index *only* for a nightly report instead of keeping it? (There is a PG feature for this.)
4. Find the two largest indexes in the schema (`pg_relation_size`) and argue for or against each.

**Solutions:** [solutions/02-indexing.md](solutions/02-indexing.md)

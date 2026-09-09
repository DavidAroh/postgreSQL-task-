# Lab 08 · Optimistic locking & the N+1 problem

**Sessions:** two (A and B) for Part A; one for Part B. **Goal:** implement
version-checked updates with retries, then create and cure N+1.

## Part A — optimistic locking on the catalogue

Product names are edited by multiple admins. Conflict rate is low → retrying is
better than blocking.

```sql
ALTER TABLE products ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;
```

The canonical optimistic UPDATE (run in both sessions against product 500):

```sql
-- Session A                                -- Session B
SELECT id, name, version FROM products WHERE id = 500;   -- both see version=1
UPDATE products
   SET name = 'A was here', version = version + 1
 WHERE id = 500 AND version = 1;             -- 1 row updated
SELECT id, name, version FROM products WHERE id = 500;
                                             UPDATE products
                                              SET name = 'B was here', version = version + 1
                                              WHERE id = 500 AND version = 1;   -- 0 rows!
                                             -- B reloads and retries with version=2:
                                             UPDATE products
                                              SET name = 'B wins', version = version + 1
                                              WHERE id = 500 AND version = 2;   -- 1 row
```

The retry loop every app needs around this (pseudo-code; write it in your language):

```
for attempt in 1..3:
    row = SELECT name, version ...
    if row is null: 404
    result = UPDATE ... WHERE id=? AND version=?
    if result.rowcount == 1: return ok
    sleep(50ms * attempt)   # jitter, backoff
return 409 Conflict
```

**When would you NOT use optimistic locking here?** (Think: 500 admins hitting the
same product every second — what does the retry storm do to the database compared to
one queue of `FOR UPDATE`?)

## Part B — create the N+1 problem, then cure it

The classic application bug, reproduced entirely in SQL shape:

```sql
-- The "N+1": 1 query for the list, then 1 query per row for details
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id,
       (SELECT count(*) FROM orders o WHERE o.user_id = u.id) AS n_orders,
       (SELECT max(o.total_cents) FROM orders o WHERE o.user_id = u.id) AS biggest
FROM users u WHERE u.status = 'active';
-- Read the plan: how many SUBPLAN nodes? How many total loops (each loop = one
-- variant of the subquery = one "round trip" from the app)?

-- Cure 1: one query, joins + GROUP BY
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, count(o.id), max(o.total_cents)
FROM users u LEFT JOIN orders o ON o.user_id = u.id
WHERE u.status = 'active'
GROUP BY u.id;

-- Cure 2: LATERAL, one aggregate per user but a single statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, s.n, s.biggest
FROM users u
CROSS JOIN LATERAL (
  SELECT count(*) AS n, max(o.total_cents) AS biggest
  FROM orders o WHERE o.user_id = u.id
) s
WHERE u.status = 'active';
-- Which cured query is better when: (a) 400 users, (b) 40,000 users, (c) only
-- the first 20 users of a paginated list? "It depends" — but say on WHAT.
```

ORM-shaped N+1 (recognise the pattern in code review):

```python
for user in session.query(User).filter(User.status == 'active'):
    print(user.id, len(user.orders))   # lazy load per user!
```

Fixes, in preference order: eager load (`selectinload`/`joinedload`), a join+GROUP BY,
or a batched second query (`WHERE user_id = ANY($1)` — one extra round trip, not N).

## Exercises

1. Add optimistic locking to `cart_items.qty` updates. Why is this a *terrible* fit compared to lab 07's atomic UPDATE? (Consider: who retries, and what does a cart update conflict even mean?)
2. Find the actual number of queries your favourite ORM issues for the Part B loop (turn on statement logging in the container: `ALTER SYSTEM SET log_statement='all'; SELECT pg_reload_conf();` — remember to turn it off).
3. A junior proposes `SELECT ... FOR UPDATE` instead of version columns "because it's simpler". Give the two strongest cases FOR their claim, and the case that kills it.
4. Prove the batching fix: write the `= ANY(...)` version of the N+1 cure for 400 users in 2 statements and time both shapes.

**Solutions:** [solutions/08-optimistic-locking.md](solutions/08-optimistic-locking.md)

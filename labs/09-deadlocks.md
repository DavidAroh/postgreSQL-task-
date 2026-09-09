# Lab 09 · Deadlocks: build one, then break it

**Sessions:** two (A and B). **Goal:** create a genuine deadlock, watch PostgreSQL
detect it, then apply the three preventions.

## Part A — build the deadlock

Two orders, two items each; both sessions update *both* orders' items, in opposite
order:

```sql
-- A                                        -- B
BEGIN;
UPDATE order_items SET qty = qty
 WHERE order_id = 100 AND line_no = 1;      -- A holds order 100 line 1
                                             BEGIN;
                                             UPDATE order_items SET qty = qty
                                              WHERE order_id = 101 AND line_no = 1;  -- B holds 101
UPDATE order_items SET qty = qty
 WHERE order_id = 101 AND line_no = 1;      -- A waits for B
                                             UPDATE order_items SET qty = qty
                                              WHERE order_id = 100 AND line_no = 1;  -- B waits for A
-- ~1 second later (deadlock_timeout), ONE session gets:
-- ERROR:  deadlock detected
-- DETAIL:  Process X waits for ShareLock on transaction Y; blocked by process Z.
```

While it is happening (a third session), see it from the outside:

```sql
SELECT blocked.pid, blocking.pid AS blocked_by, blocked.state,
       left(blocked.query, 50) AS blocked_query
FROM pg_stat_activity blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) bp ON true
JOIN pg_stat_activity blocking ON blocking.pid = bp
WHERE blocked.datname = 'advdb';
```

Note the timing: detection is *not* instant — that is `deadlock_timeout = 1s`
(trade-off: shorter = faster detection, more false-positive CPU probing).

## Part B — prevention 1: consistent lock ordering

Same work, both sessions touch orders in ascending id order. Rerun Part A's flow with
both sessions doing `order_id = 100` first, then `101`. No deadlock — the second
transaction simply queues. This is the whole fix, and it must be a *team-wide
convention* (it cannot be enforced by the database).

## Part C — prevention 2: shrink the critical section

```sql
-- Do the lock and the write in one statement; nothing between BEGIN and COMMIT:
UPDATE order_items SET qty = qty + 1 WHERE order_id = 100 AND line_no = 1;
```

Two single-statement transactions cannot hold-and-wait (Coffman condition broken).

## Part D — prevention 3: lock everything up front

```sql
BEGIN;
SELECT * FROM orders WHERE id IN (100, 101) ORDER BY id FOR UPDATE;  -- both, ordered, now
-- ... do all the work ...
COMMIT;
-- The application-level locks match the database's; no interleaving is possible.
```

## Part E — the FK surprise deadlock

FK checks take `FOR KEY SHARE` on parent rows. Try to create a deadlock from *pure
inserts*:

```sql
-- A                                        -- B
BEGIN;
INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name, qty, unit_price_cents)
VALUES (100, 7, 1, 'X', 'X', 1, 100);       -- FK KEY SHARE on order 100
                                             BEGIN;
                                             INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name, qty, unit_price_cents)
                                             VALUES (101, 7, 1, 'X', 'X', 1, 100);
UPDATE orders SET status = 'cancelled'
 WHERE id = 101;                             -- A wants order 101 too? — design the collision:
ROLLBACK;
                                             ROLLBACK;
```

Design the collision yourself: A inserts item→order 100 then updates order 101;
B inserts item→order 101 then updates order 100. Explain why the FK's `FOR KEY SHARE`
participates in the wait graph (it is a lock the UPDATE cannot share with an
inserting child that references the row).

## Exercises

1. Your app deadlocks weekly under load. You cannot change the code this sprint. What two server-side knobs reduce the blast radius, and what do they NOT fix? (`deadlock_timeout`, `lock_timeout` on the app role — set both with `ALTER ROLE app SET ...` and test.)
2. Prove that `SELECT ... FOR UPDATE` deadlocks can happen on *unread* rows: two sessions each `FOR UPDATE` a row the other will later need. Then fix with Part D.
3. Why is "retry on deadlock" (error 40P01) a standard app feature, while "retry on constraint violation" usually is not? What does retrying the latter mean the app is doing wrong?

**Solutions:** [solutions/09-deadlocks.md](solutions/09-deadlocks.md)

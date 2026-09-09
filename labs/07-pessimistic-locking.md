# Lab 07 · Pessimistic locking & race conditions: the overselling lab

**Sessions:** two (A and B). **Goal:** create a real lost update, then fix it three
ways, and know when each fix is the right one.

## Part A — cause the race (the check-then-act anti-pattern)

```sql
-- A                                        -- B
BEGIN;
SELECT quantity FROM inventory
 WHERE variant_id = 5;                       -- suppose it says 10
                                             BEGIN;
                                             SELECT quantity FROM inventory
                                              WHERE variant_id = 5;   -- also 10
UPDATE inventory SET quantity = quantity - 8
 WHERE variant_id = 5;                       -- ok, 10-8
                                             UPDATE inventory SET quantity = quantity - 8
                                              WHERE variant_id = 5;   -- 10-8 ... but from 2!
COMMIT;
                                             COMMIT;
SELECT quantity FROM inventory WHERE variant_id = 5;   -- ???
-- Was the CHECK (quantity >= 0) violated? What was the final value?
-- Both sessions "checked first". Explain exactly where the check went wrong.
```

(If B blocks, that is the *implicit row lock* of A's UPDATE — B's UPDATE waits; the
bug is that B read 10 *before* A committed. Re-do it carefully in that order.)

## Part B — fix 1: atomic predicate UPDATE (usually the best fix)

```sql
-- Both sessions, independently, no explicit transaction needed:
UPDATE inventory
   SET quantity = quantity - 8, updated_at = now()
 WHERE variant_id = 5 AND quantity >= 8;
-- Second session updates 0 rows. Check rowcount in your driver: 0 = "sold out",
-- no exception, no retry, no lock held longer than the statement.
```

Why this works under READ COMMITTED: the row lock serialises the two updates and the
second re-evaluates the WHERE against the *new* row version (EvalPlanQual).

## Part C — fix 2: pessimistic `SELECT ... FOR UPDATE`

```sql
-- A                                        -- B
BEGIN;
SELECT quantity FROM inventory
 WHERE variant_id = 6 FOR UPDATE;            -- A holds the row lock
                                             BEGIN;
                                             SELECT quantity FROM inventory
                                              WHERE variant_id = 6 FOR UPDATE;  -- BLOCKS
UPDATE inventory SET quantity = quantity - 5
 WHERE variant_id = 6;
COMMIT;
                                             -- unblocked now; re-read shows the new value
                                             SELECT quantity FROM inventory WHERE variant_id = 6;
                                             UPDATE inventory SET quantity = quantity - 5
                                              WHERE variant_id = 6;
                                             COMMIT;
```

This is the *general* tool: read whatever you need under the lock, decide anything,
then write. Costs: lock wait chains, and the connection is held while B waits.

## Part D — the two fix patterns compared (fill this table in your notes)

| | atomic predicate | FOR UPDATE |
|---|---|---|
| Blocks concurrent writers? | | |
| Needs a transaction? | | |
| Can decide on data *other than* the locked row? | | |
| Best for | | |
| Failure mode at high contention | | |

## Part E — feel the queue

```sql
-- A: lock a row and hold the transaction open
BEGIN;
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
-- B and C (a third session!): both run
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;   -- one errors immediately
-- then, without NOWAIT, from B and C:
SELECT * FROM orders WHERE id = 100 FOR UPDATE;          -- both queue, FIFO-ish
-- A: COMMIT. Watch B and C serialise. Check the queue while it happens (session D):
SELECT pid, wait_event_type, wait_event, state, left(query, 60)
FROM pg_stat_activity WHERE state <> 'idle';
ROLLBACK;
```

## Exercises

1. The cart: two devices, same user, same cart, adding the same variant simultaneously. Which constraint + which statement shape makes the final qty deterministic? Write the statement.
2. Stock is held for 15 minutes during payment (a "reservation"). Model it with the `reserved` column: write the reserve and the release transactions, and reason about a crashed client (who releases?).
3. Prove that `FOR UPDATE` does NOT block plain `SELECT` (two sessions: A locks, B plain-selects, note zero blocking). Why is this correct even though B's data is mid-change?
4. `SELECT ... FOR UPDATE` on zero rows (variant doesn't exist) locks nothing — two sessions can then both "reserve" a nonexistent variant after a fresh INSERT. What is the fix for the "reserve a row that may not exist yet" problem? (Hint: `INSERT ... ON CONFLICT ... FOR UPDATE` in a CTE, or predicate locks via SERIALIZABLE — try both, pick one, defend it.)

**Solutions:** [solutions/07-pessimistic-locking.md](solutions/07-pessimistic-locking.md)

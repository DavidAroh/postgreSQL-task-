# Lab 06 · Isolation levels: reproduce each anomaly

**Sessions:** two, side by side (A and B). Run each scenario top-to-bottom in the
order numbered, alternate as marked, and WRITE DOWN what each session *saw* before
reading the solution.

## Scenario 1 — dirty reads don't exist (verify the impossibility)

```sql
-- A                                     -- B
BEGIN;                                    BEGIN;
UPDATE inventory SET quantity = 999
 WHERE variant_id = 2;
                                          SELECT quantity FROM inventory WHERE variant_id = 2;
                                          -- what does B see? (old value — uncommitted data invisible)
ROLLBACK;
                                          COMMIT;
```

## Scenario 2 — non-repeatable read (READ COMMITTED allows it)

```sql
-- A                                     -- B
BEGIN;
SELECT quantity FROM inventory WHERE variant_id = 3;   -- note it
                                          UPDATE inventory SET quantity = quantity + 50
                                           WHERE variant_id = 3;
                                          COMMIT;
SELECT quantity FROM inventory WHERE variant_id = 3;   -- ???
COMMIT;
```

Repeat Scenario 2 but `BEGIN ISOLATION LEVEL REPEATABLE READ` in A. What changed, and
what error did B (still READ COMMITTED) hit or not hit?

## Scenario 3 — lost update (the famous one)

```sql
-- A                                     -- B
BEGIN;
SELECT quantity FROM inventory WHERE variant_id = 4;   -- note the value (10)
                                          BEGIN;
                                          SELECT quantity FROM inventory WHERE variant_id = 4;  -- also 10
UPDATE inventory SET quantity = 8
 WHERE variant_id = 4;                    UPDATE inventory SET quantity = 5
                                           WHERE variant_id = 4;   -- blocks until A commits
COMMIT;
                                          -- unblocked: UPDATE applied. Final value?
                                          COMMIT;
SELECT quantity FROM inventory WHERE variant_id = 4;
-- You "decremented" twice (10→8 and 10→5). The final value is 5, not 3.
```

You decremented twice (30−2 and 30−5) and got **one** decrement. Now re-run the whole
scenario with `BEGIN ISOLATION LEVEL REPEATABLE READ` in **both** sessions — you will
meet `could not serialize access due to concurrent update`. One of you must retry.

## Scenario 4 — write skew (the phantom-level surprise)

Business rule: "at least one of products 500 and 501 must stay active."

```sql
-- A                                     -- B
BEGIN ISOLATION LEVEL REPEATABLE READ;    BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM products
 WHERE id IN (500, 501)
   AND status = 'active';   -- 2          SELECT count(*) FROM products
                                          WHERE id IN (500, 501)
                                            AND status = 'active';   -- 2
UPDATE products SET status = 'archived'
 WHERE id = 500;                          UPDATE products SET status = 'archived'
                                           WHERE id = 501;
COMMIT;
                                          COMMIT;   -- ???
SELECT status FROM products WHERE id IN (500, 501);
```

Both transactions read "2 active", each archives *a different one*, both commit:
the invariant "at least one active" is broken while neither statement touched the
other's row. That is write skew — REPEATABLE READ does not catch it because there
is no RW conflict on a shared row.
Now re-run with `SERIALIZABLE` in both — one gets `could not serialize access due to
read/write dependencies among transactions`. That error IS the feature.

## Scenario 5 — SERIALIZABLE in practice

```sql
-- Both sessions:
BEGIN ISOLATION LEVEL SERIALIZABLE;
-- re-run scenario 3's flow. Whoever loses gets:
-- ERROR: could not serialize access due to read/write dependencies among transactions
-- The winner's app must RETRY the whole transaction. Discuss: is a retry loop
-- acceptable for a checkout? What is your retry budget and backoff?
```

## Exercises

1. Re-implement Scenario 3's business action as the atomic pattern (`UPDATE ... WHERE quantity >= 2` minus branch) — show that READ COMMITTED now yields the correct final value with zero errors. Why did isolation level stop mattering?
2. `SELECT ... FOR SHARE` on products 500/501 in Scenario 4's reads: does that fix write skew at REPEATABLE READ? Try it. What does it cost under high read concurrency?
3. Your CEO demands `dirty reads` "for performance". What do you tell them? (There is literally no knob — explain why PG doesn't offer it.)
4. For the checkout in lab 05: which isolation level does it need, given its updates are all atomic-pattern? Prove your answer by running it under each level.

**Solutions:** [solutions/06-isolation.md](solutions/06-isolation.md)

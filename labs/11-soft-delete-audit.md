# Lab 11 · Soft deletes and audit history

**Sessions:** one. **Goal:** implement the full soft-delete lifecycle and produce a
point-in-time view of a row from the audit trail.

## Part A — the soft-delete lifecycle

```sql
-- The standard query mistakenly includes deleted users? No — look at the data first:
SELECT status, count(*) FROM users GROUP BY status;

-- The trap: an admin tool that forgets the predicate
SELECT count(*) FROM users u
JOIN orders o ON o.user_id = u.id;      -- includes banned/deleted users' orders: fine or bug? Decide and write down WHY.

-- Soft delete as an UPDATE (users have no rows deleted — ever):
BEGIN;
UPDATE users SET status = 'deleted' WHERE id = 350;
-- What did NOT happen: no FK fired, no cascade, nothing lost. Verify:
SELECT id, status FROM users WHERE id = 350;
SELECT count(*) FROM orders WHERE user_id = 350;    -- orders still exist: correct? discuss
COMMIT;

-- The UNIQUE trap (docs/07): can a deleted user's email be re-registered?
SELECT id, email FROM users WHERE email = 'user350@example.com';
-- Imagine re-registration with that email. With plain UNIQUE(email) it fails.
-- What would the standard partial-index fix look like? Sketch:
--   UNIQUE index on (email) WHERE status <> 'deleted'
-- Why is that not applied here? (hint: seed uniqueness is on citext; changing
-- constraint shapes on live tables = docs/07 migration discipline)
```

## Part B — hard delete vs soft delete, measured

```sql
-- Cascade cost of a hard delete (on a throwaway user with orders):
BEGIN;
DELETE FROM users WHERE id = 400;
-- How many rows vanished across how many tables? (Check order_items, payments, refunds.)
ROLLBACK;
-- Soft delete cost: one UPDATE. That is the whole trade: storage/bloat vs a cascade
-- storm and unrecoverable data.
```

## Part C — audit trail: reconstruct history

```sql
-- What U/D activity exists?
SELECT table_name, op, count(*) FROM audit_log GROUP BY 1, 2;

-- Full history of one order line (seeded rows wrote audit entries):
SELECT occurred_at, op, old_data->>'qty' AS old_qty, new_data->>'qty' AS new_qty
FROM audit_log
WHERE table_name = 'order_items' AND row_pk = '<pick one from above>'
ORDER BY occurred_at;

-- Point-in-time reconstruction: latest state of the row before a given time
SELECT new_data
FROM audit_log
WHERE table_name = 'order_items' AND row_pk = '<same>'
  AND occurred_at <= now() - interval '1 hour'
ORDER BY occurred_at DESC LIMIT 1;
-- Write the query that reconstructs the CURRENT state: latest U's new_data,
-- or the last D's old_data if the row was deleted. (This is your mini temporal table.)
```

## Part D — watch the live trigger work

```sql
UPDATE order_items SET qty = qty + 1 WHERE order_id = 42 AND line_no = 1;
SELECT * FROM audit_log WHERE table_name = 'order_items'
ORDER BY id DESC LIMIT 1;    -- old_data vs new_data, both JSONB

-- And the totals trigger kept the denormalisation honest:
SELECT subtotal_cents, total_cents FROM orders WHERE id = 42;
SELECT sum(qty * unit_price_cents) FROM order_items WHERE order_id = 42;  -- equal
```

Try to cheat the audit:

```sql
DELETE FROM audit_log WHERE id = (SELECT max(id) FROM audit_log);   -- silently no-op (RULE)
UPDATE audit_log SET new_data = '{}' WHERE id = (SELECT max(id) FROM audit_log);
SELECT count(*) FROM audit_log WHERE id = (SELECT max(id) FROM audit_log);   -- still there
```

## Exercises

1. Add `deleted_at timestamptz` to `products` and make every catalogue query exclude it — but prove the *order history* still shows deleted products (why do order_items snapshots make this safe?).
2. GDPR erasure request for user 351: design the procedure (what is deleted, what is anonymised, what is retained and why — orders are financial records). Write the transaction.
3. The audit_log grows forever. Design retention: monthly partitioning + a drop policy vs DELETE batches. Which is right, and why does DELETE on a huge append-only table hurt (docs/01 bloat, autovacuum)?
4. Your PM asks "what did order 42 look like on March 1st?" — write that query from `audit_log`, then list what would make it *impossible* to answer (which events are missing from the trail by design?).

**Solutions:** [solutions/11-soft-delete-audit.md](solutions/11-soft-delete-audit.md)

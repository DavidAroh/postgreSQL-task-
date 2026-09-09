# Lab 01 · Constraints as executable documentation

**Sessions:** one. **Goal:** feel each constraint fail, then see why app-level checks
are not enough.

## Part A — watch them fire

Run each statement, read the error message, and name the constraint that fired:

```sql
-- 1. UNIQUE(user_id, label): a user cannot have two 'home' addresses
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
VALUES (1, 'home', '1 main st', 'Berlin', '10115', 'DE', false);

-- 2. Partial unique index: a user cannot have two defaults
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
VALUES (1, 'holiday', '2 main st', 'Berlin', '10115', 'DE', true);

-- 3. CHECK: quantity can never go negative
UPDATE inventory SET quantity = quantity - 999999 WHERE variant_id = 1;

-- 4. CHECK: reserved cannot exceed quantity
UPDATE inventory SET reserved = 100, quantity = 50 WHERE variant_id = 1;

-- 5. CHECK: SKU format
INSERT INTO product_variants (product_id, sku, price_cents)
VALUES (1, 'cheap-shoe', 1000);

-- 6. citext: case-insensitive uniqueness
SELECT count(*) FROM users WHERE email = 'USER1@EXAMPLE.COM';

-- 7. FK: orders point at real users
INSERT INTO orders (user_id, status) VALUES (999999, 'pending');
-- (fails for a second reason at COMMIT — which one? see Part C)

-- 8. Partial unique index: one successful payment per order
INSERT INTO payments (order_id, status, amount_cents, provider)
SELECT id, 'succeeded', total_cents, 'dup' FROM orders WHERE id = 2;

-- 9. Append-only audit log
UPDATE audit_log SET row_pk = 'hacked' WHERE id = 1;
DELETE FROM audit_log WHERE id = 1;
```

## Part B — upserts built on constraints

```sql
-- "Add to cart" as one idempotent statement (constraint: cart_items UNIQUE(cart_id, variant_id))
WITH cart AS (
  SELECT id FROM carts WHERE user_id = 1 AND status = 'open' LIMIT 1
)
INSERT INTO cart_items (cart_id, variant_id, qty, price_cents)
SELECT cart.id, 5, 1, (SELECT price_cents FROM product_variants WHERE id = 5)
FROM cart
ON CONFLICT (cart_id, variant_id)
DO UPDATE SET qty = cart_items.qty + EXCLUDED.qty
RETURNING id, variant_id, qty;

-- Run it twice. What happened to qty? Now try variant 1 (may not exist in the cart yet).
```

## Part C — the "check-then-act" anti-pattern, demonstrated

```sql
-- This "works" in every codebase and is still wrong:
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM payments
   WHERE order_id = 3 AND status = 'succeeded';
  IF v_count = 0 THEN
    -- pretend another request fires this same block 1ms later, concurrently:
    INSERT INTO payments (order_id, status, amount_cents, provider)
    VALUES (3, 'succeeded', 100, 'racy');
  END IF;
END $$;

SELECT * FROM payments WHERE order_id = 3;
-- Which constraint saved you here? (Look at the error from #8 again.)
```

The point: for cross-row invariants, the database is the *only* component that sees
all writers. App-level checks are optimisations for nice error messages, not
correctness mechanisms.

## Exercises (write answers in your notes)

1. Add a constraint so a product cannot have two variants with the same
   `attributes` JSONB. *(Hint: UNIQUE on a generated column or an expression
   index — try `CREATE UNIQUE INDEX ... ON product_variants (product_id, (attributes::text))` —
   what are the weaknesses of the text cast?)*
2. A PM wants: "a variant can go on sale, but never below cost". Model it: add a
   `cost_cents` column and the constraint. What happens to existing rows when you
   add the constraint?
3. `cart_items.qty > 0` — but carts should cap at 10 units per line. CHECK can't see
   other rows, so... where does this rule live? Defend your choice.
4. Why is `payments_one_success_per_order` a *partial* index? What would a full
   `UNIQUE (order_id, status)` (without the WHERE) break?
5. Delete `users` id 1 in a transaction and look at the row counts before COMMIT:
   what cascaded, and what didn't? Why do orders survive?

**Solutions:** [solutions/01-constraints.md](solutions/01-constraints.md)

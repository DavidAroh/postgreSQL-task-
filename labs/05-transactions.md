# Lab 05 · Transactions: atomicity you can watch fail

**Sessions:** one. **Goal:** internalise BEGIN/COMMIT/ROLLBACK, deferred constraints,
and why "one transaction per business operation" is a design rule, not a slogan.

## Part A — all or nothing

```sql
BEGIN;
UPDATE inventory SET quantity = quantity - 1 WHERE variant_id = 1;
INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name, attributes, qty, unit_price_cents)
VALUES (1, 9, 1, 'VEN-XXX-009', 'Ghost line', '{}', 1, 100);
SELECT * FROM order_items WHERE order_id = 1 AND line_no = 9;   -- visible in here
ROLLBACK;
SELECT * FROM order_items WHERE order_id = 1 AND line_no = 9;   -- gone
SELECT quantity FROM inventory WHERE variant_id = 1;            -- restored
```

Now the same, but `COMMIT` instead of `ROLLBACK`, and check the order total trigger
fired (`SELECT subtotal_cents, total_cents FROM orders WHERE id = 1;`). *Restore the
data afterwards: delete the ghost line and re-check totals.*

## Part B — deferred constraints

The orders→items FK is `DEFERRABLE INITIALLY DEFERRED` (008):

```sql
BEGIN;
INSERT INTO orders (user_id, status) VALUES (1, 'pending');   -- no items yet!
-- FK not checked yet. What does SELECT max(id) FROM orders say?
SELECT id FROM orders WHERE user_id = 1 ORDER BY id DESC LIMIT 1;  -- note the id
INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name, attributes, qty, unit_price_cents)
SELECT max(id), 1, 5, v.sku, p.name, v.attributes, 1, v.price_cents
FROM orders, product_variants v JOIN products p ON p.id = v.product_id
WHERE v.id = 5
GROUP BY v.sku, p.name, v.attributes, v.price_cents;
COMMIT;   -- both checks (FK + totals trigger) resolve here
```

Now break it:

```sql
BEGIN;
INSERT INTO orders (user_id, status) VALUES (1, 'pending');
SET CONSTRAINTS orders_must_have_first_item IMMEDIATE;   -- force the check now
-- ROLLBACK; -- (it already fired — read the error)
ROLLBACK;
```

Deliverable: one paragraph — when is `INITIALLY IMMEDIATE` the better default for a
deferrable constraint, even though it forbids "parent first, children later"?

## Part C — the checkout as one transaction

This is the practical task's transactional operation. Write `checkout(cart_id)` as a
single SQL transaction that, atomically:

1. locks the cart row `FOR UPDATE` (or proves the pattern unnecessary — decide!);
2. verifies every cart line's variant is active and has stock;
3. decrements `inventory.quantity` atomically (docs/06: self-contained UPDATE);
4. inserts `order_items` with snapshots + the `orders` row (deferred FK order!);
5. marks the cart `ordered`;
6. and refuses (RAISE) if anything is off — leaving *no* partial state.

Skeleton (complete it, then run it twice concurrently in two sessions on the same
cart — only one checkout may win):

```sql
CREATE OR REPLACE FUNCTION checkout(p_cart_id uuid)
RETURNS bigint  -- order id
LANGUAGE plpgsql AS $$
DECLARE
  v_order_id bigint;
  v_user_id  bigint;
BEGIN
  -- 1..6 here
  RETURN v_order_id;
END $$;
```

Test harness (pick a cart first — e.g. `SELECT id FROM carts WHERE user_id = 1 AND status = 'open';`):

```sql
-- Session A                            -- Session B
BEGIN;                                   BEGIN;
SELECT checkout('<cart-uuid>');          SELECT checkout('<same-cart-uuid>');
COMMIT;                                  COMMIT;
-- Exactly one session must succeed end-to-end. Which line made that true?
```

## Exercises

1. Move the stock decrement to *before* the cart lock. Does the double-checkout still resolve safely? Why, given both paths run the identical atomic UPDATE?
2. A teammate wraps each HTTP request in one transaction "for convenience". List three ways this hurts (hint: docs/07 pooling, locks, WAL).
3. What does `COMMIT` durably guarantee (docs/01) that `UPDATE` alone does not?
4. Delete-then-reinsert the same `cart_items` row inside one transaction vs two — which constraint notices the difference? Why?

**Solutions:** [solutions/05-transactions.md](solutions/05-transactions.md)

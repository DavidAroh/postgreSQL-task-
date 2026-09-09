# Solutions · Lab 05

**Part A:** inside the transaction the ghost line is visible (own snapshot);
after ROLLBACK both the line and the inventory decrement are gone — atomicity.
After COMMIT + cleanup, the totals trigger had already added the ghost line's value
to `orders.total_cents`; deleting the line fires the trigger again and restores it.

**Part B:** the INSERT of the order succeeds (FK deferred); `SELECT max(id)` inside
the transaction sees it; the item insert + totals trigger all queue up; at COMMIT
the FK check runs against committed-visible data including this transaction's own
inserts — passes. Breaking it: `SET CONSTRAINTS orders_must_have_first_item
IMMEDIATE` forces the check at that statement → fails right there with
`insert or update on table "orders" violates foreign key constraint`.
When INITIALLY IMMEDIATE is better: whenever errors should surface at the offending
statement (most app code), and whenever later statements depend on the invariant
already holding (e.g. the totals trigger reading items).

**Part C — reference checkout implementation:**

```sql
CREATE OR REPLACE FUNCTION checkout(p_cart_id uuid)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  v_order_id bigint;
  v_user_id  bigint;
  v_line     int := 0;
  r          record;
BEGIN
  -- Lock the cart row AND require it to still be open: a concurrent checkout
  -- blocks here, then re-evaluates status after the winner commits (EvalPlanQual)
  -- and gets NOT FOUND -> clean failure instead of a double order.
  SELECT user_id INTO v_user_id
  FROM carts
  WHERE id = p_cart_id AND status = 'open'
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'cart % not open', p_cart_id; END IF;

  DROP TABLE IF EXISTS _lines;   -- idempotent if called twice in one session
  CREATE TEMP TABLE _lines ON COMMIT DROP AS
    SELECT ci.variant_id, ci.qty, ci.price_cents
    FROM cart_items ci WHERE ci.cart_id = p_cart_id;

  IF NOT EXISTS (SELECT 1 FROM _lines) THEN
    RAISE EXCEPTION 'cart % is empty', p_cart_id;
  END IF;

  -- Atomic stock decrement: second concurrent checkout gets 0 rows and RAISEs.
  FOR r IN SELECT * FROM _lines LOOP
    UPDATE inventory
       SET quantity = quantity - r.qty, updated_at = now()
     WHERE variant_id = r.variant_id AND quantity - r.qty >= 0;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'insufficient stock for variant %', r.variant_id;
    END IF;
  END LOOP;

  INSERT INTO orders (user_id, cart_id, status, currency, shipping_name)
  VALUES (v_user_id, p_cart_id, 'pending', 'USD', 'checkout')
  RETURNING id INTO v_order_id;

  FOR r IN SELECT * FROM _lines LOOP
    v_line := v_line + 1;
    INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name,
                             attributes, qty, unit_price_cents)
    SELECT v_order_id, v_line, r.variant_id, v.sku, p.name, v.attributes,
           r.qty, r.price_cents
    FROM product_variants v JOIN products p ON p.id = v.product_id
    WHERE v.id = r.variant_id;
  END LOOP;

  UPDATE carts SET status = 'ordered' WHERE id = p_cart_id;
  RETURN v_order_id;
END $$;
```

Notes on the design decisions:

- The cart row lock (`FOR UPDATE`) serialises concurrent checkouts *of the same
  cart*; two sessions then race only on the atomic UPDATEs, where the loser gets
  `NOT FOUND` → exception → whole transaction rolls back (deferred FK and totals
  trigger included). No partial state is possible.
- All writes are atomic-pattern or protected by the cart lock — safe at READ
  COMMITTED (lab 06 #4).
- `ON COMMIT DROP` temp table keeps the loop reads stable; in production you'd
  likely write this as a single CTE chain to avoid plpgsql row loops entirely.

**Exercises:**

1. Still safe: both sessions may pass stock decrement before either locks the cart,
   but the second cart-lock holder re-evaluates stock again in its own loop (the
   atomic predicate still guards), so overselling is impossible; only the *user
   experience* (double-charging attempts) changes. The invariant lives in the
   predicate, not the lock order.
2. Per-request transactions hold locks across the request's entire duration
   (including external calls), hold pooler connections (transaction-pooling
   incompatible), and bloat WAL/idle-in-transaction timeouts. Fine-grained
   transactions around each business op.
3. COMMIT fsyncs WAL: durable across crash/power loss. A bare UPDATE returns after
   the change is in shared buffers/WAL buffer — visible immediately, but not
   durable until commit.
4. Two transactions: the UNIQUE(order_id, line_no) constraint doesn't notice
   (delete frees the key); the reversed FK does — at COMMIT, first_line_no must
   still match a line (if line 1 was deleted and line 2 reinserted, first_line_no=1
   dangles). One transaction is atomic so observers see either state; two
   transactions create a window where the order violates its own invariant.

# Solutions · Lab 01

**Part A expected errors:**

1. `duplicate key value violates unique constraint "addresses_user_label_key"`
2. `duplicate key value violates unique constraint "addresses_one_default_per_user"`
3. `new row for relation "inventory" violates check constraint "inventory_quantity_check"`
4. `violates check constraint "inventory_reserved_le_quantity_check"`
5. `violates check constraint "product_variants_sku_format_check"`
6. Returns 1 — citext matched `user1@example.com` case-insensitively.
7. FK first (`orders_user_id_fkey`); the second reason at COMMIT is the deferred
   `orders_must_have_first_item` FK — no items exist for the new order.
8. `duplicate key value violates unique constraint "payments_one_success_per_order"`
9. Both silently no-op (INSTEAD NOTHING rules) — audit_log is append-only.

**Part B:** running twice shows `qty = 2` for variant 5 — ON CONFLICT took the UPDATE
arm using EXCLUDED.qty. Variant 1: if not already in the cart, a new row is inserted
(ON CONFLICT only fires on the constraint breach).

**Part C:** the "check" (`SELECT count(*)`) and the "act" (INSERT) are two statements;
between them the other request's INSERT can commit. The partial unique index
`payments_one_success_per_order` converts the race into a constraint violation for
exactly one of the two writers. In `DO` blocks the second run fails loudly — in an
app, handle the unique violation as "payment already exists" (idempotency), never
re-try blindly.

**Exercises:**

1. `CREATE UNIQUE INDEX idx_variants_product_attrs ON product_variants (product_id, (attributes::text));`
   Weaknesses: JSONB text cast is key-order/whitespace-sensitive (`{"a":1,"b":2}` vs
   `{"b":2,"a":1}` are "different"), and the cast is opaque to the planner for
   lookups. Cleaner: normalise attributes into (key,value) child rows with a
   composite unique key.
2. `ALTER TABLE product_variants ADD COLUMN cost_cents integer;`
   `ALTER TABLE product_variants ADD CONSTRAINT price_ge_cost CHECK (price_cents >= cost_cents) NOT VALID;`
   then `ALTER TABLE ... VALIDATE CONSTRAINT ...` (takes only a SHARE UPDATE EXCLUSIVE
   lock; rows violating it surface *now* and must be fixed first — the NOT VALID
   dance is also the answer to "what happens to existing rows").
3. `CHECK (qty <= 10)` — it's single-row, so a CHECK *does* work. The exercise's real
   target was the cap "per order" (sum over rows) — that one is cross-row: trigger on
   cart_items or a materialised cart_totals table maintained in-transaction.
4. A full `UNIQUE (order_id, status)` allows only ONE row per (order, status) pair —
   so an order could never have two *failed* attempts, and once 'succeeded' existed
   the row could never... actually the killer: status rows are immutable
   (`initiated` → `succeeded` would need delete+insert, which the audit trail then
   can't explain). The partial index constrains exactly the invariant: one success.
5. Orders, payments, refunds, order_items survive (no CASCADE from users to orders —
   002/003 CASCADE only covers profiles/addresses). That asymmetry is deliberate:
   identity data is expendable, financial history is not.

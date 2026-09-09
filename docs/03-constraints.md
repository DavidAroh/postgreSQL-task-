# 03 · Database constraints: the schema is your first line of defence

Constraints are executable documentation. They are checked by the engine, in every code
path, forever — including the ad-hoc `psql` session at 3am during an incident. Every
constraint in this schema maps to a lab; know the **cost** of each.

## The catalogue

| Constraint | Example here | Cost at write time |
|---|---|---|
| `PRIMARY KEY` | every table (`bigint IDENTITY`) | one index insert per row |
| `UNIQUE` | `users.email`, `product_variants.sku`, `cart_items(cart_id, variant_id)` | index insert + uniqueness probe |
| `NOT NULL` | most columns | negligible |
| `CHECK` | `qty > 0`, `quantity >= 0`, `sku ~ '^VEN-...'` | per-row expression eval |
| `FK` | orders → users, cart_items → variants | shared lock on referenced row + lookup |
| Partial `UNIQUE` | "one default address" (003), "one successful payment" (009) | index insert when predicate matches |
| Trigger | `orders.total_cents` (011) | per-statement function call |

Costs are real but usually small — FKs are the most misunderstood: a *share* lock on
the parent row (no conflict with other readers/writers of the same child rows), held to
commit. FK trouble shows up as lock queues during bulk deletes, not as slow single
inserts.

## What each one buys you (concrete failures prevented)

- `CHECK (quantity >= 0)` — no stored oversold stock, *ever* (still not concurrency
  safety — lab 07).
- `UNIQUE (cart_id, variant_id)` — "add to cart twice" becomes one row with qty+1; the
  classic `ON CONFLICT DO UPDATE` upsert (010) is built on exactly this constraint.
- Partial unique "one default address" — no trigger, no app-level "check then set"
  race, impossible state.
- `citext` email — "Ana@x.com" and "ana@x.com" are one account, not two.
- The `sku ~ '^VEN-[A-Z0-9]{6}-[0-9]{3}$'` format CHECK — garbage in dies at the gate;
  note it checks *format*, not *uniqueness*.

## NOT NULL + DEFAULT: the underrated pair

`status text NOT NULL DEFAULT 'active'` does three jobs at once: documents the
vocabulary, prevents NULL-poisoned rows, and makes the "add a column with default"
migration O(1) in PG11+ (metadata-only — see docs/07 §migrations). `DEFAULT now()`
means timestamps cannot be forgotten by a new code path.

## Constraint vs trigger vs application code

Rule of thumb:

- **Single-row invariant** → CHECK / NOT NULL / UNIQUE. Always the database.
- **Cross-row invariant within a table** → UNIQUE / partial UNIQUE / exclusion
  constraint. Prefer the database.
- **Cross-table invariant** → FK, or trigger + serialisation care (the totals trigger
  takes `FOR UPDATE` on the order row first — without that lock, two concurrent item
  updates on one order could compute stale sums; lab 09 touches this).
- **Business policy that changes weekly** → application config, not the schema.

Anything you *can* push into the schema, push — the app will eventually have a second
writer (script, backfill, support tool) that doesn't know the rule.

## Deferred constraints

`DEFERRABLE INITIALLY DEFERRED` (the orders→items FK in 008) is checked at COMMIT. That
is what lets the seed insert orders before their line items. Use it sparingly: an
error at COMMIT is harder to handle than an error at statement time, and
`INITIALLY IMMEDIATE` (the default for deferrable constraints) keeps errors early.
Lab 05 demonstrates `SET CONSTRAINTS ... IMMEDIATE` to check early *inside* a
deferred transaction.

## Try this (each should fail — read the error)

```sql
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
VALUES (1, 'home', '1 st', 'Berlin', '10115', 'DE', false);   -- UNIQUE(user_id,label)

INSERT INTO product_variants (product_id, sku, price_cents)
VALUES (1, 'BAD-SKU', 100);                                   -- sku_format CHECK

UPDATE inventory SET quantity = -1 WHERE variant_id = 1;       -- quantity >= 0

INSERT INTO payments (order_id, status, amount_cents, provider)
SELECT id, 'succeeded', total_cents, 'test' FROM orders WHERE id = 1
ON CONFLICT DO NOTHING;
INSERT INTO payments (order_id, status, amount_cents, provider)
SELECT id, 'succeeded', total_cents, 'test' FROM orders WHERE id = 1;  -- partial unique
```

## Explain-back questions

1. Which constraint in this schema would you *delete* as over-engineering, and why?
2. Why is a partial unique index better than a trigger for "one default address"?
3. Your PM wants `price_cents` to also reject values above 1,000,000. CHECK or app code?
4. What breaks if the totals trigger did NOT take `FOR UPDATE` on the order row?

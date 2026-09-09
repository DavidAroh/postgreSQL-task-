# 02 · Relational data modelling, normalisation, denormalisation

## The vocabulary

- **Entity** → table. **Attribute** → column. **Relationship** → FK + (optionally) join table.
- **Cardinality**: 1:1, 1:N, M:N. **Optionality**: must/may exist on each side.
- **Candidate key** → a minimal set of columns that uniquely identifies a row. The
  **primary key** is the candidate key you *chose*; every other candidate key still
  deserves a UNIQUE constraint (`users.email` is unique even though `id` is the PK).

## Normal forms, operationally

Normalisation removes *modification anomalies* — states where a fact is stored twice
and can be updated in one place but not the other.

**1NF** — atomic values, no repeating groups. A product with `sizes text` holding
`"38,40,42"` is 1NF violation: you cannot index, constrain, or join on it. This schema
uses a **variant table** instead: each sellable (product, size, colour) is one row.

**2NF** — every non-key column depends on the *whole* key. If `order_items.total_cents`
existed as a stored column, it would depend on `qty × unit_price_cents`, not on the key
— a derived value pretending to be a fact. (It's not stored; the *order-level* total is,
for different reasons — see denormalisation below.)

**3NF** — no transitive dependencies. In `addresses`, `city → country` tempts you to
store country per city in a `cities` table. Whether you bother depends on whether city
attributes actually change; modelling for hypothetical updates is over-engineering
(3NF is the sensible default; 4/5NF matter when join tables themselves carry
multivalued facts).

**BCNF** — every determinant is a candidate key. Matters when you have composite keys;
this schema's composite keys (`order_items(order_id, line_no)`) are clean.

## The relationships in this schema (say them out loud)

| Relationship | Implementation | Note |
|---|---|---|
| users 1:1 user_profiles | FK + `user_id` as PK | 1:1 = UNIQUE on the FK |
| users 1:N addresses | FK on addresses | "one default" = partial unique index (003) |
| vendors 1:N products 1:N variants | FKs | the catalogue spine |
| variants 1:1 inventory | FK + PK on `variant_id` | mutable data isolated from catalogue |
| carts 1:N cart_items | FK, cascade delete | cheap, disposable, no FK to users on purpose |
| orders 1:N order_items | FK + snapshot columns | "≥1 item" = reversed composite FK (008) |
| orders 1:1 payments(successful) | partial unique index (009) | cross-row invariant |
| users M:N products (via purchases) | derived through orders | never model a join table for a derivable relation |

## Snapshotting: a modelling decision, not a hack

`order_items.sku / product_name / unit_price_cents` duplicate catalogue data. That is
**intentional denormalisation for correctness**: the catalogue will change; the order is
a historical fact and must not change with it. Same for `orders.shipping_*`. The
alternative — joining the live catalogue for historical orders — produces invoices that
rewrite themselves when a vendor renames a product.

## When to denormalise (and how to keep it honest)

Denormalise a *derived* value only when you can answer: **who recomputes it, and can a
concurrent writer corrupt it?**

| Pattern | Here | Guard |
|---|---|---|
| Counter/total column | `orders.total_cents` | trigger 011, serialised per order |
| Snapshot copy | order_items | immutable by policy + audit trigger |
| Read-time cache table | (not needed here) | would need its own refresh contract |

Every denormalisation is a small distributed-systems problem you just created. That is
the trade: write complexity / storage for read speed and historical correctness.

## Surrogate vs natural keys

- Surrogate (`bigint IDENTITY` everywhere here): stable under business re-keying,
  small (16 bytes vs a long `sku`), FK-joinable.
- Natural (e.g. `sku`): readable, but only if it is *truly* immutable. A "temporary"
  natural key that later changes is the classic migration factory.
- Hybrid (what we did): surrogate PK **plus** a UNIQUE natural key constraint —
  `product_variants.sku` is unique and indexed, but never referenced by FKs.

## Modelling exercise

Model this for your own review: a course platform where students enrol in courses,
each course has ≤ 5 assignments, each assignment ≤ 3 files per student, and a student's
final grade is derivable. Sketch tables, keys, the "≤ 5 assignments" constraint, and
decide (defend it!) whether `final_grade` is stored.

## Explain-back questions

1. Why is `order_items.total_cents` not a stored column but `orders.total_cents` is?
2. `carts.user_id` has no FK. Defend or attack that decision — what changes at 10k rps?
3. Give one concrete bug each that 1NF, 2NF and 3NF would have prevented in this schema.
4. When is a 1:1 relationship justified as two tables instead of one wide table?

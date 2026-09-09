# 04 · Indexing: B-tree, composite, partial, and the cost of each

## What an index is

A **B-tree** is a sorted, self-balancing tree of pages. A lookup descends root →
branch → leaf, each step one page read (`shared hit` if cached). That is why "indexed
lookup" ≈ 3–4 page reads regardless of table size, and why **column order in a
composite index is the whole game**: the index is sorted by `(a, then b, then c)` —
equal `a` values sort by `b`. `(user_id, occurred_at DESC)` serves `user_id = ?` order
by `occurred_at` and range scans, but a bare `WHERE occurred_at > now() - '7 days'`
cannot seek into it efficiently.

## Every index in this schema, and the query it serves

| Index | Serves | Type |
|---|---|---|
| `users_pkey`, all PKs | point lookups, FK checks | btree |
| `idx_addresses_user_id` | a user's addresses | btree |
| `addresses_one_default_per_user` | the default-address read **and** the invariant | partial unique btree |
| `idx_products_name_trgm` | `name ILIKE '%runner%'` | GIN (trigram) |
| `idx_products_vendor_created` | vendor catalogue page, newest first | btree composite |
| `idx_variants_sku` | SKU scan at checkout | unique btree |
| `idx_variants_product` | variant rows on product pages | partial btree |
| `idx_orders_user_occurred` | "my orders, newest first" | btree composite |
| `idx_orders_status_created` | ops dashboard, oldest pending first | btree composite |
| `idx_payments_order` | payment lookup by order | btree |
| `idx_audit_table_row` | "history of row X" | btree composite |

## The decision procedure (do this every time)

1. Write the query in its final form first.
2. Equality predicates first in the index, then the sort/range column.
3. Consider `INCLUDE` for a covering index (`CREATE INDEX ... ON orders (user_id, occurred_at) INCLUDE (status, total_cents)` → index-only scan).
4. Re-check in 90 days: workloads drift; so must indexes.

Why not throw INCLUDE at everything? Every index is a **second copy of a key subset,
maintained on every INSERT/UPDATE/DELETE** — write amplification, more WAL, more
buffer pressure. Hot-path indexes are paid for at write time by every other query.

## The HOT update principle

PostgreSQL updates **every index that contains any updated column** (unless HOT).
`UPDATE orders SET status = ...` — status isn't in any index → cheap. But
`UPDATE users SET email = ...` rewrites every index on `users`. Keep hot-update
columns out of indexes (this is why `updated_at` is not indexed anywhere, and the
`idx_orders_status_created` index accepts its churn because the dashboard query is
worth it).

## Column order quiz (answers in lab 02)

For each query, name the best composite index or say "none":

```sql
-- Q1  SELECT * FROM orders WHERE user_id = 42 AND status = 'paid';
-- Q2  SELECT * FROM orders WHERE status = 'paid' AND total_cents > 10000 ORDER BY created_at DESC;
-- Q3  SELECT * FROM order_items WHERE variant_id = 700;
-- Q4  SELECT * FROM orders WHERE user_id = 42 ORDER BY occurred_at DESC LIMIT 20;
-- Q5  SELECT * FROM products WHERE name ILIKE '%runner%';
-- Q6  SELECT count(*) FROM orders WHERE user_id = 42;          -- (with idx_orders_user_occurred)
-- Q7  SELECT * FROM orders WHERE EXTRACT(year FROM occurred_at) = 2026;
```

Q7 is the trap: the predicate is non-sargable — the function wraps the *column*, so
no b-tree can be used. Rewrite as a range on the bare column
(`occurred_at >= '2026-01-01' AND occurred_at < '2027-01-01'`).

## Special index types (know they exist, one sentence each)

- **GIN (pg_trgm)** — substring/similarity search on text (`idx_products_name_trgm`).
- **BRIN** — tiny summary of physical ranges; great for huge append-only time series.
- **GiST/SP-GiST** — geometric, range types, nearest-neighbour.
- **Hash** — equality-only, historically less trusted than btree; rarely needed.
- **Exclusion constraint** — "no overlapping shifts", via GiST.

## Try this

```sql
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexname::regclass) DESC;

-- is the trigram index actually used? (lab 03)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE name ILIKE '%runner%';

-- unused-index candidates (pair with pg_stat_user_tables.seq_scan):
SELECT s.schemaname, s.relname, s.indexrelname, s.idx_scan,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s
WHERE s.idx_scan = 0 AND s.relname NOT LIKE 'audit%';
```

## Explain-back questions

1. Your write latency grew 30% after a feature launch. How do you check whether new indexes are the cause?
2. Why is `(status, created_at DESC)` right for the ops dashboard but wrong for "user 42's paid orders"?
3. What does an index-only scan require to actually happen, and why does it rarely survive a busy OLTP table?
4. Which two indexes here are *also* constraints? (hint: uniqueness is enforced by index)

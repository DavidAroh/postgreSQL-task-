# Solutions · Lab 02

**Part A:**

- Q1 `(user_id, status)` or `(status, user_id)` — both equalities; put `user_id`
  first because it's higher-cardinality and matches the other user-scoped queries.
  Plan: Index Scan/Bitmap Heap Scan on your new index; Seq Scan before it.
- Q2 `(status, created_at DESC)` — equality then sort; `total_cents > 10000` is a
  filter applied on the fetched rows (or add it as a non-key INCLUDE/3rd column to
  help, but btree range on it can't serve the ORDER BY). `LIMIT 20` makes the
  ordered scan cheap: it stops after 20 rows.
- Q3 `(variant_id)` btree — already there (`idx_order_items_variant`); Index Scan,
  ~rows=27.
- Q4 existing `idx_orders_user_occurred (user_id, occurred_at DESC)` — equality +
  sort + LIMIT: perfect fit, plus it can stop after 20 rows (watch: no Sort node at
  all in the plan).
- Q5 GIN trigram `idx_products_name_trgm` → Bitmap Index Scan. Note `EXTRACT`/function
  wrapping kills btree use elsewhere; trigram is exactly for `%text%`.
- Q6 non-sargable → Seq Scan + filter. Rewrite:
  `WHERE occurred_at >= '2026-01-01' AND occurred_at < '2027-01-01'` — now a plain
  range: any btree on `occurred_at` (or composite with it second) can serve it.
- The "none needed" case: `SELECT count(*) FROM orders WHERE user_id = 42` still
  benefits from `idx_orders_user_occurred` via an index-only scan on the leading
  column (count via index, no heap).

**Part B:** after creating the covering index the first run still shows
`Heap Fetches: n` because the **visibility map** hasn't been marked all-visible yet
(VACUUM updates it; run `VACUUM orders;` then re-explain: `Heap Fetches: 0`).
Index Only Scan appears only when (a) all needed columns are in the index and
(b) pages are known all-visible.

**Part C:** roughly: no index < one index < two indexes in INSERT time (each index
adds a write + possible page splits). Numbers vary by hardware; the *ratio* is the
lesson — a wide second index can cost more than the first (bigger keys, more page
splits). This is the price table for "just add an index".

**Part D:** Case 1 (unindexed column updated) shows a large hot_updated count —
HOT update: no index maintenance, new tuple possibly on same page. Case 2 (indexed
`n` updated) hot count stays — every update must insert into the `n` index, breaking
HOT. HOT skips *index* maintenance, not row-versioning.

**Exercises:**

1. `idx_orders_status_created (status, created_at)` already exists → Index Scan with
   LIMIT stops after 50. With no index this would be a full sort (top-N heapsort);
   with it, no Sort node at all.
2. Expect hot_updated to stay near zero for those 5,000 rows (status is in the
   index) and the index to grow by dead-entry bloat; REINDEX/VACUUM reclaims later.
   Contrast: update `currency` (unindexed) → HOT count rises.
3. Partial index for a report: `CREATE INDEX ... WHERE occurred_at >= ...` refreshed
   around report time, or simply create the index before the nightly job and drop it
   after — works because report tables are append-mostly. PG also has "partitioned
   partial" strategies; the general point: index lifetime can match workload lifetime.
4. Largest are usually `idx_orders_user_occurred` / `idx_orders_status_created`
   (10k rows is small, but the *pattern* scales). Keep both: they serve the two
   dashboard shapes. The trigram GIN is the biggest per-row cost; keep it only if
   name search is a real feature (it is — it's in the lab).

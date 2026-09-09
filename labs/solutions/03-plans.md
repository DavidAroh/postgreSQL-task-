# Solutions · Lab 03

**Part A:**

1. Index Scan (or Index Only Scan) on `idx_variants_sku`: 1 row, buffers in single
   digits. This is what "O(log n)" feels like.
2. Seq Scan on orders, `rows removed by filter` ≈ most of the table: reads ~everything
   to keep a minority. `total_cents` has no index — deliberately: it's a
   rarely-queried range; adding one would tax every write (lab 02 Part C).
3. `status = 'pending'` estimate comes from the MCV list (docs/05) — pending is
   ~8% of rows, and the planner knows it. No index on status alone, so Seq Scan is
   *correct* here (8% of a small table); on a 100M-row table the same percentage
   would demand `idx_orders_status_created`.

**Part B:** the correlated-subquery version shows the subquery executed once **per
user row** (loops ≈ 380): total time = 380 index probes + aggregation each.
Fix 1 (join+GROUP BY) scans orders once and hashes: usually the winner for "all
users". Fix 2 (LATERAL) keeps per-user index probes — wins when the outer side is
already small/paginated (e.g. 20 users), or when per-user semantics need
LIMIT/ORDER per user (top-1 per user — see lab 04 Part C).
Rule of thumb: whole-set aggregates → join; per-row windowed semantics → LATERAL.

**Part C:** `pg_stats` on status shows MCVs + frequencies; the real GROUP BY counts
will diverge most for statuses whose share changed since the last ANALYZE (seed is
static, but after the labs mutate statuses — e.g. lab 10/11 — estimates drift).
`work_mem = 64kB` forces `Sort Method: external merge Disk: …` (or quicksort
spilling); the same query at default memory sorts in-RAM. Both produce identical
rows — memory only changes *how*, never *what*.

**Part D:** the 5th EXECUTE may flip to `Seq Scan on orders` (generic plan priced
with average bind selectivity — terrible for user 380, tolerable for whales).
`plan_cache_mode = force_custom_plan` re-plans per execution: parameterised plans
again. Production equivalent: a p99 latency cliff ~5 calls after first sighting of a
query — remember this when someone says "prepared statements are always faster".

**Exercises:**

1. e.g. keep ORDER BY occurred_at + LIMIT but pre-filter statuses in a CTE
   (`WITH paid AS (SELECT * FROM orders WHERE status='paid')`) — or add
   `(status, occurred_at DESC)` index and let the planner stop at 20 rows: same
   shape, no join strategy debate. The *answer* is the argument, not the SQL.
2. After the labs, the heaviest will be the per-user aggregates and the checkout
   tests. Improvements: LATERAL/GROUP BY rewrite (Part B), batched cart reads,
   covering indexes for the dashboard.
3. `rows removed by filter: 24800` → an index on the filtered column; verify with
   EXPLAIN (before: Seq Scan + removed≈24.8k; after: Bitmap/Index Scan, removed≈0).
4. (a) shared buffers cold → first run reads pages from disk; (b) plan caching /
   catalog warm-up, plus statistics warm-up on first execution.

**Explain-back (docs/05):** see the doc's section — the Q2 answer: rows is *per
loop*: actual output = rows × loops (≈1000 rows), and the index probe happened 1000
times: that arithmetic is exactly how N+1s hide inside "one query".

# Solutions · Lab 04

**Part A:** all-users: Hash Join (both sides large, no order needed) or Merge Join
depending on stats. Whales (≤40 users): Nested Loop — small outer side, index probes
on `idx_orders_user_occurred` per user; ~40 probes × thousands of rows beats a hash
build. Minnows (>340): either shape, but many fewer loops. The planner's choice
tracks the *estimated* sizes; with skewed data the estimates can be wrong — compare
`rows=` vs actual at the join node.

**Part B:** both NOT EXISTS queries → Hash Anti Join (or nested-loop anti for small
sides). LEFT JOIN + IS NULL produces the same result with an extra Filter node and
(usually) the same hash — semantics differ subtly with duplicated join keys (NOT
EXISTS deduplicates, LEFT JOIN duplicates then filters); here keys are unique so
plans match. NOT EXISTS is the clearer intent and handles duplicates correctly by
construction.

**Part C:** v1 (window) sorts/partitions everything; v2 (DISTINCT ON) sorts
`user_id, occurred_at DESC` and picks first per group — often wins with an index
available; v3 (LATERAL LIMIT 1 per user) does 400 index probes via
`idx_orders_user_occurred` — the one that scales to 100× *rows per user* with only
logarithmic cost per probe, and parallelises trivially; but with millions of users
v2/v1's bulk scan wins again. "It depends" = on users × orders-per-user ratio.

**Part D:** the 2026-only query reads fewer pages (if an index on occurred_at exists,
it's a range scan; else a seq scan with fewer surviving rows — the aggregation input
shrank either way). The GROUP BY node itself got cheaper because fewer rows flowed in.

**Exercises:**

1. Two left joins + two GROUP BY levels, or a single scan with `count(DISTINCT ...)`
   variants; verify no `SubPlan` node appears in the plan (the tell of a per-row
   subquery).
2. `pg_trgm` ignores trigrams shorter than 3 chars (fixed in the extension, no GUC
   for minimum length in stock builds): `%un%` produces no usable trigram → Seq Scan.
   `%runner%` has 'run','unn','nne','ner' → GIN Bitmap Scan.
3. `SET LOCAL enable_hashjoin = off` (etc.) flips the plan; shipping hints is a
   smell *unless* stats are provably unfixable (cross-tab skew) — then prefer
   rewriting the query, and only then `pg_hint_plan` as a documented last resort.
4. 6 nodes × 64MB × 50 = 19.2GB demand from one query shape — the sane response:
   lower work_mem for that class (transaction/role-level `SET`), fix the plan to
   avoid sorts (indexes), batch the query. Global work_mem raises are a foot-gun
   because it's per node per execution.

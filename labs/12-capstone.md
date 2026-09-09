# Lab 12 · Capstone: the full schema review

**Sessions:** one + your notes. **Goal:** the practical task's final deliverable —
defend every decision in the schema, with evidence.

For each item below, produce: the decision, the alternative you rejected, and the
EXPLAIN/measurement that supports the choice. Cite the migration file and doc section.

## The checklist

### Modelling
- [ ] Draw the ER diagram from `schema_migrations` + `\d` output. Mark 1:1, 1:N, M:N.
- [ ] Defend `order_items` snapshots vs joins to live catalogue at read time.
- [ ] Defend `carts.user_id` without FK. What changes if you add it?
- [ ] One table you would split further; one merge you would make. Why?

### Constraints
- [ ] List every constraint in the schema (`\d+` each table) with its failure mode.
- [ ] Find one business rule currently *not* enforced and add it (migration 012).
- [ ] Explain the deferrable FK in 008 to a junior, including when INITIALLY IMMEDIATE would bite.

### Indexing
- [ ] For the 5 most common access paths you can imagine in production (write them down!), verify an index exists and the plan uses it.
- [ ] Drop-or-keep decision for every index, with `pg_stat_user_indexes.idx_scan` as evidence.
- [ ] Write the two partial indexes this schema *should* have for its queries but doesn't (candidates: active carts, pending orders, low-stock alerts).

### Plans
- [ ] Take the three queries you wrote for indexing; `EXPLAIN (ANALYZE, BUFFERS)` each; annotate loops/buffers/estimation error.
- [ ] Find the worst estimation error in the whole schema (`pg_stats` vs reality) and explain its cause.

### Transactions & concurrency
- [ ] Walk through `checkout()` (lab 05) at READ COMMITTED and prove it is safe: every write is atomic-pattern or FOR UPDATE-protected.
- [ ] List every multi-row write path in the schema and its lock ordering. Where could a deadlock hide?
- [ ] The inventory decrement under REPEATABLE READ: write the retry loop. Why is the retry harmless here?

### Operations
- [ ] Write migration 013: "add `loyalty_tier` to users" as expand/contract with backfill — including the CONCURRENTLY index it needs.
- [ ] Write the pool config for 4 app pods, 8-core Postgres, and defend the number.
- [ ] Soft-delete + audit: run the GDPR exercise (lab 11 #2) for real, in one transaction.

## Deliverable

A one-page `REVIEW.md` in your own words: the five riskiest aspects of this schema as
built, each with evidence, and your fix. This is the artifact your mentor will grill
you on — weak claims ("add an index") are the tell of an intern; strong ones ("this
plan reads 24,800 rows to return 12 because the predicate is non-sargable; here is
the rewrite and its plan") are the tell of an engineer.

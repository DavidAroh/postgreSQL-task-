# Solutions · Lab 12

No fixed answers — the deliverable is your REVIEW.md. This guide gives the expected
*shape* of strong answers per checklist item, so you can self-check.

**Modelling.** Strong reviews flag: (1) `carts.user_id` without FK is defensible for
a disposable hot table but should carry a *cleanup* story (a sweeper deleting
abandoned carts, since nothing else references them); (2) the orders→items reversed
FK is unusual — being able to explain *why* it works (UNIQUE on child pair +
deferrable check) is the point; (3) a split candidate: payments → payment_attempts
vs payment_results; a merge candidate: user_profiles into users (it's 1:1 with a
single access path — counter-argument: hot/narrow users table).

**Constraints.** The unenforced rule candidates: "an order's items may not exceed
stock at checkout *if* payment captures later" (time-delayed invariant — needs the
reservation model of lab 07 #2); "cart_items.price must match variant price when
added" (enforceable only at insert time by app + trigger comparison). Deferrable FK
explanation to a junior: "the check runs at COMMIT; insert order can be
parent-before-child inside one transaction; the price is later, weirder errors."

**Indexing.** Expected access paths: user's orders page, SKU scan, vendor catalogue,
ops pending list, product search. Drop candidates will be none at this scale — the
exercise is writing the *method* (idx_scan evidence + access-path list), not the
conclusion. Partial-index candidates: pending orders (`WHERE status='pending'`),
open carts (`WHERE status='open'`), low-stock (`WHERE quantity < 5 ON inventory`).

**Plans.** Worst estimation error typically: statuses mutated by labs drift from
seed-time ANALYZE (fix: re-ANALYZE and explain *why* it drifted — column stats age);
or whale-user joins (cross-tab skew — no single histogram fixes it; fixes are
query-shape or extended statistics `CREATE STATISTICS`).

**Transactions & concurrency.** checkout() safety argument: every write is either
atomic-pattern (stock) or behind the cart FOR UPDATE (order/cart state), deferred FK
and totals trigger resolve at COMMIT, loser rolls back whole. Lock-ordering map:
cart → (variants via atomic updates, no cross-variant row locks held) → orders →
order_items; deadlock hideouts: two carts checked out concurrently that share
variants share *no* row locks (atomic UPDATE holds briefly) — the design avoids the
classic multi-row deadlock by construction; saying *that* with evidence is a senior
answer.

**Operations.** Migration 013 shape:
1. `ALTER TABLE users ADD COLUMN loyalty_tier text;` (nullable, instant)
2. batched backfill `WHERE loyalty_tier IS NULL` chunks of 10k
3. `CREATE INDEX CONCURRENTLY idx_users_loyalty ON users (loyalty_tier) WHERE loyalty_tier IS NOT NULL;`
4. app reads/writes it; later contract: `NOT NULL DEFAULT 'none'` via
   add-column-then-check or `VALIDATE` pattern.
Pool config: 4 pods × ~5 = 20 app connections + margin; Postgres-side
`max_connections=100` untouched; 8 cores → throughput-optimal around
`cores×2..4` = 16–32 total — 20 app + 10 ops/dashboard connections fits; the
defence is the *formula plus measurement* (pg_stat_activity active vs idle ratios),
not the number.

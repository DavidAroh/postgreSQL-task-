# Solutions · Lab 08

**Part A:** B's second UPDATE reports `UPDATE 0` (version moved to 2); B reloads
(name now 'A was here', version 2) and its version=2 UPDATE succeeds. The retry
loop's sleep+backoff avoids hammering; the 409 after N attempts is the honest
"someone else is editing this" answer. Not for hot rows: 500 admins on one product
per second → each conflict triggers reloads+retries (thundering herd); a single
`FOR UPDATE` queue behind the row lock would be more orderly (and the contention
visible in pg_locks rather than as app-side 409 storms).

**Part B:** the N+1-shaped EXPLAIN shows two SUBPLAN nodes each with
`loops=<number of active users>` — i.e. ~760 subquery executions. Cure 1
(join+GROUP BY): one scan of orders + hash agg. Cure 2 (LATERAL): one subplan per
user again, but *inside one statement* — still N index probes, yet no app round
trips. (a) 400 users: all similar; (b) 40k users: cure 1 wins (one hash); (c) first
20 users of a page: LATERAL wins (20 probes vs scanning all orders) — the answer is
driven by rows-per-page × probes-vs-scan crossover.

ORM N+1: `selectinload` issues one `WHERE user_id IN (...)` batch; `joinedload`
joins in the first query. Preference: eager-load per relationship, batched IN for
lists, join+GROUP BY for aggregates — never the lazy attribute access inside a loop.

**Exercises:**

1. Terrible fit: cart qty updates are *high-frequency, low-stakes, same-user* —
   conflicts would be constant (two devices), retries annoying, and the invariant
   (stock) is enforced elsewhere anyway. Atomic UPDATE with LEAST-cap (lab 07 #1)
   has no conflicts at all: last-writer-wins with a deterministic cap.
2. Log shows one SELECT for users + one SELECT per user for orders → 401 statements
   per page render. (`log_statement='all'` — don't forget
   `ALTER SYSTEM RESET log_statement; SELECT pg_reload_conf();`)
3. FOR claim: simpler mental model (no retry code), natural when transactions are
   short and contention low-ish, and it composes with multi-row invariants. Kill:
   long user think-time while holding the lock (idle-in-transaction) — deadlocks the
   pooler; and hot-row lock queues turn a UI into a latency chain.
4. Two statements:
   `SELECT ... FROM users WHERE status='active' LIMIT 400;` then
   `SELECT user_id, count(*), max(total_cents) FROM orders WHERE user_id = ANY($1) GROUP BY 1;`
   — 2 round trips total; measure: the batched shape's total time approaches cure 1
   as the page grows, and beats N round trips by an order of magnitude regardless.

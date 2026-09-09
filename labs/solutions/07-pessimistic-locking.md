# Solutions · Lab 07

**Part A:** final quantity 2 (10−8 applied twice: A's 10−8, then B's 2−8 would
violate CHECK… careful reading: B's UPDATE runs after A commits, from quantity=2,
so B's −8 hits `inventory_quantity_check` and fails. But the *lost update* already
happened if B's SELECT said 10 and B's UPDATE said 10−8 — the outcome depends on
exact interleaving; that's the lesson: with check-then-act the outcome is
*interleaving-dependent*, which is the definition of a race). The bug: B read before
A committed and acted on a stale value.

**Part B:** second UPDATE reports `UPDATE 0` — no error, no block; the predicate
re-check (EvalPlanQual) sees post-A state. Best default for single-row stock math.

**Part C:** FOR UPDATE serialises B behind A: B's re-read after A commits shows the
new value; B's own −5 then applies correctly (or correctly fails). General tool for
multi-row decisions; costs a queued connection while waiting.

**Part D table:**

| | atomic predicate | FOR UPDATE |
|---|---|---|
| Blocks concurrent writers? | no (loser re-evaluates) | yes (queued) |
| Needs a transaction? | no (single statement) | yes |
| Decide on other rows/data? | no | yes |
| Best for | single-row increments with simple preconditions | multi-row reads-then-writes, complex invariants |
| Failure at high contention | wasted work (0-row updates), no starvation | lock queues, latency chain, connection pressure |

**Part E:** NOWAIT errors instantly for one session (fast-fail UX); without NOWAIT,
B and C queue in lock-grant order and proceed serially after A commits. Session D
sees `wait_event_type = Lock`, `wait_event = transactionid` (row lock), plus
`pg_blocking_pids` showing A blocking both.

**Exercises:**

1. `INSERT ... ON CONFLICT (cart_id, variant_id) DO UPDATE SET qty = LEAST(cart_items.qty + EXCLUDED.qty, 10)`
   — deterministic final state regardless of interleaving (plus app-level cap rule).
2. Reserve: `UPDATE inventory SET reserved = reserved + q, quantity = quantity - q
   WHERE variant_id = ? AND quantity >= q` (moves stock into reserved immediately).
   Release: reverse it, idempotent via a reservation token table. Crash handling: a
   sweeper expires reservations older than N minutes (visibility-timeout thinking,
   same as lab 10). Key design point: *some* component must own expiry — the DB
   constraint alone can't.
3. A's lock held; B's plain SELECT returns instantly (MVCC snapshot — sees either
   pre-A state). Correct because B's data was never promised to be "current", only
   *transactionally consistent as of B's snapshot*; if B needs current, it must take
   the lock too (or atomic UPDATE) — this is exactly the RC contract.
4. Both sessions INSERT the missing variant then try to decrement: the unique PK on
   `inventory.variant_id` makes one INSERT fail → retry loop includes the insert.
   Pattern: `INSERT ... ON CONFLICT DO NOTHING RETURNING` (claim creation) in a CTE,
   then `UPDATE ... WHERE quantity >= q` in the same statement/transaction.
   SERIALIZABLE also works but drags retries into every path — too heavy for a
   single-row claim.

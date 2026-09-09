# Solutions · Lab 06

**S1:** B sees the old quantity — PostgreSQL never exposes uncommitted data; there
is no dirty-read knob at all (MVCC makes it unnecessary; offering it would require
exposing tuple headers mid-flight).

**S2 (READ COMMITTED):** B's second SELECT sees the *new* value — non-repeatable
read, by design (new snapshot per statement). With REPEATABLE READ in A: same value
twice (one snapshot per transaction), and B proceeds unblocked (writers never block
readers in MVCC); A commits fine since it only read.

**S3 (READ COMMITTED):** A: 10→8; B reads 10 (before A commits), its UPDATE blocks
on A's row lock, then *re-evaluates against the new row*: sets 5 unconditionally —
final value 5, A's intent (8) silently lost: lost update. Under REPEATABLE READ
both: second updater gets `could not serialize access due to concurrent update` on
COMMIT (or at the UPDATE) — must retry the whole transaction.

**S4:** both commit at RR: write skew — each transaction's precondition ("2 active
products") was invalidated by the other, but neither touched the same row, so no RW
conflict at RR. Result: both 500 and 501 are archived, the invariant is broken by
two individually-correct statements. Under SERIALIZABLE (SSI tracks
rw-antidependencies): one gets `could not serialize access due to read/write
dependencies among transactions`.

**S5:** retry loop required; acceptable for checkout if idempotent (same cart can't
double-order — the atomic stock check makes retries converge) with backoff and a
retry cap (3–5).

**Exercises:**

1. `UPDATE inventory SET quantity = quantity - 2 WHERE variant_id = 4 AND quantity >= 2`
   — READ COMMITTED + EvalPlanQual re-check serialises both writers; each decrement
   applies only if stock allows; zero errors, zero retries. Isolation level stopped
   mattering because the only shared state is one row mutated atomically — the
   anomaly needed a read + separate write.
2. Yes: `FOR SHARE` on the vendors read makes both transactions hold shared locks;
   B's UPDATE takes them exclusively → conflict detected → RR aborts one. Cost: every
   reader now registers with the lock manager on hot rows — read concurrency drops;
   SSI often scales better for this shape.
3. No knob exists; explain MVCC and offer the real alternatives: smaller
   transactions, batching, read-uncommitted-analogue = just don't wrap reads in
   long transactions. Anyone demanding dirty reads for performance is usually
   compensating for a long transaction elsewhere.
4. READ COMMITTED suffices and is the right choice: every write is atomic-pattern
   (stock) or cart-lock-protected; run it under RC/RR/SERIALIZABLE and observe
   identical final states, with RR/SERIALIZABLE occasionally demanding retries for
   zero additional safety — proving the isolation level is a performance/speculation
   decision, not a correctness one, *for this design*.

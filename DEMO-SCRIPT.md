# Demo Script · Screen recording for your senior developer

**Target length:** 7–9 minutes. **Goal:** your senior finishes the video thinking
*"this intern didn't just read about Postgres — they built one and can prove how it
behaves."* Every section below is: what to say, what to show, what to run.

---

## Before you hit record (one-time prep)

1. **Fresh database, so numbers are predictable:**
   ```bash
   bash scripts/reset.sh
   ```
2. **Two terminals, side by side, big font** (Ctrl+= in Windows Terminal). Left = Session A,
   right = Session B. Give them different prompts so the video is readable:
   ```sql
   -- in terminal A
   \set PROMPT1 'A> '
   -- in terminal B
   \set PROMPT1 'B> '
   ```
   Connect both: `docker exec -it advdb-postgres psql -U app -d advdb`
3. **Kill distractions:** Windows focus assist on, notifications off, editor theme dark,
   close Slack.
4. **Recording tool:** `Win+G` (Xbox Game Bar → capture) or OBS. Record 1920×1080.
5. **Don't type SQL live.** Keep this file open and copy-paste each block. Typing demos
   die by typo.

---

## Shot 1 · The problem and what you built (0:00–1:00)

**Show:** repo tree in your editor, then `README.md` → `WORKBOOK.md` → scroll of `sql/migrations/`.

**Say:** *"The module was advanced Postgres — modelling, constraints, indexing, plans,
transactions, concurrency. I built a full e-commerce schema as 11 numbered migrations,
seeded it with 10k orders and deliberate data skew, and wrote 12 labs with solutions
that run against it. Let me show you the parts that prove it works."*

## Shot 2 · The schema is the argument (1:00–2:30)

**Show:** open `sql/migrations/007_orders.sql` and `009_payments.sql`. Slowly scroll.
Narrate **three** design decisions, no more:

- denormalized `subtotal_cents`/`total_cents` on orders, kept correct by a trigger —
  *"read-heavy system, so we pay on write"* (docs/02, docs/07)
- the partial unique index: one *succeeded* payment per order — *"a cross-row business
  rule the database enforces, not the app"* (docs/03)
- the deferrable FK making "every order has ≥1 line" checkable at COMMIT —
  *"constraints that need to temporarily violate themselves"* (docs/03)

## Shot 3 · Constraints firing live (2:30–4:00) — Session A

Run these one at a time from `labs/01-constraints.md`; **read each error aloud**:

```sql
-- UNIQUE(user_id,label): second 'home' address
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
VALUES (1, 'home', '1 main st', 'Berlin', '10115', 'DE', false);

-- CHECK: inventory can't go negative
UPDATE inventory SET quantity = quantity - 999999 WHERE variant_id = 1;

-- partial unique index: second successful payment for order 2
INSERT INTO payments (order_id, status, amount_cents, provider)
SELECT id, 'succeeded', total_cents, 'dup' FROM orders WHERE id = 2;

-- audit log is append-only (rules rewrite tampering into nothing)
UPDATE audit_log SET row_pk = 'hacked' WHERE id = 1;
DELETE FROM audit_log WHERE id = 1;
-- then prove it: 0 rows affected, row still intact
SELECT id, table_name, op, row_pk FROM audit_log WHERE id = 1;
```

**Say:** "None of this is app code. The database is the only component that sees all
writers, so invariants live here." And for the audit log: *"the RULE rewrote my
UPDATE and DELETE into no-ops — `UPDATE 0`, `DELETE 0`, row still there. Tamper-proof
without a single line of application code."*

## Shot 4 · Plans and an index that changes one (4:00–5:30) — Session A

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE shipping_city = 'Berlin';
```
Point at **Seq Scan on orders**, the actual time, and `Buffers: shared read`.

```sql
CREATE INDEX idx_orders_city ON orders (lower(shipping_city));
EXPLAIN (ANALYZE, BUFFERS)
  SELECT count(*) FROM orders WHERE lower(shipping_city) = 'berlin';
```
Point at the plan flipping to **Bitmap Index Scan → Bitmap Heap Scan** and the timing drop.

**Say:** *"Before: reads every 10k-row page. After: index finds the city subset, heap
fetches just those rows. One index, chosen from the plan, not from a blog post."*

## Shot 5 · Concurrency you can see (5:30–7:30) — Sessions A and B

**Locking (pessimistic).** Run in order:

```sql
-- A
BEGIN;
SELECT * FROM inventory WHERE variant_id = 1 FOR UPDATE;
-- B (this now HANGS — leave it on screen for 3 seconds)
UPDATE inventory SET reserved = reserved + 1 WHERE variant_id = 1;
-- A
COMMIT;          -- B's update completes the moment you commit
```

**Who blocks whom, from a third eye** — run in A while B still hangs:

```sql
SELECT blocked.pid  AS blocked_pid,
       blocking.pid AS blocked_by,
       left(blocked.query, 40) AS blocked_query
FROM pg_stat_activity blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) bp ON true
JOIN pg_stat_activity blocking ON blocking.pid = bp;
```

**SKIP LOCKED job queue (the money shot).** Set it up once (from `labs/10-job-queue.md`):

```sql
CREATE TABLE email_queue (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload    text NOT NULL,
  status     text NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending', 'processing', 'done', 'failed')),
  attempts   integer NOT NULL DEFAULT 0,
  run_after  timestamptz NOT NULL DEFAULT now(),
  locked_at  timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_email_queue_due ON email_queue (run_after) WHERE status = 'pending';
INSERT INTO email_queue (payload) SELECT 'welcome-mail-' || g FROM generate_series(1, 20) g;
```

Then two workers claim jobs simultaneously, never the same one:

```sql
-- A and B run the SAME statement at the same time:
UPDATE email_queue SET status = 'processing', attempts = attempts + 1, locked_at = now()
WHERE id = (
  SELECT id FROM email_queue
  WHERE status = 'pending' AND run_after <= now()
  ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1
)
RETURNING id;
```
A returns one id, B returns a *different* id. **Say:** *"Two workers, zero double
processing, zero coordination service — one SQL statement."*

## Shot 6 (optional) · A real deadlock (7:30–8:30)

Follow `labs/09-deadlocks.md` Part A verbatim — two sessions updating orders 100 and
101 in opposite order. After ~1s, one session gets `ERROR: deadlock detected` and the
other finishes. **Say:** *"Detection isn't instant — that's `deadlock_timeout`, a
deliberate trade-off."* Skip this shot if you're over time; Shot 5 already proves the
point.

## Shot 7 · Close (last 45s)

```sql
SELECT query, calls, mean_exec_time
FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 3;

SELECT count(*) FROM audit_log;
```
**Say:** *"Statement stats are tracked in production config, every order mutation is
audited, and `WORKBOOK.md` has the 4-week path and grading rubric. Reset to a clean
database is one command."* Show `bash scripts/reset.sh` having already been run before
the recording instead of running it live.

---

## Questions your senior will ask (and where your answers live)

| Likely question | Your answer |
|---|---|
| "Why a partial unique index, not a trigger?" | docs/03 — declarative, race-free, visible in `\d payments` |
| "Why denormalize totals on orders?" | docs/02 + docs/07 — read-heavy; trigger keeps it honest; labs 05 prove the trigger under concurrency |
| "Why `SKIP LOCKED` and not a queue product?" | labs/10 — transactional with the business data; good to ~thousands jobs/s; know when you've outgrown it |
| "What do isolation levels actually change here?" | labs/06 — you reproduced dirty-read-prevention, nonrepeatable read, phantom, and write skew on this schema |
| "How would this migrate with zero downtime?" | docs/07 — expand/contract, `NOT VALID` + `VALIDATE CONSTRAINT` |

## Rehearsal checklist

- [ ] Full dry run once, timed — first take is always the practice take
- [ ] `reset.sh` run immediately before recording (fresh data, known counts)
- [ ] Shot 5 setup block (`email_queue`) pasted once before recording that section
- [ ] Both psql prompts customized (A>/B>), font huge, terminal opaque
- [ ] Every SQL block copy-pasteable from this file in order
- [ ] Total runtime ≤ 9 minutes; Shot 6 is the designated cut if long

**If anything breaks live:** say *"good, a real error"* — run `bash scripts/reset.sh`
after the recording, or just move to the next shot. Senior developers trust demos that
survive an error more than demos that can't have one.

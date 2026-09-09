# Solutions · Lab 11

**Part A:**
- The admin-tool join isn't inherently a bug: orders of deleted users often must
  remain queryable (finance, support). The *bug* is when user-facing lists forget
  the predicate (`WHERE status <> 'deleted'`). Rule: soft-delete predicates belong
  in one shared query layer (view/repository), never sprinkled by hand.
- Re-registration: with `UNIQUE (email)` the insert fails while the deleted user
  holds the email. Fix: drop the full unique, add
  `CREATE UNIQUE INDEX users_email_unique_live ON users (email) WHERE status <> 'deleted';`
  (or `WHERE deleted_at IS NULL`). Not pre-applied here to keep migration 002
  simple — doing it for real is exercise 1's spirit.
- Orders of user 350 remain: correct for financial history; the *user-facing*
  queries exclude them via the user's status.

**Part B:** the DELETE cascade (or explicit deletes) removes rows across
orders/order_items/payments/refunds — dozens of rows, irreversible, plus bloat and
FK locking storms if any of those tables are huge. Soft delete: one UPDATE, one row.
Trade: extra predicate on every query + storage retained, vs. unrecoverable erasure
and cascade cost.

**Part C:** the seeded audit rows give U entries (old_data/new_data JSONB). The
"current state" reconstruction: take the newest row for the pk; if op='U' →
`new_data` is current; if op='D' → `old_data` is the final state and the row no
longer exists in the live table. Caveats (exercise 4): the trail only has UPDATE/
DELETE (no INSERTs in this design) — the *initial* state must come from the live
table or a baseline snapshot; rows never updated/deleted have no trail at all.

**Part D:** the audit row shows old/new JSONB diff; `orders.total_cents` equals the
recomputed SUM (trigger kept it honest). DELETE/UPDATE on audit_log silently do
nothing (INSTEAD NOTHING rules) — count unchanged: enforcement lives in the DB, not
the app.

**Exercises:**

1.
```sql
ALTER TABLE products ADD COLUMN deleted_at timestamptz;
CREATE INDEX products_live ON products (vendor_id, created_at DESC) WHERE deleted_at IS NULL;
```
Catalogue queries add `AND deleted_at IS NULL` (or query the partial index's view).
Order history is safe because order_items snapshots `product_name`/`sku` — no join
to the live catalogue is needed to render history; deleted products vanish only from
browsing, never from receipts.

2.
```sql
BEGIN;
UPDATE users SET status = 'deleted' WHERE id = 351;
UPDATE user_profiles
   SET full_name = 'ERASED', phone = NULL, date_of_birth = NULL,
       marketing_opt_in = false
 WHERE user_id = 351;
UPDATE addresses SET line1 = 'ERASED', line2 = NULL, city = 'ERASED',
                     region = NULL, postal_code = 'ERASED'
 WHERE user_id = 351;
-- orders/order_items/payments retained: financial record-keeping requirement.
-- PII inside them: shipping_* snapshot columns must also be anonymised:
UPDATE orders SET shipping_name = 'ERASED', shipping_line1 = 'ERASED'
 WHERE user_id = 351;
COMMIT;
```
Design points: retain totals/timestamps (law), erase free-text PII (GDPR), never
DELETE history rows (audit integrity), document the policy as code.

3. Partition `audit_log` monthly (`PARTITION BY RANGE (occurred_at)`), retention =
  `DROP TABLE audit_log_2026_01` — instant, no bloat, no vacuum storm. DELETE
  batches on a huge append-only table: each delete leaves dead tuples across many
  pages → autovacuum pressure + index churn (docs/01). Drop >> delete for
  time-ordered data. (Caveat: PK must include the partition key.)

4. The March 1st query works only for rows whose U/D were captured *after* the
   trigger existed and only for order_items — product name changes, price changes
   on variants, address edits: none are audited (by design — snapshots make most of
   it unnecessary). The lesson: audit scope is a decision, write it down; the
   alternative (audit everything) costs write throughput everywhere.

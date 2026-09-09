-- 009: payments, refunds, and the audited money table
--
-- payments — "at most one successful payment per order, but keep failed
-- attempts for dispute/audit". Design decision worth remembering:
--
--   We REJECTED a composite FK payments(order_id, status) -> orders(id, status)
--   here: it would force payment.status to mirror order.status forever, so an
--   order could never move past 'paid' while payment rows pointed at the old
--   status. A cross-row invariant like "one successful payment per order" is
--   exactly what a PARTIAL UNIQUE INDEX is for:
--
CREATE TABLE payments (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id      bigint NOT NULL REFERENCES orders (id),
  status        text NOT NULL
                CHECK (status IN ('initiated', 'succeeded', 'failed')),
  amount_cents  bigint NOT NULL CHECK (amount_cents >= 0),
  provider      text NOT NULL,
  provider_ref  text UNIQUE,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

-- The invariant: one 'succeeded' row per order; 'failed'/'initiated' rows are
-- unlimited. Enforced by the database, not by "the code checks first".
CREATE UNIQUE INDEX payments_one_success_per_order
  ON payments (order_id) WHERE status = 'succeeded';

CREATE INDEX idx_payments_order ON payments (order_id);

CREATE TABLE refunds (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint NOT NULL REFERENCES payments (id),
  amount_cents  bigint NOT NULL CHECK (amount_cents > 0),
  reason        text,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------- audit history (docs/07) ----------
-- Generic append-only audit trail. Triggers keep it fed; nothing in the
-- application may write, update or delete from it.
CREATE TABLE audit_log (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  table_name   text NOT NULL,
  op           char(1) NOT NULL CHECK (op IN ('U', 'D')),
  row_pk       text NOT NULL,
  old_data     jsonb,
  new_data     jsonb,
  changed_by   text NOT NULL DEFAULT 'app'
);

CREATE INDEX idx_audit_table_row ON audit_log (table_name, row_pk, occurred_at DESC);

-- Append-only, enforced in the database itself (defense in depth):
CREATE RULE audit_log_no_update AS ON UPDATE TO audit_log DO INSTEAD NOTHING;
CREATE RULE audit_log_no_delete AS ON DELETE TO audit_log DO INSTEAD NOTHING;

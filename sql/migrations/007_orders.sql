-- 007: orders
-- The canonical order state machine. Two structural ideas:
--
--  * orders.total_cents is DENORMALISED from order_items: every UI, email,
--    report and CSV export wants "the order total", and summing 3-30 item rows
--    per order on every read is silly. The trigger in 011 keeps it correct.
--
--  * UNIQUE (id, status) looks redundant (id is already unique), but it lets
--    migration 009 build the composite FK payments(order_id, status) ->
--    orders(id, status): "only orders in a finalisable state may receive a
--    successful payment", enforced by the database.

CREATE TABLE orders (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id            bigint NOT NULL REFERENCES users (id),
  cart_id            uuid,               -- traceability back to the cart; no FK (carts are disposable)
  status             text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'paid', 'shipped', 'delivered',
                                       'cancelled', 'refunded')),
  currency           char(3) NOT NULL DEFAULT 'USD',
  subtotal_cents     bigint NOT NULL DEFAULT 0 CHECK (subtotal_cents >= 0),
  total_cents        bigint NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  occurred_at        timestamptz NOT NULL DEFAULT now(),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  -- Snapshot of delivery details: the address row can change or be deleted
  -- later, the order must still show what was promised at purchase time.
  shipping_name      text,
  shipping_line1     text,
  shipping_city      text,
  shipping_country   char(2),

  -- Target for the reversed FK in 008 (an order must own line #1).
  first_line_no      integer NOT NULL DEFAULT 1
);

-- The dashboard's default view: newest first, per status, per user.
CREATE INDEX idx_orders_user_occurred ON orders (user_id, occurred_at DESC);
CREATE INDEX idx_orders_status_created ON orders (status, created_at DESC);

COMMENT ON COLUMN orders.occurred_at IS 'Business event time; never rewritten by audit tooling.';
COMMENT ON COLUMN orders.total_cents IS 'Denormalised from order_items by trigger; do not write directly.';
COMMENT ON COLUMN orders.first_line_no IS 'Must match an order_items.line_no; enforces >=1 item per order (see 008).';

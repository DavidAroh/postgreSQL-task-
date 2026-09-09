-- 008: order_items
-- Append-only line items with immutable snapshots of what was sold.
--
-- "Every order has at least one item" — enforced with a REVERSED composite FK:
--   * order_items is UNIQUE (order_id, line_no)
--   * orders.first_line_no (default 1) must match an item's line_no
--   * orders -> order_items FK on (id, first_line_no) references (order_id, line_no)
-- An orders row cannot be inserted unless its first line item already exists.
-- Insert items first, then the order (or use a deferred variant — see lab 05).

CREATE TABLE order_items (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id         bigint NOT NULL,
  line_no          integer NOT NULL,
  variant_id       bigint NOT NULL REFERENCES product_variants (id),
  -- Immutable snapshot: what was sold, at what price, under which name/attrs.
  sku              text NOT NULL,
  product_name     text NOT NULL,
  attributes       jsonb NOT NULL DEFAULT '{}'::jsonb,
  qty              integer NOT NULL CHECK (qty > 0),
  unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0),

  UNIQUE (order_id, line_no)
);

-- Lookups like "all sales of variant X" and per-order joins.
CREATE INDEX idx_order_items_variant ON order_items (variant_id);

-- The reversed FK. DEFERRABLE INITIALLY DEFERRED: checked only at COMMIT, so a
-- transaction may insert the order first and its items later. Lab 05 shows how
-- to force the check earlier with SET CONSTRAINTS ... IMMEDIATE.
ALTER TABLE orders
  ADD CONSTRAINT orders_must_have_first_item
  FOREIGN KEY (id, first_line_no)
  REFERENCES order_items (order_id, line_no)
  DEFERRABLE INITIALLY DEFERRED;

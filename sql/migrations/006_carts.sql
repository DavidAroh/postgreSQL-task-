-- 006: carts
-- Carts are cheap, disposable, and abandoned constantly: NO foreign keys to
-- users on purpose. A dangling cart is harmless; FK checks on a hot table are
-- not. Prices are denormalised at add-to-cart time (what the customer saw).

CREATE TABLE carts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     bigint,                        -- deliberately NOT a FK (hot table)
  status      text NOT NULL DEFAULT 'open'
              CHECK (status IN ('open', 'ordered', 'abandoned')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_carts_user_status ON carts (user_id, status);

CREATE TABLE cart_items (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cart_id       uuid NOT NULL REFERENCES carts (id) ON DELETE CASCADE,
  variant_id    bigint NOT NULL REFERENCES product_variants (id),
  qty           integer NOT NULL DEFAULT 1 CHECK (qty > 0),
  price_cents   integer NOT NULL CHECK (price_cents >= 0),  -- snapshot at add-to-cart
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Same variant twice in one cart = one row with a higher qty, not two rows.
ALTER TABLE cart_items
  ADD CONSTRAINT cart_items_cart_variant_key UNIQUE (cart_id, variant_id);

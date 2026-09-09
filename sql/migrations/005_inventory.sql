-- 005: inventory
-- One row per variant (1:1 with product_variants via the FK + UNIQUE).
-- Kept separate from the catalogue because inventory mutates constantly while
-- product rows almost never do -> different vacuum/visibility pressure.
--
-- quantity CHECK (quantity >= 0) makes "overselling" impossible to *store*,
-- but note (lab 07): it does NOT by itself make a read-check-write flow safe
-- under concurrency. It is a backstop, not a concurrency-control mechanism.

CREATE TABLE inventory (
  variant_id  bigint PRIMARY KEY REFERENCES product_variants (id),
  quantity    integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  reserved    integer NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT reserved_le_quantity CHECK (reserved <= quantity)
);

COMMENT ON TABLE inventory IS 'Current stock per variant. 1:1 with product_variants.';

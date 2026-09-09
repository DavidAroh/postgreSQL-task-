-- 004: vendors, products, product_variants
-- Catalogue shape (classic e-commerce):
--   vendor 1:N product 1:N variant
--   product   = the marketing entity ("Air Max 90")
--   variant   = the thing you actually stock and price ("black / 42")
-- Pricing lives on the variant. Inventory lives in its own table (005) because
-- it changes orders of magnitude more often than the catalogue does.

CREATE TABLE vendors (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        text NOT NULL,
  slug        text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE products (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vendor_id   bigint NOT NULL REFERENCES vendors (id),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  description text,
  status      text NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft', 'active', 'archived')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Search support: trigram GIN index -> 'name ILIKE %term%' becomes indexable.
CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
-- Catalogue browsing: vendor page, newest first.
CREATE INDEX idx_products_vendor_created ON products (vendor_id, created_at DESC);

CREATE TABLE product_variants (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id  bigint NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  sku         text NOT NULL,
  attributes  jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {"size":"42","color":"black"}
  price_cents integer NOT NULL,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  -- Business rule as a constraint, not app code:
  CONSTRAINT price_non_negative CHECK (price_cents >= 0),
  -- SKU must look like VEN-XXXXXX-NNN (format-level check; uniqueness below):
  CONSTRAINT sku_format CHECK (sku ~ '^VEN-[A-Z0-9]{6}-[0-9]{3}$')
);

-- SKU must be globally unique *and* lookups by SKU must be fast.
CREATE UNIQUE INDEX idx_variants_sku ON product_variants (sku);
CREATE INDEX idx_variants_product ON product_variants (product_id) WHERE is_active;

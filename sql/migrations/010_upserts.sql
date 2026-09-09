-- 010: upserts
-- Idempotent stock loading, the standard INSERT ... ON CONFLICT pattern.
-- See lab 03 for when to use EXCLUDED vs a re-SELECT.

CREATE OR REPLACE FUNCTION upsert_inventory(p_variant_id bigint, p_qty integer)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO inventory (variant_id, quantity, reserved, updated_at)
  VALUES (p_variant_id, p_qty, 0, now())
  ON CONFLICT (variant_id) DO UPDATE
    SET quantity   = inventory.quantity + EXCLUDED.quantity,
        updated_at = now();
$$;

-- 011: triggers — three small mechanisms used across the schema
--  A) updated_at maintenance (every mutable table)
--  B) orders.total_cents: denormalised counter kept by trigger (docs/03)
--  C) audit history for order_items (docs/07): U/D go to audit_log as JSON

-- ---------- A) updated_at ----------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- For each mutable table: WHEN (OLD.* IS DISTINCT FROM NEW.*) so no-op saves
-- do not churn rows or the audit log.
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON products
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_variants_updated BEFORE UPDATE ON product_variants
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_inventory_updated BEFORE UPDATE ON inventory
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_carts_updated BEFORE UPDATE ON carts
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION set_updated_at();

-- ---------- B) orders.total_cents maintained from order_items ----------
CREATE OR REPLACE FUNCTION order_totals_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_order_id bigint := COALESCE(NEW.order_id, OLD.order_id);
  v_sub      bigint;
BEGIN
  -- Lock the parent order row so concurrent line updates on the same order
  -- serialise here instead of interleaving read-modify-write on totals.
  PERFORM 1 FROM orders WHERE id = v_order_id FOR UPDATE;

  SELECT COALESCE(SUM(qty * unit_price_cents), 0) INTO v_sub
  FROM order_items WHERE order_id = v_order_id;

  UPDATE orders
     SET subtotal_cents = v_sub,
         total_cents    = v_sub          -- flat shipping model
   WHERE id = v_order_id;

  RETURN NULL;  -- AFTER trigger
END $$;

CREATE CONSTRAINT TRIGGER trg_order_totals
  AFTER INSERT OR UPDATE OR DELETE ON order_items
  DEFERRABLE INITIALLY IMMEDIATE
  FOR EACH ROW EXECUTE FUNCTION order_totals_fn();

-- ---------- C) audit history for order_items ----------
CREATE OR REPLACE FUNCTION audit_order_items_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_log (table_name, op, row_pk, old_data, new_data)
    VALUES (TG_TABLE_NAME, 'U',
            NEW.order_id || ':' || NEW.line_no,
            to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO audit_log (table_name, op, row_pk, old_data)
    VALUES (TG_TABLE_NAME, 'D',
            OLD.order_id || ':' || OLD.line_no,
            to_jsonb(OLD));
    RETURN OLD;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_order_items_audit
  AFTER UPDATE OR DELETE ON order_items
  FOR EACH ROW EXECUTE FUNCTION audit_order_items_fn();

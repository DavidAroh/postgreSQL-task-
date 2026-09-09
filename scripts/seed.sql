-- Seed: deterministic, correlated data sized so EXPLAIN is meaningful.
--   400 users, 600 addresses, 30 vendors, 2,500 products, 7,500 variants,
--   10,000 orders, 32k items, 10k payments, plus carts, refunds and audit rows.
-- Ordered seeds make the random skew reproducible: re-running produces the
-- same database, so plan comparisons across runs are honest.
-- The whole seed is ONE transaction: the deferred orders->items FK and the
-- deferred totals trigger are only satisfied at COMMIT.

BEGIN;

TRUNCATE audit_log, refunds, payments, order_items, orders,
         cart_items, carts, inventory, product_variants, products,
         vendors, addresses, user_profiles, users RESTART IDENTITY CASCADE;

-- ---------- users ----------
INSERT INTO users (email, status, created_at)
SELECT 'user' || g || '@example.com',
       (ARRAY['active','active','active','banned','deleted'])[1 + (g % 5)],
       now() - (g || ' hours')::interval
FROM generate_series(1, 400) g;

INSERT INTO user_profiles (user_id, full_name, phone, date_of_birth, marketing_opt_in)
SELECT id, 'User ' || id, '+1-555-' || lpad(id::text, 4, '0'),
       date '1990-01-01' + (id % 8000)::int, id % 3 = 0
FROM users;

-- ---------- addresses (1-2 per user, one default per user) ----------
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
SELECT u.id,
       lbl.label,
       (100 + u.id * 7)::text || ' ' || lbl.label || ' street',
       (ARRAY['Berlin','Prague','Vienna','Warsaw','Lisbon'])[1 + (u.id + ord) % 5],
       lpad(((u.id * 37 + ord * 11) % 99999)::text, 5, '0'),
       (ARRAY['DE','CZ','AT','PL','PT'])[1 + (u.id + ord) % 5],
       ord = 0
FROM users u
CROSS JOIN (VALUES (0, 'home'), (1, 'work')) AS lbl(ord, label)
WHERE u.id % 7 <> 3;   -- every 7th user has no address (normalisation of reality)

-- Second address for every 4th addressed user.
INSERT INTO addresses (user_id, label, line1, city, postal_code, country, is_default)
SELECT a.user_id, 'gym', '12 side street', a.city, a.postal_code, a.country, false
FROM addresses a
WHERE a.label = 'home' AND a.user_id % 4 = 0;

-- ---------- vendors / products / variants ----------
INSERT INTO vendors (name, slug)
SELECT 'Vendor ' || g, 'vendor-' || g FROM generate_series(1, 30) g;

INSERT INTO products (vendor_id, slug, name, description, status, created_at)
SELECT 1 + (g % 30),
       'product-' || g,
       (ARRAY['Runner','Trail Pro','Court Classic','Cloudwalk','Aero Fly',
              'Urban Step','Alpine Grip','Metro Lite'])[1 + g % 8]
         || ' ' || (ARRAY['X1','X2','X3','X4'])[1 + g % 4],
       repeat('A solid everyday shoe. ', 10),
       (ARRAY['active','active','active','active','draft','archived'])[1 + g % 6],
       now() - ((g * 37) % 7200 || ' minutes')::interval
FROM generate_series(1, 2500) g;

INSERT INTO product_variants (product_id, sku, attributes, price_cents, is_active)
SELECT p.id,
       'VEN-' || upper(lpad(md5(p.id::text || k::text), 6, '0')) || '-' || lpad(k::text, 3, '0'),
       jsonb_build_object('size', 36 + ((p.id + k) % 9) * 2, 'color',
                          (ARRAY['black','white','grey','red'])[1 + (p.id + k) % 4]),
       2900 + ((p.id * 13 + k * 7) % 18000),
       k <> 3
FROM products p
CROSS JOIN generate_series(1, 3) k;

-- ---------- inventory: heavy skew for plan demos ----------
-- Some variants are tiny stock, most are modest, a few are huge. The skew is
-- what makes certain queries slow until you index (labs 03/04).
INSERT INTO inventory (variant_id, quantity, reserved)
SELECT v.id,
       CASE
         WHEN v.id % 97 = 0 THEN 0                                    -- sold out (~1%)
         WHEN v.id % 10 = 0 THEN 5000 + (v.id % 20) * 1000            -- bulk (~10%)
         ELSE 5 + (v.id % 40)
       END,
       CASE WHEN v.id % 97 <> 0 AND v.id % 50 = 0 THEN 2 ELSE 0 END
FROM product_variants v;

-- ---------- carts (1 open cart for ~60% of users) ----------
INSERT INTO carts (id, user_id, status, created_at)
SELECT gen_random_uuid(), u.id, 'open', now() - (u.id || ' minutes')::interval
FROM users u
WHERE u.id % 5 <> 0 AND u.status = 'active';

INSERT INTO cart_items (cart_id, variant_id, qty, price_cents)
SELECT c.id, v.id, 1 + (c.user_id % 3),
       (SELECT price_cents FROM product_variants pv WHERE pv.id = v.id)
FROM carts c
JOIN LATERAL (
  SELECT pv.* FROM product_variants pv
  WHERE pv.is_active
  ORDER BY (pv.id * 13 + c.user_id) % 101, pv.id
  LIMIT 2
) v ON true;

-- ---------- orders: Zipf-ish popularity skew ----------
-- Users 1..40 are "whales" (many orders); the rest buy rarely. This skew is
-- what makes hash joins vs nested loops interesting in lab 04.
INSERT INTO orders (user_id, cart_id, status, currency,
                    subtotal_cents, total_cents, occurred_at,
                    shipping_name, shipping_line1, shipping_city, shipping_country)
SELECT u.id, c.id,
       (ARRAY['pending','paid','paid','paid','shipped','shipped',
              'delivered','delivered','delivered','delivered','cancelled','refunded'])[1 + (g * 7 + u.id) % 12],
       'USD',
       0, 0,   -- totals are maintained by the trigger when items arrive
       now() - ((g * 53 + u.id * 11) % 43200 || ' minutes')::interval,
       'User ' || u.id,
       (100 + u.id * 7)::text || ' home street',
       (ARRAY['Berlin','Prague','Vienna','Warsaw','Lisbon'])[1 + u.id % 5],
       (ARRAY['DE','CZ','AT','PL','PT'])[1 + u.id % 5]
FROM generate_series(1, 10000) g
JOIN LATERAL (
  -- pick the buyer directly (whales: users 1..40, 100 orders each; the rest ~17)
  SELECT CASE WHEN g <= 4000 THEN 1 + (g % 40)
              ELSE 41 + ((g * 7) % 360) END AS id
) u ON true
LEFT JOIN LATERAL (
  -- only ~5% of orders keep a cart provenance link, like real checkouts
  SELECT CASE WHEN g % 20 = 0 THEN ca.id END AS id
  FROM carts ca WHERE ca.user_id = u.id LIMIT 1
) c ON true;

-- 5,200 orders get exactly two lines, 4,800 get one.
WITH two_line AS (
  SELECT id FROM orders WHERE id % 25 < 13 LIMIT 5200
),
ins AS (
  INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name,
                           attributes, qty, unit_price_cents)
  SELECT o.id, ln.line_no, v.id, v.sku, p.name, v.attributes,
         1 + ((o.id + ln.line_no) % 3), v.price_cents
  FROM orders o
  JOIN two_line t ON t.id = o.id
  CROSS JOIN (VALUES (1), (2)) ln(line_no)
  JOIN LATERAL (
    SELECT pv.* FROM product_variants pv
    WHERE pv.id % 97 <> 0 OR pv.id > 7400   -- avoid sold-out stock for order history
    ORDER BY (pv.id * 29 + o.id + ln.line_no) % 251, pv.id
    LIMIT 1
  ) v ON true
  JOIN products p ON p.id = v.product_id
  RETURNING order_id
)
INSERT INTO order_items (order_id, line_no, variant_id, sku, product_name,
                         attributes, qty, unit_price_cents)
SELECT o.id, 1, v.id, v.sku, p.name, v.attributes,
       1 + (o.id % 3), v.price_cents
FROM orders o
LEFT JOIN two_line t ON t.id = o.id
JOIN LATERAL (
  SELECT pv.* FROM product_variants pv
  WHERE pv.id % 97 <> 0 OR pv.id > 7400
  ORDER BY (pv.id * 29 + o.id) % 251, pv.id
  LIMIT 1
) v ON true
JOIN products p ON p.id = v.product_id
WHERE t.id IS NULL;

-- Set every order's first_line_no to a real line, then let the trigger totals
-- reflect the items (the FK orders -> order_items(id, first_line_no) is
-- deferrable and must hold at COMMIT).
UPDATE orders o
SET first_line_no = sub.min_line
FROM (SELECT order_id, MIN(line_no) AS min_line
      FROM order_items GROUP BY order_id) sub
WHERE sub.order_id = o.id;

-- Sanity: totals were recomputed by the trigger on item insert.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad
  FROM orders o
  WHERE o.subtotal_cents <> COALESCE((
    SELECT SUM(qty * unit_price_cents) FROM order_items i WHERE i.order_id = o.id), 0);
  IF bad > 0 THEN
    RAISE EXCEPTION 'seed inconsistency: % orders with wrong totals', bad;
  END IF;
END $$;

-- ---------- payments / refunds ----------
INSERT INTO payments (order_id, status, amount_cents, provider, provider_ref, occurred_at)
SELECT o.id,
       CASE WHEN o.status = 'pending' THEN 'initiated'
            WHEN o.status = 'cancelled' THEN 'failed'
            ELSE 'succeeded' END,   -- refunded orders DID capture money first
       o.total_cents, 'stripe',
       'ch_' || md5(o.id::text),
       o.occurred_at + '2 minutes'::interval
FROM orders o;

-- A few failed attempts on paid orders (tests the partial unique index).
INSERT INTO payments (order_id, status, amount_cents, provider, provider_ref, occurred_at)
SELECT id, 'failed', total_cents, 'stripe', 'ch_fail_' || md5(id::text), occurred_at
FROM orders WHERE id % 100 = 0 AND status <> 'pending';

-- Refunds against succeeded payments of refunded orders.
INSERT INTO refunds (payment_id, amount_cents, reason, occurred_at)
SELECT p.id, p.amount_cents, 'customer request', p.occurred_at + '1 day'::interval
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE p.status = 'succeeded' AND o.status = 'refunded';

-- ---------- a slice of audit history ----------
INSERT INTO audit_log (table_name, op, row_pk, old_data, new_data)
SELECT 'order_items', 'U', i.order_id || ':' || i.line_no,
       to_jsonb(i) || jsonb_build_object('qty', i.qty - 1),
       to_jsonb(i)
FROM order_items i
WHERE i.order_id % 200 = 0;

ANALYZE;

COMMIT;

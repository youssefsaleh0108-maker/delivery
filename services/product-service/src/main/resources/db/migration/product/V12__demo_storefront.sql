-- A browsable storefront for local demos and UAT.
--
-- Separate from V11 on purpose: V11 is the schema change and must run everywhere, this is sample
-- content. Owned by the synthetic merchant 'demo-merchant' so it never collides with a real
-- merchant's Keycloak sub, and so it can be identified and removed with a single predicate.
--
-- The three store states a storefront has to render are all represented deliberately: most stores
-- are open, one is flagged busy, and one is outside its hours. A demo where everything is green
-- proves nothing about the states that actually matter.

-- Aisles the seeded catalog needs. The V10 starter tree only had six nodes and no leaf categories
-- for anything outside food.
INSERT INTO categories (id, name, parent_id) VALUES
    ('a0000001-0000-4000-8000-000000000001', 'Coffee & Tea',     NULL),
    ('a0000002-0000-4000-8000-000000000002', 'Convenience',      NULL),
    ('a0000003-0000-4000-8000-000000000003', 'Electronics',      NULL),
    ('a0000004-0000-4000-8000-000000000004', 'Flowers & Gifts',  NULL),
    ('a0000010-0000-4000-8000-000000000010', 'Dairy & Eggs',     '22222222-2222-4222-8222-222222222222'),
    ('a0000011-0000-4000-8000-000000000011', 'Snacks',           '22222222-2222-4222-8222-222222222222'),
    ('a0000012-0000-4000-8000-000000000012', 'Beverages',        '22222222-2222-4222-8222-222222222222'),
    ('a0000013-0000-4000-8000-000000000013', 'Household',        '22222222-2222-4222-8222-222222222222'),
    ('a0000020-0000-4000-8000-000000000020', 'Mains',            '44444444-4444-4444-8444-444444444444'),
    ('a0000021-0000-4000-8000-000000000021', 'Sides',            '44444444-4444-4444-8444-444444444444'),
    ('a0000022-0000-4000-8000-000000000022', 'Desserts',         '44444444-4444-4444-8444-444444444444');

INSERT INTO stores (
    id, merchant_id, name, slug, vertical, tagline, tags,
    rating, rating_count, delivery_fee, min_order, eta_min_minutes, eta_max_minutes, status)
VALUES
    ('50000001-0000-4000-8000-000000000001', 'demo-merchant', 'Beirut Grill', 'beirut-grill',
     'RESTAURANT', 'Charcoal grills and mezze, all day',
     '["Lebanese","Grills","Mezze"]'::jsonb, 4.8, 1240, 2.50, 10.00, 25, 40, 'ACTIVE'),

    ('50000002-0000-4000-8000-000000000002', 'demo-merchant', 'Nonna''s Pizzeria', 'nonnas-pizzeria',
     'RESTAURANT', 'Wood-fired, thin crust, no shortcuts',
     '["Italian","Pizza","Pasta"]'::jsonb, 4.6, 860, 1.99, 8.00, 30, 45, 'ACTIVE'),

    ('50000003-0000-4000-8000-000000000003', 'demo-merchant', 'Roast & Co', 'roast-and-co',
     'COFFEE', 'Single-origin espresso and fresh bakes',
     '["Coffee","Breakfast","Bakery"]'::jsonb, 4.9, 2110, 1.50, 5.00, 15, 25, 'ACTIVE'),

    -- The dark store. Fast, cheap, high SKU count — the Toters Fresh equivalent, and the reason the
    -- Aisles tab exists at all.
    ('50000004-0000-4000-8000-000000000004', 'demo-merchant', 'Fresh Market', 'fresh-market',
     'GROCERY', 'Groceries in 15 minutes',
     '["Groceries","Produce","Daily"]'::jsonb, 4.5, 3480, 0.99, 12.00, 10, 20, 'ACTIVE'),

    ('50000005-0000-4000-8000-000000000005', 'demo-merchant', 'NightOwl', 'nightowl',
     'CONVENIENCE', 'Open when nothing else is',
     '["24/7","Snacks","Essentials"]'::jsonb, 4.2, 540, 1.75, 5.00, 15, 30, 'ACTIVE'),

    ('50000006-0000-4000-8000-000000000006', 'demo-merchant', 'CareFirst Pharmacy', 'carefirst-pharmacy',
     'PHARMACY', 'Prescriptions, care and wellbeing',
     '["Pharmacy","Health","Baby"]'::jsonb, 4.7, 420, 2.00, 0.00, 20, 35, 'ACTIVE'),

    ('50000007-0000-4000-8000-000000000007', 'demo-merchant', 'VoltEdge', 'voltedge',
     'ELECTRONICS', 'Chargers, cables and things that beep',
     '["Electronics","Accessories","Audio"]'::jsonb, 4.4, 310, 3.50, 15.00, 40, 70, 'ACTIVE'),

    -- Deliberately outside its hours below, so the storefront has a genuinely Closed card to render.
    ('50000008-0000-4000-8000-000000000008', 'demo-merchant', 'Bloom & Wrap', 'bloom-and-wrap',
     'FLOWERS_GIFTS', 'Same-day flowers and wrapped gifts',
     '["Flowers","Gifts","Occasions"]'::jsonb, 4.8, 190, 4.00, 20.00, 45, 90, 'ACTIVE');

-- Everything open 08:00-23:00, seven days, then the exceptions below.
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '08:00', TIME '23:00'
FROM stores s
CROSS JOIN generate_series(1, 7) AS d
WHERE s.merchant_id = 'demo-merchant'
  AND s.slug NOT IN ('nightowl', 'bloom-and-wrap', 'roast-and-co');

-- Round the clock. Two rows per day rather than one 00:00-24:00 row, because `time` has no 24:00
-- and chk_hours_order forbids a window that wraps.
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '00:00', TIME '23:59:59'
FROM stores s CROSS JOIN generate_series(1, 7) AS d
WHERE s.slug = 'nightowl';

-- Split hours: the morning rush and then again for the afternoon. This is the case a single
-- opens/closes pair per day cannot represent, which is why store_hours is a table.
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '06:30', TIME '11:30'
FROM stores s CROSS JOIN generate_series(1, 7) AS d
WHERE s.slug = 'roast-and-co';
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '14:00', TIME '19:00'
FROM stores s CROSS JOIN generate_series(1, 7) AS d
WHERE s.slug = 'roast-and-co';

-- A one-hour window nobody is awake for: reliably renders as Closed.
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '03:00', TIME '04:00'
FROM stores s CROSS JOIN generate_series(1, 7) AS d
WHERE s.slug = 'bloom-and-wrap';

-- The kitchen is behind. Self-expiring, so a demo left running overnight recovers by itself.
UPDATE stores SET busy_until = now() + interval '6 hours' WHERE slug = 'nonnas-pizzeria';

INSERT INTO store_offers (id, store_id, kind, title, subtitle, value, min_subtotal) VALUES
    ('60000001-0000-4000-8000-000000000001', '50000001-0000-4000-8000-000000000001',
     'PERCENT_OFF', '20% off mezze', 'On orders over 15.00', 20, 15.00),
    ('60000002-0000-4000-8000-000000000002', '50000002-0000-4000-8000-000000000002',
     'FREE_DELIVERY', 'Free delivery', 'On orders over 20.00', NULL, 20.00),
    ('60000003-0000-4000-8000-000000000003', '50000003-0000-4000-8000-000000000003',
     'AMOUNT_OFF', '2.00 off breakfast', 'Before 11:00', 2.00, 6.00),
    ('60000004-0000-4000-8000-000000000004', '50000004-0000-4000-8000-000000000004',
     'FREE_DELIVERY', 'Free delivery', 'Every order this week', NULL, 0.00),
    -- Platform-wide: no store_id. Renders in the Offers tab above the store-specific ones.
    ('60000005-0000-4000-8000-000000000005', NULL,
     'PERCENT_OFF', '10% off your first order', 'Automatically applied at checkout', 10, 0.00);

-- Catalog. Ids are generated: nothing references a product by a fixed id, and forty hand-written
-- UUIDs would be forty chances to typo one.
INSERT INTO products (id, merchant_id, store_id, name, description, price, category_id, status)
-- The uuid casts are required, not decorative: literals in a standalone VALUES list resolve to
-- `text`, and text does not implicitly assign to a uuid column.
SELECT gen_random_uuid(), 'demo-merchant', v.store_id::uuid, v.name, v.description,
       v.price::numeric(12, 2), v.category_id::uuid, 'ACTIVE'
FROM (VALUES
    -- Beirut Grill
    ('50000001-0000-4000-8000-000000000001', 'Mixed Grill Platter', 'Shish taouk, kafta and lamb, with garlic sauce and pickles', 24.00, 'a0000020-0000-4000-8000-000000000020'),
    ('50000001-0000-4000-8000-000000000001', 'Shish Taouk Wrap', 'Marinated chicken, garlic, pickles, in saj bread', 8.50, 'a0000020-0000-4000-8000-000000000020'),
    ('50000001-0000-4000-8000-000000000001', 'Hummus Beiruti', 'Chickpeas, tahini, parsley, a little chilli', 6.00, 'a0000021-0000-4000-8000-000000000021'),
    ('50000001-0000-4000-8000-000000000001', 'Tabbouleh', 'Parsley, tomato, bulgur, lemon', 6.50, 'a0000021-0000-4000-8000-000000000021'),
    ('50000001-0000-4000-8000-000000000001', 'Batata Harra', 'Fried potato, coriander, chilli, garlic', 5.50, 'a0000021-0000-4000-8000-000000000021'),
    ('50000001-0000-4000-8000-000000000001', 'Knafeh', 'Semolina, cheese, orange blossom syrup', 7.00, 'a0000022-0000-4000-8000-000000000022'),

    -- Nonna's Pizzeria
    ('50000002-0000-4000-8000-000000000002', 'Margherita', 'San Marzano, fior di latte, basil', 11.00, 'a0000020-0000-4000-8000-000000000020'),
    ('50000002-0000-4000-8000-000000000002', 'Diavola', 'Spicy salami, chilli, mozzarella', 13.50, 'a0000020-0000-4000-8000-000000000020'),
    ('50000002-0000-4000-8000-000000000002', 'Quattro Formaggi', 'Mozzarella, gorgonzola, fontina, parmesan', 14.00, 'a0000020-0000-4000-8000-000000000020'),
    ('50000002-0000-4000-8000-000000000002', 'Tagliatelle Ragu', 'Slow-cooked beef and pork ragu', 15.00, 'a0000020-0000-4000-8000-000000000020'),
    ('50000002-0000-4000-8000-000000000002', 'Garlic Focaccia', 'Rosemary, sea salt, olive oil', 5.00, 'a0000021-0000-4000-8000-000000000021'),
    ('50000002-0000-4000-8000-000000000002', 'Tiramisu', 'Mascarpone, espresso, cocoa', 6.50, 'a0000022-0000-4000-8000-000000000022'),

    -- Roast & Co
    ('50000003-0000-4000-8000-000000000003', 'Flat White', 'Double ristretto, silky microfoam', 4.20, 'a0000001-0000-4000-8000-000000000001'),
    ('50000003-0000-4000-8000-000000000003', 'Large Cappuccino', 'Skimmed milk available, easy on the foam', 4.50, 'a0000001-0000-4000-8000-000000000001'),
    ('50000003-0000-4000-8000-000000000003', 'Iced Latte', 'Vanilla syrup optional', 4.80, 'a0000001-0000-4000-8000-000000000001'),
    ('50000003-0000-4000-8000-000000000003', 'Filter Batch Brew', 'Rotating single origin', 3.50, 'a0000001-0000-4000-8000-000000000001'),
    ('50000003-0000-4000-8000-000000000003', 'Butter Croissant', 'Laminated overnight, baked at six', 3.20, '55555555-5555-4555-8555-555555555555'),
    ('50000003-0000-4000-8000-000000000003', 'Almond Danish', 'Frangipane, flaked almonds', 3.80, '55555555-5555-4555-8555-555555555555'),

    -- Fresh Market (the dark store: deliberately the widest aisle spread)
    ('50000004-0000-4000-8000-000000000004', 'Whole Milk 1L', 'Fresh, pasteurised', 1.40, 'a0000010-0000-4000-8000-000000000010'),
    ('50000004-0000-4000-8000-000000000004', 'Free-Range Eggs (12)', 'Large, barn laid', 3.90, 'a0000010-0000-4000-8000-000000000010'),
    ('50000004-0000-4000-8000-000000000004', 'Greek Yoghurt 500g', 'Strained, 10% fat', 2.60, 'a0000010-0000-4000-8000-000000000010'),
    ('50000004-0000-4000-8000-000000000004', 'Halloumi 250g', 'Grilling cheese', 4.50, 'a0000010-0000-4000-8000-000000000010'),
    ('50000004-0000-4000-8000-000000000004', 'Bananas 1kg', 'Ripe and ready', 1.80, '66666666-6666-4666-8666-666666666666'),
    ('50000004-0000-4000-8000-000000000004', 'Avocado (2)', 'Hass, ready to eat', 3.20, '66666666-6666-4666-8666-666666666666'),
    ('50000004-0000-4000-8000-000000000004', 'Baby Spinach 200g', 'Washed and ready', 2.10, '66666666-6666-4666-8666-666666666666'),
    ('50000004-0000-4000-8000-000000000004', 'Cherry Tomatoes 250g', 'On the vine', 2.40, '66666666-6666-4666-8666-666666666666'),
    ('50000004-0000-4000-8000-000000000004', 'Salted Crisps 150g', 'Hand cooked', 2.20, 'a0000011-0000-4000-8000-000000000011'),
    ('50000004-0000-4000-8000-000000000004', 'Dark Chocolate 100g', '70% cocoa', 2.80, 'a0000011-0000-4000-8000-000000000011'),
    ('50000004-0000-4000-8000-000000000004', 'Sparkling Water 6x500ml', 'Lightly carbonated', 3.60, 'a0000012-0000-4000-8000-000000000012'),
    ('50000004-0000-4000-8000-000000000004', 'Orange Juice 1L', 'Not from concentrate', 3.10, 'a0000012-0000-4000-8000-000000000012'),
    ('50000004-0000-4000-8000-000000000004', 'Dishwasher Tablets (30)', 'All in one', 6.90, 'a0000013-0000-4000-8000-000000000013'),
    ('50000004-0000-4000-8000-000000000004', 'Kitchen Roll (4)', 'Two ply', 4.20, 'a0000013-0000-4000-8000-000000000013'),

    -- NightOwl
    ('50000005-0000-4000-8000-000000000005', 'Instant Noodles', 'Because it is 2am', 1.20, 'a0000002-0000-4000-8000-000000000002'),
    ('50000005-0000-4000-8000-000000000005', 'Energy Drink 250ml', 'Sugar free', 2.00, 'a0000012-0000-4000-8000-000000000012'),
    ('50000005-0000-4000-8000-000000000005', 'Ice Cream Tub 500ml', 'Salted caramel', 5.50, 'a0000011-0000-4000-8000-000000000011'),
    ('50000005-0000-4000-8000-000000000005', 'Phone Charger Cable', 'USB-C, 1m', 8.00, 'a0000003-0000-4000-8000-000000000003'),
    ('50000005-0000-4000-8000-000000000005', 'Paracetamol 500mg (16)', 'Pain and fever relief', 3.00, '33333333-3333-4333-8333-333333333333'),

    -- CareFirst Pharmacy
    ('50000006-0000-4000-8000-000000000006', 'Ibuprofen 400mg (24)', 'Anti-inflammatory', 4.50, '33333333-3333-4333-8333-333333333333'),
    ('50000006-0000-4000-8000-000000000006', 'Vitamin D3 1000IU (90)', 'Daily supplement', 9.90, '33333333-3333-4333-8333-333333333333'),
    ('50000006-0000-4000-8000-000000000006', 'Antiseptic Cream 30g', 'For minor cuts and grazes', 5.20, '33333333-3333-4333-8333-333333333333'),
    ('50000006-0000-4000-8000-000000000006', 'Baby Wipes (72)', 'Fragrance free', 3.40, '33333333-3333-4333-8333-333333333333'),
    ('50000006-0000-4000-8000-000000000006', 'Digital Thermometer', 'Ten second read', 12.00, '33333333-3333-4333-8333-333333333333'),

    -- VoltEdge
    ('50000007-0000-4000-8000-000000000007', 'USB-C Fast Charger 65W', 'GaN, two ports', 34.00, 'a0000003-0000-4000-8000-000000000003'),
    ('50000007-0000-4000-8000-000000000007', 'Wireless Earbuds', 'Active noise cancelling', 89.00, 'a0000003-0000-4000-8000-000000000003'),
    ('50000007-0000-4000-8000-000000000007', 'Power Bank 20000mAh', 'Charges a laptop', 45.00, 'a0000003-0000-4000-8000-000000000003'),
    ('50000007-0000-4000-8000-000000000007', 'HDMI Cable 2m', '4K 120Hz', 14.00, 'a0000003-0000-4000-8000-000000000003'),
    ('50000007-0000-4000-8000-000000000007', 'Bluetooth Speaker', 'Waterproof, 12h battery', 59.00, 'a0000003-0000-4000-8000-000000000003'),

    -- Bloom & Wrap
    ('50000008-0000-4000-8000-000000000008', 'Seasonal Bouquet', 'Florist''s choice, wrapped', 32.00, 'a0000004-0000-4000-8000-000000000004'),
    ('50000008-0000-4000-8000-000000000008', 'Dozen Red Roses', 'Long stem, gift boxed', 55.00, 'a0000004-0000-4000-8000-000000000004'),
    ('50000008-0000-4000-8000-000000000008', 'Orchid Plant', 'In a ceramic pot', 28.00, 'a0000004-0000-4000-8000-000000000004'),
    ('50000008-0000-4000-8000-000000000008', 'Gift Wrapping', 'Paper, ribbon and a handwritten card', 6.00, 'a0000004-0000-4000-8000-000000000004')
) AS v(store_id, name, description, price, category_id);

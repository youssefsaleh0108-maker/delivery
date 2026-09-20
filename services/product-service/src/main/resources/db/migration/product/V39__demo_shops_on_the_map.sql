-- The V12 demo storefront, placed on the map and moved onto the platform's calendar.
--
-- Why this is a new migration rather than an edit to V12
-- ------------------------------------------------------
-- V12 has run everywhere. Editing it in place changes its checksum, and Flyway's validation then
-- refuses to start the service — the crash-loop V20-V22 caused for a different reason, and this
-- schema has no repair step anywhere in the repository. Nothing here has ever edited an applied
-- migration, so this does not either. A fresh environment runs V12 and then this, and ends in the
-- state V12 would have produced if coordinates had existed when it was written; an environment that
-- already has the demo shops gets the same top-up.
--
-- Why it touches nothing but the demo shops
-- -----------------------------------------
-- Every predicate below is `merchant_id = 'demo-merchant'` AND "this field is still empty".
--
-- That is not caution for its own sake. A real shop's stored zone is the zone its OPENING HOURS
-- were typed against: a shop that entered 08:00-23:00 while the row said UTC meant 08:00-23:00 UTC,
-- and rewriting the zone here would silently move its shutters by three hours. The demo shops are
-- the one set of rows whose hours this repository wrote itself (V12, lines 66-95), so they are the
-- one set it may reinterpret. Real shops are dealt with one at a time, by name, with
-- deploy/k3s/scripts/shop-pins-and-zone.sh.
--
-- 'demo-merchant' is a synthetic id V12 chose precisely so its rows could be identified with a
-- single predicate; it can never be a real merchant's Keycloak sub.

-- ---------------------------------------------------------------------------------------------
-- The pins.
-- ---------------------------------------------------------------------------------------------
--
-- Real places in and around Beirut, spread across roughly nine kilometres, because a demo where
-- every shop sits on the same corner cannot show a distance feature working: "shops near you", the
-- radius filter and the delivery circle all answer the same for every shop and prove nothing.
-- Hamra to Antelias is far enough that a 5 km search (delivery.catalog.item-search.radius-metres)
-- includes most of them and excludes the last, which is the case worth seeing.
--
-- `location`, the PostGIS geography V20 added, is GENERATED from these two columns — never written,
-- and never able to disagree with them. The CHECK constraints V20 added stand behind every value:
-- in range, both-or-neither, and not Null Island.
--
-- delivery_radius_metres is the shop's own circle (V24). Given a spread of sizes so the "this shop
-- does not reach you" path has something to answer with: the dark store carries the city, the
-- pharmacy and the florist carry their own neighbourhood.
UPDATE stores SET latitude = v.lat, longitude = v.lng,
                  delivery_radius_metres = COALESCE(delivery_radius_metres, v.radius)
FROM (VALUES
    -- Hamra
    ('50000001-0000-4000-8000-000000000001'::uuid, 33.895900, 35.482000, 4000),
    -- Mar Mikhael
    ('50000002-0000-4000-8000-000000000002'::uuid, 33.899500, 35.520000, 3000),
    -- Gemmayzeh
    ('50000003-0000-4000-8000-000000000003'::uuid, 33.895500, 35.515500, 2500),
    -- Achrafieh. The dark store: fifteen-minute groceries, so the widest circle of the eight.
    ('50000004-0000-4000-8000-000000000004'::uuid, 33.886900, 35.520000, 8000),
    -- Verdun. Open when nothing else is, and reaches across town to prove it.
    ('50000005-0000-4000-8000-000000000005'::uuid, 33.879700, 35.484200, 6000),
    -- Badaro
    ('50000006-0000-4000-8000-000000000006'::uuid, 33.872000, 35.515500, 2500),
    -- Downtown
    ('50000007-0000-4000-8000-000000000007'::uuid, 33.895900, 35.504000, 5000),
    -- Antelias, ~9 km up the coast: the shop a search centred on Hamra should NOT return.
    ('50000008-0000-4000-8000-000000000008'::uuid, 33.915000, 35.585000, 2000)
) AS v(id, lat, lng, radius)
WHERE stores.id = v.id
  AND stores.merchant_id = 'demo-merchant'
  -- Idempotent, and it never moves a pin somebody placed on purpose. Re-running this, or running it
  -- against an environment where a demo shop has already been dragged somewhere, changes nothing.
  AND stores.latitude IS NULL;

-- ---------------------------------------------------------------------------------------------
-- The calendar.
-- ---------------------------------------------------------------------------------------------
--
-- V12's store_hours were written as Lebanese trading hours — a grill "all day", a coffee shop from
-- 07:00, a florist shut in the evening — and then read in UTC, which is three hours behind Beirut
-- in summer. So the demo storefront has always shown the wrong shop open at the wrong time, and the
-- "one shop is deliberately Closed" case V12 set up was closed at a different hour than intended.
--
-- Only rows that still say UTC, so a demo environment deliberately moved to another zone keeps it.
UPDATE stores
SET timezone = 'Asia/Beirut'
WHERE merchant_id = 'demo-merchant'
  AND timezone = 'UTC';

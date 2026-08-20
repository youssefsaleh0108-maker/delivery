-- Gives opening hours to any listed store that has none.
--
-- Fixes a regression introduced by V11. That migration invented a store for every merchant who
-- already had products, and listed it ACTIVE so their catalog stayed on sale — but it created no
-- store_hours rows. Availability is derived entirely from those rows, so every backfilled store
-- computed as CLOSED forever: the products were visible and permanently unorderable.
--
-- Broad hours rather than 24/7, because these are placeholders their owner is expected to correct,
-- and a shop that claims to be open at 04:00 is a worse default than one that closes overnight.
--
-- Written as "any ACTIVE store with no hours" rather than "the stores V11 created" so it is also
-- correct on a fresh database, where V11's backfill selects nothing and this touches nothing.
INSERT INTO store_hours (id, store_id, day_of_week, opens_at, closes_at)
SELECT gen_random_uuid(), s.id, d, TIME '08:00', TIME '23:00'
FROM stores s
CROSS JOIN generate_series(1, 7) AS d
WHERE s.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM store_hours h WHERE h.store_id = s.id);

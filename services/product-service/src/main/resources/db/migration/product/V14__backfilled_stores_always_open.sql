-- Widens the placeholder hours V13 gave to backfilled stores.
--
-- V13 fixed a store listed with no hours at all (permanently closed). It gave them 08:00-23:00,
-- which was still wrong in a quieter way: before the store model existed, those merchants' products
-- were orderable at any hour, and a narrow guessed window silently made them unorderable overnight.
-- A migration that invents data must not invent a restriction the customer never had.
--
-- Always-open until the owner sets real hours on the My Shop page, matching what
-- StoreService.requireStoreFor now does for a newly provisioned store.
--
-- Scoped precisely to the placeholders V11 created — 'Store <8 hex>' owned by a real merchant. The
-- seeded demo shops keep their deliberate hours, because their split and out-of-hours windows are
-- the point of the demo.
UPDATE store_hours h
SET opens_at = TIME '00:00', closes_at = TIME '23:59:59'
FROM stores s
WHERE h.store_id = s.id
  AND s.merchant_id <> 'demo-merchant'
  AND s.name ~ '^Store [0-9a-f]{8}$'
  AND h.opens_at = TIME '08:00'
  AND h.closes_at = TIME '23:00';

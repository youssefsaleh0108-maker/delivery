-- When a shop first listed: what "New on YouDrop" means.
--
-- The neighbourhood browse's "New on YouDrop" chip used to read created_at, which is stamped when
-- the DRAFT row is inserted. A merchant who spent six weeks setting up before listing was already
-- six weeks "old" on the day they went live, and a draft left sitting for a year was never new at
-- all. published_at is stamped by a shop's FIRST publish and never moved by a later one: a shop that
-- was suspended and listed again has not just joined.
--
-- Backfill, best effort. Nothing recorded when the existing shops listed, so every shop already past
-- DRAFT takes its created_at — ACTIVE shops, and SUSPENDED ones too, which in practice were listed
-- before (leaving them null would stamp them "new" the day they are reinstated). created_at is never
-- later than the real listing, so the backfill can only make a shop look OLDER than it is, never
-- newer: the worst case is a shop that listed recently after a long set-up missing a few weeks of the
-- chip, which is the right way round for a badge that is a claim. Shops still in DRAFT stay null and
-- are stamped when they list. The UPDATE fires trg_stores_updated_at like any other write; nothing
-- reads a store's updated_at to mean "the merchant edited it".
ALTER TABLE stores ADD COLUMN published_at timestamptz;

UPDATE stores SET published_at = created_at WHERE status <> 'DRAFT';

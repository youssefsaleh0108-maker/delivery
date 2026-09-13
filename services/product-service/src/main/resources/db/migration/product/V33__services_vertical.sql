-- The services marketplace, slice 1: the SERVICES vertical, and what each service shop does.
--
-- A service provider (a print shop, a tailor, a repairer, a photo studio) is a merchant whose store
-- has the vertical SERVICES and one service category. A service shop needs everything a shop already
-- has: name, imagery, hours, pin, zones, rating, favourites, publish and suspend. That is why this is
-- one column and one more vertical rather than a table of its own.
--
-- The CHECKs hold the pair together in both directions: a SERVICES store must say what it does, and
-- a goods store must not carry a service category, so no stray write can list a restaurant under
-- Printing. Every existing row passes both. None is SERVICES, because chk_store_vertical refused that
-- until now, and the new column starts null.
--
-- The category list is the whole taxonomy, including the categories not yet offered. Which ones are
-- open to providers and shown to customers is configuration (delivery.product.services.enabled-
-- categories), not schema. Opening Cleaning must not need a migration, and closing it must not have
-- to delete a shop that already chose it.
--
-- categories.chk_category_vertical is deliberately NOT widened. A category's vertical exists only to
-- put a chip on the Home strip, and service shops never appear on Home (owner default 14 in
-- docs/figma-services-designs.md). So the database refuses a Services chip as well as the service.
--
-- Storefront isolation ships in the same change: every storefront read leaves SERVICES out unless it
-- asks for it by name. This migration must reach an environment BEFORE its first SERVICES store is
-- created. Installed apps read an unknown vertical as RESTAURANT, so a print shop that reached the
-- Home storefront of an app built before this change would be drawn as a restaurant.

ALTER TABLE stores DROP CONSTRAINT chk_store_vertical;
ALTER TABLE stores ADD CONSTRAINT chk_store_vertical CHECK (vertical IN (
    'RESTAURANT', 'COFFEE', 'GROCERY', 'CONVENIENCE', 'PHARMACY', 'ELECTRONICS', 'FLOWERS_GIFTS',
    'SERVICES'));

ALTER TABLE stores ADD COLUMN service_category varchar(24);

-- A null passes a CHECK, so goods shops need no special case here; the next constraint is the one
-- that decides who may be null.
ALTER TABLE stores ADD CONSTRAINT chk_store_service_category CHECK (service_category IN (
    'PRINTING', 'TAILORING', 'REPAIRS', 'PHOTOGRAPHY', 'CLEANING', 'BEAUTY', 'TUTORING'));

ALTER TABLE stores ADD CONSTRAINT chk_store_service_category_vertical
    CHECK ((vertical = 'SERVICES') = (service_category IS NOT NULL));

-- The Services tab's lists: live service shops in a category, best-rated first. Partial like
-- idx_stores_live_vertical, and narrower: only service shops have a category to sort by.
CREATE INDEX idx_stores_live_services ON stores (service_category, rating DESC NULLS LAST)
    WHERE status = 'ACTIVE' AND vertical = 'SERVICES';

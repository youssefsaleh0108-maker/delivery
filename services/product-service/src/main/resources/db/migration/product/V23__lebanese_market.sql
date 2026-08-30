-- The Lebanese-market store facts: power, place, and trust.
--
-- power_status is what the lights are doing RIGHT NOW — mains, the shop's own generator, or dark —
-- set by the merchant the way "busy" already is, because in a country of daily cuts "is this shop
-- actually able to cook" is the first question a customer asks of a storefront. UNKNOWN is the
-- honest default for every shop that has never said; the storefront draws no chip for it rather
-- than inventing a green one. power_note is the one-liner under the chip ("Ovens fully hot",
-- "Cold storage active"), power_updated_at is what "auto-updated" honestly means: when the
-- merchant last said so.
--
-- neighborhood is the district identity (Mar Mikhael, Hamra, Badaro...) the hyperlocal browse
-- filters on — a name, not a geometry; the delivery-zone polygons already answer "can they
-- deliver", this answers "is this MY street's shop".
--
-- verified_local is the dekkane trust badge, and it is deliberately NOT merchant-writable: a
-- badge a shop can pin on itself is decoration, so only Backoffice tooling sets it.
ALTER TABLE stores ADD COLUMN power_status VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN';
ALTER TABLE stores ADD CONSTRAINT chk_store_power_status
    CHECK (power_status IN ('UNKNOWN', 'MAINS', 'GENERATOR', 'DARK'));
ALTER TABLE stores ADD COLUMN power_note VARCHAR(160);
ALTER TABLE stores ADD COLUMN power_updated_at TIMESTAMPTZ;

ALTER TABLE stores ADD COLUMN neighborhood VARCHAR(80);
CREATE INDEX ix_stores_neighborhood ON stores (neighborhood) WHERE neighborhood IS NOT NULL;

ALTER TABLE stores ADD COLUMN verified_local BOOLEAN NOT NULL DEFAULT FALSE;

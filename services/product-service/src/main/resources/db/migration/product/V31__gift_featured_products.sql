-- ---------------------------------------------------------------------------------------------
-- Featured gift bundles for the customer gift hub (Figma 112:1684).
--
-- WHAT A "CARE BUNDLE" IS HERE: an ordinary product a shop already sells — a "Family Essentials"
-- box, a "Lebanese Breakfast" — that the back office has picked to show on the gift hub. Not a new
-- kind of thing: it is priced, stocked, published and ordered exactly like every other product,
-- from one shop, through the one-shop basket. A separate bundle entity would give the hub prices
-- checkout does not charge, and a bundle spanning several shops needs a basket that does not exist.
--
-- WHO PICKS: the back office, not the merchant. The hub is the platform's window for people
-- sending help home; a merchant who could feature their own products would turn it into ad space.
--
-- gift_featured_at orders the hub (newest pick first) and records when the pick was made, so "why
-- is this on the hub" has an answer. Both or neither. Every existing product is unfeatured.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE products
    ADD COLUMN gift_featured    boolean     NOT NULL DEFAULT false,
    ADD COLUMN gift_featured_at timestamptz;

ALTER TABLE products ADD CONSTRAINT chk_products_gift_featured_at
    CHECK (gift_featured = (gift_featured_at IS NOT NULL));

-- The hub's only query: the handful of featured products, newest pick first. Partial, because
-- almost no product is ever featured.
CREATE INDEX idx_products_gift_featured ON products (gift_featured_at DESC) WHERE gift_featured;

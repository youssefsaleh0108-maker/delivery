-- Banners, and pictures for the category strip.
--
-- Two related gaps. The home screen's promotional rail is built from offers, which are commercial
-- rules rather than artwork — there is nowhere to put a designed banner. And the category chips are
-- driven by a hard-coded enum with Material icons, so nobody can give a category its own image.

CREATE TABLE banners (
    id          uuid         PRIMARY KEY,
    title       varchar(160) NOT NULL,
    subtitle    varchar(240),

    -- Object key in the product-images bucket. Nullable so a banner can be drafted before its
    -- artwork exists; the clients fall back to a brand gradient rather than a broken image.
    image_ref   varchar(512),

    -- What tapping it does. Kept as a kind plus a single target rather than four nullable
    -- foreign keys: a banner points at exactly one thing, and a shape that can express "points at
    -- a store AND a category" is a shape somebody will eventually populate that way.
    link_kind   varchar(16)  NOT NULL DEFAULT 'NONE',
    link_target varchar(512),

    -- Display order. Curated rather than by date: a marketing rail is arranged, not sorted.
    position    smallint     NOT NULL DEFAULT 0,

    active      boolean      NOT NULL DEFAULT true,
    starts_at   timestamptz  NOT NULL DEFAULT now(),
    -- Null runs until withdrawn, matching store_offers.
    ends_at     timestamptz,

    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_banner_link_kind CHECK (link_kind IN ('NONE', 'STORE', 'CATEGORY', 'URL')),
    CONSTRAINT chk_banner_window CHECK (ends_at IS NULL OR ends_at > starts_at),
    -- A banner that links somewhere must say where. NONE must not carry a stale target.
    CONSTRAINT chk_banner_target CHECK (
        (link_kind = 'NONE' AND link_target IS NULL)
        OR (link_kind <> 'NONE' AND link_target IS NOT NULL))
);

-- The customer rail: live banners in curated order.
CREATE INDEX idx_banners_live ON banners (position, starts_at DESC) WHERE active;

CREATE TRIGGER trg_banners_updated_at
    BEFORE UPDATE ON banners
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- ---------------------------------------------------------------------------------------------
-- Category images, and the link from a category to the vertical it represents.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE categories
    ADD COLUMN image_ref varchar(512),
    -- Which storefront vertical this category stands for on the home screen, if any.
    --
    -- This is what lets the category strip be data-driven while the store filter stays an enum.
    -- Stores carry a vertical, not a category, so filtering has to be by vertical — but the chip a
    -- customer taps can now come from a row with a name and an uploaded picture, instead of from a
    -- hard-coded enum with a Material icon.
    ADD COLUMN vertical varchar(24);

ALTER TABLE categories
    ADD CONSTRAINT chk_category_vertical CHECK (vertical IS NULL OR vertical IN (
        'RESTAURANT', 'COFFEE', 'GROCERY', 'CONVENIENCE', 'PHARMACY', 'ELECTRONICS',
        'FLOWERS_GIFTS'));

-- Only one category may represent a given vertical, or the strip would show duplicates.
CREATE UNIQUE INDEX uq_category_vertical ON categories (vertical) WHERE vertical IS NOT NULL;

-- Tag the existing roots. These were seeded in V10/V12 and already line up with the verticals; this
-- just makes the correspondence explicit so the strip has rows to render from day one.
UPDATE categories SET vertical = 'RESTAURANT'    WHERE name = 'Food';
UPDATE categories SET vertical = 'GROCERY'       WHERE name = 'Groceries';
UPDATE categories SET vertical = 'PHARMACY'      WHERE name = 'Pharmacy';
UPDATE categories SET vertical = 'COFFEE'        WHERE name = 'Coffee & Tea';
UPDATE categories SET vertical = 'CONVENIENCE'   WHERE name = 'Convenience';
UPDATE categories SET vertical = 'ELECTRONICS'   WHERE name = 'Electronics';
UPDATE categories SET vertical = 'FLOWERS_GIFTS' WHERE name = 'Flowers & Gifts';

-- Stores: the object the whole customer experience hangs off.
--
-- Until now a product carried a bare `merchant_id` (a Keycloak sub) and nothing else. That is enough
-- to answer "may this user edit this row", but it cannot answer any of the questions a storefront
-- asks: what is this shop called, is it open, what does it charge to deliver, how long will it take.
-- The catalog was product-first; a marketplace is store-first. This migration adds the missing noun
-- and re-points products at it.

CREATE TABLE stores (
    id          uuid         PRIMARY KEY,
    -- Owner. Same meaning and same enforcement as products.merchant_id: every write is checked
    -- against the caller's own sub.
    merchant_id varchar(64)  NOT NULL,
    name        varchar(160) NOT NULL,
    -- Stable, human-readable URL key. Generated from the name once and then never re-derived —
    -- renaming a shop must not break a link that has already been shared.
    slug        varchar(180) NOT NULL,
    vertical    varchar(24)  NOT NULL,
    tagline     varchar(240),
    description text,

    -- Object keys in the product-images bucket, resolved to presigned URLs on read. Nullable: a
    -- store is usable before its owner has uploaded artwork, and the clients fall back to a
    -- generated monogram tile rather than a broken image.
    logo_ref    varchar(512),
    cover_ref   varchar(512),

    -- Free-text descriptors shown as chips and used by the cuisine filter ("Lebanese", "Pizza",
    -- "Vegan"). jsonb for the same reason as products.image_refs: short, always read whole.
    tags        jsonb        NOT NULL DEFAULT '[]'::jsonb,

    -- Denormalised rating. Recomputed from reviews rather than averaged on read: a storefront reads
    -- this on every card in a long list, and an aggregate per card is the classic N+1 that makes a
    -- home screen slow.
    rating          numeric(2, 1),
    rating_count    integer        NOT NULL DEFAULT 0,

    delivery_fee    numeric(12, 2) NOT NULL DEFAULT 0,
    min_order       numeric(12, 2) NOT NULL DEFAULT 0,
    -- A range, not a point. Every delivery app quotes "25-35 min" because a single number reads as
    -- a promise, and this one is an estimate.
    eta_min_minutes integer        NOT NULL DEFAULT 20,
    eta_max_minutes integer        NOT NULL DEFAULT 40,

    -- Opening hours are stored per weekday in store_hours below, interpreted in this zone. Stored
    -- per store, not per deployment: a marketplace can span zones, and "is it open" computed in the
    -- server's zone is wrong for every store that isn't in it.
    timezone    varchar(64)  NOT NULL DEFAULT 'UTC',

    address     varchar(400),
    latitude    numeric(9, 6),
    longitude   numeric(9, 6),

    -- Lifecycle, set by the owner or an admin.
    status      varchar(16)  NOT NULL DEFAULT 'DRAFT',
    -- A separate axis from status, and deliberately so. "Busy" is a kitchen saying it is behind for
    -- the next twenty minutes; it must not require de-listing the shop, and it must not be
    -- forgotten about afterwards. Nullable timestamp = a self-expiring flag.
    busy_until  timestamptz,

    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT uq_stores_slug UNIQUE (slug),
    CONSTRAINT chk_store_status CHECK (status IN ('DRAFT', 'ACTIVE', 'SUSPENDED')),
    CONSTRAINT chk_store_vertical CHECK (vertical IN (
        'RESTAURANT', 'COFFEE', 'GROCERY', 'CONVENIENCE', 'PHARMACY', 'ELECTRONICS', 'FLOWERS_GIFTS')),
    CONSTRAINT chk_store_rating CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),
    CONSTRAINT chk_store_fees CHECK (delivery_fee >= 0 AND min_order >= 0),
    CONSTRAINT chk_store_eta CHECK (eta_min_minutes > 0 AND eta_max_minutes >= eta_min_minutes)
);

-- The Merchant Portal's "my stores".
CREATE INDEX idx_stores_merchant ON stores (merchant_id, created_at DESC);

-- The customer home screen: live stores in a vertical, best-rated first. Partial, because the home
-- screen never shows a DRAFT or SUSPENDED store.
CREATE INDEX idx_stores_live_vertical ON stores (vertical, rating DESC NULLS LAST)
    WHERE status = 'ACTIVE';

-- Store search. Schema-qualified operator class for the same reason as V10's product index: the
-- extension lives in `public` but Flyway runs with the search path set to this service's schema.
CREATE INDEX idx_stores_name_trgm ON stores USING gin (name public.gin_trgm_ops);

CREATE TRIGGER trg_stores_updated_at
    BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- Opening hours, one row per contiguous window. A separate table rather than seven columns because
-- split hours are normal (a restaurant that serves lunch and dinner but not the gap between), and
-- that shape is unrepresentable in a single opens/closes pair per day.
CREATE TABLE store_hours (
    id          uuid        PRIMARY KEY,
    store_id    uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    -- ISO-8601: 1 = Monday .. 7 = Sunday, matching java.time.DayOfWeek#getValue so no translation
    -- table is needed on either side.
    day_of_week smallint    NOT NULL,
    opens_at    time        NOT NULL,
    closes_at   time        NOT NULL,

    CONSTRAINT chk_hours_day CHECK (day_of_week BETWEEN 1 AND 7),
    -- Windows that cross midnight are split into two rows by the writer. Allowing closes_at <
    -- opens_at here would make every "is it open now" query need a special case.
    CONSTRAINT chk_hours_order CHECK (closes_at > opens_at)
);

CREATE INDEX idx_store_hours_store ON store_hours (store_id, day_of_week);


-- Favourites. Toters' "star a store to keep it at the top of your screen".
CREATE TABLE store_favorites (
    user_id    varchar(64) NOT NULL,
    store_id   uuid        NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    -- The composite key IS the idempotency: starring twice is not an error, it is a no-op.
    PRIMARY KEY (user_id, store_id)
);

-- "My favourites, most recently starred first" — the top row of the home screen.
CREATE INDEX idx_store_favorites_user ON store_favorites (user_id, created_at DESC);


-- Offers. A store-scoped promotion, or a platform-wide one when store_id is null.
CREATE TABLE store_offers (
    id           uuid           PRIMARY KEY,
    store_id     uuid           REFERENCES stores (id) ON DELETE CASCADE,
    kind         varchar(24)    NOT NULL,
    title        varchar(160)   NOT NULL,
    subtitle     varchar(240),
    -- Percentage for PERCENT_OFF, currency amount for AMOUNT_OFF, unused for FREE_DELIVERY.
    value        numeric(12, 2),
    -- Floor the basket must reach. 0 = no minimum.
    min_subtotal numeric(12, 2) NOT NULL DEFAULT 0,
    starts_at    timestamptz    NOT NULL DEFAULT now(),
    -- Null = runs until withdrawn. An offer with no end date is a real thing ("free delivery on
    -- your first order") and encoding it as a far-future date makes it look like a bug.
    ends_at      timestamptz,
    active       boolean        NOT NULL DEFAULT true,

    CONSTRAINT chk_offer_kind CHECK (kind IN ('PERCENT_OFF', 'AMOUNT_OFF', 'FREE_DELIVERY')),
    CONSTRAINT chk_offer_window CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT chk_offer_percent CHECK (
        kind <> 'PERCENT_OFF' OR (value IS NOT NULL AND value > 0 AND value <= 100)),
    CONSTRAINT chk_offer_amount CHECK (kind <> 'AMOUNT_OFF' OR (value IS NOT NULL AND value > 0))
);

CREATE INDEX idx_store_offers_live ON store_offers (store_id, starts_at DESC) WHERE active;


-- ---------------------------------------------------------------------------------------------
-- Re-point products at their store.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE products ADD COLUMN store_id uuid REFERENCES stores (id) ON DELETE RESTRICT;

-- Backfill: every merchant that already has products gets a store, and their products move into it.
-- Without this the column could not be made NOT NULL, and an existing deployment would lose its
-- catalog from the storefront the moment browsing became store-scoped.
--
-- gen_random_uuid() is available without an extension on PostgreSQL 13+.
INSERT INTO stores (id, merchant_id, name, slug, vertical, status, tagline)
SELECT gen_random_uuid(),
       p.merchant_id,
       'Store ' || left(p.merchant_id, 8),
       'store-' || left(p.merchant_id, 8),
       'RESTAURANT',
       'ACTIVE',
       'Imported from the pre-store catalog'
FROM (SELECT DISTINCT merchant_id FROM products) p;

UPDATE products p
SET store_id = s.id
FROM stores s
WHERE s.merchant_id = p.merchant_id
  AND p.store_id IS NULL;

-- Safe now that every existing row is covered. New products get their store from the service, which
-- auto-provisions one for a merchant who does not yet have any.
ALTER TABLE products ALTER COLUMN store_id SET NOT NULL;

-- The store landing page's product list, which is the single most-hit catalog query in a
-- store-first app. Partial for the same reason as V10's category index.
CREATE INDEX idx_products_store_active ON products (store_id, category_id, created_at DESC)
    WHERE status = 'ACTIVE';

-- Delivery areas, and what a shop charges to reach each one.
--
-- This task was parked as "blocked on geocoding", and that was the wrong premise. Addresses here are
-- free text and always will be: in this market a street address is a landmark and a floor, not
-- something a geocoder resolves. What every local delivery app actually does — and what customers
-- already expect — is pick their AREA from a list: Hamra, Achrafieh, Verdun.
--
-- So distance pricing is priced by area, not by metres. A shop declares which areas it will deliver
-- to and what it charges for each, and an order to an area it does not serve is refused at
-- placement rather than accepted and then abandoned. No geocoding provider, no map tiles, no
-- coordinates on an address.
--
-- Coordinates remain useful later for rider tracking and ETA, and nothing here forecloses them: a
-- zone can gain a polygon without any of the pricing below changing.
CREATE TABLE delivery_zones (
    id         uuid PRIMARY KEY,

    -- The name a customer picks from a list, so it has to read like the place they would say out
    -- loud rather than like an administrative district.
    name       varchar(120) NOT NULL,

    -- Groups areas that belong together in the picker ("Beirut", "Mount Lebanon"). Free text
    -- rather than a second table: it exists to order a dropdown, and a table would invite a
    -- hierarchy nobody asked for.
    region     varchar(120),

    -- Ordering in the picker. Two areas with the same rank fall back to name.
    sort_order int          NOT NULL DEFAULT 100,

    -- Retired rather than deleted: existing addresses reference it, and an area that stops being
    -- served should disappear from the picker without rewriting anybody's saved address.
    active     boolean      NOT NULL DEFAULT true,

    created_at timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT uq_zone_name UNIQUE (name)
);

CREATE INDEX idx_zone_picker ON delivery_zones (active, sort_order, name);

-- What one shop charges to reach one area.
--
-- Absence is meaningful: a shop with no row for an area does not deliver there. That is the whole
-- point — "we don't go that far" is the commonest delivery rule in this market and previously could
-- not be expressed at all.
CREATE TABLE store_delivery_zones (
    store_id     uuid           NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    zone_id      uuid           NOT NULL REFERENCES delivery_zones (id) ON DELETE CASCADE,

    delivery_fee numeric(12, 2) NOT NULL,

    -- A shop may want a higher basket to justify a longer run. Null means "use the shop's own
    -- minimum" rather than "no minimum", so leaving it blank keeps today's behaviour.
    min_order    numeric(12, 2),

    -- Added to both ends of the shop's ETA range. Reaching a further area takes longer, and
    -- quoting the same window for every area is how an ETA stops being believed.
    eta_extra_minutes int       NOT NULL DEFAULT 0,

    updated_at   timestamptz    NOT NULL DEFAULT now(),

    PRIMARY KEY (store_id, zone_id),

    CONSTRAINT chk_zone_fee_not_negative CHECK (delivery_fee >= 0),
    CONSTRAINT chk_zone_min_not_negative CHECK (min_order IS NULL OR min_order >= 0),
    CONSTRAINT chk_zone_eta_not_negative CHECK (eta_extra_minutes >= 0)
);

-- The storefront asks "which shops deliver to this area", which is this index.
CREATE INDEX idx_store_zones_by_zone ON store_delivery_zones (zone_id);

-- Nothing is backfilled, deliberately.
--
-- A shop with no zone rows keeps charging its flat `stores.delivery_fee` to everybody, which is
-- exactly today's behaviour. Zones are opt-in per shop: inventing coverage on a merchant's behalf
-- would either invent areas they do not serve or refuse orders they were happily taking yesterday.
COMMENT ON TABLE store_delivery_zones IS
    'Per-area delivery terms. A shop with no rows here falls back to its flat delivery fee and '
    'serves everywhere, which is the pre-zone behaviour.';

-- Cached geocoder answers.
--
-- Two reasons, and the first is not performance.
--
-- 1. The dev geocoder is OpenStreetMap Nominatim, whose usage policy is explicit that heavy users
--    must cache results and that the public endpoint allows at most one request per second. The
--    same handful of addresses — the shop's own street, the three areas it delivers to — are
--    searched over and over as merchants and customers re-open the address picker. Without a cache
--    this service would spend its entire one-request-per-second budget re-asking questions it has
--    already had answered, and would deserve to be blocked.
--
-- 2. Whatever commercial provider replaces it (Google, Mapbox) bills per request. The cache is what
--    makes that switch a line item rather than a surprise.
--
-- In the database rather than in process memory on purpose: the point is to survive a restart and
-- to be shared by every replica. An in-memory map would send the whole rate budget over the wire
-- again after each deploy, which is exactly the behaviour the policy is written to prevent.
CREATE TABLE geocode_cache (
    id         uuid         PRIMARY KEY,

    -- Cached PER PROVIDER. Nominatim's answer for a query is not Mapbox's, and a switch of provider
    -- must not serve the old vendor's results under the new one's name.
    provider   varchar(32)  NOT NULL,

    -- FORWARD (text -> candidates) or REVERSE (point -> address). Separate rather than inferred
    -- from the key's shape, because "31.05,29.98" is a perfectly legal thing to type into a search
    -- box and must not collide with the reverse lookup for that point.
    lookup     varchar(16)  NOT NULL,

    -- The normalised query for FORWARD; "lat,lng" rounded to five decimals for REVERSE. Rounding is
    -- what makes a reverse cache worth having at all: a phone's GPS never reports the same point
    -- twice, and an unrounded key would miss on every single request. Five decimals is about a
    -- metre, which is far below the accuracy of the fix that produced it.
    cache_key  varchar(512) NOT NULL,

    -- The provider's answer, already translated into this service's own shape.
    --
    -- text, not jsonb. Nothing queries inside this value — it is read whole, by key, and handed to
    -- Jackson — so jsonb would buy a validation we do not need at the cost of a mapping subtlety we
    -- do not want. Contrast stores.tags, which is jsonb because it is a value the storefront
    -- genuinely filters on.
    payload    text         NOT NULL,

    fetched_at timestamptz  NOT NULL DEFAULT now(),

    -- Kept so an operator can see whether the cache is earning its keep before anyone signs a
    -- per-request contract with a commercial provider.
    hit_count  integer      NOT NULL DEFAULT 0,

    CONSTRAINT uq_geocode_cache UNIQUE (provider, lookup, cache_key),
    CONSTRAINT chk_geocode_lookup CHECK (lookup IN ('FORWARD', 'REVERSE'))
);

-- Eviction sweeps by age. Entries are re-fetched rather than deleted on read when they go stale, so
-- this index exists for the housekeeping job, not the hot path.
CREATE INDEX idx_geocode_cache_age ON geocode_cache (fetched_at);

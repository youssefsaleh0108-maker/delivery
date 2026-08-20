-- Order Tracking tables (Section 4).

-- A local projection of who is involved in an order, built purely from order.* events off the bus.
--
-- This is what lets Order Tracking answer "may this user see this rider's position?" WITHOUT a
-- synchronous call to Order Manager on every poll from a live tracking screen. The tracking read
-- path is the highest-frequency route in the platform (Section 10); putting a cross-service HTTP
-- call in it would make Order Manager's availability a hard dependency of every customer watching
-- a map.
--
-- It is eventually consistent by construction. A ping arriving before the order event that
-- explains it is stored anyway and simply is not readable until the projection catches up.
CREATE TABLE order_participants (
    order_id    uuid        PRIMARY KEY,
    customer_id varchar(64) NOT NULL,
    merchant_id varchar(64) NOT NULL,
    rider_id    varchar(64),
    status      varchar(24) NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_participants_rider ON order_participants (rider_id)
    WHERE rider_id IS NOT NULL;

-- Raw GPS pings. High write volume by nature: every active rider, every few seconds.
--
-- Section 10 requires this to be partitioned by date and given a retention policy before it grows
-- unbounded. It is a plain table for now because Phase 2 has a handful of test riders; the
-- partitioning migration is deliberately left as a Phase 5 hardening task rather than pretended at
-- here with a single partition that nothing rotates.
CREATE TABLE tracking_events (
    id          uuid             PRIMARY KEY,
    order_id    uuid             NOT NULL,
    rider_id    varchar(64)      NOT NULL,
    lat         double precision NOT NULL,
    lng         double precision NOT NULL,
    accuracy_m  real,
    recorded_at timestamptz      NOT NULL DEFAULT now(),
    -- PostGIS geography, generated from the lat/lng the client sent.
    --
    -- Generated rather than written by the application: it keeps the geometry and the raw
    -- coordinates from ever disagreeing, and means the app layer never needs hibernate-spatial.
    -- geography (not geometry) so ST_Distance returns metres on the spheroid rather than degrees.
    --
    -- Every PostGIS name here MUST be schema-qualified with public.: the extension lives in
    -- `public`, but Flyway pins the search path to this service's own schema, so bare names fail
    -- with "type geography does not exist".
    location    public.geography(Point, 4326)
        GENERATED ALWAYS AS
            (public.ST_SetSRID(public.ST_MakePoint(lng, lat), 4326)::public.geography) STORED,
    CONSTRAINT chk_lat_range CHECK (lat BETWEEN -90 AND 90),
    CONSTRAINT chk_lng_range CHECK (lng BETWEEN -180 AND 180)
);

-- The "replay this delivery" query.
CREATE INDEX idx_tracking_order ON tracking_events (order_id, recorded_at DESC);
-- The "where has this rider been" query.
CREATE INDEX idx_tracking_rider ON tracking_events (rider_id, recorded_at DESC);
-- Geo lookups, e.g. nearest available rider. GIST is the right index type for geography, and its
-- operator class needs qualifying for the same reason as the column type above.
CREATE INDEX idx_tracking_location ON tracking_events
    USING gist (location public.gist_geography_ops);

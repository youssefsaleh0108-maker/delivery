-- Phase 5 hardening: partition tracking_events by day and give it somewhere to go when it ages.
--
-- Section 10 calls this out specifically: tracking_events is the highest-write table in the
-- platform by nature - every active rider, every few seconds - and V10 left it a plain table with a
-- note saying the partitioning belonged here rather than being faked with a single partition that
-- nothing rotates. This is that migration.
--
-- DAILY partitions, not monthly. The retention policy is expressed in days
-- (delivery.tracking.raw-ping-retention-days, 30), and monthly partitions would mean keeping up to
-- 60 days to honour a 30-day policy. Daily granularity makes "drop what is older than the policy"
-- mean exactly what it says.
--
-- There is deliberately NO default partition. A row that matches no partition would land there and
-- then permanently block creating the partition that should have covered it, which turns a missed
-- maintenance run into a problem that needs manual data movement. Without one, an insert outside
-- every partition fails loudly instead - and TrackingPartitionMaintenance keeps a week of future
-- partitions ahead of the writers, and runs at startup as well as daily, so reaching that state
-- means maintenance has been dead for a week and somebody should know.

-- ---------------------------------------------------------------------------------------------
-- The partitioned table.
--
-- Postgres requires the partition key in every unique constraint, so the primary key becomes
-- (id, recorded_at). The id alone is still unique in practice - it is a v4 UUID - but the database
-- can no longer enforce that across partitions, which is the normal cost of partitioning.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE tracking_events_partitioned (
    id          uuid             NOT NULL,
    order_id    uuid             NOT NULL,
    rider_id    varchar(64)      NOT NULL,
    lat         double precision NOT NULL,
    lng         double precision NOT NULL,
    accuracy_m  real,
    recorded_at timestamptz      NOT NULL DEFAULT now(),
    -- Same generated geography as V10, and the same rule: every PostGIS name must be
    -- public.-qualified because Flyway pins the search path to this service's schema.
    location    public.geography(Point, 4326)
        GENERATED ALWAYS AS
            (public.ST_SetSRID(public.ST_MakePoint(lng, lat), 4326)::public.geography) STORED,
    CONSTRAINT chk_lat_range CHECK (lat BETWEEN -90 AND 90),
    CONSTRAINT chk_lng_range CHECK (lng BETWEEN -180 AND 180),
    PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

-- Indexes are created further down, AFTER the old table is dropped. Two reasons, and the first is
-- not optional: index names are unique per schema, so V10's idx_tracking_order cannot be recreated
-- while the table that owns it still exists. Building them after the bulk copy is also faster than
-- maintaining them during it.

-- ---------------------------------------------------------------------------------------------
-- Cover whatever is already in the old table, plus a week ahead so writes keep working from the
-- moment this migration commits until maintenance takes over.
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    day date;
    first_day date;
    last_day date;
BEGIN
    SELECT COALESCE(MIN(recorded_at)::date, CURRENT_DATE),
           GREATEST(COALESCE(MAX(recorded_at)::date, CURRENT_DATE), CURRENT_DATE) + 7
      INTO first_day, last_day
      FROM tracking_events;

    day := first_day;
    WHILE day <= last_day LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS tracking_events_%s PARTITION OF tracking_events_partitioned '
            'FOR VALUES FROM (%L) TO (%L)',
            to_char(day, 'YYYYMMDD'), day, day + 1);
        day := day + 1;
    END LOOP;
END
$$;

INSERT INTO tracking_events_partitioned (id, order_id, rider_id, lat, lng, accuracy_m, recorded_at)
SELECT id, order_id, rider_id, lat, lng, accuracy_m, recorded_at FROM tracking_events;

DROP TABLE tracking_events;
ALTER TABLE tracking_events_partitioned RENAME TO tracking_events;

-- Declared on the parent, so Postgres creates the matching index on every partition, existing and
-- future — TrackingPartitionMaintenance never has to remember to. Names match V10's so anything
-- that referenced them still works.
CREATE INDEX idx_tracking_order ON tracking_events (order_id, recorded_at DESC);
CREATE INDEX idx_tracking_rider ON tracking_events (rider_id, recorded_at DESC);
-- GIST is the right type for geography, and its operator class needs public.-qualifying for the
-- same reason as the column type.
CREATE INDEX idx_tracking_location ON tracking_events
    USING gist (location public.gist_geography_ops);

-- ---------------------------------------------------------------------------------------------
-- The downsample. Section 10 asks for "retention/downsampling", and dropping a day of pings
-- without keeping anything would lose the ability to answer "where did this delivery actually go"
-- for any order older than the retention window - which is exactly the question a delivery dispute
-- asks, and disputes arrive late.
--
-- One row per order per day: the shape of the journey reduced to endpoints, a bounding path length
-- and a ping count. Cheap to keep indefinitely, and enough to answer a dispute without holding
-- every GPS sample forever.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE tracking_event_rollup (
    order_id      uuid        NOT NULL,
    day           date        NOT NULL,
    ping_count    integer     NOT NULL,
    first_seen_at timestamptz NOT NULL,
    last_seen_at  timestamptz NOT NULL,
    first_lat     double precision NOT NULL,
    first_lng     double precision NOT NULL,
    last_lat      double precision NOT NULL,
    last_lng      double precision NOT NULL,
    -- Straight-line metres between the first and last ping of the day. Not the driven distance;
    -- an honest summary rather than a number that looks more precise than it is.
    span_metres   double precision,
    rolled_up_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (order_id, day)
);

CREATE INDEX idx_rollup_day ON tracking_event_rollup (day);

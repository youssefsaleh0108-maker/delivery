-- Rider duty/presence, off-order location, and the route points an ETA needs (Section 7).
--
-- Three things the tracking schema could not answer before this migration:
--
--   1. "Where is this delivery going?" order_participants knew who was involved but not a single
--      coordinate, so there was nothing to measure a remaining distance against.
--   2. "Is this rider working right now?" Nothing recorded duty at all. The design's carrier and
--      backoffice consoles show an on-duty roster; there was no row behind it.
--   3. "Where is this rider?" when they hold no job. tracking_events.order_id is NOT NULL, so an
--      idle rider had nowhere to be.
--
-- Nothing added here grows per ping. That is a deliberate constraint, not a coincidence — see the
-- note on rider_presence below and TrackingPartitionMaintenance for why the one table that does
-- grow per ping is the only one that needs partitioning.

-- ---------------------------------------------------------------------------------------------
-- Route points and the carrying fleet, added to the existing participants projection.
--
-- All nullable, and every one of them stays nullable on purpose. This projection is built from
-- order.* events off the bus, and the publisher does not carry coordinates yet (see the service
-- README/report: the contract asked for is pickupLat/pickupLng/dropoffLat/dropoffLng on the order
-- snapshot). Making them NOT NULL would mean either refusing every event that lacks them — which
-- would break the authorisation projection the whole read path depends on — or inventing a
-- coordinate, which is worse. Absent stays absent and the ETA endpoint says so.
--
-- carrier_id is the delivery company that claimed the order (order.deliveryProviderId). Null for
-- the platform's own riders, exactly as it is upstream.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE order_participants
    ADD COLUMN carrier_id  uuid,
    ADD COLUMN pickup_lat  double precision,
    ADD COLUMN pickup_lng  double precision,
    ADD COLUMN dropoff_lat double precision,
    ADD COLUMN dropoff_lng double precision;

-- Range checks rather than trusting the publisher. This projection is fed by a message, and a
-- message is untrusted input like any other: a transposed lat/lng pair would otherwise put a
-- Beirut delivery in the Indian Ocean and the ETA would report it with a straight face.
ALTER TABLE order_participants
    ADD CONSTRAINT chk_participants_pickup_range
        CHECK ((pickup_lat IS NULL AND pickup_lng IS NULL)
            OR (pickup_lat BETWEEN -90 AND 90 AND pickup_lng BETWEEN -180 AND 180)),
    ADD CONSTRAINT chk_participants_dropoff_range
        CHECK ((dropoff_lat IS NULL AND dropoff_lng IS NULL)
            OR (dropoff_lat BETWEEN -90 AND 90 AND dropoff_lng BETWEEN -180 AND 180));

-- "Which orders is this fleet carrying" — the carrier console's roster joins through this.
CREATE INDEX idx_participants_carrier ON order_participants (carrier_id)
    WHERE carrier_id IS NOT NULL;

-- ---------------------------------------------------------------------------------------------
-- Who works for whom.
--
-- Needed to answer "may this caller see that rider's location?" without a synchronous call to
-- Order Manager on a read path the carrier console polls — the same argument that produced
-- order_participants in V10.
--
-- source records how the row was learned, because the two sources are not equally good:
--
--   ORDER_EVENT   inferred from an order that named both a rider and a delivery provider. It is
--                 all this service can derive today, and it is late (a rider is only discovered
--                 once they have carried something) and sticky (it never learns about leaving).
--   MEMBERSHIP    told to us directly by a carrier.member_* event. Authoritative, and does not
--                 exist yet — the contract is requested in the report.
--
-- Keeping the provenance in the row means the day the real event lands, MEMBERSHIP simply wins and
-- the inferred rows age out; without it there would be no way to tell a fact from a guess.
--
-- member_kind separates riders from office staff. A carrier's dispatcher may read the roster but
-- may not be pinged for, and conflating the two would make "which of my people are on duty"
-- include the people who sit in the office.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE carrier_membership (
    user_id     varchar(64) PRIMARY KEY,
    carrier_id  uuid        NOT NULL,
    member_kind varchar(16) NOT NULL,
    source      varchar(16) NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_member_kind CHECK (member_kind IN ('RIDER', 'STAFF')),
    CONSTRAINT chk_member_source CHECK (source IN ('ORDER_EVENT', 'MEMBERSHIP'))
);

CREATE INDEX idx_membership_carrier ON carrier_membership (carrier_id, member_kind);

-- ---------------------------------------------------------------------------------------------
-- Duty state and last known fix: exactly one row per rider, forever.
--
-- This is the durable half of presence. Redis holds the same snapshot under a TTL for the hot
-- single-rider read, but Redis is NOT the record: a flushed or restarted cache would otherwise
-- take the entire fleet off duty at once, and a rider who is out on a delivery would vanish from
-- the console that is meant to be watching them.
--
-- Note what is NOT here: a history of where an idle rider has been. An off-order ping updates this
-- one row in place, so presence costs a bounded number of rows no matter how long the fleet runs,
-- and needs no partition and no retention sweep. Keeping a breadcrumb trail of a rider who is not
-- carrying anything would be a per-ping table with no question behind it — and continuous
-- location history of a worker who is on no job is surveillance, not telemetry. If a business
-- question for it ever appears, it belongs in a partitioned table alongside tracking_events with
-- its own retention, not bolted onto this one.
--
-- duty_state is what the rider DECLARED. Whether they are effectively on duty is declared-state
-- AND a recent last_seen_at, and that is computed at read time rather than stored: a phone that
-- dies cannot write a row saying it died.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE rider_presence (
    rider_id        varchar(64) PRIMARY KEY,
    carrier_id      uuid,
    duty_state      varchar(16) NOT NULL,
    duty_changed_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz,
    last_lat        double precision,
    last_lng        double precision,
    last_accuracy_m real,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    -- Same generated PostGIS geography as tracking_events, for the same reasons: derived by the
    -- database so it can never disagree with the coordinates, geography so ST_Distance answers in
    -- metres, and every PostGIS name public.-qualified because Flyway pins the search path to this
    -- service's schema. It is what a future "nearest free rider to this pickup" query needs.
    last_location   public.geography(Point, 4326)
        GENERATED ALWAYS AS
            (public.ST_SetSRID(public.ST_MakePoint(last_lng, last_lat), 4326)::public.geography) STORED,
    CONSTRAINT chk_presence_duty_state CHECK (duty_state IN ('ON_DUTY', 'OFF_DUTY')),
    CONSTRAINT chk_presence_lat_range CHECK (last_lat IS NULL OR last_lat BETWEEN -90 AND 90),
    CONSTRAINT chk_presence_lng_range CHECK (last_lng IS NULL OR last_lng BETWEEN -180 AND 180)
);

-- The roster query: on-duty riders, most recently seen first. Partial on ON_DUTY because the
-- console asks for the working ones and off-duty riders are the overwhelming majority of the table.
CREATE INDEX idx_presence_on_duty ON rider_presence (last_seen_at DESC)
    WHERE duty_state = 'ON_DUTY';
CREATE INDEX idx_presence_carrier ON rider_presence (carrier_id, duty_state)
    WHERE carrier_id IS NOT NULL;
CREATE INDEX idx_presence_location ON rider_presence
    USING gist (last_location public.gist_geography_ops);

-- ---------------------------------------------------------------------------------------------
-- An append-only log of duty transitions.
--
-- "Was this rider on duty at 14:00 last Tuesday" is asked by payroll and by anyone investigating a
-- late delivery, and rider_presence above only ever holds the current answer. This grows per
-- transition — a handful of rows per rider per day — not per ping, which is why it is a plain
-- table with a cheap date-ranged delete rather than another partitioned one: daily partitions for
-- a few thousand rows a day would be ceremony with no payoff.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE rider_duty_events (
    id          uuid        PRIMARY KEY,
    rider_id    varchar(64) NOT NULL,
    duty_state  varchar(16) NOT NULL,
    source      varchar(16) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_duty_event_state CHECK (duty_state IN ('ON_DUTY', 'OFF_DUTY')),
    CONSTRAINT chk_duty_event_source CHECK (source IN ('RIDER', 'BACKOFFICE', 'SYSTEM'))
);

CREATE INDEX idx_duty_events_rider ON rider_duty_events (rider_id, occurred_at DESC);
-- Drives the retention sweep in TrackingPartitionMaintenance.
CREATE INDEX idx_duty_events_occurred ON rider_duty_events (occurred_at);

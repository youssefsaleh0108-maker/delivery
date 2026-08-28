-- Duty sessions: the intervals behind "hours online" (rider stat tile, console columns).
--
-- rider_duty_events already records every transition, so in principle hours-online could be
-- reconstructed by pairing ON_DUTY rows with the next OFF_DUTY row at read time. That
-- reconstruction was rejected on purpose: it has to be re-derived on every read, it falls apart the
-- moment a transition is missing (a service restart between the two writes, an expired shift that
-- never got its OFF_DUTY), and every consumer would re-implement the pairing slightly differently.
-- A session row states the interval once, at write time, and the aggregate is a plain sum.
--
-- One row per shift: OPENED when a rider goes on duty, CLOSED when they go off — or when the
-- expiry sweep gives up on a rider who went silent. In that case ended_at is the rider's
-- last_seen_at, NOT the moment the sweep noticed: the hours between the last evidence of the phone
-- and the sweep run are hours nobody can show the rider was working, and crediting them would turn
-- a forgotten "go offline" tap into paid time. See DutySessionService#expireAbandoned.
--
-- Growth is per shift — the same order of magnitude as rider_duty_events, a handful of rows per
-- rider per day — so this is a plain table swept by the same dated delete, not a partitioned one.
-- History starts at this migration: nothing is backfilled from rider_duty_events, because a log
-- with possibly-missing transitions would backfill invented shifts, and an honest empty history
-- beats a plausible fabricated one.
CREATE TABLE duty_sessions (
    id         uuid        PRIMARY KEY,
    rider_id   varchar(64) NOT NULL,
    started_at timestamptz NOT NULL,
    -- NULL while the shift is running.
    ended_at   timestamptz,
    -- Who ended it: the rider, a backoffice operator, or EXPIRED for the staleness sweep. NULL
    -- exactly while ended_at is NULL — an open session has no end to explain yet.
    end_reason varchar(16),
    CONSTRAINT chk_session_closed_consistently CHECK (
        (ended_at IS NULL AND end_reason IS NULL)
        OR (ended_at IS NOT NULL AND end_reason IS NOT NULL AND ended_at >= started_at)),
    CONSTRAINT chk_session_end_reason CHECK (
        end_reason IS NULL OR end_reason IN ('RIDER', 'BACKOFFICE', 'EXPIRED'))
);

-- At most one open session per rider, enforced where it cannot be forgotten. The service checks
-- before opening, but two concurrent "go online" taps race that check; this index makes the loser
-- fail instead of leaving two open shifts both accruing hours.
CREATE UNIQUE INDEX uq_duty_sessions_open ON duty_sessions (rider_id)
    WHERE ended_at IS NULL;

-- The aggregate query: one rider's sessions overlapping a date window.
CREATE INDEX idx_duty_sessions_rider ON duty_sessions (rider_id, started_at DESC);

-- The retention sweep in TrackingPartitionMaintenance, same shape as idx_duty_events_occurred.
CREATE INDEX idx_duty_sessions_started ON duty_sessions (started_at);

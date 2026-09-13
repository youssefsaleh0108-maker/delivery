-- When each rider belonged to each delivery company: joined_at, and left_at once they left.
--
-- Nothing in this schema could say that before. carrier_membership keeps one row per person with
-- only updated_at, and rider_presence one carrier_id — each the CURRENT inference, never a history —
-- so a company reading a rider's duty history saw every shift the rider had ever worked, including
-- for somebody else before joining and after being let go. Every carrier read of a rider's history
-- is clipped to these periods (FleetMembershipGuard.membershipWindows).
--
-- Fed only by Order Manager's carrier.member_joined / carrier.member_left events, which own the
-- fact. MembershipPeriodRecorder absorbs redelivered and out-of-order events; a leave with no join
-- on record is kept as a zero-length period, so a join that arrives after it cannot open a period
-- that never closes.

CREATE TABLE carrier_membership_periods (
    id         uuid        NOT NULL,
    rider_id   varchar(64) NOT NULL,
    carrier_id uuid        NOT NULL,
    joined_at  timestamptz NOT NULL,
    left_at    timestamptz,

    CONSTRAINT pk_carrier_membership_periods PRIMARY KEY (id),
    CONSTRAINT chk_membership_period_order CHECK (left_at IS NULL OR left_at >= joined_at)
);

-- One fleet at a time, as Order Manager enforces it: at most one open period per rider.
CREATE UNIQUE INDEX uq_membership_period_open
    ON carrier_membership_periods (rider_id)
    WHERE left_at IS NULL;

-- The same join, delivered twice, is one period.
CREATE UNIQUE INDEX uq_membership_period_join
    ON carrier_membership_periods (rider_id, carrier_id, joined_at);

-- "Whose shifts may this company read, and for when": a company's periods, by time.
CREATE INDEX idx_membership_periods_carrier
    ON carrier_membership_periods (carrier_id, joined_at);

-- Points: what a merchant and a rider actually earn, now that nobody is paid by bank transfer.
--
-- The platform runs cash on delivery. The customer hands notes to the rider, the rider hands the
-- shop's share over, and what the PLATFORM owes each party is a points balance they redeem later.
-- The transactions table still records who is owed what — that ledger is unchanged and is what a
-- future bank settlement would post from — but it is not what anybody gets paid out of today.
--
-- WHY A SEPARATE LEDGER RATHER THAN A BALANCE COLUMN. A balance you can only ever read is a number
-- nobody can explain. Every earn and every redemption is a row here, so "why is my balance 4,300"
-- is answerable by selecting them, and the balance is their sum. The same argument as the outbox:
-- the derived value is cheap to recompute and the history is not recoverable once discarded.

CREATE TABLE points_ledger (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Whose balance this moves.
    --
    -- MERCHANT is the shop. CARRIER is a delivery company. RIDER is an individual rider who is not
    -- a member of any company — the platform's own fleet — and who therefore holds their own
    -- points. A rider who works for a carrier earns into the CARRIER's balance instead, and the
    -- carrier pays them; earned_by_rider_ref below is what lets the carrier see who earned what.
    owner_kind   varchar(16)  NOT NULL,
    owner_ref    varchar(64)  NOT NULL,

    -- The rider whose delivery produced these points, when that is a different party from the
    -- owner. Null on merchant earnings and on redemptions.
    --
    -- This column is the whole reason a carrier can pay its riders: without it a carrier sees one
    -- balance and no way to attribute it, and the platform has pushed a settlement problem onto
    -- them with no data to solve it.
    earned_by_rider_ref varchar(64),

    -- The order that earned them. Null on a redemption, which is not about one order.
    order_id     uuid,

    -- Signed. Positive earns, negative holds and redemptions, so the balance is a plain SUM and
    -- there is no second column to keep consistent with this one.
    points       bigint       NOT NULL,

    reason       varchar(32)  NOT NULL,
    redemption_id uuid,
    created_at   timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_points_owner_kind CHECK (owner_kind IN ('MERCHANT', 'CARRIER', 'RIDER')),
    CONSTRAINT chk_points_reason CHECK (reason IN (
        -- A delivered order.
        'ORDER_EARNED',
        -- Points moved out of the balance when a redemption is requested, so they cannot be
        -- requested twice while the first request is still being reviewed.
        'REDEMPTION_HELD',
        -- A rejected or cancelled request gives them back.
        'REDEMPTION_RELEASED',
        -- Approved and paid. The hold becomes permanent.
        'REDEMPTION_PAID',
        -- An operator correction. Deliberately available, deliberately its own reason so it can be
        -- counted separately from anything the system did on its own.
        'ADJUSTMENT'))
);

-- One earn per order per owner. The bus is at-least-once, so order.delivered arrives twice sooner
-- or later; without this a redelivery pays the shop again. Same reasoning as the unique constraint
-- on (order_id, leg) in transactions, and for the same reason it is the most important line here.
CREATE UNIQUE INDEX uq_points_order_owner
    ON points_ledger (order_id, owner_kind, owner_ref)
    WHERE reason = 'ORDER_EARNED';

-- The balance query: every row for one owner.
CREATE INDEX idx_points_owner ON points_ledger (owner_kind, owner_ref, created_at DESC);

-- The carrier's per-rider breakdown.
CREATE INDEX idx_points_rider ON points_ledger (earned_by_rider_ref, created_at DESC)
    WHERE earned_by_rider_ref IS NOT NULL;

COMMENT ON TABLE points_ledger IS
    'Signed points movements. Balance is SUM(points) for an owner; there is no balance column.';

-- ------------------------------------------------------------------------------------------------

CREATE TABLE points_redemption (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),

    owner_kind   varchar(16)  NOT NULL,
    owner_ref    varchar(64)  NOT NULL,

    points       bigint       NOT NULL CHECK (points > 0),

    -- What those points are worth, captured WHEN THE REQUEST IS MADE rather than when it is paid.
    --
    -- The rate is a setting an administrator can change. If the amount were computed at payout, a
    -- rate change between request and approval would silently pay a different number from the one
    -- the requester saw and agreed to — which is the kind of surprise that costs trust cheaply.
    amount       numeric(12,2) NOT NULL,
    currency     varchar(3)   NOT NULL,

    status       varchar(16)  NOT NULL DEFAULT 'PENDING',

    -- Free text from the requester: where to send it, which account, who to hand it to. Not
    -- structured, because the platform does not pay anybody automatically and an operator reads
    -- this before handing money over.
    payout_note  text,

    requested_by varchar(64)  NOT NULL,
    requested_at timestamptz  NOT NULL DEFAULT now(),
    decided_by   varchar(64),
    decided_at   timestamptz,
    -- Why it was rejected, or the reference of the payment once it was made.
    decision_note text,

    CONSTRAINT chk_redemption_owner_kind CHECK (owner_kind IN ('MERCHANT', 'CARRIER', 'RIDER')),
    CONSTRAINT chk_redemption_status CHECK (status IN (
        -- Requested, points held, waiting on Backoffice.
        'PENDING',
        -- Approved but the money has not left yet. A real state: approval is a decision and
        -- payment is an errand, and collapsing them loses track of what is owed right now.
        'APPROVED',
        -- Money handed over. Terminal.
        'PAID',
        -- Refused. The held points go back.
        'REJECTED',
        -- Withdrawn by the requester before a decision. The held points go back.
        'CANCELLED'))
);

CREATE INDEX idx_redemption_owner ON points_redemption (owner_kind, owner_ref, requested_at DESC);

-- The Backoffice queue: everything still waiting on somebody, oldest first, because the oldest
-- request is the one somebody has been waiting on longest.
CREATE INDEX idx_redemption_open ON points_redemption (status, requested_at)
    WHERE status IN ('PENDING', 'APPROVED');

-- One open request per owner at a time.
--
-- Not a business rule for its own sake: with concurrent requests the hold arithmetic has to be
-- serialised somewhere, and the alternative is a balance check that two requests can both pass.
-- One at a time makes overdrawing impossible rather than unlikely.
CREATE UNIQUE INDEX uq_redemption_one_open
    ON points_redemption (owner_kind, owner_ref)
    WHERE status IN ('PENDING', 'APPROVED');

COMMENT ON TABLE points_redemption IS
    'A request to turn points into money. The platform pays these by hand; nothing here moves money.';

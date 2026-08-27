-- Rider-level money: what one rider earned, what they were tipped, and what they can cash out.
--
-- Until now the smallest party this schema could pay was a COMPANY. A catalog order carried by the
-- platform's own fleet left the whole delivery fee with the platform, and an order carried by a
-- delivery company paid the COMPANY (PROVIDER_CREDIT) with no record of which rider did the work.
-- Neither shape can answer the question the rider app asks — "what did I earn today" — and the
-- redesign puts that question, and a cash-out button, on the rider's home screen.
--
-- WHY A SEPARATE LEDGER AND NOT MORE `transactions` LEGS.
-- `transactions` is per-ORDER double entry: the legs of one order sum to exactly what the customer
-- paid, and that invariant is the reason the table can be trusted at all. Two of the things below
-- do not belong to any order total. A tip is money the customer chose to add AFTER the order was
-- priced, so adding it as a leg would make an order's legs exceed its total. A cash-out belongs to
-- no order whatsoever. Forcing either into `transactions` would break the one invariant it has, so
-- this is the same call `points_ledger` made in V45 and for the same reason.
--
-- What DOES go into `transactions` is the job earning itself, on a platform-fleet order. That fee
-- used to be kept by the platform in full; paying part of it to a rider is a real re-split of the
-- order total, so it is a RIDER_CREDIT leg and the platform's leg shrinks to match. `chk_txn_leg`
-- already permits RIDER_CREDIT (V42) — this migration adds no leg, it widens when one is written:
-- previously only a Butler errand produced one, now a delivered catalog order does too. The unique
-- constraint on (order_id, leg) is unaffected because an order is either an errand or a catalog
-- order, never both.
--
-- Signed rows and no balance column, exactly as in points_ledger: a balance nobody can explain is
-- worse than a query, and "why is my balance 41.20" has to be answerable by selecting the rows
-- that made it.

CREATE TABLE rider_ledger (
    id           uuid          PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The rider. A Keycloak subject, the same identifier the order event carries.
    rider_ref    varchar(64)   NOT NULL,

    -- Null on a cash-out, which is not about one job.
    order_id     uuid,

    entry_type   varchar(24)   NOT NULL,

    -- Signed. Positive credits the rider, negative holds and pays out, so the balance is a plain
    -- SUM and there is no second column that can disagree with this one.
    amount       numeric(12,2) NOT NULL,
    currency     varchar(3)    NOT NULL,

    -- WHO OWES THIS, and the single most important column in the table.
    --
    -- PLATFORM  the platform holds the money and will hand it over on a cash-out. Counted in the
    --           balance.
    -- CARRIER   the rider is employed by a delivery company. The platform already paid that company
    --           for the job (PROVIDER_CREDIT) and what the company passes on is the company's
    --           employment contract, which the platform has never been shown. The row exists so the
    --           rider's own app can show the work they did; the platform must NOT pay it, because
    --           paying it would pay for the same delivery twice.
    -- IN_HAND   the rider is already holding the notes — a cash tip handed over at the door. Shown
    --           in the statement because the rider earned it, excluded from the balance because
    --           paying it again would pay it twice.
    --
    -- The balance is therefore SUM(amount) WHERE payable_by = 'PLATFORM' and nothing else.
    payable_by   varchar(16)   NOT NULL,

    -- Which fleet the rider was on for this job. Kept per ROW rather than looked up per rider: a
    -- rider can move between the platform's fleet and a company's, and a statement that re-reads
    -- today's employer would silently restate what they were owed for work done last month.
    fleet        varchar(16)   NOT NULL,

    -- The delivery company, when there was one. Null on the platform's own fleet.
    carrier_ref  varchar(64),

    -- WHO PAID FOR THE ORDER, carried on the job earning only.
    --
    -- Not decoration and not a duplicate of Order Manager's copy: it is the only fact this service
    -- holds that can prove the person adding a tip is the person the rider delivered to. Without
    -- it the tip endpoint would authorise on role alone, and any customer could tip any order —
    -- which inflates another rider's figures today and would charge the wrong card the moment
    -- online tips are real. Null on rows that are not a job earning.
    customer_ref varchar(64),

    -- The cash-out a hold, release or payment belongs to. Null on an earning.
    cash_out_id  uuid,

    -- WHEN THE WORK HAPPENED, which is not when the row was written.
    --
    -- The bus is at-least-once and can also be slow: an event delivered an hour late must land in
    -- the day it was earned, or a rider's Monday total changes on Tuesday. Every per-day and
    -- per-week figure buckets on this column; created_at is only ever the audit fact.
    earned_at    timestamptz   NOT NULL DEFAULT now(),
    created_at   timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT chk_rider_ledger_type CHECK (entry_type IN (
        -- The rider's share of one delivered job.
        'JOB_EARNING',
        -- A customer tip on a delivered job. Never commissioned; see the note below.
        'TIP',
        -- Money the rider fronted on a Butler errand, handed back. Not earnings — they are square,
        -- not better off — which is why it is its own type and reported separately.
        'REIMBURSEMENT',
        -- Taken out of the balance the moment a cash-out is requested, so it cannot be requested
        -- twice while the first request is still being decided.
        'CASHOUT_HELD',
        -- A rejected cash-out gives it back.
        'CASHOUT_RELEASED',
        -- Paid. A zero-amount row: the balance already fell when the hold was written, and taking
        -- it again would charge the rider twice for one payout.
        'CASHOUT_PAID',
        -- An operator correction. Deliberately available, deliberately its own type so it can be
        -- counted apart from anything the system did on its own.
        'ADJUSTMENT')),

    CONSTRAINT chk_rider_ledger_payable CHECK (payable_by IN ('PLATFORM', 'CARRIER', 'IN_HAND')),
    CONSTRAINT chk_rider_ledger_fleet CHECK (fleet IN ('PLATFORM', 'CARRIER'))
);

-- THE IDEMPOTENCY GUARANTEE, enforced by the database rather than by a check-then-act in code.
--
-- `order.delivered` arrives at least once, so it arrives twice sooner or later; without this a
-- redelivery pays the rider a second time for one job. Same reasoning as uq_txn_order_leg in V40
-- and uq_points_order_owner in V45, and for the same reason it is the most important line here.
--
-- Keyed on the TYPE as well as the order because one job can legitimately produce a job earning, a
-- reimbursement and a tip — three rows, one order, and each of them at most once.
CREATE UNIQUE INDEX uq_rider_ledger_order_entry
    ON rider_ledger (order_id, rider_ref, entry_type)
    WHERE order_id IS NOT NULL;

-- The statement queries: one rider's rows over a window, newest first.
CREATE INDEX idx_rider_ledger_rider ON rider_ledger (rider_ref, earned_at DESC);

-- The carrier's view of who did what, for the company that has to pay its own riders.
CREATE INDEX idx_rider_ledger_carrier ON rider_ledger (carrier_ref, earned_at DESC)
    WHERE carrier_ref IS NOT NULL;

COMMENT ON TABLE rider_ledger IS
    'Signed rider money movements. Balance is SUM(amount) WHERE payable_by = ''PLATFORM''; there is '
    'no balance column. Tips are recorded here and never commissioned.';

COMMENT ON COLUMN rider_ledger.payable_by IS
    'PLATFORM counts toward the cash-out balance. CARRIER is the company''s debt, shown but never '
    'paid by the platform. IN_HAND is a cash tip the rider already holds.';

-- ------------------------------------------------------------------------------------------------

-- A rider asking for their balance in money.
--
-- REQUESTED -> PAID or REJECTED, and nothing else. Deliberately shorter than the merchant
-- redemption machine in V45, which has a separate APPROVED state: a redemption is reviewed by a
-- human before anybody is paid, whereas the rider app's cash-out button promises the rider their
-- own already-earned money and an extra state on that path is a queue for no purpose.
CREATE TABLE rider_cash_out (
    id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),

    rider_ref     varchar(64)   NOT NULL,

    amount        numeric(12,2) NOT NULL CHECK (amount > 0),
    currency      varchar(3)    NOT NULL,

    status        varchar(16)   NOT NULL DEFAULT 'REQUESTED',

    -- Free text from the rider: which wallet, which account, who to hand it to. Not structured,
    -- because nothing in this platform pays anybody automatically — an operator or a payout
    -- provider reads this before money moves.
    --
    -- Never a bank account number: those live on the rider's Keycloak profile, are read by the
    -- payout provider at the moment of payment, and are deliberately not copied here where a
    -- statement query would return them.
    payout_note   text,

    requested_at  timestamptz   NOT NULL DEFAULT now(),
    decided_by    varchar(64),
    decided_at    timestamptz,
    -- Why it was refused, or the reference of the payment once it was made.
    decision_note text,
    -- What the payout provider called it. The number quoted in a dispute.
    payment_ref   varchar(64),
    -- Which provider paid it, so a row can never be mistaken for a real payment when it was the
    -- dev path that "paid" it.
    paid_via      varchar(32),

    CONSTRAINT chk_cash_out_status CHECK (status IN ('REQUESTED', 'PAID', 'REJECTED'))
);

-- ONE OPEN REQUEST PER RIDER, and this is how a cash-out is made safe under concurrency.
--
-- The overdraw check is a read of the balance followed by a write of the hold, and two concurrent
-- requests can both pass that read — the classic check-then-act. Serialising the requests
-- themselves closes it: the second insert blocks on this index until the first commits and then
-- fails outright, so it never reaches the point of writing a second hold. Making overdrawing
-- IMPOSSIBLE beats making it unlikely, and it needs no advisory lock, no SELECT FOR UPDATE on a
-- balance that does not exist as a row, and no serializable isolation on the whole service.
--
-- Same shape as uq_redemption_one_open in V45. PAID and REJECTED are both terminal, so a rider who
-- has been paid can immediately ask again.
CREATE UNIQUE INDEX uq_cash_out_one_open
    ON rider_cash_out (rider_ref)
    WHERE status = 'REQUESTED';

-- The rider's own history, and the operator's queue.
CREATE INDEX idx_cash_out_rider ON rider_cash_out (rider_ref, requested_at DESC);
CREATE INDEX idx_cash_out_open ON rider_cash_out (requested_at) WHERE status = 'REQUESTED';

COMMENT ON TABLE rider_cash_out IS
    'A rider asking for their balance in money. REQUESTED -> PAID | REJECTED. The unique partial '
    'index on rider_ref is what makes two simultaneous requests impossible.';

-- A delivery company's payroll for the riders it employs.
--
-- THE LINE THIS MUST NOT CROSS. A carrier rider's pay is the company's employment contract, which the
-- platform has never been shown (rider_ledger.payable_by = 'CARRIER': "shown and never paid"). This
-- is a tool the company keeps its own payroll in, and nothing here is platform money: no table below
-- is read by a statement, a balance, a cash-out or a bank posting, and nothing here writes a
-- `transactions` leg or a `rider_ledger` row. A payslip marked paid records that the COMPANY paid
-- its rider, outside this system, the way ManualPayoutProvider records a platform cash-out.
--
-- The one place payroll touches the platform's books is deliberate and goes through the existing
-- door: cash a rider still holds for the company, kept out of their pay, is a hand-over of custody
-- (CashFloatService.handOver), recorded as a TRANSFERRED row with method PAYROLL_DEDUCTION. It moves
-- custody from the rider to the company and posts nothing, exactly like a hand-over at the hub.
--
-- MONEY SHAPE. Every amount is numeric(12,2) and every rule that makes a payslip add up is a CHECK,
-- so a payslip whose parts do not make its total cannot be stored however it was computed. A run is
-- DRAFT (recomputed freely), then APPROVED (its figures frozen: corrections are adjustments carried
-- into a later run), then PAID (every payslip due has a recorded payment).

-- --------------------------------------------------------------------------------------------
-- 1. The hand-over method payroll records.
--
-- Only on a TRANSFERRED row: a payroll deduction is a rider's cash kept against their pay, never a
-- payment reaching the platform, and a remittance saying otherwise would book takings nobody banked.

ALTER TABLE cash_float
    DROP CONSTRAINT chk_float_method;

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_method
        CHECK (method IS NULL OR method IN ('CASH', 'BANK_DEPOSIT', 'WALLET', 'PAYROLL_DEDUCTION'));

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_payroll_method
        CHECK (method IS NULL OR method <> 'PAYROLL_DEDUCTION' OR entry_kind = 'TRANSFERRED');

-- --------------------------------------------------------------------------------------------
-- 2. Pay policies: one company's pay rules, as immutable versions.
--
-- A new version is a new row, never an edit, so every run can name the exact rules it was computed
-- with and "what were we paying in March" is a select. A version takes effect on the first day of a
-- pay period — never mid-period — so a period is always paid under one set of rules and a draft
-- recomputed tomorrow gives today's answer. The 16th only exists in the semi-monthly calendar; a
-- change of calendar can therefore only start on the 1st, the one day both calendars start a period.
--
-- The owner has not decided any of these numbers, so none is hard-coded anywhere else:
--   per_delivery_rate    no default: the company types it (0 for a fleet paid by the hour)
--   hourly_rate          null = no hourly base; paid on app-recorded duty time
--   pay_manual_hours     true: hours the office typed are paid, and shown apart from recorded ones
--   overtime_multiplier  1.00
--   late/absence         0.00 each: no deduction until the company sets one

CREATE TABLE carrier_pay_policy (
    id                   uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The company: Order Manager's provider id, resolved from the staff member's token.
    carrier_ref          varchar(64)   NOT NULL,
    effective_from       date          NOT NULL,
    pay_cycle            varchar(16)   NOT NULL,
    currency             varchar(3)    NOT NULL,
    per_delivery_rate    numeric(12,2) NOT NULL,
    hourly_rate          numeric(12,2),
    pay_manual_hours     boolean       NOT NULL,
    overtime_multiplier  numeric(4,2)  NOT NULL,
    -- Per unexcused late day, and per unexcused absence, as order-tracking judges them.
    late_deduction       numeric(12,2) NOT NULL,
    absence_deduction    numeric(12,2) NOT NULL,
    -- A Keycloak subject, never a typed name.
    created_by           varchar(64)   NOT NULL,
    created_at           timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT chk_pay_policy_cycle
        CHECK (pay_cycle IN ('SEMI_MONTHLY', 'MONTHLY')),
    CONSTRAINT chk_pay_policy_start
        CHECK (EXTRACT(DAY FROM effective_from) = 1
            OR (pay_cycle = 'SEMI_MONTHLY' AND EXTRACT(DAY FROM effective_from) = 16)),
    CONSTRAINT chk_pay_policy_amounts
        CHECK (per_delivery_rate >= 0
            AND (hourly_rate IS NULL OR hourly_rate >= 0)
            AND late_deduction >= 0
            AND absence_deduction >= 0),
    CONSTRAINT chk_pay_policy_overtime
        CHECK (overtime_multiplier >= 1 AND overtime_multiplier <= 5)
);

CREATE INDEX idx_pay_policy_carrier
    ON carrier_pay_policy (carrier_ref, effective_from DESC, created_at DESC);

-- --------------------------------------------------------------------------------------------
-- 3. Pay runs: one per company per pay period.
--
-- Periods are calendar-aligned (1-15 and 16-end, or the whole month), so any two periods of one
-- company that overlap share a first or a last day — which is why two plain unique keys are enough
-- to make paying the same day twice impossible, even across a change of calendar.

CREATE TABLE carrier_pay_run (
    id               uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    carrier_ref      varchar(64)  NOT NULL,
    -- Inclusive dates in the payroll zone, the same calendar order-tracking judges attendance in.
    period_from      date         NOT NULL,
    period_to        date         NOT NULL,
    status           varchar(16)  NOT NULL,
    -- The exact rules the figures were computed with. A later version never changes this run.
    policy_id        uuid         NOT NULL REFERENCES carrier_pay_policy (id),
    currency         varchar(3)   NOT NULL,
    -- Whether attendance hours are in the figures: not needed by the policy, included, or asked
    -- for and unavailable — in which case the run says so and approving it has to acknowledge it.
    attendance       varchar(16)  NOT NULL,
    attendance_note  varchar(200),
    -- When the hours in carrier_pay_attendance were read, or their read was tried. Attendance for a
    -- period keeps changing after it ends, so the page says which moment the hours are from.
    attendance_at    timestamptz,
    -- Bumped each time a draft is recomputed. Approval names the revision the approver looked at.
    revision         integer      NOT NULL,
    computed_at      timestamptz  NOT NULL,
    created_by       varchar(64)  NOT NULL,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    approved_by      varchar(64),
    approved_at      timestamptz,
    paid_at          timestamptz,

    CONSTRAINT uq_pay_run_from UNIQUE (carrier_ref, period_from),
    CONSTRAINT uq_pay_run_to UNIQUE (carrier_ref, period_to),
    -- At most 31 days: the longest window the attendance contract answers in one read.
    CONSTRAINT chk_pay_run_period
        CHECK (period_to >= period_from AND period_to - period_from <= 30),
    CONSTRAINT chk_pay_run_status
        CHECK (status IN ('DRAFT', 'APPROVED', 'PAID')),
    CONSTRAINT chk_pay_run_attendance
        CHECK (attendance IN ('NOT_NEEDED', 'INCLUDED', 'UNAVAILABLE')
            AND (attendance <> 'INCLUDED' OR attendance_at IS NOT NULL)),
    CONSTRAINT chk_pay_run_approved
        CHECK (status = 'DRAFT' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT chk_pay_run_paid
        CHECK (status <> 'PAID' OR paid_at IS NOT NULL)
);

-- --------------------------------------------------------------------------------------------
-- 4. Payslips: one rider's figures in one run.

CREATE TABLE carrier_payslip (
    id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id            uuid          NOT NULL REFERENCES carrier_pay_run (id),
    rider_ref         varchar(64)   NOT NULL,

    -- The facts the figures came from. Deliveries are the rider's JOB_EARNING rows for this company
    -- in the period. The attendance facts are null when no attendance was read for this rider —
    -- "we were not told" is not "zero hours".
    deliveries        integer       NOT NULL,
    worked_seconds    bigint,
    manual_seconds    bigint,
    overtime_seconds  bigint,
    lates             integer,
    absences          integer,

    base_pay          numeric(12,2) NOT NULL,
    delivery_pay      numeric(12,2) NOT NULL,
    bonuses           numeric(12,2) NOT NULL,
    deductions        numeric(12,2) NOT NULL,
    gross             numeric(12,2) NOT NULL,
    -- May be negative: deductions the company set can exceed pay. Nothing is then due, and the
    -- figure says what the rider owes the company; it is never silently clamped to zero.
    net               numeric(12,2) NOT NULL,
    -- Informational. A tip is the rider's own money (paid by the platform, or in hand), never the
    -- company's to pay, so it is in neither gross nor net.
    tips              numeric(12,2) NOT NULL,
    -- What the rider held for the company when computed, and the part kept out of this pay. All of
    -- it or none: a hand-over clears a rider's whole bag or nothing, so cash is only netted when the
    -- pay can absorb all of it. Otherwise the rider keeps chasing it at the hub, where it still shows.
    cash_held         numeric(12,2) NOT NULL,
    cash_netted       numeric(12,2) NOT NULL,
    -- The TRANSFERRED cash_float row that netted it, once approved.
    handover_id       uuid,

    status            varchar(16)   NOT NULL,
    paid_method       varchar(24),
    paid_reference    varchar(120),
    paid_by           varchar(64),
    paid_at           timestamptz,
    failure_reason    varchar(500),
    failed_by         varchar(64),
    failed_at         timestamptz,

    CONSTRAINT uq_payslip_rider UNIQUE (run_id, rider_ref),
    CONSTRAINT chk_payslip_status
        CHECK (status IN ('DRAFT', 'DUE', 'NOTHING_DUE', 'PAID', 'FAILED')),
    CONSTRAINT chk_payslip_gross
        CHECK (gross = base_pay + delivery_pay + bonuses),
    CONSTRAINT chk_payslip_net
        CHECK (net = gross - deductions),
    CONSTRAINT chk_payslip_parts
        CHECK (deliveries >= 0 AND base_pay >= 0 AND delivery_pay >= 0 AND bonuses >= 0
            AND deductions >= 0 AND tips >= 0 AND cash_held >= 0),
    CONSTRAINT chk_payslip_cash
        CHECK ((cash_netted = 0 OR cash_netted = cash_held) AND deductions >= cash_netted),
    -- Past the draft, netted cash always names the hand-over that took it.
    CONSTRAINT chk_payslip_handover
        CHECK ((handover_id IS NULL OR cash_netted > 0)
            AND (status = 'DRAFT' OR cash_netted = 0 OR handover_id IS NOT NULL)),
    CONSTRAINT chk_payslip_due
        CHECK (status NOT IN ('DUE', 'PAID', 'FAILED') OR net > 0),
    CONSTRAINT chk_payslip_paid
        CHECK (status <> 'PAID'
            OR (paid_by IS NOT NULL AND paid_at IS NOT NULL AND paid_method IS NOT NULL)),
    CONSTRAINT chk_payslip_paid_method
        CHECK (paid_method IS NULL OR paid_method IN ('CASH', 'BANK_DEPOSIT', 'WALLET')),
    CONSTRAINT chk_payslip_failed
        CHECK (status <> 'FAILED' OR (failure_reason IS NOT NULL AND failed_by IS NOT NULL))
);

CREATE INDEX idx_payslip_rider ON carrier_payslip (rider_ref);

-- --------------------------------------------------------------------------------------------
-- 5. The hours a run was computed with.
--
-- Attendance for a period is not final when the period ends: a night shift's 00:10 arrival, a
-- session still open, or an office entry made weeks later all change it. So a draft copies the
-- totals it used for every rider order-tracking listed — riders with no pay yet among them, because
-- a late delivery can put them on a payslip — and only an explicit recompute of a draft reads them
-- again. Editing a draft's lines and approving it use this copy, never a live read, so an approved
-- run's hours are the hours its approver saw.

CREATE TABLE carrier_pay_attendance (
    id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id            uuid         NOT NULL REFERENCES carrier_pay_run (id),
    rider_ref         varchar(64)  NOT NULL,
    worked_seconds    bigint       NOT NULL,
    manual_seconds    bigint       NOT NULL,
    overtime_seconds  bigint       NOT NULL,
    lates             integer      NOT NULL,
    absences          integer      NOT NULL,

    CONSTRAINT uq_pay_attendance_rider UNIQUE (run_id, rider_ref),
    CONSTRAINT chk_pay_attendance_facts
        CHECK (worked_seconds >= 0 AND manual_seconds >= 0 AND overtime_seconds >= 0
            AND lates >= 0 AND absences >= 0)
);

-- --------------------------------------------------------------------------------------------
-- 6. Corrections to an approved run.
--
-- An approved run is never edited. A correction is recorded against it and paid in the rider's
-- next run, where it appears as its own line; applied_run_id is set once, when that run is approved.

CREATE TABLE carrier_pay_adjustment (
    id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    carrier_ref      varchar(64)   NOT NULL,
    corrects_run_id  uuid          NOT NULL REFERENCES carrier_pay_run (id),
    rider_ref        varchar(64)   NOT NULL,
    kind             varchar(16)   NOT NULL,
    amount           numeric(12,2) NOT NULL,
    reason           varchar(500)  NOT NULL,
    created_by       varchar(64)   NOT NULL,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    applied_run_id   uuid          REFERENCES carrier_pay_run (id),
    applied_at       timestamptz,

    CONSTRAINT chk_pay_adjustment_kind CHECK (kind IN ('BONUS', 'DEDUCTION')),
    CONSTRAINT chk_pay_adjustment_amount CHECK (amount > 0),
    CONSTRAINT chk_pay_adjustment_applied
        CHECK ((applied_run_id IS NULL) = (applied_at IS NULL)
            AND (applied_run_id IS NULL OR applied_run_id <> corrects_run_id))
);

CREATE INDEX idx_pay_adjustment_pending
    ON carrier_pay_adjustment (carrier_ref, rider_ref)
    WHERE applied_run_id IS NULL;

-- --------------------------------------------------------------------------------------------
-- 7. Payslip lines: how each payslip's figures break down.
--
-- COMPUTED lines are regenerated whenever a draft is recomputed. MANUAL lines are the company's named
-- bonuses and deductions on a draft; taking one off marks it removed rather than deleting it.
-- ADJUSTMENT lines carry a correction from an earlier run. Amounts are never negative: the kind
-- decides which side of the payslip a line is on.

CREATE TABLE carrier_pay_line (
    id             uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id         uuid          NOT NULL REFERENCES carrier_pay_run (id),
    rider_ref      varchar(64)   NOT NULL,
    kind           varchar(24)   NOT NULL,
    source         varchar(16)   NOT NULL,
    label          varchar(500),
    -- Deliveries, hours or days; and the rate applied. Display: the amount is what counts.
    quantity       numeric(14,4),
    rate           numeric(14,4),
    amount         numeric(12,2) NOT NULL,
    adjustment_id  uuid          REFERENCES carrier_pay_adjustment (id),
    created_by     varchar(64),
    created_at     timestamptz   NOT NULL DEFAULT now(),
    removed_by     varchar(64),
    removed_at     timestamptz,

    CONSTRAINT chk_pay_line_kind
        CHECK (kind IN ('DELIVERIES', 'HOURS', 'OVERTIME', 'MANUAL_HOURS', 'LATE_DEDUCTION',
                        'ABSENCE_DEDUCTION', 'CASH_HELD', 'BONUS', 'DEDUCTION')),
    CONSTRAINT chk_pay_line_source
        CHECK (source IN ('COMPUTED', 'MANUAL', 'ADJUSTMENT')),
    CONSTRAINT chk_pay_line_amount CHECK (amount >= 0),
    CONSTRAINT chk_pay_line_named
        CHECK ((source = 'COMPUTED' AND kind NOT IN ('BONUS', 'DEDUCTION'))
            OR (source <> 'COMPUTED' AND kind IN ('BONUS', 'DEDUCTION') AND label IS NOT NULL
                AND amount > 0 AND created_by IS NOT NULL)),
    CONSTRAINT chk_pay_line_adjustment
        CHECK ((source = 'ADJUSTMENT') = (adjustment_id IS NOT NULL)),
    CONSTRAINT chk_pay_line_removed
        CHECK (removed_at IS NULL OR (source = 'MANUAL' AND removed_by IS NOT NULL))
);

CREATE INDEX idx_pay_line_run ON carrier_pay_line (run_id, rider_ref);

-- --------------------------------------------------------------------------------------------
-- 8. The audit trail: who did what to a company's payroll, and when.
--
-- run_id is deliberately not a foreign key: a discarded draft is deleted, and what was done to it
-- before it went stays answerable.

CREATE TABLE carrier_payroll_event (
    id           uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    carrier_ref  varchar(64)   NOT NULL,
    run_id       uuid,
    rider_ref    varchar(64),
    action       varchar(32)   NOT NULL,
    actor        varchar(64)   NOT NULL,
    detail       varchar(1000),
    occurred_at  timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_payroll_event_run ON carrier_payroll_event (run_id, occurred_at DESC);
CREATE INDEX idx_payroll_event_carrier ON carrier_payroll_event (carrier_ref, occurred_at DESC);

-- ---------------------------------------------------------------------------------------------
-- Shift schedules and attendance: what a rider was EXPECTED to work, set against what V13's duty
-- sessions show they DID work.
--
-- Until this migration the platform could say how long a rider was on duty and nothing about
-- whether that was the right time to be on duty. A delivery company that runs its riders on fixed
-- shifts (the owner's decision, 2026-09) needs three more facts: which shift a rider was on for a
-- given day, whether they arrived late or not at all, and the corrections an office makes by hand
-- ("sick", "phone died, was here"). Those are the three tables below.
--
-- The rule that shapes all three: duty_sessions stay evidence-only. Nothing here edits a session,
-- and a manual entry is its own row that is shown BESIDE the evidence, never folded into it — a
-- dispatcher typing "present 08:00-18:00" is a claim somebody made, and payroll has to be able to
-- tell it from a phone that was on the road.
--
-- A rider with no assignment is a freelancer: they choose when to go on duty, and nothing derived
-- from these tables may ever call them late or absent. That is enforced in AttendanceService, and
-- it is why there is no "default shift" row anywhere.
-- ---------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------
-- A named shift a delivery company runs, e.g. "Beirut Central Day, 08:00-18:00, Mon-Fri".
--
-- Times are wall-clock times in the platform's day zone (delivery.tracking.duty-session.day-zone,
-- Asia/Beirut), not instants: "08:00" means 08:00 in Beirut in July (05:00Z) and in January
-- (06:00Z) alike, and the service turns it into an instant per day through the zone's own rules.
-- An end_time at or before start_time is an overnight shift that ends the next morning; the shift
-- belongs to the day it STARTS on.
--
-- The hours are deliberately immutable. A template that could be edited would silently re-judge
-- every past day worked against it — last month's "on time" turning into "late" after the pay run
-- that relied on it. Changing the hours means a new template and moving riders onto it, so each
-- past day keeps the shift it was actually worked against. Retiring a template is archived_at,
-- never a delete, for the same reason: history still points at it.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE shift_templates (
    id                 uuid        PRIMARY KEY,
    -- The delivery company that runs the shift. Always the caller's own fleet, resolved from
    -- their token (CarrierScopeResolver), never taken from a request.
    carrier_id         uuid        NOT NULL,
    name               varchar(80) NOT NULL,
    start_time         time        NOT NULL,
    end_time           time        NOT NULL,
    -- ISO weekdays as bits: Monday = 1, Tuesday = 2, Wednesday = 4 ... Sunday = 64.
    days_mask          smallint    NOT NULL,
    -- How late a first clock-in may be before the day reads LATE. A company's call, bounded so a
    -- typo cannot turn "late" into a word that never applies.
    late_grace_minutes smallint    NOT NULL DEFAULT 10,
    archived_at        timestamptz,
    created_by         varchar(64) NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_shift_name CHECK (length(btrim(name)) > 0),
    CONSTRAINT chk_shift_days CHECK (days_mask BETWEEN 1 AND 127),
    CONSTRAINT chk_shift_grace CHECK (late_grace_minutes BETWEEN 0 AND 120),
    -- A zero-length shift is not a shift. (Equal times cannot mean "24 hours" either: nobody is
    -- scheduled round the clock, and allowing it would make every day's window ambiguous.)
    CONSTRAINT chk_shift_not_empty CHECK (start_time <> end_time)
);

CREATE INDEX idx_shift_templates_carrier ON shift_templates (carrier_id, created_at);

-- ---------------------------------------------------------------------------------------------
-- Which shift a rider works, and from when.
--
-- A history, not a pointer. Moving a rider to a new shift closes the old row the day before the
-- new one starts, so every past day is judged against the shift that applied on that day. Rows
-- are never backdated (the service refuses an effective_from before today): a schedule set on
-- the 15th must not reach back and mark the 1st to the 14th absent.
--
-- carrier_id is on the row, not only on the template, so that a rider who changes company does
-- not carry the old company's schedule with them: attendance reads assignments for the fleet that
-- is asking, and a former employer's rows simply never match.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE rider_shift_assignments (
    id             uuid        PRIMARY KEY,
    rider_id       varchar(64) NOT NULL,
    carrier_id     uuid        NOT NULL,
    template_id    uuid        NOT NULL REFERENCES shift_templates (id),
    -- Inclusive dates in the day zone.
    effective_from date        NOT NULL,
    effective_to   date,
    created_by     varchar(64) NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_assignment_range CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- At most one open-ended assignment per rider per fleet, where it cannot be forgotten. Two
-- concurrent "assign" clicks race the service's close-then-open; this makes the loser fail
-- instead of leaving a rider on two shifts at once.
CREATE UNIQUE INDEX uq_assignment_open ON rider_shift_assignments (rider_id, carrier_id)
    WHERE effective_to IS NULL;

-- The attendance read: one rider's assignments in one fleet over a month.
CREATE INDEX idx_assignment_rider ON rider_shift_assignments (rider_id, carrier_id, effective_from);

-- "Who is still on this shift?" — asked before a template may be archived.
CREATE INDEX idx_assignment_template ON rider_shift_assignments (template_id);

-- ---------------------------------------------------------------------------------------------
-- A correction the office records by hand: the Manual Attendance Log.
--
-- Append-only. Replacing or removing an entry stamps revoked_at/revoked_by on the old row and, for
-- a replacement, inserts a new one — so "who marked Tuesday as sick, and what did it say before"
-- is always answerable, which is the least a record that changes somebody's pay owes them.
--
-- status is what the office asserts about the day:
--   PRESENT         worked, though the duty evidence does not show it (a dead phone). May carry
--                   clock_in/clock_out; those hours are reported as MANUAL, never as evidence.
--   LATE_EXCUSED    arrived late with a reason the company accepts; not counted as a late.
--   ABSENT_EXCUSED  did not work, excused.
--   SICK, LEAVE     did not work, for that reason.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE attendance_entries (
    id          uuid         PRIMARY KEY,
    rider_id    varchar(64)  NOT NULL,
    carrier_id  uuid         NOT NULL,
    work_date   date         NOT NULL,
    status      varchar(16)  NOT NULL,
    -- Wall-clock times in the day zone. A clock_out at or before clock_in ends the next morning,
    -- as with an overnight shift.
    clock_in    time,
    clock_out   time,
    note        varchar(500),
    recorded_by varchar(64)  NOT NULL,
    recorded_at timestamptz  NOT NULL DEFAULT now(),
    revoked_by  varchar(64),
    revoked_at  timestamptz,
    CONSTRAINT chk_entry_status CHECK (
        status IN ('PRESENT', 'LATE_EXCUSED', 'ABSENT_EXCUSED', 'SICK', 'LEAVE')),
    -- Times come as a pair or not at all, only on a PRESENT entry, and never as a zero-length day.
    CONSTRAINT chk_entry_times CHECK (
        (clock_in IS NULL AND clock_out IS NULL)
        OR (status = 'PRESENT' AND clock_in IS NOT NULL AND clock_out IS NOT NULL
            AND clock_in <> clock_out)),
    CONSTRAINT chk_entry_revoked CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

-- One live entry per rider, fleet and day. Revoked rows are history and may repeat.
CREATE UNIQUE INDEX uq_attendance_entry_live ON attendance_entries (rider_id, carrier_id, work_date)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_attendance_entries_rider ON attendance_entries (rider_id, carrier_id, work_date);

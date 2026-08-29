-- Every statement the platform has ever sent, and to which address.
--
-- Two jobs, and the second is the reason this is a table rather than a log line.
--
-- 1. `lastSentAt` on the counterparties listing. An operator working through a month-end list needs
--    to see which shops have already been told, and a screen that cannot say that is a screen where
--    somebody is emailed twice and somebody else never.
--
-- 2. Refusing an accidental re-send. Sending the same period twice is not merely noise: a merchant
--    who receives August twice reads the second copy as a second amount owed, and the support
--    conversation that follows costs more than the send. So a repeat of the same
--    (kind, ref, from, to) is refused unless it is asked for explicitly.
--
-- NOT a unique constraint on that tuple, and that is deliberate. A genuine re-send is a real thing —
-- the first one bounced, the address was wrong, the figures were restated — and a constraint would
-- make the legitimate case impossible in order to prevent the careless one. The refusal belongs in
-- the endpoint, where it can be overridden by somebody who means it; the history stays complete.
CREATE TABLE statement_dispatch (
    id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),

    -- WHO it was about. The same pair as transactions.counterparty_*, and for the same reason: an
    -- email address is not an identity either, and the address on file changes.
    counterparty_kind varchar(16) NOT NULL,
    counterparty_ref  varchar(64) NOT NULL,

    -- WHICH PERIOD, as the inclusive dates the caller asked for rather than as instants. The range
    -- is a calendar question the operator asked in calendar terms, and storing the resolved instants
    -- would make "did we send August" unanswerable after a timezone change.
    period_from   date          NOT NULL,
    period_to     date          NOT NULL,

    -- WHERE it went. Recorded even though it can be re-derived, because it cannot: this is the
    -- address as it was on the day, and the Keycloak account it came from is mutable.
    channel       varchar(16)   NOT NULL DEFAULT 'EMAIL',
    recipient     varchar(320)  NOT NULL,

    -- WHAT IT SAID, in one number. Enough to answer "what did we tell them in August" without
    -- rebuilding the statement from a ledger that may since have gained late rows.
    net_amount    numeric(12,2) NOT NULL,
    net_direction varchar(16)   NOT NULL,
    currency      varchar(3)    NOT NULL,

    -- Notifications Manager's own id for the message, which is what its delivery log is keyed on.
    -- The trail from "we say we sent it" to "the provider says it arrived" runs through this.
    notification_ref varchar(64),

    -- WHO SENT IT. A Keycloak subject, never a service account: this endpoint is BACKOFFICE-only
    -- and is never triggered by a schedule, so there is always a person to name.
    sent_by       varchar(64)   NOT NULL,
    sent_at       timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT chk_dispatch_kind CHECK (counterparty_kind IN
        ('MERCHANT', 'RIDER', 'CARRIER', 'PLATFORM')),
    CONSTRAINT chk_dispatch_channel CHECK (channel IN ('EMAIL', 'SMS')),
    CONSTRAINT chk_dispatch_direction CHECK (net_direction IN ('WE_OWE', 'THEY_OWE', 'SETTLED')),
    -- The same rule the API enforces on a range, restated where it cannot be bypassed. An inverted
    -- period is not a statement anybody could have read.
    CONSTRAINT chk_dispatch_period CHECK (period_to >= period_from)
);

-- `lastSentAt` for one party: newest first, one row read.
CREATE INDEX idx_dispatch_counterparty
    ON statement_dispatch (counterparty_kind, counterparty_ref, sent_at DESC);

-- The duplicate check: has this exact period already gone out to this party?
CREATE INDEX idx_dispatch_period
    ON statement_dispatch (counterparty_kind, counterparty_ref, period_from, period_to);

COMMENT ON TABLE statement_dispatch IS
    'One row per statement email actually sent. Feeds lastSentAt on the counterparties listing and '
    'the refusal that stops the same period being sent twice by accident.';

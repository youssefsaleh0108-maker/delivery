-- RECON-04: a settlement that could not be made, written down where somebody can see it.
--
-- OrderEventListener caught every exception and returned, which acknowledges the message: a
-- database blip while settling an order.delivered lost that settlement for good. The listener's own
-- retries and the broker's dead-letter queue never saw it, nothing re-drove it, and no screen
-- listed it, because every reconciliation view reads legs that exist. Dev has carried two such
-- orders since 2026-09-08 (9576be97 and dcb4f889): the shop is still owed 13.11 and the delivery
-- company 4.72 on them.
--
-- A transient failure is now rethrown, so the container retries it and the broker dead-letters it.
-- What is left here is the other kind: a message this service will never be able to settle — one it
-- cannot parse, one that names no parties, one whose money was never collected. Those are still
-- acknowledged, because a bad message that comes back for ever blocks every good one behind it, but
-- they are recorded first, and the Back Office can list them.
--
-- One open row per order: a redelivery of the same bad message updates it rather than piling up.

CREATE TABLE settlement_failure (
    id             uuid         PRIMARY KEY,
    order_id       uuid,
    event_type     varchar(64)  NOT NULL,
    reason         text         NOT NULL,
    -- The message as it arrived, for whoever has to work out what happened. Bounded by the writer.
    payload        text,
    correlation_id varchar(64),
    first_seen_at  timestamptz  NOT NULL DEFAULT now(),
    last_seen_at   timestamptz  NOT NULL DEFAULT now(),
    attempts       integer      NOT NULL DEFAULT 1,
    resolved_at    timestamptz,
    resolved_by    varchar(64),
    resolution     text,
    CONSTRAINT chk_settlement_failure_resolved
        CHECK ((resolved_at IS NULL) = (resolved_by IS NULL)),
    CONSTRAINT chk_settlement_failure_attempts CHECK (attempts > 0)
);

-- The work list: what is still open, newest first.
CREATE INDEX idx_settlement_failure_open
    ON settlement_failure (last_seen_at DESC)
    WHERE resolved_at IS NULL;

-- One open row per order, so a message redelivered eight times is one line on that list.
CREATE UNIQUE INDEX uq_settlement_failure_open_order
    ON settlement_failure (order_id)
    WHERE order_id IS NOT NULL AND resolved_at IS NULL;

COMMENT ON TABLE settlement_failure IS
    'Settlements this service could not make and will not retry: the dead-letter table the Back '
    'Office reads. A transient failure is not here - it is rethrown, retried and dead-lettered by '
    'the broker, and found again by the unsettled-deliveries check.';

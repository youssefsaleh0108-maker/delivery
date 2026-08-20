-- NOTE ON THE VERSION NUMBER. This is V50, not V3, and the gap is deliberate.
--
-- Flyway merges the shared location and the service's own location into ONE version timeline, and
-- refuses by default to apply a migration numbered below what that database has already run. The
-- shared migrations were numbered V1 and V2 when the services had nothing; those services are now
-- well past V10 (orders at V21, product at V19), so a new shared V3 is out of order everywhere it
-- matters and every service using the outbox refuses to start. A fresh database applies it happily,
-- which is exactly what makes this the kind of mistake that only appears on a deployed system.
--
-- So: a shared migration added after the services exist takes a version above every service range.
-- The highest anywhere is accounting V44; V50 clears it with room. Only order-manager and
-- product-service currently include classpath:db/migration/shared.

-- Retry backoff for the outbox relay.
--
-- Without this column the relay retried a failed publish on every tick. With the shipped defaults
-- — a 2s poll interval and 5 attempts — a broker that was unreachable for eleven seconds was enough
-- to move every PENDING row in every service to DEAD_LETTERED. A RabbitMQ restart takes longer than
-- that, so the ordinary operation of restarting the broker would have dead-lettered the entire
-- backlog: orders placed in that window would never notify, never settle, and would need an
-- operator to replay them by hand.
--
-- next_attempt_at is when a row becomes eligible again. New rows default to now(), so a first
-- publish is never delayed; only a failure pushes it into the future (see OutboxEvent.markFailed).

ALTER TABLE outbox_event
    ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz NOT NULL DEFAULT now();

-- The claim query now filters on next_attempt_at as well as status, so the partial index has to
-- carry it or every tick degrades into a scan of the whole pending backlog.
DROP INDEX IF EXISTS idx_outbox_unpublished;

CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox_event (next_attempt_at, created_at)
    WHERE status = 'PENDING';

-- Shared outbox table. Every domain service applies this into its OWN schema — there is no
-- platform-wide outbox, because the whole point is that the event insert and the business write
-- are a single local commit (Section 7).
--
-- Services pick this up by adding to their Flyway locations:
--   spring.flyway.locations: classpath:db/migration/shared,classpath:db/migration/{service}

CREATE TABLE IF NOT EXISTS outbox_event (
    id             uuid         PRIMARY KEY,
    aggregate_type varchar(128) NOT NULL,
    aggregate_id   varchar(128) NOT NULL,
    event_type     varchar(191) NOT NULL,
    payload        text         NOT NULL,
    correlation_id varchar(64),
    status         varchar(24)  NOT NULL DEFAULT 'PENDING',
    attempts       integer      NOT NULL DEFAULT 0,
    last_error     text,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    published_at   timestamptz,
    CONSTRAINT chk_outbox_status CHECK (status IN ('PENDING', 'PUBLISHED', 'DEAD_LETTERED'))
);

-- Drives the relay's claim query. Partial, because PUBLISHED rows are the overwhelming majority
-- over time and the relay never looks at them.
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox_event (created_at)
    WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
    ON outbox_event (aggregate_type, aggregate_id);

-- Operator's view: anything in here needs a human (Section 10).
CREATE INDEX IF NOT EXISTS idx_outbox_dead_lettered
    ON outbox_event (created_at)
    WHERE status = 'DEAD_LETTERED';

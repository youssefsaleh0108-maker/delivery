-- In-app messages (Section 4), owned by App Notification Service.
--
-- SCHEMA NOTE. This lives in the `notification` schema alongside Notifications Manager's tables,
-- because the brief's data model puts all three there and the two services split disjoint tables:
-- the manager owns notification_templates and notification_log, this service owns in_app_messages,
-- and neither reads the other's. They run separate Flyway histories (see spring.flyway.table in
-- each application.yml) so their migrations cannot collide, and the version numbering starts at V20
-- to keep the two sequences visually distinct in the one schema.
--
-- The version range is the only reason for the gap. There is no V12-V19.

CREATE TABLE in_app_messages (
    id            uuid         PRIMARY KEY,
    -- Keycloak sub. Every read is scoped by this; there is no cross-user query anywhere.
    user_id       varchar(64)  NOT NULL,
    -- The notification_log row this came from. Also the idempotency key: bus delivery is
    -- at-least-once, and a redelivered command must not produce a second badge for one event.
    notification_id uuid       NOT NULL,
    order_id      uuid,
    event_type    varchar(64)  NOT NULL,
    title         varchar(255) NOT NULL,
    body          text         NOT NULL,
    -- Deep link and anything else the client needs to act on the message.
    metadata      jsonb        NOT NULL DEFAULT '{}'::jsonb,
    read_at       timestamptz,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_in_app_notification UNIQUE (notification_id)
);

-- The list screen: one user's messages, newest first.
CREATE INDEX idx_in_app_user ON in_app_messages (user_id, created_at DESC);

-- The unread badge, which is polled far more often than the list is opened. A partial index keeps
-- it proportional to unread messages rather than to everything the user has ever received.
CREATE INDEX idx_in_app_unread ON in_app_messages (user_id)
    WHERE read_at IS NULL;

-- What the customer has already been told about their order.
--
-- The confirmation message promises "we will message you when it is on the way", and until now
-- nothing did. This is the record that lets the platform keep that promise exactly once.
--
-- The primary key IS the idempotency guarantee. Bus delivery is at-least-once and the outbox
-- republishes anything whose PUBLISHED flag failed to commit, so the same status event arrives more
-- than once as a matter of course. A customer who is told twice that their food is on the way is
-- being told the platform is broken.
CREATE TABLE wa_order_updates (
    -- The order in Order Manager. Not a foreign key: orders live in another service's schema, and
    -- a cross-schema constraint is exactly the coupling schema-per-service exists to prevent.
    order_id     uuid         NOT NULL,

    -- The status the customer was told about.
    status       varchar(24)  NOT NULL,

    -- Which conversation it went to, so an operator can find the thread from an order id.
    conversation_id uuid      NOT NULL REFERENCES wa_conversations (id) ON DELETE CASCADE,

    notified_at  timestamptz  NOT NULL DEFAULT now(),

    PRIMARY KEY (order_id, status)
);

CREATE INDEX idx_order_updates_conversation ON wa_order_updates (conversation_id, notified_at);

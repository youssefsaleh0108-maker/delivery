-- Customer <-> rider chat, scoped to one order. Owned by App Notification Service.
--
-- Same schema and same Flyway history as V20 (see that file for why the `notification` schema is
-- shared with Notifications Manager and why the two histories are kept apart). V21 continues this
-- service's own V20+ range; Notifications Manager has since taken V12 and V13, so the "there is no
-- V12-V19" note in V20 is now only true of this service's sequence.

-- One conversation is one order's customer talking to one order's rider. Nobody else is in it.
CREATE TABLE chat_conversations (
    id              uuid        PRIMARY KEY,
    order_id        uuid        NOT NULL,
    -- Keycloak subs, both of them. Authorisation is a comparison against these two columns and
    -- nothing else, which is what makes "who may read this" answerable without calling Order
    -- Manager on every request.
    customer_id     varchar(64) NOT NULL,
    rider_id        varchar(64) NOT NULL,
    opened_at       timestamptz NOT NULL DEFAULT now(),
    -- When this conversation stops accepting posts. NULL means "the order is still in flight".
    --
    -- A single instant rather than a status column, deliberately. Closing is a function of time
    -- (delivery + a grace window), and a status column would need a scheduler to flip it - which
    -- means that between the window expiring and the sweep running, a closed conversation still
    -- accepts messages. Comparing now() against this column has no such gap and needs no job.
    closes_at       timestamptz,
    -- The next per-conversation message number to hand out. Kept on the parent row so assigning a
    -- sequence is one UPDATE under a row lock, rather than a max(sequence_no) scan of the thread
    -- that grows with the conversation.
    next_sequence   bigint      NOT NULL DEFAULT 1,
    last_message_at timestamptz,
    -- Optimistic lock, belt to the row lock's braces. The pessimistic lock is what serialises
    -- concurrent posts; this is what turns a future caller who forgets to take it into a failed
    -- transaction instead of two messages quietly sharing sequence 7.
    version         bigint      NOT NULL DEFAULT 0,
    -- A conversation with one participant twice over is a bug in whatever opened it, and it would
    -- silently defeat every "not the sender" clause below.
    CONSTRAINT ck_chat_participants_distinct CHECK (customer_id <> rider_id)
);

-- At most one LIVE conversation per order, enforced by the database rather than by a read-then-write
-- in service code. A rider reassignment closes the old conversation and opens a new one - the old
-- rider must not keep reading a thread that carries on without them - and this index is what stops
-- a redelivered order.rider_assigned from opening a second live thread alongside the first.
CREATE UNIQUE INDEX uq_chat_open_per_order ON chat_conversations (order_id)
    WHERE closes_at IS NULL;

-- The two "my conversations" list screens.
CREATE INDEX idx_chat_customer ON chat_conversations (customer_id, opened_at DESC);
CREATE INDEX idx_chat_rider    ON chat_conversations (rider_id, opened_at DESC);
-- Closed threads for one order, for the dispute case.
CREATE INDEX idx_chat_order    ON chat_conversations (order_id, opened_at DESC);

CREATE TABLE chat_messages (
    id                uuid        PRIMARY KEY,
    conversation_id   uuid        NOT NULL REFERENCES chat_conversations (id),
    -- Per-conversation, gapless, monotonic. This - not created_at - is the ordering and the
    -- reconnect cursor: two messages can share a millisecond, and a client asking for "everything
    -- after 41" must get a stable answer no matter how the clock behaved.
    sequence_no       bigint      NOT NULL,
    sender_id         varchar(64) NOT NULL,
    sender_role       varchar(16) NOT NULL,
    -- Untrusted text, stored as text and nothing else. It is never concatenated into SQL, never
    -- interpolated into a log line, and never rendered server-side; it leaves this service only as
    -- a JSON string value, which is what makes an apostrophe or a </script> inert.
    body              text        NOT NULL,
    -- The sender's own id for this message, so a client retrying a timed-out POST does not post
    -- twice. NULL is allowed and NULLs do not collide in a Postgres unique index, so a client that
    -- does not send one simply opts out of the guarantee.
    client_message_id varchar(64),
    created_at        timestamptz NOT NULL DEFAULT now(),
    -- Handed to a live socket, or fetched by the recipient on reconnect. Distinct from read_at:
    -- "it reached their phone" and "they looked at it" are different claims and the design shows
    -- both.
    delivered_at      timestamptz,
    read_at           timestamptz,
    CONSTRAINT uq_chat_message_sequence  UNIQUE (conversation_id, sequence_no),
    CONSTRAINT uq_chat_message_client_id UNIQUE (conversation_id, client_message_id)
);

-- The thread read, and the reconnect read, are the same index.
CREATE INDEX idx_chat_messages_thread ON chat_messages (conversation_id, sequence_no);

-- The unread badge. Partial, for the same reason V20's is: it should be proportional to what is
-- unread, not to everything ever said.
CREATE INDEX idx_chat_messages_unread ON chat_messages (conversation_id, sender_id)
    WHERE read_at IS NULL;

-- Support reading a transcript is a real capability with a real cost, so it leaves a trace.
--
-- Granting it at all is a decision: a "you told me to leave it at the door" dispute cannot be
-- settled without the transcript, and refusing support the read does not stop the read happening -
-- it moves it to somebody with a psql prompt and no record. An audited endpoint is the honest
-- version of what would otherwise happen anyway.
CREATE TABLE chat_transcript_access (
    id              uuid         PRIMARY KEY,
    conversation_id uuid         NOT NULL REFERENCES chat_conversations (id),
    -- The staff member's Keycloak sub. Not their name or email: this table is queried to answer
    -- "who read this", and an id is enough to answer it without copying staff PII into it.
    actor_id        varchar(64)  NOT NULL,
    -- Required and free text, so the row says why rather than only that. A ticket reference is
    -- what this is for in practice.
    reason          varchar(200) NOT NULL,
    correlation_id  varchar(64),
    accessed_at     timestamptz  NOT NULL DEFAULT now()
);

-- "Who has read this conversation" and "what has this person read", which are the two questions an
-- access review actually asks.
CREATE INDEX idx_chat_access_conversation ON chat_transcript_access (conversation_id, accessed_at DESC);
CREATE INDEX idx_chat_access_actor        ON chat_transcript_access (actor_id, accessed_at DESC);

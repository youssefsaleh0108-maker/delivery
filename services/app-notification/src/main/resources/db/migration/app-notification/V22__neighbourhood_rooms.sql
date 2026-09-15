-- Neighbourhood chat: one public room per delivery zone. Owned by App Notification Service.
--
-- Same schema and Flyway history as V20/V21. Deliberately separate tables from order chat rather
-- than a "kind" column on chat_conversations: order chat is two people and its whole security model
-- is a comparison against two columns (see V21). A room is many strangers, and loosening that model
-- to fit them would put every order conversation one bug away from being readable by a crowd.

-- One room per curated delivery zone (Product Service's delivery_zones, the list customers pick
-- their address area from). zone_id is the key, not a free-text neighbourhood name: two spellings of
-- "Mar Mikhael" must not become two rooms, and a merchant's free-text district is not something a
-- customer's membership can be checked against.
CREATE TABLE chat_rooms (
    id              uuid         PRIMARY KEY,
    zone_id         uuid         NOT NULL,
    -- The zone's name as Product Service last reported it. A copy, so reading a room never needs a
    -- cross-service call; refreshed whenever somebody joins through the zone.
    name            varchar(120) NOT NULL,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    -- Per-room gapless sequence, claimed under a row lock exactly as chat_conversations does.
    next_sequence   bigint       NOT NULL DEFAULT 1,
    last_message_at timestamptz,
    version         bigint       NOT NULL DEFAULT 0,
    CONSTRAINT uq_chat_room_zone UNIQUE (zone_id)
);

-- Who is in which room. One row per person per room, kept when they move away (left_at set) so that
-- a mute follows them back if they return, and their per-room handle stays stable.
CREATE TABLE chat_room_members (
    id           uuid        PRIMARY KEY,
    room_id      uuid        NOT NULL REFERENCES chat_rooms (id),
    -- Keycloak sub. Never leaves this service: other members see handle and display_name only.
    user_id      varchar(64) NOT NULL,
    -- Opaque, random, per room. What the app uses to tell two authors apart and what a block or a
    -- report is addressed through, so a neighbour never holds a durable identifier for a person.
    handle       uuid        NOT NULL,
    -- First name and last initial from the token, or NULL when the token has no usable name. Never
    -- the username, email or phone: see ChatDisplayName.
    display_name varchar(80),
    joined_at    timestamptz NOT NULL DEFAULT now(),
    left_at      timestamptz,
    -- Set by a moderator. A time rather than a flag so that a mute ends without a job to lift it.
    muted_until  timestamptz,
    CONSTRAINT uq_chat_room_member UNIQUE (room_id, user_id),
    CONSTRAINT uq_chat_room_handle UNIQUE (room_id, handle)
);

-- At most one CURRENT room per person, enforced here rather than by a read-then-write: a person
-- belongs to the neighbourhood they live in, and being in several at once is how one account ends up
-- posting into every room in the city.
CREATE UNIQUE INDEX uq_chat_room_current_member ON chat_room_members (user_id) WHERE left_at IS NULL;
-- The member count, and the membership check on every read, post and subscribe.
CREATE INDEX idx_chat_room_members_current ON chat_room_members (room_id, user_id) WHERE left_at IS NULL;

CREATE TABLE chat_room_messages (
    id                uuid        PRIMARY KEY,
    room_id           uuid        NOT NULL REFERENCES chat_rooms (id),
    sequence_no       bigint      NOT NULL,
    sender_id         varchar(64) NOT NULL,
    -- Copies of the sender's handle and name at the moment they spoke, so a thread renders without
    -- joining members and a message keeps the name it was said under.
    sender_handle     uuid        NOT NULL,
    sender_name       varchar(80),
    -- Untrusted text, stored as typed; leaves only as a JSON string value (see V21).
    body              text        NOT NULL,
    -- Per sender, not per room: two strangers' clients can generate the same id, and a room-wide
    -- key would hand one of them the other's message as "already posted".
    client_message_id varchar(64),
    created_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_chat_room_message_sequence  UNIQUE (room_id, sequence_no),
    CONSTRAINT uq_chat_room_message_client_id UNIQUE (room_id, sender_id, client_message_id)
);

-- History pages (newest first, then older) and the reconnect read are the same index.
CREATE INDEX idx_chat_room_messages_thread ON chat_room_messages (room_id, sequence_no);
-- The send rate limit counts one person's recent messages.
CREATE INDEX idx_chat_room_messages_sender ON chat_room_messages (sender_id, created_at DESC);

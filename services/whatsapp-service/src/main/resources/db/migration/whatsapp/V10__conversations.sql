-- The merchant's WhatsApp front door.
--
-- Almost every small shop in this market already takes orders on WhatsApp: a name, a voice note, a
-- pin. Asking them to adopt a portal is asking them to change how they work; meeting them where
-- they already are is not. This is the inbound half — the conversation and the messages in it.
--
-- Nothing here is an order. A message is a request, and turning it into an order is a decision the
-- merchant makes (see V11). That separation is the whole design: "hi" must never become a purchase.

-- Which shop owns which WhatsApp number.
--
-- A table rather than a config map, because the alternative is an engineer editing a git repository
-- every time a shop signs up. The merchant connects their own number, and until they do, a message
-- addressed to it belongs to nobody and is dropped — there is no merchant who could read it.
CREATE TABLE wa_connected_numbers (
    -- The provider's id for the number, which is what arrives on the webhook. Not the number
    -- itself: the same shop can move its display number and keep the id, and the id is the only
    -- thing the callback actually carries.
    phone_number_id  varchar(64)  PRIMARY KEY,

    -- Whose shop. The Keycloak `sub`, as everywhere else.
    merchant_ref     varchar(64)  NOT NULL,

    -- What the merchant calls it, so a shop with two numbers can tell them apart.
    label            varchar(120),

    -- The human-readable number, for display only. Nothing routes on it.
    display_number   varchar(32),

    connected_at     timestamptz  NOT NULL DEFAULT now()
);

-- A merchant's own numbers. Not unique on merchant_ref: a shop with a branch line has two.
CREATE INDEX idx_connected_numbers_merchant ON wa_connected_numbers (merchant_ref);

CREATE TABLE wa_conversations (
    id               uuid PRIMARY KEY,

    -- Whose shop this is. The Keycloak `sub`, as everywhere else.
    merchant_ref     varchar(64)  NOT NULL,

    -- The customer's WhatsApp id, which in practice is their phone number in E.164. Stored as
    -- given by the provider rather than normalised: it is an identifier here, not a phone number
    -- we intend to dial, and rewriting it risks failing to match the next message from the same
    -- person.
    customer_wa_id   varchar(32)  NOT NULL,

    -- The name WhatsApp reports for the account. Absent surprisingly often, and changed by the
    -- customer at will, so it is a hint for the merchant rather than an identity.
    customer_name    varchar(160),

    -- Bumped on every message so the inbox can sort by "who is waiting" without a join.
    last_message_at  timestamptz  NOT NULL DEFAULT now(),

    -- Unread INBOUND messages. Kept as a counter rather than derived: the inbox reads it on every
    -- poll and counting rows per conversation each time is the query that gets slow first.
    unread_count     int          NOT NULL DEFAULT 0,

    archived         boolean      NOT NULL DEFAULT false,
    created_at       timestamptz  NOT NULL DEFAULT now(),

    -- One conversation per person per shop. The same customer messaging two shops is two
    -- conversations, which is what both merchants expect to see.
    CONSTRAINT uq_conversation UNIQUE (merchant_ref, customer_wa_id)
);

-- The inbox: this merchant's conversations, the ones waiting longest first.
CREATE INDEX idx_conversations_inbox
    ON wa_conversations (merchant_ref, archived, last_message_at DESC);

CREATE TABLE wa_messages (
    id               uuid PRIMARY KEY,
    conversation_id  uuid         NOT NULL REFERENCES wa_conversations (id) ON DELETE CASCADE,

    direction        varchar(8)   NOT NULL,

    -- What was said. Text only for now: a voice note or an image arrives as a media id that has to
    -- be fetched separately, and storing the id without the means to render it would be a feature
    -- that looks present and is not.
    body             text,

    -- What kind of message it was, even when the body is empty. An unsupported type still has to
    -- appear in the thread — a merchant seeing nothing where the customer sent a voice note would
    -- think the platform lost it.
    message_type     varchar(24)  NOT NULL DEFAULT 'TEXT',

    -- The provider's own id. This is what makes redelivery harmless: WhatsApp retries a webhook it
    -- believes was not acknowledged, and without this a retried delivery becomes a duplicate
    -- message in the merchant's thread.
    provider_message_id varchar(128),

    sent_at          timestamptz  NOT NULL,
    created_at       timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_message_direction CHECK (direction IN ('INBOUND', 'OUTBOUND'))
);

-- The idempotency guarantee. Partial, because outbound messages have no provider id until the
-- send is accepted, and two nulls are not equal in a unique index anyway.
CREATE UNIQUE INDEX uq_message_provider_id ON wa_messages (provider_message_id)
    WHERE provider_message_id IS NOT NULL;

-- The thread, oldest first, which is how a conversation reads.
CREATE INDEX idx_messages_thread ON wa_messages (conversation_id, sent_at);

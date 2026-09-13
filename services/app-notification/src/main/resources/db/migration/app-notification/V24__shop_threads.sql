-- A customer talking to a shop. Owned by App Notification Service.
--
-- Separate from chat_conversations for the reason V22 gives for rooms. Order chat is exactly a
-- customer and a rider, and its whole model is a comparison against those two columns. A shop
-- thread's other side is not a person this row can name: it is whoever owns the shop, which only
-- Product Service knows, so it needs its own membership rule rather than a loosened one.
--
-- Keyed by store and nothing food-specific: a provider on the planned services marketplace is a
-- Store too, and "chat with the provider" is this same thread answered from the merchant inbox. The
-- nullable order_id columns are what keep that reuse additive - a booking can be referenced from a
-- thread or a single message without a schema change. They stay NULL until an order reference can
-- be verified against Order Manager; nothing a client sends is written into them.

CREATE TABLE chat_shop_threads (
    id              uuid         PRIMARY KEY,
    store_id        uuid         NOT NULL,
    customer_id     varchar(64)  NOT NULL,
    -- What the shop sees of the customer: first name and last initial (ChatDisplayName). Never a
    -- phone number or an address - the shop gets those on an order, when it needs them.
    customer_name   varchar(80),
    -- The shop's name when the customer last opened the thread, so lists never call Product Service
    -- once per line.
    store_name      varchar(160) NOT NULL,
    order_id        uuid,
    opened_at       timestamptz  NOT NULL DEFAULT now(),
    -- When the thread stops accepting posts: the customer's last activity plus the idle window. An
    -- instant rather than a status, for the reason V21 gives - no sweep job and no gap.
    closes_at       timestamptz  NOT NULL,
    next_sequence   bigint       NOT NULL DEFAULT 1,
    last_message_at timestamptz,
    version         bigint       NOT NULL DEFAULT 0,
    -- One thread per customer per shop, so opening the chat twice is the same conversation.
    CONSTRAINT uq_chat_shop_thread UNIQUE (store_id, customer_id)
);

-- The merchant inbox: a shop's threads that have something in them, most recent first.
CREATE INDEX idx_chat_shop_threads_inbox ON chat_shop_threads (store_id, last_message_at DESC)
    WHERE last_message_at IS NOT NULL;

CREATE TABLE chat_shop_messages (
    id                uuid        PRIMARY KEY,
    thread_id         uuid        NOT NULL REFERENCES chat_shop_threads (id),
    sequence_no       bigint      NOT NULL,
    sender_id         varchar(64) NOT NULL,
    -- Which side spoke. The customer is told "the shop", never which account answered.
    sender_side       varchar(16) NOT NULL,
    body              text        NOT NULL,
    order_id          uuid,
    client_message_id varchar(64),
    created_at        timestamptz NOT NULL DEFAULT now(),
    read_at           timestamptz,
    CONSTRAINT ck_chat_shop_message_side CHECK (sender_side IN ('CUSTOMER', 'SHOP')),
    CONSTRAINT uq_chat_shop_message_sequence  UNIQUE (thread_id, sequence_no),
    CONSTRAINT uq_chat_shop_message_client_id UNIQUE (thread_id, sender_id, client_message_id)
);

CREATE INDEX idx_chat_shop_messages_thread ON chat_shop_messages (thread_id, sequence_no);
CREATE INDEX idx_chat_shop_messages_unread ON chat_shop_messages (thread_id, sender_side)
    WHERE read_at IS NULL;
CREATE INDEX idx_chat_shop_messages_sender ON chat_shop_messages (sender_id, created_at DESC);

-- Which merchant answers for a shop, as Product Service last confirmed it FOR THAT MERCHANT'S OWN
-- TOKEN. A short-lived cache and a delivery hint, never the authority: a merchant's access is
-- trusted from here only while the confirmation is minutes old, and only for the merchant it names;
-- anything else goes back to Product Service's /api/stores/mine. It exists because the storefront
-- (StoreResponse) deliberately exposes no merchant id, so there is no other way to learn whom a
-- customer's message should be pushed to.
CREATE TABLE chat_store_owners (
    store_id     uuid        PRIMARY KEY,
    merchant_id  varchar(64) NOT NULL,
    confirmed_at timestamptz NOT NULL
);

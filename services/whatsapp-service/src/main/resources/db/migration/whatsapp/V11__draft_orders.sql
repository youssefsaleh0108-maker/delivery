-- A message is a request. An order is a decision.
--
-- The tempting design is to parse the message into an order and place it. That is wrong in a way
-- that shows up immediately: "hi", "are you open?", and "the usual" would all become purchases.
-- Worse, a mis-parsed quantity is money — and the person who pays for it is the customer.
--
-- So a conversation opens a DRAFT, which is nothing until a merchant confirms it. The merchant
-- reads what the customer actually wrote, picks the products from their own catalog, sets the
-- address, and only then does it become an order through Order Manager like any other.
CREATE TABLE wa_draft_orders (
    id              uuid PRIMARY KEY,
    conversation_id uuid         NOT NULL REFERENCES wa_conversations (id) ON DELETE CASCADE,
    merchant_ref    varchar(64)  NOT NULL,

    -- What the customer actually said, kept verbatim. The merchant is reading this to decide what
    -- to put in the order, and a summarised or "cleaned" version would hide the detail that
    -- matters — "no onions", "the small one", "same as last time".
    request_text    text,

    -- Where it is going. Typed by the merchant from the conversation rather than parsed: addresses
    -- here are landmarks and floors, and a wrong guess sends a rider to the wrong building.
    delivery_address varchar(500),

    -- The area, when the merchant picks one. Same optionality as an app order: a shop with no
    -- zones set charges its flat fee and this stays null.
    delivery_zone_id uuid,

    contact_phone   varchar(32),
    notes           varchar(500),

    status          varchar(16)  NOT NULL DEFAULT 'OPEN',

    -- Set when the draft becomes a real order. The link is one-way on purpose: Order Manager owns
    -- orders and knows nothing about WhatsApp.
    order_id        uuid,

    created_at      timestamptz  NOT NULL DEFAULT now(),
    updated_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_draft_status CHECK (status IN ('OPEN', 'PLACED', 'DISCARDED')),
    -- A placed draft must say which order it became; an open one must not pretend to.
    CONSTRAINT chk_draft_order_link CHECK (
        (status = 'PLACED' AND order_id IS NOT NULL)
        OR (status <> 'PLACED' AND order_id IS NULL))
);

-- One open draft per conversation. A second would split a single customer's request across two
-- half-orders, and the merchant would have no way to tell which one to send.
CREATE UNIQUE INDEX uq_open_draft_per_conversation
    ON wa_draft_orders (conversation_id) WHERE status = 'OPEN';

-- The merchant's work list: what still needs turning into an order.
CREATE INDEX idx_drafts_open ON wa_draft_orders (merchant_ref, status, created_at);

CREATE TABLE wa_draft_lines (
    id           uuid PRIMARY KEY,
    draft_id     uuid           NOT NULL REFERENCES wa_draft_orders (id) ON DELETE CASCADE,

    -- A product from the merchant's own catalog. Not free text: the price, the minimum order and
    -- the settlement split all come from the catalog, and a line that names a product we cannot
    -- price is a line nobody can charge for.
    product_id   uuid           NOT NULL,

    -- Snapshotted so the draft reads correctly in the thread even if the product is renamed or
    -- delisted while the merchant is still typing.
    product_name varchar(200)   NOT NULL,
    unit_price   numeric(12, 2) NOT NULL,

    qty          int            NOT NULL,

    CONSTRAINT chk_draft_line_qty CHECK (qty > 0)
);

CREATE INDEX idx_draft_lines ON wa_draft_lines (draft_id);

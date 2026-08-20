-- Options on a draft line.
--
-- Added after the first end-to-end run refused a perfectly ordinary order: the shop's own products
-- have required option groups ("Choose Size"), and a draft that could only name a product could not
-- express a single one of them. Half a real catalog was unorderable over WhatsApp.
--
-- The ids are what matter — they go to Order Manager, which prices the selection from the catalog
-- exactly as it does for the app. The names and deltas beside them are a snapshot, so the merchant
-- can read the draft back to the customer as "Large, extra cheese" rather than as two UUIDs.
CREATE TABLE wa_draft_line_options (
    id            uuid PRIMARY KEY,
    line_id       uuid           NOT NULL REFERENCES wa_draft_lines (id) ON DELETE CASCADE,

    -- The catalog's id for the chosen option. The only field that is authoritative.
    option_id     uuid           NOT NULL,

    -- Snapshotted for display, like product_name on the line above.
    group_name    varchar(120)   NOT NULL,
    option_name   varchar(120)   NOT NULL,
    price_delta   numeric(12, 2) NOT NULL DEFAULT 0,

    -- The same option twice on one line is a mistake, not a quantity.
    CONSTRAINT uq_line_option UNIQUE (line_id, option_id)
);

CREATE INDEX idx_draft_line_options ON wa_draft_line_options (line_id);

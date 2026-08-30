-- The money-transfer ledger: one row per order's payment intent.
--
-- Amounts are denominated in USD; the LBP side is the SPLIT the customer chose, stored as its USD
-- value (split_usd + split_lbp_in_usd = amount_usd exactly, no rounding gap between columns) with
-- the platform rate LOCKED at quote time in rate_used. The lira face value a rider collects is
-- computed from those two, never stored a second time to drift.
CREATE TABLE money_transfers (
    id                UUID PRIMARY KEY,
    order_id          UUID           NOT NULL,
    payer_ref         VARCHAR(64)    NOT NULL,
    method            VARCHAR(32)    NOT NULL,
    status            VARCHAR(32)    NOT NULL,
    amount_usd        NUMERIC(12,2)  NOT NULL CHECK (amount_usd > 0),
    split_usd         NUMERIC(12,2)  NOT NULL CHECK (split_usd >= 0),
    split_lbp_in_usd  NUMERIC(12,2)  NOT NULL CHECK (split_lbp_in_usd >= 0),
    rate_used         NUMERIC(12,2)  NOT NULL CHECK (rate_used > 0),
    connector         VARCHAR(64)    NOT NULL,
    connector_ref     VARCHAR(128),
    created_at        TIMESTAMPTZ    NOT NULL,
    updated_at        TIMESTAMPTZ    NOT NULL,

    CONSTRAINT chk_transfer_method
        CHECK (method IN ('CASH_ON_DELIVERY', 'WHISH', 'OMT')),
    CONSTRAINT chk_transfer_status
        CHECK (status IN ('PENDING', 'INITIATED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_transfer_split_sums
        CHECK (split_usd + split_lbp_in_usd = amount_usd)
);

-- One intent per order: re-choosing a method replaces, never stacks.
CREATE UNIQUE INDEX ux_transfer_order ON money_transfers (order_id);

CREATE INDEX ix_transfer_payer ON money_transfers (payer_ref, created_at DESC);

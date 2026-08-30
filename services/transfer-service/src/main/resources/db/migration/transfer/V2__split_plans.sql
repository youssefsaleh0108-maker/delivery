-- Group split payment: one plan per group order, one share per person.
--
-- The plan is created BEFORE the order exists (order_id fills in at placement) because the whole
-- point is that the money is committed first. The rate is locked on the plan exactly as it is on
-- money_transfers — every share's lira figure is share × rate, computed, never stored to drift.
--
-- Shares identify people by their Keycloak USERNAME, not user id: the host types "@rami.k", and
-- the invitee finds their requests by the preferred_username in their own token. A share with no
-- username is a GUEST — somebody without the app whose share the rider collects in cash at the
-- door; it is born committed as cash because there is nothing for a guest to do in an app they
-- do not have.
CREATE TABLE split_plans (
    id            UUID PRIMARY KEY,
    host_ref      VARCHAR(64)   NOT NULL,
    host_username VARCHAR(128)  NOT NULL,
    host_name     VARCHAR(160)  NOT NULL,
    store_name    VARCHAR(160),
    order_id      UUID,
    mode          VARCHAR(16)   NOT NULL,
    status        VARCHAR(16)   NOT NULL,
    total_usd     NUMERIC(12,2) NOT NULL CHECK (total_usd > 0),
    rate_used     NUMERIC(12,2) NOT NULL CHECK (rate_used > 0),
    expires_at    TIMESTAMPTZ   NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL,
    updated_at    TIMESTAMPTZ   NOT NULL,

    CONSTRAINT chk_split_mode   CHECK (mode IN ('EVEN', 'ITEMIZED')),
    CONSTRAINT chk_split_status CHECK (status IN
        ('COLLECTING', 'READY', 'PLACED', 'CANCELLED', 'EXPIRED'))
);

CREATE INDEX ix_split_host ON split_plans (host_ref, created_at DESC);
CREATE INDEX ix_split_order ON split_plans (order_id) WHERE order_id IS NOT NULL;

CREATE TABLE split_shares (
    id             UUID PRIMARY KEY,
    plan_id        UUID          NOT NULL REFERENCES split_plans (id) ON DELETE CASCADE,
    payee_username VARCHAR(128),
    payee_name     VARCHAR(160)  NOT NULL,
    amount_usd     NUMERIC(12,2) NOT NULL CHECK (amount_usd >= 0),
    items_count    INT,
    status         VARCHAR(16)   NOT NULL,
    method         VARCHAR(32),
    paid_at        TIMESTAMPTZ,

    CONSTRAINT chk_share_status CHECK (status IN
        ('PENDING', 'PAID', 'DECLINED', 'COVERED')),
    CONSTRAINT chk_share_method CHECK (method IS NULL OR method IN
        ('CASH_ON_DELIVERY', 'WHISH', 'OMT', 'BOB', 'CASH_AT_DOOR', 'HOST_ORDER'))
);

CREATE INDEX ix_share_plan ON split_shares (plan_id);
CREATE INDEX ix_share_payee ON split_shares (payee_username) WHERE payee_username IS NOT NULL;

-- BOB Finance joins the wallet methods on the main transfer ledger too.
ALTER TABLE money_transfers DROP CONSTRAINT chk_transfer_method;
ALTER TABLE money_transfers ADD CONSTRAINT chk_transfer_method
    CHECK (method IN ('CASH_ON_DELIVERY', 'WHISH', 'OMT', 'BOB'));

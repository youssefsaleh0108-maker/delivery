-- The accounting schema (Section 4), owned by Accounting Service.

-- One leg of one settlement.
--
-- A settlement is not one movement: a delivered order debits the customer, credits the merchant its
-- share and credits the platform its commission. Modelling each leg as its own row is what makes
-- partial failure representable - "the customer was debited but the merchant credit was refused" is
-- a real state a saga has to be able to be in and recover from, and a single-row design cannot
-- express it.
CREATE TABLE transactions (
    id            uuid         PRIMARY KEY,
    order_id      uuid         NOT NULL,
    -- Which part of the settlement this is.
    leg           varchar(24)  NOT NULL,
    account_ref   varchar(64)  NOT NULL,
    amount        numeric(12,2) NOT NULL,
    currency      varchar(3)   NOT NULL DEFAULT 'USD',
    direction     varchar(8)   NOT NULL,
    status        varchar(16)  NOT NULL DEFAULT 'PENDING',
    -- The bank's own identifier, once it has one. This is the number quoted in a dispute.
    core_banking_ref varchar(64),
    failure_reason text,
    attempts      integer      NOT NULL DEFAULT 0,
    correlation_id varchar(64),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    posted_at     timestamptz,

    CONSTRAINT chk_txn_direction CHECK (direction IN ('DEBIT', 'CREDIT')),
    CONSTRAINT chk_txn_leg CHECK (leg IN (
        'CUSTOMER_DEBIT', 'MERCHANT_CREDIT', 'PLATFORM_COMMISSION', 'CUSTOMER_REFUND')),
    CONSTRAINT chk_txn_status CHECK (status IN (
        'PENDING', 'POSTED', 'FAILED', 'COMPENSATED', 'ABANDONED')),
    CONSTRAINT chk_txn_amount CHECK (amount > 0),

    -- The idempotency guarantee, enforced by the database rather than by a check-then-act in code.
    -- Bus delivery is at-least-once, so order.delivered can arrive twice; without this, the second
    -- copy would settle the order a second time and really move money twice.
    CONSTRAINT uq_txn_order_leg UNIQUE (order_id, leg)
);

CREATE INDEX idx_txn_order ON transactions (order_id, created_at);
-- The reconciliation view's query: what has not reached a terminal state.
CREATE INDEX idx_txn_unsettled ON transactions (created_at)
    WHERE status IN ('PENDING', 'FAILED');

-- Exactly what was sent to the bank and exactly what came back (Section 4).
--
-- Kept separate from transactions and append-only. "What did we actually send" is the first
-- question in any reconciliation dispute and cannot be reconstructed from a status column after the
-- fact; keeping it beside the mutable row would also mean an update could quietly rewrite history.
CREATE TABLE core_banking_sync_log (
    id             uuid         PRIMARY KEY,
    transaction_id uuid         NOT NULL REFERENCES transactions (id),
    provider       varchar(32),
    request_payload  jsonb,
    response_payload jsonb,
    outcome        varchar(16)  NOT NULL,
    synced_at      timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_sync_outcome CHECK (outcome IN ('POSTED', 'REJECTED', 'RETRYABLE', 'ERROR'))
);

CREATE INDEX idx_sync_transaction ON core_banking_sync_log (transaction_id, synced_at DESC);

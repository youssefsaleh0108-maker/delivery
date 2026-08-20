-- Cash that somebody is physically holding.
--
-- Until now a cash order debited the CUSTOMER's bank account, which never happened: the customer
-- handed notes to a rider. The first attempt to fix that swapped the debit onto the rider's bank
-- account, and every posting failed for want of funds — a rider holds notes, not a balance — which
-- abandoned the merchant leg behind it and paid nobody.
--
-- The mistake was not the account. It was asking the BANK to record a movement that did not happen
-- in any bank. So the two ideas are now separated:
--
--   * a ledger fact  — who owes whom, recorded always
--   * a bank posting — real money between real accounts, only when that actually occurs
--
-- A cash collection is the first kind. It creates a receivable against whoever took the notes, and
-- that receivable is cleared later by a remittance, which IS a real posting because banking the
-- takings really does move money.
--
-- `holder_kind` exists from the start because the delivery-company marketplace makes an external
-- provider a cash holder too, and retrofitting a discriminator onto a table with rows in it is
-- worse than carrying one nobody uses yet.

ALTER TABLE transactions
    ADD COLUMN posting_required boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN transactions.posting_required IS
    'False for legs that record an obligation rather than a bank movement, such as cash taken at '
    'the door. Those are never sent to the bank and never wait on it.';

ALTER TABLE transactions
    DROP CONSTRAINT chk_txn_leg;

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_leg CHECK (leg IN (
        'CUSTOMER_DEBIT',
        'CASH_COLLECTED',
        'MERCHANT_CREDIT',
        'RIDER_CREDIT',
        'PLATFORM_COMMISSION',
        'CASH_REMITTANCE',
        'CUSTOMER_REFUND'));

-- SETTLED_IN_CASH is a terminal state like POSTED, but deliberately not POSTED: reconciliation
-- against a bank statement must know which rows it should expect to find there and which were
-- never going to appear.
ALTER TABLE transactions
    DROP CONSTRAINT chk_txn_status;

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_status CHECK (status IN (
        'PENDING', 'POSTED', 'SETTLED_IN_CASH', 'FAILED', 'COMPENSATED', 'ABANDONED'));

CREATE TABLE cash_float (
    id            uuid PRIMARY KEY,

    -- Who is holding the money. A Keycloak subject today; a delivery company's id once providers
    -- collect COD themselves.
    holder_ref    varchar(64)  NOT NULL,
    holder_kind   varchar(16)  NOT NULL,

    -- Null on a remittance, which clears many orders at once rather than belonging to one.
    order_id      uuid,

    amount        numeric(12,2) NOT NULL,
    currency      varchar(3)   NOT NULL,
    entry_kind    varchar(16)  NOT NULL,

    -- Set on a COLLECTED row when a remittance clears it, so an outstanding balance is simply the
    -- rows where this is still null. Cheaper and far easier to audit than mutating a balance.
    cleared_by    uuid,
    created_at    timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_float_kind CHECK (entry_kind IN ('COLLECTED', 'REMITTED', 'WRITTEN_OFF')),
    CONSTRAINT chk_float_holder CHECK (holder_kind IN ('RIDER', 'PROVIDER')),
    CONSTRAINT chk_float_amount CHECK (amount > 0),

    -- One collection per order. The bus delivers at least once, and collecting the same order's
    -- cash twice would invent a debt the rider does not owe.
    CONSTRAINT uq_float_order UNIQUE (order_id, entry_kind)
);

-- The question this table is asked: what is this person still holding? Partial, because cleared
-- rows are history and the outstanding set stays small even when the history does not.
CREATE INDEX idx_float_outstanding
    ON cash_float (holder_ref)
    WHERE entry_kind = 'COLLECTED' AND cleared_by IS NULL;

CREATE INDEX idx_float_holder_created ON cash_float (holder_ref, created_at DESC);

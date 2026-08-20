-- A settlement leg that pays the rider.
--
-- Needed for Butler, where there is no merchant. On a BUY the rider bought the goods with their own
-- money, so this leg is a reimbursement plus their earnings — not a delivery bonus on top of a
-- merchant payout. On a SEND nothing was bought and it is earnings alone.
--
-- Kept as a distinct leg rather than reusing MERCHANT_CREDIT with a rider's account number: the
-- reconciliation view and every future report reads the leg name to say who was paid and why, and
-- "the merchant credit went to a rider" is the kind of sentence that costs an afternoon to unpick.
--
-- The table is `transactions` in the `accounting` schema, which Flyway's default-schema resolves.
ALTER TABLE transactions
    DROP CONSTRAINT chk_txn_leg;

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_leg CHECK (leg IN (
        'CUSTOMER_DEBIT',
        'MERCHANT_CREDIT',
        'RIDER_CREDIT',
        'PLATFORM_COMMISSION',
        'CUSTOMER_REFUND'));

-- The platform paying INTO an order instead of taking out of it.
--
-- Fee waivers make this possible for the first time. Free delivery on a small basket costs the
-- platform the whole delivery fee while earning it commission on very little, so what it keeps can
-- be negative: the merchant and the carrier are both owed more than the customer paid, and the
-- difference comes out of the platform's pocket.
--
-- That is the offer working, not a fault. But it has to be POSTED rather than dropped. The previous
-- code skipped a non-positive platform leg because a zero-value posting is rejected by the bank —
-- correct for zero, and quietly wrong for a deficit, where silently omitting the leg would leave
-- the credits exceeding the collection and the books not balancing.
--
-- Its own leg rather than a negative PLATFORM_COMMISSION: `amount > 0` is enforced on this table,
-- the direction column already says which way money moves, and a report that has to read the sign
-- of a "commission" to discover the platform lost money is a report nobody trusts.
ALTER TABLE transactions
    DROP CONSTRAINT chk_txn_leg;

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_leg CHECK (leg IN (
        'CUSTOMER_DEBIT',
        'CASH_COLLECTED',
        'MERCHANT_CREDIT',
        'RIDER_CREDIT',
        'PROVIDER_CREDIT',
        'PLATFORM_COMMISSION',
        'PLATFORM_SUBSIDY',
        'CASH_REMITTANCE',
        'CUSTOMER_REFUND'));

-- Paying whoever carried the order.
--
-- Until now the delivery fee went entirely to the platform, which was right while the platform was
-- the only delivery arm there was. Once a merchant can pick a carrier, the fee is what delivery
-- COSTS rather than platform revenue — and only the take rate on it ever was.
--
-- Absent when the platform's own riders carried the order: no carrier account, no leg, and the
-- settlement is byte-for-byte what it was before providers existed.
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
        'CASH_REMITTANCE',
        'CUSTOMER_REFUND'));

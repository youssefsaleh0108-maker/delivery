-- RECON-11: money the platform actually paid out, on the ledger.
--
-- A points redemption paid to a shop and a rider's cash-out both moved real money and left no mark
-- here at all: the ledger only ever recorded what an order owed somebody. So a shop's statement
-- kept reporting the whole amount owed after the platform had paid it, and the platform's own
-- statement showed commission earned and subsidies paid with nothing for what it handed over.
--
-- PAYOUT is a DEBIT against the party that was paid, which is exactly what reduces what the
-- platform owes them on a statement. Like CASH_REMITTANCE it belongs to no order and carries the
-- payout's own id, so the unique (order_id, leg) is what stops one redemption being recorded twice.

ALTER TABLE transactions
    DROP CONSTRAINT chk_txn_leg;

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_leg CHECK (leg IN (
        'CUSTOMER_DEBIT',
        'CASH_COLLECTED',
        'MERCHANT_CREDIT',
        'GIFT_WRAP_CREDIT',
        'RIDER_CREDIT',
        'PROVIDER_CREDIT',
        'PLATFORM_COMMISSION',
        'PLATFORM_SUBSIDY',
        'CASH_REMITTANCE',
        'PAYOUT',
        'CUSTOMER_REFUND'));

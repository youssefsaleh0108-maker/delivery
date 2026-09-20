-- RECON-10: what the platform absorbs when an order is closed after pickup.
--
-- Back Office can now close a PICKED_UP order that will never arrive, paying the shop its share and
-- the carrier its fee out of the platform's pocket. Nothing was collected from the customer, so
-- those credits have no collection behind them and the platform is the one out of pocket.
--
-- Its own leg rather than PLATFORM_SUBSIDY, which is what the platform gives away on purpose — free
-- delivery, a promo code. A loss on an order that went wrong is a different fact and the owner asked
-- for it to be named as one, so it is a leg of its own, posted to its own account
-- (delivery.accounting.loss-account). The order still balances: this debit is exactly the credits
-- beside it.

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
        'PLATFORM_LOSS',
        'CASH_REMITTANCE',
        'PAYOUT',
        'CUSTOMER_REFUND'));

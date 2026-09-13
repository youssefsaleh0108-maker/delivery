-- A gift's wrapping, paid to the shop that wraps it.
--
-- Order Manager itemises a gift's wrap fee beside the delivery fee — inside the order total, outside
-- the goods subtotal and the fee — and carries it on order.delivered as giftWrapFee. Nothing read it,
-- so the fee fell into the platform's residue and was posted as PLATFORM_COMMISSION: "Commission
-- earned" on the platform's statement, "Commission on order #" at the bank, and nothing at all for
-- the merchant who did the wrapping, whose receipt lists the wrap inside the order total.
--
-- Its own leg rather than more MERCHANT_CREDIT, because commission is taken on goods and never on
-- the wrap, and the shop's statement has to show the two apart. An order has at most one of each leg
-- (uq_txn_order_leg, V40), so a second merchant credit was never an option.
--
-- Numbered 49.1: after V49, and before V50 (carrier cash custody) and V51 (payroll), which are
-- pre-assigned to branches merged after this one. It re-creates the constraint V44 last wrote; a
-- later migration that adds a leg must carry GIFT_WRAP_CREDIT forward.
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
        'CUSTOMER_REFUND'));

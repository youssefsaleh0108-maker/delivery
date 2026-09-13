-- Shops hold the cash for pickup orders.
--
-- A service order the customer collects at the shop is paid at the shop's counter (services slice 6).
-- No rider takes those notes, so the order.delivered listener had nobody to name as their holder: it
-- fell back to recording the collection against the CUSTOMER, as a CUSTOMER_DEBIT with no
-- counterparty. That claims a customer's bank account moved when nothing moved, and it leaves the
-- shop - which really is holding the platform's money - owing nothing on any statement.
--
-- MERCHANT is therefore a third holder kind: the shop that took the notes, keyed on its Keycloak
-- subject (the order's merchantId) exactly as a rider is keyed on theirs, and owed to the platform
-- directly. Its collection is COLLECTED, its payment to the platform is REMITTED, and both read
-- through every query the float already has. Safe on existing data: no MERCHANT row exists yet.
--
-- ONLY chk_float_holder is re-created. V42 wrote it and no later migration touched it, so its values
-- are V42's with MERCHANT added. Every other check on these tables keeps the values its last writer
-- gave it, because this migration never drops them: chk_txn_leg (V49_1, with GIFT_WRAP_CREDIT),
-- chk_float_kind (V50, with TRANSFERRED), chk_float_method (V51, with PAYROLL_DEDUCTION), and V50's and
-- V51's custody and payroll checks. A later migration that re-creates chk_float_holder must carry
-- MERCHANT forward.
ALTER TABLE cash_float
    DROP CONSTRAINT chk_float_holder;

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_holder CHECK (holder_kind IN ('RIDER', 'PROVIDER', 'MERCHANT'));

-- A shop's cash is never a delivery company's: nobody carried a pickup, so no company is answerable
-- for its notes. With V50's checks that one clause keeps a shop's rows to collections and remittances
-- as well - a TRANSFERRED row must name a company (chk_float_transfer_carrier) and only a company's
-- custody copy points at a hand-over (chk_float_custody) - so no hand-over can ever move a shop's till
-- into a company's safe.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_merchant_carrier
        CHECK (holder_kind <> 'MERCHANT' OR carrier_ref IS NULL);

-- Shops hold the cash for pickup orders, and keep their own share of it.
--
-- A service order the customer collects at the shop is paid at the shop's counter (services slice 6).
-- No rider takes those notes, so the order.delivered listener had nobody to name as their holder: it
-- fell back to recording the collection against the CUSTOMER, as a CUSTOMER_DEBIT with no
-- counterparty. That claims a customer's bank account moved when nothing moved, and it leaves the
-- shop - which really is holding the cash - owing nothing on any statement.
--
-- MERCHANT is therefore a third holder kind: the shop that took the notes, keyed on its Keycloak
-- subject (the order's merchantId) exactly as a rider is keyed on theirs, and owed to the platform
-- directly. Its collection is COLLECTED. It settles its till on terms of its own: it keeps its share
-- (its goods less commission) and pays the platform only the rest. What it pays is REMITTED, as every
-- holder's payment is. The share it keeps is RETAINED, a new entry kind, because none of that money
-- reached the platform and it must never be counted as paid: a REMITTED row with a flag would be
-- counted by every query that already reads REMITTED, which is why TRANSFERRED is its own kind in V50.
-- Safe on existing data: no MERCHANT or RETAINED row exists yet.
--
-- TWO checks are re-created, and only these two. chk_float_holder: V42 wrote it and no later
-- migration touched it, so its values are V42's with MERCHANT added. chk_float_kind: V50 last wrote
-- it, so its values are V50's (with TRANSFERRED) with RETAINED added. Every other check keeps the
-- values its last writer gave it, because this migration never drops them: chk_txn_leg (V49_1, with
-- GIFT_WRAP_CREDIT), chk_float_method (V51, with PAYROLL_DEDUCTION), and V50's and V51's custody and
-- payroll checks. A later migration that re-creates either of the two must carry MERCHANT and
-- RETAINED forward.
ALTER TABLE cash_float
    DROP CONSTRAINT chk_float_holder;

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_holder CHECK (holder_kind IN ('RIDER', 'PROVIDER', 'MERCHANT'));

ALTER TABLE cash_float
    DROP CONSTRAINT chk_float_kind;

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_kind
        CHECK (entry_kind IN ('COLLECTED', 'REMITTED', 'TRANSFERRED', 'WRITTEN_OFF', 'RETAINED'));

-- A shop's cash is never a delivery company's: nobody carried a pickup, so no company is answerable
-- for its notes. With V50's checks that one clause keeps a shop's rows to collections, payments and
-- the share it keeps - a TRANSFERRED row must name a company (chk_float_transfer_carrier) and only a
-- company's custody copy points at a hand-over (chk_float_custody) - so no hand-over can ever move a
-- shop's till into a company's safe.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_merchant_carrier
        CHECK (holder_kind <> 'MERCHANT' OR carrier_ref IS NULL);

-- Only a shop keeps a share of what it holds. A rider or a company holds the platform's cash and
-- pays it in whole, so a RETAINED row held by anybody else would be notes kept that nobody agreed to.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_retained_merchant
        CHECK (entry_kind <> 'RETAINED' OR holder_kind = 'MERCHANT');

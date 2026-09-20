-- RECON-05: what the platform charged a payee, recorded on the payee's own leg.
--
-- A statement could only say what the platform kept on an order as a whole: PLATFORM_COMMISSION
-- less PLATFORM_SUBSIDY, a residue that also holds the express premium the customer paid and the
-- promotion the platform funded. So a shop's statement called all of it "commission" and derived
-- "goods sold" from it: on dev, "Goods sold 311.71, Platform commission (12.5%) 19.45" where the
-- shop had sold 332.63 of goods and been charged 40.37. The net was right and the breakdown was not.
--
-- The charge is known exactly when the order is settled, so it is written down there, beside the
-- credit it came out of. NOT a leg of its own: the legs are what must sum to the order total, and
-- adding one would change an arithmetic every report and every invariant check reads.
--
-- NULL means "not recorded" — every leg written before this — and the statements fall back to the
-- old attribution for those, saying so in their note. No row is changed here.

ALTER TABLE transactions
    ADD COLUMN commission_amount numeric(12,2);

ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_commission CHECK (commission_amount IS NULL OR commission_amount >= 0);

COMMENT ON COLUMN transactions.commission_amount IS
    'What the platform charged the payee of this leg, out of what they sold or carried: the goods '
    'commission on a MERCHANT_CREDIT, the delivery cut on a PROVIDER_CREDIT or RIDER_CREDIT, zero '
    'where a waiver meant nothing was charged. NULL on every leg written before V54, and on legs '
    'that are not a payee credit. Never part of the order''s arithmetic - the legs still sum to '
    'the total on their own.';

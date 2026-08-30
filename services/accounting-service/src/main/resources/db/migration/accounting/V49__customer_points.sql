-- Customers join the points ledger: the loyalty half of the rewards screen.
--
-- Merchants and riders have earned points since V45; the customer now earns on what they SPENT —
-- the order total — where the shop earns on the goods and the carrier on the fee. Same ledger,
-- same idempotent award-per-order index, one more owner kind. Redemptions stay possible for a
-- customer by construction, but nothing offers them one yet: the rewards screen shows the
-- balance's cashback VALUE, and paying it out is a later, deliberate step.
ALTER TABLE points_ledger DROP CONSTRAINT chk_points_owner_kind;
ALTER TABLE points_ledger ADD CONSTRAINT chk_points_owner_kind
    CHECK (owner_kind IN ('MERCHANT', 'CARRIER', 'RIDER', 'CUSTOMER'));

ALTER TABLE points_redemptions DROP CONSTRAINT chk_redemption_owner_kind;
ALTER TABLE points_redemptions ADD CONSTRAINT chk_redemption_owner_kind
    CHECK (owner_kind IN ('MERCHANT', 'CARRIER', 'RIDER', 'CUSTOMER'));

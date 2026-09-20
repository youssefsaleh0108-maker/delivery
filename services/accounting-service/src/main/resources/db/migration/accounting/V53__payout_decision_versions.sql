-- RECON-07: two decisions on one payout request can no longer both win.
--
-- A rider's cash-out and a points redemption were read, decided and written back with nothing to
-- say somebody else had decided in between. Two operators on one queue row, or an operator and the
-- requester, both succeeded: a cash-out was paid AND its money released back to the balance, a
-- redemption was released twice, and one approved as its owner cancelled it could still be paid.
--
-- A version on each row makes the later of two concurrent decisions fail at commit instead
-- (JPA @Version), and the API answers it 409. Existing rows start at 0; no row is changed.

ALTER TABLE rider_cash_out
    ADD COLUMN version bigint NOT NULL DEFAULT 0;

ALTER TABLE points_redemption
    ADD COLUMN version bigint NOT NULL DEFAULT 0;

COMMENT ON COLUMN rider_cash_out.version IS
    'Optimistic lock (RECON-07): of two decisions made at once, the one committed second fails.';
COMMENT ON COLUMN points_redemption.version IS
    'Optimistic lock (RECON-07): of two decisions made at once, the one committed second fails.';

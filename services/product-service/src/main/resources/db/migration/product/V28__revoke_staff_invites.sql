-- ---------------------------------------------------------------------------------------------
-- Taking an invite back.
--
-- A pending invite had no handle at all. The controller exposed POST /invites, and the only DELETE
-- took the UUID of an already-redeemed MEMBER — so a code that had been sent to the wrong number,
-- or to somebody who then did not join, could not be cancelled by anyone. It simply stayed live
-- for its whole 24 hours, redeemable by whoever held the string; and a MANAGER invite carries all
-- seven permissions, MANAGE_STAFF and ACCESS_SETTINGS included.
--
-- Its own column rather than winding expires_at back to now. Both would stop the code working, but
-- only one of them can answer "did this time out, or did somebody take it back, and who?" — which
-- is the question anybody looking at a shop's staff history is actually asking.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE staff_invites
    ADD COLUMN revoked_at timestamptz,
    ADD COLUMN revoked_by varchar(64);

-- Both or neither, the same shape the accepted pair already uses.
ALTER TABLE staff_invites
    ADD CONSTRAINT chk_invite_revoked CHECK ((revoked_at IS NULL) = (revoked_by IS NULL));

-- An invite cannot be both taken up and taken back. Enforced here rather than trusted to the
-- service, because the two writes come from different people racing each other: the employee
-- redeeming and the manager cancelling.
ALTER TABLE staff_invites
    ADD CONSTRAINT chk_invite_not_both CHECK (accepted_at IS NULL OR revoked_at IS NULL);

-- A share is PAID only when money reached the platform (RECON-01).
--
-- Until now PAID also meant "promised". The host's own slice was PAID from birth, a guest's door
-- cash was PAID, and an invitee who picked a wallet was PAID although nothing took their money. The
-- rider's checklist read those as paid digitally and asked for 5.00 of a 19.50 cash order, while the
-- ledger booked all 19.50 as collected at the door. COMMITTED is the promise. PAID is kept for money
-- a real provider carried, which no share has yet.
ALTER TABLE split_shares DROP CONSTRAINT chk_share_status;
ALTER TABLE split_shares ADD CONSTRAINT chk_share_status CHECK (status IN
    ('PENDING', 'COMMITTED', 'PAID', 'DECLINED', 'COVERED'));

-- A wallet payment the dev simulator stood in for. It is labelled as such, and on a cash order it
-- is still collected at the door.
ALTER TABLE split_shares ADD COLUMN simulated BOOLEAN NOT NULL DEFAULT FALSE;

-- The history, stated truthfully. No provider ever carried a share: answering one with a wallet
-- marked it PAID without calling any connector. So every PAID share so far was a promise, and every
-- wallet one was a stand-in. Rows are relabelled, and none is removed.
UPDATE split_shares SET simulated = TRUE WHERE method IN ('WHISH', 'OMT', 'BOB');
UPDATE split_shares SET status = 'COMMITTED' WHERE status = 'PAID';

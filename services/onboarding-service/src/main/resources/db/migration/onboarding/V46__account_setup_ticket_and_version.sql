-- Choosing a passcode takes a secret only the applicant holds, and one application is written by
-- one request at a time.
--
-- The passcode step (POST /applications/{reference}/account) trusted the reference as its secret.
-- It is not one: back office sees it on every application, a delivery company on every rider
-- applying to it, and it travels in URL paths that access logs keep. A company could set its own
-- passcode on an applicant's unfinished sign-in and then approve the rider itself.
--
-- So the intake now issues an account-setup ticket: 256 random bits, answered once to the client
-- that submitted, valid for thirty minutes and for one sign-in. Only its SHA-256 is kept here, so a
-- read of this table gives nobody a ticket. Unsalted on purpose — a salt protects guessable secrets,
-- and nobody guesses 256 bits. An applicant whose ticket expired proves the address again with a
-- one-time code instead, which needs no column.
--
-- Null for every application taken before this migration and for every one made by a signed-in
-- account (which has its sign-in from the start): those have no ticket, and a ticket presented for
-- them is simply wrong.
ALTER TABLE onboarding_applications
    ADD COLUMN account_ticket_hash       varchar(64),
    ADD COLUMN account_ticket_expires_at timestamptz,
    ADD COLUMN account_ticket_used_at    timestamptz;

-- A ticket is a hash and a deadline together, or nothing; and only an issued ticket can be spent.
ALTER TABLE onboarding_applications
    ADD CONSTRAINT chk_application_account_ticket CHECK (
        (account_ticket_hash IS NULL) = (account_ticket_expires_at IS NULL)
        AND (account_ticket_used_at IS NULL OR account_ticket_hash IS NOT NULL));

-- Optimistic locking for the entity (@Version).
--
-- The passcode step records a sign-in on the same row a reviewer may be deciding at that moment,
-- and Hibernate writes whole rows. Without a version the later commit wrote its stale copy over the
-- earlier one: a rejection landing mid-sign-in could be answered by SUBMITTED written back over the
-- decision, or by a sign-in recorded on a rejected application. Now the later of two overlapping
-- writes fails and changes nothing, and the caller is told.
--
-- Zero for every existing row, which is simply where their count starts.
ALTER TABLE onboarding_applications
    ADD COLUMN version bigint NOT NULL DEFAULT 0;

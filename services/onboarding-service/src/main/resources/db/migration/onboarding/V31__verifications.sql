-- Proving a contact detail belongs to the person typing it.
--
-- Before this, an application could name any address at all: somebody else's, or one that does not
-- exist. Both are bad in different ways. A wrong-but-real address means the decision email goes to a
-- stranger; a non-existent one means an approved applicant is provisioned, told nothing, and never
-- signs in — the platform's own records say they were welcomed.

CREATE TABLE onboarding_verifications (
    id              uuid         PRIMARY KEY,

    -- EMAIL or PHONE. Same table for both: the mechanics are identical and only the transport
    -- differs, so a second table would be the same eight columns with a different name.
    channel         varchar(16)  NOT NULL,

    -- Normalised at the application layer (lower-cased email, digits-and-plus phone) so that
    -- "Sam@Example.com" and "sam@example.com" cannot be two separate attempts at the same inbox.
    destination     varchar(255) NOT NULL,

    -- The code is NOT stored. This is a SHA-256 of code + salt, on the same reasoning as a
    -- password: this table is the one place a database leak would hand somebody a working code for
    -- every address currently mid-verification.
    code_hash       varchar(64)  NOT NULL,
    salt            varchar(32)  NOT NULL,

    -- Wrong guesses so far. A six-digit code is one in a million per try and one in a thousand over
    -- a thousand tries, so the cap is what makes the length mean anything.
    attempts        smallint     NOT NULL DEFAULT 0,

    expires_at      timestamptz  NOT NULL,

    -- Set when the right code is entered. From then on the row is a receipt rather than a
    -- challenge, and `token` is what the application form presents as proof.
    confirmed_at    timestamptz,

    -- Single-use. Set when an application consumes the proof, so one verification cannot underwrite
    -- an unlimited number of applications.
    consumed_at     timestamptz,

    -- 160 bits. Handed out only after the code is right, and the only thing an application carries
    -- to show this ever happened.
    token           varchar(64)  NOT NULL,

    created_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_verification_channel CHECK (channel IN ('EMAIL', 'PHONE')),
    -- A token cannot be spent before it exists.
    CONSTRAINT chk_verification_consumed_after_confirmed
        CHECK (consumed_at IS NULL OR confirmed_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_verification_token ON onboarding_verifications (token);

-- The lookup the confirm step makes: the newest live challenge for this destination.
CREATE INDEX idx_verification_destination
    ON onboarding_verifications (channel, destination, created_at DESC);

-- Feeds the resend cooldown and the per-destination cap, both of which are counts over a recent
-- window. Without them this endpoint sends mail to any address anybody names, as often as they ask.
CREATE INDEX idx_verification_created ON onboarding_verifications (destination, created_at DESC);

-- Phone becomes optional.
--
-- It was NOT NULL because a form marked it required, which is a statement about a form rather than
-- about the business. A shop that answers on WhatsApp and a fleet that answers by email are both
-- reachable; insisting on a number produces invented ones, which is worse than an empty column
-- because an invented number looks like a real one.
ALTER TABLE onboarding_applications ALTER COLUMN contact_phone DROP NOT NULL;

-- What was proved, and when. Kept on the application rather than inferred by joining back to the
-- verification: a reviewer looking at this row needs to know whether the address was confirmed, and
-- the answer must not change if the verification rows are later pruned.
ALTER TABLE onboarding_applications
    ADD COLUMN email_verified_at timestamptz,
    ADD COLUMN phone_verified_at timestamptz;

-- A phone number that is present must have been proved. Absent is fine; unverified is not — an
-- unverified number is a fact nobody checked, sitting in a field a reviewer will read as checked.
--
-- NOT VALID, and that is the honest option rather than the convenient one. Applications already in
-- this table were taken before any of this existed: they carry a phone number and no proof, because
-- nobody ever asked for proof. Postgres would otherwise refuse the constraint, and the two ways to
-- make it pass are backfilling phone_verified_at — writing down that a check happened when it did
-- not — or dropping the rule entirely. NOT VALID says exactly what is true: enforced from here on,
-- and the older rows are known not to have been checked.
ALTER TABLE onboarding_applications
    ADD CONSTRAINT chk_application_phone_verified
        CHECK (contact_phone IS NULL OR phone_verified_at IS NOT NULL) NOT VALID;

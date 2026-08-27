-- Where an approved merchant, rider or delivery company gets paid.
--
-- Its own table rather than a key in the V35 `details` jsonb, even though the wizard collects it on
-- the same screens as everything else in there. Three reasons, all of them about the IBAN:
--
--  1. It is the one field on an application that moves money. It needs a validation state, a
--     timestamp and the name of whatever checked it — a lifecycle, which jsonb models badly.
--  2. It has to be maskable. Every listing shows the last four digits and nothing else, and that
--     is a projection this service must be able to make without loading the whole document.
--  3. It has to be reachable for redaction. "Delete my bank details" is a request that arrives, and
--     a targeted DELETE on one row is answerable in a way "rewrite this applicant's jsonb, hoping
--     nothing else in it was structured the way I assumed" is not.
--
-- Never logged. Never returned to anybody except the owner of the application and a reviewer
-- entitled to decide it — see PayoutDetailsService for where that is enforced and PayoutView for
-- the masked shape everything else gets.

CREATE TABLE payout_details (
    id             uuid PRIMARY KEY,

    -- One set of payout details per application, enforced by the unique constraint rather than by
    -- the service being careful: two IBANs on one application is not a state anybody could resolve
    -- at payout time.
    application_id uuid NOT NULL UNIQUE
        REFERENCES onboarding_applications (id) ON DELETE CASCADE,

    -- The name on the account. Applicant-supplied and untrusted: bound as a JPA parameter, never
    -- interpolated, and never built into markup anywhere.
    account_holder varchar(160) NOT NULL,

    -- Normalised: uppercase, no spaces. ISO 13616 caps an IBAN at 34 characters.
    --
    -- Stored as plain text, and that is a gap rather than a decision. Column-level encryption needs
    -- a key from a KMS or Vault transit engine that nobody has provisioned for this platform yet;
    -- until one exists, encrypting here with a key sitting in the same config the database
    -- credentials come from would buy nothing but the appearance of protection. What does protect
    -- it today: the per-schema database role, the masking on every listing, and the fact that no
    -- code path writes this column to a log.
    iban           varchar(34)  NOT NULL,

    -- The last four digits, denormalised so a listing can render "•••• 0002" without the full value
    -- ever leaving the database. A substring in the query would work; a column means the masked
    -- projection cannot accidentally be written to select the whole IBAN instead.
    iban_last_four varchar(4)   NOT NULL,

    -- The first two characters of the IBAN. Kept separately because payout routing and the
    -- country-specific length rules both key on it, and re-deriving it means touching the IBAN.
    --
    -- varchar(2) rather than char(2), which is what it obviously wants to be: Postgres reports a
    -- char(n) column as `bpchar`, Hibernate expects `varchar` for a String property, and
    -- `ddl-auto: validate` refuses to start the service over the difference. The blank-padding
    -- semantics of char would be wrong here anyway.
    iban_country   varchar(2)   NOT NULL,

    -- How much is actually known about this account. CHECKSUM_ONLY is the honest default: the
    -- mod-97 check proves the number is well formed and was not mistyped, and proves nothing at all
    -- about the account existing or belonging to the person named. Moving past it requires a bank
    -- or payment-processor account the platform does not have — see PayoutAccountVerifier.
    verification_state varchar(24) NOT NULL DEFAULT 'CHECKSUM_ONLY',

    -- Which verifier reached that state, by name, e.g. DEV_CHECKSUM_ONLY. Recorded so that when a
    -- real processor is switched on it is answerable which rows were only ever arithmetic-checked.
    verified_by    varchar(32),
    verified_at    timestamptz,

    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_payout_verification_state CHECK (
        verification_state IN ('CHECKSUM_ONLY', 'VERIFIED', 'FAILED')),
    -- The masked form has to match the value it was taken from, or a listing shows one account and
    -- the payout goes to another. Cheap to enforce, and the failure it prevents is expensive.
    CONSTRAINT chk_payout_last_four CHECK (right(iban, 4) = iban_last_four),
    CONSTRAINT chk_payout_country CHECK (left(iban, 2) = iban_country)
);

-- Backoffice management of a partner's record: edits that are remembered, and suspension that is
-- a state with a reason rather than a deleted account.

-- Every change a person makes to a partner's business fields: who changed it, when, which field,
-- and both values. A row per field per edit, not a log line — a log line ages out, rotates away,
-- and cannot be queried by application; this table is the answer to "who changed this partner's
-- payout email and when", asked months later.
CREATE TABLE partner_edits (
    id             uuid PRIMARY KEY,
    application_id uuid NOT NULL REFERENCES onboarding_applications (id) ON DELETE CASCADE,

    -- The Keycloak sub of the BACKOFFICE user who made the change. Never applicant-supplied.
    actor          varchar(64)  NOT NULL,

    -- Machine name of the field: businessName, contactName, contactEmail, contactPhone. Written
    -- by the service from a fixed set, so nothing user-typed lands in this column.
    field          varchar(40)  NOT NULL,

    -- The values are partner data typed by people, so they are bound as parameters and rendered
    -- as text, never as markup. 500 comfortably holds the longest editable field (200).
    old_value      varchar(500),
    new_value      varchar(500),

    created_at     timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX idx_partner_edits_application
    ON partner_edits (application_id, created_at DESC);

-- Suspension as history rather than a flag. Each row is one act — suspended or reinstated — with
-- the typed reason and the actor. The current state is the newest row; no rows means active.
-- Modelling it this way makes "why was this partner suspended in March, and who lifted it" a
-- query rather than an archaeology exercise.
CREATE TABLE partner_status_changes (
    id             uuid PRIMARY KEY,
    application_id uuid NOT NULL REFERENCES onboarding_applications (id) ON DELETE CASCADE,

    -- The Keycloak account the role was revoked from or re-granted to. Denormalised from the
    -- application on purpose: the answer to "whose access did we actually change" must not move
    -- if the application row is later edited.
    user_ref       varchar(64)  NOT NULL,

    -- true = this row records a suspension; false = a reinstatement.
    suspended      boolean      NOT NULL,

    -- Typed, from a fixed enum, so suspensions can be counted by cause. Required when suspending;
    -- null on a reinstatement, which needs no cause beyond the actor who decided it.
    reason         varchar(32),

    -- The human sentence beside the type. Backoffice-written, shown to backoffice.
    reason_note    varchar(500),

    actor          varchar(64)  NOT NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_partner_status_reason CHECK (reason IS NULL OR reason IN
        ('FRAUD', 'ABUSE', 'NON_PAYMENT', 'POLICY_VIOLATION', 'PARTNER_REQUEST', 'OTHER')),
    -- A suspension has to say why. Enforced in the service too; here so the record cannot lie.
    CONSTRAINT chk_partner_suspension_has_reason CHECK (NOT suspended OR reason IS NOT NULL)
);

CREATE INDEX idx_partner_status_application
    ON partner_status_changes (application_id, created_at DESC);

-- The phone-must-be-verified check moves from the database to the intake path.
--
-- V31 added this CHECK because the only writer of contact_phone was the applicant, and an
-- applicant-supplied number nobody proved is a fact nobody checked sitting where a reviewer reads
-- it as checked. That rule still holds for intake and is still enforced there, in the
-- OnboardingApplication constructor. What changed is that BACKOFFICE can now correct a partner's
-- phone number — a partner phones support, the number on file is wrong — and the honest record of
-- that edit is the corrected number WITH phone_verified_at cleared, because no code was answered
-- on it. The constraint would refuse exactly that honest row, and the alternatives are worse:
-- refusing the edit, or stamping a verification that never happened. A cleared phone_verified_at
-- reads as "not checked" in the reviewer's view, which is precisely true, and the partner_edits
-- row above records who put the number there.
ALTER TABLE onboarding_applications
    DROP CONSTRAINT IF EXISTS chk_application_phone_verified;

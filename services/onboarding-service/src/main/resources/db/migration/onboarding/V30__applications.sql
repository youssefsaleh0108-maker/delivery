-- Applications to join the platform.
--
-- Merchants and delivery companies only. A rider or a customer signs themselves up in the mobile
-- app and is trading within a minute — there is nothing to review, because they bring no menu, take
-- no payouts and sign no commercial terms. A shop and a delivery company do all three, so somebody
-- has to look at them before they are live, and this is the record of that looking.
--
-- Version numbered from 30 to leave room below for anything the platform adds to earlier schemas
-- without colliding here.
CREATE TABLE onboarding_applications (
    id              uuid PRIMARY KEY,

    -- What they are applying to be. Not a role name: this is the commercial relationship, and the
    -- Keycloak role is one consequence of it.
    kind            varchar(16)  NOT NULL,

    -- What a reviewer reads.
    business_name   varchar(200) NOT NULL,
    contact_name    varchar(160) NOT NULL,
    contact_email   varchar(200) NOT NULL,
    contact_phone   varchar(32)  NOT NULL,
    -- Free text: the address of the shop, or the size of the fleet. Deliberately unstructured,
    -- because the useful thing at this stage is whatever the applicant thought to say.
    notes           varchar(2000),

    status          varchar(16)  NOT NULL DEFAULT 'SUBMITTED',

    -- The reference the applicant is given. Long and random on purpose: this is the only thing
    -- standing between a stranger and somebody else's application status, since an applicant has no
    -- account to authenticate with yet.
    reference       varchar(64)  NOT NULL,

    -- The Camunda process walking this application through review. Null only if the engine failed
    -- to start one, which is a fault worth being able to see rather than hide.
    process_instance_id varchar(64),

    -- Set on a decision.
    decided_at      timestamptz,
    decided_by      varchar(64),
    rejection_reason varchar(500),

    -- What was created when it was approved. Kept so a later question — "who provisioned this
    -- shop, and from which application" — has an answer.
    provisioned_user_ref varchar(64),
    provisioned_entity_id uuid,

    created_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_application_kind CHECK (kind IN ('MERCHANT', 'CARRIER')),
    CONSTRAINT chk_application_status CHECK (status IN (
        'SUBMITTED', 'IN_REVIEW', 'APPROVED', 'REJECTED', 'PROVISIONED', 'FAILED')),
    -- A decision must say who made it and when. An approval nobody signed is not reviewable.
    CONSTRAINT chk_application_decision CHECK (
        (status IN ('SUBMITTED', 'IN_REVIEW') AND decided_at IS NULL)
        OR (status IN ('APPROVED', 'REJECTED', 'PROVISIONED', 'FAILED')
            AND decided_at IS NOT NULL AND decided_by IS NOT NULL)),
    -- A rejection has to say why. "No" with no reason is the message that generates the phone call.
    CONSTRAINT chk_application_rejection CHECK (
        status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- The reference is how an applicant with no account checks their own status, so it has to be
-- unique and it has to be indexed.
CREATE UNIQUE INDEX uq_application_reference ON onboarding_applications (reference);

-- The reviewer's queue: what is waiting, oldest first, because an applicant who has been waiting
-- three days should not be behind one who applied this morning.
CREATE INDEX idx_applications_queue ON onboarding_applications (status, created_at);

-- One live application per email per kind. Somebody who applies twice while the first is still
-- being read is not two shops, and letting it through means two reviewers doing the same work and
-- possibly reaching different answers.
CREATE UNIQUE INDEX uq_application_open_per_email
    ON onboarding_applications (lower(contact_email), kind)
    WHERE status IN ('SUBMITTED', 'IN_REVIEW');

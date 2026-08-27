-- The documents step of the redesigned wizards: identity and vehicle papers, one row per upload.
--
-- These are rows, not another key in the `details` jsonb from V35, and the split is the point.
-- `details` is free-form answers a reviewer reads whole and nothing queries; a document has a
-- lifecycle — it is uploaded, looked at, approved or refused with a reason — and each of those is
-- a write by a different person at a different time. Putting a state machine inside a jsonb blob
-- means read-modify-write over the whole document for every decision, with two reviewers able to
-- lose each other's verdicts, and no way to index "what is waiting to be looked at".
--
-- The bytes are NOT here. They live in the merchant-kyc bucket in MinIO, which is deliberately not
-- routed publicly and has no anonymous read policy: a national id or a driving licence is exactly
-- the sort of object that must never be reachable by anyone who guesses or is forwarded a URL. The
-- only way to read one is a presigned GET minted for a specific reviewer, valid for minutes. This
-- table holds the pointer and the verdict.

CREATE TABLE applicant_documents (
    id             uuid PRIMARY KEY,

    application_id uuid NOT NULL
        REFERENCES onboarding_applications (id) ON DELETE CASCADE,

    -- Which paper this is. Not free text: what a merchant must produce differs from what a rider
    -- must, and the service refuses a kind that makes no sense for the application's kind.
    kind           varchar(32)  NOT NULL,

    -- The file_metadata row, which in turn holds the bucket, the object key and the uploader's
    -- Keycloak sub. Kept as an FK so an orphaned document — a verdict pointing at nothing — is
    -- impossible, and so the ownership check has a single source.
    file_id        uuid NOT NULL
        REFERENCES file_metadata (id),

    -- Denormalised from file_metadata purely so a reviewer's list renders without a join per row.
    -- Never used to fetch the object; StorageService is always given the metadata row itself.
    object_key     varchar(512) NOT NULL,
    content_type   varchar(128) NOT NULL,

    status         varchar(16)  NOT NULL DEFAULT 'PENDING',

    -- Why it was refused. Shown to the applicant, because "rejected" with no reason produces the
    -- phone call and the same document uploaded again unchanged.
    rejection_reason varchar(500),

    -- The reviewer's own note. Deliberately a separate column from rejection_reason: this one is
    -- never returned on any applicant-facing endpoint. Two columns rather than one flag, because a
    -- flag is one forgotten `if` away from showing an applicant what a reviewer wrote about them.
    reviewer_note  varchar(1000),

    reviewed_at    timestamptz,
    reviewed_by    varchar(64),

    uploaded_at    timestamptz  NOT NULL DEFAULT now(),

    -- Set when a newer upload of the same kind replaces this one. Rows are superseded, never
    -- overwritten or deleted: "which licence did we actually approve, and what did the one before
    -- it look like" is the first question asked when a KYC decision is challenged, and an UPDATE
    -- in place cannot answer it.
    superseded_at  timestamptz,

    CONSTRAINT chk_document_kind CHECK (kind IN (
        'NATIONAL_ID', 'DRIVING_LICENCE', 'VEHICLE_REGISTRATION', 'COMMERCIAL_REGISTRATION')),
    CONSTRAINT chk_document_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    -- A verdict must say who reached it and when. An approval nobody signed is not reviewable, and
    -- this is the table an auditor reads.
    CONSTRAINT chk_document_review CHECK (
        (status = 'PENDING' AND reviewed_at IS NULL AND reviewed_by IS NULL)
        OR (status IN ('APPROVED', 'REJECTED') AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)),
    -- A rejection has to say why, same rule as an application's.
    CONSTRAINT chk_document_rejection CHECK (
        status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- One live document per kind per application. The applicant may replace a rejected licence as many
-- times as they like; what must never happen is two current licences, because then "the licence was
-- approved" stops having a single answer.
CREATE UNIQUE INDEX uq_document_live_per_kind
    ON applicant_documents (application_id, kind)
    WHERE superseded_at IS NULL;

-- The reviewer's document panel: everything for one application, newest upload of each kind first.
CREATE INDEX idx_documents_by_application
    ON applicant_documents (application_id, uploaded_at DESC);

-- What is waiting to be looked at across the platform, oldest first — same reasoning as the
-- application queue: somebody waiting three days should not sit behind this morning's upload.
CREATE INDEX idx_documents_pending
    ON applicant_documents (uploaded_at)
    WHERE status = 'PENDING' AND superseded_at IS NULL;

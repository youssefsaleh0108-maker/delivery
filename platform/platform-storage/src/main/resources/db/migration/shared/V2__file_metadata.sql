-- Postgres-side pointer to every MinIO object this service owns, so the app never lists a bucket
-- to find out what exists (Section 4).
--
-- Applied into the OWNING SERVICE'S schema, not a shared `files` schema. See the class comment on
-- FileMetadata for why: a single shared table would put several independently deployed services
-- into the same rows, which is the coupling schema-per-service exists to prevent — and which the
-- per-schema database roles from Phase 0 block outright.

CREATE TABLE IF NOT EXISTS file_metadata (
    id           uuid         PRIMARY KEY,
    bucket       varchar(64)  NOT NULL,
    object_key   varchar(512) NOT NULL,
    owner_id     varchar(64)  NOT NULL,
    content_type varchar(128) NOT NULL,
    purpose      varchar(32)  NOT NULL,
    status       varchar(16)  NOT NULL DEFAULT 'PENDING',
    size_bytes   bigint,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    uploaded_at  timestamptz,
    CONSTRAINT chk_file_status CHECK (status IN ('PENDING', 'UPLOADED', 'DELETED')),
    CONSTRAINT uq_file_object UNIQUE (bucket, object_key)
);

CREATE INDEX IF NOT EXISTS idx_file_metadata_owner
    ON file_metadata (owner_id);

CREATE INDEX IF NOT EXISTS idx_file_metadata_purpose
    ON file_metadata (purpose, status);

-- Abandoned uploads: a presigned PUT was issued and the client never confirmed. Harmless
-- individually, but they accumulate, so a later cleanup job sweeps PENDING rows past a TTL.
CREATE INDEX IF NOT EXISTS idx_file_metadata_pending
    ON file_metadata (created_at)
    WHERE status = 'PENDING';

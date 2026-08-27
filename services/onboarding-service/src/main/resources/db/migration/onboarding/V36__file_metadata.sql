-- The Postgres-side pointer to every MinIO object this service owns.
--
-- Copied deliberately, and it is worth saying why rather than leaving the next person to wonder.
-- platform-storage ships this exact DDL inside its jar as `db/migration/shared/V2__file_metadata.sql`,
-- and the services that adopted storage from day one simply add `classpath:db/migration/shared` to
-- their Flyway locations. This service cannot: its own migrations are already at V35 in the live
-- database, so a V2 appearing on the classpath now is an out-of-order migration, and Flyway either
-- refuses to start or — with `out-of-order: true`, which is worse — quietly starts accepting any
-- migration anybody backfills below the current line.
--
-- So the table is created here, at the front of this service's own timeline, with the same columns,
-- constraints and indexes as the shared file. `IF NOT EXISTS` throughout so that if the shared
-- location is ever added (after a squash, or when a dedicated File Service takes this over) the two
-- do not fight. If you change this, change the platform copy too — FileMetadata is validated
-- against it by Hibernate at boot, so drift fails the deploy rather than a query.

CREATE TABLE IF NOT EXISTS file_metadata (
    id           uuid         PRIMARY KEY,
    bucket       varchar(64)  NOT NULL,
    object_key   varchar(512) NOT NULL,
    -- The Keycloak `sub` of whoever uploaded it. Every ownership check in the platform is against
    -- this column, never against an id the client sent.
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

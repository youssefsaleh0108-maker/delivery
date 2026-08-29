-- A person's own profile extras — today just the avatar. One row per Keycloak account.
--
-- Keyed by the Keycloak sub rather than any role-specific id, because a selfie belongs to the
-- PERSON: the same face should follow an account that is customer today and rider next month.
-- Created lazily on the first upload; an account that never set a picture has no row, and the API
-- renders that as "no avatar" rather than inventing a record.
CREATE TABLE user_profiles (
    -- The Keycloak sub, same as every other actor column in this schema.
    user_ref          varchar(64) PRIMARY KEY,

    -- Object key in the PRIVATE user-avatars bucket (see FilePurpose.USER_AVATAR). Private on
    -- purpose, unlike store artwork: a customer's face is shown back to the customer on their own
    -- account screen, not marketed to the public, so reads go through short-lived presigned URLs.
    avatar_object_key varchar(512),

    updated_at        timestamptz NOT NULL DEFAULT now(),
    created_at        timestamptz NOT NULL DEFAULT now()
);

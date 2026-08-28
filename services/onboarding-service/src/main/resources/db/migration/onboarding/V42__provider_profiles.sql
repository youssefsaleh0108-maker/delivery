-- A delivery company's public face and dispatch settings, owned by the company that runs it.
--
-- Order Manager owns the provider itself — the id, the slug, the staff and rider lists — and this
-- service does not reach into that schema. What lives here is what the carrier portal's settings
-- screen edits: artwork and preferences that no dispatch decision depends on. Keyed by the Order
-- Manager provider id, which is the one id every service already shares for a company.
CREATE TABLE provider_profiles (
    -- The Order Manager provider id. One profile per company, which the PK enforces.
    provider_id      uuid PRIMARY KEY,

    -- Object key in the product-images bucket — the same publicly-readable bucket store artwork
    -- uses, and for the same reason: a company logo is made to be shown, and a plain CDN-cacheable
    -- URL is the right shape for it. Identity papers this is not; see FilePurpose.
    logo_object_key  varchar(512),

    -- The regions this company dispatches in, as the carrier names them. Free text on purpose:
    -- the platform has no region taxonomy yet, and inventing one here would put fake precision in
    -- front of real city names. Capped in count and length at the service layer.
    dispatch_regions jsonb NOT NULL DEFAULT '[]',

    -- Per-day open/close, e.g. {"MONDAY": {"open": "08:00", "close": "22:00"}}. A day absent
    -- means closed that day. Validated at the service layer: known day names, HH:mm, open before
    -- close.
    operating_hours  jsonb NOT NULL DEFAULT '{}',

    -- Who last saved the settings, so a company with several staff can answer "who changed our
    -- hours". The Keycloak sub, same as every other actor column in this schema.
    updated_by       varchar(64),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    created_at       timestamptz  NOT NULL DEFAULT now()
);

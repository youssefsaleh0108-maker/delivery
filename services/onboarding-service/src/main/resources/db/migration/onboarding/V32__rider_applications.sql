-- Riders apply to a company, and that company decides.
--
-- Every other application on this table is addressed to the platform, because a shop and a fleet
-- are asking for a commercial relationship with the platform. A rider is not: they are asking a
-- delivery company for work. The platform has no basis for that decision — it does not know who
-- turned up for a trial, who has a licence, or who was let go last month — and taking it anyway
-- would mean choosing somebody else's staff for them and then carrying the liability.
--
-- So the row carries the company it is addressed to, and the review happens in that company's own
-- portal.

ALTER TABLE onboarding_applications
    ADD COLUMN target_provider_id uuid;

-- The kind check has to allow the new value. Dropped and recreated rather than altered: Postgres
-- has no ALTER CONSTRAINT for a CHECK, and leaving the old one would refuse every rider.
ALTER TABLE onboarding_applications DROP CONSTRAINT IF EXISTS chk_application_kind;
ALTER TABLE onboarding_applications
    ADD CONSTRAINT chk_application_kind CHECK (kind IN ('MERCHANT', 'CARRIER', 'RIDER'));

-- A rider names a company; a shop or a fleet must not. The second half matters as much as the
-- first: a MERCHANT row carrying a provider id would be an application that two different queues
-- both believe is theirs.
ALTER TABLE onboarding_applications
    ADD CONSTRAINT chk_application_target_provider
        CHECK ((kind = 'RIDER' AND target_provider_id IS NOT NULL)
            OR (kind <> 'RIDER' AND target_provider_id IS NULL));

-- The carrier's own queue: their applications, oldest first.
CREATE INDEX idx_application_target_provider
    ON onboarding_applications (target_provider_id, created_at)
    WHERE target_provider_id IS NOT NULL;

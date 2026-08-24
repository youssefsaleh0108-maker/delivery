-- A rider can now apply to MyDelivery itself, not only to a delivery company.
--
-- V32 required target_provider_id on every RIDER application, on the reasoning that a rider with no
-- company is an application nobody can decide. That was true while the platform only brokered
-- riders to companies. It is not true now: with no company named, the platform is the employer and
-- the backoffice decides.
--
-- Nothing else has to change for the routing. The backoffice queue already selects applications
-- whose target is null, and a company's queue selects its own id, so a platform-direct rider lands
-- in the right place by virtue of this column alone.
--
-- The other half of the old constraint stays: a shop or a fleet naming a delivery company is still
-- nonsense, and would put a merchant into some company's applicant list.

ALTER TABLE onboarding_applications
    DROP CONSTRAINT chk_application_target_provider;

ALTER TABLE onboarding_applications
    ADD CONSTRAINT chk_application_target_provider
        CHECK (kind = 'RIDER' OR target_provider_id IS NULL);

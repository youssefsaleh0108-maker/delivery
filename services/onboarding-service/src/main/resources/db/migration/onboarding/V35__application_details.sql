-- What the client's onboarding wizards collected beyond the fixed columns.
--
-- The redesigned wizards ask different questions of different kinds of applicant: a rider's
-- vehicle type and plate and preferred work region, a merchant's business type, a date of birth,
-- a national id, and bank/payout details (account holder, IBAN). Those questions will keep
-- changing as the wizards evolve, and none of them is queried by this service — they are read by
-- a reviewer in the backoffice portal, whole.
--
-- So: one nullable jsonb column rather than a column per question. A new wizard step becomes a
-- new key in the document, not a migration. The API caps the serialised size at 16KB; nothing
-- else about the shape is enforced, deliberately.
--
-- Sensitive: bank details live in here. It is never interpolated into SQL (JPA parameters only)
-- and never written to logs.
ALTER TABLE onboarding_applications
    ADD COLUMN details jsonb;

-- The carrier documents step grows the papers a delivery company actually files (Figma 86:241):
-- a certified trade licence, fleet insurance, and the fleet's vehicle registrations, alongside
-- the commercial registration it already had. The CHECK widens in step with DocumentKind — the
-- enum is the source of truth, this constraint is its shadow in the one place that outlives
-- every deployment.
ALTER TABLE applicant_documents DROP CONSTRAINT chk_document_kind;
ALTER TABLE applicant_documents ADD CONSTRAINT chk_document_kind CHECK (kind IN (
    'NATIONAL_ID', 'DRIVING_LICENCE', 'VEHICLE_REGISTRATION', 'COMMERCIAL_REGISTRATION',
    'TRADE_LICENCE', 'FLEET_INSURANCE', 'FLEET_REGISTRATION'));
